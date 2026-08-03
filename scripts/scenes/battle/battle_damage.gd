class_name BattleDamage
extends RefCounted
## 战斗结算: 两伤害路(_apply_damage DoT/真伤 + _apply_damage_from 普攻/技能·§3.3)+治疗/护盾/buff/眩晕/击退/DoT机制(含crit/dodge RNG·确定性核心)
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

func _apply_damage(u: Dictionary, dmg: int, col: Color, src = null, bucket: String = "dot", is_self: bool = false, dot_accum: bool = false, mute_sfx: bool = false) -> void:
	if u.get("_assembling", false):
		return   # 机甲组装期免疫一切伤害。★这条路径(DoT/真伤)原先没有这个闸, 只有 _apply_damage_from 有 → DoT 能打穿组装免疫(2026-07-19)
	if battle._sd_stacks > 0:
		dmg = maxi(1, int(round(float(dmg) * (1.0 + battle._sd_amp()))))   # §SUDDEN 决胜增伤(这条路走 DoT/真伤等)
	# ★2026-07-22 全量对齐: 过与 _apply_damage_from 同一套受害者减伤(见 §MITIGATE)。
	#   bucket=="tru" 视为真伤 → 与另一条路的 raw 语义一致(真伤只无视护甲/减伤, 护盾照吸)。
	var _raw: bool = (bucket == "tru")
	var d = battle._mitigate_incoming(u, float(dmg), _raw, is_self)
	dmg = maxi(1, int(round(d)))                     # 统计/飘字用减伤【后】的值, 否则面板数字与实际掉血对不上
	var shield_before: float = u["shield"]
	d = ShieldMath.absorb(u, d)   # 普通盾+aura盾 吸全类型(§3.3 收口·两路共用)
	# 弓箭顶档【腐蚀满 5 层】: 受到伤害的 25% 转成真实伤害(无视护甲与护盾)。
	# ⚠ 两条伤害路径【都要加】—— _apply_damage(DoT/真伤) 与 _apply_damage_from(普攻/技能)
	#   各自独立扣血(CLAUDE.md §3.3), 只改一条会产生"只在某类伤害下才转真伤"的诡异行为。
	var _cor: float = BowSynergySystem.true_share(u)
	if _cor > 0.0 and bucket != "tru":   # ★这条路(_apply_damage)没有 raw 参数, 用 bucket 判真伤
		d += float(dmg) * _cor                       # 名义伤害的 25% 直接加进扣血(不经护甲/护盾)
	u["hp"] = maxf(0.0, u["hp"] - d)
	battle._blood_rite_refresh(u)   # 剑【血祭】: 血量百分比整数位变了才重算攻击力(无血祭的单位零开销)
	# 无头龟·亡灵免死锁血: 另一条路有(deathfloor_until), 这条路没有 → 免死光环亮着人被 DOT 烧死
	if u["hp"] <= 0.0 and battle._t < float(u.get("deathfloor_until", 0.0)):
		u["hp"] = 1.0
	if u.get("_review_dummy", false): u["hp"] = u["maxHp"]   # 训练靶: 受击即回满, 打不死不结算(看完整)
	if battle._audit and dmg > 100000:
		battle._audit_flag("huge_hit", "%s 单次承伤 %d (%s)" % [str(u.get("name", "?")), dmg, bucket])
	u["_st_taken"] = int(u.get("_st_taken", 0)) + dmg
	battle._st_add_type(u, "_st_taken_by_type", bucket, dmg)
	# §STATS 修(用户2026-07-19"统计面板感觉很多伤害没统计"): DoT(灼烧/中毒/流血)此前【只计承受方】,
	#   施加者的"造成"完全没算 —— 而 dot_src 一直有记来源, 只是结算时没用。这里补上施加者归属。
	if src is Dictionary and src.get("alive", false) and not is_same(src, u):
		src["_st_dealt"] = int(src.get("_st_dealt", 0)) + dmg
		battle._st_add_type(src, "_st_dealt_by_type", bucket, dmg)
	# ★DOT 累积模式(点1): 不跳小飘字, 累加进头顶【按伤害类型桶】的常驻数字(灼烧+中毒同 mag 桶)。
	if dot_accum:
		_dot_accumulate(u, bucket, dmg)
	else:
		battle._vfx._float_text(u["pos"] + Vector2(randf_range(-26.0, 26.0), -40.0 + randf_range(-10.0, 6.0)), str(dmg), col)   # 抖开: 多段/AOE 出伤飘字不重叠成糊团
	# §AUDIO: 无来源伤害也出命中音 (非暴击); 护盾破→shield-break。mute_sfx=诅咒 tick 静音(用户2026-07-23)
	if not mute_sfx:
		if shield_before > 0.0 and u["shield"] <= 0.0:
			battle._audio_sys._sfx_shield_break()
		else:
			battle._audio_sys._sfx_hit(false)
	if u["hp"] <= 0.0 and u["alive"]:
		# ★带上 src: 原为 battle._kill(u) 无凶手 → DOT 击杀【不算击杀数】, 且暴君之牙处决回血这类
		#   on-kill 装备钩子全不触发(对比另一条路 battle._kill(u, src))。2026-07-22 修。
		battle._kill(u, src if src is Dictionary else null)

