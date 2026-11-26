extends Node
## verify_spear_synergy.gd —— 长矛羁绊【百夫长】(2026-11-26 · 方案书 docs/plans/20261126-长矛羁绊.md)
##   A 登场时机: 第 8 秒(7.9 秒还没有) / 我方团队生命值 < 60% 时提前 / 每路一次 / 换路再来
##   B 登场: 全场敌人击飞(滞空 1.5 秒) + 百夫长攻击力 150% 魔法伤害
##   C 属性: 档位底子 × (1 + 不同长矛星级合计 × 3%), 同名只算一件取最高星; 护甲魔抗按档位
##   D 普攻四档: 1 只打目标 / 2 贯穿, 身后吃 50% / 3 削线上每人 1 护甲 1 魔抗至多 30 / 4 每第 4 下掷矛(按速度飞到才结算, 打最远的)
##   E 龟甲阵四档: 举盾 3 秒减伤 20% 后撤 / 2 放盾横扫 / 3 举盾期间每 0.5 秒刺一圈(6 下) / 4 冲出 4 名骑兵, 路上碰到的吃伤害并击飞
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SP := preload("res://scripts/systems/equip/spear_synergy_system.gd")

var _n := 0
var _fail := 0
var _s
var _p


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _mk(side: String, ids: Array = [], dx: float = 0.0, dy: float = 0.0, star: int = 1) -> Dictionary:
	var c: Vector2 = _s._arena_center
	var u: Dictionary = _s._spawn._make_unit("green", side, c + Vector2((-150.0 if side == "left" else 150.0) + dx, dy))
	for k in ["shield", "crit", "dodge_bonus", "damage_reduction", "damage_amp", "armor_pen", "armor_pen_pct"]:
		u[k] = 0.0
	u["base_def"] = 20.0
	u["base_mr"] = 20.0
	u["maxHp"] = 5000.0
	u["hp"] = 5000.0
	u["base_atk"] = 100.0
	u["buffs"] = []
	_s._recalc_stats(u)
	var eq: Array = []
	for id in ids:
		eq.append({"id": id, "star": star})
	u["equips"] = eq
	return u


func _field(units: Array, tier: int) -> void:
	_p.clear_all()
	_p.reset_match()
	_s._units.clear()
	_s._units.append_array(units)
	_s._synergy._by_side = {"left": {"长矛": tier} if tier > 0 else {}, "right": {}}


