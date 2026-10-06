extends Node
## verify_weekend_replay.gd — 周末看回放门禁(方案书 docs/plans/20261004-周末看回放.md)
##
## 用户 2026-10-04:「回放在哪里」「没有，回放不是让你做周六周日的吗」「周六连对阵图都没有吗」⇒ 选 A。
##
## ★全程走真入口: 真战斗场录一局周六闯关赛 + 一局周日决赛 → 真上传队列 → 假服务器收下 →
##   真实例化赛况板 / 对阵图 → **按那一格的按钮**(`pressed.emit()`) → 真换场景进回放 → 退出回到原页面。
## ★网络是假的(`SupabaseNet._transport_for_test`), 假的是**服务器**; 不向任何外部服务发请求。
##
## 段落:
##   ① 赛况板数据层(纯函数): 排序 / 状态 / 收盘后 / 只以对手身份出现的人按快照标签 / 「我」
##   ② 赛况板真屏: 行数与顺序 / 机器人不露馅 / 点人 ⇒ 只剩他的场次 / 点对局 ⇒ 进回放 ⇒ 退出回到赛况板
##   ③ 赛况板失败: 没接服务器 / 404 / 断网 ⇒ 一句话、不报错、没有死按钮
##   ④ 周日录与传: 决赛场也录; 单子带坐标; 揭晓前不传、揭晓后传; 行里 seed = 报上去的 seed_used
##   ⑤ 对阵图: 穷举每一格 —— 已翻面可点, 当前轮 / 未到 / 轮空不可点; 点已翻面 ⇒ 问对 (周,组,轮,场) ⇒ 进回放 ⇒ 回对阵图
##   ⑥ 主菜单周六那块是门, 点了进赛况板; 平日不是门

const SB := preload("res://scripts/net/supabase.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const RF := preload("res://scripts/systems/replay/replay_fetcher.gd")
const BOARD := preload("res://scripts/systems/replay/gauntlet_board.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const Backend := preload("res://scripts/net/backend.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const MAP := preload("res://scripts/scenes/BracketMapScene.gd")
const BOARD_SCENE := "res://scenes/GauntletBoard.tscn"
const MAP_SCENE := "res://scenes/BracketMap.tscn"
const ME := "11111111-2222-4333-8444-555555555555"
const TOKEN := "tok-weekend"

var _fail := 0
var _n := 0
var _gs
var _reqs: Array = []
var _rows: Dictionary = {}          # 假服务器的 matches 表: match_id → 整行(POST 进来的)
var _board_mode := "ok"
var _board_rows: Array = []
var _fr_mode := "ok"
var _fr_bodies: Array = []
var _gid := ""                      # 周六那一局的录像 id
var _fid := ""                      # 周日那一局的录像 id
var _grec: Dictionary = {}
var _frec: Dictionary = {}
## 分母: 最后一段真的走完了(协程中途被脚本错误打断时, 前面的 PASS 照样会打出来)。
var _all_sections_ran := false


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


# ─────────────────────────────── 假服务器 ───────────────────────────────
func _transport(m, u, h, b, cb) -> void:
	var url := str(u)
	var meth := str(m)
	_reqs.append({"m": meth, "u": url, "b": str(b)})
	if url.find("/auth/v1/") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({
			"access_token": TOKEN, "refresh_token": "r2", "expires_in": 3600,
			"user": {"id": ME, "is_anonymous": true}})})
		return
	if url.find("/rest/v1/matches?phase=eq.gauntlet") >= 0 and meth == "GET":
		match _board_mode:
			"404":
				cb.call({"ok": true, "code": 404, "body": "{\"message\":\"no\"}"})
			"offline":
				cb.call({"ok": false, "code": 0, "body": ""})
			_:
				cb.call({"ok": true, "code": 200, "body": JSON.stringify(_board_rows)})
		return
	if url.find("/rest/v1/matches?match_id=eq.") >= 0 and meth == "GET":
		var k := url.find("match_id=eq.")
		var id := url.substr(k + len("match_id=eq.")).get_slice("&", 0)
		var out: Array = []
		if _rows.has(id):
			out.append({"match_id": id, "replay": str((_rows[id] as Dictionary).get("replay", ""))})
		cb.call({"ok": true, "code": 200, "body": JSON.stringify(out)})
		return
	if url.ends_with("/rest/v1/matches") and meth == "POST":
		var j = JSON.parse_string(str(b))
		if j is Dictionary:
			_rows[str(j.get("match_id", ""))] = j
		cb.call({"ok": true, "code": 201, "body": ""})
		return
	if url.find("/rest/v1/rpc/finals_replay") >= 0:
		_fr_bodies.append(JSON.parse_string(str(b)))
		match _fr_mode:
			"404":
				cb.call({"ok": true, "code": 404, "body": "{\"message\":\"no fn\"}"})
			"no_replay":
				cb.call({"ok": true, "code": 200, "body": "{\"ok\":false,\"reason\":\"no_replay\"}"})
			_:
				cb.call({"ok": true, "code": 200, "body": JSON.stringify(
					{"ok": true, "match_id": _fid, "replay": RU.upload_b64(_frec)})})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


