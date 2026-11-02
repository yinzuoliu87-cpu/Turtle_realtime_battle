extends Node
## 探针(只读): 哪些装备的 `EquipStats.stat_lines` 是空的? —— 那几件才会走到
## 「这件不加属性，只有效果」那一支。不先查出来, 截图只会截到有属性的那九成。
const EquipStats := preload("res://scripts/gamedata/equip_stats.gd")

func _ready() -> void:
	await get_tree().process_frame
	var empty: Array = []
	var n := 0
	for e in DataRegistry.phase2_equipment:
		if not (e is Dictionary): continue
		n += 1
		var eid := str((e as Dictionary).get("id", ""))
		if EquipStats.stat_lines(eid, 1).is_empty():
			empty.append("%s %s" % [eid, str((e as Dictionary).get("name", "?"))])
	print("★分母: 装备 %d 件, 其中无属性行 %d 件" % [n, empty.size()])
	for s in empty: print("   " + s)
	get_tree().quit(0)
