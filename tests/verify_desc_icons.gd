extends Node
## verify_desc_icons.gd — 描述内联属性图标 (用户2026-07-24: 选A·只真属性加图标, 图标紧贴属性词前)
## SkillText.render_bbcode 在【真属性关键词】前插一枚 [img] 属性图标; 伤害类型/DoT/控制词不插。

const SkillText = preload("res://scripts/engine/skill_text.gd")

var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	var f := {"atk": 58, "def": 20, "mr": 19, "maxHp": 1370, "crit": 0.25}
	var s := {"atkScale": 3.5}
	var tpl := "造成 {N:3.5*ATK} 物理伤害并附带 25% 暴击率、10% 生命偷取；装备 +40 攻击力、+8 护甲、+300 最大生命值、+15% 攻击速度、+30 移动速度、+150 射程"
	var bb := SkillText.render_bbcode(tpl, f, s)
	print("  渲染BBCode: ", bb)

	# ① 真属性 → 词前有对应图标
	for kw in [["攻击力", "atk"], ["护甲", "def"], ["最大生命值", "hp"], ["暴击率", "crit"],
			["生命偷取", "lifesteal"], ["攻击速度", "aspd"], ["移动速度", "move"], ["射程", "range"]]:
		var icon: String = "%s-icon.png" % kw[1]
		var ip: int = bb.find(icon)
		var wp: int = bb.find(kw[0])
		_ok("★%s 前内联了 %s 图标" % [kw[0], kw[1]], ip >= 0 and ip < wp and (wp - ip) < 80, "img@%d word@%d" % [ip, wp])

	# ② 伤害类型词【不】加图标(选A) —— atk 图标只应出现在 攻击力(1次), 不出现在 物理伤害
	_ok("★「物理伤害」不加图标(选A·伤害类型保持彩字)", bb.count("atk-icon.png") == bb.count("攻击力"),
		"atk图标%d次 vs 攻击力%d次" % [bb.count("atk-icon.png"), bb.count("攻击力")])

	# ③ 无原始 <img> 泄漏(都转成 [img]) + [img] 语法
	_ok("★无 <img> 原始标签漏给玩家", not bb.contains("<img"))
	_ok("★用的是 BBCode [img=..] 语法", bb.contains("[img="))

	# ④ 反向: 关键词表里【没有 icon 的】(灼烧/眩晕/物理) 不应带图标路径混入其色块
	var bb2 := SkillText.render_bbcode("灼烧与眩晕, 造成魔法伤害", f, {})
	_ok("★灼烧/眩晕/魔法伤害 不插图标(非属性)", not bb2.contains("stats/"))

	print("ALL PASS — 描述内联属性图标" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
