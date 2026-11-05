extends Node
## 探针(2026-11-05): 主菜单刚把文案常量脚本交给后台线程加载(SkillText.prewarm_consts), 主线程立刻进战斗(同一批脚本两边同时加载)
##   —— 不许出编译错误, 战斗正常开打(单位在场、sim 在走)。
func _ready() -> void:
	await get_tree().process_frame
	var n := SkillText.prewarm_consts()
	print("[W] 后台排上 %d 个" % n)
	var t0 := Time.get_ticks_msec()
	var bt: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(bt)
	print("[W] 主线程加载战斗场景 %d ms" % (Time.get_ticks_msec() - t0))
	for i in range(300):
		await get_tree().process_frame
	var alive := 0
	for u in bt._units:
		if u.get("alive", false):
			alive += 1
	print("[W] 战斗 %.1f 秒 · 在场单位 %d · 仍在后台加载 %d" % [float(bt._t), alive, SkillText._warm_pending.size()])
	get_tree().quit()
