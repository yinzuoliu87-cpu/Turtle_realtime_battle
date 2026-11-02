extends Node
## _probe_stream_s1 —— 逐帧直播 S1 录流性能探针(下划线开头, 不进门禁)。
## 同一进程里轮流跑「不录」与「录流」, 每种取最快一遍; 比的是同进程比值(不看绝对值)。
##   S1_JOB = heavy(默认, 真实快照那局) | mirror
##   S1_REPS = 每种跑几遍(默认 2)
##   S1_DIR = 非空 ⇒ 录流那一遍把块文件写进这个目录(看文件形态)
## 输出: 以 [S1] 开头的行。

const J := preload("res://tests/_stream_jobs.gd")
const F := preload("res://scripts/systems/stream/stream_format.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var which := OS.get_environment("S1_JOB")
	var job: Dictionary = J.mirror(gs) if which == "mirror" else J.heavy()
	var reps: int = int(OS.get_environment("S1_REPS")) if OS.get_environment("S1_REPS") != "" else 2
	var best := {}
	for rep in range(reps):
		for cfg in (["rec"] if OS.get_environment("S1_REC_ONLY") != "" else ["plain", "rec"]):
			var tm := {"t0": 0, "t1": 0, "n": 0}
			var opts := {}
			if cfg == "rec":
				opts = {"keep": true, "dir": OS.get_environment("S1_DIR")}
			var res: Dictionary = await RefereeRunner.run(self, job, func(bt) -> void:
				bt.sim_stepped.connect(func() -> void:
					var now := Time.get_ticks_usec()
					if int(tm["n"]) == 0:
						tm["t0"] = now
					tm["t1"] = now
					tm["n"] = int(tm["n"]) + 1), opts)
			var us := int(tm["t1"]) - int(tm["t0"])
			var sps := float(int(tm["n"]) - 1) / maxf(1.0e-6, us / 1.0e6)
			print("[S1] rep %d %s: ok=%s 开打 %d 步 %d %.2f 秒 = %.0f 步/秒 = %.1f 倍实时 · digest %s" % [rep, cfg,
				str(res.get("ok")), int(res.get("fights", 0)), int(tm["n"]), us / 1.0e6, sps, sps / 60.0, str(res.get("digest", ""))])
			if not best.has(cfg) or sps > float(best[cfg]):
				best[cfg] = sps
			if cfg == "rec" and rep == 0:
				var m: Dictionary = res.get("stream", {})
				print("[S1] 元数据 %s" % JSON.stringify(m))
				var ok := 0
				var bad: Array = []
				var evs := {}
				var ops := {}
				var obs := {}
				var st := {}
				for c in (res.get("stream_chunks", []) as Array):
					var d := F.decode_chunk(c, st)
					if bool(d["ok"]):
						ok += 1
						for k in (d["events"] as Dictionary):
							evs[k] = int(evs.get(k, 0)) + int(d["events"][k])
						for k in (d["ops"] as Dictionary):
							ops[k] = int(ops.get(k, 0)) + int(d["ops"][k])
						for k in (d["op_bytes"] as Dictionary):
							obs[k] = int(obs.get(k, 0)) + int(d["op_bytes"][k])
					else:
						bad.append("%d:%s" % [int(d.get("seq", -1)), str(d["err"])])
				print("[S1] 解码 %d 块 OK, 坏 %d %s · ops %s · 原始字节按操作 %s · 事件 %s" % [ok, bad.size(), str(bad.slice(0, 5)), str(ops), str(obs), str(evs)])
	var p: float = float(best.get("plain", 0.0))
	var r: float = float(best.get("rec", 0.0))
	print("[S1] 最快: 不录 %.0f 步/秒(%.1f 倍实时) · 录流 %.0f 步/秒(%.1f 倍实时) · 比值 %.2f" % [p, p / 60.0, r, r / 60.0, r / maxf(1.0, p)])
	print("[S1] DONE")
	get_tree().quit(0)
