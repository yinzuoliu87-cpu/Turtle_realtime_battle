extends Node
## 探针: 真实快照局(tests/golden/stream_heavy_pair.json 那一对)换种子 —— 规则一改那局就可能 2:0(不三路打满), 直播门禁要的是三路打满。
##   用裁判真入口(RefereeRunner.run, 带录流)逐个复算 SEED_FROM..SEED_TO, 报 开打几路 / 步数 / 最大块(预算 72600 B)。
##   用法: SEED_FROM=2000072 SEED_TO=2000090 <godot> --headless --path . res://tests/probes/_probe_heavy_seed_scan.tscn
##   SCAN_MODE=mirror ⇒ 扫镜像快照局(J.mirror 那一份, 原种子 J.SEED)(2026-11-08 加: RULES_VER 4 后两局都打不满三路)
const J := preload("res://tests/_stream_jobs.gd")
const DIR := "user://heavy_seed_scan"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var d = JSON.parse_string(FileAccess.get_file_as_string(J.HEAVY))
	var a: int = int(OS.get_environment("SEED_FROM")) if OS.has_environment("SEED_FROM") else 2000072
	var b: int = int(OS.get_environment("SEED_TO")) if OS.has_environment("SEED_TO") else 2000090
	var adir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(adir)
	for s in range(a, b + 1):
		for f in DirAccess.get_files_at(adir):
			DirAccess.remove_absolute(adir.path_join(f))
		var job := J.job((d as Dictionary)["a"], (d as Dictionary)["b"], s)
		if OS.get_environment("SCAN_MODE") == "mirror":
			job = J.mirror(gs)
			job["seed"] = s
		var res: Dictionary = await RefereeRunner.run(self, job, Callable(), {"dir": adir})
		var m: Dictionary = res.get("stream", {})
		print("[SEED] %d 开打 %d 步 %d 最大块 %d 压缩 %d %s" % [s, int(res.get("fights", 0)), int(m.get("steps", 0)), int(m.get("max_chunk_bytes", 0)),
			int(m.get("z_bytes", 0)), "★三路·块在预算内" if int(res.get("fights", 0)) == 3 and int(m.get("max_chunk_bytes", 0)) <= 72600 else ""])
	get_tree().quit()
