extends Node
## 小木斧进化演出截图台(不是门禁): 真进 Shop.tscn 真点「购买」触发演出, 停掉 tween 按时间点 `_apply(t)` 逐拍存图;
## 再放一遍真时长, 逐帧记画面上的形态 / 剪影, 量它真的在动。
## 跑法(窗口只开右屏):
##   SHOT_DIR=<目录> TURTLE_SUPABASE=" " TURTLE_BACKEND=" " APPDATA=<单独目录> \
##   WINDOW=1 bash godot-quiet.sh --position 1960,60 --resolution 1560x720 res://tests/_shot_axe_evo.tscn

const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const SHOW := preload("res://scripts/scenes/shop/axe_evo_show.gd")
var dir := ""
var is_driver := false


func _ready() -> void:
	if not is_driver:
		var d = get_script().new()
		d.is_driver = true
		d.name = "ShotAxeEvoDriver"
		get_tree().root.add_child.call_deferred(d)
		return
	dir = OS.get_environment("SHOT_DIR")
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	_run.call_deferred()


func _seed(stage: int, bar: int, shelf: Array) -> void:
	load("res://tests/_setup_appstore.gd").run()
	GameState.meta_deepsea_coins = 999
	GameState.season_level = 5
	GameState.season_total_battles = maxi(1, int(GameState.season_total_battles))
	GameState.meta_shop_locked = false
	GameState.persistent_bench = [] if stage == 0 else [{"id": "p2eq_096", "star": 1}]
	GameState.axe_stage = stage
	GameState.axe_exp_bar = bar
	GameState.axe_exp_total = 300
	GameState.axe_final = ""
	GameState.axe_evo_pending = []
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
	var sc := get_tree().current_scene
	sc._axe_evo.force_anim = true
	return sc


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
	await _frames(3)


func _live(root: Node, nm: String) -> Control:
	if root == null:
		return null
	for c in root.find_children(nm, "", true, false):
		if c is Control and (c as Control).is_visible_in_tree() and not c.is_queued_for_deletion():
			return c
	return null


func _save(nm: String) -> void:
	await _frames(2)
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [dir, nm]
	get_viewport().get_texture().get_image().save_png(path)
	print("[SHOT] ", path)


## 停掉 tween, 逐拍画。
func _stills(ev, final: bool, tag: String) -> void:
	if ev._tw != null:
		ev._tw.kill()
	var cut: float = SHOW.t_cut(final)
	var beats := [["1-old", 0.2], ["2-sil", SHOW.T_DIM + SHOW.T_OLD + 0.06], ["3-swap", cut - 0.45],
		["4-preflash", cut - 0.02], ["5-cut", cut + 0.03], ["6-burst", cut + 0.18], ["7-name", cut + 0.7]]
	for b in beats:
		ev._apply(float(b[1]))
		await _save("%s-%s" % [tag, str(b[0])])


func _run() -> void:
	# ① 商店买到当场进化(木 → 石)
	_seed(0, int(AE.STAGES[1]["need"]) - 1, ["p2eq_096", "p2eq_001", "p2eq_002"])
	var sc := await _open()
	await _click(_live(sc, "ShelfItem0"))
	await _frames(10)
	await _click(_live(_live(sc, "InspectCard"), "BuyBtn"))
	await _stills(sc._axe_evo, false, "evo")
	sc._axe_evo._close()
	# ② 再播一段(石 → 铁), 这次让它按真时长播完, 逐帧记画面(入口门禁已经验过, 这里只量动画本身)
	await _frames(10)
	var t0 := Time.get_ticks_msec()
	sc.play_axe_evo([{"from": 1, "to": 2}])
	var flips := 0
	var whites := 0
	var prev := ""
	var prev_w := -1.0
	var n := 0
	while sc._axe_evo.busy() and Time.get_ticks_msec() - t0 < 8000:
		var k: String = sc._axe_evo.shown_key()
		var w: float = sc._axe_evo.shown_white()
		if prev != "" and k != prev:
			flips += 1
		if prev_w >= 0.0 and w != prev_w:
			whites += 1
		prev = k; prev_w = w
		n += 1
		await get_tree().process_frame
	print("[SHOT] 真时长: %d 毫秒 · %d 帧 · 形态切换 %d 次 · 剪影开关 %d 次 · 收尾形态 %s"
		% [Time.get_ticks_msec() - t0, n, flips, whites, prev])
	# ③ 四选一 → 余烬
	_seed(AE.STAGES.size() - 1, AE.FINAL_NEED, ["p2eq_001", "p2eq_002", "p2eq_003"])
	sc = await _open()
	var pick: Button = null
	var card := _live(sc, "InspectCard")
	if card != null:
		for b in card.find_children("*", "Button", true, false):
			if str((b as Button).text) == "余烬":
				pick = b
	await _click(pick)
	await _stills(sc._axe_evo, true, "final")
	get_tree().quit()
