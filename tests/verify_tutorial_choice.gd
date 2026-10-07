extends Node

## verify_tutorial_choice.gd — 首启选择框「开始教程 / 跳过」(2026-10-07, 方案书 §4.3)
##
## 用户:「去给我参考，一般是有跳过和开始教程选项啊」/「去口语化你做就好，但是欢迎来到斗龟场还是要留的」
## 量的是**真主菜单**(MainMenu.tscn 实例, 当成 current_scene):
##   ① onboarded=false、ONBOARD 未设 ⇒ 出现 TutorialChoice: 标题「欢迎来到斗龟场」, 按钮恰为「开始教程」「跳过」
##   ② onboarded=true ⇒ 不出现; ONBOARD=0 ⇒ 不出现
##   ③ 老号迁移: onboarded=false 但打过积分赛(场次>0 或有战绩)⇒ 不出现, 并记成看过
##   ④「跳过」⇒ 框关掉、onboarded=true、仍在主菜单、没进教程
##   ⑤「开始教程」⇒ 进选龟屏、tutorial_active=true、沙盒开着
##   ⑥ 右上「?」⇒ 同一个框, 按钮「开始教程」「取消」;「取消」只关框
##   ⑦ 框里所有字无口语词
##   ⑧ SIM 驱动(下周 120 个号要用): 新号 onboarded=false ⇒ 驱动在框里按「开始教程」(SIM_TUTORIAL=skip ⇒「跳过」);
##      没框(看过教程)⇒ 驱动不碰; 驱动只在选择框里找按钮, 绝不按教程外壳上那颗同名的「跳过教程」

const MENU := "res://scenes/MainMenu.tscn"
const BANNED := ["啦", "吧", "呢", "哦", "咱", "我教你", "试试", "就行", "搞", "热身", "练练", "!", "！", "你", "等会儿", "开打"]

