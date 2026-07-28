class_name IdleMode
extends RefCounted
## 摸鱼模式（游戏内竖版小窗口）— 方案书 docs/plans/20260729b-摸鱼模式小窗口.md
##
## 需求（用户 2026-07-28）：
##   「针对 iOS 手机出一个摸鱼模式，放置在设置里面一个按钮，点击后整个游戏在手机上以
##     小窗口的形式运行，就像框中框的形式一样，竖着的，可以正常点击交互，再次点可以还原」
##   追问后拍板：「A 小窗口也行的」「留黑就好」
##   「摸鱼模式就跟手机横屏完全一样的比例，只是小屏方便摸鱼，所以不用去专门适配」
##   → 手机【竖着拿】，屏幕中间一条 16:9 的小横窗，上下大片留黑。
##
## ══ 为什么最后没走方案书 §4 的三条路线 ══
##
## 方案书当时列了三条：改 content_scale / 整个塞进 SubViewport / 改 canvas_transform+黑边遮罩，
## 并把「输入坐标映射」标成最大风险（§6.2：缩放后触摸点的屏幕坐标 ≠ 游戏内坐标，
## 项目里多处直接读 `get_viewport().get_mouse_position()`，全都会偏）。
##
## ★但这个需求其实是 Godot 的【内置能力】，不需要自己做任何坐标变换：
##   · `stretch/aspect = "keep"` 就是标准的 letterbox —— 内容按基准比例居中、多出来的地方留黑
##   · 屏幕方向切成竖屏后，1280×720 的内容在竖屏视口里自动变成「中间一条横带，上下黑」
##   · **输入坐标由引擎在 stretch 层统一换算**，`get_mouse_position()` 拿到的一直是画布坐标
##
## 所以实现只有两行开关。自己写 canvas_transform + 黑边遮罩反而要把 §6.2 那个风险
## 亲手引入一遍 —— 那是在重造引擎已经做对的事。
##
## ══ 还剩的真风险 ══
## · iOS 上运行时切方向靠 `DisplayServer.screen_set_orientation()`，**未在真机验过**
##   （本项目没有 macOS，只能出包装机验 —— 见 CLAUDE.md §6）
## · `SafeArea.margins()` 按视口尺寸算刘海/手势条边距；竖屏下视口变高，边距基准会变
##   （方案书 §6.3 的未决点，这里按"仍用视口口径"处理 —— 小窗四周本来就是黑边，
##     多留一点白不会挡内容）

## 摸鱼模式下的屏幕方向。竖着拿 → 内容 letterbox 成中间一条横带。
const ORIENT_IDLE := DisplayServer.SCREEN_PORTRAIT
const ORIENT_NORMAL := DisplayServer.SCREEN_SENSOR_LANDSCAPE


## 应用开关。win 传 get_window()。
##
## ★aspect 必须一起改：只改方向不改 aspect 的话，"expand" 会把内容【拉伸铺满竖屏】——
##   画面变形，而不是留黑。这两件事必须成对。
static func apply(win: Window, on: bool) -> void:
	if win == null:
		return
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP if on else Window.CONTENT_SCALE_ASPECT_EXPAND
	if DisplayServer.has_feature(DisplayServer.FEATURE_ORIENTATION):
		DisplayServer.screen_set_orientation(ORIENT_IDLE if on else ORIENT_NORMAL)
	elif not on:
		return
	else:
		# 桌面没有 orientation 特性 —— 用【把窗口改成竖长条】来等价模拟，
		# 好让开发机上能自验版式与点击，而不是只能出包到真机才看得见。
		# (EQDEMO 那次教训: 开发机上永远跑不到的路径, 等于没写。)
		var scr: Vector2i = DisplayServer.screen_get_size()
		var h: int = mini(scr.y - 80, 1000)
		win.size = Vector2i(int(float(h) * 9.0 / 16.0), h)


## 当前是否在摸鱼模式（读窗口实际状态，不读存档 —— 存档可能与实际不同步）
static func is_on(win: Window) -> bool:
	return win != null and win.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP


## 给定视口尺寸，算出小窗（内容区）在屏幕上的矩形。
##
## ★这是【门禁要断言的东西】：需求第 4 条「小窗内可正常点击交互」不能靠目视，
##   要能算出内容区在哪、并验证屏幕坐标 → 画布坐标的换算是对的。
## base = 基准分辨率（project.godot 的 1280×720）。
static func content_rect(viewport_size: Vector2, base: Vector2) -> Rect2:
	if base.x <= 0.0 or base.y <= 0.0:
		return Rect2(Vector2.ZERO, viewport_size)
	var scale: float = minf(viewport_size.x / base.x, viewport_size.y / base.y)   # KEEP = 取小者
	var sz: Vector2 = base * scale
	return Rect2((viewport_size - sz) * 0.5, sz)


## 屏幕坐标 → 画布坐标（引擎内部做的就是这个换算；这里独立实现一份供门禁对照）。
## ★两份实现算出来一样，才说明"点击落在预期控件上"这件事是真的成立，
##   而不是我假设引擎会处理。
static func screen_to_canvas(screen_pos: Vector2, viewport_size: Vector2, base: Vector2) -> Vector2:
	var r: Rect2 = content_rect(viewport_size, base)
	if r.size.x <= 0.0:
		return screen_pos
	return (screen_pos - r.position) / (r.size.x / base.x)
