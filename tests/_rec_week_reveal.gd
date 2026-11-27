extends Node
## 本周羁绊开周揭晓录像台(不是门禁; 方案书 docs/plans/20261127b-本周羁绊开周揭晓.md)。
## 把钟钉在 11-30 那一周的周二(上线周: 6 个新羁绊必在), 一个已过教程、上周打过积分赛的号进主菜单 ⇒ 揭晓自动播;
##   REC_TAP_AT 秒(默认 6.0)模拟点一下(停留 → 收起)。REC_SKIP_AT 秒 = 发牌中途点一下(测跳过)。REC_SEC 秒收工。
## 跑法(右屏、静音、单独存档目录):
##   APPDATA=<目录> XDG_DATA_HOME=<目录> TURTLE_SUPABASE=" " TURTLE_BACKEND=" " WINDOW=1 \
##     bash godot-quiet.sh --path . --resolution 1280x720 --position 2000,80 --write-movie <输出>.avi --fixed-fps 30 res://tests/_rec_week_reveal.tscn
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const TUE := 1796083200 + 12 * 3600   # 2026-12-01 周二 12:00 UTC
var _el := 0.0
var _tapped := false
var _skipped := false
var _menu: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_P2C.now_override_ts = TUE
	var gs = get_node("/root/GameState")
	gs.tutorial_active = false
	gs.onboarded = true
	gs.nickname = "夜猫子"
	gs.battles_total = 30
	gs.first_tips_seen = {"start_battle": true, "first_week": true}
	StudioIntro.played = true
	gs.week_anchor_ts = WeeklySynergy.LAUNCH_WEEK   # 11-30 那一周(上线周)
	_menu = load("res://scenes/MainMenu.tscn").instantiate()
	get_tree().root.add_child(_menu)
	get_tree().current_scene = _menu
	## 收盘卡(上周的积分赛 / 闯关收盘)不在这条片子里: 记成看过
	gs.close_card_ranked_wk = int(gs.week_anchor_ts)
	gs.close_card_gauntlet_wk = int(gs.week_anchor_ts)
	print("[REC] 周锚点 ", gs.week_anchor_ts, " 本周 ", WeeklySynergy.of_week(int(gs.week_anchor_ts)))


func _tap() -> void:
	var ov = _menu.find_child(WeekReveal.NODE_NAME, true, false) if _menu != null else null
	if ov == null:
		print("[REC] %.2f 没有揭晓浮层" % _el)
		return
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true
	(ov.get_meta("reveal") as WeekReveal)._on_input(ev)
	print("[REC] %.2f 点一下" % _el)


func _process(d: float) -> void:
	_el += d
	if OS.has_environment("REC_SKIP_AT") and not _skipped and _el > float(OS.get_environment("REC_SKIP_AT")):
		_skipped = true
		_tap()
	if not _tapped and _el > float(OS.get_environment("REC_TAP_AT") if OS.has_environment("REC_TAP_AT") else "6.0"):
		_tapped = true
		_tap()
	if _el > float(OS.get_environment("REC_SEC") if OS.has_environment("REC_SEC") else "8.5"):
		print("[REC] 收工")
		get_tree().quit()
