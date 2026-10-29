class_name EnterBar
extends Control
## 闯关赛「进入对局」进度条(2026-10-29 · 方案书 docs/plans/20261029c-闯关赛排队时可回主页.md §4.7)。
## 用户 10-29「匹配成功，那里有个即将进入对局下面的进度条…现在目前是没有含义的吗？你给它有含义啊…
##   后面又写等待服务器开始对局，那那段的时间为什么不能够融入这个进度条里面呢？」
## ⇒ 从「匹配成功」到对局第一帧只有一条进度条: 遮罩横带里那条、VS 卡下那条都是本控件, 读的是会话的同一个数
##   (`referee_run.gd` `enter_progress()`), 换屏时接着走、不从头来。
## ★只负责画: 每帧调 `source`(回 0..1; < 0 = 这一刻不该显示 ⇒ 藏起来), 不自己算进度。
## ★样子 = 原来遮罩里那条(深底 + 金色填充, 3 像素一格的像素台阶), 全部代码画色块, 不用贴图。

const BAR_W := 420.0
const BAR_H := 12.0
const PAD := 3.0                 ## 底框比填充每边宽出的像素
const STEP := 3.0                ## 填充按 3 像素一格走(像素台阶, 不是平滑拉长)
const COL_BG := Color("#070b16")
const COL_FILL := Color("#ffd34a")

var source: Callable = Callable()
var value := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(BAR_W + PAD * 2.0, BAR_H + PAD * 2.0)


## 接上数据来源并当场读一次(刚建出来那一帧就是对的, 不先画一帧空条再跳上去)。
func bind(src: Callable) -> void:
	source = src
	_pull()


func _process(_delta: float) -> void:
	_pull()


func _pull() -> void:
	if not source.is_valid():
		return
	var v := float(source.call())
	visible = v >= 0.0
	set_value(maxf(v, 0.0))


func set_value(v: float) -> void:
	var px0 := fill_px()
	value = clampf(v, 0.0, 1.0)
	if fill_px() != px0:
		queue_redraw()


## 填充的像素宽(按格取整)。门禁读它: 量的是画出来的那一截, 不是数。
func fill_px() -> float:
	return floorf(BAR_W * value / STEP) * STEP


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	var f := fill_px()
	if f > 0.0:
		draw_rect(Rect2(PAD, PAD, f, BAR_H), COL_FILL)
