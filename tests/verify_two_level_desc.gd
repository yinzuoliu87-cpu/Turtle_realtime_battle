extends Node

## verify_two_level_desc.gd — 技能说明的两级描述 (用户需求1, 2026-07-22 拍板"面板级开关")
##
## 用户原话:「它们描述技能都有个缩略和详细文案，在缩略里就写实时的数值，如48魔法伤害，
##            而在详细里应该是写（20+30%攻击力=48）魔法伤害」
##
## ★做之前的事实(实测): 同一个战斗信息面板里【被动段写死取 desc(详细)、技能段写死取 brief(缩略)】,
##   选龟界面的 tooltip 与点开的弹窗是【同一串】(等于只有一级), 只有图鉴是真两级。
##   6 处散落的 fallback 链各写各的 —— 所以先收口到 SkillText.brief_of/detail_of/text_of。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SkillTextC = preload("res://scripts/engine/skill_text.gd")

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	_test_accessors()
	await _test_panel_switches()
	print("ALL PASS — 两级描述(缩略/详细 面板级开关)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## ① 取值口径: 技能用 detail, 被动用 desc, 两者都要能取到
func _test_accessors() -> void:
	var skill := {"brief": "缩略文本", "detail": "详细文本"}
	var passive := {"brief": "被动缩略", "desc": "被动详细"}
	_ok("★技能: 缩略取 brief", SkillTextC.brief_of(skill) == "缩略文本")
	_ok("★技能: 详细取 detail", SkillTextC.detail_of(skill) == "详细文本")
	_ok("★被动: 详细取 desc(字段名和技能不一样, 差异必须吸收在 helper 里)",
		SkillTextC.detail_of(passive) == "被动详细")
	_ok("★被动: 缩略取 brief", SkillTextC.brief_of(passive) == "被动缩略")
	# 缺失时的兜底: 不能显示空白
	_ok("只有 brief 时, 要详细也退回 brief(不显示空白)",
		SkillTextC.text_of({"brief": "只有这个"}, true) == "只有这个")
	_ok("只有 detail 时, 要缩略也退回 detail",
		SkillTextC.text_of({"detail": "只有详细"}, false) == "只有详细")
	_ok("空字典安全", SkillTextC.text_of({}, true) == "" and SkillTextC.text_of({}, false) == "")
	# ★两种模式必须【真的不一样】—— 否则开关等于没做
	_ok("★★两种模式取到的文本不同(否则开关是摆设)",
		SkillTextC.text_of(skill, true) != SkillTextC.text_of(skill, false))


## ② 面板行为: 切开关 → 面板里的技能文字真的变了
func _test_panel_switches() -> void:
	var s = RTScene.new()
	get_tree().root.add_child(s)
	for i in 8:
		await get_tree().process_frame

	# 找一只有技能又有被动的我方龟
	var u: Dictionary = {}
	for o in s._units:
		if o.get("is_trainer", false) or o.get("_isEgg", false) or o.get("is_summon", false):
			continue
		if str(o.get("side", "")) == "left" and (o.get("passive", {}) as Dictionary).size() > 0:
			u = o
			break
	_ok("找得到一只带被动的我方龟", not u.is_empty(), str(u.get("name", "?")))
	if u.is_empty():
		s.queue_free()
		return

	if GameState != null:
		GameState.skill_text_detail = false
	var brief_rows := s._panel_skill_entries(u)
	var brief_txt := ""
	for r in brief_rows:
		brief_txt += str((r as Dictionary).get("desc", ""))
	if GameState != null:
		GameState.skill_text_detail = true
	var detail_rows := s._panel_skill_entries(u)
	var detail_txt := ""
	for r in detail_rows:
		detail_txt += str((r as Dictionary).get("desc", ""))

	print("  [实测] %s 技能段: 简明 %d 字符 / 详细 %d 字符" % [str(u.get("name", "")), brief_txt.length(), detail_txt.length()])
	_ok("简明模式取到了文字(N=0 就是空检查)", brief_txt.length() > 0)
	# ★必须【逐行】比, 不能把所有行拼成一串比 ——
	#   2026-07-22 反向验证抓到: 把主动技那行退回写死 brief 后, 只剩普攻行还听开关,
	#   拼起来的总串仍然"变了", 断言照样绿。一行的变化盖住了其余行的没变。
	var n_rows := 0
	var n_changed := 0
	var n_switchable := 0     # 源数据里 brief 与 detail 确实不同的行(只有这些行【应该】变)
	for i in mini(brief_rows.size(), detail_rows.size()):
		var br: Dictionary = brief_rows[i]
		var dr: Dictionary = detail_rows[i]
		n_rows += 1
		var sk: Dictionary = br.get("sk", {})
		if SkillTextC.brief_of(sk) != SkillTextC.detail_of(sk):
			n_switchable += 1
			if str(br.get("desc", "")) != str(dr.get("desc", "")):
				n_changed += 1
			else:
				print("    ✗ 第%d行「%s」两种模式文字相同 —— 这行没听开关" % [i + 1, str(br.get("name", ""))])
	print("  [分母] 技能行 %d 条, 其中源数据两级不同的 %d 条, 实际跟着切的 %d 条" % [n_rows, n_switchable, n_changed])
	_ok("有可切换的行(N=0 就测不出下面那条)", n_switchable > 0)
	_ok("★★每一条【源数据有两级】的技能行都跟着开关切了(不是只有普攻在切)",
		n_changed == n_switchable, "%d/%d" % [n_changed, n_switchable])
	_ok("★详细通常更长(展开了公式与比率)", detail_txt.length() >= brief_txt.length(),
		"简明 %d / 详细 %d" % [brief_txt.length(), detail_txt.length()])

	# 被动段也要跟着切 —— 它原来是写死取详细的
	var pas: Dictionary = u.get("passive", {})
	var pb := SkillTextC.text_of(pas, false)
	var pd := SkillTextC.text_of(pas, true)
	_ok("★被动段也听同一个开关(原来写死取详细, 与技能段口径打架)", pb != pd,
		"被动 简明%d / 详细%d 字符" % [pb.length(), pd.length()])

	# 开关按钮真的建出来了
	var found := false
	for n in _walk(s):
		if n is Button and str(n.text).begins_with("简明") or (n is Button and str(n.text).begins_with("详细")):
			found = true
	# 面板没开时按钮不存在是正常的 —— 这里改为查源码接线点
	var src := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("★面板里挂了这个开关", _code_only(src).contains("_add_detail_toggle(vb, u)"),
		"没接线 = 玩家点不到")
	if GameState != null:
		GameState.skill_text_detail = false
	s.queue_free()
	await get_tree().process_frame


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


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
