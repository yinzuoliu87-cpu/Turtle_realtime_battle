extends Control

## MainMenuScene — 主菜单, 1:1 PoC MainMenuScene.ts 布局.
## 设计台 1280×720. 标题menu-title图@(240,130) / 左栏btn-frame按钮(360×87)中心x=240 /
## 右墙 frame-coin龟币框 + 4个frame-square磁贴(图鉴/教程/排行榜/战绩, 仅图标).

## 商店按钮的文字。★它同时是【商店锁的判别式】(下面 `str(s[0]) == SHOP_LABEL`) ——
##   所以必须是一个常量, 不能两处各写一遍字面量: 改了按钮名字而漏改判别式,
##   锁会【静默失效】(没打过第一场的玩家直接进得去商店), 不报错、没人看得出来。
##   同一形状 2026-08-26 在 `Backend._is_self_ghost` 上踩过一次真的, 那次的代价是
##   "接上服务器后永远匹配不到别人"。
const SHOP_LABEL := "商店"

## A5: 配额上限从常量取, 不写死 —— 写死就是把参数抄两份。
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
## D-1: 服务状态三态(没配 / 正常 / 维护中 / 连不上)。维护态要盖掉赛程显示, 见 `_week_close_block`。
const _SB := preload("res://scripts/net/supabase.gd")

const W := 1280
const H := 720
const LEFT_CX := 240        # 标题图中轴 (原 LEFT_PAD60 + 按钮宽360/2; 按钮栈已重排, 只剩标题在用)
                            # 排行榜/图鉴/教程/战绩 走右侧 4 磁贴。4×(87+12)=396 → 234..630 < 720, 不溢出。
                            # 〔原注释写"5 入口…排行榜"= 陈旧, 排行榜早就挪到右侧磁贴了〕
const WALL := 16

## ── 左栏按钮栈的几何 (2026-08-15 版式体检) ──
## ★抽成常量是因为【右信息板要和这个栈对齐到同一条竖直带】: 两边各写各的坐标,
##   就是上一版右下角空出 560×161 一大块、而左栏比右栏长 140px 的根因。
##   verify_mainmenu_layout 会量真实 rect 断言两栏首尾各差 ≤2px。
## ── 版面 (2026-09-17 重做) ────────────────────────────────────────────────
## 原版式是【三块等高圆角卡并排】: 左栏 6 个木框按钮 / 中间赛程日历 / 右边 560×398 的
## 赛季表格。用户: 「你不觉得很丑吗, 市面上哪里有游戏会这么排版呢」—— 他是对的。
##
## 从 Game UI Database 的 Main Menus 分类下了 8 张真实主菜单逐张看, 共同点四条,
## 这一版就是照这四条重排的(对照印相在方案书里):
##   ① 画面主体是【游戏世界本身】 —— Absolum / Black Jacket / Replaced 右侧全是角色群像,
##      Fuga / Zombie Rollerz 干脆让角色铺满整屏。⇒ 背景换成 28 只龟的群像(_bg)。
##   ② 次级入口是【无框文字】 —— 8 张里 4 张如此。木框只留给主 CTA。
##   ③ 玩家数据【贴角成小胶囊】 —— Zookeeper World 右上金币/钻石、WarioWare 右上 950。
##      没有一张把它做成占屏 24% 的竖排表格。⇒ 赛季数据压成一行(_status_row)。
##   ④ 主 CTA 【又大又孤立】 —— Zookeeper World 的巨型绿 PLAY 在右下角(横屏右手拇指位)。
##      ⇒ 开始战斗挪到右下, 是全屏唯一的大木框。
##
## ★竖向预算是被【触摸线】锁死的: 可点元素短边 ≥81 视口像素(=44pt, 见 _probe_ui_layout)。
##   所以左栏只放得下 1 个状态行 + 4 个入口 (5×81=405), 训龟大师因此挪到右栏跟主 CTA 一组
##   —— 它俩都是"出战准备"语义, 放一起也讲得通, 不是硬塞。
const LOGO_CY := 106.0                      # 标题图中心 y (原 130, 上移给状态行腾位)
const LOGO_SCALE := 0.98                    # 原 1.1
const ROW_H := 81.0                         # ★触摸线: 44pt = 81 视口像素, 左栏每行都吃它
const LEFT_X := 48.0                        # 左栏左沿 (= WALL*3, 与 LOGO 左沿对齐)
const LEFT_W := 382.0                       # 左栏宽
const STATUS_Y := 210.0                     # 状态+战绩行 顶沿
const MENU_Y := 299.0                       # 四个次级入口 顶沿
const MENU_N := 4
const HERO_SIZE := Vector2(508.0, 158.0)    # 主 CTA: 全屏唯一大木框, 右下角
const HERO_POS := Vector2(732.0, 462.0)
## 训龟大师【明显更窄】并与主 CTA 右沿对齐 —— 第一版两个框同宽 472, 实拍出来分不出主次,
## 而参考里主 CTA 永远是压倒性的(Zookeeper World 的绿 PLAY / Fuga 的橙高亮条)。
const TRAINER_SIZE := Vector2(340.0, 82.0)   # ★82 不是 78: 触摸线 81 视口像素(=44pt), 78 差 3px 门禁当场红
const TRAINER_POS := Vector2(900.0, 344.0)  # 900+340 = 1240 = 732+508, 右沿同轴; 与主 CTA 留 36px
const STRIP_Y := 636.0                      # 贴底赛程条
const STRIP_H := 68.0
const STRIP_X := 48.0
const STRIP_W := 884.0
## 训龟大师: 原 300×62 (4.84:1, 全场最扁) 且离 2×2 网格 71px = 看着像掉队的孤儿。
## 改成与网格同高 82 (3.66:1), 并按网格自己的 14px 节奏紧贴其下 —— 归队, 不再单飞。

