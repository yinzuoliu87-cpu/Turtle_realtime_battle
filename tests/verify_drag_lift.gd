extends Node
## verify_drag_lift.gd — 光标点击点 + 拿起卡片的摆法(2026-10-30 · 方案书 docs/plans/20261030-光标与拿卡.md)
##
## 用户 10-29「到底什么是鼠标的中心？…我抓起卡片这个中心怎么搞」→ 10-30「商业游戏做法呢」→「改这个代码肯定要改」。
## 照商业做法: 光标斜指左上、只有一个尖、点击点 = 爪尖; 拖东西时握拳。拿起卡片: 按下那一点不跳 → 卡中心滑到鼠标下
##   (电脑) / 抬到手指上方(手机); 放大、摆正、投影; 原位虚影, 拖完复原。四处(背包装备 / 单位卡 / 卡上装备 / 选统领龟卡 / 编队槽)同一套。
## 段落(每条带分母):
##   C1 平时爪子: 贴图里最靠左上的爪尖像素 = 点击点 HOT; 中趾明显比两侧短趾伸得远(只有一个尖)
##   C2 握拳: 最靠左上的那块实心(非描边)= 左上第一颗指节 = HOT_FIST
##   C3 ★真的拖起来时光标是握拳、点击点换成 HOT_FIST、原大不发青光; 松手后回到平时
##   C4 ★浅色填充 + 深描边(10-30 第二轮方向稿): 轮廓一圈全是近黑描边, 身是浅色 —— 绿身压在绿龟 / 绿装备格上看不见
##   D1 ★五个拖动源都用 DragLift, 且记下的按下点 = 真按下的那一点(卡内坐标, 差 ≤ 1px)
##   D2 ★拿起那一刻不跳: 按下点正好在鼠标点上
##   D3 ★电脑: 滑到位后卡中心离鼠标 ≤ 1px; 半途在两者之间(是滑过去不是瞬移)
##   D4 手机: 滑到位后卡底在手指上方 TOUCH_GAP、左右居中
##   D5 原位虚影: 拖动中原位 = GHOST_A(卡上装备那种不虚整张卡), 拖动结束复原成 1
## 反向验证(改坏 → 红 → 逐字节还原)见方案书 §6。

const INV := preload("res://scenes/Inventory.tscn")
const TS := preload("res://scenes/TeamSelect.tscn")
const CT := preload("res://autoload/CursorTheme.gd")

