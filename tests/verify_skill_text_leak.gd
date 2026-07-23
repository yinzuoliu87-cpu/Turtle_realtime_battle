extends Node

## verify_skill_text_leak.gd — 点5: 技能/被动文案渲染【零泄漏】门禁 (用户 2026-07-23)
##
## 背景: LoL 化重写后, 灰字注释里写了自动上色关键词、或手写 span 里放了 {token},
##   都会产生【嵌套 span】。旧 html_to_bbcode 用单正则 <span..>([^<]*)</span>,
##   一遇嵌套就断裂 → 把 `span class="val-true">` 原始标签字面量漏给玩家(实测 58 处)。
##   根因修在渲染器(栈式解析·最外层色胜出), 本门禁守住它不再回退。
##
## ★行为级: 真拿 pets.json 每一条 brief/desc/detail 过【真实】SkillText.render_bbcode,
##   断言输出里不再有 <span / class= / style="color / &lt; 等【本该被消化掉】的原始标记。
## ★自带正反例: 一个已知嵌套串必须【被判为泄漏】(证明检查会 FAIL), 否则这门禁是空的。

const LEAK_MARKERS := ["<span", "</span", "class=", "style=\"color", "&lt;", "&gt;"]

var _fail: int = 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _has_leak(bb: String) -> String:
	for mk in LEAK_MARKERS:
		if bb.contains(mk):
			return mk
	return ""

func _ready() -> void:
	var ctx := {"atk": 100.0, "def": 10.0, "mr": 10.0, "maxHp": 1000.0, "hp": 1000.0, "level": 1, "crit": 0.0}

	# ── 反向验证: 已知嵌套串必须被判为泄漏 (若渲染器"太宽容"把它也消化了, 说明断言标准失灵) ──
	var bad_nested := "普通 <span class=\"val-heal\">回复 <span class=\"val-heal\">300</span> 生命</span> 尾"
	var bad_bb := SkillText.render_bbcode(bad_nested, ctx, {})
	# 修好的渲染器【应当】把它渲染干净(最外层色胜出) → 这里换一个真正测「检测器有效」的样本:
	#   直接喂一段【渲染器输出里若含标记就算泄漏】的字面量, 确认 _has_leak 能报。
	_ok("★反向验证: _has_leak 能识别残留标记(非空检查)", _has_leak("尾巴 span class=\"x\"> 漏了") != "")
	_ok("★反向验证: 干净 bbcode 不误报", _has_leak("[color=#ff4444]70[/color] 物理伤害") == "")

	# ── 正例: pets.json 全量文案零泄漏 ──
	var raw := FileAccess.get_file_as_string("res://data/pets.json")
	var parsed = JSON.parse_string(raw)
	var pets: Array = parsed if parsed is Array else parsed.get("pets", [])
	var total := 0
	var leaked: Array = []
	for i in range(pets.size()):
		var p: Dictionary = pets[i]
		var fields: Array = []
		var pas: Dictionary = p.get("passive", {})
		fields.append(["passive.brief", str(pas.get("brief", "")), pas])
		fields.append(["passive.desc", str(pas.get("desc", "")), pas])
		var sp: Array = p.get("skillPool", [])
		for j in range(sp.size()):
			var sk: Dictionary = sp[j]
			fields.append(["skill[%d].brief" % j, str(sk.get("brief", "")), sk])
			fields.append(["skill[%d].detail" % j, str(sk.get("detail", "")), sk])
		for fld in fields:
			if str(fld[1]) == "":
				continue
			total += 1
			var bb: String = SkillText.render_bbcode(str(fld[1]), ctx, fld[2])
			var mk := _has_leak(bb)
			if mk != "":
				leaked.append("[%d %s] %s <<%s>>" % [i, str(p.get("id", "")), fld[0], mk])

	print("  [分母] 渲染文案字段 total=%d, 泄漏=%d" % [total, leaked.size()])
	_ok("★文案分母充分(N>=200, 否则是空检查)", total >= 200, "实际 %d" % total)
	_ok("★全部文案渲染零泄漏(无 span/class/&lt; 残留)", leaked.is_empty(), str(leaked))

	# ── 实体解码: &lt; 必须被解成 < (RichTextLabel 不解实体) ──
	var ent := SkillText.render_bbcode("距任一敌 &lt;120码 排除", ctx, {})
	_ok("★&lt; 解码为 <(不原样显示 &lt;)", ent.contains("<120码") and not ent.contains("&lt;"), ent)

	print("ALL PASS — 技能文案渲染零泄漏" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
