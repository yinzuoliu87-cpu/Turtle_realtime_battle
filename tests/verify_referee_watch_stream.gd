extends Node
## verify_referee_watch_stream.gd — 逐帧直播 S5 接线: 开关 `stream_on` 开着时, 「看服务器算的局」的入口一律播状态流,
##   手机一步 sim 都不跑(方案书 docs/plans/20261019-服务器逐帧直播.md 验收清单「周六闯关接线」/ §4 接线 / §5 录像)。
##
## 全程走产品自己的入口(匹配屏真场景 / ReplayFetcher / 对阵图那条 open_finals), Supabase 走注入传输(不连网),
##   状态流走本进程的最小 HTTP 服务(tests/_stream_http.gd, 口径照 server/stream/README.md 的 Caddy);
##   「服务器」那一局 = 裁判程序(与裁判机同一套代码)按客户端真交上来的两份快照真算, 同时录流(块留在内存)。
##
## 段落:
##   A 周六闯关(匹配屏 → referee_run): 账在播之前按服务器记完 ⇒ 进战斗场是 **stream 模式**(不是重算的 play 模式),
##     会话 = 裁判局 + 服务器结果; 引擎每帧驱动播完整局 ⇒ `_sim_step` 0 次; 离场 ⇒ GameState 还原成记完账的那一份
##   B 周六闯关 · 服务器没有这份流 ⇒ 不进战斗场、也不重算, 屏上「结果 · 画面无法播放」, 账照记
##   C 战绩页 / 赛况板「观看」(ReplayFetcher.open)⇒ stream 模式, sim 0
##   D 周日对阵图(open_finals, 自己那一场 = 已知裁判局): 有流 ⇒ stream; 没有流 ⇒ 不播不算
##   E 开关关 ⇒ 同一个入口照旧本机重算(play 模式), 状态流服务器一个请求都没收到
## 反向验证见方案书 §4.1。
## ── 2026-10-27 周六改在线排队: 交阵容换成进队 gauntlet_queue_join, 假服务器让它当场配上(我是 a); 之后一字不变。
##   量的需求(播服务器那一份状态流、不本机重算)没变, 只改了「交」的接口; 版本从请求头取(请求体里不再有 p_client_version)。

