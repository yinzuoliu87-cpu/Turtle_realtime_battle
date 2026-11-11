extends Node
## 探针(不进门禁; 11-11): verify_temp_level_referee 里对手星际龟「开局」最大生命 1643 = 943 + 700, 那 700 从哪来。
## 照那条测试的对局(裁判真入口, BP.one(16,0,0,0), 右方去掉装备)连开几局, 打出第一眼的最大生命 + 当时的战斗时钟。
## ★结论: 第一眼其实是开打后 0.6 ~ 1.2 秒(裁判一帧跑好几步); 量得早 = 943, 量得晚 = 1643 ——
##   +700 是对手训龟大师的口哨(trainer_system WHISTLE_TEMPHP: 随机友军 +700 临时最大生命 5 秒, 定值、两边一样), 不是快照带来的。
## 跑法: APPDATA=$U XDG_DATA_HOME=$U TURTLE_SUPABASE=" " godot --headless --audio-driver Dummy --path . res://tests/probes/_probe_foe_flat_hp.tscn

const Backend := preload("res://scripts/net/backend.gd")
const BP := preload("res://scripts/referee/bot_pool.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const MID := "6c2d3b4c-5e6f-4a71-9b8c-0d1e2f3a4b5c"

var _b = null
var _hp := {}
var _gs = null


func _on_battle(b) -> void:
	_b = b


func _process(_d: float) -> void:
	if _b == null or not is_instance_valid(_b):
		return
	for u in _b._units:
		var k := "%s/%s" % [str(u.get("side", "")), str(u.get("id", ""))]
		if not _hp.has(k):
			_hp[k] = [float(u.get("maxHp", 0.0)), int(u.get("level", 0)), float(_b._t), "第%d个战场" % (_b._st_lane_hist.size() + 1)]


func _snap_a() -> Dictionary:
	_gs.start_new_season()
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(["basic", "stone", "bamboo"])
	_gs.persistent_equipped = {}
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic"}, {"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone"}, {"kind": "leader", "slot": 2, "id": "bamboo"},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	_gs.season_level = 6
	_gs.candy_temp_levels = {}
	return Backend.build_ghost_snapshot("g_probe_a", {"name": "甲方", "avatar": "basic", "id": "g_probe_a"})


func _run(a: Dictionary, b: Dictionary) -> Dictionary:
	_b = null
	_hp = {}
	var job = JSON.parse_string(JSON.stringify({"v": 1, "job_id": 1, "match_id": MID, "mode": "gauntlet", "key": {"week": 1},
		"seed": 77, "client_version": ReplayRecorder.client_version(), "a": a, "b": b}))
	await RefereeRunner.run(self, job, _on_battle)
	_b = null
	return _hp.duplicate()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_gs.test_mode = true
	_gs.tutorial_active = false
	P2.now_override_ts = P2.week_anchor_utc(int(Time.get_unix_time_from_system())) + 5 * 86400 + 12 * 3600
	var a := _snap_a()
	var b0: Dictionary = BP.one(16, 0, 0, 0)
	b0["gl_ts"] = int(P2.now_utc()) - 300
	b0["equipped"] = {}
	for lk in ["top", "bottom"]:
		for m in ((b0.get("minions", {}) as Dictionary).get(lk, []) as Array):
			(m as Dictionary).erase("equips")
	var foe := str((b0.get("leaders", []) as Array)[0])
	print("[probe] 对手 leaders=%s foe=%s 快照键=%s" % [str(b0.get("leaders")), foe, str(b0.keys())])
	print("[probe] loadouts=%s trainer_skill=%s season_level=%s lv=%s axe_stage=%s incense_charge=%s incense_marks=%s chest=%s" % [
		str(b0.get("loadouts")), str(b0.get("trainer_skill")), str(b0.get("season_level")), str(b0.get("lv")),
		str(b0.get("axe_stage")), str(b0.get("incense_charge")), str(b0.get("incense_marks")), str(b0.get("chest_treasure_value"))])
	var variants := [["第1局", []], ["第2局", []], ["第3局", []], ["第4局", []]]
	for v in variants:
		var b: Dictionary = b0.duplicate(true)
		for k in (v[1] as Array):
			b.erase(k)
		var h: Dictionary = await _run(a, b)
		var row: Array = h.get("right/" + foe, [0, 0, 0, ""])
		print("[probe] %-10s right/%s 第一眼最大生命 %.1f Lv%d 战斗时钟 %.2f 秒 路 %s | 右方全体 %s" % [v[0], foe, row[0], row[1], row[2], row[3], str(h.keys().filter(func(x): return str(x).begins_with("right/")).map(func(x): return "%s=%.0f" % [x, h[x][0]]))])
	print("[probe] DONE")
	get_tree().quit()
