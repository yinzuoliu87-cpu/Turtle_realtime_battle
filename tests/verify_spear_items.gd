extends Node
## verify_spear_items.gd —— 长矛 10 件逐件门禁(2026-11-26 · 方案书 docs/plans/20261126-长矛羁绊.md §4)
##   每件单独生效(双方羁绊档位都是 0)。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SB := preload("res://scripts/systems/equip/eq_spear_batch.gd")

var _n := 0
var _fail := 0
var _s
var _b


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _mk(side: String, ids: Array = [], dx: float = 0.0, dy: float = 0.0) -> Dictionary:
	var c: Vector2 = _s._arena_center
	var u: Dictionary = _s._spawn._make_unit("green", side, c + Vector2((-150.0 if side == "left" else 150.0) + dx, dy))
	for k in ["shield", "crit", "dodge_bonus", "damage_reduction", "damage_amp", "armor_pen", "armor_pen_pct"]:
		u[k] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["maxHp"] = 5000.0
	u["hp"] = 5000.0
	u["base_atk"] = 100.0
	u["buffs"] = []
	u["airborne"] = false
	_s._recalc_stats(u)
	var eq: Array = []
	for id in ids:
		eq.append({"id": id, "star": 1})
	u["equips"] = eq
	return u


func _field(units: Array) -> void:
	_b.clear_all()
	_s._units.clear()
	_s._units.append_array(units)
	_s._synergy._by_side = {"left": {}, "right": {}}
	for u in units:
		if not (u.get("equips", []) as Array).is_empty():
			_s._equip_sys._stats.apply_unit(u)


