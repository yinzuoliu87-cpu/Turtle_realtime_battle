extends RefCounted
## 图鉴·「同一个技能槽随形态换招」的龟(双头龟)→ 按形态拆成两份技能池, 供形态切换钮用。
##
## ★由来(2026-10-10 图鉴体检): 双头龟的技能一 / 技能二在战斗里是**同一槽位随形态变招**
##   (远程放灵能冲击、近战放锤击; 远程放精神干扰、近战放吸收 —— `TwoHeadSystem` 按 `u.two_form` 分派),
##   pets.json 把两招写在一条里: 名字「灵能冲击/锤击」、简述两行各讲一种形态。图鉴原样印出来 ⇒
##   卡名是两个名字拼一起、正文一张卡讲两套。熔岩龟早有形态切换钮(volcanoSkills), 双头龟没有。
## ★不在 pets.json 里另抄一份「远程版 / 近战版」—— 战斗、选技界面读的都是合写的那条,
##   另抄一份就是两份文案(memory: 手抄的副本必然落后)。这里**从合写的那一条现拆**:
##   · 名字: 「远程名/近战名」按「/」拆(顺序与简述、详述里的先远程后近战一致; 门禁对过详述里的【名字】)
##   · 简述 / 详述: 逐行认「远程形态」「近战形态」; 详述里「· 远程形态【X】：」起一段, 灰字尾注回到公共段。
##   两种形态都没提到的行(融合整张、尾注)两边都留。
## 门禁: tests/verify_codex_two_head_forms.gd

const FORMS := ["远程形态", "近战形态"]
## 详述里分段的标记行: 「· 远程形态【灵能冲击】：」
const _MARK_HEAD := "· "
## 回到公共段的灰字尾注(双头龟两条变招技的末尾都是它)
const _TAIL_OPEN := "<span style=\"color:#8a93a0\">"


## 这条技能是不是「随形态变招」: 简述里两种形态都写到。
static func is_variant(sk: Variant) -> bool:
	if not (sk is Dictionary):
		return false
	var b: String = str((sk as Dictionary).get("brief", ""))
	return b.contains(FORMS[0]) and b.contains(FORMS[1])


## 这只龟有没有随形态变招的技能(普攻那条只是「随形态变化」不算 —— 只看槽位 ≥1 的技能)。
static func has_variants(pet: Dictionary) -> bool:
	var sp: Variant = pet.get("skillPool", [])
	if not (sp is Array):
		return false
	for i in range(1, (sp as Array).size()):
		if is_variant((sp as Array)[i]):
			return true
	return false


## 某一形态(0 = 远程 / 1 = 近战)下的技能池。变招技换成那一形态的名字 / 简述 / 详述; 其余原样(同一个字典)。
## 拆出来的字典带 `_base` = pets.json 里那一条 —— 角色 / 龟能 / 默认技判定都按它认(图鉴 detail_views._base_of)。
static func pool(pet: Dictionary, form: int) -> Array:
	var out: Array = []
	var sp: Variant = pet.get("skillPool", [])
	if not (sp is Array):
		return out
	for sk in (sp as Array):
		if not is_variant(sk):
			out.append(sk)
			continue
		var v: Dictionary = (sk as Dictionary).duplicate()
		v["_base"] = sk
		v["name"] = form_name(sk, form)
		v["brief"] = form_text(str((sk as Dictionary).get("brief", "")), form)
		v["detail"] = form_text(str((sk as Dictionary).get("detail", "")), form)
		out.append(v)
	return out


## 「灵能冲击/锤击」→ 远程「灵能冲击」/ 近战「锤击」。没有「/」就原名。
static func form_name(sk: Dictionary, form: int) -> String:
	var nm: String = str(sk.get("name", ""))
	var parts: PackedStringArray = nm.split("/")
	if parts.size() == FORMS.size():
		return parts[form].strip_edges()
	return nm


## 详述里各形态那一段标记的【名字】(「· 远程形态【灵能冲击】：」→ 灵能冲击); 没有就空串。门禁拿它对 form_name。
static func marked_name(detail: String, form: int) -> String:
	for ln in detail.split("\n"):
		var t: String = ln.strip_edges()
		if t.begins_with(_MARK_HEAD + FORMS[form] + "【"):
			var a: int = t.find("【")
			var b: int = t.find("】", a)
			if b > a:
				return t.substr(a + 1, b - a - 1)
	return ""


## 一段文字只留某一形态: 另一形态的行去掉, 本形态那行去掉「远程形态」这类开头(卡名已经说了是哪招)。
static func form_text(txt: String, form: int) -> String:
	var mine: String = FORMS[form]
	var other: String = FORMS[1 - form]
	var section: String = ""   # "" = 公共段; 否则 = 当前在哪个形态的分段里
	var out: PackedStringArray = []
	for ln in txt.split("\n"):
		var t: String = ln.strip_edges()
		var mk: String = _section_of(t)
		if mk != "":
			section = mk
			continue
		if t.begins_with(_TAIL_OPEN):
			section = ""
		## 「双头龟技能一，随形态变体：」这种总起句: 拆开之后只剩一种形态, 它就不成立了。
		if t.ends_with("随形态变体：") and section == "":
			continue
		if section != "":
			if section == mine:
				out.append(ln)
			continue
		var hm: bool = ln.contains(mine)
		var ho: bool = ln.contains(other)
		if hm and not ho:
			out.append(_strip_lead(ln, mine))
		elif ho and not hm:
			continue
		else:
			out.append(ln)
	return "\n".join(out)


static func _section_of(t: String) -> String:
	for f in FORMS:
		if t.begins_with(_MARK_HEAD + f + "【") and t.ends_with("："):
			return f
	return ""


## 「远程形态释放灵能冲击，…」→「释放灵能冲击，…」; 「普通攻击随形态变化：远程形态射出灵能弹，…」→「射出灵能弹，…」。
## 形态词前面若不是一句以「：」收尾的总起, 原样留着(不猜)。
static func _strip_lead(ln: String, form_word: String) -> String:
	var i: int = ln.find(form_word)
	var head: String = ln.substr(0, i)
	if head.strip_edges() == "" or head.strip_edges().ends_with("："):
		return ln.substr(i + form_word.length())
	return ln

## 立绘: 近战形态页换成战斗近战形态那张图(取 TwoHeadSystem.FORM_ART, 不另写路径); 其余原样返回同一个字典。
static func portrait_pet(pet: Dictionary, melee_view: bool) -> Dictionary:
	if not melee_view or not has_variants(pet):
		return pet
	var art: String = str(TwoHeadSystem.FORM_ART.get("melee", ""))
	if art == "" or not ResourceLoader.exists(art):
		return pet
	var d: Dictionary = pet.duplicate()
	d["img"] = art.trim_prefix("res://assets/sprites/")
	return d
