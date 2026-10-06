extends Node
## 每个可见 Label: 隐藏前后各截一帧做差 ⇒ 真实墨迹框; 再找它所属的框(兄弟里最小的、包住它的贴图/九宫格; 没有就用父控件)。
var m
func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()
func _ready() -> void:
	var gs = get_node("/root/GameState"); gs.test_mode = true
	gs.perf_lite = true                              # 低画质: 背景静止, 入场不播 ⇒ 帧差只来自那一行字
	gs.coins = 10000; gs.meta_deepsea_coins = 380
	m = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(m)
	for _i in range(120): await get_tree().process_frame
	var root: Node = m
	if OS.get_environment("PC_POPUP") != "":   # 量本周赛程页: 打开它, 只量页里的字
		m._open_week_popup()
		for _j in range(10): await get_tree().process_frame
		root = m._week_pop
	var labels: Array = []
	var st: Array = [root]
	while not st.is_empty():
		var n = st.pop_back(); st.append_array(n.get_children())
		if n is Label and (n as Label).is_visible_in_tree() and str((n as Label).text).strip_edges() != "":
			labels.append(n)
	for l in labels:
		var a: Image = await _grab()
		l.visible = false
		var b: Image = await _grab()
		l.visible = true
		var x0 := 99999; var y0 := 99999; var x1 := -1; var y1 := -1
		var r: Rect2 = l.get_global_rect()
		for y in range(maxi(0, int(r.position.y) - 6), mini(a.get_height(), int(r.end.y) + 6)):
			for x in range(maxi(0, int(r.position.x) - 6), mini(a.get_width(), int(r.end.x) + 6)):
				var ca := a.get_pixel(x, y); var cb := b.get_pixel(x, y)
				if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
					x0 = mini(x0, x); y0 = mini(y0, y); x1 = maxi(x1, x); y1 = maxi(y1, y)
		if x1 < 0:
			continue
		var par: Control = l.get_parent() as Control
		var fr: Rect2 = par.get_global_rect()
		var fname := "parent:" + str(par.name)
		for sib in par.get_children():
			if sib != l and (sib is NinePatchRect or (sib is TextureRect and (sib as TextureRect).texture != null)) and (sib as Control).visible:
				var sr: Rect2 = (sib as Control).get_global_rect()
				if sr.has_point(Vector2((x0 + x1) / 2.0, (y0 + y1) / 2.0)) and sr.get_area() < 200000 and (fname.begins_with("parent") or sr.get_area() < fr.get_area()):
					fr = sr; fname = str(sib.name) + ":" + (str((sib as NinePatchRect).texture.resource_path.get_file()) if sib is NinePatchRect else str((sib as TextureRect).texture.resource_path.get_file()))
		var al: String = ["L", "C", "R", "F"][int(l.horizontal_alignment)]
		print("TP|%s|%s|ink=%d,%d-%d,%d|frame=%.0f,%.0f %.0fx%.0f|%s|dx=%.1f|dy=%.1f|padL=%d|padR=%d" % [
			l.text.replace("\n", "⏎"), al, x0, y0, x1, y1, fr.position.x, fr.position.y, fr.size.x, fr.size.y, fname,
			(x0 + x1) / 2.0 - fr.get_center().x, (y0 + y1) / 2.0 - fr.get_center().y, x0 - int(fr.position.x), int(fr.end.x) - x1])
	get_tree().quit(0)
