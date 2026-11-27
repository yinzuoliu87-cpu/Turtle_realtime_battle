extends RefCounted
## 图鉴「角色」栏 · 装备召唤的单位(2026-11-27 · 方案书 20261127d)。登记表 / 公用函数 / 写法规矩见 summon_codex.gd 文件头。
## 列 = 装备星级 ★1 / ★2 / ★3(小木斧 = 进化形态)。数字全读各装备系统的常量(召唤行里的字面量 11-27 已提成常量, 值不变)。

const SC := preload("res://scripts/gamedata/summon_codex.gd")

const _IDS := ["skeleton", "worm", "bear", "turret", "cakebox", "pistol", "medtower", "axe",
	"cannon", "remote_bomb", "katana", "shadow_ninja", "skel_warrior", "skel_mage", "skel_priest", "mask_lion"]


static func cols(id: String) -> Array:
	if id == "axe":
		var out: Array = []
		for s in AxeEvolution.STAGES:
			out.append(str(s["name"]))
		for f in AxeEvolution.FINALS:
			out.append(str(f["name"]))
		return out
	return SC.star_cols() if _IDS.has(id) else []


static func info(id: String, ci: int) -> Dictionary:
	match id:
		"skeleton": return _skeleton(ci)
		"worm": return _worm(ci)
		"bear": return _bear(ci)
		"turret": return _turret(ci)
		"cakebox": return _cakebox(ci)
		"pistol": return _pistol(ci)
		"medtower": return _medtower(ci)
		"axe": return _axe(ci)
		"cannon": return _cannon(ci)
		"remote_bomb": return _remote(ci)
		"katana": return _katana(ci)
		"shadow_ninja": return _ninja(ci)
		"skel_warrior", "skel_mage", "skel_priest": return _skel123(id, ci)
		"mask_lion": return _lion(ci)
	return {}


static func _src(eid: String) -> Dictionary:
	var e = DataRegistry.phase2_equipment_by_id.get(eid, {})
	return {"text": Lang.t(str((e as Dictionary).get("name", eid)) if e is Dictionary else eid), "tab": "equips", "key": eid}


static func _page(name: String, kinds: Array, avatar_id: String, portrait: Dictionary, eid: String, tags: Array, st: Array,
		basic: Dictionary, skill: Dictionary, passives: Array, col_title: String = "装备星级", cols_: Array = []) -> Dictionary:
	var tg: Array = []
	for t in tags:
		tg.append(Lang.t(str(t)))
	tg.append(Lang.t("不可编入"))
	var d := {
		"name": name, "kinds": kinds,
		"avatar": "res://assets/sprites/avatars/summon-%s.png" % avatar_id,
		"portrait": portrait, "source": _src(eid), "tags": tg,
		"col_title": Lang.t(col_title), "cols": cols_ if not cols_.is_empty() else SC.star_cols(),
		"stats": st, "basic": basic, "skill": skill, "passives": passives,
	}
	if portrait.has("_box"):
		d["portrait_box"] = float(portrait["_box"])
	if portrait.has("_cy"):
		d["portrait_cy"] = float(portrait["_cy"])
	return d


static func _sheet(img: String, fw: int, n: int, box: float = 160.0, cy: float = 100.0) -> Dictionary:
	return {"img": img, "sprite": {"frameW": fw, "frameH": fw, "frames": n}, "_box": box, "_cy": cy}


# ─── 032 骨哨 · 亡灵骷髅 ───
static func _skeleton(si: int) -> Dictionary:
	var E := EqSummons
	return _page("亡灵骷髅", ["skeleton"], "skeleton", {"img": "pets/skeleton.png"}, "p2eq_032", ["近战坦克"],
		SC.stats(E.SKEL_HP[si], E.SKEL_ATK[si], 0, 0, E.SKEL_MOVE, E.SKEL_ASPD, E.SKEL_RANGE),
		{"name": "骨击", "icon": "skills/summon-skel-strike.png", "desc": SC.basic_line("亡灵骷髅")}, {},
		[{"name": "不朽之骨", "icon": "passive/summon-skel-bone-icon.png",
			"desc": "亡灵骷髅每次受到的伤害都只有 {C:EqSummons.SKEL_DMG_CAP} 点，真实伤害也一样。"},
		 {"name": "尸爆", "icon": "passive/summon-skel-boom-icon.png",
			"desc": Lang.t("亡灵骷髅阵亡或存活 {C:EqSummons.SKEL_LIFE[%d]} 秒后爆炸，对附近的敌人造成相当于其最大生命值 {C:EqSummons.SKEL_BOOM_PCT[%d]%%}%% 的真实伤害。") % [si, si]}])


