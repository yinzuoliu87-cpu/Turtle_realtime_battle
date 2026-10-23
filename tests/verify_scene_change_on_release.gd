extends Node
## verify_scene_change_on_release.gd — 点按钮切场景不再刷「!is_inside_tree() @ can_process」(2026-10-23)
##
## 正式服报错(iOS / Android, 0.21.x): `Condition "!is_inside_tree()" is true. Returning: false`
##   detail = `scene/main/node.cpp:902 @ can_process`, 没有脚本栈, 场景 = 排行榜 / 选龟屏等。
## 根因: 按钮 `pressed` 在**抬起**那一下发; 回调里同步 `change_scene_to_file` ⇒ 旧场景**当场**离树(引擎文档:
##   「The current scene node is immediately removed from the tree」), 而同一次抬起的触摸事件还在往下分发,
##   GUI 拿着这颗已离树、还没释放的按钮去问 can_process ⇒ 报一条。功能不受影响, 但每个进程都占上报器一个名额。
## 修法: 切场景一律 `SceneNav.go(tree, path)`(scripts/util/scene_nav.gd): 旧场景当场停掉处理 + 换屏延后到这一帧输入分发完。
## 判据:
##   ① 实测: 冒充触摸点一颗按钮。同步切 ⇒ 触摸抬起到达 GUI 那一刻, 被点的按钮**已经离树**(= 那条报错的前提;
##      量到就把这条事件吞掉, 不让它真打出来 —— 门禁的致命正则认 `Condition ".*" is true`, 测试里没有「预期报错」的豁免口)。
##      SceneNav.go ⇒ 那一刻按钮还在树上、Logger 一条都没收到、场景照样切过去,
##   ③ 旧场景从 go() 那一刻起**一帧 `_process` 都不再跑**(同步切换原本的语义)。
##      ⚠ 点按钮 / 计时器回调两条路量不出差别(2026-10-23 实测): 引擎在 `process_frame` 之后先清一次延后队列,
##      延后的换屏赶在各节点 `_process` 之前。差别在**旧场景某个节点自己的 `_process` 里**调 go()
##      (如战斗场每帧逻辑里切回主菜单): 延后队列要到这一帧末尾才清, 同一帧里排在它后面的旧场景节点还会再跑一次;
##      同步切换时它们当场就离树了。③ 就造这个形状。
##      (2026-10-23 本机实测: 不吞的话同步切确实打出 `Condition "!is_inside_tree()" is true … can_process (node.cpp:902)`, 与正式服逐字相同。)
##   ② 静态: `scripts/scenes/**` 里切场景只许走 `SceneNav.go(`(不许直接 `change_scene_to_file`, 同步、延后都不行)
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_scene_change_on_release.tscn

const SIG := "can_process"
const DEST := "res://tests/_blank_scene.tscn"

var _n := 0
var _fail := 0
var _btn: Button = null
var _gone_at_release := -1          # 触摸抬起到达时被点的按钮: 1 = 已离树 / 0 = 还在树上 / -1 = 没量到
var _ticker: Node = null            # 旧场景里一个每帧计数的节点
var _ticks_at_go := -1              # 按下那一刻(go 之后)它已经跑了几帧
var _cap: _Cap = null


class _Cap extends Logger:
	var msgs: Array = []
	var _mx := Mutex.new()
	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		_mx.lock()
		msgs.append("%s %s %s" % [code, rationale, _function])
		_mx.unlock()
	# zero-caller-ok: Logger 引擎虚函数, 由引擎调
	func _log_message(_message: String, _error: bool) -> void:
		pass
	func count(sig: String) -> int:
		_mx.lock()
		var k := 0
		for m in msgs:
			if str(m).find(sig) >= 0 and str(m).find("is_inside_tree") >= 0:
				k += 1
		_mx.unlock()
		return k


## 输入先过 `_input` 再进 GUI: 在这里看触摸抬起到达时那颗按钮还在不在树上。
func _input(event: InputEvent) -> void:
	if _btn == null or not (event is InputEventScreenTouch) or (event as InputEventScreenTouch).pressed:
		return
	_gone_at_release = 1 if (is_instance_valid(_btn) and not _btn.is_inside_tree()) else 0
	if _gone_at_release == 1:
		get_viewport().set_input_as_handled()     # 已量到前提; 不让它进 GUI 真打出那条报错


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


