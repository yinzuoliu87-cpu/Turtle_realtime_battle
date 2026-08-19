extends Control

## MainMenuScene — 主菜单, 1:1 PoC MainMenuScene.ts 布局.
## 设计台 1280×720. 标题menu-title图@(240,130) / 左栏btn-frame按钮(360×87)中心x=240 /
## 右墙 frame-coin龟币框 + 4个frame-square磁贴(图鉴/教程/排行榜/战绩, 仅图标).

const W := 1280
const H := 720
const LEFT_CX := 240        # LEFT_PAD60 + BTN_W360/2
const BTN_W := 360
const BTN_H := 87           # 360×161/666
                            # 排行榜/图鉴/教程/战绩 走右侧 4 磁贴。4×(87+12)=396 → 234..630 < 720, 不溢出。
                            # 〔原注释写"5 入口…排行榜"= 陈旧, 排行榜早就挪到右侧磁贴了〕
const WALL := 16
const TILE := 104

## ── 左栏按钮栈的几何 (2026-08-15 版式体检) ──
## ★抽成常量是因为【右信息板要和这个栈对齐到同一条竖直带】: 两边各写各的坐标,
##   就是上一版右下角空出 560×161 一大块、而左栏比右栏长 140px 的根因。
##   verify_mainmenu_layout 会量真实 rect 断言两栏首尾各差 ≤2px。
const HERO_SIZE := Vector2(384.0, 100.0)   # 主 CTA。原 384×96 (4.00:1) 略扁, 加高到 3.84:1 且过 44pt 触摸线
const HERO_CY := 302.0
const HERO_GRID_GAP := 24.0
const GRID_SIZE := Vector2(196.0, 82.0)    # 2×2 次级键
const GRID_GAP := Vector2(14.0, 14.0)
## 训龟大师: 原 300×62 (4.84:1, 全场最扁) 且离 2×2 网格 71px = 看着像掉队的孤儿。
## 改成与网格同高 82 (3.66:1), 并按网格自己的 14px 节奏紧贴其下 —— 归队, 不再单飞。
const TRAINER_SIZE := Vector2(300.0, 82.0)
const PANEL_W := 560.0                     # 右信息板宽 (右边缘贴墙)
const REC_H := 82.0                        # 战绩行高 = 触摸线 81px 之上
const ROW_TAIL_W := 18.0                   # 信息板每行右侧留的尾列(只有战绩行填 ›) → 各行【值】右沿严格对齐

## 字号层级 (原来 hero27 / 面板标题25 / 次级22 / 行20 —— 主次只差 5 号, 分不出层)
const FONT_HERO := 30
const FONT_PANEL_TITLE := 24
const FONT_BTN := 22
const FONT_ROW := 21
const FONT_VERSION := 16

var page_box: Control       # 当前页按钮容器
var content_root: Control   # 内容层 (1280×720 设计框, 居中于真实视口); 背景另铺满全窗口
var _bg_tile: TextureRect   # 平铺图 (resize 时重设尺寸)


