extends Node
## verify_eternal_spear.gd —— 145 永恒之枪重做(11-26 用户设计)
##   ① 进度: 每秒 +4 / 造成或受到 100 伤害 +3, 满 100 出手
##   ② 打生命值最高的敌人, 从场外按速度飞来、碰到才结算: 攻击力 + 目标最大生命两段
##   ③ 击倒滑行 250 码、眩晕 1 秒、滑行伤害按距离分摊、路径上其他敌人各挨一次
##   ④ 免控: 不倒不滑, 转而追加
##   ⑤ 临时生命值(叠加) / 灼烧圈(每秒按圈内敌人最大生命)
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SB := preload("res://scripts/systems/equip/eq_spear_batch.gd")

var _n := 0
var _fail := 0
var _s
var _b


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _mk(side: String, ids: Array = [], dx: float = 0.0, star: int = 1) -> Dictionary:
	var c: Vector2 = _s._arena_center
	var u: Dictionary = _s._spawn._make_unit("green", side, c + Vector2((-150.0 if side == "left" else 150.0) + dx, 0.0))
	for k in ["shield", "crit", "dodge_bonus", "damage_reduction", "damage_amp", "armor_pen", "armor_pen_pct", "magic_pen", "magic_pen_pct"]:
		u[k] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["maxHp"] = 5000.0
	u["hp"] = 5000.0
	u["base_atk"] = 100.0
	u["buffs"] = []
	u["airborne"] = false
	_s._recalc_stats(u)
	var eq: Array = []
	for id in ids:
		eq.append({"id": id, "star": star})
	u["equips"] = eq
	return u


func _field(units: Array) -> void:
	_b.clear_all()
	_s._ballistics._flights.clear()   # 上一段还在天上的枪别飞进下一段
	_s._units.clear()
	_s._units.append_array(units)
	_s._synergy._by_side = {"left": {}, "right": {}}
	for u in units:
		if not (u.get("equips", []) as Array).is_empty():
			_s._equip_sys._stats.apply_unit(u)
		u["_holy_store"] = {}


func _adv(sec: float, units: Array = [], step: float = 0.05) -> void:
	var t := 0.0
	while t < sec - 1e-6:
		_s._t += step
		_b.tick(step)
		for u in units:
			_b.tick_unit(u, step)
		_s._ballistics._step_flights(step)
		_s._ballistics._step_pending_shots(step)
		t += step


func _zero_stats() -> void:
	for k in _b.stat:
		_b.stat[k] = 0


