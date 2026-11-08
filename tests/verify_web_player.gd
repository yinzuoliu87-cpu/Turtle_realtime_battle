extends Node
## verify_web_player.gd — 网页录像播放器(2026-11-08 · 方案书 docs/plans/20261105c-主站对接偷袭.md §4.7、约定 docs/specs/主站对接约定.md §4.4)。
##
## 走真入口: 播放器页 scenes/WebPlayer.tscn 原样实例化, 对局号 / 站点 / 浏览器 UA 用环境变量注入(网页上读浏览器, 见 WebPlayerScene `_read_*`),
##   站点 = 本进程起的 HTTP 服务(tests/_stream_http.gd, 按 server/player/player.caddy 的路径口径回 /player/streams/… 与 /player/expired/…)。
##   SceneNav.nav_for_test 接住换屏(不真换), 换去战斗场时门禁自己实例化战斗场 —— 播放器页挂好的 StreamPlayer.pending 由它读走, 与真换屏同一条。
##   ① 判据纯函数: 手机 UA(含 iPadOS 报桌面 UA + 多点触控)/ 对局号 / 查询串 / 存档保护第四道闸 / end.json 版本判定 —— 正反各一。
##   ② 三种错误态各一条(+ 网络失败可重试、版本不一致): 手机 ⇒「请在小游戏内观看」且一个请求都不发; 过期 ⇒「录像已过期」;
##      找不到 ⇒「未找到该对局的录像」。
##   ③ 整局播放: 裁判按 mirror 任务单录一局(块留内存, 与 verify_stream_end_exit 共用录像)→ 放到本机 HTTP 上 → 播放器页取 end.json、
##      拉第 0 块读地图种子 → 进战斗场 → 状态流从头播到尾: 应用步数 = 录的步数、finish 事件 1 次、一步 sim 都不跑、地图种子 / 主题对、
##      开局状态取自流里的 rs(换路幕布照建)、有回放操作条、收尾卡「<胜方名字> 获胜」(名字取自 end.json)。
##      不登录 / 不写数据: 进页前把后端指到一个地址(会被启用), 进页后后端整层停用、全程注入的传输一条请求都没收到;
##      本机 HTTP 只收到这一局的 /player/streams/… 请求; user://(除日志)前后逐个文件相同; 离场后 GameState 与进场前相同。
##   ④ 收尾卡「返回」回播放器页 ⇒「播放结束」+「重新播放」; 点「重新播放」又进一次战斗场。
## 脚本错误由 run-tests.sh 的 FATAL 正则判(本门禁全程不许有一条)。

const J := preload("res://tests/_stream_jobs.gd")
const P := preload("res://tests/_stream_play.gd")
const HTTP := preload("res://tests/_stream_http.gd")
const SW := preload("res://scripts/systems/replay/stream_watch.gd")
const WC := preload("res://scripts/systems/replay/web_player_core.gd")
const RC := preload("res://scripts/scenes/battle/replay_controls.gd")
const SB := preload("res://scripts/net/supabase.gd")
const WPS := preload("res://scripts/scenes/WebPlayerScene.gd")
const SIM_DT := 1.0 / 60.0
const UA_DESK := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
const UA_IPHONE := "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1"
const UA_ANDROID := "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"
const UA_MAC := "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15"
const MID_EXPIRED := "0b7e9a52-3c41-4d8e-9f60-2a1b3c4d5e6f"
const MID_NONE := "7d2c4e81-9a3b-4c5d-8e6f-1a2b3c4d5e6f"
const MID_OLDVER := "5a6b7c8d-1e2f-4a3b-9c4d-5e6f7a8b9c0d"

var _fail := 0
var _n := 0
var _srv: Node = null
var _nav: Array = []
var _sb_calls: Array = []


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
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	_pure()
	_srv = HTTP.new()
	add_child(_srv)
	_ok("分母 · 本机 HTTP 起来了", _srv.start(), "port %d" % _srv.port)
	OS.set_environment(WC.ENV_ORIGIN, "http://127.0.0.1:%d" % _srv.port)
	SceneNav.nav_for_test = func(path: String) -> void: _nav.append(path)
	await _errors()
	await _full_play()
	SceneNav.nav_for_test = Callable()
	SB._transport_for_test = Callable()
	_finish()


