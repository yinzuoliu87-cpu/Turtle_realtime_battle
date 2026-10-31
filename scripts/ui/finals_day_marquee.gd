extends Control
## 周日开播期间顶部跑马灯(2026-10-31 方案书 20261031c 块 M ⑥ · 8-1 梦幻西游武神坛全服广播):
##   「冠军杯赛 半决赛 第 1 场 20:12 开播」「X 晋级冠军杯赛决赛」「X 夺得 C 组冠军，晋级冠军杯赛」。
## 一句一句排队: 条滑出 → 字从右往左走一遍 → 条收起 → 下一句。不挡点击(整条 IGNORE)。
## ★句子由 finals_day_model.facts 出(只收服务端下发的真东西); 这里只管放。

const N_TEXT := "FdMarqueeText"
const W := 560.0                 # ★与全局小条 / 开播横幅同一条道: 主菜单顶上玩家卡与货币条之间只有 ~575, 宽了会压到货币条
const H := 40.0
const SPEED := 130.0           # 像素 / 秒
const GAP := 0.5               # 两句之间收起的停顿

var queue: Array = []
var current := ""
## 门禁读: 播过的句子
var played: Array = []
var _clip: Control
var _lb: Label
var _busy := false


func _init() -> void:
	name = "FinalsDayMarquee"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(W, H)
	custom_minimum_size = size
	visible = false
	var bg := ColorRect.new()
	bg.color = Color("#120c06")
	bg.size = size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	for y in [0.0, H - 2.0]:
		var ln := ColorRect.new()
		ln.color = Color("#d9a441")
		ln.position = Vector2(0, y)
		ln.size = Vector2(W, 2)
		ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ln)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.position = Vector2(8, 2)
	_clip.size = Vector2(W - 16, H - 4)
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	_lb = Label.new()
	_lb.name = N_TEXT
	_lb.add_theme_font_size_override("font_size", 19)
	_lb.add_theme_color_override("font_color", Color("#ffe9b0"))
	_lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_lb.add_theme_constant_override("outline_size", 4)
	_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lb.size = Vector2(10, H - 4)
	_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_lb)


func push(msg: String) -> void:
	if msg == "" or msg == current or queue.has(msg):
		return
	queue.append(msg)
	if queue.size() > 6:
		queue.pop_front()              # 一下子来太多: 只留最新的几句
	if not _busy:
		_next()


func _next() -> void:
	if queue.is_empty():
		_busy = false
		current = ""
		var tw0 := create_tween()
		tw0.tween_property(self, "scale:y", 0.0, 0.18)
		tw0.tween_callback(func() -> void: visible = false)
		return
	_busy = true
	current = str(queue.pop_front())
	played.append(current)
	_lb.text = current
	_lb.reset_size()
	var tw_w: float = _lb.get_combined_minimum_size().x
	_lb.size = Vector2(tw_w, H - 4)
	_lb.position = Vector2(_clip.size.x, 0)
	visible = true
	pivot_offset = Vector2(W / 2.0, 0)
	scale = Vector2(1, 0)
	var dur: float = (_clip.size.x + tw_w) / SPEED
	var tw := create_tween()
	tw.tween_property(self, "scale:y", 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_lb, "position:x", -tw_w, dur)
	tw.tween_interval(GAP)
	tw.tween_callback(_next)
