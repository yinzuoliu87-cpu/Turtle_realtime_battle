extends "res://tests/verify_stream_parity.gd"
## _probe_slam_stream.gd — 过肩摔体检(2026-10-24, 不进门禁): 逐帧直播里过肩摔的腾空 / 倒立是否与本机一致。
## 复用 verify_stream_parity 的「原生录流 → 播放器播 → 同步号逐项比」, 只换场景, 并把采样加密到过肩摔全程每个采样步;
## 另比 Sprite3D.flip_v(父类的节点快照不比它)。

var _fv_nat := {}      # 步 → {镜像节点 id: flip_v}
var _voff_nat := {}    # 步 → 最大 _slam_voff.y
var _fv_cmp := 0
var _fv_bad: Array = []
var _fv_true_seen := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var sc := {"tag": "过肩摔", "frames": 420, "seed": "424242", "loadouts": {"basic": 3}, "pairs": [
		["basic", "left", 320.0, 300.0, []],
		["stone", "right", 420.0, 300.0, []],
		["stone", "right", 300.0, 520.0, []]]}
	var nat: Dictionary = await _record_slam(sc)
	var slam_steps := 0
	for k in _voff_nat:
		if float(_voff_nat[k]) > 1.0:
			slam_steps += 1
	_ok("分母 · 原生录到过肩摔腾空的采样步 %d 个(_slam_voff.y > 1)" % slam_steps, slam_steps >= 10)
	await _play_and_compare("det 过肩摔", nat["chunks"], nat["meta"], nat)
	await _play_dense(nat)
	_ok("分母 · flip_v 比过 %d 个节点·点, 其中原生倒立 %d 个" % [_fv_cmp, _fv_true_seen], _fv_cmp > 0 and _fv_true_seen > 0)
	_ok("★过肩摔倒立(flip_v)手机与本机一致", _fv_bad.is_empty(), str(_fv_bad.slice(0, 4)))
	_finish()


## 父类按「每 2 步一跳、只在与采样同奇偶的步上比」播; 过肩摔的采样步与它奇偶不合 ⇒ 这里一步一推、逢采样步就比。
func _play_dense(nat: Dictionary) -> void:
	var b: Node = P.make_player_battle(self, nat["chunks"], nat["meta"], int(nat["seed"]), nat.get("state", {}))
	b.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	_pl = p
	var snaps: Dictionary = nat["snaps"]
	var st := {"cmp": 0, "interp": 0, "u_n": 0, "n_n": 0, "u_bad": [], "n_bad": [], "c_bad": [], "i_max": 0.0, "i_list": [],
		"pos_max": 0.0, "rot_max": 0.0, "scl_max": 0.0, "col_max": 0.0, "ux_max": 0.0, "tex_gen": 0, "mesh_proc": 0, "missing_n": 0, "extra_n": 0,
		"dot_n": 0, "dot_bad": []}
	p.advance(0.0)
	var guard := 0
	var slam_cmp := 0
	while p.state != "ended" and p.state != "error" and guard < 5000:
		guard += 1
		p.advance(SIM_DT)
		var hd := int(roundf(p.head))
		if (hd >= 76 and hd <= 90) or (hd >= 298 and hd <= 310):
			var pu: Dictionary = P.snap_player(p)["units"]
			var nu = (snaps[hd]["units"] as Dictionary).get(0, null) if snaps.has(hd) else null
			print("    [诊断] 步%d 播放 单位0 x=%.3f | 原生快照 %s | voff原生=%.2f" % [hd, float(((pu.get(0, [Vector2.ZERO]) as Array)[0] as Vector2).x), ("x=%.3f" % float(((nu as Array)[0] as Vector2).x)) if nu != null else "(无快照)", float(_voff_nat.get(hd, -1.0))])
		if snaps.has(hd) and float(_voff_nat.get(hd, 0.0)) > 0.0:
			_cmp(hd, snaps[hd], P.snap_player(p), st)
			if float(_voff_nat.get(hd, 0.0)) > 1.0:
				slam_cmp += 1
	print("  [量] 逐步播: 比过采样点 %d(其中过肩摔腾空中 %d) · 节点·点 %d · 位置误差上限 %.5f" % [int(st["cmp"]), slam_cmp, int(st["n_n"]), float(st["pos_max"])])
	_ok("分母 · 逐步播比过的过肩摔腾空采样点 %d" % slam_cmp, slam_cmp >= 10)
	_ok("★★逐步播 · 过肩摔全程 单位位置 / 血 一致", (st["u_bad"] as Array).is_empty(), str((st["u_bad"] as Array).slice(0, 4)))
	_ok("★★逐步播 · 过肩摔全程 镜像节点(含单位立绘, 立绘位置里叠着 _slam_voff) 变换一致", (st["n_bad"] as Array).is_empty(),
		"缺 %d 多 %d · %s" % [int(st["missing_n"]), int(st["extra_n"]), str((st["n_bad"] as Array).slice(0, 4))])
	b.queue_free()
	await get_tree().process_frame


