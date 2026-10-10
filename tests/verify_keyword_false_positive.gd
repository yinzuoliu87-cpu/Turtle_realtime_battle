extends Node

## verify_keyword_false_positive.gd — 关键词自动上色不许误伤「含有关键词的别的词」(2026-10-10)
##
## 【由来】052 左轮手枪「子弹为 0 时停止射击」里的「时停」被 KEYWORD_RULES 染成控制色,
##   读起来像这件装备会时停。中文没有词边界, 规则按子串匹配, 「时 + 停止」就中招了。
##   同一形状还有「魔法波」(双头龟融合技, 打的是物理/真实伤害)、「魔法光线」(水晶球)。
##
## ★全库扫描在 `tools/keyword_false_positive_audit.py`(Python 复刻管线, 进门禁)。
##   这条测试守的是**引擎里真跑的 PCRE2** 与那份复刻在这几处上一致 ——
##   Python `re` 与 Godot RegEx 是两套实现, 审计器绿不代表游戏里也绿。
##   判据量的是 `colorize_keywords` / `equip_full_bb` 的**真实输出**, 不是数我加的标记。

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


## 这段 HTML 里, 「word」有没有被某个 class 的 span 直接包住(或以它开头被包住)
func _wrapped(html: String, cls: String, word: String) -> bool:
	return html.contains("<span class=\"%s\">%s" % [cls, word])


func _ready() -> void:
	## ── ① 误伤消失 ──
	var h1 := SkillText.colorize_keywords("子弹为 0 时停止射击，装备不会消失。")
	print("  [样本] ", h1)
	_ok("「时停止」里的「时停」不上控制色", not _wrapped(h1, "val-stun", "时停"), h1)
	var h2 := SkillText.colorize_keywords("主动释放魔法波，每段在物理与真实伤害之间交替。")
	_ok("「魔法波」里的「魔法」不上魔法色", not _wrapped(h2, "val-magic", "魔法"), h2)
	var h3 := SkillText.colorize_keywords("射出一道贯穿直线的魔法光线，造成魔法伤害。")
	_ok("「魔法光线」里的「魔法」不上魔法色", not _wrapped(h3, "val-magic", "魔法光线")
		and not h3.contains("<span class=\"val-magic\">魔法</span>光线"), h3)

	## ── ② 真命中一个不丢(反向: 证明上面不是因为规则整个失效才"不上色") ──
	var t1 := SkillText.colorize_keywords("触发时停，敌人全部静止。")
	_ok("★真命中: 「触发时停」仍上控制色", _wrapped(t1, "val-stun", "时停"), t1)
	_ok("★真命中: 同句里「魔法光线」后面的「魔法伤害」仍上魔法色", _wrapped(h3, "val-magic", "魔法伤害"), h3)
	var t2 := SkillText.colorize_keywords("伤害类型在物理与魔法之间逐次交替。")
	_ok("★真命中: 「物理与魔法之间」的「魔法」仍上魔法色", _wrapped(t2, "val-magic", "魔法"), t2)
	var t3 := SkillText.colorize_keywords("获得 25% 的魔法护盾，该护盾只吸收魔法伤害。")
	_ok("★真命中: 「魔法护盾」(只吸收魔法伤害) 的「魔法」仍上魔法色", _wrapped(t3, "val-magic", "魔法"), t3)

	## ── ③ 产品真实入口: 052 左轮手枪的商店/图鉴全文 ──
	var ed: Dictionary = DataRegistry.phase2_equipment_by_id.get("p2eq_052", {})
	_ok("★分母: 取到 052 左轮手枪", not ed.is_empty())
	var bb := SkillText.equip_full_bb(ed, 17)
	_ok("★分母: 052 全文里真有「时停止」这三个字(否则下面那条是空检查)", bb.contains("时停止"), bb)
	var stun_hex := str(SkillText.VAL_HEX["val-stun"])
	_ok("052 全文里「时停」前面没有控制色", not bb.contains("[color=%s]时停" % stun_hex), bb)

	print("ALL PASS — 关键词上色不误伤别的词" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
