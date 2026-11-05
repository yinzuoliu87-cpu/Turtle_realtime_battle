extends Node
## 探针: 装备文案 {C:类.常量} 第一次取值要加载的脚本, 各自多久(主线程)
func _ready() -> void:
	await get_tree().process_frame
	var want := ["EquipSystem", "EquipTickSystem", "AxeFinalStats", "AxeEvolution", "EqFoodBatch", "EqSpiritBatch", "EqGunBatch", "RealtimeBattle3DScene", "IceSystem"]
	var paths := {}
	for c in ProjectSettings.get_global_class_list():
		if want.has(str(c.get("class", ""))):
			paths[str(c["class"])] = str(c["path"])
	for k in want:
		if not paths.has(k):
			print("[L] %s 不是全局类" % k)
			continue
		var t0 := Time.get_ticks_usec()
		var s = load(paths[k])
		print("[L] %-22s %.1f ms  %s" % [k, (Time.get_ticks_usec() - t0) / 1000.0, paths[k]])
	get_tree().quit()
