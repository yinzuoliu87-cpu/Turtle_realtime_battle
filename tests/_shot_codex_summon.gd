extends Node
## DEV 工具(不是门禁): 图鉴「角色」栏召唤物页逐页逐列拍(方案书 20261127d)。
## 跑法: SHOT_DIR=<目录> SUMMON_SHOTS=centurion:0,centurion:3,turret:0 TURTLE_SUPABASE=" " APPDATA=<单独目录> WINDOW=1 bash godot-quiet.sh --position 1960,60 --resolution 1560x720 res://tests/_shot_codex_summon.tscn
## ★不能 --headless: 无头拿不到视口纹理。


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	await _frames(2)
	get_node("/root/GameState").test_mode = true
	var c = load("res://scenes/Codex.tscn").instantiate()
	add_child(c)
	await get_tree().create_timer(2.5).timeout   # 图鉴打开有一段淡入(按时间等: 帧跑得快)
	var k := 0
	for spec in OS.get_environment("SUMMON_SHOTS").split(",", false):
		var sid: String = spec.split(":")[0]
		var col: int = int(spec.split(":")[1]) if spec.contains(":") else 0
		for i in range(c._items.size()):
			var it = c._items[i]
			if it is Dictionary and str(it.get("_summon", "")) == sid:
				c._select(i)
		await _frames(4)
		c._codex_summon.set_col(sid, col)
		await _frames(45)   # 详情面板有淡入, 等它走完再拍
		if OS.get_environment("LIST_BOTTOM") == "1":   # 左栏列表滚到底(看「召唤物」分组)
			var lsc = c.list_vbox.get_parent()
			if lsc is ScrollContainer:
				(lsc as ScrollContainer).scroll_vertical = 100000
			await _frames(6)
		await RenderingServer.frame_post_draw
		var path := "%s/summon_%d.png" % [OS.get_environment("SHOT_DIR"), k]
		get_viewport().get_texture().get_image().save_png(path)
		print("[SHOT] ", path)
		k += 1
	get_tree().quit()
