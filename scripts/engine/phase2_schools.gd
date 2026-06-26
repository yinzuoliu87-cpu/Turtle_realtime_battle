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
const Buffs := preload("res://scripts/engine/buffs.gd")
const StatsRecalc := preload("res://scripts/engine/stats_recalc.gd")
const Damage := preload("res://scripts/engine/damage.gd")
const _DEBUFF_TYPES := ["chilled", "frozen", "freeze", "burn", "corrode", "stiffness", "stun", "curse", "poison", "armorBreak", "healReduce"]
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

## 战斗开始: 施加该队各激活学派的【开场属性类】效果 (改 maxHp / 穿透等; 在 _build_teams 最终 recalc 前调,
## 让 recalc 折入)。目前接: 珊瑚学院(+maxHP + 碎片) / 深渊议会(腐蚀穿透)。
## 其余学派的 每回合/受击/死亡/召唤/炮台 效果 = on_round_begin / on_hit / on_death (待接, 见 docs/specs/学派效果-实装规格.md)。
static func apply_team_start(team: Array) -> void:
	for a in calc_active(team):
		var school: String = str(a.get("school", ""))
		var ti: int = clampi(int(a.get("tier", 1)) - 1, 0, 2)
		match school:
			"珊瑚学院":
				# 战斗学院: 全队 +90/100/110 maxHP + 1/2/4 珊瑚碎片(潜能, 共享, ×碎片放大待逐件珊瑚装备接)
				var hp_add: int = [90, 100, 110][ti]
				for f in team:
					if f is Dictionary and not f.get("_isEgg", false):
						f["maxHp"] = int(f.get("maxHp", 0)) + hp_add
				if not team.is_empty():
					for cf in team:
						if cf is Dictionary: cf["_coralShards"] = [1, 2, 4][ti]
			"深渊议会":
				# 腐蚀: 全队攻击无视目标 12%/22%/40% 护甲和魔抗 (damage.gd 消费 armorPenPct/magicPenPct)
				var pen: float = [0.12, 0.22, 0.40][ti]
				for f in team:
					if f is Dictionary and not f.get("_isEgg", false):
						f["armorPenPct"] = float(f.get("armorPenPct", 0.0)) + pen
						f["magicPenPct"] = float(f.get("magicPenPct", 0.0)) + pen
			"潮汐议会":
				# 退潮·治疗留盾(审计): 友军受治疗额外获 治疗量×X% 护盾 (_heal_to/_heal 消费 _tideHealShieldPct)
				var _thp: float = [0.15, 0.25, 0.35, 0.50][clampi(int(a.get("tier", 1)) - 1, 0, 3)]
				for _tf in team:
					if _tf is Dictionary and not _tf.get("_isEgg", false):
						_tf["_tideHealShieldPct"] = _thp
			"血牙帮":
				# 血祭: 全队按已损血 +ATK (实际加成由 StatsRecalc 的 _bloodFangFactor 动态算; 每损1%maxHP +0.6/1/1.5)
				var bf: float = [0.6, 1.0, 1.5][ti]
				for f in team:
					if f is Dictionary and not f.get("_isEgg", false):
						f["_bloodFangFactor"] = bf
			"极地小队":
				# 冰封: 全队攻击 15/25/40% 概率冻结目标(stun 1回合)。6档僵硬(_stiffnessStacks→stats_recalc减攻)/9档易碎(_iceShatter→damage.gd +25%) 已接 BattleScene._on_hit_chain。
				var ice_ch: float = [0.15, 0.25, 0.40][ti]
				for f in team:
					if f is Dictionary and not f.get("_isEgg", false):
						f["_iceFreezeChance"] = ice_ch
			"唤灵学会":
				# 亡灵: 友军死亡召唤亡魂(继承pct属性), 亡魂死再循环×0.9 上限cycles次。死亡钩子见 BattleScene._play_death + _spawn_undead_spirit。
				var ut: int = clampi(int(a.get("tier", 1)) - 1, 0, 4)
				var upct: float = [0.20, 0.30, 0.45, 0.65, 1.0][ut]
				var ucyc: int = [0, 1, 2, 3, 4][ut]
				for f in team:
					if f is Dictionary and not f.get("_isEgg", false):
						f["_undeadPct"] = upct
						f["_undeadCycles"] = ucyc
			"圣甲议会":
				# 圣盾: 前 1/2 个非蛋非小将单位获圣盾(+150maxHP+携带标记). 每2回合生圣光护盾(on_round_begin),
				#   护盾存在时反击真伤(BattleScene on-hit-taken, 件数×50%增幅)。5档敌亡转盾/8档治疗转盾 待接。
				var st: int = clampi(int(a.get("tier", 1)) - 1, 0, 2)
				var carriers_n: int = [1, 2, 2][st]
				var holy_cnt: int = int(a.get("count", 3))
				var placed: int = 0
				for f in team:
					if placed >= carriers_n:
						break
					if f is Dictionary and not f.get("_isEgg", false) and not f.get("_isMinion", false):
						f["maxHp"] = int(f.get("maxHp", 0)) + 150
						f["_holyShield"] = true
						f["_holyCount"] = holy_cnt
						f["_holyTier"] = st + 1
						placed += 1
			"黑礁猎团":
				# 猎杀: 全队对猎物伤害 +15/25/40%; 杀猎物→全队永久 +14/26/38 攻 + 重选; 8档处决(<20%)。
				#   猎物指定/重选/伤害增幅/处决 在 BattleScene(_hunt_pick_for_side / damage.gd / _on_hit_chain / _play_death)。
				var bt: int = clampi(int(a.get("tier", 1)) - 1, 0, 2)
				for f in team:
					if f is Dictionary and not f.get("_isEgg", false):
						f["_huntTier"] = bt + 1
						f["_huntDmgBoostPct"] = [0.15, 0.25, 0.40][bt]
						f["_huntKillAtk"] = [14, 26, 38][bt]
			"深海军械库":
				# 军火: 3/6/9 档生成 1/2/3 座炮台 (本队全员共享标记, 实体由 BattleScene 在战斗开始读 _armoryTier 生成).
				#   3档=炮台1(回合末轰击, BattleScene._armory_turret_fire); 6档=+炮台2(每回合能量护盾/弹幕循环, on_round_begin);
				#   9档=+炮台3(火控: 军火携带者额外造成 (10+5×件数)% 真实伤害 → 标 _armoryTrueDmgPct, side-end 追加真伤波).
				var amt: int = clampi(int(a.get("tier", 1)), 1, 3)         # 炮台数 = 档位
				var acount: int = int(a.get("count", 3))                  # 军火件数
				for f in team:
					if not (f is Dictionary) or f.get("_isEgg", false):
						continue
					f["_armoryTier"] = amt
					f["_armoryCount"] = acount
					# 9档火控只接通【携带军火装备】的单位
					if amt >= 3 and carries_school(f, "深海军械库"):
						f["_armoryTrueDmgPct"] = float(10 + 5 * acount)


