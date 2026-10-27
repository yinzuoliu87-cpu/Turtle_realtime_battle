extends Node
## verify_stream_end_exit.gd — 逐帧直播播放端: 播完出收尾、有「退出」、离场后 GameState 还原。
## 方案书 docs/plans/20261019-服务器逐帧直播.md §2.5「播放端 HUD」· 收尾与退出。
##
## 播放模式一步 sim 都不跑 ⇒ 本机那条「`_dl_finish` → 结算屏」走不到; 服务器那一局的 `_dl_finish(won, 延时)` 录成事件 `finish`,
## 手机播到那一步出收尾(stream_hud.gd on_finish)。本门禁按入口 stream_watch.enter 的同一套步骤进场(备份 GameState → 写录像开局状态 →
## 挂 StreamPlayer.pending), 只是块来源换成内存、不挂守卫节点(守卫是另一道保险; 这里量的是战斗场自己的 `_exit_tree` 还原)。
##   ① 别人的局 / 周日(会话 kind = replay): 播放器建了「退出」(ReplayExit, 连到 `_replay_exit`); 播到结尾出收尾卡,
##      标题 = 「<胜方名字> 获胜」且与服务器结果单的胜负一致; 没有「再看一遍」(状态流没有输入录像, 再看一遍会变成本机重算); 一步 sim 都没跑。
##   ② 周六看自己那一场(kind = referee, 带服务器结果): 出正常结算屏(`_hud._settle`), 胜负按服务器结果, 不出回放收尾卡。
##   ③ 离场(战斗场离树)后 GameState 与进场前逐项相同(capture_all 全量比)。
## ★分母: 两遍都真播到结尾(应用步数 = 录的步数)、收到 finish 事件 1 次、GameState 比过的项数 > 0。

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
	var gs = get_node_or_null("/root/GameState")
	gs.tutorial_active = false
	gs.test_mode = true
	var job: Dictionary = J.mirror(gs)
	var nat: Dictionary = await P.record_referee(self, job, func(_n2: int) -> bool: return false)
	var res: Dictionary = nat["res"]
	var chunks: Array = res.get("stream_chunks", [])
	var meta: Dictionary = res.get("stream", {})
	_ok("分母 · 原生一遍三路打满、录到块", bool(res.get("ok", false)) and int(res.get("fights", 0)) == 3 and chunks.size() > 100,
		"块 %d" % chunks.size())
	var rec: Dictionary = ReplayRecorder.decode(Marshalls.base64_to_raw(str(res.get("replay_b64", ""))))
	## 服务器结果单的胜负(左 = 录像方): 结果单里各路胜负 + 蛋血, 与本机那局 `_dl_finish` 的同一个口径
	var won_srv: bool = _server_won(res)
	print("  [量] 服务器结果: 左方%s · lane_results %s · egg_hp %s" % ["胜" if won_srv else "负", str(res.get("lane_results", {})), str(res.get("egg_hp", {}))])
	gs.test_mode = false      # 入口之前: 看的人自己的存档(非测试模式), 由 begin_play 接管
	await _case("① 别人的局(kind=replay)", rec, chunks, meta, {"kind": SW.KIND_REPLAY}, won_srv, false)
	## ② 服务器结果故意给成与流相反: 结算屏必须按服务器结果(量出「胜负以服务器为准」这一条真的走到了)
	await _case("② 周六自己那一场(kind=referee)", rec, chunks, meta,
		{"kind": SW.KIND_REFEREE, "result": {"won": not won_srv, "reward": 3}}, not won_srv, true)
	gs.test_mode = true
	_finish()


static func _server_won(res: Dictionary) -> bool:
	var lr: Dictionary = res.get("lane_results", {})
	var eh: Dictionary = res.get("egg_hp", {})
	if float(eh.get("right", 1.0)) <= 0.0 and float(eh.get("left", 1.0)) > 0.0:
		return true
	if float(eh.get("left", 1.0)) <= 0.0:
		return false
	var lw := 0
	var rw := 0
	for k in lr:
		if str(lr[k]) == "left":
			lw += 1
		else:
			rw += 1
	return lw > rw


