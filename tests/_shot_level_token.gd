extends Node
## DEV 工具(不是门禁): 背包里「临时等级器」新图标(2026-10-23 用户「换上」)实拍 —— 与糖果罐、一件装备并排看。
## 跑法(右屏、静音): SHOT_DIR=<目录> TURTLE_SUPABASE=" " TURTLE_BACKEND=" " APPDATA=<单独目录> \
##   <godot> --position 2000,80 --resolution 1560x720 --audio-driver Dummy --path . res://tests/_shot_level_token.tscn


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	await _frames(2)
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	gs.season_leaders = ["candy", "stone", "bamboo"]
	gs.season_level = 6
	gs.persistent_equipped = {"candy": [], "stone": [], "bamboo": []}
	gs.persistent_bench = [gs.TEMP_LEVELER_ITEM.duplicate(), {"id": "p2eq_001", "star": 1}, gs.TEMP_LEVELER_ITEM.duplicate()]
	gs.dual_lineup = {}
	gs.candy_jar_broken = false
	gs.candy_jar_count = 20
	var inv = load("res://scenes/Inventory.tscn").instantiate()
	add_child(inv)
	await _frames(40)
	await RenderingServer.frame_post_draw
	var path := "%s/level_token.png" % OS.get_environment("SHOT_DIR")
	get_viewport().get_texture().get_image().save_png(path)
	print("[SHOT] ", path)
	get_tree().quit()