## 字号层级 (原来 hero27 / 面板标题25 / 次级22 / 行20 —— 主次只差 5 号, 分不出层)
const FONT_HERO := 30
const FONT_BTN := 22
const FONT_VERSION := 16

var page_box: Control       # 当前页按钮容器
var content_root: Control   # 内容层 (1280×720 设计框, 居中于真实视口); 背景另铺满全窗口
var _bg_tile: TextureRect   # 背景图 (resize 时重设尺寸)
var _bg_is_crowd := false   # true=28龟群像(铺满视口) / false=旧平铺纹理(要+512给漂移)


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
	_week_strip()               # 左右两栏之间那条空档 → 本周赛程条
	## ★D-1: 去问一次服务状态(没配后端时这一句什么都不做, 连节点都不建)。
	##   答复是异步回来的 ⇒ 配一个**挂在自己身上的 Timer 子节点**轮询状态变没变,
	##   变了就重建赛程条。★不能用 `get_tree().create_timer` 接闭包 ——
	##   那种计时器活过场景释放, 响的时候去绑已释放的捕获就报错
	##   (`tools/tree_timer_audit.py` 守这条, 它推荐的修法就是 Timer 子节点)。
	_SB.fetch_status_async()
	## ★D-3: 顺手确保有服务端身份。**已经有 account_id 就什么都不做** ——
	##   每次开游戏都新建一个匿名账号的话, 服务端会被刷出一堆一次性账号
	##   (Supabase 建项目时自己就警告过匿名登录被刷会撑爆 MAU)。
	##   没配后端时这一句同样什么都不做, 连节点都不建。
	_SB.ensure_signed_in_async()
	var sb_t := Timer.new()
	sb_t.wait_time = 1.0
	sb_t.autostart = true
	sb_t.timeout.connect(_sb_poll)     # 方法引用, 不是闭包
	add_child(sb_t)
	page_box = Control.new()
	content_root.add_child(page_box)
	_build_page_buttons()
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
		## 群像是【一张图】按 COVERED 填满视口; 只有平铺才需要比屏幕大一格(512)给漂移留量。
		## 原来无条件 +512 —— 换成群像后会把图放大到超出视口, 右下角内容被推出画面。
		_bg_tile.size = vp if _bg_is_crowd else Vector2(vp.x + 512, vp.y + 512)


# 不再 _exit_tree 还原 KEEP: 项目级 aspect 已是 EXPAND(全场景统一), 离场不翻转 → 场景切换丝滑。
#   各场景背景铺满已各自处理(menu平铺/select-bg/Codex全锚), 无需切回 KEEP。


