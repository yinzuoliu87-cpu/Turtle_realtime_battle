extends Node
## verify_stream_replay_controls.gd — 逐帧直播播放端: **回放**有暂停 / 倍速 / 进度条拖动, **观赛**只有「退出」。
## 方案书 docs/plans/20261019-服务器逐帧直播.md §2.5 剩余风险「没有暂停 / 倍速 / 进度条」→ 2026-10-20 补上;
## memory fb-spectate-is-not-replay(观赛 = 正在打 / 不知结果 / 无播放控件; 回放 = 已打完 / 暂停倍速进度条)。
##
## 先在本进程跑一局裁判局录流(镜像快照局, 三路打满), 再按入口 stream_watch.enter 的同一套步骤进场
##   (备份 GameState → 写录像开局状态 → 挂 StreamPlayer.pending, 块来源换成内存):
##   ⓪ 会话种类 → 给不给操作条: 只有 replay 给; live / referee / premiere 不给(`StreamWatch.controls_for`); 入口 enter 挂上的 pending 也照它
##   ① 回放: 操作条(暂停 / 倍速 / 进度槽 / 时间 / 退出回放)都建了, 进度槽吃点击(观赛那几种不吃)
##   ② 暂停: 点「暂停」⇒ 播放器停住(推 120 帧应用步数不变)、「已暂停」签牌出现; 再点 ⇒ 接着播
##   ③ 倍速: 点一下 ⇒ 播放器 speed 跟着 ReplayRecorder 的倍速走(1 → 2)
##   ④ 进度条: 在槽上点 50% 处(按下 + 松手)⇒ 播放器 seek 一次、正好落在全场一半那一步; 时间牌 = 那一步的时钟
##      拖: 80% 处按下 → 拖到 30% → 松手 ⇒ 只跳一次(拖的时候不跳), 落在 30% 那一步(往回跳)
##   ⑤ 播到结尾: 收尾卡带「全场 m:ss」; 一步 sim 都没跑
##   ⑥ 观赛(controls = false): 没有操作条 / 暂停签牌, 只有左下角「退出」; 收尾卡不报全场时长
## ★分母: 全场步数 > 0、槽宽 > 0、真的应用过步、seek 计数真的涨了。

const J := preload("res://tests/_stream_jobs.gd")
const P := preload("res://tests/_stream_play.gd")
const SW := preload("res://scripts/systems/replay/stream_watch.gd")
const RC := preload("res://scripts/scenes/battle/replay_controls.gd")
const SIM_DT := 1.0 / 60.0
const NAMES := {"l": "甲方玩家", "r": "乙方玩家"}

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	gs.tutorial_active = false
	gs.test_mode = true
	await _t_kinds()
	var nat: Dictionary = await P.record_referee(self, J.mirror(gs), func(_n2: int) -> bool: return false)
	var res: Dictionary = nat["res"]
	var chunks: Array = res.get("stream_chunks", [])
	var meta: Dictionary = res.get("stream", {})
	_ok("分母 · 录到一局三路打满的流(%d 块 / %d 步)" % [chunks.size(), int(meta.get("steps", 0))],
		bool(res.get("ok", false)) and int(res.get("fights", 0)) == 3 and chunks.size() > 100)
	var rec: Dictionary = ReplayRecorder.decode(Marshalls.base64_to_raw(str(res.get("replay_b64", ""))))
	await _t_replay(rec, chunks, meta)
	await _t_watch(rec, chunks, meta)
	gs.test_mode = true
	_finish()


## ⓪ 会话种类 → 操作条(纯判据 + 入口真挂上的 pending)
func _t_kinds() -> void:
	print("=== ⓪ 会话种类 → 给不给操作条 ===")
	_ok("⓪ ★回放(replay)给操作条", SW.controls_for(SW.KIND_REPLAY))
	_ok("⓪ ★观赛三种(live 正在算 / referee 周六自己那一场 / premiere 周日开播)不给",
		not SW.controls_for(SW.KIND_LIVE) and not SW.controls_for(SW.KIND_REFEREE) and not SW.controls_for(SW.KIND_PREMIERE))
	## 入口 enter(tree = null: 只挂待播): 挂上的 pending 里 controls 照会话种类
	var rec := {"id": "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b", "v": ReplayRecorder.FORMAT_V, "client_version": ReplayRecorder.client_version(),
		"seed": 7, "state": {}, "events": [{"s": 120, "k": "fight"}, {"s": 3000, "k": "fight"}], "cps": [], "end": {"s": 6000}}
	var got := {}
	for k in [SW.KIND_REPLAY, SW.KIND_REFEREE]:
		var w := SW.enter(null, rec, "", {}, {"kind": k})
		got[k] = [w, bool(StreamPlayer.pending.get("controls", false)), StreamPlayer.pending.get("fights", []), int(StreamPlayer.pending.get("total", -1))]
		StreamPlayer.pending = {}
		ReplayRecorder.end_play()
		SW.current = {}
	await get_tree().process_frame          # 守卫是延后挂上的: 等一帧再摘(不摘的话 30 秒后它会去还原 GameState)
	var guards := 0
	for c in get_tree().root.get_children():
		if c is SW.Guard:
			(c as SW.Guard)._done = true
			(c as Node).queue_free()
			guards += 1
	_ok("⓪ 入口 enter: 回放挂 controls = true、观赛(referee)挂 false; 进度条刻度 / 全场步数取自录像 %s" % str(got),
		str(got.get(SW.KIND_REPLAY, [])) == str(["", true, [120, 3000], 6000]) and str(got.get(SW.KIND_REFEREE, [])) == str(["", false, [120, 3000], 6000]))