## 每回合开始: 该队各激活学派的每回合效果 (turn = 当前回合, 1 起)。
## 接: 玄甲(全队盾; 玄甲化高一星结算见 apply_xuanjia_round, BattleScene 回合口调) / 潮汐(潮涌回血 + 每3回合大潮净化)。
## 其余(远古 +ATK累积 / 血牙 按已损血ATK / 深渊 腐蚀层) 需改 baseAtk+recalc 或伤害集成 → 后续增量。
## 返回【伤害事件列表】 [{target_idx, amount, type, vfx}] 供 BattleScene 渲染(飘字+刷血+AOE VFX),
##   否则远古/军火的 apply_raw_damage 静默扣血(下次整体刷新才显, 看着像坏了)。数值逻辑不变, 仅记录已造成伤害。
static func on_round_begin(fighters: Array, turn: int) -> Array:
	var dmg_events: Array = []   # 事件队列 (供 BattleScene._render_school_round_damage 可见化): 伤害=[{target_idx, amount, type, vfx}] / 盾·治疗·净化=[{target_idx, amount, kind:"shield"/"heal"/"purify", vfx:"shieldglow"/"healglow"}]
	for side in ["left", "right"]:
		var counted: Array = []   # 计数用: 该侧所有(含死亡, 装备在身羁绊不掉)
		var alive: Array = []     # 施效用: 存活非蛋
		for f in fighters:
			if not (f is Dictionary) or str(f.get("side", "")) != side:
				continue
			counted.append(f)
			if f.get("alive", false) and not f.get("_isEgg", false):
				alive.append(f)
		if alive.is_empty():
			continue
		for a in calc_active(counted):
			var school: String = str(a.get("school", ""))
			var tier: int = int(a.get("tier", 1))
			match school:
				"深渊议会":
					# 腐蚀: 每回合给全体敌人 +1 腐蚀层(max5, 每层 +pct% 受伤; damage.gd 消费 corrode buff)。pen 在 apply_team_start。
					var cpct: float = [0.03, 0.04, 0.06][clampi(tier - 1, 0, 2)]
					var enemy_side: String = "right" if side == "left" else "left"
					for ef in fighters:
						if not (ef is Dictionary) or str(ef.get("side", "")) != enemy_side or not ef.get("alive", false) or ef.get("_isEgg", false):
							continue
						var cb = null
						for b in ef.get("buffs", []):
							if b is Dictionary and b.get("type", "") == "corrode":
								cb = b
								break
						if cb == null:
							if not ef.has("buffs"):
								ef["buffs"] = []
							(ef["buffs"] as Array).append({"type": "corrode", "value": 1, "pct": cpct, "duration": 99})
						else:
							cb["value"] = mini(5, int(cb.get("value", 0)) + 1)
							cb["pct"] = cpct
				"圣甲议会":
					# 圣盾每2回合生圣光护盾 45×(1+0.5×件数) 给携带者 (5档敌亡转盾=_play_death; 8档治疗转盾=on_heal 待接)
					if turn > 0 and turn % 2 == 0:
						for f in alive:
							if f.get("_holyShield", false):
								var holy_amt: float = 45.0 * (1.0 + 0.5 * int(f.get("_holyCount", 3)))
								if tier >= 3:   # 8档: 圣盾提供的所有圣盾值 +20%
									holy_amt *= 1.2
								var holy_add: int = Buffs.grant_shield(f, roundi(holy_amt))
								if holy_add > 0:
									f["_holyShieldVal"] = int(f.get("_holyShieldVal", 0)) + holy_add   # 血条圣盾段(白黄亮)记账: 圣甲圣盾量单列
									dmg_events.append({"target_idx": fighters.find(f), "amount": holy_add, "kind": "shield", "vfx": "holyshieldglow"})   # 圣盾=白黄亮圣光色 (区别普通蓝盾)
				"玄甲卫队":
					var sh: int = [10, 15, 20][clampi(tier - 1, 0, 2)]
					for f in alive:
						var xj_add: int = Buffs.grant_shield(f, sh)
						if xj_add > 0:
							dmg_events.append({"target_idx": fighters.find(f), "amount": xj_add, "kind": "shield", "vfx": "shieldglow"})
				"深海军械库":
					# 军火 6档+: 炮台2 每回合产能 (100 + 20×件数). turn 奇=能量→护盾均摊全队; turn 偶=能量→弹幕魔法均摊敌全体.
					#   3档无炮台2(只回合末轰击, 在 BattleScene._armory_turret_fire). 9档火控走 _armoryTrueDmgPct (apply_team_start 已标).
					if tier < 2:
						continue
					var acount: int = int(a.get("count", 6))
					var energy: int = 100 + 20 * acount
					if turn % 2 == 1:
						# 护盾均摊全队
						var per_sh: int = maxi(1, energy / maxi(1, alive.size()))
						for f in alive:
							var arm_add: int = Buffs.grant_shield(f, per_sh)
							if arm_add > 0:
								dmg_events.append({"target_idx": fighters.find(f), "amount": arm_add, "kind": "shield", "vfx": "shieldglow"})
					else:
						# 弹幕: 该能量值【魔法】均摊敌全体存活非蛋
						var enemy_side: String = "right" if side == "left" else "left"
						var targets: Array = []
						for ef in fighters:
							if ef is Dictionary and str(ef.get("side", "")) == enemy_side and ef.get("alive", false) \
									and not ef.get("_isEgg", false) and not ef.get("_untargetable", false):
								targets.append(ef)
						if not targets.is_empty():
							var per_dmg: int = maxi(1, energy / targets.size())
							for ef in targets:
								var r_armory: Dictionary = Damage.apply_raw_damage(ef, per_dmg, "magic")
								var shown_armory: int = int(r_armory.get("hpLoss", 0)) + int(r_armory.get("shieldAbs", 0))
								if shown_armory > 0:
									dmg_events.append({"target_idx": fighters.find(ef), "amount": shown_armory, "type": "magic", "vfx": "armory"})
				"潮汐议会":
					var pct: float = [0.04, 0.07, 0.10, 0.12][clampi(tier - 1, 0, 3)]
					for f in alive:
						var lost: int = maxi(0, int(f.get("maxHp", 0)) - int(f.get("hp", 0)))
						if lost > 0:
							var tide_before: int = int(f.get("hp", 0))
							f["hp"] = mini(int(f.get("maxHp", 0)), int(f.get("hp", 0)) + Buffs.fatigue_amt(f, roundi(lost * pct)))
							var tide_healed: int = int(f["hp"]) - tide_before
							if tide_healed > 0:
								dmg_events.append({"target_idx": fighters.find(f), "amount": tide_healed, "kind": "heal", "vfx": "healglow"})
					if turn > 0 and turn % 3 == 0:   # 大潮: 每3回合 +15%maxHP + 净化 1/1/2/3 减益
						var purge: int = [1, 1, 2, 3][clampi(tier - 1, 0, 3)]
						for f in alive:
							var surge_before: int = int(f.get("hp", 0))
							f["hp"] = mini(int(f.get("maxHp", 0)), int(f.get("hp", 0)) + Buffs.fatigue_amt(f, roundi(int(f.get("maxHp", 0)) * 0.15)))
							var surge_healed: int = int(f["hp"]) - surge_before
							if surge_healed > 0:
								dmg_events.append({"target_idx": fighters.find(f), "amount": surge_healed, "kind": "heal", "vfx": "healglow"})
							var purged: int = _purify(f, purge)
							if purged > 0:
								dmg_events.append({"target_idx": fighters.find(f), "amount": purged, "kind": "purify", "vfx": "healglow"})
				"远古遗迹":
					# 古代觉醒: 每回合全队 +3/6/10 baseATK 累积(软上限+300); 满8回合觉醒(已累积×1.5 + 之后rate翻倍). 9档AOE待接.
					var rate0: int = [3, 6, 10][clampi(tier - 1, 0, 2)]
					for f in alive:
						if turn >= 8 and not f.get("_ancientAwakened", false):
							f["_ancientAwakened"] = true
							var boost: int = roundi(int(f.get("_ancientAccum", 0)) * 0.5)
							f["baseAtk"] = int(f.get("baseAtk", 0)) + boost
							f["_ancientAccum"] = int(f.get("_ancientAccum", 0)) + boost
						var rate: int = rate0 * (2 if f.get("_ancientAwakened", false) else 1)
						var cur: int = int(f.get("_ancientAccum", 0))
						var add: int = mini(rate, maxi(0, 300 - cur))
						if add > 0:
							f["baseAtk"] = int(f.get("baseAtk", 0)) + add
							f["_ancientAccum"] = cur + add
						StatsRecalc.recalc(f, alive)
					# 9档质变·远古降临: 觉醒后每回合 AOE 真伤 = 已累积远古之力 ×150% 给敌全体
					if tier >= 3:
						var aw_accum: int = 0
						for f2 in alive:
							if f2.get("_ancientAwakened", false):
								aw_accum = maxi(aw_accum, int(f2.get("_ancientAccum", 0)))
						if aw_accum > 0:
							var aoe_dmg: int = roundi(aw_accum * 1.5)
							var en_side2: String = "right" if side == "left" else "left"
							for ef in fighters:
								if ef is Dictionary and str(ef.get("side", "")) == en_side2 and ef.get("alive", false) and not ef.get("_isEgg", false) and not ef.get("_untargetable", false):
									var r_ancient: Dictionary = Damage.apply_raw_damage(ef, aoe_dmg, "true")
									var shown_ancient: int = int(r_ancient.get("hpLoss", 0)) + int(r_ancient.get("shieldAbs", 0))
									if shown_ancient > 0:
										dmg_events.append({"target_idx": fighters.find(ef), "amount": shown_ancient, "type": "true", "vfx": "ancient"})
				"血牙帮":
					# 血祭保命盾: 生命首次<30% → 获 100%ATK 护盾(每单位每场一次)。ATK加成走StatsRecalc, recalc刷新当前HP值.
					for f in alive:
						if not f.get("_bloodFangShieldUsed", false) and float(f.get("hp", 0)) < float(f.get("maxHp", 1)) * 0.3:
							f["_bloodFangShieldUsed"] = true
							var bf_add: int = Buffs.grant_shield(f, int(f.get("atk", 0)))
							if bf_add > 0:
								dmg_events.append({"target_idx": fighters.find(f), "amount": bf_add, "kind": "shield", "vfx": "shieldglow"})
						StatsRecalc.recalc(f, alive)
	return dmg_events


