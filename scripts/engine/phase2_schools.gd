extends RefCounted
## 二阶段双路 — 11 学派(装备套装羁绊) 计数与定义。
## 设计 11 学派全部同步在 HacknPlan(学派·XXX 设计元素)。效果实装见 _apply_* (待接战斗钩子)。
## 计数规则: 队伍中每件已装 p2eq 装备, 按其所属学派(可多个, "主＋副")各 +1。多学派件对每个学派都计数。
##   激活档 = 满足的最高阈值档 (1-based tier index)。

# 学派定义: 名 → {tag(职业/羁绊名), tiers(各档阈值件数)}
const SCHOOLS := {
	"血牙帮":    {"tag": "血祭",     "tiers": [3, 6, 9]},
	"深渊议会":  {"tag": "腐蚀",     "tiers": [3, 5, 8]},
	"玄甲卫队":  {"tag": "玄甲工坊", "tiers": [3, 5, 7]},
	"珊瑚学院":  {"tag": "战斗学院", "tiers": [3, 6, 9]},
	"深海军械库": {"tag": "军火",     "tiers": [3, 6, 9]},
	"黑礁猎团":  {"tag": "猎杀",     "tiers": [3, 5, 8]},
	"极地小队":  {"tag": "冰封",     "tiers": [3, 6, 9]},
	"潮汐议会":  {"tag": "潮汐",     "tiers": [2, 5, 7, 10]},
	"圣甲议会":  {"tag": "圣盾",     "tiers": [3, 5, 8]},
	"唤灵学会":  {"tag": "亡灵",     "tiers": [2, 4, 6, 8, 10]},
	"远古遗迹":  {"tag": "古代觉醒", "tiers": [3, 6, 9]},
}

