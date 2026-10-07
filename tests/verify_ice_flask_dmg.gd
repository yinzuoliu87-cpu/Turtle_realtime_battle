extends Node
## verify_ice_flask_dmg.gd — 028 冰冻药剂(原名冰霜冻露瓶): 改名 + 新伤害公式(2026-10-08)
##
## 用户原话:「改名为冰冻药剂，魔法伤害值修改为20/35/60+0.8/1/1.2ATK+目标3/5/9%最大生命值魔法伤害」
## 方案书: docs/plans/20261008-冰冻药剂与堡垒甲.md
##
## 判据走真入口: 命中结算 `IceSystem._ice_bottle_hit`(演出末尾与门禁都调它), 伤害经 `_resolve_dmg(magic=true)`
##   + `_apply_damage_from` 真扣血; 期望值 = 需求字面量公式 × 魔抗减免(DamageMath 共用公式)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

const BASE := [20.0, 35.0, 60.0]
const ATKC := [0.8, 1.0, 1.2]
const HPC := [0.03, 0.05, 0.09]
const ATK := 200.0
const FOE_HP := 20000.0

var _n := 0
var _fail := 0
var s


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## ★携带者用 stone 不用 basic: 小龟「不屈」对任何伤害按目标稀有度增伤, 精确值会被它带偏
func _mk(id: String, side: String, pos: Vector2, hp: float) -> Dictionary:
	var u: Dictionary = s._spawn._make_unit(id, side, pos)
	u["maxHp"] = hp; u["hp"] = hp
	u["atk"] = ATK
	u["crit"] = 0.0; u["shield"] = 0.0; u["flat_dr"] = 0.0
	u["damage_amp"] = 0.0; u["damage_reduction"] = 0.0
	u["magic_pen"] = 0.0; u["magic_pen_pct"] = 0.0
	u["dodge"] = 0.0
	u["_knock_immune"] = true
	s._units.append(u)
	return u


func _ready() -> void:
	await get_tree().process_frame
	print("=== 028 冰冻药剂: 伤害公式 / 改名 ===")
	RB.DEBUG_EDIT = true
	s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	s._edit_mode = false
	s._over = false

	print("-- ① 每星精确伤害(魔抗 50) --")
	for si in range(3):
		s._units.clear()
		var u := _mk("stone", "left", c, 9000.0)
		var o := _mk("basic", "right", c + Vector2(200, 0), FOE_HP)
		o["mr"] = 50.0
		var raw: float = BASE[si] + ATK * ATKC[si] + FOE_HP * HPC[si]
		var want: int = maxi(1, int(round(raw * DamageMath.resist_multiplier(DamageMath.effective_resist(50.0, 0.0, 0.0)))))
		var h0: float = float(o["hp"])
		s._ice_sys._ice_bottle_hit(null, u, o, si)
		var got: float = h0 - float(o["hp"])
		_ok("★★%d★ 伤害 = (%.0f + %.1f×%.0f + %.0f%%×%.0f) × 魔抗减免 = %d" % [si + 1, BASE[si], ATKC[si], ATK, HPC[si] * 100.0, FOE_HP, want],
			absf(got - float(want)) <= 1.0, "实得 %.0f" % got)

	print("-- ② 是魔法伤害(魔抗越高越少; 护甲不影响) --")
	s._units.clear()
	var u2 := _mk("stone", "left", c, 9000.0)
	var lo := _mk("basic", "right", c + Vector2(200, 0), FOE_HP)
	lo["mr"] = 0.0; lo["def"] = 500.0
	var hi := _mk("basic", "right", c + Vector2(260, 0), FOE_HP)
	hi["mr"] = 300.0; hi["def"] = 0.0
	var l0: float = float(lo["hp"]); var hh0: float = float(hi["hp"])
	s._ice_sys._ice_bottle_hit(null, u2, lo, 2)
	s._ice_sys._ice_bottle_hit(null, u2, hi, 2)
	var dl: float = l0 - float(lo["hp"]); var dh: float = hh0 - float(hi["hp"])
	var raw3: float = BASE[2] + ATK * ATKC[2] + FOE_HP * HPC[2]
	_ok("★★零魔抗(护甲 500)吃满额 = %.0f" % raw3, absf(dl - roundf(raw3)) <= 1.0, "实得 %.0f" % dl)
	_ok("★★魔抗 300 明显少吃", dh < dl * 0.6, "%.0f vs %.0f" % [dh, dl])

	print("-- ③ 改名 / 文案 --")
	var edef: Dictionary = {}
	var raw_json := FileAccess.get_file_as_string("res://data/phase2-equipment.json")
	for e in JSON.parse_string(raw_json):
		if e is Dictionary and str(e.get("id", "")) == "p2eq_028":
			edef = e
	_ok("★★名字 = 冰冻药剂", str(edef.get("name", "")) == "冰冻药剂", str(edef.get("name", "")))
	_ok("★旧名一个不剩(装备数据)", raw_json.find("冰霜冻露瓶") < 0)
	_ok("图标路径不变", str(edef.get("img", "")) == "equip/frost-flask.png", str(edef.get("img", "")))
	var full: String = SkillText.equip_full(edef)
	var brief: String = SkillText.equip_brief(edef)
	var frag := "（20/35/60+0.8/1/1.2×攻击力+目标最大生命值 3/5/9%）魔法伤害"
	_ok("★★详细写出新公式", full.find(frag) >= 0, full)
	_ok("★★简述写出新公式", brief.find(frag) >= 0, brief)
	_ok("★没有残留占位符 / 旧数值", full.find("{C:") < 0 and brief.find("{C:") < 0 and full.find("40/60/100") < 0 and brief.find("40/60/100") < 0)

	print("--- %d 条, 失败 %d ---" % [_n, _fail])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)
