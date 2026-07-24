class_name SpellDisc
extends Control

## 法术圆盘 (用户2026-07-23; 2026-07-24 照 Wild Rift 加【按住拖动瞄准】): 右下角技能钮。
## PC: 按 Q 朝鼠标(圆盘作冷却指示 + 可点/拖)。
## 移动端(学 Wild Rift 锤石Q): 【按住】技能 → 出现方向轮盘(拖动改方向) + 战场技能指示器 → 【松手】释放。
##   ·拖动超过死区 → 松手朝拖动方向施法; ·几乎没拖(轻点) → 自动瞄最近敌; ·拖回钮内 → 取消。
## ★拆成独立 Control(自绘), 主场景注入图标/回调, 每帧喂 (cd比例, 剩余秒)。照 CLAUDE.md §5。

const R := 46.0
const DEADZONE := 16.0        # 拖动小于这个距离 = 当作轻点(自动瞄准), 不算方向瞄准

var _icon: Texture2D = null
var _cd_frac: float = 0.0     # 0=就绪, 1=满冷却
var _cd_secs: float = 0.0     # 剩余秒(显示用)
var _key_hint: String = "Q"
var _on_tap: Callable = Callable()    # 轻点(自动瞄准)
var _on_aim: Callable = Callable()    # 瞄准过程: call(phase:String, dir:Vector2) phase=update/cast/cancel

var _aiming: bool = false
var _aim_off: Vector2 = Vector2.ZERO  # 拖动偏移(相对圆盘中心·屏幕像素)

func setup(icon: Texture2D, hint: String, tap: Callable, aim: Callable = Callable()) -> void:
	_icon = icon
	_key_hint = hint
	_on_tap = tap
	_on_aim = aim
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
	var ready := _cd_frac <= 0.004
	# 按下: 就绪时进入瞄准态
	if (e is InputEventScreenTouch or e is InputEventMouseButton) and e.pressed:
		if ready:
			_aiming = true
			_aim_off = e.position - Vector2(R, R)
			_emit_aim("update")
			queue_redraw()
			accept_event()
		return
	# 拖动: 更新方向
	if _aiming and (e is InputEventScreenDrag or e is InputEventMouseMotion):
		_aim_off = e.position - Vector2(R, R)
		_emit_aim("update")
		queue_redraw()
		accept_event()
		return
	# 松手: 按拖动距离决定 施法/自动瞄/取消
	if _aiming and (e is InputEventScreenTouch or e is InputEventMouseButton) and not e.pressed:
		_aiming = false
		var d := _aim_off.length()
		if d < DEADZONE:                       # 轻点 → 自动瞄准最近敌
			_emit_aim("cancel")
			if _on_tap.is_valid(): _on_tap.call()
		else:                                  # 拖动过 → 朝拖动方向施法
			if _on_aim.is_valid(): _on_aim.call("cast", _aim_off.normalized())
		_aim_off = Vector2.ZERO
		queue_redraw()
		accept_event()

func _emit_aim(phase: String) -> void:
	if _on_aim.is_valid():
		var dir := _aim_off.normalized() if _aim_off.length() > 0.001 else Vector2.ZERO
		_on_aim.call(phase, dir)

func _draw() -> void:
	var c := Vector2(R, R)
	var ready := _cd_frac <= 0.004
	draw_circle(c, R, Color(0.10, 0.12, 0.18, 0.86))                       # 底盘
	var border := Color(0.45, 0.85, 1.0, 0.95) if ready else Color(0.4, 0.46, 0.6, 0.9)
	if _aiming:
		border = Color(1.0, 0.78, 0.35, 1.0)                              # 瞄准中=橙亮
	draw_arc(c, R - 2.0, 0.0, TAU, 52, border, 3.0)
	if _icon != null:                                                     # 技能图标
		var isz := Vector2(R * 1.15, R * 1.15)
		draw_texture_rect(_icon, Rect2(c - isz * 0.5, isz), false,
			Color(1, 1, 1, 1.0 if ready else 0.5))
	if _aiming:                                                           # 方向轮盘(拖动的把手 + 指向线)
		var knob := c + _aim_off.limit_length(R * 1.4)
		draw_line(c, knob, Color(1.0, 0.85, 0.4, 0.7), 3.0)
		draw_circle(knob, 12.0, Color(1.0, 0.82, 0.4, 0.9))
		draw_arc(knob, 12.0, 0.0, TAU, 20, Color(1, 1, 1, 0.9), 2.0)
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
