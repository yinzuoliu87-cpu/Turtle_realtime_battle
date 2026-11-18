## 安卓返回键 / 返回手势(2026-11-18 · 方案书 docs/plans/20261118b-安卓直装包.md A5)。
##
## 由来: Godot 默认 `application/config/quit_on_go_back = true` —— 安卓上按返回键(或全面屏左右边缘的返回手势)
##   **直接退出游戏**。引擎源码(4.6): 实体返回键走 android_input_handler.cpp 发 `WINDOW_EVENT_GO_BACK_REQUEST`
##   + 一个 Key::BACK 按键; 返回手势走 Godot.kt onBackPressed → GodotLib.back(), **只发** GO_BACK_REQUEST。
##   Key::BACK 默认不在 ui_cancel 里 ⇒ 两条路唯一共有的信号是 `NOTIFICATION_WM_GO_BACK_REQUEST`, 只认它。
## 做法: project.godot 关掉 quit_on_go_back; GameState 收到这条通知调 `handle()`, 按顺序问下面三家, 谁接了就停:
##   ① 发一个 ui_cancel(与电脑上按 Esc 同一条路): 弹框 / 整页浮层 / 教程 / 已有 Esc 返回的页面先接;
##   ② 屏上可见、可点、打了 `tag()` 记号的按钮里**树序最后**那一枚(后建的画在上面 = 最上层)——
##      各页顶栏返回(TopBar)、选龟页返回、回放「退出」、确认框「取消」;
##   ③ 当前场景的 `_on_back_key()`; 没有而它是首页(主菜单)⇒ 弹「退出游戏」确认框(scripts/scenes/exit_confirm_dialog.gd)。
##   都没有 ⇒ 什么都不做(对局中 / 首次进入流程: 返回键不该把人带出去, 也不该退出游戏)。
##   接收点是 autoload/back_key_hook.gd(GameState.gd 已顶到 3000 行上限, 不往里加)。
## 同一帧只处理一次(实体键与手势在个别机型上会各来一条)。
## 门禁: tests/verify_back_key.gd
class_name BackKey
extends RefCounted

const EXIT := preload("res://scripts/scenes/exit_confirm_dialog.gd")
const META := "back_key"

const R_CANCEL := "cancel"     # ① ui_cancel 有人接了
const R_BUTTON := "button"     # ② 按了一枚返回记号按钮
const R_SCENE := "scene"       # ③ 场景自己处理
const R_NONE := "none"
const R_DUP := "dup"           # 同一帧第二次, 丢掉

static var _last_frame := -1


## 给一枚按钮打返回记号: 返回键按下时, 它可见可点且在最上层 ⇒ 就按它。
static func tag(b: BaseButton) -> void:
	if b != null:
		b.set_meta(META, true)


## 处理一次返回。`scene` 缺省 = 当前场景(门禁把被测场景挂在测试节点下, 显式传进来)。返回走了哪一家(R_*)。
static func handle(tree: SceneTree, scene: Node = null) -> String:
	if tree == null:
		return R_NONE
	var f := Engine.get_process_frames()
	if f == _last_frame:
		return R_DUP
	_last_frame = f
	if scene == null:
		scene = tree.current_scene
	## ①
	var go0 := SceneNav.go_count
	var down := InputEventAction.new()
	down.action = "ui_cancel"
	down.pressed = true
	tree.root.push_input(down)
	var took := tree.root.is_input_handled() or SceneNav.go_count != go0
	var up := InputEventAction.new()
	up.action = "ui_cancel"
	up.pressed = false
	tree.root.push_input(up)
	if took:
		return R_CANCEL
	## ②
	var b := top_button(tree.root)
	if b != null:
		b.pressed.emit()
		return R_BUTTON
	## ③
	if scene != null and is_instance_valid(scene):
		if scene.has_method("_on_back_key"):
			scene.call("_on_back_key")
			return R_SCENE
		if is_home(scene):
			EXIT.open(scene)
			return R_SCENE
	return R_NONE


## 是不是游戏的首页(project.godot 的 run/main_scene = 主菜单)。首页上再按返回 = 问要不要退出游戏。
static func is_home(scene: Node) -> bool:
	var home := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	return home != "" and scene.scene_file_path == home


## 可见、可点、打了记号的按钮里树序最后那一枚; 没有 ⇒ null。
static func top_button(from: Node) -> BaseButton:
	var out: Array = []
	_walk(from, out)
	return out[-1] if not out.is_empty() else null


static func _walk(n: Node, out: Array) -> void:
	if n is BaseButton and n.has_meta(META):
		var b := n as BaseButton
		if b.is_visible_in_tree() and not b.disabled:
			out.append(b)
	for c in n.get_children():
		_walk(c, out)
