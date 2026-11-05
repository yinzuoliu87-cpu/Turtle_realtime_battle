extends Node
## 实走每一页量卡顿(2026-11-05 用户「商店这个卡顿…是个典型的这个错误，整个游戏里面会不会有很多这种问题呢」)。
##   开真窗口(右屏 · QUIET=1 静音), 依次进各页、做该页最常见的一下点击, 每帧记墙钟间隔, 报 > 50 毫秒的帧落在哪一步。
##   由 tests/probes/_walk_pages.tscn 起(那一场景切走后本节点挂在 root 上继续走)。
var steps: Array = []
var i := -1
var t_step := 0.0
var last_us := 0
var cur := ""
var spikes: Array = []
var step_max: Dictionary = {}
var done := false


func _ready() -> void:
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	gs.season_total_battles = maxi(3, int(gs.season_total_battles))
	var ids: Array = DataRegistry.phase2_equipment_by_id.keys()
	var bench: Array = []
	for k in range(24):
		bench.append({"kind": "item", "id": str(ids[(k * 7) % ids.size()]), "star": 1 + k % 3})
	gs.persistent_bench = bench
	gs.meta_deepsea_coins = 999
	steps = [
		["主菜单(冷启动)", "res://scenes/MainMenu.tscn", 5.0, ""],
		["选龟页", "res://scenes/TeamSelect.tscn", 3.0, ""],
		["背包", "res://scenes/Inventory.tscn", 2.0, ""],
		["背包·点第 1 件装备", "", 1.0, "inv_sel"],
		["背包·点空白取消", "", 1.0, "inv_clear"],
		["商店", "res://scenes/Shop.tscn", 2.0, ""],
		["商店·点第 1 件货", "", 1.0, "shop_sel"],
		["商店·点空白收起", "", 1.0, "shop_clear"],
		["图鉴", "res://scenes/Codex.tscn", 2.0, ""],
		["图鉴·点第 3 只", "", 1.5, "codex_sel"],
		["排行榜", "res://scenes/Leaderboard.tscn", 1.5, ""],
		["战绩", "res://scenes/Record.tscn", 1.5, ""],
		["好友", "res://scenes/Friends.tscn", 1.5, ""],
		["设置", "res://scenes/Settings.tscn", 1.5, ""],
		["回主菜单", "res://scenes/MainMenu.tscn", 2.0, ""],
	]
	last_us = Time.get_ticks_usec()


func _act(kind: String) -> void:
	var sc = get_tree().current_scene
	if sc == null:
		return
	match kind:
		"inv_sel":
			sc._on_bench_click(0)
		"inv_clear":
			sc._clear_selection()
		"shop_sel":
			sc._on_select(0)
		"shop_clear":
			sc._dismiss_popups()
		"codex_sel":
			sc._select(2)


func _next() -> void:
	i += 1
	if i >= steps.size():
		_report()
		return
	var st: Array = steps[i]
	cur = str(st[0])
	t_step = float(st[2])
	step_max[cur] = 0.0
	if str(st[1]) != "":
		get_tree().change_scene_to_file(str(st[1]))
	else:
		_act(str(st[3]))
	last_us = Time.get_ticks_usec()


func _process(delta: float) -> void:
	if done:
		return
	var now := Time.get_ticks_usec()
	var ms := (now - last_us) / 1000.0
	last_us = now
	if i >= 0 and cur != "":
		step_max[cur] = maxf(float(step_max[cur]), ms)
		if ms > 50.0:
			spikes.append("%s: %.0f ms" % [cur, ms])
	t_step -= delta
	if i < 0 or t_step <= 0.0:
		_next()


func _report() -> void:
	done = true
	print("[WALK] 每一步最长的一帧(毫秒):")
	for k in step_max:
		print("[WALK]   %-20s %.0f" % [k, float(step_max[k])])
	print("[WALK] 超过 50 毫秒的帧 %d 个: %s" % [spikes.size(), str(spikes)])
	get_tree().quit()
