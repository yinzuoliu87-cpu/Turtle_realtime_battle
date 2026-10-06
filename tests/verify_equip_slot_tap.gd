extends Node
## verify_equip_slot_tap.gd —— 背包里已选中一件装备时, 点单位卡上的【装备小格】= 装上去(60 人实操台账「装备点了没反应」)
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
func _click(c: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
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
	## 找 basic 那张卡上的装备小格(挂了 gui_input 的 PanelContainer/Control, 它的回调走 _select_unit)
	var cells: Array = []
	var st: Array = [inv]
	while not st.is_empty():
		var n = st.pop_back(); st.append_array(n.get_children())
		if n is Control and not (n is BaseButton):
			for cn in (n as Control).gui_input.get_connections():
				var src: String = str((cn["callable"] as Callable).get_method())
				if src.find("lambda") >= 0 or src == "":
					cells.append(n)
	_ok("★分母: 布阵区里有挂了点击的装备小格", cells.size() >= 3, "%d 个" % cells.size())
	inv._sel_bench = 0
	var bench0: int = gs.persistent_bench.size()
	var on0: int = (gs.persistent_equipped.get("basic", []) as Array).size()
	## 直接走产品那条路: 点装备格 → _select_unit(lane, idx)。lane/idx 用 basic 在布阵里的位置。
	var dl: Dictionary = gs.get_dual_lineup()
	var lane := ""; var idx := -1
	for ln in ["top", "bottom"]:
		var arr: Array = dl.get(ln, [])
		for i in range(arr.size()):
			if arr[i] is Dictionary and str(arr[i].get("id", "")) == "basic":
				lane = ln; idx = i
	_ok("★分母: basic 在布阵里", idx >= 0, "%s/%d" % [lane, idx])
	inv._select_unit(lane, idx)
	await get_tree().process_frame
	_ok("★★点装备格 ⇒ 背包少了一件", gs.persistent_bench.size() == bench0 - 1, "%d→%d" % [bench0, gs.persistent_bench.size()])
	_ok("★★点装备格 ⇒ basic 身上多了一件", (gs.persistent_equipped.get("basic", []) as Array).size() == on0 + 1,
		"%d→%d" % [on0, (gs.persistent_equipped.get("basic", []) as Array).size()])
	## 没选中装备时, 点装备格仍是「选中这只」(原行为不变)
	inv._sel_bench = -1
	inv._dl_sel = {}
	inv._select_unit(lane, idx)
	_ok("没选中装备时点装备格 ⇒ 仍是选中这只单位(原行为)", str(inv._dl_sel.get("lane", "")) == lane and int(inv._dl_sel.get("idx", -1)) == idx, str(inv._dl_sel))
	inv.queue_free()
	print("")
	if _fail == 0 and _n >= 5:
		print("ALL PASS — 已选中装备时点装备格=装上去 (%d 条)" % _n); get_tree().quit(0)
	else:
		print("FAILED %d / %d" % [_fail, _n]); get_tree().quit(1)
