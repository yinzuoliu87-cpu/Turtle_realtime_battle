extends RefCounted
## Phase2Types — 装备「类型(职业)」羁绊 (12类型, 第二维羁绊; 配 Phase2Schools 学派/种族)。
## 权威规格: docs/specs/类型效果-实装规格.md (HacknPlan GDM #1机制→#11羁绊→#543-554)。
## 映射: data/p2eq-types.json (id → 类型, 单一; 每件装备恰好 1 个类型)。
## 计数: 队伍中每件该类型装备 +1; 激活档 = 满足的最高阈值档 (1-based)。
##
## ⚠ 效果实装分两层:
##   1) 属性类(每件激活类型装备给携带者档位属性) — apply_team_start (待接, 需对齐 StatsRecalc 折入机制, 别直改 atk/def 被覆盖)。
##   2) 主动类(剑回响/盾怒气冲击波/枪金弹/弓箭处决/法器法力条/灵物触手/奇械死亡产装备/食物全队血/遗物条件吸血) — 各战斗钩子, 大工程, 逐个接。
## 当前: 仅计数 + 显示打通; 效果 TODO (见规格 md)。

# 类型 → {tiers(阈值件数), stats(逐档「每件该类型装备给携带者」属性, 供实装参考/将来 apply)}
const TYPES := {
	"剑":   {"tiers": [2, 4, 6],    "stats": [{"atk": 15}, {"atk": 35}, {"atk": 50}]},
	"奇械": {"tiers": [2, 4, 6],    "stats": [{"def": 5, "mr": 5}, {"def": 10, "mr": 10}, {"def": 16, "mr": 16}]},
	"食物": {"tiers": [3, 5],       "stats": [{}, {}]},  # 团队级 maxHP (全队每件装备+30/80, 食物双倍) — 特殊, apply 另写
	"盾":   {"tiers": [2, 3, 4, 5], "stats": [{"def": 6}, {"def": 13}, {"def": 19}, {"def": 26}]},
	"药水": {"tiers": [2, 4, 5],    "stats": [{"_maxEnergy": 15}, {"_maxEnergy": 30}, {"_maxEnergy": 50}]},
	"护符": {"tiers": [2, 4, 5],    "stats": [{"mr": 20}, {"mr": 40}, {"mr": 65}]},
	"枪":   {"tiers": [2, 3, 5],    "stats": [{"armorPen": 8}, {"armorPen": 16}, {"armorPen": 28}]},
	"弓箭": {"tiers": [2, 3, 4, 5], "stats": [{"crit": 0.08}, {"crit": 0.14}, {"crit": 0.20}, {"crit": 0.28}]},
	"法器": {"tiers": [2, 4, 5],    "stats": [{"magicPen": 8, "_maxEnergy": 10}, {"magicPen": 14, "_maxEnergy": 10}, {"magicPen": 22, "_maxEnergy": 10}]},
	"饰品": {"tiers": [2, 3, 4],    "stats": [{"healAmp": 15, "shieldAmp": 15}, {"healAmp": 30, "shieldAmp": 30}, {"healAmp": 50, "shieldAmp": 50}]},
	"灵物": {"tiers": [3, 4],       "stats": [{}, {}]},  # 闪避%(apply_team_start) + 无敌触手召唤(tentacle_setup→BattleScene._spawn/_process_tentacles, 规格#553已实装)
	"遗物": {"tiers": [2, 3, 4],    "stats": [{"_lifestealPct": 5}, {"_lifestealPct": 10}, {"_lifestealPct": 20}]},
}