# ─── 033 魔法海螺 · 海螺虫 ───
static func _worm(si: int) -> Dictionary:
	var E := EquipSystem
	var ps: Array = [{"name": "海螺馈赠", "icon": "passive/summon-worm-gift-icon.png",
		"desc": Lang.t("海螺虫诞生时随机携带 3 件 %d 星的 {C:EquipSystem.CONCH_COST_MIN} 费或 {C:EquipSystem.CONCH_COST_MAX} 费装备。") % (si + 1)}]
	if si >= 2:
		ps.append({"name": "分裂", "icon": "passive/summon-worm-split-icon.png",
			"desc": "每 {C:EquipSystem.WORM_SPLIT_IV} 秒在空位分裂出一只新的海螺虫，生命值与攻击力与自身相同，但不携带装备，最多 {C:EquipSystem.WORM_CAP} 只。"})
	return _page("海螺虫", ["worm"], "worm", {"img": "pets/conch-worm.png"}, "p2eq_033", ["近战斗士"],
		SC.stats(E.WORM_HP[si], E.WORM_ATK[si], 0, 0, BattleSpawn.SUMMON_DEFAULT_SPD, E.WORM_ASPD, BattleSpawn.SUMMON_DEFAULT_RANGE),
		{"name": "啃咬", "icon": "skills/summon-worm-bite.png", "desc": SC.basic_line("海螺虫")}, {}, ps)


# ─── 034 玩偶小熊 · 大熊 ───
static func _bear(si: int) -> Dictionary:
	var T := EquipTickSystem
	return _page("大熊", ["bear"], "bear", _sheet("vfx/bear-walk.png", 96, 1, 190.0, 90.0), "p2eq_034", ["近战斗士"],
		SC.stats(T.BEAR_HP[si], T.BEAR_ATK[si], T.BEAR_RESIST, T.BEAR_RESIST, BattleSpawn.SUMMON_DEFAULT_SPD, T.BEAR_ASPD, T.BEAR_RANGE),
		{"name": "熊掌", "icon": "skills/summon-bear-paw.png", "desc": SC.basic_line("大熊") + Lang.t("每次攻击积攒 1 层。")}, {},
		[{"name": "震地波", "icon": "passive/summon-bear-wave-icon.png",
			"desc": "积攒 {C:EquipTickSystem.BEAR_PAW_STACKS} 层后，下一次攻击改为向前方打出冲击波，射程临时提高到 {C:EquipTickSystem.BEAR_WAVE_RANGE}，对路径上的敌人造成（{C:EquipTickSystem.BEAR_WAVE_COEF%}%×攻击力({ATK}) = {N:EquipTickSystem.BEAR_WAVE_COEF*ATK}）物理伤害，将其击飞并拉到大熊身前，然后清空层数。"}])


# ─── 058 远古炮塔 · 炮台 ───
## 左栏只写基础值; 携带者攻击力带来的加成写成被动【火力同调】(用户 11-27「左边就写一千四百生命，然后右边被动写这个炮台额外获得多少」)。
static func _turret(si: int) -> Dictionary:
	var E := EquipSystem
	var d := _page("炮台", ["turret"], "turret", {"img": "pets/turret.png"}, "p2eq_058", ["远程射手"],
		SC.stats(E.TURRET_HP[si], E.TURRET_ATK[si], E.TURRET_RES[si], E.TURRET_RES[si], 0, E.TURRET_ASPD, E.TURRET_RANGE),
		{"name": "炮击", "icon": "skills/summon-turret-shell.png",
			"desc": SC.basic_line("炮台") + Lang.t("每次攻击使炮台永久获得 {C:EquipSystem.TURRET_CRIT_PER_SHOT%}% 暴击率，持续到本战场结束。")}, {},
		[{"name": "火力同调", "icon": "passive/summon-turret-link-icon.png",
			"desc": "炮台登场时，额外获得相当于携带者攻击力 {C:EquipSystem.TURRET_HP_PER_ATK} 倍的生命值，以及等同于携带者攻击力的攻击力。"},
		 {"name": "护卫", "icon": "passive/summon-turret-ward-icon.png",
			"desc": Lang.t("携带者存活时，炮台获得 {C:EquipSystem.TURRET_RES[%d]} 护甲与魔抗，携带者阵亡后降为 0。") % si}])
	d["avatar"] = "res://assets/sprites/pets/turret.png"
	return d


