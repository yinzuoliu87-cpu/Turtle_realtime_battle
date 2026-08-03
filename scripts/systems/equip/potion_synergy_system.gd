class_name PotionSynergySystem
extends RefCounted
## 药水羁绊【猎物 / 猎获 / 斩首】（2026-08-03）
##
## 来源：学派「猎人集会」（`docs/archive/学派效果-实装规格.md`），
## 类型原生只有 `_maxEnergy`（每件 +5/11/20 最大龟能）。
##
## ── 三条的作用域 ─────────────────────────────────────────────────────
## | 猎物 | **全队**（标记是给整支队伍打的，所有人对猎物都增伤） |
## | 猎获 | **全队**（击杀猎物 → 全队永久涨攻，本场累积）        |
## | 斩首 | **全队**（顶档；攻击猎物时残血直接处决）             |
##
## ★为什么猎物选「当前生命值最高」而不是最低：
##   选最低就是"补刀增伤"，等于把已经要死的敌人杀得更快，收益接近 0。
##   选最高才有意义 —— 它把队伍火力集中到最肉的那只身上，这正是"狩猎"的形状。
##   （原规格就是这么写的，我照抄，没改。）
##
## ★猎物是【确定性选取】：血最高的那只，同血按 `_units` 顺序取第一个。
##   同炮台/收殓的规矩 —— 随机会让门禁与确定性回放都不稳。

var battle

## 猎物增伤（逐档）
const PREY_AMP := [0.15, 0.25, 0.40]
## 猎获：每击杀 1 名猎物，全队攻击力永久 +N（档1 无）
const HARVEST_ATK := [0.0, 22.0, 38.0]
## 斩首（仅顶档）：攻击猎物时，其生命低于这个比例 → 直接处决
const BEHEAD_TIER := 3
const BEHEAD_HP_PCT := 0.20
const PERIOD := 2.5

var _t_mark := 0.0
## 各方当前的猎物（是敌方的单位）。★存单位字典本身，比较一律用 `is_same`（CLAUDE.md §3.2）
var _prey := {"left": null, "right": null}


func _init(b) -> void:
	battle = b


func _side_tier(side: String) -> int:
	var t := 0
	for u in battle._units:
		if u is Dictionary and str(u.get("side", "")) == side:
			t = maxi(t, int(battle._synergy.tier_for(u, "药水")))
	return t


## 某只单位【是不是】某一方的猎物。
## ⚠ 用 `is_same` 不用 `==` —— 单位字典互相引用成环，`==` 会递归哈希卡死（CLAUDE.md §3.2）。
func is_prey_of(side: String, u) -> bool:
	var p = _prey.get(side, null)
	return p != null and u is Dictionary and is_same(p, u)


## 攻击方对目标的增伤倍率（挂 `_apply_damage_from`）。
func amp_for(src, tgt) -> float:
	if not (src is Dictionary) or not (tgt is Dictionary):
		return 1.0
	var side: String = str(src.get("side", ""))
	if not is_prey_of(side, tgt):
		return 1.0
	var ti: int = _side_tier(side)
	if ti <= 0:
		return 1.0
	return 1.0 + PREY_AMP[clampi(ti - 1, 0, 2)]


## 【斩首】攻击猎物时若其生命 < 20% → 直接处决（顶档）。挂在 on-hit，与弓箭处决同一个位置。
## ★返回值没人用 —— 处决本身就是终态；但保留 bool 让门禁能一眼看出"这次到底斩没斩"。
func try_behead(src, tgt) -> bool:
	if not (src is Dictionary) or not (tgt is Dictionary) or not tgt.get("alive", false):
		return false
	var side: String = str(src.get("side", ""))
	if _side_tier(side) < BEHEAD_TIER:
		return false
	if not is_prey_of(side, tgt):
		return false
	if tgt.get("eq_exec_immune", false):
		return false          # 免疫处决(龟蛋/大师等) —— 与弓箭处决同一道闸
	var mx: float = float(tgt.get("maxHp", 0.0))
	if mx <= 0.0 or float(tgt.get("hp", 0.0)) >= mx * BEHEAD_HP_PCT:
		return false
	battle._vfx._float_text(tgt["pos"], "-999999",
		battle._VC.color_of(battle._VC.cls_for("damage", "true", true)), true, "damage", "true")
	tgt["hp"] = 0.0
	battle._kill(tgt, src)
	return true


## 【猎获】猎物阵亡 → 全队攻击力永久 +N（本场累积）。挂 `_kill`。
## ★判定用的是"死的那只【是不是】某一方的猎物"，不是"杀它的人带没带药水" ——
##   猎物是给整支队伍打的标记，谁补刀都算队伍的猎获。
func on_death(dead) -> void:
	if not (dead is Dictionary):
		return
	for side in ["left", "right"]:
		if not is_prey_of(str(side), dead):
			continue
		_prey[side] = null                       # 猎物死了 → 下个周期重选
		var ti: int = _side_tier(str(side))
		if ti < 2:
			continue
		var add: float = HARVEST_ATK[clampi(ti - 1, 0, 2)]
		if add <= 0.0:
			continue
		for u in battle._units:
			if not (u is Dictionary) or str(u.get("side", "")) != str(side):
				continue
			# ★写 base_atk 而不是挂 buff: 规格是"永久"(本场累积), buff 有时限会掉。
			u["base_atk"] = float(u.get("base_atk", 0.0)) + add
			u["_harvest_atk"] = float(u.get("_harvest_atk", 0.0)) + add   # 记账, 给门禁与面板看
			battle._recalc_stats(u)


## 每 2.5 秒重选猎物：敌方当前【生命值最高】的那一名。
func tick(delta: float) -> void:
	_t_mark += delta
	if _t_mark < PERIOD:
		return
	_t_mark -= PERIOD
	for side in ["left", "right"]:
		var s: String = str(side)
		if _side_tier(s) <= 0:
			_prey[s] = null
			continue
		# 猎物还活着就不换 —— 规格是"猎物死亡后下个周期重选"
		# ⚠ 除了"还活着", 还得确认它【仍在场上】——
		#   探针实测: 单位被换掉(换路重建/测试重置)之后, 旧字典的 alive 仍是 true,
		#   于是这里永远 continue, 猎物**再也不会重选**。
		#   用 `_arr_has_unit` 不用 `in`: Array.has() 对单位字典是深比较, 互引成环会卡死(§3.2)。
		var cur = _prey.get(s, null)
		var still_here: bool = cur is Dictionary and battle._arr_has_unit(battle._units, cur)
		if still_here and (cur as Dictionary).get("alive", false):
			continue
		var best = null
		var bv := -1.0
		for u in battle._units:
			if not (u is Dictionary) or not u.get("alive", false):
				continue
			if str(u.get("side", "")) == s:
				continue
			if u.get("_isEgg", false):
				continue          # 龟蛋不当猎物: 它是胜负判定的容器, 标它等于把增伤全砸在结算物上
			var hp: float = float(u.get("hp", 0.0))
			if hp > bv:
				bv = hp
				best = u
		_prey[s] = best
		if best is Dictionary:
			battle._vfx._float_text(best["pos"], "猎物", Color("#ff9f43"), false, "buff", "mark")


func clear() -> void:
	_t_mark = 0.0
	_prey = {"left": null, "right": null}
