extends "res://tests/verify_stream_parity.gd"
## 探针(2026-11-14 晚, 不是门禁): 043 海浪护符第三版的粒子(叠加发光材质 / 2×2 帧图 / 抛物线运动)在**手机直播**里能不能照样重放。
## 为什么要单写: verify_stream_parity 的 15 个固定场景(det_scenarios)里没有 043 ⇒ 它全绿说明不了新粒子。
## 做法: 沿用 verify_stream_parity 的录流 + 重放逐采样点比对(`_play_and_compare`), 只换成一局带 043(3★)的对局,
##   开打第 60 步用法力系统自己的入口 `add_mana` 灌满 ⇒ 走真入口涌浪(与 tests/_rec_wave_ingame.gd 同一招)。
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/probes/_probe_stream_043.tscn --quit-after 30000

var _walls_max := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var sc := {"tag": "043 浪第三版", "frames": 480, "seed": "424242", "loadouts": {}, "pairs": [
		["basic", "left", 320.0, 300.0, ["p2eq_043"]],
		["stone", "left", 320.0, 420.0, []],
		["basic", "right", 900.0, 300.0, []],
		["stone", "right", 900.0, 420.0, []]]}
	if OS.get_environment("PROBE_NO043") == "1":
		((sc["pairs"] as Array)[0] as Array)[4] = []      # 对照组: 同一局不带 043, 量直播数据多了多少
	var nat: Dictionary = await _record_043(sc)
	var bytes := 0
	var big := 0
	for ch in (nat["chunks"] as Array):
		bytes += (ch as PackedByteArray).size()
		big = maxi(big, (ch as PackedByteArray).size())
	print("[量] 直播数据 %d 块 · 合计 %d 字节 · 最大一块 %d 字节" % [(nat["chunks"] as Array).size(), bytes, big])
	if OS.get_environment("PROBE_NO043") != "1":
		_ok("浪确实涌了(否则下面的比对是空跑)", _walls_max >= 1, "浪墙最多同时 %d 道" % _walls_max)
	await _play_and_compare("det " + str(sc["tag"]), nat["chunks"], nat["meta"], nat)
	_finish()


## 与父类 `_record_det` 同一套建场 / 录流, 只多一步: 第 60 步给带 043 的那只灌满法力。
func _record_043(sc: Dictionary) -> Dictionary:
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
		if rec._step_n % EVERY <= 2:
			snaps[st] = P.snap_native(rec)
	var fl := P._float_hook(floats, cur)
	get_tree().node_added.connect(fl)
	rec.pre_step()
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 40000.0
	s._edit_full_energy = true
	for p in (sc["pairs"] as Array):
		var u: Dictionary = s._debug._edit_place_unit(str(p[0]), str(p[1]), Vector2(float(p[2]), float(p[3])))
		if (p[4] as Array).size() > 0:
			var el: Array = []
			for e in (p[4] as Array):
				el.append({"id": str(e), "star": 3})
			u["_edit_equips"] = el
	s._debug._edit_start_battle()
	s.set_process(false)
	for i in range(int(sc["frames"])):
		if i % 60 == 0 and i > 0:
			await get_tree().process_frame
		if i > 0:
			rec.pre_step()
		if i == 60:
			for u in s._units:
				if u is Dictionary and str(u.get("side", "")) == "left" and u.get("alive", false):
					for e in (u.get("equips", []) as Array):
						if e is Dictionary and str(e.get("id", "")) == "p2eq_043":
							s._staff_syn.add_mana(u, 99999.0)
		s._sim_step(SIM_DT, float(s._hitstop) > 0.0, not (s._timestop._ts_active as Array).is_empty())
		rec.post_step()
		_walls_max = maxi(_walls_max, (s._equip_tick_sys._tide_walls as Array).size())
	get_tree().node_added.disconnect(fl)
	var m: Dictionary = rec.finish()
	var seed := int(s._battle_rng.seed)
	OS.set_environment("TURTLE_SEED", "")
	s.queue_free()
	RB.DEBUG_EDIT = false
	await get_tree().process_frame
	await get_tree().process_frame
	return {"chunks": rec.chunks, "meta": m, "snaps": snaps, "floats": floats, "state": {}, "seed": seed}
