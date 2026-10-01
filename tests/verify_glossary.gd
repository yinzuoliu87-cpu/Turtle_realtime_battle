extends Node

## verify_glossary.gd — 【专名】解释行 (2026-10-01)
##
## 【由来】用户 2026-10-01 拍板「要，加在详细说明底部」。依据是实读 LoL 692 条 tooltip
## 的结论（`docs/plans/ref/20260930-LoL文案体例.md` §6.1）：展开后的详细版底部有一行专名解释。
## 我们一直用【】标专名，而**从来没有任何地方解释它是什么**。
##
## 【守什么】
##   ① 玩家文案里出现的每个【X】**都必须有解释** —— 漏一个，解释行就当着玩家的面跳过它
##   ② 表里**不许有没人用的词条** —— 删了专名却忘删解释，下一个人会以为游戏里还有这东西
##   ③ `glossary_bb` 只列**这段文字里真的出现过**的词，不是把整张表倒出来
##   ④ 消费点真的接上了（源码扫描：详细说明那几处必须调过 `glossary_bb`）
##
## ★★为什么 ② 要守：这类「写了没人读 / 读了没人写」的缺口在本仓已经吃过多次
##   （memory `fb-zero-caller-is-a-whole-class`）。一张只增不减的解释表迟早会描述
##   一个**早就不存在**的机制，而那比没有解释更糟。

const TEXT_KEYS := ["brief", "desc", "detail", "effectBrief", "effectDesc1", "effectDesc2", "effectDesc3"]

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


## 把两份 json 里**玩家看得到的**文案全捞出来 —— 递归整棵树, 不按我以为的层级走。
func _all_copy() -> Array[String]:
	var out: Array[String] = []
	for path in ["res://data/phase2-equipment.json", "res://data/pets.json"]:
		var txt := FileAccess.get_file_as_string(path)
		if txt == "":
			continue
		var parsed = JSON.parse_string(txt)
		if parsed == null:
			continue
		_walk(parsed, out)
	return out


func _walk(node, out: Array[String]) -> void:
	if node is Dictionary:
		for k in (node as Dictionary):
			var v = (node as Dictionary)[k]
			if v is String and TEXT_KEYS.has(str(k)):
				out.append(str(v))
			else:
				_walk(v, out)
	elif node is Array:
		for v in (node as Array):
			_walk(v, out)


func _ready() -> void:
	var copy := _all_copy()
	print("  [分母] 玩家文案段落 %d 段 / 解释表词条 %d 个" % [copy.size(), Glossary.TERMS.size()])
	_ok("★分母: 真的读到文案(0 段则下面全是空检查)", copy.size() >= 300, "只有 %d 段" % copy.size())
	if copy.size() < 300:
		_finish()
		return

	# 文案里用到的全部【X】
	var re := RegEx.create_from_string("【([^】]{1,12})】")
	var used: Dictionary = {}
	for s in copy:
		for m in re.search_all(s):
			used[m.get_string(1)] = int(used.get(m.get_string(1), 0)) + 1
	print("  [分母] 文案里出现的【专名】共 %d 个 / %d 次" % [used.size(), _sum(used)])
	_ok("★分母: 真的扫到专名", used.size() >= 10, "只有 %d 个" % used.size())

	# ① 每个都有解释
	var missing: Array[String] = []
	for k in used:
		if not Glossary.TERMS.has(k):
			missing.append("【%s】×%d" % [k, int(used[k])])
	_ok("★文案里每个【专名】都有解释(漏一个, 解释行就当着玩家的面跳过它)",
		missing.is_empty(), str(missing))

	# ② 没有孤儿词条
	var orphan: Array[String] = []
	for k in Glossary.TERMS:
		if not used.has(k):
			orphan.append(str(k))
	_ok("★解释表里没有【没人用】的词条(删了专名忘删解释 ⇒ 描述一个早就不存在的机制)",
		orphan.is_empty(), str(orphan))

	# ③ 只列真的出现过的
	var one := "登场后进入【涨潮】；结束时【退潮】。"
	var t1 := Glossary.terms_in(one)
	_ok("★terms_in 只列这段里真出现的词",
		t1.size() == 2 and t1[0] == "涨潮" and t1[1] == "退潮", str(t1))
	_ok("★没有专名的文案 ⇒ 不产出解释行(别无条件拼一个空块)",
		SkillText.glossary_bb("这段里一个专名都没有。", 17) == "")
	var bb := SkillText.glossary_bb(one, 17)
	_ok("★有专名 ⇒ 解释行里带着那两个词与它们的解释",
		bb.contains("【涨潮】") and bb.contains("【退潮】")
			and bb.contains(str(Glossary.TERMS["涨潮"])), bb.substr(0, 60))
	_ok("★解释行是灰字(走 UIPalette.DIM, 不是现拍一个灰)", bb.contains(UIPalette.DIM))

	## ★★「就地定义」不再抄一遍 —— 这条是**实拍之后**才加的(2026-10-01 双头龟技能一):
	##   正文写「· 远程形态【灵能冲击】：射出一颗紫色炮弹…」, 底部解释行又来一句
	##   「【灵能冲击】双头龟远程形态的技能一：射出一颗炮弹…」—— 同一件事隔三行再说一遍,
	##   而且信息更少(解释行里没有数值)。判据: 专名后面紧跟全角冒号 ⇒ 不解释。
	var inplace := "· 远程形态【灵能冲击】：射出一颗紫色炮弹。"
	_ok("★就地定义(【X】：)不再在底部抄一遍", Glossary.terms_in(inplace).is_empty(),
		str(Glossary.terms_in(inplace)))
	var crossref := "普攻对敌人施加一层【气环】，可叠加 3 层。"
	_ok("★★反面: 跨段引用的(后面跟逗号/句号)照常解释 —— 否则这条可以靠「一律不解释」作弊",
		Glossary.terms_in(crossref).size() == 1, str(Glossary.terms_in(crossref)))

	# ④ 消费点真的接上了
	var wired := {
		"res://scripts/scenes/codex/detail_views.gd": "图鉴(装备详情 + 龟技能/被动详情)",
		"res://scripts/scenes/InventoryScene.gd": "背包细看弹框",
	}
	var unwired: Array[String] = []
	for f in wired:
		if not FileAccess.get_file_as_string(f).contains("glossary_bb"):
			unwired.append("%s(%s)" % [str(f).get_file(), str(wired[f])])
	_ok("★详细说明那几处真的调了 glossary_bb(接线断了, 上面的检查照样全绿)",
		unwired.is_empty(), str(unwired))
	## ★商店与战斗面板**有意不加**: 商店说明框只有 246px, 实测加上之后要滚的从 3 件涨到 7 件。
	##   这不是漏接 —— 是量过之后的取舍, 与 LoL 一致(解释行只在展开的详细版里出现)。
	_ok("★商店说明【有意】不加解释行(246px 框装不下: 实测 3 件 → 7 件要滚)",
		not FileAccess.get_file_as_string("res://scripts/scenes/ShopScene.gd").contains("glossary_bb"))

	_finish()


func _sum(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n


func _finish() -> void:
	print("ALL PASS — 【专名】解释行" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
