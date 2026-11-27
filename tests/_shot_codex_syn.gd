extends Node
## DEV 工具(不是门禁): 图鉴羁绊页逐个拍(看文案改写; 方案书 20261127d)。
## 跑法: SHOT_DIR=<目录> SYN_TYPES=长矛 TURTLE_SUPABASE=" " APPDATA=<单独目录> WINDOW=1 bash godot-quiet.sh --position 1960,60 --resolution 1560x720 res://tests/_shot_codex_syn.tscn
## ★不能 --headless: 无头拿不到视口纹理。


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	await _frames(2)
	get_node("/root/GameState").test_mode = true
	var c = load("res://scenes/Codex.tscn").instantiate()
	add_child(c)
	await get_tree().create_timer(2.5).timeout   # 图鉴打开有一段淡入
	c._switch_tab("synergies")
	await _frames(6)
	var k := 0
	for t in OS.get_environment("SYN_TYPES").split(",", false):
		for i in range(c._items.size()):
			var it = c._items[i]
			if it is Dictionary and str(it.get("_type", "")) == t:
				c._select(i)
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		var path := "%s/syn_%d.png" % [OS.get_environment("SHOT_DIR"), k]
		get_viewport().get_texture().get_image().save_png(path)
		print("[SHOT] ", path)
		k += 1
	get_tree().quit()