# ── ① 判据纯函数 ────────────────────────────────────────
func _pure() -> void:
	print("=== ① 判据 ===")
	_ok("手机 UA: iPhone / Android 判为手机", WC.is_mobile(UA_IPHONE, 5) and WC.is_mobile(UA_ANDROID, 5))
	_ok("★iPadOS(报桌面 Mac UA + 多点触控)判为手机; 真 Mac(没有触控)不是", WC.is_mobile(UA_MAC, 5) and not WC.is_mobile(UA_MAC, 0))
	_ok("电脑浏览器(带触屏的 Windows 也算电脑)不是手机", not WC.is_mobile(UA_DESK, 0) and not WC.is_mobile(UA_DESK, 10))
	_ok("对局号: 大写 / 带空白规范成小写 uuid; 不像样的给空",
		WC.norm_match_id(" 6F1C2A3B-4D5E-4F60-8A7B-9C0D1E2F3A4B ") == "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
		and WC.norm_match_id("../etc/passwd") == "" and WC.norm_match_id("") == "" and WC.norm_match_id("6f1c2a3b") == "")
	_ok("查询串取 match(带别的参数 / 编码)", WC.query_param("?a=1&match=6f1c%2Da&hop=1", "match") == "6f1c-a"
		and WC.query_param("?hop=1", "match") == "" and WC.query_param("", "match") == "")
	var gs = get_node_or_null("/root/GameState")
	_ok("★存档保护第四道闸: 网页播放器 ⇒ 开(原因 web_player); 其余三项都不沾时不开",
		str(gs.save_guard_reason(false, false, "", true)) == WebPlayerMode.FEATURE and str(gs.save_guard_reason(false, false, "", false)) == "")
	var ver := ReplayRecorder.client_version()
	var good := {"chunks": 3, "client_version": ver, "format": StreamFormat.VERSION}
	var oldv := good.duplicate()
	oldv["client_version"] = "0.0.1"
	var oldf := good.duplicate()
	oldf["format"] = StreamFormat.VERSION - 1
	_ok("end.json 判定: 这一版 ⇒ 能播; 别的版本 / 别的格式 ⇒ version; 没有块 ⇒ bad",
		WC.check_end(good, ver) == "" and WC.check_end(oldv, ver) == "version" and WC.check_end(oldf, ver) == "version"
		and WC.check_end({"chunks": 0, "client_version": ver, "format": StreamFormat.VERSION}, ver) == "bad" and WC.check_end({}, ver) == "bad")