func _ready() -> void:
	if OS.has_environment("PH_DEMO"):   # dev: 模拟大轮开局(未打第一场) → 看商店键灰锁
		GameState.season_total_battles = 0
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
	_build_page_buttons()
	# 🛠 调试场入口: 【只在开发构建/显式 DEVTOOLS 下出现】。
	#   原来无条件建 → 正式包里玩家能点进自由摆位调试场。OS.is_debug_build() 在导出 release 模板下为 false。
	if OS.is_debug_build() or OS.has_environment("DEVTOOLS"):
		_debug_arena_entry()
	get_viewport().size_changed.connect(_on_menu_resize)
	# (去掉全屏询问弹窗·用户2026-07-18「去掉这个全屏提示」; _maybe_ask_fullscreen 保留未调用, 需要可在设置里切全屏)
	# ★首次打开强制新手教学(用户2026-07-23)。判据: 从没走完过教学(onboarded=false)。
	#   ONBOARD=1/0 可强制开/关, 供开发与门禁 —— 否则本机跑一次就 onboarded=true, 再也测不到。
	_maybe_first_launch_tutorial()


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
		if not (GameState != null and GameState.perf_lite):   # 低画质: 不跑常驻背景漂移 tween
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
		var tw := create_tween()
		tw.tween_interval(0.25)                          # PoC delay 250ms
		tw.tween_property(t, "position:y", end_top_y, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(t, "scale", Vector2(1.1, 1.1), 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(t, "modulate:a", 1.0, 0.55)
		return
	else:
		var l := Label.new(); l.text = "斗龟场"; l.add_theme_font_size_override("font_size", 80)
		l.add_theme_color_override("font_color", Color("#ffd93d")); l.position = Vector2(LEFT_CX - 150, 90); content_root.add_child(l)


# ─── 左栏按钮页 (实时版: 单一干净主菜单, 无子页过场) ───
## 实时版重做: 去掉回合制残留的多页(online/local)+过场飞出/飞入逻辑.
##   主菜单就一组清晰按钮(各自从左滑入入场), 点击直接 _go 切场景, 不再有页间过场.
##   (2026-08-15 删掉了只剩一页还在传"页名"的 _show_page/_active_page —— 单页了就别再演多页。)


## 左栏按钮栈的上/下沿 —— 右信息板靠这两个数与左栏对齐, 所以必须【一个来源】。
func _stack_top() -> float:
	return HERO_CY - HERO_SIZE.y / 2.0


## 2×2 网格第一行的中心 y
func _grid_cy0() -> float:
	return HERO_CY + HERO_SIZE.y / 2.0 + HERO_GRID_GAP + GRID_SIZE.y / 2.0


## 2×2 网格的下沿 (第二行底)
func _grid_bottom() -> float:
	return _grid_cy0() + (GRID_SIZE.y + GRID_GAP.y) + GRID_SIZE.y / 2.0


func _stack_bottom() -> float:
	return _grid_bottom() + GRID_GAP.y + TRAINER_SIZE.y


## 建左栏英雄区 (正式化重排·用户2026-07-18「左英雄+右信息板·保留金框」):
##   Logo 下 → 大「开始战斗」英雄键(焦点·主 CTA) → 2×2 次级键(背包/商店/图鉴/排行榜·统一金框)
##   → 训龟大师(紧贴网格下方, 同高同节奏).
##   设置/教程 挪到右上工具簇, 战绩 挪到右信息板 (见 _right_column). 各键从左滑入错峰入场.
func _build_page_buttons() -> void:
	var eliminated := GameState.is_eliminated()   # 0命=本大轮淘汰(用户2026-07-24拍板"淘汰锁定") → 锁匹配+商店, 只"设置→重置存档"解锁
	# ── 英雄键: ⚔ 开始战斗 (最大·居左栏中轴·主 CTA) ──
	var hero_size := HERO_SIZE
	var hero_center := Vector2(LEFT_CX, HERO_CY)
	var hero := _frame_button("⚔  开始战斗", func(): _start_battle_flow(), false, hero_size, FONT_HERO, "", eliminated)
	hero.position = hero_center - hero_size / 2.0
	page_box.add_child(hero)
	if eliminated:
		_add_lock_badge(hero, hero_size)
	_slide_in_left(hero, 0)
	# ── 2×2 次级键: 背包/商店/图鉴/排行榜 (同金框·64px像素图标+文字·左右两列·用户2026-07-18图标化) ──
	var gsz := GRID_SIZE
	var gap_x := GRID_GAP.x
	var gap_y := GRID_GAP.y
	var col_dx := (gsz.x + gap_x) / 2.0                      # 两列中心相对左栏中轴 ±col_dx
	var grid_cy0 := _grid_cy0()
	var mic := "res://assets/sprites/menu/"
	var subs: Array = [
		["背包", func(): _go("Inventory"), mic + "ic-bag.png"],
		["商店", func(): _open_shop(), mic + "ic-shop.png"],
		["图鉴", func(): _go("Codex"), mic + "ic-codex.png"],
		["排行榜", func(): _go("Leaderboard"), mic + "ic-trophy.png"],
	]
	var shop_locked := int(GameState.season_total_battles) <= 0 or eliminated   # 商店锁: 大轮未打第一场(2026-07-18) OR 已淘汰(2026-07-24) → 灰显+🔒
	for i in range(subs.size()):
		var s: Array = subs[i]
		var r := i / 2                                       # 行 0,0,1,1
		var c := i % 2                                       # 列 0,1,0,1
		var center := Vector2(LEFT_CX - col_dx + float(c) * (gsz.x + gap_x), grid_cy0 + float(r) * (gsz.y + gap_y))
		var locked := (str(s[0]) == "商店") and shop_locked   # 商店锁 → 灰显+🔒角标, 但仍可点→toast提示为啥锁
		var b := _frame_button(s[0], s[1], false, gsz, FONT_BTN, str(s[2]), locked)
		b.position = center - gsz / 2.0
		page_box.add_child(b)
		if locked:
			_add_lock_badge(b, gsz)
		_slide_in_left(b, i + 1)
	# ── 训龟大师 独立键(用户2026-07-23: 配形象 + 主动技能) —— 不挤进 2×2, 但【紧贴】其下 ──
	#    原来 300×62 且离网格 71px(网格自己行距才 14) —— 又扁又落单, 看着像忘了删的一条。
	#    现在同高 82、同 14px 节奏 ⇒ 归到同一组; 顺带让整栈下沿从 683 收到 650, 不再压住左下角调试场。
	var tsz := TRAINER_SIZE
	var tb := _frame_button("🐢 训龟大师", func(): _go("TrainerConfig"), false, tsz, FONT_BTN, "")
	tb.position = Vector2(LEFT_CX - tsz.x / 2.0, _grid_bottom() + gap_y)
	page_box.add_child(tb)
	_slide_in_left(tb, subs.size() + 1)


## 左栏键入场: 从屏外左侧滑入 + 淡入, 错峰 (保留原 PoC 好动画)
func _slide_in_left(holder: Control, idx: int) -> void:
	var home_x := holder.position.x
	holder.modulate.a = 0.0
	holder.position.x = -560.0
	var tw := create_tween()
	tw.tween_interval(0.5 + 0.08 * float(idx))
	tw.tween_property(holder, "position:x", home_x, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(holder, "modulate:a", 1.0, 0.42)


## 锁定角标: 右上角 🔒 (商店未开时叠在灰框上, 一眼看出锁着)
func _add_lock_badge(holder: Control, size: Vector2) -> void:
	var lock := Label.new()
	lock.text = "🔒"
	lock.add_theme_font_size_override("font_size", 26)
	lock.position = Vector2(size.x - 36.0, 2.0)
	lock.size = Vector2(32, 32)
	lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lock)


## btn-frame.png 金色边框按钮 (NinePatchRect 9宫格保证渲染 + 透明Button点击 + 文字)
func _frame_button(label: String, cb: Callable, disabled: bool, size: Vector2 = Vector2(BTN_W, BTN_H), font_size: int = 22, icon_path: String = "", locked: bool = false) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = size
	holder.size = size
	holder.pivot_offset = size / 2.0   # hover/press 绕中心缩放
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
		frame_node.modulate = Color(0.6, 0.6, 0.6, 0.95) if (disabled or locked) else Color(1, 1, 1, 0.95)
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
	var fill := Color("#8b7755") if (disabled or locked) else Color("#3a1f00")
	var lbl := _make_stroked_label(label, font_size, fill, Color("#ffe4a0"))
	holder.add_child(lbl)
	# 左侧 64px 图标(用户2026-07-18: 图标化+协调) — 文字移到图标右侧区居中(避让, 不遮)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var isz: float = size.y * 0.62
		var ix: float = size.x * 0.09
		var ic := TextureRect.new()
		ic.texture = load(icon_path)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size = Vector2(isz, isz)
		ic.position = Vector2(ix, (size.y - isz) / 2.0)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(ic)
		var lx: float = ix + isz + 6.0
		lbl.set_anchors_preset(Control.PRESET_TOP_LEFT)
		lbl.position = Vector2(lx, 0.0)
		lbl.size = Vector2(size.x - lx - size.x * 0.06, size.y)
	# hover/press 动画 (PoC ts:358-375): hover scale1.04 + 暖金 tint; 点击 press scale0.96 → 渲染1帧 → 回弹+回调
	if not disabled:
		if locked:
			btn.pressed.connect(cb)   # 锁定态: 保持灰(不做会重置灰的hover/press动画), 但仍可点→cb出toast提示
		else:
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
		# 回退链: 系统雅黑Bold(桌面美观, 顺带给彩色emoji) → 【打包 Noto SC】(web/linux 无系统字体时的中文兜底)
		#         → 【打包 Noto Emoji】(单色 emoji 兜底, 防豆腐块). 原来只挂 cjk(SystemFont) = 无系统字体时中文/emoji 全掉字形。
		_bold_font_cache.fallbacks = [
			cjk,
			load("res://assets/fonts/NotoSansSC-Regular.otf") as FontFile,
			load("res://assets/fonts/NotoEmoji-Regular.ttf") as FontFile,
		]
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


# ─── 右上工具簇(设置/教程/龟币) + 右信息板(赛季进度/战绩) — 正式化重排(用户2026-07-18) ───
#   去掉旧的右侧 4 磁贴竖列 + 左上赛季裸条; 信息统一进右侧金边信息板, 设置/教程收进右上小磁贴.
func _right_column() -> void:
	# ── 右上一排: [教程][设置] 方形磁贴 + 龟币框 (右边缘贴墙) ──
	var coin := _coin_frame()
	coin.position = Vector2(W - WALL - 152, 30)
	content_root.add_child(coin)
	_slide_in(coin, 0)
	# 磁贴 62 → 82: 62px 在手机上只有 34pt, 低于 iOS HIG 的 44pt(=本项目 81 视口像素, 见 tests/_probe_ui_layout.gd)。
	# 82 同时更贴近旁边 85 高的龟币框, 三者读起来才是一排。
	var usz := 82.0
	var uy := 30.0 + (85.0 - usz) / 2.0                       # 与龟币框竖直居中对齐
	var set_x := float(W - WALL - 152) - 14.0 - usz
	var help_x := set_x - 10.0 - usz
	var set_tile := _tile("", "⚙", func(): _go("Settings"), Vector2(set_x, uy), "", usz)
	content_root.add_child(set_tile)
	_slide_in(set_tile, 1)
	var help_tile := _tile("ui/help-button", "❓", func(): _on_tutorial(), Vector2(help_x, uy), "", usz)
	content_root.add_child(help_tile)
	_slide_in(help_tile, 2)
	# ── 右信息板: 赛季进度(大轮/Lv/命/深海币) + 战绩(可点→Record) ──
	_info_panel()
	_version_stamp()


## 右下角版本号 —— 版本号最大的实际价值就是【测试者报 bug 时能说清是哪个版本】。
## ★必须从 ProjectSettings 读, 不许写死字符串: 写死就等于多一份会漂的副本,
##   而 iOS/Android/游戏内三处版本号曾经就是各说各的(无 / 0.9.0 / 1.0)。
##   门禁 verify_version 会断言这里没有硬编码版本号。
func _version_stamp() -> void:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	if v == "":
		return
	var l := _menu_label("v%s" % v, FONT_VERSION, Color("#7f8a99"))
	# ★★2026-08-01 修「版本号在主菜单上根本看不见」(审计器量出来的, 不是看像素猜的):
	#   _menu_label 里设了 set_anchors_preset(PRESET_FULL_RECT) —— 锚点 right/bottom = 1,
	#   于是【下一帧布局会按父容器重算 size】, 把这里设的 (200,22) 冲掉, 实测变成 1480×744。
	#   再叠上 HORIZONTAL_ALIGNMENT_RIGHT, 文字被画到那个巨框的右端 ≈ x 2544 —— 屏幕外。
	#   审计器 tests/_probe_ui_layout.gd 报: @Label@42 超出右 1064~1264 · 尺寸 1480x744。
	#   ★修法是把锚点先掰回 TOP_LEFT, 再设 size/position; 只改 size 不改锚点是没用的。
	#   版本号的全部价值 = 测试者报 bug 时能说清是哪个版本(CLAUDE.md §2.5), 看不见 = 等于没有。
	l.set_anchors_preset(Control.PRESET_TOP_LEFT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size = Vector2(200, 22)
	l.custom_minimum_size = Vector2(200, 22)
	l.position = Vector2(W - WALL - 200, H - WALL - 22)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(l)


## 龟币框 (frame-coin + 绿龟币图标染色 + 数字) — 抽出复用; 返回未定位的 Control, 调用方定位/入场
func _coin_frame() -> Control:
	var coin := Control.new()
	coin.custom_minimum_size = Vector2(152, 85); coin.size = Vector2(152, 85)
	if ResourceLoader.exists("res://assets/sprites/menu/frame-coin.png"):
		var cf := TextureRect.new(); cf.texture = load("res://assets/sprites/menu/frame-coin.png")
		cf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; cf.stretch_mode = TextureRect.STRETCH_SCALE
		cf.size = Vector2(152, 85); coin.add_child(cf)
	if ResourceLoader.exists("res://assets/sprites/ui/coin.png"):   # 黑线稿→非透明像素染绿(#1f8f3f)
		var cimg: Image = load("res://assets/sprites/ui/coin.png").get_image()
		var green := Color(0.122, 0.561, 0.247)
		for yy in range(cimg.get_height()):
			for xx in range(cimg.get_width()):
				var px := cimg.get_pixel(xx, yy)
				if px.a > 0.0:
					cimg.set_pixel(xx, yy, Color(green.r, green.g, green.b, px.a))
		var ci := TextureRect.new(); ci.texture = ImageTexture.create_from_image(cimg)
		ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ci.size = Vector2(36, 36); ci.position = Vector2(76 - 39.5 - 18, 42 - 18); coin.add_child(ci)
	var cl := Label.new(); cl.text = "%d" % GameState.coins
	cl.position = Vector2(79, 0); cl.size = Vector2(73, 85)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cl.add_theme_font_size_override("font_size", 22); cl.add_theme_color_override("font_color", Color("#2c4a1e")); coin.add_child(cl)
	return coin


## 右信息板: 金边深蓝卡(保留金框) — 赛季进度(大轮/Lv/命/深海币) + 战绩(可点→Record)
##
## ★2026-08-15 版式体检修的两件事:
##   ① 板高原来"随内容"(≈307), 顶 236 底 543, 而左栏按钮栈跑到 683 —— 右下角白白空出
##      560×161 一大块, 两栏首尾各差 100+px。现在板【首尾都焊在左栏按钮栈上】(_stack_top/_stack_bottom),
##      两栏成为同一条竖直带; 多出来的高度由一个 EXPAND 空档吃掉, 把战绩行压到板底。
##   ② 战绩行原来是 `"📜  战绩          %s      ›"` —— 用空格凑对齐, 值落在 x≈880,
##      而它上面三行的值是右对齐到 x≈1230 的。同一张卡里两套对齐 = 一眼就看得出歪。
##      现在战绩行直接复用 _panel_row 建, 列宽由同一个函数决定, 想歪也歪不了。
func _info_panel() -> void:
	var px := float(W - WALL) - PANEL_W                        # 右边缘贴墙
	var py := _stack_top()                                     # 顶沿 = 左栏按钮栈顶沿
	var panel := PanelContainer.new()
	panel.position = Vector2(px, py)
	panel.custom_minimum_size = Vector2(PANEL_W, _stack_bottom() - _stack_top())
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.10, 0.16, 0.96)             # 深海蓝近实心(正式化·防背景图标透出)
	sb.border_color = Color("#ffd93d"); sb.set_border_width_all(2)   # 金边(保留金框)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 28; sb.content_margin_right = 28
	sb.content_margin_top = 24; sb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", sb)
	content_root.add_child(panel)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 18)
	panel.add_child(vb)
	var hd := Label.new(); hd.text = "🐢  赛季进度"
	hd.add_theme_font_size_override("font_size", FONT_PANEL_TITLE); hd.add_theme_color_override("font_color", Color("#ffd93d"))
	vb.add_child(hd)
	# 大轮=奖杯图标 / 深海币=深海币图标(64px像素·用户2026-07-18) · 命=红心符号(无图标资产·确定性单色)
	var mic := "res://assets/sprites/menu/"
	vb.add_child(_panel_row("🏆", "第 %d 大轮" % int(GameState.season_id), "Lv %d" % int(GameState.season_level), Color("#ffd93d"), mic + "ic-trophy.png"))
	vb.add_child(_panel_row("♥", "剩余命数", "%d / 8" % int(GameState.hearts), Color("#ff6b6b")))
	vb.add_child(_panel_row("◆", "深海币", "%d" % int(GameState.meta_deepsea_coins), Color("#4fc3f7"), mic + "ic-deepsea.png"))
	# 多余的高度全给这个空档 → 上半是赛季数据、板底是战绩键, 板不再"随内容长短乱缩"
	var pad := Control.new()
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(pad)
	var sep := HSeparator.new()
	var sls := StyleBoxLine.new(); sls.color = Color(1.0, 0.85, 0.24, 0.35); sls.thickness = 1
	sep.add_theme_stylebox_override("separator", sls)
	vb.add_child(sep)
	var _w: int = GameState.battles_won
	var _total: int = GameState.battles_total
	var _rec := "%d 胜 %d 负" % [_w, maxi(0, _total - _w)] if _total > 0 else "暂无战绩"
	var rec := Button.new()
	rec.custom_minimum_size = Vector2(0.0, REC_H)             # ≥81 视口像素 = 44pt 触摸线(原来只有 48)
	rec.focus_mode = Control.FOCUS_NONE
	rec.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# 左右 content_margin 归零 → 行内容与上面三行【共用同一条左右基准线】(否则整行内缩 10px 又是一种歪)
	var rn := StyleBoxFlat.new(); rn.bg_color = Color(1, 1, 1, 0.04); rn.set_corner_radius_all(8)
	var rh := rn.duplicate() as StyleBoxFlat; rh.bg_color = Color(1.0, 0.85, 0.24, 0.16)
	rec.add_theme_stylebox_override("normal", rn)
	rec.add_theme_stylebox_override("hover", rh)
	rec.add_theme_stylebox_override("pressed", rh)
	rec.pressed.connect(func(): _go("Record"))
	var rrow := _panel_row("📜", "战绩", _rec, Color("#dfe6f0"), "", "›")
	rrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	rrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rec.add_child(rrow)
	vb.add_child(rec)


## 信息板一行: 图标 + 名称(左, 撑开) + 值(右) + 尾列
## ★尾列 (ROW_TAIL_W) 每行都有, 只有战绩行往里填 "›"。
##   它存在的唯一理由: 让【值】的右沿在所有行上严格相等 —— 战绩行多一个箭头,
##   不给别的行留出同宽的位, 它的值就会比上面三行往左偏一个箭头的宽度。
func _panel_row(icon: String, name_txt: String, value: String, icon_col: Color = Color("#dfe6f0"), icon_tex: String = "", tail: String = "") -> Control:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10)
	if icon_tex != "" and ResourceLoader.exists(icon_tex):   # 64px像素图标(用户2026-07-18)
		var it := TextureRect.new(); it.texture = load(icon_tex)
		it.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; it.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		it.custom_minimum_size = Vector2(34, 32); it.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(it)
	else:
		var ic := Label.new(); ic.text = icon; ic.add_theme_font_size_override("font_size", FONT_ROW)
		ic.add_theme_color_override("font_color", icon_col)
		ic.custom_minimum_size = Vector2(34, 0); ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(ic)
	var nm := Label.new(); nm.text = name_txt; nm.add_theme_font_size_override("font_size", FONT_ROW)
	nm.add_theme_color_override("font_color", Color("#dfe6f0"))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(nm)
	var vv := Label.new(); vv.text = value; vv.add_theme_font_size_override("font_size", FONT_ROW)
	vv.add_theme_color_override("font_color", Color("#ffe9a8"))
	vv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(vv)
	var tl := Label.new(); tl.text = tail; tl.add_theme_font_size_override("font_size", FONT_ROW)
	tl.add_theme_color_override("font_color", Color("#ffd93d"))
	tl.custom_minimum_size = Vector2(ROW_TAIL_W, 0)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(tl)
	return h


