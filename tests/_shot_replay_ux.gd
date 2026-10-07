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
## 环境 SHOT_NOWATCH=1: 周六 / 周日只拍页面(空态 + 有数据), 不进回放(看版式时用, 快)。
## 环境 SHOT_ONLY=board|bracket|record|live|watch: 只走那一段。
##   watch = 实时观赛(2026-10-07, docs/plans/20261007-实时观赛.md): 周六赛况板「正在打」/ 观赛屏(同步中 · 跟播 ·
##   下路准备中 · 收尾卡)/ 周日对阵图开播窗口内外 + 弹卡两种 / 开播观赛屏。假传输层当服务器, 不连外部服务。
##   cup = 冠军杯赛(2026-10-07, docs/plans/20261007-冠军杯赛.md): 小组赛页 / 冠军杯赛开赛前 / 成表我那场可打 /
##   翻面开播 / 打完冠军 + 决赛弹卡 / 1 人表直接夺冠。数据直接喂(set_data / set_week), 不联网。
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
	if OS.get_environment("SHOT_ONLY") == "cupv2":
		await _flow_cup_v2()
		get_tree().quit(0)
		return
	if OS.get_environment("SHOT_ONLY") == "cup":
		await _flow_cup()
		get_tree().quit(0)
		return
	if OS.get_environment("SHOT_ONLY") == "watch":
		await _flow_watch()
		_note("done")
		var fw := FileAccess.open("%s/ux_log_%s.txt" % [_dir, _tag], FileAccess.WRITE)
		if fw != null:
			fw.store_string("\n".join(_log))
			fw.close()
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
	## 战绩页要有几张卡才看得出版式: 在录下的那一场后面补几场(没录像; 一条老记录不带对手)。
	var now := int(Time.get_unix_time_from_system())
	var pad := [["win", ["lightning", "shell", "candy"], "浪里白条", ["ice", "hunter", "basic"], 74, 1500],
		["lose", ["basic", "stone", "bamboo"], "竹林隐士", ["angel", "lava", "stone"], 112, 7300],
		["win", ["basic", "stone", "bamboo"], "老船长", ["pirate", "ghost", "bubble"], 95, 90000],
		["lose", ["basic", "fire"], "", [], 61, 400000]]
	for p in pad:
		var e := {"result": p[0], "lineup": p[1], "mode": "实时", "turn": p[4], "ts": now - int(p[5])}
		if str(p[2]) != "":
			e["foe_name"] = p[2]
			e["foe"] = p[3]
		(_gs.match_history as Array).append(e)
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


## 周六赛况板的假数据: 真录的那一局 + 6 场别人的(8 个人, 有晋级 / 在打 / 出局; 双方阵容 la/ra 都有)。
## ★最后一场 match_id 不是 uuid ⇒ 那张卡**不该**有「观看」(看版式时顺带看没有木牌的卡长什么样)。
func _board_rows() -> Array:
	var mon: int = P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	var sat := mon + 5 * 86400 + 15 * 3600
	var now := int(Time.get_unix_time_from_system())
	var t_last: int = mini(now, sat + 3 * 3600)
	var ppl := {
		"a": {"name": "海风小将", "tag": P2C.player_tag("b"), "avatar": "bamboo", "id": "g_b"},
		"b": {"name": "石头统领", "tag": P2C.player_tag("s"), "avatar": "stone", "id": "g_s"},
		"c": {"name": "竹林隐士", "tag": P2C.player_tag("z"), "avatar": "angel", "id": "g_z"},
		"d": {"name": "老船长", "tag": P2C.player_tag("p"), "avatar": "pirate", "id": "g_p"},
		"e": {"name": "浪里白条", "tag": P2C.player_tag("w"), "avatar": "ice", "id": "g_w"},
		"f": {"name": "夜光贝", "tag": P2C.player_tag("y"), "avatar": "crystal", "id": "g_y"},
		"g": {"name": "铁甲先生", "tag": P2C.player_tag("t"), "avatar": "diamond", "id": "g_t"},
	}
	var lu := {"a": ["bamboo", "basic", "stone"], "b": ["stone", "lava", "hunter"], "c": ["angel", "ghost", "candy"],
		"d": ["pirate", "bubble", "shell"], "e": ["ice", "lightning", "fortune"], "f": ["crystal", "dice", "hiding"],
		"g": ["diamond", "cyber", "headless"]}
	var games := [["a", "b", true, 3, 1, 2, 2, 25], ["c", "d", false, 1, 3, 3, 0, 60], ["e", "f", true, 2, 2, 1, 2, 95],
		["g", "a", false, 0, 3, 2, 1, 140], ["b", "e", true, 4, 1, 1, 2, 200], ["d", "g", true, 3, 1, 0, 2, 260]]
	var rows: Array = []
	var gp: Dictionary = (_gs.dual_ghost as Dictionary).get("profile", {})
	rows.append({"match_id": _id, "created_at": Time.get_datetime_string_from_unix_time(t_last - 600) + "+00:00",
		"result": {"won": bool((_rec.get("end", {}) as Dictionary).get("won", false)), "steps": 3000, "surrendered": false, "gw": 3, "gl": 1},
		"lp": ppl["a"], "rp": gp, "la": lu["a"], "ra": (_gs.dual_ghost as Dictionary).get("leaders", []), "rw": 2, "rl": 1})
	var k := 0
	for g in games:
		k += 1
		var id := "%08d-1111-4222-8333-%012d" % [k, k] if k < games.size() else "legacy-row-%d" % k
		rows.append({"match_id": id, "created_at": Time.get_datetime_string_from_unix_time(t_last - int(g[7]) * 60) + "+00:00",
			"result": {"won": g[2], "gw": g[3], "gl": g[4]}, "lp": ppl[g[0]], "rp": ppl[g[1]],
			"la": lu[g[0]], "ra": lu[g[1]], "rw": g[5], "rl": g[6]})
	return rows


