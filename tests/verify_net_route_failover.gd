extends Node
## verify_net_route_failover.gd — 大陆中转第一阶段: 客户端多入口选路(scripts/net/net_route.gd + supabase.gd `_http` / `_send`)。
## 方案书 docs/plans/20261020-大陆中转.md §3 / 验收清单「客户端多入口选路」。
##
## 本进程起两个最小 HTTP 服务(tests/_route_http.gd, 只听 127.0.0.1)当「直连」与「中转」两条入口,
##   请求一律走产品真入口 `SupabaseNet._http`(真 HTTPRequest、真请求头), 计数在服务端那边数(不数我自己的日志)。
##
## 段落:
##   F 纯函数: 传输失败只认 code 0 / 结果不成功(426 / 401 / 500 不算)、能换路重发的只有只读、入口表(门禁空白 ⇒ 一条都没有)
##   R 竞速: ① 直连断开、中转通 ⇒ 选中转, 直播跟着走中转, 存盘 ② 两条都通、中转慢 ⇒ 选直连
##     ③ 第一次启动(没存过)⇒ 真请求等竞速出结果再发, 只发到胜出那条 ④ 存过 ⇒ 不等, 直接用上次那条
##   S 换路: ① 直连断开 ⇒ 只读请求当场换中转重发拿到 200; 连着 2 次 ⇒ 当前入口换成中转
##     ② 写请求(POST 表 / 写 RPC / 登录续期)在直连断开 ⇒ 中转收到 0 次、回调拿到失败
##     ③ 426 / 401 ⇒ 不换路、不重发(中转 0 次)
## 反向验证见方案书回填(把「只认传输失败」改成「非 2xx 都算」⇒ S3 红; retry_safe 恒真 ⇒ S2 红; 竞速认第一个回来的 ⇒ R1 红)。

const SB := preload("res://scripts/net/supabase.gd")
const NR := preload("res://scripts/net/net_route.gd")
const SW := preload("res://scripts/systems/replay/stream_watch.gd")
const H := preload("res://tests/_route_http.gd")
const STATUS := "/rest/v1/service_status?select=*&limit=1"

var _fail := 0
var _n := 0
var _d: Node = null     # 直连
var _r: Node = null     # 中转
var _save := "user://net_route_gate.cfg"


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


## 走产品真入口发一次, 等回调(墙钟上限)。回 {} = 超时没回。
func _req(method: String, path: String, body: String = "", extra: String = "") -> Dictionary:
	var box := {"res": {}, "done": false}
	var n = SB._spawn()
	if n == null:
		return {}
	await get_tree().process_frame
	n._http(method, SB.base_url() + path, body, func(res: Dictionary) -> void:
		box["res"] = res
		box["done"] = true, extra)
	await _wait(func() -> bool: return bool(box["done"]), 20000)
	if is_instance_valid(n):
		n.queue_free()
	return box["res"]


## 用裸 HTTPRequest(不走 NetRoute / Supabase 层)把一台假服务器打到回 2xx 为止。
func _warm(srv: Node) -> bool:
	srv.mode = "ok"
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000:
		var hr := HTTPRequest.new()
		add_child(hr)
		var box := {"code": -1}
		hr.request_completed.connect(func(_r0, code, _h, _b) -> void: box["code"] = code)
		if hr.request(srv.base() + STATUS) == OK:
			await _wait(func() -> bool: return int(box["code"]) >= 0, 3000)
		hr.queue_free()
		if int(box["code"]) >= 200 and int(box["code"]) < 300:
			return true
		await get_tree().process_frame
	return false


func _fresh(dmode: String, rmode: String, saved: String = "") -> void:
	NR._reset_for_test()
	NR.routes_override = PackedStringArray([_d.base(), _r.base()])
	NR.save_path_override = _save
	if FileAccess.file_exists(_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_save))
	if saved != "":
		var cf := ConfigFile.new()
		cf.set_value("route", "base", saved)
		cf.save(_save)
	_d.mode = dmode
	_r.mode = rmode
	_d.reqs.clear()
	_r.reqs.clear()
	SB._reset_for_test()


