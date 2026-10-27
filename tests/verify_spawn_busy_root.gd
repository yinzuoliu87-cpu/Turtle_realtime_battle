extends Node
## verify_spawn_busy_root.gd —— 换场景那一刻发起的联网请求不许被吞(2026-10-27)。
##
## 由来: v0.22.1 内测服陪练号 p01 首次上线(服务器 /var/lib/turtle-bots-beta/p01/last.log):
##   教程结束 → 离开背包, 引擎报
##     ERROR: Parent node is busy setting up children, `add_child()` failed.
##       [0] _spawn (supabase.gd:1544)  [1] call_rpc (friends_net.gd:69)
##       [2] put_lineup (friends_net.gd:121)  [3] _exit_tree (InventoryScene.gd:1085)
##   那次 put_lineup 没发出去(内测服库里该号 lineups 0 行, 只读查实)。
## 根因: Godot 4.4 起 `change_scene_to_*` 当场 `root.remove_child(旧场景)` ⇒ 旧场景的 `_exit_tree` 跑在 root「忙」的那一刻;
##   `SupabaseNet._spawn` 同步 `root.add_child` 被引擎拒 ⇒ 节点不在树上 ⇒ `_send` 判 `not is_inside_tree()` 回失败 ⇒ 请求被吞。
##   同一类早在三个屏各绕过一次(排行榜 / 赛况板 / 对阵图把 `_ready` 里的请求 call_deferred), 但 `_spawn` 本身一直没修。
##
## 本测起一个只听 127.0.0.1 的最小 HTTP 服务(tests/_route_http.gd)当服务器, 请求一律走产品真入口(真 HTTPRequest),
##   计数在服务器那边数(注入传输层量不到这个 bug: 注入的传输不需要节点在树上, 旧代码照样「发得出去」)。
##   A 旧场景 `_exit_tree` 里 `FriendsNet.put_lineup`(InventoryScene._exit_tree 调的就是它)⇒ 服务器收到 1 次、回调 ok
##   B 新场景 `_ready` 里 `FriendsNet.call_rpc("friend_list")` ⇒ 服务器收到 1 次、回调 ok
##   C 真背包 res://scenes/Inventory.tscn 当当前场景, 换场景离开 ⇒ 服务器收到 put_lineup、`_last_put` 记上(= 回包确认了)
##   D 全程引擎没报「Parent node is busy」
##   E 推迟挂树后带看门狗的读(`fetch_match` / `_get_once` 当场挂 Timer)照常发出、回调恰好一次、引擎不报「不在树上」
##   F 看门狗本身还在走: 服务器慢 ⇒ 按看门狗时限回 timeout(Timer 没被推迟挂树弄丢)
## 反向验证: 把 `_spawn` 改回同步 `root.add_child(n)` ⇒ A / C / D 红(见方案书外的报告原文); 看门狗改回 `tm.start()` ⇒ E / F 红。

const SB := preload("res://scripts/net/supabase.gd")
const NR := preload("res://scripts/net/net_route.gd")
const FN := preload("res://scripts/net/friends_net.gd")
const H := preload("res://tests/_route_http.gd")
const Probe := preload("res://tests/_busy_root_probe.gd")
const STATUS := "/rest/v1/service_status?select=*&limit=1"
const MATCH_ID := "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

var _fail := 0
var _n := 0
var _srv: Node = null
var _save := "user://busy_root_gate.cfg"


class ErrTap extends Logger:
	var busy := 0
	var tree := 0
	var other := 0
	var first_busy := ""
	var first_other := ""
	var mx := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		var s := code + " | " + rationale
		mx.lock()
		if s.contains("busy setting up children") or s.contains("busy adding/removing children"):
			busy += 1
			if first_busy == "":
				first_busy = s.substr(0, 200)
		elif s.contains("not inside the scene tree") or s.contains("is_inside_tree()"):
			tree += 1
			if first_other == "":
				first_other = s.substr(0, 200)
		else:
			other += 1
			if first_other == "":
				first_other = s.substr(0, 200)
		mx.unlock()


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


