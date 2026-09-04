class_name BattleDamage
extends RefCounted
## 战斗结算: 两伤害路(_apply_damage DoT/真伤 + _apply_damage_from 普攻/技能·§3.3)+治疗/护盾/buff/眩晕/击退/DoT机制(含crit/dodge RNG·确定性核心)
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

## ★★★2026-08-22【伤害类型哨兵】—— 用户:「物理伤害被跳成了蓝色数字, 这是很严重的 bug, 得彻查」
##
## 【架构上的病】飘字颜色只看全局 `battle._last_dmg_type`(物红/魔蓝/真白),
##   而**只有 `_resolve_dmg` 会写它**; `_apply_damage` / `_apply_damage_from` 只读不写。
##   ⇒ 任何不先调 `_resolve_dmg` 的伤害, 颜色就**继承上一次别人的**。
##   全仓实测: 230 个伤害调用点里, 上游 30 行内没有任何东西设过类型的有 **158 处(69%)**。
##
## 【为什么要哨兵而不是直接改 158 处】那 158 处里很多**碰巧是对的**
##   (上一次刚好也是同类型)。不先筛就动手, 等于在正确的地方白干、还可能改错。
##   ⇒ 哨兵: `_resolve_dmg` 置 fresh=true, 伤害落地时取用并清掉。
##     落地时发现 fresh 已经是 false ⇒ 这一发的类型是**捡来的**, 记一笔。
## ★只在 `DMGSENTINEL=1` 时记账 —— 正式对局零开销。
var _dt_fresh := false
var _dt_stale: Dictionary = {}          # "来源标签" → 捡类型的次数
var _dt_total := 0                      # 分母: 一共取用了几次类型(N=0 是空检查, 不是通过)
## ★哨兵的第二只眼: `_dt_fresh` 只能发现"没人设过类型", 发现不了
##   "**别人刚设了、被我捡走**"(同一帧里另一发伤害先 _resolve_dmg 了)。
##   ⇒ `_resolve_dmg` 顺手记下"这份类型是算给谁的"; 取用时目标对不上 = 捡了别人的。
var _dt_owner = null
var _dt_wrongowner: Dictionary = {}     # 归属不符(比 fresh 更严)的记账
## ★哨兵的第三只眼(2026-08-29): 前两只都只管【飘字颜色对不对】,
##   管不了**这一发到底吃没吃护甲/魔抗**。
##   `_resolve_dmg` 才是算护甲的地方(effective_resist / resist_multiplier);
##   `_mitigate_incoming` 只算【减伤类】(damage_reduction / flat_dr / 护盾 / 嘲讽),
##   **它没有护甲公式** —— 所以 `raw=false` 只保证"吃减伤", 不保证"吃护甲"。
##   ⇒ 一发伤害只要没经过 `_resolve_dmg`, 它就是【无视护甲与魔抗】的定额伤害,
##     而文案很可能写着"物理伤害"。用户 2026-08-27:「物理伤害为啥不吃护甲啊」。
##   ⇒ 记账点仍在产品自己取用类型的那一行, 不是我插的标记: 新写的伤害代码
##     只要绕开 `_resolve_dmg` 就会被记上, 我不需要预先知道它存在。
var _dt_resolved := false               # 这份类型是 _resolve_dmg 算出来的(吃护甲), 还是 set_dtype 声明的(不吃)
var _dt_unmitigated: Dictionary = {}     # "来源标签" → 没走 _resolve_dmg 的次数


## 取用伤害类型。★返回值就是飘字要用的类型; 顺带把 fresh 消费掉。
## 哨兵报告 —— 由 tests/verify_dmg_type_sentinel 调。
func sentinel_report() -> Dictionary:
	return _dt_stale.duplicate()

## 分母。★memory [[fb-verify-check-can-fail]]: 报"0 分歧"前必须打印分母。
func sentinel_total() -> int:
	return _dt_total


## 归属不符的记账(比 `_dt_stale` 更严: 连"捡了同帧别人刚算的类型"也算)。
func sentinel_wrongowner() -> Dictionary:
	return _dt_wrongowner.duplicate()


## 【没走 `_resolve_dmg`】的记账 —— 这些伤害**不吃护甲也不吃魔抗**, 哪怕文案写着物理。
func sentinel_unmitigated() -> Dictionary:
	return _dt_unmitigated.duplicate()


## ★★不走 `_resolve_dmg` 但类型是确定的那些伤害, **一律用这个**声明类型, 别手写
##   `battle._last_dmg_type = ...`。手写会漏掉 fresh / owner 两个记账位, 于是
##   哨兵既看不出问题、也统计不准(2026-08-22 实测: 我自己修的几处就是这样进的"归属不符"名单)。
##   典型场景: 弹道命中还原发射时的类型、冲击波扩张到才命中、%maxHp 的定额伤害。
## `crit`: 传 null = 不动暴击态(DoT/定额伤害这类本来就无暴击的场合);
##   传 bool = 一起还原。★暴击态 `_last_atk_crit` 与类型是**同一个生产者**(_resolve_dmg)
##   在同一行写的, 病也一样: 弹道飞行途中被别人的伤害改掉, 命中时捡到别人的暴击。
##   实测(2026-08-22 探针): 51 发弹道命中里 12 发(24%)的暴击标记是捡来的。
##   后果不止显示 —— 忍者斩击的流血层数就读它(暴击 3 层/否则 2 层), 是玩法。
## `resolved`: 这一发【已经算过护甲/魔抗】了吗。默认 false ——
##   "声明类型" ≠ "算过护甲"。但有两类场合它确实算过, 必须显式传 true, 否则第三只眼误报:
##   ① `_phys_after_armor()` 算的段(手里剑物理段 / 幽魂触碰物理段) —— 它就是护甲公式本身
##   ② 弹道: 伤害在【发射时】用 `_atk_dmg` 算好, 命中时只是还原类型
##      (`_push_proj` 顺手把发射那一刻的 `_dt_resolved` 一起存进 `dtype_resolved`)
func set_dtype(t: String, victim, crit = null, resolved: bool = false) -> void:
	battle._last_dmg_type = t
	if crit != null:
		battle._last_atk_crit = bool(crit)
	_dt_fresh = true
	_dt_owner = victim
	_dt_resolved = resolved         # ★声明类型 ≠ 算过护甲 —— 见 `_dt_resolved` 头注

## `is_raw` 的那些**不算**捡类型: 真伤飘字恒为白, 与 `_last_dmg_type` 无关(下面 `_dt` 里
## 直接写死 "true")。不排掉的话哨兵会把海盗钩索/训龟大师这类纯真伤记成问题, 淹掉真的。
func _take_dtype(who: String, is_raw: bool = false, victim = null) -> String:
	if OS.has_environment("DMGSENTINEL"):
		_dt_total += 1
		if not is_raw and victim != null and not is_same(_dt_owner, victim):
			_dt_wrongowner[who] = int(_dt_wrongowner.get(who, 0)) + 1
		## ★第三只眼: 这一发没走 `_resolve_dmg` ⇒ 不吃护甲/魔抗。标签取法与 `_dt_stale` 同款
		##   (get_stack 拿 文件:行号, 一轮就定位到那一行, 不靠反复跑去凑随机阵容)。
		if not is_raw and not _dt_resolved:
			var _su: Array = get_stack()
			var _utag: String = who
			if _su.size() >= 3:
				var _up := PackedStringArray()
				for _j in range(2, mini(4, _su.size())):
					var _uf: Dictionary = _su[_j]
					_up.append("%s:%d" % [str(_uf.get("source", "?")).get_file(), int(_uf.get("line", 0))])
				_utag = "%s  (%s)" % [" ← ".join(_up), who]
			_dt_unmitigated[_utag] = int(_dt_unmitigated.get(_utag, 0)) + 1
	if not _dt_fresh and not is_raw and OS.has_environment("DMGSENTINEL"):
		## ★标签要能【直接定位到那一行】。原来只记 "来源龟→目标龟", 结果每跑一轮
		##   随机出来的阵容不同 ⇒ 名单每轮都变, 靠反复跑去凑齐是在赌。
		##   `get_stack()` 在带调试器的运行里给出真实调用栈 ⇒ 一轮就拿到 文件:行号。
		##   (导出版拿不到栈, 退回龟名标签; 哨兵本来就只在 DMGSENTINEL 下开。)
		## 栈: [0]=_take_dtype [1]=_apply_damage_from 本身 [2]=真正的调用者。
		## 再带上 [3] —— 因为有 `_apply_basic_hit_from` 这类薄包装, [2] 会停在包装上。
		var _st: Array = get_stack()
		var _tag: String = who
		if _st.size() >= 3:
			var _parts := PackedStringArray()
			for _i in range(2, mini(4, _st.size())):
				var _fr: Dictionary = _st[_i]
				_parts.append("%s:%d" % [str(_fr.get("source", "?")).get_file(), int(_fr.get("line", 0))])
			_tag = "%s  (%s)" % [" ← ".join(_parts), who]
		_dt_stale[_tag] = int(_dt_stale.get(_tag, 0)) + 1
	## ★★结构性保险(2026-08-22): 没人给这一发定类型时, **不许继承上一发别人的**。
	##   继承 = 同一件效果这次跳红、下次跳蓝、暴击时跳紫, 玩家看到的是随机色
	##   (用户原话:「有的时候物理伤害被跳成了蓝色数字」)。
	##   回落到 `physical` 至少是**确定**的, 而且与 `VisualConstants.cls_for` 对未知类型
	##   的既有回落一致(红)。真正该是魔法/真伤的那几处仍会被上面的哨兵点名, 逐个修到 0;
	##   但在修完之前, 玩家不会再看到"看运气的颜色"。
	##   ⚠ 这道保险**不能替代**哨兵 —— 它只保证确定性, 不保证正确性。
	var _stale_now: bool = not _dt_fresh and not is_raw
	_dt_fresh = false
	_dt_resolved = false
	return "physical" if _stale_now else battle._last_dmg_type

