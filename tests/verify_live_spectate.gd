extends Node
## verify_live_spectate.gd — 实时观赛·周六直播门禁(方案书 docs/plans/20261007-实时观赛.md)
##
## 用户 2026-10-07:「观赛和回放是两码事明白吗」「周六即有回放也有正在打的啊」。
##
## ★全程走真入口: 真战斗场打一局周六闯关赛(后端开着, 假传输层当服务器) → 打的人边打边 upsert `live_matches`
##   → 真实例化赛况板, 服务器回「正在打」那一行 → 点卡上的「观赛」(`pressed.emit()`) → 真换场景进战斗场跟播。
##   服务器那一侧按「打的人的进度」放行: 观众每过一步真实时间, 服务器就多交出打的人那一刻上传的那一份。
##
## 段落:
##   ① 打的人(上传): 开打前一行都不发; 第一路开打就建行(事件 1 条、horizon = 开打步号);
##      之后每个事件追加一次、每 180 步心跳一次; 每一份里观众需要的校验点都在; 打完 ended + end;
##      match_id = 打完之后正式录像的 id; 行里只有 profile / leaders, 对手摘掉 is_bot / ghost_id; 走 upsert
##   ② 赛况板: 「正在打」卡(直播横幅 / 双方名字 / VS / 「观赛」, **不写胜负**); 战绩榜那个人是红色「直播」签;
##      断了的(updated_at 太旧)/ 已结束的 / 已经打完上了「最近对局」的都不出
##   ③ 观众(跟播): 观赛模式 + 顶栏「直播」; **没有**暂停 / 倍速 / 进度条 / 全场时长 / 再看一遍, 有「退出」;
##      追帧时一帧 8 步、屏上「同步中」; 任何时刻都不越过 horizon; 换路摆位时「下路准备中」, 事件来了接着打;
##      收尾之前屏上没有「获胜」; ★校验点逐个与打的人比过(个数 = 打的人全部非摆位校验点)、终局一致
##   ④ 收尾卡: 「X 获胜」, 没有「再看一遍」, 有「返回赛况」
##   ⑤ 中断: 行停在某一步不再更新 ⇒ 「直播中断」收尾卡; 行没了 ⇒ 同; 打开时就已经断了 ⇒ 不进场, 说「直播中断」
##   ⑥ 版本不同 ⇒ 不进场, 说「版本不同，无法观赛」
##   ⑦ 打完 ⇒ 赛况板上这一场从「正在打」变成普通卡(写胜负 + 「观看」); 打开已结束的直播行 = 普通回放(有控件)
##   ⑧ 服务端没部署(404) ⇒ 没有「正在打」那一块、不报错; 没接服务器 ⇒ 打的人一行都不发
##   ⑨ SQL 文件: 迁移在、schema.sql 里同一段逐字相同; 表 / RLS / 策略 / 周清 / 上限 = 客户端常量 / revealed_at
## 每条新断言都做过反向验证(改坏 → 红 → 逐字节还原), 见方案书「实施回填」。

