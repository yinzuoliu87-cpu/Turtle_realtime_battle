class_name SpellDisc
extends Control

## 法术圆盘(用户2026-07-23): 右下角技能钮。
## ★★U2(母方案书 20260916 §4.4, 2026-10-03 落地): 训龟大师**不再由人操控**、每周期自动放技能
##   ⇒ 圆盘改成**只读**: 只显示已装配技能的图标 + 冷却扇形/读秒 + 魔法石层数角标。
##   原来的「按住拖动瞄准 / 轻点自动瞄 / PC 按 Q」三条施法入口连同 battle_aim.gd 一起删了
##   (它们是局内实时输入, 让实战不可复现: 20261003-跨设备回放 §2.7)。
##   mouse_filter = IGNORE: 点它什么都不发生, 也不挡住身后的镜头平移。
## ★拆成独立 Control(自绘), 主场景注入图标, 每帧喂 (cd比例, 剩余秒)。照 CLAUDE.md §5。

const R := 46.0

var _icon: Texture2D = null
var _cd_frac: float = 0.0     # 0=就绪, 1=满冷却
var _cd_secs: float = 0.0     # 剩余秒(显示用)

## 叠层角标(用户 2026-07-30:「魔法石，我希望图标上有层数显示」)。
## 0 = 不画 —— 开局没层数时不给圆盘加噪点。
## ★放【右上角】: 圆盘下方 y≈R*0.86 已被键位提示"Q"占着, 中心被冷却读秒占着。
##   右上是 LoL/Dota 叠层数的常规位置, 也不会被冷却扇形(从顶部顺时针扫)第一时间盖住。
var _stacks: int = 0
var _stack_font: Font = null

## 角标环色随阈值档位(0/1/2/3) —— 与大师【本体】那圈符文环/晶石的分档配色对齐,
## 让"到第几档了"在 UI 上也看得出, 不用去数场上的晶石。tier3 转金 = 到顶。
var _tier: int = 0
const TIER_RING := [
	Color("#c86bff"), Color("#c86bff"), Color("#dd9bff"), Color("#ffd35c")]

func setup(icon: Texture2D) -> void:
	_icon = icon
	custom_minimum_size = Vector2(R * 2.0, R * 2.0)
	size = Vector2(R * 2.0, R * 2.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 只读: 不接任何点击/拖动

## 每帧喂当前叠层。只在变化时重绘 —— set_cd 同理(圆盘是自绘 Control, 每帧 queue_redraw 是浪费)。
func set_stacks(n: int) -> void:
	n = maxi(0, n)
	if n != _stacks:
		_stacks = n
		queue_redraw()


## 每帧喂当前档位(0~3)。同 set_stacks: 只在变化时重绘。
func set_tier(t: int) -> void:
	t = clampi(t, 0, 3)
	if t != _tier:
		_tier = t
		queue_redraw()


func set_cd(frac: float, secs: float) -> void:
	frac = clampf(frac, 0.0, 1.0)
	if absf(frac - _cd_frac) > 0.004 or absf(secs - _cd_secs) > 0.08:
		_cd_frac = frac
		_cd_secs = secs
		queue_redraw()

func _draw() -> void:
	var c := Vector2(R, R)
	var ready := _cd_frac <= 0.004
	draw_circle(c, R, Color(0.10, 0.12, 0.18, 0.86))                       # 底盘
	var border := Color(0.45, 0.85, 1.0, 0.95) if ready else Color(0.4, 0.46, 0.6, 0.9)
	draw_arc(c, R - 2.0, 0.0, TAU, 52, border, 3.0)
	if _icon != null:                                                     # 技能图标
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
	# ★不画键位提示(用户 2026-07-30:「不要显示Q」; U2 之后本来也没有键可按)。
	if _stacks > 0:                                                       # 叠层角标(魔法石攻速层数)
		if _stack_font == null:
			_stack_font = load("res://assets/fonts/m6x11.ttf")             # 全局数字字体(与飘字/血条一致·像素风)
		var bc := c + Vector2(R * 0.70, -R * 0.70)
		var br := 15.0
		draw_circle(bc, br, Color(0.08, 0.05, 0.14, 0.94))                # 深底(盖住图标, 数字才读得清)
		# 环色随档位: 紫 → 亮紫 → 金(到顶)。与大师本体的分档配色对齐。
		draw_arc(bc, br - 1.0, 0.0, TAU, 24, TIER_RING[clampi(_tier, 0, 3)], 2.0)
		var txt := str(_stacks)
		var fs := 22 if _stacks < 10 else (18 if _stacks < 100 else 14)   # 三位数也塞得下(每层+5%, 上不封顶)
		var f2: Font = _stack_font if _stack_font != null else ThemeDB.fallback_font
		var tw2: float = f2.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f2, bc + Vector2(-tw2 * 0.5, fs * 0.36), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.98))
