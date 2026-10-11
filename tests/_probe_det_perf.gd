extends Node
## _probe_det_perf —— 量「每个 sim 步(含那一帧的演出更新)」花多少微秒, 用确定性场景表(探针, 不进门禁)。
## 跑法: <godot> --headless --path . res://tests/_probe_det_perf.tscn --quit-after 60000
##   PERF_REPS=N  每个场景重复 N 遍取最小值(默认 3)
##   PERF_RAW=1   DetMath 走引擎原版(= 加固前的数值与开销)
## 输出: 每个场景一行 [PERF] tag | 步数 | 合计 ms | 每步 us(最小一遍) , 最后一行总计。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SC := preload("res://tests/_det_scenarios.gd")


func _run(sc: Dictionary) -> Array:
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s.set_process(false)
	s._debug._edit_clear()
	var lo: Dictionary = sc.get("loadouts", {})
	if not lo.is_empty():
		var gs2 = get_node_or_null("/root/GameState")
		if gs2 != null:
			for k in lo:
				gs2.loadouts[str(k)] = int(lo[k])
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 40000.0
	s._edit_full_energy = true
	for p in (sc["pairs"] as Array):
		var pid: String = str(p[0])
		if pid.begins_with("__minion__"):
			var bits: PackedStringArray = pid.split(":")
			s._edit_minion_role = str(bits[1]) if bits.size() > 1 else "front"
			pid = "__minion__"
		var u: Dictionary = s._debug._edit_place_unit(pid, str(p[1]), Vector2(float(p[2]), float(p[3])))
		if (p[4] as Array).size() > 0:
			var el: Array = []
			for e in (p[4] as Array):
				el.append({"id": str(e), "star": 3})
			u["_edit_equips"] = el
		if (p as Array).size() > 5 and bool(p[5]):
			u["active_skills"] = s._resolve_active_skills(pid, false)
			u["skill_idx"] = 0
	s._debug._edit_start_battle()
	var us := 0
	var n0: int = int(s._sim_step_n)
	for _i in range(int(sc["frames"])):
		var t0 := Time.get_ticks_usec()
		s._process(1.0 / 60.0)
		us += Time.get_ticks_usec() - t0
		await get_tree().process_frame
	var steps: int = int(s._sim_step_n) - n0
	var fp: String = SC.fp(s).md5_text()
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return [us, steps, fp]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.week_anchor_ts = int(SC.PIN_WEEK_ANCHOR)
	if OS.get_environment("PERF_MICRO") != "":
		_micro()
		get_tree().quit(0)
		return
	var reps: int = int(OS.get_environment("PERF_REPS")) if OS.get_environment("PERF_REPS") != "" else 3
	if OS.get_environment("PERF_RAW") != "":
		DetMath.raw = true
	print("[PERF] raw=%s reps=%d" % [str(DetMath.raw), reps])
	var tot_us := 0
	var tot_steps := 0
	for sc in SC.all():
		var best := -1
		var steps := 0
		var fp := ""
		for _r in range(reps):
			OS.set_environment("TURTLE_SEED", str((sc as Dictionary)["seed"]))
			var r: Array = await _run(sc as Dictionary)
			OS.set_environment("TURTLE_SEED", "")
			if best < 0 or int(r[0]) < best:
				best = int(r[0])
			steps = int(r[1])
			fp = str(r[2])
		tot_us += best
		tot_steps += steps
		print("[PERF] %s | 步 %d | %.1f ms | 每步 %.1f us | 终局 %s" % [str(sc["tag"]), steps, best / 1000.0,
			float(best) / maxf(1.0, float(steps)), fp.left(8)])
	print("[PERF] 合计 %d 步 %.1f ms 每步 %.1f us" % [tot_steps, tot_us / 1000.0, float(tot_us) / maxf(1.0, float(tot_steps))])
	get_tree().quit(0)


## 单次调用开销(纳秒): 引擎原版 vs DetMath。每项 20 万次, 取三遍最小。
func _micro() -> void:
	var N := 200000
	var v := Vector2(3.7, -1.2)
	var w := Vector2(-0.4, 8.1)
	var names := ["sin", "atan2", "distance_to", "normalized", "rotated"]
	for nm in names:
		var best_raw := 1 << 60
		var best_det := 1 << 60
		for _r in range(3):
			var acc := 0.0
			var t0 := Time.get_ticks_usec()
			for i in range(N):
				var x: float = float(i) * 0.001
				match nm:
					"sin": acc += sin(x)
					"atan2": acc += atan2(x, 1.3)
					"distance_to": acc += v.distance_to(w)
					"normalized": acc += v.normalized().x
					"rotated": acc += v.rotated(x).x
			best_raw = mini(best_raw, Time.get_ticks_usec() - t0)
			t0 = Time.get_ticks_usec()
			for i in range(N):
				var x: float = float(i) * 0.001
				match nm:
					"sin": acc += DetMath.dsin(x)
					"atan2": acc += DetMath.datan2(x, 1.3)
					"distance_to": acc += DetMath.dist(v, w)
					"normalized": acc += DetMath.norm(v).x
					"rotated": acc += DetMath.rotated(v, x).x
			best_det = mini(best_det, Time.get_ticks_usec() - t0)
		print("[MICRO] %s: 引擎 %.0f ns/次 · DetMath %.0f ns/次(含循环开销)" % [nm, best_raw * 1000.0 / N, best_det * 1000.0 / N])
