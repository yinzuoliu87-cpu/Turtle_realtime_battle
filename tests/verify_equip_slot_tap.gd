extends Node
## verify_equip_slot_tap.gd —— 背包里已选中一件装备时, 点单位卡(含卡上的装备小格)= 装上去(60 人实操台账「装备点了没反应」)
## 原现象: 点在装备小格上走 `_select_unit`, 它把背包选中清掉、不装、不提示 —— 388 次里 8 次, 都发生在装满的卡上。
## 走真入口: 真 Inventory 场景, 给装备小格喂一次真左键(它挂的 gui_input), 量背包与龟身前后的件数。
var _n := 0
var _fail := 0
func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if c: print("  [PASS] ", t, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", t, "  ", d)
## 点一下 = 按下 + 松开(2026-10-22 起单位卡「松手才算点」, 只发按下什么都不会发生)。
func _click(c: Control) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		c.gui_input.emit(ev)
func _ready() -> void:
	await get_tree().process_frame
	print("=== 已选中装备时点装备小格 = 装上去 ===")
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	gs.season_leaders = ["basic", "fortune", "ninja"]
	gs.season_level = 10
	gs.persistent_equipped = {"basic": [{"id": "p2eq_004", "star": 1}], "fortune": [], "ninja": []}
	gs.persistent_bench = [{"id": "p2eq_021", "star": 1}]
	gs.dual_lineup = {}
	var inv = load("res://scenes/Inventory.tscn").instantiate()
	add_child(inv)
	for _i in range(20): await get_tree().process_frame
	## ★2026-10-21 手机版: 装备小格(40px = 22pt)不再是单独的靶子 —— 点它 = 点这张单位卡(`_dl_click`)。
	##   判据: ① 卡上的装备小格不吃点击(IGNORE, 事件落到卡上) ② 卡挂着点击 ③ 走卡的那条路: 已选中装备 ⇒ 装上去;
	##   没选中装备 ⇒ 选中这只单位。(原现象「点装备格清掉选中、不装」的根因是小格走了另一条路, 现在只有一条路。)
	var dl: Dictionary = gs.get_dual_lineup()
	var lane := ""; var idx := -1
	for ln in ["top", "bottom"]:
		var arr: Array = dl.get(ln, [])
		for i in range(arr.size()):
			if arr[i] is Dictionary and str(arr[i].get("id", "")) == "basic":
				lane = ln; idx = i
	_ok("★分母: basic 在布阵里", idx >= 0, "%s/%d" % [lane, idx])
	## 找 basic 那张卡: 产品给的节点名 UnitCard_<路>_<序号>, 挂着点击, 子孙里写着它的名字
	##   (2026-10-22 竖卡: 名字在 NameBanner 里, 不再是卡的直接子节点)。
	var pet_name: String = str(DataRegistry.pet_by_id.get("basic", {}).get("name", "basic"))
	var card: Control = inv.find_child("UnitCard_%s_%d" % [lane, idx], true, false) as Control
	var shows_name := false
	if card != null:
		var st: Array = [card]
		while not st.is_empty():
			var n = st.pop_back(); st.append_array(n.get_children())
			if n is Label and str((n as Label).text) == pet_name:
				shows_name = true
	_ok("★分母: 找到 basic 那张单位卡(挂着点击, 写着「%s」)" % pet_name,
		card != null and card.gui_input.get_connections().size() > 0 and shows_name)
	## 装备格 = 卡的直接子 Panel、边长 EQ_CELL(羁绊赠送徽章小一圈, 不算)
	var cells: Array = []
	if card != null:
		for ch in card.get_children():
			if ch is Panel and absf((ch as Panel).size.x - float(inv.EQ_CELL)) < 0.5:
				cells.append(ch)
	_ok("★分母: 卡上有 3 个装备小格", cells.size() >= 3, "%d 个" % cells.size())
	var bad: Array = []
	for c in cells:
		if (c as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE or (c as Control).gui_input.get_connections().size() > 0:
			bad.append(str(c.name))
	_ok("★★装备小格不单独吃点击(点它 = 点卡)", cells.size() >= 3 and bad.is_empty(), str(bad))
	inv._sel_bench = 0
	var bench0: int = gs.persistent_bench.size()
	var on0: int = (gs.persistent_equipped.get("basic", []) as Array).size()
	if card != null:
		_click(card)
	await get_tree().process_frame
	_ok("★★已选中装备时点卡 ⇒ 背包少了一件", gs.persistent_bench.size() == bench0 - 1, "%d→%d" % [bench0, gs.persistent_bench.size()])
	_ok("★★已选中装备时点卡 ⇒ basic 身上多了一件", (gs.persistent_equipped.get("basic", []) as Array).size() == on0 + 1,
		"%d→%d" % [on0, (gs.persistent_equipped.get("basic", []) as Array).size()])
	## 没选中装备时, 点卡 = 选中这只
	inv._sel_bench = -1
	inv._dl_sel = {}
	inv._dl_click(lane, idx)
	_ok("没选中装备时点卡 ⇒ 选中这只单位", str(inv._dl_sel.get("lane", "")) == lane and int(inv._dl_sel.get("idx", -1)) == idx, str(inv._dl_sel))
	inv.queue_free()
	print("")
	if _fail == 0 and _n >= 5:
		print("ALL PASS — 已选中装备时点装备格=装上去 (%d 条)" % _n); get_tree().quit(0)
	else:
		print("FAILED %d / %d" % [_fail, _n]); get_tree().quit(1)
