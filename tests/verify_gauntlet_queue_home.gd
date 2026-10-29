extends Node
## verify_gauntlet_queue_home.gd — 闯关赛排队时可回主页（会话活过换场景）。方案书 docs/plans/20261029c-闯关赛排队时可回主页.md §4.2 / §6。
##
## 用户 10-29「我认为用户在开战里锁定了后，还是能回到主页的，只是不能动背包商店，然后开始战斗你得变按钮，在边上也要有取消按钮」
## 全程走产品自己的入口：真匹配屏 → `referee_run.gd` → 注入传输（假服务器，不连网）。主页的样子由 verify_gauntlet_queue_menu 量。
##
## 段落（每条断言带分母）：
##   H1 排队中按「←」⇒ 会话搬到 root（名 GauntletSession、active 指向它）、匹配屏离场后心跳照样每 2 秒到服务器、`queue_locked` 为真；
##      「←」在排队屏上可见且压在等待界面上面；等待界面有「可返回主页」那一行
##   H2 会话活着时主菜单补查（`resume_if_any`）不出队（原来会把人踢出队）
##   H3 回匹配屏 ⇒ 认领同一个会话（不重新进队：join 只发过 1 次）、会话搬回匹配屏下面、等待界面照画
##   H4 ★R2：在 root 上配上 ⇒ 那一刻不落任务单（单子仍是排队单）、状态 found、`queue_locked` 仍为真；换到匹配屏认领后才落任务单、走原来那条（VS 卡 / 查任务）
##   H5 在 root 上被服务端判离开 ⇒ 主菜单那句话（`RefereeWatch.notice`）= 「已退出排队」、会话自删、active 空、锁解开、排队单销掉
##   H6 切后台 11 秒回来、心跳回已过期 ⇒ 自动用同一份阵容重排一次（join 多 1 次、回到排队中）；切后台 3 秒回来 ⇒ 不重排
## 反向验证（改坏 → 红 → 逐字节还原）：detach 不搬到 root ⇒ H1 红；resume_if_any 去掉会话闸 ⇒ H2 红；
##   `_paired` 在 root 上也当场 `_on_submit` ⇒ H4 红；`_to` 在 root 上走到头不自删 ⇒ H5 红；不重排 ⇒ H6 红。

