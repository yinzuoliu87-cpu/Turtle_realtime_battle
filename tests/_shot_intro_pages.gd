extends Node
## 首启介绍页的背景图台(2026-10-21 v4, 方案书 docs/plans/20261020-教程重写.md §v4)。不是门禁。
## 介绍页要「游戏真实画面」(用户 10-21) ⇒ 这里在真场景里拍, 产物进 assets/sprites/intro/(人工挑帧、转 jpg)。
##
##   INTRO_SHOT=battle  双路对局连拍(战斗场自带 SELFSHOT / SHOT_BURST / SHOT_STEP / SHOT_OUT)
##   INTRO_SHOT=shop    商店选中一件(说明卡 + 购买)
##   INTRO_SHOT=week    主菜单「本周赛程」弹层
##   INTRO_SHOT=egg     双路对局(对调阵容): 开场每 0.5 秒拍一张(第 1 页用); 定局那一路对手罩子破了之后
##                      镜头拉近跟拍**敌方的蛋**, 每 2 帧拍一张直到蛋碎后 1.5 秒(第 3 页用)。SHOT_OUT = 输出目录。
## ★两边名字一律换成「我方 / 敌方」(主会话 10-21: 介绍图上不许露出测试昵称)。
## 跑法(不能 --headless: 无头截出空图且不报错; 窗口只开右屏):
##   INTRO_SHOT=battle SELFSHOT=1 SHOT_BURST=80 SHOT_STEP=0.5 SHOT_OUT=<dir>/b.png DUALLANE=1 SHIP=1 QUIET=1 ONBOARD=0 \
##   TURTLE_SUPABASE=" " TURTLE_BACKEND=" " <godot> --audio-driver Dummy --position 1960,60 --resolution 1950x900 \
##     --path . res://tests/_shot_intro_pages.tscn
## ★种子沿用 App Store 那份(一个打了一周的玩家), 只换统领: 变脸龟正在另一条线上改, 介绍页不拍它。

const LEADERS := ["phoenix", "lightning", "ninja"]


func _ready() -> void:
	GameState.test_mode = true
	## 自绘的绿龟爪光标不进画面(手机上本来就没有它; memory fb-green-blob-is-cursor)。
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	load("res://tests/_setup_appstore.gd").run()
	GameState.nickname = "我方"
	var g0: Dictionary = GameState.dual_ghost
	(g0["profile"] as Dictionary)["name"] = "敌方"
	GameState.dual_ghost = g0
	GameState.season_leaders = LEADERS.duplicate()
	GameState.dual_lineup = {}
	GameState.dual_lineup = GameState.get_dual_lineup()
	var eq: Dictionary = GameState.persistent_equipped
	GameState.persistent_equipped = {"phoenix": eq.get("phoenix", []), "lightning": eq.get("lightning", []),
		"ninja": eq.get("two_head", [])}
	## INTRO_SWAP=1: 两边阵容对调(App Store 那份对手阵容归我方)⇒ 我方在破蛋窗口里打碎**对手**的蛋(拍「击碎敌方的蛋」那一页)。
	if OS.get_environment("INTRO_SWAP") == "1":
		var g: Dictionary = GameState.dual_ghost
		var mine: Dictionary = GameState.persistent_equipped.duplicate(true)
		var foe_l: Array = (g["leaders"] as Array).duplicate()
		var foe_eq: Dictionary = (g["equipped"] as Dictionary).duplicate(true)
		g["leaders"] = LEADERS.duplicate()
		g["lane_assign"] = {"top": [LEADERS[0], LEADERS[1]], "bottom": [LEADERS[2]]}
		g["equipped"] = mine
		g["pet_levels"] = {LEADERS[0]: 1, LEADERS[1]: 1, LEADERS[2]: 1}
		(g["profile"] as Dictionary)["avatar"] = LEADERS[0]
		GameState.dual_ghost = g
		GameState.season_leaders = foe_l
		GameState.dual_lineup = {}
		GameState.dual_lineup = GameState.get_dual_lineup()
		GameState.persistent_equipped = foe_eq
	await get_tree().process_frame
	var mode := OS.get_environment("INTRO_SHOT")
	if mode == "egg":
		_egg_mode()
		return
	if mode == "battle":
		get_tree().change_scene_to_file("res://scenes/RealtimeBattle3D.tscn")
		return
	var path := "res://scenes/Shop.tscn" if mode == "shop" else "res://scenes/MainMenu.tscn"
	var inst: Node = load(path).instantiate()
	add_child(inst)
	await get_tree().process_frame
	if mode == "shop":
		OS.set_environment("SHOT_STATE", "sel")
		load("res://tests/_shot_shop_states.gd").run(inst)
	for _i in range(150):
		await get_tree().process_frame
	if mode == "week" and inst.has_method("_open_week_popup"):
		inst.call("_open_week_popup")
		for _j in range(90):
			await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var out := OS.get_environment("SHOT_OUT")
	img.save_png(out)
	print("[INTRO_SHOT] %s → %s (%dx%d)" % [mode, out, img.get_width(), img.get_height()])
	get_tree().quit(0)


