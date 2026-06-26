extends Control

## SettingsScene — 设置 (1:1 PoC SettingsScene.ts): BGM/SFX 音量 + 全屏 + 重置存档.
## Phaser 绝对坐标 (中心原点) → Godot 左上 (position = 中心 - size/2). 视口 1280×720.

const W := 1280.0
const H := 720.0

var _perf_lite := false   # 低画质模式 (桌面默认关). Godot 无 backdrop-filter → 仅 label 切换.
var _perf_btn: Label = null


func _ready() -> void:
	_bg()

	# 标题 @ (W/2, 80), 40px #ffd93d stroke #1a1a2e 厚5
	var title := _stroked_label("设置", 40, "#ffd93d", "#1a1a2e", 5)
	_place_center(title, W / 2.0, 80.0)

	# 返回 icon 按钮 @ (40,40)
	_icon_button(40.0, 40.0, "←", func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))

	# BGM 滑条 @ (W/2, 220)
	_slider(W / 2.0, 220.0, "🎵 BGM 音量", GameState.bgm_volume, func(v):
		GameState.bgm_volume = v; Audio.bgm_volume = v; GameState.save())
	# SFX 滑条 @ (W/2, 330)
	_slider(W / 2.0, 330.0, "🔊 音效音量", GameState.sfx_volume, func(v):
		GameState.sfx_volume = v; Audio.sfx_volume = v; Audio.play_sfx("hit-physical", 1.0); GameState.save())

	# 全屏 @ (W/2, 410) — PoC: document.fullscreenElement ? '⛶ 退出全屏' : '⛶ 全屏' (默认 ⛶ 全屏)
	_text_button(W / 2.0, 410.0, _fullscreen_label(), _toggle_fullscreen)

	# 低画质模式 @ (W/2, 490) — PoC: isPerfLite() ? '🪶 低画质模式: 开 (流畅)' : '🪶 低画质模式: 关 (高画质)'
	#   桌面默认关. Godot 无 backdrop-filter blur → 切换仅改 label (引擎天生差异, 见报告).
	_perf_btn = _text_button(W / 2.0, 490.0, _perf_label(), _toggle_perf)

	# 重置存档 @ (W/2, 580)
	_text_button(W / 2.0, 580.0, "⚠ 重置所有存档", _reset_save)

	# 底部提示 @ (W/2, H-40), 11px #888
	var hint := _stroked_label("设置自动保存", 11, "#888888", "", 0)   # PoC 字面是"到 localStorage"(浏览器术语), Godot 存 user:// → 去掉误导后缀
	_place_center(hint, W / 2.0, H - 40.0)


func _fullscreen_label() -> String:
	var m := DisplayServer.window_get_mode()
	if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		return "⛶ 退出全屏"
	return "⛶ 全屏"


func _perf_label() -> String:
	if _perf_lite:
		return "🪶 低画质模式: 开 (流畅)"
	return "🪶 低画质模式: 关 (高画质)"


func _toggle_perf() -> void:
	_perf_lite = not _perf_lite
	if _perf_btn != null:
		_perf_btn.text = _perf_label()


func _toggle_fullscreen() -> void:
	var m := DisplayServer.window_get_mode()
	if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _reset_save() -> void:
	GameState.reset_save()
	# 成功提示 @ (W/2, 560), alpha tween 0→1 200ms, hold 1500ms 再淡出
	var ok := _stroked_label("✓ 存档已清空", 16, "#06d6a0", "", 0)
	_place_center(ok, W / 2.0, 560.0)
	ok.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(ok, "modulate:a", 1.0, 0.2)
	tw.tween_interval(1.5)
	tw.tween_property(ok, "modulate:a", 0.0, 0.2)
	tw.tween_callback(ok.queue_free)


