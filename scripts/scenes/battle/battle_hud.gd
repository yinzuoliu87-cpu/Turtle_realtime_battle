class_name BattleHud
extends RefCounted
## 战斗HUD/面板构建与显示: UI层/暂停/日志/统计/编辑笔刷/队伍头像框/胜负横幅/点龟详情面板/触控盘·纯UI
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

func _build_ui_layer() -> void:
	battle._ui_layer = CanvasLayer.new()
	battle._ui_layer.name = "UIOverlay"
	if OS.has_environment("VFXISO"): battle._ui_layer.visible = false   # 纯特效隔离: 藏UI层(血条/飘字/头顶)
	battle._ui_layer.layer = 10
	battle.add_child(battle._ui_layer)
	# 屏幕暗角 (vignette): 铺满屏一张 radial 渐变 (中心透明→四角压暗) → 聚焦中心战斗, 收边氛围.
	#   作 battle._ui_layer 首个子 → 在 3D 之上、其余 UI(标题/血条/飘字)之下, 不挡可读性.
	if not OS.has_environment("NOVIG"):
		var vig = ColorRect.new()
		vig.name = "Vignette"
		vig.set_anchors_preset(Control.PRESET_FULL_RECT)
		vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vig.material = battle._make_vignette_material()   # canvas shader: 按 UV 半径算暗角 alpha (RGB 正确, 不露灰)
		battle._ui_layer.add_child(vig)
	var title = Label.new()
	title.text = "2.5D 实时战斗 · 3v3 (左队 vs 右队)"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#cfe6ff"))
	title.position = Vector2(24, 16)
	battle._ui_layer.add_child(title)
	if battle._is_dual_lane_mode():   # 双路 HUD: 当前路 + 双方蛋血
		battle._dl_hud = Label.new()
		battle._dl_hud.add_theme_font_size_override("font_size", 17)
		battle._dl_hud.add_theme_color_override("font_color", Color("#ffe08a"))
		battle._dl_hud.position = Vector2(340, 44); battle._dl_hud.size = Vector2(700, 24)
		battle._dl_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		battle._ui_layer.add_child(battle._dl_hud)
	_build_pause_log_ui()   # ⏸ 暂停 + 📜 日志 按钮/面板 (R2b)


## ⏸ 暂停 + 📜 日志 顶栏按钮 + 两个默认隐藏面板. 按钮/面板 process_mode=ALWAYS → 暂停中仍可操作.
func _build_pause_log_ui() -> void:
	battle._pause_btn = Button.new()
	battle._pause_btn.text = "⏸"
	battle._pause_btn.position = Vector2(1208, 12); battle._pause_btn.size = Vector2(52, 38)
	battle._pause_btn.add_theme_font_size_override("font_size", 22)
	battle._style_hud_btn(battle._pause_btn)
	battle._pause_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	battle._pause_btn.pressed.connect(battle._toggle_pause)
	battle._ui_layer.add_child(battle._pause_btn)

	var log_btn = Button.new()
	log_btn.text = "📜"
	log_btn.position = Vector2(1148, 12); log_btn.size = Vector2(52, 38)
	log_btn.add_theme_font_size_override("font_size", 20)
	battle._style_hud_btn(log_btn)
	log_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	log_btn.pressed.connect(battle._toggle_log)
	battle._ui_layer.add_child(log_btn)

	var stats_btn = Button.new()
	stats_btn.text = "📊"
	stats_btn.position = Vector2(1088, 12); stats_btn.size = Vector2(52, 38)
	stats_btn.add_theme_font_size_override("font_size", 20)
	battle._style_hud_btn(stats_btn)
	stats_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	stats_btn.pressed.connect(battle._on_dmg_stats_toggle)
	battle._ui_layer.add_child(stats_btn)

	battle._build_pause_panel()
	_build_log_panel()


## HUD 小按钮统一样式: 半透明深底 + 圆角 + hover 高亮.
func _build_log_panel() -> void:
	battle._log_panel = Panel.new()
	battle._log_panel.position = Vector2(24, 300); battle._log_panel.size = Vector2(440, 380)
	battle._log_panel.visible = false
	battle._log_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var psb = StyleBoxFlat.new()
	psb.bg_color = Color(0.03, 0.05, 0.08, 0.92)
	psb.border_color = Color(0.4, 0.55, 0.72, 0.5)
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(8)
	battle._log_panel.add_theme_stylebox_override("panel", psb)
	var vb = VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 12; vb.offset_top = 10; vb.offset_right = -12; vb.offset_bottom = -12
	vb.add_theme_constant_override("separation", 6)
	battle._log_panel.add_child(vb)
	var hdr = Label.new()
	hdr.text = "📜 战斗日志"
	hdr.add_theme_font_size_override("font_size", 17)
	hdr.add_theme_color_override("font_color", Color("#cfe6ff"))
	vb.add_child(hdr)
	battle._log_rt = RichTextLabel.new()
	battle._log_rt.bbcode_enabled = true
	battle._log_rt.scroll_active = true
	battle._log_rt.scroll_following = true
	battle._log_rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle._log_rt.add_theme_font_size_override("normal_font_size", 14)
	vb.add_child(battle._log_rt)
	battle._ui_layer.add_child(battle._log_panel)


