extends RefCounted
## 图鉴「角色」栏 · 龟技能召唤的单位 / 羁绊召唤的亡魂 / 战场单位(龟蛋、训龟大师)(2026-11-27 · 方案书 20261127d)。
## 登记表 / 公用函数 / 写法规矩见 summon_codex.gd 文件头。数字全读各系统常量。
## 属性取决于主人的(糖果炸弹 / 水晶球 / 海盗船 / 机甲)左栏写「未知」、伤害算式写「= 未知」(用户 11-27「总比填个假数字要好吧」);
##   召唤物多少血 / 攻击写在主人自己的技能文案里, 角色页不再重复(用户 11-27「那么这里就不需要再写糖果造物了吧」)。

const SC := preload("res://scripts/gamedata/summon_codex.gd")

static func cols(id: String) -> Array:
	match id:
		"wraith":
			var o2: Array = []
			for t in (SC._P2T.TYPES.get("灵物", {}) as Dictionary).get("tiers", []):
				o2.append("(%d)" % int(t))
			return o2
	return []


static func info(id: String, ci: int) -> Dictionary:
	match id:
		"candybomb": return _candybomb()
		"crystalball": return _crystalball()
		"ship": return _ship()
		"mech": return _mech()
		"wraith": return _wraith(ci)
		"egg": return _egg()
		"trainer": return _trainer()
	return {}


static func _pet_src(pet_id: String) -> Dictionary:
	var p: Dictionary = SC.owner_base(pet_id)
	return {"text": Lang.t(str(p.get("name", pet_id))), "tab": "pets", "key": pet_id}


static func _base(name: String, kinds: Array, avatar_id: String, portrait: Dictionary, source: Dictionary, tags: Array, st: Array,
		basic: Dictionary, skill: Dictionary, passives: Array) -> Dictionary:
	## 战场单位(龟蛋 / 训龟大师)不挂签牌: 定位 / 不可编入 / 来源对它们都没意义
	##   (用户 11-27「你要这个每路一颗和战场单位还有不可编入这三个东西干啥呢？」); source 传 {} 即不挂。
	var tg: Array = []
	if not source.is_empty():
		for t in tags:
			tg.append(Lang.t(str(t)))
		tg.append(Lang.t("不可编入"))
	var d := {"name": name, "kinds": kinds, "avatar": "res://assets/sprites/avatars/summon-%s.png" % avatar_id,
		"portrait": portrait, "source": source, "tags": tg, "col_title": "", "cols": [],
		"stats": st, "basic": basic, "skill": skill, "passives": passives}
	if portrait.has("_box"):
		d["portrait_box"] = float(portrait["_box"])
	if portrait.has("_cy"):
		d["portrait_cy"] = float(portrait["_cy"])
	return d


# ─── 糖果龟 · 糖果炸弹 ───
const U := "未知"


static func _candybomb() -> Dictionary:
	return _base("糖果炸弹", ["candybomb"], "candybomb", {"img": "pets/candy-bomb.png", "_box": 150.0, "_cy": 104.0}, _pet_src("candy"), ["近战坦克"],
		SC.stats(U, 0, 0, 0, 0, 0, 0),
		{}, {},
		[{"name": "甜蜜引信", "icon": "passive/summon-candy-boom-icon.png",
			"desc": "糖果炸弹每秒损失 {C:CandySystem.BOMB_DECAY_PCT%}% 最大生命值，阵亡时爆炸，造成相当于其最大生命值 {C:CandySystem.BOMB_DEATH_AOE%}% 的魔法伤害，由所有敌人平摊。"},
		 {"name": "投喂", "icon": "passive/summon-candy-feed-icon.png",
			"desc": "糖果龟施放技能时，若糖果炸弹还在，炸弹最大生命值增加糖果龟最大生命值的 {C:CandySystem.BOMB_FEED_MAXHP_PCT%}%，并回复相当于糖果龟最大生命值 {C:CandySystem.BOMB_FEED_HEAL_PCT%}% 的生命值。若炸弹已不在，召唤一枚新的糖果炸弹，生命值为糖果龟最大生命值的 {C:CandySystem.BOMB_REVIVE_HP_PCT%}%。"}])


