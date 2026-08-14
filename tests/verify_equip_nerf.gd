extends Node

## verify_equip_nerf.gd — 龙蛋 / 暴君之牙 削弱 (用户 2026-07-23)
## 龙蛋: 灼烧层数 0.67×ATK → 固定 30/45/70
## 暴君之牙: 毒牙 2/3/7×ATK → 1/1.8/4×ATK; 斩杀线 5/7/10%+10/15/40%×暴击 → 4/6/12%×(1+暴击)
## ★源码级: 断言实时脚本里是新值、旧值已消失。数值改错 → 红。

var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	# 2026-07-25: 主文件拆分后, 效果代码可能搬到 scripts/systems/(如龙蛋灼烧→dragon_system.gd)。
	#   把 systems/ 一并读进来对账, 否则拆一个效果出去就误报。
	#   2026-07-25b: systems/ 下再分 skills/ 与 equip/ 子目录(角色技能↔装备分开管理)→ 递归一层。
	for _dir in ["res://scripts/systems", "res://scripts/systems/skills", "res://scripts/systems/equip"]:
		var _sysd := DirAccess.open(_dir)
		if _sysd:
			for _f in _sysd.get_files():
				if _f.ends_with(".gd"):
					src += "\n" + FileAccess.get_file_as_string(_dir + "/" + _f)
	_ok("源码读到(分母)", src.length() > 100000, "%d 字符" % src.length())

	# ── 龙蛋 削弱二(用户 2026-07-29): 属性 / 伤害 / 治疗 / 灼烧 四处一起削 ──
	#    ★这里写的是【用户口述的需求值】, 不是从代码常量读回来的 —— 拿代码跟自己比等于没查
	#    (verify_trainer_magicstone 曾经就是恒真式, 把常量改坏照样 ALL PASS)。
	_ok("★龙蛋灼烧 = [20, 35, 50]", src.contains('_apply_dot_stacks(o, "burn", [20, 35, 50][si], u)'))
	_ok("★龙蛋灼烧旧值 30/45/70 已消失", not src.contains('"burn", [30, 45, 70][si]'))
	_ok("★龙蛋魔法伤害 = 45/80/120 + 1×ATK", src.contains('u["atk"] * 1.0 + float([45, 80, 120][si])'))
	_ok("★龙蛋治疗 = 45/80/120 + 1×ATK", src.contains('_heal(o, u["atk"] * 1.0 + float([45, 80, 120][si]))'))
	_ok("★龙蛋旧的 0.7/1.0/2.0×ATK 系数已消失", not src.contains("[0.7, 1.0, 2.0][si]"))
	_ok("★龙蛋旧的 1500 伤害 / 1000 治疗已消失",
		not src.contains("[50, 120, 1500][si]") and not src.contains("[70, 150, 1000][si]"))
	# 属性表(EquipStats 是装备属性的真事实源, 见 CLAUDE.md §1)
	var st := FileAccess.get_file_as_string("res://scripts/gamedata/equip_stats.gd")
	_ok("★龙蛋属性 = 攻20/45/70 · 魔穿8/15/27", st.contains(
		'"p2eq_024": [{"atk": 20, "magicPen": 8, "_maxEnergy": 20}, {"atk": 45, "magicPen": 15, "_maxEnergy": 20}, {"atk": 70, "magicPen": 27, "_maxEnergy": 20}]'))
	_ok("★龙蛋旧属性 300 攻已消失", not st.contains('"atk": 300, "magicPen": 50'))

	# ── 暴君之牙 毒牙 1/1.8/4 ──
	_ok("★暴君毒牙 = [1.0, 1.8, 4.0]", src.contains('[1.0, 1.8, 4.0][si] * float(u.get("atk", 0.0))'))
	_ok("★暴君毒牙旧值 2/3/7 已消失", not src.contains("[2.0, 3.0, 7.0][si] * float(u.get"))

	# ── 暴君之牙 斩杀线 4/6/12% × (1+暴击) ──
	_ok("★暴君斩杀线 = [0.04, 0.06, 0.12]×(1+暴击)", src.contains('[0.04, 0.06, 0.12][si] * (1.0 + float(src["crit"]))'))
	_ok("★暴君斩杀线旧值已消失", not src.contains('[0.05, 0.07, 0.10][si] + [0.10, 0.15, 0.40][si] * src["crit"]'))

	# ── tooltip 同步(effectDesc1 里出现新数字) ──
	var eq := FileAccess.get_file_as_string("res://data/phase2-equipment.json")
	_ok("★龙蛋文案含 20/35/50 层灼烧", eq.contains("20/35/50层灼烧"))
	_ok("★龙蛋文案含 45/80/120+1×攻击力", eq.contains("（45/80/120+1×攻击力）魔法伤害"))
	_ok("★龙蛋 baseStats1 镜像已同步", eq.contains("+攻20/45/70·魔穿8/15/27·+20龟能"))
	_ok("★暴君文案含 1/1.8/4×攻击力", eq.contains("1/1.8/4×攻击力魔法伤害"))
	_ok("★暴君文案含 4/6/12% 斩杀线", eq.contains("4/6/12%最大生命值×（1+暴击率）"))   # 2026-07-24 术语补全: 最大生命→最大生命值

	print("ALL PASS — 装备削弱(龙蛋/暴君之牙)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
