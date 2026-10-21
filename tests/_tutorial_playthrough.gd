extends Node
## 新手教程 v5 实玩录制(v5 2026-10-21: 开始教程 ⇒ 选龟屏 3 只依次真点 + 真点一个技能 + 出战; 战斗 6 句提示挂在事件上;
##   分镜 docs/plans/20261021-教程分镜v5.md)。
## v4 原文: 新手教程 v4 实玩录制(调试工具, 不进门禁; v4 2026-10-21 加首启介绍 / 问 / 起名, TUT_PATH=play|skip): 从真主菜单开始, 按屏上那一句提示去**真点 / 真拖**(鼠标事件),
##   战斗真打完(不走结算快捷入口), 每一步提示出现时截一张图, 并把每一帧的步骤名记进时间轴。
##   方案书 docs/plans/20261020-教程重写.md §5 第 3 条(录屏给用户看)。整条的断言版是 tests/verify_tutorial_flow_v3.gd。
##
## 跑法(右屏、静音、独立存档; 录屏用引擎自带的 Movie Maker 逐帧落 PNG):
##   APPDATA=<新目录> XDG_DATA_HOME=<新目录> TURTLE_BACKEND=" " TURTLE_SUPABASE=" " QUIET=1 SHIP=1 \
##   TUT_OUT=<截图目录> godot --audio-driver Dummy --resolution 1280x720 --position 1960,60 \
##     --write-movie <帧目录>/f.png --fixed-fps 20 --path . res://tests/_tutorial_playthrough.tscn
## ★不要带 ONBOARD=1: 它强制弹首启选择框, 教程完成回到主菜单时会再弹一次(10-20 重录踩到; 方案书 R7 同一条)。
## ★驱动是通用的: 每一步读引导条自己的「指点处」(point, 缺省 highlight)去点 —— 不另抄一份坐标表;
##   引导挖洞挖错了, 这一下就会被暗幕吃掉, 流程停在那一步(= 实玩会卡住的地方)。
## ★等待一律按帧(Movie Maker 下每帧 = 固定的 1/fps 秒游戏时间; 墙钟与游戏时间无关)。

