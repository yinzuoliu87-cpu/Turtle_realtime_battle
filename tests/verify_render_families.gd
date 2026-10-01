extends Node

## verify_render_families.gd — 渲染语义族的覆盖率 (2026-10-02)
##
## 【由来】用户 2026-09-30:「按新版 lol 再去截图别人游戏内的技能描述，因为**人家用到了属性图标，
## 伤害类型还会渲染**，你找图去学习，最少 150 个不同技能描述，包括简略和详细的」。
##
## ★我上一轮只读了**数据层的文字**，并且只统计了 3 个伤害类型标签（852 个），
##   **漏掉了另外 27 种渲染标签** —— 而那些才是「属性图标 + 伤害类型渲染」的真来源。
##   2026-10-02 重抓 LoL 16.19.1：**860 条技能 / 172 个英雄 / 688 条有详细版**，全标签统计：
##     keywordMajor(专名) 308 · status(控制) 509 · spellName(引用技能名) 129 ·
##     speed 129 · recast 113 · healing 107 · spellPassive 90 · shield 76 · spellActive 74 ·
##     attackSpeed 63 · scaleArmor 42 · scaleMR 33 · trueDamage 28 …
##
## 【这条门禁守什么】**我们自己文案里的这两族，必须真的被渲染出颜色**：
##   ① 专名【X】—— 全库 39 处，原来一个字都没上色
##   ② 控制/状态 —— 全库 140 处，原来只有「眩晕」31 处有色，另 109 处是裸字
##
## ★判据量的是 `render_bbcode` 的**真实输出**（产品自己的账），不是数我插的标记。

const CC_WORDS := ["眩晕", "击飞", "击退", "减速", "嘲讽", "定身", "束缚", "沉默", "缴械", "时停"]

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	var f := {"atk": 100.0, "def": 20.0, "mr": 20.0, "maxHp": 1000.0}

	# ── ① 专名上色 ──
	var bb1: String = SkillText.render_bbcode("登场后进入【涨潮】，结束时【退潮】。", f, {})
	print("  [分母] 专名样本渲染结果: ", bb1)
	_ok("★【X】被渲染成专名色(UIPalette.KEYWORD)",
		bb1.count("[color=" + UIPalette.KEYWORD + "]") == 2, bb1)
	_ok("★分母: 专名色不是空串(拼错常量名会让上一条恒真)", UIPalette.KEYWORD.length() == 7,
		UIPalette.KEYWORD)
	## ★反面: 没有【】的句子不许凭空多出专名色 —— 否则规则写宽了, 整段都会被染。
	var bb1n: String = SkillText.render_bbcode("这句话里一个专名都没有。", f, {})
	_ok("★★反面: 没有【】就不该出现专名色(规则写宽了会把整段染掉)",
		not bb1n.contains(UIPalette.KEYWORD), bb1n)

	# ── ② 控制/状态成类 ──
	var miss: Array[String] = []
	for w in CC_WORDS:
		var bb: String = SkillText.render_bbcode("对目标造成 %s 效果。" % w, f, {})
		if not bb.contains("[color=" + str(SkillText.VAL_HEX["val-stun"]) + "]" + w):
			miss.append(w)
	print("  [分母] 受检控制词 %d 个" % CC_WORDS.size())
	_ok("★分母: 控制词表非空(空表会让下一条恒真)", CC_WORDS.size() >= 8)
	_ok("★每个控制/状态词都归到同一个色(LoL 把 509 处 status 全归一色, 我们照这个思路)",
		miss.is_empty(), "没上色的: %s" % str(miss))
	## ★反面: 不是控制词的普通词不许被染成控制色。
	var bb2n: String = SkillText.render_bbcode("对目标造成伤害。", f, {})
	_ok("★★反面: 普通句子不许出现控制色",
		not bb2n.contains("[color=" + str(SkillText.VAL_HEX["val-stun"]) + "]"), bb2n)

	# ── ③ 真实文案抽样: 这两族在全库里确实被用到(不是只在我造的句子里成立) ──
	var n_kw := 0
	var n_cc := 0
	var n_seg := 0
	for e in DataRegistry.phase2_equipment:
		var ed: Dictionary = e
		var s: String = SkillText.equip_full_bb(ed, 17)
		if s == "":
			continue
		n_seg += 1
		if s.contains("[color=" + UIPalette.KEYWORD + "]"):
			n_kw += 1
		if s.contains("[color=" + str(SkillText.VAL_HEX["val-stun"]) + "]"):
			n_cc += 1
	print("  [分母] 装备文案 %d 段: 出现专名色 %d 段 · 出现控制色 %d 段" % [n_seg, n_kw, n_cc])
	_ok("★分母: 真扫到装备文案", n_seg >= 90, "只有 %d 段" % n_seg)
	_ok("★真实文案里确实有段落被染上专名色", n_kw >= 5, "只有 %d 段" % n_kw)
	_ok("★真实文案里确实有段落被染上控制色", n_cc >= 5, "只有 %d 段" % n_cc)

	print("ALL PASS — 渲染语义族(专名 / 控制)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
