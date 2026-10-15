extends Node
## verify_line_finish_target.gd — 画龙点睛打谁(2026-10-15 用户「画龙点睛, 你觉得有bug吗」)
##   文案: 对墨迹层数最多的敌人点下终笔; 场上无墨迹时转而攻击最近的敌人。
##   原代码只有 `ink > best_ink`(起始 -1) ⇒ 全场 0 层时打的是【列表第一个】, 并列时同理。
##   ① 全场 0 层 ⇒ 打最近的(远的那个在列表前面, 按旧代码会被选中)
##   ② 层数并列 ⇒ 打最近的
##   ③ 层数多的照样优先, 哪怕更远

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond: print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else: _fail += 1; print("  [FAIL] ", name, "  ", detail)

func _mk(scene, id: String, side: String, pos: Vector2) -> Dictionary:
	var u: Dictionary = scene._spawn._make_unit(id, side, pos)
	u["crit"] = 0.0
	u["maxHp"] = 100000.0; u["hp"] = 100000.0
	u["shield"] = 0.0
	u["_auraShieldVal"] = 0.0
	scene._units.append(u)
	return u

## 摆一只线条龟 + 两个敌人(far 先进列表), 放一次画龙点睛, 返回 [far 掉血, near 掉血]
func _cast(scene, far_ink: int, near_ink: int) -> Array:
	scene._units.clear()
	var line: Dictionary = _mk(scene, "line", "left", Vector2(100, 400))
	var far: Dictionary = _mk(scene, "ninja", "right", Vector2(900, 400))
	var near: Dictionary = _mk(scene, "ninja", "right", Vector2(250, 400))
	far["stacks"] = {"ink": far_ink}
	near["stacks"] = {"ink": near_ink}
	scene._line_sys._sk_line_finish(line)
	return [100000.0 - float(far["hp"]), 100000.0 - float(near["hp"])]

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	scene.set_process(false); scene.set_physics_process(false)
	scene._t = 0.0; scene._over = false; scene._edit_mode = false

	var r1 := _cast(scene, 0, 0)
	_ok("① 全场 0 层 ⇒ 打最近的(远的在列表前面)", r1[1] > 0.0 and r1[0] == 0.0, "far=%.0f near=%.0f" % r1)
	var r2 := _cast(scene, 3, 3)
	_ok("② 层数并列 ⇒ 打最近的", r2[1] > 0.0 and r2[0] == 0.0, "far=%.0f near=%.0f" % r2)
	var r3 := _cast(scene, 4, 1)
	_ok("③ 层数多的优先(更远也打它)", r3[0] > 0.0 and r3[1] == 0.0, "far=%.0f near=%.0f" % r3)
	print("ALL PASS — 画龙点睛选目标" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
