extends CanvasLayer
## PersistentBg — 常驻背景, 始终渲染在所有场景之后 (1:1 PoC html 背景常驻)。
## 作用: 场景切换的空隙(旧场景已 free、新场景首帧未渲)期间, 露出的是这层深绿瓷砖底而非黑屏,
##   消除"页面跳转黑屏闪一下"。各场景自带的不透明背景平时盖住本层, 仅切换空隙可见。
## autoload (root 子节点) 跨场景常驻, 不随 change_scene 销毁。

const LiteTexLoader := preload("res://scripts/systems/sim/lite_tex_loader.gd")

## 无头陪练号的大贴图占位加载器(没装 = null; 判据与原因见 lite_tex_loader.gd 头注)。
var lite_tex: ResourceFormatLoader = null


## ★必须在 _init 里装, 不能等 _ready: 本节点是第一个 autoload, _init 早于其余 autoload 脚本载入与任何场景;
##   到 _ready 时别的 autoload 已经载过贴图, 那些仍是带像素的真贴图。
func _init() -> void:
	lite_tex = LiteTexLoader.install_if_bot(DisplayServer.get_name() == "headless", OS.get_environment("SIM_DRIVER"))


## 下一次换场景的空隙露黑底（默认清屏色）而不是绿瓷砖：上一屏是渐黑离场的 ⇒ 黑 → 绿闪 → 新页面那一下就没了（2026-10-29 录屏逐帧量到 3 帧）。
##   新场景挂上并画过两帧后自己恢复；最多等 2 秒（换场失败也不会一直黑着）。
func dark_once() -> void:
	visible = false
	var tree := get_tree()
	var cs0 := tree.current_scene
	var n := 0
	while n < 120 and (tree.current_scene == cs0 or tree.current_scene == null):
		await tree.process_frame
		n += 1
	await tree.process_frame
	await tree.process_frame
	visible = true


func _ready() -> void:
	layer = -100   # 顶到最底, 在所有场景/CanvasLayer 之后渲染
	if DisplayServer.get_name() == "headless":
		return
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 深绿底 #1a3a2a (PoC menu-bg-active 底色)
	var base := ColorRect.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color(0.102, 0.227, 0.165)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(base)
	# menu-bg-tile 平铺 (与菜单/选龟/图鉴边距同款, 切换空隙观感连续)
	if ResourceLoader.exists("res://assets/sprites/menu/menu-bg-tile.png"):
		var tile := TextureRect.new()
		tile.set_anchors_preset(Control.PRESET_FULL_RECT)
		var ti: Image = load("res://assets/sprites/menu/menu-bg-tile.png").get_image()
		ti.resize(512, 512, Image.INTERPOLATE_LANCZOS)
		tile.texture = ImageTexture.create_from_image(ti)
		tile.stretch_mode = TextureRect.STRETCH_TILE
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tile)
	add_child(holder)
