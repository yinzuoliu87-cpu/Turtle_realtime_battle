extends Node
## 探针(不进门禁): 读一个流目录(环境变量 SP_DIR), 找最大的几块, 看着色器热参数(带 v4 点数组的材质)在里面占多少。

const F := preload("res://scripts/systems/stream/stream_format.gd")

const J := preload("res://tests/_stream_jobs.gd")

func _ready() -> void:
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var res: Dictionary = await RefereeRunner.run(self, J.heavy(), Callable(), {"keep": true})
	var chunks: Array = res.get("stream_chunks", [])
	print("[mix] 开打 %d · 块 %d" % [int(res.get("fights", 0)), chunks.size()])
	var files: Array = []
	for i in range(chunks.size()):
		files.append(i)
	var st := {}
	var hot := {}
	var rows: Array = []
	var tot_hot := 0
	for fn in files:
		var data: PackedByteArray = chunks[int(fn)]
		var d := F.parse_chunk(data, st)
		var e := F.Enc.new()
		var npts := 0
		for stp in (d.get("list", []) as Array):
			for op in (stp[2] as Array):
				var pl = null
				if int(op[0]) == F.OP_RES_DEF and int(op[2]) == F.RES_PARAM:
					pl = op[4]
					for x in (pl as Array):
						if (x as Array).size() > 3:
							hot[int(op[1])] = true
				elif int(op[0]) == F.OP_RES_SET and hot.has(int(op[1])):
					pl = op[2]
				else:
					continue
				if not hot.has(int(op[1])):
					continue
				e.u8(int(op[0]))
				e.vu(int(op[1]))
				e.vu((pl as Array).size())
				for x in (pl as Array):
					e.s(str(x[0]))
					if (x as Array).size() > 3:
						npts += 1
						e.pts(F.T_V3QD if int(x[3][0]) == 1 else F.T_V3Q, x[3][1])
					elif bool(x[2]):
						e.res(int(x[1]))
					else:
						e.val(x[1])
		var raw := e.take()
		var z := raw.compress(FileAccess.COMPRESSION_ZSTD).size() if raw.size() > 0 else 0
		tot_hot += z
		rows.append([data.size(), fn, z, npts])
	rows.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	print("[mix] 块 %d 个 · 热参数单独压缩合计 %d B · 点数组条数合计见下" % [files.size(), tot_hot])
	for i in range(mini(6, rows.size())):
		print("[mix] 块%s %d B · 其中热参数(单独压缩) %d B · 点数组 %d 条" % [str(rows[i][1]), rows[i][0], rows[i][2], rows[i][3]])
	get_tree().quit(0)
