extends Node
## _probe_oob.gd — 打印主菜单在四个比例下【越出视口】的控件(探针, 不进门禁)。
## 由来: verify_ui_layout 报「溢出 36 个, 最严重 340x82 超出 21px」, 但按设计坐标算不该越界。
##   推理出的根因不算根因(memory fb-probe-before-claiming-rootcause) —— 打出来看。
const VIEWS := [[1280, 720], [1560, 720], [1680, 720], [1280, 960]]

func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	for v in VIEWS:
		get_tree().root.size = Vector2i(v[0], v[1])
		await get_tree().process_frame
		var mm = load("res://scenes/MainMenu.tscn").instantiate()
		get_tree().root.add_child(mm)
		for _i in range(40):
			await get_tree().process_frame
		var vp := Vector2(v[0], v[1])
		var oob: Array = []
		var q: Array = [mm]
		while not q.is_empty():
			var nd = q.pop_back()
			for ch in nd.get_children():
				q.append(ch)
				if ch is Control and (ch as Control).visible:
					var r: Rect2 = (ch as Control).get_global_rect()
					if r.size.x >= vp.x - 1.0 and r.size.y >= vp.y - 1.0: continue
					var ov := maxf(maxf(-r.position.x, -r.position.y), maxf(r.end.x - vp.x, r.end.y - vp.y))
					if ov > 0.5:
						oob.append("%.0fpx %s %s @(%.0f,%.0f)%.0fx%.0f 文本=%s" % [
							ov, ch.get_class(), ch.name, r.position.x, r.position.y, r.size.x, r.size.y,
							str((ch as Label).text).substr(0, 12) if ch is Label else "-"])
		oob.sort_custom(func(a, b): return float(str(a).split("px")[0]) > float(str(b).split("px")[0]))
		print("== %dx%d 越界 %d 个 ==" % [v[0], v[1], oob.size()])
		for o in oob.slice(0, 6):
			print("   ", o)
		mm.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
