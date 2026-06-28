extends Control

## RecordScene — 战绩 (1:1 PoC RecordScene.ts): 总览(总场/胜/负/胜率) + 最近20场.

const MODE_LABEL := {"single": "野生", "pve": "野生", "dungeon": "深海闯关", "custom": "自定义",
	"boss": "Boss", "boss-pick": "指定 Boss", "test": "测试"}

const W := 1280.0
const PANEL_W := 760.0


func _ready() -> void:
	_bg()

	# 标题 @ (W/2, 50), 36px #ffd93d stroke #1a1a2e 厚5
	var title := _stroked_label("📊 战绩", 36, "#ffd93d", "#1a1a2e", 5)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(400, 52)
	title.position = Vector2(W / 2.0 - 200.0, 50.0 - 26.0)
	add_child(title)

	# 返回 icon @ (40,40)
	_icon_button(40.0, 40.0, "←", func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))

	# 总览数据
	var total: int = GameState.battles_total
	var wins: int = GameState.battles_won
	var losses: int = maxi(0, total - wins)
	var rate: int = int(round(float(wins) / total * 100.0)) if total > 0 else 0

	# 主面板 @ (W-PANEL_W)/2, 100, 宽 760
	var panel_x := (W - PANEL_W) / 2.0
	var root := VBoxContainer.new()
	root.position = Vector2(panel_x, 100.0)
	root.custom_minimum_size = Vector2(PANEL_W, 0)
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	# ── 总览卡: bg rgba(20,32,40,.82) 边框2px #2e4a5e 圆角12 ──
	var overview := PanelContainer.new()
	var ovsb := StyleBoxFlat.new()
	ovsb.bg_color = Color(20.0 / 255.0, 32.0 / 255.0, 40.0 / 255.0, 0.82)
	ovsb.set_border_width_all(2)
	ovsb.border_color = Color("#2e4a5e")
	ovsb.set_corner_radius_all(12)
	ovsb.content_margin_left = 20; ovsb.content_margin_right = 20
	ovsb.content_margin_top = 16; ovsb.content_margin_bottom = 16
	overview.add_theme_stylebox_override("panel", ovsb)
	overview.custom_minimum_size = Vector2(PANEL_W, 0)
	root.add_child(overview)
	var ovrow := HBoxContainer.new()
	ovrow.add_theme_constant_override("separation", 8)
	overview.add_child(ovrow)
	ovrow.add_child(_stat("总场次", str(total), "#ffffff"))
	ovrow.add_child(_stat("胜", str(wins), "#06d6a0"))
	ovrow.add_child(_stat("负", str(losses), "#ff6b6b"))
	ovrow.add_child(_stat("胜率", "%d%%" % rate, "#ffd93d"))

	# 列表标题 "最近对局 (N)" 13px #58d3ff bold
	var n: int = mini(20, GameState.match_history.size())
	var lh := Label.new()
	lh.text = "最近对局 (%d)" % n
	lh.add_theme_font_size_override("font_size", 13)
	lh.add_theme_color_override("font_color", Color("#58d3ff"))
	root.add_child(lh)

	# ── 对局列表 (最多 20), 滚动 ──
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_W, 430)
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	if GameState.match_history.is_empty():
		# 空提示 14px #789
		var empty := Label.new()
		empty.text = "还没有对局记录，去打一场吧！"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", Color("#778899"))
		empty.custom_minimum_size = Vector2(PANEL_W, 96)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		list.add_child(empty)
	else:
		for i in range(n):
			list.add_child(_match_row(GameState.match_history[i]))


# 总览统计块: 数值 30px bold + 标签 12px #9ab
func _stat(label: String, value: String, color: String) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", 30)
	v.add_theme_color_override("font_color", Color(color))
	box.add_child(v)
	var l := Label.new()
	l.text = label
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color("#99aabb"))
	box.add_child(l)
	return box


# 对局行: bg rgba(20,32,40,.7) + 左边框4px (胜#06d6a0/负#ff5c5c) 圆角6
func _match_row(m: Dictionary) -> Control:
	var won: bool = m.get("result", "") == "win"
	var col := Color("#06d6a0") if won else Color("#ff5c5c")
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(20.0 / 255.0, 32.0 / 255.0, 40.0 / 255.0, 0.7)
	sb.set_corner_radius_all(6)
	sb.border_width_left = 4
	sb.border_color = col
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	pc.add_child(hb)

	# 结果 胜/负 30px 宽 15px bold
	var res := Label.new()
	res.text = "胜" if won else "负"
	res.custom_minimum_size = Vector2(30, 0)
	res.add_theme_font_size_override("font_size", 15)
	res.add_theme_color_override("font_color", col)
	res.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(res)

	# 头像 34×34 圆角6 1px边框#2e4a5e (gap 4)
	var avs := HBoxContainer.new()
	avs.add_theme_constant_override("separation", 4)
	hb.add_child(avs)
	for pid in m.get("lineup", []):
		avs.add_child(_avatar(pid))

	# spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)

	# 模式 12px #9cf
	var mode_l := Label.new()
	mode_l.text = MODE_LABEL.get(m.get("mode", ""), m.get("mode", ""))
	mode_l.add_theme_font_size_override("font_size", 12)
	mode_l.add_theme_color_override("font_color", Color("#99ccff"))
	mode_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(mode_l)

	# 回合 11px #778 宽46 右对齐
	var turn_l := Label.new()
	turn_l.text = ("%d秒" if m.get("mode", "") == "实时" else "%d回合") % int(m.get("turn", 0))   # 实时无回合→显时长
	turn_l.add_theme_font_size_override("font_size", 11)
	turn_l.add_theme_color_override("font_color", Color("#777788"))
	turn_l.custom_minimum_size = Vector2(46, 0)
	turn_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	turn_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(turn_l)

	# 相对时间 11px #667 宽64 右对齐
	var time_l := Label.new()
	time_l.text = _rel_time(int(m.get("ts", 0)))
	time_l.add_theme_font_size_override("font_size", 11)
	time_l.add_theme_color_override("font_color", Color("#666677"))
	time_l.custom_minimum_size = Vector2(64, 0)
	time_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(time_l)
	return pc


