extends Node
## 结算屏【赛季版】实拍台(2026-10-27 · 用户 iPad 实机截图: 积分赛失败结算 MVP 那一行被按钮排切掉一半,
##   左上「失败」压在战斗 HUD 的头像 / 名字上, 右边缘透出单位栏)。
##
## _shot_title_font.tscn 的 B1_settle 拍的是【练习赛】(没有生命 / 上传 / 五格数据), 漏了最高的那一版。
## 这里按变体逐个建结算屏, 每个变体拍三页(战果 / 我方 / 敌方), 并把第 1 页每一行的高度打出来:
##   ranked_win / ranked_loss     积分赛三路 + 「阵容已上传」+ 五格数据 + MVP(截图那一版)
##   gauntlet_in                  闯关赛晋级那一局: 副标题下面还有两行说明(最高的那一版)
##   practice_win / practice_loss 练习赛两路(原来拍过的那一版, 对照)
##
## ★★会开窗口: 先问用户什么时候方便再跑(用户 2026-10-27「停，别弹窗」—— 一个尺寸一个窗口, 连着跑就是一个接一个弹)。
##   版式对不对由无头门禁 verify_settle_fit 管; 这个台只管给人看的实拍图。
## 跑法(Git Bash; 不能 --headless —— 无头截出来是空图):
##   APPDATA=<私有目录> XDG_DATA_HOME=<私有目录> QUIET=1 WINDOW=1 SHOT_DIR=C:/tmp/x SHOT_TAG=ipad \
##     TURTLE_SUPABASE=" " bash godot-quiet.sh res://tests/_shot_settle_season.tscn --resolution 1289x720 --position 2000,80
## SHOT_ONLY=ranked_loss,practice 只拍名字里含这些片段的变体。
## SHOT_INSETS=l,t,r,b 模拟真机安全区(逻辑 px; 桌面窗口拿不到真机安全区, iPad 窗口底边约 21、iPhone 横屏底 39 左右 100)。
## ★不是门禁(不进 run-tests: 名字不以 verify_ 开头)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const Backend := preload("res://scripts/net/backend.gd")

var is_driver := false
var dir := ""
var tag := ""
var only: PackedStringArray = []
var n_shot := 0


func _ready() -> void:
	if not is_driver:
		var d = get_script().new()
		d.is_driver = true
		d.name = "ShotSettleSeasonDriver"
		get_tree().root.add_child.call_deferred(d)
		return
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	load("res://tests/_setup_appstore.gd").run()
	gs.onboarded = true
	gs.nickname = "louist02"
	dir = OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = "C:/tmp/settle_shots"
	DirAccess.make_dir_recursive_absolute(dir)
	tag = OS.get_environment("SHOT_TAG")
	if tag == "":
		var vs: Vector2 = get_viewport().get_visible_rect().size
		tag = "%dx%d" % [int(vs.x), int(vs.y)]
	var o := OS.get_environment("SHOT_ONLY")
	if o != "":
		only = o.split(",")
	var ins := OS.get_environment("SHOT_INSETS")
	if ins != "":
		var p := ins.split(",")
		if p.size() == 4:
			SafeArea.override_insets = Vector4(float(p[0]), float(p[1]), float(p[2]), float(p[3]))
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


