extends Node
## _probe_parasol_live —— 用户 11-12「磷光水母伞有什么效果吗？我怎么看那一直都是暂无效果」:
##   裁判真入口打一整局, 量 060 携带者每一路: 伞撑开几次 / 每次罩到几个人 / 收伞回了多少血 / 「本局」统计里 060 记了什么。探针, 不进门禁。

const Backend := preload("res://scripts/net/backend.gd")
var host: Node


func _ready() -> void:
	host = Node.new()
	add_child(host)
	_run.call_deferred()


func _run() -> void:
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	gs.reset_dual_lane()
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	gs.persistent_equipped = {"basic": [{"id": "p2eq_060", "star": 3}]}
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic"}, {"kind": "minion", "role": "front", "equips": []}, {"kind": "minion", "role": "back", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []}, {"kind": "leader", "slot": 2, "id": "bamboo", "equips": []}, {"kind": "minion", "role": "back", "equips": []}],
	}
	gs.loadouts = {"basic": 1, "stone": 2}
	gs.trainer_skill = "hook"
	gs.season_level = 6
	gs.season_total_battles = 5
	gs.persistent_bench = []
	var a := Backend.build_ghost_snapshot("g_pa_a", {"name": "a", "avatar": "basic", "id": "g_pa_a"})
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261112
	var b: Dictionary = Backend.make_bot(3, rng)
	var job: Dictionary = JSON.parse_string(JSON.stringify({"v": 1, "job_id": 1, "match_id": "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b", "mode": "gauntlet",
		"key": {"week": 1, "account": "t"}, "seed": 2000023, "client_version": ReplayRecorder.client_version(), "level": 6, "a": a, "b": b}))
	var st := {"lane": "", "opens": 0, "covered": 0, "was_open": false, "lanes": []}
	await RefereeRunner.run(host, job, func(bt) -> void:
		bt.sim_stepped.connect(func() -> void:
			var lane: String = str(GameState.current_lane)
			if lane != st["lane"]:
				st["lane"] = lane
				st["opens"] = 0
				st["covered"] = 0
				st["was_open"] = false
				st["lanes"].append(lane)
			for u in bt._units:
				if not (str(u.get("side")) == "left" and str(u.get("id")) == "basic"):
					continue
				var stt: Dictionary = (u.get("eq_state", {}) as Dictionary).get("p2eq_060", {})
				var op: bool = bool(stt.get("pa_open", false))
				if op and not bool(st["was_open"]):
					st["opens"] = int(st["opens"]) + 1
					st["covered"] = int(st["covered"]) + (stt.get("pa_units", []) as Array).size()
				st["was_open"] = op
				var eqs = (u.get("_st_eq", {}) as Dictionary).get("p2eq_060", {})
				st["last_" + lane] = "撑开 %d 次 · 共罩到 %d 人次 · 活着=%s · 本局统计(060)=%s · 自身总治疗 %.0f" % [int(st["opens"]), int(st["covered"]), str(u.get("alive")), str(eqs), float(u.get("_st_heal", 0.0))]
		)
	)
	for ln in st["lanes"]:
		print("[PA] %s: %s" % [ln, str(st.get("last_" + str(ln), "(带伞的龟不在这一路)"))])
	get_tree().quit(0)
