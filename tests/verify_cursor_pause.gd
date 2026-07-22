extends Node

## verify_cursor_pause.gd — 暂停时自绘光标仍要跟手 (用户 2026-07-22:「点暂停光标没有动啊，这是大问题」)
##
## 根因(探针实测, 不是推理): CursorTheme 是 autoload, 自绘光标靠 _process 每帧贴到鼠标位置;
## autoload 默认 process_mode=INHERIT → 跟 root 的 PAUSABLE → get_tree().paused 后
## _process 直接停跑 → 光标定在原地。而系统光标是 MOUSE_MODE_HIDDEN 的,
## 于是玩家看到的是"鼠标彻底失灵"。
##
## ★这和同日修的「暂停后拖不动镜头」是【同一类】根因(都是 process_mode), 但**是两个独立的洞** ——
##   修好相机那次并没有顺带修好光标, 因为它们在不同的节点上。

const SRC := "res://autoload/CursorTheme.gd"

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	var ct := get_node_or_null("/root/CursorTheme")
	_ok("CursorTheme autoload 在", ct != null)
	if ct == null:
		_done()
		return

	_ok("光标是靠 _process 每帧驱动的(前提: 所以它怕暂停)", ct.has_method("_process"))
	print("  [实测] CursorTheme.process_mode=%d  root.process_mode=%d" % [ct.process_mode, get_tree().root.process_mode])
	_ok("★光标节点是 PROCESS_MODE_ALWAYS", ct.process_mode == Node.PROCESS_MODE_ALWAYS,
		"process_mode=%d (0=INHERIT 1=PAUSABLE 3=ALWAYS)" % ct.process_mode)

	# 行为: 真暂停一次, 问它还跑不跑
	var was := get_tree().paused
	_ok("未暂停时能跑(对照组, 否则下面那条没意义)", ct.can_process())
	get_tree().paused = true
	await get_tree().process_frame
	print("  [实测] 暂停后 can_process()=%s" % ct.can_process())
	_ok("★★暂停中光标仍在跑(false = 光标定在原地 = 玩家以为鼠标失灵)", ct.can_process())
	get_tree().paused = was
	await get_tree().process_frame
	_ok("恢复后仍在跑", ct.can_process())

	_test_set_before_early_returns()
	_done()


## ★结构: 那行必须在几个早退【之前】—— 放后面的话无头/移动端根本执行不到,
##   而无头正是本门禁跑的地方 → 会变成一条永远测不到真实代码的假断言。
func _test_set_before_early_returns() -> void:
	var src := FileAccess.get_file_as_string(SRC)
	_ok("读得到 CursorTheme.gd", src != "")
	var body := _func_body(src, "_ready")
	var code := _code_only(body)
	var i_set := code.find("process_mode = Node.PROCESS_MODE_ALWAYS")
	var i_ret := code.find("return")
	print("  [实测] _ready 里 设置@%d / 第一个 return@%d" % [i_set, i_ret])
	_ok("★_ready 里设了 ALWAYS", i_set >= 0)
	_ok("★设置在第一个早退之前(否则无头/移动端执行不到, 这条门禁会变成假断言)",
		i_set >= 0 and (i_ret < 0 or i_set < i_ret),
		"设置@%d 早退@%d" % [i_set, i_ret])


func _func_body(src: String, fname: String) -> String:
	var head := "\nfunc %s(" % fname
	var i := src.find(head)
	if i < 0:
		return ""
	var start := i + 1
	var j := src.find("\nfunc ", start)
	if j < 0:
		j = src.length()
	return src.substr(start, j - start)


func _strip_comment(line: String) -> String:
	var in_q := false
	var q := ""
	for i in line.length():
		var ch := line[i]
		if in_q:
			if ch == q and (i == 0 or line[i - 1] != "\\"):
				in_q = false
		elif ch == "\"" or ch == "'":
			in_q = true
			q = ch
		elif ch == "#":
			return line.substr(0, i)
	return line


func _code_only(block: String) -> String:
	var out := ""
	for l in block.split("\n"):
		out += _strip_comment(str(l)) + "\n"
	return out


func _done() -> void:
	print("ALL PASS — 暂停中自绘光标仍跟手" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