# ── ② 错误态 ───────────────────────────────────────────
func _errors() -> void:
	print("=== ② 错误态 ===")
	_srv.expired[MID_EXPIRED] = true
	_srv.put(MID_OLDVER, [PackedByteArray([1])], {"chunks": 1, "client_version": "0.0.1", "format": StreamFormat.VERSION})
	## 手机: 一个请求都不发(不下载录像)
	var r0: int = _srv.reqs.size()
	var wp := await _open(MID_NONE, UA_IPHONE, 5)
	_ok("★★手机浏览器 ⇒「%s」、一个请求都不发" % WC.TXT_MOBILE,
		wp.state == "mobile" and _status(wp) == WC.TXT_MOBILE and wp.requests.is_empty() and _srv.reqs.size() == r0,
		"state=%s 「%s」 页面请求 %d / 服务端收到 %d" % [wp.state, _status(wp), wp.requests.size(), _srv.reqs.size() - r0])
	_close(wp)
	## 过期: end.json 404 → 过期记号 200
	wp = await _open(MID_EXPIRED, UA_DESK, 0)
	_ok("★★过了保留期(end.json 404、过期记号 200)⇒「%s」" % WC.TXT_EXPIRED,
		wp.state == "expired" and _status(wp) == WC.TXT_EXPIRED and _codes(wp) == [404, 200], "state=%s 「%s」 %s" % [wp.state, _status(wp), str(wp.requests)])
	_close(wp)
	## 找不到: 两个都 404
	wp = await _open(MID_NONE, UA_DESK, 0)
	_ok("★★找不到这一局(end.json 404、过期记号 404)⇒「%s」" % WC.TXT_NOT_FOUND,
		wp.state == "not_found" and _status(wp) == WC.TXT_NOT_FOUND and _codes(wp) == [404, 404], "state=%s 「%s」 %s" % [wp.state, _status(wp), str(wp.requests)])
	_close(wp)
	## 对局号不像样: 不发请求
	wp = await _open("not-a-match", UA_DESK, 0)
	_ok("对局号不像样 ⇒「%s」、不发请求" % WC.TXT_NOT_FOUND, wp.state == "not_found" and wp.requests.is_empty())
	_close(wp)
	## 版本不一致(桌面上没有入口页可回)
	wp = await _open(MID_OLDVER, UA_DESK, 0)
	_ok("录像不是这一版录的 ⇒「%s」、不拉块" % WC.TXT_VERSION, wp.state == "version" and _status(wp) == WC.TXT_VERSION and _codes(wp) == [200],
		"state=%s %s" % [wp.state, str(wp.requests)])
	_close(wp)
	## 网络失败 ⇒ 可重试; 重试时通了 ⇒ 接着判
	_srv.mode = "500"
	wp = await _open(MID_EXPIRED, UA_DESK, 0)
	var btn := wp.find_child(WPS.N_BUTTON, true, false) as Button
	var off_ok: bool = wp.state == "offline" and _status(wp) == WC.TXT_OFFLINE and btn != null and btn.visible and btn.text == WC.BTN_RETRY
	_srv.mode = "ok"
	if btn != null:
		btn.pressed.emit()
	await _settle(wp)
	_ok("网络失败(5xx)⇒「%s」+「%s」; 点了重试、通了之后接着判(这里 = 过期)" % [WC.TXT_OFFLINE, WC.BTN_RETRY], off_ok and wp.state == "expired",
		"state=%s" % wp.state)
	_close(wp)