# ── 滑条 (PoC renderSlider, track w=380, handle r14) ──
func _slider(cx: float, cy: float, label: String, init: float, cb: Callable) -> void:
	var track_w := 380.0
	var left := cx - track_w / 2.0

	# 标签 @ (x - w/2, y - 30) origin(0,0.5), 16px #fff
	var lbl := _stroked_label(label, 16, "#ffffff", "", 0)
	lbl.position = Vector2(left, cy - 30.0 - 8.0)
	add_child(lbl)

	# 轨道 8px 高 #444
	var track := ColorRect.new()
	track.color = Color("#444444")
	track.size = Vector2(track_w, 8.0)
	track.position = Vector2(left, cy - 4.0)
	add_child(track)
	# 填充 #ffd93d
	var fill := ColorRect.new()
	fill.color = Color("#ffd93d")
	fill.size = Vector2(track_w * init, 8.0)
	fill.position = Vector2(left, cy - 4.0)
	add_child(fill)

	# 百分比文字 @ (x + w/2 + 20, y) origin(0,0.5), monospace 14px #ffd93d
	var pct := Label.new()
	pct.text = "%d%%" % int(round(init * 100.0))
	pct.add_theme_font_size_override("font_size", 14)
	pct.add_theme_color_override("font_color", Color("#ffd93d"))
	pct.add_theme_font_override("font", _mono_font())
	pct.size = Vector2(60, 16)
	pct.position = Vector2(cx + track_w / 2.0 + 20.0, cy - 8.0)
	add_child(pct)

	# 圆 handle r14 (用 HSlider 隐藏轨道, 自绘圆) — 用 Button 圆形 grabber
	var handle := _circle(14.0, Color("#ffd93d"))
	handle.position = Vector2(left + track_w * init - 14.0, cy - 14.0)
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(handle)

	var apply := func(px: float):
		var clamped: float = clampf(px, left, left + track_w)
		var v: float = (clamped - left) / track_w
		handle.position.x = clamped - 14.0
		fill.size.x = track_w * v
		pct.text = "%d%%" % int(round(v * 100.0))
		cb.call(v)

	# 拖拽 handle
	handle.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			apply.call(handle.global_position.x + 14.0 + ev.relative.x))
	# 点轨道跳
	track.mouse_filter = Control.MOUSE_FILTER_STOP
	track.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			apply.call(track.global_position.x + ev.position.x))


func _circle(r: float, col: Color) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(r * 2.0, r * 2.0)
	c.size = Vector2(r * 2.0, r * 2.0)
	var draw := func():
		c.draw_circle(Vector2(r, r), r, col)
	c.draw.connect(draw)
	return c


# ── 按钮: btn-frame.png 整图拉伸 260×50 + 文字描边 + hover/press 动画 ──
func _text_button(cx: float, cy: float, label: String, cb: Callable) -> Label:
	var cont := Control.new()
	cont.size = Vector2(260, 50)
	cont.pivot_offset = Vector2(130, 25)
	cont.position = Vector2(cx - 130.0, cy - 25.0)
	add_child(cont)

	var frame := TextureRect.new()
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.size = Vector2(260, 50)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists("res://assets/sprites/menu/btn-frame.png"):
		frame.texture = load("res://assets/sprites/menu/btn-frame.png")
	cont.add_child(frame)

	# 文字 18px #3a1f00 stroke #ffe4a0 厚2, 居中
	var txt := _stroked_label(label, 18, "#3a1f00", "#ffe4a0", 2)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	txt.size = Vector2(260, 50)
	txt.position = Vector2(0, -2)
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cont.add_child(txt)

	var pressed_tex := "res://assets/sprites/menu/btn-frame-pressed.png"
	# hover scale→1.05 100ms
	frame.mouse_entered.connect(func():
		var tw := create_tween()
		tw.tween_property(cont, "scale", Vector2(1.05, 1.05), 0.1))
	frame.mouse_exited.connect(func():
		var tw := create_tween()
		tw.tween_property(cont, "scale", Vector2(1, 1), 0.1)
		if ResourceLoader.exists("res://assets/sprites/menu/btn-frame.png"):
			frame.texture = load("res://assets/sprites/menu/btn-frame.png"))
	frame.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if ResourceLoader.exists(pressed_tex):
				frame.texture = load(pressed_tex)
			# press scale→0.96 60ms yoyo
			var tw := create_tween()
			tw.tween_property(cont, "scale", Vector2(0.96, 0.96), 0.06)
			tw.tween_property(cont, "scale", Vector2(1, 1), 0.06)
			get_tree().create_timer(0.1).timeout.connect(cb))
	return txt


