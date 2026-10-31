extends Node
## verify_touch_detach_on_release.gd — 手指抬起时被按的控件不许已离树(正式服 iOS「!is_inside_tree() @ can_process」, 2026-10-31)
##
## 正式服 client_errors(iOS 独有, 0.21.8 ~ 0.22.6 每版 1~5 条, 场景 背包 / 选龟 / 排行榜 / 赛况板):
##   `Condition "!is_inside_tree()" is true. Returning: false`  detail = `scene/main/node.cpp:902 @ can_process`, 没有脚本栈。
## 引擎路径(Godot 4.6.3-stable 源码逐行核过):
##   · viewport.cpp:2195  手指按下: `gui.touch_focus[index] = 按下那一点命中的控件` (存的是 ObjectID)
##   · viewport.cpp:2205-2207 手指抬起 / 2240-2246 手指拖动: 按 ObjectID 取回它, 只判了「还没释放」就调 `over->can_process()`
##   · node.cpp:902  `can_process()` 第一行 `ERR_FAIL_COND_V(!is_inside_tree(), false)` ⇒ 就是这条报错
##   · viewport.cpp:2545-2563 `_gui_remove_control`(控件离树时调): 清了 mouse_focus / key_focus / 悬停 / 拖放 / 提示,
##     **唯独不清 touch_focus**
##   · input.cpp:849-881 vs 986: 一下触摸, 引擎**先**派模拟出来的鼠标左键(按钮的 pressed 在这里发), **再**派触摸本身
##   ⇒ 按钮回调里把「被按的那颗(或它的祖先)」**摘下树但没当场释放**(remove_child / reload / 同步换场景
##      —— scene_tree.cpp:1710-1713 换场景是当场 remove_child, 要到下一次 process 的 _flush_scene_change(1647-1652)才删),
##      紧跟着的触摸抬起就打到它 ⇒ 报一条。
##   · 只在触屏: 项目没覆盖 input_devices/pointing, 桌面默认不产生 ScreenTouch。Android 走同一条路(正式服 Android 0 条, 原因未核)。
##   · 无害但占名额: 返回 false 只是这一下触摸不送给它; 上报器同签名每进程只排一次。
## 哪些写法安全(帧内顺序 main.cpp:4875/4957 输入 → physics/process → scene_tree.cpp:655/724 删除队列):
##   在 `_process` / 网络回调 / 计时器 / 延后调用里摘树 + queue_free —— 同一个 process 末尾就删了, 下一次输入取不回它;
##   只 queue_free 不摘 —— 帧尾才离树, 抬起时还在树上。
##
## 判据:
##   ① 引擎机理(合成): 真手指(Input.parse_input_event, 引擎自己生成模拟鼠标)点一颗按钮, 回调里
##      「摘下树不释放」⇒ 抬起到达时它已离树(= 那条报错的前提, 本机复现; 量到就吞掉这条事件, 不让门禁日志真出现报错);
##      「延后摘」/「只 queue_free」⇒ 抬起时还在树上、Logger 0 条。
##   ② 赛况板: 手指点左栏选手行(0.22.6 及以前回调里当场 `_render()` ⇒ 整行 remove_child, 探针在 0.22.6 上逐字复现正式服那条)
##      ⇒ 抬起时那颗还在树上、Logger 0 条、点一下仍选中了这个人。
##   ③ 设置页「存档冲突」弹框: 点「使用本地存档」(原来回调里同步 `reload_current_scene()` ⇒ 整个设置场景当场离树)
##      ⇒ 抬起时按钮还在树上、Logger 0 条、设置页照样重开了。
##   ④ 静态: scripts/scenes/** 里不许再有 `reload_current_scene(`(它就是同步 change_scene_to_file(当前场景),
##      `verify_scene_change_on_release` ② 只认 `change_scene_to_file` 这个字面量, 这一个从缝里漏了)。
##      只放行登记过理由的(都不是触摸点按); 登记项不再出现 ⇒ 红(提醒删掉, 别让名单烂掉)。
##
## 手动核对引擎报错原文: `GATE_LET_ENGINE_ERR=1` ⇒ 量到「已离树」也不吞, 让引擎真打出来, 打印 Logger 收到的原文(门禁里不要设)。
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_touch_detach_on_release.tscn

const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const BOARD := "res://scenes/GauntletBoard.tscn"
const SETTINGS := "res://scenes/Settings.tscn"
const BTN_USE_LOCAL := "使用本地存档"

