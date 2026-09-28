extends Node
## 探针: 赛程条「今天」那一格 —— 位置在哪、金色顶条建没建、可见吗。
func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.account_email = "t@x.co"
	await get_tree().process_frame
	var mm = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(mm)
	for _i in range(20):
		await get_tree().process_frame
	var box = mm.find_child("WeekStrip", true, false)
	print("[探针] WeekStrip 存在: %s" % str(box != null))
	if box == null:
		get_tree().quit(0); return
	print("[探针] 条带 rect = %s  可见=%s  modulate=%s" % [
		str((box as Control).get_global_rect()), str((box as Control).is_visible_in_tree()),
		str((box as Control).modulate)])
	var hb = null
	for c in box.get_children():
		if c is HBoxContainer:
			hb = c; break
	if hb == null:
		print("[探针] 没找到格子容器"); get_tree().quit(0); return
	var i := 0
	for cell in hb.get_children():
		i += 1
		var txt := ""
		var st: Array = [cell]
		var bars := 0
		while not st.is_empty():
			var n = st.pop_front()
			if n is Label and str((n as Label).text).strip_edges() != "":
				txt += str((n as Label).text) + " "
			if n is ColorRect:
				bars += 1
				print("        ↳ 金条 ColorRect color=%s rect=%s 可见=%s" % [
					str((n as ColorRect).color), str((n as ColorRect).get_global_rect()),
					str((n as ColorRect).is_visible_in_tree())])
			for ch in n.get_children():
				st.append(ch)
		var r: Rect2 = (cell as Control).get_global_rect()
		print("[格 %d] %-12s rect=%s  modulate.a=%.2f  金条=%d" % [
			i, txt.strip_edges(), str(r), (cell as Control).modulate.a, bars])
	get_tree().quit(0)
