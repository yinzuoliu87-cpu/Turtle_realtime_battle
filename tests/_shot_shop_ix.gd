extends Node
## 商店交互截图台(不是门禁, 2026-10-22 交互排查): 真进 Shop.tscn, 派真鼠标点击走一遍, 在关键几拍存视口截图。
## 跑法(窗口只开右屏):
##   SHOT_DIR=<目录> TURTLE_SUPABASE=" " TURTLE_BACKEND=" " APPDATA=<单独目录> \
##   WINDOW=1 bash godot-quiet.sh --position 1960,60 --resolution 1560x720 res://tests/_shot_shop_ix.tscn
## 存:  refresh.png  选一件 → 卡里「购买」→「刷新」之后那一拍(用户报的「自动选中」)
##      axe.png      小木斧攒满待选最终造物, 进店自动弹的那张
##      tall.png     说明最长的 084 选中后
##      odds.png     选着货再点等级(出货概率)
##      poor.png     币 1 时点「刷新」
##      idle.png     空闲(顶栏左上页签)

const AE := preload("res://scripts/gamedata/axe_evolution.gd")
var dir := ""
var is_driver := false


func _ready() -> void:
	## 本节点是启动场景, 一换场景就被释放 ⇒ 另起一份挂在 root 上当驱动(换场景不丢)。
	if not is_driver:
		var d = get_script().new()
		d.is_driver = true
		d.name = "ShotShopIxDriver"
		get_tree().root.add_child.call_deferred(d)
		return
	dir = OS.get_environment("SHOT_DIR")
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	_run.call_deferred()


func _seed(coins: int, shelf: Array) -> void:
	load("res://tests/_setup_appstore.gd").run()
	GameState.meta_deepsea_coins = coins
	GameState.season_level = 5
	GameState.season_xp = 0
	GameState.season_total_battles = maxi(1, int(GameState.season_total_battles))
	GameState.meta_shop_locked = false
	GameState.axe_exp_bar = 0
	GameState.axe_exp_total = 0
	GameState.axe_stage = 0
	GameState.axe_final = ""
	if shelf.is_empty():
		GameState.meta_shop_offer = []
		GameState.meta_shop_battles = -1
	else:
		var out: Array = []
		for i in range(10):
			out.append({"id": str(shelf[i % shelf.size()])})
		GameState.meta_shop_offer = out
		GameState.meta_shop_battles = int(GameState.season_total_battles)


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _open() -> Node:
	get_tree().change_scene_to_file("res://scenes/Shop.tscn")
	await _frames(90)
	return get_tree().current_scene


func _ev(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	get_viewport().push_input(e)


func _click(c) -> void:
	if not (c is Control):
		print("[SHOT] 点不到: ", c)
		return
	var p: Vector2 = (c as Control).get_global_rect().get_center()
	_ev(p, true)
	await get_tree().process_frame
	_ev(p, false)
	await _frames(20)


func _live(root: Node, nm: String) -> Control:
	if root == null:
		return null
	for c in root.find_children(nm, "", true, false):
		if c is Control and (c as Control).is_visible_in_tree() and not c.is_queued_for_deletion():
			var ok := true
			var q: Node = c
			while q != null:
				if q.is_queued_for_deletion():
					ok = false
				q = q.get_parent()
			if ok:
				return c
	return null


func _save(nm: String) -> void:
	await _frames(30)
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [dir, nm]
	get_viewport().get_texture().get_image().save_png(path)
	print("[SHOT] ", path)


func _run() -> void:
	# ① 用户报的那条: 选一件 → 购买 → 刷新
	_seed(428, [])
	var sc := await _open()
	await _click(_live(sc, "ShelfItem0"))
	var card := _live(sc, "InspectCard")
	await _click(_live(card, "BuyBtn") if card != null else null)
	await _frames(30)        # 让「购买成功」那条提示自己收掉之前先刷新(玩家就是这么快)
	await _click(_live(sc, "ShopRefreshBtn"))
	await _save("refresh")
	# ② 小木斧待选最终造物
	_seed(428, ["p2eq_001", "p2eq_002", "p2eq_003", "p2eq_004", "p2eq_005", "p2eq_006", "p2eq_007", "p2eq_008", "p2eq_009", "p2eq_010"])
	GameState.persistent_bench.append({"id": "p2eq_096", "star": 1})
	GameState.axe_stage = AE.STAGES.size() - 1
	GameState.axe_exp_bar = AE.FINAL_NEED
	GameState.axe_exp_total = 900
	sc = await _open()
	await _save("axe")
	# ③ 说明最长的 084
	_seed(428, ["p2eq_084", "p2eq_001", "p2eq_002", "p2eq_003", "p2eq_004", "p2eq_005", "p2eq_006", "p2eq_007", "p2eq_008", "p2eq_009"])
	sc = await _open()
	await _click(_live(sc, "ShelfItem0"))
	await _save("tall")
	# ④ 选着货点等级
	_seed(428, [])
	sc = await _open()
	await _click(_live(sc, "ShelfItem7"))
	await _click(_live(sc, "LevelTap"))
	await _save("odds")
	# ⑤ 币 1 点刷新
	_seed(1, [])
	sc = await _open()
	await _click(_live(sc, "ShopRefreshBtn"))
	await _save("poor")
	# ⑥ 空闲(顶栏)
	_seed(428, [])
	sc = await _open()
	await _save("idle")
	get_tree().quit()