# ─── 072 蛋糕盒 · 蛋糕礼盒(携带者阵亡时分裂出的两个) ───
## 属性整份按携带者 ⇒ 左栏写比例(用户 11-27 模板: 左栏写底子; 礼盒没有底子, 只有比例)。
static func _cakebox(si: int) -> Dictionary:
	var F := EqFoodBatch
	return _page("蛋糕礼盒", ["cakebox"], "cakebox", {"img": "vfx/eq072-cake-box.png", "_box": 120.0, "_cy": 104.0}, "p2eq_072", ["近战坦克"],
		SC.stats(SC._pct(F.BOX_SPLIT_HP_PCT[si]) + "%", "100%", "100%", "100%", 0, "同携带者", RealtimeBattle3DScene.MELEE_ATK_RANGE_MIN,
			{"hp": "携带者生命", "atk": "携带者攻击", "def": "携带者护甲", "mr": "携带者魔抗"}),
		{"name": "礼盒撞击", "icon": "skills/summon-cake-bump.png",
			"desc": "蛋糕礼盒的攻击造成 {C:EqFoodBatch.BOX_HIT_COEF%}% 攻击力的物理伤害。"}, {},
		[{"name": "甜蜜诱惑", "icon": "passive/summon-cake-lure-icon.png",
			"desc": Lang.t("嘲讽附近所有敌人。每有一个敌人以蛋糕礼盒为目标，蛋糕礼盒获得 {C:EqFoodBatch.BOX_RES_PER_LOCKER[%d]} 护甲和魔抗。") % si},
		 {"name": "蛋糕法阵", "icon": "passive/summon-cake-field-icon.png",
			"desc": Lang.t("登场 {C:EqFoodBatch.BOX_SPLIT_FIELD_FIRST} 秒后召唤蛋糕法阵，之后每 {C:EqFoodBatch.BOX_SPLIT_FIELD_IV} 秒一次，持续 {C:EqFoodBatch.BOX_FIELD_SEC} 秒，每秒为其中友军回复 {C:EqFoodBatch.BOX_FIELD_HEAL[%d]} 生命值与 {C:EqFoodBatch.BOX_FIELD_ENERGY[%d]} 龟能。") % [si, si]},
		 {"name": "礼盒分身", "icon": "passive/summon-cake-split-icon.png",
			"desc": Lang.t("蛋糕礼盒拥有携带者 {C:EqFoodBatch.BOX_SPLIT_HP_PCT[%d]%%}%% 的最大生命值，攻击力、护甲、魔抗与攻击速度与携带者相同，不能移动。") % si}])


# ─── 077 小手枪 ───
static func _pistol(si: int) -> Dictionary:
	var G := EqGunBatch
	return _page("小手枪", ["pistol"], "pistol", _sheet("vfx/eq-pistol-idle.png", 40, 16, 120.0, 100.0), "p2eq_077", ["远程射手"],
		SC.stats(G.PISTOL_HP[si], G.PISTOL_ATK[si], 0, 0, BattleSpawn.SUMMON_DEFAULT_SPD, 1.0 / G.PISTOL_IV, G.PISTOL_RANGE),
		{"name": "连射", "icon": "skills/summon-pistol-shot.png",
			"desc": "小手枪的攻击造成（{C:EqGunBatch.PISTOL_COEF%}%×攻击力({ATK}) = {N:EqGunBatch.PISTOL_COEF*ATK}）物理伤害，拥有 {C:EqGunBatch.PISTOL_CRIT%}% 暴击率。每次攻击使小手枪永久获得 {C:EqGunBatch.PISTOL_PEN_PER_SHOT} 点护甲穿透，持续到本战场结束。攻击速度不受加成影响。"}, {},
		[{"name": "小不点", "icon": "passive/summon-pistol-tiny-icon.png",
			"desc": "小手枪没有护盾时，受到的所有伤害降为 {C:EqGunBatch.PISTOL_DMG_CAP} 点，真实伤害也一样，携带者阵亡后降为 {C:EqGunBatch.PISTOL_DMG_CAP_DEAD} 点。受到的治疗至多 {C:EqGunBatch.PISTOL_HEAL_CAP} 点。"}])


# ─── 079 医疗塔 · 急救塔 ───
static func _medtower(si: int) -> Dictionary:
	var G := EqGunBatch
	return _page("急救塔", ["medtower"], "medtower", _sheet("vfx/eq-coraltower-idle.png", 64, 16, 170.0, 96.0), "p2eq_079", ["远程辅助"],
		SC.stats(G.TOWER_HP[si], G.TOWER_ATK[si], G.TOWER_RES[si], G.TOWER_RES[si], 0, "同携带者", G.TOWER_RANGE),
		{"name": "急救弹", "icon": "skills/summon-tower-shot.png",
			"desc": Lang.t("急救塔的攻击造成（{C:EqGunBatch.TOWER_COEF%%}%%×攻击力({ATK}) = {N:EqGunBatch.TOWER_COEF*ATK}）物理伤害，另加目标最大生命值 {C:EqGunBatch.TOWER_MAXHP_PCT[%d]%%}%% 的魔法伤害，并为生命值百分比最低的友军回复 {C:EqGunBatch.TOWER_HEAL[%d]} 生命值。") % [si, si]}, {},
		[{"name": "同步射速", "icon": "passive/summon-tower-sync-icon.png",
			"desc": "急救塔的攻击速度与携带者相同，携带者阵亡后保持阵亡时的攻击速度。"},
		 {"name": "急救金弹", "icon": "passive/summon-tower-gold-icon.png",
			"desc": "急救塔拥有独立的金弹计数，随枪羁绊件数每攻击 {C:EqGunBatch.TOWER_GOLD_EVERY} 次射出一发金弹，金弹附加本段伤害 {C:EqGunBatch.TOWER_GOLD_PCT%}% 的真实伤害，治疗量翻倍。"}])


