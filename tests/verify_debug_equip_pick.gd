extends Node
var _fail := 0
var _n := 0
func _ok(nm: String, c: bool, d: String = "") -> void:
	_n += 1
	if c: print("  [PASS] ", nm, "  ", d)
	else:
		_fail += 1; print("  [FAIL] ", nm, "  ", d)
## verify_debug_equip_pick —— 调试场「点单位 → 加装备 → 点装备」整条真点击链路哪一步断(用户 2026-10-04「调试场现在根本选不到装备」)
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

func _click(p: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		get_viewport().push_input(ev)
		await get_tree().process_frame
		await get_tree().process_frame

func _find_btn(n: Node, txt: String) -> Button:
	if n is Button and str((n as Button).text).find(txt) >= 0 and (n as Button).is_visible_in_tree():
		return n
	for c in n.get_children():
		var r = _find_btn(c, txt)
		if r != null: return r
	return null

func _ready() -> void:
	get_tree().root.size = Vector2i(1560, 720)
	RB.DEBUG_EDIT = true
	RB._edit_collapsed = false
	var scene = RB.new()
	add_child(scene)
	for _i in range(8):
		await get_tree().process_frame
	var u = scene._debug._edit_place_unit("basic", "left", Vector2(450, 0))
	for _i in range(8):
		await get_tree().process_frame
	var sp: Vector2 = scene._cam.unproject_position(scene._world_pos(u["pos"], u["height"] + 1.0))
	var mv := InputEventMouseMotion.new(); mv.position = sp; mv.global_position = sp; get_viewport().push_input(mv)
	await get_tree().process_frame
	var hv = get_viewport().gui_get_hovered_control()
	await _click(sp)
	_ok("① 真点击场上单位 ⇒ 选中", scene._edit_sel_unit != null)
	if scene._edit_sel_unit == null:
		scene._debug._edit_select_unit(u)
		await get_tree().process_frame
	for _i in range(4):
		await get_tree().process_frame
	for _i in range(4):
		await get_tree().process_frame
	var add := _find_btn(scene, "加装备")
	_ok("② 找到「➕ 加装备」", add != null)
	if add == null:
		print("FAIL x%d" % _fail); get_tree().quit(1); return
	_ok("②a 左面板底边在笔刷栏上方(不被盖住)", scene._edit_palette.get_global_rect().end.y <= scene._edit_brush_bar.get_global_rect().position.y, "%s vs %s" % [scene._edit_palette.get_global_rect().end.y, scene._edit_brush_bar.get_global_rect().position.y])
	var c2: Vector2 = add.get_global_rect().get_center()
	var mv2 := InputEventMouseMotion.new(); mv2.position = c2; mv2.global_position = c2; get_viewport().push_input(mv2)
	await get_tree().process_frame
	var hv2 = get_viewport().gui_get_hovered_control()
	await _click(c2)
	_ok("③ 真点击「➕ 加装备」⇒ 弹出装备格子", scene._edit_grid_popup != null and is_instance_valid(scene._edit_grid_popup))
	if scene._edit_grid_popup == null:
		print("FAIL x%d" % _fail); get_tree().quit(1); return
	var card: Button = null
	var stack: Array = [scene._edit_grid_popup]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Button and n.custom_minimum_size == Vector2(128, 112):
			if card == null or n.get_global_rect().position.y < card.get_global_rect().position.y or (n.get_global_rect().position.y == card.get_global_rect().position.y and n.get_global_rect().position.x < card.get_global_rect().position.x):
				card = n
		for c in n.get_children(): stack.append(c)
	if card != null:
		await _click(card.get_global_rect().get_center())
	_ok("⑤ 真点击装备卡 ⇒ 这件装进选中单位", (u.get("_edit_equips", []) as Array).size() == 1, str(u.get("_edit_equips", [])))
	print("ALL PASS — 调试场选装备" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