## 伤害统计的分桶归属: 输出归攻击者、承受归目标, 按【真实伤害类型】分桶(不是按 col ——
## col 是主题色, 大量物理攻击传偏蓝色, 按颜色判会把它们全算成法术)。
## ★抽成独立函数: 它是纯记账, 与伤害结算零耦合(CLAUDE.md §5「不在 _sim_step 调用链上的
##   不进主体」的同一条判据), 顺带让 _apply_damage_from 回到 250 行架构预算内。
func _record_buckets(src, u: Dictionary, dmg: int, bkt: String, was_crit: bool) -> void:
	if src is Dictionary and src.has("side") and not is_same(src, u):
		src["_st_dealt"] = int(src.get("_st_dealt", 0)) + dmg
		battle._st_add_type(src, "_st_dealt_by_type", bkt, dmg)
		if was_crit:
			src["_st_crit"] = int(src.get("_st_crit", 0)) + 1
	u["_st_taken"] = int(u.get("_st_taken", 0)) + dmg
	battle._st_add_type(u, "_st_taken_by_type", bkt, dmg)


func _apply_damage(u: Dictionary, dmg: int, col: Color, src = null, bucket: String = "dot", is_self: bool = false, dot_accum: bool = false, mute_sfx: bool = false) -> void:
	if u.get("_assembling", false):
		return   # 机甲组装期免疫一切伤害。★这条路径(DoT/真伤)原先没有这个闸, 只有 _apply_damage_from 有 → DoT 能打穿组装免疫(2026-07-19)
	if battle._sd_stacks > 0:
		dmg = maxi(1, int(round(float(dmg) * (1.0 + battle._sd_amp()))))   # §SUDDEN 决胜增伤(这条路走 DoT/真伤等)
	# ★2026-07-22 全量对齐: 过与 _apply_damage_from 同一套受害者减伤(见 §MITIGATE)。
	#   bucket=="tru" 视为真伤 → 与另一条路的 raw 语义一致(真伤只无视护甲/减伤, 护盾照吸)。
	var _raw: bool = (bucket == "tru")
	var d = battle._mitigate_incoming(u, float(dmg), _raw, is_self)
	# ★这里原来是 082 砗磲护心甲的「护盾存在时额外减伤 8/14/22%」(`_clam_dr`)。
	#   2026-08-06 用户把 082 整条重做成【护心反伤】(每受一段攻击反伤魔法伤害 + 攒充能
	#   + 普攻消耗一层回血) —— 新设计里**没有减伤这一半** ⇒ 两条路的消费点一并撤掉。
	#   ⚠ 撤要两条路一起撤(CLAUDE.md §3.3), 另一半在 _apply_damage_from 的同一位置。
	dmg = maxi(1, int(round(d)))                     # 统计/飘字用减伤【后】的值, 否则面板数字与实际掉血对不上
	var shield_before: float = u["shield"]
	d = ShieldMath.absorb(u, d)   # 普通盾+aura盾 吸全类型(§3.3 收口·两路共用)
	d = battle._spec.absorb(u, d)  # ★特殊余额(幽灵/法力/灰条/奶油/终极盾)在普通盾之后扛; §3.3 两路都接
	# 弓箭顶档【腐蚀满 5 层】: 受到伤害的 25% 转成真实伤害(无视护甲与护盾)。
	# ⚠ 两条伤害路径【都要加】—— _apply_damage(DoT/真伤) 与 _apply_damage_from(普攻/技能)
	#   各自独立扣血(CLAUDE.md §3.3), 只改一条会产生"只在某类伤害下才转真伤"的诡异行为。
	var _cor: float = BowSynergySystem.true_share(u)
	if _cor > 0.0 and bucket != "tru":   # ★这条路(_apply_damage)没有 raw 参数, 用 bucket 判真伤
		d += float(dmg) * _cor                       # 名义伤害的 25% 直接加进扣血(不经护甲/护盾)
	# ★新钩子【受到致命伤害时】(装备 063 幽影墨囊 · 用户拍板 U6-A): 减伤之后、扣血之前判。
	# ⚠ 两条伤害路径【都要挂】(CLAUDE.md §3.3) —— 只挂一条 = "只有被普攻打死才救得回来"。
	if u.get("_ink_sac", false) and d > 0.0 and float(u["hp"]) - d <= 0.0:
		d = battle._equip_sys._eq_ink_sac(u, d)
	u["hp"] = maxf(0.0, u["hp"] - d)
	battle._blood_rite_refresh(u)   # 剑【血祭】: 血量百分比整数位变了才重算攻击力(无血祭的单位零开销)
	battle._staff_syn.add_mana(u, float(dmg) * StaffSynergySystem.MANA_FROM_TAKEN)   # 法器: 受伤 ×0.1 涨法力
	# 无头龟·亡灵免死锁血: 另一条路有(deathfloor_until), 这条路没有 → 免死光环亮着人被 DOT 烧死
	if u["hp"] <= 0.0 and battle._t < float(u.get("deathfloor_until", 0.0)):
		u["hp"] = 1.0
	if u.get("_review_dummy", false): u["hp"] = u["maxHp"]   # 训练靶: 受击即回满, 打不死不结算(看完整)
	if battle._audit and dmg > 100000:
		battle._audit_flag("huge_hit", "%s 单次承伤 %d (%s)" % [str(u.get("name", "?")), dmg, bucket])
	# §STATS 修(用户2026-07-19"统计面板感觉很多伤害没统计"): DoT(灼烧/中毒/流血)此前【只计承受方】,
	#   施加者的"造成"完全没算 —— 而 dot_src 一直有记来源, 只是结算时没用。
	## ★★★2026-09-04: 这里原来是**自己抄了一遍**记账(而不是调 `_record_buckets`),
	##   条件还写成 `src.get("alive")` —— 而共用函数用的是 `src.has("side")`。
	##   ⇒ **施加者阵亡后**, DoT 继续跳的那些伤害走这条路就**不算给他**,
	##     而走 `_apply_damage_from` 的同类伤害照算。同一份伤害算不算数, 取决于走哪条路。
	##   2026-07-19 那次修只修了一半(补了 `_st_dealt`, 但条件用了 alive)。
	##   ⇒ 改调共用函数, 与另一条路同源。was_crit 恒 false: 这条路是 DoT/真伤, 本就不暴击。
	##   门禁 `verify_dmg_paths_agree` ① 守这条(修之前它是红的)。
	_record_buckets(src, u, dmg, bucket, false)
	# ★DOT 累积模式(点1): 不跳小飘字, 累加进头顶【按伤害类型桶】的常驻数字(灼烧+中毒同 mag 桶)。
	if dot_accum:
		_dot_accumulate(u, bucket, dmg)
	else:
		## ★★跳法必须是【伤害】那一套 —— 用户 2026-09-03:「跳出方法不应该是向上淡出, 必须按规矩」。
		##   规矩(本文件 `_float_text` 头注, 1:1 回合制 `_spawn_float_text`):
		##     kind="damage" → 爆大 pop(1.6~2.5) + **抛物弹射**(重力 200, 朝屏边跳)
		##     其它(label/heal/shield) → pop 1.2 + 缓升 50px + 淡出
		##   这一行原来**一个 kind 都没传** ⇒ 吃默认值 "label" ⇒ 走的是缓升淡出那条,
		##   而隔壁 `_apply_damage_from` 传的是 "damage"。
		##   ⇒ **两条伤害路的飘字跳法不一样**(CLAUDE.md §3.3: 改伤害必须两条都改, 这里就漏了一条)。
		## ★同时补 `dmg_type` —— `_float_row_offset` 靠它排行(红0/蓝1/白2, 真伤跳最上面),
		##   不传就全挤在第 0 行。
		## ⚠ 颜色仍用调用点传的 `col`(**没改**): `_apply_damage_from` 那条路是按类型统一取色的,
		##   把这条也统一意味着 20 多处主题色当场失效 —— 那是全局收口, 用户 2026-09-03 明确
		##   「别, 记录好到下一个方案里去做」⇒ 见 docs/plans/ 的伤害飘字统一方案。
		var _fdt: String = {"tru": "true", "mag": "magic", "phy": "physical"}.get(bucket, "true")
		## ★★【真实伤害统一白色】—— 用户 2026-09-03 逐字:「我现在告诉你真实伤害统一白色」。
		##   隔壁 `_apply_damage_from` 早就按类型统一取色(`_ncol`, 调用点传的 col 被忽略),
		##   这条路却直接用调用点传的 `col` ⇒ **同一种真伤, 两条路跳出来颜色不一样**
		##   (CLAUDE.md §3.3「改伤害必须两条都改」在这里又漏了一条)。
		##   ⇒ 只收口真伤这一类; 物理/魔法用户没点, 留在方案书
		##     `docs/plans/20260903b-伤害飘字统一收口.md` §5 未决① 里, 不擅自扩大。
		##   ⚠ 这会让走这条路、传主题色的真伤调用点当场变白(古灵精怪枪自伤紫、
		##     训龟大师暗红等)。那正是用户要的"按规矩", 不逐处商量豁免。
		var _fcol: Color = Color(UIPalette.TRUE_DMG) if bucket == "tru" else col
		battle._vfx._float_text(u["pos"] + Vector2(randf_range(-26.0, 26.0), -40.0 + randf_range(-10.0, 6.0)), str(dmg), _fcol, false, "damage", _fdt)   # 抖开: 多段/AOE 出伤飘字不重叠成糊团
	# §AUDIO: 无来源伤害也出命中音 (非暴击); 护盾破→shield-break。mute_sfx=诅咒 tick 静音(用户2026-07-23)
	if not mute_sfx:
		if shield_before > 0.0 and u["shield"] <= 0.0:
			battle._audio_sys._sfx_shield_break()
		else:
			battle._audio_sys._sfx_hit(false)
	# ★2026-08-06 窄口: 068 深海气压罐的充能条要吃【所有】伤害(用户原文"将收到的...伤害储存"),
	#   而 `_eq_on_target` 只挂在另一条路上。不给那个钩子补全路是因为它还挂着硬化层/冰封反制,
	#   让它们从每一跳灼烧触发是行为变更。详见 eq_potion_batch.store_from_any_damage 的头注。
	if u.get("_potion_tick", false):
		battle._equip_sys._potion_sys.store_from_any_damage(u, dmg)
	# ★★2026-08-06 批④ 同款窄口(§3.3 的另一半): 081 的举盾充能条 / 085 的受伤转龟能 /
	#   087 的压载舱, 按 §0.5 规格都要吃【所有】伤害, 而 `_eq_on_target` 只挂在
	#   `_apply_damage_from`(普攻/技能)那一条路上。理由与做法见 EquipSystem._b4_on_damaged_any 的头注 ——
	#   不给 `_eq_on_target` 补全路, 是因为它还挂着 013/014 硬化层与 015 荆棘反伤等已上线装备,
	#   让它们从每一跳灼烧触发是【行为变更】。
	if u.get("_b4_eq", false):
		battle._equip_sys._b4_on_damaged_any(u, src, dmg)
	# ★★2026-08-06 补: 这条路(DoT/真伤)原先【完全没有 HP 阈值检查】——
	#   `_eq_check_hp_threshold` 与血线只挂在 _apply_damage_from(普攻/技能)上。
	#   后果: 044 深海项链 / 045 珍珠耳环 的"首次<50%保命"在被**灼烧/中毒/流血/诅咒/真伤**
	#   打到半血时【不触发】, 要等再挨一次普攻才补上。这是 CLAUDE.md §3.3 那一类的既有 bug。
	#   (我加多条血线时先只接了一条路, 自己又踩了一次同样的坑, 所以两条一起补。)
	if u["alive"]:
		battle._equip_sys._eq_check_hp_threshold(u)
		battle._hpl.check(u)
	if u["hp"] <= 0.0 and u["alive"]:
		# ★带上 src: 原为 battle._kill(u) 无凶手 → DOT 击杀【不算击杀数】, 且暴君之牙处决回血这类
		#   on-kill 装备钩子全不触发(对比另一条路 battle._kill(u, src))。2026-07-22 修。
		battle._kill(u, src if src is Dictionary else null)

