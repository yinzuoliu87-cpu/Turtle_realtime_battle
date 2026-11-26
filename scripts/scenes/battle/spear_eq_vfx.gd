class_name SpearEqVfx
extends MaskEqVfx
## spear_eq_vfx.gd —— 长矛羁绊 + 10 件长矛的演出层(2026-11-26 · 方案书 docs/plans/20261126-长矛羁绊.md)。结算全在 sim 侧, 这里只画。
## 继承面具演出层拿帧条工具(_strip / _tick_mfx)。


func tick(delta: float) -> void:
	super.tick(delta)
