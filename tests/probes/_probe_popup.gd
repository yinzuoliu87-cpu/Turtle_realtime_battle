extends Node
func _ready() -> void:
	if OS.get_environment("PC_W") != "":   # 宽屏实拍: PC_W=1560
		get_tree().root.size = Vector2i(int(OS.get_environment("PC_W")), 720)
	var gs = get_node("/root/GameState"); gs.test_mode = true
	gs.coins = 10000; gs.meta_deepsea_coins = 380
	var m = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(m)
	if OS.get_environment("PC_POPUP") != "":
		for _i in range(90): await get_tree().process_frame
		m._open_week_popup()
	if OS.get_environment("PC_SHOT") != "":   # 直接存视口一帧(movie writer 固定 1280 宽, 宽屏走这条)
		for _j in range(60): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("PC_SHOT"))
		get_tree().quit(0)
