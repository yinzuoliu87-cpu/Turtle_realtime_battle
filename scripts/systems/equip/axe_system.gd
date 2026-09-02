class_name AxeSystem
extends RefCounted
## 小木斧 —— 斧头召唤物 + 通用主动 + 被动 2 (用户 2026-08-31·方案书三期)
##
## ★数值**全部**取自 `scripts/gamedata/axe_evolution.gd`(AxeEvolution)。
##   这里一个裸数字都不许有 —— 036 温泉蛋刚踩过"同一个数存两份必漂"。
##
## ★本期(三期)只做骨架:
##   · 登场召唤斧头(近战 / 1ATK / 0.8 攻速 / 双抗 5 / 血与攻随**历史累计经验**)
##   · 通用主动: 攒满 140 龟能 → 召唤物回 5% 最大生命 + 给自己 5% 最大生命护盾
##   · 被动 2(木斧就有): 召唤物普攻窃取目标 10% 护盾, **转成普通护盾**给自己
##   经验条/进化/商店换形态在四期; 被动 3~6 在五期; 最终造物在六期。
##
## ★「已收集的经验值」= **历史累计**(未决点 ⑥, 用户 2026-08-31「历史累计」)。
##   本期还没有攒经验的通路(那是四期), 所以读到的是 0 ⇒ 木斧召唤物 = 500 血 / 30 攻。
##   读的地方只有一个 `_exp_total()`, 四期把它接到 GameState 上即可。
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const AP := preload("res://scripts/systems/equip/axe_passives.gd")
const AFF := preload("res://scripts/systems/equip/axe_final_forms.gd")
const AFS := preload("res://scripts/gamedata/axe_final_stats.gd")

var battle = null
var _pas = null                          # 被动 3~6(五期), 见 axe_passives.gd
var _fin = null                          # 四个最终造物(六期), 见 axe_final_forms.gd


func _init(b) -> void:
	battle = b
	_pas = AP.new(b)
	_fin = AFF.new(b)


## 历史累计经验。★四期之前恒为 0 —— 但**必须现在就走这个函数**,
##   否则四期接上经验时得回头找散落各处的 0。
func _exp_total() -> int:
	return _gs_int("axe_exp_total", 0)


## 当前档位索引(0=木斧)。四期之前恒为 0。
func _stage_idx() -> int:
	return clampi(_gs_int("axe_stage", 0), 0, AE.STAGES.size() - 1)


## 从 GameState 读一个整数, **null 安全**。
## ★★这条防的是 memory [[fb-null-readback-makes-test-silently-abort]] 那个坑:
##   `Node.get("不存在的属性")` 返回 **null**, 而 `int(null)` 是运行时错误 ——
##   它会让**调用它的那个函数当场中止**, 剩下的断言一条都不跑, 而门禁照样打 ALL PASS
##   (唯一线索是断言总数悄悄变少)。所以这里显式判 null 再转。
## 从 GameState 读一个字符串, **null 安全**(同 _gs_int 那条注释)。
func _gs_str(prop: String, dflt: String) -> String:
	var gs = battle.get_node_or_null("/root/GameState")
	if gs == null:
		return dflt
	var v = gs.get(prop)
	return dflt if v == null else str(v)


func _gs_int(prop: String, dflt: int) -> int:
	var gs = battle.get_node_or_null("/root/GameState")
	if gs == null:
		return dflt
	var v = gs.get(prop)
	if v == null:
		return dflt
	return int(v)


