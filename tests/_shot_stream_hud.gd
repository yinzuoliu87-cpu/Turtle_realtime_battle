extends Node
## _shot_stream_hud.gd — 逐帧直播播放端 HUD 实拍(探针, 不进门禁; 由 _shot_stream_s2.gd 改): 同一局「本机直接跑」与「录流再播放」在同一步各拍一张, 左右拼成一张。
## 看的是 HUD: 左右头像框栏(立绘 / 血条 / 装备格)、法术圆盘、顶栏(名字 / PK 条 / 路名计时牌 / 路点)、头顶血条。
## ★顶栏名字: 播放端按入口给的名字(这里给任务单里两份快照的名字); 本机那边是这台机器自己的账号名(服务器上没有意义)。
## 跑法(离屏窗口、静音; 无头没有画面可拍):
##   SHOT_OUT=<目录> QUIET=1 <godot> --position 5000,5000 --resolution 1280x720 --audio-driver Dummy --path . res://tests/_shot_stream_hud.tscn
## 环境 SHOT_JOB = heavy(默认, 最重那局) | mirror; SHOT_STEPS = 逗号分隔的步号(要是渲染采样步: first + 奇数)。
## 本机那一遍: 裁判模式 + 录流(与服务器同一条路), 预算压到每帧 1 步, 到目标步那一帧停住、等两帧画出来再拍;
## 播放那一遍: 用刚录的块建播放模式战斗场, 手动推到同一步再拍。

const J := preload("res://tests/_stream_jobs.gd")
const SIM_DT := 1.0 / 60.0

var _out := ""
var _native := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	_out = OS.get_environment("SHOT_OUT")
	if _out == "":
		_out = ProjectSettings.globalize_path("user://s2_shots")
	DirAccess.make_dir_recursive_absolute(_out)
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	var job: Dictionary = J.mirror(gs) if OS.get_environment("SHOT_JOB") == "mirror" else J.heavy()
	var steps: Array = []
	for x in (OS.get_environment("SHOT_STEPS") if OS.get_environment("SHOT_STEPS") != "" else "1501,2701,7801").split(","):
		steps.append(int(x))
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
	rec.on_sampled = func(s: int) -> void:
		if s in steps:
			hit[0] = s
			battle.set_process(false)
	var last: int = int(steps.max())
	while int(battle._sim_step_n) < last:
		await get_tree().process_frame
		if hit[0] >= 0:
			await get_tree().process_frame
			await get_tree().process_frame
			_native[hit[0]] = get_viewport().get_texture().get_image()
			print("[S2SHOT] 本机 第 %d 步" % hit[0])
			hit[0] = -1
			battle.set_process(true)
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
	for s in steps:
		while int(roundf(p.head)) < int(s) and p.state != "error" and p.state != "ended":
			p.advance(minf(2.0, float(s) - p.head) * SIM_DT)
			await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		print("[S2SHOT] 播放 第 %d 步 (播放头 %.1f, 状态 %s)" % [int(s), p.head, p.state])
		_save_pair(int(s), _native.get(int(s)), img)
	b.queue_free()
	ReplayRecorder.play_names = pn0
	await get_tree().process_frame
	for k in backup:
		var v = backup[k]
		gs.set(str(k), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	get_tree().quit(0)


func _save_pair(s: int, a: Image, b: Image) -> void:
	if a == null or b == null:
		print("[S2SHOT] 第 %d 步缺图" % s)
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
	var path := _out.path_join("hud-step%05d-本机跑_左-播放_右.png" % s)
	out.save_png(path)
	print("[S2SHOT] 存 ", path)