func _run() -> void:
	var gs = get_node("/root/GameState")
	get_tree().change_scene_to_file("res://scenes/Settings.tscn")
	await _frames(3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	gs.dual_ghost = Backend.make_bot(3, rng)
	gs.dual_active = true
	gs.current_lane = "top"
	gs.lane_results = {}
	var s = RB.new()
	get_tree().current_scene.add_child(s)
	## 等到场上真有单位(开场三路总览演完、HUD 的头像栏 / 单位栏都建出来)再冻住 —— 结算那一刻的样子
	var t0 := Time.get_ticks_msec()
	while (s._units as Array).is_empty() and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	await _wait(3.0)
	s.set_process(false)
	print("[SHOT] 场上单位 %d 个" % (s._units as Array).size())
	var h = s._hud
	print("[SHOT] 视口 %s 安全区 %s" % [str(get_viewport().get_visible_rect().size), str(SafeArea.insets(get_viewport().get_visible_rect().size))])
	for v in [["ranked_loss", false, "ranked"], ["ranked_win", true, "ranked"], ["gauntlet_in", true, "gauntlet"],
			["practice_win", true, "practice"], ["practice_loss", false, "practice"]]:
		if not _want(str(v[0])):
			continue
		await _one(s, h, gs, str(v[0]), bool(v[1]), str(v[2]))
	print("[SHOT] 共 %d 张 → %s" % [n_shot, dir])
	get_tree().quit(0)


func _one(s, h, gs, nm: String, won: bool, kind: String) -> void:
	var three := kind != "practice"
	## 前几路走快照、最后一路读活单位(与真实对局结算那一刻同形: HUD 上的头像 / 单位栏都还在, 会不会透出来才看得到)
	s._st_lane_hist = _make_hist(three)
	gs.current_lane = "final" if three else "bottom"
	gs.finals_pending_reveal = {}
	if three:
		gs.lane_results = {"top": "left", "bottom": "right", "final": "left" if won else "right"}
	else:
		gs.lane_results = {"top": "right" if won else "left", "bottom": "left" if won else "right"}
	gs.week_phase = P2.PHASE_RANKED if kind == "ranked" else (P2.PHASE_GAUNTLET if kind == "gauntlet" else "")
	gs.hearts = 5
	gs.season_wins = 3 if won else 0
	gs.ranked_used = 1
	gs.season_level = 2
	s._had_season = kind != "practice"
	s._last_was_exhibition = false
	s._last_reward = 15
	s._last_settle_kind = P2.SETTLE_RANKED if kind == "ranked" else (P2.SETTLE_GAUNTLET if kind == "gauntlet" else "")
	if kind == "gauntlet":
		gs.gauntlet_wins = 4
		gs.gauntlet_losses = 1
		gs.gauntlet_backfill_paid = 1        # 1 场提前晋级奖励 ⇒ 说明是两行(最高的那一版)
	s._settled = false
	h._show_banner(won)
	await _frames(2)
	var scr = h._settle
	if scr == null or not is_instance_valid(scr):
		print("[SHOT] %s 没建出结算屏" % nm)
		return
	## 晋级那一局先演整屏仪式(点一下才看到战果页) ⇒ 截图台直接收掉仪式
	var cer: Node = scr.find_child(StageCeremony.NODE_NAME, true, false)
	if cer != null:
		cer.queue_free()
	## 「阵容已上传」是回执到了才亮的那一行: 截图台没有回执 ⇒ 手动点亮(截图里它是亮的)
	if kind != "practice":
		for l in _labels_in(scr):
			if str((l as Label).text) == "阵容已上传":
				(l as Label).visible = true
	await _wait(2.0)
	_dump(scr, nm)
	await _shot("%s_p1" % nm)
	for pi in [1, 2]:
		scr.show_page(pi)
		await _wait(0.5)
		await _shot("%s_p%d" % [nm, pi + 1])
	scr.queue_free()
	await _frames(3)


## 第 1 页逐行的高度 + 页体高(看是谁把 MVP 挤出去的)
func _dump(scr, nm: String) -> void:
	var p1: Control = scr.pages[0]
	var body: Control = p1.get_parent()
	print("[DUMP] %s 页体 %s  第1页最小高 %.0f  页 %s" % [nm, str(body.get_global_rect()), p1.get_combined_minimum_size().y, str(p1.get_global_rect())])
	for c in p1.get_children():
		if c is Control and (c as Control).visible:
			print("[DUMP]   %-14s h=%.0f  rect=%s" % [str(c.name).substr(0, 14), (c as Control).get_combined_minimum_size().y, str((c as Control).get_global_rect())])
	var frame: Control = scr.find_child("SettleFrame", true, false)
	print("[DUMP]   框 %s  按钮行 %s" % [str(frame.get_global_rect()), str((scr.btn_row as Control).get_global_rect())])


func _labels_in(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append(n)
	for c in n.get_children():
		out += _labels_in(c)
	return out


func _row(id: String, nm: String, d: int) -> Dictionary:
	return {"name": nm, "id": id, "is_summon": false, "_st_multi": id == "minion", "rarity": "C",
		"alive": d % 2 == 0, "hp": 0.0, "maxHp": 100.0,
		"_st_dealt": d, "_st_taken": 500, "_st_heal": 0, "_st_crit": 0, "_st_kills": 1,
		"_st_shield": 0, "_st_dealt_by_type": {"phy": d - d / 3, "mag": d / 3, "tru": 0}}


## 双路(练习赛) / 三路(积分赛: 上路 + 下路 + 终极战场)合成快照, 合计每侧 8 行左右
func _make_hist(three: bool) -> Array:
	var out: Array = []
	var lanes: Array = ["top", "bottom"] if three else ["top"]
	for lane in lanes:
		var snap := {"lane": lane}
		snap["left"] = [_row("phoenix", "回圈龟", 2077), _row("two_head", "双头龟", 900), _row("minion", "小将", 300),
			_row("egg", "龟蛋", 0), _row("trainer", "训龟大师", 40)]
		snap["right"] = [_row("hunter", "猎人龟", 800), _row("minion", "精英小将", 300), _row("minion", "小将", 120),
			_row("egg", "龟蛋", 0), _row("trainer", "训龟大师", 40)]
		out.append(snap)
	return out
