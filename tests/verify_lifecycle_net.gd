extends Node
## verify_lifecycle_net.gd — 切后台 / 回前台时的联网动作真的发得出去(2026-10-23)
##
## 正式服报错(0.21.8 · LouisT01 手机): 「Parent node is busy setting up children, add_child() failed」,
##   栈 = supabase.gd _spawn ← fetch_status_async ← version_wall._fetch ← _notification。
## 根因: 引擎下发切后台 / 回前台 / 关窗这几条通知时, 是从根节点往下逐个传的, 根节点此刻「忙」,
##   同步 add_child 必失败 ⇒ SupabaseNet._spawn 建的请求节点进不了树、请求当场判失败。中招的:
##   · 版本墙回前台问服务状态(每次都问不到 ⇒ 记成「连不上」⇒ 墙被撤掉)
##   · 报错上报器切后台上传(切后台前攒的报错全丢)
##   · GameState 切后台推云存档、回前台续登录令牌
## 修法: 这几处一律 call_deferred 到这一帧末尾再做。
##
## ★判据为什么这么量: 原来的门禁直接调 `wall._notification(...)`, 根节点不忙 ⇒ 永远量不到这个 bug。
##   这里照引擎的真实下发方式 `root.propagate_notification(...)`, 并装一个 Logger 截引擎报错,
##   量「那条签名有没有出现」+「请求真的发出去了」(注入传输记下的地址)。

const SB := preload("res://scripts/net/supabase.gd")
const BUSY := "busy setting up children"

var _n := 0
var _fail := 0
var _urls: Array = []
var _cap: _Cap = null


class _Cap extends Logger:
	var msgs: Array = []
	var _mx := Mutex.new()
	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		_mx.lock()
		msgs.append("%s %s" % [code, rationale])
		_mx.unlock()
	# zero-caller-ok: Logger 引擎虚函数, 由引擎调
	func _log_message(_message: String, _error: bool) -> void:
		pass
	func busy_count() -> int:
		_mx.lock()
		var k := 0
		for m in msgs:
			if str(m).find(BUSY) >= 0:
				k += 1
		_mx.unlock()
		return k


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _spy(method, url, _headers, _body, cb) -> void:
	_urls.append("%s %s" % [str(method), str(url)])
	cb.call({"ok": true, "code": 200, "body": "[]"})


func _sent(path: String) -> int:
	var k := 0
	for u in _urls:
		if str(u).find(path) >= 0:
			k += 1
	return k


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	print("=== 切后台 / 回前台的联网动作 ===")
	var tm0: bool = bool(GameState.test_mode)
	var keep := {"aid": str(GameState.account_id), "mail": str(GameState.account_email), "tut": bool(GameState.tutorial_active)}
	var had_env: bool = OS.has_environment(SB.ENV_URL)
	var env0: String = OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	var tok0: String = SB._token
	var exp0: int = int(SB._expires_at)
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	SB._transport_for_test = _spy
	SB._token = "gate-token"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	_ok("★分母: 后端打开了(注入传输)", SB.enabled())
	_cap = _Cap.new()
	OS.add_logger(_cap)

	# ── ① 回前台: 版本墙问服务状态 ──
	var wall: VersionWall = GameState.get_node_or_null(VersionWall.NODE_NAME) as VersionWall
	_ok("★分母: GameState 下常驻着版本墙", wall != null)
	if wall != null:
		SB._reset_for_test()
		SB._transport_for_test = _spy
		wall._last_fetch_ms = -100000
		var a0 := SB.ask_count()
		var b0 := _cap.busy_count()
		get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_RESUMED)   # 照引擎真实下发: 从根往下传
		await _frames(6)
		_ok("★① 回前台: 版本墙真的去问了服务状态", SB.ask_count() > a0, "ask %d → %d" % [a0, SB.ask_count()])
		_ok("★★① 回前台: 没有出现正式服那条「%s」报错" % BUSY, _cap.busy_count() == b0, "新增 %d 条" % (_cap.busy_count() - b0))

	# ── ② 切后台: 推云存档(绑了邮箱的号、存档脏了) ──
	GameState.test_mode = false             # GameState 的生命周期处理在 test_mode 下不动作
	GameState.tutorial_active = false
	GameState.account_id = "gate-acc-life"
	GameState.account_email = "gate@turtle.test"
	SB._reset_save_sync_for_test()
	SB.note_save_dirty()
	_urls.clear()
	var b1 := _cap.busy_count()
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_PAUSED)
	await _frames(6)
	GameState.test_mode = true
	_ok("★② 切后台: 云存档真的推了(push_save)", _sent("/rpc/push_save") >= 1, str(_urls))
	_ok("★★② 切后台: 没有出现「%s」报错" % BUSY, _cap.busy_count() == b1, "新增 %d 条" % (_cap.busy_count() - b1))

	# ── ③ 切后台: 报错上报器把攒下的报错传上去 ──
	var rep := ErrorReporter.instance()
	_ok("★分母: 报错上报器装着", rep != null)
	if rep != null:
		rep._seen.clear()
		push_error("gate-lifecycle-probe %d" % Time.get_ticks_usec())   # 攒一条(上报器靠 Logger 收)
		await _frames(1)
		_ok("★分母: 上报器队列里真有一条待传", rep._queue.size() >= 1, "队列 %d" % rep._queue.size())
		_urls.clear()
		var b2 := _cap.busy_count()
		get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_PAUSED)
		await _frames(6)
		_ok("★③ 切后台: 报错真的传了(report_client_error)", _sent("/rpc/report_client_error") >= 1, str(_urls))
		_ok("★★③ 切后台: 没有出现「%s」报错" % BUSY, _cap.busy_count() == b2, "新增 %d 条" % (_cap.busy_count() - b2))

	OS.remove_logger(_cap)
	SB._transport_for_test = Callable()
	SB._reset_for_test()
	SB._reset_save_sync_for_test()
	SB._token = tok0
	SB._expires_at = exp0
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	if had_env:
		OS.set_environment(SB.ENV_URL, env0)
	else:
		OS.unset_environment(SB.ENV_URL)
	GameState.test_mode = tm0
	GameState.account_id = keep["aid"]
	GameState.account_email = keep["mail"]
	GameState.tutorial_active = keep["tut"]
	if wall != null:
		wall.refresh()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 切后台 / 回前台的联网动作" if _fail == 0 and _n >= 10 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
