extends Node

## verify_equip_text_bb.gd — 装备文案接上龟技能那条渲染管线 (2026-10-01·两层渲染 P2)
##
## 【由来】用户 2026-09-30「要统一吧，按新的学习的语术来，包括装备和技能」。
## 在这之前**只有龟技能**走 `render_bbcode`（颜色 + 词前内联属性图标），装备侧只展开
## `{C:}` 占位符 ⇒ 同一个「魔法伤害」，龟技能里是青蓝带图标、装备里是一片白字。
##
## 【守什么】
##   ① 带色的那版真的带色了（分母: 96 件里有多少件至少上到一处色）
##   ② **纯文本那版不许混进 BBCode 标记** —— 它喂的是 Label 与 `tooltip_text`，
##      那两个不吃 BBCode，混进去玩家会看到字面的 `[color=#xxxxxx]`
##   ③ 两版的**文字内容逐字相同** —— 这条管线只加颜色与图标，一个字都不改
##   ④ 没有 `{C:}` 残留、没有 `<span`/`<img` 漏到玩家眼前
##   ⑤ ★方案书 §5.9 担心的事：文案里若出现 `[` `]` 会被 BBCode 当标记吃掉。
##      2026-10-01 实测全库 0 条 —— 但那是**当时**的事实，所以焊一条判据在这里。

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


## 把 BBCode 标记剥掉, 只留文字 —— 用来证明"只加标记不改字"。
func _strip_bb(s: String) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		if s[i] == "[":
			var j := s.find("]", i)
			if j < 0:
				out += s.substr(i)
				break
			var tag := s.substr(i + 1, j - i - 1)
			# [img …]路径[/img] 整段都不是文字, 连里面的路径一起丢掉
			if tag.begins_with("img"):
				var k := s.find("[/img]", j)
				i = (k + 6) if k >= 0 else (j + 1)
				continue
			i = j + 1
			continue
		out += s[i]
		i += 1
	return out


func _ready() -> void:
	var eqs: Array = DataRegistry.phase2_equipment
	print("  [分母] 装备共 %d 件" % eqs.size())
	_ok("★分母: 真的读到装备(0 件则下面全是空检查)", eqs.size() >= 90, "只有 %d 件" % eqs.size())
	if eqs.size() < 90:
		_finish()
		return

	var n_colored := 0
	var n_icon := 0
	var bad_plain: Array[String] = []
	var bad_text: Array[String] = []
	var left_const: Array[String] = []
	var html_leak: Array[String] = []
	var brackets: Array[String] = []
	for e in eqs:
		var ed: Dictionary = e
		var nm: String = str(ed.get("name", ed.get("id", "?")))
		var plain: String = SkillText.equip_full(ed)
		var bb: String = SkillText.equip_full_bb(ed, 20)
		if plain == "":
			continue
		# ① 上色覆盖
		if bb.contains("[color="):
			n_colored += 1
		if bb.contains("[img"):
			n_icon += 1
		# ② 纯文本版不许有 BBCode 标记(它喂 Label / tooltip_text)
		if plain.contains("[color=") or plain.contains("[img") or plain.contains("[b]"):
			bad_plain.append(nm)
		# ③ 只加标记不改字
		if _strip_bb(bb) != plain:
			bad_text.append(nm)
		# ④ 残留
		if bb.contains("{C:") or plain.contains("{C:"):
			left_const.append(nm)
		if bb.contains("<span") or bb.contains("<img") or plain.contains("<span"):
			html_leak.append(nm)
		# ⑤ 源文案里的方括号会被 BBCode 吃掉
		for f in ["effectBrief", "effectDesc1", "effectDesc2", "effectDesc3"]:
			var raw: String = str(ed.get(f, ""))
			if raw.contains("[") or raw.contains("]"):
				brackets.append("%s.%s" % [nm, f])

	print("  [分母] 上到色的 %d 件 / 插了内联图标的 %d 件" % [n_colored, n_icon])
	_ok("★大多数装备文案真的上到了色(0 件 = 管线没接上, 而上面那些检查照样全绿)",
		n_colored >= int(eqs.size() * 0.6), "只有 %d 件" % n_colored)
	_ok("★至少有一批插上了内联属性图标", n_icon >= 20, "只有 %d 件" % n_icon)
	_ok("★纯文本版不许混进 BBCode 标记(它喂 Label 与 tooltip_text, 那两个不吃 BBCode)",
		bad_plain.is_empty(), str(bad_plain))
	_ok("★带色版剥掉标记后与纯文本版【逐字相同】(这条管线只加颜色与图标, 不改字)",
		bad_text.is_empty(), str(bad_text))
	_ok("★没有 {C:} 占位符残留", left_const.is_empty(), str(left_const))
	_ok("★没有 <span>/<img> 这类 HTML 漏给玩家", html_leak.is_empty(), str(html_leak))
	_ok("★源文案里没有方括号(有的话会被 BBCode 当标记吃掉 —— 方案书 §5.9)",
		brackets.is_empty(), str(brackets))

	# ── 简述那一路同样要过 ──
	var nb := 0
	var bad_b: Array[String] = []
	for e in eqs:
		var ed: Dictionary = e
		var pb: String = SkillText.equip_brief(ed)
		if pb == "":
			continue
		nb += 1
		if _strip_bb(SkillText.equip_brief_bb(ed, 15)) != pb:
			bad_b.append(str(ed.get("name", "?")))
	print("  [分母] 有简述的 %d 件" % nb)
	_ok("★分母: 简述这一路真的有东西可比", nb >= 90, "只有 %d 件" % nb)
	_ok("★简述的带色版剥掉标记后也与纯文本逐字相同", bad_b.is_empty(), str(bad_b))

	_finish()


func _finish() -> void:
	print("ALL PASS — 装备文案与龟技能同一条渲染管线" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
