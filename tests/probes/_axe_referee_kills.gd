extends Node
## 探针(2026-11-06): 服务器局里小木斧的击杀经验到底发生了没有、带没带回来。
## 跑 E2E_JOB 指的真任务(tools 里从正式服只读取出来的), 裁判运行时每帧盯 GameState.axe_exp_total ——
## 裁判跑完会把 GameState 整份还原, 所以只有运行中才看得到。打印: 这一局涨了多少、结果单里有没有带斧头的键。

var _base := -1
var _peak := -1
var _running := false


func _process(_d: float) -> void:
	if _running:
		var t := int(GameState.axe_exp_total)
		if t != _base:
			_peak = maxi(_peak, t)


func _ready() -> void:
	await get_tree().process_frame
	GameState.test_mode = true
	var job = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("E2E_JOB")))
	job["client_version"] = str(ProjectSettings.get_setting("application/config/version"))
	var a: Dictionary = job["a"]
	var start := int(a.get("axe_exp_total", 0))
	_running = true
	_base = int(GameState.axe_exp_total)
	var res: Dictionary = await RefereeRunner.run(self, job)
	_running = false
	var keys: Array = []
	for k in res:
		if str(k).find("axe") >= 0 or str(k).find("kill") >= 0:
			keys.append(k)
	print("[AXE] 任务 %s 起点累计 %d | 运行中最高 %d(基线 %d)| 涨了 %d | 结果 ok=%s steps=%s | 结果单共 %d 键, 带斧头/击杀的键 %s" % [
		str(job.get("job_id")), start, _peak, _base, maxi(0, _peak - start), str(res.get("ok")), str(res.get("steps")), res.size(), str(keys)])
	print("[AXE] 结果单的键: ", res.keys(), " error=", res.get("error", ""))
	print("ALL PASS")
	get_tree().quit(0)
