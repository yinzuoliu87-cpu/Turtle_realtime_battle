extends Node
var _fail := 0
var _n := 0
func _ok(nm: String, c: bool, d: String = "") -> void:
	_n += 1
	if c: print("  [PASS] ", nm, "  ", d)
	else:
		_fail += 1; print("  [FAIL] ", nm, "  ", d)
## verify_debug_equip_pick —— 调试场「点单位 → 加装备 → 点装备」整条真点击链路哪一步断(用户 2026-10-04「调试场现在根本选不到装备」)
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

func _click(p: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		get_viewport().push_input(ev)
		await get_tree().process_frame
		await get_tree().process_frame

func _find_btn(n: Node, txt: String) -> Button:
	if n is Button and str((n as Button).text).find(txt) >= 0 and (n as Button).is_visible_in_tree():
		return n
	for c in n.get_children():
		var r = _find_btn(c, txt)
		if r != null: return r
	return null

func _ready() -> void:
	get_tree().root.size = Vector2i(1560, 720)
	RB.DEBUG_EDIT = true
	RB._edit_collapsed = false
	var scene = RB.new()
	add_child(scene)
	for _i in range(8):
		await get_tree().process_frame
	var u = scene._debug._edit_place_unit("basic", "left", Vector2(450, 0))
	for _i in range(8):
		await get_tree().process_frame
	var sp: Vector2 = scene._cam.unproject_position(scene._world_pos(u["pos"], u["height"] + 1.0))
	var mv := InputEventMouseMotion.new(); mv.position = sp; mv.global_position = sp; get_viewport().push_input(mv)
	await get_tree().process_frame
	var hv = get_viewport().gui_get_hovered_control()
	await _click(sp)
	_ok("① 真点击场上单位 ⇒ 选中", scene._edit_sel_unit != null)
	if scene._edit_sel_unit == null:
		scene._debug._edit_select_unit(u)
		await get_tree().process_frame
	for _i in range(4):
		await get_tree().process_frame
	for _i in range(4):
		await get_tree().process_frame
	var add := _find_btn(scene, "加装备")
	_ok("② 找到「➕ 加装备」", add != null)
	if add == null:
		print("FAIL x%d" % _fail); get_tree().quit(1); return
	_ok("②a 左面板底边在笔刷栏上方(不被盖住)", scene._edit_palette.get_global_rect().end.y <= scene._edit_brush_bar.get_global_rect().position.y, "%s vs %s" % [scene._edit_palette.get_global_rect().end.y, scene._edit_brush_bar.get_global_rect().position.y])
	var c2: Vector2 = add.get_global_rect().get_center()
	var mv2 := InputEventMouseMotion.new(); mv2.position = c2; mv2.global_position = c2; get_viewport().push_input(mv2)
	await get_tree().process_frame
	var hv2 = get_viewport().gui_get_hovered_control()
	await _click(c2)
	_ok("③ 真点击「➕ 加装备」⇒ 弹出装备格子", scene._edit_grid_popup != null and is_instance_valid(scene._edit_grid_popup))
	if scene._edit_grid_popup == null:
		print("FAIL x%d" % _fail); get_tree().quit(1); return
	var card: Button = null
	var stack: Array = [scene._edit_grid_popup]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Button and n.custom_minimum_size == Vector2(128, 112):
			if card == null or n.get_global_rect().position.y < card.get_global_rect().position.y or (n.get_global_rect().position.y == card.get_global_rect().position.y and n.get_global_rect().position.x < card.get_global_rect().position.x):
				card = n
		for c in n.get_children(): stack.append(c)
	if card != null:
		await _click(card.get_global_rect().get_center())
	_ok("⑤ 真点击装备卡 ⇒ 这件装进选中单位", (u.get("_edit_equips", []) as Array).size() == 1, str(u.get("_edit_equips", [])))
	scene.queue_free()
	for _i in range(4):
		await get_tree().process_frame
	## ── 触屏版(2026-10-05 用户「手机上调试场点不了装备」): 鼠标版全绿而手机上照样不行 ⇒ 同一条链路用真触摸再走一遍 ──
	await _touch_flow(Vector2i(1560, 720), "2340×1080")
	await _touch_flow(Vector2i(1334, 750), "1334×750")
	print("ALL PASS — 调试场选装备" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## ════════════ 触屏 ════════════
## ★走 `Input.parse_input_event`(不是 push_input): 只有这条路会经过 emulate_mouse_from_touch 生成模拟鼠标,
##   与手机上一模一样。★`emulate_touch_from_mouse` 打开 ⇒ `DisplayServer.is_touchscreen_available()` 为真,
##   ScrollContainer 才走它的触屏拖动分支(手机上就是这样; 桌面无头默认关, 那条分支根本不跑)。
## ★真手指点一下几乎必带几像素抖动 ⇒ 每次 tap 都夹两帧 ScreenDrag(共 4px), 这是本门禁的要点:
##   鼠标点击零位移, 所以鼠标版量不出「一抖就算拖」这一类。
var _xf: Transform2D = Transform2D.IDENTITY
var _tpos: Vector2 = Vector2.ZERO

func _t_ev(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await get_tree().process_frame

func _t_down(p: Vector2) -> void:
	var t := InputEventScreenTouch.new(); t.index = 0; t.pressed = true; t.position = _xf * p
	_tpos = p
	await _t_ev(t)

func _t_move(p: Vector2) -> void:
	var d := InputEventScreenDrag.new(); d.index = 0; d.position = _xf * p
	d.relative = _xf.basis_xform(p - _tpos); d.screen_relative = d.relative
	_tpos = p
	await _t_ev(d)

func _t_up() -> void:
	var t := InputEventScreenTouch.new(); t.index = 0; t.pressed = false; t.position = _xf * _tpos
	await _t_ev(t)
	await get_tree().process_frame

## 一次手指点按: 按下 → 抖 2px → 再抖 2px → 抬起。
func _tap(p: Vector2) -> void:
	await _t_down(p)
	await _t_move(p + Vector2(2, 1))
	await _t_move(p + Vector2(3, 3))
	await _t_up()

func _touch_flow(win: Vector2i, tag: String) -> void:
	var em0: bool = Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	Input.emulate_mouse_from_touch = true
	get_tree().root.size = win
	for _i in range(3):
		await get_tree().process_frame
	_xf = get_tree().root.get_final_transform()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	RB._edit_collapsed = false
	var scene = RB.new()
	add_child(scene)
	for _i in range(8):
		await get_tree().process_frame
	_ok("T0 %s 触屏可用(分母: ScrollContainer 走触屏分支)" % tag, DisplayServer.is_touchscreen_available())
	var u = scene._debug._edit_place_unit("basic", "left", Vector2(450, 0))
	for _i in range(8):
		await get_tree().process_frame
	var sp: Vector2 = scene._cam.unproject_position(scene._world_pos(u["pos"], u["height"] + 1.0))
	## 窄屏(1334×750 ⇒ 1280 宽)时 x=450 那一点落在左面板底下 —— 点到的是面板不是单位。挪到面板右边去点。
	var home: Vector2 = u["pos"]
	var pr: Rect2 = scene._edit_palette.get_global_rect().grow(70.0)
	while pr.has_point(sp) and home.x < 900.0:
		home.x += 50.0
		u["pos"] = home
		await get_tree().process_frame
		sp = scene._cam.unproject_position(scene._world_pos(u["pos"], u["height"] + 1.0))
	_ok("T0 %s 点的那一点不在面板底下(分母)" % tag, not pr.has_point(sp), "%s home=%s" % [sp, home])
	await _t_down(sp)
	_ok("T0 %s 坐标换算对(手指落点 = 目标点)" % tag, get_viewport().get_mouse_position().distance_to(sp) < 1.5,
		"%s vs %s" % [get_viewport().get_mouse_position(), sp])
	await _t_move(sp + Vector2(2, 1))
	await _t_move(sp + Vector2(3, 3))
	await _t_up()
	_ok("T① %s 手指点场上单位(带 4px 抖动) ⇒ 选中" % tag, scene._edit_sel_unit != null and is_same(scene._edit_sel_unit, u), "sel=%s units=%d" % [str(scene._edit_sel_unit.get("pos")) if scene._edit_sel_unit != null else "null", scene._units.size()])
	_ok("T① %s 点一下不算拖(单位没被挪走)" % tag, (u["pos"] as Vector2).distance_to(home) < 0.5, str(u["pos"]))
	if scene._edit_sel_unit == null:
		scene._debug._edit_select_unit(u)
	for _i in range(8):
		await get_tree().process_frame
	var add := _find_btn(scene, "加装备")
	_ok("T② %s 找到「➕ 加装备」" % tag, add != null)
	if add == null:
		scene.queue_free(); Input.emulate_touch_from_mouse = em0; return
	var ar: Rect2 = add.get_global_rect()
	var bar_top: float = scene._edit_brush_bar.get_global_rect().position.y
	_ok("T② %s 「加装备」整颗在屏内且在笔刷栏上方(不用先滑)" % tag,
		ar.position.x >= 0 and ar.position.y >= 0 and ar.end.x <= vp.x and ar.end.y <= bar_top, "%s bar_top=%s vp=%s" % [ar, bar_top, vp])
	var c2: Vector2 = ar.get_center()
	await _tap(c2)
	_ok("T③ %s 手指点「➕ 加装备」⇒ 弹出装备格子" % tag, scene._edit_grid_popup != null and is_instance_valid(scene._edit_grid_popup))
	if scene._edit_grid_popup == null:
		scene.queue_free(); Input.emulate_touch_from_mouse = em0; return
	for _i in range(4):
		await get_tree().process_frame
	var cards: Array = []
	var sc: ScrollContainer = null
	var stack: Array = [scene._edit_grid_popup]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Button and n.custom_minimum_size == Vector2(128, 112):
			cards.append(n)
		if n is ScrollContainer and sc == null:
			sc = n
		for c in n.get_children(): stack.append(c)
	_ok("T③ %s 卡片在场(分母)" % tag, cards.size() >= 50 and sc != null, "cards=%d" % cards.size())
	cards.sort_custom(func(a, b): return a.get_global_rect().position.y < b.get_global_rect().position.y or (a.get_global_rect().position.y == b.get_global_rect().position.y and a.get_global_rect().position.x < b.get_global_rect().position.x))
	var card: Button = cards[0]
	await _tap(card.get_global_rect().get_center())
	_ok("T⑤ %s 手指点装备卡(带抖动) ⇒ 这件装进选中单位" % tag, (u.get("_edit_equips", []) as Array).size() == 1, str(u.get("_edit_equips", [])))
	## 手指在卡片网格上往上滑 ⇒ 是滚动, 不是点卡
	var n0: int = (u.get("_edit_equips", []) as Array).size()
	var v0: int = sc.scroll_vertical
	var g: Vector2 = cards[cards.size() / 2].get_global_rect().get_center()
	g.y = clampf(g.y, sc.get_global_rect().position.y + 150.0, sc.get_global_rect().end.y - 20.0)
	await _t_down(g)
	for k in range(8):
		await _t_move(g - Vector2(0, 15 * (k + 1)))
	await _t_up()
	_ok("T⑥ %s 手指上滑卡片网格 ⇒ 滚动了" % tag, sc.scroll_vertical > v0, "%d → %d" % [v0, sc.scroll_vertical])
	_ok("T⑥ %s 滑动不误点卡" % tag, (u.get("_edit_equips", []) as Array).size() == n0)
	for _i in range(30):
		await get_tree().process_frame
	## 滑完再点一张(滚动后可见的那张)
	var vis: Button = null
	var scr: Rect2 = sc.get_global_rect()
	for cd in cards:
		var r: Rect2 = (cd as Button).get_global_rect()
		if scr.encloses(r):
			vis = cd; break
	if vis != null:
		await _tap(vis.get_global_rect().get_center())
	_ok("T⑦ %s 滑过之后手指再点一张卡 ⇒ 第二件装上" % tag, (u.get("_edit_equips", []) as Array).size() == n0 + 1, str(u.get("_edit_equips", [])))
	## 阈值没把「拖单位挪位」也弄坏: 关掉弹层, 手指按住单位拖 60px ⇒ 单位跟着走
	scene._debug._edit_close_popup()
	for _i in range(4):
		await get_tree().process_frame
	sp = scene._cam.unproject_position(scene._world_pos(u["pos"], u["height"] + 1.0))
	var before: Vector2 = u["pos"]
	await _t_down(sp)
	for k in range(6):
		await _t_move(sp + Vector2(10 * (k + 1), 0))
	await _t_up()
	_ok("T⑧ %s 手指拖单位 60px ⇒ 单位挪了(拖拽没被阈值弄坏)" % tag, (u["pos"] as Vector2).distance_to(before) > 5.0, "%s → %s" % [before, u["pos"]])
	scene.queue_free()
	for _i in range(4):
		await get_tree().process_frame
	Input.emulate_touch_from_mouse = em0
