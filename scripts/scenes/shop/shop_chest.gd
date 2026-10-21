class_name ShopChest
extends RefCounted
## 商店左半【店主】(2026-10-21 宝箱 / 背包那一排已拿出商店, 卖出只在背包页)。原:【店主 + 宝箱】(2026-10-18 整页重做·第三版)。
##
## 用户 10-18:「整个页面就应该重做啊，没有任何游戏搞的这种浏览器网页感」→ 商店改成货铺场景;
##   接着「我并不觉得左边的阵容可以放在商店里吧」→ 选「店主 + 宝箱」:
##   商店只管买 / 卖 / 看; 买下的东西进宝箱(= 背包), 装到龟身上回背包页做。
## ⇒ 左半: 店主站在地毯上(待机轻晃) + 左下角宝箱(背景图里本来就有) 旁边一排已有装备。
##   只有点按, 没有拖拽(用户 10-18「为什么要拖入宝箱去购买？」): 点货架 → 说明卡 → 购买;
##   点宝箱里一件 → 详情 / 卖出。
## ★卖走背包页同一套 `InvOps`(私人池退张、羁绊赠送件不可卖、存盘都在里面)。
## ★触控尺寸(verify_ui_consistency「热区不足」): 宝箱格 81、按钮 81 高。
## ★照 CLAUDE.md §5 拆分模板: RefCounted + 构造注入宿主(ShopScene)。

## ── 店主 ──
## ★2026-10-21 手机版: 原生 128 × 2.75 = 352 → × 2.0 = 256, 站到左栏靠货柜那一侧、地毯后沿上
##   (原来 352 高占掉左半屏, 可点的 10 件挤在右半 —— 用户 10-20 iPhone 实拍)。
## ★★2026-10-21 宽货柜: 倍率改成与货柜 / 底图同一个(1280/384, 像素粗细一致), 站在货柜左立柱前面。
##   原生人形占 x21..98 / y4..124 ⇒ 放大后 x70..327 / y13..413: 右沿 262 不压第一格货(279 起), 左沿 5 在 16:9 也不出屏, 脚踩 SAFE_BOTTOM。
const KEEPER_SCALE := 1280.0 / 384.0
## 只画人形那一条(原生 x21..98, 裁掉两侧空白) ⇒ 控件不出 1280 设计框(verify_shop_layout ①)。
const KEEPER_REGION := Rect2(20.0, 0.0, 80.0, 128.0)
## 待机动画(用户 2026-10-21「你动态在哪」→「待机等于走路吗」): 8 帧横排序列 shopkeeper-idle.png, 每帧 128×128。
##   ★由 shopkeeper.png 逐像素做出来, 不用 AI 生成(两版 AI 待机腿都在迈步): 腰(y63)以下每帧不动,
##   上半身呼吸起伏 1 像素, 提灯(x85..98 / y56..77)左右晃 1 像素, 火苗明暗变。
const KEEPER_IDLE_TEX = preload("res://assets/sprites/shop/shopkeeper-idle.png")
const KEEPER_FRAMES := 8
const KEEPER_FRAME_SEC := 0.16
## 每帧提灯火苗的位置(原生, 逐帧量的), 提灯光跟着火苗走
const KEEPER_FLAME := [Vector2(94, 69), Vector2(95, 69), Vector2(95, 68), Vector2(94, 68), Vector2(94, 68), Vector2(93, 68), Vector2(93, 69), Vector2(94, 69)]
const KEEPER_SIZE := KEEPER_REGION.size * KEEPER_SCALE
const KEEPER_POS := Vector2(4.0, 682.0 - 124.0 * KEEPER_SCALE)

var host = null
static var _ell_cache: Dictionary = {}


func _init(h) -> void:
	host = h


