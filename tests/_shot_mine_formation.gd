extends Node
## DEV 工具(不是门禁): 背包站位图里的 102 地雷长什么样(2026-11-24 · 方案书 20261124f §4.2)。
## 跑法: SHOT_DIR=<目录> APPDATA=<单独目录> XDG_DATA_HOME=<同> TURTLE_SUPABASE=" " TURTLE_BACKEND=" " WINDOW=1 \
##   bash godot-quiet.sh --path . --resolution 1280x720 --position 2000,80 res://tests/_shot_mine_formation.tscn

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	gs.onboarded = true
	gs.reset_dual_lane()
	gs.dual_active = false
	gs.season_leaders = ["stone", "basic", "bamboo"]
	gs.persistent_equipped = {"stone": [{"id": "p2eq_102", "star": 2}, {"id": "p2eq_099", "star": 1}], "basic": [], "bamboo": []}
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "stone", "equips": []}, {"kind": "leader", "slot": 1, "id": "basic", "equips": []}, {"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []}, {"kind": "minion", "role": "front", "equips": [{"id": "p2eq_102", "star": 1}]}, {"kind": "minion", "role": "back", "equips": []}],
	}
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	var sc = load("res://scenes/Inventory.tscn").instantiate()
	get_tree().root.add_child(sc)
	for _i in range(30):
		await get_tree().process_frame
	var fb := sc.find_child("FormationBtn", true, false) as Button
	if fb != null:
		fb.pressed.emit()
	for _i in range(150):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var p := "%s/mine_formation.png" % OS.get_environment("SHOT_DIR")
	get_viewport().get_texture().get_image().save_png(p)
	print("[SHOT] ", p)
	get_tree().quit()