var _out := ""
var _shot := 0
var _frame := 0
var _log: Array = []
var _timeline: Array = []      # [帧号, 事件]
var _fps := 20.0
## 每一步提示出现后先停这么多帧再点(20fps 下 ≈ 1.5 秒), 录屏里每一句读得清。
const READ_FRAMES := 30


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_out = OS.get_environment("TUT_OUT") if OS.has_environment("TUT_OUT") else "C:/tmp/tut_shots"
	DirAccess.make_dir_recursive_absolute(_out)
	_fps = float(OS.get_environment("TUT_FPS")) if OS.has_environment("TUT_FPS") else 60.0
	## v4(2026-10-21): TUT_PATH=play(默认, 要教程) | skip(不要教程)。两条路都从真主菜单起: 首启 ⇒ 首启流程那一屏(介绍 → 问) ⇒ …… ⇒ 起名 ⇒ 主菜单。
	var path := OS.get_environment("TUT_PATH") if OS.has_environment("TUT_PATH") else "play"
	_tag = "P" if path == "play" else "S"
	await get_tree().process_frame
	## 自己挪到根上常驻, 再像玩家一样换到主菜单(主菜单要是真的 current_scene 才进首启流程)
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	GameState.test_mode = false     # 从 tests/ 启动会被存档闸置 test_mode(不写盘 ⇒ 欢迎框反复出现等假象)
	GameState.onboarded = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	var fl := await _wait_scene("FirstLaunch.tscn", 300)
	if fl == null:
		_note("★ 没进首启流程"); _finish(); return
	_timeline.append([_frame, "首启流程(介绍)"])
	## 介绍: 不点, 让它自己放完(玩家什么都不做时看到的就是这个); 每页淡入后拍一张。
	var last := -1
	var guard := 0
	while is_instance_valid(fl) and not bool(fl.call("is_asking")) and guard < 2400:
		var pi: int = int(fl.call("page_index"))
		if pi != last:
			last = pi
			await _f(24)
			var pg: Dictionary = fl.PAGES[pi]
			await _shoot("介绍%d_%s" % [pi + 1, _fname(str(pg["text"]))])
			_timeline.append([_frame, "介绍 %d: %s %s" % [pi + 1, str(pg["title"]), str(pg["text"])]])
		await _f(1)
		guard += 1
	await _f(10)
	var ch: Node = fl.get_node_or_null("TutorialChoice")
	await _shoot("问_新手教程")
	_timeline.append([_frame, "问: 新手教程 · 开始教程 / 跳过"])
	if ch == null:
		_note("★ 没弹选择框"); _finish(); return
	await _f(READ_FRAMES)
	await _click_ctl(ch.find_child("SkipTutorial" if path == "skip" else "StartTutorial", true, false) as Control)
	if path != "skip":
		var g_guard := 0
		while g_guard < 60:
			g_guard += 1
			if _naming_scene() != null:
				break
			var g := await _wait_guide(9000)   # 战斗真打完: 三路最长 ~140 游戏秒
			if g == null:
				if _naming_scene() != null:
					break
				var cs := get_tree().current_scene
				_note("★ 等不到下一句提示(卡在 %s)" % (str(cs.scene_file_path) if cs != null else "?"))
				break
			await _do_step(g)
	## 起名
	var nfl := await _wait_naming(600)
	if nfl == null:
		_note("★ 没出起名框"); _finish(); return
	await _f(10)
	await _shoot("起名")
	_timeline.append([_frame, "起名: 输入昵称(预填) · 确认"])
	await _f(READ_FRAMES)
	await _click_ctl(nfl.find_child("NameOk", true, false) as Control)
	var mm := await _wait_scene("MainMenu.tscn", 300)
	_timeline.append([_frame, "主菜单"])
	await _f(60)
	await _shoot("主菜单_首次进入")
	## 10-21: 教程结束后第一次进主菜单 ⇒ 本周赛程页 + 一句赛季说明(FirstTips.FIRST_WEEK)。读一会儿, 点左上返回关掉。
	if mm != null and is_instance_valid(mm.get("_week_intro")):
		var wt := mm.find_child("WeekIntroText", true, false) as Label
		_timeline.append([_frame, "本周赛程: " + (wt.text if wt != null else "")])
		await _f(READ_FRAMES * 4)
		await _shoot("本周赛程_首次")
		var back := mm.find_child("WeekPopupBack", true, false) as Control
		await _click_ctl(back)
		await _f(30)
		_timeline.append([_frame, "关掉赛程页 ⇒ 主菜单"])
		await _shoot("主菜单_关掉赛程后")
	else:
		_note("★ 第一次进主菜单没打开本周赛程页")
	await _f(90)
	if mm != null and path != "skip":
		## 新手逐个点亮: 点一下锁着的「背包」, 录下那一句
		var sq: Node = mm.find_child("Sq_背包", true, false)
		if sq != null:
			await _click((sq as Control).get_global_rect().get_center())
			await _f(20)
			await _shoot("主菜单_点锁着的背包")
			_timeline.append([_frame, "点锁着的背包 ⇒ 首战后解锁"])
	await _f(60)
	_finish()


var _tag := "P"
var _seq := 0
var _steps_seen: Array = []


func _fname(t: String) -> String:
	return t.replace("，", "_").replace("：", "_").replace("、", "_").replace(" ", "").replace(":", "比")


func _wait_scene(suffix: String, max_f: int) -> Node:
	for _i in range(max_f):
		var cs := get_tree().current_scene
		if cs != null and str(cs.scene_file_path).ends_with(suffix):
			await _f(3)
			return get_tree().current_scene
		await _f(1)
	return null


func _naming_scene() -> Node:
	var cs := get_tree().current_scene
	if cs != null and str(cs.scene_file_path).ends_with("FirstLaunch.tscn") and bool(cs.call("is_naming")):
		return cs
	return null


func _wait_naming(max_f: int) -> Node:
	for _i in range(max_f):
		var n := _naming_scene()
		if n != null:
			return n
		await _f(1)
	return null


## 等一条正在显示的引导(战斗里那两句不阻塞提示也算)。最多 max_f 帧。
func _wait_guide(max_f: int) -> Node:
	for _i in range(max_f):
		for n in get_tree().get_nodes_in_group("tut_overlay"):
			if is_instance_valid(n) and n.has_method("is_showing") and not n.is_queued_for_deletion() and n.is_showing():
				return n
		var cs := get_tree().current_scene
		if cs != null and str(cs.scene_file_path).ends_with("MainMenu.tscn") and not GameState.tutorial_active:
			return null
		if _naming_scene() != null:
			return null
		await _f(1)
	return null


