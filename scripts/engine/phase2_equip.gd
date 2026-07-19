extends RefCounted

## Phase2Equip — 二阶段装备: 三合一升星 + 套装 (壳, 数值占位)
##
## 用 preload 引 (不用 class_name — 防 F5 未声明崩):
##   const Phase2Equip = preload("res://scripts/engine/phase2_equip.gd")
##
## 现状(壳): 升星/合成/套装的【结构与规则】已搭, 数值是占位, 待用户定:
##   - 1星基础属性 ×1.8 升星 = 占位公式 (设计文档没给精确值)
##   - 套装加成数值 = 占位 (设计只定了触发条件: 系列≥3 / 子流派≥2, 没给加成数值)
##   - 装备效果(effectDesc1/3) 还没接战斗 apply (data 里 effectImpl=false)
## 数据来源: res://data/phase2-equipment.json (59件, xlsx「处理B」结构化).

const P2 := preload("res://scripts/engine/phase2_config.gd")

const STAR_MULT := 1.8          # 占位: 每升一星, 基础属性 ×1.8
const MERGE_COUNT := 3          # 三合一: 3 件同款同星 → 1 件高一星
const MAX_STAR := 3

# 基础属性 token 后缀 → fighter 字段 (长后缀优先匹配, 见 parse_base_stats)
const _STAT_SUFFIX := [
	["护甲魔抗", ["def", "mr"]],
	["双穿", ["armorPen", "magicPen"]],
	["魔穿", ["magicPen"]],
	["暴击", ["crit"]],
	["反伤", ["reflectPct"]],
	["盾疗", ["shieldHealPct"]],
	["护甲", ["def"]],
	["魔抗", ["mr"]],
	["生命", ["hp"]],
	["攻", ["atk"]],
	["穿", ["armorPen"]],
	["暴", ["crit"]],
]


## 解析 "+10攻/+10%暴击" → {"atk": 10.0, "crit": 10.0}. (暴击单位是%, 这里只取数值.)
static func parse_base_stats(s: String) -> Dictionary:
	var out: Dictionary = {}
	for raw in s.split("/", false):
		var tok: String = raw.strip_edges().trim_prefix("+")
		if tok.is_empty():
			continue
		# 取前导数字
		var num_str := ""
		var i := 0
		while i < tok.length() and (tok[i].is_valid_int() or tok[i] == "."):
			num_str += tok[i]
			i += 1
		if num_str.is_empty():
			continue
		var val := float(num_str)
		var rest := tok.substr(i).replace("%", "")
		for pair in _STAT_SUFFIX:
			if rest.ends_with(pair[0]):
				for field in pair[1]:
					out[field] = float(out.get(field, 0.0)) + val
				break
	return out


## 升星属性 (占位 ×1.8^(star-1)). star: 1/2/3.
static func star_stats(base: Dictionary, star: int) -> Dictionary:
	var mult: float = pow(STAR_MULT, maxi(0, star - 1))
	var out: Dictionary = {}
	for k in base:
		out[k] = float(base[k]) * mult
	return out


## item def + 当前星级 → 解析并升星后的属性.
static func item_stats(item: Dictionary, star: int) -> Dictionary:
	return star_stats(parse_base_stats(str(item.get("baseStats1", ""))), star)


## 三合一可否: 恰好 MERGE_COUNT 件、同 id、同星、且未到满星.
static func can_merge(item_ids: Array, star: int) -> bool:
	if item_ids.size() != MERGE_COUNT or star >= MAX_STAR:
		return false
	for x in item_ids:
		if x != item_ids[0]:
			return false
	return true


## 合成结果 = 同 id 高一星.
static func merge_result(item_id: String, star: int) -> Dictionary:
	return {"id": item_id, "star": mini(MAX_STAR, star + 1)}


## 升到 star 星 需要的同款【1星】总数: 1星=1, 2星=3, 3星=9.
static func items_for_star(star: int) -> int:
	return int(round(pow(MERGE_COUNT, maxi(0, star - 1))))


## 星级标签.
static func star_label(star: int) -> String:
	return "%d星" % clampi(star, 1, MAX_STAR)


## 新商店掷货: 按局内等级的费用概率(SHOP_COST_ODDS[level]) 掷 count 个槽, 每槽从该费用的可刷池随机取一件.
##   pool=DataRegistry.phase2_equipment; rng 由调用方给(可 battle_seed 化→PvP一致/可测). 该费用没货则往低费回退.
static func roll_shop(pool: Array, level: int, count: int, rng: RandomNumberGenerator) -> Array:
	var by_cost: Dictionary = {}
	for it in pool:
		if not (it is Dictionary) or int(it.get("shopAvailable", 0)) != 1:
			continue
		var c := int(it.get("cost", 1))
		if not by_cost.has(c):
			by_cost[c] = []
		(by_cost[c] as Array).append(it)
	var out: Array = []
	for i in range(count):
		var tier := P2.roll_cost_tier(level, rng.randf())   # 费用档 1-5
		while tier >= 1 and (not by_cost.has(tier) or (by_cost[tier] as Array).is_empty()):
			tier -= 1   # 该费用没货 → 回退低费
		if tier < 1:
			out.append(null)
			continue
		var lst: Array = by_cost[tier]
		out.append(lst[rng.randi() % lst.size()])
	return out


## 检测套装 (壳): 统计已装备的系列/套装标签计数, 返回触发的套装.
## 加成数值占位 (设计未定) → bonus 为空 dict, 待填.
