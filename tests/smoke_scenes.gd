extends Node
## smoke_scenes.gd — 全流程闪退排查 (轮I)
## 跑法: godot --headless --path . res://tests/smoke_scenes.tscn --quit-after 3000
##
## 用户〖2026-07-10〗:「出个apk，我去测试，需要注意有没有闪退问题，我上次测试时玩到一半闪退了，
##                    是不是整个流程有漏洞」
##
## 本测试不猜崩因, 只制造【真实会发生的时序】然后看有没有报错:
##   1. 逐个实例化每个场景 → tick 若干帧 → free           (进得去/出得来)
##   2. 反复进出同一场景 (×3)                              (重复进出泄漏/悬垂引用)
##   3. ★战斗打到一半【突然 free 掉整个战斗场景】          (技能 await/create_timer 还挂着 → 协程回来时节点没了)
##   4. ★战斗跑满 60 秒直到自然结束                        (胜负判定 / 结算路径)
##
## 判据: 全程 stderr 里不得出现 SCRIPT ERROR / Parse Error / freed instance / null instance。
## 由外层 shell 抓 (本脚本只负责制造时序 + 自己 print 里程碑)。

const SCENES := [
	"res://scenes/MainMenu.tscn",
	"res://scenes/TeamSelect.tscn",
	"res://scenes/Shop.tscn",
	"res://scenes/Inventory.tscn",
	"res://scenes/Codex.tscn",
	"res://scenes/Settings.tscn",
	"res://scenes/Record.tscn",
	"res://scenes/Leaderboard.tscn",
	"res://scenes/Matchmaking.tscn",
]

const BATTLE := "res://scenes/RealtimeBattle3D.tscn"


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true          # 绝不写玩家存档

	print("=== 1. 逐场景 进入→tick→退出 ===")
	for path in SCENES:
		await _cycle(path, 30)

	print("=== 2. 反复进出 (每个场景 ×3) ===")
	for path in SCENES:
		for i in 3:
			await _cycle(path, 8)
	print("  [OK] 反复进出完成")

	print("=== 3. ★战斗打到一半突然 free 掉整个战斗场景 ===")
	for i in 3:
		var pack: PackedScene = load(BATTLE)
		var inst := pack.instantiate()
		add_child(inst)
		# 跑 2.5 秒: 足够让龟放技 (技能里有 0.3~0.6s 的 create_timer/await 挂着)
		await _tick_for(2.5)
		inst.free()                                  # ★不是 queue_free: 立刻释放, 最恶劣时序
		await _tick_for(1.5)                         # 让所有挂起的 timer 回调打回来
		print("  [OK] 中途硬释放 第%d次" % (i + 1))

	print("=== 4. ★战斗跑满 60 秒 (自然打完/结算) ===")
	var pack2: PackedScene = load(BATTLE)
	var inst2 := pack2.instantiate()
	add_child(inst2)
	await _tick_for(60.0)
	print("  [OK] 60 秒战斗跑完, 场景仍存活=%s" % is_instance_valid(inst2))
	if is_instance_valid(inst2):
		inst2.free()
	await _tick_for(1.0)

	print("")
	print("SMOKE DONE — 无崩溃 (报错由外层 shell 判定)")
	get_tree().quit(0)


func _cycle(path: String, frames: int) -> void:
	if not ResourceLoader.exists(path):
		print("  [SKIP] 不存在: ", path)
		return
	var pack: PackedScene = load(path)
	if pack == null:
		print("  [FAIL] load 失败: ", path)
		return
	var inst := pack.instantiate()
	add_child(inst)
	for i in frames:
		await get_tree().process_frame
	inst.free()
	await get_tree().process_frame
	print("  [OK] ", path.get_file())


func _tick_for(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
