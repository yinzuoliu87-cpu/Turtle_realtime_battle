class_name ShopAmbience
extends RefCounted
## 商店环境动态(用户 2026-10-21「商店需要动态」): 灯笼光闪、水泡上浮、货品轻浮。
## ★全部画在货柜图层之上、货品之下(宿主在 _build_cabinet 之后、货架之前调 build), 不挡点击(MOUSE_FILTER_IGNORE)。
## ★像素画不做亚像素位移: 浮动按整像素跳(round)。
## ★照 CLAUDE.md §5 拆分模板: RefCounted + 构造注入宿主(ShopScene)。

## 货柜里四盏灯笼的灯芯(原生坐标, shop-shelf-wide.png 量的)
const LANTERNS := [Vector2(56.0, 52.0), Vector2(126.0, 52.0), Vector2(197.5, 52.0), Vector2(269.0, 52.0)]
const GLOW_COL := Color(1.0, 0.72, 0.32, 1.0)
const BUBBLE_MAX := 20
const BUBBLE_EVERY := 0.25      # 秒
const ITEM_BOB_PX := 5.0

var host = null
var _layer: Control = null
var _rng := RandomNumberGenerator.new()
static var _glow_tex: Texture2D = null
static var _bubble_tex: Texture2D = null


func _init(h) -> void:
	host = h


func build(parent: Control) -> void:
	_layer = Control.new(); _layer.name = "ShopAmbience"
	_layer.position = Vector2(host.CAB_X, host.CAB_Y)
	## 只到下层板沿(原生 y166): 水泡不飘过底下刷新 / 锁定 / 买经验那一排(用户 10-21 截图「这是？」)
	_layer.size = Vector2(324.0, 166.0) * host.CAB_SCALE
	_layer.clip_contents = true
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_layer)
	if bool(GameState.test_mode):
		_rng.seed = 20261021
	else:
		_rng.randomize()
	for i in range(LANTERNS.size()):
		_lantern_glow(LANTERNS[i] * host.CAB_SCALE, i)
	var tm := Timer.new(); tm.name = "BubbleTimer"
	tm.wait_time = BUBBLE_EVERY
	tm.timeout.connect(_spawn_bubble)
	_layer.add_child(tm)
	tm.start()


## 柔和的径向光(中心亮、边缘透明)。光不是像素物件, 用平滑渐变; 硬边像素圆放大后是一块方砖(实拍过)。
static func glow_tex() -> Texture2D:
	if _glow_tex == null:
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		gr.add_point(0.45, Color(1, 1, 1, 0.35))
		var gt := GradientTexture2D.new()
		gt.gradient = gr; gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64; gt.height = 64
		_glow_tex = gt
	return _glow_tex


## 像素水泡: 5×5 原生的小圆环 + 左上一点高光。
static func bubble_tex() -> Texture2D:
	if _bubble_tex == null:
		var img := Image.create(5, 5, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var ring := Color(0.80, 0.96, 1.0, 0.85)
		for p in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(0, 1), Vector2i(4, 1), Vector2i(0, 2), Vector2i(4, 2),
				Vector2i(0, 3), Vector2i(4, 3), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4)]:
			img.set_pixelv(p, ring)
		img.set_pixel(1, 1, Color(1, 1, 1, 1))
		_bubble_tex = ImageTexture.create_from_image(img)
	return _bubble_tex


func _soft_glow(sz: float) -> TextureRect:
	var g := TextureRect.new()
	g.texture = glow_tex()
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; g.stretch_mode = TextureRect.STRETCH_SCALE
	g.size = Vector2(sz, sz)
	g.self_modulate = GLOW_COL
	var mat := CanvasItemMaterial.new(); mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = mat
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


## 一盏灯一团加色暖光, 亮度随机抖(烛火), 每盏错开相位。
func _lantern_glow(c: Vector2, i: int) -> void:
	var g := _soft_glow(180.0)
	g.name = "LanternGlow%d" % i
	g.position = c - Vector2(90.0, 90.0)
	g.modulate.a = 0.28
	_layer.add_child(g)
	var tw := TweenKit.loop_bound(host, g)
	tw.tween_interval(0.07 * float(i))
	for _k in range(6):
		tw.tween_property(g, "modulate:a", _rng.randf_range(0.14, 0.42), _rng.randf_range(0.06, 0.18))


