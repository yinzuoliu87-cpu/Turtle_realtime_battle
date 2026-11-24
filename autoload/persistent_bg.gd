extends CanvasLayer
## PersistentBg — 常驻背景, 始终渲染在所有场景之后 (1:1 PoC html 背景常驻)。
## 作用: 场景切换的空隙(旧场景已 free、新场景首帧未渲)期间, 露出的是这层深色底而非黑屏,
##   ★2026-11-24 绿色瓷砖底去掉(用户「绿底…就都不要了」): 改成各页专属底图垫的同一个深色 SceneBackdrop.BASE。
##   消除"页面跳转黑屏闪一下"。各场景自带的不透明背景平时盖住本层, 仅切换空隙可见。
## autoload (root 子节点) 跨场景常驻, 不随 change_scene 销毁。

const LiteTexLoader := preload("res://scripts/systems/sim/lite_tex_loader.gd")
## 底色 = 各页专属底图垫的同一个深色(autoload 比全局类表先就位 ⇒ preload, 不写类名)
const _Backdrop := preload("res://scripts/util/scene_backdrop.gd")

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
	var base := ColorRect.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = _Backdrop.BASE
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(base)
	add_child(holder)
