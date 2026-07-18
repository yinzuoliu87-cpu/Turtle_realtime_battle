extends Node
## 自定义鼠标光标 — 1:1 PoC src/systems/cursor.ts (真正运行的那套, 非 index.html --glove 兜底)。
## PoC = 跟随式像素龟爪 div, 带动画: default POINT(爪尖朝上) / pointer 可点(放大1.12+青光+微浮bob)
##   / press 按下(缩0.8) / grab·grabbing 换 FIST 卷爪(grabbing 缩0.9+青光) / disabled 红化。hotspot=(11,1)。
## Godot 实现: 隐藏系统光标(MOUSE_MODE_HIDDEN) + 顶层 CanvasLayer 自绘跟随节点, 每帧测状态切贴图/缩放/青光。
##   尺寸固定屏幕 ~24px (除内容缩放因子, 1:1 PoC position:fixed div 不随画布缩放)。
## 状态测法: gui_get_hovered_control().get_cursor_shape() (覆盖所有 Control UI) + 全局鼠标键(press)
##   + 外部 force_state (战斗 Area2D 拖拽/选目标无 Control hover, 由场景显式设)。

# ── POINT (默认绿龟爪, 24×24, 爪尖朝上) — 色: 奶白爪尖/深绿描边/绿/高光 ──
var _point_cols := [Color("#ffe9b0"), Color("#1f6b3f"), Color("#3cba6e"), Color("#7fe6a0")]
var _point_rects := PackedInt32Array([
	0,4,0,2,4, 0,10,0,2,4, 0,16,0,2,4, 1,2,4,18,2, 1,2,6,2,2, 1,18,6,2,2, 1,0,8,4,2, 1,20,8,2,2, 1,0,10,2,2, 1,20,10,2,2,
	1,0,12,2,2, 1,20,12,2,2, 1,0,14,2,2, 1,20,14,2,2, 1,2,16,2,2, 1,18,16,2,2, 1,2,18,2,2, 1,18,18,2,2, 1,4,20,2,2, 1,16,20,2,2,
	1,6,22,10,2, 2,4,6,6,2, 2,12,6,6,2, 2,4,8,6,2, 2,12,8,8,2, 2,2,10,8,2, 2,12,10,8,2, 2,2,12,2,2, 2,8,12,12,2, 2,2,14,18,2,
	2,4,16,14,2, 2,4,18,14,2, 2,6,20,10,2, 3,10,6,2,2, 3,10,8,2,2, 3,10,10,2,2, 3,4,12,4,2,
])
# ── FIST (抓取卷爪, 24×22) ──
var _fist_cols := [Color("#1f6b3f"), Color("#3cba6e"), Color("#7fe6a0")]
var _fist_rects := PackedInt32Array([
	0,6,2,10,2, 0,2,4,4,2, 0,16,4,4,2, 0,0,6,2,2, 0,20,6,2,2, 0,0,8,2,2, 0,20,8,2,2, 0,0,10,2,2, 0,20,10,2,2, 0,0,12,2,2,
	0,20,12,2,2, 0,2,14,2,2, 0,18,14,2,2, 0,4,16,2,2, 0,16,16,2,2, 0,6,18,10,2, 1,6,4,10,2, 1,2,6,18,2, 1,2,8,8,2, 1,12,8,8,2,
	1,2,10,18,2, 1,2,12,18,2, 1,4,14,14,2, 1,6,16,10,2, 2,10,8,2,2, 2,4,6,4,2,
])

const ART := 24                      # 贴图美术宽 (热点基于 24×24 坐标)
const HOT := Vector2(11, 1)          # PoC hotspot (中爪尖)
const ORIGIN := Vector2(11.04, 1.44) # PoC transform-origin 46% 6% (×24) — 缩放锚

