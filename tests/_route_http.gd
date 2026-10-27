extends Node
## 大陆中转门禁共用: 本进程里的最小 HTTP 服务, 模拟「一条入口」(下划线开头: 不是门禁)。被 verify_net_route_failover preload。
##   只听 127.0.0.1(CI 无外网也能跑), 不起子进程。一个实例 = 一条入口(直连 / 中转各起一个)。
##
## mode:
##   "ok"   ⇒ 200(service_status 回一行 JSON, 其余回 {})
##   "slow" ⇒ 等 delay_ms 毫秒再回 200(竞速里慢的那条)
##   "drop" ⇒ 收完请求不回话直接断开(= 传输层失败: 连接被重置 / 丢包)
##   "426" / "401" / "500" ⇒ 回这个码(服务器真的回了话)
## 记账(reqs): 每个请求 [方法, 路径(含查询串), 回的码(断开记 0)]。

var port := 0
var mode := "ok"
var delay_ms := 800
## 非空 ⇒ 200 的 RPC(`/rest/v1/rpc/…`)回这段正文(默认空 = 照旧回 {})。verify_spawn_busy_root 用它回 {"ok":true}。
var rpc_body := ""
var reqs: Array = []
var _srv := TCPServer.new()
var _conns: Array = []


func start(from_port: int) -> bool:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for p in range(from_port, from_port + 100):
		if _srv.listen(p, "127.0.0.1") == OK:
			port = p
			return true
	return false


func base() -> String:
	return "http://127.0.0.1:%d" % port


## 方法 + 路径里含 needle 的请求数。
func count(method: String = "", needle: String = "") -> int:
	var n := 0
	for r in reqs:
		if (method == "" or str(r[0]) == method) and (needle == "" or str(r[1]).find(needle) >= 0):
			n += 1
	return n


func _exit_tree() -> void:
	_srv.stop()


func _process(_dt: float) -> void:
	while _srv.is_connection_available():
		_conns.append({"c": _srv.take_connection(), "buf": PackedByteArray(), "state": "read", "t": 0, "due": 0, "req": []})
	var keep: Array = []
	var now := Time.get_ticks_msec()
	for cn in _conns:
		var c: StreamPeerTCP = cn["c"]
		c.poll()
		match str(cn["state"]):
			"sent":
				cn["t"] = int(cn["t"]) + 1
				if int(cn["t"]) > 2:
					c.disconnect_from_host()
					continue
			"wait":
				if now >= int(cn["due"]):
					_reply(cn, 200)
			"read":
				if c.get_status() != StreamPeerTCP.STATUS_CONNECTED:
					continue
				var n := c.get_available_bytes()
				if n > 0:
					var got: Array = c.get_data(n)
					if int(got[0]) == OK:
						var buf: PackedByteArray = cn["buf"]      # ★Packed 数组是值类型: 取出来改的是副本, 要写回
						buf.append_array(got[1])
						cn["buf"] = buf
				if _complete(cn["buf"]):
					if not _answer(cn):
						continue
		keep.append(cn)
	_conns = keep


## 请求头读完、正文按 Content-Length 也读完了没有。
func _complete(buf: PackedByteArray) -> bool:
	var txt := buf.get_string_from_ascii()
	var h := txt.find("\r\n\r\n")
	if h < 0:
		return false
	var want := 0
	for l in txt.substr(0, h).split("\r\n"):
		if l.to_lower().begins_with("content-length:"):
			want = int(l.substr(l.find(":") + 1).strip_edges())
	return buf.size() >= h + 4 + want


## 回 false = 连接已断(不留)。
func _answer(cn: Dictionary) -> bool:
	var txt := (cn["buf"] as PackedByteArray).get_string_from_ascii()
	var parts := txt.split("\r\n")[0].split(" ")
	var method := parts[0] if parts.size() > 0 else ""
	var path := parts[1] if parts.size() > 1 else ""
	cn["req"] = [method, path]
	match mode:
		"drop":
			reqs.append([method, path, 0])
			(cn["c"] as StreamPeerTCP).disconnect_from_host()
			return false
		"slow":
			cn["state"] = "wait"
			cn["due"] = Time.get_ticks_msec() + delay_ms
		"426", "401", "500":
			_reply(cn, int(mode))
		_:
			_reply(cn, 200)
	return true


func _reply(cn: Dictionary, code: int) -> void:
	var method := str(cn["req"][0])
	var path := str(cn["req"][1])
	reqs.append([method, path, code])
	var body := "{}"
	if code == 200 and path.find("service_status") >= 0:
		body = "[{\"id\":1,\"maintenance\":false,\"notice\":\"\",\"min_client_version\":\"\"}]"
	elif code == 200 and rpc_body != "" and path.find("/rest/v1/rpc/") >= 0:
		body = rpc_body
	elif code == 426:
		body = "{\"message\":\"update_required\"}"
	elif code == 401:
		body = "{\"message\":\"Invalid API key\"}"
	var b := body.to_utf8_buffer()
	var reason: String = {200: "OK", 401: "Unauthorized", 426: "Upgrade Required", 500: "Internal Server Error"}.get(code, "X")
	var head := "HTTP/1.1 %d %s\r\nContent-Length: %d\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n" % [code, reason, b.size()]
	var out := head.to_ascii_buffer()
	out.append_array(b)
	(cn["c"] as StreamPeerTCP).put_data(out)
	cn["state"] = "sent"
	cn["t"] = 0
