extends Node
## DEV 探针: 全新安装 + **真后端真网络**, 走登录墙点「发验证码」到底发生什么。
## 用户 2026-09-28 实测: 两个邮箱都能收到我手工触发的验证码邮件(服务端 200),
## 但**在 app 里点没反应** ⇒ 发信层没问题, 问题在客户端这条路。
## ⇒ 这里不推理, 把每一步的真值打出来。
##
## 跑法: <godot> --headless --path . res://tests/_probe_wall_live.tscn --quit-after 1200
## ★收件人用 example.com(保留域, 不会真骚扰任何人)。

const SB := preload("res://scripts/net/supabase.gd")

const MAIL := "turtle-probe@example.com"


func _w(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	await _w(2)
	## 全新安装的样子 —— **不设 TURTLE_SUPABASE**, 让它用 project.godot 里的真地址
	GameState.test_mode = true
	GameState.account_id = ""
	GameState.account_email = ""
	SB._reset_auth_for_test()
	print("[0] enabled=%s  base=%s" % [str(SB.enabled()), SB.base_url()])
	print("[0] token空=%s  account_id空=%s" % [str(SB._token == ""), str(str(GameState.account_id) == "")])

	## ── ① 匿名登录(墙上点发码之前, 产品自己会踢的那一脚) ──
	SB.ensure_signed_in_async()
	for i in range(60):
		await _w(10)
		if SB._token != "":
			break
	print("[1] 等了 %d 帧后 token 非空=%s  account_id=%s"
		% [60 * 10, str(SB._token != ""), str(GameState.account_id).substr(0, 8)])

	## ── ② 点「发验证码」 ──
	SB.send_code_async(MAIL, SB.FLOW_BIND)
	print("[2] 刚点完: state=%s  msg=「%s」" % [SB.email_state(), SB.email_msg()])
	for i in range(60):
		await _w(10)
		if SB.email_state() != SB.EM_SENDING:
			break
	print("[3] 等回包后: state=%s  msg=「%s」" % [SB.email_state(), SB.email_msg()])
	print("[3] pending=%s  flow=%s" % [SB._email_pending, SB._email_flow])
	get_tree().quit(0)
