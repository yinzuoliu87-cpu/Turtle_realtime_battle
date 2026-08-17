extends Node
## _probe_panel_heights.gd — 28 只龟的信息面板【内容高度】排行(2026-08-17, 只量不判)
##
## 由来: 面板每一类元素都换过素材了, 但我只用眼睛看过 lava 和 chest 两只。
## 28 只逐个截图要开 28 次 Godot(这台机器 CPU 有确诊故障, 多进程编译最危险) ——
## 所以【一次进程量出全部高度】, 再只截最紧的那几只。
##
## `verify_info_panel_fits` 只打印前 3 只的分母, 拿不到全表, 所以单写这个探针。
##
## 跑法: <godot> --headless --path . res://tests/_probe_panel_heights.tscn --quit-after 20000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")


func _ready() -> void:
	await get_tree().process_frame
	## ★视口必须焊死成设计尺寸 —— 无头默认是 1280x1280 的正方形, 高度差一倍, 量了白量。
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._units.clear()
	s._edit_mode = false
	s._over = false
	s.set_process(false)

	var ids: Array = []
	for k in DataRegistry.pet_by_id.keys():
		ids.append(str(k))
	ids.sort()
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var rows: Array = []
	for pid in ids:
		var u: Dictionary = s._spawn._make_unit(str(pid), "left", c)
		u["hp"] = float(u.get("maxHp", 1000)) * 0.62
		u["equips"] = [{"id": "p2eq_004", "star": 2}, {"id": "p2eq_093", "star": 1},
			{"id": "p2eq_040", "star": 3}]
		u["shield"] = 240.0
		u["burn_stacks"] = 7.0
		u["slow_until"] = s._t + 99.0
		u["slow_mult"] = 0.6
		match str(pid):
			"lava":    u["rage"] = 30.0
			"space":   u["star_energy"] = float(u.get("maxHp", 1000)) * 0.18
			"shell":   u["store_energy"] = float(u.get("maxHp", 1000)) * 0.25
			"bubble":  u["bubble_store"] = float(u.get("maxHp", 1000)) * 0.5
			"chest":   u["dmg_dealt"] = 800.0
			"fortune": u["gold"] = 37.0
		s._units.clear()
		s._units.append(u)
		s._hud._show_unit_info_panel(u)
		for _i in range(4):
			await get_tree().process_frame
		var panel = s._info_panel
		if panel == null or not is_instance_valid(panel):
			print("  %s: 面板没建出来" % pid)
			continue
		var sc: ScrollContainer = null
		var vb: Control = null
		var st: Array = [panel]
		while not st.is_empty():
			var n: Node = st.pop_back()
			if n is ScrollContainer:
				sc = n as ScrollContainer
				for ch in sc.get_children():
					if ch is VBoxContainer:
						vb = ch as Control
				break
			for ch2 in n.get_children():
				st.append(ch2)
		if sc == null or vb == null:
			print("  %s: 找不到滚动容器" % pid)
			continue
		rows.append([str(pid), vb.get_combined_minimum_size().y, sc.size.y, (panel as Control).size.x])

	rows.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	print("=== 28 只龟的面板内容高度(视口 %d) ===" % int(rows[0][2] if rows.size() > 0 else 0))
	for r in rows:
		var need: float = float(r[1])
		var have: float = float(r[2])
		print("  %-10s 内容 %4.0f / 视口 %4.0f  余 %4.0f  面板宽 %.0f%s"
			% [r[0], need, have, have - need, float(r[3]), "   ★装不下" if need > have else ""])
	print("PROBE DONE")
	get_tree().quit(0)
