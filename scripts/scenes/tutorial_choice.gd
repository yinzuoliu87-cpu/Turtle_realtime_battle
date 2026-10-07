extends RefCounted
class_name TutorialChoice
## 新手教程选择框(方案书 docs/plans/20261007-新手教程重做.md §4.3)。
##
## 用户 2026-10-07:「一般是有跳过和开始教程选项啊」; 文案去口语化(「去口语化你做就好，但是欢迎来到斗龟场还是要留的」)。
##   · 首启:  标题「欢迎来到斗龟场」/ 副标题「新手教程」/ 按钮「开始教程」「跳过」
##   · 右上「?」: 标题「新手教程」/ 按钮「开始教程」「取消」
## 「开始教程」⇒ TutorialDirector.enter();「跳过」⇒ end_tutorial("skipped")(与走完同一个出口);「取消」⇒ 关框。
## ★节点名固定 `TutorialChoice` —— 驱动(sim_driver)与门禁按名字找它。
## ★皮肤沿用主菜单那块已换好的九宫格面板 + `UISkin.button`(verify_ui_consistency 量这块弹层)。

const NODE_NAME := "TutorialChoice"
const TXT_WELCOME := "欢迎来到斗龟场"
const TXT_TITLE := "新手教程"
const TXT_START := "开始教程"
const TXT_SKIP := "跳过"
const TXT_CANCEL := "取消"
const BTN_SIZE := Vector2(168, 81)


## 建框并挂到 host 上。first_launch = 首启(第二个按钮是「跳过」, 否则是「取消」)。已有就不重建, 返回旧的。
static func open(host: Node, first_launch: bool) -> Control:
	var old := host.get_node_or_null(NODE_NAME)
	if old != null:
		return old as Control
	var ov := ColorRect.new()
	ov.name = NODE_NAME
	ov.color = Color(0, 0, 0, 0.6)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	ov.set_meta("first_launch", first_launch)
	var box := PanelContainer.new()
	box.anchor_left = 0.5; box.anchor_top = 0.5; box.anchor_right = 0.5; box.anchor_bottom = 0.5
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH; box.grow_vertical = Control.GROW_DIRECTION_BOTH
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("#16213a")
	bsb.set_border_width_all(0)
	bsb.set_corner_radius_all(0)
	bsb.content_margin_left = 40; bsb.content_margin_right = 40; bsb.content_margin_top = 30; bsb.content_margin_bottom = 30
	var bframe := UISkin.nine("panel-frame.png", 20, bsb)
	bframe.content_margin_left = 40; bframe.content_margin_right = 40
	bframe.content_margin_top = 30; bframe.content_margin_bottom = 30
	box.add_theme_stylebox_override("panel", bframe)
	ov.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14); vb.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(vb)
	var t := Label.new()
	t.name = "Title"
	t.text = TXT_WELCOME if first_launch else TXT_TITLE
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 30); t.add_theme_color_override("font_color", Color("#ffd93d"))
	vb.add_child(t)
	if first_launch:
		var d := Label.new()
		d.name = "Subtitle"
		d.text = TXT_TITLE
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.add_theme_font_size_override("font_size", 20); d.add_theme_color_override("font_color", Color("#e8d9b0"))
		vb.add_child(d)
	var bh := HBoxContainer.new()
	bh.alignment = BoxContainer.ALIGNMENT_CENTER; bh.add_theme_constant_override("separation", 18)
	vb.add_child(bh)
	var start_btn := Button.new()
	start_btn.name = "StartTutorial"
	start_btn.text = TXT_START; start_btn.custom_minimum_size = BTN_SIZE
	start_btn.add_theme_font_size_override("font_size", 22)
	start_btn.add_theme_color_override("font_color", Color("#ffe9a8"))
	UISkin.button(start_btn, Color("#ffd08a"))
	start_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bh.add_child(start_btn)
	var other := Button.new()
	other.name = "SkipTutorial" if first_launch else "CancelTutorial"
	other.text = TXT_SKIP if first_launch else TXT_CANCEL
	other.custom_minimum_size = BTN_SIZE
	other.add_theme_font_size_override("font_size", 22)
	other.add_theme_color_override("font_color", Color("#c6d2e0"))
	UISkin.button(other, Color("#9fb6c9"))
	other.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bh.add_child(other)
	start_btn.pressed.connect(func() -> void:
		ov.queue_free()
		var td = host.get_node_or_null("/root/TutorialDirector")
		if td != null:
			td.enter(host))
	other.pressed.connect(func() -> void:
		ov.queue_free()
		if first_launch:
			var td2 = host.get_node_or_null("/root/TutorialDirector")
			if td2 != null:
				td2.end_tutorial("skipped"))
	host.add_child(ov)
	return ov
