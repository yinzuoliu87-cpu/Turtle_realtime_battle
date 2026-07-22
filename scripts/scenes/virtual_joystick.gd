extends Control

## virtual_joystick.gd — 移动端虚拟摇杆 (用户 2026-07-22:「移动要遥感」)
##
## 只在移动端出现(PC 走键盘, 见 RealtimeBattle3DScene._trainer_input_vec)。
## 输出 `value`: 归一化方向 × 拉杆比例(0..1), 静止时为 Vector2.ZERO。
##
## ★手势隔离: 本控件 mouse_filter = STOP, 落在它上面的按下/拖动【不会】继续冒泡到
##   _unhandled_input —— 所以摇杆区域内的拖动不会同时把镜头也拖走。
##   (镜头平移是 2026-07-22 刚修好的, 新控件绝不能再抢它。)
##
## ★同时认 ScreenTouch/Drag 与 MouseButton/Motion: emulate_mouse_from_touch 默认开,
##   真机上两种事件会成对到来。这里靠 `_active_idx` 只认第一根手指, 第二根落在摇杆上会被忽略,
##   不会出现"两根手指各拉一次 = 速度翻倍"(平移那次踩过这个坑)。

const RADIUS := 78.0          # 摇杆底盘半径
const KNOB_RADIUS := 32.0     # 摇杆头半径
const DEADZONE := 0.12        # 死区: 拉杆比例低于这个当没动(防手指微抖导致慢慢漂)

var value: Vector2 = Vector2.ZERO      # 归一化方向 × 拉杆比例(0..1)
var _active_idx: int = -1              # 当前占用的手指 index; -1=没人按; -2=鼠标
var _knob: Vector2 = Vector2.ZERO      # 摇杆头相对中心的偏移(像素)


func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP   # ★吃掉本区域的事件, 不让它冒泡去拖镜头
	set_process_input(false)


func _center() -> Vector2:
	return size * 0.5


## 把一个本地坐标点换算成摇杆输出并记下摇杆头位置
func _set_from_local(p: Vector2) -> void:
	var off: Vector2 = p - _center()
	var r: float = off.length()
	if r > RADIUS:
		off = off.normalized() * RADIUS
		r = RADIUS
	_knob = off
	var ratio: float = r / RADIUS
	value = Vector2.ZERO if ratio < DEADZONE else off.normalized() * ratio
	queue_redraw()


func _release() -> void:
	_active_idx = -1
	_knob = Vector2.ZERO
	value = Vector2.ZERO
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _active_idx == -1:
				_active_idx = t.index
				_set_from_local(t.position)
		elif t.index == _active_idx:
			_release()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _active_idx:
			_set_from_local(d.position)
	elif event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		if m.button_index != MOUSE_BUTTON_LEFT:
			return
		# ★只有在没有真触屏占用时才认模拟鼠标, 否则同一次拖会被算两遍
		if m.pressed:
			if _active_idx == -1:
				_active_idx = -2
				_set_from_local(m.position)
		elif _active_idx == -2:
			_release()
	elif event is InputEventMouseMotion and _active_idx == -2:
		_set_from_local((event as InputEventMouseMotion).position)


func _draw() -> void:
	var c := _center()
	draw_circle(c, RADIUS, Color(0.06, 0.09, 0.14, 0.42))            # 底盘
	draw_arc(c, RADIUS, 0.0, TAU, 48, Color(1, 0.85, 0.42, 0.35), 2.0)
	draw_circle(c + _knob, KNOB_RADIUS, Color(1, 0.76, 0.24, 0.72))  # 摇杆头
	draw_arc(c + _knob, KNOB_RADIUS, 0.0, TAU, 32, Color(0.1, 0.07, 0.0, 0.55), 2.0)
