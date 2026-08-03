extends RefCounted

## Phase2Equip — 二阶段装备: 三合一升星 + 套装 (壳, 数值占位)
##
## 用 preload 引 (不用 class_name — 防 F5 未声明崩):
##   const Phase2Equip = preload("res://scripts/gamedata/phase2_equip.gd")
##
## 现状(壳): 升星/合成/套装的【结构与规则】已搭, 数值是占位, 待用户定:
##   - 1星基础属性 ×1.8 升星 = 占位公式 (设计文档没给精确值)
##   - 套装加成数值 = 占位 (设计只定了触发条件: 系列≥3 / 子流派≥2, 没给加成数值)
##   - (过期描述已订正 2026-07-19) 装备效果早已全部接进实时战斗, 见 phase2_equip_runtime.gd; data 里 effectImpl 恒为 true 且无人读取
## 数据来源: res://data/phase2-equipment.json (59件, xlsx「处理B」结构化).

const P2 := preload("res://scripts/gamedata/phase2_config.gd")

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


## 新商店掷货: 按局内等级的费用概率(SHOP_COST_ODDS[level]) 掷 count 个槽, 每槽从该费用的可刷池随机取一件.
##   pool=DataRegistry.phase2_equipment; rng 由调用方给(可 battle_seed 化→PvP一致/可测). 该费用没货则往低费回退.
## ★2026-08-03 批2: 加了 `no_dup` —— 同一次掷货里不出重复的件(方案书 D23 的配套)。
##   D23 定的是「货架未买的不算已扣、成交才扣」, 好处是池状态与货架完全解耦(不必成对回滚);
##   代价就是同一屏可能掷出两个一样的格子。这里在【本次掷货的局部】去重即可,
##   ★不碰池状态 —— 一碰就把 D23 的好处丢了。
##   去重是"尽力而为": 该费用的可选件不够 count 个时不会硬凑, 宁可重复也不留空格。
static func roll_shop(pool: Array, level: int, count: int, rng: RandomNumberGenerator, no_dup: bool = true) -> Array:
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
		var pick = lst[rng.randi() % lst.size()]
		if no_dup and lst.size() > 1:
			# 最多重试 lst.size() 次 —— 不用 while(重复) 死循环: 该费用只剩 1 件可选时永远退不出来。
			var tries := 0
			while tries < lst.size() and _already_picked(out, pick):
				pick = lst[rng.randi() % lst.size()]
				tries += 1
		out.append(pick)
	return out


static func _already_picked(out: Array, cand) -> bool:
	if not (cand is Dictionary):
		return false
	var cid: String = str((cand as Dictionary).get("id", ""))
	for o in out:
		if o is Dictionary and str((o as Dictionary).get("id", "")) == cid:
			return true
	return false


## 检测套装 (壳): 统计已装备的系列/套装标签计数, 返回触发的套装.
## 加成数值占位 (设计未定) → bonus 为空 dict, 待填.
