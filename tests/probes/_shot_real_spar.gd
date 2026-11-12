extends Node
## _shot_real_spar —— 用户 11-12「你拿两个账号实际的去切磋一下嘛，然后你可以看一下这个东西有没有生效」:
##   左方 = LouisT01 的真实云存档(正式服只读取出: .out/louist01_payload.json), 右方 = alex1997 在服务器上最新的阵容快照(.out/alex_ghost.json),
##   走切磋真入口(Spar.begin → 完整战斗场景, 开窗渲染), **不快进、自然打完**。
##   每一路记: 打了多少秒 / 每个带 060 的单位伞撑开几次、收伞时血量 / 带 071 时奶油盾镜像与真实余额是否一致。伞撑开时截图。
##   开窗跑(WINDOW=1 bash godot-quiet.sh ...), 不进门禁。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const MAX_FRAMES := 60000
const MAX_SHOTS := 24
const OUT := "res://.out/shots/real_spar"

var _shots := 0
var _pending: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	var payload = JSON.parse_string(FileAccess.get_file_as_string("res://.out/louist01_payload.json"))
	var ghost = JSON.parse_string(FileAccess.get_file_as_string("res://.out/alex_ghost.json"))
	if not (payload is Dictionary) or not (ghost is Dictionary):
		print("[RS] ✗ 读不到存档 / 阵容文件")
		get_tree().quit(1)
		return
	gs._apply_save_dict(payload)
	gs.tutorial_active = false
	gs.tutorial = false
	gs.dual_active = false
	print("[RS] 左方 %s 统领 %s 装备 %s" % [str(gs.get("nickname")), str(gs.season_leaders), str(gs.persistent_equipped)])
	print("[RS] 右方 %s 统领 %s" % [str((ghost.get("profile", {}) as Dictionary).get("name", "?")), str(ghost.get("leaders"))])
	print("[RS] Spar.begin = %s · my_side_check=「%s」" % [str(Spar.begin(ghost, {"name": "alex1997", "tag": "ALEX"})), Spar.my_side_check()])
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	s._deterministic = true
	var st := {"lane": "", "steps": 0, "frame": 0, "sum": {}}
	s.sim_stepped.connect(func() -> void:
		var lane: String = str(GameState.current_lane)
		if lane != st["lane"]:
			if str(st["lane"]) != "":
				print("[RS] —— %s 打了 %.1f 秒" % [str(st["lane"]), float(st["steps"]) * float(s.SIM_DT)])
			st["lane"] = lane
			st["steps"] = 0
		if str(s._dl_state) != "fight":
			return
		st["steps"] = int(st["steps"]) + 1
		for u in s._units:
			if not u.get("alive", false):
				continue
			var who: String = "%s:%s" % [str(u.get("side")), "援军" if str(u.get("minion_role", "")) == "reserve" else str(u.get("name", u.get("id")))]
			var key: String = lane + "|" + who
			var stt: Dictionary = (u.get("eq_state", {}) as Dictionary).get("p2eq_060", {})
			if not stt.is_empty():
				var op: bool = bool(stt.get("pa_open", false))
				var ok := "wo_" + key
				if op and not bool(st.get(ok, false)):
					var n: int = int((st["sum"] as Dictionary).get(key + "|伞撑开", 0)) + 1
					(st["sum"] as Dictionary)[key + "|伞撑开"] = n
					print("[RS] %s 第 %.1f 秒 %s 伞撑开(第 %d 次) · 罩到 %d 人" % [lane, float(st["steps"]) * float(s.SIM_DT), who, n, (stt.get("pa_units", []) as Array).size()])
					_want(int(st["frame"]) + 40, "%s_%s_伞开%d" % [lane, who.replace(":", "_"), n])
				if not op and bool(st.get(ok, false)):
					print("[RS] %s 第 %.1f 秒 %s 收伞 · 血 %.0f/%.0f · 060 本局=%s" % [lane, float(st["steps"]) * float(s.SIM_DT), who, float(u["hp"]), float(u["maxHp"]), str((u.get("_st_eq", {}) as Dictionary).get("p2eq_060", {}))])
				st[ok] = op
			if u.has("_creamShieldVal"):
				var real: float = s._spec.val(u, "p2eq_071_cream")
				var shown: float = float(u.get("_creamShieldVal", 0.0))
				var prev: float = float(st.get("cr_prev_" + key, real))
				st["cr_prev_" + key] = real
				if absf(real - shown) > 0.5:
					(st["sum"] as Dictionary)[key + "|奶油盾差一步(只差这一步)"] = int((st["sum"] as Dictionary).get(key + "|奶油盾差一步(只差这一步)", 0)) + (1 if absf(prev - shown) <= 0.5 else 0)
					if absf(prev - shown) > 0.5:
						(st["sum"] as Dictionary)[key + "|奶油盾真不一致步数"] = int((st["sum"] as Dictionary).get(key + "|奶油盾真不一致步数", 0)) + 1
						if int(st.get("crp_" + key, 0)) < 3:
							st["crp_" + key] = int(st.get("crp_" + key, 0)) + 1
							print("[RS] %s 第 %.1f 秒 %s 奶油盾 显示 %.0f · 实际 %.0f · 上一步 %.0f" % [lane, float(st["steps"]) * float(s.SIM_DT), who, shown, real, prev])
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
		if str(s._dl_state) == "done":
			break
	print("[RS] —— %s 打了 %.1f 秒" % [str(st["lane"]), float(st["steps"]) * float(s.SIM_DT)])
	for k in (st["sum"] as Dictionary).keys():
		print("[RS] 汇总 %s = %s" % [str(k), str((st["sum"] as Dictionary)[k])])
	print("[RS] 结束 state=%s 截图 %d 张 → %s" % [str(s._dl_state), _shots, ProjectSettings.globalize_path(OUT)])
	Spar.end()
	get_tree().quit(0)


func _want(frame: int, label: String) -> void:
	_pending.append([frame, label])


func _take_due(frame: int) -> void:
	var due: Array = _pending.filter(func(p): return int(p[0]) <= frame)
	if due.is_empty() or DisplayServer.get_name() == "headless":
		return
	_pending = _pending.filter(func(p): return int(p[0]) > frame)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	for p in due:
		if _shots >= MAX_SHOTS:
			return
		_shots += 1
		img.save_png(ProjectSettings.globalize_path("%s/%02d_%s.png" % [OUT, _shots, str(p[1])]))
