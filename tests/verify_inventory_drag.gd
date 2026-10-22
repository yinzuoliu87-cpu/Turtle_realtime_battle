extends Node
## verify_inventory_drag.gd — 背包卡片式拖动真的能用(2026-10-22 · 方案书 20261022-背包重做.md)
##
## 用户 10-22「做，最好要支持卡片式拖动的」「把龟做成卡片」。走真入口: 往视口里推鼠标按下 / 移动 / 松开,
## 由引擎自己的拖放(不直接调落下函数)。量的是存档里真的变了没有。
##   D1 背包一件 → 拖到有空位的统领卡 = 装上(背包 −1、它身上 +1)
##   D2 那一件 → 从卡上拖回背包区 = 卸下
##   D3 一张卡 → 拖到另一路的一张卡 = 两张互换
##   D4 卡上一件 → 拖到另一只单位 = 换人(全队件数不变)

const INV := preload("res://scenes/Inventory.tscn")

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


func _drag(from: Vector2, to: Vector2) -> void:
	var vp := get_viewport()
	var dn := InputEventMouseButton.new()
	dn.button_index = MOUSE_BUTTON_LEFT; dn.pressed = true; dn.position = from; dn.global_position = from
	vp.push_input(dn, true)
	await get_tree().process_frame
	for k in range(1, 15):
		var mm := InputEventMouseMotion.new()
		var p := from.lerp(to, float(k) / 14.0)
		mm.position = p; mm.global_position = p
		mm.relative = (to - from) / 14.0
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		vp.push_input(mm, true)
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false; up.position = to; up.global_position = to
	vp.push_input(up, true)
	for _i in range(3):
		await get_tree().process_frame


func _card(lane: String, i: int) -> Control:
	return sc.find_child("UnitCard_%s_%d" % [lane, i], true, false) as Control


func _worn_center(card: Control, cell: int) -> Vector2:
	var x0: float = sc.CARD_W / 2.0 - (3.0 * 44.0 + 2.0 * 5.0) / 2.0
	return card.get_global_rect().position + Vector2(x0 + float(cell) * 49.0 + 22.0, sc.SLOT_ROW_Y + 22.0)


func _unit(lane: String, i: int) -> Dictionary:
	var arr: Array = GameState.get_dual_lineup().get(lane, [])
	return arr[i] if i < arr.size() and arr[i] is Dictionary else {}