## 右栏卡片入场: 从右(贴墙外)滑入 + 淡入. PoC delay 850+60*idx, dur420.
func _slide_in(holder: Control, idx: int) -> void:
	var home_x := holder.position.x
	holder.position.x = home_x + 60.0
	holder.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.85 + 0.06 * idx)
	tw.tween_property(holder, "position:x", home_x, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(holder, "modulate:a", 1.0, 0.42)


func _tile(icon_key: String, label: String, cb: Callable, pos: Vector2, sub_value: String = "", sz: float = float(TILE)) -> Control:
	var holder := Control.new()
	holder.position = pos
	holder.custom_minimum_size = Vector2(sz, sz)
	holder.size = Vector2(sz, sz)
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
		var isz := roundi(sz * (0.58 if has_sub else 0.72))   # 无sub图标(教程❓)填满些 (原0.62偏小)
		var iy_off := -sz * 0.10 if has_sub else 0.0          # 无sub → 正居中(原-6上偏→与旁边⚙不齐·歪·用户2026-07-18)
		ic.size = Vector2(isz, isz); ic.position = Vector2((sz - isz) / 2.0, (sz - isz) / 2.0 + iy_off)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE; holder.add_child(ic)
		if has_sub:
			var vl := Label.new()
			vl.text = sub_value
			vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			vl.add_theme_font_size_override("font_size", 13)
			vl.add_theme_color_override("font_color", Color("#ffd966"))
			vl.size = Vector2(sz, 16); vl.position = Vector2(0, sz / 2.0 + sz * 0.34 - 8.0)
			vl.mouse_filter = Control.MOUSE_FILTER_IGNORE; holder.add_child(vl)
	else:
		var tl := Label.new(); tl.text = label; tl.set_anchors_preset(Control.PRESET_FULL_RECT)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tl.add_theme_font_size_override("font_size", roundi(sz * 0.44)); tl.mouse_filter = Control.MOUSE_FILTER_IGNORE; holder.add_child(tl)
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


# ─── 🛠 调试场入口 (右下角; 开发用自由摆位测试场) ───
const _RB_DEBUG := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

func _debug_arena_entry() -> void:
	var b := Button.new()
	b.text = "🛠 调试场"
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color("#ffe9a8"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.10, 0.16, 0.82)
	sb.border_color = Color("#ffd93d")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14; sb.content_margin_right = 14
	sb.content_margin_top = 7; sb.content_margin_bottom = 7
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# ★原来钉在左下角 (16, 666) 120×38, 而「训龟大师」键跨 y 621..683 x 90..390
	#   —— 两者实打实重叠 46×17 px, 调试构建里点训龟大师的左下角会点到调试场。
	#   现在挪到左右两栏之间那条空档 (左栏右沿 443 / 信息板左沿 704), 谁也不压。
	#   高度 38→46: 仍低于 81 视口像素的触摸线, 但它是【开发工具·正式包不出现】,
	#   为它把玩家版式撑大不划算 —— 门禁里显式豁免并写明原因, 不是"忘了量"。
	b.size = Vector2(120, 46)   # ★维持 46: 见上方注释 —— 调试构建专用, 已在门禁显式豁免; 撑到 81 会顶出屏底
	b.position = Vector2(452, H - 46 - WALL)
	content_root.add_child(b)
	b.pressed.connect(_open_debug_arena)

func _open_debug_arena() -> void:
	_RB_DEBUG.DEBUG_EDIT = true    # 调试场=自由摆位编辑器(左键摆龟/拖拽/右键删/装备笔刷/开始暂停·用户2026-07-12恢复)
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.set("dual_active", false)   # 清双路态
	get_tree().change_scene_to_file("res://scenes/RealtimeBattle3D.tscn")


# ─── 路由 ───
## 切场景。找不到目标 → 不切、打印错误 (原来直接 change_scene_to_file, 打错名字就静默黑屏)
func _go(scene: String) -> void:
	var path := "res://scenes/%s.tscn" % scene
	if not ResourceLoader.exists(path):
		push_error("[MainMenu] 目标场景不存在: " + path)
		return
	get_tree().change_scene_to_file(path)


## 商店入口: 大轮未打第一场 → 上锁不进(用户2026-07-18); 打完第一场解锁
func _open_shop() -> void:
	if GameState.is_eliminated():
		_toast("💀 赛季已淘汰 · 设置→重置存档 重开赛季")
		return
	if int(GameState.season_total_battles) <= 0:
		_toast("🔒 本大轮打完第一场才开店")
		return
	_go("Shop")


## 轻提示: 顶部飘一行金字, 1.4s 后淡出
func _toast(msg: String) -> void:
	var t := Label.new()
	t.text = msg
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", Color("#ffd93d"))
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	t.add_theme_constant_override("outline_size", 5)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var vw := get_viewport_rect().size.x
	t.position = Vector2(vw / 2.0 - 320.0, 120.0); t.size = Vector2(640, 40)
	t.z_index = 200
	add_child(t)
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(t, "modulate:a", 0.0, 0.5)
	tw.tween_callback(t.queue_free)


## 开始战斗 → 选龟流程 (实时版): 选龟(TeamSelect) → 匹配(Matchmaking) → 2.5D 战斗(RealtimeBattle3D).
##   非教程的常规入口. mode 置 single (含经济, 非教程标记). 进选龟前清掉上局对手快照, 让 Matchmaking 重抽.
func _start_battle_flow() -> void:
	if GameState.is_eliminated():   # 大轮淘汰锁(用户2026-07-24): 0命封匹配, 只重置存档解锁
		_toast("💀 赛季已淘汰 · 设置→重置存档 重开赛季")
		return
	GameState.mode = "single"
	GameState.tutorial = false
	GameState.dual_ghost = {}
	GameState.dual_opponent = {}
	GameState.dual_active = true   # 常规开始战斗 = 双路对局(分路/小将/蛋/半场流程)
	_go("TeamSelect")


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
		ov.queue_free()
		_begin_tutorial(false))   # ❓ 手动重玩: 可跳过(mandatory=false)
	cancel_btn.pressed.connect(func() -> void: ov.queue_free())
	add_child(ov)


