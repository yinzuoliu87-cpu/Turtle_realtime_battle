## 设置页「测试时间」弹层 —— 开发包时间穿越的手机/桌面入口(2026-10-04)
##
## 用户 2026-10-04:「由于现在我们规定好了每周的哪些天是哪些比赛, 那测试的话我们只能等到
##   对应日期, 还是我们有什么更好的办法」。方案书 docs/plans/20261004-时间穿越测试.md。
##
## ★为什么要有界面而不是只有环境变量: 测试者拿的是 iPhone 包, 手机上**没有环境变量**。
## ★逻辑一行都不在这里: 穿越 / 恢复 / 文案全走 `phase2_config` 的
##   `travel_to_weekday()` / `travel_reset()` / `travel_label()`; 本类只负责摆按钮。
## ★入口按钮由 `SettingsScene` 按 `_P2C.time_travel_allowed()` 决定建不建 ⇒ 正式包里这一屏不存在;
##   就算有人绕进来, `travel_to()` 自己也会再判一次、什么都不做。
##
## 拆法照 `scripts/scenes/battle/dmg_stats_panel.gd`: `RefCounted` + 构造注入宿主。
extends RefCounted

const _P2C := preload("res://scripts/gamedata/phase2_config.gd")

## 弹层根节点名 —— 门禁 `verify_time_travel` 按名字找。
const LAYER_NAME := "TimeTravelLayer"
const _BW := 760.0
const _BH := 330.0
const _DESIGN := Vector2(1280, 720)

var _host: Control = null
var _layer: Control = null
var _status: Label = null
var _hm: Label = null
var _day_btns: Array = []
## 选中的星期几(ISO 1~7)与 UTC 时刻。
var wd: int = 6
var hour: int = 15
var minute: int = 0


func _init(host: Control) -> void:
	_host = host


func is_open() -> bool:
	return is_instance_valid(_layer)


func open() -> void:
	if is_open():
		return
	## 初值: 已穿越 ⇒ 从当前假时刻起; 没穿越 ⇒ 周六 15:00(最常被测的那一格)。
	if _P2C.travel_active():
		var n: int = _P2C.now_utc()
		var d: Dictionary = Time.get_datetime_dict_from_unix_time(n)
		wd = _P2C.iso_weekday_utc(n)
		hour = int(d.get("hour", 0))
		var mi: int = int(d.get("minute", 0))
		minute = mi - mi % 5
	_layer = Control.new()
	_layer.name = LAYER_NAME
	_layer.position = Vector2.ZERO
	_layer.size = _DESIGN
	_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.position = Vector2.ZERO
	dim.size = _DESIGN
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(dim)

	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ffb347")
	sb.set_border_width_all(3); sb.set_corner_radius_all(0)
	var btex := UISkin.nine("panel-frame.png", 20, sb)
	box.add_theme_stylebox_override("panel", btex)
	box.size = Vector2(_BW, _BH)
	box.position = (_DESIGN - box.size) / 2.0
	_layer.add_child(box)

	_label(box, "测试时间(只在开发包里有)", 22, Color("#ffe9a8"), 18.0)
	_label(box, "只改这台机器的时钟, 从选的那一刻起照常往前走; 服务端照真实时间", 14, Color("#c6d2e0"), 52.0)

	## 第一行: 周一 ~ 周日
	_day_btns.clear()
	var dx0: float = (_BW - 7.0 * 96.0 + 8.0) / 2.0
	for i in range(7):
		var b := _btn(box, "周" + str(_P2C.WEEKDAY_CN[i]), Vector2(dx0 + i * 96.0, 88.0), Vector2(88, 44),
			pick_day.bind(i + 1))
		_day_btns.append(b)

	## 第二行: 时 / 分 (UTC)
	_btn(box, "-1 时", Vector2(90, 150), Vector2(110, 44), nudge.bind(-60))
	_btn(box, "-5 分", Vector2(210, 150), Vector2(110, 44), nudge.bind(-5))
	_hm = _label(box, "", 22, Color("#ffe9a8"), 156.0)
	_btn(box, "+5 分", Vector2(_BW - 320, 150), Vector2(110, 44), nudge.bind(5))
	_btn(box, "+1 时", Vector2(_BW - 200, 150), Vector2(110, 44), nudge.bind(60))

	_status = _label(box, "", 16, Color("#ffb347"), 208.0)

	## 第三行: 穿越 / 恢复 / 关闭
	_btn(box, "穿越到这一刻", Vector2(70, 254), Vector2(200, 50), apply)
	_btn(box, "恢复真实时间", Vector2(280, 254), Vector2(200, 50), reset)
	_btn(box, "关闭", Vector2(490, 254), Vector2(200, 50), close)

	_host.add_child(_layer)
	_refresh()


func close() -> void:
	if is_open():
		_layer.queue_free()
	_layer = null


func pick_day(d: int) -> void:
	wd = clampi(d, 1, 7)
	_refresh()


## 按分钟挪, 跨 0 点在一天之内绕回(星期几由上面那排按钮单独选)。
func nudge(mins: int) -> void:
	var t: int = posmod(hour * 60 + minute + mins, 24 * 60)
	minute = t % 60
	hour = (t - minute) / 60
	_refresh()


func apply() -> void:
	_P2C.travel_to_weekday(wd, hour, minute)
	_refresh()


func reset() -> void:
	_P2C.travel_reset()
	_refresh()


func _refresh() -> void:
	if not is_open():
		return
	for i in range(_day_btns.size()):
		UISkin.button(_day_btns[i] as Button, Color("#ffd93d") if i + 1 == wd else Color.WHITE)
	_hm.text = "周%s %02d:%02d UTC" % [_P2C.WEEKDAY_CN[wd - 1], hour, minute]
	_status.text = ("现在: " + _P2C.travel_label(_P2C.now_utc())) if _P2C.travel_active() \
		else "现在: 真实时间"


func _label(parent: Control, t: String, fs: int, col: Color, y: float) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color("#0b1220"))
	l.add_theme_constant_override("outline_size", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, y)
	l.size = Vector2(_BW, float(fs) + 12.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _btn(parent: Control, t: String, pos: Vector2, sz: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", 16)
	b.position = pos
	b.size = sz
	b.custom_minimum_size = sz
	UISkin.button(b)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
