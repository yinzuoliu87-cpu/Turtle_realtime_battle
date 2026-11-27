extends RefCounted
## 图鉴「角色」栏 · 龟技能召唤的单位 / 羁绊召唤的亡魂 / 战场单位(龟蛋、训龟大师)(2026-11-27 · 方案书 20261127d)。
## 登记表 / 公用函数 / 写法规矩见 summon_codex.gd 文件头。数字全读各系统常量。
## 按主人比例的(糖果炸弹 / 水晶球 / 海盗船 / 机甲)左栏按 1 级主人算(同龟页 / 小将页按 1 级显示), 被动里写比例。

const SC := preload("res://scripts/gamedata/summon_codex.gd")
const _TRAINER_CFG := preload("res://scripts/scenes/TrainerConfigScene.gd")

## 机甲的列: 赛博龟阵亡时的浮游炮数(上限 CyberSystem.DRONE_CAP)
const MECH_DRONES := [5, 10, 15, 20]


static func cols(id: String) -> Array:
	match id:
		"mech":
			var out: Array = []
			for n in MECH_DRONES:
				out.append("%d" % int(n))
			return out
		"wraith":
			var o2: Array = []
			for t in (SC._P2T.TYPES.get("灵物", {}) as Dictionary).get("tiers", []):
				o2.append("(%d)" % int(t))
			return o2
		"trainer":
			var o3: Array = []
			for sk in _TRAINER_CFG.SKILLS:
				o3.append(str(sk["name"]))
			return o3
	return []


static func info(id: String, ci: int) -> Dictionary:
	match id:
		"candybomb": return _candybomb()
		"crystalball": return _crystalball()
		"ship": return _ship()
		"mech": return _mech(ci)
		"minion": return _minion()
		"wraith": return _wraith(ci)
		"egg": return _egg()
		"trainer": return _trainer(ci)
	return {}


static func _pet_src(pet_id: String) -> Dictionary:
	var p: Dictionary = SC.owner_base(pet_id)
	return {"text": Lang.t(str(p.get("name", pet_id))), "tab": "pets", "key": pet_id}


static func _base(name: String, kinds: Array, avatar_id: String, portrait: Dictionary, source: Dictionary, tags: Array, st: Array,
		basic: Dictionary, skill: Dictionary, passives: Array) -> Dictionary:
	var tg: Array = []
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
static func _candybomb() -> Dictionary:
	var C := CandySystem
	var o: Dictionary = SC.owner_base("candy")
	return _base("糖果炸弹", ["candybomb"], "candybomb", {"img": "pets/candy-bomb.png", "_box": 150.0, "_cy": 104.0}, _pet_src("candy"), ["近战坦克"],
		SC.stats(float(o.get("hp", 0)) * C.BOMB_HP_PCT, 0, 0, 0, 0, 0, 0),
		{}, {},
		[{"name": "糖果造物", "icon": "passive/summon-candy-make-icon.png",
			"desc": "糖果炸弹登场时的生命值为糖果龟最大生命值的 {C:CandySystem.BOMB_HP_PCT%}%，不移动、不攻击，攻击力、护甲与魔抗均为 0。左侧按 1 级糖果龟计算。"},
		 {"name": "糖衣融化", "icon": "passive/summon-candy-melt-icon.png",
			"desc": "糖果炸弹每秒损失 {C:CandySystem.BOMB_DECAY_PCT%}% 最大生命值。"},
		 {"name": "投喂", "icon": "passive/summon-candy-feed-icon.png",
			"desc": "糖果龟施放技能时，若糖果炸弹还在，炸弹最大生命值增加糖果龟最大生命值的 {C:CandySystem.BOMB_FEED_MAXHP_PCT%}%，并回复糖果龟最大生命值 {C:CandySystem.BOMB_FEED_HEAL_PCT%}% 的生命值。若炸弹已不在，召唤一枚新的糖果炸弹，生命值为糖果龟最大生命值的 {C:CandySystem.BOMB_REVIVE_HP_PCT%}%。"},
		 {"name": "甜蜜爆炸", "icon": "passive/summon-candy-boom-icon.png",
			"desc": "糖果炸弹阵亡时爆炸，造成相当于其最大生命值 {C:CandySystem.BOMB_DEATH_AOE%}% 的魔法伤害，平均分给所有敌人。"}])