var _fail := 0
var _n := 0
const MIN_ASSERTS := 25
const Drv := preload("res://scripts/systems/sim/sim_driver.gd")


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	GameState.test_mode = true
	OS.set_environment("ONBOARD", "")
	get_tree().root.size = Vector2i(1280, 720)

	# ① 首启
	_fresh(false)
	var m = await _open_menu()
	var ch: Node = m.get_node_or_null("TutorialChoice")
	_ok("★★首启(onboarded=false)出现教程选择框", ch != null)
	if ch != null:
		var texts := _texts(ch)
		print("  [实测] 框里的字: %s" % str(texts))
		_ok("★标题「欢迎来到斗龟场」(用户: 要留)", "欢迎来到斗龟场" in texts)
		_ok("★副标题「新手教程」", "新手教程" in texts)
		var bt := _button_texts(ch)
		_ok("★★按钮恰为「开始教程」「跳过」", bt == ["开始教程", "跳过"], str(bt))
		_check_banned(texts, "首启框")
		# ④ 跳过
		var sk := ch.find_child("SkipTutorial", true, false) as Button
		sk.emit_signal("pressed")
		await _frames(3)
		_ok("★★「跳过」⇒ 框关掉", m.get_node_or_null("TutorialChoice") == null)
		_ok("★★「跳过」⇒ onboarded=true(下次不再弹)", bool(GameState.onboarded))
		_ok("★「跳过」⇒ 没进教程", not bool(GameState.tutorial_active))
		_ok("★「跳过」⇒ 仍在主菜单", get_tree().current_scene == m)
	await _close(m)

	# ② 已看过 / ONBOARD=0
	_fresh(true)
	m = await _open_menu()
	_ok("★onboarded=true ⇒ 不弹框", m.get_node_or_null("TutorialChoice") == null)
	await _close(m)
	_fresh(false)
	OS.set_environment("ONBOARD", "0")
	m = await _open_menu()
	_ok("★ONBOARD=0 ⇒ 不弹框", m.get_node_or_null("TutorialChoice") == null)
	OS.set_environment("ONBOARD", "")
	await _close(m)

	# ③ 老号迁移
	_fresh(false)
	GameState.match_history = [{"result": "win", "lineup": [], "mode": "dual", "turn": 1}]
	m = await _open_menu()
	_ok("★老号(有战绩但 onboarded=false) ⇒ 不弹框", m.get_node_or_null("TutorialChoice") == null)
	_ok("★老号 ⇒ 静默记成看过", bool(GameState.onboarded))
	await _close(m)

	# ⑥ 右上「?」
	_fresh(true)
	m = await _open_menu()
	m._on_tutorial()
	await _frames(2)
	ch = m.get_node_or_null("TutorialChoice")
	_ok("★「?」⇒ 同一个选择框", ch != null)
	if ch != null:
		var t2 := _texts(ch)
		_ok("★「?」框标题「新手教程」", "新手教程" in t2, str(t2))
		_ok("★★「?」框按钮恰为「开始教程」「取消」", _button_texts(ch) == ["开始教程", "取消"], str(_button_texts(ch)))
		_check_banned(t2, "?框")
		(ch.find_child("CancelTutorial", true, false) as Button).emit_signal("pressed")
		await _frames(3)
		_ok("★「取消」⇒ 只关框, 不进教程", m.get_node_or_null("TutorialChoice") == null and not bool(GameState.tutorial_active))
	await _close(m)

	# ⑧ SIM 驱动: skip / 没框
	_fresh(false)
	OS.set_environment("SIM_TUTORIAL", "skip")
	m = await _open_menu()
	var d = Drv.new()
	_ok("★⑧ 驱动认得出首启选择框", d._press_tutorial_choice(m))
	await _frames(3)
	_ok("★⑧ SIM_TUTORIAL=skip ⇒ 驱动按的是「跳过」(onboarded=true, 没进教程, 框关了)",
		bool(GameState.onboarded) and not bool(GameState.tutorial_active) and m.get_node_or_null("TutorialChoice") == null)
	d.free()
	await _close(m)
	OS.set_environment("SIM_TUTORIAL", "")
	_fresh(true)
	m = await _open_menu()
	d = Drv.new()
	_ok("★⑧ 看过教程的号: 驱动不认为有框(不乱按)", not d._press_tutorial_choice(m))
	d.free()
	await _close(m)
	var dsrc := FileAccess.get_file_as_string("res://scripts/systems/sim/sim_driver.gd")
	var fn := dsrc.substr(dsrc.find("func _press_tutorial_choice"))
	fn = fn.substr(0, fn.find("\nfunc ", 10))
	_ok("★★⑧ 驱动只在选择框里找「SkipTutorial」(全文件只出现在 _press_tutorial_choice 里; 外壳那颗同名钮绝不碰)",
		dsrc.count("\"SkipTutorial\"") == 1 and fn.contains("\"SkipTutorial\"") and fn.contains("get_node_or_null(\"TutorialChoice\")"))
	_ok("★⑧ 驱动不再翻 tut_overlay 里的按钮(旧「下一站」逻辑会误按跳过钮)", not dsrc.contains("_press_tut_next"))

	# ⑤ 开始教程(放最后: 会换场到选龟) —— 由 SIM 驱动按(默认 play), 同时验驱动那一半
	_fresh(false)
	m = await _open_menu()
	ch = m.get_node_or_null("TutorialChoice")
	if ch != null:
		var d2 = Drv.new()
		_ok("★⑧ SIM_TUTORIAL 默认(play): 驱动按了框里的按钮", d2._press_tutorial_choice(m))
		d2.free()
		var w := 0
		while w < 300 and (get_tree().current_scene == null or not str(get_tree().current_scene.scene_file_path).ends_with("TeamSelect.tscn")):
			await get_tree().process_frame
			w += 1
		_ok("★★「开始教程」⇒ 进选龟屏", get_tree().current_scene != null
			and str(get_tree().current_scene.scene_file_path).ends_with("TeamSelect.tscn"), "等了 %d 帧" % w)
		_ok("★「开始教程」⇒ tutorial_active=true 且沙盒开着", bool(GameState.tutorial_active)
			and get_node("/root/TutorialDirector").in_sandbox())
		get_node("/root/TutorialDirector").end_tutorial("skipped")
		await _frames(4)
	else:
		_ok("「开始教程」分母: 框在", false)
	_end()


func _end() -> void:
	print("  (共 %d 条断言 · 跑了 %d 帧)" % [_n, Engine.get_process_frames()])
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少 %d)" % [_n, MIN_ASSERTS])
	print("ALL PASS — 首启教程选择框" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _fresh(onboarded: bool) -> void:
	GameState.reset_save()
	GameState.onboarded = onboarded
	GameState.tutorial_active = false


func _open_menu() -> Node:
	var m = load(MENU).instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	await _frames(6)
	## 主菜单要是自己换了场(例: 首启不弹框直接进教程)就把真正的当前场景交回去 —— 下面的「框在不在」照样能判红,
	##   而不是拿一个已释放的实例往下走、整条协程中止。
	if not is_instance_valid(m):
		return get_tree().current_scene
	return m


func _close(m: Node) -> void:
	if is_instance_valid(m):
		if get_tree().current_scene == m:
			get_tree().current_scene = null
		m.queue_free()
	await _frames(2)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _texts(root: Node) -> Array:
	var out: Array = []
	for c in root.find_children("*", "Label", true, false):
		out.append((c as Label).text)
	for c in root.find_children("*", "Button", true, false):
		out.append((c as Button).text)
	return out


func _button_texts(root: Node) -> Array:
	var out: Array = []
	for c in root.find_children("*", "Button", true, false):
		out.append((c as Button).text)
	return out


func _check_banned(texts: Array, tag: String) -> void:
	var hits: Array = []
	for t in texts:
		for w in BANNED:
			if str(t).contains(str(w)):
				hits.append("%s⊃%s" % [t, w])
	_ok("★%s 无口语词" % tag, hits.is_empty(), str(hits))
