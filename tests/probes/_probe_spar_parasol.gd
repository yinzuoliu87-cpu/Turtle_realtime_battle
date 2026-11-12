extends Node
## _probe_spar_parasol —— 用户 11-12「切磋的时候…终极战场带了这个伞，什么都没有，特效也没有，也没回血」:
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
	var eq := "p2eq_060"
	var star := 3
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
	gs.persistent_equipped = {"basic": [{"id": "p2eq_060", "star": 3}]}
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
		if lane == "final" or lane == "top":
			for u in s._units:
				if not (u.get("alive", false) and str(u.get("side")) == "left"):
					continue
				var has60 := false
				for e in u.get("equips", []):
					if str(e.get("id", "")) == "p2eq_060":
						has60 = true
				if not has60:
					continue
				var k: String = lane + ":" + str(u.get("name", u.get("id")))
				var stt: Dictionary = (u.get("eq_state", {}) as Dictionary).get("p2eq_060", {})
				if not st.has("seen_" + k):
					st["seen_" + k] = true
					print("[PS] %s 带伞 _parasol_si=%s eq_state有060=%s hp=%.0f/%.0f" % [k, str(u.get("_parasol_si", "无")), str((u.get("eq_state", {}) as Dictionary).has("p2eq_060")), float(u["hp"]), float(u["maxHp"])])
				var op: bool = bool(stt.get("pa_open", false))
				if op and not bool(st.get("wo_" + k, false)):
					st["opens_" + k] = int(st.get("opens_" + k, 0)) + 1
				st["wo_" + k] = op
				st["sum_" + k] = "撑开 %d 次 · 060 统计=%s · 相位计时=%.2f" % [int(st.get("opens_" + k, 0)), str((u.get("_st_eq", {}) as Dictionary).get("p2eq_060", {})), float(stt.get("pa_t", -1.0))]
			if lane == "final":
				return
		## 快进到终极: 上路 30 步两边清; 下路 30 步清右、90 步清左(同 verify_reserve_minion S2)
		var key := lane + str(int(st["steps"]))
		if int(st["steps"]) == 30 and not st["done"].has(key):
			st["done"][key] = true
			_kill_side(s, "right" if lane == "top" else "left")
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
	for k in st.keys():
		if str(k).begins_with("sum_"):
			print("[PS] %s: %s" % [str(k).substr(4), str(st[k])])
	print("[PS] 结束 state=%s lane=%s" % [str(s._dl_state), str(GameState.current_lane)])
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
