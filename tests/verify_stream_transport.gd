extends Node
## verify_stream_transport.gd — 逐帧直播 S5: 客户端传输(`StreamSource.Http` / `probe`)与分流口(`stream_watch.route`)。
## 方案书 docs/plans/20261019-服务器逐帧直播.md 验收清单「传输」那一条(服务端部分 S4 已在公网实测, 这里是客户端那半)。
##
## 本进程起一个最小 HTTP 服务(tests/_stream_http.gd, 只听 127.0.0.1, CI 无外网也能跑), 口径照 server/stream/README.md 的 Caddy;
##   「服务器」那一份流由裁判程序(与裁判机同一套代码)在本进程真录出来(镜像快照局, 三路打满, 块留在内存)。
##
## 段落:
##   T 来源本身: ① 404 ⇒ 退避重试(0.5 → 4 秒封顶)、不判没有 ② 块一块块到 ⇒ 字节逐块相同 ③ 请求头带本机版本 ④ 426 ⇒ 版本墙回调、停
##     ⑤ 断网 / 500 ⇒ 一直重试、永远不判 gone(哪怕调用方说「早算完了」)⑥ 早算完了而 404 一直不消失 ⇒ gone
##   P 播放器 + HTTP(引擎每帧真驱动): ① 只到 2 块 ⇒「同步中」一步没应用 ② 到 8 块 ⇒ 开播、追上边沿停住「同步中」
##     ③ 断网一段 ⇒ 停在「同步中」、重试过 ④ 恢复 + 全部到齐 + end.json ⇒ 播到结尾, 解了全部块
##     ⑤ 中途 426 ⇒ 前面的播完停在「画面无法播放」 ⑥ 没有这份流 ⇒「画面无法播放」
##     ★全程 `_sim_step` 0 次(步号 0 / sim_stepped 0 / pre_step 0)—— 断网、404、426 都**没有**改成本机重算
##   R 分流口: 开关关 ⇒ 同步走老路、一个请求都不发; 开 ⇒ 200 播流 / 404 不知道 ⇒ 老路、知道是裁判局 ⇒ 不播 /
##     426 ⇒ 版本墙 / 断网 ⇒ 不播也**不**重算
## 每条判据都做过反向验证(方案书 §4.1)。

