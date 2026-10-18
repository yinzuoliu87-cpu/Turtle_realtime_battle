extends Node
## verify_prep_screen_one_step_equip.gd — 商店里「买下 → 点龟」两下装上(2026-10-18)
##
## 玩家反馈 10-17「游戏的操作风格与道具装备的流程存在提升空间」;
## 实玩: 原来买一件再装上要 6 下、跨两个界面(方案书 docs/plans/20261018-商店背包合一.md「实玩记录」)。
##
## ★走真入口: 真的实例化 Shop.tscn; 购买走 `_on_buy`(购买按钮接的就是它),
##   点龟走单位行自己的 gui_input 处理器(发一个真的鼠标按下事件), 不直接调装备函数。
##
## 断言:
##   E0  分母: 商店开店、右侧阵容面板在、6 个单位行在
##   E1  ★买下一件(没合成) → 还在商店, 这件自动成为「待装」, 提示写着它的名字
##   E2  ★点一只龟 → 这件装到这只龟身上、背包少一件、全队已装 +1 —— 全程没换场景
##   E3  选中一只龟 → 操作条有「卸下」, 按下去 → 回到背包
##   E4  ★买下即合成(已有 2 件同款) → 不进入「待装」(没有一件新东西可装)
##   E5  ★全队装满时买 → 不进入「待装」, 提示写着全队已满
##   E6  还没选龟的统领位接不了装备(未选龟)

const SHOP := preload("res://scenes/Shop.tscn")

var _fail := 0
var _n := 0
const MIN_ASSERTS := 17
const ITEM := "p2eq_001"

