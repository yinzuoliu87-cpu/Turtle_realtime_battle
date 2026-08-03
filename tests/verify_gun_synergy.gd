extends Node
## verify_gun_synergy.gd — 枪羁绊【三座炮台 / 金弹 / 火控】(用户 2026-08-03 定)
##
## ★炮台做成【逻辑实体】而不是场上单位 —— 原设计里它没有血量也不会被摧毁,
##   只是"一个位置 + 一个计时器"。方案书把它估成"全表最贵的一条"是按【新单位】算的
##   (生成/朝向/弹道/阵亡/换路重建), 那套复杂度这里根本不需要。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const GUN := preload("res://scripts/systems/equip/gun_synergy_system.gd")

var _n := 0
var _fail := 0
var _scene
func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	var s = RB.new(); add_child(s); _scene = s
	await get_tree().process_frame; await get_tree().process_frame
	var G := _ids("枪", 9)
	_ok("★分母: 找到 %d 件枪" % G.size(), G.size() >= 9)
	print("=== 枪羁绊 ===")

	# ── ① 火控: 顶档才有, 按【携带者身上】件数, 最高 40% ──
	for cfg in [[3, 3, 0.0], [6, 3, 0.0], [9, 3, 0.40], [9, 1, 0.20], [9, 0, 0.0]]:
		var tn: int = int(cfg[0]); var mine: int = int(cfg[1])
		var me := _mk("left", G.slice(0, mine))
		var arr: Array = [me]
		var k: int = mine
		while k < tn:
			arr.append(_mk("left", G.slice(k, mini(k + 3, tn)))); k += 3
		arr.append(_mk("right", []))
		_run(s, arr)
		_ok("① 枪 %d 件·本龟带 %d 把 → 火控 %.0f%%" % [tn, mine, float(cfg[2]) * 100.0],
			absf(float(me.get("_fire_ctrl", 0.0)) - float(cfg[2])) < 0.001,
			"实得 %.2f" % float(me.get("_fire_ctrl", 0.0)))

	# ── ② 炮台一: 3 件起, 直线打敌人 + 给最低血友军回血 ──
	var c1 := _mk("left", G.slice(0, 3))
	var hurt := _mk("left", [])
	hurt["hp"] = hurt["maxHp"] * 0.2
	var f1 := _mk("right", []); var f2 := _mk("right", [])
	# 把两个敌人摆在炮台→最近敌的直线上
	var org: Vector2 = s._gun_syn._turret_pos("left", 0)
	f1["pos"] = org + Vector2(300, 0); f2["pos"] = org + Vector2(600, 0)
	_run(s, [c1, hurt, f1, f2])
	var h0: float = float(hurt["hp"])
	var e1: float = float(f1["hp"]); var e2: float = float(f2["hp"])
	s._gun_syn._t_acc = 0.0
	s._gun_syn.tick(2.6)
	_ok("② 炮台一: 直线上【两个】敌人都吃到伤害",
		float(f1["hp"]) < e1 and float(f2["hp"]) < e2,
		"敌1 -%.0f / 敌2 -%.0f" % [e1 - float(f1["hp"]), e2 - float(f2["hp"])])
	_ok("② 炮台一: 最低血友军回了血(30%% × 造成伤害)", float(hurt["hp"]) > h0,
		"%.0f → %.0f" % [h0, float(hurt["hp"])])
	# 对照: 2 件不够, 一炮不放
	var lone := _mk("left", G.slice(0, 2))
	var lf := _mk("right", [])
	lf["pos"] = s._gun_syn._turret_pos("left", 0) + Vector2(300, 0)
	_run(s, [lone, lf])
	var lh: float = float(lf["hp"])
	s._gun_syn._t_acc = 0.0
	s._gun_syn.tick(2.6)
	_ok("② ★对照: 只有 2 件枪(未达首档) → 炮台不生成", absf(float(lf["hp"]) - lh) < 0.5,
		"敌掉 %.0f" % (lh - float(lf["hp"])))

	# ── ③ 炮台二: 6 件起, 护盾↔弹幕交替 ──
	var c2 := _mk("left", G.slice(0, 3))
	var ally2 := _mk("left", [])
	var foe2 := _mk("right", [])
	foe2["pos"] = s._gun_syn._turret_pos("left", 0) + Vector2(0, 400)   # 挪出直线, 隔离炮台一
	_run(s, [c2, ally2, _mk("left", G.slice(3, 6)), foe2])
	s._gun_syn.clear()
	ally2["shield"] = 0.0
	s._gun_syn._t2_acc = 0.0
	s._gun_syn.tick(5.1)
	_ok("③ 炮台二(每5秒)·第一拍: 转护盾均摊全队", float(ally2.get("shield", 0.0)) > 0.0,
		"护盾 %.0f" % float(ally2.get("shield", 0.0)))
	var fh: float = float(foe2["hp"])
	s._gun_syn._t2_acc = 0.0
	s._gun_syn.tick(5.1)
	_ok("③ 炮台二(每5秒)·第二拍: 化弹幕打敌方全体", float(foe2["hp"]) < fh,
		"敌掉 %.0f" % (fh - float(foe2["hp"])))
	# 对照: 3 件时没有第二座
	var c3 := _mk("left", G.slice(0, 3))
	var ally3 := _mk("left", [])
	var foe3 := _mk("right", [])
	foe3["pos"] = s._gun_syn._turret_pos("left", 0) + Vector2(0, 400)
	_run(s, [c3, ally3, foe3])
	s._gun_syn.clear()
	ally3["shield"] = 0.0
	s._gun_syn._t2_acc = 0.0
	s._gun_syn.tick(5.1)
	_ok("③ ★对照: 3 件时【没有】第二座炮台(不给护盾)",
		absf(float(ally3.get("shield", 0.0))) < 0.5, "护盾 %.0f" % float(ally3.get("shield", 0.0)))

	# ── ④ 金弹: 射满 4/3/2 发额外射一发 ──
	for cfg2 in [[3, 4], [6, 3], [9, 2]]:
		var tn2: int = int(cfg2[0]); var per: int = int(cfg2[1])
		var gu := _mk("left", G.slice(0, 3))
		var arr2: Array = [gu]
		var kk: int = 3
		while kk < tn2:
			arr2.append(_mk("left", G.slice(kk, mini(kk + 3, tn2)))); kk += 3
		arr2.append(_mk("right", []))
		_run(s, arr2)
		s._pending_shots.clear()
		gu["_gun_shot_ct"] = {}
		s._queue_shots(per, 0.05, func() -> void: pass, gu, "p2eq_048")
		_ok("④ 枪 %d 件: 射满 %d 发 → 多出 1 发金弹(共 %d 条)" % [tn2, per, per + 1],
			s._pending_shots.size() == per + 1, "实得 %d" % s._pending_shots.size())
	# 对照: 未激活不给金弹
	var g0 := _mk("left", G.slice(0, 2))
	_run(s, [g0, _mk("right", [])])
	s._pending_shots.clear(); g0["_gun_shot_ct"] = {}
	s._queue_shots(6, 0.05, func() -> void: pass, g0, "p2eq_048")
	_ok("④ ★对照: 未激活(2件) → 6 发就是 6 发, 没有金弹",
		s._pending_shots.size() == 6, "实得 %d" % s._pending_shots.size())

	s._units.clear(); s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 枪羁绊" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

