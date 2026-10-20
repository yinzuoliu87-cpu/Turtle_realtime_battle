extends Node
## _tw_motion_probe —— 探针(不是门禁): 位移演出在「本机原生渲染」与「录流→播放」两边的立绘轨迹是否一致。
## A. det 场景原生跑(同时录流), 每个渲染步(每 2 步)记每个单位立绘 position; 再按流播, 一步一推, 记同样的东西。
## B. 交互累加器(非 det)按 20 / 60 fps 喂, 每帧渲染步, 看位移段里立绘是否跟着 pos 走。
## C. 复现 _th_shots 的现象: 先跑几帧交互(存了 _prev_pos), 再切 det。

const P := preload("res://tests/_stream_play.gd")
const SC := preload("res://scripts/referee/det_scenarios.gd")
const SIM_DT := 1.0 / 60.0
const MOVE_PX := 3.0      # 一步位移 > 3 像素 = 位移演出(普通走路 ≈ 1~2 像素/步)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	if OS.get_environment("TW_REF") != "":
		await _probe_referee()   # ★先跑: 后面 _build 会把 DEBUG_EDIT 静态开关置真, 裁判局就成了调试场、永远不开打
	var want := OS.get_environment("TW_SC")
	for sc in SC.all():
		var tag := str((sc as Dictionary)["tag"])
		if want != "" and not tag.begins_with(want):
			continue
		if OS.get_environment("TW_ONLY_B") == "":
			await _probe_stream(sc)
		await _probe_interactive(sc, 20.0)
		await _probe_interactive(sc, 30.0)
		await _probe_interactive(sc, 60.0)
	await _probe_th()
	get_tree().quit()


func _spr_pos(u: Dictionary):
	var s = u.get("sprite")
	if s == null or not is_instance_valid(s):
		return null
	return (s as Node3D).position


func _voff(u: Dictionary) -> Vector3:
	return u.get("_slam_voff", Vector3.ZERO) + u.get("_bear_voff", Vector3.ZERO) + u.get("_atk_voff", Vector3.ZERO)


## 建 det 场景(同 verify_stream_parity._record_det)。rec 可空。
func _build(sc: Dictionary, det: bool) -> Node:
	OS.set_environment("TURTLE_SEED", str(sc["seed"]) if det else "")
	var RB = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	RB.DEBUG_EDIT = true
	var s = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	s._debug._edit_clear()
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	return s


func _place(s: Node, sc: Dictionary) -> void:
	var lo: Dictionary = sc.get("loadouts", {})
	var gs2 = get_node_or_null("/root/GameState")
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
	s.set_process(false)


## 位移段: 每个单位 pos 一步变化 > MOVE_PX 或 voff/height 非零 的连续步
func _segments(traj: Dictionary) -> Array:
	var segs: Array = []
	for idx in traj:
		var tr: Dictionary = traj[idx]
		var ks: Array = tr.keys()
		ks.sort()
		var inside := false
		var start := -1
		var prev = null
		for s in ks:
			var row: Array = tr[s]
			var mv := false
			if prev != null:
				mv = (row[0] as Vector2).distance_to(prev[0]) > MOVE_PX * (int(s) - int(prev[-1]))
			mv = mv or (row[2] as Vector3).length() > 0.01 or float(row[1]) > 0.01
			if mv and not inside:
				inside = true
				start = int(s)
			elif not mv and inside:
				inside = false
				segs.append([idx, start, int(s)])
			prev = row + [s]
		if inside:
			segs.append([idx, start, int(ks[-1])])
	return segs


func _probe_stream(sc: Dictionary) -> void:
	var tag := str(sc["tag"])
	var s: Node = await _build(sc, true)
	var rec := StreamRecorder.new(s, {"keep": true})
	rec.start()
	var nat := {}       # idx → 步 → [pos, height, voff, spr_pos(渲染步才有), id]
	rec.on_sampled = func(st: int) -> void:
		var ren: bool = rec._step_n % 2 == 0
		for i in range(rec._uk.size()):
			var u: Dictionary = rec._uk[i]
			if not bool(u.get("alive", false)):
				continue
			if not nat.has(i):
				nat[i] = {}
			nat[i][st] = [u.get("pos", Vector2.ZERO), float(u.get("height", 0.0)), _voff(u), _spr_pos(u) if ren else null, str(u.get("id", "")),
				u.has("_prev_pos")]
	rec.pre_step()
	_place(s, sc)
	for i in range(int(sc["frames"])):
		if i % 60 == 0 and i > 0:
			await get_tree().process_frame
		if i > 0:
			rec.pre_step()
		s._sim_step(SIM_DT, float(s._hitstop) > 0.0, not (s._timestop._ts_active as Array).is_empty())
		rec.post_step()
	var meta: Dictionary = rec.finish({})
	var chunks: Array = rec.chunks
	var seed := int(str(sc["seed"]))
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await _play_cmp(tag, nat, chunks, meta, seed, {})


