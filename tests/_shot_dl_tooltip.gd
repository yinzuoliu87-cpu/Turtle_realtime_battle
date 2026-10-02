extends Node
## DEV 工具(`_` 前缀 ⇒ run-tests 不收录): 给【战斗内对阵预览幕布里那个 44×44 装备格的 tooltip】实拍。
##
## 由来 2026-10-02: 那个格子的 tooltip 一直走 Godot 的系统 tooltip(纯 Label)。
## 「它到底画成什么样」只能拍, 不能推 —— 本文件把真正的预览幕布建出来、把鼠标真推上去、
## 等 tooltip 浮出来再抓视口纹理。
##
## 跑法(★不能 --headless: 无头不渲染, 存出来是空图而且不报错):
##   WINDOW=1 SHOT_OUT=/c/tmp/x.png bash godot-quiet.sh \
##     --resolution 1280x720 --position 5000,5000 res://tests/_shot_dl_tooltip.tscn
##
## ★两条实测结论(见 tests/_post_ts_tooltip.gd 的头注):
##   ① hover 要用 `Viewport.push_input()`, 且先在控件外面动一下再移进来;
##   ② Godot 4.6 的 tooltip 宿主类名是 `PopupPanel`, 里面不含 "Tooltip" 字样。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")


func _ready() -> void:
	## ★截图台不是 headless ⇒ `GameState.test_mode` 不会自动置位, 不手动置的话
	##   页面自己的写入会落盘污染玩家真存档(同 tests/_shot_scene.gd 的头注)。
	var _gs = get_node_or_null("/root/GameState")
	if _gs != null:
		_gs.test_mode = true
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	for _i in range(4):
		await get_tree().process_frame

	## 给这一路的我方阵容【真的配上装备】—— `_dl_unit_card` 只在 `spec.equips` 非空时
	## 才画那一排 44×44 的格子, 不配就是「（无装备）」一行字, 拍不到要拍的东西。
	## ★走 `GameState.dual_lineup` 这个产品自己读的字段(见 `get_dual_lineup`), 不另开后门。
	var _eqs := [{"id": "p2eq_001", "star": 2}, {"id": "p2eq_002", "star": 3}]
	if _gs != null:
		var _dl: Dictionary = _gs.get_dual_lineup()
		for _lane in ["top", "bottom"]:
			for _u in (_dl.get(_lane, []) as Array):
				if _u is Dictionary and str((_u as Dictionary).get("kind", "")) == "leader":
					(_u as Dictionary)["equips"] = _eqs.duplicate(true)
		_gs.dual_lineup = _dl
	## 直接建产品自己的【对阵预览幕布】—— 里面那一排就是 44×44 的装备格。
	## ★不是我另搭一个台子: `_dl_build_present_overlay` 就是玩家开打前看到的那一屏,
	##   节点、版式、tooltip 全是同一份代码产出的。
	s._dl_sys._dl_build_present_overlay("preview")
	for _i2 in range(6):
		await get_tree().process_frame

	## 找那一排里的 44×44 格子(按【它自己的尺寸】找, 不按节点名/路径找)。
	var chip: Control = null
	var stack: Array = [s]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control:
			var c := n as Control
			if c.custom_minimum_size == Vector2(44, 44) and str(c.tooltip_text) != "" \
					and c.is_visible_in_tree():
				chip = c
				break
		for ch in n.get_children():
			stack.append(ch)
	if chip == null:
		print("[DLTIP] ⚠ 预览幕布里没找到 44×44 装备格 —— 这一屏可能没装备")
		get_tree().quit(1)
		return
	print("[DLTIP] 命中 %s 脚本=%s rect=%s" % [chip.get_class(),
		("无" if chip.get_script() == null else str(chip.get_script().resource_path)),
		str(chip.get_global_rect())])
	print("[DLTIP] tooltip_text = |%s|" % str(chip.tooltip_text).replace("\n", "⏎"))

	var ctr: Vector2 = chip.get_global_rect().get_center()
	var vp := get_viewport()
	for d in [Vector2(0, -140), Vector2(0, -60), Vector2.ZERO, Vector2(1, 0)]:
		var e := InputEventMouseMotion.new()
		e.position = ctr + d
		e.global_position = e.position
		e.relative = Vector2(1, 1)
		vp.push_input(e)
	for _i3 in range(150):
		await get_tree().process_frame

	var found := false
	var q: Array = [get_tree().root]
	while not q.is_empty():
		var n2: Node = q.pop_back()
		if n2 is Popup:
			var q2: Array = [n2]
			while not q2.is_empty():
				var m: Node = q2.pop_back()
				if m is RichTextLabel:
					found = true
					print("[DLTIP] ★tooltip 里是 RichTextLabel(吃 BBCode) · 屏上的字 = |%s|"
						% str((m as RichTextLabel).get_parsed_text()).replace("\n", "⏎"))
				elif m is Label:
					found = true
					print("[DLTIP] ★tooltip 里是 Label(不吃 BBCode) · 屏上原样印的字 = |%s|"
						% str((m as Label).text).replace("\n", "⏎"))
				for c2 in m.get_children():
					q2.append(c2)
		for ch2 in n2.get_children():
			q.append(ch2)
	if not found:
		print("[DLTIP] ⚠ tooltip 没浮出来")

	var out := "res://_dltip.png"
	if OS.has_environment("SHOT_OUT"):
		out = OS.get_environment("SHOT_OUT")
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(out)
	print("[DLTIP] → %s (%dx%d)" % [out, img.get_width(), img.get_height()])
	get_tree().quit(0)
