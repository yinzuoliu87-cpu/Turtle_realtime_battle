class_name MenuCtaGlow
extends TextureRect
## menu_cta_glow.gd — 主菜单「开始战斗」木框的呼吸光晕 + 金边 (2026-10-05)。
##
## 由来: 方案书 docs/plans/20260917-主菜单版式重做.md R2(用户拍板):
##   主 CTA **保留木框**, 靠「呼吸光晕 + 亮金描边」拉开量级; ❌ 不换纯色实心块
##   (那等于在木质像素风里插一块扁平色块)。
##
## 画法: 运行时按按钮尺寸生成一张【低一档分辨率】的光晕图(一格 = 4 屏幕像素), 最近邻放大 ——
##   紧贴木框外沿一圈实金边, 往外三圈离散递减。不用平滑径向渐变: 平滑渐变光晕正是用户
##   点过名的「AI 味/网页味」, 像素风里光也该是一格一格的。
## 呼吸: 透明度在 0.40~1.0 之间 1.8 秒一个来回(`step()` 推, 测试可直接喂 dt)。
## ★锁着(开打被拦)时**不挂**: 灰框配金光是在说「快点我」, 而点了只会被拦。

const NODE_NAME := "HeroGlow"
const CELL := 4.0                 # 一格几个屏幕像素(与背景的 ×4 同一像素密度)
const RINGS := 3                  # 实金边外面再几圈
const INSET := 4.0                # frame-rect.png 四周有 4~5px 透明边(实测 bbox 4,5,663,157), 金边要贴着木头不是贴着空气
const PERIOD := 1.8
const A_LO := 0.40
const A_HI := 1.0
const GOLD := Color(1.0, 0.80, 0.32)

var _t := 0.0


func _init() -> void:
	name = NODE_NAME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stretch_mode = TextureRect.STRETCH_SCALE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add


## 挂到按钮 holder 上, 垫在最底层(木框之下), 四周各外扩 RINGS 格。
static func attach(holder: Control, btn_size: Vector2) -> MenuCtaGlow:
	var g := MenuCtaGlow.new()
	g._make(btn_size)
	holder.add_child(g)
	holder.move_child(g, 0)
	return g


func _make(btn_size: Vector2) -> void:
	var pad := (RINGS + 1) * CELL - INSET              # 外扩: 实金边那一格压在木框透明边上
	var full := btn_size + Vector2(pad, pad) * 2.0
	var cw := int(ceil(full.x / CELL))
	var ch := int(ceil(full.y / CELL))
	var img := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	## 第 0 圈 = 紧贴木框外沿的实金边; 1..RINGS 圈往外递减。圈号 = 到「按钮内框」的切比雪夫距离(格)。
	var alphas := [0.85, 0.42, 0.22, 0.10]
	for y in range(ch):
		for x in range(cw):
			var dx: int = maxi(RINGS - x, x - (cw - 1 - RINGS))
			var dy: int = maxi(RINGS - y, y - (ch - 1 - RINGS))
			var ring: int = RINGS - maxi(dx, dy)          # 外沿 0 → 内沿 RINGS
			var d: int = RINGS - ring                      # 0 = 贴着木框
			if maxi(dx, dy) < 0:
				continue                                   # 木框里面不画(木头本身不发光)
			## 切掉四个角上的那一格: 方角光晕像个选中框
			if dx == dy and dx >= RINGS - 1:
				continue
			img.set_pixel(x, y, Color(GOLD.r, GOLD.g, GOLD.b, alphas[clampi(d, 0, RINGS)]))
	texture = ImageTexture.create_from_image(img)
	position = -Vector2(pad, pad)
	size = Vector2(cw, ch) * CELL


func _ready() -> void:
	step(0.0)


func _process(delta: float) -> void:
	step(minf(delta, 0.1))


func step(dt: float) -> void:
	_t += dt
	var k := 0.5 + 0.5 * sin(TAU * _t / PERIOD)
	modulate.a = lerpf(A_LO, A_HI, k)