# 来源已知的伤害: 闪避 / 吸血 / 伤害统计 / 累积条(怒气/星能/储能) / 受伤被动. extra_ls=技能额外吸血%; raw=真伤穿盾
# 来源已知的伤害: 闪避 / 吸血 / 伤害统计 / 累积条(怒气/星能/储能) / 受伤被动. extra_ls=技能额外吸血%; raw=真伤穿盾
## ★no_popup: 不跳通用伤害飘字。给【自己维护一个常驻数字】的效果用 ——
##   靶向器钩索炸弹的 DoT 是"宿主头上一个累加滚动数字"(用户 2026-08-01 指定),
##   再叠一串通用红字就是两个数字打架。伤害/统计/护盾一切照旧, 只是不弹那个字。
func _apply_damage_from(src: Dictionary, u: Dictionary, dmg: int, col: Color, extra_ls: float = 0.0, raw: bool = false, from_equip: bool = false, pre_crit: bool = false, no_dodge: bool = false, no_popup: bool = false) -> void:
	battle._adf_ct += 1
	if battle._adf_ct > 20000:                        # 防御: 一帧伤害调用爆炸(死亡链无限级联)→本帧后续伤害丢弃防卡死(用户2026-07-19卡死猎手)
		if not battle._adf_warned:
			battle._adf_warned = true
			printerr("[GUARD] _apply_damage_from 一帧调用超2万→截断防卡死 (last=%s src=%s)" % [str(u.get("id", "?")), str(src.get("id", "?"))])
		return
	if battle._stress: battle._dbg_op2 = str(u.get("id", "?"))   # 卡死猎手诊断: 最后经手的受伤单位
	# pre_crit=true: 该 raw 段的暴击已在上游算进 dmg(如手里剑真伤段=暴击总伤的一部分)→ 此处不再掷真伤暴击(防二次暴击)
	if u.get("_assembling", false):   # 机甲组装期免疫一切攻击(用户2026-07-16)
		return
	# 闪避 (目标 dodge_bonus); 瞄准镜054: 攻击者伤害无视闪避 (必中)
	# no_dodge: 吸取类必中(用户2026-07-22「吸取不可以被闪避或暴击」)
	if not no_dodge and u.get("dodge_bonus", 0.0) > 0.0 and not src.get("eq_cannot_be_dodged", false) and battle._battle_rng.randf() < u["dodge_bonus"]:
		battle._vfx._float_text(u["pos"] + Vector2(0, -40), "闪避", Color("#a0e8ff"))
		battle._equip_sys._eq_on_dodge(u)          # on-dodge 钩子 (幽灵墨鱼046: 闪避→永久护盾)
		return
	# 小龟·不屈: 造成的任何伤害按目标稀有度增伤 (总闸→普攻/技能/真伤/固定伤全覆盖, 只算一次)
	if src.get("id", "") == "basic" and not is_same(src, u):
		dmg = int(round(float(dmg) * (1.0 + battle._BASIC_RARITY_BONUS.get(str(u.get("rarity", "C")), 0.20))))
	# 伤害输出乘数 (龟壳复制60%等; 默认1.0=不变): 缩放src本次造成的即时伤害
	if src.get("dmg_out_mult", 1.0) != 1.0:
		dmg = int(round(float(dmg) * float(src.get("dmg_out_mult", 1.0))))
	if battle._sd_stacks > 0:
		dmg = maxi(1, int(round(float(dmg) * (1.0 + battle._sd_amp()))))   # §SUDDEN 决胜增伤(这条路走普攻/技能主线)
	# 星辉战利品(宝箱传说): 所有伤害转真实=跳过减伤(钻石18%/岩层/铁壁flat) — 完整"绕护甲"局限留F5(伤害多已由_atk_dmg预减)
	if src.get("chest_starlight", false):
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
		_ink_true = float(dmg) * 0.05 * float(_ink)   # 墨迹: 原伤害之外·每层额外承受5%【真实伤害】(穿减伤穿盾·满10层=50%·用户2026-07-10纠正: 非×1.05增伤)
	# ★受害者侧减伤(靶向器/暴露蛋/钻石/岩层/嘲讽/铁壁盾)全部收口到 §MITIGATE,
	#   与 _apply_damage 共用 —— 原先这段只在本函数里, 导致 DOT 完全不吃任何减伤。
	var d = battle._mitigate_incoming(u, float(dmg), raw)
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
	if _ink_true > 0.0: d += _ink_true   # 墨迹真伤: 穿减伤穿盾(唯一穿盾例外·护盾吸收后加), 直接进扣血并计入跳字
	# 弓箭顶档【腐蚀满 5 层】: 受到伤害的 25% 转成真实伤害(无视护甲与护盾)。
	# ⚠ 两条伤害路径【都要加】—— _apply_damage(DoT/真伤) 与 _apply_damage_from(普攻/技能)
	#   各自独立扣血(CLAUDE.md §3.3), 只改一条会产生"只在某类伤害下才转真伤"的诡异行为。
	var _cor: float = BowSynergySystem.true_share(u)
	if _cor > 0.0 and not raw:
		d += float(dmg) * _cor                       # 名义伤害的 25% 直接加进扣血(不经护甲/护盾)
	u["hp"] = maxf(0.0, u["hp"] - d)
	battle._blood_rite_refresh(u)   # 剑【血祭】: 血量百分比整数位变了才重算攻击力(无血祭的单位零开销)
	if u.get("_review_dummy", false): u["hp"] = u["maxHp"]   # 训练靶: 受击即回满, 打不死不结算(看完整)
	if not from_equip and d > 0.0: battle._line_sys._ink_link_transfer(u, d)   # 连笔: 受伤30%以真实伤害传导给连接对象(附录B-05)
	# §STATS: 战斗统计 — 输出归攻击者/承受归目标 (用显示数 dmg); 按伤害类型分桶(战中分段条用) + 暴击计数
	var _bkt: String = ("tru" if raw else ("mag" if battle._last_dmg_type == "magic" else "phy"))   # 伤害分桶=真实类型(battle._last_dmg_type/raw), 非col: col是主题色·大量物理攻击传偏蓝色(忍者冲击#9fe8ff/#cfd8e8等)→原按col.b>col.r误判成法术=统计条+飘字全蓝(用户2026-07-11抓出)
	if src is Dictionary and src.has("side") and not is_same(src, u):
		src["_st_dealt"] = int(src.get("_st_dealt", 0)) + dmg
		battle._st_add_type(src, "_st_dealt_by_type", _bkt, dmg)
		if was_crit:
			src["_st_crit"] = int(src.get("_st_crit", 0)) + 1
	u["_st_taken"] = int(u.get("_st_taken", 0)) + dmg
	battle._st_add_type(u, "_st_taken_by_type", _bkt, dmg)
	# headless 亡灵: 首次濒死→5秒内HP不降到1以下(免死), 5秒后正常死
	if u["id"] == "headless" and u["hp"] <= 0.0 and not u.get("undead_used", false):
		u["undead_used"] = true; u["deathfloor_until"] = battle._t + 5.0
		battle._vfx._float_text(u["pos"] + Vector2(0, -64), "亡灵!", Color("#9b6bff"))
		battle._headless_sys._headless_undead_vfx(u)                                    # 免死金骨光环5秒(2026-07-17)
	if battle._t < float(u.get("deathfloor_until", 0.0)):
		u["hp"] = maxf(1.0, u["hp"])
	var _dt: String = "true" if raw else battle._last_dmg_type   # 飘字类型=真实伤害类型(_resolve_dmg设的_last_dmg_type·即时伤害对); 远程弹道在飞时会被别的伤害覆写→弹道在_step_projectiles命中前用捕获的pr.dtype还原(见那里)
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
		if _sx > 0.0 and _bacc < 30.0:
			var _dec: float = minf(_sx, 30.0 - _bacc)
			u["base_def"] = maxf(0.0, u["base_def"] - _dec)
			u["base_mr"] = maxf(0.0, u["base_mr"] - _dec)
			u["bind_acc"] = _bacc + _dec
			battle._recalc_stats(u)
	# 泡泡·泡沫: 受伤的100%存为泡泡值(上限maxHp) → 周期消耗(见 _tick_periodic_passive)
	if u["id"] == "bubble":
		u["bubble_store"] = minf(u["maxHp"], float(u.get("bubble_store", 0.0)) + d)
	# 反伤(通用): 受击反弹 reflect% × 受到伤害 给攻击者(真实伤害); from_equip守卫防循环; stone坚壁随防御涨(被动)
	var _refl_pct: float = float(u.get("reflect", 0.0))
	if u["id"] == "stone": _refl_pct += 0.05 + (u["def"] + u["mr"] * 0.5) * 0.01
	if u["id"] == "stone" and u.get("stone_rockbody", false) and not from_equip and dmg > 0 and int(u.get("rock_layers", 0)) < 30:
		u["rock_layers"] = int(u.get("rock_layers", 0)) + 1   # 岩层(岩石之躯被动·选此才有): 每受伤+1层上限30
		u["size_mult"] = 1.0 + 0.02 * float(u["rock_layers"])   # +2%体型/层(回合制 rockShockwave.rockSizePctPerLayer=2·满30层=+60%)
	if _refl_pct > 0.0 and not is_same(src, u) and src.get("alive", false) and not from_equip and dmg > 0:
		var _refl = int(dmg * _refl_pct)
		if _refl > 0:
			_apply_damage_from(u, src, _refl, Color("#c9a36b"), 0.0, true, true)
	# 凤凰熔岩盾: 5秒内对每段攻击反击 0.14×ATK 魔法 (from_equip守卫防循环)
	if u["id"] == "phoenix" and battle._t < float(u.get("lava_shield_until", 0.0)) and not is_same(src, u) and src.get("alive", false) and not from_equip and dmg > 0:
		_apply_damage_from(u, src, battle._atk_dmg(u, 0.14, src, true), Color("#ff7a3c"), 0.0, false, true)
	# 闪电雷盾: 盾在时对每段攻击反击 0.3×ATK 魔法(用户2026-07-29 平衡四轮: 0.1→0.3) + 给攻击者叠1层电击
	if u["id"] == "lightning" and battle._t < float(u.get("thunder_shield_until", 0.0)) and float(u.get("shield", 0.0)) > 0.0 and not is_same(src, u) and src.get("alive", false) and not from_equip and dmg > 0:
		_apply_damage_from(u, src, battle._atk_dmg(u, 0.3, src, true), Color("#4dabf7"), 0.0, false, true)
		battle._add_stack(src, "electric", 1, 8)
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
	src["dmg_dealt"] += float(dmg)
	# 吸血 (lifesteal 基础 + buff + 技能 extra) — silent: 高频回血不刷治疗音
	var ls: float = src.get("lifesteal", 0.0) + src.get("ls_bonus", 0.0) + extra_ls
	if ls > 0.0 and src["alive"]:
		_heal(src, float(dmg) * ls, true)
	# 猎人猎杀(重做·用户2026-07-14): 处决不再在此中央路径逐次判; 改由 _update_hunter_passive 每帧扫场→任一敌<斩杀线→自动射强化箭→命中处决. 窃取仍走 battle._kill→_on_unit_death 钩子.
	# 怒气 (熔岩造伤25% / 受伤20%)
	if src["id"] == "lava" and not src.get("volcano", false):     # 火山形态不获怒气(条=形态倒计时·用户2026-07-15)
		src["rage"] = minf(battle.RAGE_MAX, src["rage"] + float(dmg) * 0.10)
	if u["id"] == "lava" and not u.get("volcano", false):
		u["rage"] = minf(battle.RAGE_MAX, u["rage"] + float(dmg) * 0.10)
	if src is Dictionary and src.get("has_egg", false) and src.get("alive", false):   # 温泉蛋(036): 造成伤害×0.1进度
		battle._equip_tick_sys._egg_add_progress(src, float(dmg) * 0.1)
	if u.get("has_egg", false):   # 温泉蛋(036): 承受伤害×0.1进度
		battle._equip_tick_sys._egg_add_progress(u, float(dmg) * 0.1)
	# 星能 (星际造伤35%·用户2026-07-16: 62→35; 星波施法期锁定不涨)
	if src["id"] == "space" and battle._t >= float(src.get("star_lock_until", 0.0)):
		src["star_energy"] = minf(src["maxHp"] * 0.40, src["star_energy"] + float(dmg) * 0.35)
	# 储能 (龟壳受伤转储能, 上限50%最大HP) — 仅"store"相位累积 ("cd"相位不储)
	if u["id"] == "shell" and u.get("shell_phase", "store") == "store":
		u["store_energy"] = minf(u["maxHp"] * 0.50, u["store_energy"] + float(dmg))
		u["_auraEnergy"] = u["store_energy"]   # 镜像给Hp条储能条显示(1:1回合制字段)
	if u["id"] == "shell" and float(dmg) > 0.0:
		u["shell_last_dmg_t"] = battle._t                 # 潜影(暗影被动): 记最后受伤时间(6秒无伤→隐身). AOE命中也计→不误进隐身(设计: AOE吃伤但不破隐, 未说进隐身; 计伤保守=受伤即重置)
	# 双头坚韧 (融合打包被动·选中融合才有): 每受一段攻击 +1护甲+1魔抗 (各上限20)
	if u["id"] == "two_head" and u.get("two_fused", false):
		var th: int = int(u.get("two_tough", 0))
		if th < 20:
			th += 1; u["two_tough"] = th
			u["base_def"] += 1.0; u["base_mr"] += 1.0; battle._recalc_stats(u)
			if battle._t - float(u.get("_tough_glint_t", -1.0)) > 0.35:   # 坚韧变硬微光(节流·用户2026-07-11)
				u["_tough_glint_t"] = battle._t
				battle._skill_ring(u["pos"], Color(0.55, 0.75, 1.0, 0.5), 46.0)
	# (反伤已合并到上方通用块, 删除重复的第二处石头反伤)
	# 装备事件钩子 (on-hit 攻击方 / on-target 防守方 / HP阈值) — 装备自身造的段不再回钩
	if not from_equip:
		if src["alive"] and u["alive"]:
			battle._equip_sys._eq_on_hit(src, u, dmg)        # on-hit: 攻击者装备 (流血/灼烧/连锁/追击/穿透/标记 等)
			battle._bow_syn.on_hit(src, u)                   # 弓箭【处决】: 全队(用户2026-08-03改), 斩杀线按各自暴击率
		if u["alive"]:
			battle._equip_sys._eq_on_target(u, src, dmg)     # on-target: 防守者装备 (硬化层/冰封反制 等)
			battle._shield_syn.on_damaged(u, src, dmg)       # 盾羁绊: 怒气累计(全队·满400放冲击波) + 顶档反击
		# 宝箱藏宝图 on-hit 战利品 (火石灼烧/毒箭治疗削减/雷刃金闪电引爆·此块已在not from_equip内→天然防循环)
		var _cht = src.get("chest_treasures", null)
		if _cht is Dictionary and not is_same(src, u) and u.get("alive", false):
			if _cht.has("flint"):    # 火石: 命中→灼烧层=round(0.1×ATK)(用户2026-07-16: 0.67→0.1)
				_apply_dot_stacks(u, "burn", maxi(1, roundi(float(src["atk"]) * 0.1)), src)
			if _cht.has("poison"):   # 毒箭: 命中→治疗削减-50%·5秒
				u["heal_reduce_until"] = maxf(float(u.get("heal_reduce_until", 0.0)), battle._t + 5.0)
				u["heal_reduce_pct"] = maxf(float(u.get("heal_reduce_pct", 0.0)), 0.5)
			if _cht.has("thunder"):  # 雷刃: 命中叠金闪电·满5→引爆1.0A真伤(from_equip=true防循环)
				var _tl = battle._add_stack(u, "chest_thunder", 1, 5)
				if _tl >= 5:
					battle._consume_stacks(u, "chest_thunder")
					_apply_damage_from(src, u, maxi(1, int(float(src["atk"]))), Color("#ffe94d"), 0.0, true, true)
					battle._skill_ring(u["pos"], Color(1.0, 0.92, 0.3, 0.6), 40.0)
	if u["alive"]:
		battle._equip_sys._eq_check_hp_threshold(u)          # HP阈值: 首次<50% (深海项链/珍珠耳环)
		if str(u.get("id", "")) == "fortune" and not u.get("_lowhp_fired", false) and u["hp"] <= u["maxHp"] * FortuneSystem.LOWHP_PCT:
			battle._fortune_sys._fortune_lowhp_burst(u)       # 财神【通用被动】(用户2026-07-28): 首次跌破20%血 → 立得70龟能(不论带哪个技能)
	if u["hp"] <= 0.0 and u["alive"]:
		battle._kill(u, src)

