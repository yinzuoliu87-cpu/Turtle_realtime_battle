extends Node
## verify_truefire_egg_half.gd —— 022 余烬燃油瓶【真火】打龟蛋: 灼烧伤害减少 EMBER_TRUEFIRE_EGG_REDUCE%(用户 2026-11-06
## 「真火对龟蛋的伤害减少百分之五十」)。
##
## 做法: 真实 RealtimeBattle3DScene 里造一只龟蛋(走 _make_unit 的 egg spec, 单位上带 `_isEgg`)和一只普通单位,
##   两者最大生命、灼烧层数、真火状态完全一样, 各直接驱动一次 `_tick_dot_stacks`(主场景真入口), 比掉了多少血。
## 判据落在产品自己的账上(掉血), 并带两组对照:
##   ① 真火: 龟蛋掉血 = 普通单位掉血 × (1 − REDUCE/100)  —— 需求本身
##   ② 没有真火(普通灼烧走魔抗): 龟蛋掉血 = 普通单位掉血  —— 只减真火这一跳, 普通灼烧打蛋不变
## 反向验证: 让 EquipSystem.truefire_burn_dmg 对龟蛋也原样返回 ⇒ ① 红(两边掉一样多)。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const STACKS := 100
const MAX_HP := 6000.0

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _prep(u: Dictionary, true_fire: bool, scene) -> void:
	u["maxHp"] = MAX_HP
	u["hp"] = MAX_HP
	u["shield"] = 0.0
	u["mr"] = 0.0
	u["dot_stacks"] = {}
	u["true_fire_until"] = (float(scene.get("_t")) + 99.0) if true_fire else 0.0
	scene._damage.call("_apply_dot_stacks", u, "burn", STACKS, null)


func _lost(u: Dictionary, scene) -> float:
	var hp0: float = float(u["hp"]) + float(u.get("shield", 0.0))
	scene.call("_tick_dot_stacks", u)
	return hp0 - float(u["hp"]) - float(u.get("shield", 0.0))


func _ready() -> void:
	await get_tree().process_frame
	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	print("=== 022【真火】打龟蛋减伤 ===")
	var egg: Dictionary = scene._spawn._make_unit("__egg__", "right", Vector2(900, 300), {"egg": true, "egg_side": "right", "hp": MAX_HP, "hp_max": MAX_HP})
	var mob: Dictionary = scene._spawn._make_unit("basic", "right", Vector2(900, 420))
	_ok("★分母: 造出来的龟蛋带 _isEgg、普通单位不带", bool(egg.get("_isEgg", false)) and not bool(mob.get("_isEgg", false)))
	var reduce: int = EquipSystem.EMBER_TRUEFIRE_EGG_REDUCE
	_ok("减伤常量 = 用户说的 50%", reduce == 50, "%d" % reduce)

	## ① 真火
	_prep(egg, true, scene)
	_prep(mob, true, scene)
	var e1: float = _lost(egg, scene)
	var m1: float = _lost(mob, scene)
	var want: float = float(roundi(m1 * (1.0 - float(reduce) / 100.0)))
	_ok("★分母: 真火这一跳普通单位确实掉了血", m1 > 0.0, "%.0f" % m1)
	_ok("★★真火: 龟蛋掉血 = 普通单位 × (1 − %d%%)" % reduce, absf(e1 - want) < 0.5, "蛋 %.0f / 普通 %.0f / 期望 %.0f" % [e1, m1, want])

	## ② 普通灼烧(没有真火)
	_prep(egg, false, scene)
	_prep(mob, false, scene)
	var e2: float = _lost(egg, scene)
	var m2: float = _lost(mob, scene)
	_ok("★分母: 普通灼烧这一跳普通单位确实掉了血", m2 > 0.0, "%.0f" % m2)
	_ok("★普通灼烧打蛋不受影响(只减真火)", absf(e2 - m2) < 0.5, "蛋 %.0f / 普通 %.0f" % [e2, m2])

	## 文案里写了这条(数字走占位符, 不手抄)
	var txt := FileAccess.get_file_as_string("res://data/phase2-equipment.json")
	_ok("★余烬燃油瓶文案写了龟蛋减伤且读常量", txt.contains("对龟蛋的灼烧伤害降低 {C:EquipSystem.EMBER_TRUEFIRE_EGG_REDUCE}%"))

	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 真火打龟蛋减伤 %d%%" % reduce if _fail == 0 else "FAIL")
	get_tree().quit(0 if _fail == 0 else 1)
