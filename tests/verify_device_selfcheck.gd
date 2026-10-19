extends Node
## verify_device_selfcheck.gd —— 设置页隐藏的「设备自检」(诊断用, 2026-10-19)
## 方案书 docs/plans/20261019-服务器裁判.md「设备自检（诊断用）」。本体 scripts/referee/device_selfcheck.gd,
## 弹框 scripts/scenes/settings/selfcheck_panel.gd。
##
## 判据:
##   ① 场景表只有一份: 自检与 verify_determinism_cross 共用 `DetScenarios`(scripts/referee/det_scenarios.gd), 金标共用
##      `DeviceSelfcheck.GOLDEN_PATH`(data/); tests/ 下没有第二份表 / 金标; 全仓 .gd 里场景名字面量只出现在那一个文件。
##   ② 导出包里有: 每个导出预设的 exclude_filter 都不排除场景表与金标(反证: 原位置 tests/golden/ 会被排除)。
##   ③ 走真入口: 设置页版本号连点 —— 4 下不开、5 下开; 点「开始」⇒ 在不渲染的 SubViewport 里跑 15 场,
##      与金标比 ⇒ 本机必须 15/15 一致, 屏上那一句是「15/15 一致」, 15 格全写「一致」。
##   ④ 玩家现场不受影响: 跑之前故意弄脏 GameState(等级 / 强制等级 / 技能选择 / 装备 / 币 / 周锚点)——
##      仍然 15/15(证明跑的是全新默认值那一局, 不是玩家这一份), 跑完逐个还原;
##      DEBUG_EDIT / TURTLE_SEED / 调试场摆位文件 / 音效静音 一并还原。
##   ⑤ 上报一条: kind = selfcheck, 消息含 [SelfCheck] + 15/15 + 版本 + 平台 + 架构; 详情逐场景。
##   ⑥ 取消: 跑的时候点「取消」⇒ 当前场景下一帧收手、屏上「已取消」、不上报、现场照样还原; 再点「关闭」弹框消失。