# DoT 落血 (穿护盾, 不弹字防刷屏; 血条体现)
func _knockback(by: Dictionary, tgt: Dictionary, _dist: float, vy_mult: float = 1.0, push_mult: float = 1.0) -> void:
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
	u["shield"] = minf(u["shield"] + amt, u["maxHp"] * battle.SHIELD_CAP_MULT)
	if dur > 0.0:
		u["shield_until"] = maxf(float(u.get("shield_until", 0.0)), battle._t + dur)   # 限时盾原语(封板通用护盾=4秒): 记到期(多源取更晚); dur=0=永久(不设→_tick不过期·shell/嘲讽/既有盾全默认永久不变)
	var got = int(u["shield"] - sb)
	u["_st_shield"] = int(u.get("_st_shield", 0)) + got   # §STATS: 实际获盾
	if got >= 8:                             # #1 护盾飘字 "+N 盾" (浅蓝); 门槛过滤每帧微盾被动防刷屏
		battle._vfx._float_text(u["pos"] + Vector2(0, -52), "+%d 盾" % got, Color("#ffffff"), false, "shield")
	battle._skill_ring(u["pos"], Color(1.0, 0.85, 0.2, 0.4), 44.0)
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
	_grant_shield(u, amt * battle._shield_syn.T3_CONVERT)
	_holy_busy = false


func _heal(u: Dictionary, amt: float, silent: bool = false) -> float:   # 返回【实际】回血(满血=0·溢出转盾不计·用户2026-07-19"按实际治疗算")
	if amt <= 0.0: return 0.0
	amt *= battle._copy_fx_mult                        # 龟壳复制期: 治疗也按60%
	amt *= 1.0 + float(u.get("heal_amp", 0.0))   # 治疗加成(受到方,所有来源)
	amt *= battle._sd_heal_mult()                       # §SUDDEN 决胜期治疗 ×50%
	if battle._t < float(u.get("heal_reduce_until", 0.0)):
		amt *= maxf(0.0, 1.0 - float(u.get("heal_reduce_pct", 0.0)))   # 治疗削减(凤凰涅槃/烫伤等)
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
	return maxi(1, int(round(out)))

# 层数 DoT 每秒结算 (1:1 dot.gd tick). 固定顺序 burn→poison→bleed; 出伤后层数衰减, ≤0 移除.
