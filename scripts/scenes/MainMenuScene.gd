extends Control

## MainMenuScene — 主菜单, 1:1 PoC MainMenuScene.ts 布局.
## 设计台 1280×720. 标题menu-title图@(240,130) / 左栏btn-frame按钮(360×87)中心x=240 /
## 右墙 frame-coin龟币框 + 4个frame-square磁贴(图鉴/教程/成就/战绩, 仅图标).

const W := 1280
const H := 720
const LEFT_CX := 240        # LEFT_PAD60 + BTN_W360/2
const BTN_W := 360
const BTN_H := 87           # 360×161/666
const BTN_GAP := 12
const GROUP_TOP := 280      # RIGHT_COL_TOP_Y
const WALL := 16
const TILE := 104
const TSTEP := 120
const TILE_TOP := 190
const FLY := 160.0          # 1:1 PoC MainMenuScene.FLY — 过场飞出/飞入竖直位移

var page_box: Control       # 当前页按钮容器
var _active_page: String = ""   # 当前页 (空=未加载); 过场用
var _title_node: Control = null # 标题节点 (主菜单专属, 参与过场飞出/入)
var _card_nodes: Array = []     # 右列龟币框 + 4 磁贴 (主菜单专属, 参与过场 — 1:1 PoC main 行含 cards)
var content_root: Control   # 内容层 (1280×720 设计框, 居中于真实视口); 背景另铺满全窗口
var _bg_tile: TextureRect   # 平铺图 (resize 时重设尺寸)


func _ready() -> void:
	await get_tree().process_frame
	# 1:1 PoC: 背景铺满整个窗口(无黑边), 内容 1280×720 居中。EXPAND → 视口随窗口比例扩展(不裁不缩内容)。
	#   16:9 屏 EXPAND 不扩展 = 与旧 FIT 完全一致(无回归); 非 16:9 时背景填满、内容居中。
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	await get_tree().process_frame   # 让视口按 EXPAND 重算尺寸再读
	Audio.play_bgm("menu", 1.0, 0.4)   # 1:1 PoC menu BGM volume 0.4
	_bg()                            # 背景层 → self 最底, 填满真实视口(含原黑边区)
	content_root = Control.new()     # 内容层 → 1280×720 设计框, 居中
	content_root.size = Vector2(W, H)
	content_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content_root)
	_center_content()
	_title()
	_right_column()
	page_box = Control.new()
	content_root.add_child(page_box)
	_show_page("main")
	get_viewport().size_changed.connect(_on_menu_resize)
	_maybe_ask_fullscreen()   # 1:1 PoC maybeAskFullscreen: 每会话一次问是否全屏


## 内容框居中于真实视口 (1:1 PoC FIT 居中); bg 在 self 上随视口自适应
func _center_content() -> void:
	if content_root != null:
		content_root.position = ((get_viewport_rect().size - Vector2(W, H)) / 2.0).round()


func _on_menu_resize() -> void:
	_center_content()
	var vp := get_viewport_rect().size
	if is_instance_valid(_bg_tile):
		_bg_tile.size = Vector2(vp.x + 512, vp.y + 512)


# 不再 _exit_tree 还原 KEEP: 项目级 aspect 已是 EXPAND(全场景统一), 离场不翻转 → 场景切换丝滑。
#   各场景背景铺满已各自处理(menu平铺/select-bg/Codex全锚), 无需切回 KEEP。


