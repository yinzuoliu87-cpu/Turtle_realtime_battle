extends Node
## TutorialChrome — 教程期间每一屏都挂的外壳(导演 `TutorialDirector._attach_chrome` 挂, 不用各屏自己记得)。
##
## 两件事:
##   ① 右上常驻「跳过教程」—— 教程里唯一能随时离开的入口(方案书 §1 方向 3; 参考 9 款里 7 款在右上)。
##      点了 = `TutorialDirector.end_tutorial("skipped")`: 与走完教程**同一个出口**。
##   ② 吞掉 ESC / 返回键(ui_cancel)—— 用户 2026-10-07「教程里就不应该有返回键啊，要一直跟着教程走啊」。
##      各屏的返回箭头/切屏按钮由各屏在教程中自己藏(TopBar / 选龟 / 结算 / 认输), 键盘这条路在这里一处收口。
##
## ★层级 9000 > 引导条 8000: 引导的暗幕会挡住一切洞外点击, 跳过钮必须压在暗幕上面才点得到。
## ★位置: 宿主实现 `_tutorial_skip_slot() -> Rect2` 就用它(宿主最清楚自己顶栏哪里空着, 修 B7 那一类);
##   没实现 ⇒ 右上角安全区内。

const LAYER := 9000
const BTN_SIZE := Vector2(132, 44)
const MARGIN := 16.0

var button: Button = null
var _layer: CanvasLayer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("tut_overlay")   # ★商店/背包 `_rebuild()` 跳过本组, 否则买一件装备外壳就被清掉
	_layer = CanvasLayer.new()
	_layer.layer = LAYER
	add_child(_layer)
	button = Button.new()
	button.name = "SkipTutorial"
	button.text = "跳过教程"
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color("#e8f0f6"))
	button.custom_minimum_size = BTN_SIZE
	UISkin.button(button, Color("#9fb6c9"))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_on_skip)
	_layer.add_child(button)
	_place()
	get_viewport().size_changed.connect(_place)


func _process(_dt: float) -> void:
	_place()   # 宿主可能晚建顶栏 / 换分辨率 —— 每帧对一次, 只是几个赋值


func _place() -> void:
	if button == null:
		return
	var host := get_parent()
	var r := Rect2()
	if host != null and host.has_method("_tutorial_skip_slot"):
		r = host.call("_tutorial_skip_slot")
	elif host != null and host.get("_hud") != null and (host.get("_hud") as Object).has_method("tutorial_skip_slot"):
		r = (host.get("_hud") as Object).call("tutorial_skip_slot")   # 战斗场: 位置归 HUD 管(主文件不加函数)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var sm: Vector4 = SafeArea.margins(vp, MARGIN)
		r = Rect2(Vector2(vp.x - sm.z - BTN_SIZE.x, sm.y), BTN_SIZE)
	button.position = r.position
	button.size = r.size


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") \
			or (event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()


func _on_skip() -> void:
	var td = get_node_or_null("/root/TutorialDirector")
	if td != null:
		td.end_tutorial("skipped")