# ─── 水晶龟 · 水晶球 ───
static func _crystalball() -> Dictionary:
	var C := CrystalSystem
	var o: Dictionary = SC.owner_base("crystal")
	return _base("水晶球", ["crystalball"], "crystalball", {"img": "pets/crystal-ball.png", "_box": 130.0, "_cy": 100.0}, _pet_src("crystal"), ["远程法师"],
		SC.stats(float(o.get("hp", 0)) * C.ORB_HP_PCT, float(o.get("atk", 0)), 0, 0, C.ORB_MOVE, 1.0 / C.ORB_RAY_IV, C.ORB_RANGE),
		{"name": "水晶射线", "icon": "skills/summon-crystal-ray.png",
			"desc": "水晶球每 {C:CrystalSystem.ORB_RAY_IV} 秒朝最近的敌人射出一道贯穿射线，共造成（{C:CrystalSystem.ORB_RAY_COEF%}%×攻击力({ATK}) = {M:CrystalSystem.ORB_RAY_COEF*ATK}）魔法伤害，并给命中的敌人叠加 {C:CrystalSystem.ORB_RAY_STACKS} 层水晶，与水晶龟叠的水晶共用。"}, {},
		[{"name": "水晶造物", "icon": "passive/summon-crystal-make-icon.png",
			"desc": "水晶球的生命值为水晶龟最大生命值的 {C:CrystalSystem.ORB_HP_PCT%}%，攻击力与水晶龟相同，没有护甲与魔抗。水晶龟阵亡后水晶球继续战斗。左侧按 1 级水晶龟计算。"}])


# ─── 海盗龟 · 海盗船 ───
static func _ship() -> Dictionary:
	var P := PirateSystem
	var o: Dictionary = SC.owner_base("pirate")
	return _base("海盗船", ["ship"], "ship", {"img": "skills/pirate-ship.png", "_box": 200.0, "_cy": 96.0}, _pet_src("pirate"), ["近战坦克"],
		SC.stats(float(o.get("hp", 0)) * P.SHIP_HP_SCALE, float(o.get("atk", 0)) * P.SHIP_ATK_SCALE, 0, 0, P.SHIP_MOVE, P.SHIP_ASPD, P.SHIP_RANGE),
		{"name": "舷炮", "icon": "skills/summon-ship-broadside.png",
			"desc": "海盗船每 {C:PirateSystem.SHIP_SHOT_CD} 秒朝最近的敌人开一炮，不论远近，造成（{C:PirateSystem.SHIP_SHOT_COEF%}%×攻击力({ATK}) = {N:PirateSystem.SHIP_SHOT_COEF*ATK}）物理伤害。"}, {},
		[{"name": "破浪登场", "icon": "passive/summon-ship-ram-icon.png",
			"desc": "海盗船登场时冲进战场，对落点附近的敌人造成（{C:PirateSystem.SHIP_CHARGE_COEF%}%×海盗龟攻击力({ATK}) = {M:PirateSystem.SHIP_CHARGE_COEF*ATK}）魔法伤害，将其击退并眩晕 {C:PirateSystem.SHIP_CHARGE_STUN} 秒。"},
		 {"name": "海盗造物", "icon": "passive/summon-ship-make-icon.png",
			"desc": "海盗船的生命值为海盗龟最大生命值的 {C:PirateSystem.SHIP_HP_SCALE%}%，攻击力为海盗龟攻击力的 {C:PirateSystem.SHIP_ATK_SCALE%}%，没有护甲与魔抗。海盗船沉没后不会再召唤。左侧按 1 级海盗龟计算。"}])


