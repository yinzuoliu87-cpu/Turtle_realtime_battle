extends Node
func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await get_tree().process_frame
	var inst = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	add_child(inst)
	for _i in range(14):
		await get_tree().process_frame
	var st: Array = [inst]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is Label and (n as Label).is_visible_in_tree():
			var l := n as Label
			var t := str(l.text).strip_edges()
			if t == "排行榜" or t == "图鉴":
				var f: Font = l.get_theme_font("font")
				var fs: int = l.get_theme_font_size("font_size")
				print("  「%s」 rect=%s  halign=%d valign=%d  字宽=%.0f  父=%s" % [
					t, str(l.get_global_rect()), l.horizontal_alignment, l.vertical_alignment,
					(f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if f != null else -1.0),
					l.get_parent().name])
		for ch in n.get_children():
			st.append(ch)
	print("PROBE DONE")
	get_tree().quit(0)
