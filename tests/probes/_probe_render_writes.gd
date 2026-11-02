extends Node
## _probe_render_writes.gd — 量「渲染那一步往单位字典里写了哪些键」, 以及换渲染节奏后 sim 状态哪些键分叉。
## 方案书 docs/plans/20261003-跨设备回放.md §9.6。不进门禁, 手跑。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const PAT_A := [1]
const PAT_B := [0, 3, 1, 0, 2, 0, 1, 3]
const MAX_STEPS := 4000


func _setup(gs, leaders: Array, bot: int) -> void:
	gs.reset_dual_lane()
	gs.test_mode = true
	gs.tutorial_active = false
	gs.week_phase = "ranked"
	gs.season_leaders = leaders.duplicate()
	gs.left_team.assign(leaders)
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": leaders[0]}, {"kind": "minion", "role": "back", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": leaders[1], "equips": []},
			{"kind": "leader", "slot": 2, "id": leaders[2], "equips": []}, {"kind": "minion", "role": "front", "equips": []}],
	}
	gs.persistent_equipped = {}
	gs.loadouts = {"headless": 3}
	gs.season_level = 10
	gs.trainer_skill = "magic_stone"
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + bot
	gs.dual_ghost = Backend.make_bot(bot, rng)
	gs.dual_active = true


static func _prim(v) -> bool:
	match typeof(v):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR, TYPE_VECTOR2I:
			return true
	return false


static func _deep(v, depth: int = 0) -> String:
	if depth > 4: return "…"
	match typeof(v):
		TYPE_DICTIONARY:
			if (v as Dictionary).has("side") and (v as Dictionary).has("id") and depth > 0:
				return "<U %s/%s>" % [str(v["id"]), str(v["side"])]
			var ks := (v as Dictionary).keys()
			var parts: Array = []
			for k in ks:
				parts.append(str(k) + "=" + _deep(v[k], depth + 1))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var parts2: Array = []
			for x in v:
				parts2.append(_deep(x, depth + 1))
			return "[" + ",".join(parts2) + "]"
		TYPE_OBJECT:
			if v == null or not is_instance_valid(v): return "<freed>"
			var o: Object = v
			var extra := ""
			if o is Sprite3D: extra = " f=%d vis=%s a=%.3f" % [(o as Sprite3D).frame, str((o as Sprite3D).visible), (o as Sprite3D).modulate.a]
			elif o is Node3D: extra = " vis=%s" % str((o as Node3D).visible)
			elif o is Tween: extra = " run=%s valid=%s t=%.3f" % [str((o as Tween).is_running()), str((o as Tween).is_valid()), (o as Tween).get_total_elapsed_time()]
			return "<" + o.get_class() + extra + ">"
		TYPE_CALLABLE:
			return "<callable>"
	return str(v)


static func _ukey(u: Dictionary, i: int) -> String:
	return "%d/%s/%s" % [i, str(u.get("id", "")), str(u.get("side", ""))]