## 造一个「当前场景」, 中间一颗按钮; 点它 ⇒ 按 deferred 决定同步切 / SceneNav.go 到空场景。
## 场景里挂一个每帧 +1 的节点(代表旧场景自己的 `_process`, 如战斗场的 sim)。
## ★场景根是一个高层 CanvasLayer: 常驻层(版本墙 / 提示条…)盖在第 0 层上, 普通 Control 收不到点击。
func _make_scene(deferred: bool) -> CanvasLayer:
	var sc := CanvasLayer.new()
	sc.name = "ProbeScene"
	sc.layer = 120
	var b := Button.new()
	b.name = "Go"
	b.text = "切"
	b.position = Vector2(200, 200)
	b.size = Vector2(200, 100)
	sc.add_child(b)
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar ticks := 0\nfunc _process(_d: float) -> void:\n\tticks += 1\nfunc _exit_tree() -> void:\n\tget_tree().root.set_meta(\"gate_ticks_exit\", ticks)\n"
	gs.reload()
	_ticker = Node.new()
	_ticker.name = "Ticker"
	_ticker.set_script(gs)
	sc.add_child(_ticker)
	if deferred:
		b.pressed.connect(func() -> void:
			SceneNav.go(get_tree(), DEST)
			_ticks_at_go = int(_ticker.get("ticks")))
	else:
		b.pressed.connect(func() -> void:
			_ticks_at_go = int(_ticker.get("ticks"))
			get_tree().change_scene_to_file(DEST))
	get_tree().root.add_child(sc)
	get_tree().current_scene = sc
	return sc


## 冒充手指, 照手机上引擎的下发顺序: 触摸先被转成一条鼠标事件喂给 GUI(按钮靠它判按下 / 抬起),
##   然后**同一条触摸事件本身**再下发一次。抬起那条鼠标事件触发 `pressed` ⇒ 同步切场景 ⇒ 按钮当场离树,
##   紧接着到的触摸抬起还指向它。(`Input.parse_input_event` 在无头下不走 GUI, 这里直接按视口本地坐标推给视口。)
func _tap(at: Vector2) -> void:
	var vpt := get_viewport()
	var mp := InputEventMouseButton.new()
	mp.button_index = MOUSE_BUTTON_LEFT
	mp.pressed = true
	mp.position = at
	mp.global_position = at
	vpt.push_input(mp, true)
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = at
	t.pressed = true
	vpt.push_input(t, true)
	await _frames(2)
	var mr := InputEventMouseButton.new()
	mr.button_index = MOUSE_BUTTON_LEFT
	mr.pressed = false
	mr.position = at
	mr.global_position = at
	vpt.push_input(mr, true)
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.position = at
	u.pressed = false
	vpt.push_input(u, true)
	await _frames(4)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	print("=== 点按钮切场景不刷 can_process ===")
	_cap = _Cap.new()
	OS.add_logger(_cap)
	var res := {}
	for deferred in [false, true]:
		var sc := _make_scene(deferred)
		await _frames(3)
		var c0 := _cap.count(SIG)
		_btn = sc.get_node("Go") as Button
		_gone_at_release = -1
		_ticks_at_go = -1
		get_tree().root.set_meta("gate_ticks_exit", -1)
		await _tap(_btn.get_global_rect().get_center())
		var cs := get_tree().current_scene
		var after: int = int(get_tree().root.get_meta("gate_ticks_exit", -1))   # 旧场景离树那一刻它跑了几帧
		res[deferred] = {"errs": _cap.count(SIG) - c0, "gone": _gone_at_release,
			"switched": cs != null and cs != sc and str(cs.scene_file_path) == DEST,
			"ticks_go": _ticks_at_go, "ticks_after": after}
		_btn = null
		if is_instance_valid(sc):
			sc.queue_free()
		if cs != null and cs != sc and is_instance_valid(cs):
			cs.queue_free()
		await _frames(2)
	## Logger 的分母: 它真收得到引擎报错(不然下面「0 条」是空检查)
	var tag := "gate-scene-change-probe %d" % Time.get_ticks_usec()
	push_error(tag)
	await _frames(1)
	var got := false
	for m in _cap.msgs:
		got = got or str(m).find(tag) >= 0
	OS.remove_logger(_cap)
	_ok("★分母: Logger 真收得到引擎报错", got)
	_ok("★分母: 同步切 ⇒ 场景切过去了(按钮真的被触摸点到)", bool(res[false]["switched"]), str(res[false]))
	_ok("★分母: 同步切 ⇒ 触摸抬起到达时被点的按钮已离树(正式服那条报错的前提, 本机复现)", int(res[false]["gone"]) == 1, str(res[false]))
	_ok("★① 延后切 ⇒ 场景照样切过去", bool(res[true]["switched"]), str(res[true]))
	_ok("★★① 延后切 ⇒ 触摸抬起到达时按钮还在树上", int(res[true]["gone"]) == 0, str(res[true]))
	_ok("★★① 延后切 ⇒「!is_inside_tree() @ can_process」一条都不报", int(res[true]["errs"]) == 0, str(res[true]))
	_ok("★分母: 旧场景的计数节点在点之前真的在跑(按下时已跑 ≥ 3 帧)", int(res[true]["ticks_go"]) >= 3, str(res[true]))
	_ok("① 点按钮那条路: go() 之后旧场景也没再跑", int(res[true]["ticks_go"]) >= 0 and int(res[true]["ticks_after"]) == int(res[true]["ticks_go"]), str(res[true]))

	## ③ 旧场景节点自己的 `_process` 里 go(): 排在它后面的旧场景节点这一帧不许再跑
	var sc3 := _make_scene(true)
	var caller := Node.new()
	var cs_src := GDScript.new()
	cs_src.source_code = "extends Node\nfunc _process(_d: float) -> void:\n\tvar r := get_tree().root\n\tif r.get_meta(\"gate_go_now\", false):\n\t\tr.set_meta(\"gate_go_now\", false)\n\t\tSceneNav.go(get_tree(), \"%s\")\n\t\tr.set_meta(\"gate_ticks_at_go\", int(get_parent().get_node(\"Ticker\").get(\"ticks\")))\n" % DEST
	cs_src.reload()
	caller.set_script(cs_src)
	sc3.add_child(caller)
	sc3.move_child(caller, 0)                 # 排在计数节点前面: 同一帧里它先跑
	await _frames(3)
	get_tree().root.set_meta("gate_ticks_exit", -1)
	get_tree().root.set_meta("gate_ticks_at_go", -1)
	get_tree().root.set_meta("gate_go_now", true)
	var at_go := [-1]
	for _i in range(60):
		await get_tree().process_frame
		if int(get_tree().root.get_meta("gate_ticks_exit", -1)) >= 0:
			break
	await _frames(2)
	at_go[0] = int(get_tree().root.get_meta("gate_ticks_at_go", -1))
	var ex3: int = int(get_tree().root.get_meta("gate_ticks_exit", -1))
	var cs3 := get_tree().current_scene
	_ok("★分母 ③: 旧场景节点的 `_process` 真的调了 go()、旧场景真的离树了", at_go[0] >= 3 and ex3 >= 0, "go 时 %d 帧 / 离树时 %d 帧" % [at_go[0], ex3])
	_ok("★★③ 旧场景 `_process` 里 go() 之后, 排在后面的旧场景节点这一帧不再跑", ex3 == at_go[0], "go 时 %d 帧 / 离树时 %d 帧" % [at_go[0], ex3])
	if is_instance_valid(sc3):
		sc3.queue_free()
	if cs3 != null and cs3 != sc3 and is_instance_valid(cs3):
		cs3.queue_free()
	await _frames(2)

	## ② 静态: scripts/scenes/** 里切场景只许走 SceneNav.go
	var raw: Array = []
	var sites := 0
	for f in _gd_files("res://scripts/scenes"):
		var ln := 0
		for line in FileAccess.get_file_as_string(f).split("\n"):
			ln += 1
			var t := line.strip_edges()
			if t.begins_with("#"):
				continue
			if t.find("SceneNav.go(") >= 0:
				sites += 1
			if t.find("change_scene_to_file") >= 0:
				raw.append("%s:%d" % [f, ln])
	_ok("② 分母: scripts/scenes 里走 SceneNav.go 的切场景 %d 处" % sites, sites >= 30, str(sites))
	_ok("★★② scripts/scenes 里没有直接 change_scene_to_file(一律 SceneNav.go)", raw.is_empty(), str(raw))

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 点按钮切场景不刷 can_process" if _fail == 0 and _n >= 11 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


func _gd_files(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_gd_files(dir.path_join(sub)))
	return out