# 来源已知的伤害: 闪避 / 吸血 / 伤害统计 / 累积条(怒气/星能/储能) / 受伤被动. extra_ls=技能额外吸血%; raw=真伤穿盾
# 来源已知的伤害: 闪避 / 吸血 / 伤害统计 / 累积条(怒气/星能/储能) / 受伤被动. extra_ls=技能额外吸血%; raw=真伤穿盾
## ★no_popup: 不跳通用伤害飘字。给【自己维护一个常驻数字】的效果用 ——
##   靶向器钩索炸弹的 DoT 是"宿主头上一个累加滚动数字"(用户 2026-08-01 指定),
##   再叠一串通用红字就是两个数字打架。伤害/统计/护盾一切照旧, 只是不弹那个字。
## ★`basic=true` 只给【普攻链】打(近战直伤/普攻弹道落点/各龟的普攻分支/普攻溅射):
##   2026-08-11 用户报「浮游炮(非普攻)能触发钻孔螺」—— _eq_on_hit 原来对一切
##   _apply_damage_from 无差别开火, 而 015/038/056/061/062/063 的规格都写的是【普攻】。
##   技能/演出伤害一律不打这个标 ⇒ 那六件不再被技能触发。
func _apply_basic_hit_from(src: Dictionary, u: Dictionary, dmg: int, col: Color, extra_ls: float = 0.0, raw: bool = false) -> void:
	_apply_damage_from(src, u, dmg, col, extra_ls, raw, false, false, false, false, true)


