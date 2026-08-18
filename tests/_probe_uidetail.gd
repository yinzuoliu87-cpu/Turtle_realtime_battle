extends Node
## _probe_uidetail.gd — 把「网页盒/圆角盒」逐个点名(2026-08-18)
##
## 由来: 同一个背包, `_probe_webbox` 报 0/1, `_probe_uiaudit` 报 10/19。
## **两个探针打架时不许挑好看的那个报** —— 先逐个点名, 看差在哪。
## 已知两处口径差: ①uiaudit 只数 `is_visible_in_tree()` 的 ②uiaudit 喂了 demo 数据。

const SCENES: Array = [
	["res://scenes/Inventory.tscn", "res://tests/_setup_inv_demo.gd"],
	["res://scenes/Codex.tscn", ""],
	["res://scenes/TeamSelect.tscn", ""],
	["res://scenes/Shop.tscn", ""],
]


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await get_tree().process_frame
	for row in SCENES:
		var path: String = str(row[0])
		var setup: String = str(row[1])
		if setup != "" and ResourceLoader.exists(setup):
			var sc = load(setup)
			if sc != null and sc.has_method("run"):
				sc.run()
		var inst = (load(path) as PackedScene).instantiate()
		add_child(inst)
		for _i in range(14):
			await get_tree().process_frame
		print("=== %s ===" % path.get_file())
		var web := {}
		var rnd := {}
		var st: Array = [inst]
		while not st.is_empty():
			var n: Node = st.pop_back()
			if n is Control and (n as Control).is_visible_in_tree():
				var c := n as Control
				for slot in ["panel", "normal", "background", "fill"]:
					if not c.has_theme_stylebox_override(slot):
						continue
					var sb = c.get_theme_stylebox(slot)
					if not (sb is StyleBoxFlat):
						continue
					var f := sb as StyleBoxFlat
					var key := "%s/%s(%.0fx%.0f)" % [c.get_parent().name, c.name, c.size.x, c.size.y]
					if f.corner_radius_top_left > 0:
						rnd[key] = int(rnd.get(key, 0)) + 1
					if f.border_width_top > 0 and f.border_width_bottom > 0 \
							and f.border_width_left > 0 and f.border_width_right > 0 \
							and f.bg_color.a < 0.95:
						web[key] = int(web.get(key, 0)) + 1
			for ch in n.get_children():
				st.append(ch)
		print("  网页盒 %d 处:" % web.size())
		for k in web.keys():
			print("     %s" % k)
		print("  圆角盒 %d 处(前 12):" % rnd.size())
		var i := 0
		for k in rnd.keys():
			print("     %s" % k)
			i += 1
			if i >= 12:
				break
		inst.queue_free()
		await get_tree().process_frame
	print("PROBE DONE")
	get_tree().quit(0)