# ─── 水晶龟 · 水晶球 ───
static func _crystalball() -> Dictionary:
	var C := CrystalSystem
	return _base("水晶球", ["crystalball"], "crystalball", {"img": "pets/crystal-ball.png", "_box": 130.0, "_cy": 100.0}, _pet_src("crystal"), ["远程法师"],
		SC.stats(U, U, 0, 0, C.ORB_MOVE, 1.0 / C.ORB_RAY_IV, C.ORB_RANGE),
		{"name": "水晶光线", "icon": "skills/summon-crystal-ray.png",
			"desc": "水晶球的攻击射出一道贯穿光线，分两段对直线上的所有敌人共造成（{C:CrystalSystem.ORB_RAY_COEF%}%×攻击力(未知) = 未知）魔法伤害，并叠加 {C:CrystalSystem.ORB_RAY_STACKS} 层结晶印记。"}, {},
		[])


# ─── 海盗龟 · 海盗船 ───
static func _ship() -> Dictionary:
	var P := PirateSystem
	return _base("海盗船", ["ship"], "ship", {"img": "skills/pirate-ship.png", "_box": 200.0, "_cy": 96.0}, _pet_src("pirate"), ["远程坦克"],
		SC.stats(U, U, 0, 0, P.SHIP_MOVE, P.SHIP_ASPD, "全场"),
		{"name": "舷炮", "icon": "skills/summon-ship-broadside.png",
			"desc": "海盗船的攻击造成（{C:PirateSystem.SHIP_SHOT_COEF%}%×攻击力(未知) = 未知）物理伤害。"}, {},
		[{"name": "破浪登场", "icon": "passive/summon-ship-ram-icon.png",
			"desc": "海盗船登场时冲锋撞击目标，对其附近的敌人造成（{C:PirateSystem.SHIP_CHARGE_COEF%}%×海盗龟攻击力(未知) = 未知）魔法伤害并击飞 {C:PirateSystem.SHIP_CHARGE_STUN} 秒。"}])


# ─── 赛博龟 · 机甲 ───
## 属性跟着赛博龟的等级与阵亡时的浮游炮数走(公式在赛博龟被动里) ⇒ 生命 / 攻击 / 双抗都写「未知」, 不设选择牌
##   (第一版拿浮游炮数当列, 用户 11-27「机甲肯定不能用浮游炮数，这肯定是不对的」)。
static func _mech() -> Dictionary:
	var Y := CyberSystem
	return _base("机甲", ["mech"], "mech", {"img": "pets/mech.png", "_box": 180.0, "_cy": 96.0}, _pet_src("cyber"), ["近战坦克"],
		SC.stats(U, U, U, U, Y.MECH_MOVE, Y.MECH_ASPD, Y.MECH_RANGE),
		{"name": "机甲重拳", "icon": "skills/summon-mech-punch.png", "desc": SC.basic_line_unknown("机甲")}, {},
		[{"name": "歼灭炮", "icon": "passive/summon-mech-blast-icon.png",
			"desc": "机甲每 {C:CyberSystem.MECH_BLAST_CD} 秒朝生命值最低的敌人开一炮，造成（{C:CyberSystem.MECH_BLAST_COEF%}%×攻击力(未知) = 未知）物理伤害。"}])


# ─── 灵物羁绊 · 亡魂(列 = 灵物件数) ───
## 属性整份按阵亡单位 ⇒ 左栏写比例。再生衰减按最初阵亡单位算(spirit_synergy_system 11-27 修)。
static func _wraith(ci: int) -> Dictionary:
	var W := SpiritSynergySystem
	var k: int = clampi(ci, 0, W.WRAITH_INHERIT.size() - 1)
	var ps: Array = [{"name": "亡灵", "icon": "passive/summon-wraith-rise-icon.png",
		"desc": Lang.t("我方单位阵亡时化为亡魂，继承其 {C:SpiritSynergySystem.WRAITH_INHERIT[%d]%%}%% 的最大生命值与攻击力，没有护甲与魔抗。召唤物阵亡不会化为亡魂。") % k}]
	if int(W.WRAITH_LOOPS[k]) > 0:
		ps.append({"name": "轮回", "icon": "passive/summon-wraith-loop-icon.png",
			"desc": Lang.t("亡魂阵亡后会再次化为亡魂，至多 {C:SpiritSynergySystem.WRAITH_LOOPS[%d]} 次，每次继承的比例变为上一次的 {C:SpiritSynergySystem.WRAITH_DECAY%%}%%。") % k})
	var d := _base("亡魂", ["wraith"], "wraith", {"img": "pets/wraith.png", "_box": 150.0, "_cy": 100.0},
		{"text": Lang.t("灵物羁绊"), "tab": "synergies", "key": "灵物"}, ["近战斗士"],
		SC.stats(SC._pct(W.WRAITH_INHERIT[k]) + "%", SC._pct(W.WRAITH_INHERIT[k]) + "%", 0, 0, BattleSpawn.SUMMON_DEFAULT_SPD,
			1.0 / BattleSpawn.SUMMON_DEFAULT_IV, BattleSpawn.SUMMON_DEFAULT_RANGE, {"hp": "阵亡者生命", "atk": "阵亡者攻击"}),
		{"name": "幽魂爪", "icon": "skills/summon-wraith-claw.png", "desc": "亡魂的攻击造成 {C:BasicConsts.DEFAULT_BASIC_COEF%}% 攻击力的物理伤害。"}, {},
		ps)
	d["col_title"] = Lang.t("灵物件数")
	d["cols"] = cols("wraith")
	return d


