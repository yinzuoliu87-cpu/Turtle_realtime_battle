extends Node
## _shot_stream_fx.gd — 逐帧直播「本机跑 vs 录流播放」按效果类别实拍(探针, 不进门禁; 由 _shot_stream_hud.gd 改)。
## 两种模式:
##   SHOT_MODE=probe(无头即可): 原生跑一遍(裁判 + 录流), 每个采样步扫 `_world` 里可见节点的出处键(程序网格 / 程序贴图的生成函数名)
##     + 时停 / 路 / 幕布状态, 打印每类效果出现的步号区间 —— 挑步用, 不盲截。
##   SHOT_MODE=shoot(要真窗口, 离屏 + 静音): 与 _shot_stream_hud.gd 相同的两遍(本机每帧 1 步、到步停住拍 / 播放推到同一步拍),
##     SHOT_SHOTS = "步号:名字,步号:名字,…"(名字进文件名), SHOT_END=1 另拍一张收尾(本机横幅 / 播放收尾卡 + 退出)。
## 跑法:
##   SHOT_MODE=probe QUIET=1 <godot> --headless --audio-driver Dummy --path . res://tests/_shot_stream_fx.tscn
##   SHOT_MODE=shoot SHOT_OUT=<目录> SHOT_SHOTS=... QUIET=1 <godot> --position 5000,5000 --resolution 1280x720 --audio-driver Dummy --path . res://tests/_shot_stream_fx.tscn
## 环境 SHOT_JOB = heavy(默认) | mirror。

const J := preload("res://tests/_stream_jobs.gd")
const SIM_DT := 1.0 / 60.0
const END_WAIT := 3.0     # 收尾: 横幅 / 收尾卡有真实钟延时, 多等几秒再拍

var _out := ""
var _native := {}
var _names := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	_out = OS.get_environment("SHOT_OUT")
	if _out == "":
		_out = ProjectSettings.globalize_path("user://fx_shots")
	DirAccess.make_dir_recursive_absolute(_out)
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	var jn := OS.get_environment("SHOT_JOB")
	var job: Dictionary = J.mirror(gs) if jn == "mirror" else (_ts_job(gs) if jn == "ts" else J.heavy())
	if OS.get_environment("SHOT_MODE") == "probe":
		await _probe(gs, job)
	else:
		## ★两遍都锁 20 帧/秒、每帧 1 步 ⇒ 两边都是 20 步/秒真实时间。飘字 / PK 条数字 / 幕布淡入走真实钟 tween:
		##   不锁的话本机(每帧还要录流, 帧慢)与播放(帧快)每秒推的步数不同, 同一步上飘字的年龄不同 ⇒ 拍出假差异(实测多出 20~45 个飘字)。
		Engine.max_fps = int(OS.get_environment("SHOT_FPS")) if OS.get_environment("SHOT_FPS") != "" else 20
		await _shoot(gs, job)
	get_tree().quit(0)


## 时停合成局: 镜像局阵容, 上路小龟带 059 沙漏 3★(其余同镜像局) —— 最重局里 059 在 1★ 小将身上, 一次没放出来。
func _ts_job(gs) -> Dictionary:
	var base: Dictionary = J.mirror(gs)
	var pe: Dictionary = gs.persistent_equipped.duplicate(true)
	pe["basic"] = [{"id": "p2eq_059", "star": 3}]
	gs.persistent_equipped = pe
	var a: Dictionary = J.Backend.build_ghost_snapshot("g_stream_ts_a", {"name": "甲方", "avatar": "basic", "id": "g_stream_ts_a"})
	var b: Dictionary = a.duplicate(true)
	b["profile"] = {"name": "乙方", "avatar": "stone", "id": "g_stream_ts_b"}
	b["ghost_id"] = "g_stream_ts_b"
	return J.job(a, b, int(base.get("seed", J.SEED)))


