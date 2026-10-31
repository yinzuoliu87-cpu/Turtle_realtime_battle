extends Node
## _shot_replay_end_card.gd — 周日开播 C 块实拍(探针, 不进门禁; 方案书 docs/plans/20261031c-周日赛事界面重做.md §4 C)。
## 真战斗场打到上路开战一会儿后冻住(背景 = 真实战场 + 顶栏), 在它上面依次拍:
##   ① 开场 VS(半决赛 / 决赛金)—— 名牌落位 + 阵容翻完(2.9 秒)与倒数(3.4 秒)
##   ② 观战页(开播中): 阶段标签 / 比分条 + 三路灯 / 拔河条 / 下一场条 / 助威栏(按一下飘起来)/ 迟到的「从头看」; 路间幕布那一块
##   ③ 结束三拍 × 三种身份(看别人 / 自己赢 / 自己输 = 出局卡): 每拍落定各一张
## 跑法(离屏、静音):
##   SHOT_OUT=<目录> SHOT_TAG=<phone|ipad> QUIET=1 TURTLE_SUPABASE=" " <godot> --position 5000,5000 --resolution 1560x720 \
##     --audio-driver Dummy --path . res://tests/_shot_replay_end_card.tscn
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const RC := preload("res://scripts/scenes/battle/replay_controls.gd")
const EB := preload("res://scripts/scenes/battle/finals_end_beats.gd")
const VS := preload("res://scripts/scenes/battle/finals_vs_intro.gd")
const HUD := preload("res://scripts/scenes/battle/finals_watch_hud.gd")

