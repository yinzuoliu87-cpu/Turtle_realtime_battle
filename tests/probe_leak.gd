extends Node
## probe_leak.gd — 探针: 战斗过程中节点数 / 孤儿节点 / 显存对象是否单调增长 (OOM → 黑屏 → 闪退 的可测部分)
## 跑法: SHIP=1 godot --headless --path . res://tests/probe_leak.tscn --quit-after 40000
##
## 用户〖2026-07-10 真机〗:「有些角色图片是黑的」「可能是忍者龟带来的莫名卡顿」「打到一半突然黑屏然后闪退」
## 假设(可证伪): VFX/Sprite3D/Tween 节点没被回收 → 节点数单调增长 → 手机内存耗尽 → 黑屏+闪退。
## 本探针只报【事实】: 每 5 秒打印一次节点数与孤儿数, 最后给增长率。不下结论。

const BATTLE := "res://scenes/RealtimeBattle3D.tscn"

var _samples: Array = []


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	var pack: PackedScene = load(BATTLE)
	var inst := pack.instantiate()
	add_child(inst)

	print("t(s)  nodes  orphans  objects")
	var t := 0.0
	var next := 0.0
	while t < 90.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if t >= next:
			next += 5.0
			var nodes := get_tree().get_node_count()
			var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
			var objs := int(Performance.get_monitor(Performance.OBJECT_COUNT))
			_samples.append([t, nodes, orphans, objs])
			print("%5.0f %6d %8d %8d" % [t, nodes, orphans, objs])

	print("")
	if _samples.size() >= 2:
		var a: Array = _samples[0]
		var b: Array = _samples[_samples.size() - 1]
		var dt: float = float(b[0]) - float(a[0])
		print("节点数 %d → %d  (%.1f 个/秒)" % [int(a[1]), int(b[1]), (float(b[1]) - float(a[1])) / maxf(1.0, dt)])
		print("对象数 %d → %d  (%.1f 个/秒)" % [int(a[3]), int(b[3]), (float(b[3]) - float(a[3])) / maxf(1.0, dt)])
		print("孤儿节点 最终 %d" % int(b[2]))
	print("PROBE DONE")
	get_tree().quit(0)
