extends Node
## verify_stream_referee_paths.gd — 逐帧直播 2026-10-20 三条接线(方案书 docs/plans/20261019-服务器逐帧直播.md §4.1 / §5):
##   ③ 裁判局识别: 取录像时多选 `matches.result`, 带 `referee: true` 的一行一律按「已知裁判局」⇒ **裁判局永不本机重算**
##   ④ 周六「观赛」正在算的裁判局: 赛况板问 `referee_live_gauntlet`(20261020 迁移, 只写文件), 点「观赛」播状态流(边算边播, 无操作条)
##   ⑤ 旧裁判局(开流之前算的)按需补流: 没有流 ⇒ `referee_request_restream` 排队 ⇒ 进场「画面生成中」⇒ 块按 404 退避等, 到了就播
##
## 全程走产品入口(ReplayFetcher.open / open_finals / GauntletBoardScene 真场景), Supabase 走注入传输(不连网),
##   状态流走本进程的最小 HTTP 服务(tests/_stream_http.gd); 流本身 = 裁判程序在本进程真算一局三路打满时录下的。
##
## 段落:
##   K 纯函数: 查询串带 result、回包认出 referee、直播列表 / 补流回包的解析
##   F 裁判局识别 + 补流: F1 有流 ⇒ 播流; F2 没流 ⇒ 补流请求一次 + 进场「画面生成中」+ 流到了播完(sim 0、从没进 play 模式);
##     F3 本机局(没有 referee 标记)没流 ⇒ 老路(play 模式); F4 补流请求 404 / F5 补过且失败 ⇒「画面无法播放」、不进场;
##     F6 本机缓存带 `.ref` ⇒ 仍按裁判局(不重算), 去掉 `.ref` ⇒ 老路; F7 周日 finals_replay 回 referee ⇒ 同样不重算
##   G 赛况板: G1 正在算的裁判局出「正在打」卡(不写胜负; 版本不同灰签); G2 点「观赛」⇒ stream 模式、会话 live、没有操作条;
##     G3 服务器还没算完(只到 3 块、没有 end.json)⇒ 停在「同步中」, 不判没有、不报错; G4 算完 ⇒ 播到结尾、收尾卡揭晓胜方、不报全场时长;
##     G5 离场还原 GameState; G6 列表 404 ⇒ 没有裁判局卡、不报错; G7 开关关 ⇒ 不问列表
##   S 迁移 SQL 静态: 文件在、CRLF、schema.sql 末尾逐字同一段(只一次); 权限(anon 不可 / authenticated 可 / 裁判机两个只给 service_role);
##     列表函数不回快照整列; finals_replay 最后一版回 referee; 补流任务单键名 = 轮询器读的那几个

