extends Node
## 截图(2026-11-05 用户「图鉴这个小将整个小将和龟为什么差这么多？因为应该是要一个结构的呀」): 同一图鉴里龟页 vs 小将页
func _ready() -> void:
	await get_tree().process_frame
	get_node("/root/GameState").test_mode = true
	var sc: Node = (load("res://scenes/Codex.tscn") as PackedScene).instantiate()
	add_child(sc)
	for i in range(20):
		await get_tree().process_frame
	var want := {"turtle_ninja": "", "minion_elite": "", "minion_front": ""}
	for k in range(sc._items.size()):
		var it: Dictionary = sc._items[k]
		var tag := ""
		if it.has("_minion"):
			tag = "minion_" + str(it["_minion"])
		else:
			tag = "turtle_" + str(it.get("id", ""))
		if want.has(tag):
			sc._select(k)
			for i in range(20):
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			img.save_png("res://.out/shots/codex_%s.png" % tag)
			print("[SHOT] ", tag)
	get_tree().quit()
