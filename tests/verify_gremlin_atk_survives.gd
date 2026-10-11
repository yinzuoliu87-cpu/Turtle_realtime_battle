extends Node
## verify_gremlin_atk_survives.gd —— 古灵精怪枪的「+攻击」要经得起属性重算(2026-10-11 全项目通读 A17)
## ★原来写在 `atk`(重算的输出)上, 下一次任何 buff 触发 `_recalc_stats` 就丢; 要写在 `base_atk`(重算的输入)上。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const GG := preload("res://scripts/systems/equip/gremlin_gun.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit("basic", "left", c)
	s._units.append(u)
	s._recalc_stats(u)
	var a0: float = float(u["atk"])
	var gg = GG.new(s)
	gg.give(u)
	var a1: float = float(u["atk"])
	_ok("★分母: 给枪后攻击涨了 %.1f" % GG.ATK_PER_GUN, absf(a1 - a0 - GG.ATK_PER_GUN) < 1e-3, "%.2f → %.2f" % [a0, a1])
	s._recalc_stats(u)
	_ok("★★重算属性后攻击加成还在", absf(float(u["atk"]) - a1) < 1e-3, "重算后 %.2f(应 %.2f)" % [float(u["atk"]), a1])
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
