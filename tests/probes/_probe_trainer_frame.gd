extends Node
## 探针(2026-11-25): verify_stream_parity 最重真实快照局, 右方训龟大师立绘第 5640 步起本机 24 / 播放 25 —— 本机这一侧逐步打大师的动画状态
const J := preload("res://tests/_stream_jobs.gd")


func _ready() -> void:
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var hook := func(bt) -> void:
		bt.ready.connect(func() -> void:
			var rec: StreamRecorder = bt._replay.stream
			rec.on_sampled = func(_s: int) -> void:
				var n: int = rec._step_n
				if n < 5560 or n > 5660:
					return
				for u in bt._units:
					if u is Dictionary and str(u.get("id", "")) == "__trainer__" and str(u.get("side", "")) == "right" and u.get("alive", false):
						var sp = u.get("sprite", null)
						var sd: Dictionary = u.get("anim_sd", {})
						print("[T] 步%d frame=%s hf=%s act=%s anim_t=%.6f fps=%s frames=%s manual=%s state=%s fat=%s" % [n,
							str((sp as Sprite3D).frame) if sp is Sprite3D else "-", str((sp as Sprite3D).hframes) if sp is Sprite3D else "-",
							str(u.get("anim_action", "")), float(u.get("anim_t", 0.0)), str(sd.get("fps", "?")), str(sd.get("frames", "?")),
							str(u.get("_manual_anim", false)), str(u.get("state", "")), str((sp as Sprite3D).get_meta(&"_fat", "-")) if sp is Sprite3D else "-"])
			, CONNECT_ONE_SHOT)
	var res: Dictionary = await RefereeRunner.run(self, J.heavy(), hook, {"keep": true})
	print("[T] 结束 steps=%d" % int(res.get("steps", 0)))
	get_tree().quit(0)