func _posts_to_matches() -> Array:
	var out: Array = []
	for r in _reqs:
		if str(r["u"]).ends_with("/rest/v1/matches") and str(r["m"]) == "POST":
			out.append(JSON.parse_string(str(r["b"])))
	return out


# ─────────────────────────────── 主流程 ───────────────────────────────
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
	_ok("分母: 录制时后端是关的(录完那一下不往外传)", not SB.enabled())
	_setup_gs()

	await _t_record_gauntlet()
	await _t_record_finals()
	_t_board_pure()

	## 开后端(假服务器)。
	var had_env: bool = OS.has_environment(SB.ENV_URL)
	var env0: String = OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._token = TOKEN
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	_ok("★分母: 后端真的打开了", SB.enabled())

	await _t_upload_gate()
	await _t_board_screen()
	await _t_board_failures()
	await _t_bracket()
	await _t_mainmenu_door()

	SB._transport_for_test = Callable()
	SB._reset_auth_for_test()
	SB.finals_clear()
	SB.finals_week_clear()
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	if had_env:
		OS.set_environment(SB.ENV_URL, env0)
	else:
		OS.unset_environment(SB.ENV_URL)
	_finish()


func _setup_gs() -> void:
	_gs.reset_dual_lane()
	_gs.test_mode = true
	_gs.tutorial_active = false
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	_gs.dual_active = true
	_gs.account_id = ME
	_gs.auth_refresh = "r1"
	_gs.week_anchor_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	_gs.replay_upload_pending = []


## 扮演玩家打一局(与 verify_replay_watch 同一套动作)。返回录像 id。
func _play_one(tag: String) -> String:
	var q0: int = (_gs.replay_upload_pending as Array).size()
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	_ok("%s 分母: 这一局在录" % tag, str(s._replay.mode) == "rec", str(s._replay.mode))
	var last := ""
	var stf := 0
	var fights := 0
	var surrendered := false
	var i := 0
	while i < 6000 and (_gs.replay_upload_pending as Array).size() == q0:
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
		elif st == "fight" and fights >= 2 and stf == 120 and not surrendered:
			s._do_surrender()
			surrendered = true
		s._process(0.05)
		await get_tree().process_frame
		i += 1
	await _frames(6)
	var q: Array = _gs.replay_upload_pending
	var id := str((q[q.size() - 1] as Dictionary).get("id", "")) if q.size() > q0 else ""
	_ok("%s 分母: 结算把录像排进了上传队列(uuid)" % tag, SB.is_uuid(id), id)
	s.queue_free()
	await _frames(4)
	return id


# ④a ─────────────────────────────────────────────────────────────
func _t_record_gauntlet() -> void:
	print("── ④a 周六: 录一局闯关赛(赛前 2-1) ──")
	_gs.week_phase = "gauntlet"
	_gs.finals_match = {}
	_gs.gauntlet_wins = 2
	_gs.gauntlet_losses = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261004
	_gs.dual_ghost = Backend.make_bot(3, rng, 2, 1)
	_gid = await _play_one("④a")
	_grec = ReplayRecorder.load_record(_gid) if _gid != "" else {}
	var e: Dictionary = _entry(_gid)
	_ok("④a 单子标成闯关(ph=gauntlet)、带赛前战绩 2-1",
		str(e.get("ph", "")) == RU.PH_GAUNTLET and int(e.get("gw0", -1)) == 2 and int(e.get("gl0", -1)) == 1, str(e.keys()))
	var row: Dictionary = RU.build_row(e, _grec, ME)
	var won := bool((_grec.get("end", {}) as Dictionary).get("won", false))
	var res: Dictionary = row.get("result", {})
	_ok("④a ★行里写的是【这一局打完之后】的战绩(%s)" % ("赢" if won else "输"),
		int(res.get("gw", -1)) == (3 if won else 2) and int(res.get("gl", -1)) == (1 if won else 2), str(res))
	_ok("④a 行 phase = gauntlet, 不带决赛坐标", str(row.get("phase", "")) == "gauntlet" and not res.has("fb"))
	var rs: Dictionary = row.get("right_snapshot", {})
	_ok("④a ★对手快照不露馅: 没有 is_bot / ghost_id, 名字与 #ID 合法",
		not rs.has("is_bot") and not rs.has("ghost_id") and P2C.tag_valid(str((rs.get("profile", {}) as Dictionary).get("tag", ""))),
		str(rs.get("profile", {})))
	_ok("④a 对手快照带战绩标签 2-1(赛况板拿它记对手)", int(rs.get("gl_w", -1)) == 2 and int(rs.get("gl_l", -1)) == 1)


func _entry(id: String) -> Dictionary:
	for e in _gs.replay_upload_pending:
		if e is Dictionary and str((e as Dictionary).get("id", "")) == id:
			return e
	return {}