const SB := preload("res://scripts/net/supabase.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const LU := preload("res://scripts/systems/replay/live_upload.gd")
const LS := preload("res://scripts/systems/replay/live_spectate.gd")
const Board := preload("res://scripts/systems/replay/gauntlet_board.gd")
const Backend := preload("res://scripts/net/backend.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const RC := preload("res://scripts/scenes/battle/replay_controls.gd")
const GBS := preload("res://scripts/scenes/GauntletBoardScene.gd")
const BOARD_SCENE := "res://scenes/GauntletBoard.tscn"
const MIGRATION := "res://server/supabase/migrations/20261007_live_matches.sql"
const SCHEMA := "res://server/supabase/schema.sql"
const MARK_BEGIN := "-- >>> BEGIN live_matches 20261007 >>>"
const MARK_END := "-- <<< END live_matches 20261007 <<<"
const ME := "11111111-2222-4333-8444-555555555555"
const DT := 1.0 / 60.0
## 第二路摆位多停一会儿(步): 观众要在「下路准备中」里停够看得见的一段。
const PLACE2_STEPS := 1200

var _fail := 0
var _n := 0
var _gs
var _now := 0
## 假服务器
var _snaps: Array = []          # 打的人每次 upsert 的那一行(解析后) + 打的人那一刻的状态
var _pre_fight_posts := 0
var _prefer_ok := 0
var _serve: Dictionary = {}     # 观众 GET 拿到的那一行(null = 没这一行)
var _serve_missing := false
var _board_live: Array = []     # 赛况板「本周还在打的」
var _board_games: Array = []    # 赛况板「最近对局」(matches)
var _live_404 := false
var _rec_b = null
var _rec_fights := 0
var _final_rec: Dictionary = {}
var _id := ""


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _iso(t: int) -> String:
	return Time.get_datetime_string_from_unix_time(t) + "+00:00"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	OS.set_environment("TURTLE_SEED", "")
	_t_sql()
	## 一个周六中午(服务器钟): 赛况板的「多久前开打」/「还在打吗」都按它算。
	var real := int(Time.get_unix_time_from_system())
	_now = P2C.week_anchor_utc(real) + 5 * 86400 + 12 * 3600
	P2C.now_override_ts = _now
	_setup_gs()
	_ok("⑧ 没接服务器 ⇒ 这一局不直播(LiveUpload.wanted 为假)", not SB.enabled() and not LU.wanted())
	_backend(true)
	_ok("分母: 后端开着(假传输) / 周六闯关赛 / 要录", SB.enabled() and ReplayRecorder.should_record()
		and ReplayRecorder.current_settle_kind() == ReplayRecorder.Phase2Cfg.SETTLE_GAUNTLET)
	await _record()
	if _snaps.is_empty() or _final_rec.is_empty():
		_ok("★录制与上传都走完了", false)
		_cleanup()
		_finish()
		return
	_t_uploads()
	await _t_board_and_watch()
	await _t_stale()
	await _t_version_and_finished()
	await _t_unavailable()
	_cleanup()
	_finish()


func _setup_gs() -> void:
	_gs.reset_dual_lane()
	_gs.test_mode = true
	_gs.tutorial_active = false
	_gs.onboarded = true
	_gs.week_phase = "gauntlet"
	_gs.week_anchor_ts = P2C.week_anchor_utc(_now)
	_gs.season_id = 1
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
	rng.seed = 20261007
	_gs.dual_ghost = Backend.make_bot(3, rng)
	_gs.dual_active = true
	_gs.account_id = ME


func _backend(on: bool) -> void:
	if on:
		OS.set_environment(SB.ENV_URL, "http://live.local")
		ProjectSettings.set_setting(SB.SETTING_KEY, "live-anon-key")
		SB._transport_for_test = _transport
		SB._reset_auth_for_test()
		SB._token = "tok"
	else:
		OS.set_environment(SB.ENV_URL, " ")
		ProjectSettings.set_setting(SB.SETTING_KEY, "")
		SB._transport_for_test = Callable()
		SB._token = ""


func _cleanup() -> void:
	_backend(false)
	P2C.now_override_ts = 0
	LS.pending = {}
	LS.stale_sec_for_test = 0.0
	LU._reset_for_test()


# ─────────────────────────────── 假服务器 ───────────────────────────────

func _transport(m, u, h, b, cb) -> void:
	var url := str(u)
	var method := str(m).to_upper()
	if url.find("/auth/v1/") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({
			"access_token": "tok", "refresh_token": "r2", "expires_in": 3600,
			"user": {"id": ME, "is_anonymous": true}})})
		return
	if url.find("/rest/v1/live_matches") >= 0:
		if _live_404:
			cb.call({"ok": true, "code": 404, "body": "{\"message\":\"relation does not exist\"}"})
			return
		if method == "POST":
			var j := JSON.new()
			var row: Dictionary = j.data if j.parse(str(b)) == OK and j.data is Dictionary else {}
			if _rec_fights == 0:
				_pre_fight_posts += 1
			for hh in h:
				if str(hh).begins_with("Prefer:") and str(hh).contains("resolution=merge-duplicates"):
					_prefer_ok += 1
			_snaps.append({"row": row, "st": str(_rec_b._dl_state) if _rec_b != null and is_instance_valid(_rec_b) else "",
				"fights": _rec_fights})
			cb.call({"ok": true, "code": 201, "body": ""})
			return
		if url.find("match_id=eq.") >= 0:
			if _serve_missing or _serve.is_empty():
				cb.call({"ok": true, "code": 200, "body": "[]"})
				return
			cb.call({"ok": true, "code": 200, "body": JSON.stringify([_serve])})
			return
		cb.call({"ok": true, "code": 200, "body": JSON.stringify(_board_live)})
		return
	if url.find("/rest/v1/matches") >= 0 and method == "GET" and url.find("phase=eq.gauntlet") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify(_board_games)})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


## 打的人那一份 → 服务器上那一行(观众 GET 的形状; updated_at 由服务器定)。
func _served(snap: Dictionary, updated: int) -> Dictionary:
	var r: Dictionary = snap["row"]
	return {"match_id": str(r.get("match_id", "")), "replay": str(r.get("replay", "")),
		"horizon": int(r.get("horizon", 0)), "ended": bool(r.get("ended", false)),
		"client_version": str(r.get("client_version", "")), "updated_at": _iso(updated)}


## 赛况板那一行(只取摘要)。
func _board_row(snap: Dictionary, started: int, updated: int) -> Dictionary:
	var r: Dictionary = snap["row"]
	return {"match_id": str(r.get("match_id", "")), "started_at": _iso(started), "updated_at": _iso(updated),
		"client_version": str(r.get("client_version", "")), "ended": bool(r.get("ended", false)),
		## ★深拷贝: 几行共用同一份 profile 的话, 改「别人那一行」的名字会把打的人那一行一起改掉(实测踩过)。
		"lp": ((r.get("left_snapshot", {}) as Dictionary).get("profile", {}) as Dictionary).duplicate(true),
		"rp": ((r.get("right_snapshot", {}) as Dictionary).get("profile", {}) as Dictionary).duplicate(true),
		"la": ((r.get("left_snapshot", {}) as Dictionary).get("leaders", []) as Array).duplicate(),
		"ra": ((r.get("right_snapshot", {}) as Dictionary).get("leaders", []) as Array).duplicate()}


func _rec_of(snap: Dictionary) -> Dictionary:
	return LS.decode_row(str((snap["row"] as Dictionary).get("replay", "")), str((snap["row"] as Dictionary).get("match_id", "")))


