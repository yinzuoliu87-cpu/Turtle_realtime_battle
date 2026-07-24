extends Node
## verify_combat_math.gd — combat/ 通用小算式模块 CombatMath(去重 9 处)
## decay_stacks(3处) / hp_frac(4处) / cooldown_ready(2处)。
## 守: 已知例 + 边界 + 与 god file 原式逐位一致(采样)。prove-fail 见各系数。

var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	# ① decay_stacks = floori(stacks * 0.8)
	_ok("decay 10 → 8", CombatMath.decay_stacks(10) == 8)
	_ok("decay 5 → 4 (floori 4.0)", CombatMath.decay_stacks(5) == 4)
	_ok("decay 3 → 2 (floori 2.4)", CombatMath.decay_stacks(3) == 2)
	_ok("decay 1 → 0 (floori 0.8)", CombatMath.decay_stacks(1) == 0)
	_ok("decay 0 → 0", CombatMath.decay_stacks(0) == 0)
	var md := 0
	for s in range(0, 200):
		if CombatMath.decay_stacks(s) != floori(s * 0.8): md += 1
	_ok("★decay 与原式 200 逐位一致(N=200)", md == 0, "分歧 %d/200" % md)

	# ② hp_frac = hp / maxf(1.0, maxHp)
	_ok("hp_frac 50/100 → 0.5", is_equal_approx(CombatMath.hp_frac(50.0, 100.0), 0.5))
	_ok("hp_frac 0/100 → 0.0", is_equal_approx(CombatMath.hp_frac(0.0, 100.0), 0.0))
	_ok("hp_frac 5/0 → 5.0 (分母钳1防除零)", is_equal_approx(CombatMath.hp_frac(5.0, 0.0), 5.0))
	var mh := 0
	for _i in range(200):
		var hp := randf() * 500.0
		var mx := randf() * 500.0
		if not is_equal_approx(CombatMath.hp_frac(hp, mx), hp / maxf(1.0, mx)): mh += 1
	_ok("★hp_frac 与原式 200 采样逐位一致(N=200)", mh == 0, "分歧 %d/200" % mh)

	# ③ cooldown_ready = clampf(1 - cd/maxf(0.01,max_cd), 0, 1)
	_ok("cd_ready cd=0 → 1.0 (就绪)", is_equal_approx(CombatMath.cooldown_ready(0.0, 5.0), 1.0))
	_ok("cd_ready cd=max → 0.0 (刚放)", is_equal_approx(CombatMath.cooldown_ready(5.0, 5.0), 0.0))
	_ok("cd_ready cd=半 → 0.5", is_equal_approx(CombatMath.cooldown_ready(2.5, 5.0), 0.5))
	_ok("cd_ready cd>max → 钳0", is_equal_approx(CombatMath.cooldown_ready(9.0, 5.0), 0.0))
	var mc := 0
	for _j in range(200):
		var cd := randf() * 8.0
		var mxcd := randf() * 8.0
		if not is_equal_approx(CombatMath.cooldown_ready(cd, mxcd), clampf(1.0 - (cd / maxf(0.01, mxcd)), 0.0, 1.0)): mc += 1
	_ok("★cd_ready 与原式 200 采样逐位一致(N=200)", mc == 0, "分歧 %d/200" % mc)

	print("ALL PASS — CombatMath(decay/hp_frac/cd_ready·抽SIM模块·去重9处·与原式一致)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
