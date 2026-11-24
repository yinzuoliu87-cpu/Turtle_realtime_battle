extends Node
## _rec_finals_open.gd — 周日开播「开场」成品录像(探针, 不进门禁; 方案书 docs/plans/20261122-周日全流程走查与优化.md B2)。
## 真流程自己走: 桌面地图开场(轮次缎带 / 名牌 / VS 盾徽, lane_map_finals)→ 对阵幕(上路三对三斜切对峙)→ 布阵 → 开打 → 再录 3 秒。
## 与 _rec_finals_watch 的区别: 那个台是先在黑幕下打到开战再手动摆各幕; 这里战斗场一开始就挂好周日观战页, 幕布按真流程换。
## 跑法(右屏、静音; Movie Maker 定 60 帧):
##   QUIET=1 SHIP=1 TURTLE_SUPABASE=" " WINDOW=1 bash godot-quiet.sh --position 2200,200 --resolution 1280x720 \
##     --write-movie <x.avi> --fixed-fps 60 --quit-after 1500 res://tests/_rec_finals_open.tscn
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const RC := preload("res://scripts/scenes/battle/replay_controls.gd")
const HUD := preload("res://scripts/scenes/battle/finals_watch_hud.gd")

var _gs


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	await get_tree().process_frame
	_gs = get_node("/root/GameState")
	OS.set_environment("TURTLE_SEED", "")
	_gs.reset_dual_lane()
	_gs.test_mode = true
	_gs.tutorial_active = false
	_gs.onboarded = true
	_gs.nickname = "旁观的人"
	_gs.season_id = 1
	_gs.season_level = 6
	_gs.season_leaders = ["angel", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "angel", "equips": []}, {"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []}, {"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261031
	var bot: Dictionary = Backend.make_bot(3, rng)
	(bot["profile"] as Dictionary)["name"] = "小辉同学"
	_gs.dual_ghost = bot
	_gs.dual_active = true
	ReplayRecorder.play_names = {"l": "吃货一枚", "r": "小辉同学", "pair": ["吃货一枚", "小辉同学"], "me": -1,
		"stage": {"cup": true, "group": 0, "round": 2, "rounds": 3, "round_name": "半决赛", "next_name": "决赛", "match_i": 1, "match_n": 2},
		"view": "finals", "bucket": 1000000, "srv_off": 0,
		"cards": [{"group": 1, "record": "闯关 9 胜 2 负"}, {"group": 4, "record": "闯关 8 胜 3 负", "title": "卫冕"}]}
	ReplayRecorder.viewer_name = "旁观的人"
	var b = RB.new()
	add_child(b)
	await get_tree().process_frame
	## 周日开播: 战斗场 HUD 挂着建了观战页的回放控件(真开播就是这样认「周日这一场」)
	var ui = RC.new(b)
	ui.build()
	ui.strip.visible = false
	ui._names = {"l": "吃货一枚", "r": "小辉同学"}
	var vp: Vector2 = get_viewport().get_visible_rect().size
	ui.hud = HUD.new(b, ui)
	ui.hud.build(ui.root, vp, SafeArea.margins(vp, 18.0), ui._names)
	b._hud._replay_ui = ui
	## 开场幕布在战斗场进场那一刻已经建了(那时还没挂观战页)⇒ 按周日重建一次, 从 0 秒演
	_gs.current_lane = "top"
	b._dl_sys._dl_build_present_overlay("overview")
	ui.refresh()
	print("[rec] SHOW_START")
	## 真流程: 开场 5 秒 → 对阵 5 秒 → 布阵(点开打)→ 开打后再录 3 秒
	var fought := -1
	for i in 60 * 20:
		await get_tree().process_frame
		if str(b._dl_state) == "place" and is_instance_valid(b._dl_go_btn) and b._dl_go_btn.visible:
			b._dl_go_btn.pressed.emit()
		if str(b._dl_state) == "fight" and fought < 0:
			fought = i
			print("[rec] fight at frame ", i)
		if fought >= 0 and i - fought > 180:
			break
		if i % 30 == 0:
			ui.refresh()
	print("[rec] done")
	get_tree().quit(0)
