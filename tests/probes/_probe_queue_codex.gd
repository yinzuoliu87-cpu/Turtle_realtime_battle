extends "res://tests/verify_gauntlet_queue_home.gd"
## DEV 探针(11-22): 测试玩家 alex1997 11-21 反馈「周六匹配的时候，如果再翻图鉴什么的，那就批不到人」。
## 复用 verify_gauntlet_queue_home 的假服务器与排队步骤: 排队 → 回主页(会话搬到 root)→ 进图鉴、连点几只龟 → 停 20 秒,
##   量心跳是否一直到服务器、会话是否活着、排队单是否还在; 最后让假服务器配上, 看会话是否进到「匹配成功」。
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/probes/_probe_queue_codex.tscn

const CODEX := "res://scenes/Codex.tscn"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_gs = get_node_or_null("/root/GameState")
	P2C.now_override_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 5 * 86400 + 12 * 3600
	_setup_gs()
	_net_fake()
	MMK._may_leave_for_test = func(_to: String) -> bool: return false
	_reset_sc({})
	_park()
	var run = await _queue_then_home()
	_ok("分母: 排队后回主页, 会话在 root", run != null and _active() == run and run.get_parent() == get_tree().root)
	## 进图鉴(当前场景换成图鉴)
	var cx: Node = (load(CODEX) as PackedScene).instantiate()
	get_tree().root.add_child(cx)
	get_tree().current_scene = cx
	await _frames(5)
	var p0 := _hit(POLL)
	var t0 := Time.get_ticks_msec()
	var n_sel := 0
	while Time.get_ticks_msec() - t0 < 20000:
		if cx.has_method("_select") and (Time.get_ticks_msec() - t0) % 1500 < 20:
			cx.call("_select", n_sel % 20)
			n_sel += 1
		await get_tree().process_frame
	var p1 := _hit(POLL)
	_ok("★在图鉴里待 20 秒(点了 %d 次龟)心跳照样到服务器(%d → %d, 应约 10 次)" % [n_sel, p0, p1], p1 - p0 >= 7)
	_ok("★会话还活着、排队锁还在、排队单还在", _active() == run and RW.queue_locked() and RW.is_queue_bill(_gs.referee_pending),
		"active=%s locked=%s bill=%s" % [str(_active() != null), str(RW.queue_locked()), str(_gs.referee_pending)])
	## 配上
	_sc["pair"] = true
	var ok_pair := await _wait(func() -> bool: return run != null and is_instance_valid(run) and str(run.state) == RW.ST_FOUND, 8000)
	_ok("★在图鉴里时服务器配上 ⇒ 会话进到「匹配成功」", ok_pair, str(run.state) if run != null and is_instance_valid(run) else "freed")
	cx.queue_free()
	_cleanup()
	_finish()
