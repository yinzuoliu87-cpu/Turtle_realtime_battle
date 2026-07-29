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
## ★留这条门禁的唯一理由：**防止有人再把它改成允许竖屏**。改了直接红。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_orientation_lock.tscn

var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	print("=== 屏幕方向锁 ===")
	var orient := str(ProjectSettings.get_setting("display/window/handheld/orientation", ""))
	print("  display/window/handheld/orientation = \"%s\"  (★分母: 读得到设置)" % orient)
	_chk("① 设置读得到(空 = 这条是空检查)", orient != "")
	print("  必须含 \"landscape\"。允许竖屏(\"sensor\"/\"portrait\")会导致:")
	print("    竖着拿手机启动 → 游戏直接竖屏, 且运行时转不回来(iOS 启动即定方向)")
	_chk("② ★方向锁死横屏", orient.find("landscape") >= 0)

	print("")
	print("ALL PASS — 屏幕方向锁" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _chk(what: String, ok: bool) -> void:
	if not ok:
		_fail += 1
	print("     %s %s" % ["[PASS]" if ok else "[FAIL]", what])