## ★★伤害类型在【函数第一行】就取走(`_dtv`) —— 本函数后面会跑 `_ink_link_transfer`
##   (连笔: 受伤 30% 传导给连接对象)、`_staff_syn.add_mana`(法器涨法力可触发技能) 等
##   **会自己打伤害**的逻辑; 那些嵌套伤害各自走一遍 `_resolve_dmg`, 等回到这里时
##   全局 `_last_dmg_type` 早被改了 ⇒ 这一发的飘字捡到别人的颜色。
##   2026-08-22 哨兵实测: 弹道那批修掉后剩的最后几发就是这个形状(连笔龟 line 在名单里)。
##   取在第一行 = 拿到的就是【产生 dmg 那次 _resolve_dmg 写的类型】, 嵌套再多也偷不走。
func _apply_damage_from(src: Dictionary, u: Dictionary, dmg: int, col: Color, extra_ls: float = 0.0, raw: bool = false, from_equip: bool = false, pre_crit: bool = false, no_dodge: bool = false, no_popup: bool = false, basic: bool = false) -> void:
	var _dtv: String = _take_dtype(("%s→%s" % [str(src.get("id", "?")) if src is Dictionary else "-", str(u.get("id", "?"))]), raw, u)
	battle._adf_ct += 1
	if battle._adf_ct > 20000:                        # 防御: 一帧伤害调用爆炸(死亡链无限级联)→本帧后续伤害丢弃防卡死(用户2026-07-19卡死猎手)
		if not battle._adf_warned:
			battle._adf_warned = true
			printerr("[GUARD] _apply_damage_from 一帧调用超2万→截断防卡死 (last=%s src=%s)" % [str(u.get("id", "?")), str(src.get("id", "?"))])
		return
	if battle._stress or battle._wd_on: battle._dbg_op2 = str(u.get("id", "?"))   # 卡死猎手诊断: 最后经手的受伤单位
	# pre_crit=true: 该 raw 段的暴击已在上游算进 dmg(如手里剑真伤段=暴击总伤的一部分)→ 此处不再掷真伤暴击(防二次暴击)
	if u.get("_assembling", false):   # 机甲组装期免疫一切攻击(用户2026-07-16)
		return
	# 闪避 (目标 dodge_bonus); 瞄准镜054: 攻击者伤害无视闪避 (必中)
	# no_dodge: 吸取类必中(用户2026-07-22「吸取不可以被闪避或暴击」)
	if not no_dodge and u.get("dodge_bonus", 0.0) > 0.0 and not src.get("eq_cannot_be_dodged", false) and battle._battle_rng.randf() < u["dodge_bonus"]:
		battle._vfx._float_text(u["pos"] + Vector2(0, -40), "闪避", Color("#a0e8ff"))
		battle._equip_sys._eq_on_dodge(u)          # on-dodge 钩子 (幽灵墨鱼046: 闪避→永久护盾)
		battle._spirit_syn.on_dodge(u)             # 灵物【闪避追击】: 触手立即追击 1 次(25% 伤害, 每周期上限队伍共用)
		return
	# 小龟·不屈: 造成的任何伤害按目标稀有度增伤 (总闸→普攻/技能/真伤/固定伤全覆盖, 只算一次)
	if src.get("id", "") == "basic" and not is_same(src, u):
		dmg = int(round(float(dmg) * (1.0 + battle._BASIC_RARITY_BONUS.get(str(u.get("rarity", "C")), 0.20))))
	# 伤害输出乘数 (龟壳复制60%等; 默认1.0=不变): 缩放src本次造成的即时伤害
	if src.get("dmg_out_mult", 1.0) != 1.0:
		dmg = int(round(float(dmg) * float(src.get("dmg_out_mult", 1.0))))
	if battle._sd_stacks > 0:
		dmg = maxi(1, int(round(float(dmg) * (1.0 + battle._sd_amp()))))   # §SUDDEN 决胜增伤(这条路走普攻/技能主线)
	## 星辉战利品(宝箱传说): 转真实 = 跳过减伤(钻石18%/岩层/铁壁flat)。
	## ★用户 2026-08-14 收窄: **只有普攻与技能**转真实 —— 原来是"所有伤害",
	##   连装备触发的段(`from_equip`)也白嫖穿甲。现在装备段照常吃减伤。
	## ⚠ 已知局限(文案里也写了): 它走的是 raw 通道, **护盾与 flat 减伤仍会吃**,
	##   不是完全绕护甲(伤害多已由 `_atk_dmg` 预减)。
	if src.get("chest_starlight", false) and not from_equip:
		raw = true
	# ★靶向器055(+20%) 与 终极暴露蛋(×5) 已并入 §MITIGATE, 与 _apply_damage 共用同一份实现。
	#   拆成两半是因为下面的暴击/墨迹要插在中间(它们是攻击者侧, 只有这条路有)。
	# 真伤暴击 (全局: "暴击全龟通用"; 真伤照旧无视护甲/减伤, 只加暴击判定) (用户)
	if raw and not pre_crit and src is Dictionary and src.has("crit") and not is_same(src, u):
		var _trc: float = minf(float(src.get("crit", 0.0)), 1.0)
		battle._last_atk_crit = battle._battle_rng.randf() < _trc
		if battle._last_atk_crit:
			dmg = int(round(float(dmg) * DamageMath.crit_multiplier(float(src.get("crit", 0.0)), float(src.get("crit_dmg", 1.5)))))
	var was_crit = battle._last_atk_crit          # §AUDIO: 先抓暴击态 (下方 hook 里嵌套 battle._atk_dmg 会改写它)
	# 受伤被动(结算前改 dmg): 线条·墨迹(每层额外5%真实伤害·穿减伤穿盾) / 钻石·结构(受伤减免)
	var _ink = int((u.get("stacks", {}) as Dictionary).get("ink", 0))
	var _ink_true: float = 0.0
	if _ink > 0:
		_ink_true = float(dmg) * LineSystem.INK_TRUE_PER_STACK * float(_ink)   # 墨迹: 原伤害之外·每层额外承受5%【真实伤害】(穿减伤穿盾·满10层=50%·用户2026-07-10纠正: 非×1.05增伤)
	# ★受害者侧减伤(靶向器/暴露蛋/钻石/岩层/嘲讽/铁壁盾)全部收口到 §MITIGATE,
	#   与 _apply_damage 共用 —— 原先这段只在本函数里, 导致 DOT 完全不吃任何减伤。
	# 药水羁绊【猎物】: 全队对猎物造成的伤害 +15/25/40%。
	# ★攻击者侧(要 src) ⇒ 只在这条路加; DoT 那条 `_apply_damage` 根本没有 src。
	var _prey_amp: float = battle._potion_syn.amp_for(src, u)
	if _prey_amp != 1.0:
		dmg = maxi(1, int(round(float(dmg) * _prey_amp)))
	var d = battle._mitigate_incoming(u, float(dmg), raw)
	# ★082 的旧减伤消费点已撤 —— 与 _apply_damage 同一位置的另一半(§3.3), 理由见那边。
	dmg = maxi(1, int(round(d)))
	# 守护贝母021: 该单位被指向为"伤害转移", 把一部分入伤转给携带者承担 (护盾前分流, 剩余部分仍走本体护盾/血)
	var _rd = u.get("dmg_redirect_to", null)
	if _rd is Dictionary and battle._t < float(_rd.get("until", 0.0)):
		var carrier = _rd.get("carrier", null)
		if carrier is Dictionary and carrier.get("alive", false) and not is_same(carrier, u) and d > 0.0:   # is_same: 这里在【中央伤害管线】上, 每次伤害结算都跑 → 深比较风险最高
			var moved: float = d * float(_rd.get("pct", 0.0))
			if moved >= 1.0:
				d -= moved
				battle._redirect_damage(carrier, moved, ("true" if raw else battle._last_dmg_type))   # 按友军所受的同一类型落到携带者+跳数字(用户2026-07-19)
	# 枪羁绊【金弹】: 这一发是金弹时, 额外补一段真实伤害(60/80/100% × 本段伤害)。
	# ★真伤直接进扣血, 不走护甲/魔抗 —— 与原规格"额外造成 N% 的真实伤害"一致。
	# ⚠ 只在 _apply_damage_from(普攻/技能路)加 —— 金弹是枪打出去的子弹, 不走 DoT 那条路。
	var _gold: float = float(src.get("_golden_pct", 0.0)) if src is Dictionary else 0.0
	# 枪羁绊【火控】(第三座炮台): 带枪者额外造成 (10 + 身上枪件数×10)% 真实伤害。
	# ★与金弹【叠加】—— 一发金弹 + 火控 = 两段额外真伤, 这是原设计的意思(两条来源不同)。
	if src is Dictionary:
		_gold += float(src.get("_fire_ctrl", 0.0))
	if _gold > 0.0 and not raw:
		d += float(dmg) * _gold
	var shield_before: float = u["shield"]
	# 护盾吸收【全类型】伤害(物理/法术/真实): 1:1 回合制 damage.gd「真伤(true)也走护盾」+ 用户2026-07-11「真伤/反伤真伤要被盾档」。
	#   真伤只无视护甲/魔抗/减伤(见上方 not raw 分支), 但护盾照吸。唯一穿盾=墨迹(_ink_true·在护盾后单独加·由线条被动设计)。
	d = ShieldMath.absorb(u, d)   # 普通盾+aura盾 吸全类型(§3.3 收口·两路共用)
	d = battle._spec.absorb(u, d)  # ★特殊余额(幽灵/法力/灰条/奶油/终极盾)在普通盾之后扛; §3.3 两路都接
	if _ink_true > 0.0: d += _ink_true   # 墨迹真伤: 穿减伤穿盾(唯一穿盾例外·护盾吸收后加), 直接进扣血并计入跳字
	# 弓箭顶档【腐蚀满 5 层】: 受到伤害的 25% 转成真实伤害(无视护甲与护盾)。
	# ⚠ 两条伤害路径【都要加】—— _apply_damage(DoT/真伤) 与 _apply_damage_from(普攻/技能)
	#   各自独立扣血(CLAUDE.md §3.3), 只改一条会产生"只在某类伤害下才转真伤"的诡异行为。
	var _cor: float = BowSynergySystem.true_share(u)
	if _cor > 0.0 and not raw:
		d += float(dmg) * _cor                       # 名义伤害的 25% 直接加进扣血(不经护甲/护盾)
	# ★新钩子【受到致命伤害时】(装备 063 幽影墨囊 · 用户拍板 U6-A) —— 与 _apply_damage 同一位置的另一半(§3.3)
	if u.get("_ink_sac", false) and d > 0.0 and float(u["hp"]) - d <= 0.0:
		d = battle._equip_sys._eq_ink_sac(u, d)
	u["hp"] = maxf(0.0, u["hp"] - d)
	battle._blood_rite_refresh(u)   # 剑【血祭】: 血量百分比整数位变了才重算攻击力(无血祭的单位零开销)
	battle._staff_syn.add_mana(u, float(dmg) * StaffSynergySystem.MANA_FROM_TAKEN)   # 法器: 受伤 ×0.1 涨法力
	if u.get("_review_dummy", false): u["hp"] = u["maxHp"]   # 训练靶: 受击即回满, 打不死不结算(看完整)
	if not from_equip and d > 0.0: battle._line_sys._ink_link_transfer(u, d)   # 连笔: 受伤30%以真实伤害传导给连接对象(附录B-05)
	# §STATS: 战斗统计 — 输出归攻击者/承受归目标 (用显示数 dmg); 按伤害类型分桶(战中分段条用) + 暴击计数
	## ★哨兵在这里取用类型: 谁在没设类型的情况下打伤害, 这里会记一笔(见 _take_dtype)。
	##   标签用【来源单位 id + 目标 id】—— 足够把调用点定位到具体的龟/装备。
	var _bkt: String = ("tru" if raw else ("mag" if _dtv == "magic" else "phy"))   # 伤害分桶=真实类型(battle._last_dmg_type/raw), 非col: col是主题色·大量物理攻击传偏蓝色(忍者冲击#9fe8ff/#cfd8e8等)→原按col.b>col.r误判成法术=统计条+飘字全蓝(用户2026-07-11抓出)
	_record_buckets(src, u, dmg, _bkt, was_crit)
	# headless 亡灵: 首次濒死→5秒内HP不降到1以下(免死), 5秒后正常死
	if u["id"] == "headless" and u["hp"] <= 0.0 and not u.get("undead_used", false):
		u["undead_used"] = true; u["deathfloor_until"] = battle._t + HeadlessSystem.UNDEAD_DEATHFLOOR
		battle._vfx._float_text(u["pos"] + Vector2(0, -64), "亡灵!", Color("#9b6bff"))
		battle._headless_sys._headless_undead_vfx(u)                                    # 免死金骨光环5秒(2026-07-17)
	if battle._t < float(u.get("deathfloor_until", 0.0)):
		u["hp"] = maxf(1.0, u["hp"])
	var _dt: String = "true" if raw else _dtv   # 飘字类型=真实伤害类型(_resolve_dmg设的_last_dmg_type·即时伤害对); 远程弹道在飞时会被别的伤害覆写→弹道在_step_projectiles命中前用捕获的pr.dtype还原(见那里)
	var _ncol: Color = battle._VC.color_of(battle._VC.cls_for("damage", _dt, was_crit))   # 飘字按伤害类型统一取色 (物红/魔蓝/真白, 1:1 回合制)
	var _jdir: float = 0.0
	if src is Dictionary and not is_same(src, u) and src.has("pos"):
		_jdir = 1.0 if float(src["pos"].x) < float(u["pos"].x) else -1.0   # 来源在左→数字往右跳, 反之往左(用户规则)
	if not no_popup:
		battle._vfx._float_text(u["pos"], str(dmg), _ncol, was_crit, "damage", _dt, _jdir)   # 伤害: 朝远离来源方向弹射
	if _ink_true >= 0.5:   # ★墨迹(线条被动)真伤单独跳白字+计真伤桶(用户2026-07-18"墨迹真伤没生效"): 原折进d扣血但不跳字不计统计→看着像没生效; 现显式可见=真的在打
		var _iv = int(round(_ink_true))
		battle._vfx._float_text(u["pos"] + Vector2(0.0, -34.0), str(_iv), battle._VC.color_of(battle._VC.cls_for("damage", "true", false)), false, "damage", "true", -_jdir)
		u["_st_taken"] = int(u.get("_st_taken", 0)) + _iv
		battle._st_add_type(u, "_st_taken_by_type", "tru", _iv)
		if src is Dictionary and src.has("side") and not is_same(src, u):
			src["_st_dealt"] = int(src.get("_st_dealt", 0)) + _iv
			battle._st_add_type(src, "_st_dealt_by_type", "tru", _iv)
	# 泡泡束缚(bubbleBind): 束缚期间每受一段伤害 → 永久 -X 护甲/魔抗 (单次累计上限各30)
	if battle._t < u.get("bind_until", 0.0):
		var _sx: float = float(u.get("bind_shred", 0.0))
		var _bacc: float = float(u.get("bind_acc", 0.0))
		if _sx > 0.0 and _bacc < BubbleSystem.BIND_SHRED_CAP:
			var _dec: float = minf(_sx, BubbleSystem.BIND_SHRED_CAP - _bacc)
			u["base_def"] = maxf(0.0, u["base_def"] - _dec)
			u["base_mr"] = maxf(0.0, u["base_mr"] - _dec)
			u["bind_acc"] = _bacc + _dec
			battle._recalc_stats(u)
	# 泡泡·泡沫: 受伤的100%存为泡泡值(上限maxHp) → 周期消耗(见 _tick_periodic_passive)
	if u["id"] == "bubble":
		u["bubble_store"] = minf(u["maxHp"], float(u.get("bubble_store", 0.0)) + d * BubbleSystem.FOAM_STORE_PCT)
	# 反伤(通用): 受击反弹 reflect% × 受到伤害 给攻击者(真实伤害); from_equip守卫防循环; stone坚壁随防御涨(被动)
	var _refl_pct: float = float(u.get("reflect", 0.0))
	if u["id"] == "stone": _refl_pct += StoneSystem.REFLECT_BASE + (u["def"] + u["mr"] * StoneSystem.REFLECT_MR_WEIGHT) * StoneSystem.REFLECT_PER_DEF
	if u["id"] == "stone" and u.get("stone_rockbody", false) and not from_equip and dmg > 0 and int(u.get("rock_layers", 0)) < StoneSystem.ROCK_LAYER_CAP:
		u["rock_layers"] = int(u.get("rock_layers", 0)) + 1   # 岩层(岩石之躯被动·选此才有): 每受伤+1层上限30
		u["size_mult"] = 1.0 + StoneSystem.ROCK_SIZE_PER_LAYER * float(u["rock_layers"])   # +2%体型/层(回合制 rockShockwave.rockSizePctPerLayer=2·满30层=+60%)
	if _refl_pct > 0.0 and not is_same(src, u) and src.get("alive", false) and not from_equip and dmg > 0:
		var _refl = int(dmg * _refl_pct)
		if _refl > 0:
			_apply_damage_from(u, src, _refl, Color("#c9a36b"), 0.0, true, true)
	# 凤凰熔岩盾: 持盾窗口内对每段攻击反击 LAVA_RETALIATE×ATK 魔法 (from_equip守卫防循环)
	# ★注释原写"5秒"是过期的 —— 真值是 PhoenixSystem.LAVA_SHIELD_SEC(4 秒·与护盾同步)。
	if u["id"] == "phoenix" and battle._t < float(u.get("lava_shield_until", 0.0)) and not is_same(src, u) and src.get("alive", false) and not from_equip and dmg > 0:
		_apply_damage_from(u, src, battle._atk_dmg(u, PhoenixSystem.LAVA_RETALIATE, src, true), Color("#ff7a3c"), 0.0, false, true)
	# 闪电雷盾: 盾在时对每段攻击反击 0.3×ATK 魔法(用户2026-07-29 平衡四轮: 0.1→0.3) + 给攻击者叠1层电击
	if u["id"] == "lightning" and battle._t < float(u.get("thunder_shield_until", 0.0)) and float(u.get("shield", 0.0)) > 0.0 and not is_same(src, u) and src.get("alive", false) and not from_equip and dmg > 0:
		_apply_damage_from(u, src, battle._atk_dmg(u, LightningSystem.SHIELD_RETALIATE, src, true), Color("#4dabf7"), 0.0, false, true)
		battle._add_stack(src, "electric", 1, LightningSystem.SHOCK_STACK_MAX)
	# §AUDIO: 命中音 (暴击→hit-crit / 否则→hit-physical, 节流防多段刷屏); 护盾刚被打没→shield-break (真伤现在也能打盾→去掉 not raw).
	if shield_before > 0.0 and u["shield"] <= 0.0:
		u["shield_until"] = 0.0   # 盾被打空→清限时标记(防陈旧到期误清后续永久盾)
		battle._audio_sys._sfx_shield_break()
	else:
		battle._audio_sys._sfx_hit(was_crit)
	# Phase4 打击感: 受击闪白+轻压扁(每段直接命中); 顿帧/震屏/火花按伤害分级(auto: ≥gate=重击).
	battle._vfx._flash(u)
	battle._vfx._impact(u, dmg, "auto")
	# 来源累积 ----
	src["dmg_dealt"] = float(src.get("dmg_dealt", 0.0)) + float(dmg)   # ★.get 不是 +=: 合成来源(触手ghost等)没这个键, += 缺键=运行时错误⇒本函数当场中止(后面吸血/统计/死亡全不跑)而测试照样 ALL PASS
	# 吸血 (lifesteal 基础 + buff + 技能 extra) — silent: 高频回血不刷治疗音
	var ls: float = src.get("lifesteal", 0.0) + src.get("ls_bonus", 0.0) + extra_ls
	if ls > 0.0 and src["alive"]:
		_heal(src, float(dmg) * ls, true)
	# 猎人猎杀(重做·用户2026-07-14): 处决不再在此中央路径逐次判; 改由 _update_hunter_passive 每帧扫场→任一敌<斩杀线→自动射强化箭→命中处决. 窃取仍走 battle._kill→_on_unit_death 钩子.
	# 怒气 (熔岩造伤25% / 受伤20%)
	if src["id"] == "lava" and not src.get("volcano", false):     # 火山形态不获怒气(条=形态倒计时·用户2026-07-15)
		src["rage"] = minf(battle.RAGE_MAX, src["rage"] + float(dmg) * LavaSystem.RAGE_GAIN_PCT)
	if u["id"] == "lava" and not u.get("volcano", false):
		u["rage"] = minf(battle.RAGE_MAX, u["rage"] + float(dmg) * LavaSystem.RAGE_GAIN_PCT)
	if src is Dictionary and src.get("has_egg", false) and src.get("alive", false):   # 温泉蛋(036): 造成伤害×0.1进度
		battle._equip_tick_sys._egg_add_progress(src, float(dmg) * EquipTickSystem.EGG_DMG_RATIO)
	if u.get("has_egg", false):   # 温泉蛋(036): 承受伤害×0.1进度
		battle._equip_tick_sys._egg_add_progress(u, float(dmg) * EquipTickSystem.EGG_DMG_RATIO)
	# 星能 (星际造伤35%·用户2026-07-16: 62→35; 星波施法期锁定不涨)
	if src["id"] == "space" and battle._t >= float(src.get("star_lock_until", 0.0)):
		src["star_energy"] = minf(src["maxHp"] * StarSystem.ENERGY_CAP_PCT, src["star_energy"] + float(dmg) * StarSystem.ENERGY_GAIN)
	# 储能 (龟壳受伤转储能, 上限50%最大HP) — 仅"store"相位累积 ("cd"相位不储)
	if u["id"] == "shell" and u.get("shell_phase", "store") == "store":
		u["store_energy"] = minf(u["maxHp"] * ShellSystem.STORE_CAP_PCT, u["store_energy"] + float(dmg))
		u["_auraEnergy"] = u["store_energy"]   # 镜像给Hp条储能条显示(1:1回合制字段)
	if u["id"] == "shell" and float(dmg) > 0.0:
		u["shell_last_dmg_t"] = battle._t                 # 潜影(暗影被动): 记最后受伤时间(6秒无伤→隐身). AOE命中也计→不误进隐身(设计: AOE吃伤但不破隐, 未说进隐身; 计伤保守=受伤即重置)
	# 双头坚韧 (融合打包被动·选中融合才有): 每受一段攻击 +1护甲+1魔抗 (各上限20)
	if u["id"] == "two_head" and u.get("two_fused", false):
		var th: int = int(u.get("two_tough", 0))
		if th < TwoHeadSystem.FUSION_TOUGH_CAP:
			th += 1; u["two_tough"] = th
			u["base_def"] += 1.0; u["base_mr"] += 1.0; battle._recalc_stats(u)
			if battle._t - float(u.get("_tough_glint_t", -1.0)) > 0.35:   # 坚韧变硬微光(节流·用户2026-07-11)
				u["_tough_glint_t"] = battle._t
				battle._skill_ring(u["pos"], Color(0.55, 0.75, 1.0, 0.5), 46.0)
	# (反伤已合并到上方通用块, 删除重复的第二处石头反伤)
	# 装备事件钩子 (on-hit 攻击方 / on-target 防守方 / HP阈值) — 装备自身造的段不再回钩
	if not from_equip:
		if src["alive"] and u["alive"]:
			battle._equip_sys._eq_on_hit(src, u, dmg, basic, was_crit) # on-hit: 攻击者装备(★was_crit 是掷骰当时的快照, 别让它自己读全局: 中间的反伤/熔岩盾/雷盾会改写) (流血/灼烧/连锁/追击/穿透/标记 等; basic 闸【普攻】类)
			battle._bow_syn.on_hit(src, u)                   # 弓箭【处决】: 全队(用户2026-08-03改), 斩杀线按各自暴击率
			battle._potion_syn.try_behead(src, u)            # 药水顶档【斩首】: 攻击猎物且其 <20% 血 → 直接处决
			battle._gadget_syn.on_hit(src, u)                # 奇械【冰封】掷骰冻结 + 【僵硬】叠 1 层
			battle._staff_syn.add_mana(src, float(dmg) * StaffSynergySystem.MANA_FROM_DMG)   # 法器: 造成伤害 ×0.1 涨法力
			battle._equip_sys._gremlin.on_hit(src, basic)                # 古灵精怪枪: 携带者每次【普攻】自伤 1%最大生命(真实·能打死自己)
			battle._equip_sys._axe.on_hit(src, u, basic)      # 096 小木斧·被动2: 斧头普攻窃取目标 10% 护盾转普通护盾给自己
		if u["alive"]:
			battle._equip_sys._eq_on_target(u, src, dmg)     # on-target: 防守者装备 (硬化层/冰封反制 等)
			# 批④(2026-08-06) 后 17 件里吃【法术伤害】的那几件走这条钩。
			# ★守卫从 `_b3_gadget`(085/086 旧效果专用)换成批④统一的 `_b4_eq` ——
			#   085/086 已整条重做, 旧标记随之作废(见 EquipStatsApply._b4_on_spawn_all)。
			# ★传算好的伤害桶 _bkt 而不是让它自己读 battle._last_dmg_type —— 那个全局在
			#   上一行的 on-hit 链里会被嵌套的 _atk_dmg 覆写(见本函数 was_crit 那段注释)。
			if u.get("_b4_eq", false):
				battle._equip_sys._eq_on_magic_hurt(u, src, dmg, _bkt)
			battle._shield_syn.on_damaged(u, src, dmg)       # 盾羁绊: 怒气累计(全队·满400放冲击波) + 顶档反击
		# 宝箱藏宝图 on-hit 战利品 (火石灼烧/毒箭治疗削减/雷刃金闪电引爆·此块已在not from_equip内→天然防循环)
		var _cht = src.get("chest_treasures", null)
		if _cht is Dictionary and not is_same(src, u) and u.get("alive", false):
			if _cht.has("flint"):    # 火石: 命中→灼烧层(用户2026-08-14: 0.1→0.05, 走 ChestSystem 常量)
				_apply_dot_stacks(u, "burn", maxi(1, roundi(float(src["atk"]) * ChestSystem.FLINT_BURN_COEF)), src)
			if _cht.has("poison"):   # 毒箭: 命中→治疗削减-50%·5秒
				u["heal_reduce_until"] = maxf(float(u.get("heal_reduce_until", 0.0)), battle._t + 5.0)
				u["heal_reduce_pct"] = maxf(float(u.get("heal_reduce_pct", 0.0)), 0.5)
			## 雷刃: 命中叠金闪电·满5→引爆1.0A真伤(引爆那下 from_equip=true 防循环)
			## ★用户 2026-08-14 收窄: 只有【普攻与技能】命中才叠层 —— 装备触发的段不再叠。
			if _cht.has("thunder") and not from_equip:
				var _tl = battle._add_stack(u, "chest_thunder", 1, 5)
				if _tl >= 5:
					battle._consume_stacks(u, "chest_thunder")
					_apply_damage_from(src, u, maxi(1, int(float(src["atk"]))), Color("#ffe94d"), 0.0, true, true)
					battle._skill_ring(u["pos"], Color(1.0, 0.92, 0.3, 0.6), 40.0)
	if u["alive"]:
		battle._equip_sys._eq_check_hp_threshold(u)          # HP阈值: 首次<50% (深海项链/珍珠耳环)
		battle._hpl.check(u)                                 # ★多条血线(069 三块糕 80/55/30% · 064 <35%); 与上面那条 50% 线并存
		if str(u.get("id", "")) == "fortune" and not u.get("_lowhp_fired", false) and u["hp"] <= u["maxHp"] * FortuneSystem.LOWHP_PCT:
			battle._fortune_sys._fortune_lowhp_burst(u)       # 财神【通用被动】(用户2026-07-28): 首次跌破20%血 → 立得70龟能(不论带哪个技能)
	if u["hp"] <= 0.0 and u["alive"]:
		battle._kill(u, src)

