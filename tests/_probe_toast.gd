extends Node
func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	await get_tree().process_frame
	var inst = (load("res://scenes/TeamSelect.tscn") as PackedScene).instantiate()
	add_child(inst)
	for _i in range(120): await get_tree().process_frame
	var st: Array = [inst]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is Label:
			var l := n as Label
			var t := str(l.text).strip_edges()
			if t.findn("本大轮") >= 0 or t == "C" or t == "B":
				print("  「%s」 rect=%s alpha=%.2f 可见=%s" % [t.substr(0,14), str(l.get_global_rect()), l.get_modulate().a, str(l.is_visible_in_tree())])
		for ch in n.get_children(): st.append(ch)
	print("PROBE DONE")
	get_tree().quit(0)
