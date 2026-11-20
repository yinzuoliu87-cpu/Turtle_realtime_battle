extends Node
## _probe_motion_jitter.gd —— 看直播时人物「一抽一抽」量化(探针, 2026-11-20)。
## 用户 11-20「我肯定是在笔记本上玩…对局之后，游戏内有点卡卡的，然后…人物角色的那个动画…感觉有时候一抽一抽的」。
## _probe_native_frametime 只量了每帧耗时(239Hz 屏上很平稳), 量不到「画面里的东西动得匀不匀」。这里:
##   按真实时间播一局 heavy 直播(主循环照常 _process), 每帧记每只活着的单位: 立绘节点的世界坐标 + 立绘帧号。
##   ① 位移: 移动中的单位逐帧位移 d; 「停一下再跳」= 连续 ≥2 帧 d≈0 后紧跟一帧 d > 2.5×中位; 「往回退」= 与前一帧方向反向
##   ② 立绘帧: 每一帧号停留了多久(毫秒); 停留 ≤ 1 个渲染帧的 = 一闪而过
##   ③ 同一帧里推了几个 sim 步(0 / 1 / 2…)的分布: 239Hz 下理想是 0,0,0,1 均匀
## 必须开窗口: --position 5000,5000 --resolution 1560x720 --audio-driver Dummy。环境 MJ_MODE=local ⇒ 改成本机直接跑同一局(切磋那条路)。
## 输出 .out/motion_jitter_<MJ_TAG>.txt

const J := preload("res://tests/_stream_jobs.gd")

var _p: StreamPlayer = null
var _b: Node = null
var _playing := false
var _t0 := 0
var _last := 0
var _prev := {}            # 单位 id(实例) → [Vector3 位置, Vector3 上一帧位移, 帧号, 帧号起始 us]
var _d_all: Array = []     # 移动中单位逐帧位移
var _freeze_jump := 0
var _backstep := 0
var _moving_frames := 0
var _holds: Array = []     # 立绘帧号停留毫秒
var _flash := 0
var _steps_hist := {}
var _last_step := -1
var _events: Array = []
var _mode := "stream"
var _flashes: Array = []
var _holds_t: Array = []


func _ready() -> void:
	_mode = OS.get_environment("MJ_MODE") if OS.has_environment("MJ_MODE") else "stream"
	var gs = get_node_or_null("/root/GameState")
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	if _mode == "local":
		load("res://tests/_setup_appstore.gd").run()
		gs.tutorial_active = false
		var rng := RandomNumberGenerator.new()
		rng.seed = 20261120
		var g: Dictionary = load("res://scripts/net/backend.gd").make_bot(6, rng)
		g["profile"] = {"name": "对照", "avatar": "stone", "id": "MJLOC1"}
		Spar.begin(g, {"name": "对照", "tag": "MJLOC1"})
		_b = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
		add_child(_b)
		await get_tree().process_frame
		_t0 = Time.get_ticks_usec()
		_last = _t0
		_playing = true
		return
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
	_t0 = Time.get_ticks_usec()
	_last = _t0
	_playing = true


func _units() -> Array:
	var out: Array = []
	if _mode == "local" and _b != null:
		var arr: Array = _b._units
		for i in range(arr.size()):
			var u: Dictionary = arr[i]
			out.append(["%s|%s|%s" % [str(u.get("id", "")), str(u.get("side", "")), str(u.get("_spec_uid", i))], u])
		return out
	if _p != null:
		for i in _p.units:
			out.append([i, _p.units[i]])
	return out


