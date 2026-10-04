extends Node
## verify_equip_full_hint.gd — 台账 S18「装备满 18/18 时选中背包装备、再点已占的槽: 什么都不发生」
##
## ★走真入口: 背包选中一件(`_on_bench_click`, 那一步不是被测对象), 然后对单位卡上
##   **已占的装备小格**派一次真的鼠标按下(`Viewport.push_input`, 走引擎自己的命中与冒泡),
##   量**屏幕上真的出现的那行提示**(ToastLayer 里的 Toast), 不调 `_equip_to` 内部函数。
## ★两种满:
##   A 全队 18/18 且这只 3/3  ⇒ 先撞单只上限(equip_ops 的判序)
##   B 全队 16/16(等级 9)但这只没满(单只 1/3) ⇒ 撞全队上限
## ★分母: 点下去之前确实处在「选中了背包装备」+「全队已满」; 点到的确实是一个已占格。
## ★2026-10-04 复现结果: 当前 HEAD 上 18/18 个已占格点下去**都有** toast(A11 那次
##   「提示被 _rebuild 当帧删掉」已在 09-29 修了)。剩下的毛病是**提示只活 2 秒且不说下一步** ——
##   所以判据量的是「每一格都有提示 + 提示里给出下一步(卸一件)」, 这一份当回归守卫。
##
## 跑法: <godot> --headless --path . res://tests/verify_equip_full_hint.tscn --quit-after 1500

const InvScene := preload("res://scripts/scenes/InventoryScene.gd")

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond:
		_fail += 1
	print("  %s %s%s" % ["[PASS]" if cond else "[FAIL]", name, ("   " + detail) if detail != "" else ""])


func _walk(n: Node, out: Array) -> void:
	if n is Control:
		out.append(n)
	for c in n.get_children():
		_walk(c, out)


## 单位卡上的装备小格(40×40 Panel), 只要**已占**的(里面有图标子节点)。
func _filled_minis(sc: Node) -> Array:
	var all: Array = []
	_walk(sc, all)
	var out: Array = []
	for c in all:
		var ctl: Control = c
		if ctl is Panel and ctl.is_visible_in_tree() and absf(ctl.size.x - 40.0) < 0.5 \
				and absf(ctl.size.y - 40.0) < 0.5 and ctl.get_child_count() > 0:
			out.append(ctl)
	return out


func _toast_text(sc: Node) -> String:
	for c in sc.get_children():
		if c is CanvasLayer and str(c.name) == "ToastLayer":
			for t in c.get_children():
				if t is Label and (t as Label).visible and not t.is_queued_for_deletion():
					return str((t as Label).text)
	return ""


