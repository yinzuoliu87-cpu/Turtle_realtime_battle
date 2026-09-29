extends Node
## DEV 探针: **端到端**走完绑定 —— 发码 → 等外部把码写进文件 → 验码 → 看绑定成没成。
## ★收件人用 turtlesupport32+e2e@gmail.com(就是发信箱本身), 这样外部能用 IMAP 把码读出来。

const SB := preload("res://scripts/net/supabase.gd")
const MAIL := "turtlesupport32+e2e@gmail.com"
const CODE_FILE := "C:/tmp/e2e/code.txt"


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
	print("[1] token 拿到, account_id=%s" % str(GameState.account_id).substr(0, 8))

	SB.send_code_async(MAIL, SB.FLOW_BIND)
	for i in range(80):
		await _w(10)
		if SB.email_state() != SB.EM_SENDING:
			break
	print("[2] 发码: state=%s msg=「%s」" % [SB.email_state(), SB.email_msg()])
	if SB.email_state() != SB.EM_SENT:
		print("[X] 发码就没成, 端到端到此为止")
		get_tree().quit(1)
		return

	print("[3] 等外部把验证码写进 %s ..." % CODE_FILE)
	var code := ""
	for i in range(600):                      ## 最多等 ~120 秒
		await _w(12)
		if FileAccess.file_exists(CODE_FILE):
			var f := FileAccess.open(CODE_FILE, FileAccess.READ)
			if f != null:
				code = f.get_as_text().strip_edges()
				f.close()
			if code != "":
				break
	if code == "":
		print("[X] 等不到验证码(邮件没来或读不出来)")
		get_tree().quit(2)
		return
	print("[4] 拿到验证码: %s (%d 位)" % [code, code.length()])

	SB.verify_code_async(code)
	for i in range(80):
		await _w(10)
		if SB.email_state() != SB.EM_VERIFYING:
			break
	print("[5] 验码: state=%s msg=「%s」" % [SB.email_state(), SB.email_msg()])
	print("[6] 绑定结果: account_email=「%s」" % str(GameState.account_email))
	var ok: bool = SB.email_state() == SB.EM_OK or str(GameState.account_email) == MAIL
	print("[7] 端到端 %s" % ("成功 —— 绑定真的完成了" if ok else "失败"))
	get_tree().quit(0 if ok else 3)
