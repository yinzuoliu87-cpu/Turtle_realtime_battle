extends Node
## _shot_replay_ux.gd — 回放体验实拍(探针, 不进门禁)。方案书 docs/plans/20261005-回放体验打磨.md。
## 以玩家身份走一遍: 主菜单 → 战绩 → 点「回放」→ 看(开场 / 开打 / 打到一半 / 换路 / 结束)→ 退出;
##   周六赛况板 → 点一场 → 看 → 退出; 周日对阵图 → 点已揭晓那一格 → 看 → 退出。
## 数据自己造: 后端关着(TURTLE_BACKEND=" "), 真战斗场打一局周六闯关赛留下本机录像;
##   对阵图那一段用假传输层回 `finals_replay`(不连任何外部服务)。
## 跑法(离屏、不开可见窗口、静音):
##   SHOT_OUT=<目录> SHOT_TAG=<比例名> QUIET=1 <godot> --position 5000,5000 --resolution 1560x720 \
##     --audio-driver Dummy --path . res://tests/_shot_replay_ux.tscn
## 环境 SHOT_SPEED=<n>: 播放时按回放条上的倍速钮直到 n×(没有倍速钮就照常速看完)。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const SB := preload("res://scripts/net/supabase.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const ME := "11111111-2222-4333-8444-555555555555"

var _dir := "user://"
var _tag := "x"
var _gs
var _id := ""
var _rec: Dictionary = {}
var _log: Array = []


func _note(s: String) -> void:
	_log.append(s)
	print("[ux] ", s)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _shot(name: String, settle: int = 3) -> void:
	for _i in range(settle):
		await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [_dir, name, _tag])
	_note("shot " + name)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_dir = OS.get_environment("SHOT_OUT") if OS.has_environment("SHOT_OUT") else "user://"
	_tag = OS.get_environment("SHOT_TAG") if OS.has_environment("SHOT_TAG") else "x"
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	OS.set_environment("TURTLE_SEED", "")
	_setup_gs()
	if OS.get_environment("SHOT_ONLY") == "live":
		await _flow_live()
		get_tree().quit(0)
		return
	await _record()
	if _id == "":
		_note("录制失败")
		get_tree().quit(1)
		return
	var sp := OS.get_environment("SHOT_ONLY")
	if sp == "live":
		await _flow_live()
	if sp == "" or sp == "record":
		await _flow_record()
	if sp == "" or sp == "board":
		await _flow_board()
	if sp == "" or sp == "bracket":
		await _flow_bracket()
	_note("done")
	var f := FileAccess.open("%s/ux_log_%s.txt" % [_dir, _tag], FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_log))
		f.close()
	get_tree().quit(0)


func _setup_gs() -> void:
	_gs.reset_dual_lane()
	_gs.test_mode = true
	_gs.tutorial_active = false
	_gs.onboarded = true
	_gs.week_phase = "gauntlet"
	_gs.season_id = 1
	_gs.season_level = 6
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261005
	_gs.dual_ghost = Backend.make_bot(3, rng)
	_gs.dual_active = true
	_gs.account_id = ME


## 真战斗场打一局(不认输, 三路打完)。
func _record() -> void:
	var hist0: int = (_gs.match_history as Array).size()
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	_note("rec mode=" + str(s._replay.mode))
	var last := ""
	var stf := 0
	var fights := 0
	var i := 0
	while i < 9000 and (_gs.match_history as Array).size() == hist0:
		var st: String = str(s._dl_state)
		if st != last:
			last = st
			stf = 0
		stf += 1
		if (st == "overview" or st == "lane_settle") and stf == 9:
			s._dl_sys._dl_present_click()
		elif st == "place" and stf == 20 and is_instance_valid(s._dl_go_btn):
			s._dl_go_btn.pressed.emit()
			fights += 1
		s._process(0.1)
		if i % 4 == 0:
			await get_tree().process_frame
		i += 1
	await _frames(10)
	_id = str(_gs.match_history[0].get("replay_id", "")) if (_gs.match_history as Array).size() > hist0 else ""
	_rec = ReplayRecorder.load_record(_id) if _id != "" else {}
	_note("recorded id=%s fights=%d steps=%d won=%s" % [_id, fights,
		int((_rec.get("end", {}) as Dictionary).get("s", -1)), str((_rec.get("end", {}) as Dictionary).get("won", "?"))])
	s.queue_free()
	await _frames(4)


func _scene_is(n, suffix: String) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() != null \
		and str((n.get_script() as Script).resource_path).ends_with(suffix)


func _wait_scene(suffix: String, max_frames: int = 300) -> Node:
	for _i in range(max_frames):
		var cs := get_tree().current_scene
		if _scene_is(cs, suffix):
			return cs
		await get_tree().process_frame
	return null