func _click_at(p: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = p
	down.global_position = p
	get_viewport().push_input(down)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = p
	up.global_position = p
	get_viewport().push_input(up)
	await get_tree().process_frame
	await get_tree().process_frame


func _seed(leader_n: int, level: int) -> void:
	var e3 := func() -> Array:
		return [{"id": "p2eq_001", "star": 1}, {"id": "p2eq_002", "star": 1}, {"id": "p2eq_003", "star": 1}]
	GameState.season_level = level         # 全队上限 = (level-1)*2
	GameState.season_leaders = ["basic", "stone", "bamboo"]
	var first: Array = []
	for k in range(leader_n):
		first.append({"id": "p2eq_00%d" % (4 + k), "star": 1})
	GameState.persistent_equipped = {"basic": first, "stone": e3.call(), "bamboo": e3.call()}
	GameState.dual_lineup = {}
	var dl: Dictionary = GameState.get_dual_lineup()
	for lane in ["top", "bottom"]:
		for u in (dl.get(lane, []) as Array):
			if u is Dictionary and str(u.get("kind", "")) == "minion":
				u["equips"] = e3.call()
	GameState.dual_lineup = dl
	GameState.persistent_bench = [{"id": "p2eq_010", "star": 1}]


func _case(tag: String, leader_n: int, level: int, want_sub: String, first_sub: String) -> void:
	print("")
	print("── %s ──" % tag)
	_seed(leader_n, level)
	var sc = InvScene.new()
	get_tree().root.add_child(sc)
	for _i in range(12):
		await get_tree().process_frame
	_ok("%s ★分母: 全队已满 %d/%d" % [tag, GameState.team_equipped_count(), GameState.team_equip_cap()],
		not GameState.team_has_equip_room())
	sc._on_bench_click(0)
	for _i in range(4):
		await get_tree().process_frame
	_ok("%s ★分母: 背包里那件已选中" % tag, int(sc._sel_bench) == 0, "sel=%d" % int(sc._sel_bench))
	## basic 是 top 路第 0 只(slot 0) —— 取它那张卡上的已占格。
	##   按位置挑: 所有已占格里最靠左上的那一个, 就是 top 路第一张卡。
	var minis: Array = _filled_minis(sc)
	_ok("%s ★分母: 屏上有已占的装备小格" % tag, minis.size() > 0, "%d 个" % minis.size())
	if minis.is_empty():
		sc.queue_free()
		await get_tree().process_frame
		return
	## ★每一个已占格都真点一遍(统领卡 + 小将卡都在内) —— 只点一格的话,
	##   「某类卡上的格子吞掉点击」这种形状照样漏网。
	var total: int = minis.size()
	var hit := 0
	var bad: Array = []
	var first_txt := ""
	var before_eq: int = GameState.team_equipped_count()
	for i in range(total):
		if int(sc._sel_bench) != 0:
			sc._on_bench_click(0)
			for _k in range(3):
				await get_tree().process_frame
		var cur: Array = _filled_minis(sc)
		cur.sort_custom(func(x, y) -> bool:
			var rx: Rect2 = (x as Control).get_global_rect()
			var ry: Rect2 = (y as Control).get_global_rect()
			return rx.position.y < ry.position.y - 0.5 or (absf(rx.position.y - ry.position.y) < 0.5 and rx.position.x < ry.position.x))
		if i >= cur.size():
			bad.append("#%d 格子没了(%d)" % [i, cur.size()])
			continue
		var c_rect: Rect2 = (cur[i] as Control).get_global_rect()
		for t in sc.get_children():
			if t is CanvasLayer and str(t.name) == "ToastLayer":
				for tl in t.get_children():
					tl.free()
		await _click_at(c_rect.get_center())
		var txt := _toast_text(sc)
		if i == 0:
			first_txt = txt
		if txt.find(want_sub) >= 0:
			hit += 1
		else:
			bad.append("#%d @(%.0f,%.0f) 「%s」" % [i, c_rect.position.x, c_rect.position.y, txt])
	print("  %s 点了 %d 个已占格, 有提示 %d 个; 没提示: %s" % [tag, total, hit, str(bad.slice(0, 6))])
	_ok("%s ★★每个已占的槽点下去都出现提示(不是什么都不发生)" % tag, hit == total and total > 0,
		"%d/%d" % [hit, total])
	_ok("%s 左上第一格(basic 那张卡)说的是那条原因(含「%s」)" % [tag, first_sub],
		first_txt.find(first_sub) >= 0, first_txt)
	_ok("%s 没有偷偷装上(件数不变)" % tag, GameState.team_equipped_count() == before_eq,
		"%d → %d" % [before_eq, GameState.team_equipped_count()])
	sc.queue_free()
	for _i in range(3):
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	print("=== 满装备时点已占槽的提示(台账 S18) ===")
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.size = Vector2i(1280, 720)
	for _q in range(4):
		await get_tree().process_frame
	GameState.test_mode = true          # ★绝不许写进玩家真存档
	await _case("A 全队18/18·这只3/3", 3, 10, "卸", "已装满 3 件")
	await _case("B 全队16/16·这只1/3", 1, 9, "卸", "全队装备已满")
	print("")
	print("断言 %d 条" % _n)
	if _fail == 0 and _n >= 12:
		print("ALL PASS — 满装备点已占槽有提示")
		get_tree().quit(0)
	else:
		print("FAIL x%d (断言 %d 条)" % [_fail, _n])
		get_tree().quit(1)
