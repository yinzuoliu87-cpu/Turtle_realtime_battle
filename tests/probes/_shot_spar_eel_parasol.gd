extends Node
## _shot_spar_eel_parasol —— 用户 11-12「终极战场带了这个伞，什么都没有，特效也没有，也没回血」+「两费…放子弹放电的那个枪(078 电鳗双管铳)是有问题」
##   走切磋真入口(Spar.begin → 完整战斗场景, 开窗渲染), 左方小龟带 060 + 078(3 星), 援军小将背包抽 060;
##   上路左赢、下路右赢 ⇒ 1:1 进终极战场。终极里在【伞撑开 / 收伞 / 每次开枪】之后几帧截图, 加每 90 步一张全景。
##   产物 .out/shots/spar_eel_pa/。开窗口跑(WINDOW=1 bash godot-quiet.sh ...), 不进门禁。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const MAX_FRAMES := 40000
const MAX_SHOTS := 48
const OUT := "res://.out/shots/spar_eel_pa"

var _shots := 0
var _pending: Array = []      ## [[第几帧拍, 标签]]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
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
	gs.persistent_equipped = {"basic": [{"id": "p2eq_060", "star": 3}, {"id": "p2eq_078", "star": 3}]}
	gs.persistent_bench = [{"id": "p2eq_060", "star": 3}]
	gs.season_level = 6
	gs.trainer_skill = "hook"
	gs.dual_active = false
	gs.dual_ghost = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261112
	var g: Dictionary = Backend.make_bot(3, rng)
	g["profile"] = {"name": "好友乙", "avatar": "stone", "id": "FRND02"}
	print("[SHOT] Spar.begin = %s" % str(Spar.begin(g, {"name": "好友乙", "tag": "FRND02"})))
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	s._deterministic = true
	var st := {"lane": "", "steps": 0, "done": {}, "frame": 0, "fin": 0}
	s.sim_stepped.connect(func() -> void:
		var lane: String = str(GameState.current_lane)
		if lane != st["lane"]:
			st["lane"] = lane
			st["steps"] = 0
		if str(s._dl_state) != "fight":
			return
		st["steps"] = int(st["steps"]) + 1
		if lane == "final":
			st["fin"] = int(st["fin"]) + 1
			if int(st["fin"]) % 90 == 1:
				_want(int(st["frame"]) + 1, "全景_步%d" % int(st["fin"]))
			for u in s._units:
				if not (u.get("alive", false) and str(u.get("side")) == "left"):
					continue
				var who: String = "援军" if str(u.get("minion_role", "")) == "reserve" else str(u.get("id"))
				var stt: Dictionary = (u.get("eq_state", {}) as Dictionary).get("p2eq_060", {})
				if not stt.is_empty():
					var op: bool = bool(stt.get("pa_open", false))
					var k := "wo_" + who
					if op and not bool(st.get(k, false)):
						print("[SHOT] 终极步 %d %s 伞撑开 · 罩到 %d 人" % [int(st["fin"]), who, (stt.get("pa_units", []) as Array).size()])
						_want(int(st["frame"]) + 3, "%s_伞开_步%d" % [who, int(st["fin"])])
						_want(int(st["frame"]) + 40, "%s_伞开中_步%d" % [who, int(st["fin"])])
					if not op and bool(st.get(k, false)):
						print("[SHOT] 终极步 %d %s 伞收起 · 血 %.0f/%.0f" % [int(st["fin"]), who, float(u["hp"]), float(u["maxHp"])])
						_want(int(st["frame"]) + 6, "%s_收伞回血_步%d" % [who, int(st["fin"])])
					st[k] = op
				if u.has("_g078_si"):
					var n: int = int(u.get("_g078_n", 0))
					if n > int(st.get("gn_" + who, 0)):
						print("[SHOT] 终极步 %d %s 双管铳第 %d 枪(%s管)" % [int(st["fin"]), who, n, "左" if (n - 1) % 2 == 0 else "右"])
						_want(int(st["frame"]) + 2, "%s_第%d枪_早" % [who, n])
						_want(int(st["frame"]) + 7, "%s_第%d枪_晚" % [who, n])
					st["gn_" + who] = n
			return
		## 快进: 上路 30 步清右(左赢, 带装备的小龟活着进终极); 下路 30 步清左(右赢) ⇒ 1:1
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
		st["frame"] = int(st["frame"]) + 1
		await _take_due(int(st["frame"]))
		if str(s._dl_state) == "done" or _shots >= MAX_SHOTS:
			break
	print("[SHOT] 结束 state=%s lane=%s 截图 %d 张 → %s" % [str(s._dl_state), str(GameState.current_lane), _shots, ProjectSettings.globalize_path(OUT)])
	Spar.end()
	get_tree().quit(0)


func _want(frame: int, label: String) -> void:
	_pending.append([frame, label])


func _take_due(frame: int) -> void:
	var due: Array = _pending.filter(func(p): return int(p[0]) <= frame)
	if due.is_empty():
		return
	_pending = _pending.filter(func(p): return int(p[0]) > frame)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	for p in due:
		if _shots >= MAX_SHOTS:
			return
		_shots += 1
		img.save_png(ProjectSettings.globalize_path("%s/%02d_%s.png" % [OUT, _shots, str(p[1])]))


func _kill_side(bt, side: String) -> void:
	for u in bt._units.duplicate():
		if not u.get("alive", false) or u.get("_isEgg", false) or u.get("is_trainer", false):
			continue
		if str(bt._eff_side(u)) != side:
			continue
		u["hp"] = 0.0
		bt._kill(u)
