extends SceneTree
## 探针(2026-11-18 · 方案书 20261118d): 网页播放器预热按签名去重后, 同一类节点的各种签名之间到底差在哪几个属性。
## 用法: godot --headless -s res://tests/probes/_probe_warm_sigs.gd -- <块目录> [类名=Sprite3D]
const W := preload("res://scripts/systems/replay/web_shader_warmup.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0]
	var cls: String = args[1] if args.size() > 1 else "Sprite3D"
	var names: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".bin"):
			names.append(f)
	names.sort()
	var w = W.new()
	for nm in names:
		w.chunks.append(FileAccess.get_file_as_bytes(dir.path_join(nm)))
	while w._i < w.chunks.size():
		w._parse_some()
	## 每个属性在这一类的各签名里出现了几种取值
	var vals := {}
	var n := 0
	for sig in w._sigs:
		var parts: PackedStringArray = str(sig).split("|")
		if parts[0] != cls:
			continue
		n += 1
		for p in parts:
			var k := p.split("=")[0]
			if not vals.has(k):
				vals[k] = {}
			vals[k][p] = true
	print("%s: %d signatures" % [cls, n])
	var rows: Array = []
	for k in vals:
		rows.append([(vals[k] as Dictionary).size(), k])
	rows.sort()
	rows.reverse()
	for r in rows:
		if int(r[0]) > 1:
			var ex: Array = (vals[r[1]] as Dictionary).keys().slice(0, 3)
			print("  %3d distinct  %s   e.g. %s" % [r[0], r[1], str(ex).left(220)])
	w.free()
	quit()