func _avatar(pid: String) -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0a1422")
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color("#2e4a5e")
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(34, 34)
	var tex := TextureRect.new()
	tex.custom_minimum_size = Vector2(34, 34)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var path := "res://assets/sprites/avatars/%s.png" % pid
	if ResourceLoader.exists(path):
		tex.texture = load(path)
	pc.add_child(tex)
	return pc


func _rel_time(ts: int) -> String:
	if ts <= 0:
		return ""
	var d := int(Time.get_unix_time_from_system() * 1000.0) - ts
	if d < 60000:
		return "刚刚"
	if d < 3600000:
		return "%d 分钟前" % int(d / 60000.0)
	if d < 86400000:
		return "%d 小时前" % int(d / 3600000.0)
	return "%d 天前" % int(d / 86400000.0)


func _mono_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["monospace", "Consolas", "Courier New"])
	f.fallbacks = [load("res://assets/fonts/NotoSansSC-Regular.otf")]   # CJK 网页/iOS 兜底 (SystemFont 在 web 取不到系统字体→中文乱码)
	return f


func _stroked_label(t: String, size: int, color: String, stroke: String, thick: int) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(color))
	if thick > 0 and stroke != "":
		l.add_theme_constant_override("outline_size", thick)
		l.add_theme_color_override("font_outline_color", Color(stroke))
	return l


func _icon_button(cx: float, cy: float, icon: String, cb: Callable) -> void:
	var r := 18.0
	var btn := Control.new()
	btn.size = Vector2(r * 2.0, r * 2.0)
	btn.pivot_offset = Vector2(r, r)
	btn.position = Vector2(cx - r, cy - r)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(btn)
	var stroke := {"c": Color("#58d3ff")}
	btn.draw.connect(func():
		btn.draw_circle(Vector2(r, r), r, Color(0, 0, 0, 0.55))
		btn.draw_arc(Vector2(r, r), r - 1.0, 0, TAU, 32, stroke["c"], 2.0))
	var txt := Label.new()
	txt.text = icon
	txt.add_theme_font_size_override("font_size", 18)
	txt.add_theme_font_override("font", _mono_font())   # PoC RecordScene.ts:105 fontFamily:'monospace'
	txt.add_theme_color_override("font_color", Color("#ffffff"))
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	txt.size = Vector2(r * 2.0, r * 2.0)
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(txt)
	btn.mouse_entered.connect(func(): stroke["c"] = Color("#ffd93d"); btn.queue_redraw())
	btn.mouse_exited.connect(func(): stroke["c"] = Color("#58d3ff"); btn.queue_redraw())
	btn.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			var tw := create_tween()
			tw.tween_property(btn, "scale", Vector2(0.85, 0.85), 0.06)
			tw.tween_property(btn, "scale", Vector2(1, 1), 0.06)
			get_tree().create_timer(0.08).timeout.connect(cb))


func _bg() -> void:
	# PoC (index.html menu-bg-active): RecordScene 套主菜单 tile bg = menu-bg-tile.png 平铺 (512px repeat)
	#   over 深绿底 #1a3a2a, 上叠暗渐变 ::after rgba(8,12,20,.15→.40). 不是 menu-bg.png 废墟图!
	var base := ColorRect.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color(0.102, 0.227, 0.165)   # #1a3a2a 深绿底
	add_child(base)
	if ResourceLoader.exists("res://assets/sprites/menu/menu-bg-tile.png"):
		var tile := TextureRect.new()
		# PoC CSS background-size:512px → 把 tile 缩到 512² 再平铺
		tile.texture = PreloadCache.menu_bg_tile_tex()   # 复用缓存512²纹理 (resize只做一次, 消除进场景LANCZOS卡顿)
		tile.stretch_mode = TextureRect.STRETCH_TILE
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 漂移 -512→0 / 25s linear 循环 (1:1 PoC menuBgDrift index.html:79/90) — 原静态不动是bug
		var vp := get_viewport_rect().size
		tile.size = Vector2(vp.x + 512, vp.y + 512)
		tile.position = Vector2(-512, -512)
		add_child(tile)
		var drift := tile.create_tween().set_loops()
		drift.tween_property(tile, "position", Vector2(0, 0), 25.0).from(Vector2(-512, -512)).set_trans(Tween.TRANS_LINEAR)
	# ::after 暗渐变遮罩 (顶 alpha.15 → 底 .40)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.colors = PackedColorArray([
		Color(0.031, 0.047, 0.078, 0.15),
		Color(0.031, 0.047, 0.078, 0.25),
		Color(0.031, 0.047, 0.078, 0.40),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 128
	var ov := TextureRect.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.texture = gt
	ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ov.stretch_mode = TextureRect.STRETCH_SCALE
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ov)
