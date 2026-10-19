extends Node
## _probe_stream_s2 —— 逐帧直播 S2 体积分层探针(下划线开头, 不进门禁)。录一局(S2_JOB = mirror | heavy), 按操作码打原始字节,
## 再按「单位字段键 / 节点属性名」打出现次数(看哪一层涨了)。输出以 [S2] 开头。

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
	var job: Dictionary = J.heavy() if OS.get_environment("S2_JOB") == "heavy" else J.mirror(gs)
	var res: Dictionary = await RefereeRunner.run(self, job, Callable(), {"keep": true})
	var m: Dictionary = res.get("stream", {})
	var ob := {}
	var ukeys := {}
	var nprops := {}
	var st := {}
	for c in (res.get("stream_chunks", []) as Array):
		var d := F.decode_chunk(c, {})
		for k in (d.get("op_bytes", {}) as Dictionary):
			ob[k] = int(ob.get(k, 0)) + int(d["op_bytes"][k])
		var p := F.parse_chunk(c, st)
		for s in (p.get("list", []) as Array):
			for op in (s[2] as Array):
				if int(op[0]) == F.OP_UNIT_SET:
					for k2 in (op[2] as Dictionary):
						ukeys[k2] = int(ukeys.get(k2, 0)) + 1
				elif int(op[0]) == F.OP_NODE_SET:
					for e in (op[2] as Array):
						nprops[str(e[0])] = int(nprops.get(str(e[0]), 0)) + 1
	print("[S2] z %d raw %d chunks %d" % [int(m.get("z_bytes", 0)), int(m.get("raw_bytes", 0)), int(m.get("chunks", 0))])
	print("[S2] op_bytes ", ob)
	var ul: Array = []
	for k in ukeys:
		ul.append([int(ukeys[k]), k])
	ul.sort()
	ul.reverse()
	print("[S2] unit keys ", ul.slice(0, 25))
	var nl: Array = []
	for k in nprops:
		nl.append([int(nprops[k]), k])
	nl.sort()
	nl.reverse()
	print("[S2] node props ", nl.slice(0, 20))
	get_tree().quit(0)
