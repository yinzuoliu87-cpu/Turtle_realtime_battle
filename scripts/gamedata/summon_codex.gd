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
## 文案照小将模板(minion_codex.gd): 伤害写「（倍率×攻击力({ATK}) = 结果）」, 物理用 {N:}、魔法用 {M:}, 倍率读 {C:} 常量;
##   图鉴按左栏当前属性现算(SkillText.render_bbcode, ctx 的 ATK = 选中那一档的攻击力)。
## 用户 11-27: 被动 / 攻击 / 技能要照模板、有图标; 「从天而降」名字不好; 加成写成被动, 不要左下那行说明。
## 图标: tools/assetgen/summon_icons_1127.py(参考研究 docs/studies/20261127-参考-召唤物技能图标.md), 源文件 tools/assetgen/ase/summon_icons/*.aseprite。
const _SP := "SpearSynergySystem"


static func _centurion(ci: int) -> Dictionary:
	var S := SpearSynergySystem
	var tier: int = ci + 1   # 第几档(1~4), 攻击 / 技能逐档叠加
	var basic: String = "百夫长的攻击造成（{C:BasicConsts.DEFAULT_BASIC_COEF%}%×攻击力({ATK}) = {N:BasicConsts.DEFAULT_BASIC_COEF*ATK}）物理伤害。"
	if tier >= 2:
		basic += "刺击时沿刺击方向推出一道冲击波，贯穿目标身后的敌人，造成（{C:%s.PIERCE_BEHIND%%}%%×攻击力({ATK}) = {N:%s.PIERCE_BEHIND*ATK}）物理伤害。" % [_SP, _SP]
	if tier >= 3:
		basic += "每次刺中使敌人失去 1 点护甲和魔抗，每个敌人至多 {C:%s.SHRED_CAP} 点。" % _SP
	if tier >= 4:
		basic += "每第 {C:%s.THROW_EVERY} 次攻击改为掷出长矛，飞向最远的敌人，贯穿沿途敌人，造成（{C:%s.THROW_COEF%%}%%×攻击力({ATK}) = {N:%s.THROW_COEF*ATK}）物理伤害。" % [_SP, _SP, _SP]
	var skill: String = "百夫长举盾 {C:%s.SHIELD_SEC} 秒，受到的伤害降低 {C:%s.SHIELD_DR%%}%%。" % [_SP, _SP]
	if tier >= 3:
		skill += "举盾期间每 {C:%s.POKE_IV} 秒刺击周围敌人，造成（{C:%s.POKE_COEF%%}%%×攻击力({ATK}) = {M:%s.POKE_COEF*ATK}）魔法伤害。" % [_SP, _SP, _SP]
	if tier >= 2:
		skill += "放下盾时横扫周围敌人，造成（{C:%s.SWEEP_COEF%%}%%×攻击力({ATK}) = {M:%s.SWEEP_COEF*ATK}）魔法伤害。" % [_SP, _SP]
	if tier >= 4:
		skill += "横扫后，我方身后冲出 {C:%s.CAV_N} 名持矛骑兵，各冲向一名随机敌人，撞到的每个敌人受到（{C:%s.CAV_COEF%%}%%×攻击力({ATK}) = {N:%s.CAV_COEF*ATK}）物理伤害并被击飞。" % [_SP, _SP, _SP]
	return {
		"name": "百夫长", "kinds": ["centurion"],
		"avatar": "res://assets/sprites/avatars/summon-centurion.png",
		"portrait": {"id": "__summon_centurion", "img": "vfx/eq-centurion-idle.png",
			"sprite": {"frameW": 192, "frameH": 192, "frames": 4}},
		## 待机帧 192×192 里人物只占中间约 68×123 ⇒ 按龟的 160 框放显得小一圈: 框放大到 230、中心上移到 76(脚底约 190, 不压属性方块 196)
		"portrait_box": 230.0, "portrait_cy": 76.0,
		"source": {"text": Lang.t("长矛羁绊"), "tab": "synergies", "key": "长矛"},
		"tags": [Lang.t("近战斗士"), Lang.t("不可编入")],   # 定位用龟的十种叫法(turtle_stats.ROLE_SPEC); 用户 11-26「高血量中等输出的战士」
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
		"basic": {"name": "突刺", "icon": "skills/summon-cent-thrust.png", "desc": basic},
		"skill": {"name": "龟甲阵", "icon": "skills/summon-cent-guard.png", "desc": skill, "energy": int(S.EN_MAX)},
		"passives": [
			{"name": "军团天降", "icon": "passive/summon-cent-land-icon.png",
				"desc": "百夫长登场时从高空落下，落地时击飞全场敌人 {C:%s.KNOCK_SEC} 秒，造成（{C:%s.ENTRY_COEF%%}%%×攻击力({ATK}) = {M:%s.ENTRY_COEF*ATK}）魔法伤害。" % [_SP, _SP, _SP]},
			{"name": "众矛之力", "icon": "passive/summon-cent-spears-icon.png",
				"desc": "我方每有一件不同的长矛，按其星级每星使百夫长生命值与攻击力提高 {C:%s.STAR_PCT%%}%%。" % _SP},
		],
	}


# ─── 炮台(058 远古炮塔) ───────────────────────────────────────────
## 生命 / 攻击三档写在 eq_summons.gd 召唤那一行的字面量里(没抽常量); 这里引用同一组数, 门禁 verify_codex_summon 对着那一行核。
## 左栏只写基础值; 携带者攻击力带来的加成写成被动【火力同调】(用户 11-27「左边就写一千四百生命，然后右边被动写这个炮台额外获得多少」)。
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
		"tags": [Lang.t("远程射手"), Lang.t("不可编入")],   # 不可移动看左栏移速 0, 不另起签牌(同小将页三块签牌)
		"col_title": Lang.t("装备星级"), "cols": cols("turret"),
		"stats": [
			{"key": "hp", "label": "生命", "disp": _n(TURRET_HP[si])},
			{"key": "atk", "label": "攻击", "disp": _n(TURRET_ATK[si])},
			{"key": "def", "label": "护甲", "disp": _n(TURRET_RES[si])},
			{"key": "mr", "label": "魔抗", "disp": _n(TURRET_RES[si])},
			{"key": "move", "label": "移速", "disp": "0"},
			{"key": "aspd", "label": "每秒攻击", "disp": "%.2f" % E.TURRET_ASPD},
			{"key": "range", "label": "射程", "disp": _n(E.TURRET_RANGE)},
		],
		"basic": {"name": "炮击", "icon": "skills/summon-turret-shell.png",
			"desc": "炮台的攻击造成（{C:BasicConsts.DEFAULT_BASIC_COEF%}%×攻击力({ATK}) = {N:BasicConsts.DEFAULT_BASIC_COEF*ATK}）物理伤害，并使炮台永久获得 {C:EquipSystem.TURRET_CRIT_PER_SHOT%}% 暴击率，持续到本战场结束。"},
		"skill": {},
		"passives": [
			{"name": "火力同调", "icon": "passive/summon-turret-link-icon.png",
				"desc": "炮台登场时，额外获得相当于携带者攻击力 {C:EquipSystem.TURRET_HP_PER_ATK} 倍的生命值，以及等同于携带者攻击力的攻击力。"},
			{"name": "护卫", "icon": "passive/summon-turret-ward-icon.png",
				"desc": "携带者存活时，炮台获得 %s 护甲与魔抗，携带者阵亡后降为 0。" % _n(TURRET_RES[si])},
		],
	}
