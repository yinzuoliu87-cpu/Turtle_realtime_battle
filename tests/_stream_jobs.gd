extends RefCounted
## 逐帧直播 S1 门禁共用的任务单(下划线开头: 不是门禁, 被 verify_stream_* 三个门禁 preload)。
##   · mirror: 与 verify_referee_job_roundtrip `_snap_a(gs, false)` 同一份(镜像阵容, 种子 2000023 打满三路)
##   · heavy:  tests/golden/stream_heavy_pair.json(真实快照池两份打满赛季的快照, S0 的「裁判局②」, 种子 2000023)

const Backend := preload("res://scripts/net/backend.gd")
const HEAVY := "res://tests/golden/stream_heavy_pair.json"
## 2026-10-20: 白名单报警样本(真人快照一对, 带 072 蛋糕礼盒 ⇒ 立绘换表改 vframes), 见 verify_stream_whitelist_alarm
const ALARM_072 := "res://tests/golden/stream_alarm_pair_072.json"
const LEVEL := 6
const SEED := 2000023


static func job(a: Dictionary, b: Dictionary, seed: int) -> Dictionary:
	var j := {"v": 1, "job_id": 1, "match_id": "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b", "mode": "gauntlet",
		"key": {"week": 1, "account": "t"}, "seed": seed, "client_version": ReplayRecorder.client_version(),
		"level": LEVEL, "a": a, "b": b}
	return JSON.parse_string(JSON.stringify(j))


static func mirror(gs) -> Dictionary:
	gs.reset_dual_lane()
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	var shop: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			shop.append(str((e as Dictionary)["id"]))
	var k := 0
	var pe := {}
	for pid in gs.season_leaders:
		pe[pid] = [{"id": str(shop[k % shop.size()]), "star": 1}]
		k += 1
	gs.persistent_equipped = pe
	gs.dual_lineup = {
		"top": [
			{"kind": "leader", "slot": 0, "id": "basic", "off": [-100, 160]},
			{"kind": "minion", "role": "front", "equips": [], "off": [150, -200]},
			{"kind": "minion", "role": "back", "equips": []},
		],
		"bottom": [
			{"kind": "leader", "slot": 1, "id": "stone", "equips": [], "off": [60, -120]},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []},
		],
	}
	gs.loadouts = {"basic": 1, "stone": 2}
	gs.trainer_skill = "hook"
	gs.season_level = LEVEL
	var a: Dictionary = Backend.build_ghost_snapshot("g_stream_m_a", {"name": "甲方", "avatar": "basic", "id": "g_stream_m_a"})
	var b: Dictionary = a.duplicate(true)
	b["profile"] = {"name": "乙方", "avatar": "stone", "id": "g_stream_m_b"}
	b["ghost_id"] = "g_stream_m_b"
	return job(a, b, SEED)


static func alarm_072() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(ALARM_072))
	if not (d is Dictionary):
		return {}
	var j := job((d as Dictionary)["a"], (d as Dictionary)["b"], int((d as Dictionary)["seed"]))
	j["level"] = int((d as Dictionary).get("level", LEVEL))
	return j


static func heavy() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(HEAVY))
	if not (d is Dictionary):
		return {}
	return job((d as Dictionary)["a"], (d as Dictionary)["b"], int((d as Dictionary)["seed"]))
