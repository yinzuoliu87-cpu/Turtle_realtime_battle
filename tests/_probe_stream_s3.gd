extends Node
## _probe_stream_s3.gd — 逐帧直播 S3 探针(下划线开头, 不进门禁): 最重那局录流, 把出处键定义按生成函数拆开量。
##   · 每个生成函数: 定义次数 / 三种写法(全量 / 别名 / 差分)各几次 / 差分里每个参数是「同参照 / 异或 / 相减 / 原样」的次数
##   · T_IDIFF 的差值分布(0 占多少、|差| ≤ 1 / ≤ 3 / 更大)
##   · 估压缩后的账: 每块把某个生成函数的定义「拿掉」(同一块里其余操作原样再编一遍)前后各压一次, 差 = 它在压缩后占多少
## 跑法: <godot> --headless --path . res://tests/_probe_stream_s3.tscn   (环境 S3P_JOB = heavy(默认) | mirror)

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
	var job: Dictionary = J.mirror(gs) if OS.get_environment("S3P_JOB") == "mirror" else J.heavy()
	var res: Dictionary = await RefereeRunner.run(self, job, Callable(), {"keep": true})
	var chunks: Array = res.get("stream_chunks", [])
	print("[S3P] 块 %d" % chunks.size())
	var st := {}
	var per := {}          # gid → {n, mode{}, ops{}}
	var dist := {"0": 0, "1": 0, "3": 0, "big": 0}
	var z_all := 0
	var z_wo := {}         # gid → 拿掉它之后的压缩字节
	var keys_seen := {}
	for c in chunks:
		var data: PackedByteArray = c
		z_all += data.size()
		var d := F.parse_chunk(data, st)
		if not bool(d.get("ok", false)):
			print("[S3P] 解不开: ", d.get("err"))
			continue
		for stp in (d["list"] as Array):
			for op in (stp[2] as Array):
				if int(op[0]) != F.OP_RES_DEF or int(op[2]) != F.RES_GEN:
					continue
				var gid := str(op[4]).get_slice(":", 2)
				keys_seen[gid] = true
				var pr: Dictionary = per.get(gid, {"n": 0, "mode": {}, "ops": {}})
				pr["n"] = int(pr["n"]) + 1
				var pa: Array = op[5]
				var md := int(pa[3])
				(pr["mode"] as Dictionary)[md] = int((pr["mode"] as Dictionary).get(md, 0)) + 1
				if md == F.GEN_DELTA:
					for e in (pa[1] as Array):
						var k := int(e[2])
						(pr["ops"] as Dictionary)[k] = int((pr["ops"] as Dictionary).get(k, 0)) + 1
						if k == 3:
							for v in (e[0] as PackedInt32Array):
								var av := absi(int(v))
								if av == 0:
									dist["0"] += 1
								elif av <= 1:
									dist["1"] += 1
								elif av <= 3:
									dist["3"] += 1
								else:
									dist["big"] += 1
				per[gid] = pr
	for gid in per:
		print("[S3P] %s: %s" % [gid, str(per[gid])])
	print("[S3P] 触手中心点差分分布: ", dist)
	print("[S3P] 整局压缩后 %d B" % z_all)
	## 压缩后的账: 每块解出原始字节, 找出各生成函数的定义所在的字节段, 拿掉再压, 与原样压的差 = 它占的压缩后字节
	var want: Array = ["gen_tentacle_body", "gen_tentacle_halo", "gen_tentacle_warn", "gen_water_quad", "gen_bolt_line", "*"]
	var zsum := {}
	var zbase := 0
	for c in chunks:
		var data: PackedByteArray = c
		var hb := StreamPeerBuffer.new()
		hb.big_endian = false
		hb.data_array = data.slice(4, F.HEADER_BYTES)
		hb.get_u16(); hb.get_u32(); hb.get_u32(); hb.get_u16()
		var key := (hb.get_u8() & F.FLAG_KEY) != 0
		var raw_len := int(hb.get_u32())
		var raw := data.slice(F.HEADER_BYTES).decompress(raw_len, FileAccess.COMPRESSION_ZSTD)
		var ranges := _gen_ranges(raw, key)
		zbase += raw.compress(FileAccess.COMPRESSION_ZSTD).size()
		for w in want:
			var keep := PackedByteArray()
			var p := 0
			for rg in ranges:
				if w == "*" or str(rg[2]) == w:
					keep.append_array(raw.slice(p, int(rg[0])))
					p = int(rg[1])
			keep.append_array(raw.slice(p))
			zsum[w] = int(zsum.get(w, 0)) + keep.compress(FileAccess.COMPRESSION_ZSTD).size()
	for w in want:
		print("[S3P] 拿掉 %s 的定义: 压缩后 %d → %d B(它占 %d B)" % [w, zbase, int(zsum[w]), zbase - int(zsum[w])])
	get_tree().quit(0)


## 原始字节里每条「出处键定义」的 [起, 止, 函数名](照 StreamFormat.decode_chunk 的走法, 只为记下字节段)。
var _strs: Array = [""]
func _gen_ranges(raw: PackedByteArray, key: bool) -> Array:
	var out: Array = []
	var r := F.Rd.new(raw)
	if key:
		_strs = [""]
	r.strs = _strs
	while not r.eof() and r.err == "":
		var p0 := r.p
		var op := r.u8()
		match op:
			F.OP_STEP:
				r.vu()
			F.OP_KEYFRAME:
				pass
			F.OP_NODE_NEW:
				r.vu()
				var pk := r.u8()
				if pk == F.PAR_NODE:
					r.vu()
				elif pk == F.PAR_UNIT:
					r.vu()
					r.s()
				elif pk == F.PAR_PATH:
					r.s()
				r.s()
				r.props()
			F.OP_NODE_SET, F.OP_RES_SET, F.OP_UNIT_SET:
				r.vu()
				r.props()
			F.OP_NODE_DEL, F.OP_UNIT_DEL:
				r.vu()
			F.OP_GLOBAL:
				r.props()
			F.OP_UNIT_NEW:
				r.vu()
				r.s()
				r.s()
			F.OP_EVENT:
				r.s()
				var n := r.vu()
				for _i in range(n):
					r.val()
			F.OP_RES_DEF:
				r.vu()
				var kind := r.u8()
				match kind:
					F.RES_PATH, F.RES_SHADER, F.RES_OTHER:
						r.s()
					F.RES_PARAM:
						r.s()
						r.props()
					F.RES_GEN_TEX:
						r.s()
						r.vu()
						r.vu()
					F.RES_PROC_MESH:
						r.s()
						r.vu()
					F.RES_GEN:
						r.s()
						var gid := r.s()
						r.vu()
						var md := r.vu()
						if md == F.GEN_ALIAS:
							r.vu()
						else:
							if md == F.GEN_DELTA:
								r.vu()
							var gn := r.vu()
							for _g in range(gn):
								r.val()
						out.append([p0, r.p, gid.get_slice(":", 2)])
	_strs = r.strs
	return out