func _hp_lost(u: Dictionary, h0: float) -> float:
	return h0 - float(u["hp"])


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s.set_process(false)
	_s.set_physics_process(false)
	_s._t = 3000.0
	_b = _s._equip_sys._spear_sys
	print("=== 145 永恒之枪 ===")

	## ① 进度: 只靠时间 ⇒ 25 秒满; 24.9 秒还没出手
	var me := _mk("left", ["p2eq_145"])
	var small := _mk("right", [], 0.0)
	var big := _mk("right", [], 120.0)
	_field([me, small, big])
	big["maxHp"] = 9000.0
	big["hp"] = 9000.0
	small["pos"] = Vector2(small["pos"]) + Vector2(0, -160)
	_zero_stats()
	_adv(24.9, [me])
	var before := int(_b.stat["eternal"])
	_adv(0.2, [me])
	_ok("① 只靠时间: 每秒 +4 ⇒ 25 秒满才出手", before == 0 and int(_b.stat["eternal"]) == 1, "%d → %d" % [before, int(_b.stat["eternal"])])
	## 受到 1000 伤害 ⇒ +30
	var me2 := _mk("left", ["p2eq_145"])
	_field([me2])
	_b.on_damaged(me2, null, 1000.0, "p2eq_145", 0)
	_ok("① 受到 1000 点伤害 +30 进度", absf(_b._acc(me2, "eter:p2eq_145") - 30.0) < 0.01, "%.1f" % _b._acc(me2, "eter:p2eq_145"))
	me2["dmg_dealt"] = 2000.0
	_b.tick_unit(me2, 0.0)
	_ok("① 造成 2000 点伤害 +60 进度", absf(_b._acc(me2, "eter:p2eq_145") - 90.0) < 0.01, "%.1f" % _b._acc(me2, "eter:p2eq_145"))

	## ② ③ 飞到才打(生命值最高的 big), 攻击力 + 最大生命两段; 击倒滑行 250 码、眩晕
	_field([me, small, big])
	me["_spear_acc"] = {}
	big["pos"] = _s._arena_center + Vector2(60, 0)
	small["pos"] = _s._arena_center + Vector2(160, 0)   # 正好在滑行路线上(枪从左上方来 ⇒ 往右下滑)
	small["maxHp"] = 5000.0
	small["hp"] = 5000.0
	big["hp"] = 9000.0
	_zero_stats()
	me["_spear_acc"] = {"eter:p2eq_145": 100.0}
	var p0 := Vector2(big["pos"])
	var hb := float(big["hp"])
	_adv(0.05, [me])
	var fired := int(_b.stat["eternal"])
	_adv(0.5, [me])
	_ok("② 飞行中还没打到(按速度飞, 场外 ~1000 码 / 700)", fired == 1 and int(_b.stat["eternal_hit"]) == 0 and float(big["hp"]) == hb)
	_adv(1.6, [me])   # 场外 ~1040 码 / 700 ≈ 1.5 秒到; 再滑 0.5 秒; 灼烧第一跳在命中后 1 秒(还没到)
	var hit_dmg: int = _s._phys_after_armor(me, 1.2 * float(me["atk"]) + 0.04 * 9000.0, big)
	var slide_dmg: int = _s._phys_after_armor(me, 0.4 * float(me["atk"]) + 0.02 * 9000.0, big)
	var moved: float = Vector2(big["pos"]).distance_to(p0)
	_ok("② 打的是生命值最高的、碰到才结算", int(_b.stat["eternal_hit"]) == 1)
	_ok("② ③ 目标掉血 ≈ 命中(攻击 120% + 最大生命 4%) + 滑行(攻击 40% + 最大生命 2%)",
		absf(_hp_lost(big, hb) - float(hit_dmg + slide_dmg)) <= 12.0, "掉 %.0f(应 %d; 滑行按每步分摊, 每步取整最多差 1)" % [_hp_lost(big, hb), hit_dmg + slide_dmg])
	_ok("③ 滑行 250 码(往远离出手方向)", absf(moved - 250.0) < 3.0, "%.1f 码" % moved)
	_ok("③ 路线上的另一个敌人被撞到一次(攻击 80% + 其最大生命 3%)", int(_b.stat["eternal_pass"]) == 1 and float(small["hp"]) < 5000.0,
		"撞 %d · 掉 %.0f" % [int(_b.stat["eternal_pass"]), 5000.0 - float(small["hp"])])

	## ④ 免控: 不倒不滑, 转而追加
	var me3 := _mk("left", ["p2eq_145"])
	var tank := _mk("right", [], 60.0)
	tank["maxHp"] = 9000.0
	tank["hp"] = 9000.0
	tank["cc_immune_until"] = 99999.0
	_field([me3, tank])
	_zero_stats()
	me3["_spear_acc"] = {"eter:p2eq_145": 100.0}
	var tp0 := Vector2(tank["pos"])
	var th := float(tank["hp"])
	_adv(2.0, [me3])
	var imm_dmg: int = _s._phys_after_armor(me3, 1.2 * float(me3["atk"]) + 0.04 * 9000.0, tank) + _s._phys_after_armor(me3, 1.0 * float(me3["atk"]) + 0.04 * 9000.0, tank)
	imm_dmg += int(_b.stat["eternal_burn"]) * _s._resolve_dmg(me3, 9000.0 * 0.02, tank, true, false)   # 2 秒里灼烧圈可能已经跳过
	_ok("④ 免控: 没滑、转而追加(攻击 100% + 最大生命 4%)", int(_b.stat["eternal_imm"]) == 1 and Vector2(tank["pos"]).distance_to(tp0) < 0.5
		and absf(_hp_lost(tank, th) - float(imm_dmg)) <= 3.0, "免控 %d · 掉 %.0f(应 %d)" % [int(_b.stat["eternal_imm"]), _hp_lost(tank, th), imm_dmg])

	## ⑤ 临时生命值 + 灼烧圈
	_ok("⑤ 携带者拿到临时生命值(最大生命 +20%)", float(me3["maxHp"]) > 5000.0 * 1.19, "最大生命 %.0f" % float(me3["maxHp"]))
	var tb := float(tank["hp"])
	var b0 := int(_b.stat["eternal_burn"])
	_adv(3.0, [me3])
	var burn_each: int = _s._resolve_dmg(me3, 9000.0 * 0.02, tank, true, false)
	_ok("⑤ 灼烧圈每秒按圈内敌人最大生命 2% 魔伤(3 秒 3 跳)", int(_b.stat["eternal_burn"]) - b0 == 3 and absf(_hp_lost(tank, tb) - 3.0 * float(burn_each)) <= 3.0,
		"跳 %d · 掉 %.0f(应 %d)" % [int(_b.stat["eternal_burn"]) - b0, _hp_lost(tank, tb), 3 * burn_each])
	_adv(4.0, [me3])
	_ok("⑤ 临时生命值 6 秒后削回", float(me3["maxHp"]) < 5000.0 * 1.01, "最大生命 %.0f" % float(me3["maxHp"]))

	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 145 永恒之枪 (%d 条)" % _n)
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
