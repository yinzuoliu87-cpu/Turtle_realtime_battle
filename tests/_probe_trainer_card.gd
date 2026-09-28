extends Node
## 探针: 训龟大师技能卡 —— 卡多高、框的边带多厚、里面三样东西各占多高。
## ★别再猜 offset 了: 内容比内容区高多少, 量出来就知道该让多少。
const TC := preload("res://scripts/scenes/TrainerConfigScene.gd")
const UIC := preload("res://tests/verify_ui_consistency.gd")


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await get_tree().process_frame
	var sc = load("res://scenes/TrainerConfig.tscn").instantiate()
	add_child(sc)
	for _i in range(20):
		await get_tree().process_frame
	var aud = UIC.new()
	add_child(aud)
	await get_tree().process_frame
	var st: Array = [sc]
	var n := 0
	while not st.is_empty() and n < 3:
		var c = st.pop_back()
		if c is Button and c.has_theme_stylebox_override("normal"):
			var sb = c.get_theme_stylebox("normal")
			if sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null:
				var band: float = aud._band_of((sb as StyleBoxTexture).texture)
				var r: Rect2 = (c as Control).get_global_rect()
				n += 1
				print("[卡 %d] rect=%s  边带=%.1f  内容区高=%.1f" % [n, str(r), band, r.size.y - band * 2.0])
				var st2: Array = [c]
				while not st2.is_empty():
					var k = st2.pop_front()
					if k is Label and str((k as Label).text).strip_edges() != "":
						var ir: Rect2 = aud._ink_rect(k as Label)
						print("     Label「%s」 ink y %.0f~%.0f (框内容区 y %.0f~%.0f)" % [
							str((k as Label).text).substr(0,6), ir.position.y, ir.end.y,
							r.position.y + band, r.end.y - band])
					elif k is TextureRect:
						var tr: Rect2 = (k as TextureRect).get_global_rect()
						print("     图标 rect y %.0f~%.0f  高 %.0f" % [tr.position.y, tr.end.y, tr.size.y])
					for ch in k.get_children():
						st2.append(ch)
		for ch2 in c.get_children():
			st.append(ch2)
	get_tree().quit(0)