var gs


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _enter() -> Node:
	var sc = SHOP.instantiate()
	add_child(sc)
	if sc is Control:
		(sc as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(sc as Control).size = Vector2(1280, 720)
	await get_tree().process_frame
	return sc


func _leave(sc: Node) -> void:
	remove_child(sc)
	sc.free()


func _find(n: Node, nm: String) -> Node:
	if str(n.name) == nm:
		return n
	for c in n.get_children():
		var r = _find(c, nm)
		if r != null:
			return r
	return null


func _count_prefix(n: Node, pre: String) -> int:
	var k := 1 if str(n.name).begins_with(pre) else 0
	for c in n.get_children():
		k += _count_prefix(c, pre)
	return k


## 真点一下: 往这个控件的 gui_input 送一个鼠标左键按下(产品里接的就是这个信号)。
func _tap(ct: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = ct.size * 0.5
	ct.gui_input.emit(ev)
	await get_tree().process_frame


func _hint(sc) -> String:
	var h = _find(sc, "LineupHint")
	return str((h as Label).text) if h != null else ""


func _shelf_with(id: String) -> void:
	var a: Array = []
	for i in range(10):
		a.append({"id": id})
	gs.meta_shop_offer = a
	gs.meta_shop_battles = int(gs.season_total_battles)


func _reset(level: int) -> void:
	gs.meta_deepsea_coins = 999
	gs.season_level = level
	gs.season_total_battles = 3
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.dual_lineup = {}
	gs.get_dual_lineup()
	gs.persistent_bench = []
	gs.persistent_equipped = {}
	gs.meta_shop_locked = false
	_shelf_with(ITEM)


func _ready() -> void:
	await get_tree().process_frame
	gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 GameState"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 商店里买下 → 点龟 两下装上 ===")

	# ── E0 分母 ──
	_reset(5)
	var sc = await _enter()
	_ok("E0 分母: 商店开店(货架 10 格)", (sc._offer as Array).size() == 10, "格数 %d" % (sc._offer as Array).size())
	_ok("E0 分母: 右侧阵容面板在", _find(sc, "LineupPanel") != null)
	_ok("E0 分母: 6 个单位行", _count_prefix(sc, "LineupRow_") == 6, "实测 %d" % _count_prefix(sc, "LineupRow_"))
	var top0: Dictionary = gs.get_dual_lineup()["top"][0]
	var pid := str(top0.get("id", ""))
	_ok("E0 分母: 上战场第一格是统领且有龟", str(top0.get("kind", "")) == "leader" and pid != "", str(top0))

	# ── E1 买下 ──
	var used0: int = int(gs.team_equipped_count())
	sc._on_buy(0)
	await get_tree().process_frame
	_ok("E1 买下后还在商店(没换场景)", is_instance_valid(sc) and sc.is_inside_tree())
	var bi: int = int(sc._sel_bench)
	_ok("E1 ★买下的这件自动成为「待装」", bi >= 0 and bi < gs.persistent_bench.size()
		and str(gs.persistent_bench[bi].get("id", "")) == ITEM, "sel_bench=%d bench=%s" % [bi, str(gs.persistent_bench)])
	var nm := str(DataRegistry.phase2_equipment_by_id.get(ITEM, {}).get("name", "?"))
	_ok("E1 提示写着「点一只龟装上「%s」」" % nm, _hint(sc).find(nm) >= 0 and _hint(sc).find("点一只龟") >= 0, _hint(sc))

	# ── E2 点龟 ──
	var row = _find(sc, "LineupRow_top_0")
	_ok("E2 分母: 找得到上战场第一行", row != null)
	if row != null:
		await _tap(row)
	var eqs: Array = gs.persistent_equipped.get(pid, [])
	_ok("E2 ★点一下这只龟 → 装到它身上", eqs.size() == 1 and str(eqs[0].get("id", "")) == ITEM, str(eqs))
	_ok("E2 背包少了这一件", gs.persistent_bench.is_empty(), str(gs.persistent_bench))
	_ok("E2 全队已装 +1", int(gs.team_equipped_count()) == used0 + 1, "%d → %d" % [used0, int(gs.team_equipped_count())])
	_ok("E2 装完退出「待装」", int(sc._sel_bench) == -1)

	# ── E3 卸下 ──
	row = _find(sc, "LineupRow_top_0")
	if row != null:
		await _tap(row)
	var act = _find(sc, "LineupAct0")
	_ok("E3 选中这只龟 → 操作条第一颗是「卸下」", act != null and str((act as Button).text).begins_with("卸下"),
		str((act as Button).text) if act != null else "无")
	if act != null:
		(act as Button).pressed.emit()
		await get_tree().process_frame
	_ok("E3 卸下 → 回到背包", (gs.persistent_equipped.get(pid, []) as Array).is_empty() and gs.persistent_bench.size() == 1,
		"身上 %s / 背包 %s" % [str(gs.persistent_equipped.get(pid, [])), str(gs.persistent_bench)])
	_leave(sc)

	# ── E4 买下即合成 ──
	_reset(5)
	gs.persistent_equipped = {"basic": [{"id": ITEM, "star": 1}, {"id": ITEM, "star": 1}]}
	sc = await _enter()
	sc._on_buy(0)
	await get_tree().process_frame
	var merged: bool = false
	for it in gs.persistent_equipped.get("basic", []):
		if str(it.get("id", "")) == ITEM and int(it.get("star", 1)) == 2:
			merged = true
	_ok("E4 分母: 真的合成了 ★2", merged, str(gs.persistent_equipped))
	_ok("E4 ★合成掉的不进入「待装」", int(sc._sel_bench) == -1, "sel_bench=%d" % int(sc._sel_bench))
	_leave(sc)

	# ── E5 全队已满 ──
	_reset(2)
	var cap: int = int(gs.team_equip_cap())
	var filler: Array = []
	for i in range(cap):
		filler.append({"id": "p2eq_%03d" % (10 + i), "star": 1})
	gs.persistent_equipped = {"basic": filler}
	sc = await _enter()
	_ok("E5 分母: 全队已满(%d/%d)" % [int(gs.team_equipped_count()), cap], not gs.team_has_equip_room() and cap > 0)
	sc._on_buy(0)
	await get_tree().process_frame
	_ok("E5 ★全队已满时买 → 不进入「待装」", int(sc._sel_bench) == -1)
	_ok("E5 屏上写着全队已满", str(sc._toast_node.text if sc._toast_node != null else "").find("全队") >= 0,
		str(sc._toast_node.text) if sc._toast_node != null else "无提示")
	_leave(sc)

	# ── E6 未选龟 ──
	_reset(5)
	gs.season_leaders = []
	gs.dual_lineup = {}
	gs.persistent_bench = [{"id": ITEM, "star": 1}]
	sc = await _enter()
	sc._sel_bench = 0
	sc._rebuild()
	await get_tree().process_frame
	row = _find(sc, "LineupRow_top_0")
	if row != null:
		await _tap(row)
	_ok("E6 未选龟的统领位接不了装备(背包仍是 1 件)", gs.persistent_bench.size() == 1, str(gs.persistent_bench))
	_leave(sc)

	print("")
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少该有 %d)" % [_n, MIN_ASSERTS])
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 商店里两下装上" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
