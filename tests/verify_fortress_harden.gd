extends Node
## verify_fortress_harden.gd — 014 深海堡垒甲: 每层硬化 +2/3/6 护甲和魔抗(2026-10-08)
##
## 用户原话:「每层硬化改为提供2/3/6护甲和魔抗」(原 2/4/6)
## 方案书: docs/plans/20261008-冰冻药剂与堡垒甲.md
##
## 判据走真入口: 装备旗标走 `_eq_apply_flags`, 叠层走受击钩 `_eq_on_target`(两条伤害路径都调它)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const WANT := [2.0, 3.0, 6.0]

var _n := 0
var _fail := 0
var s


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	print("=== 014 深海堡垒甲: 每层硬化 ===")
	RB.DEBUG_EDIT = true
	s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	s._edit_mode = false
	s._over = false
	for si in range(3):
		s._units.clear()
		var u: Dictionary = s._spawn._make_unit("basic", "left", c)
		var a: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(60, 0))
		u["maxHp"] = 99999.0; u["hp"] = 99999.0
		u["equips"] = [{"id": "p2eq_014", "star": si + 1}]
		u["eq_state"] = {}
		s._units.append(u); s._units.append(a)
		s._equip_sys._stats._eq_apply_flags(u, "p2eq_014", si + 1)
		var d0: float = float(u["base_def"]); var m0: float = float(u["base_mr"])
		s._equip_sys._eq_on_target(u, a, 10)
		_ok("★★%d★ 一层硬化 +%.0f 护甲" % [si + 1, WANT[si]], absf(float(u["base_def"]) - d0 - WANT[si]) < 0.001, "%.1f → %.1f" % [d0, float(u["base_def"])])
		_ok("★★%d★ 一层硬化 +%.0f 魔抗" % [si + 1, WANT[si]], absf(float(u["base_mr"]) - m0 - WANT[si]) < 0.001, "%.1f → %.1f" % [m0, float(u["base_mr"])])
		s._equip_sys._eq_on_target(u, a, 10)
		_ok("%d★ 两层 = 2×" % (si + 1), absf(float(u["base_def"]) - d0 - 2.0 * WANT[si]) < 0.001, "%.1f" % float(u["base_def"]))
	var edef: Dictionary = {}
	for e in JSON.parse_string(FileAccess.get_file_as_string("res://data/phase2-equipment.json")):
		if e is Dictionary and str(e.get("id", "")) == "p2eq_014":
			edef = e
	var full: String = SkillText.equip_full(edef)
	var brief: String = SkillText.equip_brief(edef)
	_ok("★文案详细 +2/3/6", full.find("每层提供+2/3/6 护甲和魔抗") >= 0, full)
	_ok("★文案简述 +2/3/6", brief.find("各 +2/3/6 双抗") >= 0, brief)
	_ok("没有残留占位符", full.find("{C:") < 0 and brief.find("{C:") < 0)
	print("--- %d 条, 失败 %d ---" % [_n, _fail])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)
