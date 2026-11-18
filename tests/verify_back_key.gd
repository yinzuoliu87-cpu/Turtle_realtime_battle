extends Node
## verify_back_key — 安卓返回键 / 返回手势不再直接退出游戏, 而是一层层退回(方案书 20261118b A5, scripts/util/back_key.gd)。
##
## 量的是活节点, 不是源码里找字:
##   ① project.godot 关掉了 quit_on_go_back(不关 ⇒ 引擎收到返回请求当场退出, 下面全白做);
##   ② 真走 GameState 收通知那条路(propagate_notification): 一条返回请求 ⇒ 恰好处理一次;
##   ③ 每个有返回键的页: 返回 ⇒ 恰好换屏一次、去的是那一页返回键去的地方(换屏走 SceneNav.nav_for_test 截下);
##      有 Esc 返回的页(①)与只有顶栏返回键的页(②)都要恰好一次 —— 两家都接 = 连跳两屏;
##   ④ 主菜单: 返回 ⇒ 弹「退出游戏」; 再按 ⇒ 关掉; 点「退出」⇒ 退出(quit_for_test 截下), 不真退;
##   ⑤ 优先级: ui_cancel 有人接 ⇒ 不再按按钮; 多枚记号按钮按树序最后那枚; 隐藏 / 禁用的不算; 同一帧第二次丢掉;
##   ⑥ 回放「退出」/ 确认框「继续观看」/ 结算「返回主菜单」打了记号(这几处要整局对战才建得出来, 退一步查源码)。

const MENU := "res://scenes/MainMenu.tscn"
const EXIT := preload("res://scripts/scenes/exit_confirm_dialog.gd")

## 页面 → 返回键去哪。
const PAGES := {
	"Record": MENU, "Settings": MENU, "Leaderboard": MENU, "Inventory": MENU, "Codex": MENU, "Shop": MENU,
	"Friends": MENU, "GauntletBoard": MENU, "TrainerConfig": MENU, "BracketMap": MENU, "TeamSelect": MENU,
}

var _pass := 0
var _fail := 0
var _navs: Array = []


func _ok(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [label, extra])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [label, extra])


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	SceneNav.nav_for_test = func(p: String) -> void: _navs.append(p)
	EXIT.quit_for_test = Callable()

	print("— ① 引擎设置")
	_ok("application/config/quit_on_go_back = false", ProjectSettings.get_setting("application/config/quit_on_go_back", true) == false)

	print("— ⑤ 优先级(合成节点)")
	await _priority()

	print("— ② 通知那条路(GameState)")
	await _notification_path()

	print("— ③ 每个有返回键的页")
	var n_pages := 0
	for scn in PAGES:
		var path := "res://scenes/%s.tscn" % scn
		if not ResourceLoader.exists(path):
			_ok("场景 %s 在" % scn, false)
			continue
		var inst: Node = (load(path) as PackedScene).instantiate()
		add_child(inst)
		await _frames(40)
		_navs.clear()
		await _frames(1)
		var how := BackKey.handle(get_tree(), inst)
		await _frames(3)
		_ok("%s: 返回 ⇒ 恰好换屏一次、去 %s" % [scn, str(PAGES[scn]).get_file()],
			_navs.size() == 1 and _navs[0] == PAGES[scn], "走了 %s, 换屏 %s" % [how, str(_navs)])
		n_pages += 1
		inst.queue_free()
		await _frames(3)
	_ok("[分母] 量了 %d 页" % n_pages, n_pages == PAGES.size())

	print("— ④ 主菜单")
	await _main_menu()

	print("— ⑥ 记号(源码)")
	_static_tags()

	SceneNav.nav_for_test = Callable()
	EXIT.quit_for_test = Callable()
	print("[分母] %d 条断言" % (_pass + _fail))
	if _fail == 0 and _pass >= 25:
		print("ALL PASS — verify_back_key %d 条" % _pass)
	else:
		print("FAIL %d / %d" % [_fail, _pass + _fail])
	get_tree().quit()


func _tagged(nm: String, host: Node) -> Button:
	var b := Button.new()
	b.name = nm
	b.size = Vector2(80, 80)
	BackKey.tag(b)
	host.add_child(b)
	return b