# ══════════════════════════════════════════════════════════════════
# 【两区式 TFT 羁绊面板·显示数据】(用户 2026-06-25 拍板)
#   每个类型: 图标 emoji + 逐档效果文本(属性写完整: 全名+数值, 不缩写)。
#   TIER_DESCS[类型] 的第 i 项 = 第 (i+1) 档(对应 TYPES[类型].tiers[i] 阈值)的完整效果描述。
#   文本逐字对应 docs/specs/类型效果-实装规格.md (#543-554)。档位区列全部档, 主区取当前激活档。
# ══════════════════════════════════════════════════════════════════
const TYPE_EMOJI := {
	"剑": "🗡️", "奇械": "⚙️", "食物": "🍖", "盾": "🛡️", "药水": "🧪", "护符": "📿",
	"枪": "🔫", "弓箭": "🏹", "法器": "🔮", "饰品": "💍", "灵物": "🐙", "遗物": "🏺",
}
const TYPE_NAME := {
	"剑": "剑系", "奇械": "奇械·深海工坊", "食物": "食物·增益", "盾": "盾·守护",
	"药水": "药水·龟能", "护符": "护符·魔抗", "枪": "枪·神枪手", "弓箭": "弓箭·神射手",
	"法器": "法器·法师", "饰品": "饰品·续航", "灵物": "灵物·召唤", "遗物": "遗物·古物",
}
# 逐档完整效果文本 (属性全名+逐档数值写满, 不缩写)。
const TIER_DESCS := {
	"剑": [
		"全队每件剑额外提供 +15 攻击力 · 剑触发伤害效果后, 再以 50% 伤害回响 1 次(回响不触发任何装备效果)",
		"全队每件剑额外提供 +35 攻击力 · 剑触发伤害效果后, 再以 50% 伤害回响 2 次(回响不触发任何装备效果)",
		"全队每件剑额外提供 +50 攻击力 · 剑触发伤害效果后, 再以 50% 伤害回响 3 次(回响不触发任何装备效果)",
	],
	"奇械": [
		"每件奇械额外提供 +5 护甲 与 +5 魔法抗性 · 携带奇械者每回合铸造 1 枚深海币 · 每累计失去 1 名我方单位, 每件奇械各产 1 件装备(费用=累计失去数, 封顶 5 费, 永久入背包)",
		"每件奇械额外提供 +10 护甲 与 +10 魔法抗性 · 携带奇械者每回合铸造 2 枚深海币 · 每累计失去 1 名我方单位, 每件奇械各产 1 件装备(费用=累计失去数, 封顶 5 费, 永久入背包)",
		"每件奇械额外提供 +16 护甲 与 +16 魔法抗性 · 携带奇械者每回合铸造 3 枚深海币 · 每累计失去 1 名我方单位, 每件奇械各产 1 件装备(费用=累计失去数, 封顶 5 费, 永久入背包)",
	],
	"食物": [
		"队伍每件装备额外提供 +30 最大生命值(食物类装备双倍, +60) · 每回合每件食物为携带者及相邻宠物各永久 +8 最大生命值(可无限累积)",
		"队伍每件装备额外提供 +80 最大生命值(食物类装备双倍, +160) · 每回合每件食物为携带者及相邻宠物各永久 +20 最大生命值(可无限累积)",
	],
	"盾": [
		"每件盾额外提供 +6 护甲 · 携带盾者每次受伤获得(身上盾件数)怒气, 满 10 怒气消耗全部对一名敌人释放冲击波, 造成 4% 最大生命值的真实伤害, 并为自己获得 4% 最大生命值的护盾值",
		"每件盾额外提供 +13 护甲 · 携带盾者每次受伤获得(身上盾件数)怒气, 满 10 怒气消耗全部对一名敌人释放冲击波, 造成 5% 最大生命值的真实伤害, 并为自己获得 5% 最大生命值的护盾值",
		"每件盾额外提供 +19 护甲 · 携带盾者每次受伤获得(身上盾件数)怒气, 满 10 怒气消耗全部对一名敌人释放冲击波, 造成 6% 最大生命值的真实伤害, 并为自己获得 6% 最大生命值的护盾值",
		"每件盾额外提供 +26 护甲 · 携带盾者每次受伤获得(身上盾件数)怒气, 满 10 怒气消耗全部对一名敌人释放冲击波, 造成 8% 最大生命值的真实伤害, 并为自己获得 8% 最大生命值的护盾值",
	],
	"药水": [
		"每件药水额外提供 +15 最大龟能",
		"每件药水额外提供 +30 最大龟能",
		"每件药水额外提供 +50 最大龟能",
	],
	"护符": [
		"每件护符额外提供 +20 魔法抗性",
		"每件护符额外提供 +40 魔法抗性",
		"每件护符额外提供 +65 魔法抗性",
	],
	"枪": [
		"每件枪额外提供 +8 护甲穿透 · 每把枪射满 4 发额外射出 1 发金弹(继承该枪全部子弹效果 + 额外 60% 真实伤害, 不占弹药)",
		"每件枪额外提供 +16 护甲穿透 · 每把枪射满 3 发额外射出 1 发金弹(继承该枪全部子弹效果 + 额外 80% 真实伤害, 不占弹药)",
		"每件枪额外提供 +28 护甲穿透 · 每把枪射满 2 发额外射出 1 发金弹(继承该枪全部子弹效果 + 额外 100% 真实伤害, 不占弹药)",
	],
	"弓箭": [
		"每件弓箭额外提供 +8% 暴击率 · 携带弓箭者攻击时, 目标生命百分比低于斩杀线则直接处决(斩杀线 = 4% + 暴击率×0.1)",
		"每件弓箭额外提供 +14% 暴击率 · 携带弓箭者攻击时, 目标生命百分比低于斩杀线则直接处决(斩杀线 = 5% + 暴击率×0.1)",
		"每件弓箭额外提供 +20% 暴击率 · 携带弓箭者攻击时, 目标生命百分比低于斩杀线则直接处决(斩杀线 = 7% + 暴击率×0.1)",
		"每件弓箭额外提供 +28% 暴击率 · 携带弓箭者攻击时, 目标生命百分比低于斩杀线则直接处决(斩杀线 = 10% + 暴击率×0.1)",
	],
	"法器": [
		"每件法器额外提供 +8 法术穿透 与 +10 最大龟能 · 每件法器独立法力条满 100 触发其效果(每回合 +25 法力, 另按技能伤害×0.1 + 受伤×0.1 积累)",
		"每件法器额外提供 +14 法术穿透 与 +10 最大龟能 · 每件法器独立法力条满 80 触发其效果(每回合 +25 法力, 另按技能伤害×0.1 + 受伤×0.1 积累)",
		"每件法器额外提供 +22 法术穿透 与 +10 最大龟能 · 每件法器独立法力条满 60 触发其效果(每回合 +25 法力, 另按技能伤害×0.1 + 受伤×0.1 积累)",
	],
	"饰品": [
		"每件饰品额外提供 +15% 治疗强度 与 +15% 护盾强度 · 携带饰品者治疗溢出(满血仍受治疗)时, 溢出部分转化为护盾(无上限累积)",
		"每件饰品额外提供 +30% 治疗强度 与 +30% 护盾强度 · 携带饰品者治疗溢出(满血仍受治疗)时, 溢出部分转化为护盾(无上限累积)",
		"每件饰品额外提供 +50% 治疗强度 与 +50% 护盾强度 · 携带饰品者治疗溢出(满血仍受治疗)时, 溢出部分转化为护盾(无上限累积)",
	],
	"灵物": [
		"每件灵物额外提供 +5% 闪避率(上限 75%) · 1 个无敌触手登场, 每回合朝一目标拍击, 对沿途敌人造成(4%目标最大生命+55)物理伤害 · 每件独特灵物每升 1 星拍击 +5% · 每成功闪避 1 次触手追击 1 次(25% 伤害, 每回合最多 3 次)",
		"每件灵物额外提供 +10% 闪避率(上限 75%) · 2 个无敌触手登场, 每回合朝一目标拍击, 对沿途敌人造成(4%目标最大生命+55)物理伤害 · 每件独特灵物每升 1 星拍击 +5% · 每成功闪避 1 次触手追击 1 次(25% 伤害, 每回合最多 3 次)",
	],
	"遗物": [
		"每件遗物额外提供 +5% 吸血 · 携带遗物者生命 >50% 时额外 +3% 攻击力 · 生命 <50% 时遗物提供的吸血翻倍(→10%)",
		"每件遗物额外提供 +10% 吸血 · 携带遗物者生命 >50% 时额外 +5% 攻击力 · 生命 <50% 时遗物提供的吸血翻倍(→20%)",
		"每件遗物额外提供 +20% 吸血 · 携带遗物者生命 >50% 时额外 +8% 攻击力 · 生命 <50% 时遗物提供的吸血翻倍(→40%)",
	],
}

