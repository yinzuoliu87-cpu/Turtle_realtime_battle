extends Node
## verify_orientation_lock.gd — 屏幕方向必须锁死横屏
##
## 由来（2026-07-29，这条是用真机翻车换来的）：
## 摸鱼模式想在运行时切竖屏，我把 project.godot 的 handheld/orientation
## 从 "sensor_landscape" 改成 "sensor"（允许全部方向）。结果用户装上包：
##   「摸鱼模式关的时候，为啥 iOS 上还是竖着的」
##
## 根因：**iOS 在启动那一刻就按 Info.plist 决定方向**。plist 一旦允许竖屏，
## 用户竖着拿手机启动，App 就直接以竖屏起来；代码里"锁回横屏"跑在启动之后，
## iOS 16+ 收窄方向掩码**不会自动转回去**。
##
## → 这个游戏是横版的，方向必须在工程设置里就锁死。摸鱼模式已放弃（见
##   docs/plans/20260729b-摸鱼模式小窗口.md 的 R6/R7）。
##
## ★留这条门禁的理由：**防止有人再把它改成允许竖屏**。改了直接红。
##
## ★★2026-10-24 改正（用户真机「手机倒过来画面不转」）：
##   project.godot 里写的是字符串 `"sensor_landscape"` —— 那是 **Godot 3** 的写法。
##   Godot 4 这一项是整数枚举, 字符串被当整数读 = 0 = `SCREEN_LANDSCAPE`(只认一个横向)。
##   ⇒ 横屏是锁住了, 但手机转 180° 画面不跟着翻。
##   而原来这条门禁判的是「字符串里含 landscape」—— 它把那个错写法**当成了标准**, 一直绿。
##   ⇒ 现在判**引擎实际读到的值**: 必须是整数 `SCREEN_SENSOR_LANDSCAPE`(4 = 两个横向都跟着转、不许竖屏)。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_orientation_lock.tscn

var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	print("=== 屏幕方向锁 ===")
	var raw = ProjectSettings.get_setting("display/window/handheld/orientation", null)
	print("  display/window/handheld/orientation = %s (%s)  (★分母: 读得到设置)" % [var_to_str(raw), type_string(typeof(raw))])
	_chk("① 设置读得到(null = 这条是空检查)", raw != null)
	_chk("② 是 Godot 4 的整数枚举(字符串 \"sensor_landscape\" 会被读成 0 = 只认一个横向)", typeof(raw) == TYPE_INT)
	print("  必须 = SCREEN_SENSOR_LANDSCAPE(%d)。只认一个横向(0/2) ⇒ 手机倒过来画面不转;" % DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	print("    允许竖屏(sensor/portrait) ⇒ 竖着拿手机启动 → 游戏直接竖屏, 且运行时转不回来(iOS 启动即定方向)")
	_chk("③ ★两个横向都跟着转、不许竖屏", typeof(raw) == TYPE_INT and int(raw) == DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	## ⚠ 不拿 `DisplayServer.screen_get_orientation()` 当判据: 无头显示服务器不管设置写什么都回 0(实测), 量不出东西。
	##   真正的产物是导出包 Info.plist 的 UISupportedInterfaceOrientations。2026-10-24 本机导 iOS 工程对照:
	##   字符串写法 ⇒ iPhone 只有 LandscapeLeft、iPad 只有 LandscapeRight; 整数 4 ⇒ 两边都是 Left + Right。

	print("")
	print("ALL PASS — 屏幕方向锁" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _chk(what: String, ok: bool) -> void:
	if not ok:
		_fail += 1
	print("     %s %s" % ["[PASS]" if ok else "[FAIL]", what])