# ══════════════════════════════════════════════════════════════════
# 【两区式 TFT 羁绊面板·显示数据】(用户 2026-06-25 拍板, 同类型两区式)
#   每个学派: 图标 emoji + 逐档完整效果文本(属性写全名+数值)。
#   TIER_DESCS[学派] 第 i 项 = 第 (i+1) 档(对应 SCHOOLS[学派].tiers[i] 阈值)的完整效果。
#   文本逐字对应 docs/specs/学派效果-实装规格.md。
# ══════════════════════════════════════════════════════════════════
const SCHOOL_EMOJI := {
	"血牙帮": "🩸", "深渊议会": "🦠", "玄甲卫队": "🐢", "珊瑚学院": "🔮", "深海军械库": "🔩",
	"黑礁猎团": "🎯", "极地小队": "❄️", "潮汐议会": "🌊", "圣甲议会": "✨", "唤灵学会": "👻", "远古遗迹": "🗿",
}
# 逐档完整效果文本 (属性全名+逐档数值写满, 不缩写)。
const TIER_DESCS := {
	"血牙帮": [
		"全队每损失 1% 最大生命值 → +0.6 攻击力 · 每个友军生命首次跌至 30% 以下时获得相当于其 100% 攻击力的护盾(每单位每场一次)",
		"全队每损失 1% 最大生命值 → +1.0 攻击力 · 每个友军生命首次跌至 30% 以下时获得相当于其 100% 攻击力的护盾(每单位每场一次)",
		"全队每损失 1% 最大生命值 → +1.5 攻击力 · 每个友军生命首次跌至 30% 以下时获得相当于其 100% 攻击力的护盾(每单位每场一次)",
	],
	"深渊议会": [
		"全队攻击无视目标 12% 护甲和魔抗 · 每回合末所有敌人 +1 层腐蚀(每层使其受到的伤害 +3%, 最多 5 层) · 满 5 层时受到伤害的 30% 转化为真实伤害",
		"全队攻击无视目标 22% 护甲和魔抗 · 每回合末所有敌人 +1 层腐蚀(每层使其受到的伤害 +4%, 最多 5 层) · 满 5 层时受到伤害的 30% 转化为真实伤害",
		"全队攻击无视目标 40% 护甲和魔抗 · 每回合末所有敌人 +1 层腐蚀(每层使其受到的伤害 +6%, 最多 5 层) · 满 5 层时受到伤害的 30% 转化为真实伤害",
	],
	"玄甲卫队": [
		"每回合开始随机将 1 件「费用≤2 且非3星」装备临时玄甲化(本回合按高一星结算) · 每回合开始全队 +10 护盾值",
		"每回合开始随机将 1 件「费用≤3 且非3星」装备临时玄甲化(本回合按高一星结算) · 每回合开始全队 +15 护盾值",
		"每回合开始随机将 2 件「费用≤4 且非3星」装备临时玄甲化(本回合按高一星结算) · 每回合开始全队 +20 护盾值",
	],
	"珊瑚学院": [
		"队伍获得 +90 最大生命值 · 激活获得 1 枚珊瑚碎片(全体珊瑚装备共享的潜能, 碎片越多珊瑚装备效果越强)",
		"队伍获得 +100 最大生命值 · 激活获得 2 枚珊瑚碎片(全体珊瑚装备共享的潜能, 碎片越多珊瑚装备效果越强)",
		"队伍获得 +110 最大生命值 · 激活获得 4 枚珊瑚碎片(全体珊瑚装备共享的潜能, 碎片越多珊瑚装备效果越强)",
	],
	"深海军械库": [
		"最前方生成炮台1: 回合末选一名敌人轰击, 对直线命中单位造成 80 物理伤害, 并为最低血友军回复(30%×造成伤害)生命",
		"+ 中心炮台2: 每回合产(100+20×件数)能量, 奇数回合转护盾均摊全队 / 偶数回合化弹幕魔法均摊敌全体, 循环",
		"+ 后方炮台3·火控: 军械库携带者额外造成(10+5×件数)% 真实伤害",
	],
	"黑礁猎团": [
		"战斗开始获得猎杀卡指定猎物 · 全队对猎物伤害 +15% · 每击杀一个猎物全队攻击力永久 +14(本场累积, 可重选)",
		"战斗开始获得猎杀卡指定猎物 · 全队对猎物伤害 +25% · 每击杀一个猎物全队攻击力永久 +26(本场累积, 可重选)",
		"战斗开始获得猎杀卡指定猎物 · 全队对猎物伤害 +40% · 每击杀一个猎物全队攻击力永久 +38 · 攻击猎物生命 <20% 时直接处决(斩首)",
	],
	"极地小队": [
		"全队攻击 15% 概率冻结目标 1 回合(同目标每回合最多冻结 1 次, 解冻后 1 回合免疫冻结)",
		"全队攻击 25% 概率冻结目标 1 回合 · 每段攻击额外叠 1 层僵硬(持续4回合, 每层攻击力 -2%, 最多 20 层)",
		"全队攻击 40% 概率冻结目标 1 回合 · 每段攻击叠 1 层僵硬(每层攻击力 -2%, 最多 20 层) · 被冻结/眩晕的敌人受到的伤害 +25%",
	],
	"潮汐议会": [
		"每回合开始全队回复已损失生命的 4% · 友军受治疗时额外获得治疗量 15% 的护盾 · 每 3 回合大潮: 全队回复 15% 最大生命并净化 1 个减益",
		"每回合开始全队回复已损失生命的 7% · 友军受治疗时额外获得治疗量 25% 的护盾 · 每 3 回合大潮: 全队回复 15% 最大生命并净化 1 个减益",
		"每回合开始全队回复已损失生命的 10% · 友军受治疗时额外获得治疗量 35% 的护盾 · 每 3 回合大潮: 全队回复 15% 最大生命并净化 2 个减益",
		"每回合开始全队回复已损失生命的 12% · 友军受治疗时额外获得治疗量 50% 的护盾 · 每 3 回合大潮: 全队回复 15% 最大生命并净化 3 个减益",
	],
	"圣甲议会": [
		"获得 1 个圣盾装备(+150 最大生命值) · 每 2 回合为携带者生成 45×(1+0.5×件数)圣光护盾 · 护盾存在时反击每段伤害造成(2×(1+0.5×件数))真实伤害",
		"获得 2 个圣盾装备(各 +150 最大生命值) · 每 2 回合生成圣光护盾并反击真实伤害 · 敌方阵亡时圣盾立即为携带者提供该单位 30% 最大生命的圣光护盾",
		"获得 2 个圣盾装备(各 +150 最大生命值) · 敌亡转盾 · 圣甲提供治疗/护盾时额外 +20% 治疗量/护盾量 的圣光护盾 · 圣盾提供的所有圣盾值 +20%",
	],
	"唤灵学会": [
		"友方阵亡时原地召唤亡魂, 继承其 20% 攻击力和生命, 自动攻击最近敌人 · 亡魂阵亡不再循环(0 次)",
		"友方阵亡时原地召唤亡魂, 继承其 30% 攻击力和生命 · 亡魂阵亡后再循环 1 次(每次属性 ×0.9 递减)",
		"友方阵亡时原地召唤亡魂, 继承其 45% 攻击力和生命 · 亡魂阵亡后再循环 2 次(每次属性 ×0.9 递减)",
		"友方阵亡时原地召唤亡魂, 继承其 65% 攻击力和生命 · 亡魂阵亡后再循环 3 次(每次属性 ×0.9 递减)",
		"友方阵亡时原地召唤亡魂, 继承其 100% 攻击力和生命 · 亡魂阵亡后再循环 4 次(每次属性 ×0.9 递减)",
	],
	"远古遗迹": [
		"龟蛋获得 +500 最大生命值 · 每回合全队永久 +3 攻击力(本场累积, 软上限 +300) · 满 8 回合觉醒: 已累积效果 +50% 且之后每回合获得翻倍",
		"龟蛋获得 +750 最大生命值 · 每回合全队永久 +6 攻击力(本场累积, 软上限 +300) · 满 8 回合觉醒: 已累积效果 +50% 且之后每回合获得翻倍",
		"龟蛋获得 +1500 最大生命值 · 每回合全队永久 +10 攻击力(软上限 +300) · 满 8 回合觉醒翻倍 · 觉醒后每回合对全体敌人造成已累积远古之力 150% 的真实伤害",
	],
}

