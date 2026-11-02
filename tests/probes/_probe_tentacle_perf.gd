extends Node
## _probe_tentacle_perf.gd — 触手每帧花多少时间(探针, 不进门禁: 文件名不是 verify_*)。
##
## 量两件事(方案书 20261031d §2.3「回放掉帧」):
##   ① 服务器 / 本机: `TentacleVfx.tick(1/60)` 每帧的 CPU 微秒(两方各 2 根 = 实战上限 4 根, 一直循环拍击)
##   ② 手机播放端: 录流里触手每发一代网格, 手机就要按出处键重算一次(`StreamMirror.gen_call`)。
##      这里逐帧看触手节点的网格换没换代, 换了就照手机那样重算一遍并计时。
## 跑法: bash godot-quiet.sh res://tests/probes/_probe_tentacle_perf.tscn --quit-after 4000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SM := preload("res://scripts/systems/stream/stream_mirror.gd")

var _s


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	var tv = _s._tentacle_vfx
	tv.clear()
	tv.preview_lock = true
	tv.ensure_forced("left", 2)
	tv.ensure_forced("right", 2)
	var dt := 1.0 / 60.0
	## 先出土站稳(不计时)
	for _i in range(150):
		tv.tick(dt)
	var foe_l := Vector2(_s.ARENA.position.x + _s.ARENA.size.x * 0.40, _s.ARENA.position.y + _s.ARENA.size.y * 0.5)
	var foe_r := Vector2(_s.ARENA.position.x + _s.ARENA.size.x * 0.60, _s.ARENA.position.y + _s.ARENA.size.y * 0.5)
	var us: Array = []
	var last_mesh := {}
	var regen := 0
	var regen_us := 0
	var par_set := 0
	var par_us := 0
	var N := 1200
	for f in range(N):
		for sd in ["left", "right"]:
			for i in range(2):
				if int(tv.state_of(sd, i)) == 1 and (f + i * 37) % 170 == 0:
					tv.strike(sd, i, foe_l if sd == "left" else foe_r, 1.0)
		var t0 := Time.get_ticks_usec()
		tv.tick(dt)
		us.append(Time.get_ticks_usec() - t0)
		## ② 手机端: 网格换代 ⇒ 按出处键重算(与 StreamMirror._gen_def 同一个入口)
		for c in _s._world.get_children():
			if not (c is MeshInstance3D) or not str(c.name).begins_with("Tentacle"):
				continue
			if str(c.name).begins_with("TentacleWarn"):
				continue
			var m = (c as MeshInstance3D).mesh
			var key := str(c.name)
			if m != null and last_mesh.get(key, null) != m:
				last_mesh[key] = m
				if (m as Resource).has_meta(&"stream_gen"):
					var gm: Array = (m as Resource).get_meta(&"stream_gen")
					var t1 := Time.get_ticks_usec()
					SM.gen_call("%s:%s" % [str(gm[0]), str(gm[1])], gm[2] as Array)
					regen_us += Time.get_ticks_usec() - t1
					regen += 1
			var mo = (c as MeshInstance3D).material_override
			if mo is ShaderMaterial and c.has_meta(&"stream_shader_params"):
				## 新做法: 手机端每步只是把会变的那几个着色器参数照抄过去(StreamMirror._apply_props 同样是按名字 set)
				var names: PackedStringArray = c.get_meta(&"stream_shader_params")
				var vals: Array = []
				for nm in names:
					vals.append((mo as ShaderMaterial).get_shader_parameter(nm))
				var t2 := Time.get_ticks_usec()
				for q in range(names.size()):
					(mo as ShaderMaterial).set("shader_parameter/" + names[q], vals[q])
					par_set += 1
				par_us += Time.get_ticks_usec() - t2
	us.sort()
	var tot := 0
	for v in us:
		tot += int(v)
	print("[perf] 触手 %d 根 · %d 帧" % [tv.count(), N])
	print("[perf] ① tick 每帧 μs: 均值 %.1f  p50 %d  p95 %d  max %d" % [float(tot) / N, us[N / 2], us[int(N * 0.95)], us[N - 1]])
	print("[perf] ② 手机端重算网格: %d 次 / %d 帧 = 每秒 %.1f 次, 每次 %.1f μs, 折合每帧 %.1f μs" % [regen, N,
		float(regen) / (float(N) / 60.0), float(regen_us) / maxf(1.0, float(regen)), float(regen_us) / float(N)])
	print("[perf] ② 手机端着色器参数照抄: %d 项 / %d 帧, 折合每帧 %.1f μs" % [par_set, N, float(par_us) / float(N)])
	## ③ 分项(各 2000 次取均值): 本体一次几何(姿态 + 链式模拟 + 半径) / 写 uniform / 预警带一次重建
	var tt: Dictionary = tv._tents["left|0"]
	var t3 := Time.get_ticks_usec()
	for _k in range(2000):
		tt["dt"] = dt
		tv._geom(tt)
	var u_geo: float = float(Time.get_ticks_usec() - t3) / 2000.0
	var g: Array = tv._geom(tt)
	t3 = Time.get_ticks_usec()
	for _k in range(2000):
		TentacleMeshVfx.apply(tt, g[0], g[1], g[2], g[3], g[4], float(_s._t))
	var u_ap: float = float(Time.get_ticks_usec() - t3) / 2000.0
	tt["aim"] = foe_l
	t3 = Time.get_ticks_usec()
	for _k in range(2000):
		tv._telegraph_tick(tt, 0.5)
	var u_wb: float = float(Time.get_ticks_usec() - t3) / 2000.0
	tv._telegraph_hide(tt)
	print("[perf] ③ 分项 μs/次: 本体几何(姿态 + 链式模拟 + 半径) %.1f · 写 uniform %.1f · 预警带重建 %.1f" % [u_geo, u_ap, u_wb])
	get_tree().quit(0)
