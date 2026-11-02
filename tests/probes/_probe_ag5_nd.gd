extends Node
## 探针(不进门禁): 同一份录像在同一进程里放两遍, 逐步比所有单位的「标量字段」(不只指纹那几项), 找出第一处不同的字段。
##   PROBE_ID=<id>  PROBE_N=<跑到第几步>  PROBE_FROM=<从第几步开始记>
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const RR := preload("res://scripts/systems/replay/replay_recorder.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var id := OS.get_environment("PROBE_ID").strip_edges()
	var n := int(OS.get_environment("PROBE_N"))
	var from := int(OS.get_environment("PROBE_FROM"))
	var rec: Dictionary = RR.load_record(id)
	var runs := []
	for r in range(int(OS.get_environment("PROBE_RUNS")) if OS.get_environment("PROBE_RUNS") != "" else 2):
		RR.begin_play(rec)
		runs.append(await _run(n, from))
		RR.end_play()
	var a: Dictionary = runs[0]
	for ri in range(1, runs.size()):
		var b: Dictionary = runs[ri]
		var found := false
		for s in range(from, n + 1):
			if not a.has(s) or not b.has(s):
				continue
			var ua: Array = a[s]
			var ub: Array = b[s]
			if ua.size() != ub.size():
				print("[ND] run%d step %d unit count %d vs %d" % [ri, s, ua.size(), ub.size()])
				found = true
				break
			for i in range(ua.size()):
				var da: Dictionary = ua[i]
				var db: Dictionary = ub[i]
				var diffs := []
				for k in da:
					if not db.has(k) or str(da[k]) != str(db[k]):
						diffs.append("%s: %s | %s" % [k, str(da[k]), str(db.get(k, "<缺>"))])
				for k in db:
					if not da.has(k):
						diffs.append("%s: <缺> | %s" % [k, str(db[k])])
				if not diffs.is_empty():
					print("[ND] run%d step %d unit %d %s/%s:\n    %s" % [ri, s, i, da.get("id"), da.get("side"), "\n    ".join(diffs)])
					found = true
			if found:
				break
		if not found:
			print("[ND] run%d identical to run0 over %d..%d" % [ri, from, n])
	get_tree().quit(0)


var _ign: PackedStringArray = OS.get_environment("PROBE_IGN").split(",")


func _snap(s) -> Array:
	var out := []
	for u in s._units:
		var d := {}
		for k in u:
			if str(k) in _ign:
				continue
			var v = u[k]
			match typeof(v):
				TYPE_FLOAT, TYPE_INT, TYPE_BOOL, TYPE_STRING, TYPE_VECTOR2, TYPE_STRING_NAME:
					d[k] = v if typeof(v) != TYPE_FLOAT else RR.exact(v)
				TYPE_ARRAY:
					d[k] = "arr%d" % (v as Array).size()
				TYPE_DICTIONARY:
					if (v as Dictionary).has("id") and (v as Dictionary).has("side"):
						d[k] = "ref:%s/%s@%s" % [v["id"], v["side"], str(v.get("pos"))]
					else:
						d[k] = "dict%d" % (v as Dictionary).size()
		out.append(d)
	var bs := _objsnap(s, "battle", 1)
	var ps := []
	for e in s._pending_shots:
		var src = e.get("src", null)
		var fn = e.get("fn", null)
		if fn is Callable and str(fn.get_method()) in _ign:
			continue
		ps.append("%s/%s:%s:%s" % [str(src.get("id")) if src is Dictionary else "-", str(src.get("side")) if src is Dictionary else "-", RR.exact(float(e.get("delay", -1.0))), str(fn.get_method()) if fn is Callable else str(e.keys())])
	if not "PS" in _ign: bs["PS"] = " ; ".join(ps)
	var pr := []
	for e in s._projectiles:
		var sr = e.get("src", null)
		var tg = e.get("tgt", null)
		pr.append("%s>%s v=%s t=%s" % [str(sr.get("id")) if sr is Dictionary else "-", str(tg.get("id")) + "/" + str(tg.get("side")) if tg is Dictionary else "-", str(is_instance_valid(e.get("node"))), RR.exact(float(e.get("t", 0.0)))])
	bs["PR"] = " ; ".join(pr)
	out.append(bs)
	return out


func _val(v):
	match typeof(v):
		TYPE_FLOAT: return RR.exact(v)
		TYPE_INT, TYPE_BOOL, TYPE_STRING, TYPE_VECTOR2, TYPE_STRING_NAME: return v
		TYPE_ARRAY: return "arr%d" % (v as Array).size()
		TYPE_DICTIONARY: return "dict%d" % (v as Dictionary).size()
	return null


func _objsnap(o: Object, pre: String, depth: int) -> Dictionary:
	var d := {"id": pre, "side": ""}
	for p in o.get_property_list():
		if (int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var k := str(p["name"])
		if k in _ign:
			continue
		var v = o.get(k)
		var sv = _val(v)
		if sv != null:
			d[pre + "." + k] = sv
		elif depth > 0 and v is RefCounted and not (v is Resource):
			var sub := _objsnap(v, pre + "." + k, depth - 1)
			for kk in sub:
				if kk != "id" and kk != "side":
					d[kk] = sub[kk]
	return d


func _run(n: int, from: int) -> Dictionary:
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	var snaps := {}
	s.sim_stepped.connect(func() -> void:
		if int(s._sim_step_n) >= from:
			snaps[int(s._sim_step_n)] = _snap(s))
	await get_tree().process_frame
	var i := 0
	while i < 200000 and int(s._sim_step_n) < n and not s._replay.finished and s._replay.diverged_at < 0:
		s._process(0.05)
		i += 1
		if i % 8 == 0:
			await get_tree().process_frame
	s.queue_free()
	for _g in range(3):
		await get_tree().process_frame
	return snaps
