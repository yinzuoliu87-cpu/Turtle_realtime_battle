## 登录墙背后的游戏美术 —— 从 `SettingsScene.gd` 抽出·2026-09-29
##
## ═════════════════════════════════════════════════════════════════════
##  为什么要有这东西: 这一屏看不见这个游戏
## ═════════════════════════════════════════════════════════════════════
## 探针 `tests/_probe_wall_look.gd` 实测: `SettingsScene._maybe_login_wall()` 把 self 下的
## Control **整批藏掉**, 连 `_bg()` 建的底色 / 平铺砖 / 渐变一起藏(探针打出那三个
## 节点都是 `visible=false`) ⇒ 玩家看到的是一块深蓝面板压在**自动载入的
## `PersistentBg` 那张平铺花砖**上 —— 全屏没有任何属于这个游戏的东西。
##
## 参考里 Arknights / Free Fire / Disney Mirrorverse / Hungry Shark 的账号控件
## **直接浮在游戏美术上**, 没有对话框、没有纯黑遮罩。
##
## ★★素材是**主菜单自己在用的那两张**(`MainMenuScene._bg` / `_title`), 一张新的
##   都没生成 —— 这一屏该长得像它后面那一屏, 不是像另一个游戏。
## ★★★形状上一步不许倒退: `verify_ui_consistency` 登录墙那格是
##   {web:0, round:0, frame:0, tap:0}。所以这里只用 `TextureRect` + **直角纯色**
##   `ColorRect`, 一个带圆角 / 描边的 `StyleBoxFlat` 都不往里放。
##
## 拆法照 `scripts/scenes/battle/dmg_stats_panel.gd`: `RefCounted` + 构造注入,
## 本类**不认识** `SettingsScene` —— 它只拿到一个要铺的层和几个数。
class_name LoginWallArt
extends RefCounted

## 墙背景那张图。★**路径只写在这一处** —— 产品与门禁都读它,
##   两边各写一份就是抄一遍永远落后(memory `fb-hand-rolled-copies-drift`)。
const WALL_ART_TEX := "res://assets/sprites/menu/menu-bg-crowd.png"
## 斗龟场的标(主菜单 `_title()` 用的同一张的静帧版)。
const WALL_LOGO_TEX := "res://assets/sprites/menu/menu-title.png"
## 图上再压一层暗。★那张图生成时已经压过 ×0.62
##   (见 `tools/build_menu_crowd_bg.py`), 但它上面还要摧一个对话框 ——
##   对比度不够字就读不清。它同时是原来那层 0.65 纯黑遮罩的**替代品**:
##   遮罩本身还在(它负责吃点击), 只是被这张图盖住了。
const SHADE_A := 0.34
## 标摆在框左边那块空地里。空地还要留边(`LOGO_MARGIN`), 而不论空地多大
## 标也不超过 `LOGO_MAX_W`; 空地窄于 `LOGO_MIN_W` 就**整个不显示**,
## 而不是缩成一小块或压到框上去。
const LOGO_MARGIN := 48.0
const LOGO_MAX_W := 360.0
const LOGO_MIN_W := 140.0


## 往 `layer` 里铺美术(背景图 + 压暗层 + 标), 返回**那张标**(素材缺就 null)。
##
## ★三层都是 `MOUSE_FILTER_IGNORE`: 抢了点击就是「点了没反应」。
## ★按调用顺序入树 ⇒ 背景图在最底、压暗层在中、标在上; 调用方必须在
##   **把对话框挂进去之前**调它, 否则图会盖在框上面。
static func build(layer: Control) -> TextureRect:
	if layer == null or not is_instance_valid(layer):
		return null
	if ResourceLoader.exists(WALL_ART_TEX):
		var art := TextureRect.new()
		art.texture = load(WALL_ART_TEX)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.add_child(art)
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, SHADE_A)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.add_child(shade)
	if not ResourceLoader.exists(WALL_LOGO_TEX):
		return null
	var logo := TextureRect.new()
	logo.texture = load(WALL_LOGO_TEX)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## ★尺寸 / 位置一律交给 `place_logo()` —— 它每帧跟着真实视口算。
	layer.add_child(logo)
	return logo


## 摆标: 框左边那块空地的正中, 竖向居中于可用区。
##
## ★它是**背景**, 不跟着键盘让位一起挑 —— 让位是为了把要打字的那几个
##   东西露出来, 把一张标也一起往上挑只会把它顶出屏幕。
##   ★★所以入参只拿 `box_left`(框左沿)与 `avail_y`(可用区高), **不拿框的 y** ——
##   拿了就会想跟着它走。
## ★纯几何: 门禁可以直接量它, 不用起整个场景。
static func place_logo(logo: TextureRect, box_left: float, avail_y: float) -> void:
	if logo == null or not is_instance_valid(logo) or logo.texture == null:
		return
	var w: float = clampf(box_left - LOGO_MARGIN, 0.0, LOGO_MAX_W)
	logo.visible = w >= LOGO_MIN_W
	if not logo.visible:
		return
	var t: Texture2D = logo.texture
	var h: float = w * float(t.get_height()) / maxf(1.0, float(t.get_width()))
	logo.size = Vector2(w, h)
	logo.position = Vector2((box_left - w) * 0.5, (avail_y - h) * 0.5).round()
