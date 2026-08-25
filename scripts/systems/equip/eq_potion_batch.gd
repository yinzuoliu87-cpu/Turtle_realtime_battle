class_name EqPotionBatch
extends RefCounted
## eq_potion_batch.gd — 药水四件(065 鲨肝油 / 066 鲸涎浓浆 / 067 毒药瓶 / 068 深海气压罐)
## 的效果本体。规格 = docs/plans/20260805-装备逐件重做.md §0.5(用户逐件亲手写、已定稿),
## 接口 = docs/plans/20260805-实装契约.md。
##
## ★本文件只放【效果】。演出全部在 scripts/scenes/battle/potion_eq_vfx.gd(自建·零素材·物理模型)。
##
## ══════════════════════════════════════════════════════════════════════
##  ★本批踩到的四颗地雷 (CLAUDE.md 逐条对照)
## ══════════════════════════════════════════════════════════════════════
## ① §3.4 `_t` 跨路累加、永不重置 —— 066 的「登场第 11 秒」与 068 的「第 12 秒」
##    **都自存 t0**(`brew_t0` / `can_t0`, 由 EquipStatsApply 在【每一路的开战管线】里预置)。
##    直接判 `battle._t >= 11` 会让**下路一开场就触发**(那时 _t 早过 11)。
## ② §3.3 两条伤害路径 —— 068 的充能挂在 `_eq_on_target`, 而那个钩子**只在
##    `_apply_damage_from`(普攻/技能)那条路上**。⚠ **诚实记录**: DoT/真伤(`_apply_damage`)
##    不进充能条。这与方案书 U5「DoT 不算受到伤害来攒原液(频率会失控)」同口径,
##    但它是【实现限制】不是设计选择 —— 要改必须动 battle_damage.gd(本路无权)。
## ③ §3.2 不拿单位字典当 Dictionary 的键 —— 067 的减益标记写在**目标自己的字段**上
##    (`_vial_sa`), 比较一律 `is_same`。
## ④ §3.1 装备 hp 已是最终值 —— 066 的「最大生命 100/200/400」直接加, **不乘 HP_MULT**。
##
## ══════════════════════════════════════════════════════════════════════
##  ★为什么 067 的「护盾强度减半」要每帧撤了再重算
## ══════════════════════════════════════════════════════════════════════
## `shield_amp` 是**加法**通道(`_grant_shield` 里 `amt *= 1 + shield_amp`)。
## 用户规格是**×0.5**(方案书写死「本文取 ×0.5」), 而 `shield_amp -= 0.5` 只在基数为 0 时
## 才等于减半 —— 目标身上本来有 +30% 护盾增幅的话, 直接减 0.5 会得到 ×0.8 而不是 ×0.65。
## ⇒ 每帧【先撤掉上一次自己加的增量, 再按当前基数重算】:
##       d = −0.5·(1 + base)   ⇒   1 + base + d = 0.5·(1 + base)   ∀base
## 这样别的系统中途改 `shield_amp` 也不会算错, 且撤销是幂等的。

const Vfx := preload("res://scripts/scenes/battle/potion_eq_vfx.gd")
## ★068 的可转向射线单独成文件: 它是自成一体的子系统(实测包络表 + 3D 几何 +
##   转向 + 枪口 + 命中爆点), 塞进 potion_eq_vfx 会把那份文件顶成第二个上帝文件。
const BeamVfx := preload("res://scripts/scenes/battle/mana_beam_vfx.gd")

## 067 减益的悬挂时长(秒): 每帧刷新, 中毒一结束就在这个窗口内自然失效。
const VIAL_DEBUFF_HOLD := 0.30
## 068 激光的出伤节拍(秒)。★不逐帧出伤: `_dot_after_resist` 有 `maxi(1, …)` 下限,
##   逐帧结算会让"每帧至少 1 点"在高帧率下把总量顶上天。按固定节拍分段, 总量才守得住。
const BEAM_TICK := 0.25

var battle
var _vfx
var _beam_vfx

## 演出推进的帧去重(同 EquipSystem 里 `_sig_tick_fr` 的做法):
## `tick_unit` 是**每单位**调的, 不去重会一帧推进 N 次(N = 携带者数)。
var _adv_fr: int = -1


func _init(b) -> void:
	battle = b
	_vfx = Vfx.new(b)
	_beam_vfx = BeamVfx.new(b)


func vfx():
	return _vfx


# ══════════════════════════════════════════════════════════════════
#  §每帧 —— 由 EquipSystem._eq_tick 的前置守卫调(常驻字段 `_potion_tick`)
# ══════════════════════════════════════════════════════════════════