## 日志开关: 显/隐面板; 打开时用累积的 _battle_log 重建文本.
func _build_trainer_joystick() -> void:
	if not (SafeArea.is_mobile() or OS.has_environment("TRAINER_JOY")):
		return
	if battle._joystick != null and is_instance_valid(battle._joystick):
		return
	battle._joystick = battle.VirtualJoystick.new()
	var m: Vector4 = SafeArea.margins(Vector2(battle.get_viewport().get_visible_rect().size), 18.0)
	battle._joystick.position = Vector2(m.x, float(battle.get_viewport().get_visible_rect().size.y) - battle.VirtualJoystick.RADIUS * 2.0 - m.w)
	battle._ui_layer.add_child(battle._joystick)


## 双方各 spawn 一个训龟大师(用户2026-07-22 需求3: 己方玩家控制, 对面人机)。
## 站位: 各自基地【后方角落】—— 它射程 2000 够到全场, 不需要靠前; 放角落才像"场外监视者",
## 也不会挤进战线影响分离/避障。
## ★幂等: 已经有了就不重复建 —— _spawn._spawn_teams 与 battle._dl_sys._dl_build_lane_field 都会调, 双路模式下
##   若两边都跑到会 spawn 两个(实测双路走的是后者, 但留这道闸防将来改动)。
func _build_spell_disc() -> void:
	if battle._spell_disc != null and is_instance_valid(battle._spell_disc):
		return
	if battle._ui_layer == null:
		return
	# 圆盘显示【我方大师已装配的主动技能】图标(缺图→无图标, 不崩)。
	# 单技能装配(2026-07-26): 装配的是被动(magic_stone)时无主动→ _act 为 ""(R2 再给圆盘加"被动生效中"循环特效)。
	var _act: String = GameState.trainer_active_skill()
	var sid: String = battle._valid_active(_act) if _act != "" else ""
	var ipath: String = str(battle.TRAINER_SKILLS.get(sid, {}).get("icon", battle.HOOK_ICON))
	var icon: Texture2D = load(ipath) if ResourceLoader.exists(ipath) else null
	battle._spell_disc = battle.SpellDisc.new()
	battle._spell_disc.setup(icon, "Q", Callable(battle._trainer_sys, "_player_cast_hook_auto"), Callable(battle._aim, "_on_spell_aim"))   # 2026-07-26: 修好回调指向真owner(原 Callable(self=BattleHud,…) 指向不存在的方法·移动端圆盘一直没接上)
	var vp: Vector2 = Vector2(battle.get_viewport().get_visible_rect().size)
	var m: Vector4 = SafeArea.margins(vp, 18.0)
	battle._spell_disc.position = Vector2(vp.x - battle.SpellDisc.R * 2.0 - m.z, vp.y - battle.SpellDisc.R * 2.0 - m.w)
	battle._ui_layer.add_child(battle._spell_disc)