const SB := preload("res://scripts/net/supabase.gd")
const MF := preload("res://scripts/net/match_fetch.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const RF := preload("res://scripts/systems/replay/replay_fetcher.gd")
const SW := preload("res://scripts/systems/replay/stream_watch.gd")
const RC := preload("res://scripts/scenes/battle/replay_controls.gd")
const GBS := preload("res://scripts/scenes/GauntletBoardScene.gd")
const H := preload("res://tests/_stream_http.gd")
const J := preload("res://tests/_stream_jobs.gd")
const P := preload("res://tests/_stream_play.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RB_PATH := "res://scripts/scenes/RealtimeBattle3DScene.gd"
const BOARD_SCENE := "res://scenes/GauntletBoard.tscn"
const MIG := "res://server/supabase/migrations/20261020_referee_live_list.sql"
const SCHEMA := "res://server/supabase/schema.sql"
const POLLER := "res://server/referee/referee_poller.py"
const MARK_BEGIN := "-- >>> BEGIN referee_live_list 20261020 >>>"
const MARK_END := "-- <<< END referee_live_list 20261020 <<<"
const ME := "11111111-2222-4333-8444-555555555555"
const MID2 := "7a1b2c3d-4e5f-4a60-8b7c-9d0e1f2a3b4c"
const MID3 := "7a1b2c3d-4e5f-4a60-8b7c-9d0e1f2a3b4d"

var _fail := 0
var _n := 0
var _gs
var _http: Node = null
var _hits := {}
var _bodies := {}
var _mid := ""
var _b64 := ""
var _chunks: Array = []
var _meta: Dictionary = {}
var _seed := 0
var _row_referee := true
var _finals_referee := true
var _restream_mode := "ok"
var _live_mode := "rows"
var _live_rows: Array = []


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


func _wait(pred: Callable, ms: int = 15000) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		if pred.call():
			return true
		await get_tree().process_frame
	return pred.call()


func _hit(name: String) -> int:
	return int(_hits.get(name, 0))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 120
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_gs = get_node_or_null("/root/GameState")
	_gs.tutorial_active = false
	_gs.test_mode = true
	_gs.onboarded = true
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	_t_sql()
	var job: Dictionary = J.mirror(_gs)
	var nat: Dictionary = await P.record_referee(self, job, func(_n2: int) -> bool: return false)
	var res: Dictionary = nat["res"]
	_chunks = res.get("stream_chunks", [])
	_meta = (res.get("stream", {}) as Dictionary).duplicate()
	_b64 = str(res.get("replay_b64", ""))
	_mid = str(job["match_id"])
	_seed = int(nat["seed"])
	_ok("分母 · 裁判程序算完一局三路打满并录流(%d 块 / %d 步)" % [_chunks.size(), int(_meta.get("steps", 0))],
		bool(res.get("ok", false)) and _chunks.size() > 100 and _b64 != "")
	_t_pure()
	## 网络: 注入传输 + 本机状态流服务; 开关开(周六裁判 + 逐帧直播)
	var sat: int = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 5 * 86400 + 12 * 3600
	P2C.now_override_ts = sat
	_http = H.new()
	add_child(_http)
	_ok("分母 · 本机状态流服务起来了", _http.start())
	OS.set_environment(SW.ENV_BASE, _http.base())
	OS.set_environment(SB.ENV_URL, "http://referee.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "referee-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._token = "tok"
	_gs.account_id = ME
	_set_flags(true)
	_ok("分母 · 开关开(stream_on, stream_version = 本机版本)", RN.stream_on())
	## ★入口会 change_scene: 当前场景不能是门禁自己(换场景会把门禁释放掉)⇒ 先放一个占位场景
	var ph := Node.new()
	ph.name = "Placeholder"
	get_tree().root.add_child(ph)
	get_tree().current_scene = ph
	await _t_f()
	await _t_g()
	_cleanup()
	_finish()


func _set_flags(stream: bool) -> void:
	_gs.referee_flags = {RN.K_FINALS: true, RN.K_GAUNTLET: true, RN.K_STREAM: stream, RN.K_STREAM_VER: ReplayRecorder.client_version()}


func _cleanup() -> void:
	P2C.now_override_ts = 0
	OS.set_environment(SB.ENV_URL, " ")
	ProjectSettings.set_setting(SB.SETTING_KEY, "")
	SB._transport_for_test = Callable()
	SB._token = ""
	OS.set_environment(SW.ENV_BASE, "")
	_gs.referee_flags = {}


func _transport(m, u, _h, b, cb) -> void:
	var url := str(u)
	if url.find("/auth/v1/") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({
			"access_token": "tok", "refresh_token": "r2", "expires_in": 3600, "user": {"id": ME, "is_anonymous": true}})})
		return
	var i := url.find("/rest/v1/rpc/")
	var rpc := url.substr(i + 13).split("?")[0] if i >= 0 else ""
	if rpc != "":
		_hits[rpc] = _hit(rpc) + 1
		_bodies[rpc] = str(b)
	match rpc:
		"referee_flags":
			cb.call({"ok": true, "code": 200, "body": JSON.stringify(_gs.referee_flags)})
			return
		"referee_request_restream":
			match _restream_mode:
				"404":
					cb.call({"ok": true, "code": 404, "body": "{}"})
				"failed":
					cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "failed"})})
				_:
					cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "pending"})})
			return
		"referee_live_gauntlet":
			if _live_mode == "404":
				cb.call({"ok": true, "code": 404, "body": "{}"})
			else:
				cb.call({"ok": true, "code": 200, "body": JSON.stringify(_live_rows)})
			return
		"finals_replay":
			cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "match_id": _mid, "replay": _b64, "referee": _finals_referee})})
			return
	if str(m) == "GET" and url.find("/rest/v1/matches?") >= 0 and url.find("match_id=eq." + _mid) >= 0:
		_hits["matches_get"] = _hit("matches_get") + 1
		_bodies["matches_get"] = url
		var row := {"match_id": _mid, "replay": _b64}
		if url.find("result") >= 0:
			row["result"] = {"won": true, "referee": true} if _row_referee else {"won": true}
		cb.call({"ok": true, "code": 200, "body": JSON.stringify([row])})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


