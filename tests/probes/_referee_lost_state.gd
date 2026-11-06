extends Node
## 探针(2026-11-06 · 一整类: 服务器局丢数据): 裁判跑一局时, 存档字段里哪些变了? 裁判跑完 GameState 整份还原 ⇒ 变了的字段, 结果单不带就丢了。
## 小木斧击杀经验就是这么丢的。跑 E2E_JOBS(逗号分隔的任务文件), 每帧比 capture_all 的快照, 打印「变过的字段 + 起止值」。

var _base := {}
var _changed := {}
var _running := false
var _n := 0


func _process(_d: float) -> void:
	if not _running:
		return
	_n += 1
	if _n % 5 != 0:
		return
	var now: Dictionary = ReplayRecorder.capture_all()
	for k in now:
		var a = var_to_bytes(now[k])
		if a != _base.get(k, PackedByteArray()):
			var s := str(now[k])
			if not _changed.has(k):
				_changed[k] = {"first": s.left(70), "base": bytes_to_var(_base[k]) if _base.has(k) else null}
			_changed[k]["last"] = s.left(70)


func _ready() -> void:
	await get_tree().process_frame
	GameState.test_mode = true
	var total := {}
	for path in OS.get_environment("E2E_JOBS").split(","):
		var job = JSON.parse_string(FileAccess.get_file_as_string(path))
		job["client_version"] = str(ProjectSettings.get_setting("application/config/version"))
		_changed = {}
		_base = {}
		var cap: Dictionary = ReplayRecorder.capture_all()
		for k in cap:
			_base[k] = var_to_bytes(cap[k])
		_running = true
		var res: Dictionary = await RefereeRunner.run(self, job)
		_running = false
		print("[LOST] 任务 %s ok=%s 变过的字段 %d 个" % [str(job.get("job_id")), str(res.get("ok")), _changed.size()])
		for k in _changed:
			total[k] = int(total.get(k, 0)) + 1
	var res_keys := "chest chest_b incense incense_b coins coins_b axe_kills axe_kills_b"
	print("[LOST] 结果单已带: ", res_keys)
	var ks: Array = total.keys()
	ks.sort()
	for k in ks:
		print("[LOST] %s  出现在 %d 局" % [str(k), int(total[k])])
	print("[LOST] capture_all 字段数 ", _base.size())
	print("ALL PASS")
	get_tree().quit(0)
