extends Node
## verify_knock_parabola.gd —— 击退 / 击飞的轨迹是**匀速抛物线**, 且落点距离与滞空时长与改之前一样(2026-11-14)。
##
## 用户 11-14:「你这击飞是抛物线吗」「怎么击飞击退，正常人家会这么设计」「做吧」。
## 原来所有击退的横向速度每步 ×0.9 衰减 ⇒ 0.35 秒冲完九成距离、剩下竖着掉。改成 BattleDamage.knock_to_parabola:
##   横向速度一被设定, 就按原衰减模型算出它本来会走的总距离, 在剩余滞空里匀速走完。
## 判据(走产品的两条击飞入口 `_knockback` / `_knock_up`, 外加一个改重力的(石头龟砸地式)):
##   ① 落点距离 == 原衰减模型在同样滞空步数里会走的距离(±3%) —— 落点不变
##   ② 到最高点时水平走了总距离的一半(±12%) —— 是抛物线(原模型到最高点前已走完九成以上)
##   ③ 滞空步数 == 2·vy / |g| 推出来的步数(±2 步) —— 滞空不变

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
	print("=== 击退 / 击飞 = 匀速抛物线(落点与滞空不变) ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	for case in [["_knockback 默认", 0], ["_knock_up(9.0)", 1], ["_knockback 改重力(砸地式 vy×3.61 / g −36.1)", 2]]:
		s._units.clear()
		var by: Dictionary = s._spawn._make_unit("stone", "left", c - Vector2(60, 0))
		var tg: Dictionary = s._spawn._make_unit("basic", "right", c)
		for x in [by, tg]:
			x["no_move"] = true
			x["no_basic"] = true
			x["atk"] = 0.0
		tg["maxHp"] = 1.0e6
		tg["hp"] = 1.0e6
		s._units.append(by)
		s._units.append(tg)
		s._edit_mode = false
		s._over = false
		match int(case[1]):
			0:
				s._damage._knockback(by, tg, 0.0)
			1:
				s._knock_up(tg, by["pos"], 9.0)
			2:
				s._damage._knockback(by, tg, 80.0, 3.6111)
				tg["knock_g"] = -36.111
		_ok("★分母(%s): 真的飞起来了且有横推" % case[0], bool(tg.get("airborne", false)) and absf(float(tg.get("vx", 0.0))) > 0.01,
			"vx %.2f" % float(tg.get("vx", 0.0)))
		var vx0: float = float(tg["vx"])
		var vy0: float = float(tg["vy"])
		var g: float = float(tg.get("knock_g", s.GRAVITY))
		var x0: float = float((tg["pos"] as Vector2).x)
		var steps := 0
		var apex_dx := -1.0
		var h_prev := 0.0
		while bool(tg.get("airborne", false)) and steps < 600:
			s._sim_step(s.SIM_DT, false, false)
			steps += 1
			var h: float = float(tg.get("height", 0.0))
			if apex_dx < 0.0 and h < h_prev:
				apex_dx = float((tg["pos"] as Vector2).x) - x0
			h_prev = h
		var land_dx: float = float((tg["pos"] as Vector2).x) - x0
		## 原衰减模型在同样的步数里会走多远(码): Σ vx0·r^k·dt / WS, k = 0..steps−1
		var r: float = DetMath.dpow(0.9, s.SIM_DT * 60.0)
		var old_dx: float = vx0 * s.SIM_DT * (1.0 - pow(r, float(steps))) / (1.0 - r) / s.WS
		var want_steps: int = int(round(2.0 * vy0 / -g / s.SIM_DT))
		_ok("① %s 落点 %.1f 码 == 原模型 %.1f 码(±3%%)" % [case[0], land_dx, old_dx], absf(land_dx - old_dx) <= absf(old_dx) * 0.03 + 0.5)
		_ok("② %s 最高点时走了 %.1f 码 ≈ 一半 %.1f(±12%%)" % [case[0], apex_dx, land_dx * 0.5], absf(apex_dx - land_dx * 0.5) <= absf(land_dx) * 0.12 + 0.5)
		_ok("③ %s 滞空 %d 步 == 2·vy/|g| 推的 %d 步(±2)" % [case[0], steps, want_steps], absi(steps - want_steps) <= 2)
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