# ④b ─────────────────────────────────────────────────────────────
func _t_record_finals() -> void:
	print("── ④b 周日: 决赛场也录 ──")
	_gs.week_phase = "finals"
	_gs.finals_match = {"bucket": 2, "round": 1, "match": 1, "side": 1}
	_gs.finals_report_pending = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_gs.dual_ghost = Backend.make_bot(5, rng)
	_ok("④b ★决赛场(有 finals_match)要录", ReplayRecorder.should_record())
	var fm0: Dictionary = _gs.finals_match.duplicate()
	_gs.finals_match = {}
	_ok("④b 周日但不是对阵图开的那一局(没有 finals_match) ⇒ 不录", not ReplayRecorder.should_record())
	_gs.finals_match = fm0
	_fid = await _play_one("④b")
	_frec = ReplayRecorder.load_record(_fid) if _fid != "" else {}
	var e: Dictionary = _entry(_fid)
	var fk: Dictionary = e.get("fk", {})
	_ok("④b 单子标成决赛、带坐标(组 2 · 第 1 轮 · 第 1 场 · 侧 1)",
		str(e.get("ph", "")) == RU.PH_FINALS and int(fk.get("b", -1)) == 2 and int(fk.get("r", -1)) == 1
		and int(fk.get("m", -1)) == 1 and int(fk.get("s", -1)) == 1, str(e))
	var row: Dictionary = RU.build_row(e, _frec, ME)
	var res: Dictionary = row.get("result", {})
	_ok("④b 行 phase = finals, result 带 fb/fr/fm",
		str(row.get("phase", "")) == "finals" and int(res.get("fb", -1)) == 2 and int(res.get("fr", -1)) == 1
		and int(res.get("fm", -1)) == 1 and not res.has("gw"), str(res))
	var pend: Dictionary = _gs.finals_report_pending
	_ok("④b 分母: 结算报了决赛结果(补报单在)", pend.has("seed"), str(pend))
	_ok("④b ★★行里的 seed == 报给服务端的 seed_used(服务端靠它认出采纳那一份)",
		int(row.get("seed", 0)) != 0 and int(row.get("seed", 0)) == int(pend.get("seed", -1))
		and int(Backend.last_finals_report.get("seed", -2)) == int(row.get("seed", 0)),
		"row=%d pend=%d last=%d" % [int(row.get("seed", 0)), int(pend.get("seed", -1)),
			int(Backend.last_finals_report.get("seed", -2))])
	_gs.finals_match = {}
	_gs.week_phase = "gauntlet"


# ① ─────────────────────────────────────────────────────────────
func _prof(nm: String, tag: String, av: String = "basic") -> Dictionary:
	return {"name": nm, "tag": tag, "avatar": av, "id": "g_x"}


func _row(id: String, t: String, lp: Dictionary, rp: Dictionary, won: bool, gw = null, gl = null,
		rw = null, rl = null) -> Dictionary:
	var res := {"won": won, "steps": 100, "surrendered": false}
	if gw != null:
		res["gw"] = gw
		res["gl"] = gl
	return {"match_id": id, "created_at": t, "result": res, "lp": lp, "rp": rp, "rw": rw, "rl": rl}


func _uid(n: int) -> String:
	return "%08x-0000-4000-8000-%012x" % [n, n]


## 一套固定输入(标签自洽: 闯关只同标签互配, 对手快照标签 = 录像方赛前战绩):
##   我 2-0(在打) / 甲 4-1(晋级) / 乙 1-3(出局) / 丙 只以对手出现、快照标签 2-1 / 戊 只以对手出现、标签 3-1 /
##   丁 老行没有 gw(数场次 1-1)。
func _fixture() -> Array:
	var me := _prof("小龟我", Backend.my_tag())
	var a := _prof("甲龟", P2C.player_tag("acct:a"))
	var b := _prof("乙龟", P2C.player_tag("acct:b"))
	var c := _prof("丙龟", P2C.player_tag("acct:c"))
	var d := _prof("丁龟", P2C.player_tag("acct:d"))
	var e := _prof("戊龟", P2C.player_tag("acct:e"))
	return [
		_row(_uid(1), "2026-10-03T10:00:00.000+00:00", me, c, true, 1, 0, 0, 0),
		_row(_uid(2), "2026-10-03T11:00:00.000+00:00", me, b, true, 2, 0, 1, 0),
		_row(_uid(3), "2026-10-03T09:00:00+00:00", a, e, true, 4, 1, 3, 1),
		_row(_uid(4), "2026-10-03T08:00:00+00:00", b, a, false, 1, 3, 1, 2),
		_row(_uid(5), "2026-10-03T12:00:00+08:00", d, c, true, null, null, 2, 1),
		_row(_uid(6), "2026-10-03T03:30:00+00:00", d, a, false, null, null, 2, 1),
	]


