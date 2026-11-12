extends Node
## _probe_spar_reserve_ls —— 用户 11-12 切磋反馈「援军小将装备栏里有饮血护符坠…掉了血，打中人却一点都不回」:
##   走切磋真入口(Spar.begin → 完整战斗场景, 同 verify_spar_isolation), 打到终极战场, 逐步记两边援军:
##   lifesteal / 掉血时打中几步、当步回没回血 / 打中的是谁。探针, 不进门禁。PROBE_EQ / PROBE_STAR 换装备。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const MAX_FRAMES := 40000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	var eq := OS.get_environment("PROBE_EQ") if OS.get_environment("PROBE_EQ") != "" else "p2eq_011"
	var star := int(OS.get_environment("PROBE_STAR")) if OS.get_environment("PROBE_STAR") != "" else 1
	gs.reset_dual_lane()
	gs.test_mode = false
	gs.tutorial_active = false
	gs.tutorial = false
	gs.week_phase = "ranked"
	gs.hearts = 4
	gs.season_total_battles = 5
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []}, {"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []}, {"kind": "minion", "role": "back", "equips": []}],
	}
	gs.persistent_equipped = {}
	gs.persistent_bench = [{"id": eq, "star": star}]
	gs.season_level = 6
	gs.trainer_skill = "hook"
	gs.dual_active = false
	gs.dual_ghost = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261112
	var g: Dictionary = Backend.make_bot(3, rng)
	g["profile"] = {"name": "好友乙", "avatar": "stone", "id": "FRND02"}
	g["reserve_pool"] = [{"id": eq, "star": star}]
	print("[SP] Spar.begin = %s" % str(Spar.begin(g, {"name": "好友乙", "tag": "FRND02"})))
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	s._deterministic = true
	var st := {"lane": "", "steps": 0, "done": {}, "reported": false}
	s.sim_stepped.connect(func() -> void:
		var lane: String = str(GameState.current_lane)
		if lane != st["lane"]:
			st["lane"] = lane
			st["steps"] = 0
		if str(s._dl_state) != "fight":
			return
		st["steps"] = int(st["steps"]) + 1
		if lane == "final":
			for u in s._units:
				if not (u.get("alive", false) and str(u.get("minion_role", "")) == "reserve"):
					continue
				var k: String = str(u.get("side"))
				if not st.has("seen_" + k):
					st["seen_" + k] = true
					print("[SP] 终极 %s 援军 equips=%s lifesteal=%.3f heal_amp=%.3f maxHp=%.0f hp=%.0f" % [k, str(u.get("equips")), float(u.get("lifesteal", 0.0)), float(u.get("heal_amp", 0.0)), float(u["maxHp"]), float(u["hp"])])
				var pd: int = int(st.get("pd_" + k, int(u.get("_st_dealt", 0))))
				var ph: float = float(st.get("ph_" + k, float(u.get("_st_heal", 0.0))))
				var phf: float = float(st.get("hf_" + k, 1.0))
				var dd: int = int(u.get("_st_dealt", 0)) - pd
				if dd > 0:
					if phf < 0.999:
						st["dh_" + k] = int(st.get("dh_" + k, 0)) + 1
						if float(u.get("_st_heal", 0.0)) > ph + 0.001:
							st["dhh_" + k] = int(st.get("dhh_" + k, 0)) + 1
							st["hsum_" + k] = float(st.get("hsum_" + k, 0.0)) + float(u.get("_st_heal", 0.0)) - ph
							st["dsum_" + k] = int(st.get("dsum_" + k, 0)) + dd
						elif int(st.get("miss_print_" + k, 0)) < 5:
							st["miss_print_" + k] = int(st.get("miss_print_" + k, 0)) + 1
							var tg = u.get("target", null)
							print("[SP]   %s 掉血(%.0f%%)打中 %d 却没回血 · 目标=%s · lifesteal=%.3f" % [k, phf * 100.0, dd, str((tg as Dictionary).get("name", "?")) if tg is Dictionary else "?", float(u.get("lifesteal", 0.0))])
					else:
						st["fh_" + k] = int(st.get("fh_" + k, 0)) + 1
				st["pd_" + k] = int(u.get("_st_dealt", 0))
				st["ph_" + k] = float(u.get("_st_heal", 0.0))
				st["hf_" + k] = float(u["hp"]) / maxf(1.0, float(u["maxHp"]))
			return
		## 快进到终极: 上路 30 步两边清; 下路 30 步清右、90 步清左(同 verify_reserve_minion S2)
		var key := lane + str(int(st["steps"]))
		if int(st["steps"]) == 30 and not st["done"].has(key):
			st["done"][key] = true
			_kill_side(s, "right")
			if lane == "top":
				_kill_side(s, "left")
		if lane == "bottom" and int(st["steps"]) == 90 and not st["done"].has("b90"):
			st["done"]["b90"] = true
			_kill_side(s, "left")
	)
	var last := ""
	var st_frames := 0
	for _i in range(MAX_FRAMES):
		var ds: String = str(s._dl_state)
		if ds != last:
			last = ds
			st_frames = 0
		st_frames += 1
		if ds == "overview" and st_frames == 9:
			s._dl_sys._dl_present_click()
		s._process(s.SIM_DT)
		await get_tree().process_frame
		if str(s._dl_state) == "done":
			break
	for k in ["left", "right"]:
		var _n: int = maxi(1, int(st.get("dhh_" + k, 0)))
		print("[SP] %s 援军: 掉血时每次打中平均 伤害 %.0f · 回血 %.1f(占它最大生命 %.2f%%)" % [k, float(st.get("dsum_" + k, 0)) / _n, float(st.get("hsum_" + k, 0.0)) / _n, 100.0 * float(st.get("hsum_" + k, 0.0)) / _n / 1120.0])
		print("[SP] %s 援军: 满血时打中 %d 步 · 掉血时打中 %d 步, 当步回了血 %d 步" % [k, int(st.get("fh_" + k, 0)), int(st.get("dh_" + k, 0)), int(st.get("dhh_" + k, 0))])
	print("[SP] 结束 state=%s lane=%s" % [str(s._dl_state), str(GameState.current_lane)])
	Spar.end()
	get_tree().quit(0)


func _kill_side(bt, side: String) -> void:
	for u in bt._units.duplicate():
		if not u.get("alive", false) or u.get("_isEgg", false) or u.get("is_trainer", false):
			continue
		if str(bt._eff_side(u)) != side:
			continue
		u["hp"] = 0.0
		bt._kill(u)
