extends Node
## _probe_chest_tick.gd —— 全量直播排查第 1 局里乙方宝箱龟: 账上 5500 ≥ 第 1 箱 3000 却没开箱、流里也没有 _chest_value。
## 逐采样步打印宝箱龟: 哪一路 / 活着没 / 身上镜像 / 本场账 / 已开数(探针, 2026-11-20)。

const PA := preload("res://tests/verify_stream_parity_wide.gd")
const J := preload("res://tests/_stream_jobs.gd")


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
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
	var ei := 0
	var eqA: Array = []
	var eqB: Array = []
	for k in range(3):
		eqA.append([{"id": shop[ei % shop.size()], "star": 1 + ei % 3}, {"id": shop[(ei + 1) % shop.size()], "star": 2}, {"id": shop[(ei + 2) % shop.size()], "star": 3}])
		ei += 3
	for k in range(3):
		eqB.append([{"id": shop[ei % shop.size()], "star": 1 + ei % 3}, {"id": shop[(ei + 1) % shop.size()], "star": 2}, {"id": shop[(ei + 2) % shop.size()], "star": 3}])
		ei += 3
	var six: Array = pids.slice(0, 6)
	var a: Dictionary = pa._snap(gs, six.slice(0, 3), eqA, "g_pa_0", "甲0", 0)
	var b2: Dictionary = pa._snap(gs, six.slice(3, 6), eqB, "g_pb_0", "乙0", 1)
	print("乙方快照 chest_treasure_value=", b2.get("chest_treasure_value"), " won=", b2.get("chest_treasures_won"))
	var job: Dictionary = J.job(a, b2, int(PA.SEEDS[0]))
	var last := {"s": -1000}
	var hook := func(bt) -> void:
		bt.ready.connect(func() -> void:
			var rec: StreamRecorder = bt._replay.stream
			rec.on_sampled = func(s: int) -> void:
				if s - int(last["s"]) < 300:
					return
				last["s"] = s
				for u in (bt._units as Array):
					if str((u as Dictionary).get("id", "")) != "chest":
						continue
					var tp: Dictionary = bt._chest_sys.treasure_progress(u)
					print("步 %d %s 路=%s side=%s alive=%s 镜像=%s/%s 账=%s 已开=%s 身上战利品=%s" % [s, str(bt._dl_state), str(GameState.current_lane),
						str(u.get("side")), str(u.get("alive")), str(u.get("_chest_value", "无")), str(u.get("_chest_open_n", "无")),
						str(tp["value"]), str(tp["opened"]), str((u.get("chest_treasures", {}) as Dictionary).keys())])
			, CONNECT_ONE_SHOT)
	await RefereeRunner.run(self, job, hook, {"keep": true})
	pa.free()
	print("DONE")
	get_tree().quit(0)
