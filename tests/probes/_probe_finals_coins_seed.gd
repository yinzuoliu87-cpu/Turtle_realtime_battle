extends Node
## 探针(11-08): verify_finals_coins F1 换种子 —— RULES_VER 4 后种子 3100041 两侧都铸 3 枚(判据要两侧不同)。
const Backend := preload("res://scripts/net/backend.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const MID := "5b2c7d1e-3f4a-4b6c-8d9e-0a1b2c3d4e5f"
const GEAR := "p2eq_035"
const WEEK := 1760918400
var SEED := 3100041
var _gs


## 一份快照(真生产函数 build_ghost_snapshot)。`gear` = 每只统领第一件换成几星齿轮(0 = 不带)。
func _snap(leaders: Array, gear: Array, nm: String) -> Dictionary:
	_gs.reset_dual_lane()
	_gs.season_leaders = leaders.duplicate()
	_gs.left_team.assign(_gs.season_leaders)
	var shop: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1 and str((e as Dictionary)["id"]) != GEAR:
			shop.append(str((e as Dictionary)["id"]))
	var k := 0
	var pe := {}
	for i in range(leaders.size()):
		var l: Array = []
		if int(gear[i]) > 0:
			l.append({"id": GEAR, "star": int(gear[i])})
		while l.size() < 3:
			l.append({"id": str(shop[k % shop.size()]), "star": 3})
			k += 1
		pe[leaders[i]] = l
	_gs.persistent_equipped = pe
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": leaders[0]}, {"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": leaders[1]}, {"kind": "leader", "slot": 2, "id": leaders[2]},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	_gs.season_level = 6
	return Backend.build_ghost_snapshot("g_" + nm, {"name": nm, "avatar": str(leaders[0]), "id": "g_" + nm})


func _job(a: Dictionary, b: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify({"v": 1, "job_id": 7, "match_id": MID, "mode": "finals",
		"key": {"week": WEEK, "bucket": 0, "round": 1, "match": 0}, "seed": SEED,
		"client_version": ReplayRecorder.client_version(), "a": a, "b": b}))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_gs.test_mode = true
	_gs.tutorial_active = false
	P2C.now_override_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 6 * 86400 + 12 * 3600
	var a := _snap(["basic", "stone", "bamboo"], [3, 3, 3], "amy")
	var b := _snap(["ninja", "dice", "pirate"], [1, 2, 0], "hal")
	for s in range(3100041, 3100053):
		SEED = s
		var res: Dictionary = await RefereeRunner.run(self, _job(a, b))
		print("[SEED] %d ok=%s 胜 %s 步 %d coins %d / coins_b %d %s" % [s, str(res.get("ok")), str(res.get("winner")), int(res.get("steps", 0)),
			int(res.get("coins", -1)), int(res.get("coins_b", -1)), "★不同" if int(res.get("coins", -1)) != int(res.get("coins_b", -1)) else ""])
	get_tree().quit()