func _open(path: String) -> Node:
	var n: Node = (load(path) as PackedScene).instantiate()
	get_tree().root.add_child(n)
	get_tree().current_scene = n
	await _frames(3)
	return n


## 看一场: 让战斗场自己按真实帧走(玩家眼里的速度), 关键时刻拍照。
func _watch(prefix: String) -> void:
	var b = await _wait_scene("RealtimeBattle3DScene.gd")
	if b == null:
		_note(prefix + " 没进战斗场")
		return
	var t0 := Time.get_ticks_msec()
	await _frames(20)
	await _shot(prefix + "_01_start")
	var want := int(OS.get_environment("SHOT_SPEED")) if OS.has_environment("SHOT_SPEED") else 1
	if want > 1:
		await _press_speed(b, want)
	var shot_fight := false
	var shot_mid := false
	var shot_lane := false
	var shot_place := false
	var fight_step := -1
	var fights := 0
	var last := ""
	var guard := 0
	while Time.get_ticks_msec() - t0 < 300000:
		guard += 1
		await get_tree().process_frame
		if not is_instance_valid(b):
			break
		var st := str(b._dl_state)
		if st != last:
			_note("%s t=%.1fs step=%d state %s→%s" % [prefix, (Time.get_ticks_msec() - t0) / 1000.0, int(b._sim_step_n), last, st])
			if st == "fight":
				fights += 1
				fight_step = int(b._sim_step_n)
			last = st
		if st == "place" and not shot_place:
			shot_place = true
			await _frames(5)
			await _shot(prefix + "_02_place")
		if st == "fight" and fights == 1 and not shot_fight and int(b._sim_step_n) > fight_step + 240:
			shot_fight = true
			await _shot(prefix + "_03_fight")
			var pb := _find_btn(b, ["暂停"])
			if pb != null:
				pb.pressed.emit()
				await _frames(10)
				await _shot(prefix + "_03b_paused")
				var cb := _find_btn(b, ["继续"])
				if cb != null:
					cb.pressed.emit()
		if st == "fight" and fights == 1 and not shot_mid and int(b._sim_step_n) > fight_step + 900:
			shot_mid = true
			await _shot(prefix + "_04_mid")
		if fights == 1 and (st == "lane_settle" or st == "overview") and not shot_lane:
			shot_lane = true
			await _frames(30)
			await _shot(prefix + "_05_lane")
		if b._replay.finished or b._replay.diverged_at >= 0:
			break
	_note("%s 播完 real=%.1fs steps=%d finished=%s div=%d settled=%s" % [prefix, (Time.get_ticks_msec() - t0) / 1000.0,
		int(b._sim_step_n), str(b._replay.finished), int(b._replay.diverged_at), str(b._settled)])
	var tw := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 2500:
		await get_tree().process_frame
	await _shot(prefix + "_06_end")
	## 退出: 找回放条/收尾卡上的「退出」按钮(真入口)。
	var ex := _find_btn(b, ["返回", "退出回放", "退出"])
	_note("%s exit button=%s" % [prefix, ex.text if ex != null else "<none>"])
	if ex != null:
		ex.pressed.emit()
	else:
		b._hud._replay_exit()


func _press_speed(b, want: int) -> void:
	for _k in range(4):
		var sb := _find_btn(b, ["倍速", "×", "x"])
		if sb == null:
			_note("没有倍速钮")
			return
		if sb.text.find(str(want)) >= 0:
			return
		sb.pressed.emit()
		await _frames(2)


func _find_btn(root: Node, keys: Array) -> Button:
	for k in keys:
		for c in root.find_children("*", "Button", true, false):
			var bt := c as Button
			if bt.is_visible_in_tree() and str(bt.text).find(str(k)) >= 0:
				return bt
	return null


func _flow_record() -> void:
	## 主菜单
	var mm: Node = await _open("res://scenes/MainMenu.tscn")
	await _frames(240)
	await _shot("A_00_menu")
	var rb := mm.find_child("RecordEntry", true, false)
	_note("主菜单「战绩」入口节点 RecordEntry=" + str(rb != null))
	mm.queue_free()
	var rs: Node = await _open("res://scenes/Record.tscn")
	await _frames(60)
	await _shot("A_01_record")
	var btns: Array = rs.find_children("ReplayBtn", "Button", true, false)
	_note("战绩页回放按钮 %d 个" % btns.size())
	if btns.is_empty():
		return
	(btns[0] as Button).pressed.emit()
	await _watch("A")
	var back: Node = await _wait_scene("RecordScene.gd")
	_note("A 退出后落在 " + (str(back.get_script().resource_path) if back != null else str(get_tree().current_scene)))
	await _frames(30)
	await _shot("A_07_back")