var _point_tex: ImageTexture
var _fist_tex: ImageTexture
var _layer: CanvasLayer
var _cur: Control                    # 跟随根 (定位 + 缩放/旋转锚)
var _g: TextureRect                  # 爪本体
var _glow: TextureRect               # 青光层 (pointer/grabbing 显)
var _forced: String = ""             # 外部强制态 ("grab"/"grabbing"/"disabled"/"" 自动)
var _enabled := false


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return   # 单测无显示
	if OS.get_name() in ["Android", "iOS"]:
		return   # 移动端触屏无鼠标 → 不建自绘光标(否则屏上残留一只绿龟爪·用户2026-07-18)
	_point_tex = _build(2, _point_cols, _point_rects, 24, 24)
	_fist_tex = _build(2, _fist_cols, _fist_rects, 24, 22)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_layer = CanvasLayer.new()
	_layer.layer = 4096   # 顶到最高 (盖一切 UI)
	add_child(_layer)
	_glow = TextureRect.new()
	_glow.texture = _point_tex
	_glow.custom_minimum_size = Vector2(ART, ART)
	_glow.size = Vector2(ART, ART)
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.material = _make_glow_mat()
	_glow.visible = false
	_g = TextureRect.new()
	_g.texture = _point_tex
	_g.custom_minimum_size = Vector2(ART, ART)
	_g.size = Vector2(ART, ART)
	_g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_g.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cur = Control.new()
	_cur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cur.pivot_offset = ORIGIN
	_cur.add_child(_glow)
	_cur.add_child(_g)
	_layer.add_child(_cur)
	_enabled = true
	set_process(true)


## 外部强制光标态 (战斗 Area2D 拖拽/选目标 无 Control hover 时调; 传 "" 恢复自动)
func force_state(s: String) -> void:
	_forced = s


func _process(_dt: float) -> void:
	if not _enabled:
		return
	# 系统光标可能被场景重置 → 每帧重申隐藏
	if Input.mouse_mode != Input.MOUSE_MODE_HIDDEN and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var vp := get_viewport()
	if vp == null:
		return
	var pos := vp.get_mouse_position()
	# ── 测状态 ──
	var pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var st := _forced
	if st == "":
		st = "default"
		var hov := vp.gui_get_hovered_control()
		if hov != null:
			match hov.get_cursor_shape(hov.get_local_mouse_position()):
				Control.CURSOR_POINTING_HAND:
					st = "pointer"
				Control.CURSOR_DRAG, Control.CURSOR_CAN_DROP:
					st = "grab"
				Control.CURSOR_FORBIDDEN:
					st = "disabled"
	# press 优先 (grab 时按下→grabbing, 否则 default/pointer 都缩)
	var grabbing := st == "grabbing" or (st == "grab" and pressed)
	# ── 贴图 ──
	var use_fist := grabbing or st == "grab"
	_g.texture = _fist_tex if use_fist else _point_tex
	_glow.texture = _g.texture
	# ── 缩放/青光/红化 ──
	var base_scl := 1.0
	var glow := false
	var tint := Color.WHITE
	if st == "disabled":
		tint = Color(1.0, 0.45, 0.4)        # 红化近似 (PoC sepia+hue 红)
	elif grabbing:
		base_scl = 0.9; glow = true
	elif pressed:
		base_scl = 0.8                       # is-press 缩
	elif st == "pointer":
		# bob: scale 1.12 + translateY 0↔-2px @ .9s ease-in-out
		base_scl = 1.12; glow = true
	# bob 竖向位移 (仅 pointer 非按下)
	var bob_y := 0.0
	if st == "pointer" and not pressed:
		var t := float(Time.get_ticks_msec()) / 1000.0
		bob_y = -2.0 * (0.5 - 0.5 * cos(t / 0.45 * PI))   # 0↔-2, 周期 .9s
	_g.modulate = tint
	_glow.visible = glow
	# 内容缩放反向 → 屏幕固定 ~24px (1:1 PoC fixed div 不随画布缩)
	var cf := vp.get_screen_transform().get_scale().y
	cf = clampf(cf, 0.5, 4.0)
	_cur.scale = Vector2.ONE * (base_scl / cf)
	# pivot 在 ORIGIN, position = 鼠标 - 热点 → 热点恒落鼠标点; bob 叠加竖移
	_cur.position = pos - HOT + Vector2(0, bob_y)


# 青光 shader: 采样自身 alpha 做小高斯外扩 → 青色 drop-shadow 近似 (PoC drop-shadow 0 0 5px cyan)
func _make_glow_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	vec2 ps = TEXTURE_PIXEL_SIZE;
	float a = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			a = max(a, texture(TEXTURE, UV + vec2(float(x), float(y)) * ps * 1.6).a);
		}
	}
	COLOR = vec4(0.49, 0.88, 1.0, a * 0.85);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _build(scale: int, cols: Array, rects: PackedInt32Array, w: int, h: int) -> ImageTexture:
	var img := Image.create(w * scale, h * scale, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var n := int(rects.size() / 5)
	for i in range(n):
		var ci := rects[i * 5]
		img.fill_rect(Rect2i(rects[i * 5 + 1] * scale, rects[i * 5 + 2] * scale, rects[i * 5 + 3] * scale, rects[i * 5 + 4] * scale), cols[ci])
	return ImageTexture.create_from_image(img)