const SET := preload("res://scripts/scenes/SettingsScene.gd")
const PANEL := preload("res://scripts/scenes/settings/selfcheck_panel.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
var _n := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _frames(k: int) -> void:
	for i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	print("=== 设备自检 ===")
	var gs = get_node_or_null("/root/GameState")
	_static_checks()
	_export_checks()
	await _layout_checks()

	## ── ④ 弄脏现场 ──
	gs.test_mode = true
	gs.season_level = 7
	gs.debug_level = 4
	gs.loadouts = {"stone": 2, "basic": 3, "candy": 3}
	gs.persistent_equipped = {"basic": ["p2eq_001", "p2eq_010"], "stone": ["p2eq_022"]}
	gs.gambler_wheel_stacks = {"gambler": 5}
	gs.meta_deepsea_coins = 12345
	gs.week_anchor_ts = 1790553600
	var dirty: Dictionary = ReplayRecorder.capture_all()
	var setup_txt := "{\"selfcheck_probe\": 1}"
	var sf := FileAccess.open(DeviceSelfcheck.DEBUG_SETUP, FileAccess.WRITE)
	sf.store_string(setup_txt)
	sf.close()
	OS.unset_environment("TURTLE_SEED")
	RB.DEBUG_EDIT = false
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = false
	var queued0 := ErrorReporter.queued_total

	## ── ③ 真入口: 设置页版本号连点 ──
	var sc: Control = SET.new()
	add_child(sc)
	await _frames(2)
	var fl = sc.find_child(SET.FOOT_LABEL, true, false)
	_ok("设置页有版本号那一行", fl is Label and str((fl as Label).text).contains("版本"), str(fl))
	for i in range(4):
		sc._on_foot_input(_click())
	_ok("连点 4 下: 不打开", sc.find_child(PANEL.LAYER, true, false) == null)
	sc._on_foot_input(_click())
	var layer = sc.find_child(PANEL.LAYER, true, false)
	_ok("★连点第 5 下: 打开「设备自检」", layer != null)
	_ok("隔太久的点击不累计(纯函数)", PANEL.note_tap([0, 100, 200, 300], 5000).size() == 1
		and PANEL.note_tap([4000, 4100, 4200, 4300], 5000).size() == 5)
	if layer == null:
		_finish()
		return
	await _frames(2)
	var go: Button = layer.find_child(PANEL.START, true, false)
	var close: Button = layer.find_child(PANEL.CLOSE, true, false)
	var st: Label = layer.find_child(PANEL.STATUS, true, false)
	var host = layer.find_child(PANEL.HOST, true, false)
	var chk: DeviceSelfcheck = layer.get_meta("selfcheck")
	_ok("弹框有「开始」「关闭」、状态行、不渲染的落脚处",
		go != null and close != null and st != null and host is SubViewport
		and (host as SubViewport).render_target_update_mode == SubViewport.UPDATE_DISABLED)
	_ok("按钮是像素实心钮(不是擂台金木框)", _is_pixel_skin(go) and _is_pixel_skin(close))
	var box_rect := Rect2()
	for c in layer.get_children():
		if c is Panel:
			box_rect = (c as Panel).get_global_rect()
	var vis: Rect2 = sc.get_viewport().get_visible_rect()
	_ok("弹框在可见区内", vis.encloses(box_rect), "%s in %s" % [box_rect, vis])

	var t0 := Time.get_ticks_msec()
	go.pressed.emit()
	await _frames(3)
	_ok("跑的时候: 「开始」不能再点、「关闭」变「取消」、宿主下面挂着战斗场",
		go.disabled and close.text == PANEL.BTN_CANCEL and chk.running)
	var w := 0
	while chk.running and w < 40000:
		await get_tree().process_frame
		w += 1
	var s: Dictionary = chk.summary()
	print("  自检用时 %.1f 秒 / %d 帧" % [float(Time.get_ticks_msec() - t0) / 1000.0, w])
	_ok("★分母: 跑完了 15 个场景(结果 %d 条)" % chk.results.size(), not chk.running and chk.results.size() == 15)
	var bad: Array = []
	for r in chk.results:
		if not bool((r as Dictionary)["ok"]):
			bad.append("%s 实得 %s / 金标 %s" % [str(r["tag"]), str(r["digest"]).left(16), str(r["want"]).left(16)])
	_ok("★★★本机 15/15 与金标一致(玩家 GameState 弄脏过 ⇒ 证明跑的是全新默认值那一局)",
		int(s["passed"]) == 15 and int(s["total"]) == 15, str(bad))
	_ok("屏上结论 = 「15/15 一致」", st.text == "15/15 一致", st.text)
	var grid = layer.find_child(PANEL.GRID, true, false)
	var same := 0
	for c in grid.get_children():
		if (c as Label).text.ends_with(" " + PANEL.TXT_SAME):   ## 「不一致」也以「一致」结尾 ⇒ 带上前面的空格
			same += 1
	_ok("15 格全写「一致」", same == 15, "%d" % same)
	_ok("跑完: 「开始」可点、按钮回到「关闭」", not go.disabled and close.text == PANEL.BTN_CLOSE)
	_ok("结论一句话(不一致时列圈号)", DeviceSelfcheck.result_line({"passed": 13, "total": 15,
		"failed": ["③ 3v3 满装备", "⑧ 雷暴"]}) == "13/15 一致 · 不一致 ③ ⑧")

	## ── ④ 还原 ──
	var after: Dictionary = ReplayRecorder.capture_all()
	var diff: Array = []
	for k in dirty:
		if str(after.get(k)) != str(dirty[k]):
			diff.append(str(k))
	_ok("★GameState 逐个还原(%d 个变量)" % dirty.size(), diff.is_empty() and dirty.size() > 50, str(diff))
	_ok("还原: 等级 7 / 强制等级 4 / 币 12345 / 技能选择", int(gs.season_level) == 7 and int(gs.debug_level) == 4
		and int(gs.meta_deepsea_coins) == 12345 and int(gs.loadouts.get("candy", 0)) == 3)
	_ok("还原: test_mode 回到跑之前", bool(gs.test_mode))
	_ok("还原: DEBUG_EDIT = false(否则下一场正式对局进调试场)", not RB.DEBUG_EDIT)
	_ok("还原: TURTLE_SEED 没留下(否则正式对局进 det 模式)", OS.get_environment("TURTLE_SEED") == "")
	_ok("还原: 调试场摆位文件原样", FileAccess.get_file_as_string(DeviceSelfcheck.DEBUG_SETUP) == setup_txt)
	_ok("还原: 音效不再静音", au == null or not bool(au.mute_sfx))
	_ok("宿主下面的战斗场都已离场", host.get_child_count() == 0, str(host.get_child_count()))

	## ── ⑤ 上报 ──
	var rows: Array = ErrorReporter.sent_rows.duplicate()
	if ErrorReporter.instance() != null:
		rows.append_array(ErrorReporter.instance().drain("verify"))
	var rep: Dictionary = {}
	for r in rows:
		if str((r as Dictionary).get("p_kind", "")) == DeviceSelfcheck.REPORT_KIND:
			rep = r
	var msg := str(rep.get("p_message", ""))
	_ok("★上报了一条 selfcheck", not rep.is_empty() and ErrorReporter.queued_total > queued0, str(rep))
	_ok("上报消息含 [SelfCheck] / 15/15 / 版本 / 平台 / 架构",
		msg.contains(DeviceSelfcheck.REPORT_TAG) and msg.contains("15/15") and msg.contains(ReplayRecorder.client_version())
		and msg.contains(OS.get_name()) and msg.contains(Engine.get_architecture_name()), msg)
	_ok("上报详情逐场景(15 行 OK)", str(rep.get("p_detail", "")).count("\nOK ") == 15)
	_ok("上报补了版本 / 平台", str(rep.get("p_version", "")) == ReplayRecorder.client_version()
		and str(rep.get("p_platform", "")) == OS.get_name(), str(rep))
	_ok("同一结果同一进程只报一次", not DeviceSelfcheck.report(s, chk.results))

	## ── ⑥ 取消 ──
	var q1 := ErrorReporter.queued_total
	go.pressed.emit()
	await _frames(120)
	_ok("取消前在跑", chk.running)
	close.pressed.emit()
	w = 0
	while chk.running and w < 3000:
		await get_tree().process_frame
		w += 1
	_ok("★点「取消」⇒ 很快收手(%d 帧)" % w, not chk.running and w < 300)
	_ok("取消: 屏上「已取消」、跑完的不足 15 条", st.text == PANEL.TXT_CANCELLED and chk.results.size() < 15,
		"%s / %d" % [st.text, chk.results.size()])
	_ok("取消: 不上报", ErrorReporter.queued_total == q1)
	_ok("取消: DEBUG_EDIT / TURTLE_SEED / 等级 都还原", not RB.DEBUG_EDIT and OS.get_environment("TURTLE_SEED") == ""
		and int(gs.season_level) == 7)
	_ok("取消后弹框还在(看结论)", is_instance_valid(layer) and layer.is_inside_tree())
	close.pressed.emit()
	await _frames(2)
	_ok("再点「关闭」⇒ 弹框消失", not is_instance_valid(layer) or not layer.is_inside_tree())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DeviceSelfcheck.DEBUG_SETUP))
	_finish()



