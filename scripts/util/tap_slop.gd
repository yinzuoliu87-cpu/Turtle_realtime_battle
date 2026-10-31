extends RefCounted
## tap_slop.gd — 滚动列表里「点一下」和「滑一下」的分界(2026-10-31)。
##
## 用在自己接 `gui_input` 判点的控件上(列表行 / 格子 / 详情里的热区), 按钮(BaseButton)不用它:
##   按钮设 PASS 就够 —— ScrollContainer 一开始拖动就往子孙广播 NOTIFICATION_SCROLL_BEGIN, 引擎自己把按下作废。
##
## ★为什么要量**画布全局坐标**而不是控件自己的局部坐标:
##   手指拖着列表走时, 条目跟着手指一起动 ⇒ 松手那一刻手指相对条目自己几乎没挪。
##   ScrollContainer 过死区(项目设 18px)那一下把累计量重置成「最后一步」, 滚动只落后手指「过死区之前那一点」:
##   匀速拖(每步 16px)落后 16px, 快甩(先挪 4px 再一大步)只落后 4px —— 拿局部坐标判「位移 < 14 / < 16 = 点」,
##   快甩时必然误判成点(实测: 图鉴列表一甩就换了详情, 背包一甩就选中了糖果罐)。
## ★还要「中途挪远过就不算」: 手指往下拖 30 再拖回来, 起止点离得很近, 但列表已经滚过一趟。
##
## 用法: 每个热区(或整屏共用 —— 同一时刻只有一根手指在按)一个对象:
##   var tap := TapSlop.new()
##   ctrl.gui_input.connect(func(ev): if tap.is_tap(ctrl, ev): do_it())
## ★只认鼠标事件: 手机上触摸由 emulate_mouse_from_touch(项目默认开)翻成鼠标, 同时认触摸会一次点算两次。

const SLOP := 14.0

var slop: float = SLOP
var _down := false       # 左键按着(按下发生在某个接了它的控件上)
var _moved := false      # 按下之后手指挪出过 slop
var _at := Vector2.ZERO  # 按下那一点(画布全局坐标)


func _init(s: float = SLOP) -> void:
	slop = s


## 喂一个 gui_input 事件; 返回 true = 这一下是「点」(左键松手, 且从按下起手指一直没挪出 slop)。
func is_tap(ctrl: Control, ev: InputEvent) -> bool:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var g: Vector2 = ctrl.get_global_transform_with_canvas() * (ev as InputEventMouseButton).position
		if (ev as InputEventMouseButton).pressed:
			_at = g
			_down = true
			_moved = false
			return false
		var ok: bool = _down and not _moved and g.distance_to(_at) <= slop
		_down = false
		return ok
	if ev is InputEventMouseMotion and _down:
		var g2: Vector2 = ctrl.get_global_transform_with_canvas() * (ev as InputEventMouseMotion).position
		if g2.distance_to(_at) > slop:
			_moved = true
	return false
