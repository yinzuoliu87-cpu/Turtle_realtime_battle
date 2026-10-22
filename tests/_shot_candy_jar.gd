extends Node
## DEV 工具(不是门禁): 背包里糖果罐 —— 选中罐子的说明卡 + 打碎后的领奖框(2026-10-22 改 12 档时自查用)。
## 跑法(窗口只开右屏, 不能 --headless):
##   SHOT_DIR=<目录> JAR_COUNT=37 TURTLE_SUPABASE=" " TURTLE_BACKEND=" " APPDATA=<单独目录> \
##   WINDOW=1 bash godot-quiet.sh --position 1960,60 --resolution 1560x720 res://tests/_shot_candy_jar.tscn
## ★会真打碎罐子(改的是 APPDATA 指向的那份存档) —— 一定给单独的 APPDATA。


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _save(nm: String) -> void:
	await _frames(6)
	await RenderingServer.frame_post_draw
	var path := "%s/jar_%s.png" % [OS.get_environment("SHOT_DIR"), nm]
	get_viewport().get_texture().get_image().save_png(path)
	print("[SHOT] ", path)


func _ready() -> void:
	await _frames(2)
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	gs.season_leaders = ["candy", "stone", "bamboo"]
	gs.season_level = 6
	gs.persistent_equipped = {"candy": [], "stone": [], "bamboo": []}
	gs.persistent_bench = []
	gs.dual_lineup = {}
	gs.candy_jar_broken = false
	gs.candy_jar_count = int(OS.get_environment("JAR_COUNT")) if OS.get_environment("JAR_COUNT").is_valid_int() else 37
	var inv = load("res://scenes/Inventory.tscn").instantiate()
	add_child(inv)
	await _frames(20)
	inv.set("_sel_jar", true)
	inv.call("_rebuild")
	await _frames(10)
	await _save("card")
	inv._inv_jar._on_break_jar()
	await _frames(10)
	await _save("reward")
	get_tree().quit()
