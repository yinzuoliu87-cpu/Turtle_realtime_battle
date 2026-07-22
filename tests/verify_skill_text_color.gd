extends Node

## verify_skill_text_color.gd — 选龟界面技能说明上色 (2026-07-22)
##
## 用户需求1:「文案描述里的数值和文字该怎么渲染颜色」。
## 此前选龟界面(tooltip + 弹窗)走 render_plain + Label = 全灰, 图鉴是唯一有色的地方。
##
## ★这条门禁必须是【行为级】的: 光断言源码里写了 render_bbcode 没用 ——
##   只要盛放的控件还是 Label, 玩家看到的就是满屏 "[color=#ff4444]70[/color]" 字面量,
##   比不上色更糟。所以真建控件、真塞带标记的文本、再问它解析后的纯文本是什么。

const SkillTipButton := preload("res://scripts/scenes/SkillTipButton.gd")
const TEAM_SRC := "res://scripts/scenes/TeamSelectScene.gd"

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	_test_renderer()
	_test_tooltip_widget()
	_test_no_plain_left()
	print("ALL PASS — 选龟技能说明上色(标记真到达控件)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## ① 渲染器: 真拿 pets.json 的 brief 过一遍, 统计有多少条能出颜色标记
func _test_renderer() -> void:
	var raw := FileAccess.get_file_as_string("res://data/pets.json")
	var parsed = JSON.parse_string(raw)
	var pets: Array = []
	if parsed is Dictionary and parsed.has("pets"):
		pets = parsed["pets"]
	elif parsed is Array:
		pets = parsed
	var ctx := {"atk": 100.0, "def": 10.0, "mr": 10.0, "maxHp": 1000.0, "hp": 1000.0, "level": 1, "crit": 0.0}
	var n_brief := 0
	var n_colored := 0
	for p in pets:
		for sk in p.get("skillPool", []):
			var b := str(sk.get("brief", ""))
			if b == "":
				continue
			n_brief += 1
			if SkillText.render_bbcode(b, ctx, sk).contains("[color="):
				n_colored += 1
	print("  [分母] 有 brief 的技能格 %d 个, 其中 render_bbcode 能出颜色标记的 %d 个" % [n_brief, n_colored])
	_ok("brief 分母非 0(N=0 是空检查不是通过)", n_brief > 0)
	_ok("★绝大多数技能说明能出颜色标记", n_colored >= int(n_brief * 0.8),
		"%d/%d" % [n_colored, n_brief])
	# 对照: render_plain 必须【不带】标记, 否则两个出口分不清
	var sample := "造成（{N:0.7*ATK}）物理伤害"
	var plain := SkillText.render_plain(sample, ctx, {})
	_ok("render_plain 仍是纯文本(不带标记)", not plain.contains("[color="), plain)
	_ok("render_bbcode 与 render_plain 确实不同(否则上色根本没发生)",
		SkillText.render_bbcode(sample, ctx, {}) != plain)


## ② 控件: tooltip 里盛放描述的必须是能解析 bbcode 的控件
func _test_tooltip_widget() -> void:
	var btn := SkillTipButton.new()
	add_child(btn)
	var marked := "[color=#ff4444]70[/color] 物理伤害"
	var tip = btn._make_custom_tooltip("烈焰斩 (CD8)\n" + marked)
	_ok("tooltip 建出来了", tip != null)
	if tip == null:
		btn.queue_free()
		return
	add_child(tip)
	await_frames()
	var rt: RichTextLabel = _find_rich(tip)
	_ok("★描述体是 RichTextLabel(用 Label 会把 [color=..] 原样显示给玩家)", rt != null)
	if rt != null:
		_ok("★开了 bbcode_enabled", rt.bbcode_enabled)
		_ok("★fit_content 开着(不开高度为 0, tooltip 只剩标题)", rt.fit_content)
		var parsed_txt := rt.get_parsed_text()
		print("  [实测] 解析后的纯文本 = %s" % parsed_txt.strip_edges())
		_ok("★标记被解析掉而不是当字面量显示", not parsed_txt.contains("[color="), parsed_txt)
		_ok("★内容还在(解析没把正文一起吃掉)", parsed_txt.contains("70") and parsed_txt.contains("物理伤害"))
	tip.queue_free()
	btn.queue_free()


func await_frames() -> void:
	pass


func _find_rich(n: Node) -> RichTextLabel:
	if n is RichTextLabel:
		return n
	for c in n.get_children():
		var r := _find_rich(c)
		if r != null:
			return r
	return null


## ③ 选龟界面不许再有走 render_plain 的 tooltip —— 那条路径出来的字是灰的
func _test_no_plain_left() -> void:
	var src := FileAccess.get_file_as_string(TEAM_SRC)
	_ok("读得到 TeamSelectScene.gd", src != "")
	var code := _code_only(src)
	var n_plain := code.count("render_plain(")
	var n_bb := code.count("render_bbcode(")
	print("  [分母] TeamSelectScene 里 render_bbcode %d 处 / render_plain %d 处" % [n_bb, n_plain])
	_ok("★选龟界面已改走 render_bbcode", n_bb >= 4, "只有 %d 处" % n_bb)
	_ok("★没有残留的 render_plain(那条路径是灰字)", n_plain == 0, "还剩 %d 处" % n_plain)


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
