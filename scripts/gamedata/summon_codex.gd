class_name SummonCodex
extends RefCounted
## 图鉴「角色」栏 · 召唤物的【单一文案 / 数值源】(2026-11-27 · 方案书 docs/plans/20261127d-图鉴角色栏收全部单位.md)。
##
## 用户 11-27:「对于矛这个羁绊，核心是召唤物并强化技能，所以图鉴里最好龟换成角色，及游戏里的可能出现的单位，这里去描述属性，
##   所以对于羁绊里的召唤去描述可以换种方式」「百夫长没有等级，收所有单位」「(登场击飞) 这个应该作为角色的被动吧」。
##
## ★数字一律读战斗代码里的常量(SpearSynergySystem / EquipSystem …), 不手抄 —— 同 minion_codex.gd 的教训(两份手抄已经漂过)。
##   门禁 verify_codex_summon 对着常量逐个核页面上的数。
## ★属性跟着什么变, 列就是什么: 百夫长没有等级 ⇒ 列 = 长矛件数 (2) / (5) / (8) / (10); 装备召唤物 ⇒ 列 = 装备星级 ★1 / ★2 / ★3。
## ★登场效果算被动(用户 11-27); 「什么时候召唤」是召唤它的羁绊 / 装备的规则, 这里只在「来源」带过。
##
## 一页的形状 info(id, 列号):
##   name / avatar(列表头像) / portrait(立绘, 同龟页 _add_pet_portrait 认的形状) / kinds(战斗里 _spawn_summon 的种类名)
##   source {text, tab, key}(来源: 点了跳到哪一栏哪一条) / tags(签牌) / col_title / cols(列名)
##   stats [{key, label, disp}](与龟页属性方块同一套键) / stat_note(属性下一行灰字)
##   basic {name, desc} / skill {name, desc, energy}(没有就空) / passives [{name, desc}]

const IDS: Array[String] = ["centurion", "turret"]
const _P2T := preload("res://scripts/gamedata/phase2_types.gd")


static func _pct(x: float) -> String:
	var v: float = snappedf(x * 100.0, 0.01)
	return str(int(v)) if is_equal_approx(v, roundf(v)) else str(v)