const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const RUN := preload("res://scripts/systems/replay/referee_run.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const MMK := preload("res://scripts/scenes/MatchmakingScene.gd")
const BP := preload("res://scripts/referee/bot_pool.gd")
const QW := preload("res://scripts/scenes/queue_wait_view.gd")
const MMK_SCENE := "res://scenes/Matchmaking.tscn"
const ME := "11111111-2222-4333-8444-555555555555"
const MID := "5b2c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
const JOIN := "gauntlet_queue_join"
const POLL := "gauntlet_queue_poll"
const CANCEL := "gauntlet_queue_cancel"
const STATUS := "referee_job_status"

var _fail := 0
var _n := 0
var _gs
var _hits := {}
var _poll_t: Array = []
var _sc: Dictionary = {}
var _sc_polls := 0
var _paired_now := false
var _job := 700
var _srv_b: Dictionary = {}
var _stub: Node = null


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


func _hit(name: String) -> int:
	return int(_hits.get(name, 0))


func _wait(pred: Callable, ms: int = 15000) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		if pred.call():
			return true
		await get_tree().process_frame
	return pred.call()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	P2C.now_override_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 5 * 86400 + 12 * 3600
	_setup_gs()
	_net_fake()
	_ok("分母: 时间钉在周六、闯关赛上线、开关开", P2C.phase_at_utc(P2C.now_utc()) == P2C.PHASE_GAUNTLET
		and P2C.phase_mode_live(P2C.PHASE_GAUNTLET) and RW.gauntlet_on())
	MMK._may_leave_for_test = func(_to: String) -> bool: return false   # 「回主菜单」只量到出口，不真换场景
	await _t_h1_h2_h3()
	await _t_h4()
	await _t_h5()
	await _t_h6()
	_cleanup()
	_finish()


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
	_gs.battles_total = 9
	_gs.referee_pending = {}
	_gs.referee_flags = {RW.RN.K_FINALS: false, RW.RN.K_GAUNTLET: true}
	_gs.dual_active = true


func _net_fake() -> void:
	OS.set_environment(RW.SB.ENV_URL, "http://referee.local")
	ProjectSettings.set_setting(RW.SB.SETTING_KEY, "referee-anon-key")
	RW.SB._transport_for_test = _transport
	RW.SB._reset_auth_for_test()
	RW.SB._token = "tok"
	RW.SB._expires_at = int(Time.get_unix_time_from_system()) + 3600


func _cleanup() -> void:
	var act = RUN.active
	if act != null and is_instance_valid(act):
		(act as Node).queue_free()
	RUN.active = null
	for n in get_tree().root.get_children():
		if n != self and n != get_tree().current_scene and str(n.name).begins_with(RUN.ROOT_NAME):
			n.queue_free()
	P2C.now_override_ts = 0
	OS.set_environment(RW.SB.ENV_URL, " ")
	ProjectSettings.set_setting(RW.SB.SETTING_KEY, "")
	RW.SB._transport_for_test = Callable()
	RW.SB._token = ""
	MMK._may_leave_for_test = Callable()
	RW.notice = ""
	_gs.referee_flags = {}
	_gs.referee_pending = {}


func _reset_sc(sc: Dictionary) -> void:
	_sc = sc
	_sc_polls = 0
	_paired_now = false
	_poll_t.clear()
	_hits.clear()
	_job += 1
	_srv_b = BP.one(9, int(_gs.gauntlet_wins), int(_gs.gauntlet_losses), _job % 6)


func _paired_body() -> String:
	return JSON.stringify({"ok": true, "status": "paired", "job_id": _job, "side": "a", "match_id": MID,
		"opp": {"profile": _srv_b["profile"], "leaders": _srv_b["leaders"]},
		"gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses), "waited_sec": _sc_polls * 2})


func _waiting_body() -> String:
	return JSON.stringify({"ok": true, "status": "waiting", "gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses),
		"waited_sec": _sc_polls * 2})


## 假服务器。剧本：pair（true ⇒ 下一次心跳配上）/ poll_end（下一次心跳回它：expired / none）/ rejoin_ok（重排之后回 waiting）。
func _transport(_m, u, _h, _b, cb) -> void:
	var url := str(u)
	if url.find("/auth/v1/") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({
			"access_token": "tok", "refresh_token": "r2", "expires_in": 3600, "user": {"id": ME, "is_anonymous": true}})})
		return
	var i := url.find("/rest/v1/rpc/")
	var rpc := url.substr(i + 13).split("?")[0] if i >= 0 else ""
	if rpc != "":
		_hits[rpc] = _hit(rpc) + 1
	match rpc:
		"referee_flags":
			cb.call({"ok": true, "code": 200, "body": "{\"finals_on\":false,\"gauntlet_on\":true}"})
			return
		JOIN:
			_sc.erase("poll_end")
			cb.call({"ok": true, "code": 200, "body": _waiting_body()})
			return
		POLL:
			_poll_t.append(Time.get_ticks_msec())
			_sc_polls += 1
			if str(_sc.get("poll_end", "")) != "":
				cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": str(_sc["poll_end"])})})
				return
			if bool(_sc.get("pair", false)):
				_paired_now = true
			cb.call({"ok": true, "code": 200, "body": _paired_body() if _paired_now else _waiting_body()})
			return
		CANCEL:
			cb.call({"ok": true, "code": 200, "body": "{\"ok\":true,\"status\":\"cancelled\"}"})
			return
		STATUS:
			cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "pending", "match_id": MID})})
			return
	cb.call({"ok": true, "code": 200, "body": "[]"})


# ───────────────────────────── 场景小工具 ─────────────────────────────
## current_scene 换成一个空节点（SceneNav.go 换场景时释放的是它，不是本测试）。
func _park() -> void:
	if _stub == null or not is_instance_valid(_stub):
		_stub = Node.new()
		_stub.name = "ParkedScene"
		get_tree().root.add_child(_stub)
	get_tree().current_scene = _stub


