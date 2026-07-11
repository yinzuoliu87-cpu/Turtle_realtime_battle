extends Node
## verify_two_head_fusion.gd — 双头技3融合·魔法波改制自证(用户2026-07-11)
##   每段0.8ATK(物理/真实交替)+附加轻击飞; 波数基础4·每次释放+1累积到战斗结束
##   飞行/击飞观感留用户 F5(走tween/pending·headless不推进)

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _fail := 0
func _ok(n, c, d=""):
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	var sc = RTScene.new(); add_child(sc)
	await get_tree().process_frame
	await get_tree().process_frame
	sc.set_process(false); sc.set_physics_process(false)
	sc._units.clear(); sc._t = 0.0; sc._over = false; sc._edit_mode = false
	sc._pending_shots.clear()

	var dh: Dictionary = sc._make_unit("two_head", "left", Vector2(200, 400))
	dh["atk"] = 100.0; dh["crit"] = 0.0; dh["armor_pen"] = 0.0; dh["armor_pen_pct"] = 0.0; dh["damage_amp"] = 0.0
	sc._units.append(dh)
	var tgt: Dictionary = sc._make_unit("basic", "right", Vector2(320, 400))
	tgt["def"] = 0.0; tgt["base_def"] = 0.0; tgt["mr"] = 0.0; tgt["base_mr"] = 0.0
	tgt["damage_reduction"] = 0.0; tgt["shield"] = 0.0; tgt["maxHp"] = 100000.0; tgt["hp"] = 100000.0
	tgt["no_basic"] = true; tgt["no_move"] = true; tgt["_st_taken"] = 0; tgt["airborne"] = false
	sc._units.append(tgt)

	# ── 物理波 0.8A = 80 ──
	sc._two_head_fusion_wave_hit(dh, tgt, false, null)
	_ok("物理波段 0.8A = 80", int(tgt["_st_taken"]) == 80, "taken=%d" % int(tgt["_st_taken"]))
	_ok("物理波附加击飞(airborne)", bool(tgt.get("airborne", false)) == true)

	# ── 真实波 0.8A = 80 ──
	tgt["_st_taken"] = 0; tgt["airborne"] = false; tgt["vy"] = 0.0; tgt["vx"] = 0.0; tgt["vz"] = 0.0
	sc._two_head_fusion_wave_hit(dh, tgt, true, null)
	_ok("真实波段 0.8A = 80", int(tgt["_st_taken"]) == 80, "taken=%d" % int(tgt["_st_taken"]))

	# ── 波数量: 基础4·每次释放+1累积 ──
	dh["two_wave_count"] = 4
	sc._pending_shots.clear()
	sc._sk_two_head_fusion(dh, tgt)
	_ok("首次释放 = 4 段波", sc._pending_shots.size() == 4, "n=%d" % sc._pending_shots.size())
	_ok("释放后波数 +1 = 5", int(dh["two_wave_count"]) == 5, "cnt=%d" % int(dh["two_wave_count"]))
	sc._pending_shots.clear()
	sc._sk_two_head_fusion(dh, tgt)
	_ok("★再释放 = 5 段波(累积)", sc._pending_shots.size() == 5, "n=%d" % sc._pending_shots.size())
	_ok("波数再 +1 = 6", int(dh["two_wave_count"]) == 6, "cnt=%d" % int(dh["two_wave_count"]))

	print("")
	print(("ALL PASS — 双头技3融合魔法波改制 正常" if _fail == 0 else "FAIL x%d" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)
