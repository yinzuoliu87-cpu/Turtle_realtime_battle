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
	## ★11-14 判定改「波前每步碰各人当前位置」(用户「整个游戏难道你搞了很多这种不合理的地方吗」「做吧」)。两个探针专钉这一条:
	##   walk_in  出手时在带外(横向 330), 出手后马上走进带内 ⇒ 波前扫到它 ⇒ 要挨打(旧写法出手时没选它 ⇒ 不挨打)
	##   walk_out 出手时在带内、是石头龟的目标(决定岩脊朝向), 波前到之前走出带外 ⇒ 不挨打(旧写法照样挨打 + 眩晕)
	var walk_in: Dictionary = s._spawn._make_unit("basic", "right", o + Vector2(450, 330))
	var walk_out: Dictionary = s._spawn._make_unit("basic", "right", o + Vector2(500, 0))
	for e in [near, far, walk_in, walk_out]:
		e["maxHp"] = 1.0e6
		e["hp"] = 1.0e6
		e["atk"] = 0.0
		e["no_move"] = true
		e["no_basic"] = true
	s._units.append(st)
	s._units.append(near)
	s._units.append(far)
	s._units.append(walk_in)
	s._units.append(walk_out)
	s._edit_mode = false
	s._over = false
	s._stone_sys._sk_rock_shockwave(st)
	var rw: Array = s._equip_tick_sys._rock_waves
	_ok("★分母: 登记了 1 道岩脊且朝 +x(目标 = 500 码那个)", rw.size() == 1 and float((rw[0]["dir"] as Vector2).x) > 0.99,
		"%d 道" % rw.size())
	for i in range(int(round(3.0 / float(s.SIM_DT)))):
		s._sim_step(s.SIM_DT, false, false)
		if i == 0:
			walk_in["pos"] = o + Vector2(450, 0)       # 走进岩脊(波前此时还在起手, 约 0.6 秒后才到 450 码)
			walk_out["pos"] = o + Vector2(500, 250)    # 走出岩脊
	_ok("★分母: 600 码的敌人被打到", float(near["hp"]) < 1.0e6, "hp %.0f" % float(near["hp"]))
	_ok("★★1500 码(岩脊没铺到)的敌人不被打", float(far["hp"]) >= 1.0e6, "hp %.0f" % float(far["hp"]))
	_ok("★★出手后走进岩脊的敌人挨打(波前扫到它当时的位置)", float(walk_in["hp"]) < 1.0e6, "hp %.0f" % float(walk_in["hp"]))
	_ok("★★出手后走出岩脊的敌人不挨打(不按出手那一刻的位置排队)", float(walk_out["hp"]) >= 1.0e6 and float(walk_out.get("stun_until", 0.0)) <= 0.0,
		"hp %.0f · 眩晕到 %.2f" % [float(walk_out["hp"]), float(walk_out.get("stun_until", 0.0))])
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
