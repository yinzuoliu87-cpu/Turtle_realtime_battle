extends Node
## 标题像素字逐屏实拍台(2026-10-27 · docs/plans/20261027-UI美术规矩.md §6「两个比例逐屏实拍」那一条)。
##
## 一个进程按【启动时的窗口比例】把 §3.2 换过标题字的各屏挨个建出来, 每屏截一张。
## 两个比例各起一次进程(stretch 按启动窗口算, 进程里改尺寸测不准 —— 同 _shot_screens.gd 的理由):
##   QUIET=1 SHOT_DIR=C:/tmp/x SHOT_TAG=phone <godot> --audio-driver Dummy --path . \
##     res://tests/_shot_title_font.tscn --resolution 1560x720 --position 2000,80
##   (iPad 4:3 换 --resolution 1280x960, SHOT_TAG=ipad)
## SHOT_ONLY=a,b 只拍名字里含这些片段的几张。
## ★不能 --headless: 无头没有真实渲染, 截出来是空图而且不报错。
## ★不是门禁(不进 run-tests: 名字不以 verify_ 开头)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SC := preload("res://scripts/scenes/stage_ceremony.gd")
const WCC := preload("res://scripts/scenes/week_close_card.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const SHOW := preload("res://scripts/scenes/shop/axe_evo_show.gd")
const Backend := preload("res://scripts/net/backend.gd")
const ACCT_DEL := preload("res://scripts/scenes/settings/account_delete_dialog.gd")
const BLP := preload("res://scripts/scenes/settings/blocklist_panel.gd")
const SELFCHECK := preload("res://scripts/scenes/settings/selfcheck_panel.gd")
const FB_PANEL := preload("res://scripts/scenes/feedback_panel.gd")

var is_driver := false
var dir := ""
var tag := ""
var only: PackedStringArray = []
var n_shot := 0


func _ready() -> void:
	## 截图台自己挂到 root 下(换场景时不跟着被释放)
	if not is_driver:
		var d = get_script().new()
		d.is_driver = true
		d.name = "ShotTitleFontDriver"
		get_tree().root.add_child.call_deferred(d)
		return
	var gs = get_node("/root/GameState")
	gs.test_mode = true              # 截图台要渲染所以不是无头 ⇒ 手动置, 不写真存档
	load("res://tests/_setup_appstore.gd").run()   # 摆一个像样的号(昵称 / 阵容 / 背包), 不然各屏是空态
	gs.onboarded = true
	dir = OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = "C:/tmp/title_shots"
	DirAccess.make_dir_recursive_absolute(dir)
	tag = OS.get_environment("SHOT_TAG")
	if tag == "":
		var vs: Vector2 = get_viewport().get_visible_rect().size
		tag = "%dx%d" % [int(vs.x), int(vs.y)]
	var o := OS.get_environment("SHOT_ONLY")
	if o != "":
		only = o.split(",")
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	_run.call_deferred()


func _want(nm: String) -> bool:
	if only.is_empty():
		return true
	for k in only:
		if nm.contains(k):
			return true
	return false


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


## 墙钟等(入场 tween 走真实时间)
func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await get_tree().process_frame


func _shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s_%s.png" % [dir, nm, tag]
	get_viewport().get_texture().get_image().save_png(path)
	n_shot += 1
	print("[SHOT] ", path)


func _go_scene(path: String, settle: float = 2.0) -> Node:
	get_tree().change_scene_to_file(path)
	await _frames(3)
	await _wait(settle)
	return get_tree().current_scene


func _run() -> void:
	## ── A1 顶栏页名(九个枢纽页里挑名字最长 / 最常见的几个) ──
	for p in [["A1_settings", "Settings"], ["A1_record", "Record"], ["A1_codex", "Codex"],
			["A1_trainer", "TrainerConfig"], ["A1_friends", "Friends"], ["A1_leaderboard", "Leaderboard"],
			["A1_gauntlet", "GauntletBoard"], ["A1_bracket", "BracketMap"]]:
		if _want(p[0]):
			await _go_scene("res://scenes/%s.tscn" % p[1])
			await _shot(p[0])
	## ── A2 + A3 本周赛程页 ──
	if _want("A2_week"):
		var mm = await _go_scene("res://scenes/MainMenu.tscn", 3.5)
		if mm != null and mm.has_method("_open_week_popup"):
			mm._open_week_popup()
			await _wait(0.6)
			await _shot("A2_week")
	## ── D 设置类弹框 ──
	var dlg := [
		["D1_conflict", func(s): s._open_conflict_dialog()],
		["D2_bind", func(s): s._open_email_dialog("bind")],
		["D3_reset", func(s): s._ask_reset()],
		["D4_rename", func(s): s._open_rename_dialog()],
		["D5_acctdel", func(s): ACCT_DEL.open(s, "player@example.com", func() -> void: pass)],
		["D6_blocklist", func(s): BLP.open(s)],
		["D7_selfcheck", func(s): SELFCHECK.open(s)],
		["D8_feedback", func(s): FB_PANEL.open(s)],
	]
	for e in dlg:
		if not _want(e[0]):
			continue
		var s = await _go_scene("res://scenes/Settings.tscn", 1.5)
		(e[1] as Callable).call(s)
		await _wait(0.8)
		await _shot(e[0])
	## ── D9~D11 背包类 ──
	if _want("D9_help"):
		var inv = await _go_scene("res://scenes/Inventory.tscn", 2.0)
		inv._show_lineup_help()
		await _wait(0.6)
		await _shot("D9_help")
	if _want("D10_formation"):
		var inv2 = await _go_scene("res://scenes/Inventory.tscn", 2.0)
		inv2._formation.open()
		await _wait(0.8)
		await _shot("D10_formation")
	if _want("D11_candy"):
		var inv3 = await _go_scene("res://scenes/Inventory.tscn", 2.0)
		inv3._inv_jar._show_jar_reward({"tier": 7, "coins": 120, "xp": 30, "levelers": 1, "equips": []})
		await _wait(0.8)
		await _shot("D11_candy")
	## ── C1 + C2 + C3 首启 ──
	if _want("C1_intro") or _want("C2_naming") or _want("C3_tutchoice"):
		var fl = await _go_scene("res://scenes/FirstLaunch.tscn", 2.5)
		if _want("C1_intro"):
			await _shot("C1_intro")
		if _want("C3_tutchoice"):
			fl._ask()
			await _wait(0.8)
			await _shot("C3_tutchoice")
		if _want("C2_naming"):
			fl.open_naming()
			await _wait(0.8)
			await _shot("C2_naming")
	## ── C4 版本墙 ──
	if _want("C4_wall"):
		var cur = await _go_scene("res://scenes/Settings.tscn", 1.0)
		var vw := VersionWall.new()
		cur.add_child(vw)
		await _frames(2)
		vw.set_process(false)            # 它每帧按真判据(版本够新 ⇒ 不挡)把墙藏回去; 拍照时停掉
		var blk := vw.get_node_or_null("Blocker") as Control
		if blk != null:
			blk.visible = true
		await _wait(0.5)
		await _shot("C4_wall")
	## ── C5 + C6 匹配 ──
	if _want("C5_searching") or _want("C6_found"):
		var mk = await _go_scene("res://scenes/Matchmaking.tscn", 1.0)
		if _want("C5_searching"):
			await _shot("C5_searching")
		if _want("C6_found") and is_instance_valid(mk):
			mk.set("_cancelled", true)
			mk._build_vs({"name": "海龟大师123", "avatar": "stone", "id": "#ABC123"})
			await _wait(1.2)
			await _shot("C6_found")
	## ── C7 小木斧进化 ──
	if _want("C7_axe"):
		var host = await _go_scene("res://scenes/Settings.tscn", 1.0)
		var sh = SHOW.new(host)
		sh.force_anim = true
		sh.play([{"from": 0, "to": 1}])
		await _wait(SHOW.t_cut(false) + SHOW.T_NAME_DELAY + SHOW.T_NAME_IN + 0.4)
		await _shot("C7_axe")
	## ── 晋级仪式 / 收盘缎带 ──
	if _want("E1_ceremony"):
		var h1 = await _go_scene("res://scenes/MainMenu.tscn", 2.5)
		SC.play(h1, P2.PHASE_RANKED, P2.PHASE_GAUNTLET, "晋级闯关赛！", "周六闯关赛开打", false, func() -> void: pass)
		await _wait(3.0)
		await _shot("E1_ceremony")
	if _want("E2_closecard"):
		var h2 = await _go_scene("res://scenes/MainMenu.tscn", 2.5)
		var now := int(Time.get_unix_time_from_system())
		var d: Dictionary = WCC.spec(WCC.KIND_RANKED_IN, GameState, now)
		WCC.open(h2, d, func() -> void: pass)
		await _wait(2.0)
		await _shot("E2_closecard")
	## ── B 战斗里的大字(双路合成局, 照 verify_topbar_states 的摆法) ──
	if _want("B"):
		await _battle_shots()
	print("[SHOT] 共 %d 张 → %s" % [n_shot, dir])
	get_tree().quit(0)


func _battle_shots() -> void:
	var gs = get_node("/root/GameState")
	get_tree().change_scene_to_file("res://scenes/Settings.tscn")   # 先离开别的场景
	await _frames(3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	gs.dual_ghost = Backend.make_bot(3, rng)
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "minion", "role": "front", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	gs.dual_active = true
	gs.current_lane = "top"
	gs.lane_results = {}
	var s = RB.new()
	get_tree().current_scene.add_child(s)
	await _wait(2.5)
	s.set_process(false)
	var h = s._hud
	## B6 三路开战
	if _want("B6_overview"):
		s._dl_sys._dl_build_present_overlay("overview")
		await _wait(1.2)
		await _shot("B6_overview")
		s._dl_sys._dl_clear_present_overlay()
		await _wait(0.6)                 # 幕布淡出 0.22 秒再销毁
	## B6 + B7 本路战果
	if _want("B7_lanesettle"):
		s._dl_pending_loser = "right"
		s._dl_sys._dl_build_present_overlay("lane_settle")
		await _wait(1.2)
		await _shot("B7_lanesettle")
		s._dl_sys._dl_clear_present_overlay()
		await _wait(0.6)                 # 幕布淡出 0.22 秒再销毁
	## B8 加时
	if _want("B8_overtime") and h._topbar != null:
		h._topbar.show_splash()
		h._topbar._tick_splash(0.5)
		await _frames(2)
		await _shot("B8_overtime")
		h._topbar._tick_splash(99.0)
	## B1~B4 结算屏(先拍: 回放操作条一建就一直在, 会压在结算屏上)
	if _want("B1_settle") or _want("B3_team"):
		s._st_lane_hist = _make_hist()
		s._units.clear()
		gs.lane_results = {"top": "right", "bottom": "left"}
		gs.finals_pending_reveal = {}
		s._settled = false
		h._show_banner(true)
		await _wait(2.0)
		await _shot("B1_settle")
		var scr = h._settle
		if scr != null and is_instance_valid(scr):
			scr.show_page(1)
			await _wait(0.8)
			await _shot("B3_team")
			scr.queue_free()
			await _frames(3)
	## B5 回放收尾卡(固定文字「胜利」)
	if _want("B5_replay"):
		h.build_replay_bar()
		if h._replay_ui != null:
			h._replay_ui._end_card(true, false)
			await _wait(1.0)
			await _shot("B5_replay")


## 结算屏用的合成双路快照(同 verify_settle_pages 的形状)。
func _row(id: String, nm: String, d: int) -> Dictionary:
	return {"name": nm, "id": id, "is_summon": false, "_st_multi": false, "rarity": "C",
		"alive": true, "hp": 0.0, "maxHp": 100.0,
		"_st_dealt": d, "_st_taken": 500, "_st_heal": 0, "_st_crit": 0, "_st_kills": 1,
		"_st_shield": 0, "_st_dealt_by_type": {"phy": d, "mag": 0, "tru": 0}}


func _make_hist() -> Array:
	var out: Array = []
	for lane in ["top", "bottom"]:
		var snap := {"lane": lane}
		snap["left"] = [_row("stone", "石头龟", 1200), _row("bamboo", "竹叶龟", 900), _row("egg", "龟蛋", 0)]
		snap["right"] = [_row("hunter", "猎人龟", 800), _row("minion", "小将", 300), _row("egg", "龟蛋", 0)]
		out.append(snap)
	return out
