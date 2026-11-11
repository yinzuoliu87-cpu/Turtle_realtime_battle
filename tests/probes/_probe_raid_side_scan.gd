extends Node
## 探针: 偷袭是不是左边(攻方 = A)系统性占优(2026-11-11 内测联调: 同一对号互换攻守, 两场都是攻方赢)。
##   取内测服那两场锁定的双方阵容(tools 只读取到 .out/side_probe/raids.json: a_snapshot / b_snapshot / a_owned / b_owned),
##   每个种子各跑两遍: X 攻 Y、Y 攻 X(裁判真入口 RefereeRunner.run, mode = raid)。左边赢的比例显著高于一半 ⇒ 有偏。
##   用法: RAIDS_JSON=<绝对路径> SEEDS=1,2,3 <godot> --headless --path . res://tests/probes/_probe_raid_side_scan.tscn

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var rows = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("RAIDS_JSON")))
	if not (rows is Array) or (rows as Array).is_empty():
		print("[SIDE] 读不到 RAIDS_JSON"); get_tree().quit(1); return
	var r0: Dictionary = rows[0]
	var X: Dictionary = r0["a_snapshot"]   # raid 1 的攻方
	var Y: Dictionary = r0["b_snapshot"]   # raid 1 的守方
	var ox: Array = r0.get("a_owned", []) if r0.get("a_owned") is Array else []
	var oy: Array = r0.get("b_owned", []) if r0.get("b_owned") is Array else []
	var seeds: Array = []
	for s in str(OS.get_environment("SEEDS")).split(",", false):
		seeds.append(int(s))
	var left_wins := 0
	var total := 0
	for sd in seeds:
		for orient in [["X", X, ox, "Y", Y, oy], ["Y", Y, oy, "X", X, ox]]:
			var job := {"v": 1, "job_id": 1, "match_id": "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b", "mode": "raid",
				## 不给 a_account / b_account ⇒ 裁判跳过「拥有 ∪ 本周限免」那道(限免按真账号 + 周号抽, 本机编的号算不对); 这里只量胜负
				"key": {"week": 1, "account": "t"},
				"seed": sd, "client_version": ReplayRecorder.client_version(), "level": 2, "a": orient[1], "b": orient[4]}
			job = JSON.parse_string(JSON.stringify(job))
			var res: Dictionary = await RefereeRunner.run(self, job, Callable(), {})
			var w := str(res.get("winner", "?"))
			if w == "a":
				left_wins += 1
			if w == "a" or w == "b":
				total += 1
			print("[SIDE] seed %d  %s 攻 %s ⇒ winner=%s(%s) score=%s err=%s" % [sd, orient[0], orient[3], w,
				("攻方" if w == "a" else ("守方" if w == "b" else "?")), str(res.get("score_code", "")), str(res.get("error", ""))])
	print("[SIDE] 合计: 攻方(左)赢 %d / %d" % [left_wins, total])
	get_tree().quit()