# ─── 096 小木斧 · 斧头(列 = 进化形态) ───
## 左栏 = 刚进化到这一形态时的属性(砍伐经验取进化门槛的累计值, 最终造物另加 AxeFinalStats 的那一份)。
static func _axe_exp_at(k: int) -> int:
	var e := 0
	for i in range(mini(k, AxeEvolution.STAGE_NEEDS.size())):
		e += int(AxeEvolution.STAGE_NEEDS[i])
	if k >= AxeEvolution.STAGES.size():
		e += int(AxeEvolution.FINAL_NEED)
	return e


static func _axe(ci: int) -> Dictionary:
	var A := AxeEvolution
	var F := AxeFinalStats
	var n_st: int = A.STAGES.size()
	var stage: int = mini(ci, n_st - 1)
	var fin: String = str(A.FINALS[ci - n_st]["key"]) if ci >= n_st else ""
	var ex: int = _axe_exp_at(ci)
	var hp: float = A.minion_hp(ex, A.passives_at(stage))
	var atk: float = A.minion_atk(ex, A.passives_at(stage))
	var df: float = A.MINION_DEF + A.PASSIVE_DEF * float(A.passives_at(stage))
	var mr: float = A.MINION_MR + A.PASSIVE_MR * float(A.passives_at(stage))
	var aspd: float = A.MINION_ASPD
	var rng: float = BattleSpawn.SUMMON_DEFAULT_RANGE
	var move: float = BattleSpawn.SUMMON_DEFAULT_SPD
	match fin:
		"undead": hp += F.UNDEAD_HP; atk += F.UNDEAD_ATK; df += F.UNDEAD_DEF; mr += F.UNDEAD_DEF
		"seraph": hp += F.SERAPH_HP; atk += F.SERAPH_ATK; df += F.SERAPH_DEF; mr += F.SERAPH_DEF; rng = F.SERAPH_RANGE
		"holo": hp += F.HOLO_HP; atk += F.HOLO_ATK; df += F.HOLO_DEF; mr += F.HOLO_DEF
		"ember": hp += F.EMBER_HP; atk += F.EMBER_ATK; aspd *= 1.0 + F.EMBER_ASPD; move *= 1.0 + F.EMBER_MOVE
	var basic: String = SC.basic_line("斧头") + Lang.t("每次攻击窃取目标 {C:AxeEvolution.SHIELD_STEAL_PCT%}% 的护盾，转为自身的护盾。")
	var skill: String = Lang.t("回复自身 {C:AxeEvolution.ACTIVE_HEAL_PCT%}% 最大生命值，并获得自身 {C:AxeEvolution.ACTIVE_SHIELD_PCT%}% 最大生命值的护盾。")
	if stage >= 4 and fin == "":
		skill += Lang.t("随后开始【蓄力猛砸】，蓄力 {C:AxeEvolution.CHARGE_TIME} 秒，期间获得 {C:AxeEvolution.CHARGE_DR%}% 减伤。蓄力结束时砸下，对前方区域内的每个敌人造成（{C:AxeEvolution.SLAM_ATK%}%×攻击力({ATK}) = {N:AxeEvolution.SLAM_ATK*ATK}）物理伤害，将其击飞并眩晕 {C:AxeEvolution.SLAM_STUN} 秒。")
	match fin:
		"seraph": skill += Lang.t("随后在 {C:AxeFinalStats.SERAPH_CAST_TIME} 秒内投出 {C:AxeFinalStats.SERAPH_BOOMERANGS} 把回旋镖，回旋镖飞出后返回，命中时造成（{C:AxeFinalStats.SERAPH_BOOM_ATK%}%×攻击力({ATK}) = {M:AxeFinalStats.SERAPH_BOOM_ATK*ATK}）魔法伤害，并施加 {C:AxeFinalStats.SERAPH_BOOM_BURN} 层灼烧。")
		"holo": skill += Lang.t("随后插地 {C:AxeFinalStats.HOLO_PLANT_TIME} 秒，期间获得 {C:AxeFinalStats.HOLO_PLANT_DR%}% 减伤，附近的友军每 {C:AxeFinalStats.HOLO_AURA_TICK} 秒回复 {C:AxeFinalStats.HOLO_AURA_HEAL} 生命值和 {C:AxeFinalStats.HOLO_AURA_ENERGY} 龟能，并获得 {C:AxeFinalStats.HOLO_AURA_ASPD%}% 攻击速度。")
		"ember": skill += Lang.t("随后点燃【余烬之光】：{C:AxeFinalStats.EMBER_LIGHT_TIME} 秒内获得 {C:AxeFinalStats.EMBER_LIGHT_LIFESTEAL%}% 生命偷取、{C:AxeFinalStats.EMBER_LIGHT_DR%}% 减伤和 {C:AxeFinalStats.EMBER_LIGHT_ASPD%}% 攻击速度，并免疫控制效果。期间仍会积累龟能，再次施放时效果独立叠加。")
		"undead": skill += Lang.t("随后开始【蓄力猛砸】，蓄力 {C:AxeEvolution.CHARGE_TIME} 秒，期间获得 {C:AxeEvolution.CHARGE_DR%}% 减伤。蓄力结束时砸下，对前方区域内的每个敌人造成（{C:AxeEvolution.SLAM_ATK%}%×攻击力({ATK}) = {N:AxeEvolution.SLAM_ATK*ATK}）物理伤害，将其击飞并眩晕 {C:AxeEvolution.SLAM_STUN} 秒。")
	var ps: Array = [{"name": "砍伐成长", "icon": "passive/summon-axe-grow-icon.png",
		"desc": "斧头的生命值为 {C:AxeEvolution.MINION_HP_BASE} + {C:AxeEvolution.MINION_HP_PER_EXP} × 砍伐经验，攻击力为 {C:AxeEvolution.MINION_ATK_BASE} + {C:AxeEvolution.MINION_ATK_PER_EXP} × 砍伐经验。小木斧每次进化，斧头额外获得 {C:AxeEvolution.PASSIVE_HP} 生命值、{C:AxeEvolution.PASSIVE_ATK} 攻击力、{C:AxeEvolution.PASSIVE_DEF} 护甲和 {C:AxeEvolution.PASSIVE_MR} 魔抗。左侧属性为刚进化到此形态时的数值。"}]
	if stage >= 1:
		ps.append({"name": "石斧 · 重击", "icon": "passive/summon-axe-smash-icon.png",
			"desc": "每 {C:AxeEvolution.SMASH_IV} 秒，斧头的下一次攻击额外造成（{C:AxeEvolution.SMASH_ATK%}%×攻击力({ATK}) = {N:AxeEvolution.SMASH_ATK*ATK}）物理伤害，并将目标击飞和短暂击退。"})
	if stage >= 2:
		ps.append({"name": "铁斧 · 竖劈", "icon": "passive/summon-axe-cleave-icon.png",
			"desc": "斧头每第 2 次攻击变为竖劈，额外造成目标 {C:AxeEvolution.CLEAVE_MAXHP_PCT%}% 最大生命值的真实伤害，并施加 {C:AxeEvolution.CLEAVE_BLEED} 层流血。"})
	if stage >= 3:
		ps.append({"name": "金斧 · 效率", "icon": "passive/summon-axe-sweep-icon.png",
			"desc": "斧头的攻击在 {C:AxeEvolution.SWEEP_ARC_DEG}° 横扫和竖劈之间交替，横扫命中前方所有敌人。每次攻击命中获得 1 层【效率】，持续 {C:AxeEvolution.EFF_DUR} 秒，可无限叠加，叠加时刷新持续时间。每层【效率】提供 {C:AxeEvolution.EFF_ASPD%}% 攻击速度和 {C:AxeEvolution.EFF_MOVE%}% 移动速度。"})
	match fin:
		"undead": ps.append({"name": "亡灵之斧", "icon": "passive/summon-axe-undead-icon.png",
			"desc": "附近的敌人每秒受到其 {C:AxeFinalStats.UNDEAD_RING_MAXHP_PCT%}% 最大生命值的魔法伤害。附近每有一个敌人，斧头每秒回复自身 {C:AxeFinalStats.UNDEAD_LEECH_PCT%}% 最大生命值。斧头阵亡 {C:AxeFinalStats.UNDEAD_REVIVE_DELAY} 秒后以自身 {C:AxeFinalStats.UNDEAD_REVIVE_HP_PCT%}% 最大生命值复活，每个战场一次。"})
		"seraph": ps.append({"name": "炽天使", "icon": "passive/summon-axe-seraph-icon.png",
			"desc": "斧头的攻击施加 {C:AxeFinalStats.SERAPH_BURN_ON_HIT} 层灼烧。"})
		"holo": ps.append({"name": "全息斧", "icon": "passive/summon-axe-holo-icon.png",
			"desc": "斧头获得 {C:AxeFinalStats.HOLO_ENERGY_RATE%}% 龟能充能。攻击为生命值百分比最低的友军提供 {C:AxeFinalStats.HOLO_ONHIT_SHIELD} 护盾和 {C:AxeFinalStats.HOLO_ONHIT_ENERGY} 龟能。"})
		"ember": ps.append({"name": "余烬", "icon": "passive/summon-axe-ember-icon.png",
			"desc": "斧头的攻击命中时，对目标施加 {C:AxeFinalStats.EMBER_SEED_PER_HIT} 层【余烬种子】，并处决生命值低于斩杀线的目标。每层【余烬种子】使该目标的斩杀线提高其最大生命值的 {C:AxeFinalStats.EMBER_SEED_EXEC_PCT%}%，无上限。每处决一个单位获得 {C:AxeFinalStats.EMBER_EXEC_ENERGY} 龟能。"})
	var key: String = (fin if fin != "" else ["wood", "stone", "iron", "gold", "diamond"][stage])
	return _page("斧头", ["axe"], "axe", _sheet("vfx/eq096-axe-%s-idle.png" % key, 112, 8, 200.0, 92.0), "p2eq_096", ["远程斗士" if fin == "seraph" else "近战斗士"],
		SC.stats(hp, atk, df, mr, move, aspd, rng),
		{"name": "斧击", "icon": "skills/summon-axe-chop.png", "desc": basic},
		{"name": "斧之守护", "icon": "skills/summon-axe-guard.png", "desc": skill, "energy": int(A.ACTIVE_ENERGY)},
		ps, "进化形态", cols("axe"))


