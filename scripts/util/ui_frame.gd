class_name UIFrame
extends Control
## 【设计框】—— 把一屏的内容装进 1280×720 的框里, 并让这个框【居中于真实视口】。
##
## ═══ 由来(用户 2026-08-01:「有些画面都没有居中」「pc端做一板，手机端做一板」) ═══
## 审计器 tests/_probe_ui_layout.gd 实测(量真实 get_global_rect, 不是看像素猜):
##
##   屏           1280×720 视口   1680×720 视口   差
##   排行榜        居中偏移 -126    -326           -200  ← 一点没重排
##   战绩          -119            -319           -200  ← 一点没重排
##   设置          -174            -374           -200  ← 一点没重排
##   商店          -146            -246           -100  ← 半重排
##   主菜单        +0              +0             0     ← 有 content_root, 正确
##   匹配          +0              -86            -86
##
## 根因: 主菜单/匹配有 `content_root`(1280×720 设计框居中于视口), 其余七屏【没有】——
## 它们直接按设计坐标画在视口 (0,0) 上, 于是宽屏多出来的 400px 全堆在右边,
## 内容整体坐在左边 200px。差值恰好等于 (视口宽-1280)/2, 这是"完全不重排"的指纹。
##
## ═══ 为什么视口宽只会 ≥1280 ═══
## project.godot 是 canvas_items + expand, 基准 1280×720。expand 锁的是【受限的那一轴】:
##   · 窗口比 16:9 宽 → 锁高 720, 宽变大(21:9 → 1680×720)
##   · 窗口比 16:9 窄 → 锁宽 1280, 高变大(iPad 4:3 → 1280×960; 折叠屏 1:1 → 1280×1280)
## 所以内容【永远不会被挤扁】, 只会"多出空地"。适配要解决的不是溢出, 是【多出来的地方怎么分】——
## 大厂做法就是这个: 内容锁在设计框里居中, 背景铺满整窗。
##
## ═══ 用法(每屏一行) ═══
##     func _ready() -> void:
##         ...建完全部 UI...
##         UIFrame.attach(self)          # 放在 _ready 最后
##
## ★满铺层(背景/遮罩, 面积 ≥ 视口 0.95)【不】进框 —— 它们本来就该铺满整窗, 进框会露边。
## ★晚加进来的子节点(异步载数据后建的列表等)会被自动收编: 见 _process 里的孤儿收编。

const DESIGN := Vector2(1280.0, 720.0)
const FULL_BLEED_RATIO := 0.95   # 面积 ≥ 视口×这个比例 = 满铺层, 不进框

var _host: Node = null
var _frame: Control = null
var _last_n: int = -1


## 给 host 建一个居中设计框, 并把它现有的非满铺 Control 子节点收编进去。返回那个框。
## ★UIFrame【自己就是那个框】(extends Control), 不再是"一个 Node 挂着一个 Control 子节点"。
##   由来: 第一版 UIFrame extends Node, 于是 host 底下多出一个【非 Control 的子节点】——
##   商店那边有段代码遍历子节点设 `.visible`, 撞上它直接 SCRIPT ERROR
##   (`Invalid assignment of property 'visible' on a base object of type 'Node'`)。
##   往别人的子节点列表里塞异类, 就是在给所有遍历子节点的代码埋雷。
static func attach(host: Node) -> Control:
	if host == null:
		return null
	# ★幂等: 已经有框就【复用】, 只重新收编+居中。
	#   商店的 _rebuild() 会 free 掉所有子节点再重建(买一件装备就触发一次), 所以它必须在
	#   _rebuild 末尾再 attach 一次 —— 不幂等的话每次重建都多挂一个框。
	for ch in host.get_children():
		# ★必须排掉【已排队删除】的框: queue_free() 是【延迟】的, 同一帧里 is_instance_valid()
		#   还是 true。商店 _rebuild() 开头 queue_free 掉所有子节点、末尾再 attach ——
		#   不判这一条就会复用到那个注定要死的框, 把新内容收编进去, 下一帧连内容一起没了
		#   (实测: 门禁只扫到 1 个可见控件)。
		if ch is UIFrame and is_instance_valid(ch) and not (ch as Node).is_queued_for_deletion():
			(ch as UIFrame)._adopt()
			(ch as UIFrame)._center()
			return ch as Control
	var f := UIFrame.new()
	f.name = "DesignFrame"
	host.add_child(f)
	return f._setup(host)


