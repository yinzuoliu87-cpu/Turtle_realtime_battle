extends Node

## verify_tutorial_steps_v2.gd — 教程步骤数据 + 引导条行为(2026-10-07 重做, 方案书 §6.2)
##
## 用户「行」认可的方向(方案书 §1):
##   4. 每一步只有**一句短的祈使句**  5. 高亮目标 + 手势指针; **玩家做了那个动作才前进**; 不要一串「下一步」
##   6. 文案不口语化(「不要口语化的我说了多少遍了」)
##
## 本门禁量:
##   ① 数据: 每步都有 advanceOn + highlight; 文案单行、≤14 字、无禁用词、无 <b> 标记
##   ② 每个 advanceOn 在 scripts/ 里都有一处产品代码发它(`notify("事件")`) —— 否则那一步永远翻不过去
##   ③ 引导条节点里**没有任何 Button**(B2/B3 都是「下一步/知道了」造的)
##   ④ 只在动作事件上前进: 不相干的事件不动; 越级事件(做了后面那步的动作)直接跳过去, 不卡死
##   ⑤ 导演 steps_key_for 用到的每个 key 在 json 里都有, json 里的 key 也都有人用(不留死步骤集)

const TutorialGuide := preload("res://scripts/scenes/TutorialGuide.gd")
const STEPS_JSON := "res://data/tutorial-steps.json"
## 方案书 §6.1 禁用词 + 第二人称(「你」) —— 口语化/说明书腔的来源。
const BANNED := ["啦", "吧", "呢", "哦", "咱", "我教你", "试试", "就行", "搞", "热身", "练练", "!", "！", "你", "<b>", "\n"]
const MAX_CHARS := 14

var _fail := 0
var _n := 0
## ★断言条数地板: 协程半路被 SCRIPT ERROR 掐断时照样会打 ALL PASS(memory fb-null-readback-makes-test-silently-abort)。
const MIN_ASSERTS := 70


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(STEPS_JSON))
	_ok("tutorial-steps.json 是对象", parsed is Dictionary)
	if not (parsed is Dictionary):
		_end()
		return
	var events := _check_data(parsed as Dictionary)
	_check_notify_sites(events)
	_check_keys(parsed as Dictionary)
	await _check_guide_behaviour()
	_end()


