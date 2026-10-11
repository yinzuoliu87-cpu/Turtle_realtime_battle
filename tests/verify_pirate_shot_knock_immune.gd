extends Node
## verify_pirate_shot_knock_immune.gd —— 海盗霰弹的 40 码击退要守免击退(2026-10-11 全项目通读 A5)
##
## ★读码发现: 霰弹直接改 `hit["pos"]`, 不走 `_knockback`, 也不查 `_knock_immune`(017 不沉之锚 / 小将不可阻挡)。
##   `_knockback` 开头的三道守卫(活着 / 不在空中 / 免击退)在这条路上一条都没有。
## ★判据走产品技能: 目标免击退 ⇒ 霰弹命中后位置不变(伤害照吃); 对照: 不免疫的被推开。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _shoot(s, immune: bool) -> Array:
	s._units.clear()
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var p: Dictionary = s._spawn._make_unit("pirate", "left", c)
	var t: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(150, 0))
	t["maxHp"] = 1.0e6
	t["hp"] = 1.0e6
	t["_knock_immune"] = immune
	s._units.append(p)
	s._units.append(t)
	var p0: Vector2 = t["pos"]
	s._pirate_sys._pirate_shotgun(p, t)
	return [DetMath.dist(t["pos"], p0), 1.0e6 - float(t["hp"])]


func _ready() -> void:
	await get_tree().process_frame
	print("=== 海盗霰弹击退守免击退 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._edit_mode = false
	s._over = false
	var a := _shoot(s, false)
	_ok("★分母: 不免疫的目标被霰弹打中且被推开", float(a[1]) > 0.0 and float(a[0]) > 1.0, "推 %.1f 码 / 伤 %.0f" % [a[0], a[1]])
	var b := _shoot(s, true)
	_ok("★★免击退的目标: 伤害照吃, 位置不动", float(b[1]) > 0.0 and float(b[0]) < 0.01, "推 %.1f 码 / 伤 %.0f" % [b[0], b[1]])
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
