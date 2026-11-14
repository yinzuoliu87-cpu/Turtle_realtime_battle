extends Node
## 卡顿排查探针(2026-11-14, 不是门禁): 用户「我朋友…单杀王那个账号…打我…路易斯零一的那个账号那场对局，他手机上看，然后发现卡卡的」。
## 按**手机的播放路径**(状态流, 一步 sim 都不跑; tests/_stream_play.gd make_player_battle 同形)把正式服那一局完整放一遍, 逐帧记耗时。
##   PERF_DIR=<数据块目录: 000000.bin… + end.json>  PERF_SEED=<referee_jobs.seed>  [PERF_OUT=<csv 路径>]
##   跑法: <godot> --headless --audio-driver Dummy --path . --fixed-fps 60 res://tests/probes/_probe_stream_perf.tscn
##   ★--fixed-fps 60: 每帧正好推进 1/60 秒的播放量, 墙钟耗时 = 这一帧的处理成本(与机器快慢成比例, 看相对尖峰)。
##   ★无头只量 CPU 侧(解码 / 应用节点 / 建网格 / 脚本); GPU 侧(着色器首次编译、填充率)要开窗口另量。
## 数据块怎么下: memory ref-stream-chunk-download(要带 X-Client-Version 头)。

const BATTLE := "res://scenes/RealtimeBattle3D.tscn"
const MAX_FRAMES := 12000

var _b = null
var _rows: Array = []
var _last_us := 0
var _prev_applied := -1
var _prev_nodes := 0
var _frames := 0
var _done := false


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var d := OS.get_environment("PERF_DIR")
	if d == "" or not DirAccess.dir_exists_absolute(d):
		print("PERF FAIL: PERF_DIR 不存在: ", d)
		get_tree().quit(1)
		return
	var src := StreamSource.Dir.new(d)
	## PERF_DECODE_ONLY=1: 只把每一块解码一遍(与播放器 `_decode` 同一个 parse_chunk、同样接力字符串表), 记每块耗时 —— 分清「慢在解码」还是「慢在应用」
	if OS.get_environment("PERF_DECODE_ONLY") == "1":
		var F := preload("res://scripts/systems/stream/stream_format.gd")
		var st := {}
		var times: Array = []
		for seq in range(src.available()):
			var data: PackedByteArray = src.chunk(seq)
			var t0 := Time.get_ticks_usec()
			var res: Dictionary = F.parse_chunk(data, st.duplicate())
			var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
			if not bool(res.get("ok", false)):
				print("PERF FAIL: chunk %d: %s" % [seq, str(res.get("err", ""))])
				break
			st = res["st"]
			times.append([seq, ms, data.size(), (res["list"] as Array).size()])
		var v: Array = times.map(func(x): return float(x[1]))
		v.sort()
		print("[DECODE] %d 块 · 每块解码: 中位 %.2f ms · p90 %.2f · 最慢 %.2f · 合计 %.0f ms" % [v.size(), v[v.size() / 2], v[int(v.size() * 0.9)], v[v.size() - 1], v.reduce(func(a, b): return a + b, 0.0)])
		times.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
		for x in times.slice(0, 8):
			print("   块 %d: %.1f ms · %d 字节 · %d 步" % x)
		print("PERF DONE")
		get_tree().quit(0)
		return
	StreamPlayer.pending = {"source": src, "seed": int(OS.get_environment("PERF_SEED"))}
	_b = (load(BATTLE) as PackedScene).instantiate()
	add_child(_b)
	StreamPlayer.pending = {}
	_last_us = Time.get_ticks_usec()
	_prev_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func _process(_d: float) -> void:
	if _done:
		return
	var now := Time.get_ticks_usec()
	var dt_ms: float = float(now - _last_us) / 1000.0
	_last_us = now
	_frames += 1
	var p = _b._replay.player if _b != null and _b.get("_replay") != null else null
	var applied: int = int(p.applied) if p != null else -1
	var st: String = str(p.state) if p != null else "?"
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_rows.append([_frames, dt_ms, applied, applied - _prev_applied if _prev_applied >= 0 else 0, nodes, nodes - _prev_nodes, st,
		float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0])
	_prev_applied = applied
	_prev_nodes = nodes
	if (p != null and st == "ended") or _frames >= MAX_FRAMES:
		_finish(p)


func _finish(p) -> void:
	_done = true
	var out := OS.get_environment("PERF_OUT")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_line("frame,ms,step,steps_this_frame,nodes,new_nodes,state,process_ms")
		for r in _rows:
			f.store_line("%d,%.3f,%d,%d,%d,%d,%s,%.3f" % r)
		f.close()
	## 跳过开头 30 帧(场景加载 / 第一次建场)单独报
	var ms: Array = []
	for r in _rows.slice(30):
		ms.append(float(r[1]))
	ms.sort()
	var n := ms.size()
	if n == 0:
		print("PERF FAIL: 没有帧")
		get_tree().quit(1)
		return
	print("[PERF] 帧数 %d · 播到第 %d 步 · 状态 %s" % [_frames, int(p.applied) if p != null else -1, str(p.state) if p != null else "?"])
	print("[PERF] 开头 30 帧(加载): 最慢 %.1f ms" % _rows.slice(0, 30).map(func(r): return float(r[1])).max())
	print("[PERF] 之后每帧耗时: 中位 %.2f ms · p95 %.2f · p99 %.2f · 最慢 %.2f · 超过 16.7ms 的帧 %d · 超过 33ms 的帧 %d" % [
		ms[n / 2], ms[int(n * 0.95)], ms[int(n * 0.99)], ms[n - 1],
		ms.filter(func(v): return v > 16.7).size(), ms.filter(func(v): return v > 33.0).size()])
	var top: Array = _rows.slice(30)
	top.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	print("[PERF] 最重的 20 帧(帧号 / 毫秒 / 播到步 / 本帧推进步数 / 节点总数 / 本帧新增节点):")
	for r in top.slice(0, 20):
		print("   #%d  %.1f ms  第 %d 步(%.1f 秒)  +%d 步  节点 %d  新增 %d" % [r[0], r[1], r[2], float(r[2]) / 60.0, r[3], r[4], r[5]])
	print("PERF DONE")
	get_tree().quit(0)
