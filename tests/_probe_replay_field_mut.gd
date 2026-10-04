extends Node
## _probe_replay_field_mut.gd — 逐字段变异: 录像里拿掉字段 F、本机 GameState 的 F 换成「另一台设备」的值 ⇒ 重放还逐步一致吗?
## 方案书 docs/plans/20261003-跨设备回放.md §9.5。不进门禁, 手跑(可分片并行):
##   PROBE_FIELDS=a,b,c godot --headless --path . res://tests/_probe_replay_field_mut.tscn --quit-after 900000
## 候选 = `_probe_replay_gs_reads` 量到的「回放窗口读过的变量」并集 + 静态扫到的 sim 读者(gambler_wheel_stacks)。
## 每个进程: 录一局(R) → 基线(录像只留全部候选、其余变量全换成另一份) → 逐个拿掉候选 F。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const PAT_REC := [0.016, 0.004, 0.04, 0.0167, 0.025, 0.05, 0.009, 0.0333]
const PAT_PLAY := [0.05, 0.0167, 0.004, 0.03, 0.012, 0.0167, 0.045, 0.02]
const MAX_FRAMES := 30000

const CANDIDATES := ["candy_temp_levels", "chest_treasure_value", "chest_treasures_won", "current_lane",
	"debug_level", "dual_active", "dual_ghost", "dual_lineup", "dual_ms_stacks", "dual_survivors", "egg_hp",
	"foe_loadouts", "incense_charge", "incense_marks", "lane_results", "loadouts", "perf_lite",
	"persistent_equipped", "season_leaders", "season_level", "test_mode", "trainer_appearance", "trainer_skill",
	"tutorial", "gambler_wheel_stacks"]


## R: 录制方(把每个候选都摆成「有内容、会起作用」的值)。
func _setup_r(gs) -> void:
	gs.reset_dual_lane()
	gs.test_mode = false
	gs.tutorial_active = false
	gs.tutorial = false
	gs.debug_level = 0
	gs.perf_lite = false
	gs.week_phase = "gauntlet"
	var L: Array = ["gambler", "chest", "headless"]
	gs.season_leaders = L.duplicate()
	gs.left_team.assign(L)
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "gambler"}, {"kind": "minion", "role": "back", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "chest"}, {"kind": "leader", "slot": 2, "id": "headless"},
			{"kind": "minion", "role": "front", "equips": []}],
	}
	gs.persistent_equipped = {"gambler": [{"id": "p2eq_001", "star": 3}], "chest": [{"id": "p2eq_093", "star": 1}],
		"basic": [{"id": "p2eq_010", "star": 2}]}
	gs.loadouts = {"gambler": 3, "headless": 3, "chest": 1}
	gs.candy_temp_levels = {"gambler": 2, "chest": 1}
	gs.gambler_wheel_stacks = {"spade": 3, "heart": 1}
	gs.chest_treasure_value = 4000.0
	gs.chest_treasures_won = ["dagger"]
	gs.incense_marks = 120
	gs.incense_charge = 3999
	gs.season_level = 6
	gs.trainer_skill = "hook"
	gs.trainer_appearance = "mage"
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	gs.dual_ghost = Backend.make_bot(14, rng)
	gs.dual_active = true


