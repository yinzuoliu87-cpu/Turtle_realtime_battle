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
##   ⑤ 正式服探针(2026-11-01): 上报器自己认得出「按下的是哪一颗」—— 那条引擎报错没有脚本栈, 本机又复现不出剩下的出处
##      (新号开局 18~26 秒内报上来的两条, 当时的界面本机全屏点遍了都量不到), 只能让正式服下次报的时候把出处带上来:
##      手指先离开、再直接按下(不先移过去, 同真机)⇒ 回调里摘下树 ⇒ 抬起到达时上报器记下的 = 被按那颗**按下那一刻**的路径;
##      把引擎那条报错原样喂给上报器 ⇒ 那一行详情附上这条路径、签名按它算(不同出处各一行)、场景 = 报错那一刻的(不是清队列那一刻的);
##      上报器只读不吞(排在它后面的节点照样收到这次抬起)。
##   ⑥ 主菜单周六排队态(2026-11-01 读码找到的同一形状, 0.22.6 起才有这颗): 排队态主按钮与左侧取消键都在 page_box 里,
##      `MenuQueue.refresh()` 一重建就把 page_box 整排 remove_child。两条路在按钮回调里同步走到它:
##      a 取消键 → 会话 cancel_queue 当场出队(发不出取消请求时 `_to(ST_LEFT)`)→ changed → refresh;
##      b 会话没发信号就没了(R7)时点主按钮 → `_on_hero_tap` → refresh。
##      ⇒ 真手指点 ⇒ 抬起到达时那颗还在树上、Logger 0 条、之后照样重建成「开始战斗」。
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
const RUN := preload("res://scripts/systems/replay/referee_run.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
## 钉在周六闯关赛(排队态只在这一天出现; 与 verify_gauntlet_queue_menu 同一刻)
const PIN_SAT_TS := 1789603200 + 2 * 86400 + 10 * 3600

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
## ⑤ 用: 本测试自己的 `_input` 不吞(它排在上报器的 _Watch 前面, 吞了 _Watch 就看不到这次抬起), 改由根上第 0 个节点吞
var _late_swallow := false

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
	if gone and not _let_err and not _late_swallow:
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
	await _part_reporter()
	await _part_menu_queue()
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
	print("ALL PASS — 手指抬起时被按的控件还在树上" if _fail == 0 and _n >= 36 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
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


# ─────────────────────────────── ⑤ 正式服探针 ───────────────────────────────
## 根上第 0 个: `_input` 按树序倒着调 ⇒ 它在所有自动加载(含上报器的 _Watch)之后、GUI 之前 —— 在这里吞, 上报器已经看过这次抬起。
class _Swallow extends Node:
	var watch: Control = null
	var seen_release := 0
	func _input(event: InputEvent) -> void:
		var rel: bool = event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed
		if not (rel or event is InputEventScreenDrag):
			return
		if rel:
			seen_release += 1
		if watch != null and is_instance_valid(watch) and not watch.is_inside_tree():
			get_viewport().set_input_as_handled()


func _part_reporter() -> void:
	var r: ErrorReporter = ErrorReporter.instance()
	_ok("⑤ 分母: GameState 开机装上了上报器", r != null)
	if r == null:
		return
	var sw := _Swallow.new()
	get_tree().root.add_child(sw)
	get_tree().root.move_child(sw, 0)
	_late_swallow = true
	var layer := CanvasLayer.new()
	layer.layer = 120
	var holder := Control.new()
	holder.name = "ProbeHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(1280, 720)
	var b := Button.new()
	b.name = "ProbeBtn"
	b.position = Vector2(540, 300)
	b.size = Vector2(200, 100)
	holder.add_child(b)
	layer.add_child(holder)
	get_tree().root.add_child(layer)
	var fired := [0]
	b.pressed.connect(func() -> void:
		fired[0] += 1
		layer.remove_child(holder))
	await _frames(3)
	var want := ErrorReporter.path_text(str(b.get_path()))
	sw.watch = b
	## 手指先在别处(不离开视口), 再直接按在按钮上 —— 不先移过去: 真机上手指按下之前没有悬停
	_hover(Vector2(4, 4))
	var p := b.get_global_rect().get_center()
	var t := InputEventScreenTouch.new(); t.index = 0; t.pressed = true; t.position = _xf * p
	await _ev(t)
	var u := InputEventScreenTouch.new(); u.index = 0; u.pressed = false; u.position = _xf * p
	await _ev(u)
	var stash: String = ErrorReporter._touch_gone
	_ok("⑤ 分母: 手指直接按下(没先悬停)也真点到了按钮、回调里摘下了树", int(fired[0]) == 1 and not b.is_inside_tree(), "pressed=%d" % int(fired[0]))
	_ok("★★⑤ 抬起到达时上报器记下的 = 被按那颗按下那一刻的路径", stash == want and want != "", "记下 %s / 期望 %s" % [stash, want])
	_ok("⑤ 上报器只读不吞: 排在它后面的节点照样收到这次抬起", sw.seen_release == 1, "%d 次" % sw.seen_release)
	## 引擎那条报错紧跟着来; 门禁里不能真让它打出来(致命正则认 `Condition ".*" is true`)⇒ 照原文直接喂给上报器
	r.drain("")
	var no_bt: Array[ScriptBacktrace] = []
	var code := 'Condition "!is_inside_tree()" is true. Returning: false'
	r._log_error("can_process", "scene/main/node.cpp", 902, code, "", false, Logger.ERROR_TYPE_ERROR, no_bt)
	var rows: Array = r.drain("Later.tscn")
	var here := str(scene_file_path).get_file()
	_ok("⑤ 分母: 喂进去的那条排进了队列", rows.size() == 1, str(rows.size()))
	if rows.size() == 1:
		_ok("★★⑤ 那一行详情附上了按下的控件", str(rows[0]["p_detail"]).find(ErrorReporter.TOUCH_TAG + want) >= 0, str(rows[0]["p_detail"]).right(160))
		_ok("★⑤ 签名按按下的控件算(不同出处各占一行)", str(rows[0]["p_sig"]) == ErrorReporter.sig_of("", 0, "", want), str(rows[0]["p_sig"]))
		_ok("★⑤ 场景是报错那一刻的(%s), 不是清队列那一刻的 Later.tscn" % here, str(rows[0]["p_scene"]) == here, str(rows[0]["p_scene"]))
	## 同一处再报 ⇒ 不再排; 换一处 ⇒ 另排一行
	ErrorReporter._note_touch_gone(want)
	r._log_error("can_process", "scene/main/node.cpp", 902, code, "", false, Logger.ERROR_TYPE_ERROR, no_bt)
	ErrorReporter._note_touch_gone(want + "/Other")
	r._log_error("can_process", "scene/main/node.cpp", 902, code, "", false, Logger.ERROR_TYPE_ERROR, no_bt)
	var rows2: Array = r.drain("Later.tscn")
	_ok("⑤ 同一处再报不再排、换一处另排一行", rows2.size() == 1 and str(rows2[0]["p_detail"]).find(want + "/Other") >= 0, str(rows2.size()))
	## 正常的一下(回调里不摘树)⇒ 不记
	var b2 := Button.new()
	b2.position = Vector2(540, 300)
	b2.size = Vector2(200, 100)
	var layer2 := CanvasLayer.new()
	layer2.layer = 120
	layer2.add_child(b2)
	get_tree().root.add_child(layer2)
	await _frames(3)
	_hover(Vector2(4, 4))
	var t2 := InputEventScreenTouch.new(); t2.index = 0; t2.pressed = true; t2.position = _xf * p
	await _ev(t2)
	var u2 := InputEventScreenTouch.new(); u2.index = 0; u2.pressed = false; u2.position = _xf * p
	await _ev(u2)
	_ok("⑤ 反面: 回调里不摘树 ⇒ 上报器不记", ErrorReporter._touch_gone == "", ErrorReporter._touch_gone)
	_late_swallow = false
	sw.queue_free()
	if is_instance_valid(holder) and holder.get_parent() == null:
		holder.free()
	layer.queue_free()
	layer2.queue_free()
	await _frames(2)


# ─────────────────────────────── ⑥ 主菜单排队态 ───────────────────────────────
## 快点一下: 按下与抬起同一帧到(真机上快点就是这样)⇒ 中间没有一次 `_process` 能先把这颗重建掉 ——
##   要量的正是「抬起那一下的回调里当场重建」, 不是「两帧之间别处顺手重建了」(那样旧的帧末已释放, 引擎取不回它, 不报)。
func _tap_one_frame(p: Vector2, target: Control) -> bool:
	var h := _hover(p)
	var on: bool = h != null and (h == target or target.is_ancestor_of(h))
	_watch = h
	_rel = -1
	var t := InputEventScreenTouch.new(); t.index = 0; t.pressed = true; t.position = _xf * p
	var u := InputEventScreenTouch.new(); u.index = 0; u.pressed = false; u.position = _xf * p
	Input.parse_input_event(t)
	Input.parse_input_event(u)
	Input.flush_buffered_events()
	await get_tree().process_frame
	return on


## 假会话: 有 changed / state / cell / waited_now() / cancel_queue()(同 verify_gauntlet_queue_menu 的 FakeRun)。
## cancel_queue 照 referee_run 发不出取消请求那一支: 当场 `_to(ST_LEFT)` = 改状态 + 发 changed。
class _FakeRun extends Node:
	signal changed
	var state := ""
	var cell := Vector2i(2, 1)
	var t0 := 0

	func waited_now() -> int:
		return 64 + (Time.get_ticks_msec() - t0) / 1000

	func cancel_queue() -> bool:
		state = "left"
		changed.emit()
		return true


func _menu_with_queue() -> Array:
	var f := _FakeRun.new()
	f.state = RW.ST_QUEUE
	f.t0 = Time.get_ticks_msec()
	add_child(f)
	RUN.active = f
	var m: Control = load("res://scenes/MainMenu.tscn").instantiate()
	m.clock_override_ts = PIN_SAT_TS
	get_tree().root.add_child(m)
	m.set_anchors_preset(Control.PRESET_TOP_LEFT)
	m.size = Vector2(1280, 720)
	get_tree().current_scene = m
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2400:      # 入场滑入落定(同 verify_gauntlet_queue_menu: 0.85 + 0.06×5 + 0.42 秒)
		OS.delay_msec(40)
		await get_tree().process_frame
	var qh: Control = m.page_box.get_node_or_null(MenuQueue.N_HERO) as Control if m.page_box != null else null
	return [f, m, qh]


func _drop_menu(f: Node, m: Node) -> void:
	RUN.active = null
	RW.notice = ""
	if is_instance_valid(f):
		f.queue_free()
	if is_instance_valid(m):
		m.queue_free()
	get_tree().current_scene = self
	await _frames(3)


func _part_menu_queue() -> void:
	var gs = get_node_or_null("/root/GameState")
	var keys := ["season_total_battles", "season_id", "hearts", "ranked_used", "onboarded", "season_leaders",
		"season_wins", "promoted", "gauntlet_wins", "gauntlet_losses", "battles_total"]
	var bak := {}
	for k in keys:
		var v = gs.get(k)
		bak[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	gs.season_total_battles = 3; gs.season_id = 2; gs.hearts = 5; gs.ranked_used = 0; gs.onboarded = true
	gs.season_leaders = ["phoenix", "pirate", "ninja"]; gs.season_wins = 12; gs.promoted = true
	gs.gauntlet_wins = 2; gs.gauntlet_losses = 1
	gs.battles_total = 5                          # 打过几场 ⇒ 不出「本周赛程」首次说明(它整页压暗盖住主菜单, 手指点不到主按钮)
	## a: 取消键 → 会话当场出队
	var a := await _menu_with_queue()
	var qh: Control = a[2]
	_ok("⑥ 分母: 排队中进主菜单 ⇒ 主按钮是排队态", qh != null)
	if qh != null:
		var ck: Control = qh.get_node_or_null(MenuQueue.N_CANCEL) as Control
		var c0 := _cap.count()
		var on := await _tap(ck.get_global_rect().get_center(), ck) if ck != null else false
		await _frames(4)
		var errs := _cap.count() - c0
		_ok("⑥a 分母: 手指按下真命中取消键", on)
		_ok("★★⑥a 点取消键(会话当场出队)⇒ 抬起到达时取消键还在树上", _rel == 0, "rel=%d" % _rel)
		_ok("★★⑥a 点取消键 ⇒「!is_inside_tree() @ can_process」0 条", errs == 0, "%d 条" % errs)
		_ok("⑥a 之后照样重建成「开始战斗」(排队态没了)", (a[1] as Node).get("page_box") != null
			and ((a[1] as Node).get("page_box") as Node).get_node_or_null(MenuQueue.N_HERO) == null)
	_watch = null
	await _drop_menu(a[0], a[1])
	## b: 会话没发信号就没了(R7)时点主按钮
	var b := await _menu_with_queue()
	var qh2: Control = b[2]
	_ok("⑥ 分母: 第二次进主菜单仍是排队态", qh2 != null)
	if qh2 != null:
		var tick := (b[1] as Node).get_node_or_null(MenuQueue.N_TICK) as Timer
		if tick != null:
			tick.paused = true                    # 不让 0.25 秒那一拍抢在手指前面把主按钮重建掉(要量的就是这个空当)
		(b[0] as _FakeRun).state = "left"         # 没发 changed
		var hp := qh2.get_global_rect()
		var p := Vector2(hp.position.x + hp.size.x * 0.72, hp.get_center().y)
		var ck2: Control = qh2.get_node_or_null(MenuQueue.N_CANCEL) as Control
		var hh := _hover(p)
		var not_ck: bool = ck2 == null or hh == null or not (hh == ck2 or ck2.is_ancestor_of(hh))
		var c1 := _cap.count()
		var on2 := await _tap_one_frame(p, qh2)
		await _frames(4)
		var errs2 := _cap.count() - c1
		_ok("⑥b 分母: 手指按下真命中主按钮排队态(不是取消键)", on2 and not_ck)
		_ok("★★⑥b 会话没了时点主按钮 ⇒ 抬起到达时那颗还在树上", _rel == 0, "rel=%d" % _rel)
		_ok("★★⑥b 会话没了时点主按钮 ⇒「!is_inside_tree() @ can_process」0 条", errs2 == 0, "%d 条" % errs2)
		_ok("⑥b 之后照样重建成「开始战斗」", ((b[1] as Node).get("page_box") as Node).get_node_or_null(MenuQueue.N_HERO) == null)
		if tick != null and is_instance_valid(tick):
			tick.paused = false
	_watch = null
	await _drop_menu(b[0], b[1])
	for k in keys:
		gs.set(k, bak[k])


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
