extends Node
## 新手教程 v3 实玩录制(调试工具, 不进门禁): 从真主菜单开始, 按屏上那一句提示去**真点 / 真拖**(鼠标事件),
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
	await get_tree().process_frame
	## 自己挪到根上常驻, 再像玩家一样换到主菜单(主菜单要是真的 current_scene 才弹首启选择框)
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	GameState.test_mode = false     # 从 tests/ 启动会被存档闸置 test_mode(不写盘 ⇒ 欢迎框反复出现等假象)
	GameState.onboarded = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	await _f(60)
	var m := get_tree().current_scene
	var ch: Node = m.get_node_or_null("TutorialChoice")
	await _shoot("00_选择框")
	if ch == null:
		_note("★ 没弹选择框"); _finish(); return
	await _click_ctl(ch.find_child("StartTutorial", true, false) as Control)
	var guard := 0
	while guard < 60:
		guard += 1
		var cs := get_tree().current_scene
		if cs != null and str(cs.scene_file_path).ends_with("MainMenu.tscn") and not GameState.tutorial_active:
			break
		var g := await _wait_guide(9000)   # 战斗真打完: 三路最长 ~140 游戏秒
		if g == null:
			cs = get_tree().current_scene
			if cs != null and str(cs.scene_file_path).ends_with("MainMenu.tscn") and not GameState.tutorial_active:
				break
			_note("★ 等不到下一句提示(卡在 %s)" % (str(cs.scene_file_path) if cs != null else "?"))
			break
		await _do_step(g)
	## 回到主菜单: 首次提示
	await _f(30)
	await _shoot("16_主菜单_首次提示")
	await _f(60)
	_finish()


## 等一条正在显示的引导(战斗里那两句不阻塞提示也算)。最多 max_f 帧。
func _wait_guide(max_f: int) -> Node:
	for _i in range(max_f):
		for n in get_tree().get_nodes_in_group("tut_overlay"):
			if is_instance_valid(n) and n.has_method("is_showing") and not n.is_queued_for_deletion() and n.is_showing():
				return n
		var cs := get_tree().current_scene
		if cs != null and str(cs.scene_file_path).ends_with("MainMenu.tscn") and not GameState.tutorial_active:
			return null
		await _f(1)
	return null


func _do_step(g: Node) -> void:
	var idx: int = int(g._idx)
	var step: Dictionary = g._steps[idx]
	var txt := str(step.get("text", ""))
	await _f(8)       # 让提示淡入 / 手势动起来再拍
	await _shoot("%02d_%s" % [_step_no(txt), txt.replace("，", "_").replace(" ", "").replace(":", "比")])
	_timeline.append([_frame, txt])
	if not g.is_tip():
		await _f(READ_FRAMES)   # 像玩家一样先读一眼再点(录屏里每一步看得清)
	if g.is_tip():
		## 不阻塞提示: 什么都不点, 等它自己走
		while is_instance_valid(g) and int(g._idx) == idx and not g.is_queued_for_deletion():
			await _f(1)
		## 第二句放完: 点一下我方头像栏上方的「教程加成」签, 录下说明句(用户 10-20 要求看得见)
		if txt == "击碎敌方的蛋直接获胜":
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
	await _shoot("04b_教程加成_%s" % str(bn.popup_text()).replace("：", "_").replace("，", "_").replace(" ", "").replace("%", "pct"))
	_timeline.append([_frame, "(点开) " + str(bn.popup_text())])
	await _f(READ_FRAMES)
	await _click((bn.badge as Control).get_global_rect().get_center())


## 方案书 §1 表里的编号(截图文件名用)。
func _step_no(txt: String) -> int:
	var order := ["选择 3 只龟上阵", "点击出战", "赢两个战场获胜，1:1 进入终极战场", "击碎敌方的蛋直接获胜", "点击前往商店",
		"购买经验，升到 2 级", "点击一件装备", "点击购买", "点击背包"]
	var i := order.find(txt)
	if i >= 0:
		## 「点击一件装备」商店和背包各有一句: 背包那句排第 10
		var cs := get_tree().current_scene
		if txt == "点击一件装备" and cs != null and str(cs.scene_file_path).ends_with("Inventory.tscn"):
			return 10
		return i + 1
	var inv := ["点击一件装备", "点击一只龟装上", "点击站位", "拖动龟调整站位", "点击完成", "点击完成教程"]
	var j := inv.find(txt)
	return 10 + j if j >= 0 else 99


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
			await _shoot("13b_拖动中")
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
		var path := "%s/%s.png" % [_out, tag]
		img.save_png(path)
	_note("%s @帧 %d" % [tag, _frame])


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
	print("  PLAYTHROUGH DONE")
	get_tree().quit(0)