const SB := preload("res://scripts/net/supabase.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const RF := preload("res://scripts/systems/replay/replay_fetcher.gd")
const SW := preload("res://scripts/systems/replay/stream_watch.gd")
const H := preload("res://tests/_stream_http.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RB_PATH := "res://scripts/scenes/RealtimeBattle3DScene.gd"   # 不 preload: 与本文件其它 preload 一起会让 class_name 解析顺序出环
const MMK_SCENE := "res://scenes/Matchmaking.tscn"
const ME := "11111111-2222-4333-8444-555555555555"
const MID := "5b2c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"

var _fail := 0
var _n := 0
var _gs
var _http: Node = null
var _hits := {}
var _submit_body: Dictionary = {}
var _srv_b: Dictionary = {}       # 门禁当服务器: 服务端挑的对手(机器人池那一份)
const BP := preload("res://scripts/referee/bot_pool.gd")
var _job := 300
var _done := false
var _srv_won := false
var _srv_gw := 0
var _srv_gl := 0
var _rec_b64 := ""
var _rec: Dictionary = {}
var _chunks: Array = []
var _meta: Dictionary = {}
var _flags := {}


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
	Engine.max_fps = 120             # 判据按墙钟等; 钉帧率 ⇒ 帧预算可预期
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	OS.set_environment("TURTLE_SEED", "")
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	var sat: int = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 5 * 86400 + 12 * 3600
	P2C.now_override_ts = sat
	_setup_gs()
	_http = H.new()
	add_child(_http)
	var up: bool = _http.start()
	_ok("分母: 本机状态流服务起来了(端口 %d)" % _http.port, up)
	OS.set_environment(SW.ENV_BASE, _http.base())
	OS.set_environment(SB.ENV_URL, "http://referee.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "referee-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._token = "tok"
	_set_flags(true)
	_ok("分母: 开关开(周六裁判 + 逐帧直播, stream_version = 本机版本)", RN.gauntlet_on() and RN.stream_on())
	await _t_a()
	if not _rec.is_empty():
		await _t_b()
		await _t_c()
		await _t_d()
		await _t_e()
	_cleanup()
	_finish()


func _set_flags(stream: bool) -> void:
	_flags = {RN.K_FINALS: true, RN.K_GAUNTLET: true, RN.K_STREAM: stream, RN.K_STREAM_VER: ReplayRecorder.client_version()}
	_gs.referee_flags = _flags.duplicate()


func _setup_gs() -> void:
	_gs.test_mode = true
	_gs.account_id = ME
	_gs.tutorial_active = false
	_gs.onboarded = true
	_gs.reset_dual_lane()
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	_gs.persistent_equipped = {}
	_gs.week_anchor_ts = P2C.week_anchor_utc(P2C.now_utc())
	_gs.promoted = true
	_gs.hearts = int(P2C.HEARTS_MAX)
	_gs.gauntlet_wins = 1
	_gs.gauntlet_losses = 0
	_gs.referee_pending = {}
	_gs.dual_active = true


func _cleanup() -> void:
	P2C.now_override_ts = 0
	OS.set_environment(SB.ENV_URL, " ")
	ProjectSettings.set_setting(SB.SETTING_KEY, "")
	SB._transport_for_test = Callable()
	SB._token = ""
	OS.set_environment(SW.ENV_BASE, "")
	_gs.referee_flags = {}
	_gs.referee_pending = {}


func _transport(m, u, _h, b, cb) -> void:
	var url := str(u)
	if url.find("/auth/v1/") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({
			"access_token": "tok", "refresh_token": "r2", "expires_in": 3600,
			"user": {"id": ME, "is_anonymous": true}})})
		return
	var i := url.find("/rest/v1/rpc/")
	var rpc := url.substr(i + 13).split("?")[0] if i >= 0 else ""
	if rpc != "":
		_hits[rpc] = _hit(rpc) + 1
	match rpc:
		"referee_flags":
			cb.call({"ok": true, "code": 200, "body": JSON.stringify(_flags)})
			return
		"gauntlet_queue_join":
			var j = JSON.parse_string(str(b))
			_submit_body = j if j is Dictionary else {}
			## 2026-10-27 起先进队: 门禁当服务器让它当场配上(我是 a), 对手从机器人池取一份(与 SQL 兜底同口径), 回卡片
			_srv_b = BP.one(maxi(int(_gs.season_total_battles), int(_gs.gauntlet_wins) + int(_gs.gauntlet_losses)),
				int(_gs.gauntlet_wins), int(_gs.gauntlet_losses), 0)
			_srv_b["gl_ts"] = int(Time.get_unix_time_from_system()) - 300
			cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "paired", "job_id": _job, "match_id": MID,
				"side": "a", "opp": {"profile": _srv_b["profile"], "leaders": _srv_b["leaders"]}})})
			return
		"referee_job_status":
			if not _done:
				cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "pending", "match_id": MID})})
				return
			cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "done", "match_id": MID,
				"won": _srv_won, "score": 0, "gw": _srv_gw, "gl": _srv_gl, "error": null})})
			return
		"finals_replay":
			cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "match_id": MID, "replay": _rec_b64})})
			return
	if str(m) == "GET" and url.find("/rest/v1/matches?") >= 0 and url.find("match_id=eq." + MID) >= 0:
		_hits["matches_get"] = _hit("matches_get") + 1
		cb.call({"ok": true, "code": 200, "body": JSON.stringify([{"match_id": MID, "replay": _rec_b64}])})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


