extends Node
## verify_scored_match_keys —— 计分对局里 ESC / R 不许把这一局抹掉(2026-10-10 周六 60 人实操查实)。
##
## 原来 `_unhandled_input` 里 R = `reload_current_scene()`、ESC = 回主菜单, **不分场合** ⇒
## PC / Mac 包上积分赛劣势按 ESC 就逃掉一条命、周六逃掉一负(结算只在打完时记)。
## 用户 2026-07-30 拍板: 认输 = 整场负, 不许直接回主菜单。
## ⇒ 计分对局没打完时: ESC = 弹认输确认(再按一次收起), R 不响应。非计分(没阵容 / 教程 / 回放)照旧。
## ★★2026-10-19 用户「投降不要了」: 认输整个删了 ⇒ ESC 不再拦, 走老路回主菜单(不留一个按了没反应的键)。
##   这一局不会被抹掉: 开局那一刻已落了待结算单(`AbandonedMatch`), 主菜单一进来就把它按正常规则打完结算
##   (用户 2026-10-10「学习他们的做法」: 退出不作废、也不直接判负; 那一条由 verify_abandoned_match 守)。
##   R 仍然不响应(重开 = 新开一局, 待结算单被覆盖 = 抹局)。
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
	_ok("★认输键 / 认输框不存在(2026-10-19 删)", scene.get("_surrender_panel") == null and scene.get("_surrender_btn") == null)
	_ok("★计分对局: 键盘守卫不拦 ESC(走老路回主菜单)、只拦 R",
		not scene._world_builder._scored_key_guard(KEY_ESCAPE) and scene._world_builder._scored_key_guard(KEY_R))

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

	## ★ESC 真按键走到底: 战斗场换成当前场景(换场景只会释放它, 不释放本测试), 按 ESC ⇒ 去了主菜单。
	remove_child(scene)
	get_tree().root.add_child(scene)        # current_scene 必须是根节点的直接子节点
	get_tree().current_scene = scene
	_key(scene, KEY_ESCAPE)
	var w := 0
	while w < 60 and (get_tree().current_scene == null or get_tree().current_scene == scene):
		await get_tree().process_frame
		w += 1
	var cs = get_tree().current_scene
	_ok("★★计分对局按 ESC ⇒ 回到主菜单(不是按了没反应)", cs != null and str(cs.scene_file_path) == "res://scenes/MainMenu.tscn",
		str(cs.scene_file_path) if cs != null else "null")
	if cs != null and cs != self:
		cs.queue_free()
		get_tree().current_scene = self
	gs.season_leaders = leaders0
	gs.tutorial_active = tut0
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 计分对局 R 不抹局 / ESC 回主菜单")
	get_tree().quit(1 if _fail > 0 else 0)