func _t_board_pure() -> void:
	print("── ① 赛况板数据层 ──")
	_ok("① 时间串: Z 偏移 / +08:00 / 带毫秒",
		BOARD.iso_to_unix("2026-10-03T12:00:00+08:00") == BOARD.iso_to_unix("2026-10-03T04:00:00+00:00")
		and BOARD.iso_to_unix("2026-10-03T04:00:00.123+00:00") == BOARD.iso_to_unix("2026-10-03T04:00:00+00:00")
		and BOARD.iso_to_unix("2026-10-03T04:00:00+00:00") > 0)
	var d: Dictionary = BOARD.build(_fixture(), Backend.my_tag(), false)
	var ps: Array = d["players"]
	var got: Array = []
	for p in ps:
		got.append("%s %d-%d %s" % [p["name"], int(p["w"]), int(p["l"]), p["state_text"]])
	print("    榜: ", got)
	_ok("① 分母: 六个人都上榜", ps.size() == 6, str(ps.size()))
	_ok("① ★★排序 = 胜多在前、负少在前; 状态 = 4 胜晋级 / 3 负出局",
		got == ["甲龟 4-1 已晋级", "戊龟 3-1 在打", "小龟我 2-0 在打", "丙龟 2-1 在打", "丁龟 1-1 在打", "乙龟 1-3 已出局"], str(got))
	_ok("① ★排序判据本身: 2-0 排在 2-1 前面", got.find("小龟我 2-0 在打") >= 0 and got.find("小龟我 2-0 在打") < got.find("丙龟 2-1 在打"), str(got))
	var me_n := 0
	for p in ps:
		if bool(p["me"]):
			me_n += 1
	_ok("① 「我」恰好一个、是我", me_n == 1 and bool(ps[got.find("小龟我 2-0 在打")]["me"]))
	_ok("① ★只以对手身份出现的丙按快照标签记 2-1(与机器人走同一条规则)", got.has("丙龟 2-1 在打"), str(got))
	_ok("① 老行(没有 gw/gl)退回数场次: 丁 1-1", got.has("丁龟 1-1 在打"), str(got))
	var gs: Array = d["games"]
	_ok("① 流水 6 场、新的在前(+08:00 那场其实是 04:00 UTC)", gs.size() == 6 and str(gs[0]["id"]) == _uid(2)
		and str(gs[5]["id"]) == _uid(6) and str(gs[4]["id"]) == _uid(5), str(gs.map(func(g): return g["id"])))
	_ok("① 甲打过 / 被打过的有 3 场", BOARD.games_of(gs, P2C.player_tag("acct:a")).size() == 3)
	_ok("① 胜者名字", BOARD.winner_name(gs[0]) == "小龟我" and BOARD.winner_name(gs[5]) == "甲龟")
	var dc: Dictionary = BOARD.build(_fixture(), Backend.my_tag(), true)
	var st_c := {}
	for p in dc["players"]:
		st_c[str(p["name"])] = str(p["state_text"])
	_ok("① ★收盘后还在打的一律算出局(没打满 = 没晋级), 晋级的不变",
		st_c.get("小龟我", "") == "已出局" and st_c.get("丙龟", "") == "已出局" and st_c.get("甲龟", "") == "已晋级", str(st_c))
	_ok("① 空输入 ⇒ 空榜, 不报错", (BOARD.build([], "", false)["players"] as Array).is_empty())


# ④c ─────────────────────────────────────────────────────────────
func _t_upload_gate() -> void:
	print("── ④c 上传: 周六的直接传, 周日的揭晓后才传 ──")
	SB.finals_clear()
	SB.finals_week_clear()
	var now := int(Time.get_unix_time_from_system())
	var ef: Dictionary = _entry(_fid)
	_ok("④c 纯判据: 没有对阵数据 ⇒ 周日单子不能发", not RU.finals_upload_ready(ef, now, []))
	_ok("④c 纯判据: 那一场在当前轮(不在 done) ⇒ 不能发",
		not RU.finals_upload_ready(ef, now, [{"bucket": 2, "done": {"1-0": 0}}]))
	_ok("④c 纯判据: 别的组同一个场号揭晓了 ⇒ 不能发",
		not RU.finals_upload_ready(ef, now, [{"bucket": 3, "done": {"1-1": 0}}]))
	_ok("④c ★纯判据: 那一场揭晓了 ⇒ 能发", RU.finals_upload_ready(ef, now, [{"bucket": 2, "done": {"1-1": 1}}]))
	_ok("④c 纯判据: 那一周过完了 ⇒ 能发", RU.finals_upload_ready(ef, int(ef["wk"]) + 7 * 86400, []))
	_ok("④c 周六单子不受这道闸", RU.finals_upload_ready(_entry(_gid), now, []))
	RU._inflight.clear()
	RU.retry()
	await _wait_posts(1)
	var phs: Array = []
	for p in _posts_to_matches():
		phs.append(str((p as Dictionary).get("phase", "")))
	_ok("④c ★没揭晓: 只传了周六那一局, 决赛那一局压着", phs == ["gauntlet"], str(phs))
	_ok("④c 周六那一局回读确认后销单", _entry(_gid).is_empty())
	_ok("④c 决赛单子还在队列里", not _entry(_fid).is_empty())
	## 对阵图拿到「那一场翻面了」的数据(就是产品自己的缓存那一格)
	SB._finals_view = {"bucket": 2, "size": 4, "round": 2, "done": {"1-0": 0, "1-1": 1}}
	RU.retry()
	await _wait_posts(2)
	phs.clear()
	var fpost: Dictionary = {}
	for p in _posts_to_matches():
		phs.append(str((p as Dictionary).get("phase", "")))
		if str((p as Dictionary).get("phase", "")) == "finals":
			fpost = p
	_ok("④c ★揭晓之后: 决赛那一局传上去了", phs == ["gauntlet", "finals"], str(phs))
	_ok("④c 决赛行带坐标与种子", int((fpost.get("result", {}) as Dictionary).get("fm", -1)) == 1
		and int(fpost.get("seed", 0)) == int(_frec.get("seed", -1)), str(fpost.get("result", {})))
	_ok("④c ★right_account 恒空(机器人没有账号, 填了就露馅)", fpost.get("right_account", "x") == null)
	_ok("④c 决赛单子回读确认后销单", _entry(_fid).is_empty())
	SB.finals_clear()


