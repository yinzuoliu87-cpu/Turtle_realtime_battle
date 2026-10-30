extends Node
## 自定义鼠标光标 — 1:1 PoC src/systems/cursor.ts (真正运行的那套, 非 index.html --glove 兜底)。
## PoC = 跟随式像素龟爪 div, 带动画: default POINT(爪尖朝上) / pointer 可点(放大1.12+青光+微浮bob)
##   / press 按下(缩0.8) / grab·grabbing 换 FIST 握拳(2026-10-30 起不缩不发光, 见 §配色) / disabled 红化。点击点见下方 §HOT(2026-10-30 起斜指左上)。
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
##   + 正在拖东西(gui_is_dragging ⇒ 握拳) + 外部 force_state (战斗 Area2D 拖拽/选目标无 Control hover, 由场景显式设)。
##
## ═══ §HOT 点击点(2026-10-30 改, 用户「到底什么是鼠标的中心」→「商业游戏做法呢」→「改这个代码肯定要改」) ═══
## 旧爪子三根爪一样长、朝正上, 点击点在中爪尖 (11,1), 而圆团身子的中心比它低 11.6 设计px ⇒ 三个「尖」, 看不出点在哪。
## 照商业游戏: 英雄联盟护手 / Dota 2(官方规范: 点击点 = 默认箭头尖) / 星露谷 / 暗黑都是【斜指左上、只有一个尖】;
##   拖东西时换握拳, 点击点在最前那颗指节(Chrome grabbing)。⇒ 中趾沿对角线伸向左上、爪尖 = 点击点 HOT;
##   两侧短趾; 握拳的点击点 HOT_FIST = 左上第一颗指节。
## 缩放锚 = 当前点击点 ⇒ 按下缩小 / 悬停放大时爪尖不离开鼠标点。
##
## ═══ §配色 浅色填充 + 深描边(2026-10-30 第二轮, 用户看过方向稿:「你直接改吧」) ═══
## 第一轮沿用的绿身绿爪压在绿龟 / 绿小将 / 绿装备格上几乎看不见, 握拳是一团、看着像绿宝石。
## 商业光标(英雄联盟金护手 / Dota 2 银箭头 / Chrome 白握拳)一律【浅色填充 + 粗深描边】、不用游戏主色
##   ⇒ 暖白身 + 近黑描边 + 琥珀爪尖(= 点击点); 握拳重画成三颗指节 + 折痕, 爪尖收着看不见。
##   八块实拍背景(绿龟 / 绿小将 / 绿装备格 / 金框 / 羊皮纸 / 深蓝格 / 木头 / 白胸甲)上比过三种浅色:
##   浅金在金框和羊皮纸上发糊, 纯白跟木头 / 羊皮纸的暖色不搭 ⇒ 暖白。
## 拖东西时握拳原大、不发青光(拿掉 PoC 的「grabbing 缩 0.9 + 青光」); 悬停可点仍是放大 + 青光 + 浮动。
## 画法: 12×12 大块(每块 2×2 像素)手画; 色号 0 爪尖 / 1 描边 / 2 身 / 3 暗面 / 4 高光(光从左上来)。
## 守卫: tests/verify_drag_lift.gd C1 爪尖 = HOT、C2 第一颗指节 = HOT_FIST、C3 拖动中握拳且不缩不发光、
##   C4 轮廓一圈全是深描边且身是浅色; verify_ui_consistency CURSOR_SCALE(爪尖落在鼠标点)。

# ── POINT (平时: 斜指左上, 24×24) — 色号: 0 琥珀爪尖 / 1 近黑描边 / 2 暖白身 / 3 暗面 / 4 高光(见 §配色) ──
var _point_cols := [Color("#f0a82e"), Color("#1a1310"), Color("#f4ecd8"), Color("#c8b48e"), Color("#ffffff")]
var _point_rects := PackedInt32Array([
	1,2,0,4,2, 1,0,2,2,2, 0,2,2,4,2, 1,6,2,2,2, 1,16,2,2,2, 1,0,4,2,2, 0,2,4,2,2, 2,4,4,4,2, 1,8,4,2,2, 1,14,4,2,2,
	0,16,4,2,2, 1,18,4,2,2, 1,2,6,2,2, 2,4,6,6,2, 1,10,6,6,2, 2,16,6,2,2, 1,18,6,2,2, 1,4,8,2,2, 2,6,8,10,2, 3,16,8,2,2,
	1,18,8,2,2, 1,6,10,2,2, 2,8,10,2,2, 4,10,10,4,2, 2,14,10,4,2, 3,18,10,2,2, 1,20,10,2,2, 1,6,12,2,2, 2,8,12,2,2, 4,10,12,2,2,
	2,12,12,8,2, 3,20,12,2,2, 1,22,12,2,2, 1,4,14,4,2, 2,8,14,12,2, 3,20,14,2,2, 1,22,14,2,2, 1,2,16,2,2, 0,4,16,2,2, 2,6,16,2,2,
	3,8,16,2,2, 2,10,16,10,2, 3,20,16,2,2, 1,22,16,2,2, 1,4,18,6,2, 3,10,18,2,2, 2,12,18,6,2, 3,18,18,2,2, 1,20,18,2,2, 1,10,20,2,2,
	3,12,20,6,2, 1,18,20,2,2, 1,12,22,6,2,
])
# ── FIST (拖东西时: 三颗指节 + 折痕的握拳, 爪尖收着, 24×24) ──
var _fist_cols := [Color("#f0a82e"), Color("#1a1310"), Color("#f4ecd8"), Color("#c8b48e"), Color("#ffffff")]
var _fist_rects := PackedInt32Array([
	1,4,2,4,2, 1,10,2,4,2, 1,16,2,4,2, 1,2,4,2,2, 4,4,4,2,2, 2,6,4,2,2, 1,8,4,2,2, 2,10,4,4,2, 1,14,4,2,2, 2,16,4,4,2,
	1,20,4,2,2, 1,2,6,2,2, 2,4,6,4,2, 1,8,6,2,2, 2,10,6,4,2, 1,14,6,2,2, 2,16,6,2,2, 3,18,6,2,2, 1,20,6,2,2, 1,0,8,2,2,
	2,2,8,18,2, 3,20,8,2,2, 1,22,8,2,2, 1,0,10,2,2, 2,2,10,2,2, 4,4,10,2,2, 2,6,10,14,2, 3,20,10,2,2, 1,22,10,2,2, 1,0,12,2,2,
	2,2,12,18,2, 3,20,12,2,2, 1,22,12,2,2, 1,2,14,2,2, 2,4,14,14,2, 3,18,14,2,2, 1,20,14,2,2, 1,2,16,2,2, 3,4,16,2,2, 2,6,16,12,2,
	3,18,16,2,2, 1,20,16,2,2, 1,4,18,2,2, 3,6,18,4,2, 2,10,18,4,2, 3,14,18,4,2, 1,18,18,2,2, 1,6,20,4,2, 3,10,20,4,2, 1,14,20,4,2,
	1,10,22,4,2,
])

