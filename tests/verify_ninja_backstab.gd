extends Node
## verify_ninja_backstab.gd — 忍者·背刺(ninjaBackstab)自证
##   ①+5穿甲(5秒) ②闪现到【全场最远敌】身后 ③背刺3段(每300ms一刀·hitStaggerMs)只打最远那只·近敌不吃
##   每段 0.6667A 物理(共2.0A)。闪现刀光/斩弧观感留用户 F5。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond: print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else: _fail += 1; print("  [FAIL] ", name, "  ", detail)

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	scene.set_process(false); scene.set_physics_process(false)
	scene._units.clear(); scene._t = 0.0; scene._over = false; scene._edit_mode = false

	var ninja: Dictionary = scene._make_unit("ninja", "left", Vector2(200, 400))
	ninja["atk"] = 100.0
	ninja["crit"] = 0.0
	ninja["armor_pen"] = 0.0; ninja["armor_pen_pct"] = 0.0; ninja["damage_amp"] = 0.0
	scene._units.append(ninja)
	var near1: Dictionary = scene._make_unit("basic", "right", Vector2(320, 340))   # 近(~140)
	var near2: Dictionary = scene._make_unit("basic", "right", Vector2(320, 460))   # 近
	var far1: Dictionary = scene._make_unit("basic", "right", Vector2(670, 400))    # 远(~470=全场最远)
	for d in [near1, near2, far1]:
		d["base_def"] = 15.0; d["def"] = 15.0          # def15 + 背刺+15穿甲 → resist0 → mult1.0(验穿甲=15)
		d["damage_reduction"] = 0.0; d["shield"] = 0.0
		d["maxHp"] = 1000000.0; d["hp"] = 1000000.0
		d["no_basic"] = true; d["no_move"] = true; d["move_spd"] = 0.0
		d["_st_taken"] = 0
		scene._units.append(d)

	# 放背刺 (tgt 传近的, 应自己重定向到最远的 far1)
	scene._sk_ninja_backstab(ninja, near1)

	_ok("获得+15穿甲", int(round(float(ninja.get("armor_pen", 0.0)))) == 15, "armor_pen=%.1f" % float(ninja.get("armor_pen", 0.0)))
	var dist_far: float = ninja["pos"].distance_to(far1["pos"])
	_ok("★闪现到【最远敌】身后(贴近far1≤80)", dist_far <= 80.0, "闪现后距far1=%.0f" % dist_far)

	# 推进 pending_shots ~0.7s → 3段全落 (delay 0/0.3/0.6)
	for i in range(16):
		scene._t += 0.05
		scene._step_pending_shots(0.05)
	var tf: int = int(far1.get("_st_taken", 0))
	var tn: int = int(near1.get("_st_taken", 0)) + int(near2.get("_st_taken", 0))
	# 每段 round(100×0.6667×1.0)=67 ×3 = 201 (共≈2.0A)
	_ok("背刺3段只打最远那只(共201≈2.0A)", tf == 201, "far承伤=%d" % tf)
	_ok("★近敌不受背刺(只打最远)", tn == 0, "近敌合计承伤=%d" % tn)

	print("")
	print(("ALL PASS — 忍者背刺 正常" if _fail == 0 else "FAIL x%d" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)
