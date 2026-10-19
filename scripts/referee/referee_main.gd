extends Node
## 服务器裁判 —— 命令行入口(场景 `res://scenes/Referee.tscn`)。方案书 docs/plans/20261019-服务器裁判.md §1。
##
##   godot --headless --audio-driver Dummy --path <工程> res://scenes/Referee.tscn -- --job=<任务单.json> --out=<结果单.json>
##   可选 `--stream=<目录>`: 同时录状态流(逐帧直播 S1), 块文件与 end.json 写进那个目录(传输 S4 再做)。
##
## 读一份任务单(形状见 `referee_job.gd` 头注) → `RefereeRunner.run` 跑完整一局 → 写结果单 → 退出。
## 退出码: 0 = 算完(结果单 ok=true) / 2 = 拒算(任务单本身不对, 重算也不会变, 结果单 permanent=true)
##        / 3 = 没算完(卡死 / 内部错误, 可重领) / 4 = 参数或文件读写错误。
## ★不连网: 进来第一件事就把后端整层停掉(空白串 = 停用, 与门禁 run-tests.sh 同一个开关); 网络只归轮询器管。
## ★清掉会改走法的开发开关(TURTLE_SEED 会把战斗切成 det 模式、DL_AUTOFIGHT 会跳过幕布……) —— 裁判只认任务单。

const DEV_ENV := ["TURTLE_SEED", "DL_AUTOFIGHT", "STRESS", "WATCHDOG", "SIM_AUTOPILOT", "AI_TRAINER_LEFT",
	"VFXLAB", "MAPEDIT", "DEBUG_EDIT", "REVIEW", "EQDEMO_EQUIP", "EQDEMO_EQUIP2", "SELFSHOT", "VFXCAST", "VFXISO",
	"INFO_DEMO", "VFXPREVIEW", "TRAINER_APPEAR", "AUDIT", "XDBG"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	for k in DEV_ENV:
		if OS.has_environment(k):
			OS.unset_environment(k)
	var args := _args()
	var jp := str(args.get("job", OS.get_environment("REFEREE_JOB")))
	var op := str(args.get("out", OS.get_environment("REFEREE_OUT")))
	if jp == "" or op == "":
		printerr("[Referee] 用法: -- --job=<任务单.json> --out=<结果单.json>")
		get_tree().quit(4)
		return
	var txt := FileAccess.get_file_as_string(jp)
	if txt == "":
		printerr("[Referee] 读不到任务单 %s" % jp)
		get_tree().quit(4)
		return
	var job = JSON.parse_string(txt)
	await get_tree().process_frame
	var res: Dictionary
	if job is Dictionary:
		var sd := str(args.get("stream", OS.get_environment("REFEREE_STREAM")))
		res = await RefereeRunner.run(self, job, Callable(), {"dir": sd} if sd != "" else {})
	else:
		res = RefereeJob.error_result({}, "bad_job")
	var f := FileAccess.open(op, FileAccess.WRITE)
	if f == null:
		printerr("[Referee] 写不了结果单 %s" % op)
		get_tree().quit(4)
		return
	f.store_string(JSON.stringify(res))
	f.close()
	var code := 0
	if not bool(res.get("ok", false)):
		code = 2 if bool(res.get("permanent", false)) else 3
	print("[Referee] %s job=%s winner=%s score=%s steps=%s digest=%s %sms" % [
		"OK" if code == 0 else "ERR " + str(res.get("error", "")), str(res.get("job_id", "")),
		str(res.get("winner", "-")), str(res.get("score_code", "-")), str(res.get("steps", "-")),
		str(res.get("digest", "-")), str(res.get("elapsed_ms", "-"))])
	get_tree().quit(code)


## `--` 之后的 --k=v 参数。
func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--") and s.contains("="):
			var i := s.find("=")
			out[s.substr(2, i - 2)] = s.substr(i + 1)
	return out
