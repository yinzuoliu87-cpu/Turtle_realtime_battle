class_name RefereeRunner
extends RefCounted
## 服务器裁判 —— 在本进程里按一份任务单跑完整一局双路(上路 → 下路 → 必要时终极), 返回结果单。
## 方案书: docs/plans/20261019-服务器裁判.md §1。任务单 / 结果单形状见 `referee_job.gd`。
##
## 走的是**真入口**(战斗场 `RealtimeBattle3D.tscn` 原样实例化), 不另起一套模拟:
##   · GameState 按 A 方快照摆好(左), `dual_ghost` = B 方快照(右);
##   · `ReplayRecorder` 以 "referee" 模式开局: 种子从任务单来, 录像格式与客户端录制逐字段相同;
##   · 没有人的输入: 换路幕布 5 秒自己走(sim 里的 `DL_PRESENT_SEC`), 摆位屏一出现就按快照站位开打, 没有判负;
##   · 每帧在时间预算内直接推 sim(`ReplayRecorder.referee_budget_us`), 3D 不渲染、音效静音 —— 都不改结果;
##   · 结算一律跳过(记账是服务端写回 RPC 的事), 打完把 GameState 还原成跑之前那一份(门禁里同一进程连跑多局)。

const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"
## 帧数上限(防卡死的第二道; 第一道是 ReplayRecorder.RESUME_STEP_CAP 步数上限)。100ms 预算下一局约 60~150 帧。
const MAX_FRAMES := 200000