## V: 看回放的那台设备(全部候选都与 R 不同; 局内临时字段摆成「上一局打完留下的」样子)。
func _setup_v(gs) -> void:
	gs.reset_dual_lane()
	gs.tutorial_active = false
	gs.tutorial = true
	gs.debug_level = 5
	gs.perf_lite = true
	gs.week_phase = "ranked"
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	gs.dual_lineup = {"top": [{"kind": "leader", "slot": 0, "id": "basic"}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone"}, {"kind": "leader", "slot": 2, "id": "bamboo"}]}
	gs.persistent_equipped = {"basic": [{"id": "p2eq_065", "star": 1}], "gambler": [{"id": "p2eq_010", "star": 1}]}
	gs.loadouts = {"gambler": 1, "headless": 1, "chest": 3}
	gs.candy_temp_levels = {"gambler": 5}
	gs.gambler_wheel_stacks = {"club": 6}
	gs.chest_treasure_value = 0.0
	gs.chest_treasures_won = ["crown", "thunder"]
	gs.incense_marks = 0
	gs.incense_charge = 0
	gs.season_level = 2
	gs.trainer_skill = "whistle"
	gs.trainer_appearance = "girl"
	gs.current_lane = "bottom"
	gs.egg_hp = {"left": 77, "right": 88}
	gs.lane_results = {"top": "right"}
	gs.dual_survivors = {"left": ["basic"], "right": []}
	gs.dual_ms_stacks = {"left": 9, "right": 9}
	gs.foe_loadouts = {"basic": 2}
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	gs.dual_ghost = Backend.make_bot(30, rng)
	gs.dual_active = false


func _slim(rec: Dictionary, keys: Array) -> Dictionary:
	var r: Dictionary = RU.for_upload(rec)
	var st: Dictionary = r["state"]
	var out := {}
	for k in keys:
		if st.has(k):
			out[k] = st[k]
	r["state"] = out
	return r


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	## ★手跑也不许打真网络: project.godot 里填着真 Supabase 地址; 空白串 = 后端整层停用(与 run-tests.sh 同)
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	OS.set_environment("TURTLE_SEED", "")
	_setup_r(gs)
	await _run(PAT_REC, true)
	var hist: Array = gs.match_history
	var rid: String = str((hist[0] as Dictionary).get("replay_id", "")) if not hist.is_empty() else ""
	var rec: Dictionary = ReplayRecorder.load_record(rid)
	print("[mut] 录: steps=%d events=%d state 键=%d" % [int(rec.get("end", {}).get("s", -1)), (rec.get("events", []) as Array).size(), (rec.get("state", {}) as Dictionary).size()])
	var only := OS.get_environment("PROBE_FIELDS")
	if only == "" or only.contains("BASE"):
		_setup_v(gs)
		ReplayRecorder.begin_play(_slim(rec, CANDIDATES))
		var b: Dictionary = await _run(PAT_PLAY, false)
		print("[mut] 基线(录像只留 %d 个候选, 本机全换成另一份): div=%d %s cps=%d finished=%s" % [CANDIDATES.size(), int(b["div"]), b["why"], int(b["cps"]), str(b["finished"])])
		_setup_v(gs)
		ReplayRecorder.begin_play(RU.for_upload(rec))
		var b2: Dictionary = await _run(PAT_PLAY, false)
		print("[mut] 对照(原样全量录像): div=%d %s cps=%d finished=%s" % [int(b2["div"]), b2["why"], int(b2["cps"]), str(b2["finished"])])
	for f in CANDIDATES:
		if only != "" and not (only.split(",") as Array).has(f):
			continue
		var keys: Array = CANDIDATES.duplicate()
		keys.erase(f)
		_setup_v(gs)
		ReplayRecorder.begin_play(_slim(rec, keys))
		var r: Dictionary = await _run(PAT_PLAY, false)
		print("[mut] 拿掉 %-22s ⇒ %s  (div=%d %s cps=%d)" % [f, "★分叉(必需)" if int(r["div"]) >= 0 else "一致", int(r["div"]), r["why"], int(r["cps"])])
	print("PROBE DONE")
	get_tree().quit(0)


func _run(pat: Array, as_player: bool) -> Dictionary:
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	var st_frames := 0
	var last_state := ""
	var fights := 0
	var surrendered := false
	var done_frames := 0
	var i := 0
	while i < MAX_FRAMES:
		var st: String = str(s._dl_state)
		if st != last_state:
			last_state = st
			st_frames = 0
		st_frames += 1
		if as_player:
			if (st == "overview" or st == "lane_settle") and st_frames == 9:
				s._dl_sys._dl_present_click()
			elif st == "place" and st_frames == 6:
				for u in s._units:
					if str(u.get("side", "")) == "left" and s._can_place_drag(u):
						u["pos"] = s._dl_sys._dl_clamp_place(u["pos"] + Vector2(-70.0, 30.0 + 20.0 * fights))
						break
			elif st == "place" and st_frames == 25 and is_instance_valid(s._dl_go_btn):
				s._dl_go_btn.pressed.emit()
				fights += 1
			elif st == "fight" and fights >= 2 and st_frames == 400 and not surrendered:
				s._do_surrender()
				surrendered = true
		s._process(float(pat[i % pat.size()]))
		await get_tree().process_frame
		i += 1
		if s._replay.diverged_at >= 0:
			break
		if str(s._dl_state) == "done":
			done_frames += 1
			if done_frames > 30:
				break
	var out := {"div": int(s._replay.diverged_at), "why": str(s._replay.diverge_why),
		"cps": int(s._replay.cp_checked), "finished": bool(s._replay.finished)}
	for _g in range(10):
		await get_tree().process_frame
	s.queue_free()
	for _g in range(4):
		await get_tree().process_frame
	return out
