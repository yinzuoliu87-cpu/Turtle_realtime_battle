extends Node
func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	await get_tree().process_frame
	var inst = (load("res://scenes/Codex.tscn") as PackedScene).instantiate()
	add_child(inst)
	for _i in range(60): await get_tree().process_frame
	inst._switch_tab("pets")
	for _i in range(20): await get_tree().process_frame
	inst._select(1)
	for _i in range(40): await get_tree().process_frame
	for c in inst.detail.get_children():
		if c is RichTextLabel:
			var r := c as RichTextLabel
			print("  RT size=%.0fx%.0f content=%.0f %s 「%s」" % [r.size.x, r.size.y,
				r.get_content_height(), ("★超" if r.get_content_height() > r.size.y + 0.5 else "  "),
				r.get_parsed_text().substr(0, 22).replace("\n", " ")])
		elif c is Label and str((c as Label).text).findn("全部") >= 0 or (c is Label and str((c as Label).text).findn("全文") >= 0):
			print("  提示标签 「%s」" % str((c as Label).text))
	print("PROBE DONE")
	get_tree().quit(0)