## ★守卫是【常驻字段】而不是遍历 equips ⇒ 不带这四件的单位在 `_eq_tick` 里只多一次 dict.get。
func tick_unit(u: Dictionary, delta: float) -> void:
	var fr: int = Engine.get_process_frames()
	if fr != _adv_fr:
		_adv_fr = fr
		_vfx.advance(delta)
		_vial_expire_sweep()
	if not u.get("alive", false):
		return
	for e in u.get("equips", []):
		if not (e is Dictionary):
			continue
		var iid: String = str((e as Dictionary).get("id", ""))
		var si: int = clampi(int((e as Dictionary).get("star", 1)), 1, 3) - 1
		match iid:
			"p2eq_066": _tick_whale_brew(u, si)
			"p2eq_067": _tick_vial_field(u, si)
			"p2eq_068": _tick_pressure_can(u, si, delta)


# ══════════════════════════════════════════════════════════════════
#  §065 鲨肝油 (药水 · 3 费)
#    每次普攻后 +5 龟能; 每次普攻再 +1/2/4% 攻速, **不设上限**, 换路重置。
# ══════════════════════════════════════════════════════════════════

## 每次普攻。★攻速走 `aspd_perm`(累加通道, 不会被 `_recalc_stats` 重算冲掉);
##   换路时单位字典整体重建 ⇒ `aspd_perm` 回到 1.0 ⇒ **换路重置是天然的**, 不用自己清。
## ★用户拍板「滚雪球类叠层不设上限」(2026-08-05 原话「没上限」) —— 这里**没有 cap**, 别加。
func _eq_shark_oil(u: Dictionary, si: int) -> void:
	if not u.get("alive", false):
		return
	var stt: Dictionary = u["eq_state"].get("p2eq_065", {})
	battle._equip_sys._eq_grant_energy(u, LIVER_ENERGY)
	u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) + [0.01, 0.02, 0.04][si]
	stt["oil_stacks"] = int(stt.get("oil_stacks", 0)) + 1
	u["eq_state"]["p2eq_065"] = stt
	# ★读数只走装备格右下角层数徽章(PANEL_COUNT 的 oil_stacks) —— 用户 2026-08-11:
	#   「这个不要特效, 但图标那里要显示层数」。油膜光晕/飘字整条撤除。


# ══════════════════════════════════════════════════════════════════
#  §066 鲸涎浓浆 (药水 · 4 费)
#    登场第 11 秒喝药: 免疫控制到战斗结束 + 十一项属性 + 体型 +40%。每路一次。
# ══════════════════════════════════════════════════════════════════

## 喝下去要多久(秒) —— 用户规格「登场的第 11 秒」。**按本路起算**, 不是全局 `_t`。
const BREW_AT := 11.0
## 体型终值(倍)。用户规格「额外体型 +40%」, 三星同值。
const BREW_SIZE := 1.40
## 推导: 文案说的是"体型额外 +40%", 代码要的是最终倍率 1.40 —— 只存一份。
const BREW_SIZE_UP := BREW_SIZE - 1.0
## 【065 鲨肝油】每次普攻后额外获得的龟能。
const LIVER_ENERGY := 5.0


## 每帧: 没喝就看时候到没到; 喝过了就维持免疫 + 推进过冲回稳的体型曲线。
func _tick_whale_brew(u: Dictionary, si: int) -> void:
	var stt: Dictionary = u["eq_state"].get("p2eq_066", {})
	if not stt.has("brew_t0"):
		stt["brew_t0"] = battle._t          # 兜底: 合成单位/老存档没走 _eq_apply_flags
	if not bool(stt.get("brew_done", false)):
		if battle._t - float(stt["brew_t0"]) >= BREW_AT:
			_eq_whale_brew(u, si, stt)
		u["eq_state"]["p2eq_066"] = stt
		return
	var el: float = battle._t - float(stt.get("brew_at_t", battle._t))
	u["size_mult"] = float(stt.get("brew_size0", 1.0)) * Vfx.ovr_size_at(el, BREW_SIZE)
	_vfx.brew_glow_tick(u, el)   # 金红体光: 帧同步 + 强度/色相推进(常驻=免控标识)
	_brew_immune(u)
	u["eq_state"]["p2eq_066"] = stt


## 喝药: 一次性把整套属性灌下去。★走 `EquipStatsApply.apply_stat_dict` 这一个既有入口 ——
##   十一个字段各写一遍 = 十一次抄写, 而那个函数才是「属性 dict → 单位字段」的单一事实源
##   (它同时管 crit 是小数、_lifestealPct 是整数百分比、hp 不乘 HP_MULT 这些口径)。
func _eq_whale_brew(u: Dictionary, si: int, stt: Dictionary) -> void:
	if not u.get("alive", false):
		return
	stt["brew_done"] = true
	stt["brew_at_t"] = battle._t
	stt["brew_size0"] = float(u.get("size_mult", 1.0))
	var gain: Dictionary = {
		"_lifestealPct": [8.0, 13.0, 20.0][si],
		"hp": [100.0, 200.0, 400.0][si],
		"def": [12.0, 17.0, 25.0][si],
		"mr": [12.0, 17.0, 25.0][si],
		"_aspdPct": [10.0, 17.0, 25.0][si],
		"crit": [0.10, 0.17, 0.25][si],
		"critDmg": [0.07, 0.13, 0.18][si],
		"_echargePct": [5.0, 7.0, 10.0][si],
		"atk": [13.0, 18.0, 25.0][si],
		"armorPen": [4.0, 7.0, 10.0][si],
		"magicPen": [4.0, 7.0, 10.0][si],
	}
	battle._equip_sys._stats.apply_stat_dict(u, gain, "p2eq_066")
	u["_brew_immune"] = true
	u["eq_state"]["p2eq_066"] = stt
	_brew_immune(u)
	_vfx.brew_glow_start(u)   # 金红体光(金圈已废, 用户 2026-08-11)
	battle._vfx._float_text(u["pos"] + Vector2(0, -84), "浓浆!", Color(1.0, 0.88, 0.55))


