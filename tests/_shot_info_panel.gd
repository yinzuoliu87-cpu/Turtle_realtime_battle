extends Node
## DEV 工具(不是门禁·`_` 前缀所以 run-tests 不会自动收录): 给【战斗内信息面板】截图。
##
## 由来 2026-08-16: 面板素材迭代要求"生成 → 接上 → 实拍 → 自己看图 → 再改",
## 而战斗场的 SELFSHOT 拍的是整场战斗、面板默认没开 ⇒ 拍不到我要看的东西。
## 这个 harness 只做一件事: 开一只配好装备/技能的龟的面板, 定住, 存 PNG。
##
## 跑法:
##   SHOT_OUT=res://_panel.png SHOT_PET=basic \
##     <godot> --path . res://tests/_shot_info_panel.tscn --position 5000,5000 --resolution 1280x720
##
## ★不能用 --headless: 无头拿不到视口纹理(存出来是全黑)。
## ★不走 tween/演出: 面板搭完直接 `_refresh_info_panel()` 同步刷一次再拍(CLAUDE.md §3.5)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame

	var pet := "basic"
	if OS.has_environment("SHOT_PET"):
		pet = OS.get_environment("SHOT_PET")
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit(pet, "left", c)

	## 把这只龟喂饱, 让面板【每一行都有东西可画】——
	## 空面板拍出来看不出素材好坏(条是空的、槽是空的), 等于没拍。
	u["hp"] = float(u.get("maxHp", 1000)) * 0.62
	## ★龟能【不是 u["energy"]】—— 它由 `_energy_state` 从技能冷却进度推出来
	##   (rdy = cooldown_ready(剩余, 满冷却), 显示值 = rdy × 消耗)。
	##   我一开始写 u["energy"]=46, 拍出来一直是 0/80 —— 喂错字段, 图上看着像"条是空的"。
	for _t in (u.get("active_skills", []) as Array):
		var _full: float = s._skill_cd(u, str(_t))
		(u["skill_cd"] as Dictionary)[str(_t)] = _full * 0.45   # 剩 45% 冷却 ⇒ 龟能约 55%
	## ★按【这只龟自己的】专属资源喂 —— 一只龟最多只有一种。
	##   给所有龟都塞怒气会拍出"星际龟/赌神龟也有怒气条"的假象, 看图时会误判。
	if OS.has_environment("SHOT_RES"):
		match pet:
			"lava":    u["rage"] = 30.0
			"space":   u["star_energy"] = float(u.get("maxHp", 1000)) * 0.18
			"shell":   u["shell_storage"] = float(u.get("maxHp", 1000)) * 0.25
			"bubble":  u["bubble_val"] = float(u.get("maxHp", 1000)) * 0.5
			"chest":   u["dmg_dealt"] = 800.0
			"fortune": u["gold"] = 37.0
	## ★装备的真格式是 [{id, star}] 的字典数组, 不是 id 字符串数组 ——
	##   喂错格式会让产品代码 `e as Dictionary` 每只龟报一次 cast 错误(实测 28 条),
	##   而断言照样全绿: 这是【测试数据错】伪装成产品报错, 门禁的致命正则才逮住它。
	## SHOT_EQ=1: 换成带局内读数的三件(087 压载舱 / 083 连击层 / 093 香火石刻痕)
	if OS.has_environment("SHOT_EQ"):
		u["equips"] = [{"id": "p2eq_087", "star": 2}, {"id": "p2eq_083", "star": 3},
			{"id": "p2eq_093", "star": 1}]
		var _gs = s._equip_sys._gadget_sys
		for _q in range(4):
			_gs.tick_unit(u, 0.5)
		s._damage._apply_damage(u, 300, Color.WHITE)
		for _q2 in range(2):
			_gs.tick_unit(u, 0.5)
	else:
		u["equips"] = [{"id": "p2eq_004", "star": 2}, {"id": "p2eq_021", "star": 1},
			{"id": "p2eq_040", "star": 3}]
	if OS.has_environment("SHOT_STATUS"):
		u["slow_until"] = s._t + 99.0
		u["slow_mult"] = 0.6
		u["burn_stacks"] = 7.0
		u["shield"] = 240.0

	s._units.clear()
	s._units.append(u)
	s._edit_mode = false
	s._over = false
	s.set_process(false)

	s._hud._show_unit_info_panel(u)
	s._info_sys._refresh_info_panel()
	for _i in range(6):
		await get_tree().process_frame

	## ★量, 不要眯眼看图。把面板里每个可见 Control 的【矩形 + 文字】打出来 ——
	##   "属性区不见了"这种判断, 靠看截图会判反(我已栽过一次), 靠这份清单不会。
	if OS.has_environment("SHOT_TREE"):
		print("--- 面板节点树(rect / 文字) ---")
		var stack: Array = [[s._info_panel, 0]]
		while not stack.is_empty():
			var it: Array = stack.pop_back()
			var n: Node = it[0]
			var d: int = it[1]
			if n is Control:
				var cc := n as Control
				var r := cc.get_global_rect()
				var tx := ""
				if n is Label: tx = str((n as Label).text)
				elif n is RichTextLabel: tx = str((n as RichTextLabel).get_parsed_text())
				## ★宽度失控要看 combined_minimum_size, 不能看 rect ——
				##   rect 里所有 EXPAND_FILL 的孩子都会跟着撑成一样宽,
				##   看 rect 只能看到"大家都 380", 看不到【是谁要求 380 的】。
				var ms := cc.get_combined_minimum_size()
				print("%s%s [%.0f,%.0f %.0fx%.0f] min=%.0fx%.0f vis=%s  %s" % [
					"  ".repeat(d), n.get_class(), r.position.x, r.position.y,
					r.size.x, r.size.y, ms.x, ms.y,
					str(cc.is_visible_in_tree()), tx.replace("\n", "⏎")])
			var kids := n.get_children()
			for i in range(kids.size() - 1, -1, -1):
				stack.append([kids[i], d + 1])

	## SHOT_DETAIL=skill|equip|more: 顺带把【点开后的描述浮层】也打开再拍 ——
	## 我修好了"点得动"(见 _info_passthrough 的注释), 但点开长什么样一直没拍过。
	if OS.has_environment("SHOT_DETAIL"):
		var which := OS.get_environment("SHOT_DETAIL")
		var ents: Array = s._info_sys._skill_bar_entries(u)
		if which == "skill" and ents.size() > 0:
			var e0: Dictionary = ents[ents.size() - 1]
			s._info_sys._show_detail(s._info_panel, "skill_shot", str(e0.get("name", "")),
				str(e0.get("desc", "")), e0, u)
		elif which == "more":
			var mtxt := ""
			for r2 in s._info_sys._info_stat_rows_minor(u):
				mtxt += str((r2 as Array)[1]) + "
"
			s._info_sys._show_detail(s._info_panel, "more_stats", "更多属性", mtxt, {}, u)
		for _j in range(8):
			await get_tree().process_frame

	var out := "res://_panel.png"
	if OS.has_environment("SHOT_OUT"):
		out = OS.get_environment("SHOT_OUT")
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(out)
	print("[SHOT] 面板 → %s (%dx%d)" % [out, img.get_width(), img.get_height()])
	get_tree().quit()
