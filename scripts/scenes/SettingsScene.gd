extends Control

## SettingsScene — 设置 (1:1 PoC SettingsScene.ts): BGM/SFX 音量 + 全屏 + 重置存档.
## Phaser 绝对坐标 (中心原点) → Godot 左上 (position = 中心 - size/2). 视口 1280×720.

const W := 1280.0
const H := 720.0

var _perf_btn: Label = null
var _full_btn: Label = null   # 全屏按钮文字 (切换后要同步, 原来没接住 → 切了还写"全屏")


func _ready() -> void:
	_bg()

	# 标题 @ (W/2, 80), 40px #ffd93d stroke #1a1a2e 厚5
	var title := _stroked_label("设置", 40, "#ffd93d", "#1a1a2e", 5)
	_place_center(title, W / 2.0, 80.0)

	# 返回 icon 按钮 @ (40,40)
	_icon_button(40.0, 40.0, "←", func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))

	# BGM 滑条 @ (W/2, 220) — 拖动实时生效; 写盘只在松手时一次 (原来每帧 save() = 拖一下写几十次盘)
	_slider(W / 2.0, 220.0, "🎵 BGM 音量", GameState.bgm_volume,
		func(v): GameState.bgm_volume = v; Audio.bgm_volume = v; Audio.apply_bgm_volume(),   # ★补: 原来只设变量没调 apply → 拖动对正在播的BGM无效(用户2026-07-19"音量键根本没效果")
		func(): GameState.save())
	# SFX 滑条 @ (W/2, 330) — 松手才试听 + 写盘 (原来拖动中每帧都播音效)
	_slider(W / 2.0, 330.0, "🔊 音效音量", GameState.sfx_volume,
		func(v): GameState.sfx_volume = v; Audio.sfx_volume = v,
		func(): Audio.play_sfx("hit-physical", 1.0); GameState.save())

	# 全屏 @ (W/2, 410) — PoC 用 ⛶(U+26F6) 做图标, 但打包字体链无此字形(web/linux 豆腐块)且无等义替代 → 只留文字
	_full_btn = _text_button(W / 2.0, 410.0, _fullscreen_label(), _toggle_fullscreen)

	# 低画质模式 @ (W/2, 490) — 现在是【真开关】: 关 MSAA + 3D 渲染分辨率 ×0.75 + 停菜单背景漂移; 持久化到存档.
	_perf_btn = _text_button(W / 2.0, 490.0, _perf_label(), _toggle_perf)


	# 重置存档 @ (W/2, 580) — ⚠ 破坏性 → 二次确认
	_text_button(W / 2.0, 580.0, "⚠ 重置所有存档", _ask_reset)

	# 底部提示 @ (W/2, H-40), 11px #888
	var hint := _stroked_label("设置自动保存", 11, "#888888", "", 0)   # PoC 字面是"到 localStorage"(浏览器术语), Godot 存 user:// → 去掉误导后缀
	_place_center(hint, W / 2.0, H - 40.0)


## ESC 返回主菜单 (原来只能点左上角箭头)
	# ★UI 双端适配(用户2026-08-01「有些画面都没有居中」): 把内容装进 1280×720 设计框并居中于真实视口。
	#   本屏原先直接按设计坐标画在视口(0,0) → 21:9 上内容整体坐在左边 200px(审计器实测)。
	#   ★必须放在 _ready 最后 —— UIFrame 收编的是【已经建出来的】子节点。
	#   (异步晚建的节点由 UIFrame._process 的孤儿收编兜住。)
	UIFrame.attach(self)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _confirm_layer != null and is_instance_valid(_confirm_layer):
			_confirm_layer.queue_free()   # 确认框开着 → ESC 先取消
			return
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _fullscreen_label() -> String:
	var m := DisplayServer.window_get_mode()
	if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		return "退出全屏"
	return "全屏"


