class_name BombSynergySystem
extends RefCounted
## 炸弹羁绊【导弹轰炸】（2026-11-24 · 方案书 docs/plans/20261124f-炸弹羁绊.md §4.1）
##
## 用户 11-24：「在战斗开始时…会存在一个导弹定位器，定位到整个战场的中心…一条…红线指向这个战场中心…在开打的第十秒钟，
##   会有一发…导弹…飞向这个中心。来对全场的所有敌方英雄造成…一段物理伤害，并且击飞一秒」「那肯定三六十嘛」
##   「三档的话，只递增伤害就可以了」「羁绊哪里有攻击力呢？所以肯定是固定伤害…加上目标最大生命值百分比的物理伤害」
##   「目标最大生命值伤害改为一档是百分之八，二档百分之十五，三档百分之四十」
##
## 类型原生属性是 `armorPen`（每件 +5 / 12 / 20，逐档，见 `Phase2Types.TYPES["炸弹"]`）。
##
## ── 规则 ─────────────────────────────────────────────────────────────
## · 每一路（上路 / 下路 / 决胜）各自计时：`battle._sd_t0` 是这一路开打那一刻（`_t` 跨路累加，CLAUDE.md §4.4）。
## · 开打时出现定位器（红线指向战场中心，纯表现）；开打第 FIRE_AT 秒，有炸弹羁绊的一方落一发导弹。
## · 导弹打**对方全体存活单位**（龟与小将）；龟蛋除外；训龟大师走 `_untouch_block`（§UNTOUCHABLE）。
## · 伤害 = DMG_FLAT[档] + DMG_MAXHP[档] × 目标最大生命（真实 maxHp，不除 HP_MULT，CLAUDE.md §4.1），**物理**，
##   过护甲（出手方 = 这一方第一个活着的炸弹携带者，吃它的护甲穿透）；**不暴击**（羁绊效果，不是普攻）。
## · 击飞 AIR_SEC 秒：走唯一入口 `_knockback`（免控 / 阵亡 / 已在空中都由它挡），水平推力 0 = 原地抛起。
## · 两方都有炸弹 ⇒ 各落各的，同一刻结算，按 left → right 的固定顺序（确定性）。
var battle
## 开打第几秒落导弹
const FIRE_AT := 10.0
## 每档固定伤害
const DMG_FLAT := [100.0, 200.0, 400.0]
## 每档目标最大生命值比例
const DMG_MAXHP := [0.08, 0.15, 0.40]
## 击飞时长（秒）
const AIR_SEC := 1.0
const COL_PHYS := Color("#ff8a3d")
## 本路已经落过的方
var _fired := {"left": false, "right": false}
## 记下「这一路」的开打时刻，变了 = 换路 ⇒ 重新计时
var _lane_t0 := -1.0
## 门禁量：本进程落过几发
var strikes := 0


func _init(b) -> void:
	battle = b


func side_tier(side: String) -> int:
	var t := 0
	for u in battle._units:
		if u is Dictionary and str(u.get("side", "")) == side:
			t = maxi(t, int(battle._synergy.tier_for(u, "炸弹")))
	return t


## 击飞 AIR_SEC 秒需要的上抛倍率：腾空时间 = 2 × KNOCK_VY × 倍率 / |GRAVITY|
static func air_vy_mult(knock_vy: float, gravity: float, sec: float) -> float:
	return sec * absf(gravity) / (2.0 * knock_vy)


func tick(_dt: float) -> void:
	var t0 := float(battle._sd_t0)
	if t0 != _lane_t0:
		_lane_t0 = t0
		_fired = {"left": false, "right": false}
		for side in ["left", "right"]:
			if side_tier(side) > 0 and battle.get("_bomb_vfx") != null:
				battle._bomb_vfx.show_locator(side, FIRE_AT)
	if float(battle._t) - t0 < FIRE_AT:
		return
	for side in ["left", "right"]:
		if bool(_fired[side]):
			continue
		_fired[side] = true
		var tier := side_tier(side)
		if tier > 0:
			strike(side, tier)


## 落一发（纯结算；演出只是跟着放）。返回挨炸的单位个数。
func strike(side: String, tier: int) -> int:
	var src = null
	for u in battle._units:
		if u is Dictionary and u.get("alive", false) and str(u.get("side", "")) == side \
				and int(battle._synergy.tier_for(u, "炸弹")) > 0:
			src = u
			break
	if src == null:
		for u in battle._units:
			if u is Dictionary and u.get("alive", false) and str(u.get("side", "")) == side:
				src = u
				break
	if src == null:
		return 0
	strikes += 1
	var k := clampi(tier, 1, DMG_FLAT.size()) - 1
	var vy_mult := air_vy_mult(float(battle.KNOCK_VY), float(battle.GRAVITY), AIR_SEC)
	var hit := 0
	var targets: Array = []
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false):
			continue
		if str(u.get("side", "")) == side or bool(u.get("_isEgg", false)) or battle._is_untouchable(u):
			continue
		targets.append(u)
	if battle.get("_bomb_vfx") != null:
		battle._bomb_vfx.missile_impact(side)
	for u in targets:
		if not u.get("alive", false):
			continue
		var base: float = float(DMG_FLAT[k]) + float(DMG_MAXHP[k]) * float(u.get("maxHp", 0.0))
		var dmg: int = battle._resolve_dmg(src, base, u, false, false)
		battle._damage._apply_damage_from(src, u, dmg, COL_PHYS, 0.0, false, true)
		battle._damage._knockback(src, u, 0.0, vy_mult, 0.0)
		hit += 1
	return hit


## 一场结束（不是换路）：羁绊本身没有跨路状态；顺带清 104 定时炸弹的跨路叠层（装备效果，挂在同一个时机，主文件不多加一行）。
func reset_match() -> void:
	_fired = {"left": false, "right": false}
	_lane_t0 = -1.0
	if battle.get("_equip_sys") != null and battle._equip_sys.get("_bomb_sys") != null:
		battle._equip_sys._bomb_sys.reset_match()
