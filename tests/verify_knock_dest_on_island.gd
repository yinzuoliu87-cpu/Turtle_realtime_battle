extends Node
## verify_knock_dest_on_island.gd —— 位移落点必须在岛(超椭圆)里, 不许按矩形钳(2026-10-11 全项目通读 A4)
## ★无头镰刀击退 / 星际奇点换位 的落点原来按 ARENA 矩形 clampf ⇒ 矩形四角在岛外(海里)。
##   全仓其它位移早改成 ArenaShape.clamp_in(形状由 arena_shape.gd 说了算)。
## ★判据走产品函数: 单位放在岛的右下缘, 朝右下角(矩形里、岛外)击退 400 码 ⇒ 落地后仍在岛里。
## ★2026-10-11 实测: 原代码这条就是绿的 —— 每帧移动/分离会把位置钳回岛内, 落点越界最多是飞行途中短暂过岸线。
##   通读台账 A4「击退落岛外」按「最终落点」不成立; 本门禁留着守最终落点(以后谁拆了每帧钳制会红)。

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
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var A: Rect2 = s.ARENA
	var corner: Vector2 = A.end - Vector2(1, 1)
	_ok("★分母: 矩形右下角确实在岛外", not ArenaShape.in_rect_shape(corner, A), str(corner))
	s._units.clear()
	var c: Vector2 = A.position + A.size * 0.5
	var start: Vector2 = c + (corner - c) * 0.80
	var u: Dictionary = s._spawn._make_unit("basic", "right", ArenaShape.clamp_in(start, A))
	var keep: Dictionary = s._spawn._make_unit("basic", "left", c)
	s._units.append(u)
	s._units.append(keep)
	s._edit_mode = false
	s._over = false
	s._headless_sys._headless_knock_out(u, DetMath.norm(corner - c), 400.0)
	for i in range(int(round(1.5 / float(s.SIM_DT)))):
		s._sim_step(s.SIM_DT, false, false)
	_ok("★★无头镰刀朝角落击退 400 码 ⇒ 落地仍在岛里", ArenaShape.in_rect_shape(u["pos"], A, -2.0), "落点 %s" % str(u["pos"]))
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
