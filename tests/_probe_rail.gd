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
	var rc = inst._rect("grid")
	print("  grid 区: pos=%s size=%s" % [str(rc.position), str(rc.size)])
	var rail = inst._ent_rail
	if rail != null:
		print("  rail: pos=%s size=%s 子=%d" % [str(rail.position), str(rail.size), rail.get_child_count()])
		for c in rail.get_children():
			print("     %s %s" % [str((c as Control).size), str((c as Button).text) if c is Button else ""])
	print("PROBE DONE")
	get_tree().quit(0)