## 墙钟上限(CLAUDE.md §3.5: 等网络回调用墙钟, 不用帧数)。
func _wait(pred: Callable, ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		if pred.call():
			return true
		await get_tree().process_frame
	return pred.call()


## 用裸 HTTPRequest 把假服务器打到回 2xx 为止(同 verify_net_route_failover `_warm`: CI 上刚 listen 的第一发会被丢)。
func _warm() -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000:
		var hr := HTTPRequest.new()
		add_child(hr)
		var box := {"code": -1}
		hr.request_completed.connect(func(_r0, code, _h, _b) -> void: box["code"] = code)
		if hr.request(_srv.base() + STATUS) == OK:
			await _wait(func() -> bool: return int(box["code"]) >= 0, 3000)
		hr.queue_free()
		if int(box["code"]) >= 200 and int(box["code"]) < 300:
			return true
		await get_tree().process_frame
	return false


func _posts(fn: String) -> int:
	return _srv.count("POST", "/rest/v1/rpc/" + fn)


## 一个只挂替身脚本的场景(钩子在类上, 由调用方在换场景前设)。
func _probe_scene(nm: String) -> PackedScene:
	var p := Probe.new()
	p.name = nm
	var ps := PackedScene.new()
	ps.pack(p)
	p.free()
	return ps


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	print("=== verify_spawn_busy_root ===")
	var gs = get_node("/root/GameState")
	gs.test_mode = true          # 不写盘(只在 C 离开背包那一下放开, 见下)
	gs.tutorial_active = false
	gs.season_leaders = ["basic", "stone", "bamboo"]
	_srv = H.new()
	add_child(_srv)
	_ok("分母: 本地服务器起来了", _srv.start(19431), str(_srv.port))
	_ok("分母: 本地服务器真能应答(热身)", await _warm())
	_srv.rpc_body = "{\"ok\":true}"
	NR._reset_for_test()
	NR.routes_override = PackedStringArray([_srv.base()])
	NR.save_path_override = _save
	SB._reset_for_test()
	SB._reset_auth_for_test()
	SB._transport_for_test = Callable()      # ★真 HTTPRequest(注入传输量不到「节点不在树上」)
	SB._token = "gate-token"                 # 令牌新鲜 ⇒ `_await_token` 当场放行(与服务器上那次一样)
	SB._expires_at = 0
	_ok("分母: 后端指到本地服务器", SB.enabled() and SB.base_url() == _srv.base(), SB.base_url())
	_srv.reqs.clear()
	var tap := ErrTap.new()
	OS.add_logger(tap)
	var f0 := Engine.get_process_frames()

	await _part_ab(tap)
	await _part_c(gs, tap)
	await _part_ef(tap)

	print("-- D 全程")
	## 断言名不写引擎原句: run-tests.sh 的致命正则含那句, 名字里写了会被当成报错。
	_ok("D 引擎没报「根节点忙、挂树被拒」", tap.busy == 0, "%d 条  %s" % [tap.busy, tap.first_busy])
	_ok("D 引擎没报「不在树上」", tap.tree == 0, "%d 条  %s" % [tap.tree, tap.first_other])
	print("  (其余引擎报错 %d 条, 只打印不判: %s)" % [tap.other, tap.first_other])
	print("  (用了 %d 帧)" % (Engine.get_process_frames() - f0))
	OS.remove_logger(tap)
	NR._reset_for_test()
	NR.routes_override = PackedStringArray()
	NR.save_path_override = ""
	SB._reset_for_test()
	SB._reset_auth_for_test()
	if FileAccess.file_exists(_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_save))
	print("=== %d 条, 失败 %d ===" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)


## A + B: 一次真换场景, 旧场景 `_exit_tree` 与新场景 `_ready` 各发一个请求。
func _part_ab(tap: ErrTap) -> void:
	print("-- A/B 换场景那一刻发请求")
	var leaving := Probe.new()
	leaving.name = "Leaving"
	get_tree().root.add_child(leaving)
	await get_tree().process_frame
	get_tree().current_scene = leaving
	var got_a: Array = []
	var got_b: Array = []
	var busy0 := tap.busy
	FN._last_put = ""
	## 钩子在 leaving 进树之后才设(否则 leaving 自己的 `_ready` 就把它用掉了)。
	Probe.on_exit = func() -> void:
		FN.put_lineup(func(r: Dictionary) -> void: got_a.append(r), true)
	Probe.on_ready = func() -> void:
		FN.call_rpc("friend_list", {}, func(r: Dictionary) -> void: got_b.append(r))
	var err := get_tree().change_scene_to_packed(_probe_scene("Arriving"))
	_ok("A 前提: 换场景成功发起", err == OK, str(err))
	_ok("A 前提: 旧场景的 _exit_tree 当场跑了(钩子已用掉)", not Probe.on_exit.is_valid())
	await _wait(func() -> bool: return got_a.size() > 0 and got_b.size() > 0, 10000)
	_ok("A 旧场景 _exit_tree 里的 put_lineup: 服务器收到 1 次", _posts("put_lineup") == 1, "收到 %d 次" % _posts("put_lineup"))
	_ok("A 回调恰好一次且成功", got_a.size() == 1 and bool((got_a[0] as Dictionary).get("ok", false)), str(got_a))
	_ok("A 换场景那一下引擎没报 busy", tap.busy == busy0, "%d 条  %s" % [tap.busy - busy0, tap.first_busy])
	_ok("B 新场景 _ready 里的 friend_list: 服务器收到 1 次", _posts("friend_list") == 1, "收到 %d 次" % _posts("friend_list"))
	_ok("B 回调恰好一次且成功", got_b.size() == 1 and bool((got_b[0] as Dictionary).get("ok", false)), str(got_b))
	Probe.on_exit = Callable()
	Probe.on_ready = Callable()


