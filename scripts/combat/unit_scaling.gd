class_name UnitScaling
extends RefCounted
## 单位/召唤体的属性缩放 (SIM · 无节点 · 可 headless 单测) —— 结构治理 combat/ 模块之一。
## 与 DamageMath 同族: 把 god file 里的纯算式抽出、去重、可单测。

## 等级乘数: 每级 +5%(1 级 = 1.0×; 2 级 = 1.05×; 11 级 = 1.5×)。
## lvl 已含临时等级(糖果罐 temp_level_bonus)等修正——由调用方算好后传入, 本函数只做纯乘数。
## 与 god file 原地公式逐字一致(原散在 2 处: _lvl_mult_for 3278 · _make_unit 3464)。
static func level_multiplier(lvl: int) -> float:
	return 1.0 + 0.05 * float(lvl - 1)