## ★★「免疫控制效果」= 用户点名的**五条通道**(2026-08-05「免疫减速, 减攻速, 嘲讽, 击飞」+ 眩晕/冻结)。
##   减速有**两条并行通道**(`slow_*` 与 `spd_*`), 只挡一条 = 半个免疫 —— 契约 §4 焊死。
##
## ★实现取【每帧清除】而不是【在每个施加点判免疫】: 施加点散在几十处(眩晕虽已收口,
##   减速/嘲讽都没有), 逐个去改就是"手抄的副本必然落后"那个形状。
##   每帧清一次的代价 = 携带者一人一帧几次 dict.get, 而覆盖面是**全部现有与将来的施加点**。
##
## ⚠ `spd_move_mult` / `spd_aspd_mult` 这条通道**buff 与 debuff 共用**(熔岩 1.3、凤凰 1.5 是增益),
##   所以只在【<1.0】时才复位, 不能整条抹掉 —— 抹掉会连自己的加速一起没收。
func _brew_immune(u: Dictionary) -> void:
	u["cc_immune_until"] = maxf(float(u.get("cc_immune_until", 0.0)), battle._t + 1.0)
	u["_knock_immune"] = true
	if float(u.get("stun_until", 0.0)) > battle._t:
		u["stun_until"] = 0.0
	if float(u.get("slow_until", 0.0)) > battle._t:
		u["slow_until"] = 0.0
	if float(u.get("spd_move_mult", 1.0)) < 1.0:
		u["spd_move_mult"] = 1.0
	if float(u.get("spd_aspd_mult", 1.0)) < 1.0:
		u["spd_aspd_mult"] = 1.0
	if int(u.get("stiff_stacks", 0)) > 0:
		u["stiff_stacks"] = 0
		battle._recalc_stats(u)
	if float(u.get("taunt_until", 0.0)) > battle._t:
		u["taunt_until"] = 0.0
		u["taunt_by"] = null


# ══════════════════════════════════════════════════════════════════
#  §067 毒药瓶 (药水 · 4 费)
#    ① 每 6 秒朝最密集处投瓶 → 400 码内施加 40/70/110 层中毒
#    ② 携带者存活时, 中毒的敌人受到的治疗与获得的护盾减半
#    ③ 普攻额外施加 3/5/8 层中毒
# ══════════════════════════════════════════════════════════════════

## 药瓶的效果半径(码) —— 用户规格 400 码。演出的毒云也定标到这个数(见 potion_eq_vfx CLOUD_D)。
const VIAL_RADIUS := 400.0


## 「敌人最密集的地方」。★判据 = 以**每个敌人**为圆心取 400 码, 数圈内敌人数, 取最多的那个位置。
## ★**确定性、不掷骰**(用户拍板口径): 平手时用严格 `>` ⇒ 取先出现的那个,
##   而枚举顺序来自 `battle._units`(确定性数组)。门禁可以逐点复算。
## ★圆心候选走 `_pick_enemies_of`(排除训龟大师: 它是场外监视者, 永远在最远处, 拿它当圆心
##   会让药瓶永远扔到没人的地方 —— 珊瑚刺 008 踩过一模一样的坑);
##   但**计数**用 `_enemies_of` —— 落点是真 AOE, 扫到谁算谁。
func _eq_vial_dest(u: Dictionary) -> Dictionary:
	var centers: Array = battle._targeting._pick_enemies_of(u)
	if centers.is_empty():
		return {"ok": false, "pos": Vector2.ZERO, "n": 0}
	var hits: Array = battle._targeting._enemies_of(u)
	var best: Vector2 = centers[0]["pos"]
	var bn: int = -1
	for a in centers:
		var n: int = 0
		for b in hits:
			if (b["pos"] - a["pos"]).length() <= VIAL_RADIUS:
				n += 1
		if n > bn:
			bn = n
			best = a["pos"]
	return {"ok": true, "pos": best, "n": bn}