## ═══════════════ 探针: 每类效果出现在哪些采样步 ═══════════════
func _probe(gs, job: Dictionary) -> void:
	var backup: Dictionary = ReplayRecorder.capture_all()
	var battle: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	var st: Dictionary = RefereeJob.state_for(job, Callable(battle, "_foe_normalize_lane"))
	gs.reset_dual_lane()
	ReplayRecorder.apply_state(st)
	ReplayRecorder.pending_play = {}
	ReplayRecorder.pending_referee = {"seed": RefereeJob.seed_of(job), "id": str(job.get("match_id", "")), "stream": {"keep": true}}
	add_child(battle)
	ReplayRecorder.pending_referee = {}
	var rec: StreamRecorder = battle._replay.stream
	var hits := {}          # 类别 → [[步, 个数]…]
	var last_state := [""]
	rec.on_sampled = func(s: int) -> void:
		var cnt := {}
		_scan(battle._world, cnt)
		var ts: bool = not (battle._timestop._ts_active as Array).is_empty()
		if ts:
			cnt["@timestop"] = 1
		var stt := "%s/%s/%s" % [str(GameState.current_lane), str(battle._dl_state),
			"幕" if (battle._dl_present_root != null and is_instance_valid(battle._dl_present_root)) else "-"]
		if stt != last_state[0]:
			print("[FXPROBE] 状态 步%d %s" % [s, stt])
			last_state[0] = stt
		for k in cnt:
			if not hits.has(k):
				hits[k] = []
			(hits[k] as Array).append([s, int(cnt[k])])
	var guard := 0
	while not bool(battle._over) and guard < 200000:
		guard += 1
		await get_tree().process_frame
	print("[FXPROBE] 结束 步%d over=%s" % [int(battle._sim_step_n), str(battle._over)])
	var ks: Array = hits.keys()
	ks.sort()
	for k in ks:
		var arr: Array = hits[k]
		## 压成区间: 相邻采样步(差 ≤ 2)连起来, 每段记 [起, 止, 段内最大个数]
		var segs: Array = []
		for e in arr:
			if not segs.is_empty() and int(e[0]) - int(segs[-1][1]) <= 2:
				segs[-1][1] = int(e[0])
				segs[-1][2] = maxi(int(segs[-1][2]), int(e[1]))
			else:
				segs.append([int(e[0]), int(e[0]), int(e[1])])
		var parts := PackedStringArray()
		for sg in segs.slice(0, 40):
			parts.append("%d-%d(%d)" % sg)
		print("[FXPROBE] %s 采样点 %d 段 %d: %s%s" % [k, arr.size(), segs.size(), " ".join(parts), " …" if segs.size() > 40 else ""])
	battle.set_process(false)
	battle.queue_free()
	await get_tree().process_frame
	for k in backup:
		var v = backup[k]
		gs.set(str(k), v.duplicate(true) if (v is Array or v is Dictionary) else v)


func _gen_name(r) -> String:
	if r == null or not is_instance_valid(r) or not (r as Object).has_meta(&"stream_gen"):
		return ""
	var m = (r as Object).get_meta(&"stream_gen")
	return str(m[1]) if m is Array and (m as Array).size() > 1 else ""


func _scan(n: Node, cnt: Dictionary) -> void:
	for c in n.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is Node3D and not (c as Node3D).visible:
			continue
		var names := []
		if c is MeshInstance3D:
			names.append(_gen_name((c as MeshInstance3D).mesh))
			var mo = (c as MeshInstance3D).material_override
			if mo is StandardMaterial3D:
				names.append(_gen_name((mo as StandardMaterial3D).albedo_texture))
		elif c is Sprite3D:
			names.append(_gen_name((c as Sprite3D).texture))
		for nm in names:
			if str(nm) != "":
				cnt[nm] = int(cnt.get(nm, 0)) + 1
		_scan(c, cnt)


