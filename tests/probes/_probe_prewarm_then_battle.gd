extends Node
## 探针(2026-11-05): 主菜单刚把文案常量脚本交给后台线程加载(SkillText.prewarm_consts), 立刻进战斗(同一批脚本两边同时加载)
##   —— 不许出编译错误, 战斗正常开打(单位在场、sim 在走)。
## PROBE_MODE(11-11 加):
##   main     = 主线程同步 load 战斗场景(abandoned_match 补打 / 测试直接 load 的路)
##   threaded = 后台线程 load_threaded_request 战斗场景再取(SceneFader.go 的路)
##   none     = 不排预加载, 只进战斗(对照)
func _ready() -> void:
	await get_tree().process_frame
	var mode := OS.get_environment("PROBE_MODE")
	if mode == "":
		mode = "main"
	var n := 0
	if mode != "none":
		n = SkillText.prewarm_consts()
	print("[W] 模式 %s · 后台排上 %d 个" % [mode, n])
	var t0 := Time.get_ticks_msec()
	var ps: PackedScene = null
	if mode == "threaded":
		var path := "res://scenes/RealtimeBattle3D.tscn"
		ResourceLoader.load_threaded_request(path)
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
		ps = ResourceLoader.load_threaded_get(path) as PackedScene
	else:
		ps = load("res://scenes/RealtimeBattle3D.tscn") as PackedScene
	var bt: Node = ps.instantiate()
	add_child(bt)
	print("[W] 加载战斗场景 %d ms" % (Time.get_ticks_msec() - t0))
	for i in range(300):
		await get_tree().process_frame
	var alive := 0
	for u in bt._units:
		if u.get("alive", false):
			alive += 1
	print("[W] 战斗 %.1f 秒 · 在场单位 %d · 仍在后台加载 %d" % [float(bt._t), alive, SkillText._warm_pending.size()])
	get_tree().quit()