func _flow_board() -> void:
	var mon: int = P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	var sat := mon + 5 * 86400 + 15 * 3600
	var bs: Node = await _open("res://scenes/GauntletBoard.tscn")
	var rows: Array = [{"match_id": _id, "created_at": Time.get_datetime_string_from_unix_time(sat) + "+00:00",
		"result": {"won": bool((_rec.get("end", {}) as Dictionary).get("won", false)), "steps": 3000, "surrendered": false, "gw": 3, "gl": 1},
		"lp": {"name": "海风小将", "tag": P2C.player_tag("b"), "avatar": "bamboo", "id": "g_b"},
		"rp": (_gs.dual_ghost as Dictionary).get("profile", {}), "rw": 2, "rl": 1}]
	bs.set_rows(rows)
	await _frames(60)
	await _shot("B_01_board")
	var gb: Array = bs.find_children("GameBtn", "Button", true, false)
	_note("赛况板对局按钮 %d 个" % gb.size())
	if gb.is_empty():
		return
	(gb[0] as Button).pressed.emit()
	await _watch("B")
	var back: Node = await _wait_scene("GauntletBoardScene.gd")
	_note("B 退出后落在 " + (str(back.get_script().resource_path) if back != null else str(get_tree().current_scene)))
	await _frames(30)
	await _shot("B_07_back")


func _transport(m, u, _h, _b, cb) -> void:
	var url := str(u)
	if url.find("/auth/v1/") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({
			"access_token": "tok", "refresh_token": "r2", "expires_in": 3600,
			"user": {"id": ME, "is_anonymous": true}})})
		return
	if url.find("/rest/v1/rpc/finals_replay") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify(
			{"ok": true, "match_id": _id, "replay": RU.upload_b64(_rec)})})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


func _flow_bracket() -> void:
	OS.set_environment(SB.ENV_URL, "http://shot.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "shot-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._token = "tok"
	var now := int(Time.get_unix_time_from_system())
	var wk := P2C.week_anchor_utc(now)
	var nm := ["石头统领", "海风小将", "阿龟", "竹林隐士", "老船长", "浪里白条", "夜光贝", "铁甲先生"]
	var ents: Array = []
	for i in range(8):
		ents.append({"seed": i, "name": nm[i], "account_id": "acct-%d" % i})
	var wv: Dictionary = SB.parse_finals_week(true, 200, JSON.stringify({"ok": true, "week": wk, "now": now,
		"buckets": [{"bucket": 1, "n": 8, "round": 2, "closed": false,
			"done": {"1-0": 0, "1-1": 1, "1-2": 0, "1-3": 1}, "entrants": ents}]}), "", now)
	var m: Node = await _open("res://scenes/BracketMap.tscn")
	m.set_data({}, {}, now)
	m.set_week(wv)
	await _frames(60)
	await _shot("C_01_bracket")
	m.open_replay(1, 1)
	await _watch("C")
	var back: Node = await _wait_scene("BracketMapScene.gd")
	_note("C 退出后落在 " + (str(back.get_script().resource_path) if back != null else str(get_tree().current_scene)))
	await _frames(60)
	await _shot("C_07_back")
	SB._transport_for_test = Callable()


## 实战(不是回放): 主菜单(带头衔) / 选龟页 / 摆位屏(开打钮) / 开打后(两侧单位栏 + 顶部路名)。
func _flow_live() -> void:
	_gs.titles = [P2C.title_row(P2C.TITLE_SEMIFINAL, P2C.week_anchor_utc(int(Time.get_unix_time_from_system())))]
	_gs.battles_total = 4
	_gs.battles_won = 3
	var mm: Node = await _open("res://scenes/MainMenu.tscn")
	await _frames(240)
	await _shot("L_00_menu")
	mm.queue_free()
	var ts: Node = await _open("res://scenes/TeamSelect.tscn")
	await _frames(120)
	await _shot("L_01_teamselect")
	ts.queue_free()
	var b = RB.new()
	get_tree().root.add_child(b)
	get_tree().current_scene = b
	var last := ""
	var stf := 0
	var shot_ov := false
	for _i in range(6000):
		await get_tree().process_frame
		var st := str(b._dl_state)
		if st != last:
			last = st
			stf = 0
		stf += 1
		if st == "overview" and stf == 30 and not shot_ov:
			shot_ov = true
			await _shot("L_02_overview")
			b._dl_sys._dl_present_click()
		elif st == "preview" and stf == 30:
			await _shot("L_03_preview")
			b._dl_sys._dl_present_click()
		elif st == "place" and stf == 40:
			await _shot("L_04_place")
			b._dl_go_btn.pressed.emit()
		elif st == "fight" and stf == 400:
			await _shot("L_05_fight")
			break
	b.queue_free()
