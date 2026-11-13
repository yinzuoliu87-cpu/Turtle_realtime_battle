extends Node
## verify_save_iso —— 存档隔离闸(scripts/util/save_iso.gd, 2026-11-13)
##
## 起因: 11-12 用户真存档被测试假号(11111111-2222-…)覆盖。测试为了量存档会 `test_mode = false` 再 save();
##   不带 APPDATA / XDG_DATA_HOME 单跑 ⇒ 写进玩家真目录。闸: 测试 / 台子进程 + 默认目录 ⇒ save() 拒写。
## ★本测试**不改任何环境变量**: Windows 上 Godot 每次访问 user:// 都按当时的 APPDATA 重新解析 ——
##   第一版在进程里把 APPDATA 改成真目录来模拟, 结果第④步真写进了用户的存档(11-13 事故)。
##   现在只拨 `SaveIso.assume_default_for_test`, user:// 始终是门禁给的临时目录; 开头还先确认自己是隔离跑的, 不是就不写。
## ① 纯判据 is_default_dir(Windows / Linux 各几组)
## ② 本进程: 开机已记下 harness(无头) · 临时目录下照常写
## ③ ★拨测试开关当作「默认目录」⇒ save() 不写(存档逐字节不变) · 拨回 ⇒ 又能写
## ④ 真玩家进程(harness 空)在默认目录照常写

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== verify_save_iso: 测试 / 台子进程不写玩家真存档 ===")
	_t_pure()
	_t_live()
	print("合计 %d 条" % _n)
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _t_pure() -> void:
	print("── ① 纯判据 ──")
	var W := "Windows"
	_ok("① Windows 默认 APPDATA ⇒ 默认目录", SaveIso.is_default_dir(W, "C:\\Users\\a\\AppData\\Roaming", "C:\\Users\\a", "", ""))
	_ok("① Windows 大小写 / 斜杠 / 结尾斜杠不同也认", SaveIso.is_default_dir(W, "c:/users/A/appdata/roaming/", "C:\\Users\\a", "", ""))
	_ok("① Windows APPDATA 指到临时目录 ⇒ 不是", not SaveIso.is_default_dir(W, "C:/Users/a/AppData/Local/Temp/tmp.x", "C:\\Users\\a", "", ""))
	_ok("① Windows 门禁目录 C:/tmp/gate_appdata ⇒ 不是", not SaveIso.is_default_dir(W, "C:/tmp/gate_appdata/verify_x", "C:\\Users\\a", "", ""))
	_ok("① Windows APPDATA 缺 ⇒ 拿不准当默认", SaveIso.is_default_dir(W, "", "C:\\Users\\a", "", ""))
	_ok("① Linux XDG 没设 ⇒ 默认", SaveIso.is_default_dir("Linux", "", "", "", "/home/a"))
	_ok("① Linux XDG = ~/.local/share ⇒ 默认", SaveIso.is_default_dir("Linux", "", "", "/home/a/.local/share/", "/home/a"))
	_ok("① Linux XDG 指到别处(CI / 裁判机每局目录) ⇒ 不是", not SaveIso.is_default_dir("Linux", "", "", "/tmp/gate_appdata/x", "/home/a"))


func _save_bytes(gs) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(gs.SAVE_PATH) if FileAccess.file_exists(gs.SAVE_PATH) else PackedByteArray()


func _t_live() -> void:
	print("── ②③④ 本进程 ──")
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		_ok("② 分母: GameState 在", false)
		return
	_ok("② 开机已记下「这是测试进程」(harness=%s)" % SaveIso.harness, SaveIso.harness != "")
	## ★先确认自己是隔离跑的; 不是就**一个字都不写**直接判红(本测试下面会真写存档)。
	if SaveIso.on_default_dir():
		_ok("② ★本测试没带隔离(APPDATA / XDG_DATA_HOME 是默认目录) ⇒ 不往下跑, 免得写玩家真存档", false)
		return
	_ok("② ★分母: 门禁给了临时 user:// ⇒ 现在不是默认目录", true,
		"APPDATA=%s XDG=%s" % [OS.get_environment("APPDATA"), OS.get_environment("XDG_DATA_HOME")])
	var tm0: bool = gs.test_mode
	var nick0 = gs.nickname
	gs.test_mode = false
	gs.nickname = "隔离甲"
	gs.save()
	var b1 := _save_bytes(gs)
	_ok("② 临时目录下照常写(存档里有「隔离甲」)", b1.get_string_from_utf8().contains("隔离甲"))
	## ③ 只拨测试开关, 环境变量一个不动 ⇒ user:// 始终是临时目录, 就算闸失灵也只写到临时目录。
	SaveIso.assume_default_for_test = true
	_ok("③ 分母: 开关拨上后闸认成默认目录", SaveIso.on_default_dir())
	gs.nickname = "隔离乙"
	gs.save()
	var b2 := _save_bytes(gs)
	_ok("③ ★★默认目录 + 测试进程 ⇒ save() 不写(存档逐字节不变, 没有「隔离乙」)", b2 == b1 and not b2.get_string_from_utf8().contains("隔离乙"),
		"b1 %d 字节 / b2 %d 字节" % [b1.size(), b2.size()])
	var h0 := SaveIso.harness
	SaveIso.harness = ""
	gs.nickname = "隔离丙"
	gs.save()
	_ok("④ 真玩家进程(harness 空)在默认目录照常写", _save_bytes(gs).get_string_from_utf8().contains("隔离丙"))
	SaveIso.harness = h0
	SaveIso.assume_default_for_test = false
	_ok("③ 开关拨回 ⇒ 闸放行", not SaveIso.on_default_dir() and not SaveIso.blocks_save())
	gs.nickname = nick0
	gs.test_mode = tm0