func _ids(t: String, n: int) -> Array:
	var out: Array = []
	for e in DataRegistry.phase2_equipment:
		if _scene.Phase2Types.type_of(str((e as Dictionary).get("id", ""))) == t:
			out.append(str((e as Dictionary).get("id", "")))
		if out.size() >= n: break
	return out

func _run(s, units: Array) -> void:
	s._units.clear(); s._units.append_array(units)
	s._synergy._by_side = {"left": {}, "right": {}}
	s._synergy.apply_all()
	s._gun_syn.apply_all()

func _mk(side: String, ids: Array) -> Dictionary:
	var c: Vector2 = _scene.ARENA.position + _scene.ARENA.size * 0.5
	var off := Vector2(-200.0, 0.0) if side == "left" else Vector2(200.0, 0.0)
	var u: Dictionary = _scene._spawn._make_unit("green", side, c + off)
	u["maxHp"] = 3000.0; u["hp"] = 3000.0; u["shield"] = 0.0
	u["crit"] = 0.0; u["def"] = 0.0; u["base_def"] = 0.0; u["mr"] = 0.0; u["base_mr"] = 0.0
	u["flat_dr"] = 0.0; u["dodge_bonus"] = 0.0
	var e: Array = []
	for i in ids: e.append({"id": str(i), "star": 1})
	u["equips"] = e; u["eq_state"] = {}
	return u