func _flow_board() -> void:
	## 空态先拍一张: 没接服务器(TURTLE_BACKEND=" ")⇒ 正中提示框。
	var be: Node = await _open("res://scenes/GauntletBoard.tscn")
	await _frames(20)
	await _shot("B_00_empty")
	be.queue_free()
	await _frames(2)
	var rows := _board_rows()
	var bs: Node = await _open("res://scenes/GauntletBoard.tscn")
	bs.set_rows(rows)
	await _frames(60)
	await _shot("B_01_board")
	## 点一个人 ⇒ 右栏只剩他的那几场
	var pb: Array = bs.find_children("PlayerBtn", "Button", true, false)
	if pb.size() > 1:
		(pb[1] as Button).pressed.emit()
		await _frames(10)
		await _shot("B_01b_focus")
		bs._show_all()
		await _frames(5)
	var gb: Array = bs.find_children("GameBtn", "Button", true, false)
	_note("赛况板观看按钮 %d 个 / 卡 %d 张" % [gb.size(), (bs.data.get("games", []) as Array).size()])
	if gb.is_empty() or OS.get_environment("SHOT_NOWATCH") == "1":
		return
	(gb[0] as Button).pressed.emit()
	await _watch("B")
	var back: Node = await _wait_scene("GauntletBoardScene.gd")
	_note("B 退出后落在 " + (str(back.get_script().resource_path) if back != null else str(get_tree().current_scene)))
	## ★回来的是一个新建的赛况板: 探针那份注入数据已不在(后端关着, 它只会说「不支持在线赛况」)
	##   ⇒ 再喂一次, 「返回」这张拍的才是玩家真回来时看到的样子(有数据的那一页)。
	if back != null:
		back.set_rows(rows)
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


## 周日对阵图的假数据: 第 1 组 8 人(第一轮全揭晓 ⇒ 4 颗「观看」/ 第二轮进行中 / 决赛待定),
##   第 2 组 4 人(已收盘, 决赛打完 ⇒ 冠军)。头像按 #ID 喂, 故意留两个人对不上(画名字首字)。
func _bracket_feed(now: int) -> Array:
	var wk := P2C.week_anchor_utc(now)
	var nm := ["石头统领", "海风小将", "阿龟", "竹林隐士", "老船长", "浪里白条", "夜光贝", "铁甲先生"]
	var av := ["stone", "bamboo", "", "angel", "pirate", "ice", "", "diamond"]
	var ents: Array = []
	var por := {}
	for i in range(8):
		ents.append({"seed": i, "name": nm[i], "account_id": "acct-%d" % i})
		if str(av[i]) != "":
			por[P2C.player_tag("acct-%d" % i)] = av[i]
	var nm2 := ["糖果龟主", "雷霆小队", "冰川行者", "猎手阿岩"]
	var av2 := ["candy", "lightning", "ice", "hunter"]
	var ents2: Array = []
	for i in range(4):
		ents2.append({"seed": i, "name": nm2[i], "account_id": "acct-b%d" % i})
		por[P2C.player_tag("acct-b%d" % i)] = av2[i]
	var wv: Dictionary = SB.parse_finals_week(true, 200, JSON.stringify({"ok": true, "week": wk, "now": now,
		"buckets": [{"bucket": 0, "n": 8, "round": 2, "closed": false,
			"done": {"1-0": 0, "1-1": 1, "1-2": 0, "1-3": 1}, "entrants": ents},
			{"bucket": 1, "n": 4, "round": 2, "closed": true,
			"done": {"1-0": 0, "1-1": 1, "2-0": 1}, "entrants": ents2}]}), "", now)
	return [wv, por]


