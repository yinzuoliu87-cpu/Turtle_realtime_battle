extends Node
## DEV 探针(11-22 用户「闪电龟被动的图标现在是看不到吗」):
##   ① 敌人身上有电击层时, 头顶叠层行(_hbrow_stack)的徽章节点状态 —— 可见 / 位置 / 贴图 / 透明度
##   ② 打开闪电龟自己的详情面板, 被动格的图标
## ★不是门禁。要开窗口才拍得到图:
##   WINDOW=1 SHIP=1 bash godot-quiet.sh --position 2000,80 --resolution 1560x720 res://tests/probes/_probe_lightning_badge.tscn

func _ready() -> void:
	await get_tree().process_frame
	var sc = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	get_tree().root.add_child(sc)
	var t0 := Time.get_ticks_msec()
	var tgt = null
	while Time.get_ticks_msec() - t0 < 40000:
		await get_tree().process_frame
		for u in sc._units:
			if u.get("alive", false) and int((u.get("stacks", {}) as Dictionary).get("electric", 0)) > 0:
				tgt = u
				break
		if tgt != null:
			break
	var lu = null
	for u in sc._units:
		if str(u.get("id", "")) == "lightning" and u.get("alive", false):
			lu = u
	print("[probe] lightning unit = %s" % (lu != null))
	if tgt == null:
		print("[probe] 40 秒内没有任何单位带电击层")
	else:
		for fi in range(30):
			await get_tree().process_frame
			var pl: Array = tgt.get("_hbrow_stack", [])
			var desc := ""
			for b in pl:
				if is_instance_valid(b):
					desc += "#%d sc=%.2f t0=%s sig=%s; " % [b.get_instance_id() % 100000, b.scale.x, str(b.get_meta("pop_t0", "-")), str(b.get_meta("sig", "-")).get_file()]
			print("[probe] f%02d _t=%.3f elec=%d pool=%d %s" % [fi, sc._t, int((tgt.get("stacks", {}) as Dictionary).get("electric", 0)), pl.size(), desc])
		var st: Dictionary = tgt.get("stacks", {})
		print("[probe] 目标 id=%s side=%s stacks=%s" % [tgt.get("id", ""), tgt.get("side", ""), st])
		var head: Vector3 = BattleRender.bar_anchor(sc, tgt)
		print("[probe] bar_anchor 屏幕 = %s  vp=%s" % [sc._cam.unproject_position(head), get_viewport().get_visible_rect().size])
		var pool: Array = tgt.get("_hbrow_stack", [])
		print("[probe] _hbrow_stack 节点数 = %d" % pool.size())
		for b in pool:
			if not is_instance_valid(b):
				print("  (freed)")
				continue
			var ic := b.get_node("icon") as TextureRect
			print("  vis=%s in_tree_vis=%s pos=%s gpos=%s scale=%s mod=%s parent=%s" % [b.visible, b.is_visible_in_tree(), b.position, b.global_position, b.scale, b.modulate, b.get_parent().name if b.get_parent() else "null"])
			print("    icon tex=%s size=%s mod=%s self_mod=%s num='%s'" % [ic.texture.resource_path if ic.texture else "null", ic.size, ic.modulate, ic.self_modulate, (b.get_node("num") as Label).text])
		var ui = sc.get("_ui_layer")
		print("[probe] _ui_layer = %s visible=%s layer=%s" % [ui, ui.visible if ui else "-", ui.layer if ui is CanvasLayer else "-"])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(DevOut.prep("res://.out/shots/lb_badge.png"))
		for k in range(8):
			var t1 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t1 < 400:
				await get_tree().process_frame
			if not tgt.get("alive", false):
				break
			var a: Vector2 = sc._cam.unproject_position(BattleRender.bar_anchor(sc, tgt))
			var pb: Array = tgt.get("_hbrow_stack", [])
			var bd := ""
			for b in pb:
				if is_instance_valid(b) and b.visible:
					bd += "(%d,%d sc%.2f n=%s) " % [int(b.position.x), int(b.position.y), b.scale.x, (b.get_node("num") as Label).text]
			print("[burst] k=%d anchor=(%d,%d) elec=%d badges=%s" % [k, int(a.x), int(a.y), int((tgt.get("stacks", {}) as Dictionary).get("electric", 0)), bd])
			await RenderingServer.frame_post_draw
			var im := get_viewport().get_texture().get_image()
			var r := Rect2i(int(a.x) - 90, int(a.y) - 80, 180, 110).intersection(Rect2i(0, 0, im.get_width(), im.get_height()))
			var c := im.get_region(r)
			c.resize(c.get_width() * 3, c.get_height() * 3, Image.INTERPOLATE_NEAREST)
			c.save_png(DevOut.prep("res://.out/shots/lb_burst_%d.png" % k))
	if lu != null:
		sc._hud._show_unit_info_panel(lu)
		for _i in range(20):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(DevOut.prep("res://.out/shots/lb_panel.png"))
	get_tree().quit(0)