func _ready() -> void:
	await get_tree().process_frame
	GameState.test_mode = true
	load("res://tests/_setup_appstore.gd").run()
	GameState.season_level = 10            # 全队装备上限放宽, 量的是拖拽不是容量
	print("=== 背包卡片式拖动 ===")
	sc = INV.instantiate()
	add_child(sc)
	(sc as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
	(sc as Control).size = Vector2(1280, 720)
	for _i in range(4):
		await get_tree().process_frame
	## 找一只身上不满 3 件的统领
	var lane := ""; var li := -1
	for lk in ["top", "bottom"]:
		var arr: Array = GameState.get_dual_lineup().get(lk, [])
		for i in range(arr.size()):
			var u: Dictionary = arr[i]
			if str(u.get("kind", "")) == "leader" and str(u.get("id", "")) != "" and GameState._cap_count(sc._unit_equips(u)) < 3 and li < 0:
				lane = lk; li = i
	_ok("分母: 有一只没装满的统领、背包里有东西", li >= 0 and GameState.persistent_bench.size() > 0,
		"%s %d · 背包 %d" % [lane, li, GameState.persistent_bench.size()])
	if li < 0:
		_finish(); return
	var pid := str(_unit(lane, li).get("id", ""))

	# ── D1 背包 → 卡 ──
	var b0: int = GameState.persistent_bench.size()
	var e0: int = (GameState.persistent_equipped.get(pid, []) as Array).size()
	var src: Control = sc._tut_first_item
	var dst: Control = _card(lane, li)
	_ok("分母: 背包第一格与目标卡都在", src != null and dst != null)
	if src == null or dst == null:
		_finish(); return
	await _drag(src.get_global_rect().get_center(), dst.get_global_rect().get_center())
	var e1: int = (GameState.persistent_equipped.get(pid, []) as Array).size()
	_ok("D1 ★背包一件拖到统领卡 = 装上", e1 == e0 + 1 and GameState.persistent_bench.size() <= b0 - 1,
		"身上 %d→%d · 背包 %d→%d" % [e0, e1, b0, GameState.persistent_bench.size()])

	# ── D2 卡上那一件 → 背包区 ──
	var b1: int = GameState.persistent_bench.size()
	dst = _card(lane, li)
	await _drag(_worn_center(dst, e1 - 1), sc._bench_area.get_global_rect().get_center())
	var e2: int = (GameState.persistent_equipped.get(pid, []) as Array).size()
	_ok("D2 ★卡上一件拖回背包 = 卸下", e2 == e1 - 1 and GameState.persistent_bench.size() >= b1,
		"身上 %d→%d · 背包 %d→%d" % [e1, e2, b1, GameState.persistent_bench.size()])

	# ── D3 卡 ↔ 卡 ──
	var a_id := str(_unit("top", 0).get("id", "")) + "/" + str(_unit("top", 0).get("kind", ""))
	var b_id := str(_unit("bottom", 0).get("id", "")) + "/" + str(_unit("bottom", 0).get("kind", ""))
	var ca: Control = _card("top", 0)
	var cb: Control = _card("bottom", 0)
	## 按在立绘上(不是装备格)拖
	await _drag(ca.get_global_rect().position + Vector2(sc.CARD_W / 2.0, 60.0), cb.get_global_rect().get_center())
	var a2 := str(_unit("top", 0).get("id", "")) + "/" + str(_unit("top", 0).get("kind", ""))
	var b2 := str(_unit("bottom", 0).get("id", "")) + "/" + str(_unit("bottom", 0).get("kind", ""))
	_ok("D3 ★卡拖到另一路的卡 = 互换", a2 == b_id and b2 == a_id, "上0 %s→%s · 下0 %s→%s" % [a_id, a2, b_id, b2])

	# ── D4 卡上一件 → 另一只单位 ──
	var team0: int = int(GameState.team_equipped_count())
	var from_l := ""; var from_i := -1; var to_l := ""; var to_i := -1
	for lk in ["top", "bottom"]:
		var arr: Array = GameState.get_dual_lineup().get(lk, [])
		for i in range(arr.size()):
			var u: Dictionary = arr[i]
			var n: int = GameState._cap_count(sc._unit_equips(u))
			if n > 0 and from_i < 0:
				from_l = lk; from_i = i
			elif n < 3 and to_i < 0 and not (str(u.get("kind", "")) == "leader" and str(u.get("id", "")) == ""):
				to_l = lk; to_i = i
	_ok("分母: 有一只有装备的、一只有空位的", from_i >= 0 and to_i >= 0)
	if from_i >= 0 and to_i >= 0:
		var nf0: int = sc._unit_equips(_unit(from_l, from_i)).size()
		var nt0: int = sc._unit_equips(_unit(to_l, to_i)).size()
		await _drag(_worn_center(_card(from_l, from_i), 0), _card(to_l, to_i).get_global_rect().get_center())
		var nf1: int = sc._unit_equips(_unit(from_l, from_i)).size()
		var nt1: int = sc._unit_equips(_unit(to_l, to_i)).size()
		_ok("D4 ★卡上一件拖到另一只 = 换人(全队件数不变)", nf1 == nf0 - 1 and nt1 == nt0 + 1 and int(GameState.team_equipped_count()) == team0,
			"%s%d %d→%d · %s%d %d→%d · 全队 %d→%d" % [from_l, from_i, nf0, nf1, to_l, to_i, nt0, nt1, team0, GameState.team_equipped_count()])
	_finish()


func _finish() -> void:
	print("  (共 %d 条断言)" % _n)
	if _fail == 0 and _n >= 6:
		print("ALL PASS")
		get_tree().quit(0)
	else:
		print("FAILED: %d" % _fail)
		get_tree().quit(1)
