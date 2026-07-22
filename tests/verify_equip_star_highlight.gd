extends Node

## verify_equip_star_highlight.gd — 装备文案按当前星级高亮 (2026-07-22)
##
## 用户需求1:「商店里装备介绍，背包里装备介绍」+ 拍板【不改数据格式】。
## 59 件装备的 effectDesc1 用 `a/b/c` 表示 1★/2★/3★, 但此前三档一律同色,
## 玩家得自己数第几个才知道哪个是自己的。
##
## ★这条门禁最要紧的一件事: 高亮是【渲染期】变换, data/phase2-equipment.json 一个字不能动。
##   tools/tooltip_number_audit.py 靠 `\d+/\d+/\d+` 正则从 effectDesc1 抠三元组去和代码对账,
##   数据格式一变它就抠不出来 → total 归零 → 打印 ALL OK 但什么都没查(方案书 R1 记的静默失效)。

const RichTooltip := preload("res://scripts/scenes/rich_tooltip.gd")
const UIPalette = preload("res://scripts/engine/ui_palette.gd")
const SkillTextC = preload("res://scripts/engine/skill_text.gd")
const INV_SRC := "res://scripts/scenes/InventoryScene.gd"
const EQ_JSON := "res://data/phase2-equipment.json"

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	_test_highlight_picks_right_one()
	_test_real_equipment_coverage()
	_test_data_untouched()
	_test_widget_renders_bbcode()
	print("ALL PASS — 装备文案按星级高亮(渲染期, 未动数据格式)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## ① 选中的必须是第 star 档, 不是第一档也不是最后一档
func _test_highlight_picks_right_one() -> void:
	var desc := "造成 0.6/0.75/1.0×攻击力 物理伤害"
	for star in [1, 2, 3]:
		var out := SkillTextC.highlight_star(desc, star)
		var want: String = ["0.6", "0.75", "1.0"][star - 1]
		# 亮的那档: 被 [b][color=..] 包住
		var lit := "[b][color=%s]%s[/color][/b]" % [UIPalette.DEF, want]
		_ok("★★%d 高亮的是第 %d 档 (%s)" % [star, star, want], out.contains(lit), out)
		# 另两档必须【暗】而不是同样高亮 —— 否则等于没区分
		for i in 3:
			if i == star - 1:
				continue
			var other: String = ["0.6", "0.75", "1.0"][i]
			_ok("★%d 时第 %d 档是暗的" % [star, i + 1],
				out.contains("[color=#5a6472]%s[/color]" % other),
				"第 %d 档 %s 没变暗" % [i + 1, other])
	# 越界/无星级 → 原样返回(图鉴没有玩家星级)
	_ok("star=0 时不高亮(图鉴那种没有玩家星级的场合)", SkillTextC.highlight_star(desc, 0) == desc)
	_ok("空串安全", SkillTextC.highlight_star("", 2) == "")


## ② 拿真实的 59 件装备跑一遍, 打印分母
func _test_real_equipment_coverage() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(EQ_JSON))
	var eq: Array = []
	if parsed is Array:
		eq = parsed
	elif parsed is Dictionary:
		for k in ["equipment", "items"]:
			if parsed.has(k):
				eq = parsed[k]
				break
	var n_total := eq.size()
	var n_tri := 0
	var n_changed := 0
	for e in eq:
		var d := str((e as Dictionary).get("effectDesc1", ""))
		if d == "":
			continue
		var hl := SkillTextC.highlight_star(d, 2)
		if hl != d:
			n_changed += 1
			n_tri += 1
	print("  [分母] 装备 %d 件, 其中含三元组能被高亮的 %d 件" % [n_total, n_tri])
	_ok("装备分母非 0(N=0 是空检查不是通过)", n_total > 0)
	_ok("★大多数装备的文案能被高亮", n_tri >= int(n_total * 0.8), "%d/%d" % [n_tri, n_total])


## ③ 数据格式没被动过 —— 这是本次改动最容易顺手做错的事
func _test_data_untouched() -> void:
	var raw := FileAccess.get_file_as_string(EQ_JSON)
	_ok("读得到装备表", raw != "")
	_ok("★装备表里没有 BBCode(高亮必须只发生在渲染期)",
		not raw.contains("[color=") and not raw.contains("[b]"),
		"数据里出现了 BBCode = 有人把高亮写死进数据了")
	var re := RegEx.create_from_string("\\d+(?:\\.\\d+)?/\\d+(?:\\.\\d+)?/\\d+(?:\\.\\d+)?")
	var n := re.search_all(raw).size()
	print("  [分母] 装备表里仍能被 tooltip_number_audit 正则抠出的三元组 %d 个" % n)
	_ok("★三元组正则仍抠得出(否则 tooltip_number_audit 会静默变成空检查)", n >= 50, "只剩 %d 个" % n)


## ④ 控件真能渲染 —— 光生成 BBCode 没用, 系统 tooltip 是纯文本会原样显示出来
func _test_widget_renders_bbcode() -> void:
	var panel := Panel.new()
	panel.set_script(RichTooltip)
	add_child(panel)
	var marked := SkillTextC.highlight_star("造成 0.6/0.75/1.0×攻击力", 2)
	var tip = panel._make_custom_tooltip(marked)
	_ok("自定义 tooltip 建出来了", tip != null)
	if tip != null:
		add_child(tip)
		var rt := _find_rich(tip)
		_ok("★tooltip 里是 RichTextLabel", rt != null)
		if rt != null:
			_ok("★开了 bbcode_enabled", rt.bbcode_enabled)
			_ok("★fit_content 开着(不开 tooltip 是空白的)", rt.fit_content)
			var txt := rt.get_parsed_text()
			print("  [实测] 解析后 = %s" % txt.strip_edges())
			_ok("★标记被解析掉而不是当字面量显示", not txt.contains("[color="), txt)
			_ok("★三个档位都还在(高亮没吃掉内容)",
				txt.contains("0.6") and txt.contains("0.75") and txt.contains("1.0"), txt)
		tip.queue_free()
	panel.queue_free()
	# 背包确实用上了这条路径
	var src := _code_only(FileAccess.get_file_as_string(INV_SRC))
	_ok("★背包真的调了 highlight_star", src.contains("SkillText.highlight_star("),
		"背包没接线 = 玩家看不到高亮")
	_ok("★背包格子挂了能渲染 BBCode 的 tooltip", src.contains("set_script(RichTooltip)"),
		"不挂就是系统纯文本 tooltip, 会把 [color=..] 显示给玩家")


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
