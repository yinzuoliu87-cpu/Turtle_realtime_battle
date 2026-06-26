extends Button
## 选龟技能图标按钮 — 自定义 styled tooltip (1:1 PoC .dp-skill-tip index.html:642-652)
##
## 用 preload 直引 (不 class_name, 避免新全局类 F5 未声明崩 — 见 ledger 坑)。
## tooltip_text 约定: 第一行=标题(可含 " (CDn)"), 其余行=描述体(含双形态 近战/火山)。
## Godot 系统 tooltip 机制: 有 tooltip_text 即按 gui tooltip_delay 悬浮触发并自动定位, 保证显示。

func _make_custom_tooltip(for_text: String) -> Object:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0a0e18")                       # PoC bg #0a0e18
	sb.border_color = Color(1, 216.0 / 255.0, 107.0 / 255.0, 0.5)   # border rgba(255,216,107,.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10; sb.content_margin_right = 10   # padding 8px 10px
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	sb.shadow_color = Color(0, 0, 0, 0.6); sb.shadow_size = 8    # box-shadow 0 4px 14px rgba(0,0,0,.6)
	pc.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)

	var lines := for_text.split("\n")
	# tip-head: 13px #fff (CD 段 PoC 是 #ffd86b, 这里整行白, 够用)
	var head := Label.new()
	head.text = lines[0] if lines.size() > 0 else for_text
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", Color(1, 1, 1))
	vb.add_child(head)

	if lines.size() > 1:
		var rest: Array = []
		for i in range(1, lines.size()):
			rest.append(lines[i])
		var body := Label.new()
		body.text = "\n".join(rest)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(220, 0)   # PoC max-width 250 / min 180
		body.add_theme_font_size_override("font_size", 11)   # tip-body 11px
		body.add_theme_color_override("font_color", Color("#bbccdd"))   # #bcd
		vb.add_child(body)

	return pc
