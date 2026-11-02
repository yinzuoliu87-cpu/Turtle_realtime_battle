extends Node
## DEV 探针: 用**游戏自己的 headers**发那条 PUT, 把服务端回包**原文**打出来。
## 已知(N=3): 游戏代码发的一封都没真发出去, 而 curl 发的出去了 —— 同端点同 body 都回 200。
## ⇒ 这里不猜, 打回包。

const SB := preload("res://scripts/net/supabase.gd")
const MAIL := "turtlesupport32+raw2@gmail.com"


func _w(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	await _w(2)
	GameState.test_mode = true
	GameState.account_id = ""
	GameState.account_email = ""
	SB._reset_auth_for_test()
	SB.ensure_signed_in_async()
	for i in range(60):
		await _w(10)
		if SB._token != "":
			break
	print("[0] token 非空=%s  len=%d" % [str(SB._token != ""), SB._token.length()])

	var hdr := PackedStringArray([
		"apikey: " + SB.anon_key(),
		"Authorization: Bearer " + SB._token,
		"Accept: application/json",
		"Content-Type: application/json",
	])
	var url := SB.base_url().rstrip("/") + "/auth/v1/user"
	var req := HTTPRequest.new()
	req.timeout = 30.0
	add_child(req)
	var done := [false]
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, data: PackedByteArray):
		print("[1] result=%d  HTTP=%d" % [result, code])
		print("[1] body=%s" % data.get_string_from_utf8().substr(0, 600))
		done[0] = true)
	var err := req.request(url, hdr, HTTPClient.METHOD_PUT, JSON.stringify({"email": MAIL}))
	print("[0] request() err=%d" % err)
	for i in range(120):
		await _w(10)
		if done[0]:
			break
	get_tree().quit(0)