func _feed_bracket(m: Node, now: int) -> void:
	var fd := _bracket_feed(now)
	m.set_data({}, {}, now)
	m.set_week(fd[0])
	m.set_portraits(fd[1])


func _flow_bracket() -> void:
	OS.set_environment(SB.ENV_URL, "http://shot.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "shot-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._token = "tok"
	var now := int(Time.get_unix_time_from_system())
	## 空态: 没有组、观赛名单也没有 ⇒ 正中提示框。
	var me: Node = await _open("res://scenes/BracketMap.tscn")
	me.set_data({}, {}, now)
	me.set_week({"buckets": []})
	await _frames(20)
	await _shot("C_00_empty")
	(me._tabs.get_child(1) as Button).pressed.emit()
	await _frames(10)
	await _shot("C_00b_champ_empty")
	me.queue_free()
	await _frames(2)
	var m: Node = await _open("res://scenes/BracketMap.tscn")
	_feed_bracket(m, now)
	await _frames(60)
	await _shot("C_01_bracket")
	m._spec_step(1)
	await _frames(20)
	await _shot("C_01b_bracket_closed")
	(m._tabs.get_child(1) as Button).pressed.emit()
	await _frames(20)
	await _shot("C_01c_champions")
	(m._tabs.get_child(0) as Button).pressed.emit()
	m._spec_step(-1)
	await _frames(10)
	## 点一格已揭晓的 ⇒ 弹出对局卡(审图第三版: 「观看」在卡里, 对阵图上没有按钮)
	var nb: Array = m._canvas.find_children("NodeBtn", "Button", true, false)
	_note("对阵图可点的格子 %d 个" % nb.size())
	if nb.is_empty():
		SB._transport_for_test = Callable()
		return
	(nb[0] as Button).pressed.emit()
	await _frames(10)
	await _shot("C_01d_popup")
	var go: Button = m.find_child("PopupGoBtn", true, false) as Button
	if OS.get_environment("SHOT_NOWATCH") == "1" or go == null:
		SB._transport_for_test = Callable()
		return
	go.pressed.emit()
	await _watch("C")
	var back: Node = await _wait_scene("BracketMapScene.gd")
	_note("C 退出后落在 " + (str(back.get_script().resource_path) if back != null else str(get_tree().current_scene)))
	## ★同赛况板: 回来的是新建的对阵图, 再喂一次那份数据。
	if back != null:
		_feed_bracket(back, now)
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



# ═════════════════════════════════════════════════════════════
#  实时观赛(SHOT_ONLY=watch)
# ═════════════════════════════════════════════════════════════
const LS := preload("res://scripts/systems/replay/live_spectate.gd")
const LU := preload("res://scripts/systems/replay/live_upload.gd")
const GB := preload("res://scripts/systems/replay/gauntlet_board.gd")
var _w_snaps: Array = []
var _w_serve: Dictionary = {}
var _w_board_live: Array = []
var _w_board_games: Array = []
var _w_rec_b = null
var _w_fights := 0
var _w_rec: Dictionary = {}
var _w_id := ""


func _w_iso(t: int) -> String:
	return Time.get_datetime_string_from_unix_time(t) + "+00:00"


func _w_transport(m, u, h, b, cb) -> void:
	var url := str(u)
	var method := str(m).to_upper()
	if url.find("/auth/v1/") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({
			"access_token": "tok", "refresh_token": "r2", "expires_in": 3600,
			"user": {"id": ME, "is_anonymous": true}})})
		return
	if url.find("/rest/v1/live_matches") >= 0:
		if method == "POST":
			var j := JSON.new()
			if j.parse(str(b)) == OK and j.data is Dictionary:
				_w_snaps.append({"row": j.data, "st": str(_w_rec_b._dl_state) if _w_rec_b != null and is_instance_valid(_w_rec_b) else "",
					"fights": _w_fights})
			cb.call({"ok": true, "code": 201, "body": ""})
			return
		if url.find("match_id=eq.") >= 0:
			cb.call({"ok": true, "code": 200, "body": JSON.stringify([_w_serve]) if not _w_serve.is_empty() else "[]"})
			return
		cb.call({"ok": true, "code": 200, "body": JSON.stringify(_w_board_live)})
		return
	if url.find("/rest/v1/matches") >= 0 and method == "GET" and url.find("phase=eq.gauntlet") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify(_w_board_games)})
		return
	if url.find("/rest/v1/rpc/finals_replay") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "match_id": _w_id, "replay": RU.upload_b64(_w_rec)})})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


