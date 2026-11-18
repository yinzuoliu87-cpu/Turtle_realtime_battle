extends RefCounted
## exit_confirm_dialog.gd —— 主菜单上按安卓返回键:「退出游戏」确认框(2026-11-18 · 方案书 20261118b A5)。
##
## 原来安卓上返回键 / 返回手势直接退出游戏(Godot 默认 quit_on_go_back); 现在返回键一路退回主菜单,
##   在主菜单上再按一次才问要不要退(`BackKey` ③ → MainMenuScene._on_back_key)。开着时再按返回 = 「取消」
##   (取消键打了 BackKey 记号, ② 先按它)。
## ★皮照抄设置页的确认框(压暗底 + `panel-frame` 九宫格 + 弹框里的按钮一律 `UISkin.card_button`, 用户 10-22)。
## ★自带一层 CanvasLayer: 主菜单的内容分在好几层 CanvasLayer 上, 挂在场景根 Control 下会被压在底下。

const BOX := Vector2(520.0, 200.0)
const LAYER_Z := 120

## 【门禁按名字找的节点】
const LAYER := "ExitConfirmLayer"
const TITLE := "ExitConfirmTitle"
const BTN_CANCEL := "ExitConfirmCancel"
const BTN_OK := "ExitConfirmOk"

const T_TITLE := "退出游戏"
const L_CANCEL := "取消"
const L_OK := "退出"

## 【门禁注入点】有效 ⇒ 点「退出」不真退出, 改调它。⚠ static, 用完必须还原。
static var quit_for_test: Callable = Callable()


static func is_open(host: Node) -> bool:
	return host != null and host.get_node_or_null(LAYER) != null


## 打开。已经开着就不再开一个。返回那层 CanvasLayer。
static func open(host: Node) -> CanvasLayer:
	var old := host.get_node_or_null(LAYER)
	if old != null:
		return old as CanvasLayer
	var layer := CanvasLayer.new()
	layer.name = LAYER
	layer.layer = LAYER_Z
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ffb454")
	sb.set_border_width_all(3); sb.set_corner_radius_all(0)
	var tex := UISkin.nine("panel-frame.png", 20, sb)
	if tex is StyleBoxTexture:
		(tex as StyleBoxTexture).modulate_color = UISkin.tint_of(Color("#ffb454"))
	box.add_theme_stylebox_override("panel", tex)
	var vs: Vector2 = host.get_viewport().get_visible_rect().size
	box.position = ((vs - BOX) * 0.5).round()
	box.size = BOX
	dim.add_child(box)

	var ttl := Label.new()
	ttl.name = TITLE
	ttl.text = T_TITLE
	ttl.add_theme_font_size_override("font_size", 24)
	UISkin.title_label(ttl, 24)        # 弹框标题统一 24 号像素标题字(docs/plans/20261027-UI美术规矩.md §4.1)
	ttl.add_theme_color_override("font_color", Color("#ffb454"))
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ttl)
	ttl.position = Vector2(0, 34); ttl.size = Vector2(BOX.x, 36)

	var cancel := _btn(box, BTN_CANCEL, L_CANCEL, Vector2(30, 112))
	var ok := _btn(box, BTN_OK, L_OK, Vector2(270, 112))
	BackKey.tag(cancel)
	cancel.pressed.connect(func() -> void: layer.queue_free())
	ok.pressed.connect(func() -> void:
		if quit_for_test.is_valid():
			quit_for_test.call()
			return
		var tree := layer.get_tree()
		if tree != null:
			tree.quit())
	return layer


static func _btn(box: Control, nm: String, label: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	UISkin.card_button(b)
	box.add_child(b)
	b.position = pos
	b.size = Vector2(220, 56)
	return b