## 训龟大师立绘。用户要「像素风的冒险家」, 形象未定 —— 真图放到 battle.TRAINER_SPRITE 即自动生效。
## ★没真图时【退回占位并 push_warning】而不是静默兜底: 占位是小龟, 和冒险家长得完全不一样,
##   悄悄用会让人(包括我自己)以为形象已经做完了。门禁 verify_trainer 也断言这条 warning 存在。
func _show_banner(won: bool) -> void:
	if battle._settled:
		return
	battle._settled = true
	# 结算: 解除暂停态并禁用暂停按钮(结果屏不可暂停); 记一条日志.
	if battle.get_tree().paused:
		battle.get_tree().paused = false
	if battle._pause_panel != null and is_instance_valid(battle._pause_panel):
		battle._pause_panel.visible = false
	if battle._pause_btn != null and is_instance_valid(battle._pause_btn):
		battle._pause_btn.disabled = true
	battle._log("[color=%s]%s[/color]" % ["#ffd93d" if won else "#ff6b6b", "🏆 战斗胜利!" if won else "💀 战斗失败!"])
	# §AUDIO: 结算 — 败方放 defeat 音; BGM 淡出收尾.
	# ⚠缺口(2026-07-21 核实): assets/audio/sfx/ 下【只有 defeat.wav, 没有胜利音】,
	#   所以赢了是静悄悄的。不在这里硬写一个 "victory" —— 文件不存在时 battle._audio_sys._sfx_simple 是
	#   静默失败(不报错、只是没声音), 反而更难发现。等补了音频文件再接。
	if not won:
		battle._audio_sys._sfx_simple("defeat")
	var a = battle._audio_sys._audio()
	if a != null:
		a.stop_bgm()
	var gs = battle.get_node_or_null("/root/GameState")
	var accent = Color("#ffd93d") if won else Color("#ff6b6b")
	# ★2026-07-21 修: 原来这里【全部写死 1280×720 + 绝对 y 坐标】, 只有正好 1280×720 才对,
	#   手机上(分辨率不同)大字会跑偏甚至出屏。改成锚点自适应 —— 任何分辨率都居中。
	#   (用户问「结算的页面你放在屏幕中间了吗」时查出来的: 本路结算幕用 CenterContainer 是对的,
	#    但这个【最终胜负横幅】是另一套写死坐标的代码。)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)                    # 从全透明淡入
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)   # ★锚点铺满, 不写死尺寸
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	battle._ui_layer.add_child(dim)
	var dtw = battle.create_tween()
	dtw.tween_property(dim, "color:a", 0.6, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var big = Label.new()
	big.text = ("🏆 胜利!" if won else "💀 失败!")
	big.add_theme_font_size_override("font_size", 56)
	big.add_theme_color_override("font_color", accent)
	big.set_anchors_preset(Control.PRESET_CENTER_TOP)  # ★横向锚点居中
	big.anchor_left = 0.0; big.anchor_right = 1.0
	big.offset_left = 0.0; big.offset_right = 0.0
	big.anchor_top = 0.34; big.anchor_bottom = 0.34
	big.offset_top = -40.0; big.offset_bottom = 40.0
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	battle._ui_layer.add_child(big)
	# 大字入场: 从大缩到正常 + 淡入(原来是瞬间弹出)
	big.scale = Vector2(1.9, 1.9)
	big.pivot_offset = Vector2(big.size.x * 0.5, 40.0)
	big.modulate.a = 0.0
	var btw = battle.create_tween()
	btw.set_parallel(true)
	btw.tween_property(big, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.12)
	btw.tween_property(big, "modulate:a", 1.0, 0.30).set_delay(0.12)
	# 双路: 大标题下补「整场比分 X-Y」→ 上下路都输显 0-2 整场失败, 一目了然(用户2026-07-12)
	if battle._is_dual_lane_mode() and gs != null and gs.get("lane_results") is Dictionary and not (gs.get("lane_results") as Dictionary).is_empty():
		var score = Label.new()
		score.text = battle._dl_sys._dl_record_line()
		score.add_theme_font_size_override("font_size", 24)
		score.add_theme_color_override("font_color", Color("#cfe6ff"))
		_banner_anchor_row(score, 0.455, 17.0)   # ★锚点自适应(原 position=(0,316) 写死)
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		battle._ui_layer.add_child(score)
		_banner_fade_in(score, 0.34)
	# 奖励/赛季行 (有赛季态才显)
	var info = ""
	if battle._had_season and gs != null:
		if battle._last_was_exhibition:
			info = "表演赛 · +%d 深海币 (已淘汰, 无生命消耗)" % battle._last_reward
		else:
			info = "+%d 深海币    命 %d/8    胜场 %d    Lv.%d" % [battle._last_reward, int(gs.hearts), int(gs.season_wins), int(gs.get("season_level") if gs.get("season_level") != null else 1)]
			if not won:
				info += "    (失一命)"
			if gs.is_eliminated():
				info += "  ·  赛季淘汰!"
	else:
		info = "(练习赛 · 无赛季奖励)"
	var rew = Label.new()
	rew.text = info
	rew.add_theme_font_size_override("font_size", 22)
	rew.add_theme_color_override("font_color", Color("#ffe9a8"))
	_banner_anchor_row(rew, 0.505, 15.0)   # ★锚点自适应(原 position=(0,350) 写死)
	rew.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battle._ui_layer.add_child(rew)
	_banner_fade_in(rew, 0.46)
	# 结束操作按钮化: 只留「返回菜单」(用户2026-07-18"匹配里不应该有再战": 再战=reload重打同对手, roguelike流程不该原地重战→删).
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 28)
	_banner_anchor_row(btn_row, 0.575, 24.0)   # ★锚点自适应(原 position=(0,392) 写死)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	battle._ui_layer.add_child(btn_row)
	# ★教学模式: 结算按钮走导演(战斗1打完→商店, 战斗2打完→结束回菜单), 而不是直接返回菜单。
	var _td = battle.get_node_or_null("/root/TutorialDirector")
	if _td != null and _td.is_active():
		# ★文字用 _peek_next【只读】—— 用 next_scene_after 会在【建按钮时】就推进 stage,
		#   导致战斗1一结算 stage 就跳到 shop, 玩家还没点。点了才 next_scene_after 真推进。
		#   (2026-07-23 自动跑一遍抓到: 战斗1→MainMenu、收尾没关沙盒, 就是这个副作用。)
		var _peek: String = _td._peek_next("battle")
		var _label: String = "去商店 逛逛 ▶" if _peek.ends_with("Shop.tscn") else ("完成教学 ✓" if _peek.ends_with("MainMenu.tscn") else "继续 ▶")
		btn_row.add_child(battle._make_result_btn(_label, Color("#ffc23c"), Color("#3a1f00"),
			func() -> void: battle.get_tree().change_scene_to_file(_td.next_scene_after("battle"))))
	else:
		btn_row.add_child(battle._make_result_btn("🏠 返回菜单", Color("#5aa0d8"), Color("#04121e"),
			func() -> void: battle.get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")))
	_banner_fade_in(btn_row, 0.60)
	_build_stats_panel()             # #2 战斗统计面板


## 结算横幅的一行: 横向铺满 + 纵向按【屏幕比例】定位(而不是写死像素 y)。
## ★为什么: 原来全是 position=Vector2(0, 316) 这种绝对坐标 + size=Vector2(1280,...),
##   只有正好 1280×720 才对; 手机分辨率一变, 大字/比分/按钮就会偏甚至跑出屏幕。
##   frac = 该行中心在屏幕高度的比例; half_h = 行高的一半(像素)。
func _banner_anchor_row(c: Control, frac: float, half_h: float) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	c.offset_left = 0.0
	c.offset_right = 0.0
	c.anchor_top = frac
	c.anchor_bottom = frac
	c.offset_top = -half_h
	c.offset_bottom = half_h

## 结算横幅元素逐个淡入(原来整块瞬间弹出, 没有节奏)
func _banner_fade_in(c: Control, delay: float) -> void:
	c.modulate.a = 0.0
	var tw = battle.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 结算按钮 (再战/返回菜单) — 圆角实色底 + 深字 + hover/pressed 态.
# ══════════════════════════════════════════════════════════════
# 结算统计表 (1:1 回合制 BattleEndScene._stats_table 7 列样式) — 双队并排, 召唤体单列一行
# ══════════════════════════════════════════════════════════════
func _build_stats_panel() -> void:
	# 结算页要含【前面战场】的总结, 不能只有当前这一路(用户2026-07-19): 已结束的路走 battle._st_lane_hist 快照,
	# 当前路直接读活的 battle._units; 三路以上信息量太大 → 做成分页(默认停在「合计」).
	var pages: Array = []            # [{lane, title, left:[row], right:[row]}]
	for snap in battle._st_lane_hist:
		pages.append({"lane": snap["lane"], "title": battle._LANE_CN.get(snap["lane"], str(snap["lane"])),
			"left": snap["left"], "right": snap["right"]})
	var cur = {"lane": "cur", "title": "", "left": [], "right": []}
	for u in battle._units:
		var sd = str(u.get("side", ""))
		if sd == "left" or sd == "right":
			(cur[sd] as Array).append(battle._st_row(u))
	if not ((cur["left"] as Array).is_empty() and (cur["right"] as Array).is_empty()):
		var cl = str(GameState.current_lane) if GameState != null else ""
		cur["title"] = battle._LANE_CN.get(cl, "本场") if not pages.is_empty() else "本场"
		pages.append(cur)
	if pages.is_empty():
		return
	if pages.size() > 1:             # 只有一路就没有「合计」的必要
		pages.append({"lane": "all", "title": "合计",
			"left": battle._st_merge_all(pages, "left"), "right": battle._st_merge_all(pages, "right")})

	var panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.92)
	sb.border_color = Color(0.3, 0.5, 0.7, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 12; sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var title = Label.new()
	title.text = "⚔ 战斗统计"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#cfe6ff"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	# 页体: 每页一个 HBox(我方|敌方), 同时只显一个; 外面套 ScrollContainer —— 合计页行数可能超屏底
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body = Control.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var bodies: Array = []
	for pg in pages:
		var cols = HBoxContainer.new()
		cols.add_theme_constant_override("separation", 28)
		cols.add_child(battle._stats_column("🔵 我方", pg["left"], Color("#7ec8ff")))
		cols.add_child(battle._stats_column("🔴 敌方", pg["right"], Color("#ff9a9a")))
		cols.visible = false
		body.add_child(cols)
		bodies.append(cols)

	# 页签(单路时不显): 点了切页 + 高亮
	var tab_btns: Array = []
	if pages.size() > 1:
		var tabs = HBoxContainer.new()
		tabs.add_theme_constant_override("separation", 6)
		tabs.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(tabs)
		for i in range(pages.size()):
			var b = Button.new()
			b.text = str(pages[i]["title"])
			b.add_theme_font_size_override("font_size", 14)
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var idx = i
			b.pressed.connect(func() -> void: battle._stats_show_page(bodies, tab_btns, idx))
			tabs.add_child(b)
			tab_btns.append(b)
	vb.add_child(scroll)
	battle._stats_show_page(bodies, tab_btns, pages.size() - 1)   # 默认落在最后一页(多路=合计 / 单路=本场)
	battle._ui_layer.add_child(panel)
	panel.position = Vector2(316, 438)
	battle._center_panel_deferred(panel)

func _build_edit_palette() -> void:
	var ids: Array = battle.STATS.keys()
	if not ids.is_empty() and not ids.has(battle._edit_pick_id):
		battle._edit_pick_id = str(ids[0])
	var panel = PanelContainer.new()
	panel.name = "DebugEditPalette"
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.08, 0.13, 0.94)
	sb.border_color = Color("#ffd93d")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 16; sb.content_margin_right = 16
	sb.content_margin_top = 14; sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(16, 52)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	battle._ui_layer.add_child(panel)
	battle._edit_palette = panel

	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	# 标题栏 + 折叠按钮(用户2026-07-24: 左边大面板要能关) —— 折叠时只留这一行, 释放整个左半场。
	var titlebar = HBoxContainer.new(); titlebar.add_theme_constant_override("separation", 8); vb.add_child(titlebar)
	var title = Label.new()
	title.text = "🛠 调试场"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#ffd93d"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titlebar.add_child(title)
	battle._edit_btn_collapse = battle._debug._edit_mk_btn("⊟ 折叠", func(): battle._debug._edit_toggle_collapse(), 84)
	titlebar.add_child(battle._edit_btn_collapse)
	# 可折叠主体: 后续所有设置行都进 battle._edit_body(把 vb 重指向它)
	# 主体套 ScrollContainer: 内容多(尤其选中单位→Inspector追加行)时不撑出屏外够不到(治与"加装备够不到"同类·2026-07-27)
	var _body_sc = ScrollContainer.new()
	_body_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var _evp: Vector2 = Vector2(battle.get_viewport().get_visible_rect().size)
	var _em: Vector4 = SafeArea.margins(_evp, 18.0)
	_body_sc.custom_minimum_size = Vector2(0, clampf(_evp.y - _em.y - _em.w - 130.0, 200.0, 640.0))   # 体高上限=可用高−标题/位置留白 → 面板永远在屏内
	vb.add_child(_body_sc)
	battle._edit_body_sc = _body_sc
	battle._edit_body = VBoxContainer.new(); battle._edit_body.add_theme_constant_override("separation", 10); _body_sc.add_child(battle._edit_body)
	vb = battle._edit_body

	# 选龟/选边/小将 → 已移到底部常驻笔刷栏(_build_brush_bar·用户2026-07-24), 这里不再放。
	var row_min = HBoxContainer.new(); row_min.add_theme_constant_override("separation", 8); vb.add_child(row_min)
	battle._edit_btn_energy = battle._debug._edit_mk_btn("满龟能默认:关", func(): battle._debug._edit_toggle_full_energy(), 160)
	row_min.add_child(battle._edit_btn_energy)

	var row_hp = HBoxContainer.new(); row_hp.add_theme_constant_override("separation", 8); vb.add_child(row_hp)
	row_hp.add_child(battle._debug._edit_lbl("假人HP"))
	row_hp.add_child(battle._debug._edit_mk_btn("−", func(): battle._debug._edit_adjust_hp(-100.0), 48))
	battle._edit_lbl_hp = battle._debug._edit_val_lbl(96)
	row_hp.add_child(battle._edit_lbl_hp)
	row_hp.add_child(battle._debug._edit_mk_btn("+", func(): battle._debug._edit_adjust_hp(100.0), 48))
	row_hp.add_child(battle._debug._edit_mk_btn("掉血/不死", func(): battle._debug._edit_toggle_killable(), 130))

	var row_star = HBoxContainer.new(); row_star.add_theme_constant_override("separation", 8); vb.add_child(row_star)
	row_star.add_child(battle._debug._edit_lbl("装备星级"))
	battle._edit_star_btns = []
	for st in [1, 2, 3]:
		var stc: int = st
		var bs = battle._debug._edit_mk_btn("★%d" % stc, func(): battle._debug._edit_set_star(stc), 60)
		battle._edit_star_btns.append(bs)
		row_star.add_child(bs)

	var row_spd = HBoxContainer.new(); row_spd.add_theme_constant_override("separation", 8); vb.add_child(row_spd)
	row_spd.add_child(battle._debug._edit_lbl("倍速"))
	battle._edit_speed_btns = []
	for si in range(battle.EDIT_SPEEDS.size()):
		var sidx: int = si
		var bp = battle._debug._edit_mk_btn("%s×" % battle._fmt_num(float(battle.EDIT_SPEEDS[si])), func(): battle._debug._edit_set_speed(sidx), 60)   # %g Godot不支持→battle._fmt_num(2026-07-26修预存bug)
		battle._edit_speed_btns.append(bp)
		row_spd.add_child(bp)

	var row_ctl = HBoxContainer.new(); row_ctl.add_theme_constant_override("separation", 8); vb.add_child(row_ctl)
	battle._edit_btn_start = battle._debug._edit_mk_btn("▶ 开始", func(): battle._debug._edit_start_battle(), 100)
	row_ctl.add_child(battle._edit_btn_start)
	battle._edit_btn_edit = battle._debug._edit_mk_btn("⏸ 编辑", func(): battle._debug._edit_back_to_edit(), 100)
	battle._edit_btn_edit.disabled = true
	row_ctl.add_child(battle._edit_btn_edit)
	row_ctl.add_child(battle._debug._edit_mk_btn("🔁 再来一把", func(): battle._debug._edit_replay(), 130))

	var row_ctl2 = HBoxContainer.new(); row_ctl2.add_theme_constant_override("separation", 8); vb.add_child(row_ctl2)
	row_ctl2.add_child(battle._debug._edit_mk_btn("清空", func(): battle._debug._edit_clear(), 90))
	row_ctl2.add_child(battle._debug._edit_mk_btn("返回菜单", func(): battle._debug._edit_exit_to_menu(), 120))

	battle._edit_lbl_status = Label.new()
	battle._edit_lbl_status.add_theme_font_size_override("font_size", 15)
	battle._edit_lbl_status.add_theme_color_override("font_color", Color("#ffe9a8"))
	vb.add_child(battle._edit_lbl_status)
	var help = Label.new()
	help.text = "点空地=摆(龟/小将) · 点单位=选中配装 · 拖拽=挪位 · 满龟能开→秒放技看效果"
	help.add_theme_font_size_override("font_size", 13)
	help.add_theme_color_override("font_color", Color("#7a8a96"))
	vb.add_child(help)

	battle._edit_equip_box = VBoxContainer.new()
	battle._edit_equip_box.add_theme_constant_override("separation", 6)
	vb.add_child(battle._edit_equip_box)

	battle._debug._edit_set_speed(battle._edit_speed_idx)
	battle._debug._edit_load_setup()
	battle._debug._edit_refresh_labels()
	battle._debug._edit_refresh_equip_panel()
	battle._debug._edit_apply_collapse()   # 恢复折叠态(跨编辑/开始/再来 重建持久·用户2026-07-24)

func _build_brush_bar() -> void:
	if battle._edit_brush_bar != null and is_instance_valid(battle._edit_brush_bar):
		battle._edit_brush_bar.queue_free()
	battle._edit_brush_cells = []
	var bar = PanelContainer.new()
	bar.name = "DebugBrushBar"
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.055, 0.09, 0.95)
	sb.border_color = Color("#ffd93d"); sb.border_width_top = 2
	sb.content_margin_left = 8; sb.content_margin_right = 8; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	bar.add_theme_stylebox_override("panel", sb)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -94
	battle._ui_layer.add_child(bar)
	battle._edit_brush_bar = bar
	var root = VBoxContainer.new(); root.add_theme_constant_override("separation", 3); bar.add_child(root)
	var line = HBoxContainer.new(); line.add_theme_constant_override("separation", 8); root.add_child(line)
	battle._edit_btn_side = battle._debug._edit_mk_btn("左队(友军)", func(): battle._debug._edit_toggle_side(), 116)
	line.add_child(battle._edit_btn_side)
	var sc = ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 64)
	line.add_child(sc)
	var strip = HBoxContainer.new(); strip.add_theme_constant_override("separation", 5); sc.add_child(strip)
	for id in battle.STATS.keys():
		var iid = str(id)
		if iid == "__minion__" or iid == battle.TRAINER_ID: continue
		strip.add_child(battle._debug._edit_brush_cell(iid, battle.AVATAR_DIR + iid + ".png", str(battle._data_by_id.get(iid, {}).get("name", iid))))
	strip.add_child(battle._debug._edit_brush_cell("__minion__:front", "", "浪板"))
	strip.add_child(battle._debug._edit_brush_cell("__minion__:back", "", "火箭"))
	strip.add_child(battle._debug._edit_brush_cell("__minion__:elite", "", "精英"))
	strip.add_child(battle._debug._edit_brush_cell(battle.TRAINER_ID, battle.TRAINER_SPRITE, "大师"))
	var hint = Label.new()
	hint.text = "点笔刷(下面高亮)→点战场连点连摆 · 点已摆的龟→设置面板出配置(技能/装备/血量/无敌/满龟能)"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("#ffe9a8"))
	root.add_child(hint)
	battle._debug._edit_refresh_brush_highlight()

