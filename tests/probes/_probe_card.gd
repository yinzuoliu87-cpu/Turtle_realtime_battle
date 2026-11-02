extends Node
func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await get_tree().process_frame
	var inst = (load("res://scenes/TeamSelect.tscn") as PackedScene).instantiate()
	add_child(inst)
	for _i in range(120):
		await get_tree().process_frame
	var shown := 0
	var st: Array = [inst]
	while not st.is_empty() and shown < 3:
		var n: Node = st.pop_back()
		if n is Label and (n as Label).is_visible_in_tree() and str((n as Label).text).strip_edges() == "小龟":
			var l := n as Label
			var f: Font = l.get_theme_font("font")
			var fs: int = l.get_theme_font_size("font_size")
			print("  名字 rect=%s  字宽=%.1f 字高=%.1f halign=%d valign=%d" % [
				str(l.get_global_rect()),
				f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x,
				f.get_height(fs), l.horizontal_alignment, l.vertical_alignment])
			var p: Node = l.get_parent()
			while p != null and p is Control:
				var pc := p as Control
				for slot in ["panel", "normal"]:
					if pc.has_theme_stylebox_override(slot):
						var sb = pc.get_theme_stylebox(slot)
						print("      祖先 %s rect=%s 样式=%s" % [pc.name, str(pc.get_global_rect()), sb.get_class()])
				p = p.get_parent()
			# 同级里找那个铺满卡的背景 Panel
			var card := l.get_parent()
			while card != null and not (card.get_parent() is GridContainer):
				card = card.get_parent()
			if card != null:
				for ch in card.get_children():
					if ch is Panel:
						print("      卡背景 rect=%s" % str((ch as Panel).get_global_rect()))
			shown += 1
		for ch2 in n.get_children():
			st.append(ch2)
	print("PROBE DONE")
	get_tree().quit(0)
