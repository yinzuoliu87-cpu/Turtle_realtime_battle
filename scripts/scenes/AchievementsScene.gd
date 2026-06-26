extends Control

## AchievementsScene — 成就 (1:1 PoC AchievementsScene.ts): 4类Tab + 卡片网格 + 解锁状态.

const CATS := [["battle", "战斗"], ["collect", "收集"], ["progress", "进度"], ["special", "特殊"]]
const W := 1280.0
const H := 720.0
const CARD_W := 360.0
const CARD_H := 100.0

var current_cat: String = "battle"
var grid: GridContainer
var _tab_btns := {}   # cat_id -> Button


func _ready() -> void:
	_bg()

	# 返回 icon @ (40,40)
	_icon_button(40.0, 40.0, "←", func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))

	# 标题 @ (W/2, 50), 36px #ffd93d stroke #1a1a2e 厚5
	var unlocked: int = GameState.achievements_unlocked.size()
	var total: int = DataRegistry.achievements.size()
	var title := _stroked_label("🏆 成就 %d/%d" % [unlocked, total], 36, "#ffd93d", "#1a1a2e", 5)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(500, 52)
	title.position = Vector2(W / 2.0 - 250.0, 50.0 - 26.0)
	add_child(title)

	# ── Tab 行 @ tabY=110, 4 个 130×36, 间隔 140 中心 ──
	var tab_y := 110.0
	for i in range(CATS.size()):
		var c: Array = CATS[i]
		var cx := W / 2.0 + (float(i) - 1.5) * 140.0
		_tab(cx, tab_y, c[0], c[1])

	# ── 网格外框 @ gridX=60 gridY=170, gridW=W-120 gridH=H-200 ──
	#   边框2px #58d3ff@0.4 + 半透背景 (黑 0.4)
	var grid_x := 60.0
	var grid_y := 170.0
	var grid_w := W - 120.0
	var grid_h := H - 200.0
	var outer := Panel.new()
	var osb := StyleBoxFlat.new()
	osb.bg_color = Color(0, 0, 0, 0.4)
	osb.set_border_width_all(2)
	osb.border_color = Color(0x58 / 255.0, 0xd3 / 255.0, 0xff / 255.0, 0.4)
	outer.add_theme_stylebox_override("panel", osb)
	outer.position = Vector2(grid_x, grid_y)
	outer.size = Vector2(grid_w, grid_h)
	add_child(outer)

	# 滚动容器 (clip 在外框内)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(grid_x + 20.0, grid_y + 20.0)
	scroll.size = Vector2(grid_w - 40.0, grid_h - 40.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	_populate()


func _tab(cx: float, cy: float, cat_id: String, label: String) -> void:
	var btn := Button.new()
	btn.text = label
	btn.size = Vector2(130, 36)
	btn.position = Vector2(cx - 65.0, cy - 18.0)
	btn.add_theme_font_size_override("font_size", 15)
	btn.pressed.connect(func(): _switch(cat_id))
	add_child(btn)
	_tab_btns[cat_id] = btn
	_style_tab(btn, cat_id == current_cat)


# active 底#ffd93d 文字#1a1a2e / inactive 底#1a2740@0.95 文字#ffd93d, 边2px #ffd93d
func _style_tab(btn: Button, active: bool) -> void:
	var bg := Color("#ffd93d") if active else Color(0x1a / 255.0, 0x27 / 255.0, 0x40 / 255.0, 0.95)
	var fg := Color("#1a1a2e") if active else Color("#ffd93d")
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_border_width_all(2)
		sb.border_color = Color("#ffd93d")
		sb.set_corner_radius_all(4)
		btn.add_theme_stylebox_override(st, sb)
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(slot, fg)


func _switch(cat: String) -> void:
	# PoC scene.restart() 保留 currentCat 字段; Godot 用就地重绘 (重着色 tab + 重填网格).
	if cat == current_cat:
		return
	current_cat = cat
	for cid in _tab_btns:
		_style_tab(_tab_btns[cid], cid == current_cat)
	_populate()


func _populate() -> void:
	for c in grid.get_children():
		c.queue_free()
	for ach in DataRegistry.achievements:
		if ach.get("category", "") != current_cat:
			continue
		grid.add_child(_card(ach))


# 成就卡 360×100; 卡背 0x1a2740 alpha 解锁0.95/未0.5; 边框2px 解锁#ffd93d/未#666
func _card(ach: Dictionary) -> Control:
	var unlocked: bool = ach.get("id", "") in GameState.achievements_unlocked
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(CARD_W, CARD_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0x1a / 255.0, 0x27 / 255.0, 0x40 / 255.0, 0.95 if unlocked else 0.5)
	sb.set_border_width_all(2)
	sb.border_color = Color("#ffd93d") if unlocked else Color(0x66 / 255.0, 0x66 / 255.0, 0x66 / 255.0)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(0)
	pc.add_theme_stylebox_override("panel", sb)

	# 内容用绝对定位 (PoC Phaser 用容器内坐标)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(CARD_W, CARD_H)
	pc.add_child(inner)

	# emoji @ (-cardW/2+28, 0) center → inner (28, H/2), 40px; 未解锁 alpha .3
	var emoji := Label.new()
	emoji.text = ach.get("emoji", "🏆")
	emoji.add_theme_font_size_override("font_size", 40)
	emoji.add_theme_font_override("font", _mono_font())   # PoC AchievementsScene.ts:80 fontFamily:'monospace'
	emoji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emoji.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	emoji.size = Vector2(56, CARD_H)
	emoji.position = Vector2(0, 0)
	if not unlocked:
		emoji.modulate.a = 0.3
	inner.add_child(emoji)

	# name @ (-cardW/2+70, -22) origin(0,0.5), 16px bold, 解锁#ffd93d/未#888
	var nm := Label.new()
	nm.text = ach.get("name", "?")
	nm.add_theme_font_size_override("font_size", 16)
	nm.add_theme_color_override("font_color", Color("#ffd93d") if unlocked else Color("#888888"))
	nm.position = Vector2(70, CARD_H / 2.0 - 22.0 - 10.0)
	nm.size = Vector2(CARD_W - 100.0, 20)
	inner.add_child(nm)

	# desc @ (-cardW/2+70, 8) origin(0,0.5), 12px, wrap (cardW-100), 解锁#fff/未#666
	var ds := Label.new()
	ds.text = ach.get("desc", "")
	ds.add_theme_font_size_override("font_size", 12)
	ds.add_theme_color_override("font_color", Color("#ffffff") if unlocked else Color("#666666"))
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.position = Vector2(70, CARD_H / 2.0 + 8.0 - 14.0)
	ds.size = Vector2(CARD_W - 100.0, 40)
	inner.add_child(ds)

	# reward @ (cardW/2-12, -cardH/2+14) origin(1,0.5), 11px monospace
	if int(ach.get("rewardCoins", 0)) > 0:
		var rw := Label.new()
		rw.text = "🪙 %d" % int(ach.get("rewardCoins", 0))
		rw.add_theme_font_size_override("font_size", 11)
		rw.add_theme_font_override("font", _mono_font())   # PoC AchievementsScene.ts:100 fontFamily:'monospace'
		rw.add_theme_color_override("font_color", Color("#ffd93d") if unlocked else Color("#666666"))
		rw.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rw.position = Vector2(CARD_W - 12.0 - 80.0, 14.0 - 8.0)
		rw.size = Vector2(80, 16)
		inner.add_child(rw)

	# "✓ 已解锁" @ (cardW/2-12, cardH/2-14) origin(1,0.5), 11px #06d6a0 bold (独立文本)
	if unlocked:
		var done := Label.new()
		done.text = "✓ 已解锁"
		done.add_theme_font_size_override("font_size", 11)
		done.add_theme_color_override("font_color", Color("#06d6a0"))
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		done.position = Vector2(CARD_W - 12.0 - 80.0, CARD_H - 14.0 - 8.0)
		done.size = Vector2(80, 16)
		inner.add_child(done)

	return pc


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
	# PoC (index.html menu-bg-active): AchievementsScene 套主菜单 tile bg = menu-bg-tile.png 平铺 (512px repeat)
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
