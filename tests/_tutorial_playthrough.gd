extends Node
## 自动跑一遍完整新手教程, 每一步截图。给用户看"流程跑通"的工具(非门禁)。
## 跑法: SHIP=1 ONBOARD=1 godot --path . res://tests/_tutorial_playthrough.tscn --quit-after 60000
##
## ★流程(2026-10-07 重做, 方案书 docs/plans/20261007-新手教程重做.md §4.1):
##   主菜单选择框「开始教程」→ 选龟(只 3 只教学龟) → 战斗(三路, 拖一只龟 → 开始战斗) → 结算「前往商店」
##   → 商店(买经验升 2 级 → 买 1 件装备 → 点击背包) → 背包(点装备 → 点龟装上 → 完成教程) → 主菜单。
## ★每一步都走产品自己的入口(按钮 pressed / 场景自己的点击函数), 引导条从产品代码里收到事件才翻页 ——
##   本工具不调任何「翻页」接口(引导条也没有了)。整条的断言版是 tests/verify_tutorial_flow_v2.gd。
## ★战斗打完三路要 ~140 游戏秒; 本工具在开打后直接走产品的结算入口 `_hud._show_banner(true)`。
## ★本节点放弃 current_scene 身份常驻根上(change_scene 只 free current_scene)。

var _shot := 0
var _log: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	if get_tree().current_scene == self:
		get_tree().current_scene = null
	GameState.onboarded = false
	var m = load("res://scenes/MainMenu.tscn").instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	await _sleep(1.5)
	var ch: Node = m.get_node_or_null("TutorialChoice")
	await _shoot("0_choice")
	if ch == null:
		_note("★ 没弹选择框"); _finish(); return
	(ch.find_child("StartTutorial", true, false) as Button).emit_signal("pressed")
	var ts := await _wait("TeamSelect.tscn")
	await _sleep(1.0)
	await _shoot("1_team_select")
	for pid in get_node("/root/TutorialDirector").FIXED_TEAM:
		ts._on_pick_pet(str(pid))
		await _sleep(0.3)
	await _sleep(0.6)
	await _shoot("2_team_confirm")
	ts._on_start()
	var bt := await _wait("RealtimeBattle3D.tscn")
	while is_instance_valid(bt) and str(bt._dl_state) != "place":
		await get_tree().process_frame
	await _sleep(1.2)
	await _shoot("3_place_drag")
	var r: Rect2 = bt._dl_sys._tut_anchor("my_unit")
	if r.size.x > 0.0:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT; e.pressed = true; e.position = r.get_center()
		Input.parse_input_event(e)
		await get_tree().process_frame
		for i in range(1, 9):
			var mm := InputEventMouseMotion.new()
			mm.position = r.get_center() + Vector2(110, -40) * (float(i) / 8.0)
			mm.button_mask = MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(mm)
			await get_tree().process_frame
		var u := InputEventMouseButton.new()
		u.button_index = MOUSE_BUTTON_LEFT; u.pressed = false; u.position = r.get_center() + Vector2(110, -40)
		Input.parse_input_event(u)
	await _sleep(0.8)
	await _shoot("4_place_go")
	(bt._dl_go_btn as Button).emit_signal("pressed")
	await _sleep(2.0)
	bt._hud._show_banner(true)
	await _sleep(1.5)
	await _shoot("5_settle")
	for c in (bt._hud._settle.btn_row as Node).get_children():
		if c is Button:
			(c as Button).emit_signal("pressed")
			break
	var sh := await _wait("Shop.tscn")
	await _sleep(1.0)
	await _shoot("6_shop_xp")
	(sh._tut_xp_btn as Button).emit_signal("pressed")
	await _sleep(0.8)
	await _shoot("7_shop_buy")
	for i in range((sh._offer as Array).size()):
		if sh._offer[i] != null and sh._price(sh._deco(sh._offer[i])) <= int(GameState.meta_deepsea_coins):
			sh._on_select(i)
			await _sleep(0.5)
			sh._on_buy(i)
			break
	await _sleep(0.8)
	await _shoot("8_shop_bag")
	sh._go_inventory()
	var inv := await _wait("Inventory.tscn")
	await _sleep(1.0)
	await _shoot("9_inv_item")
	inv._on_bench_click(0)
	await _sleep(0.6)
	await _shoot("10_inv_turtle")
	inv._dl_click("top", 0)
	await _sleep(0.6)
	await _shoot("11_inv_finish")
	(inv._tut_finish_btn as Button).emit_signal("pressed")
	await _wait("MainMenu.tscn")
	await _sleep(1.0)
	await _shoot("12_menu")
	_finish()


func _wait(suffix: String) -> Node:
	for _i in range(3000):
		var cs := get_tree().current_scene
		if cs != null and str(cs.scene_file_path).ends_with(suffix):
			return cs
		await get_tree().process_frame
	return null


func _sleep(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _shoot(tag: String) -> void:
	## headless 无渲染 ⇒ 不截图, 只记流程
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "C:/tmp/tut_flow_%02d_%s.png" % [_shot, tag]
		img.save_png(path)
		print("  [截图] %s" % path)
	_note(tag)
	_shot += 1


func _note(s: String) -> void:
	_log.append(s)
	print("  [流程] ", s)


func _finish() -> void:
	print("  ═══ 完整流程 ═══")
	for l in _log:
		print("    " + str(l))
	print("  收尾: onboarded=%s(应true) tutorial_active=%s(应false)" % [GameState.onboarded, GameState.tutorial_active])
	print("  PLAYTHROUGH DONE")
	get_tree().quit(0)