func _case(tag: String, rec: Dictionary, chunks: Array, meta: Dictionary, sess: Dictionary, want_won: bool, settle: bool) -> void:
	print("=== %s ===" % tag)
	var gs = get_node_or_null("/root/GameState")
	var before: Dictionary = ReplayRecorder.capture_all()
	## ── 入口(同 stream_watch.enter, 块来源换成内存、不挂守卫) ──
	ReplayRecorder.play_names = NAMES.duplicate()
	ReplayRecorder.viewer_name = ""
	ReplayRecorder.return_scene = ""
	ReplayRecorder.begin_play(rec)
	ReplayRecorder.pending_play = {}
	StreamPlayer.pending = {"source": StreamSource.Mem.new(chunks, meta), "seed": int(rec.get("seed", 0))}
	SW.current = sess.duplicate(true)
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	var b: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(b)
	StreamPlayer.pending = {}
	b.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	_ok("分母 · %s 播放模式建起来了" % tag, p != null and str(b._replay.mode) == "stream")
	if p == null or p.hud == null:
		return
	p.advance(0.0)
	var ui = b._hud._replay_ui
	var ex: Button = ui.exit_btn if ui != null else null
	var ex_ok: bool = ex != null and is_instance_valid(ex) and ex.is_visible_in_tree() and str(ex.name) == RC.N_EXIT \
		and ex.pressed.is_connected(ui._ask_exit)
	var yes_ok := false
	if ex_ok:
		ex.pressed.emit()                 # 退出先确认(2026-10-27): 框里的「退出」连到 _replay_exit, 「继续观看」收起
		var yes := b.find_child(RC.N_EXIT_YES, true, false) as Button
		var no := b.find_child(RC.N_EXIT_NO, true, false) as Button
		yes_ok = yes != null and no != null and yes.pressed.is_connected(b._hud._replay_exit)
		if no != null:
			no.pressed.emit()
		await get_tree().process_frame
	_ok("★★%s 播放时有「退出」(%s, 可见; 点了先出确认框, 框里「退出」连到 _replay_exit = 回放退出同一个)" % [tag, RC.N_EXIT],
		ex_ok and yes_ok)
	var guard := 0
	while p.state != "ended" and p.state != "error" and guard < 40000:
		guard += 1
		p.advance(2.0 * SIM_DT)
		if guard % 30 == 0:
			await get_tree().process_frame
	## 收尾有延时(蛋碎后晚 1.2 秒出结算 / 收尾卡再晚 CARD_DELAY): 等真实时间
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		p.advance(SIM_DT)
		await get_tree().process_frame
		if settle and b._hud._settle != null:
			break
		if not settle and ui != null and ui.card != null:
			break
	var lbl := "分母 · %s 播到结尾(应用 %d / %d 步)、收到 finish 事件 %d 次、sim %d 步" % [tag, int(p.steps_applied), int(meta.get("steps", 0)),
		int(p.events.get("finish", 0)), int(b._sim_step_n)]
	_ok(lbl,
		p.state == "ended" and p.steps_applied == int(meta.get("steps", 0)) and int(p.events.get("finish", 0)) == 1 and int(b._sim_step_n) == 0)
	if settle:
		var scr = b._hud._settle
		_ok("★★%s 出正常结算屏(_hud._settle)、不出回放收尾卡" % tag, scr != null and is_instance_valid(scr) and (ui == null or ui.card == null))
		_ok("★★%s 结算胜负按服务器结果(服务器给的是%s)" % [tag, "胜" if want_won else "负"],
			scr != null and _settle_won(b) == want_won, "结算屏标题 %s" % _settle_title(b))
	else:
		var card = ui.card if ui != null else null
		var title := ""
		if card != null and is_instance_valid(card):
			var tl = card.find_child("ReplayResult", true, false)
			title = (tl as Label).text if tl != null else ""
		var want_title := "%s 获胜" % str(NAMES["l"] if want_won else NAMES["r"])
		_ok("★★%s 出收尾卡、标题 =「%s」(服务器那一局的胜方)" % [tag, want_title], card != null and title == want_title, "标题「%s」" % title)
		_ok("★%s 收尾卡没有「再看一遍」(状态流不许本机重算)、有「返回」" % tag,
			card != null and card.find_child(RC.N_AGAIN, true, false) == null and card.find_child(RC.N_BACK, true, false) != null)
		_ok("★%s 没有出正常结算屏(别人的局不记账)" % tag, b._hud._settle == null)
	## ── 离场: 战斗场离树 ⇒ `_exit_tree` 还原 GameState ──
	b.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	SW.current = {}
	ReplayRecorder.play_names = {}
	var after: Dictionary = ReplayRecorder.capture_all()
	var diffk: Array = []
	for k in before:
		if str(before[k]) != str(after.get(k)):
			diffk.append(str(k))
	var tm_ok: bool = bool(gs.test_mode) == false
	_ok("★★%s 离场后 GameState 与进场前相同(比了 %d 项, 不同 %d 项)、test_mode 还原" % [tag, before.size(), diffk.size()],
		before.size() > 20 and diffk.is_empty() and tm_ok, str(diffk.slice(0, 6)))


## 结算屏的胜负: 横幅上的那个字
func _settle_title(b) -> String:
	var scr = b._hud._settle
	if scr == null:
		return ""
	var out: Array = []
	var st: Array = [scr]
	while not st.is_empty():
		var n: Node = st.pop_back()
		for c in n.get_children():
			st.append(c)
			if c is Label and ((c as Label).text.contains("胜利") or (c as Label).text.contains("失败")):
				out.append((c as Label).text)
	return str(out)


func _settle_won(b) -> bool:
	var t := _settle_title(b)
	return t.contains("胜利") and not t.contains("失败")


func _finish() -> void:
	print("")
	print("  [量] 用了 %d 帧" % Engine.get_process_frames())
	if _fail == 0:
		print("ALL PASS — 播放端播完出收尾、有退出、离场还原 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
