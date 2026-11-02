extends Node
## DEV 探针: 把 `send_code_async` **真正发出去的那一条**原样录下来。
## 已知(N=3): 走 send_code_async 的一封都没真发出去; 而我手写同样 headers 的 HTTPRequest 发得出去。
## ⇒ 装一个"日志传输": 打印 方法/地址/请求头/正文, 然后**转发真请求**, 再打回包。

const SB := preload("res://scripts/net/supabase.gd")
const MAIL := "turtlesupport32+log2@gmail.com"

var _done := false


func _w(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	await _w(2)
	GameState.test_mode = true
	GameState.account_id = ""
	GameState.account_email = ""
	SB._reset_auth_for_test()
	print("[0] _transport_for_test 有效吗 = %s" % str(SB._transport_for_test.is_valid()))
	SB.ensure_signed_in_async()
	for i in range(60):
		await _w(10)
		if SB._token != "":
			break
	print("[0] token len=%d" % SB._token.length())

	## 日志传输: 原样打印, 再用真 HTTPRequest 转发
	SB._transport_for_test = func(method: String, url: String, hdr: PackedStringArray,
			body: String, cb: Callable) -> void:
		print("[REQ] %s %s" % [method, url])
		for h in hdr:
			var hs := str(h)
			if hs.begins_with("Authorization"):
				hs = "Authorization: Bearer <len %d>" % (hs.length() - 22)
			elif hs.begins_with("apikey"):
				hs = "apikey: <len %d>" % (hs.length() - 8)
			print("[REQ]   %s" % hs)
		print("[REQ] body=%s" % body)
		var r := HTTPRequest.new()
		r.timeout = 30.0
		add_child(r)
		r.request_completed.connect(func(res: int, code: int, _h: PackedStringArray, d: PackedByteArray):
			print("[RES] result=%d HTTP=%d" % [res, code])
			print("[RES] body=%s" % d.get_string_from_utf8().substr(0, 400))
			cb.call({"ok": res == HTTPRequest.RESULT_SUCCESS, "code": code,
				"body": d.get_string_from_utf8()})
			r.queue_free()
			_done = true)
		var e := r.request(url, hdr, SB._method_of(method), body)
		if e != OK:
			print("[REQ] request() err=%d" % e)
			cb.call({"ok": false, "code": 0, "body": ""})
			_done = true

	## ★对照: 拿到 token 之后**多等 2 秒**再发
	await _w(120)
	print("[0] 已多等 120 帧")
	SB.send_code_async(MAIL, SB.FLOW_BIND)
	for i in range(120):
		await _w(10)
		if _done:
			break
	print("[9] state=%s msg=「%s」" % [SB.email_state(), SB.email_msg()])
	SB._transport_for_test = Callable()
	get_tree().quit(0)
