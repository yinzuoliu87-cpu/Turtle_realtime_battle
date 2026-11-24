extends Node
## 探针(2026-11-15, 不是门禁): 每件商店装备 3★ 实打一局, 看它的「本局」统计记下了什么。
## 用户 11-15:「蓄电池…装备统计现在啥都没有…应该是…已获得龟能这样子的东西」「辣椒…施加流血层数是多少多少层」。
## 我方血量 ×3、打 60 秒(原血量十来秒就死, 撑伞 / 受击转化 / 低血触发类来不及生效)。
## 做法: 调试场(DEBUG_EDIT)摆 携带者 basic(左, 带这件 3★) + 队友 stone(左) vs 敌人 3 只(右, 会打会走; 一只残血好触发击杀 / 处决),
##   第 60 步给携带者灌满法力(【法力】类装备才放得出来), 打 SWEEP_STEPS 步, 读携带者 `_st_eq` 里这件那一行。
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/probes/_probe_eq_tally_sweep.tscn --quit-after 400000
##   SWEEP_ONLY=p2eq_085,p2eq_002 只跑这几件; 输出 .out/eq_tally_sweep.tsv(id / 名字 / 统计键=值)。

const SIM_DT := 1.0 / 60.0
const SWEEP_STEPS := 3600   # 60 秒: 我方血量 ×3 后约在后半段掉到三成以下(低血触发类装备要)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var only := OS.get_environment("SWEEP_ONLY")
	var ids: Array = []
	for e in DataRegistry.phase2_equipment:
		var d: Dictionary = e
		if int(d.get("shopAvailable", 0)) != 1:
			continue
		if only != "" and not (only.split(",") as PackedStringArray).has(str(d["id"])):
			continue
		ids.append([str(d["id"]), str(d["name"])])
	var lines: Array = []
	for pair in ids:
		## 两种场景取并集: A 耐打(我方血 ×6、60 秒: 周期 / 受击类有时间生效) · B 脆皮(原血量、30 秒: 阵亡 / 低血触发类)
		var row: Dictionary = await _one(str(pair[0]), 6.0, 3600)
		var rb: Dictionary = await _one(str(pair[0]), 1.0, 1800)
		for kb in rb:
			row[kb] = maxf(float(row.get(kb, 0.0)), float(rb[kb]))
		var parts: Array = []
		var ks: Array = row.keys()
		ks.sort()
		for k in ks:
			parts.append("%s=%d" % [k, int(round(float(row[k])))])
		var line := "%s\t%s\t%s" % [pair[0], pair[1], " ".join(parts) if not parts.is_empty() else "(空)"]
		print("[SWEEP] ", line)
		lines.append(line)
	var f := FileAccess.open(ProjectSettings.globalize_path("res://.out/eq_tally_sweep.tsv"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	print("SWEEP DONE %d" % lines.size())
	get_tree().quit(0)


func _one(eid: String, hp_mult: float, steps: int) -> Dictionary:
	OS.set_environment("TURTLE_SEED", "424242")
	var RB = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	RB.DEBUG_EDIT = true
	var s = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	s._debug._edit_clear()
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 9000.0
	s._edit_full_energy = false
	var car: Dictionary = s._debug._edit_place_unit("basic", "left", Vector2(420.0, 360.0))
	car["_edit_equips"] = [{"id": eid, "star": 3}]
	s._debug._edit_place_unit("stone", "left", Vector2(360.0, 460.0))
	var foes: Array = []
	for p in [["basic", Vector2(820.0, 330.0)], ["stone", Vector2(860.0, 430.0)], ["bamboo", Vector2(900.0, 260.0)]]:
		foes.append(s._debug._edit_place_unit(str(p[0]), "right", p[1]))
	s._debug._edit_start_battle()
	s.set_process(false)
	## 敌人放开: 会走会普攻(调试场默认是不动的假人), 第三只残血(击杀 / 处决类装备要有人死)
	var k := 0
	for u in s._units:
		if u is Dictionary and str(u.get("side", "")) == "right":
			u.erase("no_basic")
			u.erase("no_move")
			if k == 2:
				u["hp"] = 1200.0
			k += 1
	## 我方血量 ×3: 原血量十来秒就被三只敌人打死, 撑伞 / 受击转化 / 低血触发类来不及生效
	for u in s._units:
		if u is Dictionary and str(u.get("side", "")) == "left":
			u["maxHp"] = float(u["maxHp"]) * hp_mult
			u["hp"] = u["maxHp"]
	var c = null
	for u in s._units:
		if u is Dictionary and str(u.get("side", "")) == "left" and str(u.get("id", "")) == "basic":
			c = u
	for i in range(steps):
		if i == 60 and c is Dictionary and s.get("_staff_syn") != null:
			s._staff_syn.add_mana(c, 99999.0)
		s._sim_step(SIM_DT, float(s._hitstop) > 0.0, not (s._timestop._ts_active as Array).is_empty())
		if i % 300 == 0:
			await get_tree().process_frame
	var out: Dictionary = {}
	if OS.get_environment("SWEEP_DIAG") != "":
		for u in s._units:
			if u is Dictionary:
				print("   [诊断] %s %s alive=%s hp=%.0f/%.0f 承伤=%.0f 造成=%.0f no_basic=%s" % [str(u.get("side")), str(u.get("id")), str(u.get("alive")), float(u.get("hp", 0)), float(u.get("maxHp", 0)), float(u.get("_st_taken", 0)), float(u.get("_st_dealt", 0)), str(u.get("no_basic", false))])
	if OS.get_environment("SWEEP_DIAG") != "" and c is Dictionary:
		print("   [诊断] eq_state=%s  _st_eq=%s" % [str(c.get("eq_state", {})).left(400), str(c.get("_st_eq", {})).left(300)])
	if c is Dictionary:
		var t: Dictionary = c.get("_st_eq", {})
		for iid in t:
			if EquipCk.base_id(str(iid)) != eid:
				continue
			for kk in (t[iid] as Dictionary):
				out[kk] = float(out.get(kk, 0.0)) + float(t[iid][kk])
	OS.set_environment("TURTLE_SEED", "")
	s.queue_free()
	RB.DEBUG_EDIT = false
	await get_tree().process_frame
	await get_tree().process_frame
	return out