func _leave() -> void:
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	await _frames(4)


func _is_battle(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() != null and str((n.get_script() as Script).resource_path) == RB_PATH


func _battle_now() -> Node:
	var cs := get_tree().current_scene
	return cs if _is_battle(cs) else null


func _clear_cache() -> void:
	for ext in [".rpl", RF.REF_EXT]:
		var p: String = ReplayRecorder.SAVE_DIR + _mid + ext
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _open(finals: bool = false) -> Array:
	var got: Array = []
	if finals:
		RF.open_finals(get_tree(), 1, 0, 1, 0, func(c: String, msg: String) -> void: got.append([c, msg]), "", {})
	else:
		RF.open(get_tree(), _mid, func(c: String, msg: String) -> void: got.append([c, msg]), "", {"l": "甲方", "r": "乙方"})
	await _wait(func() -> bool: return not got.is_empty(), 15000)
	return got


func _play_to_end(b: Node) -> Array:
	var p: StreamPlayer = b._replay.player
	var emits := [0]
	b.sim_stepped.connect(func() -> void: emits[0] += 1)
	p.speed = 40.0
	await _wait(func() -> bool: return not is_instance_valid(b) or p.state == "ended" or p.state == "error", 120000)
	return [int(b._sim_step_n), emits[0], p.sim_calls]


func _labels_text(root: Node) -> Array:
	var out: Array = []
	for c in root.find_children("*", "Label", true, false):
		if (c as Label).is_visible_in_tree():
			out.append((c as Label).text)
	return out


# K ─────────────────────────────────────────────────────────────
func _t_pure() -> void:
	print("── K 纯函数 ──")
	_ok("K ★取录像的查询多选 result(认裁判局)", MF.match_fetch_query(_mid) == "match_id=eq.%s&select=match_id,replay,result" % _mid,
		MF.match_fetch_query(_mid))
	var rows_ref := JSON.stringify([{"match_id": _mid, "replay": "eJw=", "result": {"won": true, "referee": true}}])
	var rows_loc := JSON.stringify([{"match_id": _mid, "replay": "eJw=", "result": {"won": true}}])
	var rows_str := JSON.stringify([{"match_id": _mid, "replay": "eJw=", "result": {"referee": "true"}}])
	_ok("K ★matches 行带 referee:true ⇒ referee; 本机局(没有这个键)/ 不是布尔 ⇒ 不是",
		bool(MF.parse_fetched_match(true, 200, rows_ref, _mid).get("referee", false))
		and not bool(MF.parse_fetched_match(true, 200, rows_loc, _mid).get("referee", true))
		and not bool(MF.parse_fetched_match(true, 200, rows_str, _mid).get("referee", true)))
	_ok("K finals_replay 回 referee ⇒ referee; 旧服务端(没有这个键)⇒ 不是",
		bool(MF.parse_finals_replay(true, 200, JSON.stringify({"ok": true, "match_id": _mid, "replay": "eJw=", "referee": true})).get("referee", false))
		and not bool(MF.parse_finals_replay(true, 200, JSON.stringify({"ok": true, "match_id": _mid, "replay": "eJw="})).get("referee", true)))
	var lv: Dictionary = RN.parse_live(true, 200, JSON.stringify([
		{"match_id": MID2, "seed": 2000023.0, "client_version": "x", "lp": {"name": "甲"}, "rp": {"name": "乙"}},
		{"match_id": "not-a-uuid", "seed": 5}, {"match_id": MID3, "seed": 0}]))
	var lr: Array = lv.get("rows", [])
	_ok("K ★直播列表: 认 uuid + 种子 > 0 的行, 种子变整数、打上 referee", lr.size() == 1 and int(lr[0]["seed"]) == 2000023
		and lr[0]["seed"] is int and bool(lr[0]["referee"]), str(lr))
	_ok("K 直播列表 404 ⇒ unavailable(服务端没部署)", str(RN.parse_live(true, 404, "").get("reason", "")) == "unavailable")
	_ok("K 补流回包: ok/status、服务端 reason、404 ⇒ unavailable",
		RN.parse_restream(true, 200, JSON.stringify({"ok": true, "status": "pending"})) == {"err": "", "status": "pending"}
		and str(RN.parse_restream(true, 200, JSON.stringify({"ok": false, "reason": "not_referee"})).get("err", "")) == "not_referee"
		and str(RN.parse_restream(true, 404, "").get("err", "")) == "unavailable")


# F ─────────────────────────────────────────────────────────────
func _t_f() -> void:
	print("── F 裁判局识别 + 补流 ──")
	## F1 有流 ⇒ 播流(赛况板 / 战绩页入口, 调用方不知道是不是裁判局)
	_clear_cache()
	_row_referee = true
	_http.put(_mid, _chunks, _meta)
	var got := await _open()
	var b: Node = _battle_now() if await _wait(func() -> bool: return _battle_now() != null, 15000) else null
	_ok("F1 有流 ⇒ stream 模式、会话 replay(有操作条)", str(got) == str([["", ""]]) and b != null and str(b._replay.mode) == "stream"
		and str(SW.current.get("kind", "")) == SW.KIND_REPLAY and b._replay.player.controls, str(got))
	_ok("F1 分母 · 取录像那一次的查询带 result", str(_bodies.get("matches_get", "")).find("select=match_id,replay,result") >= 0)
	await _leave()
	## F2 没流 ⇒ 补流 ⇒ 「画面生成中」⇒ 流到了播完
	_clear_cache()
	_http.streams.erase(_mid)
	_restream_mode = "ok"
	var rs0 := _hit("referee_request_restream")
	got = await _open()
	b = _battle_now() if await _wait(func() -> bool: return _battle_now() != null, 15000) else null
	_ok("F2 ★没有流 ⇒ 请求补流恰好一次(p_match_id = 这一场)", _hit("referee_request_restream") == rs0 + 1
		and str(_bodies.get("referee_request_restream", "")).find(_mid) >= 0, str(_bodies.get("referee_request_restream", "")))
	_ok("F2 ★★进场是 stream 模式(不是本机重算的 play 模式), 会话标了补流", b != null and str(b._replay.mode) == "stream"
		and b._replay.player != null and bool(SW.current.get("restream", false)) and ReplayRecorder.pending_play.is_empty(), str(got))
	if b == null or b._replay.player == null:
		return
	var p: StreamPlayer = b._replay.player
	await _frames(20)
	_ok("F2 ★块还没生成 ⇒ 屏上「%s」(状态 %s)" % [SW.TXT_GENERATING, p.state], p.status_text() == SW.TXT_GENERATING
		and p.state == "buffering" and p.applied < 0)
	_ok("F2 缓存旁边记下了裁判局(.ref)", RF.referee_cached(_mid))
	_http.put(_mid, _chunks, _meta)
	var r: Array = await _play_to_end(b)
	_ok("F2 ★流到了 ⇒ 接着播到结尾(应用 %d / %d 步, 状态 %s %s)" % [p.steps_applied, int(_meta.get("steps", 0)), p.state, p.err],
		p.state == "ended" and p.steps_applied == int(_meta.get("steps", -1)))
	_ok("F2 ★★整局 sim 0 次(步号 %d / sim_stepped %d / pre_step %d)" % r, int(r[0]) == 0 and int(r[1]) == 0 and int(r[2]) == 0)
	await _leave()
	_ok("F2 离场还原 GameState(备份清掉)、会话清掉", not ReplayRecorder._has_backup and SW.current.is_empty())
	## F3 本机局(行上没有 referee)、没流 ⇒ 老路
	_clear_cache()
	_http.streams.erase(_mid)
	_row_referee = false
	rs0 = _hit("referee_request_restream")
	got = await _open()
	b = _battle_now() if await _wait(func() -> bool: return _battle_now() != null, 15000) else null
	_ok("F3 ★本机局(没有 referee 标记)没有流 ⇒ 老路: play 模式(本机重算)、不请求补流", b != null and str(b._replay.mode) == "play"
		and _hit("referee_request_restream") == rs0, str(got))
	await _leave()
	_row_referee = true
	## F4 补流请求 404(服务端没部署) / F5 补过且失败 ⇒ 不进场、「画面无法播放」
	for mode in ["404", "failed"]:
		_clear_cache()
		_restream_mode = mode
		rs0 = _hit("referee_request_restream")
		got = await _open()
		await _frames(10)
		_ok("F%s ★补流%s ⇒ 「%s」、不进场、不重算(%s)" % ["4" if mode == "404" else "5", "请求 404" if mode == "404" else "失败过", StreamPlayer.TXT_ERROR, str(got)],
			got.size() == 1 and str(got[0][0]) == "no_stream" and str(got[0][1]) == StreamPlayer.TXT_ERROR
			and _battle_now() == null and ReplayRecorder.pending_play.is_empty() and not ReplayRecorder._has_backup
			and _hit("referee_request_restream") == rs0 + 1)
	## F6 本机缓存: 带 .ref ⇒ 裁判局; 去掉 .ref ⇒ 老路
	_restream_mode = "404"
	RF._cache(_mid, RF.decode_b64(_b64), true)
	var mg0 := _hit("matches_get")
	rs0 = _hit("referee_request_restream")
	got = await _open()
	await _frames(10)
	_ok("F6 ★本机缓存带 .ref ⇒ 不去服务端取、仍按裁判局(请求补流, 不重算)", _hit("matches_get") == mg0
		and _hit("referee_request_restream") == rs0 + 1 and _battle_now() == null and str(got[0][0]) == "no_stream", str(got))
	DirAccess.remove_absolute(ReplayRecorder.SAVE_DIR + _mid + RF.REF_EXT)
	got = await _open()
	b = _battle_now() if await _wait(func() -> bool: return _battle_now() != null, 15000) else null
	_ok("F6 去掉 .ref(本机局的缓存)⇒ 老路 play 模式", b != null and str(b._replay.mode) == "play", str(got))
	await _leave()
	## F7 周日对阵图(调用方不说 known): finals_replay 回 referee ⇒ 不重算
	_clear_cache()
	_finals_referee = true
	rs0 = _hit("referee_request_restream")
	got = await _open(true)
	await _frames(10)
	_ok("F7 ★周日 finals_replay 回 referee ⇒ 没有流时请求补流、不重算", _hit("referee_request_restream") == rs0 + 1
		and _battle_now() == null and str(got[0][0]) == "no_stream", str(got))
	_clear_cache()
	_restream_mode = "ok"


# G ─────────────────────────────────────────────────────────────
func _open_board() -> Node:
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	var n: Node = (load(BOARD_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(n)
	get_tree().current_scene = n
	await _frames(4)
	return n


func _live_row(id: String, ver: String, ln: String, rn: String) -> Dictionary:
	var now := Time.get_datetime_string_from_unix_time(P2C.now_utc()) + "Z"
	return {"match_id": id, "started_at": now, "updated_at": now, "client_version": ver, "seed": _seed,
		"lp": {"name": ln, "avatar": "basic", "id": "", "tag": ""}, "rp": {"name": rn, "avatar": "stone", "id": "", "tag": ""}}


func _t_g() -> void:
	print("── G 赛况板 · 正在算的裁判局 ──")
	_live_mode = "rows"
	_live_rows = [_live_row(MID2, ReplayRecorder.client_version(), "甲方直播", "乙方直播"), _live_row(MID3, "0.0.1", "旧版丙", "旧版丁")]
	_http.put(MID2, _chunks, _meta, 3, false)
	var la0 := _hit("referee_live_gauntlet")
	var bs: Node = await _open_board()
	await _wait(func() -> bool: return is_instance_valid(bs) and (bs.live_games as Array).size() >= 2, 10000)
	var cards: Array = bs.find_children(GBS.N_LIVE_CARD + "*", "", true, false)
	_ok("G1 分母 · 进赛况板就问了一次列表", _hit("referee_live_gauntlet") == la0 + 1)
	var mine: Node = null
	var old: Node = null
	var bad_txt := 0
	for c in cards:
		if str((c as Node).get_meta("match_id", "")) == MID2:
			mine = c
		if str((c as Node).get_meta("match_id", "")) == MID3:
			old = c
		for t in _labels_text(c):
			if str(t).contains("获胜") or str(t).contains("胜利"):
				bad_txt += 1
	_ok("G1 ★正在算的两场都出「正在打」卡、不写胜负", cards.size() == 2 and mine != null and old != null and bad_txt == 0,
		"卡 %d" % cards.size())
	var lb: Button = mine.find_child(GBS.N_LIVE_BTN, true, false) as Button if mine != null else null
	_ok("G1 本机版本那一场有「观赛」; 版本不同那一场没有(灰签)", lb != null and lb.text == "观赛" and old != null
		and old.find_children(GBS.N_LIVE_BTN, "Button", true, false).is_empty() and old.find_children("VerOff", "", true, false).size() == 1)
	if lb == null:
		return
	lb.pressed.emit()
	var b: Node = _battle_now() if await _wait(func() -> bool: return _battle_now() != null, 15000) else null
	_ok("G2 ★点「观赛」⇒ stream 模式、会话 live(正在算)", b != null and str(b._replay.mode) == "stream" and b._replay.player != null
		and str(SW.current.get("kind", "")) == SW.KIND_LIVE and str(SW.current.get("id", "")) == MID2,
		str(bs.last_replay_code) + " " + str(bs.last_replay_msg) if is_instance_valid(bs) else "")
	if b == null or b._replay.player == null:
		return
	var p: StreamPlayer = b._replay.player
	await _frames(6)
	_ok("G2 ★观赛没有操作条(暂停 / 倍速 / 进度槽), 只有「退出」", not p.controls and b.find_child(RC.N_PAUSE, true, false) == null
		and b.find_child(RC.N_TRACK, true, false) == null and b.find_child(RC.N_EXIT, true, false) != null)
	_ok("G2 块来源 = 边算边播(没说「早算完了」⇒ 404 永不判没有)、GameState 已备份 + 存盘空转",
		p.src is StreamSource.Http and not bool(p.src.finished) and ReplayRecorder._has_backup and bool(_gs.test_mode))
	## G3 服务器还在算: 只到 3 块、没有 end.json
	var t0 := Time.get_ticks_msec()
	await _wait(func() -> bool: return Time.get_ticks_msec() - t0 > 4000, 6000)
	_ok("G3 ★服务器还在算(只到 3 块) ⇒ 停在「同步中」、没有报错、来源没判「没有」(状态 %s / 来源 %s / 已拉 %d 块)" % [p.state, str(p.src.state), int(p.src.fetched())],
		(p.state == "buffering" or p.state == "stalled") and p.status_text() == StreamPlayer.Live.TXT_SYNC
		and str(p.src.state) == StreamSource.Http.ST_FETCHING and int(p.src.fetched()) == 3)
	_http.put(MID2, _chunks, _meta)
	var r: Array = await _play_to_end(b)
	var ui = b._hud._replay_ui
	await _wait(func() -> bool: return ui != null and ui.card != null, 6000)
	var ct: Array = _labels_text(ui.card) if ui != null and ui.card != null else []
	_ok("G4 ★算完 ⇒ 播到结尾(应用 %d / %d 步), sim 0 次" % [p.steps_applied, int(_meta.get("steps", 0))],
		p.state == "ended" and p.steps_applied == int(_meta.get("steps", -1)) and int(r[0]) == 0 and int(r[1]) == 0 and int(r[2]) == 0)
	_ok("G4 ★收尾卡揭晓胜方(名字来自列表)、不报全场时长 %s" % str(ct), (str(ct).contains("甲方直播 获胜") or str(ct).contains("乙方直播 获胜"))
		and not str(ct).contains("全场"))
	await _leave()
	_ok("G5 离场 ⇒ GameState 还原(备份清掉)、会话清掉", not ReplayRecorder._has_backup and SW.current.is_empty())
	## G6 列表 404
	_live_mode = "404"
	la0 = _hit("referee_live_gauntlet")
	bs = await _open_board()
	await _wait(func() -> bool: return _hit("referee_live_gauntlet") > la0, 5000)
	await _frames(4)
	_ok("G6 列表 404(服务端没部署)⇒ 没有裁判局卡、不报错", _hit("referee_live_gauntlet") == la0 + 1
		and bs.find_children(GBS.N_LIVE_CARD + "*", "", true, false).is_empty() and str(bs.load_state) == "ok", str(bs.load_state))
	## G7 开关关
	_set_flags(false)
	_live_mode = "rows"
	la0 = _hit("referee_live_gauntlet")
	bs = await _open_board()
	await _frames(20)
	_ok("G7 ★开关关 ⇒ 不问正在算的裁判局", _hit("referee_live_gauntlet") == la0 and bs.find_children(GBS.N_LIVE_CARD + "*", "", true, false).is_empty())
	_set_flags(true)
	await _leave()


# S ─────────────────────────────────────────────────────────────
func _seg(t: String) -> String:
	var a := t.find(MARK_BEGIN)
	var b2 := t.find(MARK_END)
	return t.substr(a, b2 + MARK_END.length() - a) if a >= 0 and b2 > a else ""


func _fn(t: String, name: String) -> String:
	var a := t.find("create or replace function public.%s(" % name)
	if a < 0:
		return ""
	var b2 := t.find("$$;", t.find("$$", a) + 2)
	return t.substr(a, b2 - a) if b2 > a else ""


func _t_sql() -> void:
	print("── S 迁移 SQL 静态 ──")
	var raw := FileAccess.get_file_as_bytes(MIG)
	var mig := raw.get_string_from_utf8()
	var sch := FileAccess.get_file_as_string(SCHEMA)
	_ok("分母 · 迁移文件与 schema.sql 都读得到", mig.length() > 2000 and sch.length() > 100000, "%d / %d 字" % [mig.length(), sch.length()])
	var crlf := mig.count("\r\n")
	_ok("S 迁移文件行尾 CRLF(与 schema.sql 相同), 首尾标记各一", crlf > 50 and crlf == mig.count("\n")
		and mig.count(MARK_BEGIN) == 1 and mig.count(MARK_END) == 1)
	var seg := _seg(mig)
	_ok("S ★schema.sql 末尾逐字同一段(只一次)", seg != "" and sch.count(MARK_BEGIN) == 1 and _seg(sch) == seg
		and sch.strip_edges().ends_with(MARK_END))
	var live := _fn(seg, "referee_live_gauntlet")
	_ok("S ★列表函数: anon 不可、authenticated 可", live != "" and seg.contains("revoke all on function public.referee_live_gauntlet() from public, anon;")
		and seg.contains("grant execute on function public.referee_live_gauntlet() to authenticated;")
		and not seg.contains("referee_live_gauntlet() to anon"))
	_ok("S ★列表函数不回快照整列(只取 profile 的名字 / 头像 / #ID)", live.contains("'lp', jsonb_build_object(")
		and not live.contains("j.a_snapshot,") and not live.contains("j.b_snapshot,") and not live.contains("'leaders'")
		and not live.contains("lane_assign") and live.count("_snapshot->'profile'->>") == 8)
	_ok("S 列表只取本周、周六闯关、正在算(claimed、租期内)", live.contains("kind = 'gauntlet'") and live.contains("status = 'claimed'")
		and live.contains("season_week = wk") and live.contains("lease_sec"))
	_ok("S ★补流请求: anon 不可、authenticated 可; 裁判机两个只给 service_role",
		seg.contains("revoke all on function public.referee_request_restream(uuid) from public, anon;")
		and seg.contains("grant execute on function public.referee_request_restream(uuid) to authenticated;")
		and seg.contains("grant execute on function public.referee_claim_restream(text, text[], int) to service_role;")
		and seg.contains("grant execute on function public.referee_restream_done(uuid, text, boolean, text, boolean) to service_role;")
		and not seg.contains("referee_claim_restream(text, text[], int) to authenticated"))
	var done := _fn(seg, "referee_restream_done")
	_ok("S ★补流写回不碰 matches / 赛果 / 账本", done != "" and not done.contains("matches") and not done.contains("finals_results")
		and not done.contains("gauntlet_records") and not done.contains("gauntlet_ghosts"))
	_ok("S 补流只认裁判局(matches.result->>'referee')", _fn(seg, "referee_request_restream").contains("m.result->>'referee'"))
	var claim := _fn(seg, "referee_claim_restream")
	var py := FileAccess.get_file_as_string(POLLER)
	var miss: Array = []
	for k in ["task", "expect_winner", "expect_digest", "match_id", "client_version"]:
		if not claim.contains("'%s', " % k) or not py.contains("\"%s\"" % k):
			miss.append(k)
	_ok("S ★补流任务单的键 = 轮询器读的键(task / expect_winner / expect_digest …)", claim != "" and miss.is_empty()
		and claim.contains("'restream'") and py.contains("TASK_RESTREAM = \"restream\""), "缺 " + str(miss))
	var wait_ok := true
	for st in SW.RESTREAM_WAIT:
		if not seg.contains("'%s'" % st):
			wait_ok = false
	_ok("S 客户端认的补流状态 ⊆ 表的状态", wait_ok)
	var a0 := sch.find(MARK_BEGIN)
	var last := sch.rfind("create or replace function public.finals_replay(")
	_ok("S ★schema.sql 里最后一个 finals_replay 落在本段、回 referee(整份重放时生效的是新版)", last > a0 and a0 > 0
		and _fn(sch.substr(last), "finals_replay").contains("'referee', coalesce(res->>'referee', 'false') = 'true'"))


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 裁判局永不本机重算 / 补流 / 观赛正在算的裁判局" if _fail == 0 and _n >= 40 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
