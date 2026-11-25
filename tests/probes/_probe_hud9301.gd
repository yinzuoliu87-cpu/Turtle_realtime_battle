extends Node
## _probe_hud9301.gd —— 匕首批 verify_stream_hud_parity 红(最重真实快照局第 9301 步「团灭」印章本机有 / 播放没有)的探针(2026-11-25)
## 原生跑一遍最重真实快照局, 第 9290~9303 步每步打: 双路状态 / 每方存活计数 / 每个 hp>0 或 alive 有变化的单位(id / side / hp / alive / 召唤物)
const J := preload("res://tests/_stream_jobs.gd")


func _ready() -> void:
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var job: Dictionary = J.heavy()
	var hook := func(bt) -> void:
		bt.ready.connect(func() -> void:
			var rec: StreamRecorder = bt._replay.stream
			var prev := {}
			rec.on_sampled = func(s: int) -> void:
				var n: int = rec._step_n
				if n < 9285 or n > 9304:
					return
				var line := "[P] 步 %d 采样 %d · dl=%s · 活 左 %d 右 %d" % [n, s, str(bt._dl_state),
					int(bt._dl_sys._dl_side_alive("left")), int(bt._dl_sys._dl_side_alive("right"))]
				print(line)
				for i in range(rec._uk.size()):
					var u = rec._uk[i]
					if not (u is Dictionary):
						continue
					var key := "%s|%s" % [str(u.get("hp", 0)), str(u.get("alive", false))]
					if prev.get(i, "") != key and (float(u.get("hp", 0.0)) > 0.0 or bool(u.get("alive", false)) or prev.has(i)):
						print("    [P] 单位%d %s %s hp=%.1f/%.0f alive=%s summon=%s egg=%s" % [i, str(u.get("id", "")), str(u.get("side", "")),
							float(u.get("hp", 0.0)), float(u.get("maxHp", 0.0)), str(u.get("alive", false)), str(u.get("is_summon", false)), str(u.get("_isEgg", false))])
					prev[i] = key
			, CONNECT_ONE_SHOT)
	var res: Dictionary = await RefereeRunner.run(self, job, hook, {"keep": true})
	print("[P] 结束 ok=%s steps=%d" % [str(res.get("ok", false)), int(res.get("steps", 0))])
	get_tree().quit(0)
