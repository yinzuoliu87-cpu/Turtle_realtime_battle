extends Node
## verify_brief_dedup.gd — 图鉴里「简述+全文」不许把同一件事写两遍 (2026-08-31)
##
## ★由来: 用户 2026-08-31 在图鉴看到辣椒的效果区写了两遍(简述一行 + 全文一段,
##   而两者几乎是同一句话)。渲染层本来就有防重, 但它只挡【一字不差】,
##   "差几个字"的全漏过去了。
##
## ★判据用两个【有人话含义】的条件, 不用相似度分数(那个没有干净的分界线):
##   ① 简述没更短(≥ 全文 75%) ② 简述没说新东西(被覆盖 ≥ 90%) ⇒ 判定重复。
##
## ★★两个方向都要守:
##   · 该合的要合(辣椒这类)
##   · **不该动的不许动**(暴君之牙 27 字简述 vs 128 字全文, 那是真·简述)
##   只写前一半的话, 把 brief_is_redundant 改成永远返回 true 也会绿 —— 那是把功能删了。
const SkillText := preload("res://scripts/util/skill_text.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 图鉴简述去重 ===")
	var eqs: Array = DataRegistry.phase2_equipment
	_ok("★分母: 装备表非空(%d 件)" % eqs.size(), eqs.size() >= 50)

	var dup: Array = []
	var kept: Array = []
	for e in eqs:
		if not (e is Dictionary):
			continue
		var b: String = SkillText.equip_brief(e)
		var f: String = SkillText.equip_full(e)
		if b == "" or f == "":
			continue
		if SkillText.brief_is_redundant(b, f):
			dup.append(str((e as Dictionary).get("name", "?")))
		else:
			kept.append(str((e as Dictionary).get("name", "?")))
	_ok("★分母: 两边都不为空 —— 合 %d 件 / 留 %d 件" % [dup.size(), kept.size()],
		dup.size() >= 1 and kept.size() >= 50,
		"合的: %s" % str(dup))

	## ① 该合的合了
	_ok("① ★★辣椒被判为重复(简述 32 字 vs 全文 39 字, 内容全被覆盖)",
		dup.has("辣椒"), "合的清单: %s" % str(dup))

	## ② ★不该动的没被误伤 —— 这一半才是防"把功能删了"
	_ok("② ★★暴君之牙【不】判重复(它的简述是真·简述: 短得多且全文另有机制)",
		kept.has("暴君之牙"))
	_ok("② ★★绝大多数装备照旧显示两段(合掉的必须是少数)",
		dup.size() <= 10, "合掉了 %d 件, 超过 10 件就说明判据太宽" % dup.size())

	## ③ 判据本身的边界
	_ok("③ 一字不差 → 判重复", SkillText.brief_is_redundant("同一句话。", "同一句话。"))
	_ok("③ 明显更短的简述 → 不判重复(哪怕内容全被覆盖)",
		not SkillText.brief_is_redundant("射出毒牙吸血。",
			"射出毒牙吸血。此外携带者每 6 秒向最近的敌人射出一颗剧毒獠牙，造成大量魔法伤害并回复自身生命。"))
	_ok("③ 一样长但说的是别的事 → 不判重复",
		not SkillText.brief_is_redundant("每 3 秒甩出一道剑气。", "受到伤害时获得护盾层数。"))

	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 8:
		print("  [FAIL] ★分母: 断言只有 %d 条(<8)" % _n)
		_fail += 1
	print("ALL PASS — 图鉴简述去重" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