func _bg() -> void:
	# PoC (index.html menu-bg-active + BootScene:579): 菜单背景 = menu-bg-tile.png 平铺 (512px repeat)
	#   over 深绿底 #1a3a2a, 上叠暗渐变 ::after rgba(8,12,20,.15→.40). 不是 menu-bg.png 废墟图!
	var vp := get_viewport_rect().size   # 真实视口(EXPAND 后=窗口比例); bg 全填它, 含原黑边区
	var base := ColorRect.new(); base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color("#1a3a2a")   # 深绿底 — 用 PoC 字面色值, 不四舍五入
	add_child(base)
	if ResourceLoader.exists("res://assets/sprites/menu/menu-bg-tile.png"):
		var tile := TextureRect.new()
		# PoC CSS background-size:512px → 1946² tile 缩到 512² 平铺. + menuBgDrift 25s linear infinite 漂移
		tile.texture = PreloadCache.menu_bg_tile_tex()   # 复用缓存512²纹理 (resize只做一次, 消除进场景LANCZOS卡顿)
		tile.stretch_mode = TextureRect.STRETCH_TILE
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 比屏幕大一格(512) → 漂移时不露边; 512=一个tile周期 → -512→0 循环无缝 (1:1 @keyframes menuBgDrift 0→512px)
		tile.size = Vector2(vp.x + 512, vp.y + 512)
		tile.position = Vector2(-512, -512)
		add_child(tile)
		_bg_tile = tile
		var drift := tile.create_tween().set_loops()
		drift.tween_property(tile, "position", Vector2(0, 0), 25.0).from(Vector2(-512, -512)).set_trans(Tween.TRANS_LINEAR)
	# ::after 暗渐变遮罩 (顶 alpha.15 → 底 .40), 压暗背景
	# 显式设 offsets+colors (别用 set_color/add_point — Gradient 默认 offset1 是白点, 会漏成底部白光)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.colors = PackedColorArray([
		Color(8.0 / 255.0, 12.0 / 255.0, 20.0 / 255.0, 0.15),   # rgba(8,12,20,.15) 字面值
		Color(8.0 / 255.0, 12.0 / 255.0, 20.0 / 255.0, 0.25),
		Color(8.0 / 255.0, 12.0 / 255.0, 20.0 / 255.0, 0.40),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1); gt.width = 8; gt.height = 128
	var ov := TextureRect.new(); ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.texture = gt; ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ov.stretch_mode = TextureRect.STRETCH_SCALE
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ov)
	# (金色飘落粒子已移除 — 用户要求去掉; PoC 虽有 add.particles 但实机极淡, Godot 渲染显突兀)