const ART := 24                      # 贴图美术宽 (点击点基于 24×24 坐标)
const HOT := Vector2(2, 2)           # 平时: 中趾琥珀爪尖的左上角(见 §HOT)
const HOT_FIST := Vector2(4, 4)      # 握拳: 左上第一颗指节的左上角

var _point_tex: ImageTexture
var _fist_tex: ImageTexture
var _layer: CanvasLayer
var _cur: Control                    # 跟随根 (定位 + 缩放/旋转锚)
var _g: TextureRect                  # 爪本体
var _glow: TextureRect               # 青光层 (只有 pointer 显; 拖东西不发光, 见 §配色)
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
	if uses_os_cursor():
		_build_os_cursor()
		return
	_build_cursor()


## ★Mac 不自绘, 把爪子交给系统当光标(2026-10-14 内测:「外部鼠标和绘制的鼠标图案重合」)。
##   自绘这套靠 MOUSE_MODE_HIDDEN 藏系统光标, 而 macOS 上系统光标会自己回来
##   (切窗口 / 碰 Dock / 从窗外移进来), 于是屏上同时两个箭头; 自绘的又比系统光标晚一帧, 一动就错开。
##   系统光标由操作系统画: 不会有第二个, 也不拖帧。
##   代价(已知): 没有悬停青光 / 浮动 / 按下缩小这些动画; 状态只剩「普通 / 可点 / 抓取 / 禁用」四张图。
##   守卫: tests/verify_cursor_mac_os_cursor.gd
static var platform_override := ""


static func uses_os_cursor() -> bool:
	var plat: String = platform_override if platform_override != "" else OS.get_name()
	return plat == "macOS"


func _build_os_cursor() -> void:
	_enabled = false
	set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	## 1 倍贴图 = 24 点, 与自绘那只同为 24 设计px(见 §CURSOR_SCALE); 点击点与自绘同一对 HOT / HOT_FIST。
	var point := _build(1, _point_cols, _point_rects, 24, 24)
	var fist := _build(1, _fist_cols, _fist_rects, 24, 24)
	var red_cols: Array = []
	for c in _point_cols:
		red_cols.append(Color(c.r, c.g * 0.45, c.b * 0.4, c.a))
	var forbidden := _build(1, red_cols, _point_rects, 24, 24)
	Input.set_custom_mouse_cursor(point, Input.CURSOR_ARROW, HOT)
	Input.set_custom_mouse_cursor(point, Input.CURSOR_POINTING_HAND, HOT)
	Input.set_custom_mouse_cursor(fist, Input.CURSOR_DRAG, HOT_FIST)
	Input.set_custom_mouse_cursor(fist, Input.CURSOR_CAN_DROP, HOT_FIST)
	Input.set_custom_mouse_cursor(forbidden, Input.CURSOR_FORBIDDEN, HOT)


## 建爪子(贴图 + 顶层 CanvasLayer + 跟随节点)。
## ★从 `_ready` 抽出来的**唯一**原因: 无头下 `_ready` 必须早退(没有显示), 于是门禁想量
##   "爪子在屏上多大" 就只能自己照抄一份建树代码 —— 而手抄的副本必然落后(见 memory)。
##   抽成函数后门禁调的是**产品自己这一份**, 只绕过平台早退那两行。
func _build_cursor() -> void:
	_point_tex = _build(2, _point_cols, _point_rects, 24, 24)
	_fist_tex = _build(2, _fist_cols, _fist_rects, 24, 24)
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
	_cur.pivot_offset = HOT
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
		## 正在拖东西(背包 / 选统领拿起一张卡)⇒ 握拳。原来没有任何可拖控件把光标形状设成「抓取」, 卷爪从来没出现过。
		if vp.gui_is_dragging():
			st = "grabbing"
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
		## 拖东西: 握拳原大、不发青光(§配色)。这一支不能删 —— 拖动时左键是按着的, 落到下一支会被「按下」缩成 0.8。
		base_scl = 1.0
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
	## 缩放锚 = 点击点, position = 鼠标 − 点击点 ⇒ 不论缩放, 爪尖恒落鼠标点; bob 叠加竖移
	var hot := hot_for(use_fist)
	_cur.pivot_offset = hot
	_cur.position = pos - hot + Vector2(0, bob_y)


## 这张贴图的点击点(握拳 / 平时)。实拍脚本与门禁也读它, 不另抄一份。
func hot_for(fist: bool) -> Vector2:
	return HOT_FIST if fist else HOT


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
