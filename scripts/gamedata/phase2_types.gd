extends RefCounted
## Phase2Types — 装备「类型」羁绊 (10 类型, 2026-08-03 起是【唯一】的羁绊维度; 学派系统已删除)。
## 逐档效果定稿: docs/plans/20260802-装备扩充.md §5 (十个类型逐档效果, 2026-08-03 批1 落地文案层)。
## 映射: data/p2eq-types.json (id → 类型, 单一; 每件装备恰好 1 个类型)。
## 计数: 队伍中每件该类型装备 +1; 激活档 = 满足的最高阈值档 (1-based)。
##
## ⚠ 效果实装分两层:
##   1) 属性类(每件激活类型装备给携带者档位属性) — apply_team_start (待接, 需对齐 StatsRecalc 折入机制, 别直改 atk/def 被覆盖)。
##   2) 主动类(剑回响/盾怒气冲击波/枪金弹/弓箭处决/法器法力条/灵物触手/奇械死亡产装备/食物全队血/遗物条件吸血) — 各战斗钩子, 大工程, 逐个接。
## 当前: 仅计数 + 显示打通; 效果 TODO (见规格 md)。

# 类型 → {tiers(阈值件数), stats(逐档「每件该类型装备给携带者」属性, 供实装参考/将来 apply)}
# 类型 → {tiers(阈值件数), stats(逐档「每件该类型装备给携带者」属性, 供实装参考/将来 apply)}
# ★2026-08-03 批1(方案书 docs/plans/20260802-装备扩充.md):
#   · 12 → 10 类型: 「护符」「饰品」解散(D2)。护符的 mr 转给【奇械】(D10, 奇械从此是纯魔抗、不再给 def);
#     饰品的 healAmp/shieldAmp 【直接消失, 不补给任何类型】(D14, 用户原话「u2消失就好」)。
#     ⇒ 羁绊层的 def 从此【只剩盾一家】(§4.9.3), 单件装备的 def 属性不受影响。
#   · 阈值重定(D5): 10 件的类型 [2,5,8,10] / 9 件的类型 [3,6,9]。
#     ★【顶档 == 该类型件数】是有意为之, 不是 bug —— 走宽(凑满一个类型)与走高(合 3★)互斥,
#     因为 calc_active 每件 +1、不看星不去重; 顶档 10 件要占满级 18 个装备位的 56%。
#     verify_equip_types ⑥ 焊死这条, 免得下一个人当 bug "修"掉。
#   · ★★2026-08-03 批4-1 【按实时版基础属性重新标定】。原来这张表的数值来自方案书 §5,
#     而 §5 又继承自这张表更早的版本 —— 那份数据【从来没有被施加过】(羁绊在战斗里零效果),
#     所以量级错了一整个数量级也没人发现。批4-1 把它接上战斗的当天, 探针一量:
#       剑顶档带 3 件 = 攻击力 ×5.65(40→226) · 奇械 ×23.5(魔抗 14→329) · 盾 ×9.14 · 弓箭暴击 +90%
#     (龟基础属性取 pets.json 28 只的中位: 攻 40 / 血 944 / 护甲 14 / 魔抗 14)
#   · 新数值按方案书 §4.5.3 自己的口径反解: 顶档占 50~56% 装备位、收益超线性
#     ⇒ 定为【携带者带满 3 件时战力约 ×2.2】(4 档的是 ×1.2/1.55/1.9/2.3, 3 档的 ×1.3/1.7/2.2)。
#     护甲/魔抗用【真公式】反解, 不是拍脑袋: DamageMath.resist_multiplier(r) = 1 - r/(r+40),
#     取"等效生命倍率"达标的 r 再除以 3 件。逐档数字与推导见 CHANGELOG v0.19.3。
#   · ★一个意外的旁证: 反解出的奇械 4/10/16/23 与【这张表最初的 5/10/16】几乎一致 ——
#     说明最初那版是按实时版口径标的, 是方案书 §4.9.2 的"重标定"(18/40/68/105)把它推高了 4~6 倍。
#   · 效果文本见下方 TIER_DESCS(那是设计定稿, 属性数值以本表为准)。
const TYPES := {
	"剑":   {"tiers": [3, 6, 9],     "stats": [{"atk": 8}, {"atk": 15}, {"atk": 25}]},   # 用户 2026-08-03 定
	"奇械": {"tiers": [2, 5, 8, 10], "stats": [{"mr": 4}, {"mr": 10}, {"mr": 16}, {"mr": 23}]},
	"食物": {"tiers": [3, 6, 9],     "stats": [{"_foodPerEquip": 30}, {"_foodPerEquip": 70}, {"_foodPerEquip": 130}]},
	"盾":   {"tiers": [3, 6, 9],     "stats": [{"def": 5}, {"def": 13}, {"def": 22}]},
	"药水": {"tiers": [3, 6, 9],     "stats": [{"_maxEnergy": 5}, {"_maxEnergy": 11}, {"_maxEnergy": 20}]},
	"枪":   {"tiers": [3, 6, 9],     "stats": [{"armorPen": 3}, {"armorPen": 6}, {"armorPen": 10}]},
	# ★弓箭必须同时给【暴伤】: 只给暴击撑不起顶档 —— DPS 倍率 = 1 + 暴击×(暴伤−1),
	#   暴伤基础只有 1.5 ⇒ 就算 +30% 暴击也只是 +15% DPS(量级门禁当场抓出来的)。
	#   两条同比例涨才够: 顶档带 3 件 = 暴击 +65% / 暴伤 +134% ⇒ DPS ×2.2。
	"弓箭": {"tiers": [3, 6, 9],     "stats": [{"crit": 0.09, "critDmg": 0.19}, {"crit": 0.16, "critDmg": 0.33}, {"crit": 0.22, "critDmg": 0.45}]},
	"法器": {"tiers": [2, 5, 8, 10], "stats": [{"magicPen": 4, "_maxEnergy": 4}, {"magicPen": 7, "_maxEnergy": 6}, {"magicPen": 11, "_maxEnergy": 8}, {"magicPen": 14, "_maxEnergy": 10}]},
	"灵物": {"tiers": [2, 5, 8, 10], "stats": [{"dodgePct": 5}, {"dodgePct": 9}, {"dodgePct": 13}, {"dodgePct": 18}]},
	"遗物": {"tiers": [2, 5, 8, 10], "stats": [{"_lifestealPct": 3}, {"_lifestealPct": 5}, {"_lifestealPct": 8}, {"_lifestealPct": 10}]},
}


