extends Node
## _probe_draw_surrender.gd — E8「平局会不会发生」+ 投降局的战绩记录长什么样（探针, 不进门禁）
##
## 由来: 大轮赛制 v2 方案书 §8 边界情况清单 E8。我在 §8 里写的是
##   「平局被静默算成玩家输 —— `overall_winner()` 返回 "" 时 `_dl_overall_won()` 判 false」。
## 但那是**读代码推出来的**, 按本仓规矩不算数(memory fb-probe-before-claiming-rootcause)。
## 本探针要回答两个问题, 用真实对局的数:
##
##   Q1 打到 `_dl_state == "done"` 时, `dual_lane_winner()` 会不会是空串?
##      (`phase2_duallane.gd:64` 的注释写的是「无平局(NO_DRAW) → 调用方在 final 强制分出」,
##       所以这里真正要验的是【调用方到底做没做到】。)
##
##   Q2 **投降**这条路 —— `RealtimeBattle3DScene.gd:1256` 直接调 `_dl_finish(false)`,
##      **完全绕过 `record_lane_result`** ⇒ 投降局的 `lane_results` 是残缺的。
##      v2 的 A3 要按 `lane_results` 记「横扫」并写进战绩记录, 所以这一条到底残缺成什么样要量出来。
##      现有门禁 `verify_battle_ui.gd:85` 验的是 `_over` / `_settled`, **一个字都没碰 lane_results**。
##
## 跑法(headless):
##   PROBE_MODE=matches|surrender SHIP=1 DL_AUTOFIGHT=1 TURTLE_SEED=<n> TURTLE_BACKEND=" " \
##   APPDATA=<隔离目录> <godot> --headless --audio-driver Dummy --path . \
##   res://tests/_probe_draw_surrender.tscn --quit-after 20000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")

const FRAME_CAP := 18000


func _setup_gs(gs) -> void:
	gs.test_mode = true
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	gs.dual_lineup = {
		"top": [
			{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []},
		],
		"bottom": [
			{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "front", "equips": []},
		],
	}
	gs.season_level = 5
	gs.hearts = 8
	gs.season_total_battles = 12


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("[FAIL] 没有 GameState")
		get_tree().quit(1)
		return
	var mode: String = OS.get_environment("PROBE_MODE") if OS.has_environment("PROBE_MODE") else "matches"
	_setup_gs(gs)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(OS.get_environment("TURTLE_SEED")) if OS.has_environment("TURTLE_SEED") else 1
	gs.dual_ghost = Backend.make_bot(5, rng)
	gs.reset_dual_lane()
	gs.dual_active = true

	var s = RB.new()
	add_child(s)
	await get_tree().process_frame

	if mode == "surrender":
		await _run_surrender(s, gs)
	else:
		await _run_to_done(s, gs)
	print("PROBE_DONE")
	get_tree().quit(0)


## Q1: 打完整局, 看胜者会不会是空串。
func _run_to_done(s, gs) -> void:
	var fr := 0
	while fr < FRAME_CAP and str(s._dl_state) != "done":
		await get_tree().process_frame
		fr += 1
	var winner := str(gs.dual_lane_winner())
	print("── [Q1] 打到收场 ──")
	print("  跑了 %d 帧, _dl_state=%s" % [fr, str(s._dl_state)])
	print("  lane_results = %s" % str(gs.lane_results))
	print("  dual_lane_winner() = '%s'" % winner)
	print("  ⇒ %s" % ("★空串 = 平局真的会发生" if winner == "" else "有胜者, 这一跑不构成平局证据"))
	if str(s._dl_state) != "done":
		print("  ⚠ 没打到 done(帧数不够或卡住) —— 这一跑的胜者判定不算数")


## Q2: 走真投降入口, 看战绩记录被写成什么样。
func _run_surrender(s, gs) -> void:
	# 先让对局真的打起来(等到有单位、进入 fight)
	var fr := 0
	while fr < 3000 and (str(s._dl_state) != "fight" or (s._units as Array).size() == 0):
		await get_tree().process_frame
		fr += 1
	# 再往前推一段, 让它确实打过一会儿(但别打完)
	for _i in range(600):
		if str(s._dl_state) == "done":
			break
		await get_tree().process_frame
	print("── [Q2] 投降前 ──")
	print("  _dl_state=%s  current_lane=%s" % [str(s._dl_state), str(gs.current_lane)])
	print("  lane_results = %s" % str(gs.lane_results))
	var hearts0: int = int(gs.hearts)
	var battles0: int = int(gs.season_total_battles)
	var hist0: int = (gs.match_history as Array).size() if gs.match_history is Array else -1
	print("  命=%d 总场次=%d 战绩条数=%d" % [hearts0, battles0, hist0])

	if str(s._dl_state) == "done":
		print("  ⚠ 已经打完了, 投降这条路没测到 —— 这一跑不算数")
		return

	## ★走真入口: HUD 的投降按钮回调就是这一句(battle_hud.gd:187)
	s._do_surrender()
	await get_tree().process_frame
	await get_tree().process_frame

	print("── [Q2] 投降后 ──")
	print("  _over=%s _settled=%s _dl_state=%s" % [str(s._over), str(s._settled), str(s._dl_state)])
	print("  lane_results = %s" % str(gs.lane_results))
	print("  dual_lane_winner() = '%s'" % str(gs.dual_lane_winner()))
	var hearts1: int = int(gs.hearts)
	var battles1: int = int(gs.season_total_battles)
	var hist1: int = (gs.match_history as Array).size() if gs.match_history is Array else -1
	print("  命 %d → %d(差 %+d)  总场次 %d → %d(差 %+d)  战绩条数 %d → %d(差 %+d)"
		% [hearts0, hearts1, hearts1 - hearts0, battles0, battles1, battles1 - battles0,
		hist0, hist1, hist1 - hist0])
	if hist1 > 0 and gs.match_history is Array:
		print("  最新一条战绩 = %s" % str((gs.match_history as Array)[0]))
	print("  ⇒ lane_results 里有 %d 条记录(打满两路应为 2, 打到终极应为 3)"
		% (gs.lane_results as Dictionary).size())
