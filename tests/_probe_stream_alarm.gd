extends Node
## 探针(下划线开头: 不是门禁): 按任务单列表逐局录流, 打印白名单外报警(alarm / alarm_props / alarm_first / alarm_where)。
## 用法: ALARM_JOBS=<任务单数组 json 路径> godot --headless res://tests/_probe_stream_alarm.tscn
## 2026-10-20 生产冒烟局(两份上周决赛真人快照)alarm 38 次 —— 用它在真人快照池里找能复现的组合。


func _ready() -> void:
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var jobs = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ALARM_JOBS")))
	if not (jobs is Array):
		print("ALARM_PROBE no jobs")
		get_tree().quit(2)
		return
	for i in range((jobs as Array).size()):
		var job: Dictionary = jobs[i]
		var res: Dictionary = await RefereeRunner.run(self, job, Callable(), {"keep": false})
		var m: Dictionary = res.get("stream", {})
		print("ALARM_PROBE #%d tag=%s ok=%s steps=%s alarm=%s props=%s first=%s" % [i, str(job.get("tag", "")), str(res.get("ok", false)),
			str(res.get("steps", 0)), str(m.get("alarm", -1)), str(m.get("alarm_props", {})), str(m.get("alarm_first", {}))])
		var aw: Dictionary = m.get("alarm_where", {})
		for k in aw:
			for w in aw[k]:
				print("ALARM_WHERE #%d %s :: %s" % [i, k, w])
	print("ALARM_PROBE done")
	get_tree().quit(0)
