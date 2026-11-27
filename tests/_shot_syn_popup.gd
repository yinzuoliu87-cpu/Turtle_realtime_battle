extends Node
## DEV 工具(不是门禁): 背包羁绊详情弹框(11-27 统一成图鉴写法)逐个拍。
## 跑法: SHOT_DIR=<目录> SYN_TYPES=剑,遗物,长矛 TURTLE_SUPABASE=" " APPDATA=<单独目录> WINDOW=1 bash godot-quiet.sh --position 1960,60 --resolution 1560x720 res://tests/_shot_syn_popup.tscn
## ★不能 --headless: 无头拿不到视口纹理。


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	await _frames(2)
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	gs.season_leaders = ["chest", "stone", "bamboo"]
	gs.season_level = 6
	gs.persistent_equipped = {"chest": [{"id": "p2eq_001", "star": 1}, {"id": "p2eq_003", "star": 1}, {"id": "p2eq_006", "star": 1}], "stone": [], "bamboo": []}
	gs.persistent_bench = []
	gs.dual_lineup = {}
	var inv = load("res://scenes/Inventory.tscn").instantiate()
	add_child(inv)
	await _frames(20)
	var k := 0
	for t in OS.get_environment("SYN_TYPES").split(",", false):
		inv._inv_synergy._show_synergy_popup(str(t), 1 if k == 0 else 2)
		await _frames(8)
		await RenderingServer.frame_post_draw
		var path := "%s/syn_%d.png" % [OS.get_environment("SHOT_DIR"), k]
		get_viewport().get_texture().get_image().save_png(path)
		print("[SHOT] ", path)
		for c in inv.get_children():
			if c is ColorRect and c.get_child_count() > 0 and c.get_child(0) is Panel:
				c.queue_free()
		await _frames(3)
		k += 1
	get_tree().quit()
