extends Node
## _shot_cursor_grab.gd — 实拍「光标点在哪、拿起卡片那一刻和滑到位后卡在鼠标哪儿」(给人看, 不是门禁)
## 由来: 2026-10-29 用户「抓起卡片这个中心怎么搞」; 10-30 照商业做法改完后用它验收(方案书 docs/plans/20261030-光标与拿卡.md)。
## 跑法: SHOT_OUT=<目录> WINDOW=1 bash godot-quiet.sh --position 2000,80 --resolution 1280x720 res://tests/_shot_cursor_grab.tscn
## ★根视口的 get_mouse_position() 读的是系统真鼠标, 推进去的假事件挪不动爪子 ⇒ 状态 / 贴图 / 点击点让产品自己的
##   CursorTheme._process 算, 只把位置按同一条公式(鼠标点 − 点击点)摆到假鼠标那儿。红十字 = 鼠标真正的点(SHOT_MARK=1 才画)。
## 方向稿: SHOT_PAW_JSON=<json>(cols / point_rects / fist_rects / hot / hot_fist, rects 与 CursorTheme._build 同格式)
##   换上候选贴图与点击点、拖动时不缩不发光 —— 用产品自己的光标节点画, 不改产品代码(10-30 浅色光标方向稿)。

const INV := preload("res://scenes/Inventory.tscn")
const TS := preload("res://scenes/TeamSelect.tscn")

var out := ""
var ct
var mark: Control
var paw_over := {}