## ④ 放行名单: 文件 → 理由。都不是触摸点按触发的(键盘 / 压测 / 桌面调试台)。
const RELOAD_OK := {
	"res://scripts/scenes/RealtimeBattle3DScene.gd": "键盘 R 重开(InputEventKey, 不经过 touch_focus) + STRESS=1 压测循环(sim 里调, 非输入回调)",
	"res://scripts/scenes/battle/review_console.gd": "REVIEW=1 桌面单技能审阅台(无触摸)",
}

var _n := 0
var _fail := 0
var _xf: Transform2D = Transform2D.IDENTITY
var _cap: _Cap = null
var _let_err := false

## 手指按下那一点命中的控件(= 引擎记进 touch_focus 的那一颗); 抬起到达时量它
var _watch: Control = null
var _rel := -1               # 触摸抬起到达时: 1 = 已离树 / 0 = 还在树上 / -1 = 没量到


class _Cap extends Logger:
	var msgs: Array = []
	var _mx := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		_mx.lock()
		msgs.append("%s %s | %s:%d @ %s" % [code, rationale, file, line, function])
		_mx.unlock()
	# zero-caller-ok: Logger 引擎虚函数, 由引擎调
	func _log_message(_message: String, _error: bool) -> void:
		pass
	func count() -> int:
		_mx.lock()
		var k := 0
		for m in msgs:
			if str(m).find("is_inside_tree") >= 0 and str(m).find("can_process") >= 0:
				k += 1
		_mx.unlock()
		return k