# ── ③④ 整局播放 ────────────────────────────────────────
func _full_play() -> void:
	print("=== ③ 整局播放 ===")
	var gs = get_node_or_null("/root/GameState")
	gs.tutorial_active = false
	gs.test_mode = true
	var job: Dictionary = J.mirror(gs)
	var nat: Dictionary = await P.record_referee_shared(self, job)
	var res: Dictionary = nat["res"]
	var chunks: Array = res.get("stream_chunks", [])
	var meta: Dictionary = (res.get("stream", {}) as Dictionary).duplicate(true)
	var mid := str(job["match_id"])
	_ok("分母 · 裁判录了一局(三路打满、块 > 100)", bool(res.get("ok", false)) and int(res.get("fights", 0)) == 3 and chunks.size() > 100, "块 %d" % chunks.size())
	_ok("end.json 带上了网页播放器要的名字 / 路名刻度 / 模式",
		(meta.get("names", {}) as Dictionary).get("l", "") == "甲方" and (meta.get("names", {}) as Dictionary).get("r", "") == "乙方"
		and (meta.get("fights", []) as Array).size() == 3 and str(meta.get("mode", "")) == "gauntlet", "%s %s %s" % [str(meta.get("names")), str(meta.get("fights")), str(meta.get("mode"))])
	var won_l: bool = _server_won(res)
	_srv.put(mid, chunks, meta)
	gs.test_mode = false          # 进页之前: 看的人自己的进程(非测试模式), 由播放器页与 begin_play 接管
	var before: Dictionary = ReplayRecorder.capture_all()
	var files0 := _user_files()
	## 进页前把后端指到一个地址(会被启用)+ 注入传输记下每一条: 进页之后必须整层停用、一条都不发
	OS.set_environment("TURTLE_SUPABASE", "http://127.0.0.1:%d/sb" % _srv.port)
	SB._transport_for_test = func(method, url, _h, _body, cb) -> void:
		_sb_calls.append("%s %s" % [str(method), str(url)])
		if cb is Callable and (cb as Callable).is_valid():
			(cb as Callable).call({"ok": false, "code": 0, "body": ""})
	var sb_before: bool = SB.enabled()
	var r0: int = _srv.reqs.size()
	_nav.clear()
	var wp := await _open(mid, UA_DESK, 0, 2400)
	_ok("分母 · 进页前后端是开着的(这条不成立, 下一条就是空检查)", sb_before)
	_ok("★★进了播放器页 ⇒ 后端整层停用(不登录)", not SB.enabled())
	_ok("★播放器页取了 end.json、拉到第 0 块读出地图种子、换去战斗场",
		wp.state == "playing" and _codes(wp) == [200] and int(wp.map_seed) == int(nat.get("seed", -1)) and _nav == [ReplayRecorder.BATTLE_SCENE],
		"state=%s 种子 %d(任务单 %d) 换屏 %s 请求 %s 服务端收到 %d" % [wp.state, int(wp.map_seed), int(nat.get("seed", -1)), str(_nav), str(wp.requests), _srv.reqs.size() - r0])
	_close(wp)
	if _nav != [ReplayRecorder.BATTLE_SCENE]:
		return
	## ── 换屏: 战斗场(当前场景, 守卫按它认)──
	var b: Node = (load(ReplayRecorder.BATTLE_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(b)
	get_tree().current_scene = b
	b.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	_ok("分母 · 战斗场是状态流播放模式", p != null and str(b._replay.mode) == "stream")
	if p == null:
		return
	_ok("★回放操作条(暂停 / 倍速 / 进度条)开着, 会话 = 回放", p.controls and str(SW.current.get("kind", "")) == SW.KIND_REPLAY and bool(SW.current.get("web", false)))
	var guard := 0
	while p.state != "ended" and p.state != "error" and guard < 60000:
		guard += 1
		p.advance(2.0 * SIM_DT)
		if guard % 20 == 0 or p.state == "stalled" or p.state == "buffering":
			await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var ui = b._hud._replay_ui
	while Time.get_ticks_msec() - t0 < 5000:
		p.advance(SIM_DT)
		await get_tree().process_frame
		if ui != null and ui.card != null:
			break
	_ok("★★状态流从头播到尾(应用 %d / %d 步、finish %d 次、sim %d 步、状态 %s)" % [int(p.steps_applied), int(meta.get("steps", 0)),
		int(p.events.get("finish", 0)), int(b._sim_step_n), p.state],
		p.state == "ended" and p.steps_applied == int(meta.get("steps", 0)) and int(p.events.get("finish", 0)) == 1 and int(b._sim_step_n) == 0)
	_ok("★地图种子 / 主题与服务器那一局相同(种子取自第 0 块)", not p.seed_mismatch() and not p.theme_mismatch(), "%s / %s" % [p._theme_seen, ArenaTheme.active])
	_ok("★开局状态取自流里的 rs(换路幕布照建)", p.state_from_stream)
	var http_ok := true
	for r in _srv.reqs.slice(r0):
		if not str(r[0]).begins_with("/player/streams/%s/" % mid):
			http_ok = false
	_ok("★★本机 HTTP 只收到这一局的 /player/streams/… 请求(块 %d 个)" % _srv.count(200, ".bin"), http_ok and _srv.count(200, ".bin") == chunks.size(),
		str(_srv.reqs.slice(r0, r0 + 3)))
	var card = ui.card if ui != null else null
	var title := ""
	if card != null and is_instance_valid(card):
		var tl = card.find_child("ReplayResult", true, false)
		title = (tl as Label).text if tl != null else ""
	var want_title := "%s 获胜" % ("甲方" if won_l else "乙方")
	_ok("★★收尾卡「%s」(胜方名字取自 end.json)" % want_title, title == want_title, "标题「%s」" % title)
	## ── ④ 收尾卡「返回」⇒ 回播放器页 ──
	var back := card.find_child(RC.N_BACK, true, false) as Button if card != null else null
	_nav.clear()
	if back != null:
		back.pressed.emit()
	await get_tree().process_frame
	_ok("★收尾卡「返回」⇒ 回播放器页", _nav == [WebPlayerMode.SCENE], str(_nav))
	get_tree().current_scene = self
	b.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("★★全程注入的传输一条请求都没收到(不登录、不推云存档)", _sb_calls.is_empty(), str(_sb_calls.slice(0, 3)))
	var files1 := _user_files()
	var fdiff: Array = []
	for k in files0:
		if str(files0[k]) != str(files1.get(k, "")):
			fdiff.append(k)
	for k in files1:
		if not files0.has(k):
			fdiff.append(k)
	_ok("★★user://(除日志)一个文件都没变(比了 %d 个)" % files0.size(), fdiff.is_empty(), str(fdiff.slice(0, 5)))
	SW.current = {}
	ReplayRecorder.play_names = {}
	var after: Dictionary = ReplayRecorder.capture_all()
	var diffk: Array = []
	for k in before:
		if str(before[k]) != str(after.get(k)):
			diffk.append(str(k))
	_ok("★离场后 GameState 与进场前相同(比了 %d 项)" % before.size(), before.size() > 20 and diffk.is_empty(), str(diffk.slice(0, 6)))
	_ok("★离场后存档保护仍开着(网页播放器从不恢复存档)", bool(gs.test_mode))
	## 回到播放器页: 播放结束 + 重新播放
	_nav.clear()
	wp = await _open(mid, UA_DESK, 0)
	var btn := wp.find_child(WPS.N_BUTTON, true, false) as Button
	_ok("★回到播放器页 ⇒「%s」+「%s」(不自动再放)" % [WC.TXT_ENDED, WC.BTN_REPLAY],
		wp.state == "ended" and _status(wp) == WC.TXT_ENDED and btn != null and btn.visible and btn.text == WC.BTN_REPLAY and _nav.is_empty())
	var e0: int = SW.web_enters
	if btn != null:
		btn.pressed.emit()
	await _settle(wp, 2400)
	_ok("点「重新播放」⇒ 又进一次战斗场", wp.state == "playing" and SW.web_enters == e0 + 1 and _nav == [ReplayRecorder.BATTLE_SCENE], "state=%s %s" % [wp.state, str(_nav)])
	_close(wp)
	## 收拾: 第二次进场挂好的待播 / 守卫 / 沙盒都撤掉
	StreamPlayer.pending = {}
	for c in get_tree().root.get_children():
		if c is SW.Guard:
			(c as SW.Guard).retire()
	ReplayRecorder.end_play()
	SW.current = {}
	WC.last_played = ""
	OS.set_environment("TURTLE_SUPABASE", " ")


# ── 工具 ───────────────────────────────────────────────
func _open(mid: String, ua: String, touch: int, max_frames: int = 600) -> Node:
	OS.set_environment(WC.ENV_MATCH, mid)
	OS.set_environment(WC.ENV_UA, ua)
	OS.set_environment(WC.ENV_TOUCH, str(touch))
	var wp: Node = (load(WebPlayerMode.SCENE) as PackedScene).instantiate()
	add_child(wp)
	await _settle(wp, max_frames)
	return wp


## 等页面停在一个终态(或已进场)。
func _settle(wp: Node, max_frames: int = 600) -> void:
	for _i in range(max_frames):
		await get_tree().process_frame
		if not (str(wp.state) in ["", "checking", "loading"]):
			return


func _close(wp: Node) -> void:
	if wp != null and is_instance_valid(wp):
		wp.queue_free()


func _status(wp: Node) -> String:
	var l := wp.find_child(WPS.N_STATUS, true, false) as Label
	return l.text if l != null else ""


func _codes(wp: Node) -> Array:
	var out: Array = []
	for r in wp.requests:
		out.append(int(r[1]))
	return out


## user:// 下每个文件 → 「大小 / 修改时刻」(日志目录除外: 引擎自己在写)。
func _user_files() -> Dictionary:
	var out := {}
	var stack: Array = ["user://"]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		for sub in da.get_directories():
			if d == "user://" and sub == "logs":
				continue
			stack.append(d.path_join(sub))
		for f in da.get_files():
			var p := d.path_join(f)
			var fa := FileAccess.open(p, FileAccess.READ)
			var sz := fa.get_length() if fa != null else -1
			out[p] = "%d/%d" % [sz, FileAccess.get_modified_time(p)]
	return out


## 服务器结果单的胜负(左 = A 方), 口径同 verify_stream_end_exit。
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


func _finish() -> void:
	print("")
	print("  [量] 用了 %d 帧" % Engine.get_process_frames())
	if _fail == 0:
		print("ALL PASS — 网页录像播放器: 三种错误态 + 整局从头播到尾、不登录不写数据 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
