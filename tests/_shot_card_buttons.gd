extends Node
## _shot_card_buttons.gd — 卡片 / 弹框 / 操作条按钮换皮后的实拍(探针, 不进门禁; 2026-10-23)。
## 拍: 结算屏(战果页 + 我方页分路切换)/ 新手教程选择框。
## 跑法(右屏、静音): SHOT_OUT=<目录> <godot> --position 2000,80 --resolution 1560x720 --audio-driver Dummy \
##   --path . res://tests/_shot_card_buttons.tscn

const SCENE := "res://scenes/RealtimeBattle3D.tscn"
var _dir := "user://"


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_dir, name])
	print("[shot] ", name)


func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await get_tree().process_frame


func _row(id: String, nm: String, d: int, t: int) -> Dictionary:
	return {"name": nm, "id": id, "is_summon": false, "_st_multi": false, "rarity": "C",
		"alive": true, "hp": 0.0, "maxHp": 100.0, "_st_dealt": d, "_st_taken": t, "_st_heal": 0, "_st_crit": 0,
		"_st_kills": 1, "_st_shield": 0, "_st_dealt_by_type": {"phy": d, "mag": 0, "tru": 0}}


func _ready() -> void:
	_dir = OS.get_environment("SHOT_OUT") if OS.has_environment("SHOT_OUT") else "user://"
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	var sc = load(SCENE).instantiate()
	get_tree().root.add_child(sc)
	await _wait(1.0)
	sc.set_process(false)
	sc.set_physics_process(false)
	var hist: Array = []
	for lane in ["top", "bottom"]:
		hist.append({"lane": lane, "left": [_row("stone", "石头龟", 900, 700), _row("bamboo", "竹叶龟", 700, 500)],
			"right": [_row("hunter", "猎人龟", 800, 900)]})
	sc._st_lane_hist = hist
	sc._units.clear()
	gs.dual_active = true
	gs.lane_results = {"top": "left", "bottom": "left"}
	gs.finals_pending_reveal = {}
	sc._settled = false
	sc._hud._show_banner(true)
	await _wait(1.5)
	await _shot("settle_result")
	var st = sc._hud._settle
	if st != null and st.has_method("show_page"):
		st.show_page(1)
		await _wait(0.6)
		await _shot("settle_mine")
	sc.queue_free()
	await _wait(0.3)
	var host := ColorRect.new()
	host.color = Color("#1d2633")
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(host)
	TutorialChoice.open(host, true)
	await _wait(0.8)
	await _shot("tutorial_choice")
	get_tree().quit(0)
