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
	_ok("★与原公式 200 随机采样逐位一致(N=200)", mism == 0, "分歧 %d/200" % mism)

	print("ALL PASS — DamageMath.crit_multiplier(抽出SIM模块·3处去重·与原式一致)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
