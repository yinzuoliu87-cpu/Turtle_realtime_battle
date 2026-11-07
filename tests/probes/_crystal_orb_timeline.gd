extends Node
## 探针(2026-11-06, 玩家反馈「水晶球这个有bug」): 跑 E2E_JOB 指的真任务, 记录水晶球每一发光线的时刻 / 伤害 / 存活。
## 文案: 登场召唤, 生命 = 本体 50%, 每 5 秒一道贯穿光线(两段共 1.0×攻击力魔法), 叠 2 层结晶。

var _b = null
var _seen := {}          # 球 uid → {t0, last_dealt, shots: [t...], dealt, hp0}
var _running := false


func _on_battle(b) -> void:
	_b = b


func _process(_d: float) -> void:
	if not _running or _b == null or not is_instance_valid(_b):
		return
	for u in _b._units:
		if str(u.get("kind", "")) != "crystalball" and str(u.get("summon_kind", "")) != "crystalball" and str(u.get("_summon_kind", "")) != "crystalball" and str(u.get("name", "")) != "水晶球" and str(u.get("label", "")) != "水晶球":
			continue
		var k := "%s/%s/%d" % [str(u.get("side", "")), str(u.get("lane", _b.get("_lane") if "_lane" in _b else "")), int(u.get("_spec_uid", u.get("uid", 0)))]
		if not _seen.has(k):
			_seen[k] = {"t0": float(_b._t), "shots": [], "dealt": 0, "maxHp": float(u.get("maxHp", 0)), "atk": float(u.get("atk", 0)),
				"owner_atk": 0.0, "death": -1.0, "pos0": u.get("pos"), "pos1": u.get("pos"), "mr": u.get("mr", 0), "move": 0.0}
		var s: Dictionary = _seen[k]
		var d := int(u.get("_st_dealt", 0))
		if d > int(s["dealt"]):
			var ts: Array = s["shots"]
			if ts.is_empty() or float(_b._t) - float(ts[-1]) > 0.6:
				ts.append(snappedf(float(_b._t), 0.01))
			s["dealt"] = d
		s["pos1"] = u.get("pos")
		if not u.get("alive", false) and float(s["death"]) < 0.0:
			s["death"] = float(_b._t)


func _ready() -> void:
	await get_tree().process_frame
	GameState.test_mode = true
	var job = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("E2E_JOB")))
	job["client_version"] = str(ProjectSettings.get_setting("application/config/version"))
	_running = true
	var res: Dictionary = await RefereeRunner.run(self, job, _on_battle)
	_running = false
	print("[ORB] 任务 %s ok=%s winner=%s steps=%s err=%s 水晶球 %d 个" % [str(job.get("job_id")), str(res.get("ok")), str(res.get("winner", "-")), str(res.get("steps", "-")), str(res.get("error", "")), _seen.size()])
	for k in _seen:
		var s: Dictionary = _seen[k]
		var ts: Array = s["shots"]
		var gaps: Array = []
		for i in range(1, ts.size()):
			gaps.append(snappedf(float(ts[i]) - float(ts[i - 1]), 0.1))
		print("[ORB] %s 生命 %d 攻 %d 登场 t=%.1f 阵亡 t=%.1f 发射 %d 次 累计伤害 %d 间隔 %s 位置 %s → %s" % [k, int(s["maxHp"]), int(s["atk"]), float(s["t0"]), float(s["death"]), ts.size(), int(s["dealt"]), str(gaps), str(s["pos0"]), str(s["pos1"])])
	print("ALL PASS")
	get_tree().quit(0)
