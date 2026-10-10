extends Node
## verify_scored_match_keys —— 计分对局里 ESC / R 不许把这一局抹掉(2026-10-10 周六 60 人实操查实)。
##
## 原来 `_unhandled_input` 里 R = `reload_current_scene()`、ESC = 回主菜单, **不分场合** ⇒
## PC / Mac 包上积分赛劣势按 ESC 就逃掉一条命、周六逃掉一负(结算只在打完时记)。
## 用户 2026-07-30 拍板: 认输 = 整场负, 不许直接回主菜单。
## ⇒ 计分对局没打完时: ESC = 弹认输确认(再按一次收起), R 不响应。非计分(没阵容 / 教程 / 回放)照旧。
## ★发的是**真按键事件**进 `_unhandled_input`(真入口), 不是直接调我加的判据。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _key(scene: Node, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	scene._unhandled_input(ev)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	_ok("分母: GameState 在", gs != null)
	if gs == null:
		get_tree().quit(1)
		return
	gs.test_mode = true
	var leaders0 = gs.season_leaders.duplicate() if gs.season_leaders is Array else []
	var tut0 := bool(gs.get("tutorial_active"))
	gs.season_leaders = ["basic", "stone", "ice"]
	gs.tutorial_active = false

	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	scene.set_process(false)
	scene.set_physics_process(false)
	var cur0 := get_tree().current_scene

	_ok("分母: 有阵容、非教程、非回放 ⇒ 计分对局", scene._world_builder._is_scored_match())
	_ok("分母: 认输框已建且默认收着", scene._surrender_panel != null and not scene._surrender_panel.visible)

	_key(scene, KEY_ESCAPE)
	await get_tree().process_frame
	_ok("★计分对局按 ESC ⇒ 不退场, 弹认输确认", is_instance_valid(scene) and scene.is_inside_tree()
		and get_tree().current_scene == cur0 and scene._surrender_panel.visible)
	_ok("★按 ESC 不结算(_over / _settled 仍 false)", not scene._over and not scene._settled)
	_key(scene, KEY_ESCAPE)
	await get_tree().process_frame
	_ok("框开着再按 ESC ⇒ 收起(= 取消)", not scene._surrender_panel.visible and not scene._settled)

	## R: 原来是 reload_current_scene() —— 在这里 current_scene 就是本测试, 变异回去会把测试自己重载掉(⇒ 不打 ALL PASS = 红)。
	_key(scene, KEY_R)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("★计分对局按 R ⇒ 不重开", is_instance_valid(scene) and scene.is_inside_tree() and get_tree().current_scene == cur0)

	## 非计分: 判据必须跟着变(否则调试场 / 演示里 R、ESC 全废)。
	gs.season_leaders = []
	_ok("没阵容 ⇒ 非计分", not scene._world_builder._is_scored_match())
	gs.season_leaders = ["basic", "stone", "ice"]
	gs.tutorial_active = true
	_ok("教程 ⇒ 非计分", not scene._world_builder._is_scored_match())
	gs.tutorial_active = false

	scene.queue_free()
	gs.season_leaders = leaders0
	gs.tutorial_active = tut0
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 计分对局 ESC/R 不抹局")
	get_tree().quit(1 if _fail > 0 else 0)