## 登场召唤斧头。照 058 炮台的 `_spawn_summon` 底座。
func summon(u: Dictionary) -> Variant:
	if not u.get("alive", false):
		return null
	var et: int = _exp_total()
	var si: int = _stage_idx()
	var pv: int = AE.passives_at(si)
	var ax = battle._spawn._spawn_summon(u, "axe", AE.minion_hp(et, pv), AE.minion_atk(et, pv),
		{"label": str(AE.stage(si)["name"]), "spr_id": "axe", "col_size": AE.MINION_COL_SIZE, "hp_w": 28.0,
		 "atk_interval": 1.0 / AE.MINION_ASPD, "melee": true})
	if ax == null:
		return null
	ax["eq_state"] = {}
	ax["equips"] = []
	ax["_eq_axe"] = true                    # 认亲标记: 被动 2 / 主动都靠它认出"这是斧头"
	## ★把档位解锁的被动条数**钉在召唤物身上**, 而不是每次用的时候回头问 GameState:
	##   一路打到一半玩家在别处进化了, 场上这只不该中途变身(它的血/攻也是登场那一刻算的)。
	ax["_axe_pv"] = pv
	## ★被动的 +3 护甲 / +3 魔抗**必须算进来** —— 之前这里写死 MINION_DEF/MINION_MR,
	##   于是进化到钻石斧护甲魔抗还是 5/5(用户在游戏里看到的就是这个)。
	ax["base_def"] = AE.minion_def(pv)
	ax["base_mr"] = AE.minion_mr(pv)
	## ★主动是**召唤物自己**攒龟能(需求「主动治疗140龟能：斧头召唤物回复…并为自己提供…」,
	##   而且最终造物 4 明写"处决一个单位会使召唤物获得150点龟能" ⇒ 龟能确实在召唤物身上)。
	ax["maxEnergy"] = AE.ACTIVE_ENERGY
	ax["energy"] = 0.0
	## ★最终造物的属性要在 `_recalc_stats` **之前**折进去(它改的是 base_*)。
	##   ★钉在召唤物身上: 一路打到一半玩家在别处选了造物, 场上这只不该中途变身。
	_fin.apply_stats(ax, _gs_str("axe_final", ""))
	battle._recalc_stats(ax)
	ax["hp"] = float(ax["maxHp"])
	u["_axe_ref"] = ax                       # ★只用 is_same 比较, 绝不当 Dictionary 的键(CLAUDE.md §3.2)
	return ax


## 这一档的斧头召唤物**应该**是多少血/多少攻(纯函数, 门禁直接调它验数)。
func expected_hp() -> float:
	return AE.minion_hp(_exp_total(), AE.passives_at(_stage_idx()))


func expected_atk() -> float:
	return AE.minion_atk(_exp_total(), AE.passives_at(_stage_idx()))


## 通用主动: 攒满 140 龟能 → 回 5% 最大生命 + 给自己 5% 最大生命护盾, 然后清空龟能。
## ★结算与演出分开(CLAUDE.md §3.5): 这个函数是**纯结算**, 门禁直接调它;
##   演出(如果以后加)在末尾调它, 不许把数值埋进 tween 链。
func cast_heal(ax: Dictionary) -> bool:
	if not (ax is Dictionary) or not ax.get("alive", false):
		return false
	if float(ax.get("energy", 0.0)) < AE.ACTIVE_ENERGY:
		return false
	ax["energy"] = 0.0
	play_cast(ax)                    # 技能释放动画(用户点名的四条之一)
	_pas.vfx.heal(ax)                # 演出: 绿光柱(治疗) + 金底环(护盾) —— 对应下面两行的两个效果
	var mh: float = float(ax.get("maxHp", 0.0))
	battle._damage._heal(ax, mh * AE.ACTIVE_HEAL_PCT)
	battle._damage._grant_shield(ax, mh * AE.ACTIVE_SHIELD_PCT)
	return true


## 亡灵环的节拍器。★存"下一跳的时刻"而不是累加 delta —— 后者漏一帧就永远差一点,
##   而这类漏拍在游戏里看不出来(同 tick_smash 那条)。
func _tick_undead_ring(ax: Dictionary, _delta: float) -> void:
	if not ax.get("alive", false):
		return
	if not ax.has("_undead_ring_at"):
		ax["_undead_ring_at"] = float(battle._t) + AFS.UNDEAD_RING_TICK
		return
	if float(battle._t) < float(ax["_undead_ring_at"]):
		return
	ax["_undead_ring_at"] = float(battle._t) + AFS.UNDEAD_RING_TICK
	_fin.undead_ring_tick(ax)


## 播【技能释放】动画。
## ★为什么不复用 `_elite_anim`: 它开头就 `if not u.get("is_elite")` 直接 return ——
##   斧头是召唤物不是精英龟, 走那条永远播不出来(而且不会报错, 只是静默什么都不发生)。
## ★为什么把键放进 `ACTION_ELITE`: `_play_action` 的"committed 动作"闸认的就是这张表
##   (`battle.ACTION_ELITE.has(_cur_act)`) ⇒ 登记进去, 施法动画播到一半不会被普攻打断。
##   那张表的名字叫 ELITE 只是历史包袱, 它实际是"非标准一次性动作"的总表。
## ★★**没有 death / 没有 hurt**(用户 2026-08-31、09-01 两次点名): 四条就是
##   待机 / 走路 / 攻击 / 技能释放。ACTION_HURT 与 ACTION_DEATH 里一个 axe 键都没有,
##   门禁 verify_summon_art 会把这条焊死。
func play_cast(ax: Dictionary) -> bool:
	return play_action(ax, "axe_cast", false)


