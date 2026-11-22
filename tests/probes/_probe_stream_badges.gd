extends Node
## DEV 探针(11-22): 看直播 / 录像时, 头顶叠层徽章(电击 / 墨迹 / 结晶 / 赛博充能)播放端画不画。
## 由来: 全场排查(_probe_cover_sweep)时发现播放端(stream_player)从不调 `_layout_head_badges`,
##   而直播一致性门禁只比面板文字 / 小卡 / 统计, 不量头顶徽章。
## 做法同 verify_stream_parity_wide: 裁判入口本机跑一局并录流 → 播放刚录的流;
##   两边各在采样步上数「身上有叠层的单位」与「画面上可见的头顶徽章」。
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/probes/_probe_stream_badges.tscn

const W := preload("res://tests/verify_stream_parity_wide.gd")
const J := preload("res://tests/_stream_jobs.gd")
const FMT := preload("res://scripts/systems/stream/stream_format.gd")
const SIM_DT := 1.0 / 60.0

var _nat := {}


func _stacked(u: Dictionary) -> int:
	var st: Dictionary = u.get("stacks", {}) if u.get("stacks") is Dictionary else {}
	var n := 0
	for k in ["electric", "ink", "crystal"]:
		if int(st.get(k, 0)) > 0:
			n += 1
	if int(u.get("cyber_ai_charge", 0)) > 0:
		n += 1
	return n


func _badges(b: Node) -> int:
	var n := 0
	for c in b._ui_layer.get_children():
		if c is Control and c.visible and not c.is_queued_for_deletion() and c.get_node_or_null("icon") != null and c.get_node_or_null("num") != null and c.scale.x > 0.05:
			n += 1
	return n


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	var w = W.new()
	var pids: Array = []
	for k in DataRegistry.pet_by_id.keys():
		pids.append(str(k))
	pids.sort()
	var six: Array = []
	for k in range(6):
		six.append(pids[(3 * 6 + k) % pids.size()])
	var a: Dictionary = w._snap(gs, six.slice(0, 3), [[], [], []], "g_pa_x", "甲", 0)
	var b2: Dictionary = w._snap(gs, six.slice(3, 6), [[], [], []], "g_pb_x", "乙", 1)
	var job: Dictionary = J.job(a, b2, 2000035)
	print("[probe] 甲 %s · 乙 %s" % [str(six.slice(0, 3)), str(six.slice(3, 6))])
	var hook := func(bt) -> void:
		bt.ready.connect(func() -> void:
			var rec: StreamRecorder = bt._replay.stream
			rec.on_sampled = func(s: int) -> void:
				if rec._step_n % FMT.CONT_EVERY != 0 or s % 60 != 0:
					return
				var su := 0
				for u in bt._units:
					if u is Dictionary and u.get("alive", false):
						su += 1 if _stacked(u) > 0 else 0
				_nat[s] = [su, _badges(bt)]
			, CONNECT_ONE_SHOT)
	var res: Dictionary = await RefereeRunner.run(self, job, hook, {"keep": true})
	var chunks: Array = res.get("stream_chunks", [])
	print("[probe] 本机一遍: %d 块 · 采样 %d 步" % [chunks.size(), _nat.size()])
	ReplayRecorder.begin_play({"state": {"dual_active": true}})
	ReplayRecorder.pending_play = {}
	ReplayRecorder.play_names = {}
	gs.dual_lineup = {}
	gs.dual_ghost = {}
	gs.season_leaders = []
	StreamPlayer.pending = {"source": StreamSource.Mem.new(chunks, res.get("stream", {})), "seed": RefereeJob.seed_of(job), "no_curtain": true}
	var b: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(b)
	StreamPlayer.pending = {}
	b.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	var nat_su := 0
	var nat_bd := 0
	var pl_su := 0
	var pl_bd := 0
	var rows := 0
	var guard := 0
	p.advance(0.0)
	while p.state != "ended" and p.state != "error" and guard < 400000:
		guard += 1
		p.advance(SIM_DT)
		if _nat.has(p.cur_step):
			var su := 0
			for i in p.units:
				var u = p.units[i]
				if u is Dictionary and u.get("alive", false):
					su += 1 if _stacked(u) > 0 else 0
			var bd := _badges(b)
			var nv: Array = _nat[p.cur_step]
			nat_su += int(nv[0])
			nat_bd += int(nv[1])
			pl_su += su
			pl_bd += bd
			if rows < 12 and int(nv[0]) > 0:
				rows += 1
				print("[probe] 步 %d · 本机: 带叠层单位 %d / 可见徽章 %d · 播放端: 带叠层单位 %d / 可见徽章 %d" % [p.cur_step, int(nv[0]), int(nv[1]), su, bd])
			_nat.erase(p.cur_step)
		if guard % 60 == 0:
			await get_tree().process_frame
	print("[probe] 合计 · 本机: 带叠层单位 %d 次 / 可见徽章 %d 个 · 播放端: 带叠层单位 %d 次 / 可见徽章 %d 个" % [nat_su, nat_bd, pl_su, pl_bd])
	w.free()
	get_tree().quit(0)
