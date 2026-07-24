extends Node
## verify_damage_math.gd — 结构治理·切片2 模式验证
## DamageMath.crit_multiplier: 从 god file 抽出的暴击倍率纯函数(原逐字散在 3 处)。
## 守: ①已知算例 ②边界(不暴击/恰100%/溢出) ③与 god file 原地公式【200 随机采样逐位一致】
##     —— 证明"抽出后语义没漂"。prove-fail: 改坏 *1.5 → 已知例 + 采样一致 全红。

var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	# ① 已知算例 + 边界
	_ok("crit=1.2, cd=1.5 → 1.8 (溢出0.2×1.5)", is_equal_approx(DamageMath.crit_multiplier(1.2, 1.5), 1.8))
	_ok("crit=0.5, cd=1.5 → 1.5 (未溢出·暴击率不改倍率)", is_equal_approx(DamageMath.crit_multiplier(0.5, 1.5), 1.5))
	_ok("crit=1.0(恰100%), cd=2.0 → 2.0 (边界·溢出0)", is_equal_approx(DamageMath.crit_multiplier(1.0, 2.0), 2.0))
	_ok("crit=2.0(200%), cd=1.5 → 3.0 (溢出1.0×1.5)", is_equal_approx(DamageMath.crit_multiplier(2.0, 1.5), 3.0))
	_ok("crit=0.0, cd=1.5 → 1.5", is_equal_approx(DamageMath.crit_multiplier(0.0, 1.5), 1.5))

	# ③ 与 god file 原地公式 200 随机采样逐位一致(抽出没改语义的硬证据)
	var mism := 0
	for _i in range(200):
		var c := randf() * 3.0                       # 0..300% 暴击率
		var cd := 1.0 + randf() * 2.0                # 1.0..3.0 暴伤
		var got := DamageMath.crit_multiplier(c, cd)
		var ref := cd + maxf(0.0, c - 1.0) * 1.5     # ← god file 原地公式(逐字)
		if not is_equal_approx(got, ref):
			mism += 1
	_ok("★暴击·与原公式 200 随机采样逐位一致(N=200)", mism == 0, "分歧 %d/200" % mism)

	# ④ resist_multiplier(护甲/魔抗减伤曲线·原逐字散在3处 9075/9094/18817)
	_ok("resist=0 → 1.0 (无护甲不减)", is_equal_approx(DamageMath.resist_multiplier(0.0), 1.0))
	_ok("resist=40 → 0.5 (等于常数K·减半)", is_equal_approx(DamageMath.resist_multiplier(40.0), 0.5))
	_ok("resist=120 → 0.25 (1-120/160)", is_equal_approx(DamageMath.resist_multiplier(120.0), 0.25))
	_ok("resist=-40 → 1.5 (负护甲增伤)", is_equal_approx(DamageMath.resist_multiplier(-40.0), 1.5))
	var mism2 := 0
	for _j in range(200):
		var resist := -100.0 + randf() * 400.0        # -100..300 净抗性(含负护甲)
		var got := DamageMath.resist_multiplier(resist)
		var ref := (1.0 - resist / (resist + 40.0)) if resist >= 0.0 else (1.0 + absf(resist) / (absf(resist) + 40.0))  # ← god file 原地公式
		if not is_equal_approx(got, ref):
			mism2 += 1
	_ok("★减伤曲线·与原公式 200 随机采样逐位一致(N=200)", mism2 == 0, "分歧 %d/200" % mism2)

	# ⑤ effective_resist(穿透后净抗性·原逐字散在3处 9071/9074/9093)
	_ok("base=100, 无穿透 → 100", is_equal_approx(DamageMath.effective_resist(100.0, 0.0, 0.0), 100.0))
	_ok("base=100, 30%穿 → 70", is_equal_approx(DamageMath.effective_resist(100.0, 0.3, 0.0), 70.0))
	_ok("base=100, 30%穿+10固定 → 60", is_equal_approx(DamageMath.effective_resist(100.0, 0.3, 10.0), 60.0))
	_ok("base=20, 50%穿+20固定 → -10 (过穿为负→增伤)", is_equal_approx(DamageMath.effective_resist(20.0, 0.5, 20.0), -10.0))
	var mism3 := 0
	for _k in range(200):
		var base := randf() * 200.0
		var pct := randf() * 0.8
		var flat := randf() * 50.0
		var got := DamageMath.effective_resist(base, pct, flat)
		var ref := base * (1.0 - pct) - flat                  # ← god file 原地公式
		if not is_equal_approx(got, ref):
			mism3 += 1
	_ok("★穿透式·与原公式 200 随机采样逐位一致(N=200)", mism3 == 0, "分歧 %d/200" % mism3)

	print("ALL PASS — DamageMath(暴击/减伤曲线/穿透·抽SIM模块·9处去重·与原式逐位一致)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
