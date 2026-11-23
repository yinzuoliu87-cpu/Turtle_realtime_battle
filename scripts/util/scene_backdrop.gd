class_name SceneBackdrop
extends RefCounted
## 二级页面的专属底图：深色底 + 一张 520×240 像素画「盖满」铺屏（最近邻）+ 压暗 + 上下暗角。
##
## 520×240 = 手机 1560×720 的整 1/3；iPad 960×720 按盖满裁中间，也是整 3 倍。
## 战绩页（RecordScene._bg）最先这么做；排行榜 / 图鉴 11-22 跟进，换掉主菜单那张绿色平铺底
## （用户 11-22「那个绿色的画布，应该是可以彻底的不要了吧」）。
## 各张底图的出处写在用它的那个场景脚本里（const BG_TEX 旁）。

const BASE := Color("#0b1622")
## 青石面板(11-22, 配专属底图): 金属九宫格框染青石; 框原图的芯子是藏青, 不画, 改铺一块深青底, 底图隐约透一点。
##   排行榜(LeaderboardScene.PANEL_TINT / LbWell)最先这么调, 设置 / 好友跟着用这两个函数。
const STONE_TINT := Color(0.60, 0.80, 0.82, 1.0)
const STONE_WELL := Color(0.045, 0.085, 0.10, 0.94)
const WELL_INSET := 20.0   # = UISkin.nine("panel-frame.png", 20, ...) 的九宫格边距: 边带照画, 芯子从这里起


## 在 parent 最底下铺一层底图。parent 必须是铺满视口的 Control（场景根或全锚背景节点）。
static func add(parent: Control, tex_path: String, dim: Color, art_name: String) -> void:
	var base := ColorRect.new()
	base.name = art_name + "Base"
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = BASE
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(base)
	if ResourceLoader.exists(tex_path):
		var art := TextureRect.new()
		art.name = art_name
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.texture = load(tex_path)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.modulate = dim
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(art)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.18, 0.6, 1.0])
	grad.colors = PackedColorArray([Color(0.03, 0.06, 0.1, 0.75), Color(0.03, 0.06, 0.1, 0.2),
		Color(0.03, 0.06, 0.1, 0.25), Color(0.02, 0.04, 0.07, 0.8)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 128
	var ov := TextureRect.new()
	ov.name = art_name + "Vignette"
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.texture = gt
	ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ov.stretch_mode = TextureRect.STRETCH_SCALE
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(ov)


## 把一张 panel-frame 九宫格框改成青石框(复制一份, 不动调用方传进来的共用样式)。不是九宫格就原样返回。
static func stone_style(base: StyleBox) -> StyleBox:
	if not (base is StyleBoxTexture):
		return base
	var st := (base as StyleBoxTexture).duplicate() as StyleBoxTexture
	st.modulate_color = STONE_TINT
	st.draw_center = false
	return st


## 给青石框铺芯: 面板第一个子节点, 盖在框的芯子区, 在面板其它内容底下。
static func add_well(panel: Control) -> void:
	var well := ColorRect.new()
	well.name = "StoneWell"
	well.color = STONE_WELL
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.set_anchors_preset(Control.PRESET_FULL_RECT)
	well.offset_left = WELL_INSET
	well.offset_top = WELL_INSET
	well.offset_right = -WELL_INSET
	well.offset_bottom = -WELL_INSET
	panel.add_child(well)
	panel.move_child(well, 0)