## C: 真背包当当前场景, 换场景离开(与陪练号那次同一条: InventoryScene._exit_tree → FriendsNet.put_lineup)。
func _part_c(gs, tap: ErrTap) -> void:
	print("-- C 真背包: 离开时传阵容")
	gs.season_level = 10
	gs.persistent_equipped = {"basic": [], "stone": [], "bamboo": []}
	gs.persistent_bench = []
	gs.dual_lineup = {}
	var inv = load("res://scenes/Inventory.tscn").instantiate()
	get_tree().root.add_child(inv)
	get_tree().current_scene = inv
	for _i in range(10):
		await get_tree().process_frame
	_ok("C 前提: 背包在树上、是当前场景", inv.is_inside_tree() and get_tree().current_scene == inv)
	FN._last_put = ""
	var n0 := _posts("put_lineup")
	var busy0 := tap.busy
	## ★`put_lineup` 在 test_mode 里不传(门禁不往服务器写); 这里要量的正是离开背包那一下的真路径,
	##   所以只在换场景这一下放开, 换完立刻收回(本测的 user:// 由门禁隔离)。
	gs.test_mode = false
	var err := get_tree().change_scene_to_packed(_probe_scene("AfterInventory"))
	for _i in range(2):
		await get_tree().process_frame
	gs.test_mode = true
	var gone: bool = not is_instance_valid(inv) or not inv.is_inside_tree()
	_ok("C 前提: 换场景成功发起、背包已离树", err == OK and gone, str(err))
	await _wait(func() -> bool: return _posts("put_lineup") > n0 and FN._last_put != "", 10000)
	_ok("C 离开背包: 服务器收到 put_lineup 1 次", _posts("put_lineup") == n0 + 1, "收到 %d 次" % (_posts("put_lineup") - n0))
	_ok("C 回包确认了(_last_put 记上, 下次同阵容不重传)", FN._last_put != "")
	_ok("C 离开背包那一下引擎没报 busy", tap.busy == busy0, "%d 条  %s" % [tap.busy - busy0, tap.first_busy])


## E + F: 推迟挂树之后, 自带看门狗 Timer 的两条读照常工作。
func _part_ef(tap: ErrTap) -> void:
	print("-- E/F 带看门狗的读")
	var tree0 := tap.tree
	var g0: int = _srv.count("GET", "/rest/v1/matches?")
	var got_e: Array = []
	_ok("E 前提: fetch_match 建了节点", SB.fetch_match_async(MATCH_ID, func(r: Dictionary) -> void: got_e.append(r)))
	var got_g: Array = []
	_ok("E 前提: 赛况板(_get_once)建了节点", SB.fetch_gauntlet_board_async(3000, func(r: Dictionary) -> void: got_g.append(r)))
	await _wait(func() -> bool: return got_e.size() > 0 and got_g.size() > 0, 10000)
	for _i in range(5):
		await get_tree().process_frame
	_ok("E 两条读都到了服务器", _srv.count("GET", "/rest/v1/matches?") == g0 + 2, "收到 %d 次" % (_srv.count("GET", "/rest/v1/matches?") - g0))
	_ok("E 回调各恰好一次", got_e.size() == 1 and got_g.size() == 1, "%d / %d" % [got_e.size(), got_g.size()])
	var e_err: String = str((got_e[0] as Dictionary).get("err", "")) if got_e.size() > 0 else "missing"
	_ok("E 回的不是看门狗超时 / 没令牌", not (e_err in ["timeout", "no_token", "missing"]), str(got_e))
	_ok("E 引擎没报「不在树上」(看门狗 Timer)", tap.tree == tree0, "%d 条  %s" % [tap.tree - tree0, tap.first_other])
	## F 服务器慢 3 秒、看门狗 0.5 秒 ⇒ 回 timeout(Timer 真在走)
	_srv.mode = "slow"
	_srv.delay_ms = 3000
	SB.match_fetch_timeout_for_test = 0.5
	var got_f: Array = []
	var t0 := Time.get_ticks_msec()
	SB.fetch_match_async(MATCH_ID, func(r: Dictionary) -> void: got_f.append(r))
	await _wait(func() -> bool: return got_f.size() > 0, 2500)
	var dt := Time.get_ticks_msec() - t0
	_ok("F 服务器慢 ⇒ 看门狗按时回 timeout", got_f.size() == 1 and str((got_f[0] as Dictionary).get("err", "")) == "timeout" and dt < 2500,
		"%s  %d ms" % [str(got_f), dt])
	SB.match_fetch_timeout_for_test = 0.0
	_srv.mode = "ok"