func _wait_posts(n: int) -> void:
	var w := 0
	while w < 300 and (_posts_to_matches().size() < n or not RU._inflight.is_empty()):
		await get_tree().process_frame
		w += 1


# ② ─────────────────────────────────────────────────────────────
func _labels_text(n: Node) -> String:
	var out := PackedStringArray()
	for c in n.find_children("*", "Label", true, false):
		out.append(str((c as Label).text))
	for c in n.find_children("*", "Button", true, false):
		out.append(str((c as Button).text))
		out.append(str((c as Button).tooltip_text))
	return " | ".join(out)


func _is(n, suffix: String) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() != null \
		and str((n.get_script() as Script).resource_path).ends_with(suffix)


func _open_scene(path: String) -> Node:
	var sc: Node = (load(path) as PackedScene).instantiate()
	get_tree().root.add_child(sc)
	get_tree().current_scene = sc
	await _frames(3)
	return sc


func _wait_scene(suffix: String, max_f: int = 300) -> Node:
	var w := 0
	while w < max_f:
		var cs = get_tree().current_scene
		if _is(cs, suffix):
			return cs
		await get_tree().process_frame
		w += 1
	return null


## 把上传上去的周六那一行翻成赛况板查询会回的形状(就是 PostgREST 按 `gauntlet_board_query` 选出来的那几列)。
func _as_board_row(row: Dictionary, created: String) -> Dictionary:
	var rs: Dictionary = row.get("right_snapshot", {})
	return {"match_id": row["match_id"], "created_at": created, "result": row["result"],
		"lp": (row.get("left_snapshot", {}) as Dictionary).get("profile", {}),
		"rp": rs.get("profile", {}), "rw": rs.get("gl_w", null), "rl": rs.get("gl_l", null)}


func _t_board_screen() -> void:
	print("── ② 赛况板真屏 ──")
	_ok("② 分母: 周六那一局在假服务器里", _rows.has(_gid))
	_board_rows = _fixture()
	if _rows.has(_gid):
		_board_rows.push_front(_as_board_row(_rows[_gid], "2026-10-03T13:00:00+00:00"))
	_board_mode = "ok"
	var q := SB.gauntlet_board_query(P2C.week_anchor_utc(P2C.now_utc()))
	_ok("② 查询只取摘要: 不取整份快照 / 录像 / 账号",
		q.find("lp:left_snapshot->profile") >= 0 and q.find("replay") < 0 and q.find("left_account") < 0
		and q.find("phase=eq.gauntlet") >= 0, q)
	## 本机录像删掉 ⇒ 点回放必须真去服务端取(走 S3 那条)
	DirAccess.remove_absolute(ReplayRecorder.SAVE_DIR + _gid + ".rpl")
	_ok("② 分母: 本机那份已删", not RF.local_available(_gid))
	_reqs.clear()
	var bs: Node = await _open_scene(BOARD_SCENE)
	await _frames(10)
	_ok("② 分母: 真去问了赛况(带本周周号)", _reqs.any(func(r): return str(r["u"]).find(
		"season_week=eq.%d" % P2C.week_anchor_utc(P2C.now_utc())) >= 0))
	var prow: Array = bs.find_children("PlayerBtn", "Button", true, false)
	var grow: Array = bs.find_children("GameBtn", "Button", true, false)
	print("    状态行: ", (bs.get("_status") as Label).text)
	_ok("② ★行数: 7 个人(含真录的那一局的对手) / 7 场", prow.size() == 7 and grow.size() == 7,
		"%d 人 / %d 场" % [prow.size(), grow.size()])
	var order: Array = []
	for p in bs.data.get("players", []):
		order.append("%s %d-%d" % [p["name"], int(p["w"]), int(p["l"])])
	_ok("② 榜首是 4-1 晋级的甲", order.size() > 0 and str(order[0]) == "甲龟 4-1", str(order))
	var txt := _labels_text(bs)
	_ok("② ★★不露馅: 屏上没有「机器人」/ bot 字样", txt.find("机器人") < 0 and txt.to_lower().find("bot") < 0,
		txt.substr(0, 120))
	var bot_prof: Dictionary = ((_rows.get(_gid, {}) as Dictionary).get("right_snapshot", {}) as Dictionary).get("profile", {})
	var bot_seen := false
	for p in bs.data.get("players", []):
		if str(p["tag"]) == str(bot_prof.get("tag", "?")):
			bot_seen = P2C.tag_valid(str(p["tag"])) and str(p["name"]) == str(bot_prof.get("name", "")) \
				and int(p["w"]) == 2 and int(p["l"]) == 1
	_ok("② ★那局的对手(机器人)上榜: 像人的名字 + 合法 #ID + 快照标签 2-1, 与真人同一种长相", bot_seen,
		str(bot_prof))
	## 点人
	var a_tag := P2C.player_tag("acct:a")
	var pa: Button = null
	for b in prow:
		if str((b as Button).get_meta("key", "")) == a_tag:
			pa = b
	_ok("② 分母: 找到甲那一行", pa != null)
	if pa != null:
		pa.pressed.emit()
		await _frames(3)
		var g2: Array = bs.find_children("GameBtn", "Button", true, false)
		_ok("② ★点甲 ⇒ 右栏只剩他的 3 场", g2.size() == 3 and str(bs.focus_tag) == a_tag, "%d 场" % g2.size())
		_ok("② 小标题说清是谁的", str((bs.get("_games_title") as Label).text).find("甲龟") >= 0)
		_ok("② 「看全部」出现", bool((bs.get("_all_btn") as Button).visible))
		(bs.get("_all_btn") as Button).pressed.emit()
		await _frames(3)
		_ok("② 「看全部」⇒ 回到 7 场", bs.find_children("GameBtn", "Button", true, false).size() == 7)
	## 点那一局 ⇒ 进回放
	var gb: Button = null
	for b in bs.find_children("GameBtn", "Button", true, false):
		if str((b as Button).get_meta("key", "")) == _gid:
			gb = b
	_ok("② 分母: 真录的那一局有一行", gb != null)
	if gb == null:
		return
	_reqs.clear()
	gb.pressed.emit()
	var bt: Node = await _wait_scene("RealtimeBattle3DScene.gd")
	_ok("② ★★点对局 ⇒ 按 match_id 去服务端取 ⇒ 换到回放", bt != null and _reqs.any(func(r):
		return str(r["u"]).find("match_id=eq.%s" % _gid) >= 0))
	_ok("② 播的是那一局(回放模式)", bt != null and bt._replay.is_playing())
	_ok("② 看完回赛况板(不是战绩页)", ReplayRecorder.exit_scene() == BOARD_SCENE, ReplayRecorder.exit_scene())
	_ok("② 结束那句话带胜者名字", ReplayRecorder.end_caption(true).find(str((_rows[_gid]["left_snapshot"]["profile"] as Dictionary).get("name", "?"))) >= 0,
		ReplayRecorder.end_caption(true))
	if bt != null:
		await _frames(30)
		bt._hud._replay_exit()
		var back: Node = await _wait_scene("GauntletBoardScene.gd")
		_ok("② ★退出回放 ⇒ 真回到赛况板", back != null)
		_ok("② 回来后 GameState 还原(没有挂着的待播)", ReplayRecorder.pending_play.is_empty() and not ReplayRecorder._has_backup)
		await _frames(10)


