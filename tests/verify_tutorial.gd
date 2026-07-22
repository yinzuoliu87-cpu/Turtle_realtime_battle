extends Node

## verify_tutorial.gd — 新手引导真的跑得起来 (2026-07-22)
##
## 用户需求1:「全面优化新手引导…比如右上角新手引导模式」。
## 调查结论: scripts/scenes/TutorialGuide.gd 143 行【完整实现】, 但**全项目零引用** ——
## 主菜单「❓教程」只设了 GameState.tutorial=true 就进普通战斗, 而战斗场零处读这个 flag。
## 教程步骤数据也不存在。等于一套写好的东西从来没人按开关。
##
## ★所以这条门禁的重点是【它真的被接上了】, 而不是"代码写得对不对":
##   死代码永远是"对"的。

const TutorialGuide := preload("res://scripts/scenes/TutorialGuide.gd")
const STEPS_JSON := "res://data/tutorial-steps.json"

var _fail := 0
var _done_called := false


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	_test_steps_data()
	await _test_guide_runs()
	_test_wired_in()
	print("ALL PASS — 新手引导已接线且能推进" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## ① 步骤数据本身
func _test_steps_data() -> void:
	var raw := FileAccess.get_file_as_string(STEPS_JSON)
	_ok("读得到 tutorial-steps.json", raw != "")
	var parsed = JSON.parse_string(raw)
	_ok("是合法 JSON 对象", parsed is Dictionary)
	if not (parsed is Dictionary):
		return
	var n_keys := 0
	var n_steps := 0
	for k in (parsed as Dictionary).keys():
		if str(k).begins_with("_"):
			continue
		var arr = parsed[k]
		if arr is Array:
			n_keys += 1
			n_steps += (arr as Array).size()
			for st in arr:
				_ok("%s 的每一步都有 text" % str(k), st is Dictionary and str(st.get("text", "")) != "",
					"缺 text: %s" % str(st))
	print("  [分母] 引导场景 %d 个, 步骤共 %d 步" % [n_keys, n_steps])
	_ok("★步骤分母非 0(N=0 是空检查不是通过)", n_keys > 0 and n_steps > 0)
	# steps_for 取得到
	for key in ["team_select", "battle"]:
		var steps := TutorialGuide.steps_for(key)
		_ok("steps_for(\"%s\") 取得到步骤" % key, steps.size() > 0, "%d 步" % steps.size())
	_ok("steps_for 对不存在的 key 返回空而不是崩",
		TutorialGuide.steps_for("__不存在的场景__").is_empty())


## ② 真跑一遍: 建 UI → 推进 → 结束回调
func _test_guide_runs() -> void:
	var g = TutorialGuide.new()
	add_child(g)
	var steps := [
		{"text": "第一步 <b>加粗</b>", "anchor": "top"},
		{"text": "第二步 等事件", "anchor": "top", "advanceOn": "手动事件"},
		{"text": "第三步 收尾", "anchor": "bottom"},
	]
	g.start(steps, func() -> void: _done_called = true)
	await get_tree().process_frame
	var rt := _find_rich(g)
	_ok("★引导真的建出了文字控件", rt != null)
	if rt != null:
		var t1 := rt.get_parsed_text()
		print("  [实测] 第1步显示 = %s" % t1.strip_edges())
		_ok("★显示的是第一步的内容", t1.contains("第一步"), t1)
		_ok("★<b> 被转成了 BBCode 而不是当字面量显示", not t1.contains("<b>"), t1)

	# 推进到第二步
	g._next()
	await get_tree().process_frame
	_ok("★能推进到第二步", _find_rich(g) != null and _find_rich(g).get_parsed_text().contains("第二步"))

	# notify: 名字不对不该推进 —— 否则任何事件都能乱推
	g.notify("不相干的事件")
	await get_tree().process_frame
	_ok("★notify 事件名不匹配时【不】推进",
		_find_rich(g).get_parsed_text().contains("第二步"), "被别的事件推走了")
	g.notify("手动事件")
	await get_tree().process_frame
	_ok("★notify 事件名匹配时推进到第三步",
		_find_rich(g) != null and _find_rich(g).get_parsed_text().contains("第三步"))

	# 最后一步再 next → 结束回调
	_ok("结束前 on_done 还没被调用", not _done_called)
	g._next()
	await get_tree().process_frame
	_ok("★走完最后一步会调 on_done", _done_called)


## ③ 真的被接上了 —— 这才是本轮的核心, 死代码永远是"对"的
func _test_wired_in() -> void:
	var refs := 0
	var hits: Array = []
	for path in ["res://scripts/scenes/TeamSelectScene.gd", "res://scripts/scenes/RealtimeBattle3DScene.gd"]:
		var src := _code_only(FileAccess.get_file_as_string(path))
		if src.contains("TutorialGuide.attach("):
			refs += 1
			hits.append(path.get_file())
	print("  [分母] 调用 TutorialGuide.attach 的场景 %d 个: %s" % [refs, str(hits)])
	_ok("★选龟与战斗两个场景都接上了引导(此前零引用)", refs >= 2, "只有 %d 个" % refs)
	var bat := _code_only(FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd"))
	_ok("★战斗场在开面板处发了推进事件(否则那一步永远卡住)",
		bat.contains("_tutorial.notify(\"info_panel_opened\")"))
	_ok("★引导只在 GameState.tutorial 时才建(正常对局不该弹)",
		bat.contains("if GameState.tutorial:"))


func _find_rich(n: Node) -> RichTextLabel:
	if n is RichTextLabel:
		return n
	for c in n.get_children():
		var r := _find_rich(c)
		if r != null:
			return r
	return null


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