# DoT 落血 (穿护盾, 不弹字防刷屏; 血条体现)
## ⚠★第三个参数**从来不被读**(2026-08-20 核实)。击飞位移实际来自 `battle.KNOCK_PUSH * push_mult`,
##   想调距离请改 `push_mult`。25 处调用点都在传一个被忽略的数 —— 谁去"调"它都不会有任何反应,
##   这比没有参数更坑。保留形参是为了不动那 25 处(GDScript 参数个数不匹配是**运行时**才炸, 批量改风险大),
##   但名字改成自说明的, 并且删掉了那个假装能调距离的 `DART_KNOCKUP_DIST` 常量。
func _knockback(by: Dictionary, tgt: Dictionary, _ignored_dist: float, vy_mult: float = 1.0, push_mult: float = 1.0) -> void:
	## ★★三道守卫必须与 `_knock_up` 完全一致 —— 它们是同一件事(让单位飞起来)的两条路。
	##   2026-09-04 彻查发现这里**少了 `alive`**: 调用点普遍是「先 `_apply_damage_from`
	##   再 `_knockback`」, 那一发要是打死了目标, 就会作用在**尸体**上(尸体飞天)。
	##   `_knock_up` 一直查着 alive, 这条路没查 ⇒ 同一件事两套标准。
	##   门禁 `verify_knock_paths_agree` ② 守这条(修之前它是红的)。
	if not tgt.get("alive", false):
		return
	if tgt["airborne"]:
		return
	if tgt.get("_knock_immune", false):   # 不沉之锚017免击飞(原flag只写不读=死标记, 用户2026-07-19"说好的免疫呢"补)
		return
	var dir: Vector2 = (tgt["pos"] - by["pos"])
	if dir.length() < 0.1:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	tgt["airborne"] = true
	tgt["vy"] = battle.KNOCK_VY * vy_mult
	tgt["vx"] = dir.x * battle.KNOCK_PUSH * push_mult
	tgt["vz"] = dir.y * battle.KNOCK_PUSH * push_mult
	# Phase4: 击飞 = 大事件 → 大震屏 + 顿帧 + 起跳火花 (起跳拉长由 battle._vfx._juice_scale_for 读 airborne/vy 自动)
	battle._shake(battle.JUICE_SHAKE_BIG)
	battle._add_hitstop(battle.JUICE_HITSTOP_KNOCK)
	battle._vfx._impact_particles(tgt["pos"], tgt.get("height", 0.0))
	# 飞镖056: 任意敌被己方击飞 → 标"靶子", 携带者周期 tick 射镖
	if battle._is_hostile(by, tgt) and battle._side_has_equip(by["side"], "p2eq_056"):
		tgt["eq_target_until"] = battle._t + 99999.0
		battle._mark_vfx(tgt, 99999.0, Color("#ffa040"))

