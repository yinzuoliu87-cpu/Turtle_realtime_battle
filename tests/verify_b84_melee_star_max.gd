extends Node
## verify_b84_melee_star_max.gd —— 近战龟同带两件 084 手半剑: 增伤按更高的星级(2026-10-11 全项目通读 A14)
## ★多件同带的重算只写了远程分支(`_b84_refresh`) ⇒ 近战「先 1★ 后 3★」停在 1★ 的 3%(应 3★ 的 10%)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BB := preload("res://scripts/systems/equip/eq_blade_batch.gd")

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
	u["melee"] = true
	u["damage_amp"] = 0.0
	s._units.append(u)
	var bs = s._equip_sys._blade_sys
	bs._spawn084(u, 0)
	_ok("★分母: 1★ 近战增伤 = %.2f" % BB.HH_MELEE_AMP[0], absf(float(u["damage_amp"]) - BB.HH_MELEE_AMP[0]) < 1e-4, "%.3f" % float(u["damage_amp"]))
	bs._spawn084(u, 2)
	_ok("★★再装一件 3★ ⇒ 增伤 = 3★ 的 %.2f(不是叠成两份, 也不停在 1★)" % BB.HH_MELEE_AMP[2],
		absf(float(u["damage_amp"]) - BB.HH_MELEE_AMP[2]) < 1e-4, "%.3f" % float(u["damage_amp"]))
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