func _hdrs() -> PackedStringArray:
	var t = SB.new()
	var h: PackedStringArray = t._headers()
	t.free()
	return h


func _race_done() -> bool:
	return NR.races > 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	print("=== verify_net_route_failover ===")
	_part_f()
	_d = H.new()
	_r = H.new()
	add_child(_d)
	add_child(_r)
	_ok("分母: 两个本地入口起来了", _d.start(18931) and _r.start(19031), "%d / %d" % [_d.port, _r.port])
	## ★热身(2026-10-21 CI 红): 开局第一发竞速在 CI 上 1 毫秒内两条都回 code 0、两台假服务器 0 次收到 ——
	##   假服务器刚 listen、还没被 _process 推过一拍就被打。本机快所以从没红过。
	##   ⇒ 先用裸 HTTPRequest 把两台各打通一次(上限 10 秒), 判据本身一字不改; _fresh 会清掉热身留下的计数。
	_ok("分母: 两个本地入口真能应答(热身)", await _warm(_d) and await _warm(_r))
	await _part_r()
	await _part_s()
	## 收尾: 还原(别的门禁同进程不会再跑, 但照样清干净)
	NR._reset_for_test()
	NR.routes_override = PackedStringArray()
	NR.save_path_override = ""
	SB._reset_for_test()
	print("=== %d 条, 失败 %d ===" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)


func _part_f() -> void:
	print("-- F 纯函数")
	_ok("F1 传输失败: code 0", NR.transport_failed({"ok": false, "code": 0}))
	_ok("F1 传输失败: 结果不成功(哪怕带了码)", NR.transport_failed({"ok": false, "code": 200}))
	for c in [426, 401, 403, 404, 500, 503]:
		_ok("F1 服务器回了 %d ⇒ 不算传输失败" % c, not NR.transport_failed({"ok": true, "code": c}))
	_ok("F1 时间穿越 / 版本墙拦下的(blocked)不算", not NR.transport_failed({"ok": false, "code": 0, "blocked": true}))
	_ok("F2 GET 可换路重发", NR.retry_safe("GET", "https://x/rest/v1/ghosts?select=*"))
	_ok("F2 只读 RPC finals_view 可换路重发", NR.retry_safe("POST", "https://x/rest/v1/rpc/finals_view"))
	_ok("F2 分母: 只读 RPC 表非空", (SB.READ_RPCS as Array).size() >= 5)
	for w in [["POST", "/rest/v1/ghosts"], ["PATCH", "/rest/v1/saves?account_id=eq.x"], ["POST", "/rest/v1/rpc/finals_report"],
			["POST", "/rest/v1/rpc/push_save"], ["POST", "/auth/v1/signup"], ["POST", "/auth/v1/token?grant_type=refresh_token"],
			["PUT", "/auth/v1/user"], ["DELETE", "/rest/v1/x"], ["POST", "/rest/v1/rpc/finals_opponent"]]:
		_ok("F2 写 / 身份请求不换路: %s %s" % [w[0], w[1]], not NR.retry_safe(w[0], "https://x" + w[1]))
	## 入口表(不设 routes_override 时读环境变量)
	var e0 := OS.get_environment(NR.ENV_URL)
	var r0 := OS.get_environment(NR.ENV_RELAY)
	var had_r := OS.has_environment(NR.ENV_RELAY)
	OS.set_environment(NR.ENV_URL, " ")
	_ok("F3 门禁空白 ⇒ 一条入口都没有(整层停用)", NR.routes().is_empty() and SB.base_url() == "")
	OS.set_environment(NR.ENV_URL, "https://example.invalid/")
	if had_r:
		OS.unset_environment(NR.ENV_RELAY)
	_ok("F3 只设了直连环境变量 ⇒ 一条(注入传输的老门禁不受影响)", NR.routes() == PackedStringArray(["https://example.invalid"]))
	OS.set_environment(NR.ENV_RELAY, "https://relay.invalid")
	var rs := NR.routes()
	_ok("F3 再设中转 ⇒ 两条, 第 0 条直连", rs.size() == 2 and rs[0] == "https://example.invalid" and rs[1] == "https://relay.invalid", str(rs))
	NR._reset_for_test()
	NR._force_for_test("https://relay.invalid")
	_ok("F4 rebase: 按直连拼的地址换到当前入口", NR.rebase("https://example.invalid/rest/v1/x?a=1") == "https://relay.invalid/rest/v1/x?a=1")
	_ok("F4 直播跟着走中转", NR.stream_base() == "https://relay.invalid/streams" and SW.base_url() == "https://relay.invalid/streams")
	NR._force_for_test("https://example.invalid")
	_ok("F4 走直连 ⇒ 直播是 stream 自己的地址", SW.base_url() == NR.STREAM_DIRECT)
	if had_r:
		OS.set_environment(NR.ENV_RELAY, r0)
	else:
		OS.unset_environment(NR.ENV_RELAY)
	OS.set_environment(NR.ENV_URL, e0)
	NR._reset_for_test()