# ③ ─────────────────────────────────────────────────────────────
func _t_board_failures() -> void:
	print("── ③ 赛况板失败 ──")
	for mode in ["404", "offline"]:
		_board_mode = mode
		var bs: Node = await _open_scene(BOARD_SCENE)
		await _frames(10)
		var st := str((bs.get("_status") as Label).text)
		_ok("③ %s ⇒ 说一句话(%s), 没有死按钮" % [mode, st],
			st != "" and bs.find_children("GameBtn", "Button", true, false).is_empty()
			and bs.find_children("PlayerBtn", "Button", true, false).is_empty())
		if mode == "404":
			_ok("③ ★404(服务端没这条) ⇒ 「赛况暂无」, 不说网络不好", st == "赛况暂无", st)
		else:
			_ok("③ 断网 ⇒ 说连不上", st.find("连不上") >= 0, st)
		bs.queue_free()
		await _frames(3)
	## 没接服务器
	OS.set_environment(SB.ENV_URL, " ")
	_ok("③ 分母: 后端关了", not SB.enabled())
	_reqs.clear()
	var bs2: Node = await _open_scene(BOARD_SCENE)
	await _frames(5)
	var st2 := str((bs2.get("_status") as Label).text)
	_ok("③ 没接服务器 ⇒ 说清楚, 一个请求都不发", st2.find("没接服务器") >= 0 and _reqs.is_empty(), st2)
	bs2.queue_free()
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	_board_mode = "ok"
	await _frames(3)


# ⑤ ─────────────────────────────────────────────────────────────
func _btn_at(m, r: int, mm: int) -> Button:
	for b in m._canvas.find_children("*", "Button", true, false):
		if (b as Button).get_meta("rm", Vector2i(-9, -9)) == Vector2i(r, mm):
			return b
	return null