func _play_cmp(tag: String, nat: Dictionary, chunks: Array, meta: Dictionary, seed: int, state: Dictionary) -> void:
	## 播放
	OS.set_environment("TURTLE_SEED", "")
	var backup: Dictionary = ReplayRecorder.capture_all()
	var b: Node = P.make_player_battle(self, chunks, meta, seed, state)
	b.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	var ply := {}
	p.advance(0.0)
	var guard := 0
	while p.state != "ended" and p.state != "error" and guard < 20000:
		guard += 1
		p.advance(SIM_DT * float(maxi(1, int(OS.get_environment("TW_K")))))
		var st := int(roundf(p.head))
		for idx in p.units:
			var u: Dictionary = p.units[idx]
			if not bool(u.get("alive", false)):
				continue
			if not ply.has(idx):
				ply[idx] = {}
			ply[idx][st] = [u.get("pos", Vector2.ZERO), float(u.get("height", 0.0)), _voff(u), _spr_pos(u)]
		if guard % 60 == 0:
			await get_tree().process_frame
	b.queue_free()
	var gsx = get_node_or_null("/root/GameState")
	for k in backup:
		var v = backup[k]
		gsx.set(str(k), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	gsx.test_mode = true
	await get_tree().process_frame
	## 比
	var segs := _segments(nat)
	var cmp_n := 0
	var seg_cmp := 0
	var max_d := 0.0
	var max_d_seg := 0.0
	var max_xz_seg := 0.0
	var worst := ""
	var prev_flag := 0
	var mid_n := 0
	var gworst := ""
	var peak_n := 0.0
	var peak_p := 0.0
	var mid_max := 0.0
	var seg_travel := 0.0
	var seg_travel_ply := 0.0
	for idx in nat:
		for st in nat[idx]:
			if bool(nat[idx][st][5]):
				prev_flag += 1
	for sg in segs:
		var idx: int = int(sg[0])
		var s0: int = int(sg[1])
		var s1: int = int(sg[2])
		var hit := false
		var first_n = null
		var last_n = null
		var first_p = null
		var last_p = null
		for st in range(s0, s1 + 1):
			if not nat[idx].has(st) or not ply.has(idx) or not (ply[idx] as Dictionary).has(st):
				continue
			var a: Array = nat[idx][st]
			var bb: Array = ply[idx][st]
			if a[3] != null and bb[3] != null:
				var d: float = (a[3] as Vector3).distance_to(bb[3])
				var dxz: float = Vector2((a[3] as Vector3).x, (a[3] as Vector3).z).distance_to(Vector2((bb[3] as Vector3).x, (bb[3] as Vector3).z))
				max_d_seg = maxf(max_d_seg, d)
				max_xz_seg = maxf(max_xz_seg, dxz)
				if d > 0.05 and worst == "":
					worst = "单位%d(%s) 步%d 原生%s 播放%s" % [idx, str(a[4]), st, str(a[3]), str(bb[3])]
				seg_cmp += 1
				peak_n = maxf(peak_n, (a[2] as Vector3).y + float(a[1]))
				peak_p = maxf(peak_p, (bb[2] as Vector3).y + float(bb[1]))
				hit = true
				if first_n == null:
					first_n = a[3]; first_p = bb[3]
				last_n = a[3]; last_p = bb[3]
			elif a[3] == null and bb[3] != null:
				## 两次采样中间那步: 播放端插值, 与原生 pos 的世界投影比(只比 XZ)
				mid_n += 1
		if hit:
			seg_travel = maxf(seg_travel, (last_n as Vector3).distance_to(first_n))
			seg_travel_ply = maxf(seg_travel_ply, (last_p as Vector3).distance_to(first_p))
	for idx in nat:
		for st in nat[idx]:
			var a: Array = nat[idx][st]
			if a[3] == null or not ply.has(idx) or not (ply[idx] as Dictionary).has(st) or ply[idx][st][3] == null:
				continue
			cmp_n += 1
			var dd: float = (a[3] as Vector3).distance_to(ply[idx][st][3])
			if dd > max_d:
				max_d = dd
				gworst = "单位%d(%s) 步%d 原生spr%s pos%s voff%s / 播放spr%s pos%s voff%s" % [idx, str(a[4]), st, str(a[3]), str(a[0]), str(a[2]),
					str(ply[idx][st][3]), str(ply[idx][st][0]), str(ply[idx][st][2])]
	## 位移段的种类(单位 id)
	var kinds := {}
	for sg in segs:
		var nm: String = str(nat[int(sg[0])][int(sg[1])][4])
		kinds[nm] = int(kinds.get(nm, 0)) + 1
	print("[tw A] %s 步%d 单位%d 位移段%d %s · 段内比对 %d 点(渲染步) 最大立绘差 %.4f 米 (XZ %.4f) · 全局比对 %d 点 最大 %.4f · 段最大位移 原生 %.2f 米/播放 %.2f 米 · 原生带 _prev_pos 的单位·步 %d · %s" % [tag,
		int(meta.get("steps", 0)), nat.size(), segs.size(), str(kinds), seg_cmp, max_d_seg, max_xz_seg, cmp_n, max_d, seg_travel, seg_travel_ply, prev_flag, worst])
	print("[tw A]   全局最差: ", gworst, " · 段内最高腾空(voff.y+height) 原生 %.3f / 播放 %.3f" % [peak_n, peak_p])



## E. 真裁判路径(RefereeRunner, 交互累加器 + referee 模式), 最重那局
func _probe_referee() -> void:
	var J := preload("res://tests/_stream_jobs.gd")
	var job: Dictionary = J.heavy()
	var nat := {}
	var hook := func(bt) -> void:
		bt.ready.connect(func() -> void:
			var rec: StreamRecorder = bt._replay.stream
			rec.on_sampled = func(st: int) -> void:
				var ren: bool = rec._step_n % 2 == 0
				for i in range(rec._uk.size()):
					var u: Dictionary = rec._uk[i]
					if not bool(u.get("alive", false)):
						continue
					if not nat.has(i):
						nat[i] = {}
					nat[i][st] = [u.get("pos", Vector2.ZERO), float(u.get("height", 0.0)), _voff(u), _spr_pos(u) if ren else null, str(u.get("id", "")),
						u.has("_prev_pos")]
			, CONNECT_ONE_SHOT)
	var res: Dictionary = await RefereeRunner.run(self, job, hook, {"keep": true})
	var st := {}
	var b64 := str(res.get("replay_b64", ""))
	if b64 != "":
		st = ReplayRecorder.decode(Marshalls.base64_to_raw(b64)).get("state", {})
	await _play_cmp("真裁判局(最重)", nat, res.get("stream_chunks", []), res.get("stream", {}), RefereeJob.seed_of(job), st)


## B. 交互(非 det)累加器: 每帧 rd = 1/fps, 渲染步每帧一次 —— 量位移段里立绘每帧是否跟着动
func _probe_interactive(sc: Dictionary, fps: float) -> void:
	var tag := str(sc["tag"])
	var s: Node = await _build(sc, false)
	s._battle_rng.seed = int(str(sc["seed"]))
	_place(s, sc)
	var rd := 1.0 / fps
	var frames := int(float(sc["frames"]) / 60.0 * fps)
	var stuck := 0          # 位移段里: pos 本帧动了 > 3 像素 而立绘没动(< 0.01 米)
	var moved := 0          # 位移段里 pos 本帧动了 > 3 像素 的单位·帧
	var lagmax := 0.0       # 立绘 XZ 与「插值目标」的差
	var stuck2 := 0
	var leap_frames := 0
	var leap_ys := {}
	var last := {}
	for f in range(frames):
		if f % 60 == 0 and f > 0:
			await get_tree().process_frame
		s._advance_sim_accum(rd)
		s._render._render_step(rd, float(s._hitstop) > 0.0, not (s._timestop._ts_active as Array).is_empty())
		for u in s._units:
			if not bool(u.get("alive", false)):
				continue
			var sp = _spr_pos(u)
			if sp == null:
				continue
			var key: int = (u as Dictionary).get("sprite").get_instance_id()
			var pos: Vector2 = u["pos"]
			if last.has(key):
				var lp: Vector2 = last[key][0]
				var ls: Vector3 = last[key][1]
				var still: bool = Vector2(sp.x, sp.z).distance_to(Vector2(ls.x, ls.z)) < 0.01
				if pos.distance_to(lp) > MOVE_PX:
					moved += 1
					if still:
						stuck += 1
						if bool(last[key][2]):
							stuck2 += 1
				last[key] = [pos, sp, still and pos.distance_to(lp) > MOVE_PX]
			else:
				last[key] = [pos, sp, false]
			if (u.get("_slam_voff", Vector3.ZERO) as Vector3).y > 0.5:
				leap_frames += 1
				leap_ys[snappedf(sp.y, 0.01)] = true
			var want: Vector2 = (u.get("_prev_pos", pos) as Vector2).lerp(pos, s._render_alpha)
			var w3: Vector3 = s._world_pos(want, 0.0)
			lagmax = maxf(lagmax, Vector2(sp.x, sp.z).distance_to(Vector2(w3.x, w3.z)) - _voff(u).length())
	print("[tw B] %s 交互 %.0f fps: 位移帧(单位·帧, pos 一帧动 > %.0f 像素) %d, 其中立绘本帧没动 %d、连续两帧没动 %d · 立绘 XZ 与 lerp(prev,pos,alpha) 最大差(扣 voff) %.4f 米 · 跳砸腾空帧 %d 立绘高度不同值 %d 个" % [tag, fps, MOVE_PX, moved, stuck, stuck2, lagmax, leap_frames, leap_ys.size()])
	s.queue_free()
	await get_tree().process_frame


## C. _th_shots 现象: 先 4 帧交互(会存 _prev_pos), 再 det —— 立绘是否冻在第 4 帧
func _probe_th() -> void:
	var sc: Dictionary = {}
	for x in SC.all():
		if str((x as Dictionary)["tag"]).begins_with("⑦"):
			sc = x
	var s: Node = await _build(sc, false)
	_place(s, sc)
	for f in range(4):
		s._advance_sim_accum(SIM_DT)
		s._render._render_step(SIM_DT, false, false)
	s._deterministic = true
	var u0: Dictionary = s._units[0]
	var sp0: Vector3 = _spr_pos(u0)
	var p0: Vector2 = u0["pos"]
	for f in range(600):
		s._process(SIM_DT)        # 真入口: det 分支(每帧 1 步 + 自己的渲染步)
	var sp1: Vector3 = _spr_pos(u0)
	print("[tw C] 交互 4 帧后切 det: 单位 %s pos 走了 %.1f 像素, 立绘 XZ 走了 %.3f 米, 有 _prev_pos=%s" % [str(u0.get("id")),
		(u0["pos"] as Vector2).distance_to(p0), Vector2(sp1.x, sp1.z).distance_to(Vector2(sp0.x, sp0.z)), str(u0.has("_prev_pos"))])
	## 纯 det(从没存过 _prev_pos)
	var s2: Node = await _build(sc, true)
	_place(s2, sc)
	var v0: Dictionary = s2._units[0]
	s2._render._render_step(SIM_DT, false, false)
	var q0: Vector3 = _spr_pos(v0)
	var pp0: Vector2 = v0["pos"]
	for f in range(600):
		s2._sim_step(SIM_DT, float(s2._hitstop) > 0.0, not (s2._timestop._ts_active as Array).is_empty())
		s2._render._render_step(SIM_DT, false, false)
	var q1: Vector3 = _spr_pos(v0)
	print("[tw C] 纯 det: 单位 %s pos 走了 %.1f 像素, 立绘 XZ 走了 %.3f 米, 有 _prev_pos=%s" % [str(v0.get("id")),
		(v0["pos"] as Vector2).distance_to(pp0), Vector2(q1.x, q1.z).distance_to(Vector2(q0.x, q0.z)), str(v0.has("_prev_pos"))])
	s.queue_free()
	s2.queue_free()
	await get_tree().process_frame
