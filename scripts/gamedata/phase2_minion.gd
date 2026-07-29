extends RefCounted

## Phase2Minion — 深海小将 补位单位生成 (壳, 1:1 设计文档 V3.2 §3「小将补位」)
##
## 用 preload 引 (不用 class_name):
##   const Minion = preload("res://scripts/gamedata/phase2_minion.gd")
##
## 规则: 每条战场开打前自动补小将, 使该路双方单位各达 3 名(前3+后3共6位).
##   Lv1 基础(2026-07-29 起写最终值·前后排分开): 前排 850生命/45攻/13甲/13抗 · 后排 770生命/55攻/9甲/9抗; 每级 ×1.05 复利.
##   前排挥砍 1.4×ATK, 后排射击 1.5×ATK.
##   某路放 0 统领 → 随机一前排小将升「深海小将精英」(整排均摊伤害). (用户 2026-06-14: 去掉"概率击杀1敌统领")
## 现状(壳): 生成【小将 fighter dict】可测; 还没接 BattleScene(补位入场/小将出手AI=基础攻击, 下一步).

## ★2026-07-29 用户「别搞这种补丁倍率，直接以最终值」+ 小将加强(前排变肉/后排变凶)。
##   旧写法是 BASE_HP 250 【×3】、BASE_ATK 30 【×1.5】—— 补丁倍率藏在 make_minion 的表达式尾部,
##   正是 CLAUDE.md 记过的坑(读表达式漏掉尾部倍率 → 文案和代码各错各的)。现在一律写最终值。
##   同时前/后排拆开: 旧版两者共用同一套基数, 只靠 atkScale(1.4/1.5) 区分, 给不了不同的生命/双抗。
# 前排(近战·肉盾定位): 生命 750→850 / 双抗 7→13 / 攻击不变
const FRONT_HP := 850
const FRONT_ATK := 45
const FRONT_DEF := 13
const FRONT_MR := 13
# 后排(远程·输出定位): 生命 750→770 / 攻击 45→55 / 双抗 7→9
const BACK_HP := 770
const BACK_ATK := 55
const BACK_DEF := 9
const BACK_MR := 9
const LEVEL_MULT := 1.05       # 每级全属性 ×1.05 复利
const FRONT_ATK_MULT := 1.4    # 前排挥砍(普攻系数·技能定义里的正经参数, 不是补丁倍率)
const BACK_ATK_MULT := 1.5     # 后排射击
# (删 ELITE_KILL_CHANCE: 用户 2026-06-14 定 — "概率击杀1敌统领"这个机制不要)


## Lv 复利系数 ×1.05^(level-1).
static func level_mult(level: int) -> float:
	return pow(LEVEL_MULT, maxi(0, level - 1))


## 小将立绘路径选取 (精英→精英皮 / 前排→砍皮 / 后排→射皮). 单一来源:
##   make_minion 建时用之 + BattleScene 槽位重算后用之 (防前/后皮没跟最终槽位). 缺图 emoji 兜底.
static func minion_img(is_elite: bool, is_back: bool) -> String:
	if is_elite:
		return "pets/minion-elite.png"
	return "pets/minion-back.png" if is_back else "pets/minion.png"


## 生成一个小将 fighter dict (战斗用精简结构; 无技能/被动, 行为=基础攻击).
##   level: 小将等级; side: "left"/"right"; slot_key: "front-0".."back-2"; is_elite: 深海小将精英.
static func make_minion(level: int, side: String, slot_key: String, is_elite: bool = false) -> Dictionary:
	var m := level_mult(level)
	var is_front := slot_key.begins_with("front")
	# 最终值 × 等级复利。前/后排各一套(用户2026-07-29)。
	var hp := int(round(float(FRONT_HP if is_front else BACK_HP) * m))
	var atk := int(round(float(FRONT_ATK if is_front else BACK_ATK) * m))
	var def_ := int(round(float(FRONT_DEF if is_front else BACK_DEF) * m))
	var mr := int(round(float(FRONT_MR if is_front else BACK_MR) * m))
	var atk_mult := FRONT_ATK_MULT if is_front else BACK_ATK_MULT
	# 基础攻击 = 复用 physical 技能类型 (单体物理, dmg = atk × atkScale). 前砍1.4 / 后射1.5.
	# 精英: 整排均摊伤害 (设计§3, 用户2026-06-14定均摊式=总÷人数). type仍physical→目标选取/AI不变(单选敌),
	#   靠 eliteRowSplit 标在 execute 分流到 _minion_elite_split 展开到【目标所在整排】.
	var basic := {
		"name": "整排挥砍" if is_elite else ("挥砍" if is_front else "射击"),
		"type": "physical", "hits": 1, "power": 0, "pierce": 0,
		"atkScale": atk_mult, "cd": 0, "cdLeft": 0, "energyCost": 0,
		"eliteRowSplit": is_elite,
		"icon": "", "brief": "", "detail": "",
	}
	return {
		"id": "minion",
		"name": "深海小将精英" if is_elite else "深海小将",
		"emoji": "🦐" if is_elite else "🐠",
		"rarity": "C",
		"side": side,
		# 美术: 深海小将立绘 (front砍/back射/elite精英); 缺则 emoji 兜底. 单一来源 minion_img() (与 BattleScene 槽位重算同口).
		"img": minion_img(is_elite, not is_front), "sprite": null,
		"_level": level,
		"_maxEnergy": 0, "_energy": 0,
		"_equippedIdxs": [], "_meleeSkills": [], "_volcanoSkills": [],
		"maxHp": hp, "hp": hp, "shield": 0,
		"baseAtk": atk, "baseDef": def_, "baseMr": mr,
		"atk": atk, "def": def_, "mr": mr,
		"crit": 0.0,
		"armorPen": 0, "armorPenPct": 0.0, "magicPen": 0, "magicPenPct": 0.0,
		"_minionAtkMult": atk_mult,    # 出手伤害系数 (前1.4/后1.5); 同步进 basic.atkScale
		"passive": null, "passiveUsedThisTurn": false,
		"skills": [basic], "_passiveSkills": [],
		"alive": true, "buffs": [], "tags": [],
		"_position": "front" if is_front else "back",
		"_slotKey": slot_key,
		"_statsDirty": false,
		"_hasRockArmor": false, "_rockLayers": 0,
		"equipment": [],
		"_isMinion": true,           # 标记: 不吃永恒buff / 不跨关继承 / 攻蛋累计归统领方
		"_isElite": is_elite,        # 整排均摊伤害 (待接战斗)
	}

