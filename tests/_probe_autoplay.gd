extends Node
## _probe_autoplay.gd — R1 探针 (方案书 docs/plans/20260727b-快照档位强度-自举机器人.md)
##
## 只回答四个问题, 不做任何调优、不写报告:
##   ① headless 下一整场双路对局能跑到 _dl_state=="done" 吗? (还是卡在某一路)
##   ② 一场要多少帧 / 多少游戏秒 → 推 30 把的机时
##   ③ _settle_season 真发币 / 真扣命 / 真计场次吗? (打印真实数值, 不推理 —— CLAUDE.md §7)
##   ④ 跑完玩家真实 user://ghost_pool.json 有没有被写? (md5 由外部脚本比对)
##
## 跑法(必须 headless, 本机开 3D 窗口会蓝屏 —— memory project-machine-bsod-during-tests):
##   SHIP=1 DL_AUTOFIGHT=1 TURTLE_SEED=20260727 \
##   <godot> --headless --audio-driver Dummy --path . res://tests/_probe_autoplay.tscn
##
## ★匹配只读 res:// 内置种子 (Backend._load_seed), 【绝不】走 load_pool ——
##   load_pool → _ensure_seeded → save_pool (backend.gd:211) 光是"读"池就会写玩家真实池。
## ★下划线前缀 = run-tests.sh 只自动发现 verify_*.gd, 这个工具不进门禁。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")

const N_MATCHES := 3
const FRAME_CAP := 60000      # 一场上限(det模式 1帧=1/60秒 → 60000帧=1000游戏秒, 远超一场三路)
const REPORT_EVERY := 5000    # 卡住时每这么多帧打一次现场, 便于定位卡在哪一路

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame

	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 没有 GameState autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true    # 双保险: headless 已自动置(GameState.gd:570), 这里显式钉死

	var dr = get_node_or_null("/root/DataRegistry")
	if dr == null:
		print("  [FAIL] 没有 DataRegistry autoload")
		get_tree().quit(1)
		return

	# ── 造一个真·新玩家: 3 统领 / 满命 / 零装备 / 零场次 / 零币 ──
	var all_ids: Array = []
	for p in dr.launch_pets:
		all_ids.append(str((p as Dictionary)["id"]))
	if all_ids.size() < 3:
		print("  [FAIL] 龟数据不足 3 只, 实际 %d" % all_ids.size())
		get_tree().quit(1)
		return
	var team: Array = all_ids.slice(0, 3)

	_rng.seed = 20260727
	gs.season_leaders = team.duplicate()
	gs.left_team.assign(team)
	gs.season_total_battles = 0
	gs.hearts = 8
	gs.meta_deepsea_coins = 0
	gs.persistent_bench = []
	gs.persistent_equipped = {}
	gs.dual_lineup = {}
	gs.get_dual_lineup()      # 建默认布阵(2上路+1下路+小将)

	print("=== _probe_autoplay: headless 连打 %d 把 ===" % N_MATCHES)
	print("  我方统领: %s" % str(team))
	print("  起始: 命=%d 币=%d 场次=%d" % [int(gs.hearts), int(gs.meta_deepsea_coins), int(gs.season_total_battles)])

	var seed_pool: Dictionary = Backend._load_seed()   # 只读 res://, 不写盘
	var seed_n := 0
	for b in seed_pool.get("brackets", {}).keys():
		seed_n += (seed_pool["brackets"][b] as Array).size()
	print("  种子池(只读 res://): %d 支队" % seed_n)
	if seed_n == 0:
		print("  [FAIL] 种子池空 —— 分母为 0, 后面全是空跑")
		get_tree().quit(1)
		return

	var done_cnt := 0
	for i in range(N_MATCHES):
		var ok: bool = await _one_match(gs, seed_pool, i + 1)
		if ok:
			done_cnt += 1

	print("")
	print("=== 探针小结 ===")
	print("  跑完整场: %d/%d" % [done_cnt, N_MATCHES])
	print("  终态: 命=%d 币=%d 赛季场次=%d 淘汰=%s" % [
		int(gs.hearts), int(gs.meta_deepsea_coins), int(gs.season_total_battles), str(gs.is_eliminated())])
	if done_cnt == N_MATCHES:
		print("PROBE OK — headless 能连打完整双路对局")
	else:
		print("PROBE FAILED — 有 %d 场没跑到 done(见上方逐场现场)" % (N_MATCHES - done_cnt))
	get_tree().quit(0 if done_cnt == N_MATCHES else 1)


## 打一场, 返回是否真的跑到 done.
func _one_match(gs, seed_pool: Dictionary, idx: int) -> bool:
	var b: int = Backend.bracket_for_battles(int(gs.season_total_battles))
	var ghost = Backend.pool_find_window(seed_pool, b - 1, b + 1, [], _rng)
	var from_bot := false
	if ghost == null:
		ghost = Backend.make_bot(b, _rng)
		from_bot = true

	# 对手装备件数(用来证明"对手真带装备", 不是空壳)
	var foe_items := 0
	for pid in (ghost as Dictionary).get("equipped", {}).keys():
		foe_items += ((ghost as Dictionary)["equipped"][pid] as Array).size()

	gs.reset_dual_lane()
	gs.dual_active = true
	gs.dual_ghost = ghost

	var coins0 := int(gs.meta_deepsea_coins)
	var batt0 := int(gs.season_total_battles)
	var hearts0 := int(gs.hearts)

	print("")
	print("── 第 %d 把 ── 我方档=%d  对手=%s(档%d%s) 对手装备%d件" % [
		idx, b, str((ghost as Dictionary).get("ghost_id", "?")),
		int((ghost as Dictionary).get("bracket", -1)),
		"·bot兜底" if from_bot else "", foe_items])

	var s = RB.new()
	add_child(s)

	var fr := 0
	while fr < FRAME_CAP and str(s._dl_state) != "done":
		await get_tree().process_frame
		fr += 1
		if fr % REPORT_EVERY == 0:
			print("    …%d帧: _dl_state=%s 当前路=%s 比分=%s 游戏秒=%.1f 场上单位=%d" % [
				fr, str(s._dl_state), str(gs.current_lane), str(gs.lane_results),
				float(s._t), (s._units as Array).size()])

	var reached: bool = str(s._dl_state) == "done"
	var winner := str(gs.dual_lane_winner())
	print("    结果: %s | 用了 %d 帧 / %.1f 游戏秒 | 逐路 %s" % [
		("跑到 done ✔" if reached else "★没跑到 done(卡在 _dl_state=%s)" % str(s._dl_state)),
		fr, float(s._t), str(gs.lane_results)])
	print("    胜负: dual_lane_winner=%s (left=我方)" % (winner if winner != "" else "(空)"))
	print("    结算: 币 %d→%d (+%d) | 命 %d→%d | 场次 %d→%d" % [
		coins0, int(gs.meta_deepsea_coins), int(gs.meta_deepsea_coins) - coins0,
		hearts0, int(gs.hearts), batt0, int(gs.season_total_battles)])

	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return reached