## 跑一局。`host` = 挂战斗场的节点(要在树里); `on_battle` = 可选, 战斗场进树之前回调一次(门禁拿它接每步指纹)。
## `stream` = 可选, 非空 ⇒ 同时录状态流(逐帧直播 S1, `StreamRecorder` 的选项: dir = 写块文件的目录 / keep = 块字节留在内存);
##   录流的元数据放进结果单的 `stream` 键(块字节在 keep 时放 `stream_chunks`)。不传 ⇒ 行为与原来逐字相同。
## 返回结果单(`RefereeJob.ok_result` / `error_result`)。
static func run(host: Node, job: Dictionary, on_battle: Callable = Callable(), stream: Dictionary = {}) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var why := RefereeJob.validate(job)
	if why != "":
		return RefereeJob.error_result(job, why)
	var gs = host.get_node_or_null("/root/GameState")
	if gs == null:
		return RefereeJob.error_result(job, "no_gamestate")
	var backup: Dictionary = ReplayRecorder.capture_all()
	var tm0 := bool(gs.test_mode)
	var battle: Node = (load(BATTLE_SCENE) as PackedScene).instantiate()
	var st: Dictionary = RefereeJob.state_for(job, Callable(battle, "_foe_normalize_lane"))
	if st.has("_error"):
		battle.free()
		return RefereeJob.error_result(job, str(st["_error"]))
	gs.test_mode = true               # 任何 save() 空转(裁判机上没有玩家存档可写)
	gs.tutorial = false
	gs.reset_dual_lane()
	ReplayRecorder.apply_state(st)
	ReplayRecorder.pending_play = {}
	ReplayRecorder.pending_referee = {"seed": RefereeJob.seed_of(job), "id": str(job.get("match_id", ""))}
	if not stream.is_empty():
		ReplayRecorder.pending_referee["stream"] = stream
	var au := host.get_node_or_null("/root/Audio")
	var muted0 := false
	if au != null and au.get("mute_sfx") != null:
		muted0 = bool(au.mute_sfx)
		au.mute_sfx = true            # 一帧几十上百步: 不静音会一帧生几百个播放器(同复算)
	if on_battle.is_valid():
		on_battle.call(battle)
	host.add_child(battle)
	ReplayRecorder.pending_referee = {}   # 正常已被 start() 读走; 万一没读走也不许留给下一局
	var rr = battle.get("_replay")
	var frames := 0
	if rr == null or str(rr.mode) != "referee":
		why = "not_referee_mode"      # 有别的待播 / 复算抢在前面了(不该发生)
	else:
		var sub = battle.get("_sub")
		if is_instance_valid(sub) and sub is SubViewport:
			(sub as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
		while frames < MAX_FRAMES and not bool(rr.finished) and not bool(rr.referee_stuck):
			await host.get_tree().process_frame
			frames += 1
		if bool(rr.referee_stuck):
			why = "step_cap"
		elif not bool(rr.finished):
			why = "frame_cap"
	var res: Dictionary
	if why != "":
		res = RefereeJob.error_result(job, why)
	else:
		res = RefereeJob.ok_result(job, (rr.rec as Dictionary).duplicate(true),
			(gs.lane_results as Dictionary).duplicate(true), (gs.egg_hp as Dictionary).duplicate(true),
			Time.get_ticks_msec() - t0, frames)
		res["sim_steps"] = int(rr.referee_steps)
		## 左方(A)这一局的战斗内铸币(奇械羁绊 + 035 齿轮): 结算被跳过(`on_settle` 裁判分支), 计数还在系统对象上 ⇒ 这里读。
		##   与本机 `_settle_season` 读的是同一个出口 `EquipTickSystem.match_minted`(门禁 verify_referee_coins 比两边相等)。
		res["coins"] = EquipTickSystem.match_minted(battle)
		## 右方(B)那一侧(2026-10-20 · 周日决赛两边都是真人, 各按自己那一侧发): 同一个出口、同一刻读。
		##   服务端 `referee_complete` 记进 `ledger.coins_b`, B 的客户端经 `referee_finals_coins` 取。
		res["coins_b"] = EquipTickSystem.match_minted(battle, "right")
		## 宝箱龟进度(2026-10-22 · 方案书 20261022-宝箱龟整条链路修复 A): 这一局结束时两侧的累计财宝值 + 已开战利品。
		##   原来结果单不带 ⇒ 服务器局里攒的财宝值 / 开出的箱子一概进不了存档(用户「宝箱整个是不是有bug啊」)。
		##   服务端存整份结果单, `referee_job_status`(A)/ `referee_finals_coins`(A 取 chest、B 取 chest_b)回给客户端,
		##   客户端 `RefereeWatch.apply_chest` 写进存档。★必须在下面还原 GameState 之前读: 左方起点就是这一局的存档。
		res["chest"] = _chest_of(battle, "left")
		res["chest_b"] = _chest_of(battle, "right")
		## 093 香火石(2026-10-23 · 方案书 20261023-香火石四个问题 3): 这一局结束时两侧的刻痕 + 充能。
		##   原来结果单不带 ⇒ 服务器局里攒的香火进不了存档。服务端 20261023 回给客户端, `RefereeWatch.apply_incense` 写存档。
		res["incense"] = _incense_of(battle, "left")
		res["incense_b"] = _incense_of(battle, "right")
	if rr != null and rr.stream != null:
		res["stream"] = rr.stream.finish({"match_id": str(job.get("match_id", "")), "ok": why == "",
			"digest": str(res.get("digest", "")), "client_version": ReplayRecorder.client_version()})
		if bool(stream.get("keep", false)):
			res["stream_chunks"] = rr.stream.chunks
	battle.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	for n in backup:
		var v = backup[n]
		gs.set(str(n), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	gs.test_mode = tm0
	if au != null and au.get("mute_sfx") != null:
		au.mute_sfx = muted0
	return res

## 一侧的宝箱进度 → 结果单里的形状 {"value": 财宝值, "won": [战利品 id]}(客户端 RefereeNet.parse_chest 认这个形状)。
##   取数走 ChestSystem.ledger_final(这一局本场宝箱账的终值; 这一侧没有宝箱龟 ⇒ 原样是起点)。
static func _incense_of(battle, side: String) -> Dictionary:
	var inc = battle._equip_sys._incense
	return {"marks": int(inc.marks_of(side)),
		"charge": clampi(int((inc._chg as Dictionary).get(side, 0)), 0, IncenseStoneSystem.PER_MARK)}


static func _chest_of(battle, side: String) -> Dictionary:
	var f: Dictionary = battle._chest_sys.ledger_final(side)
	return {"value": float(f.get("chest_treasure_value", 0.0)), "won": (f.get("chest_treasures_won", []) as Array).duplicate()}
