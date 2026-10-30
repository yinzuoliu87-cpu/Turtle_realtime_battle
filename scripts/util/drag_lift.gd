extends Control
class_name DragLift
## 拿起来跟手的那张 —— 背包(装备 / 单位卡 / 卡上的装备)与选统领页(龟卡 / 编队槽)共用一套(2026-10-30)。
##
## 用户 10-29「我抓起卡片这个中心怎么搞」→ 10-30「商业游戏做法呢」→「改这个代码肯定要改」。
## 原来四处三种摆法, 而且都是瞬间跳: 装备拿起往上跳约 70px 悬在鼠标上方; 单位卡跳到「鼠标在卡的中间偏下」;
##   选统领页只跟一个 56px 小头像, 用 Godot 默认摆法(预览左上角对鼠标)挂在右下。
## 现在照杀戮尖塔 2(反编译 NMouseCardPlay.LerpToMouse: 卡中心按指数趋近追到鼠标)与小丑牌(拿起放大 10%、投影加深):
##   · 拿起那一刻: 按下的那一点正好在鼠标下 —— 不跳
##   · 然后卡中心平滑滑到鼠标下(电脑) / 抬到手指上方(手机, 照 Backpack Battles「拾取偏移」: 手指不挡住卡)
##   · 放大 LIFT、摆正、带投影; 原位留虚影(固定格子, 不像手牌那样合拢让位), 拖动结束(落下或放弃)时自己复原
## 放到哪由鼠标那一点判定(引擎), 电脑上卡中心对准鼠标 = 看着放在哪就放到哪。
## Godot 每次鼠标移动都把预览根节点重设到鼠标点(viewport.cpp _gui_set_drag_preview / 拖动中 set_position),
##   所以根节点 = 鼠标点, 偏移全在子节点 _body 上; 拖动结束引擎会删掉预览 ⇒ 删除时还原虚影(见 _notification)。
## 守卫: tests/verify_drag_lift.gd

const LIFT := 1.08          # 拿起放大
const GLIDE := 12.0         # 每秒趋近率: 剩余位移 × exp(-GLIDE·秒), 约 0.25 秒滑到位
const TOUCH_GAP := 18.0     # 手机: 卡底离手指
const GHOST_A := 0.35       # 原位虚影
const SHADOW := Vector2(6, 8)

## 门禁用: -1 跟平台 / 0 当电脑 / 1 当手机
static var force_touch := -1
static var _last: WeakRef = null

var grab := Vector2.ZERO     # 按下点(卡内坐标)
var target := Vector2.ZERO   # _body 滑到位后的位置
var touch := false
var _body: Control
var _src: Control = null
var _src_a := 1.0


static func is_touch() -> bool:
	if force_touch >= 0:
		return force_touch == 1
	return SafeArea.is_mobile()


## 最近一次拿起来的那张(还在拖 ⇒ 有效)。门禁读它。
static func last() -> DragLift:
	return (_last.get_ref() as DragLift) if _last != null else null


## src = 原位那个控件(留虚影的对象); face = 跟手显示的那张(null ⇒ 复制 src);
## frac = 按下点在 face 上的相对位置(0~1); ghost = 原位要不要变虚影。
static func make(src: Control, face: Control, frac: Vector2, ghost: bool = true) -> DragLift:
	var d := DragLift.new()
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f: Control = face if face != null else (src.duplicate(0) as Control)
	var sz: Vector2 = f.size if face != null else src.size
	f.position = Vector2.ZERO
	f.size = sz
	f.rotation = 0.0
	f.scale = Vector2.ONE
	f.modulate = Color(1, 1, 1, 1)
	_ignore_mouse(f)
	d._body = Control.new()
	d._body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d._body.size = sz
	d._body.pivot_offset = sz * 0.5
	d._body.scale = Vector2.ONE * LIFT
	var sh := ColorRect.new()
	sh.color = Color(0, 0, 0, 0.32)
	sh.size = sz
	sh.position = SHADOW
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d._body.add_child(sh)
	d._body.add_child(f)
	d.add_child(d._body)
	d.grab = Vector2(clampf(frac.x, 0.0, 1.0) * sz.x, clampf(frac.y, 0.0, 1.0) * sz.y)
	d.touch = is_touch()
	## 卡内一点 p 画在 _body.position + 中心 + (p − 中心)·LIFT ⇒ 要它落在根节点(鼠标点)上:
	d._body.position = -(sz * 0.5 + (d.grab - sz * 0.5) * LIFT)
	if d.touch:
		## 卡底(放大后)离手指 TOUCH_GAP, 左右居中
		d.target = Vector2(-sz.x * 0.5, -TOUCH_GAP - sz.y * 0.5 * (1.0 + LIFT))
	else:
		d.target = -sz * 0.5
	if ghost and src != null:
		d._src = src
		d._src_a = src.modulate.a
		src.modulate.a = GHOST_A
	_last = weakref(d)
	return d


static func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)


func _process(dt: float) -> void:
	step(dt)


## 往目标滑 dt 秒(门禁直接调它量「滑到位」, 不靠帧率)。
func step(dt: float) -> void:
	_body.position = target + (_body.position - target) * exp(-GLIDE * dt)


## 卡中心此刻相对鼠标点的位置(电脑上滑到位 = 0)。
func center_offset() -> Vector2:
	return _body.position + _body.size * 0.5


## 按下那一点此刻相对鼠标点的位置(拿起那一刻 = 0)。
func grab_offset() -> Vector2:
	return _body.position + _body.size * 0.5 + (grab - _body.size * 0.5) * LIFT


## 原位虚影在【真被删掉】时复原(拖动结束引擎删预览), 不在退出场景树时 ——
##   背包页的 UIFrame 每帧把新子节点收进设计框, 预览刚挂上就被搬一次家(退出再进入), 那时复原虚影就没了(门禁实测)。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _src != null and is_instance_valid(_src):
		_src.modulate.a = _src_a