## 两区式面板·某学派图标 emoji。
static func emoji_of(school: String) -> String:
	return str(SCHOOL_EMOJI.get(school, "🔮"))

## 两区式面板·某学派某档(1-based)的完整效果文本; 越界返回 ""。
static func tier_desc(school: String, tier_1based: int) -> String:
	var arr: Array = TIER_DESCS.get(school, [])
	var i: int = tier_1based - 1
	if i < 0 or i >= arr.size():
		return ""
	return str(arr[i])

const _MAP_PATH := "res://data/p2eq-schools.json"
static var _eq_schools: Dictionary = {}   # id -> [学派...], 懒加载缓存
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(_MAP_PATH):
		push_warning("[Phase2Schools] 缺映射文件 %s" % _MAP_PATH)
		return
	var f := FileAccess.open(_MAP_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_eq_schools = parsed

## 某装备 id 所属学派列表 (可空)。
static func schools_of(eid: String) -> Array:
	_ensure_loaded()
	return _eq_schools.get(eid, [])

## 某 fighter 是否身上带有属于 school 的装备 (军火[9档]火控接通用: 携带者判定)。
static func carries_school(f: Dictionary, school: String) -> bool:
	if not (f is Dictionary):
		return false
	for it in f.get("_p2_equips", []):
		if it is Dictionary and schools_of(str(it.get("id", ""))).has(school):
			return true
	return false

## 统计某队(team = fighter 数组)的装备学派 → 已激活学派。
## 返回 [{school, tag, count, tier(1-based, 0=未激活不返回), tiers}]，按 count 降序。
static func calc_active(team: Array) -> Array:
	_ensure_loaded()
	var counts: Dictionary = {}
	for f in team:
		if not (f is Dictionary):
			continue
		for it in f.get("_p2_equips", []):
			if not (it is Dictionary):
				continue
			for s in schools_of(str(it.get("id", ""))):
				counts[s] = int(counts.get(s, 0)) + 1
	var active: Array = []
	for s in counts:
		if not SCHOOLS.has(s):
			continue
		var n: int = int(counts[s])
		var tiers: Array = SCHOOLS[s].get("tiers", [])
		var tier: int = 0
		for i in range(tiers.size()):
			if n >= int(tiers[i]):
				tier = i + 1
		if tier > 0:
			active.append({"school": s, "tag": str(SCHOOLS[s].get("tag", "")), "count": n, "tier": tier, "tiers": tiers})
	active.sort_custom(func(a, b): return int(a.get("count", 0)) > int(b.get("count", 0)))
	return active

## 仅计数(含未激活), 给图鉴/调试: 学派 → 件数。
static func raw_counts(team: Array) -> Dictionary:
	_ensure_loaded()
	var counts: Dictionary = {}
	for f in team:
		if not (f is Dictionary):
			continue
		for it in f.get("_p2_equips", []):
			if not (it is Dictionary):
				continue
			for s in schools_of(str(it.get("id", ""))):
				counts[s] = int(counts.get(s, 0)) + 1
	return counts
