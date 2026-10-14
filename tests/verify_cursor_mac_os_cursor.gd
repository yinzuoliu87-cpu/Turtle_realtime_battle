extends Node
## verify_cursor_mac_os_cursor.gd — Mac 上不许出现两个光标(2026-10-14 内测「外部鼠标和绘制的鼠标图案重合」)
##
## 自绘龟爪靠 MOUSE_MODE_HIDDEN 藏系统光标; macOS 上系统光标会自己回来 ⇒ 两个箭头叠在一起。
## Mac 改成把爪子交给系统当光标(Input.set_custom_mouse_cursor), 不自绘。
## 判据:
##   ① Mac: 不建自绘层(没有 CanvasLayer)、不藏系统光标、不跑每帧跟随
##   ② Windows 等其余桌面: 仍走自绘(不许把 Mac 的改法带过去)
##   ③ 系统光标用的贴图 = 24 点(与自绘同为 24 设计px), 不是 48
## 无头下 _ready 早退 ⇒ 直接调产品自己的那两个建树函数。

const CT := preload("res://autoload/CursorTheme.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _layers(ct: Node) -> int:
	return ct.get_children().filter(func(c): return c is CanvasLayer).size()


func _ready() -> void:
	print("=== Mac 不出现两个光标 ===")
	CT.platform_override = "macOS"
	_ok("① 分母: macOS 判为系统光标", CT.uses_os_cursor())
	var mac = CT.new()
	add_child(mac)
	mac._build_os_cursor()
	_ok("① ★Mac 不建自绘层", _layers(mac) == 0, "CanvasLayer %d 个" % _layers(mac))
	_ok("① ★Mac 不藏系统光标", Input.mouse_mode != Input.MOUSE_MODE_HIDDEN, "mouse_mode=%d" % Input.mouse_mode)
	_ok("① Mac 不跑每帧跟随", not mac._enabled and not mac.is_processing())
	var tex: ImageTexture = mac._build(1, mac._point_cols, mac._point_rects, 24, 24)
	_ok("③ 系统光标贴图 24×24", tex.get_size() == Vector2(24, 24), str(tex.get_size()))

	## ② 其余桌面仍自绘; 且 _ready 里 Mac 分支在自绘之前(否则 Mac 照样建自绘)
	CT.platform_override = "Windows"
	_ok("② Windows 不判为系统光标", not CT.uses_os_cursor())
	var src := FileAccess.get_file_as_string("res://autoload/CursorTheme.gd")
	var i_os := src.find("	if uses_os_cursor():")
	var i_draw := src.find("	_build_cursor()\n") if src.find("	_build_cursor()\n") >= 0 else src.find("	_build_cursor()\r\n")
	_ok("② _ready 先判 Mac 再自绘", i_os > 0 and i_draw > i_os, "os@%d draw@%d" % [i_os, i_draw])
	var win = CT.new()
	add_child(win)
	win._build_cursor()
	_ok("② Windows 照旧建自绘层", _layers(win) == 1, "CanvasLayer %d 个" % _layers(win))

	CT.platform_override = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — Mac 不出现两个光标 (%d/%d)" % [_n, _n])
	get_tree().quit(1 if _fail > 0 else 0)
