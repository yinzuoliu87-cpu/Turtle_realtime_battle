extends Node
## 探针(只读): 商店底部「出战阵容」那六列的名字, 在【还没选龟】时到底是什么?
## 实拍看到的是「上·」「下·」—— 点号后面空着。推理不算根因, 这里把真值打出来。

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	var lineup: Dictionary = gs.get_dual_lineup()
	var row := 0
	for lk in ["top", "bottom"]:
		for u in (lineup.get(lk, []) as Array):
			if not (u is Dictionary): continue
			var is_leader := str(u.get("kind", "")) == "leader"
			var nm := ""
			if is_leader:
				nm = str(DataRegistry.pet_by_id.get(str(u.get("id", "")), {}).get("name", u.get("id", "龟")))
			elif bool(u.get("elite", false)):
				nm = "精英小将"
			else:
				nm = "近战小将" if str(u.get("role", "front")) == "front" else "远程小将"
			print("  [%d] lane=%-6s kind=%-8s id=%-10s ⇒ nm=%s  ⇒ 标签「%s·%s」%s" % [
				row, lk, str(u.get("kind", "")), '"' + str(u.get("id", "")) + '"', '"' + nm + '"',
				"上" if lk == "top" else "下", nm,
				"   ★点号后面空着" if nm.strip_edges() == "" else ""])
			row += 1
	print("  ★分母: 共 %d 列" % row)
	get_tree().quit(0)
