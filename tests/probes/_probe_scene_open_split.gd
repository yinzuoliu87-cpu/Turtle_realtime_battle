extends Node
## 探针: 进一页时主线程卡在哪一段 —— 加载资源(load) / 实例化 / 进树(_ready 搭界面)
func _ready() -> void:
	await get_tree().process_frame
	get_node("/root/GameState").test_mode = true
	for p in ["res://scenes/TeamSelect.tscn", "res://scenes/Leaderboard.tscn", "res://scenes/Codex.tscn", "res://scenes/MainMenu.tscn"]:
		var t0 := Time.get_ticks_usec()
		var ps: PackedScene = load(p)
		var t1 := Time.get_ticks_usec()
		var n: Node = ps.instantiate()
		var t2 := Time.get_ticks_usec()
		add_child(n)
		var t3 := Time.get_ticks_usec()
		await get_tree().process_frame
		var t4 := Time.get_ticks_usec()
		print("[S] %-34s 加载 %5.0f ms · 实例化 %4.0f ms · 进树(_ready) %5.0f ms · 下一帧 %4.0f ms" % [p, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, (t4 - t3) / 1000.0])
		n.queue_free()
		await get_tree().process_frame
	get_tree().quit()