# ── icon 圆按钮 (PoC makeIconButton: r18, 黑0.55, 边#58d3ff→hover#ffd93d) ──
func _icon_button(cx: float, cy: float, icon: String, cb: Callable) -> void:
	var r := 18.0
	var btn := Control.new()
	btn.size = Vector2(r * 2.0, r * 2.0)
	btn.pivot_offset = Vector2(r, r)
	btn.position = Vector2(cx - r, cy - r)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(btn)
	var stroke := {"c": Color("#58d3ff")}
	var draw := func():
		btn.draw_circle(Vector2(r, r), r, Color(0, 0, 0, 0.55))
		btn.draw_arc(Vector2(r, r), r - 1.0, 0, TAU, 32, stroke["c"], 2.0)
	btn.draw.connect(draw)
	var txt := Label.new()
	txt.text = icon
	txt.add_theme_font_size_override("font_size", 18)
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


# ── helpers ──
func _stroked_label(t: String, size: int, color: String, stroke: String, thick: int) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(color))
	if thick > 0 and stroke != "":
		l.add_theme_constant_override("outline_size", thick)
		l.add_theme_color_override("font_outline_color", Color(stroke))
	return l


func _place_center(l: Label, cx: float, cy: float) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(400, float(l.get_theme_font_size("font_size")) + 16.0)
	l.position = Vector2(cx - 200.0, cy - l.size.y / 2.0)
	add_child(l)


func _mono_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["monospace", "Consolas", "Courier New"])
	f.fallbacks = [load("res://assets/fonts/NotoSansSC-Regular.otf")]   # CJK 网页/iOS 兜底 (SystemFont 在 web 取不到系统字体→中文乱码)
	return f


func _bg() -> void:
	# PoC (index.html menu-bg-active + BootScene:579): 菜单背景 = menu-bg-tile.png 平铺 (512px repeat)
	#   over 深绿底 #1a3a2a, 上叠暗渐变 ::after rgba(8,12,20,.15→.40). 不是 menu-bg.png 废墟图!
	#   1:1 复刻 MainMenuScene._bg(), 与主菜单无缝衔接.
	var base := ColorRect.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color(0.102, 0.227, 0.165)   # #1a3a2a 深绿底
	add_child(base)
	if ResourceLoader.exists("res://assets/sprites/menu/menu-bg-tile.png"):
		var tile := TextureRect.new()
		# PoC CSS background-size:512px → 把 tile 缩到 512² 再平铺 (图标密度对齐 Phaser)
		tile.texture = PreloadCache.menu_bg_tile_tex()   # 复用缓存512²纹理 (resize只做一次, 消除进场景LANCZOS卡顿)
		tile.stretch_mode = TextureRect.STRETCH_TILE
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 漂移 -512→0 / 25s linear 循环 (1:1 PoC menuBgDrift index.html:79/90, 同MainMenu) — 原静态不动是bug
		var vp := get_viewport_rect().size
		tile.size = Vector2(vp.x + 512, vp.y + 512)
		tile.position = Vector2(-512, -512)
		add_child(tile)
		var drift := tile.create_tween().set_loops()
		drift.tween_property(tile, "position", Vector2(0, 0), 25.0).from(Vector2(-512, -512)).set_trans(Tween.TRANS_LINEAR)
	# ::after 暗渐变遮罩 (顶 alpha.15 → 底 .40), 压暗背景
	# 显式设 offsets+colors (别用 set_color/add_point — Gradient 默认 offset1 是白点, 会漏成底部白光)
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
