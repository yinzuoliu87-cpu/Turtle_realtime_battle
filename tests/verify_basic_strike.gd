extends Node
## 小龟·打击(2026-10-15 重做 · 用户「打击这个技能的实现应该有问题吧」「射程无限…诸多不合理」)
##   ① 施法定身是 channel 不是眩晕: stun_until 不动; 带免控(cc_immune_until)也照样定住
##   ② 射程 420 码: 正前方 600 码的敌人一道都打不到; 300 码的被打到(分母)
##   ③ 打中谁在【飞到时】判: 发射后目标立刻走出弹道 ⇒ 打不中
##   ④ 方向随机(走 _battle_rng): 两个敌人分在两侧, 10 道里两边都被选中过, 且不是 1:1 严格交替(原来是 es[i % size] 轮流)
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
	for k in ["shield", "flat_dr", "def", "mr", "base_def", "base_mr", "dodge_bonus", "damage_amp", "crit", "damage_reduction"]:
		u[k] = 0.0
	u["maxHp"] = 100000.0
	u["hp"] = 100000.0
	u["atk"] = 100.0
	u["no_basic"] = true
	u["no_move"] = true
	u["eq_state"] = {}
	return u


## 推进 sim 时间与延时队列(打击全程 = 10 波 × 0.15 + 满程飞行 1.1 秒, 走 3 秒足够)
func _run(sec: float, mover = null) -> void:
	var dt := 0.025
	var n := int(sec / dt)
	for i in range(n):
		_s._t += dt
		_s._ballistics._step_pending_shots(dt)
		if mover != null:
			(mover as Callable).call()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_node("/root/GameState").test_mode = true
	print("=== 小龟·打击 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s._edit_mode = false
	_s._over = false
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5

	print("--- ① 施法定身不是眩晕 ---")
	var u := _mk("basic", "left", c)
	var e := _mk("green", "right", c + Vector2(300, 0))
	_s._units.clear()
	_s._units.append_array([u, e])
	_s._pending_shots.clear()
	u["cc_immune_until"] = _s._t + 999.0
	_s._sk_basic_strike(u)
	_ok("①a 施法定身生效(channel_until > 现在), 带免控也一样", float(u.get("channel_until", 0.0)) > _s._t,
		"channel_until=%.2f t=%.2f" % [float(u.get("channel_until", 0.0)), _s._t])
	_ok("①b 没有给自己上眩晕(不吃易碎、不显示眩晕)", float(u.get("stun_until", 0.0)) <= _s._t,
		"stun_until=%.2f" % float(u.get("stun_until", 0.0)))

	print("--- ② 射程 420 码 ---")
	var hp0: float = e["hp"]
	_run(3.0)
	var lost_near: float = hp0 - float(e["hp"])
	_ok("②a ★分母: 300 码正前方的敌人被打到了", lost_near > 1.0, "掉 %.0f" % lost_near)
	var u2 := _mk("basic", "left", c)
	var far := _mk("green", "right", c + Vector2(600, 0))
	_s._units.clear()
	_s._units.append_array([u2, far])
	_s._pending_shots.clear()
	_s._sk_basic_strike(u2)
	_run(3.0)
	_ok("②b 600 码正前方的敌人一道都打不到(原来不看距离 = 全场射程)", float(far["hp"]) >= 100000.0 - 0.01,
		"掉 %.0f" % (100000.0 - float(far["hp"])))

	print("--- ③ 打中谁在飞到时判 ---")
	var u3 := _mk("basic", "left", c)
	var mv := _mk("green", "right", c + Vector2(380, 0))
	_s._units.clear()
	_s._units.append_array([u3, mv])
	_s._pending_shots.clear()
	_s._sk_basic_strike(u3)
	## 第一道刚发出(t=0)就把目标挪出弹道(侧移 300 码), 之后每道发射时它都不在原方向上 ——
	##   但 _targetable_enemies 会让后续几道改朝它新位置打 ⇒ 只验【第一道】: 0.05 秒后挪走, 走 1.2 秒(第一道满程)
	var moved := [false]
	_run(0.05)
	mv["pos"] = c + Vector2(380, 300)
	_s._pending_shots = _s._pending_shots.filter(func(p): return float(p.get("delay", 0.0)) < 0.06)   # 只留第一道的弹体推进
	_run(1.3)
	_ok("③ 第一道发射后目标走出弹道 ⇒ 没打中(原来发射瞬间定好打谁, 走开照样中)",
		float(mv["hp"]) >= 100000.0 - 0.01, "掉 %.0f" % (100000.0 - float(mv["hp"])))

	print("--- ④ 方向随机 ---")
	var u4 := _mk("basic", "left", c)
	var up := _mk("green", "right", c + Vector2(200, -150))
	var dn := _mk("green", "right", c + Vector2(200, 150))
	_s._units.clear()
	_s._units.append_array([u4, up, dn])
	_s._pending_shots.clear()
	_s._battle_rng.seed = 12345
	var hits_up := [0]
	var hits_dn := [0]
	var seq: Array = []
	var hu0: float = up["hp"]
	var hd0: float = dn["hp"]
	_s._sk_basic_strike(u4)
	var lu := [hu0]
	var ld := [hd0]
	_run(3.0, func() -> void:
		if float(up["hp"]) < lu[0] - 0.5:
			hits_up[0] += 1; seq.append("U"); lu[0] = float(up["hp"])
		if float(dn["hp"]) < ld[0] - 0.5:
			hits_dn[0] += 1; seq.append("D"); ld[0] = float(dn["hp"]))
	var alt := true
	for k in range(1, seq.size()):
		if seq[k] == seq[k - 1]:
			alt = false
	_ok("④a ★分母: 10 道里两边都被打到过", hits_up[0] > 0 and hits_dn[0] > 0, "上 %d · 下 %d · 序列 %s" % [hits_up[0], hits_dn[0], "".join(seq)])
	_ok("④b 不是严格轮流交替(原来 es[i % size] = UDUDUD…)", seq.size() >= 4 and not alt, "序列 %s" % "".join(seq))

	print("=== %d 项, FAIL %d ===" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)
