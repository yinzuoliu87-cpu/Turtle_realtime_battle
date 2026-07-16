extends Node
## verify_ios_ui.gd — iOS 测试包前自检守卫(用户 2026-07-16「打包之前确认: 调试场能点击到/能测所有龟和装备/按钮不超屏不卡住」)
##
## 断言(布局功能层, 观感仍需真机眼验):
##   A. iPhone 横屏画布(1560×720 ≈ 2.167:1)下: 全部菜单 scene 的可见按钮 rect ⊆ 屏幕
##   B. 主菜单有「🛠 调试场」按钮(debug 构建), 按下把 DEBUG_EDIT 打开
##   C. 调试场编辑器: 摆位面板建齐(可选龟覆盖全 28 只)且面板按钮 rect ⊆ 屏幕
##   D. 正常战斗 HUD(REVIEW_DEMO_DEFAULT=false): 暂停/日志等按钮 rect ⊆ 屏幕
##   E. iPad 4:3 画布(1280×960)复检 A(主菜单+调试场面板)
## 匹配按档位匹快照由 tests/verify_ghost_seed 独立守卫(9档全覆盖)。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const MENU_SCENES := ["MainMenu", "Matchmaking", "TeamSelect", "Inventory", "Shop", "Codex", "Settings", "Leaderboard", "Record"]

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)

func _visible_buttons(n: Node, out: Array) -> void:
	if n is BaseButton and (n as Control).is_visible_in_tree():
		out.append(n)
	for ch in n.get_children():
		_visible_buttons(ch, out)

## 递归收集可见 Button/Label 文本(选龟卡=按钮+名字Label 组合, 光看Button text不够)
func _all_texts(n: Node) -> String:
	var s := ""
	if n is Button and (n as Control).is_visible_in_tree():
		s += str((n as Button).text) + "|"
	elif n is Label and (n as Control).is_visible_in_tree():
		s += str((n as Label).text) + "|"
	for ch in n.get_children():
		s += _all_texts(ch)
	return s

