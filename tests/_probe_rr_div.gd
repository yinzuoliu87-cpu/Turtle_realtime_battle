extends "res://tests/verify_replay_roundtrip.gd"
## 探针: 录一局 + 播一遍(不跑反证), 每个 sim 步记一份「富指纹」(单位全部标量字段 + 战斗场全部标量成员 + rng 状态),
## 播放对不上时打出第一处分岔的步号与字段。环境变量 RRP_SAVE=<路径> 时把录像存下来。

var _rich_on := true
var _last_sig := ""


static func _scalar(v) -> bool:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR2I:
			return true
	return false


static func rich(b) -> Dictionary:
	var out := {}
	out["rng"] = str(b._battle_rng.state)
	out["step"] = str(b._sim_step_n)
	var nt := 0
	for tw in b._sim_tweens:
		if tw != null and tw.is_valid(): nt += 1
	out["tweens"] = str(nt)
	for p in b.get_property_list():
		if (int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n := str(p.get("name", ""))
		var v = b.get(n)
		if _scalar(v):
			out["B." + n] = var_to_str(v)
		elif v is Array:
			out["B#" + n] = str((v as Array).size())
	var i := 0
	for u in b._units:
		var ks: Array = (u as Dictionary).keys()
		out["U%d.keyorder" % i] = str(hash(str(ks)))
		for k in ks:
			var v = u[k]
			if _scalar(v):
				out["U%d.%s" % [i, str(k)]] = var_to_str(v)
			elif v is Array:
				out["U%d#%s" % [i, str(k)]] = str((v as Array).size())
		i += 1
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	OS.set_environment("TURTLE_SEED", "")
	_setup_gs(gs)
	var r1: Dictionary = await _run_rich(PAT_REC, true)
	var hist: Array = gs.match_history
	var rid: String = str((hist[0] as Dictionary).get("replay_id", "")) if not hist.is_empty() else ""
	var rec: Dictionary = ReplayRecorder.load_record(rid) if rid != "" else {}
	if rec.is_empty():
		print("PROBE no record"); get_tree().quit(2); return
	if OS.get_environment("RRP_SAVE") != "":
		var f := FileAccess.open(OS.get_environment("RRP_SAVE"), FileAccess.WRITE)
		f.store_buffer(ReplayRecorder.encode(rec)); f.close()
	_tamper_gs(gs)
	ReplayRecorder.begin_play(rec)
	var r2: Dictionary = await _run_rich(PAT_PLAY, false)
	print("PROBE play div=%d why=%s cps=%d end=%d" % [int(r2["div"]), str(r2["why"]), int(r2["cps"]), int(rec["end"]["s"])])
	_report(r1, r2, int(rec["end"]["s"]))
	print("PROBE DONE div=%d" % int(r2["div"]))
	get_tree().quit(0)


func _report(a: Dictionary, b: Dictionary, end_s: int) -> void:
	var ra: Dictionary = a["rich"]
	var rb: Dictionary = b["rich"]
	var shown := 0
	for k in range(1, end_s + 1):
		if not ra.has(k) or not rb.has(k): continue
		var da: Dictionary = ra[k]
		var db: Dictionary = rb[k]
		var diffs: Array = []
		for key in da:
			if _ign(str(key)): continue
			if str(db.get(key, "<none>")) != str(da[key]):
				diffs.append("%s: rec=%s play=%s" % [key, str(da[key]), str(db.get(key, "<none>"))])
		for key in db:
			if not da.has(key) and not _ign(str(key)):
				diffs.append("%s: rec=<none> play=%s" % [key, str(db[key])])
		diffs.sort()
		if not diffs.is_empty() and str(diffs) != _last_sig:
			_last_sig = str(diffs)
			print("PROBE DIFF step %d (frame rec=%s play=%s) n=%d" % [k, str(a["frame_of"].get(k, -1)), str(b["frame_of"].get(k, -1)), diffs.size()])
			for d in diffs.slice(0, 60): print("   ", d)
			shown += 1
			if shown >= 14: return
	print("PROBE no rich diff")


const IGN_U := ["anim_t", "bob_phase", "_prev_pos", "_prev_height", "last_x", "_run_acc_t", "_run_acc", "keyorder", "anim_frame", "flash_t"]


func _ign(key: String) -> bool:
	if key.begins_with("B."): return _ignore_b(key)
	var dot := key.find(".")
	if key.begins_with("U") and dot > 0:
		return key.substr(dot + 1) in IGN_U
	return false


## 战斗场里与帧/渲染/演出相关、两遍天然不同的成员(探针噪声), 不报。
func _ignore_b(k: String) -> bool:
	for s in ["_render_alpha", "_sim_accum", "_frame_sim_dt", "_shake", "_juice", "_hb", "_cam", "_fps", "_replay"]:
		if k.contains(s): return true
	return false


func _run_rich(pat: Array, as_player: bool) -> Dictionary:
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	var richd := {}
	var frame_of := {}
	var fr := [0]
	s.sim_stepped.connect(func() -> void:
		richd[int(s._sim_step_n)] = rich(s)
		frame_of[int(s._sim_step_n)] = fr[0])
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
						var p0: Vector2 = u["pos"]
						u["pos"] = s._dl_sys._dl_clamp_place(p0 + Vector2(-70.0, 30.0 + 20.0 * fights))
						break
			elif st == "place" and st_frames == 25 and is_instance_valid(s._dl_go_btn):
				s._dl_go_btn.pressed.emit()
				fights += 1
			elif st == "fight" and fights >= 2 and st_frames == 300 and not surrendered:
				s._do_surrender()
				surrendered = true
		fr[0] = i
		s._process(float(pat[i % pat.size()]))
		await get_tree().process_frame
		i += 1
		if s._replay.diverged_at >= 0:
			break
		if str(s._dl_state) == "done":
			done_frames += 1
			if done_frames > 30:
				break
	var out := {"rich": richd, "frame_of": frame_of, "div": int(s._replay.diverged_at), "why": str(s._replay.diverge_why),
		"cps": int(s._replay.cp_checked)}
	for _g in range(10):
		await get_tree().process_frame
	s.queue_free()
	for _g in range(4):
		await get_tree().process_frame
	return out
