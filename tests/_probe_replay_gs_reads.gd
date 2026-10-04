extends Node
## _probe_replay_gs_reads.gd — 量「回放那一遍实际读了 GameState 的哪些变量」(录像瘦身的依据)。
## 方案书 docs/plans/20261003-跨设备回放.md §9.5。不进门禁(名字不是 verify_*), 手跑:
##   godot --headless --path . res://tests/_probe_replay_gs_reads.tscn --quit-after 400000
##
## 每个场景: 按真实交互录一局(人点幕布/拖站位/按开打/可选认输) → 播这份录像,
##   播放窗口(建场 → 打完)里 GameState 被读过的变量全部记下。多个场景(换统领/装备/大师技能/对手/
##   打满不认输)取并集。另外把录制窗口(含结算)读过的也打出来做对照。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const TRACE := preload("res://tests/_gs_read_trace.gd")
const PAT := [0.016, 0.004, 0.04, 0.0167, 0.025, 0.05, 0.009, 0.0333]
const MAX_FRAMES := 40000

const SCEN := [
	{"name": "A basic/stone/bamboo + hook + 认输", "leaders": ["basic", "stone", "bamboo"], "skill": "hook",
		"eq": {"basic": [{"id": "p2eq_001", "star": 3}]}, "bot": 3, "lv": 4, "surrender": true},
	{"name": "B ninja/dice/pirate + magic_stone + 打满", "leaders": ["ninja", "dice", "pirate"], "skill": "magic_stone",
		"eq": {"ninja": [{"id": "p2eq_065", "star": 2}], "dice": [{"id": "p2eq_010", "star": 1}]}, "bot": 20, "lv": 9, "surrender": false},
	{"name": "C gambler/candy/two_head + whistle + 打满", "leaders": ["gambler", "candy", "two_head"], "skill": "whistle",
		"eq": {"gambler": [{"id": "p2eq_030", "star": 2}]}, "bot": 12, "lv": 7, "surrender": false},
	{"name": "D hiding/headless/chest + glacier + 打满", "leaders": ["hiding", "headless", "chest"], "skill": "glacier",
		"eq": {}, "bot": 30, "lv": 10, "surrender": false},
]

var _union := {}
var _rec_union := {}


func _setup(gs, sc: Dictionary) -> void:
	gs.reset_dual_lane()
	gs.test_mode = false
	gs.tutorial_active = false
	gs.week_phase = "gauntlet"
	gs.season_leaders = sc["leaders"].duplicate()
	gs.left_team.assign(gs.season_leaders)
	var L: Array = sc["leaders"]
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": L[0]}, {"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": L[1], "equips": []},
			{"kind": "leader", "slot": 2, "id": L[2], "equips": []}, {"kind": "minion", "role": "back", "equips": []}],
	}
	gs.persistent_equipped = sc["eq"].duplicate(true)
	gs.season_level = int(sc["lv"])
	gs.trainer_skill = str(sc["skill"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261004 + int(sc["bot"])
	gs.dual_ghost = Backend.make_bot(int(sc["bot"]), rng)
	gs.dual_active = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	## ★手跑也不许打真网络: project.godot 里填着真 Supabase 地址; 空白串 = 后端整层停用(与 run-tests.sh 同)
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	OS.set_environment("TURTLE_SEED", "")
	var tr = TRACE.new()
	var err: String = "" if OS.get_environment("PROBE_NOTRACE") != "" else tr.install(gs)
	print("[probe] install: '%s' · 补了 getter 的变量 %d 个" % [err, tr.var_names.size()])
	if err != "":
		get_tree().quit(1)
		return
	var only := OS.get_environment("PROBE_ONLY")
	for si in range(SCEN.size()):
		var sc: Dictionary = SCEN[si]
		if only != "" and not only.contains(str(si)):
			continue
		print("=== 场景 ", sc["name"], " ===")
		_setup(gs, sc)
		if OS.get_environment("PROBE_NOTRACE") == "": tr.begin(gs)
		var r1: Dictionary = await _run(sc["surrender"], true)
		var rec_reads: Dictionary = {} if OS.get_environment("PROBE_NOTRACE") != "" else tr.end(gs)
		var hist: Array = gs.match_history
		var rid: String = str((hist[0] as Dictionary).get("replay_id", "")) if not hist.is_empty() else ""
		var rec: Dictionary = ReplayRecorder.load_record(rid)
		if rec.is_empty():
			print("[probe] 没录到"); continue
		print("[probe] 录: state=%s steps=%d bytes=%d events=%d" % [r1["state"], int(rec["end"]["s"]),
			ReplayRecorder.encode(rec).size(), (rec["events"] as Array).size()])
		ReplayRecorder.begin_play(RU.for_upload(rec))
		if OS.get_environment("PROBE_NOTRACE") != "": tr = null
		else: tr.begin(gs)
		gs.set("__rd_stack_for", "")
		var r2: Dictionary = await _run(false, false, tr, gs)
		gs.set("__rd_stack_for", "")
		var reads: Dictionary = r2.get("reads", {})
		if tr == null: tr = TRACE.new()
		print("[probe] 播: div=%d why=%s cps=%d finished=%s" % [int(r2["div"]), r2["why"], int(r2["cps"]), str(r2["finished"])])
		var ks := reads.keys()
		ks.sort()
		print("[probe] 播放窗口读过 %d 个: %s" % [ks.size(), str(ks)])
		for k in ks:
			_union[k] = int(_union.get(k, 0)) + int(reads[k])
		for k in rec_reads:
			_rec_union[k] = true
	var u := _union.keys()
	u.sort()
	print("[probe] ★并集 播放窗口读过 %d 个:" % u.size())
	for k in u:
		print("    %s  %d" % [k, int(_union[k])])
	var only_rec: Array = []
	for k in _rec_union:
		if not _union.has(k):
			only_rec.append(k)
	only_rec.sort()
	print("[probe] 只在录制窗口(含结算)读过的 %d 个: %s" % [only_rec.size(), str(only_rec)])
	var never: Array = []
	for k in tr.var_names:
		if not _union.has(k) and not _rec_union.has(k):
			never.append(k)
	print("[probe] 两个窗口都没读过的 %d 个: %s" % [never.size(), str(never)])
	tr.uninstall(gs)
	print("PROBE DONE")
	get_tree().quit(0)


func _run(surrender: bool, as_player: bool, tr = null, gs = null) -> Dictionary:
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
			elif surrender and st == "fight" and fights >= 2 and st_frames == 300 and not surrendered:
				s._do_surrender()
				surrendered = true
		s._process(float(PAT[i % PAT.size()]))
		await get_tree().process_frame
		i += 1
		if s._replay.diverged_at >= 0:
			break
		if str(s._dl_state) == "done":
			done_frames += 1
			if done_frames > 30:
				break
	var out := {"state": str(s._dl_state), "div": int(s._replay.diverged_at), "why": str(s._replay.diverge_why),
		"cps": int(s._replay.cp_checked), "finished": bool(s._replay.finished)}
	if tr != null:
		out["reads"] = tr.end(gs)       # ★窗口 = 建场 → 打完(不含离场还原)
	for _g in range(10):
		await get_tree().process_frame
	s.queue_free()
	for _g in range(4):
		await get_tree().process_frame
	return out