# ----------------------------------------------------------------------------
#  1) 左右队头像框栏
# ----------------------------------------------------------------------------
func _build_team_panels() -> void:
	if battle._ui_layer == null:
		return
	# 旧栏清掉 (重生/重开安全)
	if battle._team_panel_left != null and is_instance_valid(battle._team_panel_left):
		battle._team_panel_left.queue_free()
	if battle._team_panel_right != null and is_instance_valid(battle._team_panel_right):
		battle._team_panel_right.queue_free()
	battle._team_panel_left = battle._info_sys._make_team_column("left")
	battle._team_panel_right = battle._info_sys._make_team_column("right")
	battle._ui_layer.add_child(battle._team_panel_left)
	battle._ui_layer.add_child(battle._team_panel_right)

func _make_team_frame(u: Dictionary) -> Control:
	var side = str(u.get("side", "left"))
	var accent = Color("#3fa9ff") if side == "left" else Color("#ff5a5a")
	var frame = PanelContainer.new()
	frame.name = "Frame_" + str(u.get("id", ""))
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color("#12161f")
	sb.set_border_width_all(2)
	sb.border_color = accent
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 6; sb.content_margin_right = 6
	sb.content_margin_top = 5; sb.content_margin_bottom = 5
	frame.add_theme_stylebox_override("panel", sb)
	frame.custom_minimum_size = Vector2(124, 0)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP   # 吃掉点击 (别穿到战场)
	frame.tooltip_text = "%s · 点击看详情" % str(u.get("name", u.get("id", "")))

	var main_col = VBoxContainer.new()   # 头像行 + 装备格行
	main_col.add_theme_constant_override("separation", 5)
	main_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(main_col)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_col.add_child(row)

	# 头像 (44x44)
	var portrait = TextureRect.new()
	portrait.texture = battle._unit_portrait_texture(u)
	portrait.custom_minimum_size = Vector2(44, 44)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)

	# 右侧: 名 + 等级牌 (一行) + 迷你血条
	var info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(top)
	var lv_badge = battle._make_mini_lv_badge(int(u.get("level", 1)))
	if lv_badge != null:
		top.add_child(lv_badge)
	u["panel_lv_badge"] = lv_badge
	var nm = Label.new()
	nm.text = str(u.get("name", u.get("id", "")))
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", Color("#e8f2ff"))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(nm)

	# 迷你血条 (ColorRect bg + fill)
	var hp_bg = ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.55)
	hp_bg.custom_minimum_size = Vector2(battle._PANEL_HP_W, 5)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(hp_bg)
	var hp_fill = ColorRect.new()
	hp_fill.color = Color("#4ade80")
	hp_fill.position = Vector2(0, 0)
	hp_fill.size = Vector2(battle._PANEL_HP_W, 5)
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bg.add_child(hp_fill)
	# 头像下方: 至多4个装备格 (图标 + 充能类装备的充能进度条). 常建空行+存引用 → 招财进宝运行时抽装备可刷新(battle._refresh_panel_equips)
	var eq_row = HBoxContainer.new()
	eq_row.add_theme_constant_override("separation", 4)
	eq_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eq_row.alignment = BoxContainer.ALIGNMENT_CENTER
	main_col.add_child(eq_row)
	u["panel_eq_row"] = eq_row
	battle._refresh_panel_equips(u)

	# 整框点击 → 详情面板
	frame.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_unit_info_panel(u))

	# 引用挂在单位字典上, 供 battle._info_sys._update_team_panels 每帧刷
	u["panel_frame"] = frame
	u["panel_hp_fill"] = hp_fill
	u["panel_stylebox"] = sb
	return frame

