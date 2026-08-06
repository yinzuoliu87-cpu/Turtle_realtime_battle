class_name PotionSynergySystem
extends RefCounted
## 药水羁绊【猎物 / 战利品 / 斩首】（2026-08-03）
##
## 来源：学派「猎人集会」（`docs/archive/学派效果-实装规格.md`），
## 类型原生只有 `_maxEnergy`（每件 +5/11/20 最大龟能）。
##
## ── 三条的作用域 ─────────────────────────────────────────────────────
## | 猎物 | **全队**（标记是给整支队伍打的，所有人对猎物都增伤） |
## | 战利品 | **全队**（击杀猎物 → 全队永久涨攻，本场累积）        |
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
## 战利品：每击杀 1 名猎物，全队攻击力永久 +N（档1 无）。
## ★用户 2026-08-04 定稿：22/38 → **5/8**。
##   原来那个量是"一场杀 3~4 只猎物就 +66~152 攻"，相当于凭空多出一件顶级装备；
##   现在是慢积累型 —— 打得越久越强，但单次击杀不再改变战局。
const HARVEST_ATK := [0.0, 5.0, 8.0]
## 斩首（仅顶档）：攻击猎物时，其生命低于这个比例 → 直接处决
const BEHEAD_TIER := 3
const BEHEAD_HP_PCT := 0.20
const PERIOD := 2.5

var _t_mark := 0.0
## 各方当前的猎物（是敌方的单位）。★存单位字典本身，比较一律用 `is_same`（CLAUDE.md §3.2）
var _prey := {"left": null, "right": null}
## 本场累计的战利品攻击力（各方一份）。
## ★【存在系统对象上，不是单位字典上】—— 用户 2026-08-04 定"以场重置"。
##   换路 `_dl_clear_units()` 会把 `battle._units` 连字典一起清掉、`_make_unit()` 重建，
##   只写单位字典的话每一路都会打回原形。
## ★战利品是**全队同量**的（"全队攻击力永久 +N"），所以按【方】记一个总数就够，
##   不用像食物那样按单位身份键存 —— 食物的成长是每只各不相同（看它带几件食物）。
var _harvest := {"left": 0.0, "right": 0.0}


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


## 【战利品】猎物阵亡 → 全队攻击力永久 +N。挂 `_kill`。
## ⚠ "永久"的实际范围是**本路** —— 写的是单位字典的 `base_atk`，而换路会重建单位字典
##   （`_dl_clear_units()` 清空 `battle._units` → `_make_unit()` 新建），所以下一路从零重新攒。
##   同食物成长 / 遗物远古之力。只有写在【系统对象】上的（奇械 `_coins`）才真的跨路。
## ★判定用的是"死的那只【是不是】某一方的猎物"，不是"杀它的人带没带药水" ——
##   猎物是给整支队伍打的标记，谁补刀都算队伍的战利品。
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
		var lit: Array = []      # 分到这份战利品的人 —— 只喂演出, 不参与任何结算
		for u in battle._units:
			if not (u is Dictionary) or str(u.get("side", "")) != str(side):
				continue
			# ★写 base_atk 而不是挂 buff: 规格是"永久"(本场累积), buff 有时限会掉。
			u["base_atk"] = float(u.get("base_atk", 0.0)) + add
			u["_harvest_atk"] = float(u.get("_harvest_atk", 0.0)) + add   # 记账, 给门禁与面板看
			battle._recalc_stats(u)
			if u.get("alive", false):
				lit.append(Vector2(u.get("pos", Vector2.ZERO)))
		_harvest[side] = float(_harvest.get(side, 0.0)) + add   # 跨路存档
		# ★演出(批 B3): 现状全队 base_atk 悄悄 +5/8, 零表现。
		#   击杀是【离散事件】⇒ 可以放。缺的信息是"这份收益从哪来" ⇒ 从尸体向全队辐射。
		if not lit.is_empty() and battle._vfx != null and battle._vfx._syn != null:
			battle._vfx._syn.potion_harvest(Vector2(dead.get("pos", Vector2.ZERO)), lit)


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
			# ★颜色跟着药水的母题色走(#e64bd0 品红) —— 原来是 #ff9f43 橙,
			#   而枪羁绊的弹幕辐射也是橙、形状还同为"辐射带"(门禁 verify_synergy_vfx_types ⑤ 抓出来的)。
			#   飘字与环同色, 玩家才能把"猎物"这两个字和那个圈连起来。
			battle._vfx._float_text(best["pos"], "猎物", Color("#e64bd0"), false, "buff", "mark")
			# ★演出(批 B3): 现状只有这一次飘字, 之后【完全看不出谁是猎物】(全队对它增伤 15~40%)。
			#   ⚠ 常驻标记做不到 —— 它该是头顶状态徽章, 而 HEAD_ROW_CAP=4 已满、
			#     超出会【静默截断】(方案书 U5, 用户未拍板)。⇒ 只把"被选中那一下"做重(准星双环)。
			if battle._vfx._syn != null:
				battle._vfx._syn.potion_prey_mark(Vector2(best["pos"]))


## 换路重建单位【之后】调：把本场已累计的战利品攻击力重放到新的一批单位上。
## ★必须在装备/羁绊管线跑完之后 —— 否则会被后来的属性重算冲掉。
func restore() -> void:
	for u in battle._units:
		if not (u is Dictionary) or u.get("_isEgg", false) or u.get("is_trainer", false):
			continue
		if u.get("_harvest_restored", false):
			continue                              # 同一路里 apply 多次不叠
		var had: float = float(_harvest.get(str(u.get("side", "")), 0.0))
		if had <= 0.0:
			continue
		u["_harvest_restored"] = true
		u["base_atk"] = float(u.get("base_atk", 0.0)) + had
		u["_harvest_atk"] = had
		battle._recalc_stats(u)


func clear() -> void:
	_t_mark = 0.0
	_prey = {"left": null, "right": null}


## 整场结束（不是换路）：战利品归零，下一场重新开始。
func reset_match() -> void:
	_harvest = {"left": 0.0, "right": 0.0}