# ═══════════════════════════════ egg: 开场连拍 + 跟拍敌方蛋碎 ═══════════════════════════════

var _out := ""
var _t0 := 0
var _next_open := 0.0
var _n_open := 0
var _n_egg := 0
var _broken_at := -1.0
var _follow := false


func _egg_mode() -> void:
	_out = OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(_out)
	## 自己挪到根上常驻(换场会把当前场景连同本节点一起释放)
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	_t0 = Time.get_ticks_msec()
	get_tree().change_scene_to_file("res://scenes/RealtimeBattle3D.tscn")
	while true:
		await RenderingServer.frame_post_draw
		if not await _egg_tick():
			break
	get_tree().quit(0)


func _save(tag: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, tag])


## 返回 false = 拍完了。
func _egg_tick() -> bool:
	var sec: float = (Time.get_ticks_msec() - _t0) / 1000.0
	if sec > 240.0:
		print("[INTRO_SHOT] egg: 240 秒没等到敌方蛋碎")
		return false
	var bt := get_tree().current_scene
	if bt == null or not str(bt.scene_file_path).ends_with("RealtimeBattle3D.tscn"):
		return true
	## 开场 30 秒内每 0.5 秒一张
	if sec < 30.0 and sec >= _next_open:
		_next_open = sec + 0.5
		_save("open_%03d" % _n_open)
		_n_open += 1
	var egg: Dictionary = {}
	for u in bt.get("_units"):
		if u is Dictionary and bool(u.get("_isEgg", false)) and str(u.get("egg_side_lr", "")) == "right":
			egg = u
	var dl = bt.get("_dl_sys")
	var fence_down: bool = dl != null and (dl.get("fence_down") as Dictionary).has("right")
	_follow = (fence_down and not egg.is_empty()) or _broken_at >= 0.0
	if not egg.is_empty() and fence_down and _broken_at < 0.0:
		var w: Vector3 = bt.call("_world_pos", egg.get("pos", Vector2.ZERO), 0.0)
		var tgt: Vector3 = bt.get("CAM_TARGET")
		bt.set("_cam_zoom", 1.7)
		bt.set("_cam_pan", Vector3(w.x - tgt.x, 0.0, w.z - tgt.z) * 0.85)
		bt.call("_apply_cam_zoom")
	if _follow:
		if Engine.get_process_frames() % 2 == 0:
			_save("egg_%04d" % _n_egg)
			print("[INTRO_SHOT] egg_%04d hp=%s alive=%s" % [_n_egg, str(egg.get("hp", "?")), str(egg.get("alive", "?"))])
			_n_egg += 1
		if _broken_at < 0.0 and not egg.is_empty() and not bool(egg.get("alive", true)):
			_broken_at = sec
		if _broken_at >= 0.0 and sec - _broken_at > 1.5:
			print("[INTRO_SHOT] egg: 拍完(碎在 %.1f 秒)" % _broken_at)
			return false
	return true