func _bg() -> void:
	# PoC (index.html menu-bg-active + BootScene:579): 菜单背景 = menu-bg-tile.png 平铺 (512px repeat)
	#   over 深绿底 #1a3a2a, 上叠暗渐变 ::after rgba(8,12,20,.15→.40). 不是 menu-bg.png 废墟图!
	var vp := get_viewport_rect().size   # 真实视口(EXPAND 后=窗口比例); bg 全填它, 含原黑边区
	var base := ColorRect.new(); base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color("#1a3a2a")   # 深绿底 — 用 PoC 字面色值, 不四舍五入
	add_child(base)
	# ★2026-09-17 背景换成【28 只龟的群像】(menu-bg-crowd.png)。
	#   原来是 menu-bg-tile.png 平铺装备暗纹 + 25s 漂移 —— 一张淡到几乎看不见的纹理,
	#   等于把屏幕上最大的一块画布浪费掉了。而实拍参考里 Fuga / Zombie Rollerz 的做法是
	#   【让角色自己铺满整屏当背景】, 这个游戏正好有 28 只龟。
	#   图由 tools/build_menu_crowd_bg.py 从 data/pets.json 的第 0 帧合成(五层纵深 + 左侧压暗),
	#   不是手画的 —— 加龟/换立绘重跑一次就同步。
	#   ⚠ 不再漂移: 平铺纹理漂移看不出接缝, 而群像有具体内容, 一动就穿帮。
	if ResourceLoader.exists("res://assets/sprites/menu/menu-bg-crowd.png"):
		var crowd := TextureRect.new()
		crowd.texture = load("res://assets/sprites/menu/menu-bg-crowd.png")
		crowd.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# COVERED: 非 16:9 视口下【填满 + 居中裁切】, 不留黑边也不拉变形
		crowd.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		crowd.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 像素风, 放大不许插值糊掉
		crowd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crowd.size = vp
		crowd.position = Vector2.ZERO
		add_child(crowd)
		_bg_tile = crowd
		_bg_is_crowd = true
	elif ResourceLoader.exists("res://assets/sprites/menu/menu-bg-tile.png"):
		# 回退: 群像图没导入时仍走原来的平铺, 免得整屏纯色
		var tile := TextureRect.new()
		tile.texture = PreloadCache.menu_bg_tile_tex()
		tile.stretch_mode = TextureRect.STRETCH_TILE
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.size = Vector2(vp.x + 512, vp.y + 512)
		tile.position = Vector2(-512, -512)
		add_child(tile)
		_bg_tile = tile
	# ::after 暗渐变遮罩 (顶 alpha.15 → 底 .40), 压暗背景
	# 显式设 offsets+colors (别用 set_color/add_point — Gradient 默认 offset1 是白点, 会漏成底部白光)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	## ★用群像背景时遮罩要减半: 那张图在生成阶段就已经压暗(×0.62)+暗角了,
	##   再叠原来给【平铺纹理】调的 0.15~0.40, 整屏黑成一团、龟全看不见。
	##   (平铺那条回退路仍走原值, 免得它跟着一起变。)
	var _soft := _bg_is_crowd
	grad.colors = PackedColorArray([
		Color(8.0 / 255.0, 12.0 / 255.0, 20.0 / 255.0, 0.06 if _soft else 0.15),
		Color(8.0 / 255.0, 12.0 / 255.0, 20.0 / 255.0, 0.10 if _soft else 0.25),
		Color(8.0 / 255.0, 12.0 / 255.0, 20.0 / 255.0, 0.22 if _soft else 0.40),
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
		var end_top_y := LOGO_CY - 101.5                # center → 左上 y
		var start_top_y := LOGO_CY - 180.0 - 101.5      # 起点在屏外上方(原 PoC: center-180)
		t.position = Vector2(LEFT_CX - 180, start_top_y)
		t.scale = Vector2(0.85, 0.85); t.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.25)                          # PoC delay 250ms
		tw.tween_property(t, "position:y", end_top_y, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(t, "scale", Vector2(LOGO_SCALE, LOGO_SCALE), 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(t, "modulate:a", 1.0, 0.55)
		return
	else:
		var l := Label.new(); l.text = "斗龟场"; l.add_theme_font_size_override("font_size", 80)
		l.add_theme_color_override("font_color", Color("#ffd93d")); l.position = Vector2(LEFT_CX - 150, 90); content_root.add_child(l)


# ─── 左栏按钮页 (实时版: 单一干净主菜单, 无子页过场) ───
## 实时版重做: 去掉回合制残留的多页(online/local)+过场飞出/飞入逻辑.
##   主菜单就一组清晰按钮(各自从左滑入入场), 点击直接 _go 切场景, 不再有页间过场.
##   (2026-08-15 删掉了只剩一页还在传"页名"的 _show_page/_active_page —— 单页了就别再演多页。)


## 左栏四个入口的第 i 行顶沿。★一个来源 —— 状态行、入口、赛程条都靠它算,
## 各自写死就会在改版时漂开(原版式的信息板就是因为这个跟左栏栈对不齐过)。
func _menu_row_y(i: int) -> float:
	return MENU_Y + float(i) * ROW_H


## 左栏内容的下沿 (最后一个入口的底)
func _menu_bottom() -> float:
	return _menu_row_y(MENU_N - 1) + ROW_H


## 建主菜单的可点元素 (2026-09-17 版式重做, 见文件头的四条参考结论):
##   左栏  背包 / 商店 / 图鉴 / 排行榜   —— 无框文字, 每行 ROW_H
##   右栏  训龟大师(小木框) + ⚔开始战斗(巨型木框, 全屏唯一大框)
## 原版式是 1 个英雄键 + 2×2 网格 + 训龟大师, 六个木框全挤在左栏。
func _build_page_buttons() -> void:
	var eliminated := GameState.is_eliminated()   # 0命=本大轮淘汰(用户2026-07-24拍板"淘汰锁定") → 锁匹配+商店, 只"设置→重置存档"解锁
	## A4(2026-09-17 user decision): quota full also locks the shop.
	## WARNING: this line affects FIVE gates that rely on setting season_total_battles=3
	##   (verify_shop_layout / shop_merge_pips / shop_persist / ui_consistency / ui_layout).
	##   None of them sets ranked_used => on a fresh CI save ranked_used=0 < quota,
	##   so they happen NOT to be locked. That is luck, not design: if someone sets the
	##   quota to 0 or feeds those gates a ranked_used, all five go red at once -
	##   do not chase it as a product regression then.
	var shop_locked := int(GameState.season_total_battles) <= 0 or eliminated or GameState.ranked_quota_full()
	var mic := "res://assets/sprites/menu/"
	var subs: Array = [
		["背包", func(): _go("Inventory"), mic + "ic-bag.png", false],
		[SHOP_LABEL, func(): _open_shop(), mic + "ic-shop.png", shop_locked],
		["图鉴", func(): _go("Codex"), mic + "ic-codex.png", false],
		["排行榜", func(): _go("Leaderboard"), mic + "ic-trophy.png", false],
	]
	for i in range(subs.size()):
		var sN: Array = subs[i]
		var e := _text_entry(str(sN[0]), sN[1], str(sN[2]), bool(sN[3]))
		e.position = Vector2(LEFT_X, _menu_row_y(i))
		page_box.add_child(e)
		_slide_in_left(e, i)
	# ── 训龟大师: 挪到右栏、贴在主 CTA 正上方 ──
	#    它跟「开始战斗」是同一件事的两步(配大师 → 出战), 放一起比塞在左栏列表里更讲得通;
	#    直接原因则是竖向预算: 左栏 5×81 放不下(见文件头"触摸线"那段)。
	var tb := _frame_button("🐢 训龟大师", func(): _go("TrainerConfig"), false, TRAINER_SIZE, FONT_BTN, "")
	tb.position = TRAINER_POS
	page_box.add_child(tb)
	_slide_in(tb, 4)
	# ── ⚔ 开始战斗: 右下角巨型主 CTA ──
	#    位置照 Zookeeper World 的绿 PLAY —— 横屏手机右手拇指的落点, 也是全屏唯一的大木框。
	var hero := _frame_button("⚔  开始战斗", func(): _start_battle_flow(), false, HERO_SIZE, FONT_HERO, "", eliminated)
	hero.position = HERO_POS
	page_box.add_child(hero)
	if eliminated:
		_add_lock_badge(hero, HERO_SIZE)
	_slide_in(hero, 5)


## 左栏的一个无框文字入口。
## ★"无框"是照参考来的(Absolum / Black Jacket / Replaced / Fuga 的次级项都没有框),
##   但【可点区域仍然是整行 LEFT_W×ROW_H】—— 视觉轻、手指目标不小, 两件事不能混为一谈。
## 悬停时: 左侧 ◆ 淡入 + 文字右移 6px + 一层金色底光, 代替原来那个木框。
func _text_entry(label: String, cb: Callable, icon_path: String, locked: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(LEFT_W, ROW_H)
	holder.size = Vector2(LEFT_W, ROW_H)
	var glow := ColorRect.new()                     # 悬停底光(默认全透明), 放最底层
	glow.color = Color(1.0, 0.85, 0.24, 0.0)
	glow.size = Vector2(LEFT_W, ROW_H)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glow)
	var dia := _place_stroked("◆", 18, Color("#ffd93d"), Vector2(0, ROW_H / 2.0 - 14), Vector2(26, 28))
	dia.modulate.a = 0.0
	holder.add_child(dia)
	var tx := 30.0
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var it := TextureRect.new()
		it.texture = load(icon_path)
		it.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		it.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		it.size = Vector2(40, 40)
		it.position = Vector2(tx, ROW_H / 2.0 - 20)
		it.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if locked:
			it.modulate = Color(0.55, 0.55, 0.58)
		holder.add_child(it)
		tx += 52.0
	# 文字: 背景是龟群像(有明有暗), 所以一律带黑描边 —— 纯色字在群像上会读不出
	var col := Color("#8d9099") if locked else Color("#ffe9a8")
	var lb := _place_stroked(("🔒 " if locked else "") + label, 26, col,
		Vector2(tx, ROW_H / 2.0 - 21), Vector2(LEFT_W - tx - 8.0, 42))
	holder.add_child(lb)
	## (不画分隔线: 第一版画了, 实拍出来那条线横跨在背景的龟身上, 把版面切碎了。
	##  参考里的无框菜单 Absolum / Black Jacket / Replaced 一条分隔线都没有 —— 行距本身就够分行。)
	# 透明按钮铺满 = 真正的点击区 (整行 382×81, 过 44pt 触摸线)
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	## ★先设 size 再 set_anchors_preset(FULL_RECT) 会把 size 当成 offset 叠上去 ——
	## 门禁实测这个 Button 变成 764×162(正好 2 倍), 于是相邻两行互相压住、还压到右下的主 CTA。
	## 同一个坑 `_version_stamp` 的注释里写过(「锚点先掰回再设 size/position」), 这次是反向踩的。
	## FULL_RECT 自己就会铺满 holder, 不要再设 size。
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(btn)
	var tx0 := tx
	btn.mouse_entered.connect(func():
		var tw := holder.create_tween().set_parallel()
		tw.tween_property(glow, "color:a", 0.10, 0.12)
		tw.tween_property(dia, "modulate:a", 1.0, 0.12)
		tw.tween_property(lb, "position:x", tx0 + 6.0, 0.12))
	btn.mouse_exited.connect(func():
		var tw := holder.create_tween().set_parallel()
		tw.tween_property(glow, "color:a", 0.0, 0.12)
		tw.tween_property(dia, "modulate:a", 0.0, 0.12)
		tw.tween_property(lb, "position:x", tx0, 0.12))
	btn.pressed.connect(func(): cb.call())
	return holder


## 一块【定好位、左对齐】的描边文字。
## ★必须先把锚点掰回 TOP_LEFT 再设 size/position —— `_make_stroked_label` 里是 PRESET_FULL_RECT,
##   不掰的话下一帧布局会按父容器把 size 冲掉, 文字被画到别的地方去
##   (版本号 2026-08-01 就是这么跑到屏幕外 x≈2544 的, 见 _version_stamp 的注释)。
func _place_stroked(text: String, size: int, fill: Color, pos: Vector2, box: Vector2) -> Control:
	var c := _make_stroked_label(text, size, fill, Color(0, 0, 0, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.size = box
	c.custom_minimum_size = box
	c.position = pos
	return c


## 左栏键入场: 从屏外左侧滑入 + 淡入, 错峰 (保留原 PoC 好动画)
func _slide_in_left(holder: Control, idx: int) -> void:
	if GameState != null and GameState.perf_lite:   # 同 _slide_in: 低画质直接就位
		return
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
	## ★2026-08-19 从 (w-36, 2) 挪到 (w-44, 10): 原位置让锁**骑在木牌右上角的花纹柱上、还探出板外**
	##   (实拍确认, 门禁也报了「🔒+8」)。木牌的花纹边实测约占 22px, 往里让开就落在木面上。
	lock.position = Vector2(size.x - 44.0, 10.0)
	lock.size = Vector2(32, 32)
	lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lock)


## btn-frame.png 金色边框按钮 (NinePatchRect 9宫格保证渲染 + 透明Button点击 + 文字)
## `size` 2026-09-17 从"默认 360×87"改成【必填】: 版式重做后只剩训龟大师与主 CTA 两个木框,
## 两处都显式传尺寸, 那对默认常量(BTN_W/BTN_H)就再没人读了 —— 与其留着烂掉不如删。
func _frame_button(label: String, cb: Callable, disabled: bool, size: Vector2, font_size: int = 22, icon_path: String = "", locked: bool = false) -> Control:
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
## `halign` 2026-09-17 加: 新版左栏的无框文字入口要【左对齐】, 而这里原本写死居中。
## 加可选参数而不是另写一个左对齐版本 —— 抄一份就永远落后一份(fb-hand-rolled-copies-drift)。
func _make_stroked_label(text: String, size: int, fill: Color, stroke: Color,
		halign: int = HORIZONTAL_ALIGNMENT_CENTER) -> Control:
	var wrap := Control.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for off in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var s := _menu_label(text, size, stroke, halign)
		s.offset_left = off.x; s.offset_right = off.x
		s.offset_top = off.y; s.offset_bottom = off.y
		wrap.add_child(s)
	wrap.add_child(_menu_label(text, size, fill, halign))   # 主填充在最上
	return wrap


func _menu_label(text: String, size: int, col: Color,
		halign: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = halign
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
	## A5: two currency chips side by side (gold + gems treatment, user 2026-09-17).
	##   right = 龟币 (main-site currency), left = 深海币 (the in-run currency, moved out of
	##   the season panel below - it used to be a text row there, a different style entirely).
	var coin := _coin_frame()                                  # 龟币: value<0 => GameState.coins
	coin.position = Vector2(W - WALL - 152, 30)
	content_root.add_child(coin)
	_slide_in(coin, 0)
	var dsea := _coin_frame(int(GameState.meta_deepsea_coins),
		"res://assets/sprites/menu/ic-deepsea.png", Color(0, 0, 0, -1.0))   # a<0 = keep original colours
	dsea.position = Vector2(W - WALL - 152 - 12 - 152, 30)
	content_root.add_child(dsea)
	_slide_in(dsea, 0)
	# 磁贴 62 → 82: 62px 在手机上只有 34pt, 低于 iOS HIG 的 44pt(=本项目 81 视口像素, 见 tests/_probe_ui_layout.gd)。
	# 82 同时更贴近旁边 85 高的龟币框, 三者读起来才是一排。
	var usz := 82.0
	var uy := 30.0 + (85.0 - usz) / 2.0                       # 与龟币框竖直居中对齐
	var set_x := float(W - WALL - 152 - 12 - 152) - 14.0 - usz   # A5: 让开第二个货币芯片
	var help_x := set_x - 10.0 - usz
	var set_tile := _tile("", "⚙", func(): _go("Settings"), Vector2(set_x, uy), "", usz)
	content_root.add_child(set_tile)
	_slide_in(set_tile, 1)
	var help_tile := _tile("ui/help-button", "❓", func(): _on_tutorial(), Vector2(help_x, uy), "", usz)
	content_root.add_child(help_tile)
	_slide_in(help_tile, 2)
	_status_row()          # 赛季状态压成一行(原来是 560×398 的表格卡)
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
## A5(2026-09-17, user): 龟币 is the MAIN-SITE currency and must stay visible, but the two
## currencies used to sit in two totally different places/styles - 龟币 in a frame up top,
## 深海币 as a text row inside the season panel. User asked for the usual game treatment:
## gold and gems side by side. So this chip is parameterised and drawn twice.
## value < 0 => GameState.coins (龟币). icon_path "" => the old green coin.png.
func _coin_frame(value: int = -1, icon_path: String = "", tint: Color = Color(0.122, 0.561, 0.247)) -> Control:
	var coin := Control.new()
	coin.custom_minimum_size = Vector2(152, 85); coin.size = Vector2(152, 85)
	if ResourceLoader.exists("res://assets/sprites/menu/frame-coin.png"):
		var cf := TextureRect.new(); cf.texture = load("res://assets/sprites/menu/frame-coin.png")
		cf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; cf.stretch_mode = TextureRect.STRETCH_SCALE
		cf.size = Vector2(152, 85); coin.add_child(cf)
	var _ip: String = icon_path if icon_path != "" else "res://assets/sprites/ui/coin.png"
	if ResourceLoader.exists(_ip):   # 黑线稿→非透明像素染绿(#1f8f3f)
		var cimg: Image = load(_ip).get_image()
		var green := tint
		## tint.a < 0 means "this icon is already coloured, do not repaint it".
		## Found by actually looking at the shot: the tint loop paints EVERY non-transparent
		## pixel one flat colour. coin.png is line art so an outline survives; ic-deepsea.png
		## is solid, so it came out as a featureless blue dot - unreadable as an icon.
		var _repaint: bool = tint.a >= 0.0
		for yy in range(cimg.get_height()):
			for xx in range(cimg.get_width()):
				var px := cimg.get_pixel(xx, yy)
				if _repaint and px.a > 0.0:
					cimg.set_pixel(xx, yy, Color(green.r, green.g, green.b, px.a))
		var ci := TextureRect.new(); ci.texture = ImageTexture.create_from_image(cimg)
		ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ci.size = Vector2(36, 36); ci.position = Vector2(76 - 39.5 - 18, 42 - 18); coin.add_child(ci)
	var cl := Label.new(); cl.text = "%d" % (GameState.coins if value < 0 else value)
	cl.position = Vector2(79, 0); cl.size = Vector2(73, 85)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cl.add_theme_font_size_override("font_size", 22); cl.add_theme_color_override("font_color", Color("#2c4a1e")); coin.add_child(cl)
	return coin


## 赛季状态行 —— 原来是右侧 560×398 的金边表格卡(大轮/Lv/命/本周场次/战绩 五行)。
## 实拍的 8 张主菜单里【没有一张】把玩家数据做成占屏 24% 的竖排表格:
## Zookeeper World 是右上角两个小胶囊(金币 590 / 钻石 30)、WarioWare Gold 是右上 950。
## ⇒ 压成 LOGO 下面的一行, 把那 24% 的屏幕还给龟群像。
##
## 整行可点 → 战绩(Record), 所以行高吃 ROW_H(81) 过 44pt 触摸线;
## 视觉上只是一行字, 但手指目标不小 —— 跟 _text_entry 同一个思路。
func _status_row() -> void:
	var txt := "第 %d 大轮 · Lv %d   ♥ %d/8   本周 %d/%d" % [
		int(GameState.season_id), int(GameState.season_level), int(GameState.hearts),
		int(GameState.ranked_used), int(_P2C.RANKED_QUOTA)]
	var wN: int = GameState.battles_won
	var tN: int = GameState.battles_total
	var rec := "%d 胜 %d 负" % [wN, maxi(0, tN - wN)] if tN > 0 else "暂无战绩"

	var holder := Control.new()
	holder.position = Vector2(LEFT_X, STATUS_Y)
	holder.custom_minimum_size = Vector2(LEFT_W, ROW_H)
	holder.size = Vector2(LEFT_W, ROW_H)
	var glow := ColorRect.new()
	glow.color = Color(1.0, 0.85, 0.24, 0.0)
	glow.size = Vector2(LEFT_W, ROW_H)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glow)
	holder.add_child(_place_stroked(txt, 18, Color("#ffe9a8"), Vector2(4, 10), Vector2(LEFT_W - 8, 26)))
	## ★箭头连进同一行文字 —— 第一版把它钉在行尾(x≈410), 而"暂无战绩"到 x≈190 就结束了,
	##   中间一百多像素空着, 屏幕上就是一个飘在龟身上的孤零零箭头。
	holder.add_child(_place_stroked("📜 战绩  %s  ›" % rec, 17, Color("#cfd8e4"), Vector2(4, 42), Vector2(LEFT_W - 8, 26)))
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(btn)
	btn.mouse_entered.connect(func(): holder.create_tween().tween_property(glow, "color:a", 0.09, 0.12))
	btn.mouse_exited.connect(func(): holder.create_tween().tween_property(glow, "color:a", 0.0, 0.12))
	btn.pressed.connect(func(): _go("Record"))
	content_root.add_child(holder)
	_slide_in_left(holder, 0)


## 右栏卡片入场: 从右(贴墙外)滑入 + 淡入. PoC delay 850+60*idx, dur420.
func _slide_in(holder: Control, idx: int) -> void:
	## ★低画质: 直接就位, 不播入场。
	##   背景从「平铺+25s 漂移」换成静态群像后, perf_lite 在主菜单【一个消费者都没有了】
	##   (verify_settings 当场红: 「主菜单背景漂移读 perf_lite」)。
	##   静态图没有漂移可关, 但入场 tween 还在 —— 低画质关掉它, 这个开关才不是空的。
	if GameState != null and GameState.perf_lite:
		return
	var home_x := holder.position.x
	holder.position.x = home_x + 60.0
	holder.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.85 + 0.06 * idx)
	tw.tween_property(holder, "position:x", home_x, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(holder, "modulate:a", 1.0, 0.42)


func _tile(icon_key: String, label: String, cb: Callable, pos: Vector2, sub_value: String = "", sz: float = 82.0) -> Control:
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


# ─── 📅 本周赛程条 (贴底横条) ───
## v2 的核心是周赛制, 而玩家在主菜单上【完全看不到这周是怎么安排的】: 哪天积分赛、
## 哪天闯关、什么时候收盘, 全靠记。这条横着的七格就是干这个的。
##
## ★第一版做成了【中间一列竖排七行的日历表】, 连同右侧的赛季表格一起被用户否掉:
##   「市面上哪里有游戏会这么排版呢」。实拍参考里周期性/模式信息走的是
##   **底部一排横向卡**(King of Meat), 没有一张用竖排日历。⇒ 改成贴底横条。
##
## ★★E2/E4 的唯一 UI 落点: 赛程判定全程按 UTC(phase2_config 里那几个纯函数),
##   本地时区**只在 `_local_dict` 里做一次显示层换算**, 换算结果一个字节都不回流到判定。
##   门禁 verify_week_season ⑥ 焊死了这条: 判定层源码里不许出现本地时间 API。
const _WD_CN := ["一", "二", "三", "四", "五", "六", "日"]

## 赛程条的外框。★留引用是为了服务状态变化时能把它换掉(见 `_sb_poll`)。
var _week_box: Control = null
## 建这条赛程条时的服务状态。★存下来才知道"变没变" —— 只看当前值没法判断要不要重建。
var _sb_state_shown: String = ""


## D-1: 服务状态变了就重建赛程条(维护态要盖掉收盘倒计时)。
## ★判据是**状态变了**而不是"每秒都重建" —— 后者会让主菜单每秒扔一堆节点。
func _sb_poll() -> void:
	var s: String = _SB.service_state()
	if s == _sb_state_shown:
		return
	if is_instance_valid(_week_box):
		_week_box.queue_free()
	_week_strip()


func _week_strip() -> void:
	var now := int(Time.get_unix_time_from_system())     # ★UTC 纪元秒, 与本地时区无关
	var today: int = _P2C.iso_weekday_utc(now)
	_sb_state_shown = _SB.service_state()
	var box := PanelContainer.new()
	box.position = Vector2(STRIP_X, STRIP_Y)
	box.custom_minimum_size = Vector2(STRIP_W, STRIP_H)
	box.size = Vector2(STRIP_W, STRIP_H)
	var sb := StyleBoxFlat.new()
	## ★不描边 + 底色更实: verify_ui_consistency 的「网页盒」= 四边有边框 + 底半透明
	##   = CSS border+rgba 的长相(用户 2026-08-15「去掉 ai 味」时建的判据)。
	##   条子靠更实的底色跟背景分开就够了, 不需要 1px 金描边。
	sb.bg_color = Color(0.04, 0.10, 0.16, 0.94)
	sb.set_border_width_all(0)
	## ★直角不圆角: verify_ui_consistency 把「圆角盒」当网页感的指标(用户 2026-08-15「去掉 ai 味」),
	##   主菜单上限 3 个, 而赛程条一家就能凑 8 个(外框 + 七格)。像素风里圆角也本来就是异类。
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 7; sb.content_margin_bottom = 7
	box.add_theme_stylebox_override("panel", sb)
	content_root.add_child(box)
	_week_box = box          # D-1: 服务状态变了要能把它换掉
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 6)
	box.add_child(h)
	for wd in range(1, 8):
		h.add_child(_week_day_cell(wd, today))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(spacer)
	h.add_child(_week_close_block(now))
	_slide_in(box, 6)


## 赛程条的一格 = 一天。上行周几、下行阶段名。
## 今天给金边金底; 已过去的天淡到 0.42 —— 一眼看出这周走到哪了。
func _week_day_cell(wd: int, today: int) -> Control:
	var ph: String = _P2C.phase_of_weekday(wd)
	var is_today := (wd == today)
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(92, 0)
	var cs := StyleBoxFlat.new()
	cs.set_corner_radius_all(0)          # 同上: 七个格子也不圆角
	cs.content_margin_left = 6; cs.content_margin_right = 6
	cs.content_margin_top = 3; cs.content_margin_bottom = 3
	## 今天那格也不描边(同上)。改成更实的金底 + 顶部一条金色实条 ——
	## 实条是 ColorRect 不是 StyleBox, 既不算"盒", 在像素风里也比 1px 描边立得住。
	cs.bg_color = Color(1.0, 0.85, 0.24, 0.32) if is_today else Color(1, 1, 1, 0.05)
	cell.add_theme_stylebox_override("panel", cs)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0)
	cell.add_child(v)
	if is_today:
		var topbar := ColorRect.new()
		topbar.color = Color("#ffd93d")
		topbar.custom_minimum_size = Vector2(0, 4)
		topbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(topbar)
		v.move_child(topbar, 0)
	var d := Label.new(); d.text = _WD_CN[wd - 1]
	d.add_theme_font_size_override("font_size", 15)
	d.add_theme_color_override("font_color", Color("#ffd93d") if is_today else Color("#c6d2e0"))
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(d)
	var n := Label.new()
	## ★今天那格在名字后缀一个「今」——横条的格子只有 92px 宽, 光靠金边在缩略/小屏上读不出来;
	##   顺带让门禁能量到"恰好一天是今天"(竖排那版有「今天」标签, 改横条时漏掉了)。
	n.text = (str(_P2C.PHASE_LABEL.get(ph, ph)) + " 今") if is_today else str(_P2C.PHASE_LABEL.get(ph, ph))
	n.add_theme_font_size_override("font_size", 14)
	n.add_theme_color_override("font_color", Color("#ffe9a8") if is_today else Color("#9fb0c4"))
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	if wd < today:
		cell.modulate.a = 0.42
	return cell


## 条子右端的收盘块: 主行(倒计时/状态) + 副行(本地时刻)。
## 三种态各说各的话, 不拿一句话硬凑:
##   · 有收盘的阶段 → 倒计时 + 本地几点收盘
##   · 已进封盘窗口 → 直说"不开新局了", 因为这时点开始战斗会被拦下
##   · 休赛/决赛日 → 没有收盘概念(close_left_sec 返回 -1), 说各自该说的事
func _week_close_block(now: int) -> Control:
	var ph: String = _P2C.phase_at_utc(now)
	var left: int = _P2C.close_left_sec(now)
	var head := ""
	var sub := ""
	## ★★D-1(2026-09-20): 后端**主动说自己在维护**时, 这一块盖掉赛程显示。
	##   方案书 U7/§4.7 拍板「版本维护期放在周一休赛, 停服 → 发版本 → 开服」,
	##   而在此之前玩家只会看到「连不上」⇒ 以为游戏坏了。
	##   ⚠ 只有 **MAINTENANCE** 这一态才盖: 「没配后端」(当前状态)与「连不上」都不盖 ——
	##     没配是有意关掉, 连不上是网络问题, 两者都不该在主菜单上喊话
	##     (网络层第一原则: 永远不能把游戏搞坏; 这里也不能把没事说成有事)。
	if _SB.service_state() == _SB.ST_MAINTENANCE:
		head = "维护中"
		var n := _SB.notice_text()
		sub = n if n != "" else "版本维护, 稍后回来"
		return _close_block_labels(head, sub)
	## ★★2026-09-22: 闯关赛/决赛日/休赛的**玩法还没上线**(WEEKEND_MODES_LIVE=false) ⇒
	##   那三天实际走的是积分赛规则(照常开局、吃配额)。这一块必须**直说** ——
	##   在此之前周日写「决赛日 本地 X 点开打」、周一写「本日维护」, 而两天都能照常开局:
	##   玩家按字面读会以为自己错过了决赛、或者以为维护日不能玩。**说了做不到的事就是缺陷**。
	var note: String = _P2C.phase_pending_note(ph)
	if note != "":
		head = str(_P2C.PHASE_LABEL.get(ph, ph))
		sub = note
		return _close_block_labels(head, sub)
	if left < 0:
		if ph == _P2C.PHASE_FINALS:
			head = "决赛日"
			sub = "本地 %s 开打" % _local_hhmm(_utc_today_at(now, int(_P2C.FINALS_START_HOUR_UTC)))
		else:
			head = "休赛日"
			sub = "周二开赛 · 本日维护"
	elif not _P2C.can_start_match_utc(now):
		head = "已封盘"
		sub = "收盘前 %d 分钟起不开新局" % int(_P2C.CLOSE_LOCKOUT_SEC / 60)
	else:
		head = "距收盘 %s" % _left_text(left)
		sub = "本地 %s" % _local_stamp(now + left)
	return _close_block_labels(head, sub)


## 收盘块的两行标签。★抽出来是因为上面维护态那条要提前 return, 而**两条路必须长得一样** ——
##   就地再写一份 Label 就是「手抄的副本必然落后」(本项目记过)。
func _close_block_labels(head: String, sub: String) -> Control:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0)
	var a := Label.new(); a.text = head
	a.add_theme_font_size_override("font_size", 16)
	a.add_theme_color_override("font_color", Color("#ffd93d"))
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(a)
	var b := Label.new(); b.text = sub
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color("#9fb0c4"))
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(b)
	return v