## 输入先过 `_input` 再进 GUI(viewport push_input: _input → _gui_input_event): 在这里量被按的那颗还在不在树上。
func _input(event: InputEvent) -> void:
	if _watch == null:
		return
	var rel: bool = event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed
	var drg: bool = event is InputEventScreenDrag
	if not (rel or drg):
		return
	var gone: bool = is_instance_valid(_watch) and not _watch.is_inside_tree()
	if rel:
		_rel = 1 if gone else 0
	if gone and not _let_err:
		get_viewport().set_input_as_handled()     # 已量到前提; 不让它进 GUI 真打出那条报错(门禁致命正则认 `Condition ".*" is true`)


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _ev(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await get_tree().process_frame


## 鼠标移到 p ⇒ 引擎同步做一次命中测试, 返回悬停的那一个 = 手指按在这里会落到的控件(gui_find_control 同一套)。
func _hover(p: Vector2) -> Control:
	var mm := InputEventMouseMotion.new()
	mm.position = _xf * p
	mm.global_position = mm.position
	Input.parse_input_event(mm)
	Input.flush_buffered_events()
	return get_viewport().gui_get_hovered_control()


## 真手指点一下(按下 → 抬起)。返回「按下那一点命中的是 target 或它的子孙」(按下之前量; 点完 target 可能已被释放)。
## 抬起那一下由 `_input` 量。
func _tap(p: Vector2, target: Control) -> bool:
	var h := _hover(p)
	var on: bool = h != null and (h == target or target.is_ancestor_of(h))
	_watch = h
	_rel = -1
	var t := InputEventScreenTouch.new(); t.index = 0; t.pressed = true; t.position = _xf * p
	await _ev(t)
	var u := InputEventScreenTouch.new(); u.index = 0; u.pressed = false; u.position = _xf * p
	await _ev(u)
	return on


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	print("=== 手指抬起时被按的控件不许已离树 ===")
	_let_err = OS.get_environment("GATE_LET_ENGINE_ERR") == "1"
	var env0: String = OS.get_environment(SB.ENV_URL)
	var had_env: bool = OS.has_environment(SB.ENV_URL)
	OS.set_environment(SB.ENV_URL, " ")
	var em0: bool = Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch = true
	var tm0: bool = GameState.test_mode
	var ta0: bool = GameState.tutorial_active
	GameState.test_mode = true
	GameState.tutorial_active = false
	get_tree().root.size = Vector2i(1280, 720)
	await _frames(2)
	_xf = get_tree().root.get_final_transform()
	_cap = _Cap.new()
	OS.add_logger(_cap)

	await _part_engine()
	await _part_board()
	await _part_settings()
	_part_static()

	## Logger 的分母: 它真收得到引擎报错(不然上面「0 条」是空检查)
	var tag := "gate-touch-detach-probe %d" % Time.get_ticks_usec()
	push_error(tag)
	await _frames(1)
	var got := false
	for m in _cap.msgs:
		got = got or str(m).find(tag) >= 0
	OS.remove_logger(_cap)
	_ok("★分母: Logger 真收得到引擎报错", got)

	Input.emulate_mouse_from_touch = em0
	GameState.test_mode = tm0
	GameState.tutorial_active = ta0
	if had_env:
		OS.set_environment(SB.ENV_URL, env0)
	else:
		OS.unset_environment(SB.ENV_URL)
	print("")
	print("  (共 %d 条断言 · 用了 %d 帧)" % [_n, Engine.get_process_frames()])
	print("ALL PASS — 手指抬起时被按的控件还在树上" if _fail == 0 and _n >= 18 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────── ① 引擎机理 ───────────────────────────────
## 一层高 CanvasLayer(常驻层盖在第 0 层上) > holder > 按钮; 点按钮 ⇒ 按 kind 处理 holder。
func _case(kind: String) -> Dictionary:
	var layer := CanvasLayer.new()
	layer.layer = 120
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(1280, 720)
	var b := Button.new()
	b.text = kind
	b.position = Vector2(540, 300)
	b.size = Vector2(200, 100)
	holder.add_child(b)
	layer.add_child(holder)
	get_tree().root.add_child(layer)
	var fired := [0]
	## detach = 摘下树、不释放(列表重建 / 同步换场景同一形状); deferred = 延后到这一帧输入派发完; queue_free = 只排释放, 帧尾才离树
	b.pressed.connect(func() -> void:
		fired[0] += 1
		if kind == "detach":
			layer.remove_child(holder)
		elif kind == "deferred":
			layer.remove_child.call_deferred(holder)
		else:
			holder.queue_free())
	await _frames(2)
	var c0 := _cap.count()
	var m0: int = _cap.msgs.size()
	var on := await _tap(b.get_global_rect().get_center(), b)
	await _frames(2)
	var res := {"on": on, "fired": int(fired[0]), "rel": _rel, "errs": _cap.count() - c0}
	if _let_err:
		print("    [GATE_LET_ENGINE_ERR] %s 那一下引擎原文: %s" % [kind, str(_cap.msgs.slice(m0))])
	_watch = null
	if is_instance_valid(holder) and holder.get_parent() == null:
		holder.free()
	if is_instance_valid(layer):
		layer.queue_free()
	await _frames(2)
	return res


func _part_engine() -> void:
	var bad := await _case("detach")
	var dfr := await _case("deferred")
	var qf := await _case("queue_free")
	_ok("① 分母: 三种写法手指都真点到了按钮(按下命中它、pressed 发了一次)",
		bad["on"] and dfr["on"] and qf["on"] and int(bad["fired"]) == 1 and int(dfr["fired"]) == 1 and int(qf["fired"]) == 1,
		"摘下=%s 延后=%s 只释放=%s" % [str(bad), str(dfr), str(qf)])
	_ok("★① 分母: 回调里摘下树不释放 ⇒ 触摸抬起到达时被按的按钮已离树(正式服那条报错的前提, 本机复现)",
		int(bad["rel"]) == 1, str(bad))
	_ok("★① 延后摘 ⇒ 抬起时按钮还在树上、Logger 0 条", int(dfr["rel"]) == 0 and int(dfr["errs"]) == 0, str(dfr))
	_ok("★① 只 queue_free ⇒ 抬起时按钮还在树上、Logger 0 条", int(qf["rel"]) == 0 and int(qf["errs"]) == 0, str(qf))


# ─────────────────────────────── ② 赛况板 ───────────────────────────────
func _part_board() -> void:
	var r: Node = (load(BOARD) as PackedScene).instantiate()
	get_tree().root.add_child(r)
	get_tree().current_scene = r
	await _frames(4)
	var rows: Array = []
	for i in range(8):
		var j := (i + 1) % 8
		var lp := {"name": "龟%02d" % i, "tag": P2C.player_tag("acct:touch%d" % i), "avatar": "basic", "id": "g_x"}
		var rp := {"name": "龟%02d" % j, "tag": P2C.player_tag("acct:touch%d" % j), "avatar": "basic", "id": "g_x"}
		rows.append({"match_id": "%08x-0000-4000-8000-%012x" % [i + 1, i + 1],
			"created_at": "2026-10-31T10:%02d:00+00:00" % i, "lp": lp, "rp": rp, "rw": i % 3, "rl": i % 2,
			"result": {"won": i % 2 == 0, "steps": 100, "surrendered": false, "gw": 1 + i % 4, "gl": i % 3}})
	r.call("set_rows", rows)
	await _frames(3)
	var btn: Button = null
	for c in r.find_children("PlayerBtn", "Button", true, false):
		var cb := c as Button
		var rc: Rect2 = cb.get_global_rect().intersection(get_viewport().get_visible_rect())
		if cb.is_visible_in_tree() and rc.size.y > 20.0:
			btn = cb
			break
	_ok("② 分母: 赛况板左栏有选手行(PlayerBtn)", btn != null, "%d 行" % r.find_children("PlayerBtn", "Button", true, false).size())
	if btn == null:
		_cleanup_scene(r)
		await _frames(2)
		return
	var want := str(btn.get_meta("key", ""))
	var c0 := _cap.count()
	var on := await _tap(btn.get_global_rect().intersection(get_viewport().get_visible_rect()).get_center(), btn)
	await _frames(3)
	var errs := _cap.count() - c0
	_ok("② 分母: 手指按下真命中这一行的按钮", on)
	_ok("★★② 手指点选手行 ⇒ 触摸抬起到达时那颗按钮还在树上", _rel == 0, "rel=%d" % _rel)
	_ok("★★② 手指点选手行 ⇒「!is_inside_tree() @ can_process」0 条", errs == 0, "%d 条" % errs)
	_ok("② 点一下仍是点: 右栏换成了这个人的对局", want != "" and str(r.get("focus_tag")) == want,
		"focus_tag=%s 期望 %s" % [str(r.get("focus_tag")), want])
	_watch = null
	_cleanup_scene(r)
	await _frames(2)


# ─────────────────────────────── ③ 设置页存档冲突 ───────────────────────────────
func _part_settings() -> void:
	var r: Node = (load(SETTINGS) as PackedScene).instantiate()
	get_tree().root.add_child(r)
	get_tree().current_scene = r
	await _frames(4)
	r.call("_open_conflict_dialog")
	await _frames(2)
	var btn: Button = null
	var layer = r.get("_confirm_layer")
	if layer is Node and is_instance_valid(layer):
		for c in (layer as Node).find_children("*", "Button", true, false):
			if str((c as Button).text) == BTN_USE_LOCAL:
				btn = c
				break
	_ok("③ 分母: 设置页弹出了存档冲突框、找到「%s」" % BTN_USE_LOCAL, btn != null)
	if btn == null:
		_cleanup_scene(r)
		await _frames(2)
		return
	var c0 := _cap.count()
	var m0: int = _cap.msgs.size()
	var on := await _tap(btn.get_global_rect().get_center(), btn)
	await _frames(4)
	var errs := _cap.count() - c0
	if _let_err:
		print("    [GATE_LET_ENGINE_ERR] 设置页那一下引擎原文: %s" % str(_cap.msgs.slice(m0)))
	var cs := get_tree().current_scene
	_ok("③ 分母: 手指按下真命中这颗按钮", on)
	_ok("★★③ 点「%s」⇒ 触摸抬起到达时按钮还在树上" % BTN_USE_LOCAL, _rel == 0, "rel=%d" % _rel)
	_ok("★★③ 点「%s」⇒「!is_inside_tree() @ can_process」0 条" % BTN_USE_LOCAL, errs == 0, "%d 条" % errs)
	_ok("③ 设置页照样重开了(当前场景换成一份新的设置页)",
		cs != null and cs != r and str(cs.scene_file_path) == SETTINGS, "current=%s" % (str(cs.scene_file_path) if cs != null else "null"))
	_watch = null
	if is_instance_valid(r):
		_cleanup_scene(r)
	if cs != null and cs != r and is_instance_valid(cs):
		_cleanup_scene(cs)
	get_tree().current_scene = self
	await _frames(3)


func _cleanup_scene(n: Node) -> void:
	if is_instance_valid(n):
		n.queue_free()
	if get_tree().current_scene == n:
		get_tree().current_scene = self


# ─────────────────────────────── ④ 静态 ───────────────────────────────
func _part_static() -> void:
	var raw: Array = []
	var seen_ok := {}
	for f in _gd_files("res://scripts/scenes"):
		var ln := 0
		for line in FileAccess.get_file_as_string(f).split("\n"):
			ln += 1
			var t := line.strip_edges()
			if t.begins_with("#"):
				continue
			var code := t.split("#", true, 1)[0]
			if code.find("reload_current_scene(") < 0:
				continue
			if RELOAD_OK.has(f):
				seen_ok[f] = int(seen_ok.get(f, 0)) + 1
			else:
				raw.append("%s:%d" % [f, ln])
	_ok("★★④ scripts/scenes 里没有登记外的 reload_current_scene(换场景一律 SceneNav.go)", raw.is_empty(), str(raw))
	for f in RELOAD_OK:
		_ok("④ 放行名单仍在用(不在了 ⇒ 把这一条删掉): %s" % f, int(seen_ok.get(f, 0)) > 0, "%d 处" % int(seen_ok.get(f, 0)))


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