func _do_step(g: Node) -> void:
	var idx: int = int(g._idx)
	var step: Dictionary = g._steps[idx]
	await _f(8)       # 让提示淡入 / 箭头动起来再拍
	var txt: String = g.current_text() if is_instance_valid(g) else str(step.get("text", ""))   # v5: {pet}/{item} 已填好的那句
	await _shoot(_fname(txt))
	_timeline.append([_frame, txt])
	if not g.is_tip():
		await _f(READ_FRAMES)   # 像玩家一样先读一眼再点(录屏里每一步看得清)
	if g.is_tip():
		## 不阻塞提示: 什么都不点, 等它自己走
		while is_instance_valid(g) and int(g._idx) == idx and not g.is_queued_for_deletion():
			await _f(1)
		## C1(教程加成那句)放完: 点一下我方头像栏上方的「教程加成」签, 录下说明句(用户 10-20 要求看得见)
		if str(step.get("_id", "")) == "C1":
			await _show_buff_badge()
		return
	var pt := str(step.get("point", step.get("highlight", "")))
	var r: Rect2 = g._target_rect(pt)
	if r.size.x <= 0.0:
		r = g._target_rect(str(step.get("highlight", "")))
	if str(step.get("hand", "tap")) == "drag":
		await _drag(r.get_center(), r.get_center() + Vector2(-90, 60))
	else:
		await _click(r.get_center())
	## 等这一步翻过去(换屏 / 下一句)。选龟那一步要连点三只: 每点一下再读一次指点处。
	for _k in range(240):
		if not is_instance_valid(g) or g.is_queued_for_deletion() or int(g._idx) != idx:
			return
		await _f(1)
		if _k % 30 == 29:
			var r2: Rect2 = g._target_rect(pt)
			if r2.size.x > 0.0:
				await _click(r2.get_center())


## 教学战斗里点「教程加成」签 ⇒ 拍说明句 ⇒ 再点收起。
func _show_buff_badge() -> void:
	var cs := get_tree().current_scene
	var bn: Node = cs.get_node_or_null("TutorialBuffBadge") if cs != null else null
	if bn == null or not bn.badge.is_visible_in_tree():
		_note("★ 没有「教程加成」签")
		return
	await _click((bn.badge as Control).get_global_rect().get_center())
	await _f(READ_FRAMES)
	await _shoot("教程加成_%s" % _fname(str(bn.popup_text())).replace("%", "pct"))
	_timeline.append([_frame, "(点开) " + str(bn.popup_text())])
	await _f(READ_FRAMES)
	await _click((bn.badge as Control).get_global_rect().get_center())


# ── 鼠标(真事件, 走 Input 全链) ──
func _vp(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _btn(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = _vp(p)
	e.global_position = _vp(p)
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(e)


func _move(p: Vector2, rel: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = _vp(p)
	m.global_position = _vp(p)
	m.relative = rel
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(m)


func _click(p: Vector2) -> void:
	_move(p, Vector2.ZERO)
	await _f(6)
	_btn(p, true)
	await _f(3)
	_btn(p, false)
	await _f(10)


func _click_ctl(c: Control) -> void:
	if c != null:
		await _click(c.get_global_rect().get_center())


func _drag(a: Vector2, b: Vector2) -> void:
	_move(a, Vector2.ZERO)
	await _f(6)
	_btn(a, true)
	await _f(4)
	for k in range(1, 21):
		_move(a.lerp(b, k / 20.0), (b - a) / 20.0)
		await _f(1)
		if k == 12:
			await _shoot("拖动中")
	_btn(b, false)
	await _f(10)


func _f(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
		_frame += 1


func _shoot(tag: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		_seq += 1
		var path := "%s/%s%02d_%s.png" % [_out, _tag, _seq, tag]
		img.save_png(path)
	_note("%s @帧 %d" % [tag, _frame])
	_steps_seen.append(tag)


func _note(s: String) -> void:
	_log.append(s)
	print("  [流程] ", s)


func _finish() -> void:
	var f := FileAccess.open(_out + "/timeline.txt", FileAccess.WRITE)
	if f != null:
		f.store_line("fps=%s" % str(_fps))
		for t in _timeline:
			f.store_line("%d\t%s" % [int(t[0]), str(t[1])])
		f.store_line("%d\t(结束)" % _frame)
		f.close()
	print("  ═══ 完整流程 ═══")
	for l in _log:
		print("    " + str(l))
	print("  收尾: onboarded=%s(应true) tutorial_active=%s(应false) 共 %d 帧 ≈ %.1f 秒游戏时间" % [
		GameState.onboarded, GameState.tutorial_active, _frame, float(_frame) / _fps])
	print("  经过的引导 %d 句" % _steps_seen.size())
	print("  PLAYTHROUGH DONE")
	get_tree().quit(0)