## 每 6 秒一次(周期表 EquipSystem.EQ_IV_BATCH1)。演出是抛物线, **落地才结算**。
## ★落地结算走 `battle._pending_shots`(sim 循环按 delta 推进), **不是 tween** ——
##   无头 CI 下场景树 tween 推进不稳(CLAUDE.md §3.5, verify_pirate_hook 为此连红三次)。
##   门禁则直接调 `_eq_vial_land`, 一行判完, 不等任何演出。
func _eq_poison_vial(u: Dictionary, si: int) -> void:
	if not u.get("alive", false):
		return
	var d: Dictionary = _eq_vial_dest(u)
	if not bool(d["ok"]):
		return
	var dest: Vector2 = d["pos"]
	_vfx.vial_throw(u["pos"], dest)
	battle._pending_shots.append({"delay": Vfx.VIAL_FLIGHT, "src": u,
		"fn": func() -> void: _eq_vial_land(u, si, dest)})


## 药瓶落地: 400 码内每个敌人 +40/70/110 层【中毒】。
## ★中毒是**既有机制**(每秒伤害 = 层数, 结算后衰减到 80%), 走 `_apply_dot_stacks` 不另造。
func _eq_vial_land(u: Dictionary, si: int, pos: Vector2) -> void:
	if not u.get("alive", false):
		return
	var stt: Dictionary = u["eq_state"].get("p2eq_067", {})
	stt["vial_thrown"] = int(stt.get("vial_thrown", 0)) + 1
	u["eq_state"]["p2eq_067"] = stt
	_vfx.vial_cloud(pos)
	battle._splash_ring_bold(pos, Color(0.42, 0.90, 0.38), VIAL_RADIUS)
	for o in battle._targeting._enemies_of(u):
		if (o["pos"] - pos).length() > VIAL_RADIUS:
			continue
		battle._damage._apply_dot_stacks(o, "poison", [40, 70, 110][si], u)


## 普攻额外施加 3/5/8 层中毒。
func _eq_poison_touch(u: Dictionary, tgt: Dictionary, si: int) -> void:
	if not u.get("alive", false) or not tgt.get("alive", false):
		return
	var _s67: Dictionary = u["eq_state"].get("p2eq_067", {})
	battle._damage._apply_dot_stacks(tgt, "poison", [3, 5, 8][si], u)


## 每帧: 携带者存活 ⇒ 所有【中毒的敌人】治疗减半 + 获得的护盾减半。
## ★用户拍板②: 作用于**全场任何中毒者**, 不限于被这件毒的 —— 按字面, 且能与别的中毒源配合。
func _tick_vial_field(u: Dictionary, si: int) -> void:
	var _unused: int = si
	for o in battle._targeting._enemies_of(u):
		if int((o.get("dot_stacks", {}) as Dictionary).get("poison", 0)) <= 0:
			continue
		_vial_debuff_on(o)


## 挂上减益(幂等·可反复调)。
## ★治疗走**既有的** `heal_reduce_pct`/`heal_reduce_until` 通道(凤凰涅槃/烫伤在用),
##   它在 `_heal` 里是 `amt *= 1 − pct` ⇒ 0.5 就是精确的减半, 且**到期自动失效**。
##   多源取 max, 不把别人更强的削减改弱。
## ★护盾走 `shield_amp`, 但必须"撤了再算"才是 ×0.5 —— 理由见文件头。
func _vial_debuff_on(o: Dictionary) -> void:
	o["heal_reduce_pct"] = maxf(float(o.get("heal_reduce_pct", 0.0)), 0.5)
	o["heal_reduce_until"] = maxf(float(o.get("heal_reduce_until", 0.0)), battle._t + VIAL_DEBUFF_HOLD)
	var prev: float = float(o.get("_vial_sa", 0.0))
	var base: float = float(o.get("shield_amp", 0.0)) - prev
	var d: float = -0.5 * (1.0 + base)
	o["shield_amp"] = base + d
	o["_vial_sa"] = d
	o["_vial_sa_until"] = battle._t + VIAL_DEBUFF_HOLD


## 撤掉减益(幂等)。
func _vial_debuff_off(o: Dictionary) -> void:
	var prev: float = float(o.get("_vial_sa", 0.0))
	if prev == 0.0:
		return
	o["shield_amp"] = float(o.get("shield_amp", 0.0)) - prev
	o["_vial_sa"] = 0.0
	o["_vial_sa_until"] = 0.0


## 每帧一次的到期扫描: 中毒结束/携带者死掉 ⇒ 悬挂窗口过完就把护盾减益撤掉。
## ★这条是【必须有的】—— `shield_amp` 不像 `heal_reduce_until` 自带到期,
##   写进去没人撤就是永久减半(memory [[fb-write-without-reader-and-fake-gates]] 的反面: 撤销也要有人做)。
func _vial_expire_sweep() -> void:
	for o in battle._units:
		if not (o is Dictionary):
			continue
		if float((o as Dictionary).get("_vial_sa", 0.0)) == 0.0:
			continue
		if battle._t < float((o as Dictionary).get("_vial_sa_until", 0.0)):
			continue
		_vial_debuff_off(o)