func _part_r() -> void:
	print("-- R 竞速")
	## R1 直连断开、中转通
	_fresh("drop", "ok")
	_ok("R1 前提: 第一次启动(没存过)⇒ 要等竞速", NR.pending())
	NR.kick(_hdrs())
	await _wait(_race_done, 8000)
	_ok("R1 竞速收尾了", NR.races == 1, str(NR.last_race))
	_ok("R1 选中转", NR.current_base() == _r.base() and NR.last_winner == _r.base(), NR.current_base())
	_ok("R1 分母: 两条都真被问过 service_status", _d.count("GET", "service_status") == 1 and _r.count("GET", "service_status") == 1,
		"直连 %d / 中转 %d" % [_d.count("GET", "service_status"), _r.count("GET", "service_status")])
	_ok("R1 直播跟着走中转", SW.base_url() == _r.base() + "/streams", SW.base_url())
	var cf := ConfigFile.new()
	_ok("R1 选择存盘了", cf.load(_save) == OK and str(cf.get_value("route", "base", "")) == _r.base())
	## R2 两条都通、中转慢
	_fresh("ok", "slow")
	NR.kick(_hdrs())
	await _wait(_race_done, 8000)
	_ok("R2 两条都通、中转慢 ⇒ 选直连", NR.current_base() == _d.base(), str(NR.last_race))
	_ok("R2 第一个 2xx 就收尾(没等慢的那条)", NR.last_race.size() == 1, str(NR.last_race))
	## R3 第一次启动: 真请求等竞速, 只发到胜出那条
	_fresh("drop", "ok")
	var res := await _req("GET", "/rest/v1/ghosts?select=*&limit=1")
	_ok("R3 真请求拿到 200", int(res.get("code", 0)) == 200, str(res.get("code", "超时")))
	_ok("R3 真请求只发到了中转(直连 0 次, 竞速探测除外)", _r.count("GET", "/ghosts") == 1 and _d.count("GET", "/ghosts") == 0,
		"中转 %d / 直连 %d" % [_r.count("GET", "/ghosts"), _d.count("GET", "/ghosts")])
	_ok("R3 没有因此换路重发(是先等竞速, 不是先失败)", NR.alt_retries == 0)
	## R4 存过 ⇒ 不等, 直接用上次那条(竞速照样在后台跑一次纠正)
	_fresh("ok", "ok", _r.base())
	_ok("R4 上次存的是中转 ⇒ 开局就是中转、不用等", NR.current_base() == _r.base() and not NR.pending())
	await _wait(_race_done, 100)
	_ok("R4 开局还没竞速", NR.races == 0)


