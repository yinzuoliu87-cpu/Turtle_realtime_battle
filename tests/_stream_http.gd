extends Node
## 逐帧直播 S5 门禁共用: 本进程里的最小 HTTP 服务(下划线开头: 不是门禁)。被 verify_stream_transport /
##   verify_referee_watch_stream preload。只听 127.0.0.1(CI 无外网也能跑), 不起子进程、不依赖 python。
##
## 模拟 server/stream/README.md 里 Caddy 的口径:
##   GET /streams/<match_id>/<6 位序号>.bin ⇒ 序号 < served ⇒ 200 整块; 否则 404
##   GET /streams/<match_id>/end.json       ⇒ end 开着 ⇒ 200 元数据(含 chunks); 否则 404
##   mode = "426" ⇒ 一律 426(版本闸); "drop" ⇒ 收了请求不回话直接断开(断网 / 连接被重置); "500" ⇒ 500
##   req_version 非空 ⇒ 请求头 X-Client-Version 不等于它也回 426(与版本闸同口径: 不带头 / 不对 ⇒ 426)
## 记账(reqs): 每个请求 [路径, 请求头里的版本, 回的码]。

var port := 0
var mode := "ok"
var req_version := ""
var streams := {}                 # match_id → {"chunks": Array[PackedByteArray], "meta": Dictionary, "served": int, "end": bool}
var reqs: Array = []
var _srv := TCPServer.new()
var _conns: Array = []


func start() -> bool:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for p in range(18731, 18831):
		if _srv.listen(p, "127.0.0.1") == OK:
			port = p
			return true
	return false


func base() -> String:
	return "http://127.0.0.1:%d/streams" % port


func put(mid: String, chunks: Array, meta: Dictionary, served: int = -1, ended: bool = true) -> void:
	streams[mid] = {"chunks": chunks, "meta": meta, "served": chunks.size() if served < 0 else served, "end": ended}


func count(code: int, needle: String = "") -> int:
	var n := 0
	for r in reqs:
		if int(r[2]) == code and (needle == "" or str(r[0]).find(needle) >= 0):
			n += 1
	return n


func _exit_tree() -> void:
	_srv.stop()


func _process(_dt: float) -> void:
	while _srv.is_connection_available():
		_conns.append({"c": _srv.take_connection(), "buf": PackedByteArray(), "done": false, "t": 0})
	var keep: Array = []
	for cn in _conns:
		var c: StreamPeerTCP = cn["c"]
		c.poll()
		if bool(cn["done"]):
			cn["t"] = int(cn["t"]) + 1
			if int(cn["t"]) > 2:
				c.disconnect_from_host()
				continue
			keep.append(cn)
			continue
		var st := c.get_status()
		if st != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var n := c.get_available_bytes()
		if n > 0:
			var got: Array = c.get_data(n)
			if int(got[0]) == OK:
				var buf: PackedByteArray = cn["buf"]      # ★Packed 数组是值类型: 从字典里取出来改的是副本, 要写回
				buf.append_array(got[1])
				cn["buf"] = buf
		var txt := (cn["buf"] as PackedByteArray).get_string_from_ascii()
		if txt.find("\r\n\r\n") >= 0:
			_answer(c, txt)
			cn["done"] = true
		keep.append(cn)
	_conns = keep


func _answer(c: StreamPeerTCP, req: String) -> void:
	var lines := req.split("\r\n")
	var parts := lines[0].split(" ")
	var path := parts[1] if parts.size() > 1 else ""
	var ver := ""
	for l in lines:
		if l.to_lower().begins_with("x-client-version:"):
			ver = l.substr(l.find(":") + 1).strip_edges()
	if mode == "drop":
		reqs.append([path, ver, 0])
		c.disconnect_from_host()
		return
	if mode == "500":
		_send(c, path, ver, 500, PackedByteArray())
		return
	if mode == "426" or (req_version != "" and ver != req_version):
		_send(c, path, ver, 426, "{\"message\":\"update_required\"}".to_utf8_buffer())
		return
	var seg := path.split("/", false)       # streams / <mid> / <file>
	if seg.size() != 3 or seg[0] != "streams" or not streams.has(seg[1]):
		_send(c, path, ver, 404, PackedByteArray())
		return
	var s: Dictionary = streams[seg[1]]
	if seg[2] == "end.json":
		if bool(s["end"]):
			_send(c, path, ver, 200, JSON.stringify(s["meta"]).to_utf8_buffer())
		else:
			_send(c, path, ver, 404, PackedByteArray())
		return
	if seg[2].ends_with(".bin") and seg[2].get_basename().is_valid_int():
		var i := int(seg[2].get_basename())
		if i >= 0 and i < int(s["served"]) and i < (s["chunks"] as Array).size():
			_send(c, path, ver, 200, s["chunks"][i])
			return
	_send(c, path, ver, 404, PackedByteArray())


func _send(c: StreamPeerTCP, path: String, ver: String, code: int, body: PackedByteArray) -> void:
	reqs.append([path, ver, code])
	var reason: String = {200: "OK", 404: "Not Found", 426: "Upgrade Required", 500: "Internal Server Error"}.get(code, "X")
	var head := "HTTP/1.1 %d %s\r\nContent-Length: %d\r\nContent-Type: application/octet-stream\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [code, reason, body.size()]
	var out := head.to_ascii_buffer()
	out.append_array(body)
	c.put_data(out)