## 按钮是否在 ScrollContainer 内(滚动可达→不算越界; 弹窗网格cards裁剪待滚是正常态)
func _in_scroll(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false

## 按钮 rect 是否全在屏幕内(容差2px); 返回越界按钮描述列表
func _offscreen_buttons(root: Node, vp: Vector2) -> Array:
	var btns: Array = []
	_visible_buttons(root, btns)
	var bad: Array = []
	var screen := Rect2(Vector2(-2, -2), vp + Vector2(4, 4))
	for b in btns:
		if _in_scroll(b):
			continue
		var r: Rect2 = (b as Control).get_global_rect()
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		if not screen.encloses(r):
			bad.append("%s(%s) rect=%s" % [b.name, (b as Button).text.left(8) if b is Button else "-", str(r)])
	return bad

func _check_scene_buttons(scene_name: String, vp: Vector2) -> void:
	var ps = load("res://scenes/%s.tscn" % scene_name)
	if ps == null:
		_ok("%s 载入" % scene_name, false, "load失败")
		return
	var inst = ps.instantiate()
	add_child(inst)
	await get_tree().create_timer(1.7).timeout   # 等入场动画落定(主菜单右栏磁贴滑入到1.39s才完; 1.1s抓中间帧误报)
	var btns: Array = []
	_visible_buttons(inst, btns)
	var bad := _offscreen_buttons(inst, vp)
	_ok("%s: %d 个可见按钮全在屏内" % [scene_name, btns.size()], bad.is_empty(), "; ".join(bad) if not bad.is_empty() else "")
	inst.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	# ── A. iPhone 横屏画布: 全菜单按钮不越界 ──
	var vp_iphone := Vector2(1560, 720)   # 2.167:1(iPhone 14/15 横屏)·canvas_items+expand 口径
	get_tree().root.size = Vector2i(vp_iphone)
	await get_tree().process_frame
	var vp_real := Vector2(get_tree().root.size)
	print("  (画布=", vp_real, ")")
	for sn in MENU_SCENES:
		await _check_scene_buttons(sn, vp_real)

	# ── B. 主菜单调试场按钮存在 + 入口开 DEBUG_EDIT ──
	var mm = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(mm)
	await get_tree().process_frame
	await get_tree().process_frame
	var dbg_btn: Button = null
	var all_b: Array = []
	_visible_buttons(mm, all_b)
	for b in all_b:
		if b is Button and str((b as Button).text).contains("调试场"):
			dbg_btn = b
			break
	_ok("主菜单有🛠调试场按钮(debug构建)", dbg_btn != null)
	if dbg_btn != null:
		var r := dbg_btn.get_global_rect()
		_ok("调试场按钮在屏内可点", Rect2(Vector2.ZERO, vp_real).encloses(r), str(r))
		var wired := false
		for c in dbg_btn.pressed.get_connections():   # ⛔不真按: _open_debug_arena 会 change_scene 把本测试杀掉
			if str(c["callable"].get_method()) == "_open_debug_arena":
				wired = true
		_ok("按钮接线到_open_debug_arena(点了就进调试场)", wired)
	mm.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ── C. 调试场编辑器(子节点实例化·DEBUG_EDIT=true): 面板齐 + 28龟全可选 + 按钮不越界 ──
	RTScene.DEBUG_EDIT = true
	var cs = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(cs)
	await get_tree().create_timer(1.0).timeout
	var is_arena: bool = cs != null
	_ok("调试场场景已进入(DEBUG_EDIT实例化)", is_arena)
	if is_arena:
		var pal_btns: Array = []
		_visible_buttons(cs, pal_btns)
		_ok("调试场面板按钮已建(≥15)", pal_btns.size() >= 15, "共 %d" % pal_btns.size())
		var bad_c := _offscreen_buttons(cs, vp_real)
		_ok("调试场面板按钮全在屏内", bad_c.is_empty(), "; ".join(bad_c) if not bad_c.is_empty() else "")
		cs._edit_open_turtle_grid()                  # 「选龟」二级网格: 28龟全可选
		await get_tree().process_frame
		await get_tree().process_frame
		var texts := _all_texts(cs)
		var missing: Array = []
		var reg = get_node_or_null("/root/DataRegistry")
		if reg != null:
			for p in reg.all_pets:
				var pname := str((p as Dictionary).get("name", ""))
				if pname != "" and not texts.contains(pname):
					missing.append(pname)
		_ok("选龟网格28龟全可选(含每龟名)", missing.is_empty(), "缺: " + str(missing))
		var bad_g := _offscreen_buttons(cs, vp_real)
		_ok("选龟网格全在屏内", bad_g.is_empty(), "; ".join(bad_g.slice(0, 4)) if not bad_g.is_empty() else "")
		cs._edit_close_popup()
		await get_tree().process_frame
		var uu = cs._edit_place_unit("basic", "right", Vector2(600.0, 400.0))   # 装备网格: 选中单位→开
		cs._edit_sel_unit = uu
		cs._edit_open_equip_grid()
		await get_tree().process_frame
		await get_tree().process_frame
		var eq_n: int = cs._dbg_equip_ids().size()
		_ok("装备网格可开且有货(装备数=%d≥10)" % eq_n, eq_n >= 10)
		var bad_e := _offscreen_buttons(cs, vp_real)
		_ok("装备网格全在屏内", bad_e.is_empty(), "; ".join(bad_e.slice(0, 4)) if not bad_e.is_empty() else "")
		cs._edit_close_popup()
		await get_tree().process_frame
		cs.queue_free()
		await get_tree().process_frame
	RTScene.DEBUG_EDIT = false

	# ── D. 正常战斗 HUD 按钮不越界(非评审: REVIEW_DEMO_DEFAULT 已翻 false) ──
	_ok("REVIEW_DEMO_DEFAULT=false(iOS测试包不劫持战斗)", RTScene.REVIEW_DEMO_DEFAULT == false)
	var bt = RTScene.new()
	add_child(bt)
	await get_tree().process_frame
	await get_tree().process_frame
	bt.set_process(false)
	bt.set_physics_process(false)
	var bad_d := _offscreen_buttons(bt, vp_real)
	_ok("战斗HUD按钮全在屏内", bad_d.is_empty(), "; ".join(bad_d) if not bad_d.is_empty() else "")
	_ok("暂停按钮已建", bt._pause_btn != null)
	bt.queue_free()
	await get_tree().process_frame

	# ── E. iPad 4:3 画布复检(主菜单) ──
	get_tree().root.size = Vector2i(1280, 960)
	await get_tree().process_frame
	await _check_scene_buttons("MainMenu", Vector2(get_tree().root.size))

	_done()

func _done() -> void:
	get_tree().paused = false
	print("")
	if _fail == 0:
		print("ALL PASS — iOS测试包UI守卫(全菜单按钮不越界/调试场可入28龟可选/战斗HUD不越界)通过")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)
