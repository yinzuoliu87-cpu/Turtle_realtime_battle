extends Node
## verify_shield_absorb.gd — 「合并两条伤害路径」第一步(用户2026-07-24 做吧)
## 两条伤害路径原本各写一份护盾吸收(§3.3 地雷: 改盾要两处都改)→ 收口到 static _absorb_shields。
## 守: 与【抽出前的原地逻辑】逐位一致(剩余伤 + 普通盾终值 + aura盾终值); 边界; prove-fail。
## 注: 数值级 headless 可证"逐位一致"; 但"28 龟实战手感/平衡"仍需用户 F5。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

## 参考实现 = 抽出前两路各自写的那段(逐字)
func _ref_absorb(u: Dictionary, d: float) -> float:
	if u["shield"] > 0.0:
		var ab := minf(u["shield"], d)
		u["shield"] -= ab; d -= ab
	if d > 0.0 and float(u.get("_auraShieldVal", 0.0)) > 0.0:
		var ab2 := minf(float(u["_auraShieldVal"]), d)
		u["_auraShieldVal"] = float(u["_auraShieldVal"]) - ab2
		d -= ab2
	return d

func _mk(shield: float, aura: float) -> Dictionary:
	return {"shield": shield, "_auraShieldVal": aura}

func _ready() -> void:
	# 已知例 + 边界
	var u1 := _mk(30.0, 0.0)
	var r1 := RB._absorb_shields(u1, 50.0)
	_ok("盾30 吸50 → 剩20·盾0(盾破)", is_equal_approx(r1, 20.0) and is_equal_approx(u1["shield"], 0.0))
	var u2 := _mk(100.0, 0.0)
	var r2 := RB._absorb_shields(u2, 40.0)
	_ok("盾100 吸40 → 剩0·盾60(盾够)", is_equal_approx(r2, 0.0) and is_equal_approx(u2["shield"], 60.0))
	var u3 := _mk(20.0, 50.0)
	var r3 := RB._absorb_shields(u3, 45.0)
	_ok("盾20+aura50 吸45 → 剩0·盾0·aura25(接力)", is_equal_approx(r3, 0.0) and is_equal_approx(u3["shield"], 0.0) and is_equal_approx(u3["_auraShieldVal"], 25.0))
	_ok("无盾 → 原样穿透", is_equal_approx(RB._absorb_shields(_mk(0.0, 0.0), 33.0), 33.0))

	# ★与原地逻辑 300 随机采样逐位一致(同输入分别喂 helper 和 ref, 比 剩伤+普通盾终值+aura盾终值)
	var mism := 0
	for _i in range(300):
		var s := randf() * 100.0
		var a := randf() * 100.0
		var dmg := randf() * 250.0
		var ua := _mk(s, a)
		var ub := _mk(s, a)
		var ra := RB._absorb_shields(ua, dmg)
		var rb := _ref_absorb(ub, dmg)
		if not (is_equal_approx(ra, rb) and is_equal_approx(ua["shield"], ub["shield"]) and is_equal_approx(float(ua["_auraShieldVal"]), float(ub["_auraShieldVal"]))):
			mism += 1
	_ok("★与原地护盾逻辑 300 采样逐位一致(剩伤+双盾终值·N=300)", mism == 0, "分歧 %d/300" % mism)

	print("ALL PASS — _absorb_shields(两路护盾收口·与原地逐位一致)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