static func _state(s) -> Dictionary:
	var out := {}
	var i := 0
	for u in s._units:
		var d := {}
		for k in u:
			var v = u[k]
			if _prim(v):
				d[k] = v
		out[_ukey(u, i)] = d
		i += 1
	var bd := {"rng": int(s._battle_rng.state), "pend": (s._pending_shots as Array).size()}
	for p in s.get_property_list():
		if (int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0: continue
		var n := str(p["name"])
		if n in ["_render_alpha", "_sim_accum", "_frame_sim_dt"]: continue
		var v = s.get(n)
		if _prim(v): bd["B." + n] = v
		elif v is Array: bd["B#" + n] = (v as Array).size()
	out["battle"] = bd
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	## ★手跑也不许打真网络: project.godot 里填着真 Supabase 地址; 空白串 = 后端整层停用(与 run-tests.sh 同)
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	OS.set_environment("TURTLE_SEED", "515151")
	var leaders: Array = OS.get_environment("PROBE_LEADERS").split(",") if OS.has_environment("PROBE_LEADERS") else ["ninja", "headless", "hiding"]
	var bot := int(OS.get_environment("PROBE_BOT")) if OS.has_environment("PROBE_BOT") else 20
	_setup(gs, leaders, bot)
	var a: Dictionary = await _run(PAT_A)
	_setup(gs, leaders, bot)
	var b: Dictionary = await _run(PAT_B)
	var w: Array = (a["w"] as Dictionary).keys()
	for k in (b["w"] as Dictionary).keys():
		if not k in w: w.append(k)
	w.sort()
	print("[probe] 渲染写过的键 %d 个: %s" % [w.size(), str(w)])
	print("[probe] 步数 A=%d B=%d" % [int(a["steps"]), int(b["steps"])])
	var first := -1
	var diff_keys := {}
	var n := mini(int(a["steps"]), int(b["steps"]))
	for st in range(1, n + 1):
		var sa: Dictionary = a["st"].get(st, {})
		var sb: Dictionary = b["st"].get(st, {})
		for uk in sa:
			var da: Dictionary = sa[uk]
			var db: Dictionary = sb.get(uk, {})
			for k in da:
				if not db.has(k) or db[k] != da[k]:
					if not diff_keys.has(k):
						diff_keys[k] = [st, uk, str(da[k]), str(db.get(k, "<无>"))]
					if first < 0: first = st
	print("[probe] 首个分叉步 %d · 分叉键(首次出现):" % first)
	var arr := diff_keys.keys()
	arr.sort_custom(func(x, y): return int(diff_keys[x][0]) < int(diff_keys[y][0]))
	for k in arr:
		print("    %s  %s  %s" % [k, "(渲染写)" if k in w else "", str(diff_keys[k])])
	if OS.has_environment("PROBE_W0"):
		var ka: Array = (a["deep"] as Dictionary).keys()
		ka.sort()
		for sn in ka:
			var da: Dictionary = a["deep"][sn]
			var db: Dictionary = b["deep"].get(sn, {})
			var nd := 0
			for k in da:
				if str(da[k]) != str(db.get(k, "<无>")) and not k.ends_with("anim_t") and not k.ends_with("bob_phase") and not k.ends_with("_run_acc_t"):
					nd += 1
					if nd <= 400:
						print("  [deep %d] %s" % [sn, k])
						print("      A=%s" % str(da[k]).substr(0, 300))
						print("      B=%s" % str(db.get(k, "<无>")).substr(0, 300))
	print("PROBE DONE")
	get_tree().quit(0)


func _run(pat: Array) -> Dictionary:
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	var w := {}
	var st_all := {}
	var deep := {}
	var st_frames := 0
	var last_state := ""
	var done := 0
	var i := 0
	while i < MAX_STEPS * 3:
		var st: String = str(s._dl_state)
		if st != last_state:
			last_state = st
			st_frames = 0
		st_frames += 1
		if (st == "overview" or st == "lane_settle") and st_frames == 9:
			s._dl_sys._dl_present_click()
		elif st == "place" and st_frames == 6 and is_instance_valid(s._dl_go_btn):
			s._dl_go_btn.pressed.emit()
		s._sim_step(s.SIM_DT, s._hitstop > 0.0, not s._timestop._ts_active.is_empty())
		s._frame_sim_dt = s.SIM_DT
		st_all[int(s._sim_step_n)] = _state(s)
		var sn: int = int(s._sim_step_n)
		if sn >= int(OS.get_environment("PROBE_W0")) and sn <= int(OS.get_environment("PROBE_W1")):
			var dd := {}
			var ii := 0
			for u in s._units:
				for kk in u:
					dd[_ukey(u, ii) + "." + str(kk)] = _deep(u[kk], 1)
				ii += 1
			dd["pending"] = _deep(s._pending_shots, 1)
			deep[sn] = dd
		var k: int = int(pat[i % pat.size()])
		for _r in range(k):
			var pre := _state(s)
			s._render._render_step(1.0 / 60.0, s._hitstop > 0.0, not s._timestop._ts_active.is_empty())
			var post := _state(s)
			for uk in post:
				var d0: Dictionary = pre.get(uk, {})
				var d1: Dictionary = post[uk]
				for kk in d1:
					if not d0.has(kk) or d0[kk] != d1[kk]:
						w[kk] = int(w.get(kk, 0)) + 1
		i += 1
		if i % 4 == 0:
			await get_tree().process_frame
		if int(s._sim_step_n) >= MAX_STEPS or str(s._dl_state) == "done":
			done += 1
			if done > 5: break
	var out := {"w": w, "st": st_all, "steps": int(s._sim_step_n), "deep": deep}
	s.queue_free()
	for _g in range(4):
		await get_tree().process_frame
	return out