var _dir := "user://"
var _tag := "x"
var _gs


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [_dir, name, _tag])
	print("[shot] ", name)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_dir = OS.get_environment("SHOT_OUT") if OS.has_environment("SHOT_OUT") else "user://"
	_tag = OS.get_environment("SHOT_TAG") if OS.has_environment("SHOT_TAG") else "x"
	await get_tree().process_frame
	_gs = get_node("/root/GameState")
	OS.set_environment("TURTLE_SEED", "")
	_gs.reset_dual_lane()
	_gs.test_mode = true
	_gs.tutorial_active = false
	_gs.onboarded = true
	_gs.nickname = "吃货一枚"
	_gs.season_id = 1
	_gs.season_level = 6
	_gs.season_leaders = ["angel", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "angel", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261031
	var bot: Dictionary = Backend.make_bot(3, rng)
	(bot["profile"] as Dictionary)["name"] = "小辉同学"
	_gs.dual_ghost = bot
	_gs.dual_active = true
	var b = RB.new()
	add_child(b)
	b.set_process(false)
	await _frames(2)
	var last := ""
	var stf := 0
	var fight_at := -1
	var i := 0
	while i < 4000:
		var st := str(b._dl_state)
		if st != last:
			last = st
			stf = 0
		stf += 1
		if (st == "overview" or st == "lane_settle") and stf == 9:
			b._dl_sys._dl_present_click()
		elif st == "place" and stf == 20 and is_instance_valid(b._dl_go_btn):
			b._dl_go_btn.pressed.emit()
		if st == "fight" and fight_at < 0:
			fight_at = i
		if fight_at >= 0 and i - fight_at > 40:
			break
		b._process(0.1)
		if i % 6 == 0:
			await get_tree().process_frame
		i += 1
	await _frames(20)
	print("[shot] 背景就位 state=", b._dl_state, " step=", b._sim_step_n)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var m: Vector4 = SafeArea.margins(vp, 18.0)
	var stage := {"cup": true, "group": 0, "round": 2, "rounds": 3, "round_name": "半决赛", "next_name": "决赛", "match_i": 1, "match_n": 2}
	var nxt := {"a": "头发多多", "b": "ykx1314", "at": int(Time.get_unix_time_from_system()) + 95, "r": 2, "m": 1}
	var pair := ["吃货一枚", "小辉同学"]
	var cards := [{"origin": "B 组冠军", "record": "闯关 9 胜 2 负"}, {"group": 4, "record": "闯关 8 胜 3 负", "title": "卫冕"}]
	var base := {"l": "吃货一枚", "r": "小辉同学", "pair": pair, "me": -1, "stage": stage, "next": nxt, "view": "finals",
		"bucket": 1000000, "mini": {"n": 8, "r": 2, "m": 0}, "cards": cards, "srv_off": 0}
	ReplayRecorder.viewer_name = "旁观的人"
	ReplayRecorder.return_scene = "res://scenes/BracketMap.tscn"
	## ① 开场 VS
	for gold in ([] if OS.get_environment("SHOT_ONLY") == "bare" else [false, true]):
		var pn := base.duplicate(true)
		if gold:
			pn["stage"] = {"cup": true, "round": 3, "rounds": 3, "round_name": "决赛"}
			pn["mini"] = {"n": 8, "r": 3, "m": 0}
		ReplayRecorder.play_names = pn
		var ui = RC.new(b)
		ui.build()
		ui.strip.visible = false
		ui._names = {"l": "吃货一枚", "r": "小辉同学"}
		ui.start_vs()
		for tt in [1.15, 2.9, 3.35]:
			ui.vs.t = tt
			ui.vs.pose(tt)
			await _frames(2)
			ui.vs.t = tt
			ui.vs.pose(tt)
			await _shot("VS%s_t%03d" % ["_gold" if gold else "", int(roundf(tt * 100.0))])
		ui.vs.finish()
		ui.root.get_parent().queue_free()
		await _frames(4)
	## ② 观战页(开播中, 迟到进来: 有「从头看」)
	ReplayRecorder.play_names = base.duplicate(true)
	_gs.lane_results = {"top": "left"}
	_gs.current_lane = "bottom"
	var ui2 = RC.new(b)
	ui2.build()
	ui2.strip.visible = false
	ui2._names = {"l": "吃货一枚", "r": "小辉同学"}
	ui2._build_stream_exit(vp, m)
	await _frames(6)
	await _shot("Watch_bare")
	if OS.get_environment("SHOT_ONLY") == "bare":
		get_tree().quit(0)
		return
	ui2.hud = HUD.new(b, ui2)
	ui2.hud.build(ui2.root, vp, m, ui2._names)
	## 「从头看」只在状态流里有: 探针里直接按迟到的样子摆一颗(同一个建法)
	ui2.hud.refresh()
	if b._hud._topbar != null:
		b._hud._topbar._refresh_dots()     # 探针里战斗场停着(set_process false), 顶栏三路点不会自己刷
	await _frames(30)
	ui2.hud.cheer("fire")
	await _frames(8)
	await _shot("Watch_live")
	ui2.hud.toggle_cheers()
	await _frames(4)
	await _shot("Watch_cheers")
	ui2.hud.toggle_cheers()
	var bk_state: String = b._dl_state
	b._dl_state = "lane_settle"
	b._dl_pending_loser = "right"
	_gs.lane_results = {}
	_gs.current_lane = "top"
	b._dl_sys._dl_build_present_overlay("lane_settle")
	ui2.refresh()
	await _frames(12)
	await _shot("Watch_lanebreak")
	if b._dl_present_root != null and is_instance_valid(b._dl_present_root):
		b._dl_present_root.queue_free()     # 直接收掉(淡出 tween 在停着的战斗场上走不完, 会留到后面的收尾实拍里)
		b._dl_present_root = null
	b._dl_state = bk_state
	ui2.root.get_parent().queue_free()
	await _frames(12)
	## ③ 结束三拍 × 三种身份
	var cases := [
		["A_watch", false, "旁观的人", {"me": -1}, {"top": "right", "bottom": "left", "final": "right"}, "final"],
		["B_win", true, "吃货一枚", {"me": 0}, {"top": "left", "bottom": "left"}, "bottom"],
		["C_lose", false, "吃货一枚", {"me": 0}, {"top": "left", "bottom": "right", "final": "right"}, "final"],
	]
	for c in cases:
		_gs.lane_results = (c[4] as Dictionary).duplicate()
		_gs.current_lane = str(c[5])
		var pn2 := base.duplicate(true)
		pn2.merge(c[3], true)
		ReplayRecorder.play_names = pn2
		ReplayRecorder.viewer_name = str(c[2])
		b._replay.rec = {"end": {"s": 6720}, "state": {"dual_ghost": _gs.dual_ghost.duplicate(true)}}
		var ui = RC.new(b)
		ui.build()
		ui.strip.visible = false
		ui._names = {"l": "吃货一枚", "r": "小辉同学"}
		ui._end_card(bool(c[1]), false)
		var bt = ui.beats
		var times: Array = EB.beat_times(str(bt.info["case"]))
		print("[shot] %s 情况=%s 标题=%s" % [c[0], bt.info["case"], bt.info["title"]])
		for k in range(times.size()):
			var tt: float = float(times[k][1]) + (0.5 if k == 0 else float(times[k][2]) - float(times[k][1]) - 0.05)
			bt.t = tt
			bt.pose(tt)
			await _frames(3)
			bt.t = tt
			bt.pose(tt)
			await _shot("%s_beat%d" % [c[0], k + 1])
		bt._disconnect()
		ui.root.get_parent().queue_free()
		ui.card = null
		await _frames(12)
	print("[shot] done")
	get_tree().quit(0)