func _adv(sec: float, units: Array = [], step: float = 0.05) -> void:
	var t := 0.0
	while t < sec - 1e-6:
		_s._t += step
		_p.tick(step)
		_s._ballistics._step_flights(step)
		t += step


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s.set_process(false)
	_s.set_physics_process(false)
	_s._t = 2000.0
	_p = _s._spear_syn
	print("=== 长矛羁绊【百夫长】 ===")

	## ── A 登场时机 ──
	var me := _mk("left")
	var foes: Array = [_mk("right", [], 0.0, -120.0), _mk("right", [], 0.0, 0.0), _mk("right", [], 0.0, 120.0)]
	_field([me] + foes, 1)
	_s._sd_t0 = _s._t
	_adv(7.9)
	var early: int = int(_p.stat["summon"])
	_adv(0.15)
	var at8: int = int(_p.stat["summon"])
	_adv(5.0)
	_ok("A 第 8 秒登场(7.9 秒还没有), 每路只一次", early == 0 and at8 == 1 and int(_p.stat["summon"]) == 1, "%d / %d / %d" % [early, at8, int(_p.stat["summon"])])
	me = _mk("left")
	var ally := _mk("left", [], -50.0, 150.0)
	foes = [_mk("right", [], 0.0, -120.0), _mk("right", [], 0.0, 120.0)]
	_field([me, ally] + foes, 1)
	_s._sd_t0 = _s._t
	var s0: int = int(_p.stat["summon"])
	_adv(2.0)
	var before_low: int = int(_p.stat["summon"]) - s0
	me["hp"] = 2000.0
	ally["hp"] = 3900.0   # (2000 + 3900) / 10000 = 59% < 60%
	_adv(0.1)
	_ok("A 我方团队生命值掉到 59% ⇒ 第 2 秒就提前登场(60% 以上时不登场)", before_low == 0 and int(_p.stat["summon"]) - s0 == 1,
		"之前 %d · 之后 %d · 比例 %.2f" % [before_low, int(_p.stat["summon"]) - s0, _p.team_hp_ratio("left")])
	_s._sd_t0 = _s._t + 1.0
	_s._t += 1.0
	me["hp"] = 5000.0
	ally["hp"] = 5000.0
	_adv(8.1)
	_ok("A 换路(开打时刻变了)后再登场一次", int(_p.stat["summon"]) - s0 == 2, str(int(_p.stat["summon"]) - s0))

	## ── B 登场击飞 + 魔法伤害 ──
	me = _mk("left")
	foes = [_mk("right", [], 300.0, -200.0), _mk("right", [], 500.0, 0.0), _mk("right", [], 100.0, 200.0)]
	_field([me] + foes, 1)
	var hp0: Array = []
	for o in foes:
		hp0.append(float(o["hp"]))
	var rec: Dictionary = _p.summon("left", 1)
	var c: Dictionary = rec.get("u", {})
	## 从天而降: 落地之前谁都没被击飞、没掉血; 落地(LAND_SEC 秒后)那一步才全场结算
	var air_early := 0
	var hurt_early := 0
	for i0 in range(foes.size()):
		if bool((foes[i0] as Dictionary).get("airborne", false)):
			air_early += 1
		if float((foes[i0] as Dictionary)["hp"]) < float(hp0[i0]):
			hurt_early += 1
	_adv(SP.LAND_SEC - 0.1)
	var air_mid := 0
	for o0 in foes:
		if bool((o0 as Dictionary).get("airborne", false)):
			air_mid += 1
	_adv(0.15)
	_ok("B 从天而降: 召唤时与落地前 0.1 秒都没人被击飞 / 掉血, 落地那一步才结算", air_early == 0 and hurt_early == 0 and air_mid == 0 and str(rec["state"]) == "idle",
		"召唤时 击飞 %d 掉血 %d · 落地前 击飞 %d · 状态 %s" % [air_early, hurt_early, air_mid, str(rec["state"])])
	var air := 0
	var dmg_ok := true
	for i in range(foes.size()):
		var o: Dictionary = foes[i]
		if bool(o.get("airborne", false)) and absf(float(o.get("vy", 0.0)) - SP.CENT_KNOCK_VY) < 1e-3:
			air += 1
		var want: int = _s._resolve_dmg(c, 1.5 * float(c["atk"]), o, true, false)
		if absf(hp0[i] - float(o["hp"]) - float(want)) > 1.0:
			dmg_ok = false
	_ok("B 全场 3 名敌人(远近都有)都被击飞, 初速 16.5 = 滞空 1.5 秒; 各受 150%% 攻击力魔法伤害", air == 3 and dmg_ok, "击飞 %d · 伤害对 %s" % [air, str(dmg_ok)])

	## ── C 属性 + 长矛星级加成 ──
	me = _mk("left", ["p2eq_137", "p2eq_139"], 0.0, 0.0, 2)
	var me2 := _mk("left", ["p2eq_137", "p2eq_141"], 0.0, 120.0, 3)   # 137 又出现一次(3 星) ⇒ 只算一件取 3 星
	_field([me, me2, _mk("right")], 2)
	var ss: int = _p.star_sum("left")
	rec = _p.summon("left", 2)
	_p._land(rec)   # 跳过下落(落地结算不混进本段计数)
	c = rec.get("u", {})
	var k: float = 1.0 + float(ss) * SP.STAR_PCT
	_ok("C 星级合计 = 竹矛 3 + 标枪 2 + 长戟 3 = 8(同名取最高) ⇒ ×%.2f; 二档 生命 %.0f 攻 %.0f 双抗 70" % [k, 2600.0 * k, 72.0 * k],
		ss == 8 and absf(float(c["maxHp"]) - 2600.0 * k) < 0.5 and absf(float(c["base_atk"]) - 72.0 * k) < 0.01 and float(c["def"]) == 70.0 and float(c["mr"]) == 70.0,
		"星 %d · 生命 %.1f · 攻 %.2f · 甲 %.0f" % [ss, float(c["maxHp"]), float(c["base_atk"]), float(c["def"])])

	## ── D 普攻四档 ──
	var got := {}
	for tier in [1, 2, 3]:
		me = _mk("left")
		var t1 := _mk("right", [], 0.0, 0.0)
		var t2 := _mk("right", [], 120.0, 0.0)   # 正好在目标身后同一条线上
		_field([me, t1, t2], tier)
		rec = _p.summon("left", tier)
		_p._land(rec)   # 跳过下落(落地结算不混进本段计数)
		c = rec.get("u", {})
		c["pos"] = Vector2(t1["pos"]) - Vector2(100.0, 0.0)
		for o in [t1, t2]:
			o["hp"] = 5000.0
			o["airborne"] = false
		var h1: float = float(t1["hp"])
		var h2: float = float(t2["hp"])
		_s._basic_attack(c, t1)
		got[tier] = [h1 - float(t1["hp"]), h2 - float(t2["hp"]), float(t2.get("_cent_shred", 0.0)), float(t1.get("def_shred", 0.0))]
	_ok("D 一档只打目标(身后 0)", got[1][0] > 0.0 and got[1][1] == 0.0, str(got[1]))
	_ok("D 二档贯穿: 身后那只吃约一半", got[2][1] > 0.0 and absf(got[2][1] / got[2][0] - 0.5) < 0.08, str(got[2]))
	_ok("D 三档每一刺削线上每个敌人 1 护甲 1 魔抗", got[3][2] == 1.0 and got[3][3] == 1.0, str(got[3]))
	## 削甲上限 30
	for _i in range(40):
		_s._basic_attack(c, _s._units[1])
	_ok("D 三档削甲每个敌人至多 30", float((_s._units[1] as Dictionary).get("_cent_shred", 0.0)) == 30.0, str((_s._units[1] as Dictionary).get("_cent_shred", 0.0)))
	## 四档: 第 4 下掷矛, 打最远的, 飞到才结算
	me = _mk("left")
	var near := _mk("right", [], 0.0, 0.0)
	var far := _mk("right", [], 700.0, 0.0)
	_field([me, near, far], 4)
	rec = _p.summon("left", 4)
	_p._land(rec)   # 跳过下落(落地结算不混进本段计数)
	c = rec.get("u", {})
	c["pos"] = Vector2(near["pos"]) - Vector2(100.0, 0.0)
	near["airborne"] = false
	far["airborne"] = false
	far["hp"] = 5000.0
	for _i in range(3):
		_s._basic_attack(c, near)
	var far_before := float(far["hp"])
	var th0: int = int(_p.stat["throw"])
	_s._basic_attack(c, near)
	var thrown: bool = int(_p.stat["throw"]) == th0 + 1
	var same_frame: float = far_before - float(far["hp"])
	_adv(1.5)
	_ok("D 四档第 4 下掷矛: 扔向最远的敌人, 出手那一刻还没伤害, 飞到才结算", thrown and same_frame == 0.0 and far_before - float(far["hp"]) > 0.0,
		"掷 %s · 出手时 %.0f · 飞到后 %.0f" % [str(thrown), same_frame, far_before - float(far["hp"])])

	## ── E 龟甲阵 ──
	var res := {}
	for tier in [1, 2, 3, 4]:
		me = _mk("left")
		foes = [_mk("right", [], 0.0, -60.0), _mk("right", [], 0.0, 60.0), _mk("right", [], 200.0, 0.0)]
		_field([me] + foes, tier)
		rec = _p.summon("left", tier)
		_p._land(rec)   # 跳过下落(落地结算不混进本段计数)
		c = rec.get("u", {})
		c["pos"] = Vector2(foes[0]["pos"]) - Vector2(80.0, -60.0)
		for o in foes:
			o["airborne"] = false
			o["hp"] = 5000.0
		var st0: Dictionary = _p.stat.duplicate()
		rec["en"] = SP.EN_MAX
		_adv(0.06)
		var dr_on: float = float(c.get("damage_reduction", 0.0))
		_adv(3.2)
		var dr_off: float = float(c.get("damage_reduction", 0.0))
		_adv(4.0)
		res[tier] = {"dr_on": dr_on, "dr_off": dr_off, "sweep": int(_p.stat["sweep"]) - int(st0["sweep"]),
			"poke": int(_p.stat["poke"]) - int(st0["poke"]), "cav": int(_p.stat["cav"]) - int(st0["cav"]), "cav_hit": int(_p.stat["cav_hit"]) - int(st0["cav_hit"])}
	_ok("E 一档: 举盾期间减伤 +20%, 3 秒后撤掉; 没有横扫 / 刺 / 骑兵",
		absf(res[1]["dr_on"] - 0.2) < 1e-6 and absf(res[1]["dr_off"]) < 1e-6 and res[1]["sweep"] == 0 and res[1]["poke"] == 0 and res[1]["cav"] == 0, str(res[1]))
	_ok("E 二档: 放盾横扫(周围敌人各一次)", res[2]["sweep"] >= 2 and res[2]["poke"] == 0, str(res[2]))
	_ok("E 三档: 举盾 3 秒里每 0.5 秒刺一圈", res[3]["poke"] >= 6 * 2 and res[3]["sweep"] >= 2, str(res[3]))
	_ok("E 四档: 冲出 4 名骑兵, 路上撞到敌人", res[4]["cav"] == 4 and res[4]["cav_hit"] >= 1, str(res[4]))

	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 长矛羁绊【百夫长】 (%d 条)" % _n)
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
