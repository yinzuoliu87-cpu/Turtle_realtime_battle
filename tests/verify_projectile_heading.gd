extends Node
## 弹道朝向(2026-11-05 用户「龟派气波…波在生成的时候那个方向不对…波在运行的时候有的时候这个波的方向并不朝着敌人…整个游戏弹道可能有问题」
##   「主要是这个方向与它飞行方向是歪的呀，它飞的方向和它的这个头就偏离了一定的角度，包括远程小将的火箭筒技能也是」)
##   ① 聚气贴图(chiwave-spawn)尖头朝目标: 原来是立牌, 尖头永远朝屏幕右(目标在左偏 180°、在上偏 90°)
##   ② 飞行方向 = 发射那一刻小龟→目标当前位置: 原来在聚气开始时就定死(目标在 0.6 秒聚气里横走 200 码/秒 ⇒ 偏 14~17°)
##   ③ 飞行贴图尖头对准屏幕上的行进方向, 飞到画面边上也对: 原来 _orient_billboard_dir 按「点→相机」立牌, 横飞到边上偏 21.6~27.3°
##      (_orient_billboard_dir 还给训龟大师 / 宝箱 / 缩头龟导弹定向, 一起守)
##   ④ 定向函数本身: 画面中心 + 四角 × 8 个方向, 尖头(贴图 +X)在屏幕上的角度 = 屏幕行进角
##   ⑤ 远程小将·追踪火箭筒(hiding_system._minion_rocket_fly, 每步调 _orient_billboard_dir): 目标横走 ⇒ 弹道拐弯, 全程每步量机头 vs 屏幕行进
## 判据: ① ≤ 3° · ② ≤ 2°(探针取样晚一帧有 0.5° 的量法误差) · ③ ≤ 2° · ④ ≤ 1° · ⑤ 全程最大 ≤ 3°(相邻两步取样, 拐弯处一步的弦角)。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _mk(kind: String, side: String, pos: Vector2) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit(kind, side, pos)
	u["maxHp"] = 100000.0
	u["hp"] = 100000.0
	u["no_basic"] = true
	u["no_move"] = true
	u["eq_state"] = {}
	return u


func _scr_ang(n: Node3D) -> float:
	## 贴图 local +X(美术里尖头朝右)在屏幕上的角度; 立牌 billboard 的贴图永远水平朝右 = 0°
	if n is Sprite3D and (n as Sprite3D).billboard != BaseMaterial3D.BILLBOARD_DISABLED:
		return 0.0
	var p: Vector3 = n.global_position
	var d: Vector2 = _s._cam.unproject_position(p + n.global_transform.basis.x.normalized() * 0.5) - _s._cam.unproject_position(p)
	return rad_to_deg(atan2(d.y, d.x))


func _aim_scr(a2: Vector2, b2: Vector2) -> float:
	var d: Vector2 = _s._cam.unproject_position(_s._world_pos(b2, 0.9)) - _s._cam.unproject_position(_s._world_pos(a2, 0.9))
	return rad_to_deg(atan2(d.y, d.x))


func _dang(a: float, b: float) -> float:
	return absf(wrapf(a - b, -180.0, 180.0))


func _find(tex: String) -> Array:
	var out: Array = []
	for ch in _s._world.get_children():
		if ch is Sprite3D and (ch as Sprite3D).texture != null and (ch as Sprite3D).texture.resource_path.ends_with(tex):
			out.append(ch)
	return out


func _case(nm: String, foe_off: Vector2, foe_vel: Vector2) -> void:
	for u in _s._units.duplicate():
		_s._units.erase(u)
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u := _mk("basic", "left", c)
	var e := _mk("basic", "right", c + foe_off)
	_s._units.append(u)
	_s._units.append(e)
	var old_spawn := _find("chiwave-spawn.png")
	_s._sk_basic_chiwave(u, e)
	var sp_all := _find("chiwave-spawn.png").filter(func(x): return not old_spawn.has(x))
	var sp_err := -1.0
	if not sp_all.is_empty():
		sp_err = _dang(_scr_ang(sp_all[0]), _aim_scr(u["pos"], e["pos"]))
	var dt := 1.0 / 60.0
	var ball = null
	var p0 := Vector2.ZERO
	var launch_aim := 0.0
	var e_at_launch := Vector2.ZERO
	var old_ball := _find("chiwave-fly.png")
	var fly_err := -1.0
	var travel_err := -1.0
	var fly_first := -1.0
	for i in range(150):
		_s._t += dt
		_s._ballistics._step_pending_shots(dt)
		_s._step_sim_tweens(dt)
		if ball == null:
			e["pos"] = e["pos"] + foe_vel * dt
			var nb := _find("chiwave-fly.png").filter(func(x): return not old_ball.has(x))
			if not nb.is_empty():
				ball = nb[0]
				e_at_launch = e["pos"]
				p0 = Vector2(ball.global_position.x, ball.global_position.z)
				launch_aim = rad_to_deg((e_at_launch - u["pos"]).angle())
		elif is_instance_valid(ball) and i % 10 == 0:
			var p1 := Vector2(ball.global_position.x, ball.global_position.z)
			if p1.distance_to(p0) > 0.5:
				travel_err = _dang(rad_to_deg((p1 - p0).angle()), launch_aim)
				var scr_travel: float = rad_to_deg((_s._cam.unproject_position(ball.global_position) - _s._cam.unproject_position(Vector3(p0.x, ball.global_position.y, p0.y))).angle())
				fly_err = _dang(_scr_ang(ball), scr_travel)
				if fly_first < 0.0:
					fly_first = fly_err
	_ok("① %s: 聚气贴图尖头朝目标(≤ 3°)" % nm, sp_err >= 0.0 and sp_err <= 3.0, "偏 %.1f°" % sp_err)
	_ok("② %s: 飞行方向 = 发射时瞄目标当前位置(≤ 2°)" % nm, travel_err >= 0.0 and travel_err <= 2.0, "偏 %.1f°" % travel_err)
	_ok("③ %s: 飞行贴图尖头对准屏幕行进方向, 飞到画面边上也对(≤ 2°)" % nm, fly_first >= 0.0 and fly_err >= 0.0 and maxf(fly_first, fly_err) <= 2.0, "刚发射 %.1f° · 远处 %.1f°" % [fly_first, fly_err])