## 两区式面板·显示元数据: 给一个类型的图标 emoji。
static func emoji_of(typ: String) -> String:
	return str(TYPE_EMOJI.get(typ, "🗡️"))

## 两区式面板·显示名 (类型·别名)。
static func display_name(typ: String) -> String:
	return str(TYPE_NAME.get(typ, typ))

## 两区式面板·某类型某档(1-based)的完整效果文本; 越界返回 ""。
static func tier_desc(typ: String, tier_1based: int) -> String:
	var arr: Array = TIER_DESCS.get(typ, [])
	var i: int = tier_1based - 1
	if i < 0 or i >= arr.size():
		return ""
	return str(arr[i])

const _MAP_PATH := "res://data/p2eq-types.json"
static var _type_of: Dictionary = {}
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(_MAP_PATH):
		push_warning("[Phase2Types] 缺映射文件 %s" % _MAP_PATH)
		return
	var f := FileAccess.open(_MAP_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_type_of = parsed

## 某装备 id 的类型 (剑/盾/奇械/...), 无则 ""。
static func type_of(eid: String) -> String:
	_ensure_loaded()
	return str(_type_of.get(eid, ""))

## 统计某队(team = fighter 数组)的装备类型 → 已激活类型。
## 返回 [{type, count, tier(1-based, 0=未激活不返回), tiers}]，按 count 降序。
static func calc_active(team: Array) -> Array:
	_ensure_loaded()
	var counts: Dictionary = {}
	for f in team:
		if not (f is Dictionary):
			continue
		for it in f.get("_p2_equips", []):
			if not (it is Dictionary):
				continue
			var t := type_of(str(it.get("id", "")))
			if t != "":
				counts[t] = int(counts.get(t, 0)) + 1
	var active: Array = []
	for t in counts:
		if not TYPES.has(t):
			continue
		var n: int = int(counts[t])
		var tiers: Array = TYPES[t].get("tiers", [])
		var tier: int = 0
		for i in range(tiers.size()):
			if n >= int(tiers[i]):
				tier = i + 1
		if tier > 0:
			active.append({"type": t, "count": n, "tier": tier, "tiers": tiers})
	active.sort_custom(func(a, b): return int(a.get("count", 0)) > int(b.get("count", 0)))
	return active

## 仅计数(含未激活), 给两区面板灰显未达首档的类型: 类型 → 件数。
static func raw_counts(team: Array) -> Dictionary:
	_ensure_loaded()
	var counts: Dictionary = {}
	for f in team:
		if not (f is Dictionary):
			continue
		for it in f.get("_p2_equips", []):
			if not (it is Dictionary):
				continue
			var t := type_of(str(it.get("id", "")))
			if t != "" and TYPES.has(t):
				counts[t] = int(counts.get(t, 0)) + 1
	return counts


## 战斗开始: 每件「激活类型」装备给其携带者该类型当前档的【属性类】效果。
## 走 base/flat 字段 (1:1 phase2_equip_runtime.apply_stats 口径, 防被 recalc 覆盖); 在最终 recalc 前调让其折入; 蛋跳过。
## per-piece: 每件该类型装备各给一次 (同规格"X类装备额外提供Y")。
## ⚠ 主动类大部已接: 剑回响/盾怒气/枪金弹/弓箭处决/法器法力/灵物触手/奇械产装备/食物全队血/遗物条件吸血 (各战斗钩子)。
static func apply_team_start(team: Array) -> void:
	_ensure_loaded()
	var tier_of: Dictionary = {}
	for a in calc_active(team):
		tier_of[a["type"]] = int(a["tier"])
	# ── 食物[增益]开场全队血 (团队级, 一次): 食物激活 → 队伍每件装备 +30/80 maxHp, 食物类装备双倍(60/160)。 ──
	#   每回合每件食物再给携带者+相邻槽 +8/20 maxHp(累积) → _foodRoundGrow 标记, _fire_p2_turn_begin 消费。
	if tier_of.has("食物"):
		var fti: int = clampi(int(tier_of["食物"]) - 1, 0, 1)
		var per_equip: int = [30, 80][fti]
		for f in team:
			if not (f is Dictionary) or f.get("_isEgg", false):
				continue
			var add_hp: int = 0
			for it in f.get("_p2_equips", []):
				if not (it is Dictionary):
					continue
				# 食物类装备双倍, 其余装备单倍 (食物羁绊给【全队每件装备】血)。
				add_hp += per_equip * (2 if type_of(str(it.get("id", ""))) == "食物" else 1)
			if add_hp > 0:
				f["maxHp"] = int(f.get("maxHp", 0)) + add_hp
				f["hp"] = int(f.get("hp", 0)) + add_hp
			# 每回合成长标记: 携带食物者每件食物 +8/20 maxHp 给自身+相邻 (消费见 _fire_p2_turn_begin)。
			if carries_type(f, "食物"):
				f["_foodRoundGrow"] = [8, 20][fti]
	for f in team:
		if not (f is Dictionary) or f.get("_isEgg", false):
			continue
		for it in f.get("_p2_equips", []):
			if not (it is Dictionary):
				continue
			var t := type_of(str(it.get("id", "")))
			if t == "" or not tier_of.has(t):
				continue
			var stats: Array = TYPES[t].get("stats", [])
			var ti: int = clampi(int(tier_of[t]) - 1, 0, maxi(0, stats.size() - 1))
			if ti < 0 or ti >= stats.size():
				continue
			for k in stats[ti]:
				_apply_type_stat(f, k, stats[ti][k])
		# ── 主动类羁绊 flag (携带者判定, 各战斗钩子消费) ──
		# 剑[回响]: 携带剑且剑激活 → 剑装备触发伤害效果后, 再以50%伤害回响 N 次(N=激活档 1/2/3);
		#   回响伤害【不触发任何装备效果】(无嵌套回响/无后续proc)。钩子在 phase2_equip_runtime.sword_echo
		#   (包裹剑系 on_hit/on_cast/on_turn_begin 产出的伤害 effect)。规格 #543。
		if tier_of.has("剑") and carries_type(f, "剑"):
			var swt: int = clampi(int(tier_of["剑"]) - 1, 0, 2)
			f["_swordEchoCount"] = [1, 2, 3][swt]
		# 弓箭[神射手]: 携带弓箭且弓箭激活 → 处决 base (斩杀线 = base + crit×0.1, 钩子在 phase2_equip_runtime.on_hit)。
		if tier_of.has("弓箭") and carries_type(f, "弓箭"):
			var at: int = clampi(int(tier_of["弓箭"]) - 1, 0, 3)
			f["_archerExecBase"] = [0.04, 0.05, 0.07, 0.10][at]
		# 奇械[深海工坊]: 携带奇械且奇械激活 → 标件数 _gadgetPieces(死亡产装备数=件数, 钩子在 BattleScene 死亡口)
		#   + 标每回合铸币量 _gadgetMint = 1/2/3 (按激活档; 携带者每回合产, BattleScene 双路回合口消费)。规格#544。
		if tier_of.has("奇械") and carries_type(f, "奇械"):
			f["_gadgetPieces"] = count_type(f, "奇械")
			var gti: int = clampi(int(tier_of["奇械"]) - 1, 0, 2)
			f["_gadgetMint"] = [1, 2, 3][gti]
		# 遗物[古物]: 携带遗物且遗物激活 → hp>50% 额外 ATK%(StatsRecalc 动态算) + hp<50% 遗物吸血翻倍(BattleScene 吸血结算判)。
		if tier_of.has("遗物") and carries_type(f, "遗物"):
			var rt: int = clampi(int(tier_of["遗物"]) - 1, 0, 2)
			f["_relicHealthAtkPct"] = [0.03, 0.05, 0.08][rt]
			f["_relicLifestealBase"] = [0.05, 0.10, 0.20][rt]   # 遗物羁绊提供的吸血(小数); <50%时再翻一倍
		# 法器[法师]: 携带法器且法器激活 → 标 _staffTier(满档算)+ 给每件法器开一条独立法力条 _staff_mana[id]=0。
		#   ⚠ _staff_mana 是【独立字段】, 与 _energy/_maxEnergy 完全隔离(法力≠龟能)。累积/触发见 phase2_equip_runtime staff_*。
		if tier_of.has(STAFF_TYPE) and carries_type(f, STAFF_TYPE):
			f["_staffTier"] = int(tier_of[STAFF_TYPE])
			var sm: Dictionary = {}
			for sid in staff_ids_of(f):
				sm[sid] = 0
			f["_staff_mana"] = sm
		# 盾[守护]怒气冲击波: 携带盾且盾激活 → 标阈值%(冲击波真伤+自盾) + 数好身上盾件数(每次受伤+件数怒气)。
		#   怒气累积/释放见 phase2_equip_runtime.shield_rage_on_damaged (承伤口调一次/伤害实例)。
		if tier_of.has("盾") and carries_type(f, "盾"):
			var st: int = clampi(int(tier_of["盾"]) - 1, 0, 3)
			f["_shieldRageThr"] = [0.04, 0.05, 0.06, 0.08][st]   # 冲击波/自盾 = 该%×最大生命
			f["_shieldPieces"] = count_type(f, "盾")             # 每次受伤获得的怒气 = 身上盾件数
			f["_shieldRage"] = int(f.get("_shieldRage", 0))       # 累计怒气, 满10释放清零
		# 枪[神枪手]金弹: 携带枪且枪激活 → 标激活档 _gunTier(1/2/3 = 2/3/5件)。
		#   每把枪独立子弹计数, 每射满 4/3/2 发 → 额外射1发金弹(同子弹效果+60/80/100%真伤, 不计入计数)。
		#   计数器/触发见 phase2_equip_runtime.gun_fire_shot (枪系 on_cast/on_side_end 每发后调)。规格 #549。
		if tier_of.has("枪") and carries_type(f, "枪"):
			f["_gunTier"] = int(tier_of["枪"])
			f["_gunBullets"] = {}   # {枪装备id: 累计射击数} — 每把枪独立计数
		# 饰品[续航]溢出转盾: 携带饰品且饰品激活 → 治疗溢出(满血仍受治疗)转护盾, 无上限 (规格#552, _heal/_heal_to 消费)。
		#   ⚠ 属性 healAmp/shieldAmp 已由上方 per-piece stats 折入; 此 flag 仅开启"溢出转盾"(类型级, 区别于 011 单件带 cap 的 _p2BloodShieldCap)。
		if tier_of.has("饰品") and carries_type(f, "饰品"):
			f["_p2AccessoryOverflowShield"] = true
		# 灵物[召唤]闪避: 携带灵物且灵物激活 → 每件灵物 +5/10% 闪避(_extraDodge, _roll_dodge 读), 总闪避封顶 75%。
		if tier_of.has("灵物") and carries_type(f, "灵物"):
			var lt: int = clampi(int(tier_of["灵物"]) - 1, 0, 1)
			var per_dodge: int = [5, 10][lt]
			var add_dodge: int = per_dodge * count_type(f, "灵物")
			f["_extraDodge"] = mini(75, int(f.get("_extraDodge", 0)) + add_dodge)

## 单属性入 base/flat 字段 (1:1 apply_stats: atk/def/mr 入 base, 其余直加; 防 recalc 覆盖)。
static func _apply_type_stat(f: Dictionary, key: String, val) -> void:
	match key:
		"atk":
			f["baseAtk"] = int(f.get("baseAtk", 0)) + int(val); f["atk"] = f["baseAtk"]
		"def":
			f["baseDef"] = int(f.get("baseDef", 0)) + int(val); f["def"] = f["baseDef"]
		"mr":
			f["baseMr"] = int(f.get("baseMr", 0)) + int(val); f["mr"] = f["baseMr"]
		"crit":
			f["crit"] = float(f.get("crit", 0.0)) + float(val)
		"armorPen":
			f["armorPen"] = int(f.get("armorPen", 0)) + int(val)
		"magicPen":
			f["magicPen"] = int(f.get("magicPen", 0)) + int(val)
		"_maxEnergy":
			f["_maxEnergy"] = int(f.get("_maxEnergy", 0)) + int(val)
		"_lifestealPct":
			f["_lifestealPct"] = int(f.get("_lifestealPct", 0)) + int(val)
		"healAmp":
			f["healAmp"] = float(f.get("healAmp", 0.0)) + float(val)
		"shieldAmp":
			f["shieldAmp"] = float(f.get("shieldAmp", 0.0)) + float(val)


## 该 fighter 是否带有某类型装备 (携带者判定, 给主动效果用)。
static func carries_type(f: Dictionary, typ: String) -> bool:
	if not (f is Dictionary):
		return false
	for it in f.get("_p2_equips", []):
		if it is Dictionary and type_of(str(it.get("id", ""))) == typ:
			return true
	return false


## 该 fighter 身上某类型装备件数 (盾怒气=盾件数 / 灵物闪避=灵物件数 等逐件效果用)。
static func count_type(f: Dictionary, typ: String) -> int:
	if not (f is Dictionary):
		return 0
	var n: int = 0
	for it in f.get("_p2_equips", []):
		if it is Dictionary and type_of(str(it.get("id", ""))) == typ:
			n += 1
	return n


# ══════════════════════════════════════════════════════════════════
# 【灵物·召唤 无敌触手】(类型·灵物 激活 3/4 → 触手 1/2 个; 顶档 4 已由用户下调, 见 TYPES)
#   规格 #553: 激活时 1/2 个场边触手登场(无敌单位, 不可攻击/击杀); 每回合朝一目标拍击,
#   对沿途敌人 (4%目标最大HP + 55) 物理伤害。每【独特灵物】每升一星 → 拍击伤害 +5%(累加)。
#   己方每成功闪避一次攻击 → 触手立即追加一次拍击(25%原伤害); 此追击每回合最多 3 次。
#   实际召唤(spawn fighter+view)/每回合拍击/闪避追击 在 BattleScene 消费 tentacle_setup 返回值。
# ══════════════════════════════════════════════════════════════════
## 该队(team=同侧 fighter 数组)的触手配置: {count(0/1/2 触手数), dmg_mult(拍击伤害倍率)}。
##   count = 灵物激活档(tier 1→1, tier 2→2); 未激活=0。
##   dmg_mult = 1 + 0.05 × Σ(每件【独特】灵物的星级)  (每件独特灵物每升一星 +5% 累加)。
##   注: "独特" = 按装备 id 去重(同 id 多件只算一次, 取其最高星)。
static func tentacle_setup(team: Array) -> Dictionary:
	_ensure_loaded()
	var tier: int = 0
	for a in calc_active(team):
		if str(a.get("type", "")) == "灵物":
			tier = int(a.get("tier", 0))
	if tier <= 0:
		return {"count": 0, "dmg_mult": 1.0}
	# 每件独特灵物(id 去重, 取最高星)的星级求和 → +5%/星 累加。
	var star_by_id: Dictionary = {}
	for f in team:
		if not (f is Dictionary):
			continue
		for it in f.get("_p2_equips", []):
			if not (it is Dictionary):
				continue
			var eid: String = str(it.get("id", ""))
			if type_of(eid) != "灵物":
				continue
			var st: int = clampi(int(it.get("star", 1)), 1, 3)
			star_by_id[eid] = maxi(int(star_by_id.get(eid, 0)), st)
	var star_sum: int = 0
	for k in star_by_id:
		star_sum += int(star_by_id[k])
	return {"count": tier, "dmg_mult": 1.0 + 0.05 * float(star_sum)}


## 单次触手拍击的基础伤害 (沿途每个敌人): (4% 目标最大HP + 55) × dmg_mult。返整数(>=1)。
static func tentacle_slap_damage(target_max_hp: int, dmg_mult: float) -> int:
	return maxi(1, roundi((0.04 * float(target_max_hp) + 55.0) * dmg_mult))


# ══════════════════════════════════════════════════════════════════
# 【法器·法力系统】(类型·法器 [法师] 激活 2/4/6 → 满档 100/80/60)
#   ⚠ 铁律: 法力(mana) ≠ 龟能(energy)。法力存在独立字段 _staff_mana = {装备id: 当前值},
#   绝不读写 _energy / _maxEnergy。每件法器各自一条法力条, 互不共享, 也不碰龟能。
#   规格: docs/specs/类型效果-实装规格.md #551。
# ══════════════════════════════════════════════════════════════════

const STAFF_TYPE := "法器"
## 法器满档(触发阈值): tier 2/4/6 → 100/80/60。tier=该队法器激活档(1/2/3)。
static func staff_mana_cap(tier: int) -> int:
	return [100, 80, 60][clampi(tier, 1, 3) - 1]

## 某 fighter 的法器激活档(1-based, 0=未激活/无法器)。优先读 apply_team_start 标记的 _staffTier。
static func staff_tier_of(f: Dictionary) -> int:
	if not (f is Dictionary):
		return 0
	return int(f.get("_staffTier", 0))

## 该 fighter 携带的全部法器装备 id (顺序与 _p2_equips 一致)。
static func staff_ids_of(f: Dictionary) -> Array:
	var out: Array = []
	if not (f is Dictionary):
		return out
	for it in f.get("_p2_equips", []):
		if it is Dictionary and type_of(str(it.get("id", ""))) == STAFF_TYPE:
			out.append(str(it.get("id", "")))
	return out