func _open_mmk() -> Node:
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self and old != _stub:
		old.queue_free()
	await _frames(2)
	_gs.dual_opponent = {}
	var m: Node = (load(MMK_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	return m


func _close(m) -> void:
	if m != null and is_instance_valid(m):
		(m as Node).queue_free()
	await _frames(3)
	_park()


func _run_of(m):
	if m == null or not is_instance_valid(m):
		return null
	var r = (m as Node).get("_ref_run")
	return r if r != null and is_instance_valid(r) else null


func _active():
	var a = RUN.active
	return a if a != null and is_instance_valid(a) and not (a as Node).is_queued_for_deletion() else null


## 排队中：开匹配屏、等进队 + 等待界面，然后按「←」（回主页、继续匹配），关掉匹配屏。返回会话。
func _queue_then_home() -> Node:
	var m := await _open_mmk()
	await _wait(func() -> bool: return _run_of(m) != null and str(_run_of(m).state) == RW.ST_QUEUE \
		and m.find_child(QW.N_BOX, true, false) != null, 8000)
	var run = _run_of(m)
	m.call("_on_queue_home")
	await _frames(2)
	await _close(m)
	return run


# ───────────────────────────── H1 / H2 / H3 ─────────────────────────────
func _t_h1_h2_h3() -> void:
	print("── H1 排队中按「←」⇒ 会话搬到 root、心跳不断 / H2 主菜单补查不出队 / H3 回匹配屏认领同一个会话 ──")
	_reset_sc({})
	_park()
	var m := await _open_mmk()
	var queued := await _wait(func() -> bool: return _run_of(m) != null and str(_run_of(m).state) == RW.ST_QUEUE \
		and m.find_child(QW.N_BOX, true, false) != null, 8000)
	_ok("H1 分母: 进了队、等待界面在", queued, str(_hit(JOIN)))
	var back: Button = m.get("_cancel_btn")
	var box: Node = m.find_child(QW.N_BOX, true, false)
	_ok("H1 排队屏上「←」可见，且顶栏压在等待界面上面（顶栏的序号更大）",
		back != null and back.is_visible_in_tree() and box != null and back.get_parent().get_index() > box.get_index(),
		"%s / %s" % [str(back.get_parent().get_index()) if back != null else "-", str(box.get_index()) if box != null else "-"])
	var hint := m.find_child(QW.N_HOME_HINT, true, false) as Label
	_ok("H1 等待界面有「可返回主页」那一行", hint != null and hint.text == QW.TXT_HOME_HINT and hint.is_visible_in_tree())
	var run = _run_of(m)
	if back != null:
		back.pressed.emit()
	await _frames(2)
	_ok("H1 按「←」⇒ 会话搬到 root、名 GauntletSession、active 指向它",
		run != null and is_instance_valid(run) and run.get_parent() == get_tree().root and str(run.name) == RUN.ROOT_NAME
		and _active() == run, str(run.get_parent()) if run != null and is_instance_valid(run) else "freed")
	_ok("H1 匹配屏走到「回主菜单」出口、自己不再引用会话", m.get("_ref_run") == null)
	await _close(m)
	var p0 := _hit(POLL)
	await _wait(func() -> bool: return _hit(POLL) >= p0 + 2, 7000)
	_ok("H1 ★匹配屏离场后心跳照样到服务器（≥ 2 次 / 约 5 秒）", _hit(POLL) >= p0 + 2, "%d → %d" % [p0, _hit(POLL)])
	_ok("H1 queue_locked() 为真（背包 / 商店等据此锁住）", RW.queue_locked() and RW.session_alive())
	_ok("H1 排队单还在（没被当成离开销掉）", RW.is_queue_bill(_gs.referee_pending), str(_gs.referee_pending))
	var c0 := _hit(CANCEL)
	var sent := RW.resume_if_any()
	await _frames(10)
	_ok("H2 ★会话活着 ⇒ 主菜单补查不发、不出队", not sent and _hit(CANCEL) == c0 and _active() == run,
		"sent=%s cancel %d → %d" % [str(sent), c0, _hit(CANCEL)])
	var j0 := _hit(JOIN)
	var m2 := await _open_mmk()
	await _wait(func() -> bool: return m2.find_child(QW.N_BOX, true, false) != null, 5000)
	_ok("H3 回匹配屏 ⇒ 认领同一个会话（不重新进队）、搬回匹配屏下面、等待界面照画",
		_run_of(m2) == run and run.get_parent() == m2 and _hit(JOIN) == j0 and m2.find_child(QW.N_BOX, true, false) != null,
		"join %d → %d" % [j0, _hit(JOIN)])
	## 收尾：从这一屏按「取消匹配」出队（陪练号也走这条）
	m2.call("_on_queue_back")
	await _wait(func() -> bool: return _active() == null or str(run.state) == RW.ST_LEFT, 5000)
	await _close(m2)
	_ok("H3 收尾: 取消出队后 queue_locked() 为假", not RW.queue_locked())


# ───────────────────────────── H4 R2 ─────────────────────────────
func _t_h4() -> void:
	print("── H4 ★在 root 上配上 ⇒ 先换场景再落任务单（R2）──")
	_reset_sc({})
	var run = await _queue_then_home()
	_ok("H4 分母: 回了主页、会话在 root 上排队", _active() == run and str(run.state) == RW.ST_QUEUE)
	_park()
	_gs.dual_opponent = {}
	_sc["pair"] = true
	var found := await _wait(func() -> bool: return _active() != null and str(_active().state) == RW.ST_FOUND, 6000)
	_ok("H4 配上那一刻 ⇒ 状态 found、锁仍在", found and RW.queue_locked(), str(run.state))
	_ok("H4 ★那一刻不落任务单（单子仍是排队单，没有任务号）", RW.is_queue_bill(_gs.referee_pending)
		and int((_gs.referee_pending as Dictionary).get("job_id", -1)) <= 0, str(_gs.referee_pending))
	## 遮罩约 1.5 秒后换到匹配屏（SceneNav.go 是 deferred 换场景）⇒ 匹配屏认领、落任务单、查任务
	var ok := await _wait(func() -> bool:
		var cs := get_tree().current_scene
		return cs != null and cs != _stub and _run_of(cs) == run and int((_gs.referee_pending as Dictionary).get("job_id", -1)) == _job, 9000)
	var cs := get_tree().current_scene
	_ok("H4 换到匹配屏、认领同一个会话、这时才落任务单（任务号 = 服务端那一局）", ok,
		"scene=%s bill=%s" % [str(cs.name) if cs != null else "-", str(_gs.referee_pending)])
	_ok("H4 接回原来那条：查任务、状态 wait", _hit(STATUS) >= 1 and str(run.state) == RW.ST_WAIT, "%d / %s" % [_hit(STATUS), str(run.state)])
	## 玩家刚看过「匹配成功」遮罩 ⇒ 匹配屏不再演「匹配中 · 正在匹配对手」找对手动画（那一幕与遮罩自相矛盾）
	await _frames(3)
	var searching := false
	for l in cs.find_children("*", "Label", true, false):
		if (l as Label).text == "匹配中" and (l as Label).is_visible_in_tree():
			searching = true
	_ok("H4 ★认领已配上的那一局 ⇒ 没有「匹配中」找对手那一幕、对手卡已备好（VS 卡）", not searching
		and not (_gs.dual_opponent as Dictionary).is_empty(), "searching=%s opp=%s" % [str(searching), str(_gs.dual_opponent.keys())])
	_ok("H4 锁解开（不在排队了）", not RW.queue_locked())
	await _close(cs)
	_gs.referee_pending = {}


# ───────────────────────────── H5 ─────────────────────────────
func _t_h5() -> void:
	print("── H5 在 root 上被服务端判离开 ⇒ 主菜单那句话、会话自删、锁解开 ──")
	_reset_sc({})
	RW.notice = ""
	var run = await _queue_then_home()
	_ok("H5 分母: 会话在 root 上排队", _active() == run)
	_sc["poll_end"] = "expired"
	var gone := await _wait(func() -> bool: return _active() == null, 6000)
	_ok("H5 ★会话自删、active 空、锁解开", gone and not RW.queue_locked() and not RW.session_alive())
	_ok("H5 主菜单要飘的那句 = 「已退出排队」", RW.notice == RW.TXT_QUEUE_LEFT, RW.notice)
	_ok("H5 排队单销掉", (_gs.referee_pending as Dictionary).is_empty(), str(_gs.referee_pending))
	RW.notice = ""


# ───────────────────────────── H6 U7 ─────────────────────────────
func _t_h6() -> void:
	print("── H6 切后台回来：超过 10 秒且已过期 ⇒ 自动重排；3 秒 ⇒ 不重排 ──")
	_reset_sc({})
	var run = await _queue_then_home()
	_ok("H6 分母: 会话在 root 上排队、join 1 次", _active() == run and _hit(JOIN) == 1, str(_hit(JOIN)))
	## 短的：3 秒
	run._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	run.set("_paused_ms", Time.get_ticks_msec() - 3000)
	_sc["poll_end"] = "expired"
	run._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await _wait(func() -> bool: return _active() == null, 6000)
	_ok("H6 对照: 切后台 3 秒回来就过期 ⇒ 不重排（照原来「已退出排队」）", _active() == null and _hit(JOIN) == 1,
		"join=%d" % _hit(JOIN))
	RW.notice = ""
	## 长的：11 秒
	_reset_sc({})
	run = await _queue_then_home()
	run._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	run.set("_paused_ms", Time.get_ticks_msec() - 11000)
	_sc["poll_end"] = "expired"
	run._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	var again := await _wait(func() -> bool: return _hit(JOIN) == 2 and _active() != null and str(_active().state) == RW.ST_QUEUE, 6000)
	_ok("H6 ★切后台 11 秒回来、心跳回已过期 ⇒ 自动重排（join 第 2 次、回到排队中、会话还是它）",
		again and _active() == run, "join=%d state=%s" % [_hit(JOIN), str(_active().state) if _active() != null else "freed"])
	if _active() != null:
		_active().call("cancel_queue")
	await _wait(func() -> bool: return _active() == null, 5000)
	RW.notice = ""


func _finish() -> void:
	print("")
	print("共 %d 项 · FAIL %d" % [_n, _fail])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)