# ─── 105 炮筒 ───
static func _cannon(si: int) -> Dictionary:
	var B := EqBombBatch
	return _page("炮筒", ["cannon"], "cannon", _sheet("vfx/eq-cannon-idle.png", 64, 7, 170.0, 96.0), "p2eq_105", ["远程射手"],
		SC.stats(B.CANNON_HP[si], B.CANNON_ATK[si], 0, 0, 0, B.CANNON_ASPD, B.CANNON_RANGE),
		{"name": "开炮", "icon": "skills/summon-cannon-fire.png",
			"desc": "炮筒朝射程内最近的敌人开炮，炮弹落地爆炸，对周围的敌人造成（{C:BasicConsts.DEFAULT_BASIC_COEF%}%×攻击力({ATK}) = {N:BasicConsts.DEFAULT_BASIC_COEF*ATK}）物理伤害。"},
		{"name": "重炮", "icon": "skills/summon-cannon-heavy.png", "energy": int(B.CANNON_EN_MAX),
			"desc": Lang.t("炮筒进入重炮状态：每发消耗 {C:EqBombBatch.CANNON_HEAVY_COST[%d]} 龟能，炮弹沿直线飞过整个战场，击退直线上的敌人，造成（{C:EqBombBatch.CANNON_HEAVY_MULT%%}%%×攻击力({ATK}) = {N:EqBombBatch.CANNON_HEAVY_MULT*ATK}）物理伤害并施加 {C:EqBombBatch.CANNON_HEAVY_BLEED[%d]} 层流血。龟能耗尽时回到普通炮击。") % [si, si]},
		[])