# ══════════════════════════════════════════════════════════════════
# 【两区式 TFT 羁绊面板·显示数据】(用户 2026-06-25 拍板)
#   每个类型: 图标 emoji + 逐档效果文本(属性写完整: 全名+数值, 不缩写)。
#   TIER_DESCS[类型] 的第 i 项 = 第 (i+1) 档(对应 TYPES[类型].tiers[i] 阈值)的完整效果描述。
#   文本逐字对应 docs/specs/类型效果-实装规格.md (#543-554)。档位区列全部档, 主区取当前激活档。
# ══════════════════════════════════════════════════════════════════
const TYPE_EMOJI := {
	"剑": "🗡️", "奇械": "⚙️", "食物": "🍖", "盾": "🛡️", "药水": "🧪",
	"枪": "🔫", "弓箭": "🏹", "法器": "🔮", "灵物": "🐙", "遗物": "🏺",
}
const TYPE_NAME := {
	"剑": "剑系", "奇械": "奇械·魔抗", "食物": "食物·增益", "盾": "盾·守护",
	"药水": "药水·龟能", "枪": "枪·神枪手", "弓箭": "弓箭·神射手",
	"法器": "法器·法师", "灵物": "灵物·召唤", "遗物": "遗物·古物",
}
# 逐档完整效果文本 (属性全名+逐档数值写满, 不缩写)。
const TIER_DESCS := {
	"剑": [
		"每件剑额外提供 +8 攻击力 · 【剑士】携带剑者每次普攻后, 以 18%×身上剑件数 的伤害追打 1 次(5倍攻速节奏, 触发命中效果) · 【血祭】全队每个单位: 本体每损失 1% 生命 → +0.1% 攻击力",
		"每件剑额外提供 +15 攻击力 · 【剑士】追打 1 次, 伤害 25%×身上剑件数 · 【血祭】本体每损失 1% 生命 → +0.3% 攻击力",
		"每件剑额外提供 +25 攻击力 · 【剑士】追打 2 次, 每次伤害 40%×身上剑件数 · 【血祭】本体每损失 1% 生命 → +0.5% 攻击力",
	],
	"奇械": [
		"每件奇械额外提供 +4 魔法抗性 · 携带奇械者每 2.5 秒铸造 1 枚深海币",
		"每件奇械额外提供 +10 魔法抗性 · 每 2.5 秒铸 2 枚 · 【冰封】全队攻击 15% 概率冻结目标 1.5 秒(同一目标每 2.5 秒最多被冻 1 次, 解冻后 1.5 秒免疫冻结)",
		"每件奇械额外提供 +16 魔法抗性 · 每 2.5 秒铸 3 枚 · 【冰封】25% 概率 · 【僵硬】全队每段攻击为目标叠 1 层僵硬(持续 5 秒, 叠加刷新时长; 每层 -2% 攻击力, 最多 20 层)",
		"每件奇械额外提供 +23 魔法抗性 · 每 2.5 秒铸 3 枚 · 【冰封】40% 概率 · 【僵硬】同上 · 【易碎】被冻结或眩晕的敌人, 受到的伤害 +25%",
	],
	"食物": [
		"队伍每件装备为其携带者额外提供 +30 最大生命值(食物类装备双倍 +60) · 每 2.5 秒, 每件食物为携带者永久 +8 最大生命值(可无限累积)",
		"队伍每件装备 +70 最大生命值(食物双倍 +140) · 每 2.5 秒每件食物永久 +16 · 【学院】队伍全体额外 +100 最大生命值",
		"队伍每件装备 +130 最大生命值(食物双倍 +260) · 每 2.5 秒每件食物永久 +30 · 【学院】队伍全体额外 +220 最大生命值 · 【盛宴】每 2.5 秒, 全队回复已损失生命的 3%",
	],
	"盾": [
		"每件盾额外提供 +5 护甲 · 【怒气】全队每个单位每累计受到 400 点伤害, 就对最近的敌人释放一次冲击波, 造成 4% 自身最大生命值的真实伤害, 并为自己获得该伤害 20% 的护盾值 · 【圣光护盾】获得 1 件「圣光护盾」装备(可在背包自由装配, 不占装备位与单只上限; 掉档即消失): +250 最大生命, 每 3 秒为携带者生成 55 点圣光护盾值, 圣光护盾存在时反击敌人的每段伤害造成 2 点真实伤害",
		"每件盾额外提供 +13 护甲 · 【怒气】冲击波 6% · 【圣光护盾】获得第 2 件「圣光护盾」装备 · 【收殓】敌方单位阵亡时, 为最近的携带盾者提供该单位 30% 最大生命值的护盾",
		"每件盾额外提供 +22 护甲 · 【怒气】冲击波 8% · 【收殓】同上 · 【圣光·强化】盾类装备为携带者提供护盾或治疗时, 额外提供其 20% 的圣光护盾值; 且圣光护盾装备生成的所有圣盾值 +20%",
	],
	"药水": [
		"每件药水额外提供 +5 最大龟能 · 【猎物】每 2.5 秒自动将敌方当前生命值最高的 1 名单位标记为猎物(猎物死亡后下个周期重选); 全队对猎物造成的伤害 +15%",
		"每件药水额外提供 +11 最大龟能 · 【猎物】+25% · 【猎获】每击杀 1 名猎物 → 全队攻击力永久 +22(本场累积)",
		"每件药水额外提供 +20 最大龟能 · 【猎物】+40% · 【猎获】每击杀 1 名猎物 → 全队攻击力永久 +38 · 【斩首】攻击猎物时, 若其生命低于 20% → 直接处决",
	],
	"枪": [
		"每件枪额外提供 +3 护甲穿透 · 每把枪射满 4 发额外射出 1 发金弹(继承该枪全部子弹效果, 另加 60% 真实伤害; 不计入弹药计数)",
		"每件枪额外提供 +6 护甲穿透 · 每把枪射满 3 发 → 金弹(+80% 真伤) · 【火控】携带枪者额外造成 (4 + 携带者身上枪件数 × 2)% 真实伤害",
		"每件枪额外提供 +10 护甲穿透 · 每把枪射满 2 发 → 金弹(+100% 真伤) · 【火控】(6 + 携带者身上枪件数 × 3)% · 【炮台】我方阵营后方生成 1 座固定炮台: 每 2.5 秒朝敌方生命值最高者轰击, 对炮台与该敌直线上所有敌人造成 (80 + 4% 目标最大生命) 物理伤害, 并为我方最低血友军回复 30% × 造成伤害的生命",
	],
	"弓箭": [
		"每件弓箭额外提供 +9% 暴击率 与 +19% 暴击伤害 · 携带弓箭者攻击时, 目标生命百分比低于斩杀线则直接处决(斩杀线 = 4% + 暴击率 × 0.1)",
		"每件弓箭额外提供 +16% 暴击率 与 +33% 暴击伤害 · 斩杀线 = 7% + 暴击率 × 0.1 · 【腐蚀·穿透】全队攻击无视目标 20% 护甲与魔法抗性",
		"每件弓箭额外提供 +22% 暴击率 与 +45% 暴击伤害 · 斩杀线 = 10% + 暴击率 × 0.1 · 【腐蚀·穿透】无视 38% 护甲与魔法抗性 · 【腐蚀叠层】每 2.5 秒, 所有敌方单位 +1 层腐蚀(每层使其受到的伤害 +5%, 最多 5 层); 腐蚀满 5 层的敌人, 其受到伤害的 25% 转化为真实伤害",
	],
	"法器": [
		"每件法器额外提供 +4 法术穿透 与 +4 最大龟能 · 每件法器拥有独立法力条, 满 100 触发其效果(每 2.5 秒 +25 法力, 另按造成的技能伤害 ×0.1 与受到的伤害 ×0.1 累积)",
		"每件法器额外提供 +7 法术穿透 与 +6 最大龟能 · 法力条满 80 · 【潮涌】每 2.5 秒, 全队回复已损失生命的 5%",
		"每件法器额外提供 +11 法术穿透 与 +8 最大龟能 · 法力条满 60 · 【潮涌】8% · 【退潮】友军受到治疗时, 额外获得等于治疗量 30% 的护盾",
		"每件法器额外提供 +14 法术穿透 与 +10 最大龟能 · 法力条满 50 · 【潮涌】12% · 【退潮】50% · 【大潮】每 7.5 秒掀起一次大潮: 全队每个友军回复 15% 最大生命值, 并净化 2 个减益",
	],
	"灵物": [
		"每件灵物额外提供 +5% 闪避率 · 1 个无敌触手登场, 每 2.5 秒朝一名敌人拍击, 对沿途敌人造成 (4% 目标最大生命 + 55) 物理伤害 · 【亡灵】友方单位阵亡时原地召唤 1 只亡魂, 继承其 20% 攻击力与生命, 自动攻击最近敌人; 亡魂阵亡后不再循环",
		"每件灵物额外提供 +9% 闪避率 · 2 个触手 · 己方每成功闪避 1 次 → 触手立即追击 1 次(25% 伤害, 每 2.5 秒最多 3 次) · 【亡灵】继承 38% 攻击力与生命 · 亡魂阵亡后再循环 1 次(每次属性 ×0.9)",
		"每件灵物额外提供 +13% 闪避率 · 2 个触手, 拍击伤害 +30% · 闪避追击同上 · 【亡灵】继承 65% 攻击力与生命 · 亡魂阵亡后再循环 2 次",
		"每件灵物额外提供 +18% 闪避率 · 2 个触手, 拍击伤害 +60% · 闪避追击上限提到每 2.5 秒 5 次 · 【亡灵】继承 100% 攻击力与生命 · 亡魂阵亡后再循环 3 次",
	],
	"遗物": [
		"每件遗物额外提供 +3% 生命偷取 · 携带遗物者生命 >50% 时额外 +3% 攻击力; 生命 <50% 时遗物提供的生命偷取翻倍(→10%)",
		"每件遗物额外提供 +5% 生命偷取 · >50% 时 +5% 攻击力(<50% 吸血 →20%) · 【远古之力】每 2.5 秒全队永久 +4 攻击力(本场累积, 软上限 +150) · 龟蛋获得 +500 最大生命值",
		"每件遗物额外提供 +8% 生命偷取 · >50% 时 +8% 攻击力(<50% →40%) · 【远古之力】每 2.5 秒 +7 攻击力(软上限 +250) · 龟蛋 +900 最大生命值",
		"每件遗物额外提供 +10% 生命偷取 · >50% 时 +12% 攻击力(<50% →64%) · 【远古之力】每 2.5 秒 +11 攻击力(软上限 +350) · 龟蛋 +1500 最大生命值 · 【觉醒】本路战斗开打满 20 秒后, 已累积的远古之力 +50%, 之后每 2.5 秒的累积翻倍",
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
	# ★★2026-08-03 用户拍板: 按装备 id【去重】—— 带两件一模一样的剑只算 1 个羁绊数。
	#   ⇒ 顶档 == 集齐该类型的全部装备。副作用: 合成 3★ 不再扣羁绊数(见 synergy_system 的长注释)。
	#   ⚠ 背包面板与战斗侧【必须同口径】, 否则面板亮着"顶档"而打起来不是 —— 那是最难查的一类 bug。
	var seen: Dictionary = {}
	for f in team:
		if not (f is Dictionary):
			continue
		for it in f.get("_p2_equips", []):
			if not (it is Dictionary):
				continue
			var iid := str(it.get("id", ""))
			if seen.has(iid):
				continue
			seen[iid] = true
			var t := type_of(iid)
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
##
## ⛔⛔ 2026-08-03 更正两条【骗人的注释】(原文保留在下面备查):
##   ① 原注释写「主动类大部已接: 剑回响/盾怒气/枪金弹/… (各战斗钩子)」——【一条都没接】。
##      grep 实测: _swordEchoCount / _shieldRage / _gunTier / _archerExecBase … 全部零消费方。
##   ② 原注释说钩子在 `phase2_equip_runtime.sword_echo` ——【那个文件早就删了】(回合制旧引擎)。
##   ⇒ 这类"看着像事实、其实早烂了"的注释, 正是 CLAUDE.md §1 反复警告的东西。
##
## ★★而且本函数【自己就是零调用方】: 实时战斗侧的羁绊实装在
##   `scripts/systems/equip/synergy_system.gd`(2026-08-03 批4-1 新建, 用战斗的字段名)。
##   本函数用的是回合制字段名(baseAtk/baseDef/baseMr), 接上去也不会有任何效果。
##   保留它是因为里面的 flag 名与逐档口径对逐条实装还有参考价值 —— 但【不要直接调它】。
##
## 以下为原注释(记录当时的意图, 不代表现状):
##   走 base/flat 字段 (1:1 phase2_equip_runtime.apply_stats 口径, 防被 recalc 覆盖); 蛋跳过。
##   per-piece: 每件该类型装备各给一次 (同规格"X类装备额外提供Y")。
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
		# ★2026-08-03 批1: 「饰品[续航]溢出转盾」整段删除 —— 饰品类型已解散(D2), 其 healAmp/shieldAmp
		#   由用户拍板【直接消失、不补给任何类型】(D14, 原话「u2消失就好」)。代价见方案书 R19:
		#   十个类型的首档里一条治疗/护盾效果都没有, 团队续航最早要凑到法器 5 件。
		#   ⚠ 单件装备的 healAmp/shieldAmp 属性不受影响(equip_stats.gd 一个字没动)。
		# 灵物[召唤]闪避: 每件灵物 +5/9/13/18% 闪避(4 档, 方案书 §5.3)。
		#   ★上限不在这里钳 —— 战斗侧 RealtimeBattle3DScene.DODGE_CAP = 0.75 钳在 _recalc_stats 的
		#   唯一写入点(v0.18.9 修的"带 2 件 3★ 幽灵墨鱼永远打不中"就是这个), tests/verify_dodge_cap.gd 守着。
		#   这里再钳一次只会让两处上限各自漂移。
		if tier_of.has("灵物") and carries_type(f, "灵物"):
			var lt: int = clampi(int(tier_of["灵物"]) - 1, 0, 3)
			var per_dodge: int = [5, 9, 13, 18][lt]
			f["_extraDodge"] = int(f.get("_extraDodge", 0)) + per_dodge * count_type(f, "灵物")

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


# ══════════════════════════════════════════════════════════════════
# 【法器·法力系统】(类型·法器 [法师] 激活 2/4/6 → 满档 100/80/60)
#   ⚠ 铁律: 法力(mana) ≠ 龟能(energy)。法力存在独立字段 _staff_mana = {装备id: 当前值},
#   绝不读写 _energy / _maxEnergy。每件法器各自一条法力条, 互不共享, 也不碰龟能。
#   规格: docs/specs/类型效果-实装规格.md #551。
# ══════════════════════════════════════════════════════════════════

const STAFF_TYPE := "法器"
## 该 fighter 携带的全部法器装备 id (顺序与 _p2_equips 一致)。
static func staff_ids_of(f: Dictionary) -> Array:
	var out: Array = []
	if not (f is Dictionary):
		return out
	for it in f.get("_p2_equips", []):
		if it is Dictionary and type_of(str(it.get("id", ""))) == STAFF_TYPE:
			out.append(str(it.get("id", "")))
	return out