## 剩余秒 → 人话。跨天时说"天/小时"比说 47:00:00 好读。
func _left_text(sec: int) -> String:
	if sec >= 86400:
		return "%d 天 %d 小时" % [sec / 86400, (sec % 86400) / 3600]
	if sec >= 3600:
		return "%d 小时 %d 分" % [sec / 3600, (sec % 3600) / 60]
	return "%d 分 %02d 秒" % [sec / 60, sec % 60]


## 当天(UTC)的某个整点 → unix 秒。用来把 FINALS_START_HOUR_UTC 变成一个具体时刻。
func _utc_today_at(ts: int, hour: int) -> int:
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
	var secs: int = int(d.get("hour", 0)) * 3600 + int(d.get("minute", 0)) * 60 + int(d.get("second", 0))
	return ts - secs + hour * 3600


## ★★全局唯一的时区换算点(E2/E4)。判定层永远是 UTC, 只有【说给玩家听】的时候才翻译。
##   陷阱: `get_time_zone_from_system().bias` 的单位是**分钟**不是小时。
##   把偏移加到 UTC 秒上、再用 UTC 版的 from_unix_time 格式化 = 玩家墙上的时间。
func _local_dict(utc_ts: int) -> Dictionary:
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0))   # 分钟
	return Time.get_datetime_dict_from_unix_time(utc_ts + bias * 60)


