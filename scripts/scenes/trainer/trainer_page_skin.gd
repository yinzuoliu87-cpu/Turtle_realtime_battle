extends RefCounted
## 训龟大师配置页的皮(2026-10-19 重做)。只放 StyleBox / 小部件工厂, 不放布局。
##
## ★素材全部是这一页自己的(`assets/sprites/trainer_page/`), 不借别屏的框:
##   铁律「新内容一律新素材」见 `tools/asset_borrow_audit.py` 头注。
##   这些图是 16/24 原生像素 ×3 最近邻放大画出来的 ⇒ 九宫格边距按 3 的倍数取。
##
## ★全部直角、不透明 —— `verify_ui_consistency` 的「网页盒」= 四边描边 + 半透底,
##   「圆角盒」= corner_radius > 0。这一页两样都不许有。

const DIR := "res://assets/sprites/trainer_page/"

## 槽框贴图: 原生 16px, 外描边 1 + 斜面 1 + 内阴影 1 = 3 原生 = 9 设计像素。
const SLOT_MARGIN := 9
## 大面板贴图: 原生 24px, 同样 3 原生边 = 9; 九宫格切在 12 让角上铆钉不被拉伸。
const PANEL_MARGIN := 12

const GOLD := Color(1.0, 0.84, 0.42)
const TEXT := Color(0.90, 0.94, 1.0)
const TEXT_DIM := Color(0.60, 0.68, 0.78)
## 被动 / 主动两色: 与旧版说明卡里那两个色同值, 战斗 HUD 不受影响(它不读这里)。
const KIND_PASSIVE := Color(0.36, 0.78, 1.0)
const KIND_ACTIVE := Color(1.0, 0.70, 0.50)


static func tex(name: String) -> Texture2D:
	var p := DIR + name
	return load(p) if ResourceLoader.exists(p) else null


## 九宫格框。贴图缺失时退回一块**不透明、无描边、直角**的底(仍然不是网页盒)。
static func box(name: String, margin: int, pad: Vector4 = Vector4(-1, -1, -1, -1)) -> StyleBox:
	var t := tex(name)
	var sb: StyleBox = null
	if t != null:
		var st := StyleBoxTexture.new()
		st.texture = t
		st.texture_margin_left = margin
		st.texture_margin_top = margin
		st.texture_margin_right = margin
		st.texture_margin_bottom = margin
		sb = st
	else:
		var sf := StyleBoxFlat.new()
		sf.bg_color = Color(0.07, 0.10, 0.15, 1.0)
		sb = sf
	if pad.x >= 0.0:
		sb.content_margin_left = pad.x
		sb.content_margin_top = pad.y
		sb.content_margin_right = pad.z
		sb.content_margin_bottom = pad.w
	return sb


## 可选槽(技能 / 形象)四态: 常态钢灰、悬停亮钢、选中金。
static func skin_slot(b: Button) -> void:
	b.add_theme_stylebox_override("normal", box("slot-normal.png", SLOT_MARGIN))
	b.add_theme_stylebox_override("hover", box("slot-hover.png", SLOT_MARGIN))
	b.add_theme_stylebox_override("pressed", box("slot-selected.png", SLOT_MARGIN))
	b.add_theme_stylebox_override("hover_pressed", box("slot-selected.png", SLOT_MARGIN))
	b.add_theme_stylebox_override("disabled", box("slot-normal.png", SLOT_MARGIN))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE
	## 槽里只放图, 不放字: 字全在槽外 ⇒ 永远不会压在金属边带上。
	b.text = ""


## 纯色直角块(无描边、不透明) —— 小签底、分隔线都用它。
static func flat(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	return sb


## 被动 / 主动小签。
static func kind_tag(kind: String, font_px: int = 16) -> Label:
	var lb := Label.new()
	lb.text = kind
	var passive := kind == "被动"
	var fg: Color = KIND_PASSIVE if passive else KIND_ACTIVE
	var bg: Color = Color(0.09, 0.22, 0.33, 1.0) if passive else Color(0.33, 0.17, 0.08, 1.0)
	var sb := flat(bg)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	lb.add_theme_stylebox_override("normal", sb)
	lb.add_theme_color_override("font_color", fg)
	lb.add_theme_font_size_override("font_size", font_px)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lb


static func label(t: String, px: int, col: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var lb := Label.new()
	lb.text = t
	lb.add_theme_font_size_override("font_size", px)
	lb.add_theme_color_override("font_color", col)
	lb.horizontal_alignment = align
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lb


## 像素图(最近邻, 忽略原尺寸按给定框缩放, 居中保比例)。
static func pixel_rect(t: Texture2D, sz: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = sz
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
