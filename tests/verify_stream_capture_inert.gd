extends Node
## verify_stream_capture_inert.gd — 逐帧直播 S1: 录状态流不许改结果。
## 方案书 docs/plans/20261019-服务器逐帧直播.md 验收清单「录流不改结果」/ R6。
##
## 同一张任务单跑两遍: 不录(现状: 一帧推几十步、按真实帧长跑一次渲染步) vs 录流(每 2 步用 2·SIM_DT 跑一次渲染步、
## 每步采样三层、各事件总闸录事件) ⇒ **每一个 sim 步**的全场指纹(`ReplayRecorder.fingerprint`)逐字相同,
## 外加终局 digest / 开打次数 / 录像 base64 相同。两局都打满三路:
##   · 镜像快照局(verify_referee_job_roundtrip 同款, 种子 2000023)
##   · 真实快照局(tests/golden/stream_heavy_pair.json, S0 的最重那局)
## ★分母: 每局逐步比较的步数 = 终局步数且 > 5000; 录流那遍录流器真的每步都采了样(steps = sim 步数)、
##   渲染步真的由录流器跑了(us_render > 0)、建过节点、录到事件 —— 否则「相同」可能只是录流器没挂上。

const J := preload("res://tests/_stream_jobs.gd")

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var jobs := [["镜像快照局", J.mirror(gs)], ["真实快照局(最重)", J.heavy()]]
	for jj in jobs:
		await _one(str(jj[0]), jj[1])
	_finish()


func _run(job: Dictionary, stream: Dictionary) -> Array:
	var fp := {}
	var res: Dictionary = await RefereeRunner.run(self, job, func(bt) -> void:
		bt.sim_stepped.connect(func() -> void: fp[int(bt._sim_step_n)] = ReplayRecorder.fingerprint(bt)), stream)
	return [res, fp]


func _one(tag: String, job: Dictionary) -> void:
	print("=== %s ===" % tag)
	_ok("分母 · %s 任务单读得到" % tag, not job.is_empty())
	if job.is_empty():
		return
	var a: Array = await _run(job, {})
	var b: Array = await _run(job, {"keep": false})
	var ra: Dictionary = a[0]
	var rb: Dictionary = b[0]
	var fa: Dictionary = a[1]
	var fb: Dictionary = b[1]
	print("  [量] 不录: ok=%s 开打 %d 步 %d digest %s · 录流: ok=%s 开打 %d 步 %d digest %s" % [str(ra.get("ok")),
		int(ra.get("fights", 0)), int(ra.get("steps", 0)), str(ra.get("digest", "")), str(rb.get("ok")),
		int(rb.get("fights", 0)), int(rb.get("steps", 0)), str(rb.get("digest", ""))])
	_ok("分母 · %s 两遍都算完且打满三路" % tag, bool(ra.get("ok", false)) and bool(rb.get("ok", false))
		and int(ra.get("fights", 0)) == 3 and int(rb.get("fights", 0)) == 3)
	var m: Dictionary = rb.get("stream", {})
	var steps := int(ra.get("sim_steps", 0))
	_ok("分母 · %s 录流器每一步都采了样(录 %d 步 = sim %d 步)、渲染步由录流器跑(%d µs)" % [tag, int(m.get("steps", -1)), steps, int(m.get("us_render", 0))],
		steps > 5000 and int(m.get("steps", -1)) == steps and int(m.get("us_render", 0)) > 0)
	_ok("分母 · %s 录流真的录到东西: 节点 %d 个 / 事件 %s" % [tag, int(m.get("nodes_new", 0)), str(m.get("events", {}))],
		int(m.get("nodes_new", 0)) > 1000 and (m.get("events", {}) as Dictionary).size() >= 4)
	var cmp := 0
	var first_bad := -1
	for s in fa:
		if not fb.has(s) or str(fb[s]) != str(fa[s]):
			if first_bad < 0 or int(s) < first_bad:
				first_bad = int(s)
		cmp += 1
	_ok("分母 · %s 逐步比较的步数 %d = 两遍各自的步数(%d / %d)" % [tag, cmp, fa.size(), fb.size()],
		cmp == fa.size() and fa.size() == fb.size() and cmp >= steps and cmp > 5000)
	_ok("★★%s 开录 vs 不开录: 每一步全场指纹逐字相同" % tag, first_bad < 0,
		"第一个不同的步 %d" % first_bad if first_bad >= 0 else "%d 步全同" % cmp)
	for f in ["winner", "score_code", "steps", "digest", "lane_results", "egg_hp", "replay_b64"]:
		_ok("★%s 结果单 %s 相同" % [tag, f], str(ra.get(f)) == str(rb.get(f)),
			"%s / %s" % [str(ra.get(f)).left(40), str(rb.get(f)).left(40)])


func _finish() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 录状态流不改结果: 两局三路打满逐步指纹相同 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
