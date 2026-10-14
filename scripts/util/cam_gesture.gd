class_name CamGesture
extends RefCounted
## 战场镜头缩放的手势换算(2026-10-14 内测「mac 设备鼠标诸多问题」)。
##
## Godot 在 macOS 上: 触控板与妙控鼠标的滚动发 InputEventPanGesture(不发滚轮键),
##   触控板双指捏合发 InputEventMagnifyGesture。镜头原来只认滚轮 ⇒ Mac 上战场缩放不了。
## 放在这里而不是主文件: 纯输入换算, 不在 _sim_step 链上(见 CLAUDE.md §5)。
## 守卫: tests/verify_cam_mac_gestures.gd


## 返回缩放倍率(> 1 放大 / < 1 缩小); 不是缩放手势返回 0。
## 方向与滚轮一致: 往上滚(delta.y < 0) = 放大, 每格 ×1.10。
static func zoom_mult(event: InputEvent) -> float:
	if event is InputEventPanGesture:
		var py := clampf((event as InputEventPanGesture).delta.y, -3.0, 3.0)
		return pow(1.10, -py)
	if event is InputEventMagnifyGesture:
		return clampf((event as InputEventMagnifyGesture).factor, 0.5, 2.0)
	return 0.0
