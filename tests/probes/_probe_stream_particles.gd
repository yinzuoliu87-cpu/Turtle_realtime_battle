extends SceneTree
## 探针(2026-11-18 · 方案书 20261118d): 一局状态流里有哪些资源定义, ParticleProcessMaterial 有几份、几种功能组合、引用了哪些别的资源。
## 用法: godot --headless -s res://tests/probes/_probe_stream_particles.gd -- <块目录>
const F := preload("res://scripts/systems/stream/stream_format.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else ""
	var names: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".bin"):
			names.append(f)
	names.sort()
	var st := {}
	var kinds := {}
	var classes := {}
	var ppm: Array = []
	var ref_classes := {}
	var rid_class := {}
	var nodes_with_pm := 0
	for nm in names:
		var r := F.parse_chunk(FileAccess.get_file_as_bytes(dir.path_join(nm)), st)
		if not r["ok"]:
			print("bad chunk ", nm, " ", r["err"])
			continue
		for step in r["list"]:
			for op in step[2]:
				if int(op[0]) == F.OP_RES_DEF:
					var kind := int(op[2])
					kinds[kind] = int(kinds.get(kind, 0)) + 1
					if kind == F.RES_PARAM or kind == F.RES_GEN or kind == F.RES_OTHER or kind == F.RES_GEN_TEX or kind == F.RES_PROC_MESH:
						var cls := str(op[3])
						classes[cls] = int(classes.get(cls, 0)) + 1
						rid_class[int(op[1])] = cls
					if kind == F.RES_PARAM and str(op[3]) == "ParticleProcessMaterial":
						ppm.append(op)
				elif int(op[0]) == F.OP_NODE_NEW and str(op[5]).contains("Particles"):
					nodes_with_pm += 1
	print("chunks ", names.size(), " RES_DEF kinds ", kinds)
	print("classes ", classes)
	print("ParticleProcessMaterial defs ", ppm.size(), " · particle NODE_NEW ", nodes_with_pm)
	var keys := {}
	for op in ppm:
		var flags: Array = []
		for p in op[4]:
			var pn := str(p[0])
			if bool(p[2]):
				ref_classes[pn + "→" + str(rid_class.get(int(p[1]), "?"))] = true
			if pn.ends_with("_enabled") or pn.begins_with("particle_flag") or pn.contains("texture") or pn.contains("curve") or pn == "emission_shape" or pn.contains("ramp") or pn.contains("collision_mode") or pn.contains("sub_emitter_mode"):
				flags.append("%s=%s" % [pn, str(p[1]) if not bool(p[2]) else "res"])
		flags.sort()
		keys[",".join(flags)] = int(keys.get(",".join(flags), 0)) + 1
	print("distinct feature keys ", keys.size())
	for k in keys:
		print("  ", keys[k], "× ", k)
	print("referenced sub-resources ", ref_classes.keys())
	quit()
