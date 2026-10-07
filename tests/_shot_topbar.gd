extends Node
## _shot_topbar.gd — 顶部栏(PK 条)各状态实拍(探针, 不进门禁)。
## 真战斗场(双路) → 走真建场入口开一路 → 逐个造状态 → 截图:
##   normal / 加时1档 / 加时2档 / 团灭+破蛋倒计时 / 终极战场破蛋定胜负 / 蛋碎
## 跑法(右屏、静音、隔离 user://):
##   APPDATA=/c/tmp/tb_app XDG_DATA_HOME=/c/tmp/tb_app TURTLE_BACKEND=" " TURTLE_SUPABASE=" " SHIP=1 \
##   SHOT_OUT=C:/tmp/topbar2 SHOT_TAG=1560 WINDOW=1 bash godot-quiet.sh --position 2000,80 \
##   --resolution 1560x720 res://tests/_shot_topbar.tscn
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")

var _dir := "user://"
var _tag := "x"
var gs = null
var s = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_dir = OS.get_environment("SHOT_OUT") if OS.has_environment("SHOT_OUT") else "user://"
	_tag = OS.get_environment("SHOT_TAG") if OS.has_environment("SHOT_TAG") else "x"
	await get_tree().process_frame
	gs = get_node_or_null("/root/GameState")
	OS.set_environment("TURTLE_SEED", "")
	gs.reset_dual_lane()
	gs.test_mode = true
	gs.tutorial_active = false
	gs.onboarded = true
	gs.season_level = 6
	gs.nickname = "海带拌饭"
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(OS.get_environment("SHOT_SEED")) if OS.has_environment("SHOT_SEED") else 20261007
	gs.dual_ghost = Backend.make_bot(3, rng)
	gs.dual_active = true
	gs.current_lane = "top"
	gs.lane_results = {}
	s = RB.new()
	add_child(s)
	for _i in range(40):
		await get_tree().process_frame
	await _fresh("top")
	await _run(1.5)
	await _shot("1_normal")
	s._sd_t0 = s._t - 40.2
	await _run(0.5)
	await _shot("2_overtime_splash", 1)
	await _run(1.6)
	await _shot("3_overtime_x1")
	s._sd_t0 = s._t - 45.3
	await _run(0.4)
	await _shot("4_overtime_x2")
	s._hud._topbar.show_popup("amp")
	await _run(0.1)
	await _shot("4b_overtime_badge_tap")
	s._hud._topbar.hide_popup()
	s._sd_t0 = s._t
	s._sd_stacks = 0
	_wipe("right")
	await _run(1.2)
	await _shot("5_wipe_eggwindow")
	await _run(6.0)
	await _shot("6_eggwindow_last3s")
	await _shatter_visual()
	gs.lane_results = {"top": "left", "bottom": "right"}
	await _fresh("final")
	await _run(1.0)
	await _shot("7_final_normal")
	_wipe("left")
	await _run(1.2)
	await _shot("8_final_decider")
	for u in s._units:
		if u.get("_isEgg", false) and str(u.get("egg_side_lr", "")) == "left":
			s._damage._apply_damage(u, int(u["hp"]) + 99999, Color.WHITE, null, "tru", false)
	await _shot("9_egg_break", 1)
	get_tree().quit(0)
	return


## 蛋碎碎片的样子(探针专用): 真流程里蛋一碎结算屏同一帧就盖上来, 截不到条。
## 这里在一路正打着时直接调顶栏的碎蛋入口, 只为看清碎片本身。
func _shatter_visual() -> void:
	gs.lane_results = {"top": "left", "bottom": "right"}
	await _fresh("final")
	await _run(0.8)
	s._hud._topbar.break_egg("right")
	for _i in range(4):
		await get_tree().process_frame
	await _shot("9b_egg_shatter_visual", 1)


func _fresh(lane: String) -> void:
	gs.current_lane = lane
	s._over = false
	s._dl_sys._dl_clear_units()
	await get_tree().process_frame
	s._dl_sys._dl_build_lane_field()
	await get_tree().process_frame
	s._dl_sys._dl_start_fight()
	s._hud._pk_lane = ""          # 探针在同一路里重建场: 逼 PK 条当换路处理(真对局换路时自己会)


## 按墙钟跑真帧(战斗自己 _process)。
func _run(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await get_tree().process_frame


func _wipe(side: String) -> void:
	for u in s._units:
		if not u.get("alive", false) or u.get("_isEgg", false) or u.get("is_trainer", false):
			continue
		if str(s._eff_side(u)) != side:
			continue
		s._kill(u)


func _shot(name: String, settle: int = 3) -> void:
	for _i in range(settle):
		await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [_dir, name, _tag])
	print("[shot] ", name)