# ══════════════════════════════════════════════════════════════
# §DOT-FLOAT 累积伤害数字 (用户2026-07-23 点1)
# DOT(灼烧/中毒/流血/诅咒)不再每 tick 跳一个小数字, 而是【按伤害类型桶】各维持一个常驻头顶数字,
# 每 tick 累加(总数越变越大、字号随量·1→2→3→4), 该桶所有 DOT 结束才触发弹射跳走(复用伤害飘字动画)。
# 分桶=伤害类型: mag(灼烧+中毒同桶·蓝) / phy(流血·红) / tru(诅咒+真火·紫)。多桶并存左右错开。
# ══════════════════════════════════════════════════════════════
func _dot_bucket_col(bucket: String) -> Color:
	# ★语义色走 UIPalette 单一色表(用户2026-07-22「全统一」): 物理红#ff4444 / 法术蓝#4dabf7 / 真实白#ffffff。
	#   原来这里没跟调色板走, 硬编码 phy#ff6b6b / tru 紫#b48cff —— 与结算面板+调色板「真实=白」不一致
	#   (用户2026-07-24:「自损和诅咒为什么用紫色」)。诅咒/真火/自损都是 tru 桶 → 现统一为白。
	match bucket:
		"mag": return Color(UIPalette.MAGIC)
		"phy": return Color(UIPalette.PHYS)
		"tru": return Color(UIPalette.TRUE_DMG)
	return Color(UIPalette.TRUE_DMG)

## 该桶是否还有活着的 DOT 在供养(结束检测)。mag=灼烧(非真火)或中毒; phy=流血; tru=真火灼烧或任一 flat DoT(诅咒)。
func _dot_bucket_active(u: Dictionary, bucket: String) -> bool:
	var ds: Dictionary = u.get("dot_stacks", {})
	var true_fire: bool = battle._t < float(u.get("true_fire_until", 0.0))
	match bucket:
		"phy":
			return int(ds.get("bleed", 0)) > 0
		"mag":
			return (int(ds.get("burn", 0)) > 0 and not true_fire) or int(ds.get("poison", 0)) > 0
		"tru":
			if int(ds.get("burn", 0)) > 0 and true_fire:
				return true
			for dot in u.get("dots", []):
				if battle._t < float(dot.get("until", 0.0)):
					return true
	return false

## 累加一次 DOT 伤害进对应桶的常驻数字。首次建 Label(挂 battle._ui_layer), 之后每帧由 _render._update_dot_floats 跟头顶。
func _dot_accumulate(u: Dictionary, bucket: String, dmg: int) -> void:
	if not (u.get("_dot_float") is Dictionary):
		u["_dot_float"] = {}
	var df: Dictionary = u["_dot_float"]
	var col: Color = _dot_bucket_col(bucket)
	var st: Dictionary = df.get(bucket, {})
	if st.is_empty() or not is_instance_valid(st.get("node", null)):
		var lbl = battle._make_num_label("0", col, 20)
		if battle._ui_layer != null:
			battle._ui_layer.add_child(lbl)
		var used = {}   # 左右错开: 避开其它桶已占的槽
		for b in df:
			if b != bucket and is_instance_valid((df[b] as Dictionary).get("node", null)):
				used[int((df[b] as Dictionary).get("slot", 0))] = true
		var slot = 0
		while used.has(slot):
			slot += 1
		st = {"node": lbl, "total": 0, "slot": slot}
	st["total"] = int(st.get("total", 0)) + dmg
	var lbl2: Label = st["node"]
	lbl2.text = str(int(st["total"]))
	lbl2.add_theme_font_size_override("font_size", battle._vfx._float_size(int(st["total"]), false))
	lbl2.add_theme_color_override("font_color", col)
	df[bucket] = st

