extends Node
## _shot_pet_xp.gd —— 龟经验条三处界面实拍(2026-11-09 · 方案书 20261107b §4.5「实拍」)。不进门禁(不叫 verify_*)。
## 有窗口跑(要真渲染才截得到图), 静音: <godot> --audio-driver Dummy --resolution 1560x720 --position 2000,80 --path . res://tests/probes/_shot_pet_xp.tscn
## 输出 .out/shots/pet_xp/<宽>x<高>_*.png(DevOut.path): 结算屏 涨到一半 / 升级放大那一刻 / 演完; 选龟页; 图鉴石头龟页。

const SCENE := "res://scenes/RealtimeBattle3D.tscn"
const TS := "res://scenes/TeamSelect.tscn"
const CODEX := preload("res://scenes/Codex.tscn")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const FIX := {"linked": true, "owned": ["stone", "bamboo"],
	"levels": {"stone": {"lv": 1, "xp": 65}, "bamboo": {"lv": 4, "xp": 300}}}

var _tag := ""


func _shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := DevOut.path("%s_%s.png" % [_tag, nm], "shots/pet_xp")
	img.save_png(p)
	print("SHOT ", p, " ", img.get_size())


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	Engine.max_fps = 60
	await _frames(2)
	var vs := get_viewport().get_visible_rect().size
	_tag = "%dx%d" % [int(vs.x), int(vs.y)]
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.account_id = "shot-pet-xp"
	gs.tutorial_active = false
	gs.season_leaders = ["stone", "bamboo", "ice"]
	PetLevelsNet.override = FIX.duplicate(true)
	PetLevelsNet.adopt(FIX.duplicate(true))
	## 结算屏(积分赛·胜): 石头龟 65 + 8 跨到 2 级
	var sc = load(SCENE).instantiate()
	get_tree().root.add_child(sc)
	await _frames(30)
	sc.set_process(false)
	sc.set_physics_process(false)
	sc._st_lane_hist = []
	sc._units.clear()
	gs.dual_active = true
	gs.current_lane = "final"
	gs.lane_results = {"top": "left", "bottom": "right", "final": "left"}
	gs.finals_pending_reveal = {}
	gs.week_phase = P2C.PHASE_RANKED
	sc._had_season = true
	sc._last_was_exhibition = false
	sc._last_reward = 15
	sc._last_settle_kind = P2C.SETTLE_RANKED
	sc._settled = false
	var t0 := Time.get_ticks_msec()
	sc._hud._show_banner(true)
	for spec in [[1150, "settle_1_filling"], [1560, "settle_2_levelup"], [3000, "settle_3_done"]]:
		while Time.get_ticks_msec() - t0 < int(spec[0]):
			await get_tree().process_frame
		await _shot(str(spec[1]))
	sc.queue_free()
	await _frames(3)
	## 选龟页
	gs.season_leaders = []
	PetLevelsNet.adopt(FIX.duplicate(true))
	var ts = (load(TS) as PackedScene).instantiate()
	add_child(ts)
	await _frames(40)
	await _shot("teamselect")
	ts.queue_free()
	await _frames(3)
	## 图鉴 石头龟
	var cx = CODEX.instantiate()
	add_child(cx)
	await _frames(10)
	cx._switch_tab("pets")
	await _frames(4)
	for p in DataRegistry.launch_pets:
		if str((p as Dictionary).get("id", "")) == "stone":
			cx._codex_detail._show_pet(p)
	await _frames(10)
	await _shot("codex_stone")
	PetLevelsNet.override = {}
	print("SHOTS DONE")
	get_tree().quit(0)