func _w_served(sn: Dictionary) -> Dictionary:
	var r: Dictionary = sn["row"]
	return {"match_id": str(r["match_id"]), "replay": str(r["replay"]), "horizon": int(r["horizon"]),
		"ended": bool(r["ended"]), "client_version": str(r["client_version"]), "updated_at": _w_iso(P2C.now_utc())}


func _w_open(path: String) -> Node:
	var cs := get_tree().current_scene
	if cs != null and is_instance_valid(cs) and cs != self:
		cs.queue_free()
	await _frames(2)
	return await _open(path)


func _flow_watch() -> void:
	OS.set_environment(SB.ENV_URL, "http://shot.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "shot-anon-key")
	SB._transport_for_test = _w_transport
	SB._reset_auth_for_test()
	SB._token = "tok"
	var now := int(Time.get_unix_time_from_system())
	_gs.week_anchor_ts = P2C.week_anchor_utc(now)
	## ① 打的人: 真打一局周六闯关赛(直播一路上传到假服务器); 第二路摆位停 20 秒(观众那边要拍「下路准备中」)
	var s = RB.new()
	_w_rec_b = s
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	var last := ""
	var stf := 0
	var i := 0
	while i < 9000 and not s._replay.finished:
		var st: String = str(s._dl_state)
		if st != last:
			last = st
			stf = 0
		stf += 1
		if (st == "overview" or st == "lane_settle") and stf == 9:
			s._dl_sys._dl_present_click()
		elif st == "place" and is_instance_valid(s._dl_go_btn) and s._dl_go_btn.visible \
				and ((_w_fights == 0 and stf == 20) or (_w_fights == 1 and stf == 400) or (_w_fights >= 2 and stf == 20)):
			_w_fights += 1
			s._dl_go_btn.pressed.emit()
		s._process(0.05)
		if i % 4 == 0:
			await get_tree().process_frame
		i += 1
	await _frames(6)
	_w_id = str(s._replay.rec.get("id", ""))
	_w_rec = ReplayRecorder.load_record(_w_id)
	_w_rec_b = null
	s.queue_free()
	await _frames(4)
	_note("watch: 打完 %d 份直播行, id=%s steps=%d" % [_w_snaps.size(), _w_id, int((_w_rec.get("end", {}) as Dictionary).get("s", -1))])
	if _w_snaps.size() < 5:
		return
	## ② 周六赛况板: 正在打两场(录的那一场 + 一场别人的) + 打完的几场
	var j := 0
	for k in range(_w_snaps.size()):
		if int(_w_snaps[k]["fights"]) == 1 and int(_w_snaps[k]["row"]["horizon"]) > int(_w_snaps[0]["row"]["horizon"]) + 900:
			j = k
			break
	var jr: Dictionary = _w_snaps[j]["row"]
	var mine := {"match_id": _w_id, "started_at": _w_iso(now - 75), "updated_at": _w_iso(now), "client_version": str(jr["client_version"]),
		"lp": jr["left_snapshot"]["profile"], "rp": jr["right_snapshot"]["profile"],
		"la": jr["left_snapshot"]["leaders"], "ra": jr["right_snapshot"]["leaders"]}
	(mine["lp"] as Dictionary)["name"] = "浪花骑士"
	(mine["lp"] as Dictionary)["tag"] = P2C.player_tag("q")      # 拍的是「别人正在打」: 不是我那个号
	var other := {"match_id": "aaaaaaaa-1111-4222-8333-000000000001", "started_at": _w_iso(now - 200), "updated_at": _w_iso(now - 1),
		"client_version": str(jr["client_version"]), "lp": {"name": "老船长", "tag": P2C.player_tag("p"), "avatar": "pirate"},
		"rp": {"name": "夜光贝", "tag": P2C.player_tag("y"), "avatar": "crystal"},
		"la": ["pirate", "bubble", "shell"], "ra": ["crystal", "dice", "hiding"]}
	_w_board_live = [mine, other]
	_w_board_games = _board_rows()
	_w_board_games.remove_at(0)            # 第一行是回放那一段录的; 这一段只要别人打完的
	var bs: Node = await _w_open("res://scenes/GauntletBoard.tscn")
	await _frames(60)
	await _shot("W_01_board_live")
	var tg: String = GB.tag_of(mine["lp"])
	for pr in bs._players_box.get_children():
		if str((pr as Node).get_meta("tag", "")) == tg:
			(pr.find_child("PlayerBtn", true, false) as Button).pressed.emit()
	await _frames(10)
	await _shot("W_01b_focus_live")
	bs._show_all()
	await _frames(5)
	## ③ 点「观赛」⇒ 观赛屏
	var lb: Button = null
	for c in bs.find_children("LiveCard*", "", true, false):
		if str((c as Node).get_meta("match_id", "")) == _w_id:
			lb = c.find_child("LiveBtn", true, false) as Button
	_w_serve = _w_served(_w_snaps[j])
	if lb == null:
		_note("watch: 没找到观赛钮")
		return
	lb.pressed.emit()
	var b = await _wait_scene("RealtimeBattle3DScene.gd")
	if b == null or not b._replay.is_live():
		_note("watch: 没进观赛 " + str(bs.last_replay_msg if is_instance_valid(bs) else ""))
		return
	var lv = b._replay.live
	var t0 := Time.get_ticks_msec()
	var h0 := int(jr["horizon"])
	var shot_sync := false
	var shot_fight := false
	var shot_wait := false
	var hold_ms := -1
	var k2 := j
	while Time.get_ticks_msec() - t0 < 240000 and not b._replay.finished and not lv.broken:
		await get_tree().process_frame
		## 服务器按「打的人的进度」放行: 打的人比观众早 7 秒; 观众停在第二路摆位上时, 服务器多扣 4 秒不放开打那一份(拍「下路准备中」)
		var clock := int(b._sim_step_n) + 420
		var nxt := k2
		while nxt + 1 < _w_snaps.size() and int(_w_snaps[nxt + 1]["row"]["horizon"]) <= maxi(clock, h0):
			nxt += 1
		if str(b._dl_state) == "place" and int(_w_snaps[nxt]["fights"]) >= 2 and int(b._replay._ev_i) <= 3 and not shot_wait:
			if hold_ms < 0:
				hold_ms = Time.get_ticks_msec()
			if Time.get_ticks_msec() - hold_ms < 4000:
				while nxt > k2 and int(_w_snaps[nxt]["fights"]) >= 2:
					nxt -= 1
		if nxt != k2:
			k2 = nxt
			_w_serve = _w_served(_w_snaps[k2])
			lv.poll()
		if not shot_sync and str(lv.status) == LS.TXT_SYNC and Time.get_ticks_msec() - t0 > 300:
			shot_sync = true
			await _shot("W_02_live_sync")
		if not shot_fight and not lv.catching and str(b._dl_state) == "fight":
			shot_fight = true
			await _frames(90)
			await _shot("W_03_live_fight")
		if not shot_wait and str(lv.status) == LS.TXT_WAIT and str(b._dl_state) == "place":
			shot_wait = true
			var tq := Time.get_ticks_msec()
			while Time.get_ticks_msec() - tq < 1200:      # 幕布淡出按真实时间 0.22 秒; 等它走完再拍
				await get_tree().process_frame
			await _shot("W_04_live_wait")
	_note("watch: 跟播结束 finished=%s div=%d broken=%s cp=%d" % [str(b._replay.finished), int(b._replay.diverged_at), str(lv.broken), int(b._replay.cp_checked)])
	var tw := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 2600:
		await get_tree().process_frame
	await _shot("W_05_live_end")
	b._hud._replay_exit()
	await _frames(10)
	## ④ 周日对阵图: 开播窗口内 / 外, 弹卡两种
	var fd := _bracket_feed(now)
	var wv: Dictionary = fd[0]
	for bk in (wv["buckets"] as Array):
		if int(bk.get("bucket", -1)) == 0:
			bk["round_at"] = now - 40
			bk["revealed_at"] = now - 40
	var m: Node = await _w_open("res://scenes/BracketMap.tscn")
	m.set_data({}, {}, now)
	m.set_week(wv)
	m.set_portraits(fd[1])
	await _frames(60)
	await _shot("W_06_bracket_premiere")
	var nb: Button = null
	for c in m._canvas.find_children("NodeBtn", "Button", true, false):
		if (c as Button).get_meta("rm", Vector2i(-1, -1)) == Vector2i(1, 0):
			nb = c
	if nb != null:
		nb.pressed.emit()
		await _frames(10)
		await _shot("W_07_popup_premiere")
		var go: Button = m.find_child("PopupGoBtn", true, false) as Button
		if go != null:
			go.pressed.emit()
			var pb = await _wait_scene("RealtimeBattle3DScene.gd")
			if pb != null and pb._replay.is_live():
				var tp := Time.get_ticks_msec()
				while Time.get_ticks_msec() - tp < 9000 and pb._replay.live.catching:
					await get_tree().process_frame
				await _frames(120)
				await _shot("W_10_premiere_watch")
				pb._hud._replay_exit()
				await _frames(10)
			else:
				_note("watch: 开播没进观赛")
	var m2: Node = await _w_open("res://scenes/BracketMap.tscn")
	m2.set_data({}, {}, now + LS.PREMIERE_SEC + 5)
	m2.set_week(wv)
	m2.set_portraits(fd[1])
	await _frames(60)
	await _shot("W_08_bracket_after")
	for c in m2._canvas.find_children("NodeBtn", "Button", true, false):
		if (c as Button).get_meta("rm", Vector2i(-1, -1)) == Vector2i(1, 0):
			(c as Button).pressed.emit()
	await _frames(10)
	await _shot("W_09_popup_after")
	SB._transport_for_test = Callable()


# ─────────────────────────────── 冠军杯赛(2026-10-07) ───────────────────────────────
const _BR := preload("res://scripts/gamedata/bracket.gd")
const _LL := preload("res://scripts/gamedata/bracket_layout.gd")
const CUP_NAMES := ["石头统领", "糖果龟主", "海风小将", "冰川行者", "老船长", "夜光贝"]
const CUP_AV := ["stone", "candy", "bamboo", "ice", "pirate", ""]


func _cup_ents(n: int, me_seed: int) -> Array:
	var out: Array = []
	for i in range(n):
		out.append({"seed": i, "name": CUP_NAMES[i], "account_id": ME if i == me_seed else "cup-%d" % i})
	return out


## 一份冠军杯赛(服务端回包形状) → 对阵图要的形状(走产品自己的翻译 `_bucket_from`)。
func _cup_dict(now: int, n: int, rnd: int, closed: bool, done: Dictionary, round_at: int, revealed_at: int) -> Dictionary:
	var wk := P2C.week_anchor_utc(now)
	var w: Dictionary = SB.parse_finals_week(true, 200, JSON.stringify({"ok": true, "week": wk, "now": now,
		"buckets": [], "cup": {"bucket": P2C.FINALS_CUP_BUCKET, "n": n, "round": rnd, "closed": closed,
			"round_at": round_at, "revealed_at": revealed_at, "next_at": round_at + 480,
			"done": done, "entrants": _cup_ents(n, 0)}}), ME, now)
	return w.get("cup", {})


## 本周三个组(两个打完 · 一个还在打): 冠军杯赛开赛前那一页列的就是它们的组冠军。
func _cup_week(now: int) -> Dictionary:
	var wk := P2C.week_anchor_utc(now)
	var bs: Array = []
	for g in range(3):
		var ents: Array = []
		for i in range(4):
			ents.append({"seed": i, "name": CUP_NAMES[(g + i) % 6] if i == 0 else "组%d-%d号" % [g + 1, i + 1],
				"account_id": ME if (g == 0 and i == 0) else "g%d-%d" % [g, i]})
		var done := {"1-0": 0, "1-1": 0, "2-0": 0} if g < 2 else {"1-0": 0, "1-1": 1}
		bs.append({"bucket": g, "n": 4, "round": 2, "closed": g < 2, "done": done, "entrants": ents})
	return SB.parse_finals_week(true, 200, JSON.stringify({"ok": true, "week": wk, "now": now, "buckets": bs}), ME, now)


func _cup_portraits() -> Dictionary:
	var por := {}
	for i in range(6):
		if str(CUP_AV[i]) != "":
			por[P2C.player_tag("cup-%d" % i)] = CUP_AV[i]
	return por


func _flow_cup() -> void:
	var wk := P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	var noon := wk + 6 * 86400 + 12 * 3600
	var t1 := wk + 6 * 86400 + 20 * 3600 + 5 * 60
	var my_group := {}
	var wv0 := _cup_week(noon)
	for b in (wv0.get("buckets", []) as Array):
		if int(b.get("me", -1)) >= 0:
			my_group = b
	## ① 中午: 小组赛页(新名字) + 冠军杯赛开赛前(倒计时 + 组冠军名单)
	var m: Node = await _open("res://scenes/BracketMap.tscn")
	m.set_data(my_group, {}, noon)
	m.set_week(wv0)
	await _frames(40)
	await _shot("K_00_group")
	m.pick_view(_LL.VIEW_FINALS)
	await _frames(20)
	await _shot("K_01_cup_soon")
	m.queue_free()
	await _frames(2)
	## ② 20:05 成表(6 人 ⇒ 8 签, 0/1 号轮空): 第 1 轮进行中, 我(0 号)轮空 ⇒ 第 2 轮等对手
	##    换成我坐 2 号(第 1 轮要打)更能看出「对战」: 用 me_seed=0 的回包、再把 me 改成 2
	var c1 := _cup_dict(t1, 6, 1, false, {}, t1 - 30, 0)
	c1["me"] = 2
	m = await _open("res://scenes/BracketMap.tscn")
	m.set_data(my_group, c1, t1)
	m.set_portraits(_cup_portraits())
	await _frames(40)
	await _shot("K_02_cup_round1")
	var nb: Button = null
	for b in m._canvas.find_children("NodeBtn", "Button", true, false):
		if (b as Button).get_meta("rm", Vector2i(-1, -1)) == Vector2i(1, 2) or nb == null:
			nb = b
	if nb != null:
		nb.pressed.emit()
		await _frames(10)
		await _shot("K_02b_cup_popup_play")
	m.queue_free()
	await _frames(2)
	## ③ 第 1 轮翻面(开播窗口里): 第 2 轮进行中
	var t2 := t1 + 500
	## 6 人 8 签: 第 1 轮 0 场 / 2 场是轮空(服务端补 side 0), 1 场 / 3 场真打。
	var c2 := _cup_dict(t2, 6, 2, false, {"1-0": 0, "1-1": 1, "1-2": 0, "1-3": 0}, t2 - 20, t2 - 20)
	m = await _open("res://scenes/BracketMap.tscn")
	m.set_data(my_group, c2, t2)
	m.set_portraits(_cup_portraits())
	await _frames(40)
	await _shot("K_03_cup_premiere")
	m.queue_free()
	await _frames(2)
	## ④ 收盘 + 决赛窗口已过: 冠军那一行 + 决赛弹卡
	var t3 := t1 + 3000
	var c3 := _cup_dict(t3, 6, 3, true, {"1-0": 0, "1-1": 1, "1-2": 0, "1-3": 0, "2-0": 1, "2-1": 0, "3-0": 1},
		t3 - 900, t3 - 600)
	m = await _open("res://scenes/BracketMap.tscn")
	m.set_data(my_group, c3, t3)
	m.set_portraits(_cup_portraits())
	await _frames(40)
	await _shot("K_04_cup_champion")
	for b in m._canvas.find_children("NodeBtn", "Button", true, false):
		if (b as Button).get_meta("rm", Vector2i(-1, -1)) == Vector2i(3, 0):
			(b as Button).pressed.emit()
	await _frames(10)
	await _shot("K_04b_cup_final_popup")
	m.queue_free()
	await _frames(2)
	## ⑤ 1 人表(本周只有一个组): 直接夺冠
	var c5 := _cup_dict(t1, 1, 1, true, {}, t1, t1)
	m = await _open("res://scenes/BracketMap.tscn")
	m.set_data(my_group, c5, t1)
	await _frames(30)
	await _shot("K_05_cup_solo")
	m.queue_free()
	await _frames(2)
	## ⑥ 主菜单赛程页的周日那张卡(两段各自开赛时刻 + 头衔那一句)
	var mm: Node = await _open("res://scenes/MainMenu.tscn")
	await _frames(60)
	mm.strip_now_override = noon
	mm.strip_finals_live_override = 1
	mm.rebuild_week_page()
	await _frames(30)
	mm._open_week_popup()
	await _frames(60)
	await _shot("K_06_menu_week")
	mm.queue_free()
	await _frames(2)


# ─────────── 冠军杯赛 v2: 新分组规则(用户 2026-10-07)下 N=3 / 10 / 40 三种规模 ───────────
const V2_NAMES := ["石头统领", "糖果龟主", "海风小将", "冰川行者", "老船长", "夜光贝", "雷霆小队", "猎手阿岩",
	"竹林隐士", "浪里白条"]


## 按产品自己的分组规格(bracket.gd)把 N 个人切组; 我 = 0 号种子。每组按 `done_of` 给结果、按 `closed` 收盘。
func _v2_week(now: int, n: int, rnd: int, done_of: Callable, closed_all: bool) -> Dictionary:
	var nb := _BR.bucket_count(n)
	var groups: Array = []
	for i in range(nb):
		groups.append([])
	for sd in range(n):
		(groups[_BR.bucket_of_seed(sd, nb)] as Array).append(sd)
	var bs: Array = []
	for g in range(nb):
		var ents: Array = []
		var mem: Array = groups[g]
		for k in range(mem.size()):
			var gsd: int = int(mem[k])
			ents.append({"seed": k, "name": "%s%d" % [V2_NAMES[gsd % 10], gsd / 10] if gsd >= 10 else V2_NAMES[gsd],
				"account_id": ME if gsd == 0 else "v2-%d" % gsd})
		var sz := mem.size()
		var closed: bool = sz == 1 or closed_all
		bs.append({"bucket": g, "n": sz, "round": rnd if sz > 1 else 1, "closed": closed, "round_at": now - 120,
			"revealed_at": now - 600, "next_at": now + 360, "done": done_of.call(sz) if sz > 1 else {}, "entrants": ents})
	return SB.parse_finals_week(true, 200, JSON.stringify({"ok": true, "week": P2C.week_anchor_utc(now), "now": now,
		"buckets": bs}), ME, now)


func _v2_mine(w: Dictionary) -> Dictionary:
	for b in (w.get("buckets", []) as Array):
		if int(b.get("me", -1)) >= 0:
			return b
	return {}


func _v2_shot(tag: String, w: Dictionary, now: int, cup: Dictionary, cup_tab: bool) -> void:
	var m: Node = await _open("res://scenes/BracketMap.tscn")
	m.set_data(_v2_mine(w), cup, now)
	m.set_week(w)
	await _frames(40)
	if cup_tab:
		m.pick_view(_LL.VIEW_FINALS)
	else:
		m.pick_view(_LL.VIEW_BUCKET)
	await _frames(20)
	await _shot(tag)
	m.queue_free()
	await _frames(2)


func _flow_cup_v2() -> void:
	var wk := P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	var noon := wk + 6 * 86400 + 12 * 3600
	var eve := wk + 6 * 86400 + 20 * 3600 + 5 * 60
	var none := func(_sz: int) -> Dictionary: return {}
	var all0 := func(sz: int) -> Dictionary:
		var d := {}
		var r := 1
		var c := _BR.slots_for(sz) / 2
		while c >= 1:
			for mm in range(c):
				d["%d-%d" % [r, mm]] = 0
			c /= 2
			r += 1
		return d
	## N=3: 三个 1 人组(上午没有对局)
	var w3 := _v2_week(noon, 3, 1, none, false)
	await _v2_shot("V3_group_solo", w3, noon, {}, false)
	await _v2_shot("V3_cup_soon", w3, noon, {}, true)
	## N=10: 五个 2 人组, 一场定组冠军(决赛进行中)
	var w10 := _v2_week(noon, 10, 1, none, false)
	await _v2_shot("V10_group_final", w10, noon, {}, false)
	## N=10 晚上: 五个组冠军进冠军杯赛(5 人 8 签, 前 3 号种子轮空)
	var w10e := _v2_week(eve, 10, 1, all0, true)
	var c10: Dictionary = SB.parse_finals_week(true, 200, JSON.stringify({"ok": true, "week": wk, "now": eve, "buckets": [],
		"cup": {"bucket": P2C.FINALS_CUP_BUCKET, "n": 5, "round": 1, "closed": false, "round_at": eve - 30,
			"revealed_at": 0, "next_at": eve + 450, "done": {},
			"entrants": [{"seed": 0, "name": "石头统领", "account_id": ME}, {"seed": 1, "name": "糖果龟主", "account_id": "v2-1"},
				{"seed": 2, "name": "海风小将", "account_id": "v2-2"}, {"seed": 3, "name": "冰川行者", "account_id": "v2-3"},
				{"seed": 4, "name": "老船长", "account_id": "v2-4"}]}}), ME, eve).get("cup", {})
	await _v2_shot("V10_cup_round1", w10e, eve, c10, true)
	## N=40: 五个 8 人组, 第 2 轮进行中
	var w40 := _v2_week(noon, 40, 2, func(sz: int) -> Dictionary:
		var d := {}
		for mm in range(_BR.slots_for(sz) / 2):
			d["1-%d" % mm] = mm % 2
		return d, false)
	await _v2_shot("V40_group_r2", w40, noon, {}, false)
	await _v2_shot("V40_cup_soon", w40, noon, {}, true)