func _adv(sec: float, units: Array = [], step: float = 0.05) -> void:
	var t := 0.0
	while t < sec - 1e-6:
		_s._t += step
		_b.tick(step)
		for u in units:
			_b.tick_unit(u, step)
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
	_s._t = 3000.0
	_b = _s._equip_sys._spear_sys
	print("=== 长矛 10 件 ===")

	## 137 竹矛
	var me := _mk("left", ["p2eq_137"])
	var t1 := _mk("right", [], 0.0, 0.0)
	var t2 := _mk("right", [], 120.0, 0.0)
	_field([me, t1, t2])
	me["pos"] = Vector2(t1["pos"]) - Vector2(80.0, 0.0)
	var h2: Array = []
	for _i in range(3):
		var before := float(t2["hp"])
		_s._basic_attack(me, t1)
		h2.append(before - float(t2["hp"]))
	_ok("137 竹矛: 前两下身后不挨, 第 3 下刺穿身后那只(60% 攻击力过护甲)", h2[0] == 0.0 and h2[1] == 0.0 and absf(h2[2] - 0.6 * float(me["atk"])) < 1.5, str(h2))

	## 138 鱼叉
	me = _mk("left", ["p2eq_138"])
	t1 = _mk("right")
	_field([me, t1])
	_s._basic_attack(me, t1)
	var hb := float(t1["hp"])
	t1["pos"] = Vector2(t1["pos"]) + Vector2(60.0, 0.0)
	_adv(0.05)
	var at60 := hb - float(t1["hp"])
	t1["pos"] = Vector2(t1["pos"]) + Vector2(50.0, 0.0)
	_adv(0.05)
	var at110 := hb - float(t1["hp"])
	_ok("138 鱼叉: 挂倒钩后移动 60 码不掉血, 累计过 100 码掉 15", at60 == 0.0 and absf(at110 - 15.0) < 0.5, "%.0f / %.0f" % [at60, at110])

	## 139 标枪
	me = _mk("left", ["p2eq_139"])
	var nearf := _mk("right", [], 0.0, 0.0)
	var farf := _mk("right", [], 600.0, 0.0)
	_field([me, nearf, farf])
	var fh := float(farf["hp"])
	_adv(6.02, [me])
	var thrown := int(_b.stat["jav"])
	var instant := fh - float(farf["hp"])
	_adv(1.5, [me])
	_ok("139 标枪: 第 6 秒掷向最远的, 出手时没伤害, 飞到才打 + 减速", thrown == 1 and instant == 0.0 and fh - float(farf["hp"]) > 0.0 and float(farf.get("slow_until", 0.0)) > _s._t - 1.0,
		"掷 %d · 出手 %.0f · 到后 %.0f" % [thrown, instant, fh - float(farf["hp"])])

	## 140 骑枪
	me = _mk("left", ["p2eq_140"])
	t1 = _mk("right")
	_field([me, t1])
	_b.on_spawn(me, "p2eq_140", 0)
	me["pos"] = Vector2(me["pos"]) + Vector2(-320.0, 0.0)
	_adv(0.05, [me])
	var h0 := float(t1["hp"])
	_s._basic_attack(me, t1)
	var with_lance := h0 - float(t1["hp"])
	h0 = float(t1["hp"])
	_s._basic_attack(me, t1)
	var plain := h0 - float(t1["hp"])
	_ok("140 骑枪: 移动 320 码攒 3 层, 下一击多 3 × 15% = 45%, 再下一击回到普通", absf((with_lance - plain) - 0.45 * float(me["atk"])) < 2.0, "%.0f / %.0f" % [with_lance, plain])

	## 141 长戟
	me = _mk("left", ["p2eq_141"])
	t1 = _mk("right", [], 0.0, 0.0)
	var side_f := _mk("right", [], -40.0, 60.0)
	var back_f := _mk("right", [], -400.0, 0.0)
	_field([me, t1, side_f, back_f])
	me["pos"] = Vector2(t1["pos"]) - Vector2(90.0, 0.0)
	back_f["pos"] = Vector2(me["pos"]) - Vector2(100.0, 0.0)
	var hs := float(side_f["hp"])
	var hk := float(back_f["hp"])
	_s._basic_attack(me, t1)
	_ok("141 长戟: 前方扇形里的那只吃 40%, 身后的不吃", absf(hs - float(side_f["hp"]) - 0.4 * float(me["atk"])) < 1.5 and hk == float(back_f["hp"]),
		"前 %.0f · 后 %.0f" % [hs - float(side_f["hp"]), hk - float(back_f["hp"])])

	## 142 盾矛
	me = _mk("left", ["p2eq_142"])
	var front := _mk("right", [], 0.0, 0.0)
	var behind := _mk("right", [], -500.0, 0.0)
	_field([me, front, behind])
	me["face_right"] = true
	behind["pos"] = Vector2(me["pos"]) - Vector2(100.0, 0.0)
	var hm := float(me["hp"])
	_s._damage._apply_damage_from(front, me, 100, Color.WHITE)
	var from_front := hm - float(me["hp"])
	hm = float(me["hp"])
	_s._damage._apply_damage_from(behind, me, 100, Color.WHITE)
	var from_back := hm - float(me["hp"])
	var c0 := int(_b.stat["shsp_counter"])
	var fhp := float(front["hp"])
	for _i in range(4):
		_s._damage._apply_damage_from(front, me, 10, Color.WHITE)
	_ok("142 盾矛: 正面 100 ⇒ 85, 背后照吃 100; 挨满 5 下反刺攻击者", absf(from_front - 85.0) < 1.0 and absf(from_back - 100.0) < 1.0 and int(_b.stat["shsp_counter"]) == c0 + 1 and float(front["hp"]) < fhp,
		"正 %.0f · 背 %.0f · 反刺 %d" % [from_front, from_back, int(_b.stat["shsp_counter"]) - c0])

	## 143 方天画戟
	me = _mk("left", ["p2eq_143"])
	var a1 := _mk("right", [], 0.0, 0.0)
	var a2 := _mk("right", [], 0.0, 0.0)
	_field([me, a1])
	a1["pos"] = Vector2(me["pos"]) + Vector2(100.0, 0.0)
	var lone := float(a1["hp"])
	_adv(2.0, [me])
	var one_enemy := lone - float(a1["hp"])
	_field([me, a1, a2])
	a2["pos"] = Vector2(me["pos"]) + Vector2(0.0, 100.0)
	var h_a1 := float(a1["hp"])
	_adv(2.05, [me])
	_ok("143 方天画戟: 身边只有 1 个敌人不转; 2 个时每秒横扫(2 秒 2 次, 每次 30% × 攻击力)", one_enemy == 0.0 and absf((h_a1 - float(a1["hp"])) - 2.0 * 0.3 * float(me["atk"])) < 3.0,
		"一敌 %.0f · 两敌 %.0f" % [one_enemy, h_a1 - float(a1["hp"])])

	## 144 投矛器
	me = _mk("left", ["p2eq_144"])
	var grp: Array = [_mk("right", [], 200.0, -40.0), _mk("right", [], 220.0, 0.0), _mk("right", [], 200.0, 40.0)]
	_field([me] + grp)
	for i in range(3):   # 220 码外上下各 50 码(扇形张角 0.5 弧度 ⇒ 220 码处两边的矛偏 ±55 码)
		grp[i]["pos"] = Vector2(me["pos"]) + Vector2(220.0, -55.0 + 55.0 * float(i))
	_adv(10.02, [me])
	var hits0 := int(_b.stat["atl_hit"])
	_adv(1.5, [me])
	_ok("144 投矛器: 第 10 秒朝敌群扇形掷 3 根, 飞到才中", int(_b.stat["atl"]) == 1 and hits0 == 0 and int(_b.stat["atl_hit"]) >= 2, "掷 %d · 命中 %d" % [int(_b.stat["atl"]), int(_b.stat["atl_hit"])])

	## 145 永恒之枪
	me = _mk("left", ["p2eq_145"])
	var small := _mk("right", [], 0.0, -80.0)
	var big := _mk("right", [], 300.0, 80.0)
	_field([me, small, big])
	big["maxHp"] = 9000.0
	big["hp"] = 9000.0
	_adv(8.02, [me])
	var hb2 := float(big["hp"])
	_adv(1.0, [me])
	var want: int = _s._phys_after_armor(me, 9000.0 * 0.08, big)
	_ok("145 永恒之枪: 第 8 秒掷向血最多的, 飞到才打: 目标最大生命 8% 物理 + 钉住 1.5 秒",
		int(_b.stat["eternal_hit"]) == 1 and absf(hb2 - float(big["hp"]) - float(want)) < 1.5 and float(big.get("stun_until", 0.0)) > _s._t and float(small["hp"]) == 5000.0,
		"命中 %d · 掉 %.0f(应 %d)" % [int(_b.stat["eternal_hit"]), hb2 - float(big["hp"]), want])

	## 146 圣枪
	me = _mk("left", ["p2eq_146"])
	t1 = _mk("right")
	_field([me, t1])
	me["pos"] = Vector2(t1["pos"]) - Vector2(80.0, 0.0)
	me["hp"] = 2000.0
	var hh := float(t1["hp"])
	_s._basic_attack(me, t1)
	_s._basic_attack(me, t1)
	var two := hh - float(t1["hp"])
	var meh := float(me["hp"])
	_s._basic_attack(me, t1)
	var third := hh - float(t1["hp"]) - two
	_ok("146 圣枪: 第 3 下引爆, 多打 150 魔法, 并回 5% 最大生命值", int(_b.stat["holy"]) == 1 and third > float(me["atk"]) + 100.0 and float(me["hp"]) - meh > 0.04 * float(me["maxHp"]),
		"第三下 %.0f · 回 %.0f" % [third, float(me["hp"]) - meh])

	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 长矛 10 件 (%d 条)" % _n)
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
