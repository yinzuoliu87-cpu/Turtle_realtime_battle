extends Node
## _probe_stream_unit_fields.gd —— 全量直播排查剩下的几条: 某几个单位字段本机有、流里有没有、播放端收到没有(探针, 2026-11-20)。
## 跑 verify_stream_parity_wide 的某一局(环境 PJOB=1..5, 默认 4), 在第一个交战采样步记下目标龟的字段, 播流到同一步再读一遍。
## 环境 PPID=龟 id(默认 pirate), PKEYS=逗号分隔的键(默认 _picked,active_skills,eq_state,reflect)。

const PA := preload("res://tests/verify_stream_parity_wide.gd")
const J := preload("res://tests/_stream_jobs.gd")
const FMT := preload("res://scripts/systems/stream/stream_format.gd")

var _nat := {}


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	var g: int = int(OS.get_environment("PJOB")) - 1 if OS.has_environment("PJOB") else 3
	var want: String = OS.get_environment("PPID") if OS.has_environment("PPID") else "pirate"
	var keys: Array = Array((OS.get_environment("PKEYS") if OS.has_environment("PKEYS") else "_picked,active_skills,eq_state,reflect").split(","))
	var pa = PA.new()
	var pids: Array = []
	for k in DataRegistry.pet_by_id.keys():
		pids.append(str(k))
	pids.sort()
	var shop: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			shop.append(str((e as Dictionary)["id"]))
	shop.sort()
	var ei := g * 18
	var eqA: Array = []
	var eqB: Array = []
	for k in range(3):
		eqA.append([{"id": shop[ei % shop.size()], "star": 1 + ei % 3}, {"id": shop[(ei + 1) % shop.size()], "star": 2}, {"id": shop[(ei + 2) % shop.size()], "star": 3}])
		ei += 3
	for k in range(3):
		eqB.append([{"id": shop[ei % shop.size()], "star": 1 + ei % 3}, {"id": shop[(ei + 1) % shop.size()], "star": 2}, {"id": shop[(ei + 2) % shop.size()], "star": 3}])
		ei += 3
	var six: Array = []
	for k in range(6):
		six.append(pids[(g * 6 + k) % pids.size()])
	var a: Dictionary = pa._snap(gs, six.slice(0, 3), eqA, "g_pa_%d" % g, "甲%d" % g, 0)
	var b2: Dictionary = pa._snap(gs, six.slice(3, 6), eqB, "g_pb_%d" % g, "乙%d" % g, 1)
	var job: Dictionary = J.job(a, b2, int(PA.SEEDS[g]))
	print("第 %d 局 甲 %s 乙 %s · 看 %s 的 %s" % [g + 1, str(six.slice(0, 3)), str(six.slice(3, 6)), want, str(keys)])
	var hook := func(bt) -> void:
		bt.ready.connect(func() -> void:
			var rec: StreamRecorder = bt._replay.stream
			rec.on_sampled = func(s: int) -> void:
				if not _nat.is_empty() or str(bt._dl_state) != "fight" or rec._step_n % FMT.CONT_EVERY != 0:
					return
				for i in range(rec._uk.size()):
					var u = rec._uk[i]
					if str((u as Dictionary).get("id", "")) == want and bool((u as Dictionary).get("alive", false)):
						var d := {}
						for k in keys:
							d[k] = StreamRecorder._plain_copy((u as Dictionary).get(k)) if (u as Dictionary).get(k) is Dictionary else (u as Dictionary).get(k)
						_nat = {"step": s, "idx": i, "vals": d}
						break
			, CONNECT_ONE_SHOT)
	var res: Dictionary = await RefereeRunner.run(self, job, hook, {"keep": true})
	if _nat.is_empty():
		print("本机没拍到 %s(没上场 / 没活着)" % want)
		get_tree().quit(0)
		return
	for k in keys:
		print("本机 步%d #%d %s = %s" % [_nat["step"], _nat["idx"], k, str(_nat["vals"][k]).left(600)])
	ReplayRecorder.begin_play({"state": {"dual_active": true}})
	StreamPlayer.pending = {"source": StreamSource.Mem.new(res.get("stream_chunks", []), res.get("stream", {})), "seed": RefereeJob.seed_of(job), "no_curtain": true}
	var b: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(b)
	StreamPlayer.pending = {}
	b.set_process(false)
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	p.advance(0.0)
	var guard := 0
	while p.cur_step < int(_nat["step"]) and p.state != "ended" and guard < 400000:
		guard += 1
		p.advance(1.0 / 60.0)
	var pu = p.units.get(int(_nat["idx"]), {})
	for k in keys:
		print("流里 步%d #%d %s = %s" % [p.cur_step, _nat["idx"], k, str((pu as Dictionary).get(k, "<没有>")).left(600)])
	b.queue_free()
	ReplayRecorder.end_play()
	pa.free()
	get_tree().quit(0)
