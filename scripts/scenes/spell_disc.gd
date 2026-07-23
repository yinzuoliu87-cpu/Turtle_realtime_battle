class_name SpellDisc
extends Control

## 法术圆盘 (点3·用户2026-07-23): 右下角一个技能钮, 显示钩锁图标 + 冷却扇形扫暗 + 剩余秒 + 键位提示。
## PC: 主要靠按 Q(朝鼠标), 圆盘只作【冷却指示 + Q 提示】; 移动端: 点圆盘施法(自动瞄准最近敌)。
## ★拆成独立 Control(自绘冷却扇形), 主场景只注入图标/回调 + 每帧喂 (cd比例, 剩余秒), 照 CLAUDE.md §5 拆分风格。

const R := 46.0

var _icon: Texture2D = null
var _cd_frac: float = 0.0     # 0=就绪, 1=满冷却
var _cd_secs: float = 0.0     # 剩余秒(显示用)
var _key_hint: String = "Q"
var _on_tap: Callable = Callable()

func setup(icon: Texture2D, hint: String, tap: Callable) -> void:
	_icon = icon
	_key_hint = hint
	_on_tap = tap
	custom_minimum_size = Vector2(R * 2.0, R * 2.0)
	size = Vector2(R * 2.0, R * 2.0)
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_cd(frac: float, secs: float) -> void:
	frac = clampf(frac, 0.0, 1.0)
	if absf(frac - _cd_frac) > 0.004 or absf(secs - _cd_secs) > 0.08:
		_cd_frac = frac
		_cd_secs = secs
		queue_redraw()

func _gui_input(e: InputEvent) -> void:
	var tapped: bool = (e is InputEventScreenTouch and e.pressed) \
		or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
	if tapped and _cd_frac <= 0.004 and _on_tap.is_valid():
		_on_tap.call()
		accept_event()

func _draw() -> void:
	var c := Vector2(R, R)
	var ready := _cd_frac <= 0.004
	draw_circle(c, R, Color(0.10, 0.12, 0.18, 0.86))                       # 底盘
	draw_arc(c, R - 2.0, 0.0, TAU, 52,
		Color(0.45, 0.85, 1.0, 0.95) if ready else Color(0.4, 0.46, 0.6, 0.9), 3.0)   # 边框(就绪=青亮)
	if _icon != null:                                                     # 钩锁图标
		var isz := Vector2(R * 1.15, R * 1.15)
		draw_texture_rect(_icon, Rect2(c - isz * 0.5, isz), false,
			Color(1, 1, 1, 1.0 if ready else 0.5))
	if not ready:                                                         # 冷却扇形(顶部起顺时针扫暗)
		var pts := PackedVector2Array([c])
		var a0 := -PI * 0.5
		var a1 := a0 + TAU * _cd_frac
		var steps := maxi(2, int(52.0 * _cd_frac))
		for i in range(steps + 1):
			var a := a0 + (a1 - a0) * float(i) / float(steps)
			pts.append(c + Vector2(cos(a), sin(a)) * R)
		draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
		var f := ThemeDB.fallback_font
		draw_string(f, c + Vector2(0.0, 9.0), "%d" % int(ceil(_cd_secs)),
			HORIZONTAL_ALIGNMENT_CENTER, R * 1.6, 28, Color(1, 1, 1, 0.96))
	var hf := ThemeDB.fallback_font                                        # 键位提示(PC 端有意义)
	draw_string(hf, c + Vector2(R * 0.34, R * 0.86), _key_hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.75, 0.82, 1.0, 0.92))