## 16:9 与 19.5:9(另加 4:3 平板)各开一次弹框: 框在可见区内、框里每个控件在框内、格子 / 结论的字装得下。
func _layout_checks() -> void:
	var worst := DeviceSelfcheck.result_line({"passed": 0, "total": 15, "failed": DeviceSelfcheck.scenarios().map(
		func(x): return str((x as Dictionary)["tag"]))})
	for sz in [Vector2i(1280, 720), Vector2i(1560, 720), Vector2i(1280, 960)]:
		get_tree().root.size = sz
		await _frames(2)
		var sc: Control = SET.new()
		add_child(sc)
		await _frames(2)
		var layer: Control = PANEL.open(sc)
		await _frames(2)
		var box: Panel = null
		for c in layer.get_children():
			if c is Panel:
				box = c
		var vis: Rect2 = sc.get_viewport().get_visible_rect()
		var br: Rect2 = box.get_global_rect()
		var out: Array = []
		for c in box.find_children("*", "Control", true, false):
			var r: Rect2 = (c as Control).get_global_rect()
			if not br.grow(0.5).encloses(r):
				out.append(str((c as Control).name))
		var tight: Array = []
		for c in box.find_child(PANEL.GRID, true, false).get_children():
			var lb := c as Label
			for t in [lb.text, lb.text.get_slice(" ", 0) + " " + PANEL.TXT_DIFF]:
				var w: float = lb.get_theme_font("font").get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1,
					lb.get_theme_font_size("font_size")).x
				if w > lb.size.x:
					tight.append("%s %.0f>%.0f" % [t, w, lb.size.x])
		var st: Label = box.find_child(PANEL.STATUS, true, false)
		var f: Font = st.get_theme_font("font")
		var fs: int = st.get_theme_font_size("font_size")
		var lines: int = int(ceil(f.get_string_size(worst, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x / st.size.x))
		var need: float = float(lines) * f.get_height(fs)
		_ok("%dx%d: 弹框在可见区内" % [sz.x, sz.y], vis.encloses(br), "%s in %s" % [br, vis])
		_ok("%dx%d: 框里控件都在框内" % [sz.x, sz.y], out.is_empty(), str(out))
		_ok("%dx%d: 15 格「⑮ 不一致」也装得下" % [sz.x, sz.y], tight.is_empty(), str(tight))
		_ok("%dx%d: 结论最长那句(15 个都不一致)折 %d 行装得下" % [sz.x, sz.y, lines], need <= st.size.y,
			"%.0f > %.0f" % [need, st.size.y])
		sc.queue_free()
		await _frames(2)
	get_tree().root.size = Vector2i(1280, 720)
	await _frames(2)


func _click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e


func _is_pixel_skin(b: Button) -> bool:
	var sb = b.get_theme_stylebox("normal")
	return sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null \
		and str((sb as StyleBoxTexture).texture.resource_path) == UISkin.PIXEL_BTN


## ① 场景表 / 金标只有一份。
func _static_checks() -> void:
	_ok("★分母: 场景表 15 个场景", DeviceSelfcheck.scenarios().size() == 15)
	var g := DeviceSelfcheck.load_golden()
	_ok("★金标从 data/ 读到 15 条, 每个场景都有", g.size() == 15 and _all_tags_in(g), "%d" % g.size())
	_ok("金标在 data/(导出包排除 tests/)", DeviceSelfcheck.GOLDEN_PATH.begins_with("res://data/"))
	_ok("tests/ 下没有第二份场景表 / 金标", not FileAccess.file_exists("res://tests/_det_scenarios.gd")
		and not FileAccess.file_exists("res://tests/golden/determinism_cross.json"))
	var cross := FileAccess.get_file_as_string("res://tests/verify_determinism_cross.gd")
	_ok("verify_determinism_cross 用同一张表、同一份金标",
		cross.contains("preload(\"res://scripts/referee/det_scenarios.gd\")") and cross.contains("DeviceSelfcheck.GOLDEN_PATH"))
	var me := FileAccess.get_file_as_string("res://scripts/referee/device_selfcheck.gd")
	_ok("自检用 DetScenarios.all() / DetScenarios.run()", me.contains("DetScenarios.all()") and me.contains("DetScenarios.run("))
	## 场景名字面量: 全仓 .gd 只许出现在场景表那一个文件里(抄第二份 = 这里多出一个文件)。
	var hits: Array = []
	var files: Array = []
	for root in ["res://scripts", "res://tests", "res://autoload"]:
		_walk(root, files)
	var needles: Array = []
	for sc in DeviceSelfcheck.scenarios():
		needles.append("\"%s\"" % str((sc as Dictionary)["tag"]))
	for f in files:
		var txt := FileAccess.get_file_as_string(f)
		for nd in needles:
			if txt.contains(str(nd)):
				hits.append(f)
				break
	_ok("★分母: 扫了 %d 个 .gd" % files.size(), files.size() > 300)
	_ok("★★场景定义全仓只有一份(场景名字面量只在 det_scenarios.gd)",
		hits == ["res://scripts/referee/det_scenarios.gd"], str(hits))


func _all_tags_in(g: Dictionary) -> bool:
	for sc in DeviceSelfcheck.scenarios():
		if not g.has(str((sc as Dictionary)["tag"])):
			return false
	return true


func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_walk(dir + "/" + sub, out)


## ② 导出预设的 exclude_filter 不排除场景表与金标(iOS 是玩家真装的那一个)。
func _export_checks() -> void:
	var cfg := ConfigFile.new()
	_ok("读到 export_presets.cfg", cfg.load("res://export_presets.cfg") == OK)
	var need := ["data/determinism_cross.json", "scripts/referee/det_scenarios.gd", "scripts/referee/device_selfcheck.gd",
		"scripts/scenes/settings/selfcheck_panel.gd"]
	var n_presets := 0
	var ios := false
	var bad: Array = []
	var proof := false
	for sec in cfg.get_sections():
		if not (sec.begins_with("preset.") and sec.count(".") == 1):
			continue
		n_presets += 1
		var name := str(cfg.get_value(sec, "name", ""))
		if name == "iOS":
			ios = true
		var ex := str(cfg.get_value(sec, "exclude_filter", ""))
		for p in need:
			if _excluded(p, ex):
				bad.append("%s 排除了 %s" % [name, p])
		if name == "iOS":
			proof = _excluded("tests/golden/determinism_cross.json", ex)
	_ok("★分母: %d 个导出预设, 含 iOS" % n_presets, n_presets >= 5 and ios)
	_ok("★导出包不排除场景表 / 金标 / 自检", bad.is_empty(), str(bad))
	_ok("反证: 金标原位置 tests/golden/ 在 iOS 包里会被排除(这条判据会红)", proof)


func _excluded(path: String, filters: String) -> bool:
	for f in filters.split(","):
		var p := f.strip_edges()
		if p != "" and (path.matchn(p) or ("res://" + path).matchn("res://" + p)):
			return true
	return false


func _finish() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 设备自检 (%d/%d)" % [_n, _n])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _n - _fail])
	get_tree().quit(1 if _fail > 0 else 0)