func _title() -> void:
	# 标题图 menu-title.png. PoC MainMenuScene.ts:54-65:
	#   TITLE_W360 TITLE_H203, 中心 origin0.5; 起点 center=(LEFT_CX240, TITLE_BASE_Y130-180=-50),
	#   scale0.85 alpha0 → tween 到 center y130, scale TITLE_SCALE1.1, alpha1, duration550 delay250 EASE_MENU_IN.
	var anim_path := "res://assets/sprites/menu/menu-title-anim.png"
	var static_path := "res://assets/sprites/menu/menu-title.png"
	if ResourceLoader.exists(anim_path) or ResourceLoader.exists(static_path):
		var t := TextureRect.new()
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.size = Vector2(360, 203)
		t.pivot_offset = Vector2(180, 101.5)            # 绕中心缩放
		# PoC .menu-title-anim (index.html:97-105): menu-title-anim.png 5帧 421×237, steps(5) 1s 循环
		if ResourceLoader.exists(anim_path):
			var sheet: Texture2D = load(anim_path)
			var n := 5
			var fw: float = float(sheet.get_width()) / float(n)   # 2105/5 = 421
			var fh: float = float(sheet.get_height())             # 237
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(0.0, 0.0, fw, fh)
			t.texture = at
			content_root.add_child(t)
			var fanim := t.create_tween().set_loops()   # 帧循环 5fps (1s/5帧), int(f) 离散跳帧 ≈ steps(5)
			fanim.tween_method(func(f: float): at.region = Rect2(float(int(f) % n) * fw, 0.0, fw, fh), 0.0, float(n), float(n) * 0.2).set_trans(Tween.TRANS_LINEAR)
		else:
			t.texture = load(static_path)
			content_root.add_child(t)
		var end_top_y := 130.0 - 101.5                  # center130 → 左上 y
		var start_top_y := -50.0 - 101.5                # PoC 起点 center=-50 (TITLE_BASE_Y-180)
		t.position = Vector2(LEFT_CX - 180, start_top_y)
		t.scale = Vector2(0.85, 0.85); t.modulate.a = 0.0
		_title_node = t; t.set_meta("home_y", end_top_y)   # 参与过场: 记归位 y
		var tw := create_tween()
		tw.tween_interval(0.25)                          # PoC delay 250ms
		tw.tween_property(t, "position:y", end_top_y, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(t, "scale", Vector2(1.1, 1.1), 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(t, "modulate:a", 1.0, 0.55)
		return
	else:
		var l := Label.new(); l.text = "斗龟场"; l.add_theme_font_size_override("font_size", 80)
		l.add_theme_color_override("font_color", Color("#ffd93d")); l.position = Vector2(LEFT_CX - 150, 90); content_root.add_child(l)
		_title_node = l; l.set_meta("home_y", 90.0)


# ─── 左栏按钮页 (main / online / local / custom) ───
var _transitioning := false

func _show_page(page: String) -> void:
	# 首次加载: 各自入场 (按钮滑入; 标题/磁贴在 _title/_right_column 自带入场), 无过场
	if _active_page == "":
		_active_page = page
		_build_page_buttons(page, false)
		return
	if page == _active_page or _transitioning:
		return
	# 过场 (1:1 PoC goToScreen): 当前页全部飞出 → 目标页飞入。
	#   ★主菜单专属的 标题 + 右列磁贴 也一起飞 (PoC main 行 = [title, buttons, cards]) — 修"周围按钮圈没动"。
	_transitioning = true
	var leaving_main := _active_page == "main"
	var entering_main := page == "main"
	var out_objs: Array = []
	if leaving_main and is_instance_valid(_title_node):
		out_objs.append(_title_node)
	for c in page_box.get_children():
		if c is Control:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		out_objs.append(c)
	if leaving_main:
		for cd in _card_nodes:
			if is_instance_valid(cd):
				out_objs.append(cd)
	_active_page = page
	await _fly_out(out_objs)
	for c in page_box.get_children():
		c.queue_free()
	_build_page_buttons(page, true)
	var in_objs: Array = []
	if entering_main and is_instance_valid(_title_node):
		in_objs.append(_title_node)
	for c in page_box.get_children():
		in_objs.append(c)
	if entering_main:
		for cd in _card_nodes:
			if is_instance_valid(cd):
				in_objs.append(cd)
	await _fly_in(in_objs)
	_transitioning = false


## 飞出: 各对象上移 FLY + 淡出, 错峰 (1:1 PoC flyOut OUT=230ms STAG=45ms cubic.in)
func _fly_out(objs: Array) -> void:
	var last := 0.0
	for i in range(objs.size()):
		var o: Control = objs[i]
		if not is_instance_valid(o):
			continue
		var home_y: float = float(o.get_meta("home_y", o.position.y))
		var delay := i * 0.045
		last = maxf(last, delay + 0.23)
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(o, "position:y", home_y - FLY, 0.23).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(o, "modulate:a", 0.0, 0.23)
	await get_tree().create_timer(last + 0.02).timeout


## 飞入: 从下方 FLY 上移归位 + 淡入, 错峰回弹 (1:1 PoC flyIn IN=320ms STAG=55ms back.out)
func _fly_in(objs: Array) -> void:
	var last := 0.0
	for i in range(objs.size()):
		var o: Control = objs[i]
		if not is_instance_valid(o):
			continue
		var home_y: float = float(o.get_meta("home_y", o.position.y))
		o.visible = true
		o.position.y = home_y + FLY
		o.modulate.a = 0.0
		var delay := i * 0.055
		last = maxf(last, delay + 0.32)
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(o, "position:y", home_y, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(o, "modulate:a", 1.0, 0.32)
	await get_tree().create_timer(last + 0.02).timeout


## 建某页按钮. is_transition: true=过场(只建+定位+home_y meta, alpha0, 由 flyIn 接管); false=首次加载各自入场
func _build_page_buttons(page: String, is_transition: bool) -> void:
	var items: Array = []
	var centered := page != "main"   # 主菜单在左栏, 子菜单居中
	match page:
		"main":
			items = [["在线模式", func(): _show_page("online"), false], ["⚔ 实时战斗", func(): _go("RealtimeBattle"), false], ["🛒 商店", func(): _go("Shop"), false], ["🎒 背包", func(): _go("Inventory"), false], ["设置", func(): _go("Settings"), false]]
		"online":
			# 1:1 PoC: 联机未实装 → 按钮可点, 点击弹「敬请期待」toast (非禁用灰)
			items = [["快速匹配 (推塔)", func(): GameState.mode = "duallane"; GameState.clear_team(); GameState.reset_dual_lane(); get_tree().change_scene_to_file("res://scenes/Matchmaking.tscn"), false], ["🏆 排行榜", func(): _go("Leaderboard"), false], ["房间对战", func(): _show_coming_soon_toast(), false], ["← 返回", func(): _show_page("main"), false]]
		"local":
			# 上线版只有 推塔玩法 (双路龟蛋): 在线=PvP, 野生=PvE. 深海闯关/指定Boss/老单局3v3 已移除(用户 2026-06-12).
			items = [["野生对局 (推塔)", func(): GameState.mode = "duallane"; GameState.clear_team(); GameState.reset_dual_lane(); get_tree().change_scene_to_file("res://scenes/Matchmaking.tscn"), false]]
			if OS.is_debug_build():
				items.append(["测试模式", _on_test, false])
			items.append(["← 返回", func(): _show_page("main"), false])
	var n := items.size()
	var btn_spacing := BTN_H + BTN_GAP
	var cx := W / 2 if centered else LEFT_CX
	var cy0 := (H / 2 - (n - 1) * btn_spacing / 2.0) if centered else (GROUP_TOP + BTN_H / 2.0)
	for i in range(n):
		var it: Array = items[i]
		var b := _frame_button(it[0], it[1], it[2])
		var center := Vector2(cx, cy0 + i * btn_spacing)
		b.position = center - Vector2(BTN_W / 2.0, BTN_H / 2.0)
		b.set_meta("home_y", b.position.y)   # 过场归位 y
		page_box.add_child(b)
		b.modulate.a = 0.0
		if is_transition:
			continue   # flyIn 统一接管位置/alpha
		var tw := create_tween()
		if not centered:
			# 首次加载主菜单: 从左滑入 (PoC duration420 delay550+80i)
			b.position.x = -560.0
			tw.tween_interval(0.55 + 0.08 * i)
			tw.tween_property(b, "position:x", center.x - BTN_W / 2.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(b, "modulate:a", 1.0, 0.42)
		else:
			tw.tween_interval(0.06 * i)
			tw.tween_property(b, "modulate:a", 1.0, 0.28)


## btn-frame.png 金色边框按钮 (NinePatchRect 9宫格保证渲染 + 透明Button点击 + 文字)
## 进游戏问是否全屏 (1:1 PoC maybeAskFullscreen:260) — 每会话一次(static flag), 已全屏则跳过.
static var _fs_asked := false

func _maybe_ask_fullscreen() -> void:
	if _fs_asked:
		return
	var m := get_window().mode
	if m == Window.MODE_FULLSCREEN or m == Window.MODE_EXCLUSIVE_FULLSCREEN:
		return
	_fs_asked = true
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(4.0 / 255.0, 8.0 / 255.0, 14.0 / 255.0, 0.6)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var box := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("#12202a")
	bsb.border_color = Color("#ffd93d")
	bsb.set_border_width_all(2)
	bsb.set_corner_radius_all(14)
	bsb.content_margin_left = 30; bsb.content_margin_right = 30
	bsb.content_margin_top = 24; bsb.content_margin_bottom = 24
	bsb.shadow_color = Color(1, 217.0 / 255.0, 107.0 / 255.0, 0.3); bsb.shadow_size = 16
	box.add_theme_stylebox_override("panel", bsb)
	center.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	box.add_child(vb)
	var title := Label.new()
	title.text = "全屏体验更佳"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#ffd93d"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var txt := Label.new()
	txt.text = "现在进入全屏吗？\n(随时可在「设置」里切换)"
	txt.add_theme_font_size_override("font_size", 14)
	txt.add_theme_color_override("font_color", Color("#ccddee"))
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(txt)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	var no := _fs_dialog_btn("暂不", Color("#9aabbb"), Color("#1a2330"), Color("#3a4a5e"))
	no.pressed.connect(func() -> void: layer.queue_free())
	row.add_child(no)
	var yes := _fs_dialog_btn("进入全屏", Color("#ffd93d"), Color("#2a1a40"), Color("#ffd93d"))
	yes.pressed.connect(func() -> void:
		get_window().mode = Window.MODE_FULLSCREEN
		layer.queue_free())
	row.add_child(yes)
	# fade-in .2s (PoC overlay opacity 0→1)
	layer_modulate_fade(veil, center)


## 全屏弹窗按钮 (1:1 PoC no/yes 钮样式)
func _fs_dialog_btn(label: String, fg: Color, bg: Color, border: Color) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 26; sb.content_margin_right = 26
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", sb)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func layer_modulate_fade(veil: ColorRect, center: CenterContainer) -> void:
	veil.modulate.a = 0.0
	center.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(veil, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(center, "modulate:a", 1.0, 0.2)


## 「敬请期待」toast (1:1 PoC showComingSoonToast MainMenuScene.ts:873): 底中14% fade-in.18s→1.8s→fade-out
func _show_coming_soon_toast(msg: String = "联机功能开发中, 敬请期待") -> void:
	var old := get_node_or_null("ComingSoonToast")
	if old:
		old.queue_free()
	var toast := PanelContainer.new()
	toast.name = "ComingSoonToast"
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(10.0 / 255.0, 14.0 / 255.0, 24.0 / 255.0, 0.92)
	sb.border_color = Color("#ffd166")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 22; sb.content_margin_right = 22
	sb.content_margin_top = 10; sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.5); sb.shadow_size = 10
	toast.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color("#ffe9a8"))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(lbl)
	add_child(toast)
	await get_tree().process_frame   # 等 PanelContainer 量好尺寸再居中
	if not is_instance_valid(toast):
		return
	var vp := get_viewport_rect().size
	toast.position = Vector2(vp.x / 2.0 - toast.size.x / 2.0, vp.y * 0.86 - toast.size.y)
	toast.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, 0.18)
	tw.tween_interval(1.8)
	tw.tween_property(toast, "modulate:a", 0.0, 0.18)
	tw.tween_callback(toast.queue_free)


func _frame_button(label: String, cb: Callable, disabled: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(BTN_W, BTN_H)
	holder.size = Vector2(BTN_W, BTN_H)
	holder.pivot_offset = Vector2(BTN_W / 2.0, BTN_H / 2.0)   # hover/press 绕中心缩放
	# 木框背景 menu-frame-rect = frame-rect.png — Phaser setDisplaySize 整图拉伸, TextureRect STRETCH_SCALE 1:1
	var frame_path := "res://assets/sprites/menu/frame-rect.png"
	if not ResourceLoader.exists(frame_path):
		frame_path = "res://assets/sprites/menu/btn-frame.png"
	var frame_node: TextureRect = null
	if ResourceLoader.exists(frame_path):
		frame_node = TextureRect.new()
		frame_node.texture = load(frame_path)
		frame_node.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame_node.stretch_mode = TextureRect.STRETCH_SCALE
		frame_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# PoC ts:314 bg.setAlpha(0.95); 禁用走灰 tint (ts:311)
		frame_node.modulate = Color(0.6, 0.6, 0.6, 0.95) if disabled else Color(1, 1, 1, 0.95)
		holder.add_child(frame_node)
	# 透明 Button 接点击 (flat 无样式, 不盖金框)
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.disabled = disabled
	btn.focus_mode = Control.FOCUS_NONE
	holder.add_child(btn)
	# 文字 = 1:1 PoC addDomText: 22px 雅黑Bold, 填充#3a1f00, "描边"实为 4 方向 text-shadow(±1px 金#ffe4a0)
	#   (dom-text.ts:43-48 — 非 outline 轮廓扩张! 故不能用 Godot outline_size, 要 4 个偏移金副本)
	var fill := Color("#8b7755") if disabled else Color("#3a1f00")
	holder.add_child(_make_stroked_label(label, 22, fill, Color("#ffe4a0")))
	# hover/press 动画 (PoC ts:358-375): hover scale1.04 + 暖金 tint; 点击 press scale0.96 → 渲染1帧 → 回弹+回调
	if not disabled:
		btn.mouse_entered.connect(_btn_hover.bind(holder, frame_node, true))
		btn.mouse_exited.connect(_btn_hover.bind(holder, frame_node, false))
		# PoC ts:370-375: pointerdown → setScale(0.96) → delayedCall(16) → resetVisual + onClick。
		#   旧版 pressed.connect(cb) 在松手同帧立刻 change_scene → press 缩放没机会渲染 = "点了没动画"。
		btn.button_down.connect(_btn_press.bind(holder, frame_node, cb))
	return holder


## 1:1 PoC addDomText 描边 = 4 方向 text-shadow (非 outline): 4 个 ±1px 金副本在底 + 主填充在上
func _make_stroked_label(text: String, size: int, fill: Color, stroke: Color) -> Control:
	var wrap := Control.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for off in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var s := _menu_label(text, size, stroke)
		s.offset_left = off.x; s.offset_right = off.x
		s.offset_top = off.y; s.offset_bottom = off.y
		wrap.add_child(s)
	wrap.add_child(_menu_label(text, size, fill))   # 主填充在最上
	return wrap


func _menu_label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_font_override("font", _bold_font())
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 加粗字体 (1:1 PoC fontWeight:'bold' = 雅黑 Bold/weight700 真粗体)。
## 旧版 variation_embolden=1.0 假粗 → 中文字形外扩破填充, 看着"空心/描边"。改用 CJK 回退请求真 700 字重。
var _bold_font_cache: FontVariation = null
func _bold_font() -> FontVariation:
	if _bold_font_cache == null:
		var cjk := SystemFont.new()
		cjk.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Hiragino Sans GB", "Noto Sans CJK SC", "WenQuanYi Micro Hei", "sans-serif"])
		cjk.fallbacks = [load("res://assets/fonts/NotoSansSC-Regular.otf")]   # CJK 网页/iOS 兜底 (SystemFont 在 web 取不到系统字体→中文乱码)
		cjk.font_weight = 700              # 真粗体 (= PoC YaHei Bold), 非 embolden 膨胀
		cjk.allow_system_fallback = true
		# 中文平滑抗锯齿 (修"锯齿"): m6x11 像素字 import antialiasing=0, 但中文不能跟着关 AA。
		#   灰度 AA + 自动亚像素 + 不强制 hinting → 接近浏览器渲染雅黑的平滑度。
		cjk.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		cjk.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		cjk.hinting = TextServer.HINTING_NONE
		_bold_font_cache = FontVariation.new()
		_bold_font_cache.base_font = load("res://assets/fonts/m6x11.ttf") as FontFile   # 英文/数字像素打底
		_bold_font_cache.fallbacks = [cjk]                                              # 中文走雅黑 Bold
		_bold_font_cache.variation_embolden = 0.0    # 中文粗体已走 cjk.font_weight=700; 不用 embolden(会糙边)
	return _bold_font_cache


## 按钮 hover 视觉 (PoC ts:358-371) — 从中心缩放
func _btn_hover(holder: Control, frame_node: TextureRect, on: bool) -> void:
	if is_instance_valid(holder):
		holder.pivot_offset = holder.size / 2.0   # 中心缩放 (PoC setScale 绕 origin center)
		holder.scale = Vector2(1.04, 1.04) if on else Vector2(1, 1)
	if is_instance_valid(frame_node):
		frame_node.modulate = Color(1.0, 0.941, 0.753, 1.0) if on else Color(1, 1, 1, 0.95)


## 按钮点击: press 0.96 → 等 16ms (PoC delayedCall(16), 保证 press 渲染≥1帧) → 回弹 + 切场景回调
func _btn_press(holder: Control, frame_node: TextureRect, cb: Callable) -> void:
	if is_instance_valid(holder):
		holder.pivot_offset = holder.size / 2.0
		holder.scale = Vector2(0.96, 0.96)
	await get_tree().create_timer(0.016).timeout
	if is_instance_valid(holder):
		_btn_hover(holder, frame_node, false)
	if cb.is_valid():
		cb.call()


# ─── 右墙: 龟币框 + 4磁贴 (frame-square, 仅图标) ───
func _right_column() -> void:
	# 龟币框 frame-coin 152×85 中心(1280-16-76, 78)
	var coin := Control.new()
	coin.position = Vector2(W - WALL - 152, 78 - 42)
	content_root.add_child(coin)
	_card_nodes.append(coin); coin.set_meta("home_y", coin.position.y)   # 参与过场
	if ResourceLoader.exists("res://assets/sprites/menu/frame-coin.png"):
		var cf := TextureRect.new(); cf.texture = load("res://assets/sprites/menu/frame-coin.png")
		cf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; cf.stretch_mode = TextureRect.STRETCH_SCALE
		cf.size = Vector2(152, 85); coin.add_child(cf)
	# 绿色龟币图标 (PoC ts:604 Lucide coins 描边绿#1f8f3f). ui/coin.png 是黑线稿 → 把非透明像素染绿
	if ResourceLoader.exists("res://assets/sprites/ui/coin.png"):
		var cimg: Image = load("res://assets/sprites/ui/coin.png").get_image()
		var green := Color(0.122, 0.561, 0.247)   # #1f8f3f
		for yy in range(cimg.get_height()):
			for xx in range(cimg.get_width()):
				var px := cimg.get_pixel(xx, yy)
				if px.a > 0.0:
					cimg.set_pixel(xx, yy, Color(green.r, green.g, green.b, px.a))
		var ci := TextureRect.new(); ci.texture = ImageTexture.create_from_image(cimg)
		ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ci.size = Vector2(36, 36); ci.position = Vector2(76 - 39.5 - 18, 42 - 18); coin.add_child(ci)
	# 龟币数字: 深绿 #2c4a1e 22px (PoC ts:608-609 浅羊皮纸框上深字), 左对齐于 cx+W*0.02≈79
	var cl := Label.new(); cl.text = "%d" % GameState.coins
	cl.position = Vector2(79, 0); cl.size = Vector2(73, 85)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cl.add_theme_font_size_override("font_size", 22); cl.add_theme_color_override("font_color", Color("#2c4a1e")); coin.add_child(cl)
	# 入场: 龟币框为 cards[0], 4 磁贴 cards[1..4]; PoC ts:199-201 slide x→home + alpha, dur420 delay 850+60i
	_slide_in(coin, 0)
	# 4 磁贴 (图鉴/教程/成就/战绩) — PoC BootScene key→file: codex-icon, ui/help-button, menu/icon-achievements, menu/icon-record
	var defs := [
		["menu/codex-icon", "图鉴", func(): _go("Codex")],
		["ui/help-button", "教程", func(): _on_tutorial()],
		["menu/icon-achievements", "成就", func(): _go("Achievements")],
		["menu/icon-record", "战绩", func(): _go("Record")],
	]
	# 战绩磁贴显示 "X胜 Y负" (1:1 PoC makeSquareTile subValue, recordValue = total>0 ? `${w}胜 ${l}负` : '')
	var _w: int = GameState.battles_won
	var _total: int = GameState.battles_total
	var _rec := "%d胜 %d负" % [_w, maxi(0, _total - _w)] if _total > 0 else ""
	var tx := W - WALL - TILE   # 左上 x (磁贴右边缘贴墙)
	for i in range(4):
		var d: Array = defs[i]
		var sub_v: String = _rec if d[1] == "战绩" else ""
		var tile := _tile(d[0], d[1], d[2], Vector2(tx, TILE_TOP + i * TSTEP - TILE / 2.0), sub_v)
		content_root.add_child(tile)
		_card_nodes.append(tile); tile.set_meta("home_y", tile.position.y)   # 参与过场
		_slide_in(tile, i + 1)
	# V2 赛季状态条: 第N大轮 + 命 + 深海币 (设计§八 主菜单显示). 深色半透底条压住背景斗兽场, 保证可读 (截图发现原裸字对比度低)
	var v2bg := PanelContainer.new()
	var v2sb := StyleBoxFlat.new()
	v2sb.bg_color = Color(0.04, 0.10, 0.16, 0.74)   # 深海蓝半透
	v2sb.set_corner_radius_all(8)
	v2sb.content_margin_left = 12; v2sb.content_margin_right = 12
	v2sb.content_margin_top = 5; v2sb.content_margin_bottom = 5
	v2bg.add_theme_stylebox_override("panel", v2sb)
	v2bg.position = Vector2(16, 12)
	content_root.add_child(v2bg)
	var v2 := Label.new()
	v2.text = "🏆 第 %d 大轮   ·   Lv %d   ·   ❤ 命 %d/8   ·   💠 深海币 %d" % [int(GameState.season_id), int(GameState.season_level), int(GameState.hearts), int(GameState.meta_deepsea_coins)]
	v2.add_theme_font_size_override("font_size", 20)
	v2.add_theme_color_override("font_color", Color("#ffe9a8"))
	v2bg.add_child(v2)


## 右栏卡片入场: 从右(贴墙外)滑入 + 淡入. PoC delay 850+60*idx, dur420.
func _slide_in(holder: Control, idx: int) -> void:
	var home_x := holder.position.x
	holder.position.x = home_x + 60.0
	holder.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.85 + 0.06 * idx)
	tw.tween_property(holder, "position:x", home_x, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(holder, "modulate:a", 1.0, 0.42)


func _tile(icon_key: String, label: String, cb: Callable, pos: Vector2, sub_value: String = "") -> Control:
	var holder := Control.new()
	holder.position = pos
	holder.custom_minimum_size = Vector2(TILE, TILE)
	holder.size = Vector2(TILE, TILE)
	var btn := TextureButton.new()
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.ignore_texture_size = true; btn.stretch_mode = TextureButton.STRETCH_SCALE
	if ResourceLoader.exists("res://assets/sprites/menu/frame-square.png"):
		btn.texture_normal = load("res://assets/sprites/menu/frame-square.png")
	# 磁贴 hover/press (PoC ts:585-588: hover scale1.06 / press0.97 + delayedCall(60))
	if cb.is_valid():
		btn.mouse_entered.connect(_tile_hover.bind(holder, true))
		btn.mouse_exited.connect(_tile_hover.bind(holder, false))
		btn.button_down.connect(_tile_press.bind(holder, cb))
	holder.add_child(btn)
	var ipath := "res://assets/sprites/%s.png" % icon_key   # icon_key 已含子目录 (menu/.. 或 ui/..)
	if icon_key != "" and ResourceLoader.exists(ipath):
		var ic := TextureRect.new(); ic.texture = load(ipath)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 有 subValue(战绩) 时图标缩到 0.58 + 上移 size*0.10 给文字让位 (1:1 PoC makeSquareTile)
		var has_sub := sub_value != ""
		var isz := roundi(TILE * (0.58 if has_sub else 0.62))   # PoC ts:574
		var iy_off := -TILE * 0.10 if has_sub else -6.0
		ic.size = Vector2(isz, isz); ic.position = Vector2((TILE - isz) / 2.0, (TILE - isz) / 2.0 + iy_off)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE; holder.add_child(ic)
		if has_sub:
			var vl := Label.new()
			vl.text = sub_value
			vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			vl.add_theme_font_size_override("font_size", 13)
			vl.add_theme_color_override("font_color", Color("#ffd966"))
			vl.size = Vector2(TILE, 16); vl.position = Vector2(0, TILE / 2.0 + TILE * 0.34 - 8.0)
			vl.mouse_filter = Control.MOUSE_FILTER_IGNORE; holder.add_child(vl)
	else:
		var tl := Label.new(); tl.text = label; tl.set_anchors_preset(Control.PRESET_FULL_RECT)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tl.add_theme_font_size_override("font_size", 22); tl.mouse_filter = Control.MOUSE_FILTER_IGNORE; holder.add_child(tl)
	return holder


## 磁贴 hover (PoC ts:585 scale1.06) — 从中心缩放
func _tile_hover(holder: Control, on: bool) -> void:
	if is_instance_valid(holder):
		holder.pivot_offset = holder.size / 2.0
		holder.scale = Vector2(1.06, 1.06) if on else Vector2(1, 1)


## 磁贴点击 press (PoC ts:587-588 scale0.97 + delayedCall(60)) → 回弹 + 回调
func _tile_press(holder: Control, cb: Callable) -> void:
	if is_instance_valid(holder):
		holder.pivot_offset = holder.size / 2.0
		holder.scale = Vector2(0.97, 0.97)
	await get_tree().create_timer(0.06).timeout
	if is_instance_valid(holder):
		holder.scale = Vector2(1, 1)
	if cb.is_valid():
		cb.call()


# ─── 路由 ───
func _go(scene: String) -> void:
	get_tree().change_scene_to_file("res://scenes/%s.tscn" % scene)

func _on_test() -> void:
	# 测试模式(仅debug build): 改为快速进双路推塔(=正式玩法). 旧深海闯关/老单局3v3已废 → 不再走 (用户 2026-06-23)
	GameState.mode = "duallane"; GameState.clear_team(); GameState.reset_dual_lane()
	get_tree().change_scene_to_file("res://scenes/Matchmaking.tscn")


## 教程: 确认弹窗 → 固定阵容教程战斗 (1:1 PoC confirmStartTutorial → startTutorialBattle, 直进 Battle 不经选龟)
func _on_tutorial() -> void:
	if has_node("TutorialConfirm"):
		return
	var ov := ColorRect.new()
	ov.name = "TutorialConfirm"
	ov.color = Color(0, 0, 0, 0.6)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := PanelContainer.new()
	box.anchor_left = 0.5; box.anchor_top = 0.5; box.anchor_right = 0.5; box.anchor_bottom = 0.5
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH; box.grow_vertical = Control.GROW_DIRECTION_BOTH
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("#16213a"); bsb.set_border_width_all(2); bsb.border_color = Color("#ffd93d")
	bsb.set_corner_radius_all(12)
	bsb.content_margin_left = 36; bsb.content_margin_right = 36; bsb.content_margin_top = 28; bsb.content_margin_bottom = 28
	box.add_theme_stylebox_override("panel", bsb)
	ov.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16); vb.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(vb)
	var t := Label.new()
	t.text = "新手教程"; t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 20); t.add_theme_color_override("font_color", Color("#ffd93d"))
	vb.add_child(t)
	var d := Label.new()
	d.text = "是否开始龟龟对战教程？"; d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.add_theme_font_size_override("font_size", 15); d.add_theme_color_override("font_color", Color("#dfe6f0"))
	vb.add_child(d)
	var bh := HBoxContainer.new()
	bh.alignment = BoxContainer.ALIGNMENT_CENTER; bh.add_theme_constant_override("separation", 14)
	vb.add_child(bh)
	var start_btn := Button.new()
	start_btn.text = "开始教程"; start_btn.custom_minimum_size = Vector2(120, 40)
	start_btn.add_theme_color_override("font_color", Color("#3a1f00"))
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color("#ffc23c"); ssb.set_corner_radius_all(8)
	start_btn.add_theme_stylebox_override("normal", ssb)
	start_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bh.add_child(start_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"; cancel_btn.custom_minimum_size = Vector2(96, 40)
	cancel_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bh.add_child(cancel_btn)
	start_btn.pressed.connect(func() -> void:
		# mode 用玩家可控的 single (含经济/商店); tutorial 标记正交 (1:1 PoC mode:'pve'+tutorial:true)
		GameState.mode = "single"; GameState.tutorial = true; GameState.dungeon_stage = 1
		GameState.dungeon_carry_hp = {}; GameState.dungeon_dead_ids = []
		GameState.clear_team()
		get_tree().change_scene_to_file("res://scenes/Battle.tscn"))
	cancel_btn.pressed.connect(func() -> void: ov.queue_free())
	add_child(ov)