## 店主提灯的光(挂在店主节点下)。flame = 当前帧火苗的原生坐标; 换帧时由 place_keeper_glow 跟过去。
func keeper_glow(keeper: Control, scale: float, region_x: float, flame: Vector2) -> Control:
	var g := _soft_glow(130.0)
	g.name = "KeeperLanternGlow"
	place_keeper_glow(g, scale, region_x, flame)
	g.modulate.a = 0.3
	keeper.add_child(g)
	var tw := TweenKit.loop_bound(host, g)
	for _k in range(5):
		tw.tween_property(g, "modulate:a", _rng.randf_range(0.16, 0.42), _rng.randf_range(0.06, 0.16))
	return g


func place_keeper_glow(g: Control, scale: float, region_x: float, flame: Vector2) -> void:
	g.position = Vector2(flame.x - region_x, flame.y) * scale - g.size * 0.5


## 背景海水里的水泡(底图上原来画死的水泡已抹掉 —— 用户 10-21「如果背景的水泡没动会很奇怪啊」)。
##   bg = 底图 TextureRect(满铺层); band = 海水那一条在 bg 里的坐标范围。
var _water: Control = null
func build_water(bg: Control, band: Rect2) -> void:
	_water = Control.new(); _water.name = "WaterBubbles"
	_water.position = band.position; _water.size = band.size
	_water.clip_contents = true
	_water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(_water)
	var tm := Timer.new(); tm.name = "WaterBubbleTimer"
	tm.wait_time = 0.35
	tm.timeout.connect(func() -> void: _spawn_in(_water, 16, 0.75))
	_water.add_child(tm)
	tm.start()


## 水泡: 货柜底部冒出来, 一边晃一边往上飘, 到灯带附近淡掉。
func _spawn_bubble() -> void:
	_spawn_in(_layer, BUBBLE_MAX, 1.0)


func _spawn_in(layer: Control, cap: int, alpha: float) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	var n := 0
	for ch in layer.get_children():
		if str(ch.name).begins_with("Bubble"):
			n += 1
	if n >= cap:
		return
	var px: float = host.CAB_SCALE * 5.0 * (1.0 if _rng.randf() < 0.6 else 0.6)
	var b := TextureRect.new()
	b.texture = bubble_tex(); b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; b.stretch_mode = TextureRect.STRETCH_SCALE
	b.size = Vector2(px, px); b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.name = "Bubble%d" % _rng.randi()
	b.modulate.a = alpha
	var x0 := _rng.randf_range(20.0, layer.size.x - 20.0)
	var y0 := layer.size.y - _rng.randf_range(10.0, 50.0)
	b.position = Vector2(x0, y0).round()
	layer.add_child(b)
	var dur := _rng.randf_range(4.0, 7.0)
	var rise := _rng.randf_range(0.6, 1.0) * layer.size.y
	var tw: Tween = host.create_tween().bind_node(b)
	TweenKit._stop_on_exit(b, tw)   # 商店移出树(换场景)时立刻停, 不等释放(verify_loop_tween_exit)
	tw.set_parallel(true)
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(b):
			b.position = Vector2(x0 + sin(t * 9.0) * 6.0, y0 - rise * t).round(), 0.0, 1.0, dur)
	tw.tween_property(b, "modulate:a", 0.0, dur * 0.35).set_delay(dur * 0.65)
	tw.chain().tween_callback(b.queue_free)


## 货品轻浮: 物品图标上下整像素浮动, 每格错开相位。
func bob_item(icon: Control, idx: int) -> void:
	var y0 := icon.position.y
	var tw := TweenKit.loop_bound(host, icon)
	tw.tween_interval(0.13 * float(idx % 5) + 0.2 * float(idx / 5))
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(icon):
			icon.position.y = roundf(y0 - ITEM_BOB_PX * (0.5 - 0.5 * cos(t * TAU))), 0.0, 1.0, 2.4)
