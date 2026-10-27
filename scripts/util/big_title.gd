## 结算屏大字美术字(2026-10-27 用户选「方案 A」· 门禁 verify_big_title)。
##   图由 tools/build_big_titles.py 生成(大格子像素字 + 描边 + 渐变 + 落影, 存 1 倍源图), 这里按整数倍最近邻贴上去。
##   由来与商业游戏对照见那份脚本的头注释: 小格标题字放大 7 倍「利」散成方块、「负」认不出。
## ★标签本身保留(文字照旧在 Label.text 里 —— 测试、回放、读屏都读它), 只把它自己的字形调成透明
##   (self_modulate 不传给子节点), 图挂成它的子节点、居中。没有对应图的文字照旧显示标签自己的字。
class_name BigTitle
extends RefCounted

const DIR := "res://assets/sprites/ui/bigtitle/"
## 源像素 → 屏幕像素的整数倍
const SCALE := 3
const ART_NODE := "BigTitleArt"

## 大小两档的「文字 → 文件名」。与 tools/build_big_titles.py 的 WORDS 是同一张表(门禁对账)。
const BIG := {"胜利": "big_win", "失败": "big_lose", "已晋级！": "big_promoted", "结果已封存": "big_sealed"}
const RAIL := {"胜利": "rail_win", "失败": "rail_lose", "已封存": "rail_sealed"}
const LANE := {"胜": "lane_win", "负": "lane_lose", "平": "lane_draw"}


## 给标签贴上 table 里对应的图。true = 贴上了; false = 这句话没有图(标签照旧显示自己的字)。
static func apply(l: Label, table: Dictionary) -> bool:
	if not table.has(l.text):
		return false
	var tex := load(DIR + str(table[l.text]) + ".png") as Texture2D
	if tex == null:
		return false
	var art := TextureRect.new()
	art.name = ART_NODE
	art.texture = tex
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sz := tex.get_size() * SCALE
	art.size = sz
	l.add_child(art)
	l.self_modulate.a = 0.0
	## 居中按标签真实大小摆(取整到整像素, 像素图不落半格); 标签每次变大小都重摆。
	##   ★不用 PRESET_CENTER + 负偏移: 实测挂上去之后偏了半张图(门禁 verify_big_title ④ 量出来的)。
	var center := func() -> void:
		if is_instance_valid(art) and is_instance_valid(l):
			art.position = ((l.size - sz) / 2.0).floor()
	l.resized.connect(center)
	center.call()
	## ★不改标签的最小尺寸: 结算屏大字是先 apply 再 `set_anchors_and_offsets_preset(FULL_RECT)` 塞进槽,
	##   那时槽还没尺寸, 撑大最小尺寸会把标签算成「左边沿在槽中线」(实测图偏到右半边)。
	##   三处标签的字体行高 / 槽宽本来就 ≥ 图(门禁 ④ 量图不压下一句)。
	return true
