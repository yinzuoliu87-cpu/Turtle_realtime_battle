extends Node
## _probe_slam_mech.gd — 过肩摔体检探针(2026-10-24, 不进门禁): 打具体数值, 不下结论。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BC := preload("res://scripts/gamedata/basic_consts.gd")

var s


func _mk(id: String, side: String, pos: Vector2, hp: float, atk: float = 100.0) -> Dictionary:
	var u: Dictionary = s._spawn._make_unit(id, side, pos)
	u["maxHp"] = hp; u["hp"] = hp; u["shield"] = 0.0; u["flat_dr"] = 0.0
	u["def"] = 0.0; u["mr"] = 0.0; u["base_def"] = 0.0; u["base_mr"] = 0.0
	u["dodge_bonus"] = 0.0; u["damage_reduction"] = 0.0; u["damage_amp"] = 0.0
	u["crit"] = 0.0; u["crit_dmg"] = 1.5; u["buffs"] = []; u["equips"] = []; u["eq_state"] = {}
	u["atk"] = atk; u["active_skills"] = []; u["no_basic"] = true
	s._units.append(u)
	return u


func _run(b: Dictionary, t: Dictionary, hook: Callable = Callable()) -> Dictionary:
	var rec := {"steps": 0, "tv_max": 0.0, "uv_max": 0.0, "flip": false, "tpos": [], "upos": []}
	s._sk_basic_slam(b, t)
	var n := 0
	while n < 400 and bool(b.get("_slam", false)):
		if hook.is_valid(): hook.call(n)
		s._sim_step(s.SIM_DT, false, false)
		n += 1
		rec["tv_max"] = maxf(float(rec["tv_max"]), float((t.get("_slam_voff", Vector3.ZERO) as Vector3).y))
		rec["uv_max"] = maxf(float(rec["uv_max"]), float((b.get("_slam_voff", Vector3.ZERO) as Vector3).y))
		var sp = t.get("sprite", null)
		if is_instance_valid(sp) and (sp as Sprite3D).flip_v: rec["flip"] = true
		(rec["tpos"] as Array).append(t["pos"])
		(rec["upos"] as Array).append(b["pos"])
	rec["steps"] = n
	return rec


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	RB.DEBUG_EDIT = true
	s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s.set_process(false)
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	print("ARENA=", s.ARENA, " center=", c, " edit_mode=", s._edit_mode, " dl_state=", s._dl_state)
	var bonus_tab: Dictionary = s._BASIC_RARITY_BONUS

	# ── ① 基础数值: 主目标 / 溅射 / 眩晕 / 落点 ──
	s._units.clear()
	var b := _mk("basic", "left", c, 99999.0, 100.0)
	var t := _mk("stone", "right", c + Vector2(100, 0), 5000.0)
	var land_pred: Vector2 = c - Vector2(1, 0) * BC.SLAM_LAND_BACK
	var near := _mk("stone", "right", land_pred + Vector2(0, 340), 5000.0)   # 落点 340 码
	var far := _mk("stone", "right", land_pred + Vector2(0, 360), 5000.0)    # 落点 360 码
	var rb: float = float(bonus_tab.get(str(t.get("rarity", "C")), 0.2))
	var t0: float = s._t
	var r := _run(b, t)
	var main_d: float = 5000.0 - float(t["hp"])
	var near_d: float = 5000.0 - float(near["hp"])
	var far_d: float = 5000.0 - float(far["hp"])
	var want_main: float = (100.0 * BC.SLAM_MAIN_ATK + floor(100.0 * BC.SLAM_MAIN_HP_PER_ATK * 5000.0)) * (1.0 + rb)
	var want_spl: float = (100.0 * BC.SLAM_SPLASH_ATK + floor(100.0 * BC.SLAM_SPLASH_HP_PER_ATK * 5000.0)) * (1.0 + rb)
	print("① rarity(t)=%s 不屈=%.2f" % [str(t.get("rarity")), rb])
	print("① steps=%d (=%.3fs) tgt voff max=%.2f  caster voff max=%.2f flip_v seen=%s" % [r["steps"], r["steps"] * s.SIM_DT, r["tv_max"], r["uv_max"], str(r["flip"])])
	print("① 主目标掉血=%.0f 期望(def0)=%.0f | 落点340码=%.0f 期望=%.0f | 360码=%.0f" % [main_d, want_main, near_d, want_spl, far_d])
	print("① 眩晕 stun_until-_t = %.3f (_t=%.3f t0=%.3f)" % [float(t.get("stun_until", 0.0)) - s._t, s._t, t0])
	print("① 落点 tgt=%s 距龟起点=%.1f | 龟终点=%s 距起点=%.1f | 龟-敌终距=%.1f" % [str(t["pos"]), (t["pos"] as Vector2).distance_to(c), str(b["pos"]), (b["pos"] as Vector2).distance_to(c), (b["pos"] as Vector2).distance_to(t["pos"])])
	print("① 结束后 tgt._slam=%s no_move=%s voff=%s" % [str(t.get("_slam")), str(t.get("no_move")), str(t.get("_slam_voff"))])

	# ── ② 护甲 / 减伤 / 虚化 对「最大生命」那一段 ──
	for case in [["def0", 0.0, 0.0, false], ["def100", 100.0, 0.0, false], ["DR50%", 0.0, 0.5, false], ["ghost虚化", 0.0, 0.0, true]]:
		s._units.clear()
		var b2 := _mk("basic", "left", c, 99999.0, 100.0)
		var t2 := _mk("stone", "right", c + Vector2(100, 0), 5000.0)
		t2["def"] = float(case[1]); t2["damage_reduction"] = float(case[2])
		if bool(case[3]): t2["phase_until"] = s._t + 100.0
		var hp0: float = float(t2["hp"])
		_run(b2, t2)
		var d2: float = hp0 - float(t2["hp"])
		# 同一目标只打 ATK 段(1.0A)的参照
		var ref: int = s._atk_dmg(b2, BC.SLAM_MAIN_ATK, t2)
		print("② %-8s 主目标实掉 %.0f | 其中 1.0A 段(_atk_dmg)=%d | 最大生命段裸加=%d" % [str(case[0]), d2, ref, int(100.0 * BC.SLAM_MAIN_HP_PER_ATK * 5000.0)])

	# ── ③ 免控 / 免击飞 目标 ──
	for case in [["cc_immune", true, false], ["knock_immune(017锚)", false, true]]:
		s._units.clear()
		var b3 := _mk("basic", "left", c, 99999.0, 100.0)
		var t3 := _mk("fortune", "right", c + Vector2(100, 0), 5000.0)
		if bool(case[1]): t3["cc_immune_until"] = s._t + 100.0
		if bool(case[2]): t3["_knock_immune"] = true
		var p0: Vector2 = t3["pos"]
		var r3 := _run(b3, t3)
		print("③ %-18s 被挪动=%.1f码 最高腾空voff=%.2f 眩晕剩=%.2f 掉血=%.0f" % [str(case[0]), (t3["pos"] as Vector2).distance_to(p0), r3["tv_max"], float(t3.get("stun_until", 0.0)) - s._t, 5000.0 - float(t3["hp"])])

	# ── ④ 本来就 no_move 的目标(炮台 / 糖果炸弹这类) ──
	s._units.clear()
	var b4 := _mk("basic", "left", c, 99999.0, 100.0)
	var t4 := _mk("stone", "right", c + Vector2(100, 0), 5000.0)
	t4["no_move"] = true; t4["move_spd"] = 0.0
	_run(b4, t4)
	print("④ 目标原 no_move=true → 摔完 no_move=%s" % str(t4.get("no_move")))
	# 摔完跑一会儿 sim(战斗中), 看它会不会被分离推着走
	s._edit_mode = false; s._dl_state = "fight"; s._over = false
	var crowd := _mk("stone", "right", (t4["pos"] as Vector2) + Vector2(10, 0), 99999.0)
	crowd["no_move"] = true
	var p4: Vector2 = t4["pos"]
	for i in range(120):
		s._sim_step(s.SIM_DT, false, false)
	print("④ 摔完 2 秒内被分离推走 %.1f 码 (no_move=%s)" % [(t4["pos"] as Vector2).distance_to(p4), str(t4.get("no_move"))])
	s._edit_mode = true

	# ── ⑤ 小龟半空中阵亡 ──
	s._units.clear()
	var b5 := _mk("basic", "left", c, 99999.0, 100.0)
	var t5 := _mk("stone", "right", c + Vector2(100, 0), 5000.0)
	var o5 := _mk("stone", "right", c + Vector2(-55, 150), 5000.0)
	var kill_b := func(n: int) -> void:
		if n == 20:
			b5["alive"] = false; b5["hp"] = 0.0
	var bpos_before: Vector2 = Vector2.ZERO
	var r5 := _run(b5, t5, kill_b)
	print("⑤ 小龟第20步阵亡 → steps=%d 目标掉血=%.0f 眩晕剩=%.2f 旁人掉血=%.0f 尸体终点=%s 目标终点=%s voff=%s" % [r5["steps"], 5000.0 - float(t5["hp"]), float(t5.get("stun_until", 0.0)) - s._t, 5000.0 - float(o5["hp"]), str(b5["pos"]), str(t5["pos"]), str(t5.get("_slam_voff"))])
	var sp5 = t5.get("sprite", null)
	if is_instance_valid(sp5): print("⑤ 目标 flip_v=%s" % str((sp5 as Sprite3D).flip_v))

	# ── ⑥ 目标半空中死亡: 溅射以哪里为心 ──
	s._units.clear()
	var b6 := _mk("basic", "left", c, 99999.0, 100.0)
	var t6 := _mk("stone", "right", c + Vector2(300, 0), 5000.0)   # 稍远, 抡的路径长
	var land6: Vector2 = c - Vector2(1, 0) * BC.SLAM_LAND_BACK
	var o6a := _mk("stone", "right", land6 + Vector2(0, 300), 5000.0)   # 落点 300 码内
	var kill_t := func(n: int) -> void:
		if n == 12:
			t6["alive"] = false; t6["hp"] = 0.0
	var r6 := _run(b6, t6, kill_t)
	print("⑥ 目标第12步死 → steps=%d 死时位置=%s 落点=%s 落点300码那人掉血=%.0f" % [r6["steps"], str(t6["pos"]), str(land6), 5000.0 - float(o6a["hp"])])

	# ── ⑦ 两只小龟同时摔同一个目标 ──
	s._units.clear()
	var b7 := _mk("basic", "left", c, 99999.0, 100.0)
	var b7b := _mk("basic", "left", c + Vector2(200, 0), 99999.0, 100.0)
	var t7 := _mk("stone", "right", c + Vector2(100, 0), 5000.0)
	s._sk_basic_slam(b7, t7)
	var n7 := 0
	var free_mid := -1
	while n7 < 400 and (bool(b7.get("_slam", false)) or bool(b7b.get("_slam", false))):
		if n7 == 10: s._sk_basic_slam(b7b, t7)
		s._sim_step(s.SIM_DT, false, false)
		n7 += 1
		if free_mid < 0 and n7 > 12 and not bool(t7.get("_slam", false)) and bool(b7b.get("_slam", false)):
			free_mid = n7
	print("⑦ 双摔: 目标掉血=%.0f(单次约 %.0f) | 第二摔还在进行时目标 _slam 已被清(步)=%d" % [5000.0 - float(t7["hp"]), want_main, free_mid])

	# ── ⑧ 场地边缘: 背靠墙 ──
	s._units.clear()
	var edge: Vector2 = Vector2(s.ARENA.position.x + 30.0, c.y)
	var b8 := _mk("basic", "left", edge, 99999.0, 100.0)
	var t8 := _mk("stone", "right", edge + Vector2(100, 0), 5000.0)
	_run(b8, t8)
	print("⑧ 背靠左墙: 龟=%s 敌落点=%s 在岛内=%s 龟在岛内=%s" % [str(b8["pos"]), str(t8["pos"]), str(ArenaShape.in_rect_shape(t8["pos"], s.ARENA, -1.0)), str(ArenaShape.in_rect_shape(b8["pos"], s.ARENA, -1.0))])

	# ── ⑨ 龙蛋 ──
	s._units.clear()
	var b9 := _mk("basic", "left", c, 99999.0, 100.0)
	var t9 := _mk("stone", "right", c + Vector2(100, 0), 5000.0)
	t9["_eggImmune"] = true
	var p9: Vector2 = t9["pos"]
	s._sk_basic_slam(b9, t9)
	print("⑨ 蛋: 立即结算 掉血=%.0f 挪动=%.1f _slam=%s 眩晕剩=%.2f" % [5000.0 - float(t9["hp"]), (t9["pos"] as Vector2).distance_to(p9), str(b9.get("_slam")), float(t9.get("stun_until", 0.0)) - s._t])

	s._units.clear()
	print("PROBE DONE")
	get_tree().quit(0)