# ─── 赛博龟 · 机甲(列 = 赛博龟阵亡时的浮游炮数) ───
static func _mech(ci: int) -> Dictionary:
	var Y := CyberSystem
	var n: float = float(MECH_DRONES[clampi(ci, 0, MECH_DRONES.size() - 1)])
	var lv := 1.0
	var d := _base("机甲", ["mech"], "mech", {"img": "pets/mech.png", "_box": 180.0, "_cy": 96.0}, _pet_src("cyber"), ["近战坦克"],
		SC.stats((Y.MECH_HP_BASE + Y.MECH_HP_PER_LV * lv) * n, (Y.MECH_ATK_BASE + Y.MECH_ATK_PER_LV * lv) * n,
			Y.MECH_DEF_BASE + Y.MECH_DEF_PER_LV * lv, Y.MECH_DEF_BASE + Y.MECH_DEF_PER_LV * lv, Y.MECH_MOVE, Y.MECH_ASPD, Y.MECH_RANGE),
		{"name": "机甲重拳", "icon": "skills/summon-mech-punch.png", "desc": SC.basic_line("机甲")}, {},
		[{"name": "浮游炮合体", "icon": "passive/summon-mech-merge-icon.png",
			"desc": "赛博龟阵亡时，浮游炮汇聚组装成机甲，组装 {C:CyberSystem.MECH_ASSEMBLE_SEC} 秒，期间无敌且不能被选为目标。生命值 =（{C:CyberSystem.MECH_HP_BASE} + {C:CyberSystem.MECH_HP_PER_LV} × 等级）× 浮游炮数，攻击力 =（{C:CyberSystem.MECH_ATK_BASE} + {C:CyberSystem.MECH_ATK_PER_LV} × 等级）× 浮游炮数，护甲和魔抗 = {C:CyberSystem.MECH_DEF_BASE} + {C:CyberSystem.MECH_DEF_PER_LV} × 等级。左侧按 1 级赛博龟计算。"},
		 {"name": "歼灭炮", "icon": "passive/summon-mech-blast-icon.png",
			"desc": "每 {C:CyberSystem.MECH_BLAST_CD} 秒朝当前生命值最低的敌人连开两炮，共造成（{C:CyberSystem.MECH_BLAST_COEF%}%×攻击力({ATK}) = {N:CyberSystem.MECH_BLAST_COEF*ATK}）物理伤害。"}])
	d["col_title"] = Lang.t("浮游炮数")
	d["cols"] = cols("mech")
	return d