## 播斧头的**任意一个**招式动画。返回 true = 真的换上了帧表。
##
## ★★为什么做成一个出口而不是在八处各抄一遍 `_resolve_action + _set_anim_sheet`:
##   memory [[fb-hand-rolled-copies-drift]] —— 手抄的副本必然落后, 抄一次就永远差一次。
##   八个招式(smash/cleave/sweep/charge/slam/throw/plant/execute)全部走这里,
##   将来改 committed 闸/帧表解析只改这一处。
##
## ★`loop`: 蓄力(axe_charge)与插地(axe_plant)是**持续 4 秒的状态**, 要循环;
##   其余五个是一次性招式。这一位就是 `_set_anim_sheet` 的 `is_idle` 参数
##   —— 名字叫 idle 是历史包袱, 它的真实语义是"循不循环"。
##
## ★返回 false 的三种情形都**不是错误**, 分别是: 斧头没了 / 无头测试没有立绘节点 /
##   动作没登记。门禁靠返回值当分母, 所以不能吞掉这个区别。
func play_action(ax: Dictionary, key: String, loop: bool = false) -> bool:
	if not (ax is Dictionary) or not ax.get("alive", false):
		return false
	if not is_instance_valid(ax.get("sprite", null)):
		return false                 # 无头测试里没有立绘节点, 不是错误
	var e = battle.ACTION_ELITE.get(key, null)
	if e == null:
		return false
	var asd: Dictionary = battle._resolve_action(str(e[0]), float(e[1]))
	if asd.is_empty():
		return false
	battle._set_anim_sheet(ax, asd, key, loop)
	## ★记一个同步标记, 门禁拿它当【真的播了哪一招】的账 ——
	##   不是数"我插的触发标记"(memory [[fb-gate-must-measure-requirement-not-my-hook]]),
	##   而是这个函数**成功换帧表**之后才写, 与屏幕上真正在放的那一招是同一件事。
	ax["_axe_last_action"] = key
	ax["_axe_action_n"] = int(ax.get("_axe_action_n", 0)) + 1
	return true