## 该桶所有 DOT 结束 → 常驻数字弹射跳走(复用伤害飘字 kind=damage), 释放常驻节点。
func _dot_float_flyaway(u: Dictionary, bucket: String, st: Dictionary) -> void:
	if is_instance_valid(st.get("node", null)):
		(st["node"] as Node).queue_free()
	var total: int = int(st.get("total", 0))
	if total > 0:
		var dt: String = {"mag": "magic", "phy": "physical", "tru": "true"}.get(bucket, "true")
		battle._vfx._float_text(u["pos"], str(total), _dot_bucket_col(bucket), false, "damage", dt)

## 每帧: 常驻 DOT 数字跟随头顶 + 左右错开; 桶结束(或单位死)→弹射跳走。在 _process 里 _render._update_overlay 之后调。
func _grant_shield(u: Dictionary, amt: float, dur: float = 0.0) -> void:
	if amt <= 0.0: return
	_holy_convert(u, amt)      # 盾羁绊9档: 盾类装备给的护盾, 额外 20% 转成圣光护盾
	amt *= battle._copy_fx_mult                          # 龟壳复制期: 护盾也按60%(封板"以60%效果释放")
	amt *= 1.0 + float(u.get("shield_amp", 0.0))   # 护盾加成(受到方,所有来源)
	var sb: float = u["shield"]
	# ★★2026-08-05 用户拍板【删掉护盾上限】。
	#   原来这里是 `minf(u["shield"] + amt, u["maxHp"] * SHIELD_CAP_MULT)`, 封顶在最大生命的 150%。
	#   那个常量是 2026-06-27「阶段2/3雏形」那次提交里**随手写下的一行, 没有任何注释说明理由**,
	#   一年多没人回头看过, 却静默地封着全游戏 44 个给盾点。
	#   用户看到时的原话:「哪来的上限啊, 不应该有啊」——> 确认不是设计决定, 是遗留值。
	#   ⚠ 删掉之后 068 深海气压罐(3★ 法力护盾 = 300% 充能值)、072 铁皮蛋糕盒(3★ 终极护盾
	#     = 120% 最大生命) 这类新设计才拿得到设计值; 原来会被静默砍掉一半。
	u["shield"] = u["shield"] + amt
	if dur > 0.0:
		u["shield_until"] = maxf(float(u.get("shield_until", 0.0)), battle._t + dur)   # 限时盾原语(封板通用护盾=4秒): 记到期(多源取更晚); dur=0=永久(不设→_tick不过期·shell/嘲讽/既有盾全默认永久不变)
	var got = int(u["shield"] - sb)
	u["_st_shield"] = int(u.get("_st_shield", 0)) + got   # §STATS: 实际获盾
	if got >= 8:                             # #1 护盾飘字 "+N 盾" (浅蓝); 门槛过滤每帧微盾被动防刷屏
		battle._vfx._float_text(u["pos"] + Vector2(0, -52), "+%d 盾" % got, Color("#ffffff"), false, "shield")
	## ★★2026-08-09 用户看到 095 的画面:「又是程序生成的环？哪个商业游戏是你这么做啊」。
	##   这一行就是那个环 —— `_skill_ring` 是**代码现画的一个圆**, 而它封着全游戏 44 个给盾点,
	##   于是任何来源给盾, 脚下都糊同一个金圈。程序化圆环是占位素材的水平, 这条不辩解。
	## ⚠ 但它是**共享**的: 直接删会波及所有装备/羁绊/技能 ⇒ 那是单独一轮的事(已记路线图)。
	##   这里只开一个口子: **本装备自绘时跳过通用环**, 由那件装备的演出层负责这一下。
	##   `_own_grant_vfx` 由自绘方在调 `_grant_shield` 前置 true, 本函数用完即清。
	if not bool(u.get("_own_grant_vfx", false)):
		battle._skill_ring(u["pos"], Color(1.0, 0.85, 0.2, 0.4), 44.0)
	u.erase("_own_grant_vfx")
	battle._audio_sys._sfx_shield_gain()                       # §AUDIO: 得盾音 (节流; 群体上盾不刷屏)


# silent=true: 吸血等高频被动回血不出治疗音 (防刷屏), 主动治疗/技能回血出音
## 盾羁绊【圣光·强化】(9 档): 盾类装备为携带者提供护盾或治疗时, 额外给其 20% 的圣光护盾值。
## ★为什么要 reentrancy 守卫: 这里自己也调 _grant_shield, 不拦就是无限递归。
##   ★为什么用 _cur_eq_item 而不是给管线加"来源"参数: 护盾/治疗的调用点有几十处,
##     加参数要全改一遍; 而装备效果的分发本来就在几个 for 循环里, 在那里标一下最省。
var _holy_busy := false
func _holy_convert(u: Dictionary, amt: float) -> void:
	if _holy_busy or amt <= 0.0:
		return
	var iid: String = str(battle._cur_eq_item)
	if iid == "" or battle.Phase2Types.type_of(iid) != "盾":
		return                                  # 只认【盾类装备】给的
	if int(battle._synergy.tier_for(u, "盾")) < 3:
		return                                  # 9 档才有
	_holy_busy = true
	var conv: float = amt * battle._shield_syn.T3_CONVERT
	_grant_shield(u, conv)
	## ★这份也记进圣盾账(2026-08-12 用户:「9 档时自己获得普通护盾也会获得罩子」)——
	##   血条白黄段与持有球罩读的都是 `_holyShieldVal`, 不记这里就只有 095 那条路算数。
	u["_holyShieldVal"] = minf(float(u.get("_holyShieldVal", 0.0)) + conv,
		float(u.get("shield", 0.0)))
	_holy_busy = false


func _heal(u: Dictionary, amt: float, silent: bool = false) -> float:   # 返回【实际】回血(满血=0·溢出转盾不计·用户2026-07-19"按实际治疗算")
	if amt <= 0.0: return 0.0
	amt *= battle._copy_fx_mult                        # 龟壳复制期: 治疗也按60%
	amt *= 1.0 + float(u.get("heal_amp", 0.0))   # 治疗加成(受到方,所有来源)
	amt *= battle._sd_heal_mult()                       # §SUDDEN 决胜期治疗 ×50%
	if battle._t < float(u.get("heal_reduce_until", 0.0)):
		amt *= maxf(0.0, 1.0 - float(u.get("heal_reduce_pct", 0.0)))   # 治疗削减(凤凰涅槃/烫伤等)
	## ★★【治疗封顶】(用户 2026-08-12:「小手枪增加限制: 受到的所有治疗都将为1点」)。
	##   位置有讲究, 两点:
	##   ① 放在 `_heal()` 里 = **所有治疗源的共用收口**(079 医疗炮台 / 法器灵泉 / 食物盛宴 /
	##      090 治疗浪潮 各有各的入口), 在别处拦只拦得住一条 —— 同伤害封顶 `_dmg_cap_val`。
	##   ② 放在**所有乘算之后**: 「受到的治疗都将为 1 点」说的是最终到手。
	##      第一版写在函数最前面, 结果 `heal_amp +200%` 把封顶后的 1 又放大成 3 ——
	##      门禁当场抓到(「封顶在加成之前」那条断言)。
	var _hcap: float = float(u.get("_heal_cap_val", 0.0))
	if _hcap > 0.0:
		amt = minf(amt, _hcap)
	var hb: float = u["hp"]
	u["hp"] = minf(u["maxHp"], u["hp"] + amt)
	u["_st_heal"] = int(u.get("_st_heal", 0)) + int(u["hp"] - hb)   # §STATS: 实际回复(超过满血不计)
	var _osc: float = float(u.get("overheal2shield_cap", 0.0))   # 饮血护符坠(011): 溢出治疗(超过满血部分)转血护盾, 累积上限
	if _osc > 0.0:
		var _ovf: float = amt - float(u["hp"] - hb)   # 请求治疗量 - 实际回复 = 溢出
		if _ovf > 0.0 and u["shield"] < _osc:
			u["shield"] = minf(_osc, u["shield"] + _ovf)   # 静默累积(吸血高频不刷飘字), 由携带者护盾条显示
	_holy_convert(u, float(u["hp"] - hb))   # 盾羁绊9档: 盾类装备给的治疗, 额外 20% 转圣光护盾
	battle._blood_rite_refresh(u)   # 剑【血祭】: 回血也要刷(血量涨回去攻击力要跌回去)
	var _act: float = float(u["hp"] - hb)   # 实际回血(满血=0, 超出满血/转盾部分不计入绿字)
	# ★【受到治疗时】这个钩子位置保留(它是批③为旧 071 建的中央钩), 但 2026-08-06 起
	#   **没有任何装备挂在上面** —— 071 已被用户整条重做成【炼乳罐】(全队奶油护盾 + 破盾 AOE),
	#   不再需要"把回血分给友军"。原来的 `_kelp_share` 守卫恒不成立、`_eq_kelp_share` 零调用者,
	#   两边一起删掉(实装那路如实报了这条死码, 并指出调用点在本文件、要主会话连着收)。
	#   ⚠ 留着这段注释是因为**钩子位置本身有价值**: 以后再有"受到治疗时"的装备, 挂这里。
	battle._staff_syn.on_healed(u, _act)   # 法器【余韵】: 受到治疗时额外获得治疗量 N% 的护盾
	if _act > 0.0:                          # LoL式治疗累加器: 高频/多段/多源回血攒进累加, 短窗后合并成一个绿字(见_heal_flush)
		u["_heal_acc"] = float(u.get("_heal_acc", 0.0)) + _act
		u["_heal_acc_t"] = battle._t
		if float(u.get("_heal_acc_start", 0.0)) <= 0.0:
			u["_heal_acc_start"] = battle._t
	if not silent:
		battle._audio_sys._sfx_heal()                          # §AUDIO: 治疗音 (节流)
	return _act

