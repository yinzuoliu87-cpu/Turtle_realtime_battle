extends Node
## _probe_reserve_lifesteal —— 用户 11-11 反馈「援军小将装备的…根本没有吸血」: 量终极战场援军小将带吸血装备时
##   ① 身上 lifesteal 读数 ② 打出的伤害 / 实际回血。探针, 不进门禁。
##   PROBE_EQ=p2eq_011 PROBE_STAR=3(默认)

const Backend := preload("res://scripts/net/backend.gd")
var host: Node


func _ready() -> void:
	host = Node.new()
	add_child(host)
	_run.call_deferred()


func _snap(gs, pool: Array, name: String) -> Dictionary:
	gs.reset_dual_lane()
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	gs.persistent_equipped = {}
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic"}, {"kind": "minion", "role": "front", "equips": []}, {"kind": "minion", "role": "back", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []}, {"kind": "leader", "slot": 2, "id": "bamboo", "equips": []}, {"kind": "minion", "role": "back", "equips": []}],
	}
	gs.loadouts = {"basic": 1, "stone": 2}
	gs.trainer_skill = "hook"
	gs.season_level = 6
	gs.season_total_battles = 5
	gs.persistent_bench = pool.duplicate(true)
	return Backend.build_ghost_snapshot(name, {"name": name, "avatar": "basic", "id": name})


func _kill_side(bt, side: String) -> void:
	for u in bt._units.duplicate():
		if not u.get("alive", false) or u.get("_isEgg", false) or u.get("is_trainer", false):
			continue
		if str(bt._eff_side(u)) != side:
			continue
		u["hp"] = 0.0
		bt._kill(u)


func _run() -> void:
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var eq := OS.get_environment("PROBE_EQ") if OS.get_environment("PROBE_EQ") != "" else "p2eq_011"
	var star := int(OS.get_environment("PROBE_STAR")) if OS.get_environment("PROBE_STAR") != "" else 3
	var a := _snap(gs, [{"id": eq, "star": star}], "g_pl_a")
	var b: Dictionary = a.duplicate(true)
	b["ghost_id"] = "g_pl_b"
	b["reserve_pool"] = [{"id": "p2eq_016", "star": 1}]
	var job: Dictionary = JSON.parse_string(JSON.stringify({"v": 1, "job_id": 1, "match_id": "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b", "mode": "gauntlet",
		"key": {"week": 1, "account": "t"}, "seed": 2000023, "client_version": ReplayRecorder.client_version(), "level": 6, "a": a, "b": b}))
	var st := {"lane": "", "steps": 0, "done": {}, "rv": null, "fin_steps": 0}
	await RefereeRunner.run(host, job, func(bt) -> void:
		bt.sim_stepped.connect(func() -> void:
			var lane: String = str(GameState.current_lane)
			if lane != st["lane"]:
				st["lane"] = lane
				st["steps"] = 0
			if str(bt._dl_state) != "fight":
				return
			st["steps"] = int(st["steps"]) + 1
			if lane == "final":
				st["fin_steps"] = int(st["fin_steps"]) + 1
				if st["rv"] == null:
					for u in bt._units:
						if u.get("alive", false) and str(u.get("side")) == "left" and str(u.get("minion_role", "")) == "reserve":
							st["rv"] = u
							u["hp"] = float(u["maxHp"]) * 0.3          # 留出回血空间
							print("[LS] 终极开场 援军 equips=%s lifesteal=%.3f ls_bonus=%.3f maxHp=%.0f atk=%.1f" % [str(u.get("equips")), float(u.get("lifesteal", 0.0)), float(u.get("ls_bonus", 0.0)), float(u["maxHp"]), float(u["atk"])])
							break
				return
			## 同 verify_reserve_minion S2: 上路 30 步两边都清; 下路 30 步清右、90 步清左 ⇒ 终极战场两边各只剩援军
			if int(st["steps"]) == 30 and not st["done"].has(lane + "30"):
				st["done"][lane + "30"] = true
				_kill_side(bt, "right")
				if lane == "top":
					_kill_side(bt, "left")
			if lane == "bottom" and int(st["steps"]) == 90 and not st["done"].has("bottom90"):
				st["done"]["bottom90"] = true
				_kill_side(bt, "left")
		)
	)
	var rv = st["rv"]
	if rv == null:
		print("[LS] ✗ 没进终极战场 / 没找到左方援军")
	else:
		var dealt := int(rv.get("_st_dealt", 0))
		var heal := float(rv.get("_st_heal", 0.0))
		print("[LS] 终极战场 %d 步: 援军 打出 %d · 实际回血 %.1f · 回血/伤害 = %.3f · 结束时 lifesteal=%.3f alive=%s" % [int(st["fin_steps"]), dealt, heal, heal / maxf(1.0, float(dealt)), float(rv.get("lifesteal", 0.0)), str(rv.get("alive"))])
	get_tree().quit(0)