func _ready() -> void:
	out = OS.get_environment("SHOT_OUT")
	if out == "":
		out = "C:/tmp/cursor_grab"
	DirAccess.make_dir_recursive_absolute(out)
	GameState.test_mode = true
	ct = get_node_or_null("/root/CursorTheme")
	if ct != null:
		ct.set_process(false)
	var pj := OS.get_environment("SHOT_PAW_JSON")
	if pj != "" and ct != null and ct._cur != null:
		paw_over = JSON.parse_string(FileAccess.get_file_as_string(pj))
		var cols: Array = []
		for c in paw_over["cols"]:
			cols.append(Color(c))
		ct._point_tex = ct._build(2, cols, PackedInt32Array(paw_over["point_rects"]), 24, 24)
		ct._fist_tex = ct._build(2, cols, PackedInt32Array(paw_over["fist_rects"]), 24, 24)
	var lay := CanvasLayer.new()
	lay.layer = 4097
	add_child(lay)
	mark = Control.new()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.visible = OS.get_environment("SHOT_MARK") == "1"
	mark.draw.connect(func() -> void:
		var c := Color(1, 0.1, 0.1)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			mark.draw_line(d * 3.0, d * 9.0, c, 1.0))
	lay.add_child(mark)
	await get_tree().process_frame

	# ── 背包(打了一周的号) ──
	load("res://tests/_setup_appstore.gd").run()
	GameState.season_level = 10
	var sc = INV.instantiate()
	add_child(sc)
	(sc as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
	(sc as Control).size = Vector2(1280, 720)
	for _i in range(30):
		await get_tree().process_frame
	var cell: Control = sc._tut_first_item
	await _hover_shot(cell.get_global_rect().get_center() + Vector2(-20, -18), "0_hover")
	var shop_btn: Control = null
	for b in sc.find_children("*", "BaseButton", true, false):
		if b is Button and (b as Button).text == "商店" and (b as Control).is_visible_in_tree():
			shop_btn = b
			break
	if shop_btn != null:
		await _hover_shot(shop_btn.get_global_rect().get_center(), "0b_hover_button")
	await _grab_shot(cell.get_global_rect().position + cell.size * 0.3, Vector2(60, -70), "1_inv_equip", false)
	var card: Control = sc.find_child("UnitCard_top_0", true, false)
	await _grab_shot(card.get_global_rect().position + Vector2(60, 70), Vector2(150, 40), "2_inv_unit", true)
	sc.queue_free()
	for _i in range(5):
		await get_tree().process_frame

	# ── 选统领页 ──
	GameState.season_leaders = []
	var ts = TS.instantiate()
	add_child(ts)
	for _i in range(60):
		await get_tree().process_frame
	var pc: Control = null
	for c in ts._grid_flow.get_children():
		if c is Control and (c as Control).size.x > 10.0:
			pc = c
			break
	await _grab_shot(pc.get_global_rect().position + pc.size * Vector2(0.25, 0.3), Vector2(120, -90), "3_ts_card", false)
	var ids: Array = []
	for p in DataRegistry.launch_pets:
		if not (str(p["id"]) in ["hiding", "crystal", "candy"]):
			ids.append(str(p["id"]))
		if ids.size() >= 3:
			break
	ts.team = ids.duplicate()
	ts._selected_slot_idx = -1
	ts._refresh_all()
	for _i in range(10):
		await get_tree().process_frame
	var sl: Control = ts._slot_nodes[0]
	await _grab_shot(sl.get_global_rect().position + sl.size * Vector2(0.7, 0.25), Vector2(150, 60), "4_ts_slot", false)
	print("SHOT DONE")
	get_tree().quit(0)


## 产品自己算状态 / 贴图 / 点击点, 只把位置摆到假鼠标那儿。
func _paw(p: Vector2) -> String:
	mark.position = p
	mark.queue_redraw()
	if ct == null or ct._cur == null:
		return "no-cursor"
	ct._process(0.0)
	var fist: bool = ct._g.texture == ct._fist_tex
	var hot: Vector2 = ct.hot_for(fist)
	if not paw_over.is_empty():
		var h: Array = paw_over["hot_fist"] if fist else paw_over["hot"]
		hot = Vector2(h[0], h[1])
		if fist:
			ct._glow.visible = false
			ct._cur.scale = Vector2.ONE
		ct._cur.pivot_offset = hot
	ct._cur.position = p - hot
	return "握拳" if fist else "平时"


func _move(p: Vector2, rel: Vector2, held: bool) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p; m.global_position = p; m.relative = rel
	if held:
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(m, true)


func _btn(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; e.position = p; e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(e, true)


func _save(tag: String, p: Vector2, info: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, tag])
	print("SHOT %s at=(%d,%d) %s" % [tag, int(p.x), int(p.y), info])


func _hover_shot(p: Vector2, tag: String) -> void:
	_move(p, Vector2.ZERO, false)
	await get_tree().process_frame
	var info := _paw(p)
	for _i in range(3):
		await get_tree().process_frame
	_paw(p)
	await _save(tag, p, info)


## 按下 → 往 dir 拖(过引擎 10px 门槛就拿起)→ [刚拿起那一帧] → 停住等滑到位 → 拍 → 放弃这次拖动。
func _grab_shot(p0: Vector2, dir: Vector2, tag: String, also_first: bool) -> void:
	DragLift._last = null
	_move(p0, Vector2.ZERO, false)
	await get_tree().process_frame
	_btn(p0, true)
	await get_tree().process_frame
	var p := p0
	var first_done := false
	for k in range(10):
		p += dir / 10.0
		_move(p, dir / 10.0, true)
		if also_first and not first_done and DragLift.last() != null:
			## 刚拿起: 停住不再滑, 拍下「按下那一点在不在鼠标下」
			DragLift.last().set_process(false)
			_paw(p)
			await _save(tag + "_a_pickup", p, "刚拿起 · 按下点离鼠标 %s" % str(DragLift.last().grab_offset()))
			DragLift.last().set_process(true)
			first_done = true
		await get_tree().process_frame
	for _i in range(40):
		_paw(p)
		await get_tree().process_frame
	var d := DragLift.last()
	var info := _paw(p) + (" · 卡中心离鼠标 %s" % str(d.center_offset()) if d != null else " · 没有 DragLift")
	await _save(tag, p, info)
	if get_viewport().gui_is_dragging():
		get_viewport().gui_cancel_drag()
	_btn(p, false)
	for _i in range(4):
		await get_tree().process_frame
