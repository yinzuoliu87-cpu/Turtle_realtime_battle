extends Node
## _probe_native_frametime.gd —— 原生(Windows / 手机同一套渲染)看直播时逐帧耗时, 找「卡卡的」(探针, 2026-11-20)。
## 用户 11-20「我 Windows 玩这个包的时候都感觉卡卡的，这确实是什么情况呢？」
## 做法: 裁判入口跑一局 heavy(真实快照对局)并录流 → 像玩家那样按真实时间播(主循环照常 _process, 不手推)。
##   每帧记 delta; 超过 33ms 的帧记下: 播到第几步、这一帧新建了几个节点 / 几个粒子节点(播放端计数器)、累计时间。
## 必须开窗口(无头不渲染): --position 5000,5000 --resolution 1560x720 --audio-driver Dummy。
## 冷 / 热对比: 拷一份 godot.exe 到新路径跑 = 驱动着色器缓存是空的(相当于玩家第一次打开新包); 再跑一次 = 热。
## 输出: .out/frametime_<FT_TAG>.txt

const J := preload("res://tests/_stream_jobs.gd")

var _deltas: PackedFloat32Array = PackedFloat32Array()
var _spikes: Array = []
var _p: StreamPlayer = null
var _b: Node = null
var _last_us := 0
var _t0_us := 0
var _nodes_prev := 0
var _parts_prev := 0
var _playing := false
var _parts := 0


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	var job: Dictionary = J.heavy()
	print("录流中…")
	var res: Dictionary = await RefereeRunner.run(self, job, Callable(), {"keep": true})
	var chunks: Array = res.get("stream_chunks", [])
	print("录到 %d 块" % chunks.size())
	ReplayRecorder.begin_play({"state": {"dual_active": true}})
	ReplayRecorder.pending_play = {}
	ReplayRecorder.play_names = {}
	gs.dual_lineup = {}
	gs.dual_ghost = {}
	StreamPlayer.pending = {"source": StreamSource.Mem.new(chunks, res.get("stream", {})), "seed": RefereeJob.seed_of(job), "no_curtain": false}
	_b = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(_b)
	StreamPlayer.pending = {}
	await get_tree().process_frame
	_p = _b._replay.player
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is GPUParticles3D or n is CPUParticles3D:
			_parts += 1)
	_t0_us = Time.get_ticks_usec()
	_last_us = _t0_us
	_playing = true


func _process(_d: float) -> void:
	if not _playing or _p == null:
		return
	var now := Time.get_ticks_usec()
	var dt := float(now - _last_us) / 1000.0
	_last_us = now
	_deltas.append(dt)
	var mir = _p.mirror
	var nn: int = int(mir.built) if mir != null else 0
	var np: int = _parts
	if dt > 33.0:
		_spikes.append([float(now - _t0_us) / 1e6, dt, int(_p.cur_step), str(_b.get("_dl_state")), nn - _nodes_prev, np - _parts_prev])
	_nodes_prev = nn
	_parts_prev = np
	if _p.state == "ended" or _p.state == "error" or float(now - _t0_us) / 1e6 > 400.0:
		_playing = false
		_report()


func _report() -> void:
	var arr: Array = Array(_deltas)
	arr.sort()
	var n := arr.size()
	var tag := OS.get_environment("FT_TAG") if OS.has_environment("FT_TAG") else "x"
	var lines: Array = []
	lines.append("帧数 %d · 总时长 %.1f 秒 · 播放状态 %s" % [n, float(_last_us - _t0_us) / 1e6, str(_p.state)])
	if n > 0:
		lines.append("中位 %.1f ms · p95 %.1f · p99 %.1f · 最长 %.1f" % [arr[n / 2], arr[int(n * 0.95)], arr[int(n * 0.99)], arr[n - 1]])
	var c33 := 0
	var c50 := 0
	var c100 := 0
	var c250 := 0
	var tot_over := 0.0
	for d in arr:
		if d > 33.0: c33 += 1
		if d > 50.0: c50 += 1
		if d > 100.0: c100 += 1
		if d > 250.0: c250 += 1
		if d > 33.0: tot_over += d - 16.7
	lines.append(">33ms %d 帧 · >50ms %d · >100ms %d · >250ms %d · 卡顿合计多出 %.1f 秒" % [c33, c50, c100, c250, tot_over / 1000.0])
	lines.append("卡顿帧(时刻秒, 耗时ms, 步, 状态, 这一帧新建节点, 新建粒子):")
	for s in _spikes:
		lines.append("  %.2f  %.0f  步%d  %s  节点+%d  粒子+%d" % s)
	var txt := "\n".join(lines)
	print(txt)
	var f := FileAccess.open("res://.out/frametime_%s.txt" % tag, FileAccess.WRITE)
	if f != null:
		f.store_string(txt)
		f.close()
	get_tree().quit(0)