func _setup(host: Node) -> Control:
	_host = host
	_frame = self
	size = DESIGN
	custom_minimum_size = DESIGN
	# ★★必须是 IGNORE, 【不能】是 PASS —— 这条我第一版写反了, 直接把训龟大师整屏点死
	#   (用户 2026-08-01:「为啥点进训龟大师直接卡死」)。
	#   实测(tests/_probe_hit.gd, 派发真 InputEventMouseButton 数回调次数):
	#     上层框 PASS   → 它【下面】的按钮被点到 0 次   ← 整屏点不动 = 看着像卡死
	#     上层框 IGNORE → 它【下面】的按钮被点到 1 次   ✔
	#     框 IGNORE 时, 框【里】的按钮被点到 1 次       ✔ 收编进来的内容照常能点
	#   即: IGNORE 只让【这个控件自己】不参与命中, 子节点完全不受影响。
	#   而框是最后 add_child 的(画在最上层)又铺满 1280×720 —— 用 PASS 就是一块透明挡板。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_adopt()
	# ★一个都没收编 = 这屏的内容全是【铺满/锚定视口】的(训龟大师就是: dim + CenterContainer 各自
	#   FULL_RECT, 靠 CenterContainer 自己居中)。那种屏本来就已经居中, 不需要设计框 ——
	#   留一个空框在最上层只有坏处(挡命中、污染节点树、让门禁误以为"这屏做了适配")。
	#   ★这也是第二个教训: 门禁只断言了"框的位置对不对", 没断言"框里到底有没有东西",
	#     于是一个【空框】照样能让 ② 全绿。现在直接不留空框。
	if get_child_count() == 0:
		_host.remove_child(self)
		queue_free()
		return null
	_center()
	var vp := _host.get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_resize):
		vp.size_changed.connect(_on_resize)
	return _frame


func _on_resize() -> void:
	_adopt()
	_center()


## 每帧只做一次 int 比较; 子节点数变了才真去收编。
## ★为什么需要它: 有些屏是【异步载完数据再建列表】的(排行榜从云端拉榜), 那些节点建出来的时候
##   size_changed 早就过去了。只在 resize 时收编 = 那些内容永远留在框外, 而且只在非 16:9 屏上看得出来。
func _process(_dt: float) -> void:
	if _host == null or not is_instance_valid(_frame):
		return
	if is_queued_for_deletion() or not is_instance_valid(_host):
		return          # 自己已排队删除(宿主 _rebuild 清场) → 别再动树
	var n: int = _host.get_child_count()
	if n != _last_n:
		_last_n = n
		_adopt()


## 可用区域: 宿主自己的矩形优先, 没有(或明显不合理)才退回视口。
## ★为什么不直接用视口: 无头测试里视口是【方形】的(memory: fb-test-window-right-middle),
##   而门禁会把被测屏的根 Control 强制设成 1280×720 再按绝对坐标找面板 ——
##   按视口居中会把内容整体下移 280px, 门禁就找不到面板了(实测栽过)。
##   真实场景里根 Control 是铺满视口的, 两者相等, 行为不变。
func _avail() -> Vector2:
	if _host is Control:
		var hs: Vector2 = (_host as Control).size
		if hs.x >= DESIGN.x and hs.y >= 360.0:
			return hs
	var vp := _host.get_viewport()
	return Vector2(vp.get_visible_rect().size) if vp != null else DESIGN


func _center() -> void:
	if not is_instance_valid(_frame) or _host == null:
		return
	_frame.position = ((_avail() - DESIGN) * 0.5).round()


## 把 host 下【非满铺】的 Control 子节点搬进框里(保持相对顺序与设计坐标)。
func _adopt() -> void:
	if not is_instance_valid(_frame) or _host == null:
		return
	var vs: Vector2 = _avail()
	var area: float = maxf(1.0, vs.x * vs.y)
	var moved: Array = []
	for ch in _host.get_children():
		if ch == self:
			continue
		# ★跳过【别的 UIFrame】: 商店 _rebuild() 会 queue_free 旧框再建新框, 有那么一帧
		#   两个框同时在树上 —— 不跳的话 A 把 B 收进去、B 的 _process 又想把 A(现在是 B 的祖先)
		#   收进去 → Godot 直接报 "cyclic dependency"。实测就是这么炸的。
		if ch is UIFrame:
			continue
		if not (ch is Control):
			continue
		if (ch as Node).is_queued_for_deletion():
			continue                      # 正在删的节点别搬, 搬进来下一帧连着框一起没
		if (ch as Node).is_ancestor_of(self):
			continue                      # 双保险: 绝不把自己的祖先收进自己
		var c := ch as Control
		# 满铺层留在 host 上(背景/遮罩要铺满整窗)
		if c.size.x * c.size.y >= area * FULL_BLEED_RATIO:
			continue
		# 锚点铺满的(PRESET_FULL_RECT)也留下: 它就是要跟着视口长
		if absf(c.anchor_right - 1.0) < 0.001 and absf(c.anchor_bottom - 1.0) < 0.001 \
				and absf(c.anchor_left) < 0.001 and absf(c.anchor_top) < 0.001:
			continue
		moved.append(c)
	for c in moved:
		var keep: Vector2 = (c as Control).position
		_host.remove_child(c)
		_frame.add_child(c)
		(c as Control).position = keep      # 设计坐标不变 —— 框自己带着偏移, 内容不用改一行定位代码
	_last_n = _host.get_child_count()
