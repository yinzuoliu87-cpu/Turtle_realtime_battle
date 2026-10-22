extends Node
## 背包拖拽录屏台(不是门禁): App Store 那份存档开背包, 慢慢演示四种拖法, 每 2 帧存一张视口图。
## 跑法(窗口只开右屏): REC_DIR=<目录> TURTLE_SUPABASE=" " TURTLE_BACKEND=" " \
##   <godot> --audio-driver Dummy --resolution 1560x720 --position 1960,60 --path . res://tests/_rec_inventory_drag.tscn

const INV := preload("res://scenes/Inventory.tscn")
var sc
var _dir := ""
var _f := 0
var _rec := false


func _process(_dt: float) -> void:
	if not _rec:
		return
	_f += 1
	if _f % 2 == 0:
		get_viewport().get_texture().get_image().save_png("%s/f_%04d.png" % [_dir, _f / 2])


func _wait(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _drag(from: Vector2, to: Vector2, steps: int = 40) -> void:
	var vp := get_viewport()
	var dn := InputEventMouseButton.new()
	dn.button_index = MOUSE_BUTTON_LEFT; dn.pressed = true; dn.position = from; dn.global_position = from
	vp.push_input(dn, true)
	await _wait(14)
	for k in range(1, steps + 1):
		var mm := InputEventMouseMotion.new()
		var t := float(k) / float(steps)
		t = t * t * (3.0 - 2.0 * t)
		var p := from.lerp(to, t)
		mm.position = p; mm.global_position = p
		mm.relative = (to - from) / float(steps)
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		vp.push_input(mm, true)
		await get_tree().process_frame
	await _wait(10)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false; up.position = to; up.global_position = to
	vp.push_input(up, true)
	await _wait(40)


func _card(lane: String, i: int) -> Control:
	return sc.find_child("UnitCard_%s_%d" % [lane, i], true, false) as Control


func _ready() -> void:
	_dir = OS.get_environment("REC_DIR")
	await get_tree().process_frame
	GameState.test_mode = true
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	load("res://tests/_setup_appstore.gd").run()
	GameState.season_level = 10
	sc = INV.instantiate()
	add_child(sc)
	await _wait(30)
	_rec = true
	await _wait(30)
	## ① 背包第一件 → 上路第二张卡
	await _drag(sc._tut_first_item.get_global_rect().get_center(), _card("top", 1).get_global_rect().get_center())
	## ② 那一件拖回背包
	var c1: Control = _card("top", 1)
	var x0: float = sc.CARD_W / 2.0 - (3.0 * sc.EQ_CELL + 2.0 * sc.EQ_GAP) / 2.0
	await _drag(c1.get_global_rect().position + Vector2(x0 + 2.0 * (sc.EQ_CELL + sc.EQ_GAP) + sc.EQ_CELL * 0.5, sc.SLOT_ROW_Y + sc.EQ_CELL * 0.5), sc._bench_area.get_global_rect().get_center())
	## ③ 上路第一张卡 ↔ 下路第一张卡
	await _drag(_card("top", 0).get_global_rect().position + Vector2(sc.CARD_W / 2.0, 70.0), _card("bottom", 0).get_global_rect().get_center(), 50)
	## ④ 上路第一张卡身上第一件 → 下路第二张(小将)
	var c0: Control = _card("top", 0)
	await _drag(c0.get_global_rect().position + Vector2(x0 + sc.EQ_CELL * 0.5, sc.SLOT_ROW_Y + sc.EQ_CELL * 0.5), _card("bottom", 1).get_global_rect().get_center())
	await _wait(30)
	get_tree().quit()
