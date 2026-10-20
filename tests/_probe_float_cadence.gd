extends Node
## 探针(下划线开头: 不是门禁): 同一份流, 播放端每次推 K 步(模拟手机低帧率一帧推多步), 飘字序列与原生比。
## 用法: CAD_JOB=m|h godot --headless res://tests/_probe_float_cadence.tscn

const J := preload("res://tests/_stream_jobs.gd")
const P := preload("res://tests/_stream_play.gd")
const SIM_DT := 1.0 / 60.0


func _flat(d: Dictionary) -> Array:
	var ks: Array = d.keys()
	ks.sort()
	var out: Array = []
	for k in ks:
		for t in (d[k] as Array):
			out.append([int(k), str(t)])
	return out


func _ready() -> void:
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var job: Dictionary = J.heavy() if OS.get_environment("CAD_JOB") == "h" else J.mirror(gs)
	var nat: Dictionary = await P.record_referee(self, job, func(_n: int) -> bool: return false)
	var chunks: Array = nat["res"].get("stream_chunks", [])
	var meta: Dictionary = nat["res"].get("stream", {})
	var fa := _flat(nat["floats"])
	print("CAD native floats ", fa.size())
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	for k in [1, 2, 3, 4, 8]:
		var backup: Dictionary = ReplayRecorder.capture_all()
		var b: Node = P.make_player_battle(self, chunks, meta, int(nat["seed"]), nat.get("state", {}))
		b.set_process(false)
		await get_tree().process_frame
		await get_tree().process_frame
		var p: StreamPlayer = b._replay.player
		var cur := [-1]
		var floats := {}
		var fl := P._float_hook(floats, cur)
		get_tree().node_added.connect(fl)
		p.on_applied = func(s: int) -> void: cur[0] = s
		p.advance(0.0)
		var g := 0
		while p.state != "ended" and p.state != "error" and g < 400000:
			g += 1
			p.advance(float(k) * SIM_DT)
			if g % 15 == 0:
				await get_tree().process_frame
		get_tree().node_added.disconnect(fl)
		var fb := _flat(floats)
		var first := -1
		for i in range(mini(fa.size(), fb.size())):
			if str(fa[i][1]) != str(fb[i][1]) or absi(int(fa[i][0]) - int(fb[i][0])) > 2 + k:
				first = i
				break
		print("CAD k=%d playback floats %d (native %d) first_diff #%d %s / %s" % [k, fb.size(), fa.size(), first,
			str(fa[first]) if first >= 0 else "", str(fb[first]) if first >= 0 and first < fb.size() else ""])
		b.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		for kk in backup:
			var v = backup[kk]
			gs.set(str(kk), v.duplicate(true) if (v is Array or v is Dictionary) else v)
		gs.test_mode = true
	print("CAD done")
	get_tree().quit(0)