func _end() -> void:
	print("  (共 %d 条断言 · 跑了 %d 帧)" % [_n, Engine.get_process_frames()])
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少 %d) —— 有协程被半路掐断, 别当绿灯" % [_n, MIN_ASSERTS])
	print("ALL PASS — 教程步骤: 一步一句、做了才前进" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## ① 数据
func _check_data(d: Dictionary) -> Array:
	var n := 0
	var events: Array = []
	for key in d.keys():
		if str(key).begins_with("_"):
			continue
		for st in (d[key] as Array):
			n += 1
			var s: Dictionary = st
			var t := str(s.get("text", ""))
			var tag := "%s「%s」" % [key, t]
			_ok("%s 有 advanceOn(做了才前进)" % tag, str(s.get("advanceOn", "")) != "")
			_ok("%s 有 highlight(高亮目标)" % tag, str(s.get("highlight", "")) != "")
			_ok("%s 一句话: ≤%d 字" % [tag, MAX_CHARS], t.length() > 0 and t.length() <= MAX_CHARS, "%d 字" % t.length())
			var bad: Array = []
			for w in BANNED:
				if t.contains(str(w)):
					bad.append(str(w).c_escape())
			_ok("%s 无禁用词/标记" % tag, bad.is_empty(), str(bad))
			if str(s.get("advanceOn", "")) != "":
				events.append(str(s.get("advanceOn", "")))
	print("  [分母] 步骤 %d 步 / 事件 %d 个" % [n, events.size()])
	_ok("★分母: 步骤数 = 方案书 §4.1 的 11 步(选择框不算)", n == 11, "n=%d" % n)
	return events


## ② 每个 advanceOn 在产品代码里都有人发
func _check_notify_sites(events: Array) -> void:
	## ★只看含 `notify(` 的行再去注释(全仓 12 万行逐字符剥注释 + 字符串累加要几分钟)。
	var lines: PackedStringArray = []
	var files: Array = []
	_collect_gd("res://scripts", files)
	_collect_gd("res://autoload", files)
	for f in files:
		for line in FileAccess.get_file_as_string(f).split("\n"):
			if str(line).contains("notify("):
				lines.append(_strip_comment(str(line)))
	var src := "\n".join(lines)
	print("  [分母] 扫了 %d 个 .gd" % files.size())
	_ok("★分母: 扫到产品脚本", files.size() > 100, "n=%d" % files.size())
	for ev in events:
		var hit := src.contains("notify(\"%s\")" % ev)
		_ok("★事件「%s」在 scripts/ 里有产品代码发它" % ev, hit)


## ⑤ key 一一对应
func _check_keys(d: Dictionary) -> void:
	var dir_src := FileAccess.get_file_as_string("res://autoload/tutorial_director.gd")
	var used: Array = []
	var re := RegEx.new()
	re.compile("return \"([a-z_]+)\"")
	var body := dir_src.substr(dir_src.find("func steps_key_for"))
	body = body.substr(0, body.find("\nfunc ", 10) if body.find("\nfunc ", 10) > 0 else body.length())
	for m in re.search_all(body):
		used.append(m.get_string(1))
	print("  [分母] steps_key_for 用到的 key: %s" % str(used))
	_ok("★分母: steps_key_for 里找到 key", used.size() >= 4, str(used))
	for k in used:
		_ok("steps_key_for 用的「%s」在 json 里有步骤" % k, d.has(k) and (d[k] as Array).size() > 0)
	for k in d.keys():
		if not str(k).begins_with("_"):
			_ok("json 里的「%s」有人用(不留死步骤集)" % k, k in used)


## ③④ 引导条行为
func _check_guide_behaviour() -> void:
	var steps := [
		{"text": "甲", "highlight": "t", "advanceOn": "ev_a"},
		{"text": "乙", "highlight": "t", "advanceOn": "ev_b"},
		{"text": "丙", "highlight": "t", "advanceOn": "ev_c"},
	]
	var done := [false]
	var g = TutorialGuide.new()
	add_child(g)
	g.start(steps, func() -> void: done[0] = true, func(_n: String) -> Rect2: return Rect2(100, 100, 200, 60))
	for _i in range(TutorialGuide.STABLE_FRAMES + 4):
		await get_tree().process_frame
	_ok("★分母: 引导条真的显示出来了(没显示 ⇒ 下面的「没有按钮」是空检查)", g.is_showing())
	var btns := g.find_children("*", "Button", true, false)
	_ok("★★引导条里没有任何按钮(「下一步/知道了/完成/跳过」全删, 方案书 B2/B3)", btns.is_empty(),
		"找到 %d 个" % btns.size())
	_ok("显示的是第一步", g.current_text() == "甲", g.current_text())
	g.notify("不相干")
	_ok("★不相干的事件不前进", int(g._idx) == 0, "idx=%d" % int(g._idx))
	g.notify("ev_a")
	_ok("★做了这一步的动作 ⇒ 前进一步", int(g._idx) == 1 and g.current_text() == "乙")
	g.notify("ev_a")
	_ok("★已经过去的事件再来一次不倒退也不前进", int(g._idx) == 1)
	g.notify("ev_c")
	var idx_after := int(g._idx)
	await get_tree().process_frame
	_ok("★★越级: 直接做了最后一步的动作 ⇒ 引导走完(不卡在中间那步)", done[0], "idx=%d" % idx_after)
	## 越级到中间一步
	var g2 = TutorialGuide.new()
	add_child(g2)
	g2.start(steps, func() -> void: pass, func(_n: String) -> Rect2: return Rect2(100, 100, 200, 60))
	g2.notify("ev_b")
	_ok("★越级到中间: 从第 1 步直接到第 3 步", int(g2._idx) == 2 and g2.current_text() == "丙", "idx=%d" % int(g2._idx))
	g2.queue_free()
	## 手势指针在场
	var g3 = TutorialGuide.new()
	add_child(g3)
	g3.start(steps, func() -> void: pass, func(_n: String) -> Rect2: return Rect2(100, 100, 200, 60))
	for _i in range(TutorialGuide.STABLE_FRAMES + 4):
		await get_tree().process_frame
	var hand: TextureRect = g3.find_child("TutorialHand", true, false)
	_ok("★手势指针在场且可见(贴图读得到)", hand != null and hand.visible and hand.texture != null)
	if hand != null:
		var tip: Vector2 = hand.position + TutorialGuide.HAND_TIP * TutorialGuide.HAND_SCALE
		_ok("★指尖落在目标矩形里", Rect2(100, 100, 200, 60).grow(24).has_point(tip), str(tip))
	g3.queue_free()


func _collect_gd(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		var p := dir + "/" + fn
		if d.current_is_dir():
			if not fn.begins_with("."):
				_collect_gd(p, out)
		elif fn.ends_with(".gd"):
			out.append(p)
		fn = d.get_next()
	d.list_dir_end()


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