## 携带者阵亡 → 立刻撤掉自己挂出去的减益(不等悬挂窗口)。
func _eq_vial_cleanse(u: Dictionary) -> void:
	var _s: Dictionary = u.get("eq_state", {}).get("p2eq_067", {})
	for o in battle._units:
		if o is Dictionary:
			_vial_debuff_off(o)


# ══════════════════════════════════════════════════════════════════
#  §068 深海气压罐 (药水 · 5 费)
#    受到伤害 → 充能条(上限 = 最大生命的 20/40/100%)
#    本路第 12 秒起每 12 秒: 清空充能 → 法力护盾 + 2000 码法力激光
#    法力护盾存在期间锁充能条; 普攻 +5 龟能 + 回血 20/35/50
# ══════════════════════════════════════════════════════════════════

## 释放周期(秒) —— 用户规格「登场后的第 12 秒和后续的每 12 秒」。**按本路起算**。
## 【068 深海气压罐】受伤存充能 → 每周期清空换法力护盾 + 一道法力激光。
const CAN_SHIELD_DECAY := 8.0    # 法力护盾几秒内衰减完(其间充能条锁住)
## ★激光的射程与时长【不在这里】: 真源是 PotionEqVfx.BEAM_RANGE / BEAM_SEC
##   (伤害 tick 自己读的就是 Vfx.BEAM_SEC)。这里不存副本 —— 存了就会各走各的。
const CAN_HIT_ENERGY := 5.0      # 普攻额外龟能
const CAN_PERIOD := 12.0
## 法力护盾的 SpecialBalance key(契约 §2)
const CAN_MANA_KEY := "p2eq_068_mana"


## 充能上限 = 最大生命 × 20/40/100%
func _can_cap(u: Dictionary, si: int) -> float:
	return float(u.get("maxHp", 0.0)) * [0.20, 0.40, 1.00][si]


## 【受到伤害】→ 存进充能条。挂 `_eq_on_target`。
## ★「在法力护盾存在时锁充能条」—— 直接问 SpecialBalance 有没有那条余额。
## ⚠ 诚实记录: 这个钩子只在 `_apply_damage_from`(普攻/技能)那条路上,
##   DoT/真伤(`_apply_damage`)不进充能(见文件头 ②)。
## ★2026-08-06 主会话补: 让【DoT / 真伤】那条伤害路径也能给 068 充能。
##   由来: 实装那路如实报了「068 的充能只吃 _apply_damage_from(普攻/技能), DoT/真伤不进充能条」——
##   因为 `_eq_on_target` 这个钩子只挂在一条伤害路径上(battle_damage.gd:291)。
##   而用户对 068 写的是「将**收到的** 60/100/200% 伤害储存进充能条」, 没有任何"仅限普攻"的限定。
##   ⇒ 这是 CLAUDE.md §3.3 那一类的实现遗漏, 不是设计选择。
##
## ★为什么不直接给 `_eq_on_target` 补另一条路(那样更"对称"):
##   那个钩子上还挂着既有的【硬化层 / 冰封反制】。让它们从**每一跳灼烧/中毒**都触发,
##   是明显的行为变更, 而且大概率不是原意。所以走**窄口**: 只把 068 的充能接过去。
func store_from_any_damage(u: Dictionary, dmg: int) -> void:
	if dmg <= 0 or not u.get("alive", false) or not u.get("_potion_tick", false):
		return
	for e in u.get("equips", []):
		if str(e.get("id", "")) == "p2eq_068":
			_eq_pressure_store(u, dmg, battle._equip_sys._eq_si(int(e.get("star", 1))))
			return


func _eq_pressure_store(u: Dictionary, dmg: int, si: int) -> void:
	if not u.get("alive", false) or dmg <= 0:
		return
	if battle._spec.has(u, CAN_MANA_KEY):
		return
	var stt: Dictionary = u["eq_state"].get("p2eq_068", {})
	var cap: float = _can_cap(u, si)
	stt["can_charge"] = minf(cap, float(stt.get("can_charge", 0.0)) + float(dmg) * [0.60, 1.00, 2.00][si])
	# ★归一化镜像, 给局内装备格的充能条读(PANEL_CHARGE 的分母只能是常量,
	#   而这里的上限是 maxHp×20/40/100% —— 同 081 藤编圆盾存 chg_pct 的做法)。
	#   2026-08-11 补: 在此之前 068 攒了一整条充能【局内零出口】, 玩家看不到自己攒到哪,
	#   而它的效果恰恰就是"攒得越多打得越狠"。
	stt["can_pct"] = clampf(float(stt["can_charge"]) / maxf(1.0, cap) * 100.0, 0.0, 100.0)
	u["eq_state"]["p2eq_068"] = stt


## 每次普攻: +5 龟能 + 回复 20/35/50 生命。
func _eq_pressure_sip(u: Dictionary, si: int) -> void:
	if not u.get("alive", false):
		return
	var _s68: Dictionary = u["eq_state"].get("p2eq_068", {})
	battle._equip_sys._eq_grant_energy(u, CAN_HIT_ENERGY)
	battle._damage._heal(u, [20.0, 35.0, 50.0][si])