const J := preload("res://tests/_stream_jobs.gd")
const P := preload("res://tests/_stream_play.gd")
const H := preload("res://tests/_stream_http.gd")
const SW := preload("res://scripts/systems/replay/stream_watch.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const SB := preload("res://scripts/net/supabase.gd")
const MID := "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
const MID2 := "7a1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4c"
const NONE := "8b1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4d"

var _fail := 0
var _n := 0
var _http: Node = null
var _gs = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _wait(pred: Callable, ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		if pred.call():
			return true
		await get_tree().process_frame
	return pred.call()


func _sleep(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 120             # 判据全按墙钟等(网络退避是墙钟秒); 钉帧率 ⇒ 帧预算可预期(本机实测约 1.1 万帧)
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_gs.test_mode = true
	_gs.tutorial_active = false
	_http = H.new()
	add_child(_http)
	_ok("分母 · 本机 HTTP 服务起来了(端口 %d)" % _http.port, _http.start())
	OS.set_environment(SW.ENV_BASE, _http.base())
	var nat: Dictionary = await P.record_referee(self, J.mirror(_gs), func(_n2: int) -> bool: return false)
	var res: Dictionary = nat["res"]
	var chunks: Array = res.get("stream_chunks", [])
	var meta: Dictionary = (res.get("stream", {}) as Dictionary).duplicate()
	_ok("分母 · 裁判录到一局三路打满的流(%d 块 / %d 步)" % [chunks.size(), int(meta.get("steps", 0))],
		bool(res.get("ok", false)) and chunks.size() > 100 and int(meta.get("chunks", 0)) == chunks.size())
	if chunks.size() < 20:
		_finish()
		return
	await _t_source(chunks, meta)
	await _t_player(chunks, meta, nat)
	await _t_route(chunks, meta, nat)
	OS.set_environment(SW.ENV_BASE, "")
	_finish()


# ─────────────────────────────── T 来源本身 ───────────────────────────────
func _t_source(chunks: Array, meta: Dictionary) -> void:
	print("── T 来源本身 ──")
	_http.mode = "ok"
	_http.put(MID, chunks, meta, 0, false)
	var src := StreamSource.Http.new(_http.base(), MID, {})
	await _sleep(4000)
	_ok("T① 块还没生成(404)⇒ 一直在问、拿到 0 块、没判没有(状态 %s, 请求 %d, 404 %d 次, 最长退避 %.1f 秒)" % [src.state, src.requests, src.got_404, src.max_backoff],
		src.state == StreamSource.Http.ST_FETCHING and src.fetched() == 0 and src.got_404 >= 3 and src.available() == 0
		and not src.ended())
	_ok("T① 退避: 0.5 起步、翻倍、4 秒封顶(4 秒内不会一直狂问: 请求 %d 次 ≤ 12)" % src.requests,
		src.max_backoff >= 1.0 and src.max_backoff <= StreamSource.Http.RETRY_MAX and src.requests <= 12)
	## ② 块一块块出现
	_http.streams[MID]["served"] = 5
	await _wait(func() -> bool: return src.fetched() >= 5, 15000)
	var same := src.fetched() == 5
	for i in range(src.fetched()):
		same = same and (src.chunk(i) as PackedByteArray) == (chunks[i] as PackedByteArray)
	_ok("T② 块到了就拉: 5 块逐字节相同", same, "fetched %d" % src.fetched())
	_ok("T② 还没录完(没有 end.json)⇒ 不算录完", not src.ended() and src.end_meta().is_empty())
	var vers := {}
	for r in _http.reqs:
		vers[str(r[1])] = true
	_ok("T③ 每个请求都带 X-Client-Version = 本机版本 %s" % ReplayRecorder.client_version(),
		vers.size() == 1 and vers.has(ReplayRecorder.client_version()), str(vers.keys()))
	## 全部 + end.json ⇒ 录完
	_http.streams[MID]["served"] = chunks.size()
	_http.streams[MID]["end"] = true
	await _wait(func() -> bool: return src.ended(), 30000)
	_ok("T② 全到 + end.json ⇒ 录完(%d / %d 块, 元数据块数对得上)" % [src.fetched(), chunks.size()],
		src.ended() and src.fetched() == chunks.size() and src.available() == chunks.size()
		and int(src.end_meta().get("chunks", -1)) == chunks.size())
	var asked := src.requests
	await _sleep(800)
	_ok("T② 录完之后不再发请求", src.requests == asked)
	src = null
	## ④ 426
	_http.put(MID, chunks, meta, 3, false)
	var upd := [0]
	var s4 := StreamSource.Http.new(_http.base(), MID, {})
	s4.on_update_required = func() -> void: upd[0] += 1
	await _wait(func() -> bool: return s4.fetched() >= 3, 10000)
	_http.mode = "426"
	await _wait(func() -> bool: return s4.state != StreamSource.Http.ST_FETCHING, 10000)
	var r426 := s4.requests
	await _sleep(1500)
	_ok("T④ 426 ⇒ 版本墙回调一次、停在 update_required、之后不再问(状态 %s / 回调 %d / 请求 %d → %d)" % [s4.state, upd[0], r426, s4.requests],
		s4.state == StreamSource.Http.ST_UPDATE and upd[0] == 1 and s4.requests == r426)
	_ok("T④ 已拿到的 3 块照样给, 第 4 块是空的(播放器据此停在「无法播放」)",
		s4.available() == 4 and not (s4.chunk(2) as PackedByteArray).is_empty() and (s4.chunk(3) as PackedByteArray).is_empty())
	s4 = null
	## ⑤ 断网 / 500: 调用方说早算完了、放弃时限 1 秒 —— 照样永远不判 gone
	for m in ["drop", "500"]:
		_http.mode = m
		_http.put(MID, chunks, meta)
		var s5 := StreamSource.Http.new(_http.base(), MID, {"finished": true, "giveup_sec": 1.0})
		await _sleep(5000)
		_ok("T⑤ %s ⇒ 一直重试(失败 %d 次)、拿到 0 块、没判没有(状态 %s)" % [m, s5.net_fail, s5.state],
			s5.net_fail >= 2 and s5.fetched() == 0 and s5.state == StreamSource.Http.ST_FETCHING and s5.available() == 0)
		_http.mode = "ok"
		await _wait(func() -> bool: return s5.ended(), 30000)
		_ok("T⑤ %s 恢复之后接着拉完(%d 块)" % [m, s5.fetched()], s5.ended() and s5.fetched() == chunks.size())
	## ⑥ 早算完了而这份流根本没有
	var s6 := StreamSource.Http.new(_http.base(), NONE, {"finished": true, "giveup_sec": 1.5})
	await _wait(func() -> bool: return s6.state != StreamSource.Http.ST_FETCHING, 15000)
	_ok("T⑥ 早算完了而 404 一直不消失 ⇒ gone(%s)" % s6.why, s6.state == StreamSource.Http.ST_GONE
		and s6.available() == 1 and (s6.chunk(0) as PackedByteArray).is_empty())
	var s7 := StreamSource.Http.new(_http.base(), NONE, {"giveup_sec": 1.5})
	await _sleep(4000)
	_ok("T⑥ 正在算的(没说算完)⇒ 404 再久也只是等, 不判没有", s7.state == StreamSource.Http.ST_FETCHING and s7.got_404 >= 2)
	s7 = null
	## probe
	var codes: Array = []
	_http.put(MID2, chunks, meta)
	StreamSource.probe(_http.base(), MID2, ReplayRecorder.client_version(), func(c: int) -> void: codes.append(c))
	StreamSource.probe(_http.base(), NONE, ReplayRecorder.client_version(), func(c: int) -> void: codes.append(c))
	await _wait(func() -> bool: return codes.size() >= 2, 10000)
	_http.mode = "426"
	StreamSource.probe(_http.base(), MID2, ReplayRecorder.client_version(), func(c: int) -> void: codes.append(c))
	await _wait(func() -> bool: return codes.size() >= 3, 10000)
	_http.mode = "drop"
	StreamSource.probe(_http.base(), MID2, ReplayRecorder.client_version(), func(c: int) -> void: codes.append(c))
	await _wait(func() -> bool: return codes.size() >= 4, 20000)
	_http.mode = "ok"
	codes.sort()
	_ok("T probe: 有 200 / 没有 404 / 版本 426 / 断网 0(各恰好一次)", codes == [0, 200, 404, 426], str(codes))


# ─────────────────────────────── P 播放器 + HTTP ───────────────────────────────
func _player(mid: String, opts: Dictionary, nat: Dictionary) -> Node:
	if not (nat.get("state", {}) as Dictionary).is_empty():
		ReplayRecorder.apply_state(nat["state"])
	var src := StreamSource.Http.new(_http.base(), mid, opts)
	StreamPlayer.pending = {"source": src, "seed": int(nat["seed"])}
	var b: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(b)
	StreamPlayer.pending = {}
	return b


func _t_player(chunks: Array, meta: Dictionary, nat: Dictionary) -> void:
	print("── P 播放器 + HTTP(引擎每帧驱动) ──")
	var backup: Dictionary = ReplayRecorder.capture_all()
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	_http.mode = "ok"
	_http.put(MID, chunks, meta, 2, false)
	var b: Node = _player(MID, {"finished": false}, nat)
	var p: StreamPlayer = b._replay.player
	_ok("分母 · 播放模式建起来了(mode=stream, 来源是 HTTP)", p != null and str(b._replay.mode) == "stream" and p.src is StreamSource.Http)
	if p == null:
		return
	var src: StreamSource.Http = p.src
	var emits := [0]
	b.sim_stepped.connect(func() -> void: emits[0] += 1)
	p.speed = 40.0
	await _wait(func() -> bool: return src.fetched() >= 2, 10000)
	await _sleep(600)
	_ok("P① 只到 2 块 ⇒ 缓冲「同步中」、一步没应用(状态 %s / 应用 %d / 拿到 %d 块)" % [p.state, p.steps_applied, src.fetched()],
		p.state == "buffering" and p.status_text() == StreamPlayer.Live.TXT_SYNC and p.steps_applied == 0 and src.fetched() == 2)
	_http.streams[MID]["served"] = 8
	## ★等到 8 块都**解完**、停在它们的最后一步(拿到第 8 块与解它之间有一拍: 那时停在第 7 块尾, 下一拍又会接着放)
	var stalled := await _wait(func() -> bool: return p.state == "stalled" and p.chunks_decoded >= 8 and p.applied == p._last_step, 30000)
	_ok("P② 到 8 块 ⇒ 开播、追上边沿停住「同步中」(状态 %s / 应用到 %d / 已到 %d)" % [p.state, p.applied, p._last_step],
		stalled and p.status_text() == StreamPlayer.Live.TXT_SYNC and p.applied == p._last_step and p.steps_applied > 0)
	## ③ 断网一段
	_http.mode = "drop"
	_http.streams[MID]["served"] = chunks.size()
	var a0 := p.applied
	var nf0 := src.net_fail
	await _sleep(3000)
	_ok("P③ 断网 ⇒ 停在「同步中」、画面不前进、一直在重试(失败 %d 次)" % (src.net_fail - nf0),
		p.state == "stalled" and p.status_text() == StreamPlayer.Live.TXT_SYNC and p.applied == a0 and src.net_fail > nf0,
		"状态 %s / 应用 %d → %d / 拿到 %d 块 / 文字「%s」" % [p.state, a0, p.applied, src.fetched(), p.status_text()])
	_ok("P③ ★断网期间 sim 一步没跑(步号 %d / sim_stepped %d / pre_step %d)" % [int(b._sim_step_n), emits[0], p.sim_calls],
		int(b._sim_step_n) == 0 and emits[0] == 0 and p.sim_calls == 0)
	## ④ 恢复 + 全部 + end.json
	_http.mode = "ok"
	_http.streams[MID]["end"] = true
	await _wait(func() -> bool: return p.state == "ended" or p.state == "error", 120000)
	var steps := int(meta.get("steps", 0))
	_ok("分母 · P④ 恢复后播到结尾: 解了全部 %d 块、应用了全部 %d 步(状态 %s %s)" % [chunks.size(), steps, p.state, p.err],
		p.state == "ended" and p.chunks_decoded == chunks.size() and p.steps_applied == steps)
	_ok("分母 · 真的画了东西: 镜像节点建过 %d 个、单位代理 %d 个" % [p.mirror.built, p.units.size()],
		p.mirror.built > 1000 and p.units.size() > 0)
	_ok("P④ ★★整局 _sim_step 一次都没跑(步号 %d / sim_stepped %d / pre_step %d)" % [int(b._sim_step_n), emits[0], p.sim_calls],
		int(b._sim_step_n) == 0 and emits[0] == 0 and p.sim_calls == 0)
	b.queue_free()
	await _sleep(50)
	## ⑤ 中途 426
	_http.put(MID, chunks, meta, 3, false)
	var b5: Node = _player(MID, {"finished": true}, nat)
	var p5: StreamPlayer = b5._replay.player
	var e5 := [0]
	b5.sim_stepped.connect(func() -> void: e5[0] += 1)
	p5.speed = 40.0
	await _wait(func() -> bool: return (p5.src as StreamSource.Http).fetched() >= 3, 10000)
	_http.mode = "426"
	await _wait(func() -> bool: return p5.state == "error", 30000)
	_ok("P⑤ 中途 426 ⇒ 前 3 块播完、停在「%s」、sim 0 次(状态 %s / 应用到 %d / 步号 %d / sim_stepped %d)" % [StreamPlayer.TXT_ERROR, p5.state, p5.applied, int(b5._sim_step_n), e5[0]],
		p5.state == "error" and p5.status_text() == StreamPlayer.TXT_ERROR and p5.steps_applied >= 3 * StreamFormat.CHUNK_STEPS - 1
		and int(b5._sim_step_n) == 0 and e5[0] == 0 and p5.sim_calls == 0)
	_http.mode = "ok"
	b5.queue_free()
	await _sleep(50)
	## ⑥ 没有这份流
	var b6: Node = _player(NONE, {"finished": true, "giveup_sec": 1.0}, nat)
	var p6: StreamPlayer = b6._replay.player
	await _wait(func() -> bool: return p6.state == "error", 20000)
	_ok("P⑥ 没有这份流 ⇒「%s」、sim 0 次(状态 %s / 步号 %d)" % [StreamPlayer.TXT_ERROR, p6.state, int(b6._sim_step_n)],
		p6.state == "error" and p6.status_text() == StreamPlayer.TXT_ERROR and int(b6._sim_step_n) == 0 and p6.sim_calls == 0)
	b6.queue_free()
	await _sleep(50)
	_restore(backup)


# ─────────────────────────────── R 分流口 ───────────────────────────────
func _t_route(chunks: Array, meta: Dictionary, nat: Dictionary) -> void:
	print("── R 分流口(stream_watch.route) ──")
	var b64 := str((nat["res"] as Dictionary).get("replay_b64", ""))
	var rec: Dictionary = ReplayRecorder.decode(Marshalls.base64_to_raw(b64))
	_ok("分母 · 裁判那一份录像解得开(id = 这一场)", str(rec.get("id", "")) == J.job({}, {}, 1)["match_id"])
	var id := str(rec.get("id", ""))
	_http.mode = "ok"
	_http.put(id, chunks, meta)
	OS.set_environment(SB.ENV_URL, "http://referee.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "stream-anon-key")
	SB._transport_for_test = func(_m, _u, _h, _b, cb) -> void: cb.call({"ok": true, "code": 200, "body": "[]"})
	var keep_flags = _gs.referee_flags
	## 开关关 ⇒ 同步走老路
	_gs.referee_flags = {RN.K_FINALS: true, RN.K_GAUNTLET: true}
	var got: Array = []
	var legacy := [0]
	var lg := func() -> String:
		legacy[0] += 1
		return "LEGACY"
	var pr0 := SW.probes
	var rq0: int = _http.reqs.size()
	SW.route(null, rec, "", {}, false, lg, func(c: String, m: String) -> void: got.append([c, m]))
	_ok("R 开关关(没问到 stream_on)⇒ **同步**走老路、一个请求都没发", not RN.stream_on() and legacy[0] == 1 and got.size() == 1
		and str(got[0][1]) == "LEGACY" and SW.probes == pr0 and _http.reqs.size() == rq0, str(got))
	_gs.referee_flags = {RN.K_FINALS: true, RN.K_GAUNTLET: true, RN.K_STREAM: true, RN.K_STREAM_VER: "999.0.0"}
	got.clear()
	SW.route(null, rec, "", {}, false, lg, func(c: String, m: String) -> void: got.append([c, m]))
	_ok("R 开关开但本机版本低于 stream_version ⇒ 当作关(老路)", not RN.stream_on() and legacy[0] == 2 and got.size() == 1)
	_gs.referee_flags = {RN.K_FINALS: true, RN.K_GAUNTLET: true, RN.K_STREAM: true, RN.K_STREAM_VER: ReplayRecorder.client_version()}
	_ok("分母 · 开关开(stream_version = 本机版本)", RN.stream_on())
	## 404 + 不知道 ⇒ 老路;  404 + 知道是裁判局 ⇒ 不播不算
	var r2 := rec.duplicate(true)
	r2["id"] = NONE
	got.clear()
	SW.route(null, r2, "", {}, false, lg, func(c: String, m: String) -> void: got.append([c, m]))
	await _wait(func() -> bool: return not got.is_empty(), 15000)
	_ok("R 开 · 没有这份流 · 不知道是不是裁判局 ⇒ 老路(积分赛本机局 / 开流之前的局)", legacy[0] == 3 and got.size() == 1 and str(got[0][1]) == "LEGACY", str(got))
	got.clear()
	var ra0: int = RN.restream_asks
	SW.route(null, r2, "", {}, true, lg, func(c: String, m: String) -> void: got.append([c, m]))
	await _wait(func() -> bool: return not got.is_empty(), 15000)
	## 2026-10-20: 已知裁判局没有流 ⇒ 先请求补流(stream_watch._restream); 这里服务端排不上(注入传输回的不是补流回包)⇒ 不进场。
	##   补流排上之后进场等画面那一支在 verify_stream_referee_paths F2 量。
	_ok("R ★开 · 没有这份流 · 确知是裁判局 ⇒ 请求补流、没排上就不播、**不**重算(%s)" % str(got), legacy[0] == 3 and got.size() == 1
		and RN.restream_asks == ra0 + 1 and str(got[0][0]) in ["no_stream", "offline"] and StreamPlayer.pending.is_empty())
	## 426 / 断网
	SB._server_said_update = false
	_http.mode = "426"
	got.clear()
	SW.route(null, rec, "", {}, false, lg, func(c: String, m: String) -> void: got.append([c, m]))
	await _wait(func() -> bool: return not got.is_empty(), 15000)
	_ok("R 426 ⇒ 交给版本墙、不播、不重算(%s)" % str(got), legacy[0] == 3 and got.size() == 1 and str(got[0][0]) == "update_required"
		and SB._server_said_update)
	SB._server_said_update = false
	_http.mode = "drop"
	got.clear()
	SW.route(null, rec, "", {}, false, lg, func(c: String, m: String) -> void: got.append([c, m]))
	await _wait(func() -> bool: return not got.is_empty(), 30000)
	_ok("R ★断网 ⇒ 不播、也**不**当成「没有流」去重算(%s)" % str(got), legacy[0] == 3 and got.size() == 1 and str(got[0][0]) == "offline")
	## 版本不同 ⇒ 与回放同一句话, 不发请求
	_http.mode = "ok"
	var r3 := rec.duplicate(true)
	r3["client_version"] = "0.0.1"
	got.clear()
	rq0 = _http.reqs.size()
	SW.route(null, r3, "", {}, false, lg, func(c: String, m: String) -> void: got.append([c, m]))
	_ok("R 版本不同 ⇒ 同步回「不兼容」、不发请求", got.size() == 1 and str(got[0][0]) == "unplayable" and str(got[0][1]).find("不兼容") >= 0
		and _http.reqs.size() == rq0 and legacy[0] == 3)
	## 200 ⇒ 挂好待播(tree = null: 不换场景)
	var backup: Dictionary = ReplayRecorder.capture_all()
	got.clear()
	var en0 := SW.enters
	SW.route(null, rec, "", {}, false, lg, func(c: String, m: String) -> void: got.append([c, m]))
	await _wait(func() -> bool: return not got.is_empty(), 15000)
	var pend: Dictionary = StreamPlayer.pending
	_ok("R ★有流 ⇒ 播流: 挂好状态流待播(来源 HTTP、种子 = 录像的)、没有挂重算待播、没走老路",
		got.size() == 1 and str(got[0][0]) == "" and SW.enters == en0 + 1 and pend.get("source") is StreamSource.Http
		and int(pend.get("seed", -1)) == int(rec.get("seed", -2)) and ReplayRecorder.pending_play.is_empty() and legacy[0] == 3, str(got))
	_ok("R 会话: kind = replay、id = 这一场", str(SW.current.get("kind", "")) == SW.KIND_REPLAY and str(SW.current.get("id", "")) == id)
	StreamPlayer.pending = {}
	for c in get_tree().root.get_children():
		if c is SW.Guard:
			(c as SW.Guard)._finish(null)      # 不进战斗场: 守卫当场还原 GameState
	await get_tree().process_frame
	_ok("R 守卫还原 GameState、清会话", SW.current.is_empty() and not ReplayRecorder._has_backup)
	_restore(backup)
	_gs.referee_flags = keep_flags
	OS.set_environment(SB.ENV_URL, " ")
	ProjectSettings.set_setting(SB.SETTING_KEY, "")
	SB._transport_for_test = Callable()


func _restore(backup: Dictionary) -> void:
	for k in backup:
		var v = backup[k]
		_gs.set(str(k), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	_gs.test_mode = true


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	if _fail == 0 and _n >= 30:
		print("ALL PASS — 逐帧直播客户端传输: 404 等 / 426 停 / 断网同步中, 一步都不重算 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
