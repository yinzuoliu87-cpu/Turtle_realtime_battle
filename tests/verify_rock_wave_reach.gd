extends Node
## verify_rock_wave_reach.gd —— 石头龟岩石冲击波: 判定只到岩脊铺到的地方(820 码)(2026-10-11 全项目通读 A2)
##
## ★读码发现: 伤害循环只判「在前方」+「带宽 ±90」, 不判距离; 演出岩脊铺到 reach=820, AI 施法射程表也是 820
##   ⇒ 1500 码外、带宽内的敌人照样被打 + 眩晕 2 秒(看着岩脊停在半路, 远处的人却倒了)。
## ★判据走产品技能: 正前方 600 码的敌人被打, 1500 码的不被打。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 岩石冲击波判定到岩脊为止 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._units.clear()
	var o: Vector2 = s.ARENA.position + Vector2(40, s.ARENA.size.y * 0.5)
	var st: Dictionary = s._spawn._make_unit("stone", "left", o)
	var near: Dictionary = s._spawn._make_unit("basic", "right", o + Vector2(600, 0))
	var far: Dictionary = s._spawn._make_unit("basic", "right", o + Vector2(1500, 0))
	for e in [near, far]:
		e["maxHp"] = 1.0e6
		e["hp"] = 1.0e6
		e["atk"] = 0.0
	s._units.append(st)
	s._units.append(near)
	s._units.append(far)
	s._edit_mode = false
	s._over = false
	s._stone_sys._sk_rock_shockwave(st)
	for i in range(int(round(3.0 / float(s.SIM_DT)))):
		s._sim_step(s.SIM_DT, false, false)
	_ok("★分母: 600 码的敌人被打到", float(near["hp"]) < 1.0e6, "hp %.0f" % float(near["hp"]))
	_ok("★★1500 码(岩脊没铺到)的敌人不被打", float(far["hp"]) >= 1.0e6, "hp %.0f" % float(far["hp"]))
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