## 到点释放: 清空充能 → 法力护盾(充能值的 100/120/300%, 8 秒衰减) + 法力激光。
##
## ★★**两级放大是有意的**(方案书 §0.5 焊死, 用户明确接受, 不许在实施时"顺手调平"):
##   转化 200% × 护盾 300% ⇒ 挨打 X 点得到 6X 护盾;
##   转化 200% × 激光 600% ⇒ 挨打 X 点打出 12X 伤害。3★ 是换数量级, 不是变强一点。
## ★法力护盾走 `battle._spec`(SpecialBalance, 契约 §2): 独立余额 + 8 秒线性衰减 +
##   耗尽/被打光都会回调。**不自己实现衰减与吸收**。
func _eq_pressure_release(u: Dictionary, si: int, stt: Dictionary) -> void:
	stt["can_fired"] = int(stt.get("can_fired", 0)) + 1
	var stored: float = float(stt.get("can_charge", 0.0))
	stt["can_charge"] = 0.0
	stt["can_pct"] = 0.0          # ★清空充能时读数也要归零, 否则条会停在满格骗人
	u["eq_state"]["p2eq_068"] = stt
	if stored <= 0.0:
		return
	# ★读数走血条第四段(hp_bar 的法力蓝段, 见 _tick_pressure_can 的 _manaShieldVal 镜像), 不飘字 ——
	#   飘字飘完就没了, 玩家不知道自己还剩多少盾/几秒(用户 2026-08-11:「应该是给一个特殊颜色
	#   护盾条, 这是特殊护盾」)。血条早有圣盾白黄/壳青绿/海胆紫三段先例, 这是第四段。
	battle._spec.grant(u, CAN_MANA_KEY, stored * [1.00, 1.20, 3.00][si], {"decay_sec": CAN_SHIELD_DECAY, "order": 10})
	# 法力激光: 朝【最远敌人】, 2000 码贯穿, 3 秒里共打出储存值的 100/120/600%
	var far = _can_farthest(u)
	if far == null:
		return
	var dir: Vector2 = (far["pos"] - u["pos"])
	if dir.length() < 0.01:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	stt["beam_total"] = stored * [1.00, 1.20, 6.00][si]
	stt["beam_paid"] = 0.0
	stt["beam_t"] = 0.0
	stt["beam_acc"] = 0.0
	stt["beam_org"] = u["pos"]
	stt["beam_dir"] = dir
	# ★可转向(2026-08-11 用户:「本来就应该是可以转向的射线」):
	#   `beam_ang` 是**射线的真实朝向**, `beam_tgt` 是它想指向的目标。
	#   伤害判定一律用 `beam_ang` 而不是目标位置 —— 否则"扫过谁烧谁"就是假的。
	stt["beam_ang"] = dir.angle()
	# ★★扫掠起点必须钉在【开火时的朝向】。
	#   漏了这一行, 第一个 tick 的 `beam_ang_paid` 会默认成"转完之后的当前角"
	#   ⇒ 首段扫掠被压成零宽 ⇒ 开火后立刻扫过的敌人【一个都判不到】。
	#   这是 verify_mana_beam_steer ② 抓出来的真 bug, 不是假想。
	stt["beam_ang_paid"] = dir.angle()
	stt["beam_tgt"] = far
	u["eq_state"]["p2eq_068"] = stt
	stt["beam_h"] = _beam_vfx.fire(u["pos"], dir.angle(), Vfx.BEAM_RANGE, Vfx.BEAM_HALF_W)


## 最远的【可定向选取】敌人(排除训龟大师与不可选中者)。
func _can_farthest(u: Dictionary):
	var es: Array = battle._targeting._pick_enemies_of(u)
	var best = null
	var bd: float = -1.0
	for o in es:
		var d2: float = (o["pos"] - u["pos"]).length_squared()
		if d2 > bd:
			bd = d2
			best = o
	return best


## 每帧: 充能条 + 激光推进 + 到点释放。
func _tick_pressure_can(u: Dictionary, si: int, delta: float) -> void:
	var stt: Dictionary = u["eq_state"].get("p2eq_068", {})
	if not stt.has("can_t0"):
		stt["can_t0"] = battle._t          # 兜底: 合成单位/老存档没走 _eq_apply_flags
	var cap: float = _can_cap(u, si)
	# ★读数走装备图标框的 PANEL_CHARGE(见 `can_pct` 镜像), 不在这里自造头顶条 ——
	#   旧的那条实拍是【横穿龟身】的一道白线, 而且挂在 `_world` 下没人清 ⇒ 跨路残留。
	# ★法力护盾余额每帧镜像进单位字段, 给血条第四段读(HpBar 只认 f 的字段, 拿不到 battle._spec)。
	#   吸收/衰减/耗尽全走 SpecialBalance, 这里只抄读数 ⇒ 镜像永远收敛, 不会自己漂。
	u["_manaShieldVal"] = battle._spec.val(u, CAN_MANA_KEY)
	u["eq_state"]["p2eq_068"] = stt
	# 束结束后的末端爆发/塌收没有别的驱动源(束活着时由 set_hits 驱动) —— 内部有帧去重
	_beam_vfx.advance(delta)
	_eq_beam_step(u, delta)
	var due: float = float(stt["can_t0"]) + CAN_PERIOD * float(int(stt.get("can_fired", 0)) + 1)
	if battle._t >= due:
		_eq_pressure_release(u, si, stt)


