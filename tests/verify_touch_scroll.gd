extends Node

# 触屏滚动守卫 (2026-07-22)
#
# 用户:「调试场选装备选龟需要适配手机端的滑动，选龟页面也是」
#
# ★根因(项目自己踩过并写进注释): Godot 的 GUI 事件遇 MOUSE_FILTER_STOP 就停止冒泡,
#   而 ScrollContainer 的触屏拖动是在它自己的 gui_input 里处理 InputEventScreenTouch/Drag 的
#   → 列表项设了 STOP, 手指按在列表项上拖动就永远滑不动。
#   同款教训: CodexScene.gd:651「子控件吞掉拖动=手机滑不动·2026-07-18」
#            InventoryScene.gd:523「触屏拖动透传→ScrollContainer 滚动」
#
# ★为什么必须是【结构不变式】而不是模拟拖动: 全仓库零处构造过 InputEventScreenDrag,
#   无头下也没法真的产生触屏手势。而"祖先链上没有 STOP"是纯结构条件, 无头可判、稳定。
#   更要命的是 tests/verify_ios_ui.gd:42 的 _in_scroll() 把 ScrollContainer 里的按钮
#   全部【豁免】越界检查, 理由是"滚动可达" —— 而这个假设在触屏上正是错的。

var _fails: Array[String] = []


func _ready() -> void:
	_check_source("res://scripts/scenes/RealtimeBattle3DScene.gd", "_edit_grid_card",
		"调试场选装备/选龟网格卡片")
	_check_source("res://scripts/scenes/TeamSelectScene.gd", "_make_pet_card",
		"选龟龟池卡片")
	_check_teamselect_drag()
	_done()


## 卡片构造函数里不得把自己设成 MOUSE_FILTER_STOP
func _check_source(path: String, fname: String, human: String) -> void:
	var src := FileAccess.get_file_as_string(path)
	if src == "":
		_fail("读不到 %s" % path)
		return
	var body := _code_only(_func_body(src, fname))
	if body == "":
		# 函数名可能改过 —— 退化为全局扫描, 但要报出来(避免"找不到=通过"的空检查)
		_fail("%s: 找不到函数 %s(被改名?) —— 这条守卫失效了" % [human, fname])
		return
	if body.find("MOUSE_FILTER_STOP") >= 0:
		_fail("%s 把自己设成 MOUSE_FILTER_STOP —— 触屏拖动到不了 ScrollContainer, 手机上滑不动" % human)
	if body.find("MOUSE_FILTER_PASS") < 0:
		_fail("%s 没设 MOUSE_FILTER_PASS —— 默认 STOP 同样会吞掉拖动(Control 默认就是 STOP)" % human)
	print("  [%s] mouse_filter 已检" % human)


## 选龟卡片的原生拖放在手机上必须关掉, 否则 DnD 一启动就吃掉手指移动, 滚动抢不过
func _check_teamselect_drag() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/scenes/TeamSelectScene.gd")
	if src == "":
		return
	# ★只看【卡片构造函数体内】的拖放。全局 find 会命中第一处 —— 那是编队槽(_slot_drag)的,
	#   而槽位不在 ScrollContainer 里、不挡滑动, 拿它当判据是误报(2026-07-22 实测踩到)。
	var body := _code_only(_func_body(src, "_make_pet_card"))
	if body == "":
		_fail("找不到 _make_pet_card —— 这条守卫失效了")
		return
	if body.find("set_drag_forwarding") < 0:
		print("  [选龟拖放] 卡片已无原生 DnD")
		return
	if body.find("is_mobile()") < 0:
		_fail("选龟卡片的 set_drag_forwarding 没有 is_mobile 守卫 —— 手机上拖动手势会被原生 DnD 抢走, 列表滑不动")
	else:
		print("  [选龟拖放] 手机端已关掉原生 DnD")


## 剥注释 —— 注释里提到 MOUSE_FILTER_STOP 会造成假报警; 反过来注释里提到 PASS 会造成假通过。
## 不能简单按第一个 # 截断: 满文件 Color("#xxxxxx") 会被误伤 → 判引号状态。
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


func _fail(msg: String) -> void:
	_fails.append(msg)


func _done() -> void:
	if _fails.is_empty():
		print("ALL PASS — 触屏滚动透传正确")
	else:
		for f in _fails:
			printerr("FAIL: %s" % f)
		printerr("FAIL — 触屏滚动 %d 项不通过" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)
