extends Node
## verify_battle_ui.gd — 守卫 R2a/R2b: 战斗内 UX (结束按钮化 / 暂停 / 战斗日志)
## 用户〖2026-07-11〗:「战斗结束不要什么点R/ESC, 要按钮的形式, 暂停, ...日志等都通吗」
##
## 断言(功能层, 像素布局仍需 F5 眼验):
##   A. 暂停按钮/面板已建; _toggle_pause 切 get_tree().paused + 面板显隐; _settled 后不响应。
##   B. 战斗日志 _log 追加 + 封顶 _LOG_CAP(200); _toggle_log 显隐面板且开时重建文本。
##   C. 结算 _show_banner 生成 2 个操作 Button(再战/返回菜单), 且结算后暂停按钮被禁。
##
## ★注意: 测试根节点 process_mode=ALWAYS, 且结尾复位 paused=false(否则暂停态会冻住后续 await)。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _count_buttons(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is Button:
			c += 1
		c += _count_buttons(ch)
	return c


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停时本测试仍能推进
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	# ── A. 暂停 ──
	_ok("暂停按钮已建", scene._pause_btn != null)
	_ok("暂停面板已建且默认隐藏", scene._pause_panel != null and not scene._pause_panel.visible)
	scene._toggle_pause()
	_ok("暂停开: get_tree().paused=true", get_tree().paused == true)
	_ok("暂停开: 面板显示", scene._pause_panel.visible == true)
	scene._toggle_pause()
	_ok("暂停关: get_tree().paused=false", get_tree().paused == false)
	_ok("暂停关: 面板隐藏", scene._pause_panel.visible == false)
	# _settled 后不响应
	scene._settled = true
	scene._toggle_pause()
	_ok("结算后暂停按钮不响应(paused 仍 false)", get_tree().paused == false)
	scene._settled = false

	# ── B. 战斗日志 ──
	scene._battle_log.clear()
	for i in range(scene._LOG_CAP + 60):
		scene._log("[color=#fff]行 %d[/color]" % i)
	_ok("日志封顶 _LOG_CAP=%d" % scene._LOG_CAP, scene._battle_log.size() == scene._LOG_CAP,
		"实际 %d" % scene._battle_log.size())
	_ok("日志封顶后保留最新(删最旧)", str(scene._battle_log[-1]).find("行 %d" % (scene._LOG_CAP + 59)) >= 0)
	scene._toggle_log()
	_ok("日志面板开", scene._log_panel.visible == true)
	_ok("开面板后富文本非空", scene._log_rt != null and scene._log_rt.get_paragraph_count() > 0)
	scene._toggle_log()
	_ok("日志面板关", scene._log_panel.visible == false)

	# ── C. 结算按钮化 ──
	scene._show_banner(true)
	await get_tree().process_frame
	var btns := _count_buttons(scene._ui_layer)
	_ok("结算后 UI 层有操作按钮(再战/返回菜单等 ≥2)", btns >= 2, "共 %d 个 Button" % btns)
	_ok("结算后暂停按钮被禁", scene._pause_btn.disabled == true)

	# 复位, 防暂停态影响
	get_tree().paused = false
	_done()


func _done() -> void:
	get_tree().paused = false
	print("")
	if _fail == 0:
		print("ALL PASS — 战斗内 UX(结束按钮/暂停/日志) 功能守卫通过")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)
