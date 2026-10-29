extends Node
## verify_inventory_minion_drag.gd — 背包里的小将卡按在立绘上也拖得起来(2026-10-29 用户「拖不起来，你看这鼠标是不是有问题」)
##
## 病根: 小将卡「前排 / 后排」签下面挂了一块 TouchPad(立绘下半截 + 签, 整卡宽 81 高), MOUSE_FILTER_STOP 且
##   【一按下】就切站位 → 存档 → `_rebuild()` 整页重建。引擎找拖动源是从按到的控件往上走、碰到 STOP 就停,
##   根本走不到卡片本身; 而按下那一刻卡片已经被重建销毁。⇒ 按着立绘拖 = 拖不起来 + 前后排被偷偷切了。
##   新号背包里能拖的只有下路三张小将卡, 玩家伸手抓的正是立绘。
##   旧门禁 verify_inventory_drag 只拖过**统领**卡、按在立绘**上半截** y=60, 所以一直绿。
##
## 阵容照抄用户新号存档原样: 上路三个空统领位 / 下路三个小将(前·前·后)。走真入口(往视口推鼠标), 量存档。
##   ★下路 0 号是「精英小将」(统领替身, 没有前后排签); 热区只在 1 号 / 2 号普通小将卡上。
##   M1 普通小将按在立绘下半截(热区正中)横着拖 → 引擎真的进入拖动, 且站位没被切
##   M2 拖到目标卡正中(= 热区)也接得住 = 两张互换; M2b 从热区拖起再落下
##   M3 三张卡内(扣掉框边)逐点按下横拖: 能拖起的点 / 采样点 —— 分母打印, 要求 100%
##   M3b 2 号卡内逐点当落点: 接得住的点 / 采样点, 要求 100%
##   M4 不动只点一下热区 / 签 = 照旧切前后排(这功能不能修没了), 且只切一次
##   M5 点卡片别处不切站位

const INV := preload("res://scenes/Inventory.tscn")
## 采样步长: 热区 81 高 ⇒ 24 一格竖向至少落进 3 行(变异实测 24 步长红 42/63, 12 步长红 143/234, 两者都抓得到)
const STEP := 24.0

var _fail := 0
var _n := 0
var sc


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _lineup() -> Dictionary:
	return {
		"top": [
			{"id": "", "kind": "leader", "slot": 0},
			{"id": "", "kind": "leader", "slot": 1},
			{"id": "", "kind": "leader", "slot": 2},
		],
		"bottom": [
			{"kind": "minion", "role": "front"},
			{"kind": "minion", "role": "front"},
			{"kind": "minion", "role": "back"},
		],
	}


func _reset() -> void:
	GameState.dual_lineup = _lineup()
	sc._rebuild()
	for _i in range(2):
		await get_tree().process_frame


func _roles() -> String:
	var out: Array = []
	for u in (GameState.get_dual_lineup().get("bottom", []) as Array):
		out.append(str((u as Dictionary).get("role", "?")))
	return ",".join(out)


func _card(lane: String, i: int) -> Control:
	return sc.find_child("UnitCard_%s_%d" % [lane, i], true, false) as Control


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


## 按下 → 横移 40px(分 5 步) → 量「引擎是不是进入拖动了」 → 原地松手。返回是否拖起。
func _try_lift(p: Vector2) -> bool:
	_btn(p, true)
	await get_tree().process_frame
	var q := p
	for _k in range(5):
		q += Vector2(8, 0)
		_move(q, Vector2(8, 0))
		await get_tree().process_frame
	var lifted: bool = get_viewport().gui_is_dragging() and sc._drag.active()
	## 量完就放弃这次拖动: 原地松手可能落在隔壁卡上(换位 / 换装备), 后面的采样就量的是另一副阵容了
	if get_viewport().gui_is_dragging():
		get_viewport().gui_cancel_drag()
	_btn(q, false)
	for _i in range(2):
		await get_tree().process_frame
	return lifted


func _drag(from: Vector2, to: Vector2) -> void:
	_btn(from, true)
	await get_tree().process_frame
	for k in range(1, 15):
		_move(from.lerp(to, float(k) / 14.0), (to - from) / 14.0)
		await get_tree().process_frame
	_btn(to, false)
	for _i in range(3):
		await get_tree().process_frame


