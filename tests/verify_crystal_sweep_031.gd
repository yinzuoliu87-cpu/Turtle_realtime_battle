extends Node
## verify_crystal_sweep_031.gd — 031 迷你水晶球B 扫描的【直接判据】(2026-08-14)
##
## ★由来: 031 的结算原本挂在 `tween_method` 上, **tween 在无头下推不动** ⇒ 门禁量不到。
##   我先用"同窗 A/B 隔离"想绕过去 —— 本地判绿、**CI 判红**(两个值在两次运行间互换),
##   实测三次 0.979/0.840、0.840/0.840、1.118/1.257 **不同向** ⇒ 那是噪声不是信号。
##   绕不过去, 所以做了产品改动: 把扫描推进搬到 `CrystalSystem.tick`(sim 时钟),
##   缓动照抄 Godot 的 `TRANS_CUBIC + EASE_IN_OUT` 原式, 观感不变。
##
## ★★本条用【直接判据】而不是 A/B: 静音战场里除了这件装备**没有任何东西能造成伤害**,
##   所以敌人掉多少血就是它打的。裕度极大, 不必和噪声较劲。
##   (教训: 判据不稳时先问"能不能换一个裕度大的量", 而不是继续调阈值。)

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Crystal := preload("res://scripts/systems/skills/crystal_system.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	print("=== 031 水晶球B 扫描: 直接判据 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var cry = s._crystal_sys

	var u: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-60, 0))
	u["atk"] = 200.0
	u["no_basic"] = true
	u["no_move"] = true
	u["equips"] = [{"id": "p2eq_031", "star": 3}]
	u["eq_state"] = {"p2eq_031": {}}
	var es: Array = []
	for i in range(4):
		var e: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(60.0 + 50.0 * float(i), 0))
		e["maxHp"] = 1.0e7
		e["hp"] = 1.0e7
		e["no_basic"] = true
		e["no_move"] = true
		es.append(e)
	s._units.clear()
	s._units.append(u)
	s._units.append_array(es)
	s._edit_mode = false
	s._over = false
	s._equip_sys._stats._eq_apply_all_stats()

	var hp0 := 0.0
	for e2 in es:
		hp0 += float(e2["hp"])
	_ok("★分母: 开场没有正在进行的扫描", cry._sweeps.is_empty(),
		"扫描 %d 条" % cry._sweeps.size())

	# ── 走真入口: 灌满法力 ⇒ 登记一条扫描 ──────────────────────────────────
	s._staff_syn.add_mana(u, s._staff_syn.mana_full_for(u, "p2eq_031", 3) + 1.0)
	_ok("★★法力满 ⇒ 登记了一条扫描(结算走 sim 时钟, 不是 tween)",
		cry._sweeps.size() == 1, "扫描 %d 条" % cry._sweeps.size())

	# ── 推进【纯 sim 时钟】, 一帧真实帧都不等 ──────────────────────────────
	##   ★这是本次产品改动的验收点: 改之前 tween 驱动, 只推 sim 时钟它一动不动。
	for _f in range(int(Crystal.SWEEP_SEC * 60.0) + 12):
		s._sim_step(1.0 / 60.0, false, false)
	var hp1 := 0.0
	for e3 in es:
		hp1 += float(e3["hp"])
	_ok("★★★只推 sim 时钟(不等真实帧)扫描就打出了伤害: %.0f" % (hp0 - hp1),
		hp0 - hp1 > 0.5, "敌血合计 %.0f → %.0f (掉 %.0f)" % [hp0, hp1, hp0 - hp1])
	_ok("★★扫完一圈后自己清场(不残留)", cry._sweeps.is_empty(),
		"扫描 %d 条" % cry._sweeps.size())

	# ── 反面: 法力没满 ⇒ 一条扫描都不该有 ──────────────────────────────────
	var u2: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-160, 0))
	u2["atk"] = 200.0
	u2["no_basic"] = true
	u2["no_move"] = true
	u2["equips"] = [{"id": "p2eq_031", "star": 3}]
	u2["eq_state"] = {"p2eq_031": {}}
	s._units.append(u2)
	s._equip_sys._stats._eq_apply_all_stats()
	s._staff_syn.add_mana(u2, s._staff_syn.mana_full_for(u2, "p2eq_031", 3) * 0.5)
	_ok("★反面: 法力只到一半 ⇒ 不登记扫描", cry._sweeps.is_empty(),
		"扫描 %d 条" % cry._sweeps.size())

	s._units.clear()
	s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 031 水晶球B 扫描")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