# ① ─────────────────────────────────────────────────────────────
func _record() -> void:
	print("── ① 打的人: 真战斗场打一局周六闯关赛(后端开着) ──")
	LU._reset_for_test()
	var s = RB.new()
	_rec_b = s
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	_ok("① 分母: 这一局在录、而且在直播", str(s._replay.mode) == "rec" and s._replay.live_up != null)
	_ok("① ★开打前就定下 match_id(uuid)", SB.is_uuid(str(s._replay.rec.get("id", ""))))
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
				and ((_rec_fights == 0 and stf == 20) or (_rec_fights == 1 and stf == PLACE2_STEPS / 3) or (_rec_fights >= 2 and stf == 20)):
			_rec_fights += 1
			s._dl_go_btn.pressed.emit()
		s._process(0.05)
		if i % 4 == 0:
			await get_tree().process_frame
		i += 1
	await _frames(6)
	_id = str(s._replay.rec.get("id", ""))
	_final_rec = ReplayRecorder.load_record(_id)
	_ok("① 分母: 打完了、两路以上开打过、本机录像在(id 不变)", s._replay.finished and _rec_fights >= 2 and not _final_rec.is_empty(),
		"fights=%d steps=%d" % [_rec_fights, int((_final_rec.get("end", {}) as Dictionary).get("s", -1))])
	_rec_b = null
	s.queue_free()
	await _frames(4)


func _t_uploads() -> void:
	print("── ① 打的人上传的每一份 ──")
	_ok("① ★开打之前一行都没发", _pre_fight_posts == 0, "开打前 %d 次" % _pre_fight_posts)
	_ok("① 分母: 发了 %d 次(> 10)、每次都是 upsert(Prefer: resolution=merge-duplicates)" % _snaps.size(),
		_snaps.size() > 10 and _prefer_ok == _snaps.size(), "prefer %d" % _prefer_ok)
	var first: Dictionary = _snaps[0]
	var r0 := _rec_of(first)
	var ev0: Array = r0.get("events", [])
	var nf0 := 0
	for e0 in ev0:
		if str(e0.get("k", "")) == "fight":
			nf0 += 1
	_ok("① ★第一份 = 第一路开打那一下: 最后一条是 fight(只有这一条 fight)、horizon = 开打步号",
		not ev0.is_empty() and nf0 == 1 and str(ev0.back().get("k", "")) == "fight"
		and int(first["row"]["horizon"]) == int(ev0.back().get("s", -1)),
		"%d 条 h=%d" % [ev0.size(), int(first["row"]["horizon"])])
	var row0: Dictionary = first["row"]
	var ls: Dictionary = row0.get("left_snapshot", {})
	var rs: Dictionary = row0.get("right_snapshot", {})
	_ok("① 行: match_id / 账号 / 周 / phase / 版本", str(row0.get("match_id", "")) == _id and str(row0.get("account_id", "")) == ME
		and int(row0.get("season_week", 0)) == int(_gs.week_anchor_ts) and str(row0.get("phase", "")) == "gauntlet"
		and str(row0.get("client_version", "")) == ReplayRecorder.client_version())
	_ok("① ★两侧只有 profile + leaders(不上阵容装备); 对手摘掉 is_bot / ghost_id",
		ls.keys().size() == 2 and ls.has("profile") and ls.has("leaders") and rs.keys().size() == 2
		and not rs.has("is_bot") and not rs.has("ghost_id") and (ls["leaders"] as Array).size() == 3, str(ls.keys()) + str(rs.keys()))
	## 逐份: horizon 不减; 事件只增(前缀不变); 每一份里事件都 ≤ horizon; 观众可能要的校验点都在
	var mono := true
	var prefix := true
	var ev_le_h := true
	var cps_ok := true
	var beats := 0
	var ev_steps: Array = []
	var prev_h := -1
	var prev_ev: Array = []
	for sn in _snaps:
		var r := _rec_of(sn)
		var h := int(sn["row"]["horizon"])
		var evs: Array = r.get("events", [])
		if h < prev_h:
			mono = false
		for k in range(prev_ev.size()):
			if k >= evs.size() or int(evs[k]["s"]) != int(prev_ev[k]["s"]) or str(evs[k]["k"]) != str(prev_ev[k]["k"]):
				prefix = false
		for e in evs:
			if int(e.get("s", 0)) > h:
				ev_le_h = false
		if (r.get("cps", []) as Array).size() < maxi(0, (h - 1) / ReplayRecorder.CP_EVERY):
			cps_ok = false
		if evs.size() == prev_ev.size() and not bool(sn["row"].get("ended", false)):
			beats += 1
			if h % LU.HEARTBEAT_STEPS != 0:
				cps_ok = false
		if evs.size() > prev_ev.size():
			ev_steps.append(evs.size())
		prev_h = h
		prev_ev = evs
	_ok("① ★horizon 逐份不减", mono)
	_ok("① ★已发过的事件逐份原样保留(只往后追加)", prefix)
	_ok("① ★每一份里的事件步号都 ≤ horizon(观众跑到 horizon 不会漏事件)", ev_le_h)
	_ok("① ★每一份都带齐观众跑到 horizon 要比的校验点; 心跳都落在 %d 步的整数倍上" % LU.HEARTBEAT_STEPS, cps_ok)
	_ok("① 分母: 心跳 %d 次(> 5)" % beats, beats > 5)
	var fe: Array = _final_rec.get("events", [])
	var each := true
	for k in range(ev0.size(), fe.size() + 1):
		if not ev_steps.has(k):
			each = false
	_ok("① ★开打之后每出现一个事件都追加发了一次(事件数 %d..%d 各有一份)" % [ev0.size(), fe.size()],
		each and fe.size() >= ev0.size() + 2, str(ev_steps))
	var lastsn: Dictionary = _snaps[_snaps.size() - 1]
	var rl := _rec_of(lastsn)
	_ok("① ★最后一份: ended、带 end、horizon = 结算步号、录像与本机正式录像同一场",
		bool(lastsn["row"].get("ended", false)) and rl.get("end", null) is Dictionary
		and int(lastsn["row"]["horizon"]) == int((rl["end"] as Dictionary).get("s", -1))
		and (rl["end"] as Dictionary) == (_final_rec.get("end", {}) as Dictionary) and str(rl.get("id", "")) == _id)
	var ended_n := 0
	for sn in _snaps:
		if bool(sn["row"].get("ended", false)):
			ended_n += 1
	_ok("① ended 只在最后一份", ended_n == 1)
	_ok("① 本机正式录像沿用开打时定下的 id(直播行与 matches 行同一个 match_id)",
		str(_final_rec.get("id", "")) == _id and (_gs.replay_upload_pending as Array).any(func(e): return str(e.get("id", "")) == _id))
	var place_wait := 0
	for sn in _snaps:
		if int(sn["fights"]) == 1 and str(sn["st"]) == "place":
			place_wait += 1
	_ok("① 分母: 打的人第二路摆位期间也在心跳(%d 份)" % place_wait, place_wait >= 3)