func _make(rec: Dictionary, chunks: Array, meta: Dictionary, controls: bool, kind: String) -> Node:
	ReplayRecorder.play_names = NAMES.duplicate()
	ReplayRecorder.viewer_name = ""
	ReplayRecorder.return_scene = ""
	ReplayRecorder.begin_play(rec)
	ReplayRecorder.pending_play = {}
	var fights: Array = []
	for e in rec.get("events", []):
		if e is Dictionary and str((e as Dictionary).get("k", "")) == "fight":
			fights.append(int((e as Dictionary).get("s", 0)))
	StreamPlayer.pending = {"source": StreamSource.Mem.new(chunks, meta), "seed": int(rec.get("seed", 0)),
		"controls": controls, "fights": fights, "total": int((rec.get("end", {}) as Dictionary).get("s", -1))}
	SW.current = {"kind": kind}
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	var b: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(b)
	StreamPlayer.pending = {}
	b.set_process(false)
	return b


func _leave(b: Node) -> void:
	b.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	SW.current = {}
	ReplayRecorder.play_names = {}


func _named(b: Node, nm: String) -> Node:
	return b.find_child(nm, true, false)


func _click(track: Control, x: float, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = Vector2(x, 20.0)
	track.gui_input.emit(ev)


func _drag(track: Control, x: float) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(x, 20.0)
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	track.gui_input.emit(ev)


func _play_to_end(b: Node, p: StreamPlayer, ui) -> void:
	p.speed = 40.0
	var guard := 0
	while p.state != "ended" and p.state != "error" and guard < 40000:
		guard += 1
		p.advance(2.0 * SIM_DT)
		if guard % 30 == 0:
			await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000 and (ui == null or ui.card == null):
		p.advance(SIM_DT)
		await get_tree().process_frame


func _card_text(ui) -> String:
	if ui == null or ui.card == null or not is_instance_valid(ui.card):
		return ""
	var out: Array = []
	var st: Array = [ui.card]
	while not st.is_empty():
		var n: Node = st.pop_back()
		for c in n.get_children():
			st.append(c)
			if c is Label:
				out.append((c as Label).text)
	return " | ".join(out)


# ① ~ ⑤ 回放 ─────────────────────────────────────────────────
func _t_replay(rec: Dictionary, chunks: Array, meta: Dictionary) -> void:
	print("=== ①~⑤ 回放(controls = true) ===")
	var b: Node = _make(rec, chunks, meta, true, SW.KIND_REPLAY)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	_ok("分母 · 播放模式建起来了(mode=stream, controls=true)", p != null and str(b._replay.mode) == "stream" and p.controls)
	if p == null:
		await _leave(b)
		return
	p.advance(0.0)
	for _i in range(4):
		await get_tree().process_frame
	var ui = b._hud._replay_ui
	var pause_b := _named(b, RC.N_PAUSE) as Button
	var speed_b := _named(b, RC.N_SPEED) as Button
	var track := _named(b, RC.N_TRACK) as Control
	var time_l := _named(b, RC.N_TIME) as Label
	var exit_b := _named(b, RC.N_EXIT) as Button
	_ok("① ★操作条都建了: 暂停 / 倍速 / 进度槽 / 时间 / 退出(键上图标: 暂停 / x1 / X)", pause_b != null and speed_b != null and track != null
		and time_l != null and exit_b != null and PixelKey.icon_of(exit_b) == "exit" and PixelKey.icon_of(pause_b) == "pause")
	if pause_b == null or speed_b == null or track == null or time_l == null:
		await _leave(b)
		return
	_ok("① 进度槽吃点击(MOUSE_FILTER_STOP, 连着拖动处理)", track.mouse_filter == Control.MOUSE_FILTER_STOP
		and track.gui_input.is_connected(ui._on_track_input))
	var tot: int = b._replay.total_steps()
	_ok("分母 · 全场步数 %d > 0、槽宽 %.0f > 0" % [tot, track.size.x], tot > 0 and track.size.x > 10.0)
	## 先播一段
	for _i in range(200):
		p.advance(2.0 * SIM_DT)
	_ok("分母 · 先播了一段(应用到第 %d 步)" % p.applied, p.applied > 200)
	## ② 暂停
	pause_b.pressed.emit()
	ui.refresh()
	var a0 := p.applied
	for _i in range(120):
		p.advance(2.0 * SIM_DT)
	ui.refresh()
	var tag := _named(b, RC.N_PAUSED) as Control
	_ok("② ★点「暂停」⇒ 播放器停住(推 120 帧后应用步 %d → %d)、键上换成「播放」图标、「已暂停」签牌出现" % [a0, p.applied],
		p.paused and p.applied == a0 and PixelKey.icon_of(pause_b) == "play" and tag != null and tag.visible)
	pause_b.pressed.emit()
	for _i in range(30):
		p.advance(2.0 * SIM_DT)
	ui.refresh()
	_ok("② 再点 ⇒ 接着播(应用步 %d > %d)、签牌收起" % [p.applied, a0], not p.paused and p.applied > a0 and not tag.visible)
	## ③ 倍速
	var sp0: float = float(b._replay.speed)
	speed_b.pressed.emit()
	_ok("③ ★点倍速 ⇒ 播放器 speed 跟着走(%.0f → %.0f, 回放倍速 %.0f)" % [sp0, p.speed, float(b._replay.speed)],
		p.speed == float(b._replay.speed) and p.speed != sp0 and PixelKey.icon_of(speed_b) == "x%d" % int(p.speed))
	while float(b._replay.speed) != 1.0:
		speed_b.pressed.emit()
	## ④ 进度条: 点 50%
	var w := track.size.x
	var s0: int = p.seeks
	_click(track, w * 0.5, true)
	_click(track, w * 0.5, false)
	var want := int(roundf(0.5 * float(tot)))
	ui.refresh()
	_ok("④ ★在槽上点 50%% 处 ⇒ seek 一次(%d → %d)、落在第 %d 步(实际 %d)" % [s0, p.seeks, want, p.applied],
		p.seeks == s0 + 1 and p.applied == want and p.state == "playing")
	_ok("④ 时间牌 = 那一步的时钟「%s」(实际「%s」)" % [RC.clock(want) + " / " + RC.clock(tot), time_l.text],
		time_l.text == RC.clock(want) + " / " + RC.clock(tot))
	## 拖: 80% 按下 → 拖到 30% → 松手
	s0 = p.seeks
	_click(track, w * 0.8, true)
	_drag(track, w * 0.6)
	_drag(track, w * 0.3)
	var mid_seeks: int = p.seeks
	_click(track, w * 0.3, false)
	want = int(roundf(0.3 * float(tot)))
	_ok("④ ★拖动: 拖的时候不跳(拖中 seek %d 次)、松手跳一次, 落在 30%% 第 %d 步(实际 %d, 往回跳)" % [mid_seeks - s0, want, p.applied],
		mid_seeks == s0 and p.seeks == s0 + 1 and p.applied == want)
	for _i in range(30):
		p.advance(2.0 * SIM_DT)
	_ok("④ 跳完接着播(应用到 %d > %d)、sim 0 步" % [p.applied, want], p.applied > want and int(b._sim_step_n) == 0 and p.sim_calls == 0)
	## ⑤ 播到结尾
	await _play_to_end(b, p, ui)
	var ct := _card_text(ui)
	_ok("⑤ ★播到结尾出收尾卡、带「全场 %s」(回放报全场时长)" % RC.clock(tot), ui.card != null and ct.contains("全场 " + RC.clock(tot)), ct)
	_ok("⑤ ★★整局 sim 0 步(步号 %d / pre_step %d)" % [int(b._sim_step_n), p.sim_calls], int(b._sim_step_n) == 0 and p.sim_calls == 0)
	await _leave(b)


# ⑥ 观赛 ─────────────────────────────────────────────────────
func _t_watch(rec: Dictionary, chunks: Array, meta: Dictionary) -> void:
	print("=== ⑥ 观赛(controls = false) ===")
	var b: Node = _make(rec, chunks, meta, false, SW.KIND_LIVE)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	if p == null:
		_ok("⑥ 播放模式建起来了", false)
		await _leave(b)
		return
	p.advance(0.0)
	for _i in range(4):
		await get_tree().process_frame
	var ui = b._hud._replay_ui
	var exit_b := _named(b, RC.N_EXIT) as Button
	_ok("⑥ ★观赛没有操作条: 暂停 / 倍速 / 进度槽 / 时间 / 已暂停签牌一个都没有",
		_named(b, RC.N_PAUSE) == null and _named(b, RC.N_SPEED) == null and _named(b, RC.N_TRACK) == null
		and _named(b, RC.N_TIME) == null and _named(b, RC.N_PAUSED) == null and _named(b, "ReplayStrip") == null)
	_ok("⑥ 只有左下角「退出」(红键 X)", exit_b != null and PixelKey.icon_of(exit_b) == "exit" and exit_b.is_visible_in_tree())
	await _play_to_end(b, p, ui)
	var ct := _card_text(ui)
	_ok("⑥ ★观赛收尾卡揭晓胜方、不报全场时长", ui.card != null and ct.contains("获胜") and not ct.contains("全场"), ct)
	await _leave(b)


func _finish() -> void:
	print("")
	print("  [量] 用了 %d 帧" % Engine.get_process_frames())
	if _fail == 0 and _n >= 18:
		print("ALL PASS — 状态流回放有暂停 / 倍速 / 进度条拖动, 观赛只有退出 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
