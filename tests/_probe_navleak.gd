extends Node
## _probe_navleak.gd — 证明【每建一个战斗场景就漏 1 个 NavMap2D + 1 个 NavRegion2D】
##
## 起因(2026-07-27 队列模拟): 退出报告里 "30 RID allocations of type '11NavRegion2D' were leaked"
## —— 30 场正好 30 个, 一场一个, 线性。
## 根因: battle_world_builder.gd 用 NavigationServer2D.map_create()/region_create() 建的是
## 【服务器 RID】, 不归任何节点所有 → queue_free() 释放不了, 必须显式 free_rid()。
## 全仓库搜不到一处 free_rid, 战斗场景也没有 _exit_tree / NOTIFICATION_PREDELETE。
##
## 这条与真机玩家报告同形: tests/probe_leak.gd 的注释记着
## 〖2026-07-10 真机〗「打到一半突然黑屏然后闪退」—— 每场泄漏固定份额、玩得越久越多。
##
## 断言(两个方向, 缺一个这检查就是空的):
##   A. 建 N 个战斗场景再全部释放 → NavigationServer2D 的 map 数【必须回到基线】
##   B. 分母非空: 建场景时 map 数确实涨过 (否则 A 恒真 —— 可能压根没建 nav)
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/_probe_navleak.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

const N := 4

var _fail := 0

func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _maps() -> int:
	return NavigationServer2D.get_maps().size()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	var dr = get_node_or_null("/root/DataRegistry")
	if gs == null or dr == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	# ★必须搭出【真实双路对局】的上下文 —— 裸 RB.new() 走的路径不建 navmesh,
	#   那样 map 数恒 0, "没泄漏"就是假通过(★B 分母断言第一次就是这么把自己抓出来的)。
	var ids: Array = []
	for p in dr.launch_pets:
		ids.append(str((p as Dictionary)["id"]))
	gs.season_leaders = ids.slice(0, 3)
	gs.left_team.assign(ids.slice(0, 3))
	gs.season_total_battles = 5
	gs.season_level = 4
	gs.hearts = 8
	gs.dual_lineup = {}
	gs.get_dual_lineup()
	var Backend = load("res://scripts/net/backend.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var seed_pool: Dictionary = Backend._load_seed()
	var ghost = Backend.pool_find(seed_pool, 3, [], rng)
	if ghost == null:
		ghost = Backend.make_bot(3, rng)

	var base := _maps()
	print("=== 基线: NavigationServer2D 现有 map %d 个 ===" % base)

	var peak := base
	for i in range(N):
		gs.reset_dual_lane()
		gs.dual_active = true
		gs.dual_ghost = ghost
		var s = RB.new()
		add_child(s)
		for _f in range(20):        # 多跑几帧让 world_builder 把 navmesh 真建出来
			await get_tree().process_frame
		peak = maxi(peak, _maps())
		print("  建第 %d 个战斗场景后: map %d 个" % [i + 1, _maps()])
		s.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		print("  释放后:               map %d 个" % _maps())

	# ★最后一次 queue_free 是延迟的, 要多等几帧才轮到它真销毁 —— 少等就会把"还没释放"误判成"泄漏"
	for _f in range(15):
		await get_tree().process_frame
	var after := _maps()
	print("")
	print("  基线 %d → 建了 %d 个场景(峰值 %d) → 全部释放后 %d" % [base, N, peak, after])

	_ok("★B 分母: 建场景时 map 数确实涨过(否则 A 恒真)", peak > base,
		"峰值 %d vs 基线 %d" % [peak, base])
	_ok("★A 建 %d 个战斗场景再全部释放 → map 数回到基线(不泄漏)" % N, after == base,
		"基线 %d, 实际 %d, 泄漏 %d 个" % [base, after, after - base])

	print("ALL PASS — nav RID 无泄漏" if _fail == 0 else "FAILED: %d (每场漏约 %.1f 个)" % [
		_fail, float(after - base) / float(N)])
	get_tree().quit(0 if _fail == 0 else 1)