# 重建头像下装备格 (从 u["equips"] 取, 至多4格). spawn时建 + 招财进宝运行时抽/升装备后调 → 图标即时显进左右信息框(用户2026-07-12).
func _close_info_panel() -> void:
	if battle._info_panel != null and is_instance_valid(battle._info_panel):
		var _bg = battle._info_panel.get_parent()   # 老版本有全屏灰底backdrop→连父free; 新侧边版面板直接挂_ui_layer(无backdrop)→只free面板
		(_bg if _bg != null and _bg is ColorRect else battle._info_panel).queue_free()
	battle._info_panel = null
	battle._selected_unit = null

func _show_unit_info_panel(u: Dictionary) -> void:
	# 引导第 2 步等的就是"玩家点开了详情面板"这个动作(advanceOn: info_panel_opened)。
	if battle._tutorial != null and is_instance_valid(battle._tutorial):
		battle._tutorial.notify("info_panel_opened")
	_close_info_panel()
	battle._selected_unit = u
	if battle._ui_layer == null:
		return
	var id = str(u.get("id", ""))
	var pet: Dictionary = DataRegistry.pet_by_id.get(id, {})
	var is_left = str(u.get("side", "")) == "left"
	var side_col = Color("#4ade80") if is_left else Color("#ff6b6b")

	# ── 侧边面板(右锚·不遮全场·无backdrop·用户2026-07-18「侧边不遮战场」) ──
	var PW = 400.0
	var panel = PanelContainer.new()
	panel.name = "InfoPanel"
	var psb = StyleBoxFlat.new()
	psb.bg_color = Color(0.055, 0.086, 0.13, 0.96)
	psb.set_border_width_all(2); psb.border_color = Color("#ffd93d")   # 金框(与主菜单一致)
	psb.set_corner_radius_all(14)
	psb.content_margin_left = 16; psb.content_margin_right = 16
	psb.content_margin_top = 14; psb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", psb)
	panel.anchor_left = 1.0; panel.anchor_right = 1.0; panel.anchor_top = 0.0; panel.anchor_bottom = 1.0
	panel.offset_left = -(PW + 16.0); panel.offset_right = -16.0
	panel.offset_top = 56.0; panel.offset_bottom = -16.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP   # 吃掉面板内点击(不穿到战场·点空白才关)
	battle._ui_layer.add_child(panel)
	battle._info_panel = panel

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	# 头部: 头像 + 名 + 阵营/稀有度/Lv + ✖
	var head = HBoxContainer.new(); head.add_theme_constant_override("separation", 10); vb.add_child(head)
	var big = TextureRect.new()
	big.texture = battle._unit_portrait_texture(u)
	big.custom_minimum_size = Vector2(64, 64)
	big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	big.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	head.add_child(big)
	var hi = VBoxContainer.new(); hi.add_theme_constant_override("separation", 2)
	hi.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(hi)
	var nm = Label.new(); nm.text = str(u.get("name", id)); nm.add_theme_font_size_override("font_size", 21)
	var rar = str(pet.get("rarity", u.get("rarity", "C")))
	nm.add_theme_color_override("font_color", battle._pet_rarity_color(rar)); hi.add_child(nm)
	var sub = Label.new()
	sub.text = "%s · %s · Lv %d" % ["友军" if is_left else "敌方", rar, int(u.get("level", 1))]
	sub.add_theme_font_size_override("font_size", 13); sub.add_theme_color_override("font_color", side_col); hi.add_child(sub)
	# ★不再放 ✖ 按钮(用户 2026-07-21:「点空白处就直接退出信息面板, 不要那个×」)。
	#   关闭走两条: ①点面板外空白(_unhandled_input) ②ESC。面板本身 MOUSE_FILTER_STOP,
	#   所以点在面板【内】不会误关。

	# HP 条(阵营色)
	var _hpref: Array = battle._info_sys._info_bar(vb, float(u.get("hp", 0.0)), float(u.get("maxHp", 1.0)), side_col, "HP  %d / %d" % [int(u.get("hp", 0)), int(u.get("maxHp", 0))])
	battle._info_hp_bar = _hpref[0]; battle._info_hp_lbl = _hpref[1]
	# 龟能条(有主动技才显): 主技充能% = 1 − 剩余冷却/满冷却
	var acts: Array = u.get("active_skills", [])
	if not battle._is_passive_pick(u) and acts.size() > 0:
		var st0 = str(acts[0])
		var mxcd = battle._skill_cd(u, st0)
		var cd = float((u.get("skill_cd", {}) as Dictionary).get(st0, mxcd))
		var rdy = CombatMath.cooldown_ready(cd, mxcd)
		var _enref: Array = battle._info_sys._info_bar(vb, rdy, 1.0, Color("#ffce4d"), "龟能  %d%%" % int(rdy * 100.0))
		battle._info_en_bar = _enref[0]; battle._info_en_lbl = _enref[1]

	battle._add_panel_sep(vb)

	# 属性格 (2列·图标)
	var grid = GridContainer.new(); grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18); grid.add_theme_constant_override("v_separation", 5)
	vb.add_child(grid)
	# ★属性行走 battle._info_sys._info_stat_rows() 单一事实源(建面板与每帧刷新同源, 不会漂移)。
	#   图标: 8项有真图标, 其余留空占位 —— 本项目已「全去emoji(根治绿块+跨平台一致)」。
	battle._info_stat_labels.clear()
	for row in battle._info_sys._info_stat_rows(u):
		var lb = battle._info_sys._info_stat_cell(grid, "", str(row[1]), row[2], str(row[0]))
		battle._info_stat_labels.append(lb)
	battle._info_stat_grid = grid

	battle._add_panel_sep(vb)

	# 当前状态 chips
	battle._add_section_title(vb, "当前状态")
	# ★状态 chips 也要实时(用户「面板里所有的数值需要实时变化」) —— 护盾/灼烧/眩晕
	#   在战斗中变得最频繁, 原来却是开面板那一刻建一次就再也不动。
	#   chips 【条目数会变】(状态来了又走), 只能整块重建, 所以单独存容器 + 节流重建。
	battle._info_status_box = VBoxContainer.new()
	battle._info_status_box.add_theme_constant_override("separation", 4)
	vb.add_child(battle._info_status_box)
	battle._info_sys._info_status_chips(battle._info_status_box, u)
	battle._info_status_sig = battle._status_signature(u)

	# 被动
	var passive: Dictionary = u.get("passive", {})
	if passive is Dictionary and not (passive as Dictionary).is_empty():
		battle._add_panel_sep(vb)
		battle._add_section_title(vb, "被动 · " + str(passive.get("name", "")))
		# ★走模板渲染: 把 {N:0.7*ATK} 这类占位符按【本龟当前属性】算成真数字
		# ★统一口径: 原来这里【写死取 desc(详细)】而技能段写死取 brief(缩略),
		#   同一个面板里两种口径 —— 现在都听 battle._skill_detail() 的。
		var _ptpl = battle.SkillText.text_of(passive, battle._skill_detail())
		var pdesc = battle._render._render_skill_text(_ptpl, u, passive)
		if pdesc != "":
			battle._info_passive_lbl = battle._add_body_text(vb, pdesc)
			battle._info_passive_tpl = _ptpl

	# 宝箱龟专属: 财宝值进度 + 已开出的战利品(用户2026-07-19"信息面板得显示当前累计的财宝值/当前抽取的装备和图标/专属装备的描述")
	if battle._is_chest_turtle(u):
		battle._add_panel_sep(vb)
		battle._info_sys._info_chest_section(vb, u)

	# 技能
	var skills = battle._info_sys._panel_skill_entries(u)
	if not skills.is_empty():
		battle._add_panel_sep(vb)
		battle._add_section_title(vb, "技能")
		# ★简明/详细开关(用户需求1 两级描述)。放在技能段上方 —— 它同时管被动段与技能段,
		#   但被动段在上面已经画完了, 放这里是为了【靠近文字最多的地方】, 手够得着。
		battle._add_detail_toggle(vb, u)
		battle._info_skill_lbls.clear()
		for sk in skills:
			battle._add_section_title(vb, "  " + str(sk["name"]), Color("#9fd0ff"), 14)
			if str(sk["desc"]) != "":
				var slb = battle._add_body_text(vb, str(sk["desc"]))
				# 存"模板原文+Label+技能字典" → 每帧按当前属性重渲染伤害数值
				battle._info_skill_lbls.append({"lbl": slb, "tpl": str(sk.get("tpl", "")), "sk": sk.get("sk", {})})

	# 装备 —— ★也纳入实时(用户「面板里所有的数值需要实时变化」, 我不该给它开例外)。
	#   战斗中装备会变: 财神招财临时升星、宝箱龟开出新装备。条目数/星级都会变 → 整块重建, 签名节流。
	battle._add_panel_sep(vb)
	var equips: Array = u.get("equips", [])
	battle._info_equip_box = VBoxContainer.new()
	battle._info_equip_box.add_theme_constant_override("separation", 4)
	vb.add_child(battle._info_equip_box)
	battle._fill_equip_section(battle._info_equip_box, u)
	battle._info_equip_sig = battle._equip_signature(u)

	battle._info_sys._info_passthrough(vb)   # 面板内非按钮控件透传触摸→ScrollContainer可滑(手机·用户2026-07-18「列表滑动考虑手机端」)

	# 从右滑入
	panel.offset_left += PW + 40.0; panel.offset_right += PW + 40.0
	var tw = battle._reg_tween()
	tw.tween_property(panel, "offset_left", -(PW + 16.0), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(panel, "offset_right", -16.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## 是不是宝箱龟(藏宝图被动会往 chest_treasures 里塞东西; 用 id 判定最稳)
