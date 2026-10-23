extends Node
## DEV 工具(不是门禁): 背包里香火石的说明卡(带当前刻痕 / 充能那一行)—— 2026-10-23 加局外读数时自查用。
## 跑法(窗口只开右屏, 不能 --headless):
##   SHOT_DIR=<目录> SHOT_TAG=<比例名> INC_MARKS=51 INC_CHARGE=2712 TURTLE_SUPABASE=" " TURTLE_BACKEND=" " \
##   APPDATA=<单独目录> WINDOW=1 bash godot-quiet.sh --position 1960,60 --resolution 1560x720 res://tests/_shot_incense_card.tscn


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	await _frames(2)
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	gs.season_leaders = ["basic", "stone", "ninja"]
	gs.season_level = 6
	gs.candy_jar_count = 0
	gs.persistent_equipped = {"basic": [], "stone": [], "ninja": []}
	gs.persistent_bench = [{"id": "p2eq_093", "star": 2}, {"id": "p2eq_004", "star": 1}]
	gs.dual_lineup = {}
	gs.incense_marks = int(OS.get_environment("INC_MARKS")) if OS.get_environment("INC_MARKS").is_valid_int() else 51
	gs.incense_charge = int(OS.get_environment("INC_CHARGE")) if OS.get_environment("INC_CHARGE").is_valid_int() else 2712
	var inv = load("res://scenes/Inventory.tscn").instantiate()
	add_child(inv)
	await _frames(20)
	inv._on_bench_click(0)
	await _frames(12)
	await RenderingServer.frame_post_draw
	var path := "%s/incense_card_%s.png" % [OS.get_environment("SHOT_DIR"), OS.get_environment("SHOT_TAG")]
	get_viewport().get_texture().get_image().save_png(path)
	print("[SHOT] ", path)
	get_tree().quit()
