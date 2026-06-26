extends RefCounted

## Phase2Minion — 深海小将 补位单位生成 (壳, 1:1 设计文档 V3.2 §3「小将补位」)
##
## 用 preload 引 (不用 class_name):
##   const Minion = preload("res://scripts/engine/phase2_minion.gd")
##
## 规则: 每条战场开打前自动补小将, 使该路双方单位各达 3 名(前3+后3共6位).
##   Lv1 基础: 基数 250生命×3=750 / 30攻×1.5=45 / 7护甲 / 7魔抗 (×3/×1.5=用户2026-06-25补丁); 每级全属性 ×1.05 复利.
##   前排挥砍 1.4×ATK, 后排射击 1.5×ATK.
##   某路放 0 统领 → 随机一前排小将升「深海小将精英」(整排均摊伤害). (用户 2026-06-14: 去掉"概率击杀1敌统领")
## 现状(壳): 生成【小将 fighter dict】可测; 还没接 BattleScene(补位入场/小将出手AI=基础攻击, 下一步).

const BASE_HP := 250
const BASE_ATK := 30
const BASE_DEF := 7
const BASE_MR := 7
const LEVEL_MULT := 1.05       # 每级全属性 ×1.05 复利
const FRONT_ATK_MULT := 1.4    # 前排挥砍
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
	var hp := int(round(BASE_HP * m)) * 3        # 小将血量×3 (用户2026-06-25补丁)
	var atk := int(round(BASE_ATK * m * 1.5))    # 小将攻击力×1.5 (用户2026-06-25补丁)
	var def_ := int(round(BASE_DEF * m))
	var mr := int(round(BASE_MR * m))
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


## 给某一路某方补小将到 3 名: leader_count 已有统领数 → 补 (3 - leader_count) 个小将.
##   leader_count==0 → 该方一前排小将升精英 (返回里第一个小将 is_elite=true).
##   返回: 新建的小将 dict 数组 (槽位从已用之后顺延; 这里给出建议 slot_keys, 调用方可覆盖).
static func fill_lane(leader_count: int, level: int, side: String) -> Array:
	var need: int = maxi(0, 3 - leader_count)
	if need <= 0:
		return []
	var slots := ["front-0", "front-1", "front-2", "back-0", "back-1", "back-2"]
	# 已有统领默认占前排, 小将从空槽顺延 (壳: 简单按 leader_count 偏移)
	var out: Array = []
	var make_elite: bool = leader_count == 0
	for i in range(need):
		var sk: String = slots[(leader_count + i) % slots.size()]
		var elite: bool = make_elite and i == 0   # 空一路 → 第一个小将升精英
		out.append(make_minion(level, side, sk, elite))
	return out
