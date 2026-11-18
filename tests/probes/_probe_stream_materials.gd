extends SceneTree
## 探针(2026-11-18 · 方案书 20261118d): 一局状态流里「第一次出现」的材质 / 着色器 / 可画节点按时间分布 ——
## 网页播放器剩下的几次长帧(开打 t=0、换路 t≈19.4、终极战场 t≈47.2)是不是这几刻集中冒出新材质。
## 用法: godot --headless -s res://tests/probes/_probe_stream_materials.gd -- <块目录>
const F := preload("res://scripts/systems/stream/stream_format.gd")
const DRAW := ["MeshInstance3D", "Sprite3D", "AnimatedSprite3D", "GPUParticles3D", "CPUParticles3D", "MultiMeshInstance3D",
	"Label3D", "Decal", "OmniLight3D", "SpotLight3D", "DirectionalLight3D", "WorldEnvironment", "FogVolume"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else ""
	var names: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".bin"):
			names.append(f)
	names.sort()
	var st := {}
	var first_step := -1
	var shown := 0
	## 每 0.5 秒一桶: 新材质 RES_DEF 数 / 新着色器数 / 新可画节点数(按类)
	var buckets := {}
	for nm in names:
		var r := F.parse_chunk(FileAccess.get_file_as_bytes(dir.path_join(nm)), st)
		if not r["ok"]:
			continue
		for step in r["list"]:
			if shown < 3:
				print("step head: ", [step[0], step[1]], " ops=", (step[2] as Array).size())
				shown += 1
			var sn := int(step[0])
			if first_step < 0:
				first_step = sn
			var b := int(floor(float(sn - first_step) / 30.0))
			for op in step[2]:
				var code := int(op[0])
				var key := ""
				if code == F.OP_RES_DEF:
					var kind := int(op[2])
					var cls := str(op[3])
					if kind == F.RES_SHADER:
						key = "Shader"
					elif cls.contains("Material"):
						key = cls
				elif code == F.OP_NODE_NEW and str(op[5]) in DRAW:
					key = "+" + str(op[5])
				if key == "":
					continue
				if not buckets.has(b):
					buckets[b] = {}
				buckets[b][key] = int(buckets[b].get(key, 0)) + 1
	var ks: Array = buckets.keys()
	ks.sort()
	print("bucket = 0.5 s of stream steps from the first step (60 steps / s)")
	for b in ks:
		var d: Dictionary = buckets[b]
		var mats := 0
		for k in d:
			if not str(k).begins_with("+"):
				mats += int(d[k])
		if mats >= 5:
			print("  %6.1fs  materials+shaders=%3d  %s" % [b * 0.5, mats, str(d)])
	quit()
