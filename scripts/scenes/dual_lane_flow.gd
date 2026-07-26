class_name DualLaneFlow
extends RefCounted
## 双路对战流程(呈现总览/放置/逐路推进/破蛋决胜/HUD)
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

# ── 场内放置阶段 (每战场开打前: 拖我方单位到你半场任意位置) ──
func _dl_is_present() -> bool:
	return battle._dl_state == "overview" or battle._dl_state == "preview" or battle._dl_state == "lane_settle"

func _dl_enter_present(mode: String) -> void:
	battle._dl_state = mode
	battle._dl_present_t = 0.0
	if is_instance_valid(battle._dl_go_btn): battle._dl_go_btn.visible = false
	if is_instance_valid(battle._dl_place_hint): battle._dl_place_hint.visible = false
	_dl_build_present_overlay(mode)
	# ★幕布淡入(用户 2026-07-21 要"更好的动画与展示效果")。原来是瞬间 battle.add_child 硬切。
	#   ★★必须用裸 battle.create_tween 而不是 battle._reg_tween: 换路时 _dl_clear_units 会 kill 掉
	#     全部 battle._sim_tweens, 跨路存活的过场动画会被连坐清掉(注册契约见文件头)。
	if battle._dl_present_root != null and is_instance_valid(battle._dl_present_root):
		battle._dl_present_root.modulate.a = 0.0
		var tw = battle.create_tween()
		tw.tween_property(battle._dl_present_root, "modulate:a", 1.0, 0.28) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _dl_present_advance() -> void:
	var mode = battle._dl_state
	_dl_clear_present_overlay()
	if mode == "overview":
		_dl_enter_present("preview")
	elif mode == "preview":
		_dl_build_lane_field()   # ★预览结束 → 此刻才真正加载本路战场(呈现期间战场为空, 无串场)
		battle._dl_state = "place"
		_dl_enter_place()
	elif mode == "lane_settle":
		_dl_lane_over(battle._dl_pending_loser)

func _dl_clear_present_overlay() -> void:
	# ★淡出再销毁(原来是瞬间 queue_free 硬切)。先摘掉引用, 免得淡出期间又被当成"当前幕"。
	#   同样用裸 battle.create_tween(见 _dl_enter_present 的说明)。
	if battle._dl_present_root != null and is_instance_valid(battle._dl_present_root):
		var old = battle._dl_present_root
		old.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 淡出期间不再吃点击
		var tw = battle.create_tween()
		tw.tween_property(old, "modulate:a", 0.0, 0.22) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_callback(old.queue_free)
	battle._dl_present_root = null

func _dl_spec_name(spec) -> String:
	if not (spec is Dictionary): return "?"
	if str(spec.get("kind", "")) == "minion" or spec.has("role"):
		return "精英小将" if bool(spec.get("elite", false)) else "小将"
	var id = str(spec.get("id", spec.get("kind", "")))
	return str(battle._data_by_id.get(id, {}).get("name", id))

func _dl_lane_specs(lane: String) -> Array:
	if lane == "final":
		return _dl_survivor_specs("left")
	if GameState == null: return []
	return GameState.get_dual_lineup().get(lane, [])

func _dl_foe_specs(lane: String) -> Array:
	if lane == "final":
		return _dl_survivor_specs("right")
	return battle._dual_foe_lane(lane)


