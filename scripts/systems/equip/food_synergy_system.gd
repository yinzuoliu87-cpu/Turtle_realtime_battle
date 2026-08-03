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
		u["maxHp"] = float(u.get("maxHp", 0.0)) + add
		u["hp"] = float(u.get("hp", 0.0)) + add
		u["_food_grown"] = float(u.get("_food_grown", 0.0)) + add   # 记账, 给门禁与面板看


func clear() -> void:
	_t_grow = 0.0