# ─── 106 遥控炸弹 ───
static func _remote(si: int) -> Dictionary:
	var B := EqBombBatch
	var chase: String = Lang.t("遥控炸弹追着一个敌人移动，不攻击。")
	if float(B.REMOTE_DECAY[si]) > 0.0:
		chase += Lang.t("每秒损失 {C:EqBombBatch.REMOTE_DECAY[%d]%%}%% 最大生命值。") % si
	return _page("遥控炸弹", ["remote_bomb"], "remote_bomb", _sheet("vfx/eq-remote-bomb-idle.png", 64, 7, 150.0, 100.0), "p2eq_106", ["近战坦克"],
		SC.stats(B.REMOTE_HP[si], 0, B.REMOTE_RES[si], B.REMOTE_RES[si], BattleSpawn.SUMMON_DEFAULT_SPD, 0, 0),
		{}, {},
		[{"name": "锁定追踪", "icon": "passive/summon-remote-chase-icon.png", "desc": chase},
		 {"name": "引爆", "icon": "passive/summon-remote-boom-icon.png",
			"desc": Lang.t("生命值耗尽时爆炸，对大范围内的敌人造成 {C:EqBombBatch.REMOTE_FLAT[%d]} 物理伤害和相当于携带者 {C:EqBombBatch.REMOTE_TRUE_PCT[%d]%%}%% 最大生命值的真实伤害，并施加 {C:EqBombBatch.REMOTE_BLEED[%d]} 层流血。") % [si, si, si]}])


