extends Node
## 探针(2026-11-05 用户「商店这个卡顿…整个游戏里面会不会有很多这种问题呢」): 背包整页重建一次主线程多久、点一下选中多久
func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.size = Vector2i(1280, 720)
	var ids: Array = DataRegistry.phase2_equipment_by_id.keys()
	var bench: Array = []
	for i in range(24):
		bench.append({"kind": "item", "id": str(ids[(i * 7) % ids.size()]), "star": 1 + i % 3})
	gs.persistent_bench = bench
	var sc: Control = (load("res://scenes/Inventory.tscn") as PackedScene).instantiate()
	add_child(sc)
	sc.size = Vector2(1280, 720)
	for i in range(10):
		await get_tree().process_frame
	var ts: Array = []
	for k in range(5):
		var t0 := Time.get_ticks_usec()
		sc._rebuild()
		ts.append((Time.get_ticks_usec() - t0) / 1000.0)
		await get_tree().process_frame
	var nodes := sc.find_children("*", "", true, false).size()
	print("[I] 背包整页重建 5 次(毫秒): %s · 页面节点数 %d · 背包件数 %d" % [str(ts), nodes, gs.persistent_bench.size()])
	get_tree().quit()
