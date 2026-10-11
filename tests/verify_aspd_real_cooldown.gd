extends Node
## verify_aspd_real_cooldown.gd —— 攻速加成必须真的让普攻变快(2026-10-11 全项目通读)
##
## ★为什么要有这条: 2026-10-11 全项目通读时, 读码认定普攻冷却那行(`aspd_mult(u) * (A) if 加速中 else B`)
##   因三元优先级「平时不乘 aspd_mult」, 报成了第一号 bug。**探针证明是误报**: 那一行实际算出的冷却
##   就是 间隔 ÷ aspd_mult(永久 ×2 ⇒ 0.5 秒)。同一份代码用 `2.0 * (1.0) if false else 1.0` 这种简化式去推,
##   得到的是另一种结合 —— 读码推不准, 只能量。
## ★原来没有任何门禁量「真实冷却随攻速变」(`verify_aspd_panel_live` ③ 是两边都由测试自己算的恒等式),
##   这条补上: 以后谁改坏那一行, 这里会红。
## ★判据量的是【推 sim 后每次真实出手时设下的冷却】, 不是任何函数的返回值。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null
var _n := 0
var _fail := 0
var _last_n := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


## 摆一对单位(我方攻击者 + 打不死、不还手的靶子), 推 steps 步 sim, 记攻击者每次出手时【真实设下的冷却】。
## 出手 = atk_cd 从低处被重新设高(普攻那一行把它设成整段冷却)。返回这些冷却的平均值(没出手 = -1)。
## ★不数出手次数: 出手前还有一段前摇(不吃攻速), 次数比例不等于攻速比例; 冷却本身才是攻速直接作用的量。
func _count_attacks(setup: Callable, steps: int) -> float:
	_s._units.clear()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var a: Dictionary = _s._spawn._make_unit("basic", "left", c)
	var b: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(70, 0))
	a["atk"] = 1.0
	a["atk_interval"] = 1.0
	b["hp"] = 1.0e9
	b["maxHp"] = 1.0e9
	b["atk"] = 0.0
	setup.call(a)
	_s._units.append(a)
	_s._units.append(b)
	_s._edit_mode = false
	_s._over = false
	var n := 0
	var tot := 0.0
	var prev: float = float(a.get("atk_cd", 0.0))
	for i in range(steps):
		_s._sim_step(_s.SIM_DT, false, false)
		var cd: float = float(a.get("atk_cd", 0.0))
		if cd > prev + 1e-6:
			n += 1
			tot += cd
		prev = cd
	_last_n = n
	return tot / float(n) if n > 0 else -1.0


func _ready() -> void:
	await get_tree().process_frame
	print("=== 攻速加成 ⇒ 真实普攻冷却 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	var steps: int = int(round(12.0 / float(_s.SIM_DT)))   # 12 游戏秒

	var base := _count_attacks(func(_u): pass, steps)
	_ok("★分母: 基础攻速下 12 秒里确实出手多次(≥6), 冷却≈攻击间隔 1.0", _last_n >= 6 and absf(base - 1.0) < 0.05,
		"出手 %d 次, 平均冷却 %.3f 秒" % [_last_n, base])

	var fast := _count_attacks(func(u): u["aspd_perm"] = 2.0, steps)
	var r_fast: float = base / maxf(0.001, fast)
	_ok("★★永久攻速 ×2(装备/羁绊 aspd_perm) ⇒ 冷却缩成 1/2(攻速 ×1.95~2.05)",
		r_fast >= 1.95 and r_fast <= 2.05, "冷却 %.3f → %.3f 秒(攻速 ×%.2f)" % [base, fast, r_fast])

	var slow := _count_attacks(func(u):
		u["spd_aspd_mult"] = 0.5
		u["spd_dbf_until"] = _s._t + 999.0, steps)
	var r_slow: float = base / maxf(0.001, slow)
	_ok("★★减攻速 ×0.5 ⇒ 冷却变成 2 倍(攻速 ×0.48~0.52)",
		r_slow >= 0.48 and r_slow <= 0.52, "冷却 %.3f → %.3f 秒(攻速 ×%.2f)" % [base, slow, r_slow])

	var haste := _count_attacks(func(u):
		u["haste_mult"] = 2.0
		u["haste_until"] = _s._t + 999.0, steps)
	var r_h: float = base / maxf(0.001, haste)
	_ok("★对照: 临时加速 ×2(祝福类) ⇒ 冷却缩成 1/2",
		r_h >= 1.95 and r_h <= 2.05, "冷却 %.3f → %.3f 秒(攻速 ×%.2f)" % [base, haste, r_h])

	var both := _count_attacks(func(u):
		u["aspd_perm"] = 1.5
		u["haste_mult"] = 2.0
		u["haste_until"] = _s._t + 999.0, steps)
	var r_b: float = base / maxf(0.001, both)
	_ok("★永久 ×1.5 与临时 ×2 叠乘 ⇒ 攻速 ×3(2.9~3.1)",
		r_b >= 2.9 and r_b <= 3.1, "冷却 %.3f → %.3f 秒(攻速 ×%.2f)" % [base, both, r_b])

	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