# ─── 107 武士刀 · 武士刀小将 ───
## 第四次蓄力回的是小将自己的生命(代码 eq_bomb_batch `_heal(p, …)`; 装备旧文案写成「回复携带者」, 11-27 以代码为准改掉)。
static func _katana(si: int) -> Dictionary:
	var B := EqBombBatch
	return _page("武士刀小将", ["katana"], "katana", _sheet("vfx/eq-katana-idle.png", 112, 7, 200.0, 92.0), "p2eq_107", ["近战斗士"],
		SC.stats(B.KATANA_HP[si], B.KATANA_ATK[si], 0, 0, BattleSpawn.SUMMON_DEFAULT_SPD, B.KATANA_ASPD, B.KATANA_RANGE),
		{"name": "斩击", "icon": "skills/summon-katana-slash.png", "desc": SC.basic_line("武士刀小将")},
		{"name": "居合", "icon": "skills/summon-katana-iai.png", "energy": int(B.KATANA_EN_MAX),
			"desc": "四次一循环。前三次向前方挥出一道剑气，贯穿路径上的敌人，造成（{C:EqBombBatch.KATANA_WAVE_MULT%}%×攻击力({ATK}) = {N:EqBombBatch.KATANA_WAVE_MULT*ATK}）物理伤害。第四次蓄力 {C:EqBombBatch.KATANA_CHARGE} 秒，期间回复自身 {C:EqBombBatch.KATANA_HEAL_TOTAL%}% 最大生命值，随后向前方吹出 {C:EqBombBatch.KATANA_TORNADOES} 道龙卷风，造成（{C:EqBombBatch.KATANA_TORNADO_MULT%}%×攻击力({ATK}) = {N:EqBombBatch.KATANA_TORNADO_MULT*ATK}）物理伤害并击飞 {C:EqBombBatch.KATANA_AIR} 秒，每个敌人至多被龙卷风击中一次。"},
		[])


# ─── 115 暗影匕首 · 暗影忍者 ───
static func _ninja(si: int) -> Dictionary:
	var D := EqDaggerBatch
	return _page("暗影忍者", ["shadow_ninja", "shadow_clone"], "shadow_ninja", _sheet("vfx/eq-ninja-idle.png", 112, 6, 200.0, 92.0), "p2eq_115", ["近战刺客"],
		SC.stats(D.NINJA_HP[si], D.NINJA_ATK[si], D.NINJA_RES[si], D.NINJA_RES[si], BattleSpawn.SUMMON_DEFAULT_SPD, 1.0 / D.NINJA_IV, D.NINJA_RANGE),
		{"name": "忍刃", "icon": "skills/summon-ninja-blade.png",
			"desc": SC.basic_line("暗影忍者") + Lang.t("暗影忍者拥有 {C:EqDaggerBatch.NINJA_CRIT[%d]%%}%% 暴击率。") % si},
		{"name": "影袭", "icon": "skills/summon-ninja-strike.png", "energy": int(D.NINJA_EN_MAX),
			"desc": "化为黑烟，闪到生命值比例最低的敌人身后背刺，造成（{C:EqDaggerBatch.NINJA_STRIKE_MULT%}%×攻击力({ATK}) = {N:EqDaggerBatch.NINJA_STRIKE_MULT*ATK}）物理伤害，必定暴击，随后隐身 {C:EqDaggerBatch.NINJA_RESTEALTH} 秒。"},
		[{"name": "暗影潜行", "icon": "passive/summon-ninja-stealth-icon.png",
			"desc": "暗影忍者登场时隐身，攻击时现形。"},
		 {"name": "影分身", "icon": "passive/summon-ninja-clone-icon.png",
			"desc": "暗影忍者的生命值首次低于 {C:EqDaggerBatch.NINJA_CLONE_HP_PCT%}% 时，分出一名影子忍者，持续 {C:EqDaggerBatch.NINJA_CLONE_SEC} 秒，拥有其 {C:EqDaggerBatch.NINJA_CLONE_STAT%}% 最大生命值与攻击力，同样会施放影袭。"},
		 {"name": "手里剑", "icon": "passive/summon-ninja-shuriken-icon.png",
			"desc": Lang.t("每次影袭，暗影忍者朝目标掷出一枚手里剑，影子在场时两名忍者各掷一枚，对路径上的敌人造成（{C:EqDaggerBatch.SHURIKEN_FLAT[%d]} + {C:EqDaggerBatch.SHURIKEN_ATK%%}%%×攻击力({ATK}) = {M:%s+EqDaggerBatch.SHURIKEN_ATK*ATK}）魔法伤害。") % [si, SC._n(D.SHURIKEN_FLAT[si])]}])