## 穷举这一组每一格: 可点 ⇔ 已翻面 或 我上场打; 屏上真按钮与判据一一对应。
func _exhaust(m, tag: String) -> void:
	var B := preload("res://scripts/gamedata/bracket.gd")
	var n := int(m.cur().get("size", 0))
	var seen := {}
	var bad: Array = []
	var cnt := 0
	for r in range(1, B.rounds_for(n) + 1):
		for mm in range(B.matches_in_round(n, r)):
			cnt += 1
			var st := str(m.match_state(r, mm))
			seen[st] = true
			var want: bool = st == MAP.ST_DONE or m.should_fetch_opponent(r, mm)
			if bool(m.can_open(r, mm)) != want or (_btn_at(m, r, mm) != null) != want:
				bad.append("%d-%d %s can=%s btn=%s" % [r, mm, st, m.can_open(r, mm), _btn_at(m, r, mm) != null])
			if st != MAP.ST_DONE and m.can_open(r, mm) and not m.should_fetch_opponent(r, mm):
				bad.append("%d-%d %s 不该能看" % [r, mm, st])
	_ok("⑤ %s ★★穷举 %d 场: 只有已翻面(或我上场)可点, 按钮与判据一致" % [tag, cnt], bad.is_empty() and cnt > 0, str(bad))
	_ok("⑤ %s 分母: 已翻面 / 当前轮 / 未到 三种格子都在场" % tag,
		seen.has(MAP.ST_DONE) and seen.has(MAP.ST_LIVE) and seen.has(MAP.ST_LOCKED), str(seen.keys()))


func _t_bracket() -> void:
	print("── ⑤ 对阵图点格看回放 ──")
	_ok("⑤ 开关开了", MAP.REPLAY_LIVE)
	_ok("⑤ finals_replay 是读(时间穿越期间不拦)", not SB.is_write_request("POST", "http://x/rest/v1/rpc/finals_replay"))
	var now := int(Time.get_unix_time_from_system())
	var wk := P2C.week_anchor_utc(now)
	## 8 人组, 第 2 轮进行中: 第 1 轮 4 场已翻面, 第 2 轮 2 场当前轮, 第 3 轮未到。
	var ents: Array = []
	for i in range(8):
		ents.append({"seed": i, "name": "龟%d" % i, "account_id": "acct-%d" % i})
	var body := JSON.stringify({"ok": true, "week": wk, "now": now, "buckets": [
		{"bucket": 2, "n": 8, "round": 2, "closed": false,
			"done": {"1-0": 0, "1-1": 1, "1-2": 0, "1-3": 1, "2-0": 1}, "entrants": ents}]})
	var wv: Dictionary = SB.parse_finals_week(true, 200, body, "", now)
	_ok("⑤ 分母: 当前轮的 2-0 被第二道锁筛掉(服务端写错一行也漏不出来)",
		not ((wv["buckets"][0] as Dictionary)["done"] as Dictionary).has("2-0"))
	## 观众(没晋级): 产品自己的入口 —— 真场景, 联网那条路接上的 match_opened
	var m: Node = await _open_scene(MAP_SCENE)
	m.set_data({}, {}, now)
	m.set_week(wv)
	await _frames(3)
	_ok("⑤ 分母: 观众看的是第 2 组(8 人)、我不在里面", int(m.cur().get("size", 0)) == 8 and int(m.cur().get("me", 0)) == -1)
	_exhaust(m, "观众")
	_ok("⑤ ★当前轮那一格(2-0)点不开", _btn_at(m, 2, 0) == null and not m.can_open(2, 0))
	var b11 := _btn_at(m, 1, 1)
	var win11 := str(m.competitor(1, 1, m.winner_side(1, 1)).get("name", "?"))
	_ok("⑤ 分母: 已翻面 1-1 那一格有按钮", b11 != null)
	## 404: 服务端函数没上线
	_fr_mode = "404"
	_fr_bodies.clear()
	b11.pressed.emit()
	await _frames(20)
	_ok("⑤ ★没上线(404) ⇒ 一句话、不换场景", str(m.last_replay_code) == "unavailable"
		and get_tree().current_scene == m and str(m._replay_lb.text) == RF.message("unavailable"), str(m.last_replay_msg))
	_fr_mode = "no_replay"
	b11.pressed.emit()
	await _frames(20)
	_ok("⑤ 没有采纳录像(超时补判) ⇒ 说没留下回放", str(m.last_replay_code) == "no_replay", str(m.last_replay_msg))
	## 正常
	_fr_mode = "ok"
	_fr_bodies.clear()
	b11.pressed.emit()
	var bt: Node = await _wait_scene("RealtimeBattle3DScene.gd")
	var ask: Dictionary = _fr_bodies[0] if not _fr_bodies.is_empty() else {}
	_ok("⑤ ★★问的是对的那一场 (周, 组 2, 第 1 轮, 第 1 场)",
		int(ask.get("p_week", 0)) == wk and int(ask.get("p_bucket", -1)) == 2 and int(ask.get("p_round", 0)) == 1
		and int(ask.get("p_match", -1)) == 1, str(ask))
	_ok("⑤ ★★进回放, 播的是回包里那一份(决赛那一局)", bt != null and bt._replay.is_playing()
		and str(bt._replay.rec.get("id", "")) == _fid)
	_ok("⑤ 看完回对阵图", ReplayRecorder.exit_scene() == MAP_SCENE, ReplayRecorder.exit_scene())
	_ok("⑤ 结束那句话说胜者(1-1 胜者是下侧 %s), 不论录像方输赢" % win11,
		win11.begins_with("龟") and ReplayRecorder.end_caption(true).find(win11) >= 0
		and ReplayRecorder.end_caption(false).find(win11) >= 0, ReplayRecorder.end_caption(true))
	if bt != null:
		await _frames(20)
		bt._hud._replay_exit()
		var back: Node = await _wait_scene("BracketMapScene.gd")
		_ok("⑤ ★退出回放 ⇒ 真回到对阵图", back != null)
		await _frames(5)
		if back != null:
			back.queue_free()
	## 选手(我在组里): 我上场那一格照旧是「上场开打」, 翻面的仍可看
	var mine: Dictionary = SB._bucket_from({"bucket": 2, "n": 8, "round": 2, "closed": false,
		"done": {"1-0": 0, "1-1": 1, "1-2": 0, "1-3": 1}, "entrants": ents}, "acct-0", now)
	var m2 = MAP.new()
	add_child(m2)
	await get_tree().process_frame
	m2.set_data(mine, {}, now)
	await _frames(2)
	_ok("⑤ 分母: 选手视角, 我是 0 号", int(m2.cur().get("me", -1)) == 0)
	_exhaust(m2, "选手")
	_ok("⑤ 我这一场(2-0, 当前轮)仍是上场开打, 不是看回放", m2.should_fetch_opponent(2, 0)
		and _btn_at(m2, 2, 0) != null and str(_btn_at(m2, 2, 0).tooltip_text) == "开始对战")
	_ok("⑤ 已翻面的格子提示「重看这一场」(不写「回放」: 对阵图用词规矩④)",
		_btn_at(m2, 1, 2) != null and str(_btn_at(m2, 1, 2).tooltip_text) == "重看这一场")
	m2.queue_free()
	await _frames(3)


