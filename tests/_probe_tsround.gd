extends Node
## _probe_tsround.gd — 选龟屏【圆角盒】逐个点名(只量不判)
## 跑法: <godot> --headless --path . res://tests/_probe_tsround.tscn --quit-after 900

func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		if int(gs.season_total_battles) <= 0:
			gs.season_total_battles = 3
	await get_tree().process_frame
	var ps: PackedScene = load("res://scenes/TeamSelect.tscn")
	var inst = ps.instantiate()
	add_child(inst)
	for _i in range(20):
		await get_tree().process_frame
	var n_box := 0
	var n_round := 0
	var kinds: Dictionary = {}
	var st: Array = [inst]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is Control:
			for slot in ["panel", "normal", "background", "fill", "hover", "pressed"]:
				if not (n as Control).has_theme_stylebox_override(slot):
					continue
				var sb = (n as Control).get_theme_stylebox(slot)
				n_box += 1
				if sb is StyleBoxFlat:
					var f := sb as StyleBoxFlat
					if f.corner_radius_top_left > 0:
						n_round += 1
						var w: float = (n as Control).size.x
						var h: float = (n as Control).size.y
						var r: float = float(f.corner_radius_top_left)
						var circ: bool = r >= minf(w, h) * 0.45
						var key := "%s[%s] %.0fx%.0f r=%.0f %s" % [n.get_class(), slot, w, h, r,
							("CIRCLE" if circ else "ROUNDBOX")]
						kinds[key] = int(kinds.get(key, 0)) + 1
						print("  round · %s <%s>" % [key, str(inst.get_path_to(n))])
		for c in n.get_children():
			st.append(c)
	print("=== TeamSelect: stylebox %d · 圆角 %d ===" % [n_box, n_round])
	for k in kinds.keys():
		print("  x%-3d %s" % [int(kinds[k]), k])
	print("PROBE DONE")
	get_tree().quit(0)