## 像素椭圆(白色, 用 modulate 上色)。w×h 是原生像素, 显示时按 size 放大 —— 边缘是像素台阶, 不是矢量圆角
##   (verify_ui_consistency「圆角盒」= 网页味)。
static func ellipse_tex(w: int, h: int) -> Texture2D:
	var key := "%dx%d" % [w, h]
	if _ell_cache.has(key):
		return _ell_cache[key]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := (w - 1) * 0.5
	var cy := (h - 1) * 0.5
	for y in range(h):
		for x in range(w):
			var dx := (x - cx) / (w * 0.5)
			var dy := (y - cy) / (h * 0.5)
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	var tex := ImageTexture.create_from_image(img)
	_ell_cache[key] = tex
	return tex


static func ellipse(w_px: float, h_px: float, native_w: int, native_h: int, col: Color) -> TextureRect:
	var r := TextureRect.new()
	r.texture = ellipse_tex(native_w, native_h)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.size = Vector2(w_px, h_px)
	r.modulate = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# ══════════════════════════════════════════════════════════════
#  店主
# ══════════════════════════════════════════════════════════════

## 店主的 x(设计框坐标)。用户 2026-10-21「商店老板的位置要再往左边因为左边这么空」:
##   宽屏手机上设计框左边还露出 off.x(≈140) 的底图 ⇒ 店主在「屏幕左沿 .. 货柜左沿」那块空地里居中;
##   16:9 上那块空地比店主窄 ⇒ 不出屏, 退回 KEEPER_POS.x(贴着左立柱站)。
func keeper_x() -> float:
	var vs: Vector2 = Vector2(host.get_viewport().get_visible_rect().size)
	var hs: Vector2 = host.size if (host.size.x >= 1280.0 and host.size.y >= 360.0) else vs
	var off_x: float = roundf((hs.x - 1280.0) * 0.5)
	var gap_w: float = float(host.CAB_X) + off_x                 # 屏幕左沿到货柜左沿
	var want_screen: float = (gap_w - KEEPER_SIZE.x) * 0.5
	return roundf(clampf(want_screen, KEEPER_POS.x, KEEPER_POS.x + off_x) - off_x)


func build_keeper(parent: Control) -> void:
	var kpos := Vector2(keeper_x(), KEEPER_POS.y)
	var sh := ellipse(180.0, 24.0, 30, 5, Color(0.1, 0.05, 0.02, 0.45)); sh.name = "KeeperShadow"
	sh.position = kpos + Vector2((59.5 - KEEPER_REGION.position.x) * KEEPER_SCALE - 90.0, 124.0 * KEEPER_SCALE - 14.0)   # 人形中线 x59.5 / 脚底 y124(原生)
	parent.add_child(sh)
	var k := TextureRect.new(); k.name = "Shopkeeper"
	var kat := AtlasTexture.new(); kat.atlas = KEEPER_IDLE_TEX; kat.region = KEEPER_REGION
	k.texture = kat
	k.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	k.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	k.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	k.position = kpos; k.size = KEEPER_SIZE
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(k)
	var glow: Control = host._amb.keeper_glow(k, KEEPER_SCALE, KEEPER_REGION.position.x, KEEPER_FLAME[0])
	## 待机: 逐帧换 AtlasTexture 的区域(不做整张图平移 —— 那样看不出在动)
	var st := {"f": 0}
	var tm := Timer.new(); tm.name = "KeeperIdle"; tm.wait_time = KEEPER_FRAME_SEC
	tm.timeout.connect(func() -> void:
		st["f"] = (int(st["f"]) + 1) % KEEPER_FRAMES
		kat.region = Rect2(KEEPER_REGION.position + Vector2(128.0 * float(st["f"]), 0.0), KEEPER_REGION.size)
		if glow != null and is_instance_valid(glow):
			host._amb.place_keeper_glow(glow, KEEPER_SCALE, KEEPER_REGION.position.x, KEEPER_FLAME[int(st["f"])]))
	k.add_child(tm)
	tm.start()
