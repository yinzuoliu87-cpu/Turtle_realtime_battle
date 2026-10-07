extends Node
## 探针: 在登录墙上绑定成功之后, 玩家走得掉吗。
## ★不看源码顺序, 量运行时对象(memory fb-probe-before-claiming-rootcause)。
const SET := preload("res://scripts/scenes/SettingsScene.gd")
const SB := preload("res://scripts/net/supabase.gd")


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.account_email = ""
	await get_tree().process_frame
	var st = SET.new()
	st.acct_override = 1                       ## 强制「后端开着 + 未绑定」= 墙的条件
	add_child(st)
	for _i in range(6):
		await get_tree().process_frame
	print("[探针] 墙立起来了吗: _email_layer=%s" % str(st._email_layer != null))
	print("[探针] 返回箭头可见: %s" % (str(st._top_bar.back_btn.visible) if st._top_bar != null else "<no bar>"))

	## ── 模拟「验证码对了」: 服务端那一侧已经落地(邮箱写进 GameState) ──
	if gs != null:
		gs.account_email = "tester01@x.co"
	SB._email_state = SB.EM_OK
	SB._email_msg = "邮箱绑定成功"
	st.acct_override = 0                        ## 回到真实取值 ⇒ 现在「已绑定」
	## 墙里那个 Timer 每 0.25 秒喂一次 _email_poll, 等够两轮
	var _w := 0.0
	while _w < 1.2:
		await get_tree().process_frame
		_w += get_process_delta_time()

	print("[探针] 成功之后 —— _email_layer 还在吗: %s" % str(st._email_layer != null and is_instance_valid(st._email_layer)))
	print("[探针] 成功之后 —— 返回箭头可见: %s" % (str(st._top_bar.back_btn.visible) if st._top_bar != null else "<no bar>"))
	print("[探针] 成功之后 —— 状态文字: %s" % (str(st._email_status.text) if st._email_status != null and is_instance_valid(st._email_status) else "<none>"))
	print("[探针] 这一刻 login_wall_on = %s (墙本该已经不该开了)" % str(st._P2C.login_wall_on(true, str(gs.account_email))))
	get_tree().quit(0)
