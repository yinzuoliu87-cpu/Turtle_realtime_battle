extends Node
## DEV 工具(不是门禁): 背包里的宝箱龟 —— 摆好财宝值 / 已开战利品, 拍背包全景 + 点开宝箱龟那张卡。
## 跑法(窗口只开右屏):
##   SHOT_DIR=<目录> SHOT_TAG=<文件名前缀> CHEST_VALUE=5255 CHEST_LOOT=rum,dagger TURTLE_SUPABASE=" " TURTLE_BACKEND=" " \
##   APPDATA=<单独目录> WINDOW=1 bash godot-quiet.sh --position 1960,60 --resolution 1560x720 res://tests/_shot_inv_chest.tscn
## ★不能 --headless: 无头拿不到视口纹理。


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _save(nm: String) -> void:
	await _frames(6)
	await RenderingServer.frame_post_draw
	var path := "%s/%s_%s.png" % [OS.get_environment("SHOT_DIR"), OS.get_environment("SHOT_TAG"), nm]
	get_viewport().get_texture().get_image().save_png(path)
	print("[SHOT] ", path)


func _ready() -> void:
	await _frames(2)
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	gs.season_leaders = ["chest", "stone", "bamboo"]
	gs.season_level = 6
	gs.persistent_equipped = {"chest": [{"id": "p2eq_004", "star": 2}], "stone": [], "bamboo": []}
	gs.persistent_bench = [{"id": "p2eq_021", "star": 1}, {"id": "p2eq_084", "star": 1}]
	gs.dual_lineup = {}
	gs.chest_treasure_value = float(OS.get_environment("CHEST_VALUE")) if OS.get_environment("CHEST_VALUE").is_valid_float() else 0.0
	var loot: Array = []
	for t in OS.get_environment("CHEST_LOOT").split(",", false):
		loot.append(str(t))
	gs.chest_treasures_won = loot
	var inv = load("res://scenes/Inventory.tscn").instantiate()
	add_child(inv)
	await _frames(20)
	await _save("inv")
	## 点宝箱龟那张卡(真入口: 选中这只单位 ⇒ 弹属性小卡)
	var dl: Dictionary = gs.get_dual_lineup()
	for ln in ["top", "bottom"]:
		var arr: Array = dl.get(ln, [])
		for i in range(arr.size()):
			if arr[i] is Dictionary and str(arr[i].get("id", "")) == "chest":
				inv._dl_click(ln, i)
	await _frames(10)
	await _save("card")
	get_tree().quit()
