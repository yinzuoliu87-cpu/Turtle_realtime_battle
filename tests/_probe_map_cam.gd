extends Node
## _probe_map_cam —— 录屏用探针(不进门禁): 正式双路对局, 开打 5 秒后真实鼠标拖动视角上下 + 滚轮缩放, 看地图边缘/远景。
## 跑法: <godot> --path . res://tests/_probe_map_cam.tscn --resolution 1560x720 --write-movie C:/tmp/mapcam/f.avi --fixed-fps 30
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BE := preload("res://scripts/net/backend.gd")
const AT := preload("res://scripts/gamedata/arena_theme.gd")
var _gs


func _ready() -> void:
	_gs = get_node("/root/GameState")
	_gs.reset_dual_lane()
	_gs.test_mode = true
	_gs.tutorial_active = false
	_gs.onboarded = true
	_gs.season_level = 6
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261007
	_gs.dual_ghost = BE.make_bot(3, rng)
	_gs.dual_active = true
	var s = RB.new()
	add_child(s)
	get_tree().current_scene = s
	var last := ""
	var stf := 0
	var fight_f := -1
	for i in range(30 * 40):
		await get_tree().process_frame
		var st: String = str(s._dl_state)
		if st != last:
			last = st
			stf = 0
			print("[MAPCAM] state=", st, " frame=", i, " theme=", AT.forced)
		stf += 1
		if (st == "overview" or st == "lane_settle") and stf == 20:
			s._dl_sys._dl_present_click()
		elif st == "place" and stf == 30 and is_instance_valid(s._dl_go_btn):
			s._dl_go_btn.pressed.emit()
		if st == "fight" and fight_f < 0:
			fight_f = i
		if fight_f >= 0 and i - fight_f == 150:
			await _drive(s)
			break
	get_tree().quit()


func _btn(pos: Vector2, idx: int, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.global_position = pos
	e.button_index = idx
	e.pressed = pressed
	if idx == MOUSE_BUTTON_LEFT and pressed:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)


func _drag(from: Vector2, delta: Vector2, frames: int) -> void:
	_btn(from, MOUSE_BUTTON_LEFT, true)
	await get_tree().process_frame
	var p := from
	for k in range(frames):
		var m := InputEventMouseMotion.new()
		var step := delta / float(frames)
		p += step
		m.position = p
		m.global_position = p
		m.relative = step
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(m)
		await get_tree().process_frame
	_btn(p, MOUSE_BUTTON_LEFT, false)
	await get_tree().process_frame


func _wheel(pos: Vector2, up: bool, n: int) -> void:
	for k in range(n):
		_btn(pos, MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN, true)
		await get_tree().process_frame
		_btn(pos, MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN, false)
		for j in range(3):
			await get_tree().process_frame


func _drive(s) -> void:
	var c := Vector2(780, 400)
	print("[MAPCAM] 开始拖动 zoom=", s._cam_zoom)
	await _drag(c, Vector2(0, 260), 45)      # 往下拖 = 看上面
	await _wait(15)
	await _drag(c, Vector2(0, -520), 60)     # 往上拖 = 看下面
	await _wait(15)
	await _drag(c, Vector2(0, 260), 30)      # 回中
	await _wait(10)
	await _wheel(c, false, 8)                # 缩小到最小
	print("[MAPCAM] 缩到 zoom=", s._cam_zoom)
	await _wait(20)
	await _drag(c, Vector2(0, 300), 40)
	await _drag(c, Vector2(0, -600), 50)
	await _drag(c, Vector2(0, 300), 30)
	await _wheel(c, true, 16)                # 放大到最大
	print("[MAPCAM] 放到 zoom=", s._cam_zoom)
	await _wait(20)
	await _drag(c, Vector2(0, 300), 40)
	await _drag(c, Vector2(0, -600), 50)
	await _drag(c, Vector2(400, 300), 40)
	await _drag(c, Vector2(-800, 0), 50)
	await _wait(20)


func _wait(n: int) -> void:
	for k in range(n):
		await get_tree().process_frame
