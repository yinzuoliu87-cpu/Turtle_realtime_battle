extends Node
## 自定义鼠标光标 — 1:1 PoC src/systems/cursor.ts (真正运行的那套, 非 index.html --glove 兜底)。
## PoC = 跟随式像素龟爪 div, 带动画: default POINT(爪尖朝上) / pointer 可点(放大1.12+青光+微浮bob)
##   / press 按下(缩0.8) / grab·grabbing 换 FIST 卷爪(grabbing 缩0.9+青光) / disabled 红化。hotspot=(11,1)。
## Godot 实现: 隐藏系统光标(MOUSE_MODE_HIDDEN) + 顶层 CanvasLayer 自绘跟随节点, 每帧测状态切贴图/缩放/青光。
##   尺寸 = **24 个设计像素**(与场上一切像素同比例缩放)。★这不是 PoC 的那条规矩, 见 §CURSOR_SCALE。
##
## ═══ §CURSOR_SCALE 光标尺寸的口径(2026-09-30 改, 用户「这个光标为什么这么大？」) ═══
## ★**两个 bug 叠在一起**, 所以它比看代码想象的还要大一倍。都是探针实测的
##   (tests/_probe_cursor_size.gd 量比例 / tests/_probe_paw.gd 量真节点几何), 不是推算:
##
## ① 旧的 `_cur.scale = base_scl / clampf(cf, 0.5, 4.0)` 把爪子钉在**屏幕物理像素**上,
##    故意不随内容缩放(照抄 PoC 那个 `position:fixed` div) ⇒ 换算成设计像素时它**随窗口变四倍**。
## ② `_g.size = Vector2(ART, ART)` 那一行**写在 `expand_mode` 之前**, 而默认 expand_mode 是
##    `EXPAND_KEEP_SIZE` ⇒ 最小尺寸 = 贴图尺寸 **48**(`_build` 按 2× 放大过) ⇒ `size` 当场被
##    上调到 48 并且再也没缩回来。**实测 `_g.size = (48, 48)`**, 是 `ART` 的两倍。
##    连带: `HOT(11,1)` / `ORIGIN` 都是 24 坐标系的 ⇒ **爪尖画在鼠标点右下 (11, 1) 设计px**,
##    即"热点"整个是歪的(实测偏移 (11,1); 修好后是 (0,0))。
##
## 两条叠起来的实际尺寸(旧, 单位=设计px; 参照: 摆位屏「开打」钮 220×62 / 本仓触控下限 TOUCH_MIN=81):
##   | 窗口 | cf | 实测设计px | 占开打钮高 | 占触控下限 | 物理px |
##   | 2560×1440 | 2.000 | 24.0 | 39%  | 30%  | 48.0 |
##   | 1920×1080 | 1.500 | 32.0 | 52%  | 40%  | 48.0 |
##   | 1280×720  | 1.000 | 48.0 | 77%  | 59%  | 48.0 |
##   | 640×360   | 0.500 | 96.0 | 155% | 119% | 48.0 |
##   | 480×270   | 0.375→**夹到 0.5** | 96.0 | 155% | 119% | 36.0 |
## ⇒ 用户看到的"太大"就是小窗口那几行: **一只爪子比「开打」钮还高一半**。
##   而文件头原来写的"固定屏幕 ~24px"两头都不对: 真实是 48 物理px, 且 `clampf` 下界在 480 宽
##   时**真的被夹住**(36 而不是 48) —— 那句承诺本来就是假的, 624 宽时只差 2.5% 才一直没被发现。
##
## ★**为什么选"跟着 UI 缩"而不是"修 clamp 下界"**: 这是**手机触屏游戏** —— 下面 `_ready` 的早退
##   写着 Android/iOS **一只爪子都不建**(用户 2026-07-18: 手机上是屏上残留)。也就是说这只爪子
##   **只存在于桌面/开发期**, 不是玩家实际游玩的形态。既然如此, 「和屏上别的东西同一套比例」
##   比「1:1 复刻网页 PoC 的 fixed div」重要得多; 而修 clamp 下界只会让小窗口的爪子**更大**
##   (48 物理px ÷ 0.375 = 128 设计px), 正好把用户抱怨的那件事做得更狠。
## ⇒ 改法(两条各修一处):
##   ① `_cur.scale` **只吃状态缩放**(0.8/0.9/1.0/1.12), 不再碰 cf;
##   ② `expand_mode` 提到 `size` 之前 ⇒ 控件框真的是 `ART`=24。
##   合起来: 爪子恒 **24 设计px** = 开打钮高的 39% / 触控下限的 30%, 与窗口无关; 热点归零。
##   (24 也正是 `ART` / `HOT` / `ORIGIN` 三个常量自己写的坐标系 —— 这不是我另定的数。)
##   代价(已知, 接受): 小窗口下物理像素跟着变小(624 宽时 11.7px)。它和场上每一个像素同比例,
##   这正是"一致"的定义; 而且非整数倍缩放时它与别的像素画**糊得一样**, 不再独一份地抖。
## ⇒ 门禁: `tests/verify_ui_consistency.gd` 的 `_test_cursor_scale`(搜 CURSOR_SCALE)。
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
	# ★暂停时也要跟手(用户 2026-07-22:「点暂停光标没有动啊，这是大问题」)。
	#   自绘光标靠 _process 每帧贴到鼠标位置; autoload 默认 process_mode=INHERIT,
	#   跟着 root 的 PAUSABLE 走 → get_tree().paused 后 _process 直接停跑 → 光标定在原地,
	#   而系统光标又是 MOUSE_MODE_HIDDEN 的, 于是看起来"鼠标彻底失灵"。
	#   探针实测(2026-07-22): 暂停后 can_process() = false。
	#   ★必须放在下面几个早退【之前】—— 放后面的话无头/移动端根本执行不到, 门禁也验不着。
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		return   # 单测无显示
	if OS.get_name() in ["Android", "iOS"]:
		return   # 移动端触屏无鼠标 → 不建自绘光标(否则屏上残留一只绿龟爪·用户2026-07-18)
	_build_cursor()