# ─── 缩头乌龟 · 随从(随机一只 A / B / C 级龟) ───
## 龟种随机 ⇒ 左栏写比例(同蛋糕礼盒); 立绘放小龟当示意(随从就是一只真龟)。
static func _minion() -> Dictionary:
	var H := HidingSystem
	var basic: Dictionary = SC.owner_base("basic")
	var por: Dictionary = {"img": str(basic.get("img", "")), "sprite": basic.get("sprite", {}), "id": "basic"}
	return _base("随从", ["minion"], "minion", por, _pet_src("hiding"), ["随机龟种"],
		SC.stats(SC._pct(H.MINION_HP_SCALE) + "%", SC._pct(H.MINION_ATK_SCALE) + "%", "100%", "100%", "同原龟", "同原龟", "同原龟",
			{"hp": "原龟生命", "atk": "原龟攻击", "def": "原龟护甲", "mr": "原龟魔抗"}),
		{"name": "原龟普攻", "icon": "skills/summon-minion-basic.png", "desc": "随从使用原龟的普通攻击。"}, {},
		[{"name": "喊龟", "icon": "passive/summon-minion-call-icon.png",
			"desc": "缩头乌龟登场时随机喊来一只 A、B、C 级龟作随从，生命值为原龟的 {C:HidingSystem.MINION_HP_SCALE%}%，攻击力为原龟的 {C:HidingSystem.MINION_ATK_SCALE%}%，护甲、魔抗与暴击率与原龟相同，随缩头乌龟的等级成长。随从带着原龟的被动与一个技能，缩头乌龟阵亡时随从一同离场。"}])


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
static func _egg() -> Dictionary:
	var lv := 1
	var res: float = BattleSpawn.EGG_RES_BASE + BattleSpawn.EGG_RES_PER_LV * float(lv)
	return _base("龟蛋", [], "egg", {"img": "pets/egg.png", "sprite": {"frameW": 79, "frameH": 80, "frames": 3}, "_box": 150.0, "_cy": 104.0},
		{"text": Lang.t("战场单位"), "tab": "", "key": ""}, ["每路一颗"],
		SC.stats(DualLaneFlow.egg_max_for(lv), 0, res, res, 0, 0, 0),
		{}, {},
		[{"name": "围栏", "icon": "passive/summon-egg-fence-icon.png",
			"desc": "开打时龟蛋被围栏护着，不能被选为目标，范围伤害也打不到，并额外获得 {C:RealtimeBattle3DScene.EGG_FENCE_RES} 护甲和魔抗。己方单位全部倒下后围栏才会倒下。"},
		 {"name": "坚壳", "icon": "passive/summon-egg-shell-icon.png",
			"desc": "龟蛋免疫控制、斩杀与嘲讽。龟蛋的生命值在上路、下路和决胜场之间延续，不会回满。"},
		 {"name": "成长", "icon": "passive/summon-egg-grow-icon.png",
			"desc": "龟蛋的最大生命值为 {C:DualLaneFlow.EGG_HP_BASE} + {C:DualLaneFlow.EGG_HP_PER_LV} × 等级，护甲和魔抗为 {C:BattleSpawn.EGG_RES_BASE} + {C:BattleSpawn.EGG_RES_PER_LV} × 等级。左侧按 1 级计算。"},
		 {"name": "定局", "icon": "passive/summon-egg-final-icon.png",
			"desc": "定局的那一路上，围栏倒下后龟蛋受到的伤害 ×{C:RealtimeBattle3DScene.EGG_FINAL_DMG_MULT}，并每 {C:RealtimeBattle3DScene.EGG_SELFLOSS_IV} 秒损失 {C:RealtimeBattle3DScene.EGG_SELFLOSS_PCT%}% 最大生命值。"}])


# ─── 战场单位 · 训龟大师(列 = 携带的技能, N 选 1) ───
## 用户 10-31「不应该受到任何影响，就是个装饰的地位，丢点技能」; 11-27「训龟大师收」。技能文案 / 图标与训龟大师配置页同一份(TrainerConfigScene.SKILLS)。
static func _trainer(ci: int) -> Dictionary:
	var sks: Array = _TRAINER_CFG.SKILLS
	var sk: Dictionary = sks[clampi(ci, 0, sks.size() - 1)]
	var icon: String = str(sk.get("icon", "")).trim_prefix("res://assets/sprites/")
	var ps: Array = [{"name": "旁观者", "icon": "passive/summon-trainer-aloof-icon.png",
		"desc": "训龟大师站在场边，不会被选为目标，免疫一切伤害与效果。"}]
	var skill: Dictionary = {}
	if str(sk.get("kind", "")) == "被动":
		ps.append({"name": str(sk["name"]), "icon": icon, "desc": str(sk["desc"])})
	else:
		var cd: float = float((RealtimeBattle3DScene.TRAINER_SKILLS.get(str(sk["id"]), {}) as Dictionary).get("cd", 0.0))
		skill = {"name": str(sk["name"]), "icon": icon, "desc": str(sk["desc"]), "energy": 0, "cd": cd}
	var d := _base("训龟大师", [], "trainer", {"img": "trainer/trainer-villager.png", "_box": 150.0, "_cy": 100.0},
		{"text": Lang.t("战场单位"), "tab": "", "key": ""}, ["装饰"],
		SC.stats("—", RealtimeBattle3DScene.TRAINER_ATK, "—", "—", 0, 1.0 / RealtimeBattle3DScene.TRAINER_ATK_INTERVAL, RealtimeBattle3DScene.TRAINER_RANGE),
		{"name": "投石", "icon": "skills/summon-trainer-stone.png", "desc": "训龟大师朝最近的敌人扔石头，每块石头造成 1 点伤害。"},
		skill, ps)
	d["col_title"] = Lang.t("携带技能")
	d["cols"] = cols("trainer")
	return d