## 每帧: 龟能满了就放主动。
## ★放在装备层的 tick 里, 不进主场景(架构预算只减不增; 而且它不在 _sim_step 的必经链上)。
func tick(u: Dictionary, _delta: float) -> void:
	var ax = u.get("_axe_ref", null)
	if not (ax is Dictionary) or not ax.get("alive", false):
		return
	## ★★龟能充能 —— 2026-09-01 补。之前这条**根本不存在**: 探针实测真跑 13.78 秒
	##   energy 一直是 0, 于是「攒满 140 龟能」的主动、被动6的蓄力猛砸、
	##   四个最终造物的主动**在真实对局里一个都放不出来**(而门禁全绿, 因为门禁自己喂 140)。
	##   ★充能速率沿用全局换算(1 点 = 0.075 秒)并乘 `echarge_perm` ——
	##     全息斧的「50% 龟能充能速率」这才真的有了消费者。
	ax["energy"] = minf(float(ax.get("maxEnergy", AE.ACTIVE_ENERGY)),
		float(ax.get("energy", 0.0)) + AE.energy_gain(_delta, float(ax.get("echarge_perm", 1.0))))
	_pas.tick_smash(ax, _delta)
	_fin.ember_light_tick(ax)          # 余烬之光: 清过期的(多层只延长在线时间, 不叠强度)
	_fin.tick_active(ax, _delta)       # 造物主动: 甩回旋镖 / 法阵脉冲 / 到期还原减伤
	_fin.undead_tick_revive(ax)        # 亡灵: 到点站起来(不播死亡动画, 用户两次点名)
	_tick_undead_ring(ax, _delta)
	## ★蓄力中不再放主动 —— 否则 140 龟能一满就把蓄力重开, 永远砸不下去。
	## ★★`tick_charge` 的返回值有三态, 演出**必须按三态分**(2026-09-03 接线):
	##     -1 = 根本没在蓄力      0 = 蓄力进行中(播 axe_charge, 循环)
	##     ≥0 且这一帧结束了蓄力 = 砸下了(播 axe_slam, 一次性)
	##   ⚠ 只判 `>= 0` 分不出"还在蓄"和"砸完了" —— 它俩都 ≥0。
	##     区别在于调用前后 `is_charging` 变没变: 砸下的那一帧 `slam_settle` 会
	##     `_end_charge` 把 `_axe_charge_t0` 擦掉。拿这个**产品自己的状态跃迁**当判据,
	##     而不是我另插一个标记(memory [[fb-gate-must-measure-requirement-not-my-hook]])。
	var was_charging: bool = _pas.is_charging(ax)
	var cr: int = _pas.tick_charge(ax, _delta)
	if cr >= 0:
		if was_charging and not _pas.is_charging(ax):
			play_action(ax, "axe_slam")          # 蓄力结束的那一帧 = 砸下
			## ★这里必须清 —— 否则标记留在 true, **第二次蓄力就不会再播 charge 动画**
			##   (下面那行 `ax["_axe_charge_anim"] = false` 只在 cr<0 时才走得到,
			##    而砸下这一帧 cr>=0 直接 return 了)。只砸一次的台子发现不了。
			ax["_axe_charge_anim"] = false
		elif not ax.get("_axe_charge_anim", false):
			## 循环帧表只需换一次 —— 每帧重设会把它永远钉在第 0 帧(动画看着像卡住)
			if play_action(ax, "axe_charge", true):
				ax["_axe_charge_anim"] = true
		return
	ax["_axe_charge_anim"] = false
	## ★★造物主动【替换】被动6的猛砸(2026-09-01 补 —— 零调用者扫描抓到之前一个都没接):
	##   炽天使→10 把回旋镖 / 全息→插地开法阵 / 余烬→余烬之光 / 亡灵与无造物→仍走猛砸。
	##   ⚠ 造物主动正在进行中时**不许重开** —— 否则龟能一满就打断自己, 10 把永远甩不完。
	if _fin.active_busy(ax):
		return
	if cast_heal(ax):
		if _fin.begin_active(ax) == "":
			_pas.begin_charge(ax)        # 没有造物(或亡灵): 走被动 6 的梯形蓄力猛砸


## 被动 2(木斧解锁): 斧头**普攻**命中带护盾的目标 → 偷走 10% 护盾, **转成普通护盾**给自己。
## 返回偷到的量(门禁拿它当分母)。
## ★「比如有特殊护盾也转普通护盾给自己」——
##   本作只有一个护盾池 `u["shield"]`; 圣光盾是拿 `_holyShieldVal` 在这个池子上打的**标记**,
##   不是第二个池。所以"特殊护盾"要一起偷走, 做法是: 从池子里扣 10%, 并**按比例把标记也削掉**,
##   否则标记会大于池子本身(那会让血条的白黄段画出比护盾还长的一截)。
func steal_shield(ax: Dictionary, tgt: Dictionary) -> float:
	if not (ax is Dictionary) or not (tgt is Dictionary):
		return 0.0
	if not ax.get("_eq_axe", false) or not ax.get("alive", false) or not tgt.get("alive", false):
		return 0.0
	var sh: float = float(tgt.get("shield", 0.0))
	if sh <= 0.0:
		return 0.0
	var take: float = sh * AE.SHIELD_STEAL_PCT
	tgt["shield"] = sh - take
	var holy: float = float(tgt.get("_holyShieldVal", 0.0))
	if holy > 0.0:
		tgt["_holyShieldVal"] = minf(holy, float(tgt["shield"]))   # 标记不许超过池子
	battle._damage._grant_shield(ax, take)
	return take