## 法力激光的持续推进: 转向 + 扫掠伤害 + 演出。**纯同步**, 门禁直接喂 delta, 不等任何演出。
##
## ★★伤害与亮度走**同一条**实测包络(mana_beam_vfx §A): `env` 是瞬时强度,
##   `env_frac` 是它的归一化积分 ⇒ 画面最亮那一瞬也正是打得最狠那一瞬。
##   不是"画面按 A 曲线、伤害按 B 曲线"那种两张皮。
## ★按 BEAM_TICK 分段结算而不是逐帧: `_dot_after_resist` 有 `maxi(1, …)` 下限,
##   逐帧会让"每帧至少 1 点"在高帧率下把总量顶上天。
## ★走 `_apply_damage`(DoT/真伤那条路)而不是 `_apply_damage_from`:
##   ① 不再掷一次暴击(持续伤害每跳掷暴击会让总量随机化, 门禁量不准);
##   ② 那条路**结构上就不回钩 on-hit**, 比靠 from_equip 开关更硬(防自激)。
func _eq_beam_step(u: Dictionary, delta: float) -> void:
	var stt: Dictionary = u["eq_state"].get("p2eq_068", {})
	var total: float = float(stt.get("beam_total", 0.0))
	if total <= 0.0:
		return
	var t0: float = float(stt.get("beam_t", 0.0))
	var t1: float = minf(t0 + maxf(delta, 0.0), Vfx.BEAM_SEC)
	stt["beam_t"] = t1

	# ── 转向 ────────────────────────────────────────────────────
	#   目标死了/失效了就改指最远的活敌; 方向按角速率上限逼近, **不瞬移**。
	var a0: float = float(stt.get("beam_ang", 0.0))
	var tgt = stt.get("beam_tgt", null)
	if not (tgt is Dictionary) or not bool(tgt.get("alive", false)):
		tgt = _can_farthest(u)
		stt["beam_tgt"] = tgt
	if tgt is Dictionary:
		var want_ang: float = ((tgt["pos"] as Vector2) - (stt.get("beam_org", u["pos"]) as Vector2)).angle()
		var step: float = deg_to_rad(BeamVfx.TURN_DPS) * maxf(delta, 0.0)
		var dd: float = angle_difference(a0, want_ang)
		a0 = a0 + clampf(dd, -step, step)
	stt["beam_ang"] = a0
	stt["beam_dir"] = Vector2(cos(a0), sin(a0))

	# ── 演出: 只转节点 + 更新包络 + 告知现在照到了谁 ────────────────
	var h = stt.get("beam_h", null)
	if h is Dictionary and not (h as Dictionary).is_empty():
		_beam_vfx.aim(h, a0)
		_beam_vfx.set_progress(h, t1 / maxf(Vfx.BEAM_SEC, 0.001))
		_beam_vfx.set_hits(h, _beam_lit(u, stt), delta)

	# ── 伤害: 按【本 tick 扫掠过的角度区间】结算 ──────────────────
	var want: float = total * BeamVfx.env_frac(t1 / maxf(Vfx.BEAM_SEC, 0.001))
	var due: float = want - float(stt.get("beam_paid", 0.0))
	var ended: bool = t1 >= Vfx.BEAM_SEC
	stt["beam_acc"] = float(stt.get("beam_acc", 0.0)) + maxf(delta, 0.0)
	if float(stt["beam_acc"]) >= BEAM_TICK or ended:
		stt["beam_acc"] = 0.0
		if due >= 1.0:
			stt["beam_paid"] = float(stt.get("beam_paid", 0.0)) + due
			_beam_hit(u, stt, due, float(stt.get("beam_ang_paid", a0)), a0)
		stt["beam_ang_paid"] = a0
	if ended:
		stt["beam_total"] = 0.0
		if h is Dictionary and not (h as Dictionary).is_empty():
			# ★自然结束走 finale 不走 stop: 实测参考的最后 0.1s 爆点有【末端爆发】
			#   (刺长×2.2 + 实心白核 + 白刺带), 然后 4 帧塌收 —— 由 advance 自清。
			#   换路/清场仍走 stop/clear_all(立即全清), 两条路都有门禁。
			_beam_vfx.finale(h)
		stt["beam_h"] = null
		stt["beam_tgt"] = null
	u["eq_state"]["p2eq_068"] = stt


