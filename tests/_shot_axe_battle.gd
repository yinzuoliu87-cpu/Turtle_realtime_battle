extends Node
## DEV 工具(不是门禁): 局内点斧头会看到什么 —— 走真召唤入口召出斧头, 打开它的信息面板, 存图 + 打出面板里的字。
## 跑法(窗口只开右屏):
##   SHOT_DIR=<目录> TURTLE_SUPABASE=" " TURTLE_BACKEND=" " APPDATA=<单独目录> \
##   WINDOW=1 bash godot-quiet.sh --position 1960,60 --resolution 1280x720 res://tests/_shot_axe_battle.tscn
## ★不能 --headless: 无头拿不到视口纹理。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _save(nm: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [OS.get_environment("SHOT_DIR"), nm]
	get_viewport().get_texture().get_image().save_png(path)
	print("[SHOT] ", path)


func _dump(s, tag: String) -> void:
	print("--- [%s] 面板里看得见的字 ---" % tag)
	var q: Array = [s._info_panel]
	var seen: Array = []
	while not q.is_empty():
		var n: Node = q.pop_back()
		if n is Control and (n as Control).is_visible_in_tree():
			var t := ""
			if n is Label:
				t = str((n as Label).text)
			elif n is RichTextLabel:
				t = str((n as RichTextLabel).get_parsed_text())
			t = t.strip_edges().replace("\n", " / ")
			if t != "" and not seen.has(t):
				seen.append(t)
		for c in n.get_children():
			q.append(c)
	for t2 in seen:
		print("   |%s|" % t2)


func _shoot(tag: String, stage: int, total: int, fin: String) -> void:
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	gs.axe_stage = stage
	gs.axe_exp_total = total
	gs.axe_exp_bar = 0
	gs.axe_final = fin
	gs.persistent_bench = [{"id": "p2eq_096", "star": 1}]
	RB.DEBUG_EDIT = OS.has_environment("SHOT_DEBUG")
	var s = RB.new()
	add_child(s)
	await _frames(3)
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var carrier: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-120, 0))
	carrier["equips"] = [{"id": "p2eq_096", "star": 1}]
	s._units.clear()
	s._units.append(carrier)
	var ax = s._equip_sys._axe.summon(carrier)
	if not (ax is Dictionary):
		print("[SHOT] 召唤失败")
		return
	s._edit_mode = false
	s._over = false
	s.set_process(false)
	s._hud._show_unit_info_panel(ax)
	s._info_sys._refresh_info_panel()
	await _frames(90)   # 面板有滑入动画, 等它落位再拍
	await _save("axe-" + tag)
	_dump(s, tag)
	## 逐格点开说明卡(走槽自己的 gui_input, 同真点击)
	var row = s._info_panel.find_child("AbilityRow", true, false)
	if row != null:
		for i in range(row.get_child_count()):
			var cell: Control = row.get_child(i)
			var slot = cell.get_meta("slot") if cell.has_meta("slot") else cell
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			(slot as Control).gui_input.emit(ev)
			await _frames(30)
			await _save("axe-%s-card%d" % [tag, i])
	remove_child(s)
	s.queue_free()
	await _frames(3)


func _ready() -> void:
	await get_tree().process_frame
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	await _shoot("iron", 2, 300, "")
	await _shoot("ember", AE.STAGES.size() - 1, 900, "ember")
	get_tree().quit()
