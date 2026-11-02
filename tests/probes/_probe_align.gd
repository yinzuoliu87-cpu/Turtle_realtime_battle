extends Node
## 主菜单对齐体检: 每个可见 Label 的字块(真实字宽 × ascent+descent)在它所属的"框"里偏多少。
## 框 = 最近的祖先里第一个 NinePatchRect / TextureRect(贴图) / Button 的兄弟背景; 退而求其次用 Label 自己的父控件。
func _ink(l: Label) -> Rect2:
	var f: Font = l.get_theme_font("font"); var fs: int = l.get_theme_font_size("font_size")
	var w: float = f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var h: float = f.get_ascent(fs) + f.get_descent(fs)
	var r: Rect2 = l.get_global_rect()
	var x0: float = r.position.x
	if l.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER: x0 += (r.size.x - w) / 2.0
	elif l.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT: x0 += r.size.x - w
	var y0: float = r.position.y
	if l.vertical_alignment == VERTICAL_ALIGNMENT_CENTER: y0 += (r.size.y - h) / 2.0
	elif l.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM: y0 += r.size.y - h
	return Rect2(x0, y0, w, h)
func _ready() -> void:
	var gs = get_node("/root/GameState"); gs.test_mode = true
	var m = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(m); (m as Control).size = Vector2(1280, 720)
	for _i in range(200): await get_tree().process_frame
	var st: Array = [m]
	while not st.is_empty():
		var n = st.pop_back(); st.append_array(n.get_children())
		if not (n is Label) or not (n as Label).is_visible_in_tree() or str((n as Label).text).strip_edges() == "": continue
		var l := n as Label
		var ink := _ink(l)
		## 框: 父节点里的贴图兄弟(九宫格/贴图), 否则父控件
		var par: Control = l.get_parent() as Control
		var frame: Control = null
		for sib in par.get_children():
			if sib != l and (sib is NinePatchRect or (sib is TextureRect and (sib as TextureRect).texture != null)) and (sib as Control).is_visible_in_tree():
				var sr: Rect2 = (sib as Control).get_global_rect()
				if sr.encloses(ink.grow(-2)) and (frame == null or sr.get_area() < frame.get_global_rect().get_area()):
					frame = sib
		var fr: Rect2 = frame.get_global_rect() if frame != null else par.get_global_rect()
		var dx: float = (ink.position.x + ink.size.x/2.0) - (fr.position.x + fr.size.x/2.0)
		var dy: float = (ink.position.y + ink.size.y/2.0) - (fr.position.y + fr.size.y/2.0)
		var mode := "C" if l.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER else ("L" if l.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT else "R")
		print("ALIGN|%s|%s|%s|dx=%.1f|dy=%.1f|frame=%s %s|path=%s" % [l.text.replace("\n"," "), mode, str(l.get_global_rect()), dx, dy, (frame.name if frame else "parent:"+par.name), str(fr), str(m.get_path_to(l))])
	get_tree().quit(0)
