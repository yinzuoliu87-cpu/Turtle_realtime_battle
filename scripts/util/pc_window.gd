class_name PcWindow
extends Node
## pc_window.gd —— 桌面窗口行为(11-27 从 autoload/GameState.gd 原样挪出: 跟存档状态无关, GameState 超了 3000 行上限)。
## GameState._ready 里 add_child 一个; 节点跟着 GameState 常驻。

## PC 板窗口行为(用户 2026-08-01:「pc端要随便拉，支持全屏」)。
## 全屏与 F11 早就有(见下方 _unhandled_key_input + 设置页开关), 这里只补【最小窗口尺寸】——
## 少了它, 用户可以把窗口拖到 200×100, 那时 UI 字号小到点不动, 看着像"界面坏了"。
## ★640×360 = 设计尺寸 1280×720 的正好一半, 也是像素画常用的 1/2 整数比。
## ★只在桌面平台设: 手机/网页没有可拖拽窗口, 设了是空操作但会在 headless 下多一次 DisplayServer 调用。
func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not (OS.has_feature("pc") or OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linuxbsd")):
		return
	var w := get_window()
	if w != null:
		w.min_size = Vector2i(640, 360)


## 全局全屏切换: F11 / Alt+Enter.
## (画面靠 stretch=canvas_items + aspect=expand: 比 16:9 宽→锁高 720 宽变大; 比 16:9 窄→锁宽 1280 高变大。
##  两种情况内容都【不会被挤扁】, 只是多出空地 —— 多出来的地方由 UIFrame 设计框居中吃掉。
##  ★2026-08-01 修注释: 这里原本写 "aspect=keep", 而项目里早就是 expand —— 差别正是
##  "留黑边等比缩放" vs "视口跟着比例长", 照着旧注释推理会得出完全相反的结论。)
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed):
		var w := get_window()
		var is_fs: bool = w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
		w.mode = Window.MODE_WINDOWED if is_fs else Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()