## ★2026-08-19 缩短: 原文「🪶 低画质模式: 关 (高画质)」在 260 宽的木牌里**装不下** ——
##   木牌两端的花纹柱实测各占 29px, 内部只有 202px, 而这行字的墨迹约 240px ⇒ 字骑在花纹上。
##   (实拍看出来的; 门禁原来查不到, 因为它只把 StyleBoxTexture/NinePatchRect 当框,
##    而这里的框是一个**拉伸的 TextureRect**。已一并补进 verify_ui_consistency。)
##   "开/关" 也去掉了 —— 按钮显示的是**当前是什么**, 不是"这个开关的开关状态", 后者要绕一圈才读懂。
func _perf_label() -> String:
	if GameState.perf_lite:
		return "🪶 画质: 低"
	return "🪶 画质: 高"


## 低画质模式 = 真开关 (原来只改自己的 label, grep 全库无第二处引用 = 死按钮)
## 实际效果见 `apply_perf_lite()` (战斗视口) 与各菜单场景的背景漂移 gate。
func _toggle_perf() -> void:
	GameState.perf_lite = not GameState.perf_lite
	GameState.save()
	if _perf_btn != null:
		_perf_btn.text = _perf_label()
	## 按钮上只剩"高/低", 于是把"低=更流畅"这条信息挪到 toast 里, 不然玩家不知道调它图什么。
	_toast("画质已设为%s%s · 下次进战斗生效" % [
		"低" if GameState.perf_lite else "高",
		" (更流畅)" if GameState.perf_lite else ""])


func _toggle_fullscreen() -> void:
	var m := DisplayServer.window_get_mode()
	var to_full: bool = not (m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if to_full else DisplayServer.WINDOW_MODE_WINDOWED)
	GameState.fullscreen = to_full
	GameState.save()                      # 持久化: 原来切了不存, 重启回窗口
	if _full_btn != null:
		_full_btn.text = _fullscreen_label()   # 同步文字: 原来 Label 没接住, 切了还写"全屏"


# ── 重置存档: ⚠ 破坏性, 必须二次确认 ──────────────────────────
var _confirm_layer: Control = null

func _ask_reset() -> void:
	if _confirm_layer != null and is_instance_valid(_confirm_layer):
		return
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_confirm_layer = dim

	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ff5566")
	sb.set_border_width_all(3); sb.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(W / 2.0 - 260, H / 2.0 - 130); box.size = Vector2(520, 260)
	dim.add_child(box)

	var ttl := Label.new()
	ttl.text = "⚠ 重置所有存档？"
	ttl.add_theme_font_size_override("font_size", 26)
	ttl.add_theme_color_override("font_color", Color("#ff5566"))
	ttl.position = Vector2(0, 22); ttl.size = Vector2(520, 36)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ttl)

	var msg := Label.new()
	msg.text = "将清空：深海币 · 背包装备 · 出战统领 · 赛季进度(命/等级/胜场) · 糖果罐 · 布阵。\n**此操作不可撤销。**（音量/全屏/画质等偏好设置不受影响）"
	msg.add_theme_font_size_override("font_size", 15)
	msg.add_theme_color_override("font_color", Color("#c9d6e2"))
	msg.position = Vector2(30, 74); msg.size = Vector2(460, 90)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(msg)

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.position = Vector2(70, 186); cancel.size = Vector2(160, 44)
	cancel.pressed.connect(func(): dim.queue_free(); _confirm_layer = null)
	box.add_child(cancel)

	var ok := Button.new()
	ok.text = "确认清空"
	ok.add_theme_font_size_override("font_size", 18)
	ok.add_theme_color_override("font_color", Color("#ff8a94"))
	ok.position = Vector2(290, 186); ok.size = Vector2(160, 44)
	ok.pressed.connect(func():
		dim.queue_free(); _confirm_layer = null
		_do_reset())
	box.add_child(ok)


func _do_reset() -> void:
	GameState.reset_save()
	_toast("✓ 存档已清空")