func _open_mmk() -> Node:
	await _leave()
	var m: Node = (load(MMK_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	return m


func _leave() -> void:
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	await _frames(3)


func _status_text(m: Node) -> String:
	if m == null or not is_instance_valid(m):
		return ""
	var l := m.find_child("RefereeStatus", true, false) as Label
	return l.text if l != null else ""


func _is_battle(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() != null and str((n.get_script() as Script).resource_path) == RB_PATH


func _snap() -> Dictionary:
	return {"gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses), "coins": int(_gs.meta_deepsea_coins),
		"bt": int(_gs.battles_total), "mh": (_gs.match_history as Array).size()}


## 匹配屏 → 交阵容 → (门禁当服务器) → done。第一次由裁判程序真算并录流。返回是否交上去了。
func _submit_and_finish(m: Node) -> bool:
	_done = false
	var subs0 := _hit("gauntlet_queue_join")
	var got := await _wait(func() -> bool: return _hit("gauntlet_queue_join") > subs0)
	if not got:
		return false
	await _wait(func() -> bool: return _status_text(m) == RW.TXT_SETTLING, 5000)
	if _rec.is_empty():
		var job: Dictionary = JSON.parse_string(JSON.stringify({"v": 1, "job_id": _job, "match_id": MID, "mode": "gauntlet",
			"key": {"week": 1}, "seed": 2000023, "client_version": ReplayRecorder.client_version(),
			"a": _submit_body.get("p_snapshot", {}), "b": _srv_b}))
		var res: Dictionary = await RefereeRunner.run(self, job, Callable(), {"keep": true})
		_rec_b64 = str(res.get("replay_b64", ""))
		_chunks = res.get("stream_chunks", [])
		_meta = (res.get("stream", {}) as Dictionary).duplicate()
		var raw: PackedByteArray = RF.decode_b64(_rec_b64)
		_rec = ReplayRecorder.decode(raw) if not raw.is_empty() else {}
		_ok("分母: 裁判按交上来的快照算完一场并录流(%d 步 / %d 块)" % [int(res.get("steps", 0)), _chunks.size()],
			bool(res.get("ok", false)) and not _rec.is_empty() and _chunks.size() > 10 and int(_meta.get("chunks", 0)) == _chunks.size(),
			str(res.get("error", "")))
		if _rec.is_empty():
			return false
		_srv_won = bool(res.get("a_won", false))
	_srv_gw = int(_gs.gauntlet_wins) + (1 if _srv_won else 0)
	_srv_gl = int(_gs.gauntlet_losses) + (0 if _srv_won else 1)
	_done = true
	return true


## 战斗场里播状态流到结尾(引擎每帧驱动, 倍速只改每帧推几步)。返回 [sim 步号, sim_stepped 次数, pre_step 次数]。
func _play_stream_to_end(b: Node) -> Array:
	var p: StreamPlayer = b._replay.player
	var emits := [0]
	b.sim_stepped.connect(func() -> void: emits[0] += 1)
	p.speed = 40.0
	await _wait(func() -> bool: return not is_instance_valid(b) or p.state == "ended" or p.state == "error", 120000)
	return [int(b._sim_step_n), emits[0], p.sim_calls]


# A ─────────────────────────────────────────────────────────────
func _t_a() -> void:
	print("── A 周六闯关 · 开关开 ⇒ 播状态流 ──")
	_http.reqs.clear()
	var s0 := _snap()
	var m: Node = await _open_mmk()
	var sent := await _submit_and_finish(m)
	_ok("分母: 匹配屏交了阵容", sent)
	if not sent:
		return
	_http.put(MID, _chunks, _meta)
	var ok := await _wait(func() -> bool: return _is_battle(get_tree().current_scene), 30000)
	var b: Node = get_tree().current_scene if ok else null
	_ok("A ★进了战斗场, 是 stream 模式(不是本机重算的 play 模式)", b != null and str(b._replay.mode) == "stream"
		and b._replay.player != null and not b._replay.is_playing(), str(b._replay.mode) if b != null else "没进")
	if b == null or b._replay.player == null:
		return
	_ok("A 分母: 先问过 end.json、拉的是这一场(%d 个请求)" % _http.reqs.size(), _http.count(200, "/" + MID + "/end.json") >= 1
		and _http.count(200, "/" + MID + "/000000.bin") >= 0)
	_ok("A 会话 = 裁判局 + 服务器结果(%s)" % ("胜" if _srv_won else "负"), str(SW.current.get("kind", "")) == SW.KIND_REFEREE
		and bool((SW.current.get("result", {}) as Dictionary).get("won", not _srv_won)) == _srv_won and str(SW.current.get("id", "")) == MID)
	var s1 := _snap()
	_ok("A ★播之前账已按服务器记完(%d-%d、币、场次、战绩页)" % [_srv_gw, _srv_gl], int(s1["gw"]) == _srv_gw and int(s1["gl"]) == _srv_gl
		and int(s1["coins"]) == int(s0["coins"]) + int(P2C.GAUNTLET_COINS_PER_MATCH) and int(s1["bt"]) == int(s0["bt"]) + 1
		and int(s1["mh"]) == int(s0["mh"]) + 1)
	_ok("A 播的时候 GameState 是录像的开局状态(回放同一套备份)、存盘空转", ReplayRecorder._has_backup and bool(_gs.test_mode))
	var r: Array = await _play_stream_to_end(b)
	var p: StreamPlayer = b._replay.player
	_ok("分母 · A 播到结尾: 解了全部 %d 块、应用了 %d 步(状态 %s %s)" % [_chunks.size(), p.steps_applied, p.state, p.err],
		p.state == "ended" and p.chunks_decoded == _chunks.size() and p.steps_applied == int(_meta.get("steps", -1)))
	_ok("A ★★整局 _sim_step 一次都没跑(步号 %d / sim_stepped %d / pre_step %d)" % r, int(r[0]) == 0 and int(r[1]) == 0 and int(r[2]) == 0)
	await _leave()
	_ok("A 离场 ⇒ GameState 还原(备份清掉)、会话清掉、账还是服务器那一份", not ReplayRecorder._has_backup and SW.current.is_empty()
		and int(_gs.gauntlet_wins) == _srv_gw and int(_gs.gauntlet_losses) == _srv_gl and int(_gs.battles_total) == int(s1["bt"]))
	_job += 1


# B ─────────────────────────────────────────────────────────────
func _t_b() -> void:
	print("── B 周六闯关 · 服务器没有这份流 ⇒ 不播也不重算 ──")
	_http.streams.erase(MID)
	var s0 := _snap()
	var m: Node = await _open_mmk()
	var sent := await _submit_and_finish(m)
	_ok("分母: 交了阵容、服务器算完", sent)
	var tail := " · " + StreamPlayer.TXT_ERROR
	await _wait(func() -> bool: return _status_text(m).ends_with(tail) or _is_battle(get_tree().current_scene), 20000)
	_ok("B ★屏上「%s」、没进战斗场(没有本机重算)" % (RW.result_line({"won": _srv_won, "gw": _srv_gw, "gl": _srv_gl}) + tail),
		_status_text(m) == RW.result_line({"won": _srv_won, "gw": _srv_gw, "gl": _srv_gl}) + tail
		and not _is_battle(get_tree().current_scene), _status_text(m))
	_ok("B 分母: 问过 end.json 且是 404", _http.count(404, "/" + MID + "/end.json") >= 1)
	_ok("B 账照记(服务器那一份)", int(_gs.gauntlet_wins) == _srv_gw and int(_gs.gauntlet_losses) == _srv_gl
		and int(_gs.battles_total) == int(s0["bt"]) + 1)
	_ok("B 没挂任何待播(重算 / 流)、没有备份残留", ReplayRecorder.pending_play.is_empty() and StreamPlayer.pending.is_empty()
		and not ReplayRecorder._has_backup)
	_http.put(MID, _chunks, _meta)
	_job += 1


# C ─────────────────────────────────────────────────────────────
func _t_c() -> void:
	print("── C 战绩页 / 赛况板「观看」(ReplayFetcher.open) ──")
	await _leave()
	var got: Array = []
	RF.open(get_tree(), MID, func(c: String, msg: String) -> void: got.append([c, msg]), "", {"l": "甲", "r": "乙"})
	await _wait(func() -> bool: return not got.is_empty(), 15000)
	var ok := await _wait(func() -> bool: return _is_battle(get_tree().current_scene), 15000)
	var b: Node = get_tree().current_scene if ok else null
	_ok("C ★进场、stream 模式、会话 = 回放", str(got) == str([["", ""]]) and b != null and str(b._replay.mode) == "stream"
		and str(SW.current.get("kind", "")) == SW.KIND_REPLAY, str(got))
	if b == null:
		return
	var r: Array = await _play_stream_to_end(b)
	_ok("C ★播完整局 sim 0 次(步号 %d / sim_stepped %d / pre_step %d)" % r, int(r[0]) == 0 and int(r[1]) == 0 and int(r[2]) == 0
		and str(b._replay.player.state) == "ended")
	await _leave()


# D ─────────────────────────────────────────────────────────────
func _t_d() -> void:
	print("── D 周日对阵图(open_finals) ──")
	var got: Array = []
	RF.open_finals(get_tree(), 1, 0, 1, 0, func(c: String, msg: String) -> void: got.append([c, msg]), "", {}, true)
	await _wait(func() -> bool: return not got.is_empty(), 15000)
	var ok := await _wait(func() -> bool: return _is_battle(get_tree().current_scene), 15000)
	var b: Node = get_tree().current_scene if ok else null
	_ok("D ★自己那一场(已知裁判局)有流 ⇒ stream 模式", b != null and str(b._replay.mode) == "stream", str(got))
	if b != null:
		await _frames(30)
		_ok("D 播着时 sim 0 次", int(b._sim_step_n) == 0 and b._replay.player.sim_calls == 0)
	await _leave()
	_http.streams.erase(MID)
	got.clear()
	RF.open_finals(get_tree(), 1, 0, 1, 0, func(c: String, msg: String) -> void: got.append([c, msg]), "", {}, true)
	await _wait(func() -> bool: return not got.is_empty(), 15000)
	await _frames(10)
	_ok("D ★自己那一场没有流 ⇒ 不播、不重算(%s)" % str(got), got.size() == 1 and str(got[0][0]) == "no_stream"
		and not _is_battle(get_tree().current_scene) and ReplayRecorder.pending_play.is_empty())
	_http.put(MID, _chunks, _meta)


# E ─────────────────────────────────────────────────────────────
func _t_e() -> void:
	print("── E 开关关 ⇒ 老路(本机重算) ──")
	_set_flags(false)
	var n0: int = _http.reqs.size()
	var got: Array = []
	RF.open(get_tree(), MID, func(c: String, msg: String) -> void: got.append([c, msg]), "", {})
	_ok("E ★同步回调(与改之前一样, 本机有录像时一个请求都不发)", got.size() == 1 and str(got[0][0]) == "", str(got))
	var ok := await _wait(func() -> bool: return _is_battle(get_tree().current_scene), 15000)
	var b: Node = get_tree().current_scene if ok else null
	_ok("E ★进场是 play 模式(本机重算), 不是 stream", b != null and str(b._replay.mode) == "play" and b._replay.player == null)
	_ok("E 状态流服务器一个请求都没收到", _http.reqs.size() == n0, "%d → %d" % [n0, _http.reqs.size()])
	if b != null:
		await _frames(20)
		_ok("E 分母: 本机真在算(步号 %d > 0)" % int(b._sim_step_n), int(b._sim_step_n) > 0)
	await _leave()
	_set_flags(true)


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 看服务器算的局只播状态流" if _fail == 0 and _n >= 25 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
