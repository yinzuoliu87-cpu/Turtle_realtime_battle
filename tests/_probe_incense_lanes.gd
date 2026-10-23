extends Node
## 探针(不是门禁): 093 香火石 —— 上路攒下的刻痕, 换路清场(真 `_dl_clear_units`)后到终极战场还在不在
## 用户 2026-10-23「那如果上半战场叠了20%那到终极战场呢」

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

	# 上路: 携带者 + 空手队友, 打出 N 道刻痕
	var u: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-120, 0))
	var mate: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-180, 40))
	var e: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(120, 0))
	e["maxHp"] = 1.0e9
	e["hp"] = 1.0e9
	s._units.clear()
	s._units.append_array([u, mate, e])
	s._edit_mode = false
	s._over = false
	u["equips"] = [{"id": Inc.EID, "star": 1}]
	u["eq_state"] = {Inc.EID: {}}
	mate["equips"] = []
	mate["eq_state"] = {}
	s._equip_sys._stats._eq_apply_all_stats()
	s._sim_step(1.0 / 60.0, false, false)
	for _k in range(67):
		s._damage._apply_damage_from(u, e, Inc.PER_MARK, Color.RED, 0.0, true)
		s._sim_step(1.0 / 60.0, false, false)
	print("上路: 刻痕 %d · 携带者增伤 %.1f%% 减伤 %.1f%% · 空手队友增伤 %.1f%% 减伤 %.1f%%" % [
		inc.marks_of("left"), float(u.get("damage_amp", 0.0)) * 100.0, float(u.get("damage_reduction", 0.0)) * 100.0,
		float(mate.get("damage_amp", 0.0)) * 100.0, float(mate.get("damage_reduction", 0.0)) * 100.0])

	# 换路: 走真清场, 再按终极战场的方式【新建】单位(幸存名单 → 新字典)
	s._dl_sys._dl_clear_units()
	var u2: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-120, 0))
	var mate2: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-180, 40))
	var e2: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(120, 0))
	e2["maxHp"] = 1.0e9
	e2["hp"] = 1.0e9
	s._units.append_array([u2, mate2, e2])
	u2["equips"] = [{"id": Inc.EID, "star": 1}]
	u2["eq_state"] = {Inc.EID: {}}
	mate2["equips"] = []
	mate2["eq_state"] = {}
	s._equip_sys._stats._eq_apply_all_stats()
	for _k in range(3):
		s._sim_step(1.0 / 60.0, false, false)
	print("终极: 刻痕 %d · 携带者增伤 %.1f%% 减伤 %.1f%% · 空手队友增伤 %.1f%% 减伤 %.1f%%" % [
		inc.marks_of("left"), float(u2.get("damage_amp", 0.0)) * 100.0, float(u2.get("damage_reduction", 0.0)) * 100.0,
		float(mate2.get("damage_amp", 0.0)) * 100.0, float(mate2.get("damage_reduction", 0.0)) * 100.0])

	# 终极战场里【没人带石头】(携带者死在上路)
	s._dl_sys._dl_clear_units()
	var mate3: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-180, 40))
	var e3: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(120, 0))
	s._units.append_array([mate3, e3])
	mate3["equips"] = []
	mate3["eq_state"] = {}
	s._equip_sys._stats._eq_apply_all_stats()
	for _k in range(3):
		s._sim_step(1.0 / 60.0, false, false)
	print("终极(携带者已阵亡、场上无人带石头): 空手队友增伤 %.1f%% 减伤 %.1f%%" % [
		float(mate3.get("damage_amp", 0.0)) * 100.0, float(mate3.get("damage_reduction", 0.0)) * 100.0])

	GameState.incense_marks = m0
	GameState.incense_charge = c0
	get_tree().quit()