func _priority() -> void:
	var host := Control.new()
	host.name = "PrioHost"
	add_child(host)
	var hits := {"A": 0, "B": 0, "C": 0}
	var a := _tagged("A", host)
	var b := _tagged("B", host)
	a.pressed.connect(func() -> void: hits["A"] += 1)
	b.pressed.connect(func() -> void: hits["B"] += 1)
	await _frames(1)
	var how := BackKey.handle(get_tree(), host)
	_ok("两枚记号按钮 ⇒ 按树序最后那枚(B), A 不动", how == BackKey.R_BUTTON and hits["B"] == 1 and hits["A"] == 0, str(hits))
	_ok("同一帧第二次 ⇒ 丢掉", BackKey.handle(get_tree(), host) == BackKey.R_DUP and hits["B"] == 1)
	b.visible = false
	await _frames(1)
	BackKey.handle(get_tree(), host)
	_ok("B 隐藏 ⇒ 按 A", hits["A"] == 1 and hits["B"] == 1, str(hits))
	b.visible = true
	b.disabled = true
	await _frames(1)
	BackKey.handle(get_tree(), host)
	_ok("B 禁用 ⇒ 按 A", hits["A"] == 2 and hits["B"] == 1, str(hits))
	var untagged := Button.new()
	host.add_child(untagged)
	untagged.pressed.connect(func() -> void: hits["C"] += 1)
	await _frames(1)
	BackKey.handle(get_tree(), host)
	_ok("没打记号的按钮(树序更靠后)不按", hits["C"] == 0 and hits["A"] == 3, str(hits))
	## ui_cancel 有人接(并标记已处理) ⇒ 不再按按钮
	var eater := Node.new()
	var sc := GDScript.new()
	sc.source_code = "extends Node\nvar n := 0\nfunc _unhandled_input(e: InputEvent) -> void:\n\tif e.is_action_pressed(\"ui_cancel\"):\n\t\tn += 1\n\t\tget_viewport().set_input_as_handled()\n"
	sc.reload()
	eater.set_script(sc)
	host.add_child(eater)
	await _frames(1)
	how = BackKey.handle(get_tree(), host)
	_ok("ui_cancel 有人接 ⇒ 走 ①、记号按钮不按", how == BackKey.R_CANCEL and eater.get("n") == 1 and hits["A"] == 3,
		"%s n=%s %s" % [how, str(eater.get("n")), str(hits)])
	eater.queue_free()
	## ui_cancel 的接收方没标记已处理、但换了屏 ⇒ 也算接了(老页面的 Esc 返回都是这样写的)
	var nav_eater := Node.new()
	var sc2 := GDScript.new()
	sc2.source_code = "extends Node\nfunc _unhandled_input(e: InputEvent) -> void:\n\tif e.is_action_pressed(\"ui_cancel\"):\n\t\tSceneNav.go(get_tree(), \"res://scenes/MainMenu.tscn\")\n"
	sc2.reload()
	nav_eater.set_script(sc2)
	host.add_child(nav_eater)
	await _frames(1)
	_navs.clear()
	how = BackKey.handle(get_tree(), host)
	_ok("ui_cancel 接收方换了屏(没标记已处理) ⇒ 算 ①、记号按钮不按", how == BackKey.R_CANCEL and _navs.size() == 1 and hits["A"] == 3,
		"%s %s" % [how, str(_navs)])
	host.queue_free()
	await _frames(2)
	## 什么都没有 ⇒ 什么都不做
	var bare := Node.new()
	add_child(bare)
	await _frames(1)
	_ok("没有记号按钮、场景也不处理 ⇒ none(对局中 / 首次进入: 不退出、不跳走)", BackKey.handle(get_tree(), bare) == BackKey.R_NONE)
	bare.queue_free()
	await _frames(1)


func _notification_path() -> void:
	var host := Control.new()
	add_child(host)
	var hits := [0]
	var b := _tagged("N", host)
	b.pressed.connect(func() -> void: hits[0] += 1)
	await _frames(1)
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(3)
	_ok("GameState 收到返回请求 ⇒ 按了一次记号按钮", hits[0] == 1, str(hits))
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(3)
	_ok("同一帧两条返回请求(实体键 + 手势) ⇒ 只处理一次", hits[0] == 2, str(hits))
	host.queue_free()
	await _frames(2)


func _main_menu() -> void:
	var inst: Node = (load(MENU) as PackedScene).instantiate()
	add_child(inst)
	await _frames(40)
	_navs.clear()
	var quits := [0]
	EXIT.quit_for_test = func() -> void: quits[0] += 1
	_ok("主菜单: 一开始没有退出框", not EXIT.is_open(inst))
	var how := BackKey.handle(get_tree(), inst)
	await _frames(2)
	_ok("主菜单: 返回 ⇒ 弹「退出游戏」、不换屏", how == BackKey.R_SCENE and EXIT.is_open(inst) and _navs.is_empty(),
		"%s %s" % [how, str(_navs)])
	var layer: Node = inst.get_node_or_null(EXIT.LAYER)
	var ttl: Label = layer.find_child(EXIT.TITLE, true, false) if layer != null else null
	_ok("退出框标题 =「%s」" % EXIT.T_TITLE, ttl != null and ttl.text == EXIT.T_TITLE)
	how = BackKey.handle(get_tree(), inst)
	await _frames(2)
	_ok("主菜单: 开着退出框再按返回 ⇒ 关掉(按的是「取消」)、没退出", how == BackKey.R_BUTTON and not EXIT.is_open(inst) and quits[0] == 0,
		"%s quits=%d" % [how, quits[0]])
	BackKey.handle(get_tree(), inst)
	await _frames(2)
	layer = inst.get_node_or_null(EXIT.LAYER)
	var ok_btn: Button = layer.find_child(EXIT.BTN_OK, true, false) if layer != null else null
	_ok("退出框里有「%s」键" % EXIT.L_OK, ok_btn != null and ok_btn.text == EXIT.L_OK)
	if ok_btn != null:
		ok_btn.pressed.emit()
	_ok("点「退出」⇒ 退出一次", quits[0] == 1, str(quits))
	EXIT.quit_for_test = Callable()
	inst.queue_free()
	await _frames(3)


func _static_tags() -> void:
	var rc := FileAccess.get_file_as_string("res://scripts/scenes/battle/replay_controls.gd")
	_ok("回放「退出」键打了记号(两处建法都打)", rc.count("BackKey.tag(exit_btn)") >= 2, str(rc.count("BackKey.tag(exit_btn)")))
	_ok("回放退出确认框「继续观看」打了记号", rc.find("BackKey.tag(stay)") >= 0)
	var hud := FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_hud.gd")
	_ok("结算「返回主菜单」打了记号", hud.find("BackKey.tag(mb)") >= 0)
