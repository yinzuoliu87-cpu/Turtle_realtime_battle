extends "res://tests/verify_stream_parity.gd"
## verify_stream_tide_particles.gd —— 直播卡顿两处修法(2026-11-14):
##   A. 粒子只发出生参数 `@afx`, 位置 / 缩放 / 变淡 / 帧号 / 显隐由手机渲染步 `_tick_anim_fx` 按游戏钟自己算(同服务器同一个函数);
##   B. 播放器后台线程提前解下一块(StreamPlayer._prefetch), 主线程取结果的时机与原同步解码一样。
## 用户 11-14:「我朋友…他手机上看，然后发现卡卡的」→ 查出每块在主线程一帧解完(台式机最慢 91 ms) + 043 浪的粒子 30 Hz 逐采样进流
##   (同一局 8 秒带浪 173 KB / 不带 25 KB); 用户「做吧」。
## 做法: 录一局带 043(3★)的对局, 开打第 60 步用法力系统自己的入口 `add_mana` 灌满 ⇒ 走真入口涌浪(同 tests/probes/_probe_stream_043.gd),
##   再用父类 verify_stream_parity 的「录流 → 重放 → 逐采样点比」整套比一遍(节点 id / 显隐 / 帧号 / 贴图 / 变换 / 颜色 / 普查 / 飘字)。
## 判据:
##   ① 分母: 浪真涌了; 流里发了 `@afx` 的粒子 > 0; 手机按它登记的粒子 > 0
##   ② 数据量: 这一局 8 秒的直播数据 ≤ BUDGET 字节(改前 173 KB)
##   ③ 重放逐采样点与原生一致(父类 ★★ 那几条) —— 粒子改成手机自己算之后照样对得上
##   ④ 跟播直播(有线程的平台): 块一块一块到(服务器领先播放头约 4 块), 两帧之间给后台真实时间 ⇒
##      播放中在主线程当场解的块 = 0, 后台解好的块 ≥ 总块数 − 开播缓冲那 4 块; 照样播到结尾、步数一个不少
## 反向验证: 去掉录流器 `ren = ren or drv` ⇒ ② 红; 去掉镜像登记 `_afx_reg` ⇒ ③ 节点那条红(粒子停在出生位置);
##   播放中改回按 want 当场解(need_now = want)⇒ ④ 红(每到一块都在主线程解)。

## 改后实测 58109 字节(本机 11-15), 留约 25% 余量; 改前同一局 173 KB, 不带 043 约 25 KB
const BUDGET := 72000

var _walls_max := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var sc := {"tag": "043 浪粒子", "frames": 480, "seed": "424242", "loadouts": {}, "pairs": [
		["basic", "left", 320.0, 300.0, ["p2eq_043"]],
		["stone", "left", 320.0, 420.0, []],
		["basic", "right", 900.0, 300.0, []],
		["stone", "right", 900.0, 420.0, []]]}
	var nat: Dictionary = await _record_043(sc)
	var chunks: Array = nat["chunks"]
	var meta: Dictionary = nat["meta"]
	var bytes := 0
	for ch in chunks:
		bytes += (ch as PackedByteArray).size()
	print("  [量] 直播数据 %d 块 · 合计 %d 字节 · 发了出生参数的粒子(含 keyframe 重发) %d" % [chunks.size(), bytes, int(meta.get("afx", 0))])
	_ok("① 分母: 浪真涌了(浪墙最多同时 %d 道)" % _walls_max, _walls_max >= 1)
	_ok("① 分母: 流里发了出生参数 `@afx` 的粒子 %d > 0" % int(meta.get("afx", 0)), int(meta.get("afx", 0)) > 0)
	_ok("② 8 秒直播数据 %d 字节 ≤ %d(改前 173 KB)" % [bytes, BUDGET], bytes <= BUDGET)
	await _play_and_compare("det " + str(sc["tag"]), chunks, meta, nat)
	var p: StreamPlayer = _pl
	_ok("① 分母: 手机按出生参数登记的粒子 %d > 0(≤ 流里 %d)" % [p.mirror.afx_reg, int(meta.get("afx", 0))],
		p.mirror.afx_reg > 0 and p.mirror.afx_reg <= int(meta.get("afx", 0)))
	if OS.has_feature("threads"):
		await _live_follow(chunks, meta, nat)
	else:
		print("  [略] ④ 这个平台没有线程, 走同步解码")
	_finish()


## ④ 跟播直播: 块按「服务器领先播放头约 4 块」一块一块放出来; 每帧之前给后台足够的真实时间(像手机两帧之间的 16 ms)。
##   只看后台任务完没完成, 不替播放器收任务(wait_for_task_completion 只能收一次)。
func _live_follow(chunks: Array, meta: Dictionary, nat: Dictionary) -> void:
	var backup: Dictionary = ReplayRecorder.capture_all()
	var b: Node = P.make_player_battle(self, chunks, meta, int(nat["seed"]), nat.get("state", {}), 4)
	b.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	var src = p.src
	var guard := 0
	var lim_max := 4
	p.advance(0.0)
	while p.state != "ended" and p.state != "error" and guard < 20000:
		guard += 1
		if p.first_step >= 0 and p.head >= 0.0 and int(src.limit) >= 0:
			var lim := int((p.head - float(p.first_step)) / float(StreamFormat.CHUNK_STEPS)) + 4
			if lim >= chunks.size():
				src.limit = -1           # 服务器录完了
			elif lim > int(src.limit):
				src.limit = lim
				lim_max = maxi(lim_max, lim)
		var t0 := Time.get_ticks_msec()
		while p._bg_task >= 0 and not WorkerThreadPool.is_task_completed(p._bg_task) and Time.get_ticks_msec() - t0 < 3000:
			OS.delay_msec(1)
		p.advance(2.0 * SIM_DT)
		if guard % 30 == 0:
			await get_tree().process_frame
	var steps := int(meta.get("steps", 0))
	_ok("④ 分母: 跟播从头播到尾(应用 %d / %d 步, 状态 %s), 块是陆续放出来的(最多放到第 %d 块后才录完)" % [p.steps_applied, steps, p.state, lim_max],
		p.state == "ended" and p.steps_applied == steps and lim_max >= 5)
	_ok("④ 跟播: 播放中在主线程当场解的块 %d == 0(后台解好的 %d ≥ %d − 4)" % [p.sync_playing, p.chunks_bg, chunks.size()],
		p.sync_playing == 0 and p.chunks_bg >= chunks.size() - 4)
	b.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	for k in backup:
		var v = backup[k]
		gs.set(str(k), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	gs.test_mode = true


## 与父类 `_record_det` 同一套建场 / 录流, 只多一步: 第 60 步给带 043 的那只灌满法力(同 tests/probes/_probe_stream_043.gd)。
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
	for pp in (sc["pairs"] as Array):
		var u: Dictionary = s._debug._edit_place_unit(str(pp[0]), str(pp[1]), Vector2(float(pp[2]), float(pp[3])))
		if (pp[4] as Array).size() > 0:
			var el: Array = []
			for e in (pp[4] as Array):
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
