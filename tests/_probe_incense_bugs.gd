extends Node
## 探针(不是门禁, `_` 开头不进自动发现): 093 香火石 2026-10-23 用户「香火石有bug啊」→「还有呢」
## P1 一局里不满一道痕的充能零头, 有没有写进存档
## P3 同一只龟带两块香火石: 一次攻击消耗几次强化

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Inc := preload("res://scripts/systems/equip/incense_stone_system.gd")


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var inc = s._equip_sys._incense
	var m0: int = int(GameState.incense_marks)
	var c0: int = int(GameState.incense_charge)
	GameState.incense_marks = 0
	GameState.incense_charge = 0

	var u: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-120, 0))
	u["atk"] = 100.0
	var e: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(120, 0))
	e["maxHp"] = 1.0e9
	e["hp"] = 1.0e9
	s._units.clear()
	s._units.append_array([u, e])
	s._edit_mode = false
	s._over = false
	u["equips"] = [{"id": Inc.EID, "star": 1}]
	u["eq_state"] = {Inc.EID: {}}
	s._equip_sys._stats._eq_apply_all_stats()
	s._sim_step(1.0 / 60.0, false, false)

	print("── P1 充能零头 ──")
	s._damage._apply_damage_from(u, e, 2500, Color.RED, 0.0, true)
	s._sim_step(1.0 / 60.0, false, false)
	print("P1a 打 2500(不满一道): 局内充能 %d · 存档充能 %d · 刻痕 %d" % [
		int(inc._chg.get("left", 0)), int(GameState.incense_charge), inc.marks_of("left")])
	s._damage._apply_damage_from(u, e, 1500, Color.RED, 0.0, true)
	s._sim_step(1.0 / 60.0, false, false)
	print("P1b 再打 1500(凑满第一道): 局内充能 %d · 存档充能 %d · 刻痕 %d · 存档刻痕 %d" % [
		int(inc._chg.get("left", 0)), int(GameState.incense_charge), inc.marks_of("left"), int(GameState.incense_marks)])
	s._damage._apply_damage_from(u, e, 3000, Color.RED, 0.0, true)
	s._sim_step(1.0 / 60.0, false, false)
	print("P1c 再打 3000(这局就此结束): 局内充能 %d · 存档充能 %d ⇒ 结束时丢掉 %d" % [
		int(inc._chg.get("left", 0)), int(GameState.incense_charge),
		int(inc._chg.get("left", 0)) - int(GameState.incense_charge)])

	print("── P3 同一只龟两块香火石 ──")
	var t: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-200, 60))
	t["atk"] = 100.0
	t["equips"] = [{"id": Inc.EID, "star": 1}, {"id": Inc.EID, "star": 1}]
	t["eq_state"] = {Inc.EID: {}}
	s._units.append(t)
	s._equip_sys._stats._eq_apply_all_stats()
	s._sim_step(1.0 / 60.0, false, false)
	var asp0: float = float(t.get("aspd_perm", 1.0))
	var stt: Dictionary = t["eq_state"][Inc.EID]
	stt["emp_t"] = Inc.EMP_IV - 0.001
	inc.tick_unit(t, 0.01)
	print("P3 强化触发: emp=%d · 攻速乘子 %.2f → %.2f" % [int(stt.get("emp", 0)), asp0, float(t.get("aspd_perm", 1.0))])
	var hp0: float = float(e["hp"])
	for k in range(4):
		s._equip_sys._eq_on_basic_attack(t, e)
		print("   第 %d 次攻击后: 剩余强化 %d · 待兑现附带 %d · 攻速乘子 %.2f" % [k + 1,
			int(stt.get("emp", 0)), int(stt.get("hit_pending", 0)), float(t.get("aspd_perm", 1.0))])

	GameState.incense_marks = m0
	GameState.incense_charge = c0
	get_tree().quit()
