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
	_ok("源码读到(分母)", src.length() > 100000, "%d 字符" % src.length())

	# ── 龙蛋 灼烧固定 30/45/70 ──
	_ok("★龙蛋灼烧 = [30, 45, 70]", src.contains('_apply_dot_stacks(o, "burn", [30, 45, 70][si], u)'))

	# ── 暴君之牙 毒牙 1/1.8/4 ──
	_ok("★暴君毒牙 = [1.0, 1.8, 4.0]", src.contains('[1.0, 1.8, 4.0][si] * float(u.get("atk", 0.0))'))
	_ok("★暴君毒牙旧值 2/3/7 已消失", not src.contains("[2.0, 3.0, 7.0][si] * float(u.get"))

	# ── 暴君之牙 斩杀线 4/6/12% × (1+暴击) ──
	_ok("★暴君斩杀线 = [0.04, 0.06, 0.12]×(1+暴击)", src.contains('[0.04, 0.06, 0.12][si] * (1.0 + float(src["crit"]))'))
	_ok("★暴君斩杀线旧值已消失", not src.contains('[0.05, 0.07, 0.10][si] + [0.10, 0.15, 0.40][si] * src["crit"]'))

	# ── tooltip 同步(effectDesc1 里出现新数字) ──
	var eq := FileAccess.get_file_as_string("res://data/phase2-equipment.json")
	_ok("★龙蛋文案含 30/45/70 层灼烧", eq.contains("30/45/70层灼烧"))
	_ok("★暴君文案含 1/1.8/4×攻击力", eq.contains("1/1.8/4×攻击力魔法伤害"))
	_ok("★暴君文案含 4/6/12% 斩杀线", eq.contains("4/6/12%最大生命×(1+暴击率)"))

	print("ALL PASS — 装备削弱(龙蛋/暴君之牙)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
