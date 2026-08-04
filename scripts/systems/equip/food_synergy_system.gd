class_name FoodSynergySystem
extends RefCounted
## 食物羁绊【永久成长 / 学院】（2026-08-03）
##
## 食物这个类型分三块，**主人各不相同**（这是本项目的分工规矩，不是随手放的）：
##   · **每件装备 +N 最大生命**（食物双倍）→ `synergy_system.gd` 的 per-piece 属性通道
##     （十个类型共用同一条通道；食物只是它的口径特殊：数的是"携带者身上全部装备"）
##   · **盛宴**（每 2.5 秒全队回复已损失生命 3%）→ 同上，它挂在 `_pulse` 上
##   · **永久成长 / 学院** → **本文件**
##
## ── 两条的作用域 ─────────────────────────────────────────────────────
## | 永久成长 | **携带者**（每件食物为【它的携带者】+N 最大生命，可无限累积）|
## | 学院     | **全队**（队伍全体额外 +N 最大生命，不要求身上带食物）      |
##
##
## ★★【累积到什么时候】—— 探针结论，别照注释里"本场累积"的字面理解：
##   换路时 `_dl_next_lane` 先 `_dl_clear_units()`（清空 `battle._units` + free 节点），
##   再 `_dl_build_lane_field()` → `_spawn_lane_side()` → `_make_unit()` **新建字典**。
##   ⇒ **任何写在【单位字典】上的累积，换路时连字典一起没了 = 每一路各自从零累积。**
##   只有写在【系统对象】上的（如奇械 `_coins`）才真的跨路。
##   （`dual_lane_flow.gd:447` 那条注释也是这么说的：血量"天然每场重置"。）
##
## ★"永久 +最大生命"是**加 maxHp 也加当前 hp** —— 否则每跳一次血条百分比就掉一点，
##   打到后面满血的龟看起来像残血。项目里 per-piece 的 hp 通道也是这么写的
##   （`synergy_system._add` 的 `"hp"` 分支），照同一套来。

var battle

const PERIOD := 2.5
## 每 2.5 秒，每件食物为携带者永久 +N 最大生命（逐档）
const GROW_PER_FOOD := [8.0, 16.0, 30.0]
## 【学院】队伍全体额外 +N 最大生命（档1 无）
const ACADEMY := [0.0, 100.0, 220.0]

var _t_grow := 0.0
## ★【以场重置, 不是以路重置】(用户 2026-08-04 明确)。
##   换路 `_dl_clear_units()` 会把 `battle._units` 连字典一起清掉、`_make_unit()` 重建,
##   所以成长量【不能只写在单位字典上】—— 那样每一路都会打回原形。
##   存一份在本系统对象里, 换路后由 `restore()` 重放。
##   身份键照抄 `dual_lane_flow._eq_carry_key` 的口径(side|id|序号): 不拿单位字典做键
##   —— Godot 会递归哈希互引成环的单位字典 → 卡死(CLAUDE.md §3.2)。
var _carry := {}


func _init(b) -> void:
	battle = b


## 开战 / 换路后：把【学院】的固定血一次性加上。
## ⚠ 只能加【一次】—— `apply_all` 每场调一次，重复调会叠。用标记挡住。
func apply_all() -> void:
	for u in battle._units:
		if not (u is Dictionary):
			continue
		var ti: int = int(battle._synergy.tier_for(u, "食物"))
		if ti <= 0:
			continue
		var add: float = ACADEMY[clampi(ti - 1, 0, 2)]
		if add <= 0.0 or u.get("_academy_done", false):
			continue
		u["_academy_done"] = true
		u["maxHp"] = float(u.get("maxHp", 0.0)) + add
		u["hp"] = float(u.get("hp", 0.0)) + add


## 每 2.5 秒：每件食物为【它的携带者】永久 +N 最大生命。
## ★"可无限累积"是字面意思 —— 不设上限。食物是全表唯一的**滚雪球型**羁绊，
##   代价是它一点输出都不给（属性只有血）。
func tick(delta: float) -> void:
	_t_grow += delta
	if _t_grow < PERIOD:
		return
	_t_grow -= PERIOD
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false):
			continue
		var ti: int = int(battle._synergy.tier_for(u, "食物"))
		if ti <= 0:
			continue
		var mine := 0
		for e in u.get("equips", []):
			if e is Dictionary and battle.Phase2Types.type_of(str((e as Dictionary).get("id", ""))) == "食物":
				mine += 1
		if mine <= 0:
			continue          # ★是【每件食物为携带者】—— 不带食物的队友不长血(那是学院的活)
		var add: float = GROW_PER_FOOD[clampi(ti - 1, 0, 2)] * float(mine)
		_grow(u, add)


func clear() -> void:
	_t_grow = 0.0


## 给某只单位长 add 点最大生命，并把累计量同步进跨路存档。
func _grow(u: Dictionary, add: float) -> void:
	if add <= 0.0:
		return
	u["maxHp"] = float(u.get("maxHp", 0.0)) + add
	u["hp"] = float(u.get("hp", 0.0)) + add
	u["_food_grown"] = float(u.get("_food_grown", 0.0)) + add
	var k: String = str(u.get("_food_key", ""))
	if k != "":
		_carry[k] = float(u["_food_grown"])


## 单位的跨路身份键。★口径与 `dual_lane_flow._eq_carry_key` 一致（side|id|同名序号）。
func _key_of(u: Dictionary, seen: Dictionary) -> String:
	var base: String = "%s|%s" % [str(u.get("side", "left")), str(u.get("id", ""))]
	var n: int = int(seen.get(base, 0))
	seen[base] = n + 1
	return "%s|%d" % [base, n]


## 换路重建单位【之后】调：给每只单位贴上身份键，并把上一路攒的成长量重放回去。
## ★必须在装备管线跑完之后 —— 否则 maxHp 会被后来的属性重算冲掉。
func restore() -> void:
	var seen: Dictionary = {}
	for u in battle._units:
		if not (u is Dictionary) or u.get("_isEgg", false) or u.get("is_trainer", false):
			continue
		var k: String = _key_of(u, seen)
		u["_food_key"] = k
		var had: float = float(_carry.get(k, 0.0))
		if had <= 0.0:
			continue
		# ★直接补 had 这么多，而不是"重跑一遍成长"——
		#   重跑要知道上一路跳了几次、当时几件食物，那是一份会漂的副本。
		u["maxHp"] = float(u.get("maxHp", 0.0)) + had
		u["hp"] = float(u.get("hp", 0.0)) + had
		u["_food_grown"] = had


## 整场结束（不是换路）：成长归零，下一场重新开始。
func reset_match() -> void:
	_carry.clear()