# ⑥ ─────────────────────────────────────────────────────────────
func _t_mainmenu_door() -> void:
	print("── ⑥ 主菜单周六那扇门 ──")
	## ★不设成当前场景: 主菜单开场可能自己换场景(那会把它自己释放掉); 要按门那一刻才把它设成当前场景。
	var mm: Node = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(mm)
	await _frames(3)
	var mon := P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	var sat := mon + 5 * 86400 + 12 * 3600
	var wed := mon + 2 * 86400 + 12 * 3600
	_ok("⑥ 分母: 那一刻是周六闯关赛", P2C.phase_at_utc(sat) == P2C.PHASE_GAUNTLET)
	## ★2026-10-06 赛程从七格横条换成整页四张卡: 那扇门挂在**闯关赛那张卡**上。
	##   建真卡(`_week_card(week_card_info(...))`)再找按钮 —— 量的是画出来的东西, 不只问数据。
	var close_sat := P2C.gauntlet_close_ts(mon) + 600
	var blk2: Node = mm._week_card(mm.week_card_info(P2C.PHASE_GAUNTLET, close_sat))
	var d2: Button = blk2.find_child("GauntletBoardDoor", true, false) as Button
	var t2 := _labels_text(blk2)
	var fin2: Dictionary = mm.week_card_info(P2C.PHASE_FINALS, close_sat)
	_ok("⑥ 周六收盘后也还是门(正是看结果的时候), 卡上写「今日已截止」、决赛日那张写明天的开始时刻",
		d2 != null and t2.find("今日已截止") >= 0 and t2.find("全场赛况") >= 0 and str(fin2["time"]).ends_with("开始"),
		"%s · 决赛日那张「%s」" % [t2, str(fin2["time"])])
	blk2.free()
	var nd: Node = mm._week_card(mm.week_card_info(P2C.PHASE_GAUNTLET, wed))
	_ok("⑥ 平日(周三)不是门", nd.find_child("GauntletBoardDoor", true, false) == null)
	nd.free()
	var blk: Node = mm._week_card(mm.week_card_info(P2C.PHASE_GAUNTLET, sat))
	var door: Button = blk.find_child("GauntletBoardDoor", true, false) as Button
	_ok("⑥ ★周六: 闯关赛那张卡上有门(按钮)", door != null, str(blk))
	if door == null:
		return
	var tx := _labels_text(blk)
	_ok("⑥ 卡上仍是截止倒计时 + 本地截止时刻, 门上写「全场赛况」",
		tx.find("距截止") >= 0 and tx.find("截止") >= 0 and str(door.text) == "全场赛况", tx)
	_ok("⑥ 门高度 = 周日那扇门(触控下限 81)", door.custom_minimum_size.y >= 81.0)
	var conns: Array = []
	for c in door.pressed.get_connections():
		conns.append(str((c["callable"] as Callable).get_method()))
	_ok("⑥ 分母: 门接了处理函数", conns.has("_open_gauntlet_board"), str(conns))
	## 按下去(手指点的那个信号) ⇒ 真换到赛况板
	mm.add_child(blk)
	get_tree().current_scene = mm
	await _frames(2)
	door.pressed.emit()
	var bs: Node = await _wait_scene("GauntletBoardScene.gd")
	_ok("⑥ ★★点门 ⇒ 真进了赛况板", bs != null)
	await _frames(5)
	_all_sections_ran = true


func _finish() -> void:
	_ok("★分母: 六段都走到了最后一条(没有被中途打断)", _all_sections_ran)
	print("")
	print("  (共 %d 条断言 · 用了 %d 帧)" % [_n, Engine.get_process_frames()])
	print("ALL PASS — 周末看回放" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