## ④ 定向函数本身: 画面中心与四角, 8 个方向
func _sweep_orient() -> void:
	var a: Rect2 = _s.ARENA
	var pts := {"中心": a.position + a.size * 0.5, "左上": a.position + Vector2(120, 120), "右上": a.position + Vector2(a.size.x - 120, 120),
		"左下": a.position + Vector2(120, a.size.y - 120), "右下": a.position + a.size - Vector2(120, 120)}
	var worst := 0.0
	var worst_at := ""
	var n := 0
	var node := Sprite3D.new()
	node.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_s._world.add_child(node)
	for k in pts:
		for i in range(8):
			var d := Vector2.from_angle(float(i) * TAU / 8.0)
			node.position = _s._world_pos(pts[k], 0.9)
			_s._orient_billboard_dir(node, Vector3(d.x, 0.0, d.y))
			var p: Vector3 = node.global_position
			var tr: Vector2 = _s._cam.unproject_position(p + Vector3(d.x, 0.0, d.y) * 0.05) - _s._cam.unproject_position(p)
			var e := _dang(_scr_ang(node), rad_to_deg(atan2(tr.y, tr.x)))
			n += 1
			if e > worst:
				worst = e
				worst_at = "%s·%d°" % [k, i * 45]
	node.queue_free()
	_ok("④ 定向函数: 画面中心 + 四角 × 8 方向, 尖头 = 屏幕行进方向(≤ 1°)", n == 40 and worst <= 1.0, "%d 次 · 最大偏 %.2f°(%s)" % [n, worst, worst_at])


## ⑤ 远程小将·追踪火箭筒: 从左边发向右边横走的目标, 全程每步量
func _rocket_case(nm: String, from_off: Vector2, foe_off: Vector2, foe_vel: Vector2) -> void:
	for u in _s._units.duplicate():
		_s._units.erase(u)
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u := _mk("basic", "left", c + from_off)
	var e := _mk("basic", "right", c + foe_off)
	_s._units.append(u)
	_s._units.append(e)
	var old := _find("rocket-missile.png")
	_s._hiding_sys._minion_rocket_fly(u, e, u["pos"])
	var dt := 1.0 / 60.0
	var prev = null
	var worst := 0.0
	var n := 0
	for i in range(600):
		_s._frame_sim_dt = dt
		_s._t += dt
		e["pos"] = e["pos"] + foe_vel * dt
		_s.sim_stepped.emit()
		var ms := _find("rocket-missile.png").filter(func(x): return not old.has(x))
		if ms.is_empty():
			if n > 0:
				break
			continue
		var m: Sprite3D = ms[0]
		var p: Vector3 = m.global_position
		if prev != null and (p - prev).length() > 0.001:
			var tr: Vector2 = _s._cam.unproject_position(p) - _s._cam.unproject_position(prev)
			worst = maxf(worst, _dang(_scr_ang(m), rad_to_deg(atan2(tr.y, tr.x))))
			n += 1
		prev = p
	_ok("⑤ 远程小将火箭·%s: 全程机头对准屏幕行进方向(≤ 3°)" % nm, n >= 30 and worst <= 3.0, "量了 %d 步 · 最大偏 %.2f°" % [n, worst])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_node("/root/GameState").test_mode = true
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s._edit_mode = false
	_s._over = false
	_s._deterministic = true
	_case("目标在右·不动", Vector2(400, 0), Vector2.ZERO)
	_case("目标在左·不动", Vector2(-400, 0), Vector2.ZERO)
	_case("目标在上·不动", Vector2(0, -350), Vector2.ZERO)
	_case("目标在右·聚气时往下走 200码/秒", Vector2(400, 0), Vector2(0, 200))
	_case("目标在左下·聚气时往右走 200码/秒", Vector2(-300, 250), Vector2(200, 0))
	_sweep_orient()
	_rocket_case("横穿画面·目标往下走", Vector2(-700, -150), Vector2(500, 0), Vector2(0, 160))
	_rocket_case("从右下打左上·目标往右走", Vector2(600, 250), Vector2(-450, -250), Vector2(150, 0))
	print("分母: %d 项" % _n)
	if _fail == 0 and _n >= 18:
		print("ALL PASS — 龟派气波聚气 / 飞行方向 / 贴图尖头, 定向函数, 远程小将火箭机头都对准行进方向")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
