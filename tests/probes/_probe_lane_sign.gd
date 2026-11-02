extends Node
## 探针(不进门禁): 背包「上战场 / 下战场」木牌那行字的真实矩形、字体行高、木牌贴图边带。


func _ready() -> void:
	GameState.test_mode = true
	get_tree().root.size = Vector2i(1280, 720)
	var sc: Control = load("res://scenes/Inventory.tscn").instantiate()
	add_child(sc)
	for _i in range(10):
		await get_tree().process_frame
	for n in sc.find_children("LaneSign_*", "", true, false):
		var np := n as NinePatchRect
		print("SIGN ", np.name, " rect=", np.get_global_rect(), " margins t/b/l/r=", np.patch_margin_top, "/", np.patch_margin_bottom, "/", np.patch_margin_left, "/", np.patch_margin_right)
		for ch in np.get_children():
			if ch is Label:
				var l := ch as Label
				var f: Font = l.get_theme_font("font")
				var fs: int = l.get_theme_font_size("font_size")
				print("  LABEL rect=", l.get_global_rect(), " min=", l.get_minimum_size(), " font=", f, " h=", f.get_height(fs), " str=", f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs))
	var img := (load("res://assets/sprites/shop/shop-plank.png") as Texture2D).get_image()
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2
	var ctr := img.get_pixel(cx, cy)
	var bl := 0
	for x2 in range(cx, 0, -1):
		var c := img.get_pixel(x2, cy)
		if c.a < 0.04 or maxf(maxf(absf(c.r - ctr.r), absf(c.g - ctr.g)), absf(c.b - ctr.b)) > 0.12:
			bl = x2
			break
	var bt := 0
	for y2 in range(cy, 0, -1):
		var c2 := img.get_pixel(cx, y2)
		if c2.a < 0.04 or maxf(maxf(absf(c2.r - ctr.r), absf(c2.g - ctr.g)), absf(c2.b - ctr.b)) > 0.12:
			bt = y2
			break
	print("BAND_OF bl=", bl, " bt=", bt)
	get_tree().quit()
