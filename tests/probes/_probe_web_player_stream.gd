extends Node
## 探针(2026-11-08 · 网页录像播放器): 按门禁 mirror 任务单跑一局裁判局, 状态流按裁判机同一种写法(块文件 + end.json)
##   写进 PROBE_STREAM_OUT/<对局号>/ —— 给本机 Caddy(server/player/player.caddy)当流根, 拿导出的 WebPlayer 包手动验一遍。
## 跑法: APPDATA=<隔离> TURTLE_SUPABASE=" " PROBE_STREAM_OUT=<目录> <godot> --headless --audio-driver Dummy --path . res://tests/probes/_probe_web_player_stream.tscn

const J := preload("res://tests/_stream_jobs.gd")


func _ready() -> void:
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var out := OS.get_environment("PROBE_STREAM_OUT").strip_edges()
	if out == "":
		print("PROBE 没设 PROBE_STREAM_OUT")
		get_tree().quit(2)
		return
	var gs = get_node_or_null("/root/GameState")
	gs.tutorial_active = false
	gs.test_mode = true
	var job: Dictionary = J.mirror(gs)
	var dir := out.path_join(str(job["match_id"]))
	var res: Dictionary = await RefereeRunner.run(self, job, Callable(), {"dir": dir})
	var meta: Dictionary = res.get("stream", {})
	print("PROBE ok=%s dir=%s chunks=%s steps=%s names=%s" % [str(res.get("ok")), dir, str(meta.get("chunks")), str(meta.get("steps")),
		str(meta.get("names"))])
	get_tree().quit(0 if bool(res.get("ok", false)) else 1)