## 玄甲卫队[玄甲工坊] 玄甲化 (规格: 每回合开始, 随机将 1/1/2 件「费用≤2/3/4 且非3星」装备临时玄甲化:
##   本回合按【高一星级】结算其效果; 若场上无符合条件装备则不触发)。
## 实现: 临时把选中 equip 的 p2["star"] +1, 原值存 _xuanjiaOrigStar; 所有效果钩子(on_turn_begin/on_cast/on_hit)
##   读 p2["star"] → 自动按高一星结算。本回合结束前(即下回合开始本函数顶部)先还原上回合的玄甲化。
## ⚠ 仅改效果结算用的 star, 不动 base 属性(开局 apply_stats 已定); 还原幂等 (反复调安全)。
## cost_of: Callable(eid:String) -> int, 由调用方注入(BattleScene 走 DataRegistry); rng 可注入(测试确定性)。
## 返回 [{fighter, item_id, star}] 已玄甲化清单 (供 BattleScene 飘字/日志; 空=未触发)。
static func apply_xuanjia_round(fighters: Array, cost_of: Callable, rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var boosted: Array = []
	# ① 先还原【所有】单位上回合的玄甲化 (幂等; 不论本回合是否再触发)。
	for f in fighters:
		if not (f is Dictionary):
			continue
		for it in f.get("_p2_equips", []):
			if it is Dictionary and it.has("_xuanjiaOrigStar"):
				it["star"] = int(it["_xuanjiaOrigStar"])
				it.erase("_xuanjiaOrigStar")
	# ② 各侧按玄甲档随机玄甲化 N 件 (费用≤阈值 且 非3星)。
	for side in ["left", "right"]:
		var counted: Array = []   # 计数(含死亡, 装备在身羁绊不掉)
		for f in fighters:
			if f is Dictionary and str(f.get("side", "")) == side:
				counted.append(f)
		if counted.is_empty():
			continue
		var xt: int = 0
		for a in calc_active(counted):
			if str(a.get("school", "")) == "玄甲卫队":
				xt = int(a.get("tier", 0))
		if xt <= 0:
			continue
		var ti: int = clampi(xt - 1, 0, 2)
		var cost_cap: int = [2, 3, 4][ti]
		var n_boost: int = [1, 1, 2][ti]
		# 候选: 存活非蛋单位身上 费用≤cap 且 当前星<3 的 equip (引用, 直接改 star)。
		var cands: Array = []
		for f in counted:
			if not f.get("alive", false) or f.get("_isEgg", false):
				continue
			for it in f.get("_p2_equips", []):
				if not (it is Dictionary):
					continue
				if int(it.get("star", 1)) >= 3:
					continue
				if int(cost_of.call(str(it.get("id", "")))) > cost_cap:
					continue
				cands.append({"f": f, "it": it})
		# Fisher-Yates 取前 n_boost (无候选则不触发)。
		for i in range(cands.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp = cands[i]; cands[i] = cands[j]; cands[j] = tmp
		for k in range(mini(n_boost, cands.size())):
			var it: Dictionary = cands[k]["it"]
			it["_xuanjiaOrigStar"] = int(it.get("star", 1))
			it["star"] = mini(3, int(it.get("star", 1)) + 1)
			boosted.append({"fighter": cands[k]["f"], "item_id": str(it.get("id", "")), "star": int(it["star"])})
	return boosted


## 从 fighter 移除最多 n 个减益 buff (潮汐大潮净化用)。返回实际移除的减益数 (供 BattleScene 净化飘字/绿光)。
static func _purify(f: Dictionary, n: int) -> int:
	var buffs: Array = f.get("buffs", [])
	var removed: int = 0
	var i: int = 0
	while i < buffs.size() and removed < n:
		var b = buffs[i]
		if b is Dictionary and _DEBUFF_TYPES.has(str(b.get("type", ""))):
			buffs.remove_at(i)
			removed += 1
		else:
			i += 1
	return removed


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
