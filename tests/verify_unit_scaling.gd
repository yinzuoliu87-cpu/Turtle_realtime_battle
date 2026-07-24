extends Node
## verify_unit_scaling.gd — 结构治理 combat/ 模块: UnitScaling.level_multiplier
## 等级乘数(每级+5%)从 god file 抽出(原 2 处 3278/3464 逐字重复)。
## 守: 已知例 + 边界 + 与原式 200 采样逐位一致。prove-fail: 0.05→0.06 红。

var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	_ok("lvl=1 → 1.0 (基准·不缩放)", is_equal_approx(UnitScaling.level_multiplier(1), 1.0))
	_ok("lvl=2 → 1.05", is_equal_approx(UnitScaling.level_multiplier(2), 1.05))
	_ok("lvl=11 → 1.5 (每级+5%·10级=+50%)", is_equal_approx(UnitScaling.level_multiplier(11), 1.5))
	_ok("lvl=21 → 2.0", is_equal_approx(UnitScaling.level_multiplier(21), 2.0))

	var mism := 0
	for lvl in range(1, 201):
		var got := UnitScaling.level_multiplier(lvl)
		var ref := 1.0 + 0.05 * float(lvl - 1)   # ← god file 原地公式
		if not is_equal_approx(got, ref):
			mism += 1
	_ok("★与原公式 200 级逐位一致(N=200)", mism == 0, "分歧 %d/200" % mism)

	print("ALL PASS — UnitScaling.level_multiplier(抽SIM模块·去重2处·与原式一致)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