# ② ③ ④ ─────────────────────────────────────────────────────────
func _is_battle(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() == RB


func _is_board(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() == GBS


func _wait_scene(pred: Callable, max_frames: int = 240) -> Node:
	for _i in range(max_frames):
		var cs := get_tree().current_scene
		if pred.call(cs):
			return cs
		await get_tree().process_frame
	return null


func _open_board() -> Node:
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	var n: Node = (load(BOARD_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(n)
	get_tree().current_scene = n
	await _frames(4)
	return n


## 观众从哪一份开始看: 第一路开打之后、horizon 已经过了开打 + 600 步的第一份。
func _join_index() -> int:
	var f0 := int(_snaps[0]["row"]["horizon"])
	for k in range(_snaps.size()):
		if int(_snaps[k]["fights"]) == 1 and int(_snaps[k]["row"]["horizon"]) > f0 + 600:
			return k
	return 1


func _labels_text(root: Node) -> Array:
	var out: Array = []
	for c in root.find_children("*", "Label", true, false):
		if (c as Label).is_visible_in_tree():
			out.append((c as Label).text)
	return out


func _t_board_and_watch() -> void:
	print("── ② 赛况板「正在打」 / ③ 观众跟播 / ④ 收尾卡 ──")
	var j := _join_index()
	var js: Dictionary = _snaps[j]
	var t_join := _now
	_serve = _served(js, t_join)
	var other := _board_row(js, t_join - 60, t_join - 2)
	other["match_id"] = "aaaaaaaa-1111-4222-8333-000000000001"
	## 另一场直播的打的人 = 「最近对局」里已经上榜的老将丁(榜上那一行要换成红签; 我那一场的人还没上榜, 走补 0-0 那条)
	(other["lp"] as Dictionary)["name"] = "老将丁"
	(other["lp"] as Dictionary)["tag"] = P2C.player_tag("other-d")
	var stale := _board_row(js, t_join - 900, t_join - 300)
	stale["match_id"] = "aaaaaaaa-1111-4222-8333-000000000002"
	(stale["lp"] as Dictionary)["name"] = "断线乙"
	(stale["lp"] as Dictionary)["tag"] = P2C.player_tag("other-b")
	var ended := _board_row(js, t_join - 900, t_join - 3)
	ended["match_id"] = "aaaaaaaa-1111-4222-8333-000000000003"
	ended["ended"] = true
	(ended["lp"] as Dictionary)["name"] = "结束丙"
	(ended["lp"] as Dictionary)["tag"] = P2C.player_tag("other-c")
	_board_live = [_board_row(js, t_join - 120, t_join), other, stale, ended]
	var my_lp: Dictionary = (js["row"]["left_snapshot"] as Dictionary).get("profile", {})
	var my_tag: String = Board.tag_of(my_lp)
	_board_games = [{"match_id": "bbbbbbbb-1111-4222-8333-000000000009", "created_at": _iso(t_join - 1800),
		"result": {"won": true, "gw": 1, "gl": 0}, "lp": {"name": "老将丁", "tag": P2C.player_tag("other-d"), "avatar": "pirate"},
		"rp": {"name": "老将戊", "tag": P2C.player_tag("other-e"), "avatar": "ice"}, "la": ["pirate"], "ra": ["ice"], "rw": 0, "rl": 1}]
	var bs: Node = await _open_board()
	await _frames(6)
	var lives: Array = bs.live_games
	var lcards: Array = bs.find_children(GBS.N_LIVE_CARD + "*", "", true, false)
	_ok("② ★「正在打」卡 = 还在打的那两场(断了的 / 已结束的不出)", lives.size() == 2 and lcards.size() == 2,
		"卡 %d / 数据 %d" % [lcards.size(), lives.size()])
	var bad_txt := 0
	var has_live_banner := 0
	var my_card: Node = null
	for c in lcards:
		for t in _labels_text(c):
			if str(t).contains("获胜") or str(t).contains("胜利"):
				bad_txt += 1
			if str(t) == LS.TAG_LIVE:
				has_live_banner += 1
		if str((c as Node).get_meta("match_id", "")) == _id:
			my_card = c
	_ok("② ★「正在打」卡上不写胜负", bad_txt == 0)
	_ok("② 每张卡都有「直播」横幅", has_live_banner == 2)
	var lb: Button = my_card.find_child(GBS.N_LIVE_BTN, true, false) as Button if my_card != null else null
	_ok("② ★那一场的卡上有「观赛」(不是「观看」)", lb != null and lb.text == "观赛")
	var names_ok := false
	if my_card != null:
		for t0 in _labels_text(my_card):
			if str(t0).begins_with(str(my_lp.get("name", "~"))):
				names_ok = true
	_ok("② 卡上写着打的人的名字(这一场的打的人就是本机账号 ⇒ 名字后带「（我）」)", names_ok, str(my_lp.get("name", "")))
	var chip_ok := false
	var chip_ranked := false
	var chip_other := false
	for pr in bs._players_box.get_children():
		var lc: Node = (pr as Node).find_child(GBS.N_LIVE_CHIP, true, false)
		var tg0 := str((pr as Node).get_meta("tag", ""))
		if tg0 == my_tag:
			chip_ok = lc != null and _labels_text(lc).has(LS.TAG_LIVE)
		elif tg0 == P2C.player_tag("other-d"):
			chip_ranked = lc != null and _labels_text(lc).has(LS.TAG_LIVE)
		elif tg0 == P2C.player_tag("other-e") and lc != null:
			chip_other = true
	_ok("② ★战绩榜上正在打的人(这周第一场还没打完 ⇒ 补的 0-0 那一行)是红色「直播」签", chip_ok, my_tag)
	_ok("② ★已经上榜的人正在打 ⇒ 他那一行的状态签换成红色「直播」", chip_ranked)
	_ok("② 没在打的人不标「直播」", not chip_other)
	_ok("② 顶上一行写「正在打 2 场」", str(bs._status.text).contains("正在打 2 场"), str(bs._status.text))
	_ok("② 有「正在打」也有「最近对局」⇒ 中间一条小标题隔开", bs.find_child(GBS.N_SUB_HEAD, true, false) != null)
	if lb == null:
		return
	## ③ 点「观赛」(真入口)
	lb.pressed.emit()
	var b = await _wait_scene(_is_battle)
	_ok("③ 分母: 进了战斗场、在播、是观赛(不是回放)", b != null and b._replay.is_playing() and b._replay.is_live(),
		str(bs.last_replay_code) + " " + str(bs.last_replay_msg) if is_instance_valid(bs) else "")
	if b == null or not b._replay.is_live():
		return
	b.set_process(false)
	var lv = b._replay.live
	_ok("③ 会话: 直播 / 这一场 / horizon = 打的人那一刻", str(lv.kind) == LS.KIND_LIVE and str(lv.match_id) == _id
		and int(lv.horizon) == int(js["row"]["horizon"]))
	## 先跑一帧让 HUD 建起来
	b._process(DT)
	await _frames(2)
	var mark := b.find_child("ReplayMark", true, false) as Control
	var mark_lb: Array = mark.find_children("*", "Label", true, false) if mark != null else []
	_ok("③ ★顶栏小签写「直播」", mark != null and mark.is_visible_in_tree() and mark_lb.size() == 1 and (mark_lb[0] as Label).text == LS.TAG_LIVE,
		(mark_lb[0] as Label).text if not mark_lb.is_empty() else "<无>")
	var banned := [RC.N_PAUSE, RC.N_SPEED, RC.N_TIME, "ReplayStrip", RC.N_TICK_LBL + "0", RC.N_PAUSED, RC.N_AGAIN]
	var found: Array = []
	for nm in banned:
		if b.find_child(nm, true, false) != null:
			found.append(nm)
	_ok("③ ★没有暂停 / 倍速 / 进度条 / 全场时长 / 已暂停 / 再看一遍", found.is_empty(), str(found))
	var ex := b.find_child(RC.N_LIVE_EXIT, true, false) as Button
	_ok("③ 有「退出」", ex != null and ex.is_visible_in_tree() and ex.text == "退出")
	## 跟播: 服务器按打的人的进度放行(观众每过一步真实时间, 打的人也多走一步)
	var t0: int = int(js["row"]["horizon"])
	var k := j
	var frames := 0
	var catch_fast := 0
	var first_sync := ""
	var ahead := 0
	var waited := 0
	var fought_after_wait := false
	var winner_early := 0
	var prev_n := int(b._sim_step_n)
	while frames < 12000 and not b._replay.finished and b._replay.diverged_at < 0 and not lv.broken:
		frames += 1
		var clock := t0 + frames
		while k + 1 < _snaps.size() and int(_snaps[k + 1]["row"]["horizon"]) <= clock:
			k += 1
		_serve = _served(_snaps[k], _now)
		if frames % 120 == 0:
			lv.poll()
		b._process(DT)
		var n := int(b._sim_step_n)
		if frames <= 3 and n - prev_n == LS.CATCH_PER_FRAME:
			catch_fast += 1
		if frames == 2:
			first_sync = str(lv.status)
		if not lv.ended and n > int(lv.horizon):
			ahead += 1
		if str(lv.status) == LS.TXT_WAIT and str(b._dl_state) == "place":
			waited += 1
		if waited > 0 and str(b._dl_state) == "fight":
			fought_after_wait = true
		if frames % 30 == 0 and b.find_child(RC.N_CARD, true, false) == null:
			for t in _labels_text(b):
				if str(t).contains("获胜"):
					winner_early += 1
		prev_n = n
		if frames % 6 == 0:
			await get_tree().process_frame
	_ok("③ ★追帧: 一开始一帧跑 %d 步、屏上「同步中」" % LS.CATCH_PER_FRAME, catch_fast >= 2 and first_sync == LS.TXT_SYNC,
		"快帧 %d / 「%s」" % [catch_fast, first_sync])
	_ok("③ ★任何时刻都没越过 horizon(没打完时)", ahead == 0 and int(lv.max_ahead) <= 0, "越过 %d 帧 / max_ahead %d" % [ahead, int(lv.max_ahead)])
	_ok("③ 分母: 轮询合并进来新数据 %d 次(> 5)" % int(lv.merges), int(lv.merges) > 5)
	_ok("③ ★换路摆位、打的人还没开打 ⇒ 「下路准备中」(%d 帧)" % waited, waited >= 30)
	_ok("③ ★事件追加进来以后接着打(第二路开打了)", fought_after_wait)
	_ok("③ ★收尾之前屏上没有「获胜」", winner_early == 0, "%d 次" % winner_early)
	var real_cp := 0
	for hcp in _final_rec.get("cps", []):
		if str(hcp) != ReplayRecorder.PLACE_CP:
			real_cp += 1
	_ok("③ ★逐步与打的人一致: 播完、不分叉、校验点逐个比过(%d / %d)" % [int(b._replay.cp_checked), real_cp],
		b._replay.finished and b._replay.diverged_at < 0 and int(b._replay.cp_checked) == real_cp and real_cp > 20,
		"div=%d %s" % [int(b._replay.diverged_at), str(b._replay.diverge_why)])
	## 终局步号 + 指纹 + 胜负由 `on_settle` 播放分支逐字比过(对不上记成分叉); 结算那一帧剩下的步照样跑完 ⇒ 只要求 ≥。
	_ok("③ 终局: 走到了打的人结算那一步(on_settle 比过步号 / 指纹 / 胜负)", int(b._sim_step_n) >= int((_final_rec["end"] as Dictionary).get("s", -2))
		and b._replay.diverged_at < 0)
	## ④ 收尾卡
	var tw := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 2500 and b.find_child(RC.N_CARD, true, false) == null:
		await get_tree().process_frame
	var card: Node = b.find_child(RC.N_CARD, true, false)
	var won := bool((_final_rec["end"] as Dictionary).get("won", false))
	var foe_nm := str(((_final_rec["state"]["dual_ghost"] as Dictionary).get("profile", {}) as Dictionary).get("name", "~"))
	var want := "%s 获胜" % (str(my_lp.get("name", "")) if won else foe_nm)
	var res := card.find_child("ReplayResult", true, false) as Label if card != null else null
	_ok("④ ★收尾卡揭晓谁赢:「%s」" % want, res != null and res.text == want, res.text if res != null else "<无卡>")
	_ok("④ ★收尾卡没有「再看一遍」、有「返回赛况」", card != null and card.find_child(RC.N_AGAIN, true, false) == null
		and card.find_child(RC.N_BACK, true, false) != null and (card.find_child(RC.N_BACK, true, false) as Button).text == "返回赛况")
	_ok("④ 收尾卡不报全场时长", card != null and not str(_labels_text(card)).contains("全场"))
	var st_node := b.find_child(RC.N_LIVE_STATUS, true, false) as Control
	_ok("④ 底部状态牌收起", st_node == null or not st_node.visible)
	if card != null:
		(card.find_child(RC.N_BACK, true, false) as Button).pressed.emit()
	else:
		b._hud._replay_exit()
	var back = await _wait_scene(_is_board)
	_ok("④ 返回落在赛况板", back != null)
	await _frames(4)


# ⑤ ─────────────────────────────────────────────────────────────
func _spectate_from(idx: int, updated: int) -> Node:
	_serve = _served(_snaps[idx], updated)
	_serve_missing = false
	LS.open_live(get_tree(), _id, func(_c: String, _m: String) -> void: pass, "", {"l": "甲", "r": "乙"})
	var b = await _wait_scene(_is_battle, 120)
	return b


func _t_stale() -> void:
	print("── ⑤ 中断 ──")
	## 打开时就已经断了(updated_at 比现在早 100 秒)⇒ 不进场
	var j := _join_index()
	_serve = _served(_snaps[j], _now - 100)
	var got := ["~", "~"]
	var before := get_tree().current_scene
	LS.open_live(get_tree(), _id, func(c: String, m: String) -> void:
		got[0] = c
		got[1] = m)
	await _frames(4)
	_ok("⑤ ★打开时就断了 ⇒ 不进场, 说「直播中断」", got[0] == "stale" and got[1] == LS.TXT_BROKEN and get_tree().current_scene == before
		and LS.pending.is_empty(), "%s / %s" % [got[0], got[1]])
	## 进场后行再也不动 ⇒ 等满中断时限出卡
	## ★两段走(2026-10-08 CI 红): 原来进场前就把时限缩到 6 秒, 而观众要先从第 0 步追到 horizon 再停够 60 帧 ——
	##   CI 上 16 路并行时这段追帧墙钟超过 6 秒, 还没走到 horizon 就被判中断(「停在第 -1 步 / 停了 0 帧」)。
	##   中断的口径是「horizon 多久没涨」(墙钟, 从会话建立起算), 与观众追帧快慢无关 —— 产品没错, 是尺子挂在机器快慢上。
	##   ⇒ 第一段时限放到很大, 追到 horizon 并停够之后再把时限缩成「至今 + 6 秒」, 等满 6 秒判中断。
	LS.stale_sec_for_test = 3600.0
	var b = await _spectate_from(j, _now)
	_ok("⑤ 分母: 进了观赛", b != null and b._replay.is_live())
	if b == null or not b._replay.is_live():
		LS.stale_sec_for_test = 0.0
		return
	b.set_process(false)
	var lv = b._replay.live
	var tw := Time.get_ticks_msec()
	var stalled_at := -1
	var over := 0
	var held := 0
	var broke_early := false
	var t_shr := 0
	var m_shr := 0
	var shrunk := false
	while Time.get_ticks_msec() - tw < 120000 and not lv.broken:
		for _q in range(6):
			b._process(DT)
			over = maxi(over, int(b._sim_step_n) - int(lv.horizon))
			if int(b._sim_step_n) == int(lv.horizon):
				held += 1
				if stalled_at < 0:
					stalled_at = int(b._sim_step_n)
		if lv.broken and not shrunk:
			broke_early = true
		## 停够了 ⇒ 把时限缩成「horizon 上次涨至今 + 6 秒」: 再过 6 秒墙钟该判中断,
		##   而这 6 秒里轮询照样把(没涨的)行合并进来 —— 合并进来却没涨, 不许算「还活着」。
		if not shrunk and held > 60:
			shrunk = true
			t_shr = Time.get_ticks_msec()
			m_shr = int(lv.merges)
			LS.stale_sec_for_test = float(t_shr - int(lv._last_adv_ms)) / 1000.0 + 6.0
		await get_tree().process_frame
	var t_brk := Time.get_ticks_msec()
	_ok("⑤ 分母: 时限放大的那一段里没被提前判中断(提前断 = 停不停得住根本没量到)", not broke_early and shrunk,
		"提前断 %s / 缩过时限 %s" % [str(broke_early), str(shrunk)])
	_ok("⑤ ★缩时限后等满 6 秒才断, 期间轮询合并了 %d 次没涨的行(合并 ≠ 还活着)" % (int(lv.merges) - m_shr),
		shrunk and lv.broken and t_brk - t_shr >= 5500 and int(lv.merges) - m_shr >= 1,
		"缩后 %d ms 断" % (t_brk - t_shr))
	_ok("⑤ 分母: 先追到 horizon 停住(停在第 %d 步)" % stalled_at, stalled_at == int(lv.horizon))
	## ★服务器再也不放新的一份 ⇒ 观众必须**停在** horizon 上(喂多少帧都不越过), 直到判中断。
	_ok("⑤ ★horizon 不再涨 ⇒ 停在 horizon 上一步不越过(停了 %d 帧)" % held, over == 0 and held > 60
		and int(b._sim_step_n) == int(lv.horizon), "越过 %d 步" % over)
	var card: Node = b.find_child(RC.N_CARD, true, false)
	var res := card.find_child("ReplayResult", true, false) as Label if card != null else null
	_ok("⑤ ★行不再更新 ⇒ 「直播中断」收尾卡, 只有「返回」", lv.broken and res != null and res.text == LS.TXT_BROKEN
		and card.find_child(RC.N_AGAIN, true, false) == null and card.find_child(RC.N_BACK, true, false) != null,
		res.text if res != null else "<无卡>")
	var n0 := int(b._sim_step_n)
	for _i in range(30):
		b._process(DT)
	_ok("⑤ 中断之后 sim 一步都不再走", int(b._sim_step_n) == n0)
	LS.stale_sec_for_test = 0.0
	b._hud._replay_exit()
	await _frames(6)
	## 行没了(服务器回空) ⇒ 下一次轮询就中断
	var b2 = await _spectate_from(j, _now)
	if b2 != null and b2._replay.is_live():
		b2.set_process(false)
		_serve_missing = true
		b2._replay.live.poll()
		await _frames(2)
		_ok("⑤ ★行没了 ⇒ 中断", b2._replay.live.broken and str(b2._replay.live.broken_why) == LS.TXT_BROKEN)
		_serve_missing = false
		b2._hud._replay_exit()
		await _frames(6)
	else:
		_ok("⑤ 分母: 第二次进了观赛", false)


# ⑥ ⑦ ─────────────────────────────────────────────────────────────
func _t_version_and_finished() -> void:
	print("── ⑥ 版本不同 / ⑦ 打完 ──")
	var j := _join_index()
	var r := _rec_of(_snaps[j])
	r["client_version"] = "0.0.1"
	_serve = _served(_snaps[j], _now)
	_serve["replay"] = RU.upload_b64(r)
	var got := ["~", "~"]
	var before := get_tree().current_scene
	LS.open_live(get_tree(), _id, func(c: String, m: String) -> void:
		got[0] = c
		got[1] = m)
	await _frames(4)
	_ok("⑥ ★版本不同 ⇒ 不进场, 说「版本不同，无法观赛」", got[0] == "version" and got[1] == "版本不同，无法观赛"
		and get_tree().current_scene == before and LS.pending.is_empty(), "%s / %s" % [got[0], got[1]])
	## ⑦ 打完: 赛况板上这一场变成普通卡(写胜负 + 「观看」), 「正在打」里没有它
	var last: Dictionary = _snaps[_snaps.size() - 1]
	var won := bool((_final_rec["end"] as Dictionary).get("won", false))
	var lrow := _board_row(last, _now - 300, _now)
	lrow["ended"] = false        # 即使服务器那一行还没标结束, 打完的录像一上 matches 就以它为准
	_board_live = [lrow]
	_board_games = [{"match_id": _id, "created_at": _iso(_now - 5), "result": {"won": won, "gw": 1 if won else 0, "gl": 0 if won else 1},
		"lp": lrow["lp"], "rp": lrow["rp"], "la": lrow["la"], "ra": lrow["ra"], "rw": 0, "rl": 0}]
	var bs: Node = get_tree().current_scene if _is_board(get_tree().current_scene) else await _open_board()
	bs.refresh()
	await _frames(6)
	var gcard: Node = null
	for c in bs.find_children(GBS.N_CARD + "*", "", true, false):
		if str((c as Node).get_meta("match_id", "")) == _id:
			gcard = c
	_ok("⑦ ★打完 ⇒ 「正在打」里没有它", (bs.live_games as Array).is_empty()
		and bs.find_children(GBS.N_LIVE_CARD + "*", "", true, false).is_empty())
	var gb: Button = gcard.find_child(GBS.N_WATCH, true, false) as Button if gcard != null else null
	var gt: Array = _labels_text(gcard) if gcard != null else []
	_ok("⑦ ★变成普通卡: 写「X 获胜」+「观看」", gb != null and gb.text == "观看" and str(gt).contains("获胜"), str(gt))
	## 打开一行已结束的直播 ⇒ 就是一场回放(带控件)
	_serve = _served(last, _now)
	LS.open_live(get_tree(), _id, func(_c: String, _m: String) -> void: pass, "", {"l": "甲", "r": "乙"})
	var b = await _wait_scene(_is_battle, 120)
	_ok("⑦ ★已结束的直播 = 普通回放(不是观赛)", b != null and b._replay.is_playing() and not b._replay.is_live())
	if b != null:
		b.set_process(false)
		b._process(DT)
		await _frames(2)
		_ok("⑦ 回放有暂停钮(对照: 观赛没有)", b.find_child(RC.N_PAUSE, true, false) != null)
		b._hud._replay_exit()
		await _frames(6)


# ⑧ ─────────────────────────────────────────────────────────────
func _t_unavailable() -> void:
	print("── ⑧ 服务端没部署 ──")
	_live_404 = true
	var res := SB.parse_live_board(true, 404, "{}")
	_ok("⑧ 404 ⇒ unavailable", str(res.get("reason", "")) == "unavailable")
	_board_games = []
	var bs: Node = await _open_board()
	bs._live_rows = [{"match_id": _id}]
	bs.refresh()
	await _frames(6)
	_ok("⑧ ★表没部署 ⇒ 没有「正在打」那一块(原先那一份也清掉)、不报错", (bs.live_games as Array).is_empty()
		and bs.find_children(GBS.N_LIVE_CARD + "*", "", true, false).is_empty() and bs._live_rows.is_empty())
	var got := ["~", "~"]
	LS.open_live(get_tree(), _id, func(c: String, m: String) -> void:
		got[0] = c
		got[1] = m)
	await _frames(4)
	_ok("⑧ 观赛点下去说「暂不可用」类原因码(不进场)", got[0] == "unavailable", got[0])
	## 打的人那一侧: 第一次 upsert 撞 404 ⇒ 本进程不再发(不每 3 秒被拒一次)
	SB.live_table_missing = false
	LU._reset_for_test()
	var row := {"match_id": _id, "replay": "eA==", "account_id": ME}
	LU.push(row)
	await _frames(2)
	var sent1: int = LU.sent_count
	LU.push(row)
	LU.push(row)
	await _frames(2)
	_ok("⑧ ★表没部署 ⇒ 撞一次 404 之后不再发直播行", SB.live_table_missing and sent1 == 1 and LU.sent_count == 1,
		"发 %d / %d" % [sent1, LU.sent_count])
	SB.live_table_missing = false
	_live_404 = false
	bs.queue_free()
	await _frames(2)


# ⑨ ─────────────────────────────────────────────────────────────
func _read(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_as_text().replace("\r\n", "\n") if f != null else ""


func _seg(t: String) -> String:
	var a := t.find(MARK_BEGIN)
	var b := t.find(MARK_END)
	return t.substr(a, b + MARK_END.length() - a) if a >= 0 and b > a else ""


func _t_sql() -> void:
	print("── ⑨ SQL 文件 ──")
	var mig := _read(MIGRATION)
	var sch := _read(SCHEMA)
	var seg := _seg(mig)
	_ok("⑨ 分母: 迁移文件在、首尾标记各一", seg != "" and mig.count(MARK_BEGIN) == 1 and mig.count(MARK_END) == 1, "%d 字" % mig.length())
	_ok("⑨ ★schema.sql 里同一段逐字相同(只出现一次)", sch.count(MARK_BEGIN) == 1 and _seg(sch) == seg)
	var code := ""
	for ln in seg.split("\n"):
		var l2 := str(ln)
		var c := l2.find("--")
		code += (l2.substr(0, c) if c >= 0 else l2) + "\n"
	code = code.to_lower()
	for want in ["create table if not exists public.live_matches", "alter table public.live_matches enable row level security",
			"for insert with check (account_id = auth.uid())", "for update using (account_id = auth.uid()) with check (account_id = auth.uid())",
			"date_trunc('week', now() at time zone 'utc')", "delete from public.live_matches where started_at <",
			"create trigger live_matches_stamp before insert or update on public.live_matches",
			"new.updated_at  := now()", "alter table public.finals_buckets add column if not exists revealed_at timestamptz",
			"set closed = true, revealed_at = now()", "round_at = now(), revealed_at = now()",
			"'revealed_at', coalesce(extract(epoch from b.revealed_at)::bigint, 0)"]:
		_ok("⑨ 有: " + want.substr(0, 60), code.contains(want))
	_ok("⑨ ★直播行录像上限 = 客户端 REPLAY_MAX_B64(%d)" % RU.REPLAY_MAX_B64,
		code.contains("octet_length(replay) between 1 and %d" % RU.REPLAY_MAX_B64))
	_ok("⑨ 没有 delete 策略(只走周清)", not code.contains("for delete"))
	_ok("⑨ 读策略要登录、只读本周", code.contains("for select using (auth.uid() is not null") and code.contains("started_at >= date_trunc('week'"))


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 实时观赛·周六直播" if _fail == 0 and _n > 60 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