## 首次打开 → 强制走教学(不弹确认框、不能跳)。已走完(onboarded)则不触发。
func _maybe_first_launch_tutorial() -> void:
	if OS.get_environment("ONBOARD") == "0":
		return   # 显式关(测试/开发)
	var force := OS.get_environment("ONBOARD") == "1"
	# ★只在【真正作为当前主场景】时触发 —— 冒烟/门禁把主菜单当子节点 instantiate() 时,
	#   get_tree().current_scene 不是它, 这时 change_scene 会搅乱人家的场景树(smoke 报 44 条 null)。
	#   force(ONBOARD=1)时放行, 供门禁真跑首次流程。
	if not force and get_tree().current_scene != self:
		return
	if not force and GameState.onboarded:
		return   # 走完过, 不再强制
	if not force and GameState.tutorial_active:
		return   # 已经在教学里(防重入)
	_begin_tutorial(true)   # 首次: mandatory=true(无跳过)


## 统一的教学启动: 从【选龟界面】进第一把(教选龟+站位)。mandatory=首次不能跳。
## ★沙盒(tutorial_active): 不给奖励(_settle_season 直接 return)、固定阵容、弱对手。
## ★走完整流程(选龟→双路战斗含摆位), 但选龟界面只显 3 只教学龟(用户2026-07-23)。
func _begin_tutorial(mandatory: bool) -> void:
	GameState.tutorial = true
	GameState.tutorial_active = true
	GameState.dual_active = true               # 双路模式 → 战斗有【摆位阶段】可教站位
	GameState.tutorial_stage = "match1_pick"   # 导演: 第一把从选龟开始
	GameState.tutorial_mandatory = mandatory
	GameState.dungeon_stage = 1
	GameState.dungeon_carry_hp = {}; GameState.dungeon_dead_ids = []
	GameState.clear_team()
	var _td = get_node_or_null("/root/TutorialDirector")
	if _td != null:
		_td.begin_sandbox()    # 快照真经济+发教学币(结束还原, 不给奖励)
	get_tree().change_scene_to_file("res://scenes/TeamSelect.tscn")
