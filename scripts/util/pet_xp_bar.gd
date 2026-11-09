class_name PetXpBar
extends Control
## 龟经验条(2026-11-09 · 方案书 docs/plans/20261107b-龟等级与经验.md §4.5): 选龟卡片 / 图鉴 Lv 签 / 结算页三处同一根。
## 平涂: 1px 深色描边 + 深底 + 金色填充(docs/plans/20261027-UI美术规矩.md: 不用圆角 / 渐变 / 阴影)。只画, 不吃点击。
## 填充宽度取整到像素(像素画: 半像素的边会糊)。

const COL_EDGE := Color("#0d0805")
const COL_TRACK := Color("#2a2018")
const COL_FILL := Color("#ffd86b")

var fill_color := COL_FILL
## 空的那一截的底色: 默认深棕(压在立绘 / 签牌上); 黑底上(结算屏左栏)要换浅一点的, 否则空条看不见
var track_color := COL_TRACK

var frac := 0.0:
	set(v):
		frac = clampf(v, 0.0, 1.0)
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 填充那一截的像素宽(门禁量的就是它, 不读 frac)。
func fill_px() -> float:
	var inner_w := maxf(0.0, size.x - 2.0)
	return floorf(inner_w * frac)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, COL_EDGE)
	var inner := r.grow(-1.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	draw_rect(inner, track_color)
	var w := fill_px()
	if w > 0.0:
		draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), fill_color)
