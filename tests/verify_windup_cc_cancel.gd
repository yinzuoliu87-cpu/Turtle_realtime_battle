extends Node
## verify_windup_cc_cancel.gd — 蓄力出手被控即取消(2026-10-16 第二批龟核查)
##   原来「蓄力 X 秒后出手」到点无条件结算: 被晕、被击飞、甚至阵亡照样开炮。
##   ① 延后条目带 "cc" 组标记: 等待期间施法者被晕 → 本条与同组后续段都不结算
##   ② 同样的条目施法者没被控 → 照样结算(防「全取消」的空检查)
##   ③ 走真技能入口: 宝箱炮击蓄力期被晕, 线上敌人不掉血; 不晕则掉血
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _fail := 0


func _ok(name: String, cond: bool, info = "") -> void:
	print("  [%s] %s  %s" % ["PASS" if cond else "FAIL", name, str(info)])
	if not cond:
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	var s = RB.new(); add_child(s)
	await get_tree().process_frame; await get_tree().process_frame
	s._units.clear(); s._over = false; s._edit_mode = false; s._deterministic = true
	s._pending_shots.clear()
	var a: Dictionary = s._spawn._make_unit("chest", "left", Vector2(300, 400))
	s._units.append(a)
	var hit := [0, 0, 0]
	var g1 := {}
	s._pending_shots.append({"delay": 0.3, "src": a, "cc": g1, "fn": func() -> void: hit[0] += 1})
	s._pending_shots.append({"delay": 0.6, "src": a, "cc": g1, "fn": func() -> void: hit[1] += 1})
	var n0: int = int(s._ballistics._ps_cc_cancel)
	s._ballistics._step_pending_shots(0.1)
	s._damage._stun(a, 0.5, "test", true)
	for i in 10:
		s._ballistics._step_pending_shots(0.1)
	_ok("① 蓄力期被晕: 第一段不结算", hit[0] == 0, hit[0])
	_ok("① 同组第二段也不结算(晕在它到点前已结束)", hit[1] == 0, hit[1])
	_ok("① 取消计数 = 2", int(s._ballistics._ps_cc_cancel) - n0 == 2, int(s._ballistics._ps_cc_cancel) - n0)
	a["stun_until"] = 0.0
	s._pending_shots.append({"delay": 0.3, "src": a, "cc": {}, "fn": func() -> void: hit[2] += 1})
	for i in 5:
		s._ballistics._step_pending_shots(0.1)
	_ok("② 没被控: 照样结算", hit[2] == 1, hit[2])

	## ③ 真入口: 宝箱炮击(蓄力 0.4 秒)
	var res := []
	for stun in [false, true]:
		s._units.clear(); s._pending_shots.clear()
		var c: Dictionary = s._spawn._make_unit("chest", "left", Vector2(300, 400))
		var e: Dictionary = s._spawn._make_unit("stone", "right", Vector2(520, 400))
		e["maxHp"] = 1e7; e["hp"] = 1e7
		s._units.append(c); s._units.append(e)
		s._chest_sys._sk_chest_cannon(c, e) if s._chest_sys.has_method("_sk_chest_cannon") else null
		if stun:
			s._damage._stun(c, 1.0, "test", true)
		for i in 8:
			s._ballistics._step_pending_shots(0.1)
		res.append(1e7 - float(e["hp"]))
	_ok("③ 分母: 宝箱炮击入口存在", s._chest_sys.has_method("_sk_chest_cannon"))
	_ok("③ 不晕: 炮击命中掉血", float(res[0]) > 0.0, res[0])
	_ok("③ 蓄力期被晕: 炮击取消不掉血", float(res[1]) == 0.0, res[1])
	print("ALL PASS — 蓄力被控取消" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