var _fail := 0
var _n := 0
var ct


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _btn(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; e.position = p; e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(e, true)


func _move(p: Vector2, rel: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p; m.global_position = p; m.relative = rel
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(m, true)


## 按下 p → 横移 24px(过引擎 10px 门槛)→ 返回这次的 DragLift(没拖起来 ⇒ null)。不松手。
func _lift_at(p: Vector2) -> DragLift:
	DragLift._last = null
	_btn(p, true)
	await get_tree().process_frame
	var q := p
	for _k in range(3):
		q += Vector2(8, 0)
		_move(q, Vector2(8, 0))
		await get_tree().process_frame
	var d := DragLift.last()
	return d if d != null and d.is_inside_tree() and get_viewport().gui_is_dragging() else null


func _release() -> void:
	if get_viewport().gui_is_dragging():
		get_viewport().gui_cancel_drag()
	_btn(Vector2(5, 5), false)
	for _i in range(3):
		await get_tree().process_frame


## [最靠左上的爪尖色像素(24 设计px 坐标), 每根爪(爪尖色连通块)离左上角最近那一点的 x+y(设计px, 升序)]
func _tips(tex: Texture2D, cream: Color) -> Array:
	var img := tex.get_image()
	var k := float(CT.ART) / float(img.get_width())
	var w := img.get_width()
	var h := img.get_height()
	var seen := {}
	var claws: Array = []
	var best := Vector2(-1, -1)
	for y in range(h):
		for x in range(w):
			if seen.has(y * w + x) or not img.get_pixel(x, y).is_equal_approx(cream):
				continue
			## 一根爪 = 一块 4 邻连通的爪尖色
			var lo := x + y
			var st: Array = [Vector2i(x, y)]
			seen[y * w + x] = true
			while not st.is_empty():
				var p: Vector2i = st.pop_back()
				lo = mini(lo, p.x + p.y)
				if best.x < 0.0 or p.x + p.y < int(best.x + best.y):
					best = Vector2(p)
				for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = p + dd
					if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and not seen.has(q.y * w + q.x) \
							and img.get_pixel(q.x, q.y).is_equal_approx(cream):
						seen[q.y * w + q.x] = true
						st.append(q)
			claws.append(float(lo) * k)
	claws.sort()
	return [best * k, claws]


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## 最靠左上的那块实心(不透明且不是深描边)像素, 24 设计px 坐标; 找不到 ⇒ (-1,-1)
func _first_fill(tex: Texture2D) -> Vector2:
	var img := tex.get_image()
	var best := Vector2(-1, -1)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and _lum(c) > 0.3 and (best.x < 0.0 or x + y < int(best.x + best.y)):
				best = Vector2(x, y)
	return best * (float(CT.ART) / float(img.get_width())) if best.x >= 0.0 else best


func _argmax(count: Dictionary, skip: String) -> String:
	var best := ""
	for k in count:
		if k != skip and (best == "" or int(count[k]) > int(count[best])):
			best = k
	return best


## [轮廓像素数(不透明且 4 邻有透明或出界), 其中最亮那颗的亮度, 身色]
## 身色 = 除描边色(轮廓上最多的那种)以外最多的颜色 —— 指着的爪子很细, 描边像素比身还多, 不能直接取最多的。
func _edge_and_body(tex: Texture2D) -> Array:
	var img := tex.get_image()
	var w := img.get_width()
	var h := img.get_height()
	var n_edge := 0
	var edge_max := 0.0
	var count := {}
	var edge_count := {}
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			if c.a <= 0.5:
				continue
			count[c.to_html()] = int(count.get(c.to_html(), 0)) + 1
			for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + dd
				if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or img.get_pixel(q.x, q.y).a <= 0.5:
					n_edge += 1
					edge_max = maxf(edge_max, _lum(c))
					edge_count[c.to_html()] = int(edge_count.get(c.to_html(), 0)) + 1
					break
	var body := _argmax(count, _argmax(edge_count, ""))
	return [n_edge, edge_max, Color(body) if body != "" else Color(0, 0, 0, 0)]


func _ready() -> void:
	await get_tree().process_frame
	GameState.test_mode = true
	print("=== 光标点击点 + 拿起卡片 ===")
	ct = CT.new()
	add_child(ct)
	ct._build_cursor()

	# ── C1 / C2 ──
	var tp: Array = _tips(ct._point_tex, ct._point_cols[0])
	var cl: Array = tp[1]
	_ok("C1 分母: 平时爪子里找得到爪尖, 且有 3 根爪", (tp[0] as Vector2).x >= 0.0 and cl.size() == 3, "爪 %d 根 %s" % [cl.size(), str(cl)])
	_ok("C1 ★爪尖(最靠左上的爪尖色像素) = 点击点 HOT", (tp[0] as Vector2).is_equal_approx(CT.HOT), "爪尖 %s · HOT %s" % [tp[0], CT.HOT])
	## 只有一个尖: 中趾(离左上最近的那根)比第二近的那根至少往左上多伸 8 设计px(旧爪子三根并排只差 6)
	var gap: float = (float(cl[1]) - float(cl[0])) if cl.size() >= 2 else 0.0
	_ok("C1 ★只有一个尖: 中趾比两侧短趾往左上多伸 ≥ 8 设计px", gap >= 8.0, "多伸 %.1f" % gap)
	var ff: Vector2 = _first_fill(ct._fist_tex)
	_ok("C2 分母: 握拳里找得到实心像素", ff.x >= 0.0, str(ff))
	_ok("C2 ★握拳: 左上第一颗指节 = HOT_FIST", ff.is_equal_approx(CT.HOT_FIST), "指节 %s · HOT_FIST %s" % [ff, CT.HOT_FIST])
	## 平时那只按同一把尺子量也得落在 HOT 上(爪尖就是最靠左上的实心) —— 两张图同一个规矩
	_ok("C2 平时爪子按同一把尺子: 最靠左上的实心 = HOT", _first_fill(ct._point_tex).is_equal_approx(CT.HOT), str(_first_fill(ct._point_tex)))

	# ── C4 浅色填充 + 深描边 ──
	for pair in [["平时", ct._point_tex], ["握拳", ct._fist_tex]]:
		var eb: Array = _edge_and_body(pair[1])
		_ok("C4 分母: %s轮廓像素 ≥ 40" % pair[0], int(eb[0]) >= 40, "轮廓 %d" % int(eb[0]))
		_ok("C4 ★%s: 轮廓一圈全是近黑描边(最亮 ≤ 0.15)" % pair[0], float(eb[1]) <= 0.15, "最亮 %.2f" % float(eb[1]))
		var body: Color = eb[2]
		_ok("C4 ★%s: 身是浅色(亮度 ≥ 0.8)、不是游戏主色绿" % pair[0], _lum(body) >= 0.8 and not (body.g > body.r + 0.1 and body.g > body.b + 0.1),
			"身 %s 亮度 %.2f" % [body.to_html(false), _lum(body)])

	# ── 背包(打了一周的号: 有装备、统领、小将) ──
	load("res://tests/_setup_appstore.gd").run()
	GameState.season_level = 10
	var sc = INV.instantiate()
	add_child(sc)
	(sc as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
	(sc as Control).size = Vector2(1280, 720)
	for _i in range(6):
		await get_tree().process_frame

	## 背包里一件装备(按在格子左上四分之一处 ⇒ 按下点不在中心, 量得出「不跳」)
	var cell: Control = sc._tut_first_item
	var press: Vector2 = cell.get_global_rect().position + cell.size * Vector2(0.3, 0.3)
	var d: DragLift = await _lift_at(press)
	_ok("D1 ★背包装备: 拿起来用的是 DragLift", d != null)
	if d != null:
		## 跟手那张(PREVIEW_PX 小卡)上的按下点 = 格子里的相对位置换算过去
		_ok("D1 背包装备: 按下点按格子里的相对位置换算", d.grab.distance_to(Vector2(0.3, 0.3) * sc._drag.PREVIEW_PX) <= 1.5, str(d.grab))
		_ok("D5 ★背包装备: 拖动中原位是虚影", is_equal_approx(cell.modulate.a, DragLift.GHOST_A), "a=%.2f" % cell.modulate.a)
		## C3: 光标此刻是握拳(产品自己的 _process 算的)
		ct._process(0.016)
		## 现场一并打出来(2026-10-30 本机 ~18 次里红过 1 次、复现不出 —— 再红时直接看是不是没在拖 / 光标没启用 / 被强制态盖了)
		var scene := "拖动中=%s 启用=%s 强制态=「%s」 悬停=%s" % [get_viewport().gui_is_dragging(), ct._enabled, ct._forced,
			get_viewport().gui_get_hovered_control().name if get_viewport().gui_get_hovered_control() != null else "无"]
		_ok("C3 ★拖动中光标是握拳", ct._g.texture == ct._fist_tex, scene)
		_ok("C3 ★拖动中点击点换成 HOT_FIST", ct._cur.pivot_offset.is_equal_approx(CT.HOT_FIST), "%s · %s" % [ct._cur.pivot_offset, scene])
		_ok("C3 ★拖动中握拳原大、不发青光", ct._cur.scale.is_equal_approx(Vector2.ONE) and not ct._glow.visible,
			"scale %s 青光 %s · %s" % [ct._cur.scale, ct._glow.visible, scene])
	await _release()
	_ok("D5 背包装备: 拖动结束原位复原", is_equal_approx(cell.modulate.a, 1.0), "a=%.2f" % cell.modulate.a)
	ct._process(0.016)
	_ok("C3 松手后光标回到平时", ct._g.texture == ct._point_tex and ct._cur.pivot_offset.is_equal_approx(CT.HOT))

	## 整张单位卡
	var card: Control = sc.find_child("UnitCard_top_0", true, false)
	var at := Vector2(60, 70)
	d = await _lift_at(card.get_global_rect().position + at)
	_ok("D1 ★背包单位卡: 拿起来用的是 DragLift", d != null)
	if d != null:
		_ok("D1 背包单位卡: 记下的按下点 = 真按下那一点", d.grab.distance_to(at) <= 1.0, "%s vs %s" % [d.grab, at])
		_ok("D5 ★背包单位卡: 拖动中原位是虚影", is_equal_approx(card.modulate.a, DragLift.GHOST_A), "a=%.2f" % card.modulate.a)
	await _release()
	_ok("D5 背包单位卡: 拖动结束原位复原", is_equal_approx(card.modulate.a, 1.0), "a=%.2f" % card.modulate.a)

	## 卡上一件装备(统领 two_head 身上有 3 件)
	var cw: float = sc.EQ_CELL
	var gp: float = sc.EQ_GAP
	var x0: float = sc.CARD_W / 2.0 - (3.0 * cw + 2.0 * gp) / 2.0
	card = sc.find_child("UnitCard_top_0", true, false)
	d = await _lift_at(card.get_global_rect().position + Vector2(x0 + cw * 0.5, sc.SLOT_ROW_Y + cw * 0.5))
	_ok("D1 ★卡上装备: 拿起来用的是 DragLift", d != null and str(sc._drag.dragging.get("kind", "")) == "worn",
		"kind=%s" % str(sc._drag.dragging.get("kind", "")))
	if d != null:
		_ok("D5 卡上装备: 不把整张卡变虚", is_equal_approx(card.modulate.a, 1.0), "a=%.2f" % card.modulate.a)
	await _release()
	sc.queue_free()
	for _i in range(3):
		await get_tree().process_frame

	# ── 选统领页 ──
	GameState.season_leaders = []
	var ts = TS.instantiate()
	add_child(ts)
	for _i in range(60):
		await get_tree().process_frame
	var pc: Control = null
	for c in ts._grid_flow.get_children():
		if c is Control and (c as Control).size.x > 10.0:
			pc = c
			break
	_ok("分母: 选统领页有龟卡", pc != null)
	if pc != null:
		at = pc.size * Vector2(0.25, 0.3)
		d = await _lift_at(pc.get_global_rect().position + at)
		_ok("D1 ★选统领龟卡: 拿起来用的是 DragLift(整张卡, 不是挂在右下的小头像)", d != null)
		if d != null:
			_ok("D1 选统领龟卡: 记下的按下点 = 真按下那一点", d.grab.distance_to(at) <= 1.0, "%s vs %s" % [d.grab, at])
			_ok("D5 ★选统领龟卡: 拖动中原位是虚影", is_equal_approx(pc.modulate.a, DragLift.GHOST_A), "a=%.2f" % pc.modulate.a)
		await _release()
		_ok("D5 选统领龟卡: 拖动结束原位复原", is_equal_approx(pc.modulate.a, 1.0), "a=%.2f" % pc.modulate.a)
	var ids: Array = []
	for p in DataRegistry.launch_pets:
		if not (str(p["id"]) in ["hiding", "crystal", "candy"]):
			ids.append(str(p["id"]))
		if ids.size() >= 3:
			break
	ts.team = ids.duplicate()
	ts._selected_slot_idx = -1
	ts._refresh_all()
	for _i in range(5):
		await get_tree().process_frame
	var sl: Control = ts._slot_nodes[0]
	at = sl.size * Vector2(0.7, 0.25)
	d = await _lift_at(sl.get_global_rect().position + at)
	_ok("D1 ★编队槽: 拿起来用的是 DragLift", d != null)
	if d != null:
		_ok("D1 编队槽: 记下的按下点 = 真按下那一点", d.grab.distance_to(at) <= 1.0, "%s vs %s" % [d.grab, at])
		_ok("D5 编队槽: 拖动中原位是虚影", is_equal_approx(sl.modulate.a, DragLift.GHOST_A), "a=%.2f" % sl.modulate.a)
	await _release()
	_ok("D5 编队槽: 拖动结束原位复原", is_equal_approx(sl.modulate.a, 1.0), "a=%.2f" % sl.modulate.a)

	# ── D2 / D3 / D4: 摆法本身(直接造一张, 不靠帧率) ──
	var src := Control.new()
	src.size = Vector2(192, 252)
	add_child(src)
	var frac := Vector2(0.2, 0.15)
	DragLift.force_touch = 0
	var a := DragLift.make(src, null, frac, false)
	add_child(a)
	a.set_process(false)
	_ok("D2 ★拿起那一刻不跳: 按下点正好在鼠标点上", a.grab_offset().length() <= 0.01, str(a.grab_offset()))
	_ok("D2 分母: 按下点离卡中心够远(否则「不跳」恒真)", a.center_offset().length() >= 60.0, str(a.center_offset()))
	var c0: float = a.center_offset().length()
	a.step(0.05)
	var c1: float = a.center_offset().length()
	_ok("D3 ★是滑过去不是瞬移: 0.05 秒后在半途", c1 < c0 - 1.0 and c1 > 1.0, "%.1f → %.1f" % [c0, c1])
	a.step(1.0)
	_ok("D3 ★电脑: 滑到位后卡中心离鼠标 ≤ 1px", a.center_offset().length() <= 1.0, str(a.center_offset()))
	_ok("D3 拿起放大且摆正", is_equal_approx(a._body.scale.x, DragLift.LIFT) and is_zero_approx(a._body.rotation),
		"scale %.2f rot %.2f" % [a._body.scale.x, a._body.rotation])
	a.queue_free()
	DragLift.force_touch = 1
	var b := DragLift.make(src, null, frac, false)
	add_child(b)
	b.set_process(false)
	_ok("D2 手机: 拿起那一刻同样不跳", b.grab_offset().length() <= 0.01, str(b.grab_offset()))
	b.step(1.0)
	var bottom: float = b._body.position.y + src.size.y * 0.5 + src.size.y * 0.5 * DragLift.LIFT
	_ok("D4 ★手机: 卡底在手指上方 TOUCH_GAP、左右居中",
		absf(bottom + DragLift.TOUCH_GAP) <= 1.0 and absf(b.center_offset().x) <= 1.0,
		"卡底 %.1f · 中心 x %.1f" % [bottom, b.center_offset().x])
	b.queue_free()
	DragLift.force_touch = -1

	print("\n合计 %d 项 · 失败 %d · 用了 %d 帧" % [_n, _fail, Engine.get_process_frames()])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().quit(0 if _fail == 0 else 1)