func _heal_flush(u: Dictionary) -> void:   # LoL式: 治疗累加器→静默0.15s(一波打完)或攒够0.6s→合并弹一个绿字(=实际回血)
	var acc: float = float(u.get("_heal_acc", 0.0))
	if acc <= 0.0:
		return
	if battle._t - float(u.get("_heal_acc_t", 0.0)) >= 0.15 or battle._t - float(u.get("_heal_acc_start", 0.0)) >= 0.6:
		if int(round(acc)) >= 1:
			battle._vfx._float_text(u["pos"] + Vector2(0, -40), "+" + str(int(round(acc))), Color("#06d6a0"), false, "heal")
		u["_heal_acc"] = 0.0
		u["_heal_acc_start"] = 0.0

# 韧性: CC实际时长 = 基础 ×(1-韧性), 最多减90%
## 眩晕唯一入口(收口自原先分散的 17 处 `X["stun_until"] = maxf(...)`).
##
## 为什么收口: 巡检 171 局抓到 2 例单位被连续眩晕 11 秒(彩虹龟/忍者龟), 且每次采样"剩余"都只有 1.7~1.8s
## —— 不是一次长控, 是 ~2 秒的眩晕被反复续上。原先 17 个施加点各写各的, 既查不出是谁在续,
## 以后想加递减(DR)也得改 17 处。现在: 韧性(battle._cc_dur)、来源记录、将来的 DR 规则都只在这里。
##
## tenacity=false 用于【自身施法定身】(缩头/亡灵拉全场等), 那是自己给自己上的动作锁, 不该吃自己的韧性。
## 这只单位现在免控吗。
##
## ★2026-08-21 新增。由来: `_stun()` 被免疫时是**静默 return**, 不返回任何东西 ⇒
##   调用方**拿不到"它被免疫了"这件事**。而近战小将的新机制需要"目标免控就改成
##   直接结算伤害、不把自己拉过去"(用户 2026-08-20 拍板), 没有这个查询就写不出来。
## ★读的是 `_stun` 用的**同一个字段**, 不另起一套 —— 手抄的副本必然落后。
func _is_cc_immune(u) -> bool:
	if not (u is Dictionary):
		return false
	return battle._t < float((u as Dictionary).get("cc_immune_until", 0.0))


func _stun(u: Dictionary, sec: float, src_tag: String, no_tenacity: bool = false) -> void:
	# ★免控窗口(2026-07-28): 单位在 cc_immune_until 之前免疫一切眩晕/冻结。
	#   加在【唯一入口】而不是各技能自己判 —— 财神梭哈投币期免控是第一个用例, 但这是通用能力,
	#   写进技能里就等于下一个要用的人再写一遍(眩晕收口前正是 17 处各写各的)。
	if battle._t < float(u.get("cc_immune_until", 0.0)):
		return
	var d: float = sec if no_tenacity else battle._cc_dur(u, sec)
	if battle._audit:
		# ★无条件记账. 第一版只在"已晕着又被续"时记, 结果明细恒为空 —— 因为控制是在采样缝隙里
		# 断开再重上的(每次都是"当前没晕"→不记), 而 1 秒一次的采样看不见那个缝, 于是把
		# "断续被控 11 秒"误报成"连续眩晕 11 秒"。指标要数【施加次数】, 不是数采样。
		var ch: Dictionary = u.get("_stun_chain", {})
		ch[src_tag] = int(ch.get(src_tag, 0)) + 1
		u["_stun_chain"] = ch
		u["_stun_n"] = int(u.get("_stun_n", 0)) + 1
	u["_stun_src"] = src_tag
	u["stun_until"] = maxf(float(u.get("stun_until", 0.0)), battle._t + d)

func _buff(u: Dictionary, stat: String, amount: float, pct: bool, sec: float = battle.BUFF_SEC) -> void:
	u["buffs"].append({"stat": stat, "amount": amount, "pct": pct, "until": battle._t + sec})
	battle._recalc_stats(u)

# 层数式 DoT 施加 (1:1 dot.gd apply_stacks). type∈[burn,poison,bleed]; 多次施加→累加层数. burn 检免疫.
## 诅咒每秒伤害 = 目标最大生命 × 这个比例(所有诅咒源统一: 幽灵/无头触须/彩虹)
const CURSE_HP_PCT := 0.05

## ★诅咒统一入口(2026-07-28 用户:「不要层数, 以秒数来, 每秒5%; 重复叠加可以叠加时长, 无限叠加」)
##
## 与 battle._add_dot 的区别: 那个是 append —— 重复施加会【并存多条】、伤害成倍
## (原来 登场诅咒 + 灵魂风暴 + 死亡诅咒 三条同时跑 = 15%/秒)。
## 诅咒改为: 同一目标【只保留一条】, 每秒固定 5% 最大生命真伤, 重复施加把【时长累加】上去(无上限)。
## → 总量相近但爆发被拉平成持续, 不会再出现"开局叠三层瞬间蒸发"。
##
## ★只对 curse 生效: 灼烧/中毒/流血/装备 DoT 全部照走 battle._add_dot, 行为不变。
##   (_add_dot 是全局函数, 直接改它会波及所有 DoT, 所以在这一层拦。)
## ★放在本类: 诅咒是【跨龟的全局状态效果】(幽灵/无头/彩虹共用), 不属于任何单只龟的系统;
##   本文件头自陈"DoT机制", _apply_dot_stacks 也在这里 —— 同层同家。
func _add_curse(tgt: Dictionary, sec: float, src = null) -> void:
	var dps: float = float(tgt.get("maxHp", 0.0)) * CURSE_HP_PCT
	for d in tgt.get("dots", []):
		if str(d.get("tag", "")) == "curse":
			# 已过期的那条从【现在】起算, 否则会把过去的时间也累进去
			d["until"] = maxf(float(d.get("until", 0.0)), battle._t) + sec
			d["dps"] = dps                      # 最大生命可能中途变过 → 用当前值
			if src != null:
				d["src"] = src
			return
	battle._add_dot(tgt, "curse", dps, sec, src)


func _apply_dot_stacks(u: Dictionary, type: String, stacks: int, src = null) -> void:
	if u == null or not u.get("alive", false) or stacks <= 0:
		return
	if battle._copy_fx_mult != 1.0:
		stacks = maxi(1, roundi(float(stacks) * battle._copy_fx_mult))   # 龟壳复制期: DoT层数也按60%
	if type == "burn":
		if u.get("_burnImmune", false):
			return
		var passive = u.get("passive", null)
		if passive is Dictionary and passive.get("burnImmune", false):
			return
	var ds: Dictionary = u["dot_stacks"]
	ds[type] = int(ds.get(type, 0)) + stacks
	if src != null:
		u["dot_src"][type] = src

# 灼烧默认层数 = max(1, round(attacker.atk × 0.67))  (1:1 dot.gd default_burn_stacks)
# DoT 抗性减免(用户2026-07-19: 灼烧/中毒=魔法吃魔抗, 流血=物理吃护甲)。
# ★2026-07-22 用户拍板「DOT 要享受穿甲增伤等」→ 加入施加者的 护穿/法穿 与 damage_amp,
#   与 _resolve_dmg(7926-7945) 的口径一致。取值方式 = 【每跳实时查施加者】(用户选定,
#   而非施加时快照)。施加者死后单位字典【不销毁】, 属性仍在 → 继续按它死时的数值算, 不会归零。
#   ★已知限制(方案书 H19′): dot_src 只存最后一个施加者, 两人叠同种毒时前者的穿甲不生效。
func _dot_after_resist(u: Dictionary, dmg: float, magic: bool, src = null) -> int:
	var resist: float = float(u["mr"]) if magic else float(u["def"])
	if src is Dictionary:
		if magic:
			resist = resist * (1.0 - float(src.get("magic_pen_pct", 0.0))) - float(src.get("magic_pen", 0.0))
		else:
			resist = resist * (1.0 - float(src.get("armor_pen_pct", 0.0))) - float(src.get("armor_pen", 0.0))
	var mult: float = DamageMath.resist_multiplier(resist)
	var out = dmg * mult
	if src is Dictionary:
		out *= (1.0 + float(src.get("damage_amp", 0.0)))   # 攻击者增伤(信号放大器038 等)
	_dt_resolved = true                                    # 哨兵第三只眼: 这一段真算过抗性
	return maxi(1, int(round(out)))

# 层数 DoT 每秒结算 (1:1 dot.gd tick). 固定顺序 burn→poison→bleed; 出伤后层数衰减, ≤0 移除.


## 【攻速总倍率·单一事实源】真实冷却 = atk_interval / aspd_mult(u); 面板显示 = aspd_mult(u) / atk_interval。
## 由来与反向验证见 tests/verify_aspd_panel_live.gd(面板曾只读 atk_interval ⇒ 加成全看不见)。
func aspd_mult(u: Dictionary) -> float:
	var hf: float = maxf(1.0, float(u.get("haste_mult", 1.0))) if battle._t < float(u.get("haste_until", 0.0)) else 1.0
	var dbf: float = float(u.get("spd_aspd_mult", 1.0)) if battle._t < float(u.get("spd_dbf_until", 0.0)) else 1.0
	return maxf(0.1, hf * dbf * float(u.get("aspd_perm", 1.0)) * anchor_aspd(u) * float(u.get("_turret_aspd_mult", 1.0)))


func anchor_aspd(u: Dictionary) -> float:   # 不沉之锚017: 持有沉锚充能期间普攻+100%攻速(用户2026-07-19)
	var ast: Dictionary = u.get("eq_state", {}).get("p2eq_017", {})
	if ast.is_empty():
		return 1.0
	if int(ast.get("anchor_charges", 0)) > 0:
		return 1.0 + EquipTickSystem.ANCHOR_ASPD
	# 刚用掉最后一点充能的这一发也算"持有充能"(避免末发掉速)
	return 2.0 if absf(battle._t - float(u.get("anchor_swing_t", -99.0))) < 0.001 else 1.0