## 斧头的 on-hit(只有普攻算)。
func on_hit(src: Dictionary, tgt: Dictionary, basic: bool) -> void:
	if not (src is Dictionary) or not src.get("_eq_axe", false):
		return
	if tgt is Dictionary:
		## 助攻窗的起点(四期)。★记在**被打的那个**身上, 而不是在斧头身上记一份名单 ——
		##   名单要拿单位字典当元素比对, 而单位字典之间互相引用成环(CLAUDE.md §3.2)。
		tgt["_axe_touch_t"] = float(battle._t)
	if not basic:
		return
	steal_shield(src, tgt)
	## ── 五期被动(只对【普攻】生效, 与被动 2 同一条闸) ──
	## ★顺序有意: 先记这是第几下, 再按奇偶分派横扫/竖劈, 最后才是强化 on-hit 与效率层。
	##   强化 on-hit 会击飞目标, 放在选靶之前会让横扫的名单跟着位移变(判据就飘了)。
	var sw: int = _pas.bump_swing(src)
	_pas.cleave_settle(src, tgt, sw)                       # 被动4: 偶数次 → 竖劈
	for o in _pas.sweep_targets(src, tgt, sw):             # 被动5: 奇数次 → 180° 横扫
		if not is_same(o, tgt) and o.get("alive", false):
			battle._damage._apply_damage_from(src, o, maxi(1, int(round(float(src.get("atk", 0.0))))),
				Color("#cfd8dc"), 0.0, false, true)
	var smashed: float = _pas.smash_on_hit(src, tgt)       # 被动3: 每 9 秒一次强化
	_pas.add_eff(src)                                      # 被动5: 效率层 +1
	## ── 演出: 这一下普攻播哪张招式帧 ──────────────────────────────
	## ★★接在结算【之后】而不是里面: 那三个 settle 是纯函数, 门禁直接调它们喂坐标验数
	##   (文件头「结算与演出分开」)。把 play_action 塞进去, 门禁一跑就会去碰立绘节点。
	## ★优先级 = 稀有度倒序: 强化猛砸 9 秒才一次, 它和竖劈/横扫撞在同一拳时先播它;
	##   一次普攻只播一张帧表 —— 连着 _set_anim_sheet 两次, 后一张会把前一张顶掉,
	##   表现成"强化猛砸永远看不见"(而伤害照常结算, 极难发现)。
	## ★"是哪一招"问 `_pas.swing_kind()`, 不在这里重写 swing % 2(见那个函数的头注)。
	## ★★场景特效与招式帧【成对】出现: 帧表是斧头本体在做动作, 场景特效是那一招打出去的东西。
	##   只有帧没特效 = 斧头挥空气; 只有特效没帧 = 斧头站着不动东西自己飞出去。两样都要。
	var _sdir: Vector2 = (tgt.get("pos", Vector2.ZERO) as Vector2) - (src.get("pos", Vector2.ZERO) as Vector2)
	if smashed > 0.0:
		play_action(src, "axe_smash")
		_pas.vfx.smash(tgt)                       # 目标脚下的贴地冲击环 + 裂纹
	else:
		var kind: String = _pas.swing_kind(src, sw)
		if kind == "cleave":
			play_action(src, "axe_cleave")
			_pas.vfx.cleave(src, tgt)             # 竖直下劈的刀光, 落在目标身上
		elif kind == "sweep":
			play_action(src, "axe_sweep")
			_pas.vfx.sweep(src, _sdir)            # 贴地 180° 金弧, 直径 = atk_range×2 = 判定范围
	## ── 六期: 最终造物的 on-hit ──
	_fin.seraph_on_hit(src, tgt)                           # 炽天使: 8 层灼烧
	_fin.holo_on_hit(src)                                  # 全息斧: 最低血友军 +盾+龟能
	_fin.ember_on_hit(src, tgt)                            # 余烬: 种子层 + 处决


## ── 四期: 击杀 / 助攻 +2 砍伐经验 ────────────────────────────
## ★为什么不挂 `_eq_on_kill`: 那条钩子遍历**击杀者的 equips**, 而斧头是召唤物、
##   身上一件装备都没有, 永远轮不到它。而且它还要求击杀者 `alive` ——
##   斧头与目标同归于尽时就整条跳过了。
## ★为什么不靠 `on_hit` 认击杀: on-hit 那一整块被 `u["alive"]` 挡着,
##   **致命的那一下根本走不到** ⇒ 只用触碰时间戳会漏掉"斧头自己打死的"这一半。
##   所以分两路: 击杀看 killer 是不是斧头, 助攻看死者身上的触碰时间戳。
## 返回是否发生了进化(调用方将来放演出用)。
func on_death(victim: Dictionary, killer) -> bool:
	if not (victim is Dictionary):
		return false
	var gs = battle.get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("axe_add_exp"):
		return false
	var hit := false
	if killer is Dictionary and (killer as Dictionary).get("_eq_axe", false):
		hit = true                                   # 斧头亲手打死
	elif float(battle._t) - float(victim.get("_axe_touch_t", -9999.0)) <= AE.ASSIST_WINDOW:
		hit = true                                   # 3 秒内被斧头碰过 = 参与击杀
	if not hit:
		return false
	return bool(gs.axe_add_exp(AE.EXP_ON_KILL))
