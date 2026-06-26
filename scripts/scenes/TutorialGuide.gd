extends Node
## TutorialGuide — 新手教程步骤引导 (1:1 PoC src/scenes/TutorialGuide.ts)。
## 顶部/底部非阻挡横幅: 序号徽章 + 提示文 + 下一步/知道了/完成 + 跳过。玩家照提示在真实战斗里操作,
## advanceOn 事件由 BattleScene 在对应动作发生时 notify → 自动推进。
## 用法: var g = preload(".../TutorialGuide.gd").new(); add_child(g); g.start(steps, on_done)
##   steps = [{ "text": String, "advanceOn"?: String, "anchor"?: "top"|"bottom" }]

var _steps: Array = []
var _idx: int = 0
var _on_done: Callable
var _layer: CanvasLayer
var _panel: PanelContainer
var _badge: Label
var _text: RichTextLabel
var _btn_row: HBoxContainer


func start(steps: Array, on_done: Callable) -> void:
	_steps = steps
	_on_done = on_done
	_build_ui()
	_render()


func notify(event: String) -> void:
	if _idx < _steps.size() and str(_steps[_idx].get("advanceOn", "")) == event:
		_next()


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 8000
	add_child(_layer)
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5; _panel.anchor_right = 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(620, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.071, 0.110, 0.204, 0.96)   # rgba(18,28,52,.96)
	sb.set_border_width_all(2); sb.border_color = Color("#ffd93d")
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.55)   # PoC box-shadow 0 6px 30px rgba(0,0,0,.55)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 6)
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 14; sb.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", sb)
	_layer.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_panel.add_child(vb)
	# 行: 徽章 + 文字
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	_badge = Label.new()
	_badge.add_theme_font_size_override("font_size", 13)
	_badge.add_theme_color_override("font_color", Color("#3a1f00"))
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("#ffd93d")
	bsb.set_corner_radius_all(6)
	bsb.content_margin_left = 9; bsb.content_margin_right = 9
	bsb.content_margin_top = 2; bsb.content_margin_bottom = 2
	_badge.add_theme_stylebox_override("normal", bsb)
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_badge)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", 15)
	_text.add_theme_font_size_override("bold_font_size", 15)
	_text.add_theme_color_override("default_color", Color("#eaf0fa"))
	row.add_child(_text)
	# 按钮行
	_btn_row = HBoxContainer.new()
	_btn_row.alignment = BoxContainer.ALIGNMENT_END
	_btn_row.add_theme_constant_override("separation", 10)
	vb.add_child(_btn_row)


func _render() -> void:
	if _idx >= _steps.size():
		return
	var step: Dictionary = _steps[_idx]
	# 锚点: top → 顶部 14; bottom → 底部 120
	var anchor := str(step.get("anchor", "top"))
	if anchor == "bottom":
		_panel.anchor_top = 1.0; _panel.anchor_bottom = 1.0
		_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_panel.offset_top = -120.0 - 80.0; _panel.offset_bottom = -120.0
	else:
		_panel.anchor_top = 0.0; _panel.anchor_bottom = 0.0
		_panel.grow_vertical = Control.GROW_DIRECTION_END
		_panel.offset_top = 14.0; _panel.offset_bottom = 14.0 + 80.0
	_badge.text = "%d/%d" % [_idx + 1, _steps.size()]
	_text.text = _html_b_to_bbcode(str(step.get("text", "")))
	# 重建按钮
	for c in _btn_row.get_children():
		c.queue_free()
	var is_last := _idx == _steps.size() - 1
	if not is_last:
		var skip := Button.new()
		skip.text = "跳过教程"
		skip.add_theme_font_size_override("font_size", 14)
		skip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		skip.pressed.connect(_finish)
		_btn_row.add_child(skip)
	var nxt := Button.new()
	nxt.text = "完成 ✓" if is_last else ("知道了" if step.has("advanceOn") else "下一步 ▶")
	nxt.add_theme_font_size_override("font_size", 14)
	nxt.add_theme_color_override("font_color", Color("#3a1f00"))
	var nsb := StyleBoxFlat.new()
	nsb.bg_color = Color("#ffc23c")
	nsb.set_corner_radius_all(7)
	nsb.content_margin_left = 18; nsb.content_margin_right = 18
	nsb.content_margin_top = 7; nsb.content_margin_bottom = 7
	nxt.add_theme_stylebox_override("normal", nsb)
	nxt.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	nxt.pressed.connect(_next)
	_btn_row.add_child(nxt)


func _next() -> void:
	_idx += 1
	if _idx >= _steps.size():
		_finish()
		return
	_render()


func _finish() -> void:
	if _on_done.is_valid():
		_on_done.call()
	queue_free()


# <b>...</b> → [b]...[/b] (PoC 教程文用 HTML 粗体)
func _html_b_to_bbcode(s: String) -> String:
	return s.replace("<b>", "[b]").replace("</b>", "[/b]")