func _cmp(s: int, a: Dictionary, b: Dictionary, st: Dictionary) -> void:
	super._cmp(s, a, b, st)
	if not _fv_nat.has(s) or _pl == null:
		return
	var m: Dictionary = _fv_nat[s]
	for id in m:
		var n = _pl.mirror.nodes.get(int(id), null)
		if n == null or not is_instance_valid(n) or not (n is Sprite3D):
			continue
		_fv_cmp += 1
		if bool(m[id]):
			_fv_true_seen += 1
		if bool(m[id]) != (n as Sprite3D).flip_v:
			_fv_bad.append("步%d 节点%d 原生%s 播放%s" % [s, int(id), str(m[id]), str((n as Sprite3D).flip_v)])


func _record_slam(sc: Dictionary) -> Dictionary:
	OS.set_environment("TURTLE_SEED", str(sc["seed"]))
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
	var rec := StreamRecorder.new(s, {"keep": true})
	rec.start()
	var snaps := {}
	var floats := {}
	var cur := [-1]
	rec.on_sampled = func(st: int) -> void:
		cur[0] = st
		var vmax := 0.0
		for u in (s._units as Array):
			vmax = maxf(vmax, float((u.get("_slam_voff", Vector3.ZERO) as Vector3).y))
		## 过肩摔全程(以及每 60 步一个常规点)都拍
		if vmax > 0.0 or rec._step_n % 60 <= 2:
			snaps[st] = P.snap_native(rec)
			_voff_nat[st] = vmax
			var fm := {}
			for t in rec._tn:
				var tt: StreamRecorder.TN = t
				if tt.kind == StreamRecorder.K_SPRITE and is_instance_valid(tt.n):
					fm[tt.id] = (tt.n as Sprite3D).flip_v
			_fv_nat[st] = fm
	var fl := P._float_hook(floats, cur)
	get_tree().node_added.connect(fl)
	rec.pre_step()
	var gs2 = get_node_or_null("/root/GameState")
	for k in (sc.get("loadouts", {}) as Dictionary):
		gs2.loadouts[str(k)] = int(sc["loadouts"][k])
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 40000.0
	s._edit_full_energy = true
	for p in (sc["pairs"] as Array):
		s._debug._edit_place_unit(str(p[0]), str(p[1]), Vector2(float(p[2]), float(p[3])))
	s._debug._edit_start_battle()
	s.set_process(false)
	for i in range(int(sc["frames"])):
		if i % 60 == 0 and i > 0:
			await get_tree().process_frame
		if i > 0:
			rec.pre_step()
		s._sim_step(SIM_DT, float(s._hitstop) > 0.0, not (s._timestop._ts_active as Array).is_empty())
		rec.post_step()
	get_tree().node_added.disconnect(fl)
	var m: Dictionary = rec.finish()
	var seed := int(s._battle_rng.seed)
	OS.set_environment("TURTLE_SEED", "")
	s.queue_free()
	RB.DEBUG_EDIT = false
	await get_tree().process_frame
	await get_tree().process_frame
	return {"chunks": rec.chunks, "meta": m, "snaps": snaps, "floats": floats, "state": {}, "seed": seed}
