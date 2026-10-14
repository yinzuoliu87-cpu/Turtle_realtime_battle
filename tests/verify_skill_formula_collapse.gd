extends Node
## verify_skill_formula_collapse.gd — 龟技能文案默认给结论、推导按需展开(2026-10-14)
##
## 方案书: docs/plans/20261014-龟技能文案默认给结论.md
## 判据:
##   ① 全库括号推导组「（… = {X:…}）」默认全部收起(分母: 收起前 ≥ 150 组)
##   ② 公式模式(图鉴/选龟页): 结论在前、系数在括号里, 不带当前属性值 ——「20（50% 攻击力）」, 不是「（50%×攻击力(40) = 20）」
##   ③ 彩虹龟「反射」默认渲染: 有结果数字 20, 没有「×攻击力(40)」推导
##   ④ 图鉴详情永远显示推导式; 渲染完全局开关回到 false(否则战斗面板 / 选龟页也会显示推导)
##   ⑤ 图鉴被动展开后, 简述行不再与全文同时出现(彩虹龟实拍: 同一句话一屏两遍)

const SKT := preload("res://scripts/util/skill_text.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _strings(o, out: Array) -> void:
	if o is String:
		out.append(o)
	elif o is Dictionary:
		for k in o:
			_strings(o[k], out)
	elif o is Array:
		for v in o:
			_strings(v, out)


func _texts_under(n: Node, out: Array) -> void:
	if n is RichTextLabel:
		out.append((n as RichTextLabel).get_parsed_text())
	for c in n.get_children():
		_texts_under(c, out)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 龟技能文案默认给结论 ===")
	var grp := RegEx.create_from_string("[（(]((?:[^（）()]|\\([^()]*\\))*?)=\\s*(\\{[A-Z]:[^}]+\\})\\s*[）)]")
	var all: Array = []
	_strings(DataRegistry.all_pets, all)
	var before := 0
	var after := 0
	var restored := true
	var bad_fm := 0
	for s in all:
		var t := str(s)
		before += grp.search_all(t).size()
		SKT.show_formula = false
		after += grp.search_all(SKT.collapse_formulas(t)).size()
		SKT.show_formula = true
		var fm := SKT.collapse_formulas(t)
		if grp.search_all(fm).size() > 0 or fm.contains("({ATK})") or fm.contains("({HP})"):
			bad_fm += 1
	SKT.show_formula = false
	_ok("① 分母: 收起前全库推导组 ≥ 150", before >= 150, "%d 组" % before)
	_ok("① ★默认全部收起", after == 0, "剩 %d 组" % after)
	_ok("② ★公式模式: 结论在前、无当前属性值、无「= 」推导组", bad_fm == 0, "%d 段不合格" % bad_fm)

	var rb: Dictionary = {}
	for p in DataRegistry.all_pets:
		if str(p.get("id", "")) == "rainbow":
			rb = p
	var refl: Dictionary = {}
	for sk in rb.get("skillPool", []):
		if str(sk.get("name", "")) == "反射":
			refl = sk
	var ctx := {"atk": 40, "def": 15, "mr": 17, "maxHp": 966, "hp": 966}
	var plain := SKT.render_bbcode(str(refl.get("detail", "")), ctx, refl, 17)
	var stripped := RegEx.create_from_string("\\[[^\\]]*\\]").sub(plain, "", true)
	_ok("③ 分母: 彩虹龟「反射」在", not refl.is_empty())
	_ok("③ ★默认: 有结果 20, 没有「×攻击力(40)」", stripped.contains("回复 20") and not stripped.contains("×攻击力(40)"), stripped.substr(0, 90))

	## ④⑤ 走图鉴真入口
	var inst = load("res://scenes/Codex.tscn").instantiate()
	add_child(inst)
	for _i in range(20):
		await get_tree().process_frame
	inst._switch_tab("pets")
	for _i in range(6):
		await get_tree().process_frame
	var idx := -1
	for i in range(inst._items.size()):
		if str(inst._items[i].get("id", "")) == "rainbow":
			idx = i
	inst._select(idx)
	inst._codex_skill_detail = refl
	inst._codex_detail._redraw()
	for _i in range(4):
		await get_tree().process_frame
	var det: Array = []
	_texts_under(inst.detail, det)
	var has_formula := false
	for t in det:
		if str(t).contains("20（50%"):
			has_formula = true
	_ok("④ ★图鉴详情永远显示推导式(用户 10-14「图鉴里全部放显示公式的」)", has_formula)
	_ok("④ ★图鉴渲染完全局开关回到 false(战斗面板 / 选龟页仍给结论)", SKT.show_formula == false)
	inst._codex_skill_detail = {}
	inst._codex_passive_view = true
	inst._codex_detail._redraw()
	for _i in range(4):
		await get_tree().process_frame
	var texts: Array = []
	_texts_under(inst.detail, texts)
	var brief_lines := 0
	var full := 0
	for t in texts:
		if str(t).begins_with("棱镜每"):
			brief_lines += 1
		if str(t).contains("• 红色"):
			full += 1
	_ok("⑤ 分母: 被动全文真画出来了", full >= 1, "全文 %d 段" % full)
	_ok("⑤ ★展开后简述行不再同时出现", brief_lines == 0, "简述 %d 行" % brief_lines)

	inst.queue_free()
	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 龟技能文案默认给结论 (%d/%d)" % [_n, _n])
	get_tree().quit(1 if _fail > 0 else 0)