func _local_stamp(utc_ts: int) -> String:
	var d := _local_dict(utc_ts)
	var w: int = int(d.get("weekday", 0))
	var wi := 7 if w == 0 else w
	return "周%s %02d:%02d 收盘" % [_WD_CN[wi - 1], int(d.get("hour", 0)), int(d.get("minute", 0))]


func _local_hhmm(utc_ts: int) -> String:
	var d := _local_dict(utc_ts)
	return "%02d:%02d" % [int(d.get("hour", 0)), int(d.get("minute", 0))]


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
	## A4(2026-09-17): three reasons, each with its own message - same wording as
	##   _start_battle_flow so the player never sees two different names for one state.
	##   Quota-full also locks the shop (user decision: stop completely when the quota is used up).
	if GameState.is_eliminated():
		_toast("💀 本大轮已出局 · 等周六闯关赛开赛观战")
		return
	if GameState.ranked_quota_full():
		_toast("📋 本周积分赛配额已打满 · 等周六闯关赛")
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
## 开局拦截。★★A4(大轮赛制 v2·2026-09-17): 从【一个闸】拆成【三种原因各自一条提示】——
##   原来不管为什么打不了, 玩家只看到「赛季已淘汰」, 而配额打满和不在开赛时段都不是"淘汰"。
## ★三条的**先后顺序有意义**: 命尽是最终态(重置存档才解)、配额是本周期上限(等下一阶段)、
##   阶段不对只是"现在不行"。按"多严重"排, 玩家看到的是最根本的那条原因。
func _start_battle_flow() -> void:
	if GameState.is_eliminated():   # 大轮淘汰锁(用户2026-07-24): 0命封匹配, 只重置存档解锁
		## ★U9 拍板(2026-09-16):「0 命的话就只能等到周 6 周日观赛了, 不再打表演赛」
		##   ⇒ 文案从「设置→重置存档」改成指向观赛。观赛入口在 F 阶段, 先把话说对。
		_toast("💀 本大轮已出局 · 等周六闯关赛开赛观战")
		return
	if GameState.ranked_quota_full():
		_toast("📋 本周积分赛配额已打满 · 等周六闯关赛")
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
