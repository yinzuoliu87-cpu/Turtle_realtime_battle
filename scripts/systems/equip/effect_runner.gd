class_name EffectRunner
extends RefCounted
## 装备效果解释器 —— 读 EquipEffects.specs()(数据)执行(A1 · 2026-11-04 · 方案书 20261102b §8.4)。
## ★动作仍调现有的共用函数(_queue_shots / _eq_first_in_line / _spawn_eq_bolt / _atk_dmg), 调用顺序与原手写函数逐行相同
##   ⇒ 同种子同结果(verify_rules_fingerprint 守)。在 _sim_step 调用链上 ⇒ 住 systems/equip/, 数学走 DetMath。

var battle
var eq   # EquipSystem: _eq_first_in_line / _eq_farthest_enemies 住那里


func _init(b, e) -> void:
	battle = b
	eq = e


static func has(iid: String) -> bool:
	return EquipEffects.specs().has(iid)


func fire(u: Dictionary, iid: String, si: int) -> void:
	var sp: Dictionary = EquipEffects.specs()[iid]
	match str(sp["action"]):
		"volley":
			_volley(u, iid, si, sp)
		_:
			push_error("EffectRunner: 未知动作 %s (%s)" % [str(sp["action"]), iid])


## 朝一个方向连射 N 发, 每发打直线上第一个敌人。
func _volley(u: Dictionary, iid: String, si: int, sp: Dictionary) -> void:
	if not u.get("alive", false): return
	var dir: Vector2
	match str(sp["aim"]):
		"nearest":
			var t = battle._targeting._nearest_enemy(u)
			dir = DetMath.norm((t["pos"] - u["pos"])) if t != null else Vector2.RIGHT
		"farthest":
			var far: Array = eq._eq_farthest_enemies(u, false)
			if far.is_empty(): return
			dir = DetMath.norm((far[0]["pos"] - u["pos"]))
		_:
			push_error("EffectRunner: 未知瞄准 %s (%s)" % [str(sp["aim"]), iid])
			return
	var band: float = float(sp["band"])
	var dm: Dictionary = sp["dmg"]
	var fx: Dictionary = sp["fx"]
	var tex: String = str(fx["tex"])
	var col := Color(str(fx["col"]))
	var flash := Color(str(fx["flash"]))
	var psize: float = float(fx.get("psize", 0.032))
	var fire_one := func():
		if not u.get("alive", false): return
		var ft = eq._eq_first_in_line(u, dir, band)
		if ft == null: return
		var coef: float
		if dm.has("coef"):
			coef = float((dm["coef"] as Array)[si])
		else:
			var lr: Array = dm["lost_hp_lerp"]
			var lost: float = clampf((1.0 - ft["hp"] / ft["maxHp"]) / float(lr[2]), 0.0, 1.0)
			coef = DetMath.flerp(float(lr[0]), float(lr[1]), lost)
		battle._muzzle_flash(u["pos"], dir, flash)
		battle._spawn_eq_bolt(u, ft, battle._atk_dmg(u, coef, ft), tex, col, false, 0, psize)
	battle._queue_shots(int((sp["shots"] as Array)[si]), float(sp["gap"]), fire_one, u, iid)
