extends Node
## 量设置页的内容包围盒 + UIFrame 收编情况(探针, 不进门禁)。
## 由来: verify_ui_layout ② 报「既没有内容层, 内容也没自居中(偏离 185px)」。
##   推理不出来就打出来(memory fb-probe-before-claiming-rootcause)。
func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	var inst = load("res://scenes/Settings.tscn").instantiate()
	get_tree().root.add_child(inst)
	for _i in range(60):
		await get_tree().process_frame
	var has_frame := false
	for ch in inst.get_children():
		print("  直接子节点: %s (%s)" % [ch.name, ch.get_class()])
		if ch.get_class() == "UIFrame" or str(ch.name).contains("Frame"):
			has_frame = true
	print("  有 UIFrame 收编: %s" % has_frame)
	var lo := Vector2(99999, 99999)
	var hi := Vector2(-99999, -99999)
	var items: Array = []
	var q: Array = [inst]
	while not q.is_empty():
		var nd = q.pop_back()
		for ch in nd.get_children():
			q.append(ch)
			if ch is Control and (ch as Control).visible:
				var r: Rect2 = (ch as Control).get_global_rect()
				if r.size.x <= 0 or r.size.y <= 0: continue
				if r.size.x >= 1279 and r.size.y >= 719: continue
				lo.x = minf(lo.x, r.position.x); lo.y = minf(lo.y, r.position.y)
				hi.x = maxf(hi.x, r.end.x);      hi.y = maxf(hi.y, r.end.y)
				items.append("%s %s @(%.0f,%.0f)%.0fx%.0f" % [ch.get_class(), ch.name, r.position.x, r.position.y, r.size.x, r.size.y])
	var c := (lo + hi) * 0.5
	print("  包围盒 x %.0f..%.0f  y %.0f..%.0f  中心(%.0f,%.0f)  视口中心(640,360)" % [lo.x, hi.x, lo.y, hi.y, c.x, c.y])
	print("  偏离: x %.0f  y %.0f" % [c.x - 640.0, c.y - 360.0])
	print("  贴左边(x<60)的元素:")
	for s in items:
		var parts := str(s).split("@(")
		if parts.size() > 1 and float(parts[1].split(",")[0]) < 60.0:
			print("     ", s)
	get_tree().quit(0)