func _click(p: Vector2) -> void:
	_btn(p, true)
	await get_tree().process_frame
	_btn(p, false)
	for _i in range(3):
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	GameState.test_mode = true
	GameState.persistent_bench = []
	GameState.persistent_equipped = {}
	GameState.dual_lineup = _lineup()
	print("=== 背包·小将卡拖动 ===")
	sc = INV.instantiate()
	add_child(sc)
	(sc as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
	(sc as Control).size = Vector2(1280, 720)
	for _i in range(4):
		await get_tree().process_frame
	var c0 := _card("bottom", 0)
	_ok("分母: 下路三张小将卡都在、站位 = 前,前,后", c0 != null and _card("bottom", 2) != null and _roles() == "front,front,back", _roles())
	if c0 == null:
		_finish(); return
	## 热区 = 立绘下半截: 「前排/后排」签上方 20px、卡宽正中
	var pad_local := Vector2(sc.CARD_W / 2.0, sc.NAME_Y - 22.0)

	# ── M1 普通小将(下路 1 号)按在立绘下半截横拖 ──
	var lifted: bool = await _try_lift(_card("bottom", 1).get_global_rect().position + pad_local)
	_ok("M1 ★按在普通小将立绘下半截拖 = 拖得起来、站位不被切", lifted and _roles() == "front,front,back",
		"拖起=%s · 站位 %s" % [lifted, _roles()])
	await _reset()

	# ── M2 整张拖过去 = 互换(落点 = 目标卡正中, 正好是热区) ──
	await _drag(_card("bottom", 0).get_global_rect().position + Vector2(sc.CARD_W / 2.0, 40.0), _card("bottom", 2).get_global_rect().get_center())
	_ok("M2 ★精英 0 号拖到 2 号(后排)卡正中 = 两张互换", _roles() == "back,front,front", "站位 %s" % _roles())
	await _reset()
	await _drag(_card("bottom", 2).get_global_rect().position + pad_local, _card("bottom", 0).get_global_rect().get_center())
	_ok("M2b ★2 号(后排)按立绘下半截拖到 0 号 = 两张互换", _roles() == "back,front,front", "站位 %s" % _roles())
	await _reset()

	# ── M3 全卡覆盖: 起拖(三张卡) ──
	for ci in range(3):
		var hit := 0
		var tot := 0
		var miss: Array = []
		var inset: float = sc.CARD_BORDER
		var y := inset + STEP * 0.5
		while y < sc.CARD_H - inset:
			var x := inset + STEP * 0.5
			while x < sc.CARD_W - inset:
				var ok: bool = await _try_lift(_card("bottom", ci).get_global_rect().position + Vector2(x, y))
				tot += 1
				if ok:
					hit += 1
				elif miss.size() < 6:
					miss.append("(%d,%d)" % [int(x), int(y)])
				if _roles() != "front,front,back" or not ok:
					await _reset()
				x += STEP
			y += STEP
		_ok("M3 ★下路 %d 号卡内任一点按下横拖都拿得起来、站位不变" % ci, tot > 0 and hit == tot,
			"%d / %d 点 · 拿不起的例: %s" % [hit, tot, " ".join(miss)])
		await _reset()

	# ── M3b 全卡覆盖: 落点(2 号卡任一点都接得住 0 号) ──
	var dhit := 0
	var dtot := 0
	var dmiss: Array = []
	var dy: float = sc.CARD_BORDER + 12.0
	while dy < sc.CARD_H - sc.CARD_BORDER:
		var dx: float = sc.CARD_BORDER + 12.0
		while dx < sc.CARD_W - sc.CARD_BORDER:
			await _drag(_card("bottom", 0).get_global_rect().position + Vector2(sc.CARD_W / 2.0, 40.0),
				_card("bottom", 2).get_global_rect().position + Vector2(dx, dy))
			dtot += 1
			if _roles() == "back,front,front":
				dhit += 1
			elif dmiss.size() < 6:
				dmiss.append("(%d,%d)" % [int(dx), int(dy)])
			await _reset()
			dx += 24.0
		dy += 24.0
	_ok("M3b ★拖到 2 号卡内任一点都接得住(互换)", dtot > 0 and dhit == dtot,
		"%d / %d 点 · 接不住的例: %s" % [dhit, dtot, " ".join(dmiss)])

	# ── M4 只点一下热区 = 切站位, 只切一次 ──
	sc._dl_sel = {}
	await _click(_card("bottom", 1).get_global_rect().position + pad_local)
	_ok("M4 点一下 1 号立绘下半截 = 前排→后排(只切一次), 不顺带选中这张卡",
		_roles() == "front,back,back" and (sc._dl_sel as Dictionary).is_empty(), "站位 %s · 选中 %s" % [_roles(), sc._dl_sel])
	await _reset()
	await _click(_card("bottom", 2).get_global_rect().position + Vector2(sc.CARD_W / 2.0, sc.NAME_Y + 18.0))
	_ok("M4b 点 2 号「后排」签 = 后排→前排(只切一次)", _roles() == "front,front,front", "站位 %s" % _roles())
	await _reset()

	# ── M5 点卡片上半截不切站位 ──
	await _click(_card("bottom", 1).get_global_rect().position + Vector2(sc.CARD_W / 2.0, 40.0))
	_ok("M5 点 1 号立绘上半截不切站位", _roles() == "front,front,back", "站位 %s" % _roles())

	# ── M6 打了一周的号(统领 + 装备 + 小将): 六张卡逐点起拖 ──
	load("res://tests/_setup_appstore.gd").run()
	sc._dl_sel = {}
	sc._rebuild()
	for _i in range(3):
		await get_tree().process_frame
	for lk in ["top", "bottom"]:
		for ci in range((GameState.get_dual_lineup().get(lk, []) as Array).size()):
			if _card(lk, ci) == null:
				continue
			var hit := 0
			var tot := 0
			var miss: Array = []
			var y: float = sc.CARD_BORDER + 12.0
			while y < sc.CARD_H - sc.CARD_BORDER:
				var x: float = sc.CARD_BORDER + 12.0
				while x < sc.CARD_W - sc.CARD_BORDER:
					var ok: bool = await _try_lift(_card(lk, ci).get_global_rect().position + Vector2(x, y))
					tot += 1
					if ok:
						hit += 1
					elif miss.size() < 6:
						miss.append("(%d,%d)" % [int(x), int(y)])
					x += 24.0
				y += 24.0
			var u: Dictionary = (GameState.get_dual_lineup()[lk] as Array)[ci]
			_ok("M6 ★%s %d 号(%s %s)卡内任一点按下横拖都拿得起来" % [lk, ci, u.get("kind", ""), u.get("id", u.get("role", ""))],
				tot > 0 and hit == tot, "%d / %d 点 · 拿不起的例: %s" % [hit, tot, " ".join(miss)])

	_finish()


func _finish() -> void:
	print("\n合计 %d 项 · 失败 %d · 用了 %d 帧" % [_n, _fail, Engine.get_process_frames()])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)