## ═══════════════ 实拍: 同一步左右并排 ═══════════════
func _shoot(gs, job: Dictionary) -> void:
	var steps: Array = []
	for x in OS.get_environment("SHOT_SHOTS").split(",", false):
		var bits := x.split(":")
		steps.append(int(bits[0]))
		_names[int(bits[0])] = bits[1] if bits.size() > 1 else "shot"
	var want_end := OS.get_environment("SHOT_END") == "1"
	var backup: Dictionary = ReplayRecorder.capture_all()
	## ── 本机直接跑(裁判 + 录流, 每帧 1 步) ──
	var battle: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	var st: Dictionary = RefereeJob.state_for(job, Callable(battle, "_foe_normalize_lane"))
	gs.reset_dual_lane()
	ReplayRecorder.apply_state(st)
	ReplayRecorder.pending_play = {}
	ReplayRecorder.pending_referee = {"seed": RefereeJob.seed_of(job), "id": str(job.get("match_id", "")), "stream": {"keep": true}}
	var budget0 := ReplayRecorder.referee_budget_us
	ReplayRecorder.referee_budget_us = 1
	add_child(battle)
	ReplayRecorder.pending_referee = {}
	var rec: StreamRecorder = battle._replay.stream
	var hit := [-1]
	var real := {}          # 目标步 → 真拍的采样步(第一个 ≥ 目标的采样步)
	var ti := [0]
	rec.on_sampled = func(s: int) -> void:
		if ti[0] < steps.size() and s >= int(steps[ti[0]]):
			real[int(steps[ti[0]])] = s
			ti[0] += 1
			hit[0] = s
			battle.set_process(false)
	var last: int = int(steps.max()) if not steps.is_empty() else 0
	var guard := 0
	while guard < 400000:
		guard += 1
		if ti[0] >= steps.size() and hit[0] < 0 and (not want_end or bool(battle._over)):
			break
		await get_tree().process_frame
		if hit[0] >= 0:
			await get_tree().process_frame
			await get_tree().process_frame
			_native[hit[0]] = get_viewport().get_texture().get_image()
			_dump_texts("本机", hit[0], battle)
			print("[FXSHOT] 本机 第 %d 步" % hit[0])
			hit[0] = -1
			battle.set_process(true)
	var end_step := int(battle._sim_step_n)
	if want_end:
		await get_tree().create_timer(END_WAIT).timeout
		_native[-1] = get_viewport().get_texture().get_image()
		print("[FXSHOT] 本机 收尾 第 %d 步" % end_step)
	battle.set_process(false)
	var meta: Dictionary = rec.finish({})
	var chunks: Array = rec.chunks.duplicate()
	ReplayRecorder.referee_budget_us = budget0
	var seed := int(battle._battle_rng.seed)
	battle.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	for k in backup:
		var v = backup[k]
		gs.set(str(k), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	gs.test_mode = true
	## ── 录流再播放 ──
	gs.reset_dual_lane()
	ReplayRecorder.apply_state(st)
	var pn0: Dictionary = ReplayRecorder.play_names
	ReplayRecorder.play_names = {"l": str((job.get("a", {}) as Dictionary).get("profile", {}).get("name", "")),
		"r": str((job.get("b", {}) as Dictionary).get("profile", {}).get("name", ""))}
	StreamPlayer.pending = {"source": StreamSource.Mem.new(chunks, meta), "seed": seed}
	var b: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(b)
	StreamPlayer.pending = {}
	b.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	p.advance(0.0)
	for s0 in steps:
		var s: int = int(real.get(int(s0), -1))
		if s < 0:
			print("[FXSHOT] 目标 %d 本机没拍到" % int(s0))
			continue
		while int(roundf(p.head)) < int(s) and p.state != "error" and p.state != "ended":
			p.advance(minf(1.0, float(s) - p.head) * SIM_DT)   # 与本机同一节奏(每帧 1 步): 飘字 / 幕布淡入走真实钟 tween, 节奏不同会拍出假差异
			await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		_dump_texts("播放", s, b)
		if OS.get_environment("SHOT_DIAG_PLUS") == "1":
			for k in range(1, 4):
				p.advance(SIM_DT)
				await get_tree().process_frame
				_dump_texts("播放+%d" % k, s, b)
		print("[FXSHOT] 播放 第 %d 步 (播放头 %.1f, 状态 %s)" % [int(s), p.head, p.state])
		_save_pair("%s-step%05d" % [_names[int(s0)], int(s)], _native.get(int(s)), img)
	if want_end:
		while p.state != "ended" and p.state != "error":
			p.advance(SIM_DT)
			await get_tree().process_frame
		await get_tree().create_timer(END_WAIT).timeout
		var img2: Image = get_viewport().get_texture().get_image()
		print("[FXSHOT] 播放 收尾 (播放头 %.1f, 状态 %s)" % [p.head, p.state])
		_save_pair("%s-step%05d" % [OS.get_environment("SHOT_END_NAME") if OS.get_environment("SHOT_END_NAME") != "" else "finish", end_step], _native.get(-1), img2)
	b.queue_free()
	ReplayRecorder.play_names = pn0
	await get_tree().process_frame
	for k in backup:
		var v = backup[k]
		gs.set(str(k), v.duplicate(true) if (v is Array or v is Dictionary) else v)


func _save_pair(stem: String, a: Image, b: Image) -> void:
	if a == null or b == null:
		print("[FXSHOT] %s 缺图" % stem)
		return
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var w := a.get_width()
	var h := a.get_height()
	var gap := 8
	var out := Image.create(w * 2 + gap, h, false, Image.FORMAT_RGB8)
	out.fill(Color(0.1, 0.1, 0.1))
	out.blit_rect(a, Rect2i(0, 0, w, h), Vector2i(0, 0))
	out.blit_rect(b, Rect2i(0, 0, b.get_width(), b.get_height()), Vector2i(w + gap, 0))
	var path := _out.path_join("%s-本机跑_左-播放_右.png" % stem)
	out.save_png(path)
	print("[FXSHOT] 存 ", path)


## 诊断: 拍图那一刻 `_ui_layer` 下全部可见 Label 文本(排序后一行), 左右对账用。SHOT_TEXTS=1 才打。
func _dump_texts(tag: String, s: int, bt: Node) -> void:
	if OS.get_environment("SHOT_TEXTS") != "1" or bt._ui_layer == null:
		return
	var out: Array = []
	var st: Array = [bt._ui_layer]
	while not st.is_empty():
		var n: Node = st.pop_back()
		for c in n.get_children():
			st.append(c)
		if n is Label and (n as Label).is_visible_in_tree() and str((n as Label).text).strip_edges() != "":
			var tx := str((n as Label).text).replace("
", "/")
			if OS.get_environment("SHOT_TEXTS_WHERE") == "1":
				tx += "@%s/%s(%d,%d)" % [str(n.get_parent().name), str(n.name), int((n as Label).global_position.x), int((n as Label).global_position.y)]
			out.append(tx)
	out.sort()
	print("[FXTEXT] %s %d %s" % [tag, s, " | ".join(out)])