## 建爪子(贴图 + 顶层 CanvasLayer + 跟随节点)。
## ★从 `_ready` 抽出来的**唯一**原因: 无头下 `_ready` 必须早退(没有显示), 于是门禁想量
##   "爪子在屏上多大" 就只能自己照抄一份建树代码 —— 而手抄的副本必然落后(见 memory)。
##   抽成函数后门禁调的是**产品自己这一份**, 只绕过平台早退那两行。
func _build_cursor() -> void:
	_point_tex = _build(2, _point_cols, _point_rects, 24, 24)
	_fist_tex = _build(2, _fist_cols, _fist_rects, 24, 22)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_layer = CanvasLayer.new()
	_layer.layer = 4096   # 顶到最高 (盖一切 UI)
	add_child(_layer)
	_glow = TextureRect.new()
	_glow.texture = _point_tex
	## ★★`expand_mode` 必须在 `size` 【之前】设(2026-09-30 修, 见文件头 §CURSOR_SCALE 第 ② 条)。
	##   默认 expand_mode 是 `EXPAND_KEEP_SIZE` ⇒ 最小尺寸 = 贴图尺寸(48, 因为 `_build` 按 2× 放大),
	##   于是 `size = 24` 当场被**上调成 48**, 再改 expand_mode 也不会缩回去(Control 不会主动缩)。
	##   后果(探针实测): 爪子一直是 ART 的**两倍**, 而 `HOT`/`ORIGIN` 还是 24 坐标系的 ⇒ 热点偏了。
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.custom_minimum_size = Vector2(ART, ART)
	_glow.size = Vector2(ART, ART)
	_glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.material = _make_glow_mat()
	_glow.visible = false
	_g = TextureRect.new()
	_g.texture = _point_tex
	_g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # ★同上: 必须在 size 之前, 否则 size 被上调到 48
	_g.custom_minimum_size = Vector2(ART, ART)
	_g.size = Vector2(ART, ART)
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
	## ★§CURSOR_SCALE(见文件头): **只吃状态缩放, 不碰内容缩放因子**。
	##   爪子恒 24 设计px, 和场上每个像素同比例 —— 相对 UI 的大小不再随窗口变四倍。
	##   (旧写法: `base_scl / clampf(vp.get_screen_transform().get_scale().y, 0.5, 4.0)`)
	_cur.scale = Vector2.ONE * base_scl
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