func _process(_d: float) -> void:
	if not _playing or (_p == null and _mode != "local"):
		return
	var now := Time.get_ticks_usec()
	_last = now
	var st := int(_p.cur_step) if _p != null else int(_b._sim_step_n)
	var ds := st - _last_step if _last_step >= 0 else 0
	_last_step = st
	_steps_hist[ds] = int(_steps_hist.get(ds, 0)) + 1
	var fighting := str(_b.get("_dl_state")) == "fight"
	for pair in _units():
		var key = pair[0]
		var u: Dictionary = pair[1]
		if not bool(u.get("alive", false)):
			_prev.erase(key)
			continue
		var spr = u.get("sprite")
		if not (spr is Node3D) or not is_instance_valid(spr):
			continue
		var pos: Vector3 = (spr as Node3D).global_position
		var fr := int((spr as Sprite3D).frame) if spr is Sprite3D else -1
		if _prev.has(key) and fighting:
			var pv: Array = _prev[key]
			var dv: Vector3 = pos - (pv[0] as Vector3)
			var d := Vector2(dv.x, dv.z).length()
			var lastdv: Vector3 = pv[1]
			if d > 0.001 or Vector2(lastdv.x, lastdv.z).length() > 0.001:
				_moving_frames += 1
				_d_all.append(d)
				if d > 0.001 and Vector2(lastdv.x, lastdv.z).length() > 0.001 and Vector2(dv.x, dv.z).dot(Vector2(lastdv.x, lastdv.z)) < 0.0:
					_backstep += 1
			## 停一下再跳: 前面至少 2 帧没动(记在 pv[4]), 这一帧位移很大
			var still: int = int(pv[4]) if pv.size() > 4 else 0
			if d <= 0.001:
				still += 1
			else:
				if still >= 2 and still <= 12:
					_freeze_jump += 1
					if _events.size() < 40:
						_events.append("%.2fs 步%d %s 停 %d 帧后跳 %.3f" % [float(now - _t0) / 1e6, st, str(u.get("id", "?")), still, d])
				still = 0
			if fr != int(pv[2]):
				var held := float(now - int(pv[3])) / 1000.0
				_holds.append(held)
				if not str(u.get("id", "")).begins_with("_"):
					_holds_t.append(held)
				if held < 8.0 and _flashes.size() < 60:
					var tex = (spr as Sprite3D).texture if spr is Sprite3D else null
					_flashes.append("%.2fs 步%d(本帧推%d步) %s 帧 %s→%s 停%.1fms 动作=%s anim=%s" % [float(now - _t0) / 1e6, st, ds, str(u.get("id", "?")),
						str(pv[5]) if pv.size() > 5 else "?", str(fr), held, str(u.get("anim_action", "")),
						(tex as Texture2D).resource_path.get_file() if tex is Texture2D else "?"])
				_prev[key] = [pos, dv, fr, now, still, pv[2]]
			else:
				_prev[key] = [pos, dv, fr, pv[3], still, pv[5] if pv.size() > 5 else -1]
		else:
			_prev[key] = [pos, Vector3.ZERO, fr, now, 0, -1]
	var over: bool = (_p != null and (_p.state == "ended" or _p.state == "error")) or (_mode == "local" and str(_b.get("_dl_state")) == "done")
	if over or float(now - _t0) / 1e6 > (150.0 if _mode == "local" else 400.0):
		_playing = false
		_report()


func _report() -> void:
	var tag := OS.get_environment("MJ_TAG") if OS.has_environment("MJ_TAG") else "x"
	var L: Array = []
	var dd: Array = _d_all.duplicate()
	dd.sort()
	var med: float = float(dd[dd.size() / 2]) if not dd.is_empty() else 0.0
	var big := 0
	for d in _d_all:
		if med > 0.0 and float(d) > med * 2.5:
			big += 1
	L.append("总时长 %.1f 秒 · 移动中单位逐帧样本 %d · 位移中位 %.4f" % [float(_last - _t0) / 1e6, _moving_frames, med])
	L.append("位移 > 2.5×中位 的帧 %d (%.2f%%) · 停一下再跳 %d 次 · 往回退 %d 次" % [big, 100.0 * big / maxf(1.0, float(_moving_frames)), _freeze_jump, _backstep])
	var hh: Array = _holds.duplicate()
	hh.sort()
	var short := 0
	for h in hh:
		if float(h) < 8.0:
			short += 1
	if not hh.is_empty():
		L.append("立绘帧停留: 样本 %d · 中位 %.1f ms · p10 %.1f · 最短 %.1f · <8ms(一闪而过) %d 次" % [hh.size(), hh[hh.size() / 2], hh[int(hh.size() * 0.1)], hh[0], short])
	var ks: Array = _steps_hist.keys()
	ks.sort()
	var parts: Array = []
	for k in ks:
		parts.append("%d步:%d帧" % [k, _steps_hist[k]])
	L.append("每帧推进的 sim 步数分布: " + " · ".join(parts))
	var hist := {}
	for h in _holds_t:
		var b := int(float(h) / 10.0) * 10
		hist[b] = int(hist.get(b, 0)) + 1
	var hk: Array = hist.keys()
	hk.sort()
	var hs: Array = []
	for b in hk:
		if int(hist[b]) * 100 >= _holds_t.size():
			hs.append("%d-%dms:%d" % [b, b + 9, hist[b]])
	L.append("龟的立绘帧停留分布(10ms 一档, 只列 ≥1%%; 共 %d): %s" % [_holds_t.size(), " · ".join(hs)])
	L.append("一闪而过的立绘帧(前 60 次; 帧 上上个→这个):")
	for e in _flashes:
		L.append("  " + str(e))
	L.append("停一下再跳(前 40 次):")
	for e in _events:
		L.append("  " + str(e))
	var txt := "\n".join(L)
	print(txt)
	var f := FileAccess.open("res://.out/motion_jitter_%s.txt" % tag, FileAccess.WRITE)
	if f != null:
		f.store_string(txt)
		f.close()
	get_tree().quit(0)
