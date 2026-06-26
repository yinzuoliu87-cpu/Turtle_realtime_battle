extends CanvasLayer
## PersistentBg — 常驻背景, 始终渲染在所有场景之后 (1:1 PoC html 背景常驻)。
## 作用: 场景切换的空隙(旧场景已 free、新场景首帧未渲)期间, 露出的是这层深绿瓷砖底而非黑屏,
##   消除"页面跳转黑屏闪一下"。各场景自带的不透明背景平时盖住本层, 仅切换空隙可见。
## autoload (root 子节点) 跨场景常驻, 不随 change_scene 销毁。

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