func _part_s() -> void:
	print("-- S 换路")
	## S1 直连好好的, 中途断开
	_fresh("ok", "ok", _d.base())
	NR._force_for_test(_d.base())
	_d.mode = "drop"
	var a := await _req("GET", "/rest/v1/ghosts?select=*&limit=1")
	_ok("S1 只读请求: 直连断开 ⇒ 当场换中转重发拿到 200", int(a.get("code", 0)) == 200 and _r.count("GET", "/ghosts") == 1,
		"code %s / 中转 %d / 直连 %d" % [str(a.get("code", "超时")), _r.count("GET", "/ghosts"), _d.count("GET", "/ghosts")])
	_ok("S1 分母: 直连真收到了那一次(然后断开)", _d.count("GET", "/ghosts") == 1)
	_ok("S1 一次失败还不换当前入口", NR.current_base() == _d.base() and NR.switches == 0)
	var b := await _req("POST", "/rest/v1/rpc/finals_view", "{}", "Content-Type: application/json")
	_ok("S1 只读 RPC 同样换路拿到 200", int(b.get("code", 0)) == 200 and _r.count("POST", "finals_view") == 1)
	_ok("S1 连着 2 次 ⇒ 当前入口换成中转", NR.current_base() == _r.base() and NR.switches == 1, NR.current_base())
	var c := await _req("GET", "/rest/v1/ghosts?select=*&limit=2")
	_ok("S1 换过去之后直接发中转(直连不再收到)", int(c.get("code", 0)) == 200 and _d.count("GET", "limit=2") == 0 and _r.count("GET", "limit=2") == 1)
	_ok("S1 换路之后后台重新竞速一次", await _wait(func() -> bool: return NR.races >= 1, 8000))
	## S2 写请求绝不跨路
	var writes := [["POST", "/rest/v1/ghosts", "{\"a\":1}", "Prefer: resolution=merge-duplicates"],
		["POST", "/rest/v1/rpc/finals_report", "{}", "Content-Type: application/json"],
		["PATCH", "/rest/v1/saves?account_id=eq.x", "{}", "Content-Type: application/json"],
		["POST", "/auth/v1/token?grant_type=refresh_token", "{\"refresh_token\":\"x\"}", "Content-Type: application/json"],
		["POST", "/auth/v1/signup", "{}", "Content-Type: application/json"]]
	for w in writes:
		_fresh("drop", "ok", _d.base())
		NR._force_for_test(_d.base())
		var p := str(w[1]).split("?")[0]
		var res := await _req(w[0], w[1], w[2], w[3])
		_ok("S2 %s %s: 直连断开 ⇒ 回调拿到失败" % [w[0], p], not res.is_empty() and NR.transport_failed(res), str(res.get("code", "超时")))
		_ok("S2 %s %s: 分母 直连真收到 1 次" % [w[0], p], _d.count(w[0], p) == 1, str(_d.reqs))
		_ok("S2 %s %s: ★中转收到 0 次(不跨路重发)" % [w[0], p], _r.count(w[0], p) == 0, str(_r.reqs))
	## S3 服务器回了话(426 / 401 / 500)⇒ 不换路、不重发
	for m in ["426", "401", "500"]:
		_fresh(m, "ok", _d.base())
		NR._force_for_test(_d.base())
		var got: Array = []
		for i in 3:
			var r := await _req("GET", "/rest/v1/ghosts?select=*&limit=%d" % (10 + i))
			got.append(int(r.get("code", 0)))
		_ok("S3 直连回 %s ×3 ⇒ 回调拿到的就是 %s" % [m, m], got == [int(m), int(m), int(m)], str(got))
		_ok("S3 直连回 %s ×3 ⇒ 不换路" % m, NR.current_base() == _d.base() and NR.switches == 0)
		_ok("S3 直连回 %s ×3 ⇒ 中转收到 0 次" % m, _r.count("GET", "/ghosts") == 0 and NR.alt_retries == 0, str(_r.reqs))
		_ok("S3 分母: 直连真收到 3 次", _d.count("GET", "/ghosts") == 3)
		SB._reset_for_test()     # 426 会把版本墙信号立起来; 清掉免得挡住后面的写
