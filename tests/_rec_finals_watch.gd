extends Node
## _rec_finals_watch.gd — 周日「看一场冠军杯半决赛」成品录像(探针, 不进门禁; 方案书 docs/plans/20261031c-周日赛事界面重做.md C 块)。
## 真战斗场(背景 = 真实战场 + 顶栏)上按顺序演一遍:
##   开场 VS(约 6 秒)→ 开播画面(比分 / 拔河条 / 三路灯 / 下一场条, 点一下助威表情)→ 路间比分插卡 → 再打几秒 → 结束三拍
##   REC_CASE = A(看别人)/ B(自己赢)/ C(自己输到出局卡, 停 3 秒)/ GOLD(决赛金色开场 VS 单录)
## 跑法(右屏、静音; Movie Maker 定帧率, 时间全按帧走):
##   REC_CASE=A WINDOW=1 bash godot-quiet.sh --position 2000,80 --write-movie <x.avi> --fixed-fps 60 res://tests/_rec_finals_watch.tscn
## 开头准备那一段(打到上路开战)盖黑幕, 打印 [rec] SHOW_START 帧号, 转 mp4 时从那里剪。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const RC := preload("res://scripts/scenes/battle/replay_controls.gd")
const EB := preload("res://scripts/scenes/battle/finals_end_beats.gd")
const HUD := preload("res://scripts/scenes/battle/finals_watch_hud.gd")
## 全局决赛日小条(autoload FinalsDay)要在场: 假时钟 + 假服务端数据(与 M 块实拍同一份夹具)
const FX := preload("res://tests/_finals_day_fixture.gd")
const F := preload("res://scripts/ui/finals_day_feed.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const MON := 1789344000                  # 2026-09-14 周一 00:00 UTC(夹具那一周)

var _gs
var _frame := 0
var _cover: CanvasLayer = null
var _fx = null
var _ts := 0
var _fd = null


func _process(_d: float) -> void:
	_frame += 1


## 等 s 秒(按帧: Movie Maker 定帧率 60)。假时钟每 60 帧走 1 秒, 小条跟着刷。
func _sec(s: float) -> void:
	for _i in range(int(roundf(s * 60.0))):
		await get_tree().process_frame
		if _fx != null and _frame % 60 == 0:
			_ts += 1
			P2.now_override_ts = _ts
			F.override = _fx.feeds(_ts)
			if _fd != null:
				_fd.tick()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var cs := OS.get_environment("REC_CASE") if OS.has_environment("REC_CASE") else "A"
	_cover = CanvasLayer.new()
	_cover.layer = 120
	var blk := ColorRect.new()
	blk.color = Color.BLACK
	blk.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.add_child(blk)
	add_child(_cover)
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
	var b = RB.new()
	add_child(b)
	b.set_process(false)
	await get_tree().process_frame
	## 打到上路开战(黑幕下, 不进成品)
	var last := ""
	var stf := 0
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
		if st == "fight":
			break
		b._process(0.1)
		if i % 20 == 0:
			await get_tree().process_frame
		i += 1
	await get_tree().process_frame
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var m: Vector4 = SafeArea.margins(vp, 18.0)
	var gold := cs == "GOLD"
	var stage := {"cup": true, "group": 0, "round": 2, "rounds": 3, "round_name": "半决赛", "next_name": "决赛", "match_i": 1, "match_n": 2}
	if gold:
		stage = {"cup": true, "group": 0, "round": 3, "rounds": 3, "round_name": "决赛"}
	var me: int = int({"A": -1, "B": 0, "C": 0, "GOLD": -1}.get(cs, -1))
	var pn := {"l": "吃货一枚", "r": "小辉同学", "pair": ["吃货一枚", "小辉同学"], "me": me, "stage": stage,
		"next": {"a": "头发多多", "b": "ykx1314", "at": int(Time.get_unix_time_from_system()) + 95, "r": 2, "m": 1},
		"view": "finals", "bucket": 1000000, "mini": {"n": 8, "r": 3 if gold else 2, "m": 0}, "srv_off": 0,
		"cards": [{"group": 1, "record": "闯关 9 胜 2 负"}, {"group": 4, "record": "闯关 8 胜 3 负", "title": "卫冕"}]}
	ReplayRecorder.play_names = pn
	ReplayRecorder.viewer_name = "旁观的人" if me < 0 else "吃货一枚"
	ReplayRecorder.return_scene = "res://scenes/BracketMap.tscn"
	var ui = RC.new(b)
	ui.build()
	ui.strip.visible = false
	ui._names = {"l": "吃货一枚", "r": "小辉同学"}
	ui._build_stream_exit(vp, m)
	## 全局决赛日小条: 冠军杯赛半决赛第 1 场开播后 20 秒(决赛金那一条 = 决赛开播前 5 秒)
	_fx = FX.new(MON)
	_fx.me_in = cs == "B" or cs == "C"
	var tl: Array = _fx.timeline(6, _fx.cup_start(), _fx.cup_wins)
	_ts = int(((tl[1] as Dictionary)["slots"] as Dictionary).get("2-0", [_fx.cup_start() + 1430])[0]) + 20
	if gold:
		_ts = int(((tl[2] as Dictionary)["slots"] as Dictionary).get("3-0", [_ts])[0]) - 5
	P2.now_override_ts = _ts
	F.override = _fx.feeds(_ts)
	_fd = get_node_or_null("/root/FinalsDay")
	if _fd != null:
		b.scene_file_path = "res://scenes/RealtimeBattle3D.tscn"   # 小条按「观战页」那一套摆 / 写字(点了不跳走)
		_fd.test_host = b                  # 第一次刷在开场 VS 建好之后(一出来就停在 VS 的停靠位, 不从别处滑过去)
	## 观战页那几样先建好(真开播也是先建、开场 VS 盖在上面; VS 放完那一刻小条直接挪到观战页那一块)
	if not gold:
		ui.hud = HUD.new(b, ui)
		ui.hud.build(ui.root, vp, m, ui._names)
	## ── 开场 VS ──
	print("[rec] SHOW_START frame=%d" % _frame)
	_cover.queue_free()
	ui.start_vs()
	_bar_tick()
	if _fd != null:
		print("[rec] bar line=", _fd.line, " slot=", _fd.slot)
	await _sec(VS_DUR() + 0.3)
	if gold:
		print("[rec] done frame=%d" % _frame)
		get_tree().quit(0)
		return
	## ── 开播画面: 比分条 / 拔河条 / 三路灯 / 下一场条; 点一下助威 ──
	ui.refresh()
	_bar_tick()
	b.set_process(true)
	await _sec(2.2)
	ui.hud.toggle_cheers()
	await _sec(0.8)
	ui.hud.cheer("fire")
	await _sec(2.4)
	## ── 路间比分插卡(上路结束) ──
	var top_win: String = str({"A": "right", "B": "left", "C": "left"}.get(cs, "left"))
	b.set_process(false)
	_gs.lane_results = {}
	_gs.current_lane = "top"
	b._dl_pending_loser = "left" if top_win == "right" else "right"
	var keep_state: String = str(b._dl_state)
	b._dl_state = "lane_settle"
	b._dl_sys._dl_build_present_overlay("lane_settle")
	ui.refresh()
	_bar_tick()
	await _sec(3.6)
	if b._dl_present_root != null and is_instance_valid(b._dl_present_root):
		b._dl_present_root.queue_free()
		b._dl_present_root = null
	b._dl_state = keep_state
	_gs.lane_results = {"top": top_win}
	if b._hud._topbar != null:
		b._hud._topbar._refresh_dots()
	b.set_process(true)
	ui.refresh()
	_bar_tick()
	await _sec(3.0)
	## ── 结束三拍 ──
	b.set_process(false)
	var won: bool = bool({"A": false, "B": true, "C": false}.get(cs, false))
	_gs.lane_results = {"A": {"top": "right", "bottom": "left", "final": "right"}, "B": {"top": "left", "bottom": "left"},
		"C": {"top": "left", "bottom": "right", "final": "right"}}.get(cs, {})
	_gs.current_lane = "final" if cs != "B" else "bottom"
	b._replay.rec = {"end": {"s": 6720}, "state": {"dual_ghost": _gs.dual_ghost.duplicate(true)}}
	ui._end_card(won, false)
	## 真开播没有「再看一遍」(那是回放才有); 探针里战斗场不是开播会话 ⇒ 这一颗收起, 画面与真开播相同
	var ag = ui.card.find_child(RC.N_AGAIN, true, false)
	if ag != null:
		ag.visible = false
	_bar_tick()
	var case_s: String = str({"A": "watch", "B": "win", "C": "lose"}.get(cs, "watch"))
	var hold: float = float({"A": EB.AUTO_HOLD - 0.15, "B": 1.5, "C": 3.0}.get(cs, 1.0))
	await _sec(EB.total_of(case_s) + hold)
	print("[rec] done frame=%d" % _frame)
	get_tree().quit(0)


## 换了一层(开场 / 观战 / 插卡 / 收尾)就让小条马上重新找停靠位(它自己每秒也会找一次)。
func _bar_tick() -> void:
	if _fd != null:
		_fd.tick()


static func VS_DUR() -> float:
	return preload("res://scripts/scenes/battle/finals_vs_intro.gd").DUR