# ── 滑条 (PoC renderSlider, track w=380, handle r14) ──
## cb        = 拖动中每次变化都调 (实时生效, 不写盘)
## on_release= 松手/点轨道时调一次 (写盘 / 试听音效). 原实现在 cb 里 save()+play_sfx → 拖一下写几十次盘、爆音。
func _slider(cx: float, cy: float, label: String, init: float, cb: Callable, on_release: Callable = Callable()) -> void:
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
	# ★2026-08-01: handle 不再自己吃事件 —— 它只有 28×28(手机上 15pt), 是个点不中的把手。
	#   拖拽统一交给下面那条 48px 高的透明命中条(整行都能拖), 视觉不变、可拖范围大得多。
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(handle)

	var apply := func(px: float):
		var clamped: float = clampf(px, left, left + track_w)
		var v: float = (clamped - left) / track_w
		handle.position.x = clamped - 14.0
		fill.size.x = track_w * v
		pct.text = "%d%%" % int(round(v * 100.0))
		cb.call(v)

	# (原来挂在 handle 上的拖拽已删: handle 现在 mouse_filter=IGNORE, 那段代码永远收不到事件 ——
	#  留着就是一段"看起来在工作"的死代码。拖拽全走下面的命中条。)
	# 点轨道跳 (即刻应用 + 一次 on_release)
	# ★手机板触控热区(用户2026-08-01): 轨道本体只有 8px 高 = 手机上【4pt】, 手指绝无可能点中;
	#   handle 也只有 28px(15pt)。所以另铺一条【透明命中条】盖住整行(48px 高 = 26pt),
	#   点/拖它都等价于点轨道 —— 视觉一点没变, 可点范围从 4pt 变成 26pt。
	#   ★命中条要在 handle 【之前】加(add_child 顺序=绘制/命中顺序), 否则它会盖住 handle 的拖拽。
	var hit := Control.new()
	hit.size = Vector2(track_w, 48.0)
	hit.position = Vector2(left, cy - 24.0)
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(hit)
	move_child(hit, handle.get_index())   # 排到 handle 前面
	hit.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			apply.call(hit.global_position.x + ev.position.x)
			if on_release.is_valid(): on_release.call()
		elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			apply.call(hit.global_position.x + ev.position.x))
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 命中交给 hit, 轨道只负责显示
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE


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
## ★手机板触控热区(2026-08-01): 半径 18(=36×36 视口像素=20pt) → 24(=48×48=26pt)。
##   视觉圆环仍按原比例画, 只是可点范围变大 —— 图标按钮加内边距不影响构图。
func _icon_button(cx: float, cy: float, icon: String, cb: Callable) -> void:
	var r := 24.0
	## ★2026-08-19 命中区与视觉解耦: 原来 btn.size 就是圆环的外接方(48x48=26pt), 够不着 44pt。
	##   圆环半径 r 一个字不改(构图不能动), 只把**控件本身**撑到 81x81(=44pt), 圆画在正中间。
	##   —— 图标按钮周围本来就是空白, 扩命中区不影响任何相邻元素。
	const HIT := 81.0
	var c0 := HIT * 0.5          # 圆心在控件里的坐标
	var btn := Control.new()
	btn.size = Vector2(HIT, HIT)
	btn.pivot_offset = Vector2(c0, c0)
	btn.position = Vector2(cx - c0, cy - c0)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(btn)
	var stroke := {"c": Color("#58d3ff")}
	var draw := func():
		btn.draw_circle(Vector2(c0, c0), r, Color(0, 0, 0, 0.55))
		btn.draw_arc(Vector2(c0, c0), r - 1.0, 0, TAU, 32, stroke["c"], 2.0)
	btn.draw.connect(draw)
	var txt := Label.new()
	txt.text = icon
	txt.add_theme_font_size_override("font_size", 18)
	txt.add_theme_color_override("font_color", Color("#ffffff"))
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	txt.size = Vector2(HIT, HIT)
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
	# CJK + emoji 兜底 (SystemFont 在 web/linux 取不到系统字体 → 中文乱码/emoji 豆腐块)
	f.fallbacks = [
		load("res://assets/fonts/NotoSansSC-Regular.otf"),
		load("res://assets/fonts/NotoEmoji-Regular.ttf"),
	]
	return f


## 轻量提示 (1.4s 后淡出)
func _toast(msg: String) -> void:
	var l := _stroked_label(msg, 16, "#06d6a0", "", 0)
	_place_center(l, W / 2.0, 650.0)
	l.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.2)
	tw.tween_interval(1.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)


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
		if not (GameState != null and GameState.perf_lite):   # 低画质: 不跑常驻背景漂移 tween
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
