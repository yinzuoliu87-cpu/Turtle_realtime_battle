extends Node
## verify_present_click_anywhere.gd — 换路幕布「点击继续」点哪都要能继续(2026-10-14 内测反馈)
##
## 用户:「在切换下半战场时我点击中间的区域继续，怎么没反应」。
## 根因: 幕布底板 `back` 接 gui_input, 而中间那块的 CenterContainer / 面板 / 对阵卡 / 头像框
##   都是默认 mouse_filter = STOP ⇒ 按下被它们吃掉, 不往上冒到 `back`。
##   修前实测: 45 个控件中心逐个点, 45 个全没反应; 只有幕布四周的空白边能点。
## 判据(真点击, 经 Viewport.push_input 走引擎自己的 GUI 拾取):
##   ① 对阵幕布(preview)里每个可见控件的中心点一下 ⇒ 幕布都被点掉
##   ② 装备格悬停提示仍在(改成 PASS 不能把 tooltip 弄没)
##   分母: 点过的控件数 ≥ 10, 且其中有头像框 Panel。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_present_click_anywhere.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0
var _s = null
var _gs = null


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _click(p: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	get_viewport().push_input(mm, true)
	await get_tree().process_frame
	## ★push_input 第二参必须 true(视口本地坐标): 无头窗口比 1280 视口小, 默认按窗口坐标换算,
	##   只有左上角那一点落得进幕布 —— 写这条测试时我先被它骗过一轮「中间全点不动」。
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		e.position = p
		e.global_position = p
		get_viewport().push_input(e, true)
		await get_tree().process_frame


func _enter_preview() -> Control:
	_s._dl_sys._dl_enter_present("preview")
	## 等入场缩放动画(0.07×i + 0.26 秒)走完、布局落定
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 500:
		await get_tree().process_frame
	return _s._dl_present_root


func _targets(root: Control) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var c = stack.pop_back()
		for ch in c.get_children():
			stack.append(ch)
		if c == root or not (c is Control) or not (c as Control).is_visible_in_tree():
			continue
		var r: Rect2 = (c as Control).get_global_rect()
		if r.size.x < 4.0 or r.size.y < 4.0:
			continue
		out.append(c)
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	_gs.test_mode = true
	print("=== 换路幕布点哪都能继续 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_gs.current_lane = "bottom"

	var root: Control = await _enter_preview()
	_ok("分母: 下路对阵幕布在场", root != null and is_instance_valid(root))
	if root == null:
		get_tree().quit(1)
		return
	var tg := _targets(root)
	## 只记位置与种类: 每点一次幕布就换一张, 节点引用会失效
	var pts: Array = []
	var n_panel := 0
	var tips := 0
	var seen := {}
	for c in tg:
		var ctr: Vector2 = (c as Control).get_global_rect().get_center()
		## 同一点(±12px)只点一次: 卡片 / 卡内 HBox / 头像框中心常常重合, 重复点不多验任何东西
		var key := Vector2i(roundi(ctr.x / 12.0), roundi(ctr.y / 12.0))
		if c.get_class() == "Panel":
			n_panel += 1
		if seen.has(key):
			continue
		seen[key] = true
		pts.append([ctr, c.get_class(), str(c.name)])
		if (c as Control).tooltip_text != "":
			tips += 1
	_ok("分母: 幕布里可点的控件 ≥ 10 个(含头像框 Panel)", pts.size() >= 10 and n_panel >= 1, "控件 %d · Panel %d" % [pts.size(), n_panel])

	## ① 真点击端到端: 点正中间一次 ⇒ 幕布推进(下路开始建场 → place)
	root = await _enter_preview()
	await _click(get_viewport().get_visible_rect().get_center())
	_ok("① ★点屏幕正中间 ⇒ 下路对阵幕布推进", str(_s._dl_state) != "preview", "state=%s" % str(_s._dl_state))

	## ①' 其余每个点: 只量「点击冒到了底板」(底板 → 推进那一段上面已端到端验过)。
	##   每次真推进都要重建整路战场(一次约 9 秒), 60 个点跑不完 ⇒ 摘掉底板自己的回调, 换成计数器。
	root = await _enter_preview()
	for cn in root.gui_input.get_connections():
		root.gui_input.disconnect(cn["callable"])
	var hits := [0]
	root.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: hits[0] += 1)
	var missed: Array = []
	for i in range(pts.size()):
		var h0: int = hits[0]
		await _click(pts[i][0])
		if hits[0] == h0:
			missed.append("%s(%s)@%s" % [pts[i][2], pts[i][1], str(pts[i][0])])
	_ok("①' ★对阵幕布上每个控件的中心点下去都冒到底板(%d 处)" % pts.size(), missed.is_empty() and hits[0] == pts.size(),
		"没反应 %d 处: %s" % [missed.size(), str(missed)])

	## ② 悬停提示不能因此没掉: 装备格(挂 RichTooltip)放进幕布后仍收得到悬停(不是 IGNORE)且文案还在
	##   (默认阵容没带装备, 幕布里没有装备格 ⇒ 自己造一个, 走同一个 _dl_pass_clicks_to)
	var eid := str(DataRegistry.phase2_equipment[0].get("id", ""))
	var holder := ColorRect.new()
	var chip: Control = _s._dl_sys._dl_equip_chip(eid, 2)
	holder.add_child(chip)
	_s._dl_sys._dl_pass_clicks_to(holder)
	_ok("② 装备格放进幕布后仍收悬停、提示文案还在", chip.mouse_filter == Control.MOUSE_FILTER_PASS and chip.tooltip_text != "",
		"filter=%d tip=%d字" % [chip.mouse_filter, chip.tooltip_text.length()])
	holder.free()

	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 换路幕布点哪都能继续 (%d/%d)" % [_n, _n])
	get_tree().quit(1 if _fail > 0 else 0)