func _dl_build_present_overlay(mode: String) -> void:
	_dl_clear_present_overlay()
	if battle._ui_layer == null: return
	var back = ColorRect.new()
	# 完全不透明整屏幕幕布 —— 呈现层是隔开上/下/终极战场的「幕」, 绝不透出后面的战场(用户2026-07-12: 就是为了避免上下战场串东西)
	back.color = Color(0.03, 0.05, 0.09, 1.0)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	back.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: _dl_present_advance())
	battle._ui_layer.add_child(back)
	battle._dl_present_root = back
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.add_child(center)
	var panel = PanelContainer.new()
	# 撑大呈现面板(用户2026-07-12「预览这么小」), 但按视口收口 ——
	#   原来死写 980x560, 窄屏(手机竖屏/小窗)直接顶出屏幕外, 卡片被裁掉看不全。
	var _vp: Vector2 = battle.get_viewport().get_visible_rect().size   # ★Node3D 没有 get_viewport_rect()
	panel.custom_minimum_size = Vector2(minf(980.0, _vp.x - 48.0), minf(560.0, _vp.y - 48.0))
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.09, 0.14, 0.98); sb.border_color = Color("#ffd93d"); sb.set_border_width_all(3); sb.set_corner_radius_all(18)
	sb.content_margin_left = 46; sb.content_margin_right = 46; sb.content_margin_top = 36; sb.content_margin_bottom = 36
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var vb = VBoxContainer.new(); vb.add_theme_constant_override("separation", 24); vb.alignment = BoxContainer.ALIGNMENT_CENTER; panel.add_child(vb)
	var cur_lane = str(GameState.current_lane) if GameState != null else "top"
	var lane_cn: Dictionary = {"top": "上路", "bottom": "下路", "final": "终极", "done": "结算"}
	var title = Label.new()
	title.add_theme_font_size_override("font_size", 42); title.add_theme_color_override("font_color", Color("#ffd93d"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	if mode == "overview":
		title.text = "⚔  三路对阵总览"
		for ln in ["top", "bottom", "final"]:
			vb.add_child(_dl_overview_lane_row(ln, str(lane_cn.get(ln, ln))))
	elif mode == "preview":
		title.text = "【%s战场】 对阵预览" % lane_cn.get(cur_lane, cur_lane)
		vb.add_child(_dl_matchup_row(cur_lane))
	elif mode == "lane_settle":
		var win_lr = "right" if battle._dl_pending_loser == "left" else "left"
		title.text = "【%s战场】 结算" % lane_cn.get(cur_lane, cur_lane)
		var r = Label.new(); r.add_theme_font_size_override("font_size", 26)
		r.add_theme_color_override("font_color", Color("#9ae6b0") if win_lr == "left" else Color("#ff9b9b"))
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		r.text = "🏆 我方拿下本路！" if win_lr == "left" else "💀 本路失守"
		vb.add_child(r)
		var rec = Label.new(); rec.add_theme_font_size_override("font_size", 19); rec.add_theme_color_override("font_color", Color("#ffe9a8"))
		rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rec.text = _dl_record_line(cur_lane, win_lr)   # 带本路待记结果 → 赢上路即显1-0(record在5秒后才调)
		vb.add_child(rec)
		if GameState != null and GameState.egg_hp is Dictionary:
			var e = Label.new(); e.add_theme_font_size_override("font_size", 16); e.add_theme_color_override("font_color", Color("#cfe6ff"))
			e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			e.text = "蛋血  我方 %d  ·  对方 %d" % [int(GameState.egg_hp.get("left", 0.0)), int(GameState.egg_hp.get("right", 0.0))]
			vb.add_child(e)
	var hint = Label.new(); hint.add_theme_font_size_override("font_size", 13); hint.add_theme_color_override("font_color", Color("#7a8a96"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "（自动 5 秒 · 点击跳过）"
	vb.add_child(hint)
	_dl_stagger_in(vb)


## 幕布内容逐个弹入 (2026-07-21): 原本整块一次性出现, 信息一股脑砸脸上。
##   ★只能 tween alpha/scale —— 这些是 VBoxContainer 的子项, position 由布局接管, tween 它会被布局覆盖回去。
##   ★不能过 battle._reg_tween(): 后者会进 battle._sim_tweens, 而 _dl_clear_units() 换路时会把 battle._sim_tweens
##     全 kill 掉 —— 跨路的幕布动画会被连坐杀掉。
func _dl_stagger_in(vb: VBoxContainer) -> void:
	var i = 0
	for c in vb.get_children():
		var ctrl = c as Control
		if ctrl == null:
			continue
		ctrl.modulate.a = 0.0
		# pivot 要等布局算出 size 才能定 —— 这里 size 还是 0, 直接乘会把轴心钉在左上角,
		#   缩放就变成"从左边长出来"而不是原地弹。挂 resized 一次性回调。
		var _c = ctrl
		_c.resized.connect(func() -> void: _c.pivot_offset = _c.size * 0.5, CONNECT_ONE_SHOT)
		ctrl.scale = Vector2(0.88, 0.88)
		# tween 绑在 ctrl 上而不是场景上: 幕布被提前点掉时随节点一起销毁, 不会对着已释放的目标报错。
		var tw = ctrl.create_tween()
		tw.tween_interval(0.07 * float(i))
		tw.tween_property(ctrl, "modulate:a", 1.0, 0.16)
		tw.parallel().tween_property(ctrl, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1

# 本场分路比分行: "本场比分  我方 X - Y 对方".
#   extra_lane/extra_winner: 结算幕布显示时本路结果尚未 record(record在5秒后的lane_over才调) → 传入待记结果, 让「赢上路→显1-0」而非0-0(用户2026-07-12).
# 本场分路比分行: "本场比分  我方 X - Y 对方".
#   extra_lane/extra_winner: 结算幕布显示时本路结果尚未 record(record在5秒后的lane_over才调) → 传入待记结果, 让「赢上路→显1-0」而非0-0(用户2026-07-12).
func _dl_record_line(extra_lane: String = "", extra_winner: String = "") -> String:
	var lw = 0; var rw = 0
	var seen = {}
	if GameState != null and GameState.lane_results is Dictionary:
		for k in GameState.lane_results.keys():
			seen[k] = true
			if str(GameState.lane_results[k]) == "left": lw += 1
			else: rw += 1
	if extra_lane != "" and not seen.has(extra_lane):   # 补上本路待记结果(结算幕布用)
		if extra_winner == "left": lw += 1
		else: rw += 1
	return "本场比分   我方 %d - %d 对方" % [lw, rw]

# 对阵预览一行: [我方阵容列]  VS  [对方阵容列] (各带头像/等级/名字/装备图+星级)
# 对阵预览一行: [我方阵容列]  VS  [对方阵容列] (各带头像/等级/名字/装备图+星级)
func _dl_matchup_row(lane: String) -> Control:
	var row = HBoxContainer.new(); row.add_theme_constant_override("separation", 44); row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_dl_side_column(_dl_lane_specs(lane), true, "我方", Color("#9ae6b0")))
	var vs = Label.new(); vs.text = "VS"; vs.add_theme_font_size_override("font_size", 56); vs.add_theme_color_override("font_color", Color("#ffd93d")); vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(vs)
	row.add_child(_dl_side_column(_dl_foe_specs(lane), false, "对方", Color("#ff9b9b")))
	return row

# 总览一路: 【上路】 [我方小头像…] vs [对方小头像…]
# 总览一路: 【上路】 [我方小头像…] vs [对方小头像…]
func _dl_overview_lane_row(lane: String, cn: String) -> Control:
	var row = HBoxContainer.new(); row.add_theme_constant_override("separation", 18); row.alignment = BoxContainer.ALIGNMENT_CENTER
	var tag = Label.new(); tag.text = "【%s】" % cn; tag.add_theme_font_size_override("font_size", 26); tag.add_theme_color_override("font_color", Color("#cfe6ff"))
	tag.custom_minimum_size = Vector2(108, 0); row.add_child(tag)
	if lane == "final":
		var fl = Label.new(); fl.text = "上下路幸存者对决"; fl.add_theme_font_size_override("font_size", 22); fl.add_theme_color_override("font_color", Color("#9fb4c8"))
		row.add_child(fl)
		return row
	row.add_child(_dl_mini_avatars(_dl_lane_specs(lane)))
	var vs = Label.new(); vs.text = "vs"; vs.add_theme_font_size_override("font_size", 24); vs.add_theme_color_override("font_color", Color("#ffd93d")); row.add_child(vs)
	row.add_child(_dl_mini_avatars(_dl_foe_specs(lane)))
	return row

func _dl_mini_avatars(specs: Array) -> Control:
	var h = HBoxContainer.new(); h.add_theme_constant_override("separation", 6)
	for s in specs:
		h.add_child(_dl_avatar_node(s, 64))
	return h

# 一侧阵容列: 标题 + 逐单位卡片
# 一侧阵容列: 标题 + 逐单位卡片
func _dl_side_column(specs: Array, is_mine: bool, header: String, col: Color) -> Control:
	var vb = VBoxContainer.new(); vb.add_theme_constant_override("separation", 14); vb.alignment = BoxContainer.ALIGNMENT_CENTER
	var h = Label.new(); h.text = header; h.add_theme_font_size_override("font_size", 26); h.add_theme_color_override("font_color", col); h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(h)
	if specs.is_empty():
		var em = Label.new(); em.text = "—"; em.add_theme_color_override("font_color", Color("#7a8a96")); vb.add_child(em)
	for s in specs:
		vb.add_child(_dl_unit_card(s, is_mine))
	return vb

# 单位卡: [头像(稀有度描边)] [名字 / Lv] + 装备图标行(带★星级)
# 单位卡: [头像(稀有度描边)] [名字 / Lv] + 装备图标行(带★星级)
func _dl_unit_card(spec, is_mine: bool) -> Control:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(320, 0)
	var csb = StyleBoxFlat.new(); csb.bg_color = Color(0.08, 0.12, 0.18, 0.9); csb.set_corner_radius_all(10)
	csb.set_border_width_all(1); csb.border_color = Color(1, 1, 1, 0.08)
	csb.content_margin_left = 12; csb.content_margin_right = 16; csb.content_margin_top = 9; csb.content_margin_bottom = 9
	card.add_theme_stylebox_override("panel", csb)
	var hb = HBoxContainer.new(); hb.add_theme_constant_override("separation", 14); card.add_child(hb)
	hb.add_child(_dl_avatar_node(spec, 84))
	var info = VBoxContainer.new(); info.add_theme_constant_override("separation", 5); info.alignment = BoxContainer.ALIGNMENT_CENTER; hb.add_child(info)
	var nr = HBoxContainer.new(); nr.add_theme_constant_override("separation", 10); info.add_child(nr)
	var nm = Label.new(); nm.text = _dl_spec_name(spec); nm.add_theme_font_size_override("font_size", 24); nm.add_theme_color_override("font_color", Color("#e6edf3"))
	nr.add_child(nm)
	var lvl = 1
	if GameState != null and GameState.season_level != null: lvl = maxi(1, int(GameState.season_level))
	var lv = Label.new(); lv.text = "Lv.%d" % lvl; lv.add_theme_font_size_override("font_size", 17); lv.add_theme_color_override("font_color", Color("#ffd93d")); lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nr.add_child(lv)
	var eqs = _dl_spec_equips(spec, is_mine)
	if not eqs.is_empty():
		var er = HBoxContainer.new(); er.add_theme_constant_override("separation", 4)
		for e in eqs:
			if e is Dictionary:
				er.add_child(_dl_equip_chip(str(e.get("id", "")), int(e.get("star", 1))))
		info.add_child(er)
	else:
		var ne = Label.new(); ne.text = "（无装备）"; ne.add_theme_font_size_override("font_size", 15); ne.add_theme_color_override("font_color", Color("#5f6f7c")); info.add_child(ne)
	return card

# 头像节点(稀有度描边). spec 为 leader→avatars/<id>.png; minion→pets/minion.png
# 头像节点(稀有度描边). spec 为 leader→avatars/<id>.png; minion→pets/minion.png
func _dl_avatar_node(spec, sz: int) -> Control:
	var box = Panel.new(); box.custom_minimum_size = Vector2(sz, sz)
	var bsb = StyleBoxFlat.new(); bsb.bg_color = Color("#0c141c"); bsb.set_border_width_all(2); bsb.set_corner_radius_all(6)
	var id = ""
	var is_minion = false
	if spec is Dictionary:
		if str(spec.get("kind", "")) == "minion" or spec.has("role"): is_minion = true
		else: id = str(spec.get("id", spec.get("kind", "")))
	bsb.border_color = Color("#8b949e") if is_minion else battle._pet_rarity_color(str(battle._data_by_id.get(id, {}).get("rarity", "C")))
	box.add_theme_stylebox_override("panel", bsb)
	var path = (battle.SPRITE_DIR + "pets/minion.png") if is_minion else (battle.SPRITE_DIR + "avatars/" + id + ".png")
	if not ResourceLoader.exists(path) and not is_minion:
		path = battle.SPRITE_DIR + "pets/" + id + ".png"   # 无头像退回全身图
	if ResourceLoader.exists(path):
		var tex = TextureRect.new(); tex.texture = load(path)
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.offset_left = 3; tex.offset_top = 3; tex.offset_right = -3; tex.offset_bottom = -3
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		box.add_child(tex)
	return box

# 装备小图标(稀有度描边 + 右下★星级)
# 装备小图标(稀有度描边 + 右下★星级)
func _dl_equip_chip(eid: String, star: int) -> Control:
	var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
	var box = Panel.new(); box.custom_minimum_size = Vector2(44, 44)
	var bsb = StyleBoxFlat.new(); bsb.bg_color = Color("#0c141c"); bsb.set_border_width_all(2); bsb.set_corner_radius_all(4)
	bsb.border_color = battle._equip_cost_color(int(edef.get("cost", 1)))
	box.add_theme_stylebox_override("panel", bsb)
	box.tooltip_text = "%s  ★%d\n%s" % [str(edef.get("name", eid)), star, str(edef.get("effectDesc1", ""))]
	var img = str(edef.get("img", ""))
	if img != "" and ResourceLoader.exists("res://assets/sprites/" + img):
		var ic = TextureRect.new(); ic.texture = load("res://assets/sprites/" + img)
		ic.set_anchors_preset(Control.PRESET_FULL_RECT)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(ic)
	else:
		var em = Label.new(); em.text = str(edef.get("emoji", "?")); em.set_anchors_preset(Control.PRESET_FULL_RECT)
		em.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; em.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		em.add_theme_font_size_override("font_size", 11); em.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(em)
	var st = Label.new(); st.text = "★%d" % star
	st.anchor_left = 0.0; st.anchor_top = 1.0; st.anchor_right = 1.0; st.anchor_bottom = 1.0; st.offset_top = -16
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_theme_font_size_override("font_size", 13); st.add_theme_color_override("font_color", Color("#ffd93d"))
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(st)
	return box

# 单位装备解析(与 battle._inject_equipment 同口径): spec.equips 优先, 否则我方读 persistent_equipped
# 单位装备解析(与 battle._inject_equipment 同口径): spec.equips 优先, 否则我方读 persistent_equipped
func _dl_spec_equips(spec, is_mine: bool) -> Array:
	if not (spec is Dictionary): return []
	if spec.has("equips") and spec["equips"] is Array:
		return spec["equips"]
	if is_mine and str(spec.get("kind", "")) == "leader":
		var id = str(spec.get("id", ""))
		if GameState != null and GameState.get("persistent_equipped") is Dictionary:
			var pe: Dictionary = GameState.persistent_equipped
			if pe.has(id) and pe[id] is Array:
				return pe[id]
	return []

func _dl_enter_place() -> void:
	if OS.has_environment("DL_AUTOFIGHT"):   # 测试开关: 跳过放置直接开打 (headless 跑通整局流程用)
		_dl_start_fight()
		return
	battle._edit_drag_unit = null
	if not is_instance_valid(battle._dl_go_btn):
		battle._dl_go_btn = Button.new()
		battle._dl_go_btn.text = "▶  开  打"
		battle._dl_go_btn.add_theme_font_size_override("font_size", 28)
		battle._dl_go_btn.custom_minimum_size = Vector2(220, 62)
		battle._dl_go_btn.pressed.connect(_dl_start_fight)
		if battle._ui_layer != null:
			battle._ui_layer.add_child(battle._dl_go_btn)
	if not is_instance_valid(battle._dl_place_hint):
		battle._dl_place_hint = Label.new()
		battle._dl_place_hint.add_theme_font_size_override("font_size", 16)
		battle._dl_place_hint.add_theme_color_override("font_color", Color("#ffd93d"))
		battle._dl_place_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if battle._ui_layer != null:
			battle._ui_layer.add_child(battle._dl_place_hint)
	var vp: Vector2 = battle.get_viewport().get_visible_rect().size
	battle._dl_go_btn.position = Vector2(vp.x * 0.5 - 110.0, vp.y - 100.0)
	battle._dl_place_hint.position = Vector2(vp.x * 0.5 - 230.0, vp.y - 136.0)
	battle._dl_place_hint.size = Vector2(460, 24)
	battle._dl_place_hint.text = "【放置】拖我方单位到你半场(左侧)任意位置 → 点「开打」"
	battle._dl_go_btn.visible = true
	battle._dl_place_hint.visible = true
	# ★教学 match1: 摆位UI就绪 → 挂"place"引导(教站位), 只挂一次(首路; 别每路弹)。
	if not battle._tut_place_shown:
		var _tdp = battle.get_node_or_null("/root/TutorialDirector")
		if _tdp != null and _tdp.is_active() and str(_tdp.stage()) == "match1":
			battle._tut_place_shown = true
			battle._tutorial = _tdp.attach_guide(self, "battle")   # stage match1 → steps "place"

## 新手引导高亮锚点(用户2026-07-23 D): 摆位阶段用。名字→屏幕矩形; 解析不到返回空 Rect2(本步不挖洞)。
func _dl_start_fight() -> void:
	battle._sd_t0 = battle._t          # ★每个战场各自计时(battle._t 跨路累加, 见 §SUDDEN)
	battle._sd_stacks = 0
	for _tu in battle._units:   # 魔法石攻速叠层【本场结束重置】(§3.4: 按本场计, 不用全局_t) —— 每路开打清零
		if _tu.get("is_trainer", false):
			_tu["_ms_stacks"] = 0
	battle._edit_drag_unit = null
	battle._dl_state = "fight"
	if is_instance_valid(battle._dl_go_btn): battle._dl_go_btn.visible = false
	if is_instance_valid(battle._dl_place_hint): battle._dl_place_hint.visible = false
	_dl_fight_start_dramatize()


## 开打瞬间演出 (2026-07-21): 原本"点开打→什么都没有→单位就动了", 一段的开头没有落点。
##   做法对齐 _dl_wipe_dramatize(一段的结尾): 定格 + 震屏 + 闪屏 + 大字 + 两侧战线冲击环。
##   ★不要在这里做任何按 battle._t 计时的东西 —— battle._t 跨路累加, 见 §SUDDEN / battle._sd_t0。
func _dl_fight_start_dramatize() -> void:
	battle._add_hitstop(0.18)                                  # 短定格: 比团灭(0.30)短, 是"起势"不是"收势"
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	_dl_flash_screen(Color(1.0, 0.92, 0.55), 0.22)      # 淡金起手闪
	battle._vfx._float_text(battle._arena_center + Vector2(0.0, -120.0), "开 战", Color("#ffd93d"), true, "label")
	# 两侧战线各炸一圈, 强调"两边同时压上来"
	var half_w: float = battle.ARENA.size.x * 0.5
	var cy: float = battle._arena_center.y
	battle._splash_ring_bold(Vector2(battle._arena_center.x - half_w * 0.55, cy), Color(0.36, 0.66, 1.0), 150.0)
	battle._splash_ring_bold(Vector2(battle._arena_center.x + half_w * 0.55, cy), Color(1.0, 0.42, 0.42), 150.0)

func _dl_handle_place_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit = battle._edit_unit_at_screen(event.position)   # 只拖我方(left)非蛋非召唤
			if battle._can_place_drag(hit):
				battle._edit_drag_unit = hit
			else:
				battle._edit_drag_unit = null
		else:
			battle._edit_drag_unit = null
	elif event is InputEventMouseMotion and battle._edit_drag_unit != null:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			battle._edit_drag_unit = null
			return
		battle._edit_drag_unit["pos"] = _dl_clamp_place(battle._screen_to_field(event.position))

func _dl_clamp_place(fp: Vector2) -> Vector2:
	fp.x = clampf(fp.x, battle.ARENA.position.x + 60.0, battle._arena_center.x - 120.0)   # 只在我方半场(不越中线)
	fp.y = clampf(fp.y, battle.ARENA.position.y + 60.0, battle.ARENA.end.y - 60.0)
	for ob in battle._obstacles:   # 避开障碍footprint(椭圆内→推到边)
		var c: Vector2 = ob["c"]
		var rx: float = float(ob["rx"]) + battle.OBSTACLE_MARGIN
		var ry: float = float(ob["ry"]) + battle.OBSTACLE_MARGIN
		var d: Vector2 = fp - c
		var e: float = Vector2(d.x / rx, d.y / ry).length()
		if e < 1.0 and e > 0.01:
			fp = c + d / e
	return fp

# 真正加载本路战场: spawn 双方单位+蛋+地图+装备+被动+头像框. 仅在呈现(预览)结束后调用 → 呈现期间战场为空.
func _dl_build_lane_field() -> void:
	var lane: String = str(GameState.current_lane) if GameState != null and GameState.current_lane != null else "top"
	if lane == "" or lane == "done":
		lane = "top"
	var lvl: int = 1
	if GameState != null and GameState.season_level != null:
		lvl = maxi(1, int(GameState.season_level))
	var _cx = battle.ARENA.position.x + battle.ARENA.size.x * 0.5
	var _cy = battle.ARENA.position.y + battle.ARENA.size.y * 0.5
	var mine: Array
	var foe: Array
	if lane == "final":   # 终极: 上下路幸存(含小将, 带30%回血)对决
		mine = _dl_survivor_specs("left")
		foe = _dl_survivor_specs("right")
	else:
		mine = GameState.get_dual_lineup().get(lane, [])
		foe = battle._dual_foe_lane(lane)   # 确定性(读固定 ghost 快照/固定 bot 池) → 与预览显示一致
	battle._spawn_lane_side(mine, "left", lvl, Vector2(_cx - 420.0, _cy))
	battle._spawn_lane_side(foe, "right", lvl, Vector2(_cx + 420.0, _cy))
	# 两端基地各 spawn 一颗蛋(围栏罩住). egg_hp 跨路累积(缺则按平均等级初始化); hp_max=原始满血→血条显跨路累积伤害.
	_dl_ensure_egg_hp(lvl)
	var egg_max: float = 3000.0 + 300.0 * float(lvl)   # 蛋原始满血(用户2026-07-19: 2000+100/级 → 3000+300/级) = maxHp 基准
	battle._units.append(battle._make_unit("__egg__", "left", Vector2(battle.ARENA.position.x + 70.0, _cy), {"egg": true, "egg_side": "left", "hp": _dl_egg_hp("left"), "hp_max": egg_max}))
	battle._units.append(battle._make_unit("__egg__", "right", Vector2(battle.ARENA.end.x - 70.0, _cy), {"egg": true, "egg_side": "right", "hp": _dl_egg_hp("right"), "hp_max": egg_max}))
	battle._spawn_trainers()    # 双方场外监视者。★放在这里 = 每路 spawn 一次, 而 _dl_next_lane 会先
						 #   _dl_clear_units() 再重 spawn → 血量【天然每场重置】(用户要的), 不用另写重置逻辑。
						 #   另见 _dl_snapshot_survivors: 训龟大师不进幸存名单, 否则会带残血去终极战场+重复 spawn。
	battle._world_builder._build_map_props()   # 地图障碍(中央大礁+两侧墙)+基地穹顶围栏(幂等, 跨路复用)
	battle._world_builder._build_navmesh()     # 2D navmesh 避障(幂等; 障碍挖洞→单位绕行)
	# 装备+登场被动管线(评审流程走的 756-758, 双路早退绕过了→这里补上): leader读persistent_equipped+dual_lineup, 小将读dual_lineup._dl_equips, 双方leader上登场被动
	battle._inject_equipment()
	battle._apply_spawn_passives()
	battle._equip_sys._stats._eq_apply_all_stats()
	battle._build_team_panels()   # ★双路补建左右头像框(装备图标随之显示): 原只在非双路分支L1051调·双路早退绕过→装了装备头像框空白(用户2026-07-11 #5)

func _dl_ensure_egg_hp(lvl: int) -> void:   # egg_hp 缺则按 3000+300×平均等级 初始化(两侧·用户2026-07-19)
	if GameState == null:
		return
	if not (GameState.egg_hp is Dictionary):
		return
	for s in ["left", "right"]:
		if float(GameState.egg_hp.get(s, 0.0)) <= 0.0:
			GameState.egg_hp[s] = 3000.0 + 300.0 * float(lvl)

func _dl_egg_hp(side_lr: String) -> float:
	if GameState != null and GameState.egg_hp is Dictionary:
		return maxf(1.0, float(GameState.egg_hp.get(side_lr, 2100.0)))
	return 2100.0

# spawn 一路一侧: leaders 用 battle._make_unit(id); 小将用 minion spec; 0统领路首个小将=精英. 纵向排开.
# 终极战场我方/敌方阵容 = 上下路累加的幸存(含小将+30%回血). 缺则兜底.
func _dl_survivor_specs(side_lr: String) -> Array:
	if GameState != null and GameState.dual_survivors is Dictionary:
		var s: Array = GameState.dual_survivors.get(side_lr, [])
		if not s.is_empty():
			return s
	return [{"kind": "leader", "id": "basic"}]   # 兜底(理论不会到)

func _dl_side_alive(side: String) -> int:   # 一侧存活非蛋·非惰性召唤 单位数(战斗型召唤算数·用户2026-07-11 #3)
	var n = 0
	for u in battle._units:
		if not u.get("alive", false) or u.get("_isEgg", false) or (u.get("is_summon", false) and battle._DL_INERT_SUMMON.has(str(u.get("summon_kind", "")))):
			continue
		if u.get("is_trainer", false):
			continue   # 训龟大师不计团灭(用户: "训龟大师不算, 其实就是个场外监视者")
		# 赛博侵入被黑单位: 按【原阵营】计存活数(临时倒戈不算赛博方·也别把原阵营"抹空"→防提前判胜负)
		var _eff_side: String = str(u.get("_hijack_orig_side", u.get("side", ""))) if u.get("hijacked", false) else str(u.get("side", ""))
		if _eff_side == side:
			n += 1
	# 赛博机甲组装过渡(用户2026-07-18「组装期/召唤都算存活」): 本体死→机甲2.8s后才spawn, 中间空档若此侧其他单位也死会被误判团灭→提前开破蛋。此侧有机甲在路上(死亡演出→组装)就当还有1个存活, 桥接到机甲spawn。
	if n == 0 and battle._t < float(battle._mech_incoming.get(side, 0.0)):
		n = 1
	return n

# 该次团灭是否「定局路」= 终极路, 或上下路横扫(此路胜方=对方已赢另一路→整场2-0/0-2定负). 定局路给败蛋挂终极buff+无限窗口, 打碎蛋才结束(用户2026-07-12).
# 该次团灭是否「定局路」= 终极路, 或上下路横扫(此路胜方=对方已赢另一路→整场2-0/0-2定负). 定局路给败蛋挂终极buff+无限窗口, 打碎蛋才结束(用户2026-07-12).
func _dl_is_decider(wiped_side: String) -> bool:
	if GameState == null: return false
	var lane = str(GameState.current_lane)
	if lane == "final": return true
	if lane == "bottom" and GameState.lane_results is Dictionary:
		var winner = "right" if wiped_side == "left" else "left"   # 本路胜方
		return str(GameState.lane_results.get("top", "")) == winner   # 上路也是这方赢 → 横扫定局
	return false

## ★团灭瞬间的演出(用户 2026-07-21:「上半场结束/下半场结束…设计更好的动画与展示效果」)。
## 原来这一刻【只有基地穹顶塌缩 0.7s】—— 团灭这么大的事, 玩家只看到 HUD 多几个字。
## 这里全部复用项目已有的 juice helper, 不新造轮子:
##   顿帧 → 让"最后一个倒下"这一刻停住；震屏 → 冲击感；全屏闪 → 断章感；
##   大字 → 明确告诉玩家发生了什么(用 battle._vfx._float_text 的 label 模式, 决胜公告也是这么做的)。
## ★用裸 battle.create_tween 的地方见 _dl_enter_present 说明(跨路存活不能被 battle._sim_tweens 连坐清掉)。
func _dl_wipe_dramatize(wiped_lr: String) -> void:
	var we_lost: bool = (wiped_lr == "left")
	battle._add_hitstop(0.30)                     # 定格: 比普通击杀(0.05~0.12)长得多, 标记"这是一段的结束"
	battle._shake(battle.JUICE_SHAKE_BIG)
	# 全屏闪: 我方被团灭→暗红警示; 我方获胜→金色
	var col: Color = Color(0.85, 0.12, 0.16) if we_lost else Color(1.0, 0.82, 0.30)
	_dl_flash_screen(col, 0.34)
	# 全场大字
	var txt: String = "全军覆没" if we_lost else "敌军覆没"
	var tcol: Color = Color("#ff6b6b") if we_lost else Color("#ffd93d")
	battle._vfx._float_text(battle._arena_center + Vector2(0.0, -120.0), txt, tcol, true, "label")
	# 幸存方每个单位身上冒一记火花, 强调"是他们打完的"
	var survivor: String = "right" if we_lost else "left"
	for u in battle._units:
		if u.get("alive", false) and str(u.get("side", "")) == survivor and not u.get("_isEgg", false):
			battle._vfx._hit_spark(u)

## ★蛋破演出 —— 整场的最高潮, 原来却是【直接跳胜负横幅】, 零过场(横扫/终极路都走这条)。
## 比团灭更重: 更长的顿帧 + 最大震屏 + 蛋位置爆冲击环 + 全场大字。
func _dl_egg_break_dramatize(broken_side_lr: String) -> void:
	var we_lost: bool = (broken_side_lr == "left")
	battle._add_hitstop(0.45)                    # 比团灭(0.30)更长 —— 这是整场结束
	battle._shake(battle.JUICE_SHAKE_MAX)
	_dl_flash_screen(Color(1.0, 0.95, 0.85) if not we_lost else Color(0.9, 0.1, 0.12), 0.55)
	# 在破掉的那颗蛋的位置炸冲击环
	for u in battle._units:
		if u.get("_isEgg", false) and str(u.get("egg_side_lr", "")) == broken_side_lr:
			battle._splash_ring_bold(u.get("pos", battle._arena_center), Color(1.0, 0.85, 0.4, 0.95), 420.0)
			# ★贴图路径必须是真实存在的 —— battle._burst_vfx 里 load() 失败会静默 return, 什么都不显示。
			#   我第一版写了 explosion.png(不存在), 查目录才发现。
			battle._burst_vfx("res://assets/sprites/vfx/boom-wave-anim.png", u.get("pos", battle._arena_center), 260.0, 0.9)
			break
	var txt: String = "龟蛋破碎" if we_lost else "击碎敌蛋"
	battle._vfx._float_text(battle._arena_center + Vector2(0.0, -140.0), txt,
		Color("#ff5c5c") if we_lost else Color("#ffe680"), true, "label")

## 全屏一次性闪光(仿 _smolder_sys._smolder_flash 的写法; 用于段落切换)
func _dl_flash_screen(col: Color, dur: float) -> void:
	if battle._ui_layer == null or not is_instance_valid(battle._ui_layer):
		return
	var r = ColorRect.new()
	r.color = Color(col.r, col.g, col.b, 0.0)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle._ui_layer.add_child(r)
	var tw = battle.create_tween()
	tw.tween_property(r, "color:a", 0.34, dur * 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(r, "color:a", 0.0, dur * 0.82).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(r.queue_free)


func _dl_drop_fence(side_lr: String) -> void:   # 该方蛋围栏消失(可被自由索敌); 定局路(终极/横扫)暴露蛋挂 ×5承伤+自损
	var final_buff: bool = _dl_is_decider(side_lr)   # 定局路: 蛋挂×5+自损→快速打碎收尾(用户2026-07-12「将终极战场buff给到蛋上，打碎蛋再结束」)
	for u in battle._units:
		if u.get("_isEgg", false) and str(u.get("egg_side_lr", "")) == side_lr:
			u["_egg_fence"] = false
			u["def"] = maxf(0.0, float(u.get("def", 60.0)) - battle.EGG_FENCE_RES); u["mr"] = maxf(0.0, float(u.get("mr", 60.0)) - battle.EGG_FENCE_RES)   # 屏障消失→回落到 60+15×等级
			u["base_def"] = maxf(0.0, float(u.get("base_def", 60.0)) - battle.EGG_FENCE_RES); u["base_mr"] = maxf(0.0, float(u.get("base_mr", 60.0)) - battle.EGG_FENCE_RES)
			if final_buff:
				u["_egg_final"] = true                # ×5承伤(见 _apply_damage_from)
				u["_egg_selfloss_next"] = battle._t + battle.EGG_SELFLOSS_IV
	var dome = battle._base_domes.get(side_lr, null)   # 围栏消失: 穹顶塌缩淡出(蛋暴露)
	if is_instance_valid(dome):
		battle._reg_tween().tween_property(dome, "scale", Vector3(0.02, 0.02, 0.02), 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

func _dl_flow_check() -> void:
	if battle._over or battle._dl_state == "done":
		return
	# 终极暴露蛋自损: 每 1 秒 5% maxHp (用户2026-07-19: 原每2.5秒25% = 10%/秒 → 现 5%/秒)
	for u in battle._units:
		if u.get("_egg_final", false) and u.get("alive", false) and battle._t >= float(u.get("_egg_selfloss_next", 1.0e18)):
			u["_egg_selfloss_next"] = battle._t + battle.EGG_SELFLOSS_IV
			battle._apply_damage(u, maxi(1, int(round(u["maxHp"] * battle.EGG_SELFLOSS_PCT))), Color(UIPalette.TRUE_DMG), null, "tru", true)   # 自损=真伤 → 白(跟「真实=白」惯例·用户2026-07-24; 原 #ff9a9a 粉)
	# 蛋血同步回 GameState + 蛋破判负(谁蛋先破谁输)
	for u in battle._units:
		if u.get("_isEgg", false):
			var es = str(u.get("egg_side_lr", "left"))
			if GameState != null and GameState.egg_hp is Dictionary:
				GameState.egg_hp[es] = maxf(0.0, float(u["hp"]))
			if not u.get("alive", true):
				# 定局路走蛋破结束, 跳过了 _dl_lane_over 的 record_lane_result → 这里补记本路结果, 整场比分才对(碎蛋方的对手赢本路)
				if GameState != null and GameState.lane_results is Dictionary:
					var _ln = str(GameState.current_lane)
					if _ln != "" and _ln != "done" and not GameState.lane_results.has(_ln):
						GameState.lane_results[_ln] = ("right" if es == "left" else "left")
				_dl_egg_break_dramatize(es)   # ★蛋破演出(原来是直接跳胜负横幅, 整场最高潮却零过场)
				_dl_finish(es == "right")   # 蛋破=立即结束整场(用户2026-07-12「蛋被打碎立马结束」); 右蛋破→我方(左)赢
				return
	var la = _dl_side_alive("left")
	var ra = _dl_side_alive("right")
	if battle._dl_state == "fight":
		if la == 0 or ra == 0:
			battle._dl_wiped_side = "left" if la == 0 else "right"
			_dl_wipe_dramatize(battle._dl_wiped_side)   # ★团灭演出(原来这一刻只有穹顶塌缩, 毫无冲击力)
			_dl_drop_fence(battle._dl_wiped_side)   # 内部按定局判定给蛋挂终极buff(×5承伤+自损)
			var decider: bool = _dl_is_decider(battle._dl_wiped_side)   # 终极路 或 横扫定胜负那一路 = 定局路
			battle._dl_window_until = (1.0e18 if decider else battle._t + 10.0)   # 定局→无限(打碎蛋才结束·自损保证≤10s必碎); 非定局→10s累计后本路结束
			battle._dl_state = "eggwindow"
			if OS.has_environment("XDBG"): print("XDBG_DL wiped=", battle._dl_wiped_side, " decider=", decider, " t=", battle._t, " → eggwindow")
	elif battle._dl_state == "eggwindow":
		if battle._t >= battle._dl_window_until:
			battle._dl_pending_loser = battle._dl_wiped_side
			_dl_enter_present("lane_settle")   # 结算5秒→再推进(用户2026-07-12)

# P5: 本路结束 → 记录胜方 + 幸存snapshot(30%回血,供终极) + 推进 top→bottom→final/done
# P5: 本路结束 → 记录胜方 + 幸存snapshot(30%回血,供终极) + 推进 top→bottom→final/done
func _dl_lane_over(loser_side: String) -> void:
	if battle._over:
		return
	var winner_lr = "right" if loser_side == "left" else "left"
	var lane = str(GameState.current_lane) if GameState != null else "top"
	_dl_snapshot_survivors()          # 上下路幸存(含小将)累加, 回30%血 → 终极战场用
	if GameState != null:
		GameState.record_lane_result(winner_lr)   # 内部推进 current_lane (top→bottom→final→done)
	var next_lane = str(GameState.current_lane) if GameState != null else "done"
	if OS.has_environment("XDBG"): print("XDBG_DL lane '", lane, "' over, winner=", winner_lr, " → next=", next_lane)
	# 整场结束? (done, 或 2-0 横扫无需终极)
	if next_lane == "done":
		_dl_finish(_dl_overall_won())
		return
	if next_lane == "final" and GameState != null and not GameState.dual_lane_needs_final():
		_dl_finish(_dl_overall_won())   # 2-0 横扫
		return
	_dl_next_lane(lane)               # 清场重开下一路(bottom/final); 传本路名 → 清场前先存统计快照

func _dl_overall_won() -> bool:
	if GameState == null:
		return false
	return str(GameState.dual_lane_winner()) == "left"

# 幸存快照: 上下路存活的 leaders+小将(非蛋非召唤) 回30%已损血, 累加进 dual_survivors(供终极)
# 幸存快照: 上下路存活的 leaders+小将(非蛋非召唤) 回30%已损血, 累加进 dual_survivors(供终极)
func _dl_snapshot_survivors() -> void:
	if GameState == null or not (GameState.dual_survivors is Dictionary):
		return
	for side in ["left", "right"]:
		var cur: Array = GameState.dual_survivors.get(side, [])
		for u in battle._units:
			if not u.get("alive", false) or str(u.get("side", "")) != side:
				continue
			if u.get("_isEgg", false) or u.get("is_summon", false):
				continue
			if u.get("is_trainer", false):
				continue   # ★不进幸存名单: 进了会带着残血去终极战场(用户要每场重置), 还会被重复 spawn
			var healed: float = minf(u["maxHp"], u["hp"] + (u["maxHp"] - u["hp"]) * 0.30)
			var spec = {"hp_frac": clampf(healed / maxf(1.0, u["maxHp"]), 0.05, 1.0)}
			if u.get("_isMinion", false):
				spec["kind"] = "minion"; spec["role"] = str(u.get("minion_role", "front")); spec["elite"] = bool(u.get("is_elite", false))
			else:
				spec["kind"] = "leader"; spec["id"] = str(u.get("id", "basic"))
			var eq: Array = u.get("equips", [])   # ★带装备进终极战场(用户2026-07-18"到终极战场装备都消失了"): 原survivor spec漏拷equips→_spawn_lane_side走不到_dl_equips→_inject只兜底左leader base装→小将/敌leader/局内获取装全空. 拷equips后双方leader+小将+局内装全带入
			if eq is Array and not (eq as Array).is_empty():
				spec["equips"] = (eq as Array).duplicate(true)
			cur.append(spec)
		GameState.dual_survivors[side] = cur

# 清当前路所有单位/弹道/特效节点 → 供重开下一路
func _dl_clear_units() -> void:
	for u in battle._units:
		for k in ["sprite", "shadow", "contact", "ring", "flame_sector"]:   # +flame_sector: 凤凰喷火扇形常驻MeshInstance3D·换路不清会残留下半场(用户2026-07-18"换到下半场没清掉")
			var n = u.get(k, null)
			if is_instance_valid(n):
				n.queue_free()
		var br = u.get("bar_root", null)
		if is_instance_valid(br):
			br.queue_free()
	battle._units.clear()
	for pr in battle._projectiles:
		var pn = pr.get("node", null)
		if is_instance_valid(pn):
			pn.queue_free()
	battle._projectiles.clear()
	battle._pending_shots.clear()
	for f in battle._follow_vfx:
		var fs = f.get("spr", null)
		if is_instance_valid(fs):
			fs.queue_free()
	battle._follow_vfx.clear()
	for z in battle._lava_sys._lava_zones:                     # 补清: 岩浆池(用户2026-07-12"回合间没清")
		var zd = z.get("disc", null)
		if is_instance_valid(zd): zd.queue_free()
	battle._lava_sys._lava_zones.clear()
	battle._glacier_zones.clear()                    # 补清: 冰川带(换路/清场不残留)
	for lk in battle._ink_links:                     # 补清: 墨迹连线
		var ls = lk.get("spr", null)
		if is_instance_valid(ls): ls.queue_free()
	battle._ink_links.clear()
	# ★换路彻底清场(用户2026-07-12「10秒到buff要立马清, 很多技能同理要清场」):
	#   per-unit 状态(流血/DoT/buff/护盾/眩晕/减速等) 随上面 battle._units 释放已清, 下一路单位全新 dots:[]/buffs:[] —— 不跨路带.
	#   下面补清【全局残留】: 时停 + 被时停暂停的tween/粒子 + 时之主光辉 + 所有VFX tween + 飘字错峰窗口, 保证下一路干净起步.
	if not battle._timestop._ts_active.is_empty() or battle._timestop._ts_remaining > 0.0:
		battle._timestop._ts_resume_freeze()                   # 时停未结束→先恢复被暂停的tween/粒子(否则卡死进下一路)
	battle._timestop._ts_active.clear(); battle._timestop._ts_remaining = 0.0
	battle._timestop._ts_charge_casters.clear(); battle._timestop._ts_frozen_tweens.clear(); battle._timestop._ts_frozen_particles.clear()
	if is_instance_valid(battle._timestop._ts_overlay): battle._timestop._ts_overlay.visible = false
	if is_instance_valid(battle._timestop._ts_flash_overlay): battle._timestop._ts_flash_overlay.visible = false
	for g in battle._timestop._ts_glow_sprs:
		if is_instance_valid(g): g.queue_free()
	battle._timestop._ts_glow_sprs.clear()
	for tw in battle._sim_tweens:                    # 杀掉所有在跑的VFX tween(斩弧/曳光/召唤动画等), 别续进下一路
		if tw != null and tw.is_valid(): tw.kill()
	battle._sim_tweens.clear()
	battle._float_dmg_window.clear(); battle._float_nd_window.clear(); battle._float_merge.clear()
	# ★换路残留特效彻底清场(用户2026-07-19"上半→下半/终极 很多特效都没有清理"):
	#   绝大多数VFX的 queue_free 是挂在 tween 的【最后一个 callback】上的, 而上面 tw.kill()
	#   一杀, 那个 callback 就永远不会执行 → 精灵永久留在 _world 里跨路残留。
	#   这里按建场快照兜底: 凡不在常驻集内的 _world 子节点一律释放。
	var _swept = battle._sweep_world_vfx()
	if OS.has_environment("XDBG"): print("XDBG_DL 换路清扫遗留节点: ", _swept)
	_dl_clear_present_overlay()

func _dl_next_lane(finished_lane: String = "") -> void:
	battle._st_snapshot_lane(finished_lane)   # ★必须在 _dl_clear_units 之前: 清场后 battle._units 就空了
	_dl_clear_units()
	battle._over = false
	battle._dl_state = ""
	battle._dl_wiped_side = ""
	battle._spawn_dual_lane()   # 读推进后的 current_lane; final 从幸存 spawn

func _dl_finish(won: bool) -> void:
	if battle._over:
		return
	if OS.has_environment("XDBG"): print("XDBG_DL finish won=", won, " t=", battle._t, " egg_hp=", (GameState.egg_hp if GameState != null else {}))
	battle._over = true
	battle._dl_state = "done"
	battle._settle_season(won)    # 结果喂赛季(命/币/胜场/XP/糖果罐/ghost上传), 守卫一次性
	battle._show_banner(won)

func _dl_update_hud() -> void:   # 双路 HUD: 当前路 + 双方蛋血 + 破蛋窗口计时
	var lane = str(GameState.current_lane) if GameState != null else "top"
	var lane_cn: String = {"top": "上半场", "bottom": "下半场", "final": "终极战场", "done": "结算"}.get(lane, lane)
	var lhp = 0
	var rhp = 0
	for u in battle._units:
		if u.get("_isEgg", false):
			if str(u.get("egg_side_lr", "")) == "left":
				lhp = int(u["hp"])
			else:
				rhp = int(u["hp"])
	var st = ""
	if battle._dl_state == "eggwindow":
		var rem = battle._dl_window_until - battle._t
		st = ("  ·  破蛋窗口 %.0fs" % maxf(0.0, rem)) if rem < 1.0e17 else "  ·  破蛋(决胜)"
	if battle._sd_stacks > 0:   # §SUDDEN 决胜档位: 不显玩家会莫名其妙"怎么突然打得动了/奶不住了"
		st += "  ·  ⚔决胜 +%d%%增伤 · 治疗-50%%" % int(battle._sd_amp() * 100.0)
	battle._dl_hud.text = "【%s】   我方蛋 %d   vs   敌方蛋 %d%s" % [lane_cn, lhp, rhp, st]

## 匹配对手快照的首领 id (Matchmaking 写 GameState.dual_ghost). 过滤到 STATS 已知龟, 上限 3.
