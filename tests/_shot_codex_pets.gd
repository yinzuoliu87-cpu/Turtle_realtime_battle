extends Node
## DEV 工具(不是门禁): 图鉴「角色」栏按条目拍(龟 id / 小将 _minion / 召唤物 _summon), 对比模板用。
## 跑法: SHOT_DIR=<目录> ROLE_ITEMS=basic,_minion:elite,_summon:centurion TURTLE_SUPABASE=" " APPDATA=<单独目录> WINDOW=1 bash godot-quiet.sh --position 1960,60 --resolution 1560x720 res://tests/_shot_codex_pets.tscn


func _ready() -> void:
	await get_tree().process_frame
	get_node("/root/GameState").test_mode = true
	var c = load("res://scenes/Codex.tscn").instantiate()
	add_child(c)
	await get_tree().create_timer(2.5).timeout
	var k := 0
	for spec in OS.get_environment("ROLE_ITEMS").split(",", false):
		for i in range(c._items.size()):
			var it = c._items[i]
			if not (it is Dictionary):
				continue
			var hit := false
			if spec.begins_with("_minion:"):
				hit = str(it.get("_minion", "")) == spec.substr(8)
			elif spec.begins_with("_summon:"):
				hit = str(it.get("_summon", "")) == spec.substr(8)
			else:
				hit = str(it.get("id", "")) == spec and not it.has("_minion") and not it.has("_summon")
			if hit:
				c._select(i)
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		var path := "%s/role_%d.png" % [OS.get_environment("SHOT_DIR"), k]
		get_viewport().get_texture().get_image().save_png(path)
		print("[SHOT] ", path)
		k += 1
	get_tree().quit()
