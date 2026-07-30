extends Node
## 探针: 打开统计面板后截图(看真实交互观感)。
const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	var s = RTScene.new()
	get_tree().root.add_child(s)
	for _i in range(20):
		await get_tree().process_frame
	s._on_dmg_stats_toggle()
	for _i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_OUT"))
	print("saved")
	get_tree().quit(0)
