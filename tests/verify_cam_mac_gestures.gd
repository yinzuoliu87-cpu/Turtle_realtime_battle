extends Node
## verify_cam_mac_gestures.gd — Mac 触控板 / 妙控鼠标能缩放战场(2026-10-14 内测「mac 设备鼠标诸多问题」)
##
## Godot 在 macOS 上: 触控板与妙控鼠标的滚动发 InputEventPanGesture(不发滚轮键),
##   触控板双指捏合发 InputEventMagnifyGesture。原来 _cam_handle_input 只认滚轮 ⇒ Mac 上战场缩放不了。
## 判据(事件经 Viewport.push_input 走真入口 _unhandled_input):
##   ① 往上滚(delta.y<0) ⇒ 放大; 往下滚 ⇒ 缩小(与滚轮同向)
##   ② 捏合 factor>1 ⇒ 放大; <1 ⇒ 缩小
##   ③ 分母: 同一条路上的滚轮键也确实改了缩放(证明事件到得了相机)

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n)
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _send(s, ev: InputEvent) -> float:
	s._cam_zoom = 1.0
	s._apply_cam_zoom()
	if ev is InputEventMouse or ev is InputEventGesture:
		ev.position = get_viewport().get_visible_rect().get_center()
	get_viewport().push_input(ev, true)
	await get_tree().process_frame
	return float(s._cam_zoom)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var s = RTScene.new()
	get_tree().root.add_child(s)
	for _i in range(30):
		await get_tree().process_frame
	print("=== Mac 手势缩放战场 ===")

	var wh := InputEventMouseButton.new(); wh.button_index = MOUSE_BUTTON_WHEEL_UP; wh.pressed = true
	var z_wheel: float = await _send(s, wh)
	_ok("③ 分母: 滚轮往上 ⇒ 放大(事件到得了相机)", z_wheel > 1.0, "zoom=%.3f" % z_wheel)

	var up := InputEventPanGesture.new(); up.delta = Vector2(0, -1.0)
	var z_up: float = await _send(s, up)
	var dn := InputEventPanGesture.new(); dn.delta = Vector2(0, 1.0)
	var z_dn: float = await _send(s, dn)
	_ok("① ★妙控鼠标/触控板往上滚 ⇒ 放大", z_up > 1.0, "zoom=%.3f" % z_up)
	_ok("① ★往下滚 ⇒ 缩小", z_dn < 1.0, "zoom=%.3f" % z_dn)

	var mi := InputEventMagnifyGesture.new(); mi.factor = 1.2
	var z_in: float = await _send(s, mi)
	var mo := InputEventMagnifyGesture.new(); mo.factor = 0.8
	var z_out: float = await _send(s, mo)
	_ok("② ★触控板捏合张开 ⇒ 放大", z_in > 1.0, "zoom=%.3f" % z_in)
	_ok("② ★捏合收拢 ⇒ 缩小", z_out < 1.0, "zoom=%.3f" % z_out)

	s.queue_free()
	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — Mac 手势缩放战场 (%d/%d)" % [_n, _n])
	get_tree().quit(1 if _fail > 0 else 0)
