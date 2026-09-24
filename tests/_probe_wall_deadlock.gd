extends Node
## DEV 探针: 全新安装的玩家被登录墙挡住时, 点「发验证码」到底看到什么。
## ★不是门禁(下划线开头 ⇒ 不被自动发现)。
##
## 怀疑(2026-09-24, 读 v0.19.440 的控制流读出来的):
##   `MainMenuScene._ready()` 里顺序是
##       103  if login_wall_on(...): _go("Settings"); return   ← 墙在这里就 return
##       118  _SB.ensure_signed_in_async()                     ← 匿名登录, 到不了
##   而 `send_code_async` 的绑定分支要求 `_token != ""`, 否则回
##       「还没登录，先联网开一局再绑」
##   —— 墙正好不让他开局。
##   兜底只有 `GameState` 的 20 秒保活 tick(`wait_time=20 autostart` ⇒ **第一次在 t=20s**)。
##
## ⇒ 这里不推理, 直接走真入口, 把**玩家看到的那句话**打出来。
##
## 跑法: <godot> --headless --path . res://tests/_probe_wall_deadlock.tscn --quit-after 600

const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")


func _ready() -> void:
	await get_tree().process_frame
	## 全新安装的样子: 后端配了(用死地址, 不真打网络) + 没 id + 没邮箱
	OS.set_environment("TURTLE_SUPABASE", "http://127.0.0.1:9")
	SB._reset_auth_for_test()
	GameState.test_mode = true
	GameState.account_id = ""
	GameState.account_email = ""

	print("=== 全新安装 + 登录墙: 玩家点「发验证码」看到什么 ===")
	print("  后端 enabled = %s   该挡吗 = %s" % [
		SB.enabled(), P2C.login_wall_on(SB.enabled(), str(GameState.account_email))])
	print("  开机时 _token = 「%s」 (空 = 还没有匿名会话)" % SB._token)
	print("")

	## ★走真入口: 真的进主菜单。墙要求 `current_scene == self` 才跳 ⇒ 必须走
	##   `change_scene_to_file`(它**先**置 current_scene 再 add_child, 所以主菜单的
	##   `_ready` 里那个判等成立; 这也正是真实开机的样子)。
	##   ★但探针自己就是 current_scene, 换场景会当场把探针拆掉(本仓记过这个坑) ⇒
	##     先把 current_scene 置空: 引擎只 `memdelete(current_scene)`, 置空之后
	##     它谁也不删, 探针作为 root 的普通子节点活下来继续量。
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	for _i in 12:
		await get_tree().process_frame
	var cur := get_tree().current_scene
	print("  主菜单 _ready 之后, 当前场景 = %s" % (cur.name if cur != null else "<null>"))
	## ★★复现 CI 那条红: `_auth_inflight` 是**瞬时量** —— 请求在飞时才为真。
	##   死地址 127.0.0.1:9 在 Linux 上**秒拒** ⇒ 回包早回来了 ⇒ 它已被清回 false,
	##   而 `_auth_tries` 变 1。本地 Windows 慢一点, 16 帧时还在飞 ⇒ 反过来。
	##   ⇒ 单看哪一个都不稳; 「发起过」= inflight **或** tries>0。
	print("  ── 两个时刻各量一次(证明它是瞬时量) ──")
	print("     第 12 帧: _auth_inflight=%s  auth_try_count=%d  ⇒ 发起过=%s" % [
		SB._auth_inflight, SB.auth_try_count(),
		SB._auth_inflight or SB.auth_try_count() > 0])
	for _j in 400:
		await get_tree().process_frame
	print("     第 412 帧: _auth_inflight=%s  auth_try_count=%d  ⇒ 发起过=%s" % [
		SB._auth_inflight, SB.auth_try_count(),
		SB._auth_inflight or SB.auth_try_count() > 0])
	print("  _token = 「%s」" % SB._token)
	print("  ★分母: 主菜单 118 行的 `ensure_signed_in_async` 跑到了吗 ——")
	print("     它跑到的话会 spawn 一个请求节点并置 _auth_inflight; 现在 _auth_inflight = %s"
		% SB._auth_inflight)
	print("")

	## ★玩家的动作: 在墙上填邮箱 → 点「发验证码」
	SB.send_code_async("newplayer@example.com", SB.FLOW_BIND)
	await get_tree().process_frame
	print("  玩家点「发验证码」→ 状态 = %s" % SB._email_state)
	print("  ★玩家看到的那句话 = 「%s」" % SB._email_msg)
	print("")
	var stuck: bool = str(SB._email_msg).find("开一局") >= 0
	print("  结论: %s" % ("★★卡住了 —— 提示让他去做墙不让他做的事" if stuck
		else "没卡住(提示是另一句, 见上)"))
	print("  兜底: GameState 保活 Timer wait_time=%.0fs autostart ⇒ 第一次在 t=%.0fs" % [20.0, 20.0])
	get_tree().quit(0)