static func _n(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else str(snappedf(x, 0.01))


static func cols(id: String) -> Array:
	match id:
		"centurion":
			var out: Array = []
			for t in (_P2T.TYPES.get("长矛", {}) as Dictionary).get("tiers", []):
				out.append("(%d)" % int(t))
			return out
		"turret":
			return ["★1", "★2", "★3"]
	return []


static func info(id: String, ci: int) -> Dictionary:
	match id:
		"centurion":
			return _centurion(clampi(ci, 0, cols(id).size() - 1))
		"turret":
			return _turret(clampi(ci, 0, 2))
	return {}


## 战斗里会出现的召唤物种类名 → 图鉴条目 id(门禁拿它对全仓 _spawn_summon 调用点)。
static func id_of_kind(kind: String) -> String:
	for id in IDS:
		if (info(id, 0).get("kinds", []) as Array).has(kind):
			return id
	return ""


# ─── 百夫长(长矛羁绊) ─────────────────────────────────────────────
static func _centurion(ci: int) -> Dictionary:
	var S := SpearSynergySystem
	var tier: int = ci + 1   # 第几档(1~4), 普攻 / 技能逐档叠加
	var basic: String = Lang.t("刺击目标，造成 %s%% 攻击力的物理伤害。") % _pct(1.0)
	if tier >= 2:
		basic += Lang.t("刺击时沿刺击方向推出一道冲击波，贯穿目标身后的敌人，造成 %s%% 伤害。") % _pct(S.PIERCE_BEHIND)
	if tier >= 3:
		basic += Lang.t("每次刺中使敌人失去 1 点护甲和魔抗，每个敌人至多 %s 点。") % _n(S.SHRED_CAP)
	if tier >= 4:
		basic += Lang.t("每第 %d 次攻击改为掷出长矛，飞向最远的敌人，贯穿沿途敌人，造成 %s%% 攻击力的物理伤害。") % [S.THROW_EVERY, _pct(S.THROW_COEF)]
	var skill: String = Lang.t("举盾 %s 秒，受到的伤害降低 %s%%。") % [_n(S.SHIELD_SEC), _pct(S.SHIELD_DR)]
	if tier >= 3:
		skill += Lang.t("举盾期间每 %s 秒刺击周围敌人，造成 %s%% 攻击力的魔法伤害。") % [_n(S.POKE_IV), _pct(S.POKE_COEF)]
	if tier >= 2:
		skill += Lang.t("放下盾时横扫周围敌人，造成 %s%% 攻击力的魔法伤害。") % _pct(S.SWEEP_COEF)
	if tier >= 4:
		skill += Lang.t("横扫后，我方身后冲出 %d 名持矛骑兵，各冲向一名随机敌人，撞到的每个敌人受到百夫长 %s%% 攻击力的物理伤害并被击飞。") % [S.CAV_N, _pct(S.CAV_COEF)]
	return {
		"name": "百夫长", "kinds": ["centurion"],
		"avatar": "res://assets/sprites/avatars/summon-centurion.png",
		"portrait": {"id": "__summon_centurion", "img": "vfx/eq-centurion-idle.png",
			"sprite": {"frameW": 192, "frameH": 192, "frames": 4}},
		## 待机帧 192×192 里人物只占中间约 68×123 ⇒ 按龟的 160 框放显得小一圈: 框放大到 230、中心上移到 76(脚底约 190, 不压属性方块 196)
		"portrait_box": 230.0, "portrait_cy": 76.0,
		"source": {"text": Lang.t("长矛羁绊"), "tab": "synergies", "key": "长矛"},
		"tags": [Lang.t("近战")],
		"col_title": Lang.t("长矛件数"), "cols": cols("centurion"),
		"stats": [
			{"key": "hp", "label": "生命", "disp": _n(S.HP[ci])},
			{"key": "atk", "label": "攻击", "disp": _n(S.ATK[ci])},
			{"key": "def", "label": "护甲", "disp": _n(S.RES[ci])},
			{"key": "mr", "label": "魔抗", "disp": _n(S.RES[ci])},
			{"key": "move", "label": "移速", "disp": _n(load("res://scripts/scenes/battle/battle_spawn.gd").SUMMON_DEFAULT_SPD)},
			{"key": "aspd", "label": "每秒攻击", "disp": "1.00"},
			{"key": "range", "label": "射程", "disp": _n(S.RANGE)},
		],
		"stat_note": Lang.t("我方每有一件不同的长矛，按其星级，每星使百夫长生命值与攻击力提高 %s%%。存在到被击败为止。") % _pct(S.STAR_PCT),
		"basic": {"name": "突刺", "desc": basic},
		"skill": {"name": "龟甲阵", "desc": skill, "energy": int(S.EN_MAX)},
		"passives": [{"name": "从天而降",
			"desc": Lang.t("登场时从高空落下，落地时击飞全场敌人 %s 秒，造成 %s%% 攻击力的魔法伤害。") % [_n(S.KNOCK_SEC), _pct(S.ENTRY_COEF)]}],
	}


# ─── 炮台(058 远古炮塔) ───────────────────────────────────────────
## 生命 / 攻击三档写在 eq_summons.gd 召唤那一行的字面量里(没抽常量); 这里引用同一组数, 门禁 verify_codex_summon 对着那一行核。
const TURRET_HP := [650.0, 1400.0, 2500.0]
const TURRET_ATK := [70.0, 120.0, 180.0]
const TURRET_RES := [70.0, 85.0, 100.0]


static func _turret(si: int) -> Dictionary:
	var E := EquipSystem
	return {
		"name": "炮台", "kinds": ["turret"],
		"avatar": "res://assets/sprites/pets/turret.png",
		"portrait": {"id": "__summon_turret", "img": "pets/turret.png"},
		"source": {"text": Lang.t("远古炮塔"), "tab": "equips", "key": "p2eq_058"},
		"tags": [Lang.t("远程"), Lang.t("不可移动")],
		"col_title": Lang.t("装备星级"), "cols": cols("turret"),
		"stats": [
			{"key": "hp", "label": Lang.t("生命 +%s×携带者攻击力") % _n(E.TURRET_HP_PER_ATK), "disp": _n(TURRET_HP[si])},
			{"key": "atk", "label": Lang.t("攻击 +携带者攻击力"), "disp": _n(TURRET_ATK[si])},
			{"key": "def", "label": "护甲", "disp": _n(TURRET_RES[si])},
			{"key": "mr", "label": "魔抗", "disp": _n(TURRET_RES[si])},
			{"key": "move", "label": "移速", "disp": "0"},
			{"key": "aspd", "label": "每秒攻击", "disp": "%.2f" % E.TURRET_ASPD},
			{"key": "range", "label": "射程", "disp": _n(E.TURRET_RANGE)},
		],
		"stat_note": Lang.t("登场时按携带者当时的攻击力定下生命值与攻击力，之后不再变化。每件远古炮塔各召唤一座，存在到被击败为止。"),
		"basic": {"name": "炮击", "desc": Lang.t("炮击射程内的敌人，造成 %s%% 攻击力的物理伤害，并永久获得 %s%% 暴击率，持续到本战场结束。") % [_pct(1.0), _pct(E.TURRET_CRIT_PER_SHOT)]},
		"skill": {},
		## 「携带者在炮台附近加攻速」是携带者拿到的好处, 写在远古炮塔装备里, 这里不重复(11-27)
		"passives": [
			{"name": "护卫", "desc": Lang.t("携带者存活时，炮台获得 %s 护甲与魔抗；携带者阵亡后归零。") % _n(TURRET_RES[si])},
		],
	}
