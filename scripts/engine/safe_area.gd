## 屏幕安全区 — 刘海/灵动岛/圆角/手势条 的内缩量, 换算到【逻辑(视口)像素】.
##
## 为什么需要换算: DisplayServer.get_display_safe_area() 返回的是**物理像素**的可用矩形,
## 而所有 UI 摆位用的是 stretch(canvas_items) 之后的逻辑坐标. 两者比例 = 视口尺寸 / 窗口物理尺寸.
## 直接拿物理 inset 去摆逻辑坐标, 在高 DPI 手机上会内缩过头(iPhone ×3 → 缩 3 倍).
##
## project.godot: stretch mode=canvas_items, aspect=expand → 高锁 720, 宽随屏比膨胀,
## 所以逻辑可视区和真实可视区是同一块, 只需再减掉安全区内缩即可.
##
## 桌面端恒返回 0 —— get_display_safe_area 在桌面就是整个窗口, 但显式短路更省事也更明确.
class_name SafeArea
extends RefCounted

## 各边内缩 (left, top, right, bottom), 单位 = 逻辑像素.
static func insets(vp_size: Vector2) -> Vector4:
	if not is_mobile():
		return Vector4.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	if win.x < 0.5 or win.y < 0.5 or vp_size.x < 0.5 or vp_size.y < 0.5:
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x < 0.5 or safe.size.y < 0.5:
		return Vector4.ZERO                      # 平台没报安全区 → 当作无内缩, 别瞎猜
	var k := vp_size / win                       # 物理 → 逻辑
	return Vector4(
		maxf(0.0, float(safe.position.x) * k.x),
		maxf(0.0, float(safe.position.y) * k.y),
		maxf(0.0, (win.x - float(safe.end.x)) * k.x),
		maxf(0.0, (win.y - float(safe.end.y)) * k.y))

## 贴边控件的最小边距 = 基础留白 + 该边安全区内缩.
static func margins(vp_size: Vector2, base: float = 6.0) -> Vector4:
	var i := insets(vp_size)
	return Vector4(i.x + base, i.y + base, i.z + base, i.w + base)

static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]