## 此刻**正被射线照到**的敌人(瞬时判定, 只给演出用 —— 伤害走扫掠, 见 `_beam_hit`)。
func _beam_lit(u: Dictionary, stt: Dictionary) -> Array:
	var org: Vector2 = stt.get("beam_org", u["pos"])
	var ang: float = float(stt.get("beam_ang", 0.0))
	var out: Array = []
	for o in battle._targeting._enemies_of(u):
		var rel: Vector2 = o["pos"] - org
		var d: float = rel.length()
		if d > Vfx.BEAM_RANGE:
			continue
		if absf(angle_difference(ang, rel.angle())) <= _half_angle(d):
			out.append(o)
	return out


## 敌人在距离 d 处占的【角半宽】。
## ★用 asin 而不是 atan: 这样它与旧版"垂距 ≤ BEAM_HALF_W"的判定【严格等价】——
##   点在距离 d、角偏 θ 处的垂距 = d·sin(θ), 所以 垂距≤W ⇔ |θ| ≤ asin(W/d)。
##   等价性是回归保护的基础: 不转向时新旧行为必须逐字一致。
func _half_angle(d: float) -> float:
	return asin(clampf(Vfx.BEAM_HALF_W / maxf(d, 0.001), 0.0, 1.0))


## 本 tick 内, 敌人被射线照到的【时长比例】。
##
## ★★为什么必须这样算, 而不是"tick 结束时在不在线上":
##   BEAM_TICK=0.25s, 转向 110°/s ⇒ **一个 tick 转 27.5°**。在 500 码处是 240 码弧长,
##   而射线全宽才 116 码 ⇒ 敌人会整个从两个 tick 的缝里漏过去, 且**不报任何错**。
##   (与「逐帧机制门禁必须逐帧喂」「合成单位被钳到同一点」同族: 粗粒度采样看不见缝隙。)
##
## 闭式解不是采样: 把"敌人占的角区间"与"本 tick 扫掠的角区间"求交, 交集长度 ÷ 扫掠角。
## ★不转向时(|Δ|≈0)退化成 f=1 ⇒ **与改动前逐字一致**, 这是回归保护。
func _sweep_frac(a0: float, a1: float, beta: float, alpha: float) -> float:
	var d: float = angle_difference(a0, a1)
	var b: float = angle_difference(a0, beta)
	if absf(d) < 1e-5:
		return 1.0 if absf(b) <= alpha else 0.0
	var lo: float = minf(0.0, d)
	var hi: float = maxf(0.0, d)
	var ov: float = minf(hi, b + alpha) - maxf(lo, b - alpha)
	if ov <= 0.0:
		return 0.0
	return clampf(ov / absf(d), 0.0, 1.0)


## 这一跳打给【本 tick 被射线扫过】的每个敌人, 各自按被照时长比例结算。
##
## ★用户 2026-08-11:「射线碰到谁就开始造成伤害, 射线离开就停止造成伤害」。
## ★数值契约不变: `_beam_hit` 本来就是"带内每个敌人各吃全额"(不是平分),
##   所以「3 秒共造成充能值的 100/120/600%」说的一直是**对单个持续被照的目标**。
##   改成扫射后这条原样成立; 变的只是被扫过的敌人按被照时长拿一部分。
func _beam_hit(u: Dictionary, stt: Dictionary, amount: float, a0: float, a1: float) -> void:
	var org: Vector2 = stt.get("beam_org", u["pos"])
	for o in battle._targeting._enemies_of(u):
		var rel: Vector2 = o["pos"] - org
		var d: float = rel.length()
		if d > Vfx.BEAM_RANGE:
			continue
		var f: float = _sweep_frac(a0, a1, rel.angle(), _half_angle(d))
		if f <= 0.0:
			continue
		var part: float = amount * f
		if part < 1.0:
			continue
		o["_mana_beam_n"] = int(o.get("_mana_beam_n", 0)) + 1   # 同步触发证据(门禁数它, 不等演出)
		battle._damage._apply_damage(o, battle._damage._dot_after_resist(o, part, true, u),
			Color(0.62, 0.82, 1.0), u, "mag", false, true)


## 换路/战斗结束的撤场。
##
## ★★2026-08-11 发现: `_potion_sys` **既没有 `clear_all` 也没有 `clear`** ——
##   而 `dual_lane_flow` 的换路清理用的是 `has_method` 保护 ⇒ **药水这一路一直被静默跳过**。
##   四件(065~068)的演出节点都挂在 `battle._world` 下, 换路时 `_world` 不重建 ⇒ 全留到下一路。
##   这是"写了没人读"的同族: 保护性的 `has_method` 让"没写 clear"变成了静默不清。
func clear_all() -> void:
	if _beam_vfx != null:
		_beam_vfx.clear_all()
	if _vfx != null and _vfx.has_method("clear_all"):
		_vfx.clear_all()


