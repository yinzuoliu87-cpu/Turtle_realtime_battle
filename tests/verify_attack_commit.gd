extends Node
## verify_attack_commit.gd — 出手承诺(用户2026-07-12): 前摇走完必打出伤害, 目标前摇期跑出射程也不作废
##   根治"近战被风筝→抬手→目标跑→攻击作废→再追→再空转→伤害完全打不出"
const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _fail := 0
func _ok(n, c, d=""):
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _run(sc, teleport: bool) -> float:
	sc._units.clear(); sc._t = 0.0; sc._over = false; sc._edit_mode = false; sc._dl_state = "fight"
	var m: Dictionary = sc._make_unit("basic", "left", Vector2(400, 400))
	m["active_skills"] = []; m["maxHp"] = 1000000.0; m["hp"] = 1000000.0
	sc._units.append(m)
	var k: Dictionary = sc._make_unit("angel", "right", Vector2(480, 400))
	k["active_skills"] = []; k["no_basic"] = true; k["no_move"] = true; k["move_spd"] = 0.0
	k["maxHp"] = 1000000.0; k["hp"] = 1000000.0
	sc._units.append(k)
	var hp0: float = float(k["hp"])
	var phase := 0; var steps_after := 0; var dmg_commit := 0.0
	for i in range(400):
		sc._t += 0.05
		for u in sc._units.duplicate():
			if u.get("alive", false): sc._tick_unit(u, 0.05)
		sc._apply_separation_pass(0.05); sc._step_pending_shots(0.05); sc._step_projectiles(0.05)
		if phase == 0 and str(m.get("state", "")) == "windup" and str(m.get("pending", "")) == "B":
			if teleport: k["pos"] = Vector2(1500, 400)   # 前摇期风筝跑出射程
			phase = 1; steps_after = 0
		elif phase == 1:
			steps_after += 1
			if str(m.get("state", "")) == "move":
				dmg_commit = hp0 - float(k["hp"]); break
			if steps_after > 25: break
	return dmg_commit

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	var sc = RTScene.new(); add_child(sc)
	await get_tree().process_frame
	await get_tree().process_frame
	sc.set_process(false); sc.set_physics_process(false)

	var d_normal: float = _run(sc, false)
	_ok("目标在射程内→前摇结束打出伤害(基线)", d_normal > 0.0, "dmg=%d" % int(d_normal))
	var d_kite: float = _run(sc, true)
	_ok("★目标前摇期跑出射程(1100px)→攻击仍打出(出手承诺)", d_kite > 0.0, "dmg=%d" % int(d_kite))

	print("")
	print(("ALL PASS — 出手承诺: 前摇走完必打出, 不被风筝空转" if _fail == 0 else "FAIL x%d" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)
