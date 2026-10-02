extends Node

## verify_glossary.gd — 【专名】解释行 (2026-10-01)
##
## 【由来】用户 2026-10-01 拍板「要，加在详细说明底部」。依据是实读 LoL 692 条 tooltip
## 的结论（`docs/plans/ref/20260930-LoL文案体例.md` §6.1）：展开后的详细版底部有一行专名解释。
## 我们一直用【】标专名，而**从来没有任何地方解释它是什么**。
##
## 【守什么】
##   ① 玩家文案里出现的每个【X】**都必须有出处** —— 漏一个，解释行就当着玩家的面跳过它。
##      ★★2026-10-02 从「只认一类」升级成**三类合法出处**（因为这天把 19 个原来写成
##        「X」的专名并进了【】，而它们里头只有 6 个该进解释表）：
##          (a) 在 `Glossary.TERMS` ⇒ 底部出一行解释
##          (b) **就地定义** `【X】：` 后面紧跟着就是解释 ⇒ 底部不必抄第二遍
##              （`terms_in` 2026-10-01 就有这条豁免，是**这条门禁的正则没跟上**）
##          (c) **引用另一个技能/装备的真名字** ⇒ 它自己那张卡就是解释，再抄一份只会撑长面板
##        ⚠ 三类各配一条**分母断言**：某一类命中 0 个，那一支就是空检查。
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


## 数据里**所有技能/装备的真名字** —— 判定 (c) 那一类用。
## ★不另立手写名单：手抄的副本必然落后（memory `fb-hand-rolled-copies-drift`）。
## 判据就是「这个【X】是不是 json 里某个 name」，名字改了这条自动跟着走。
func _all_names() -> Dictionary:
	var out: Dictionary = {}
	for path in ["res://data/phase2-equipment.json", "res://data/pets.json"]:
		var txt := FileAccess.get_file_as_string(path)
		if txt == "":
			continue
		var parsed = JSON.parse_string(txt)
		if parsed != null:
			_walk_names(parsed, out)
	return out


func _walk_names(node, out: Dictionary) -> void:
	if node is Dictionary:
		for k in (node as Dictionary):
			var v = (node as Dictionary)[k]
			if v is String and (str(k) == "name" or str(k) == "title"):
				var s := str(v).strip_edges()
				if s != "":
					out[s] = true
			else:
				_walk_names(v, out)
	elif node is Array:
		for v in (node as Array):
			_walk_names(v, out)


func _ready() -> void:
	var copy := _all_copy()
	print("  [分母] 玩家文案段落 %d 段 / 解释表词条 %d 个" % [copy.size(), Glossary.TERMS.size()])
	_ok("★分母: 真的读到文案(0 段则下面全是空检查)", copy.size() >= 300, "只有 %d 段" % copy.size())
	if copy.size() < 300:
		_finish()
		return

	# 文案里用到的全部【X】。★正则多抓一组：】后面紧跟的那个全角冒号(就地定义的标志)。
	var re := RegEx.create_from_string("【([^】]{1,12})】(：)?")
	var used: Dictionary = {}
	var _def_inplace: Dictionary = {}       # 至少出现过一次「【X】：」的
	for s in copy:
		for m in re.search_all(s):
			var k := m.get_string(1)
			used[k] = int(used.get(k, 0)) + 1
			if m.get_string(2) == "：":
				_def_inplace[k] = true
	print("  [分母] 文案里出现的【专名】共 %d 个 / %d 次" % [used.size(), _sum(used)])
	_ok("★分母: 真的扫到专名", used.size() >= 10, "只有 %d 个" % used.size())

	# ① 每个【X】都得有出处 —— 三类之一
	var names := _all_names()
	var by_terms: Array[String] = []
	var by__def_inplace: Array[String] = []
	var by_name: Array[String] = []
	var missing: Array[String] = []
	for k in used:
		if Glossary.TERMS.has(k):
			by_terms.append(str(k))
		elif _def_inplace.has(k):
			by__def_inplace.append(str(k))
		elif names.has(k):
			by_name.append(str(k))
		else:
			missing.append("【%s】×%d" % [k, int(used[k])])
	print("  [分母] 出处分布: 解释表 %d · 就地定义 %d · 引用真名字 %d · 没出处 %d  (数据里的真名字共 %d 个)"
		% [by_terms.size(), by__def_inplace.size(), by_name.size(), missing.size(), names.size()])
	_ok("★文案里每个【专名】都有出处(解释表 / 就地定义 / 引用另一个技能的真名字)",
		missing.is_empty(), str(missing))
	## ★★三条分母 —— 某一类命中 0 个, 上面那条就有一支是空检查, 而它照样会绿。
	_ok("★分母(a): 真有专名走【解释表】这一支", by_terms.size() >= 10,
		"只有 %d 个: %s" % [by_terms.size(), str(by_terms)])
	_ok("★分母(b): 真有专名走【就地定义】这一支", by__def_inplace.size() >= 1,
		"%d 个 —— 0 的话 `【X】：` 这条豁免等于没被量过: %s" % [_def_inplace.size(), str(_def_inplace.keys())])
	_ok("★分母(c): 真有专名走【引用真名字】这一支", by_name.size() >= 5,
		"只有 %d 个: %s" % [by_name.size(), str(by_name)])
	_ok("★分母: 真的读到了数据里的名字(0 个会让 (c) 那一支永远走不到)", names.size() >= 100,
		"只有 %d 个" % names.size())

	# ①b ★解释文本**自己**引用的【X】也必须有出处 —— 2026-10-02 加。
	## 【由来】这天新写 6 条词条时，我顺手在解释里写了「海胆叠满【硬化】时…」
	##   与「受到的【灼烧】全部改判成真实伤害」——**【硬化】【灼烧】两个都没登记、也不是技能名**。
	##   玩家点开看到的就是一个带括号却没有任何解释的词，等于**解释行里又生出一个新谜语**。
	##   抓到它的不是任何断言，是 `tools/text_golden.py` 把新增的屏幕文案逐条列出来给我看见的。
	## ★★顺带: 那句话还用了「叠满」—— 正是 2026-10-01 刚从文案里清零的口语词。
	##   解释表是**后来加的新表**，前面清过的规矩没有自动覆盖到它。
	var dangling: Array[String] = []
	var n_ref := 0
	var re2 := RegEx.create_from_string("【([^】]{1,12})】")
	for k in Glossary.TERMS:
		for m in re2.search_all(str(Glossary.TERMS[k])):
			n_ref += 1
			var r := m.get_string(1)
			if not (Glossary.TERMS.has(r) or names.has(r)):
				dangling.append("【%s】的解释引用了【%s】" % [str(k), r])
	print("  [分母] 解释文本里的交叉引用【X】共 %d 处" % n_ref)
	_ok("★分母: 解释里真的有交叉引用(0 处 ⇒ 下一条是空检查)", n_ref >= 2, "只有 %d 处" % n_ref)
	_ok("★解释文本自己引用的【X】也得有出处(否则解释行里又生出一个没人解释的谜语)",
		dangling.is_empty(), str(dangling))
	## ★解释表是后加的新表 —— 前面在文案上清过的口语词规矩不会自动覆盖到它。
	var oral: Array[String] = []
	for w in ["叠满", "攒满", "炸开", "攒到", "攒够", "打满"]:
		for k in Glossary.TERMS:
			if str(Glossary.TERMS[k]).contains(w):
				oral.append("【%s】: %s" % [str(k), w])
	_ok("★解释文本也不许用那几个口语词(2026-10-01 在文案里清零的那批)", oral.is_empty(), str(oral))

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