# ─── 123 亡者之书 · 骷髅战士 / 骷髅法师 / 骷髅祭司 ───
static func _skel123(id: String, si: int) -> Dictionary:
	var M := EqMagicBatch
	var life := {"name": "亡者契约", "icon": "passive/summon-skel123-pact-icon.png",
		"desc": "亡者之书召唤的骷髅存在时间等于携带者这次施放技能消耗的龟能 × {C:EqMagicBatch.SKEL_SEC_PER_EN} 秒，到时化为尘土。"}
	match id:
		"skel_warrior":
			return _page("骷髅战士", ["skel_warrior"], "skel_warrior", _sheet("vfx/eq-skelw-idle.png", 112, 6, 200.0, 92.0), "p2eq_123", ["近战斗士"],
				SC.stats(M.SKW_HP[si], M.SKW_ATK[si], M.SKW_RES[si], M.SKW_RES[si], BattleSpawn.SUMMON_DEFAULT_SPD, 1.0 / M.SKW_IV, M.SKW_RANGE),
				{"name": "骨斧", "icon": "skills/summon-skelw-axe.png", "desc": SC.basic_line("骷髅战士")},
				{"name": "骸骨狂怒", "icon": "skills/summon-skelw-rage.png", "energy": int(M.SKEL_EN_MAX),
					"desc": "骷髅战士狂怒 {C:EqMagicBatch.SKW_RAGE_SEC} 秒：受到的伤害降低 {C:EqMagicBatch.SKW_DR%}%，获得 {C:EqMagicBatch.SKW_LS%}% 生命偷取，每次攻击额外造成（{C:EqMagicBatch.SKW_EXTRA%}%×攻击力({ATK}) = {N:EqMagicBatch.SKW_EXTRA*ATK}）物理伤害。狂怒期间不积攒龟能。"},
				[life])
		"skel_mage":
			return _page("骷髅法师", ["skel_mage"], "skel_mage", _sheet("vfx/eq-skelm-idle.png", 112, 6, 200.0, 92.0), "p2eq_123", ["远程法师"],
				SC.stats(M.SKM_HP[si], M.SKM_ATK[si], M.SKM_RES[si], M.SKM_RES[si], BattleSpawn.SUMMON_DEFAULT_SPD, 1.0 / M.SKM_IV, M.SKM_RANGE),
				{"name": "骨火弹", "icon": "skills/summon-skelm-bolt.png",
					"desc": "骷髅法师的攻击造成（{C:EqMagicBatch.SKM_BASIC%}%×攻击力({ATK}) = {M:EqMagicBatch.SKM_BASIC*ATK}）魔法伤害。"},
				{"name": "骨火爆裂", "icon": "skills/summon-skelm-blast.png", "energy": int(M.SKEL_EN_MAX),
					"desc": "目标及其周围的敌人受到（{C:EqMagicBatch.SKM_BLAST_ATK%}%×攻击力({ATK}) = {M:EqMagicBatch.SKM_BLAST_ATK*ATK}）魔法伤害。"},
				[life])
	return _page("骷髅祭司", ["skel_priest"], "skel_priest", _sheet("vfx/eq-skelp-idle.png", 112, 6, 200.0, 92.0), "p2eq_123", ["远程辅助"],
		SC.stats(M.SKP_HP[si], M.SKP_ATK[si], M.SKP_RES[si], M.SKP_RES[si], BattleSpawn.SUMMON_DEFAULT_SPD, 1.0 / M.SKP_IV, M.SKP_RANGE),
		{"name": "魂火", "icon": "skills/summon-skelp-soul.png",
			"desc": "骷髅祭司的攻击造成（{C:EqMagicBatch.SKP_BASIC%}%×攻击力({ATK}) = {M:EqMagicBatch.SKP_BASIC*ATK}）魔法伤害。"},
		{"name": "亡灵浪潮", "icon": "skills/summon-skelp-wave.png", "energy": int(M.SKEL_EN_MAX),
			"desc": Lang.t("推出一道缓慢前进的亡灵浪潮，途经的敌人受到 {C:EqMagicBatch.WAVE_DMG[%d]} 物理伤害、被击飞并眩晕 {C:EqMagicBatch.WAVE_STUN} 秒、{C:EqMagicBatch.WAVE_MR_SEC} 秒内魔抗降低 {C:EqMagicBatch.WAVE_MR_SHRED%%}%%，途经的友军回复 {C:EqMagicBatch.WAVE_HEAL[%d]} 生命值。") % [si, si]},
		[life])


# ─── 130 舞狮头 · 舞狮 ───
static func _lion(si: int) -> Dictionary:
	var K := EqMaskBatch
	var coef: float = float(K.LION_CHARGE_ATK[si])
	return _page("舞狮", ["mask_lion"], "mask_lion", _sheet("vfx/eq-masklion-idle.png", 112, 6, 200.0, 92.0), "p2eq_130", ["近战斗士"],
		SC.stats(K.LION_HP[si], K.LION_ATK[si], K.LION_RES[si], K.LION_RES[si], BattleSpawn.SUMMON_DEFAULT_SPD, K.LION_ASPD, K.LION_RANGE),
		{"name": "狮咬", "icon": "skills/summon-lion-bite.png", "desc": SC.basic_line("舞狮")},
		{"name": "冲撞", "icon": "skills/summon-lion-charge.png", "energy": int(K.LION_EN_MAX),
			"desc": Lang.t("舞狮朝前方冲撞，对途经的敌人造成（{C:EqMaskBatch.LION_CHARGE_ATK[%d]%%}%%×攻击力({ATK}) = {N:%s*ATK}）物理伤害，将其撞退并眩晕 {C:EqMaskBatch.LION_STUN[%d]} 秒。") % [si, SC._n(coef), si]},
		[])