# ─── 战场单位 · 龟蛋 ───
## 左栏 = 基础值(不含等级那一份); 等级加成写成被动【成长】(用户 11-27「这个东西是有基础生命值的」「这里已经有三千的基础生命值了，所以你这里可以说龟蛋额外获得」)。
## 路名按用户定的全称: 上路战场 / 下路战场 / 终极战场(memory project-lane-names; 11-27「定局那一路上…你要按规矩来行不行啊」)。
static func _egg() -> Dictionary:
	return _base("龟蛋", [], "egg", {"img": "pets/egg.png", "sprite": {"frameW": 79, "frameH": 80, "frames": 3}, "_box": 150.0, "_cy": 104.0},
		{}, [],
		SC.stats(DualLaneFlow.EGG_HP_BASE, 0, BattleSpawn.EGG_RES_BASE, BattleSpawn.EGG_RES_BASE, 0, 0, 0),
		{}, {},
		[{"name": "围栏", "icon": "passive/summon-egg-fence-icon.png",
			"desc": "每个战场开始时，龟蛋处于围栏保护中：不可被选取，不受范围伤害，并额外获得 {C:RealtimeBattle3DScene.EGG_FENCE_RES} 护甲和魔抗。己方单位全部阵亡后，围栏消失。"},
		 {"name": "坚壳", "icon": "passive/summon-egg-shell-icon.png",
			"desc": "龟蛋免疫控制与斩杀，生命值在上路战场、下路战场和终极战场之间延续，不会回满。"},
		 {"name": "成长", "icon": "passive/summon-egg-grow-icon.png",
			"desc": "龟蛋额外获得（{C:DualLaneFlow.EGG_HP_PER_LV}×等级）最大生命值、（{C:BattleSpawn.EGG_RES_PER_LV}×等级）护甲和（{C:BattleSpawn.EGG_RES_PER_LV}×等级）魔抗。"},
		 {"name": "决战", "icon": "passive/summon-egg-final-icon.png",
			"desc": "在终极战场，或一方已赢下上路战场时的下路战场，围栏消失后龟蛋受到 {C:RealtimeBattle3DScene.EGG_FINAL_DMG_MULT} 倍伤害，并每秒损失 {C:RealtimeBattle3DScene.EGG_SELFLOSS_PCT%}% 最大生命值。"}])


# ─── 战场单位 · 训龟大师 ───
## 用户 11-27: 形象用像素风问号(训龟大师的形象玩家自己选, tools/assetgen/trainer_unknown.py); 不要「携带技能」选择牌和各技能
##   (训龟大师有专门的配置页展示全部技能); 只写【旁观者】(末尾一句可以携带一个独特的技能) + 【投石】。
static func _trainer() -> Dictionary:
	return _base("训龟大师", [], "trainer", {"img": "trainer/trainer-unknown.png", "_box": 150.0, "_cy": 100.0},
		{}, [],
		SC.stats("—", RealtimeBattle3DScene.TRAINER_ATK, "—", "—", 0, 1.0 / RealtimeBattle3DScene.TRAINER_ATK_INTERVAL, RealtimeBattle3DScene.TRAINER_RANGE),
		{"name": "投石", "icon": "skills/summon-trainer-stone.png",
			"desc": "训龟大师朝最近的敌人投掷石头，每块石头造成（{C:BasicConsts.DEFAULT_BASIC_COEF%}%×攻击力({ATK}) = {N:BasicConsts.DEFAULT_BASIC_COEF*ATK}）物理伤害。"},
		{},
		[{"name": "旁观者", "icon": "passive/summon-trainer-aloof-icon.png",
			"desc": "训龟大师站在场边，不可被选取，免疫一切伤害与效果。训龟大师可以携带一个独特的技能。"}])
