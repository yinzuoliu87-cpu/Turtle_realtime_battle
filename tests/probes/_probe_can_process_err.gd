extends Node
## DEV 探针(11-22): 哪种操作会打出「Condition "!is_inside_tree()" is true. Returning: false @ can_process」(LouisT01 / alex1997 周日对阵图报的那条)
func _ready() -> void:
	var cases := {
		"timer_autostart_child_of_outside": func():
			var p := Node.new(); var t := Timer.new(); t.autostart = true; t.wait_time = 0.1; p.add_child(t); return p,
		"http_request_outside": func():
			var h := HTTPRequest.new(); h.request("http://127.0.0.1:9/x"); return h,
		"node_can_process_outside": func():
			var n := Node.new(); n.can_process(); return n,
		"tween_bound_outside": func():
			var n := Node.new(); var tw := get_tree().create_tween(); tw.bind_node(n); tw.tween_interval(0.1); return n,
		"set_process_outside": func():
			var n := Node.new(); n.set_process(true); n.set_process_internal(true); return n,
		"is_processing_outside": func():
			var n := Node.new(); n.is_processing(); return n,
		"tween_bound_then_removed": func():
			var n := Node2D.new(); add_child(n); var tw := n.create_tween(); tw.tween_property(n, "position", Vector2(100, 0), 1.0); remove_child(n); return n,
		"tree_tween_bound_then_removed": func():
			var n := Node2D.new(); add_child(n); var tw := get_tree().create_tween(); tw.bind_node(n); tw.tween_property(n, "position", Vector2(100, 0), 1.0); remove_child(n); return n,
		"timer_child_then_removed": func():
			var n := Node.new(); add_child(n); var t := Timer.new(); t.wait_time = 0.05; t.autostart = true; n.add_child(t); remove_child(n); return n,
		"anim_player_outside": func():
			var a := AnimationPlayer.new(); a.play(&"x"); return a,
	}
	for k in cases:
		print("=== CASE ", k)
		var o = (cases[k] as Callable).call()
		await get_tree().process_frame
		await get_tree().process_frame
		print("=== END ", k)
	get_tree().quit(0)
