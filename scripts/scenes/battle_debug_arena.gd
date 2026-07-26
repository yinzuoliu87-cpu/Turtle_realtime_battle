class_name BattleDebugArena
extends RefCounted
## 调试场(DEBUG_EDIT: 摆兵/配装/拖拽/满龟能/大师技·dev-only)
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

func _edit_handle_mouse_button(ev: InputEventMouseButton) -> void:
	var screen = ev.position
	if ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		# 右键删除最近单位
		var hit = battle._edit_unit_at_screen(screen)
		if hit != null:
			_edit_delete_unit(hit)
			_edit_set_status("删除了 1 个单位 (剩 %d)" % battle._units.size())
		return
	if ev.button_index != MOUSE_BUTTON_LEFT:
		return
	if ev.pressed:
		# 按下: 若命中已有单位 → 准备拖拽; 否则记录, 松手时摆放.
		battle._edit_drag_moved = false
		battle._edit_drag_unit = battle._edit_unit_at_screen(screen)
	else:
		# 松手: 拖拽了 → 已实时挪好, 不再摆放; 否则点空地 → 摆放新单位.
		if battle._edit_drag_unit != null:
			if not battle._edit_drag_moved:
				_edit_select_unit(battle._edit_drag_unit)   # 单击已有单位(没拖动) → 选中配装(用户2026-07-12)
		else:
			var fp = battle._screen_to_field(screen)
			fp.x = clampf(fp.x, battle.ARENA.position.x, battle.ARENA.end.x)
			fp.y = clampf(fp.y, battle.ARENA.position.y, battle.ARENA.end.y)
			_edit_place_unit(battle._edit_pick_id, battle._edit_pick_side, fp)
		battle._edit_drag_unit = null
		battle._edit_drag_moved = false

func _edit_handle_mouse_motion(ev: InputEventMouseMotion) -> void:
	if battle._edit_drag_unit == null:
		return
	if not (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		battle._edit_drag_unit = null
		return
	battle._edit_drag_moved = true
	var fp = battle._screen_to_field(ev.position)
	fp.x = clampf(fp.x, battle.ARENA.position.x, battle.ARENA.end.x)
	fp.y = clampf(fp.y, battle.ARENA.position.y, battle.ARENA.end.y)
	battle._edit_drag_unit["pos"] = fp   # transforms/overlay 下一帧自动跟到新位置

# 摆放一个单位: 复用 battle._spawn._make_unit, 右队按调试场设置改成假人 (不动/不打/可设血/可不死).
# 摆放一个单位: 复用 battle._spawn._make_unit, 右队按调试场设置改成假人 (不动/不打/可设血/可不死).
func _edit_place_unit(id: String, side: String, pos: Vector2) -> Dictionary:
	var u: Dictionary
	# ★训龟大师(用户2026-07-24): 调试场【自由摆位】, 不走正式对局"蛋后上方"那套站位(调试场没蛋)。
	if id == battle.TRAINER_ID:
		u = battle._spawn._make_unit(battle.TRAINER_ID, side, pos, {"trainer": true})
		u["_tr_active"] = battle._valid_active(battle._edit_trainer_active)
		u["_tr_passive"] = ""
		battle._units.append(u)
		if str(side) == "left":
			battle._hud._build_spell_disc()   # 我方大师 → 建法术圆盘(按 Q / 点盘 放主动)
		_edit_set_status("摆放 训龟大师·%s (%s) · 我方按 Q 放/敌方自动放 · 共 %d 单位" % [
			str(battle.TRAINER_SKILLS.get(battle._edit_trainer_active, {}).get("name", battle._edit_trainer_active)),
			("友军" if side == "left" else "敌方"), battle._units.size()])
		return u
	if id == "__minion__":   # 调试场摆小将: front=近战浪板 / back=远程火箭 / elite=精英(用户2026-07-24 补精英)
		var _mlvl = maxi(1, int(battle._edit_dummy_hp / 300.0))
		var _elite: bool = (battle._edit_minion_role == "elite")
		var _spec: Dictionary = {"minion": true, "elite": _elite, "level": _mlvl}
		if not _elite: _spec["role"] = battle._edit_minion_role   # 精英不分前后排(独立造型)
		u = battle._spawn._make_unit("__minion__", side, pos, _spec)
		u["_edit_minion_role"] = battle._edit_minion_role   # 存角色/等级→⏸编辑重生/存盘时按此重建(否则小将退化成默认龟)
		u["_edit_minion_lvl"] = _mlvl
	else:
		u = battle._spawn._make_unit(id, side, pos)
	if side == "right":
		u["no_basic"] = true
		u["no_move"] = true
		u["active_skills"] = []
		u["maxHp"] = battle._edit_dummy_hp
		u["hp"] = u["maxHp"]
		if not battle._edit_dummy_killable:
			u["_review_dummy"] = true   # 不死沙包(受击回满)
	elif battle._edit_full_energy:
		_edit_apply_full_energy(u)      # 友军: 满龟能开→技能即就绪+快速回充
	battle._units.append(u)
	var _pn: String = str(battle._data_by_id.get(id, {}).get("name", id))
	if id == "__minion__":
		_pn = {"front": "近战小将·浪板", "back": "远程小将·火箭", "elite": "精英小将"}.get(battle._edit_minion_role, "小将")
	_edit_set_status("摆放 %s (%s) · 共 %d 单位" % [_pn, ("友军" if side == "left" else "假人"), battle._units.size()])
	return u

# 释放一个单位的全部 3D 节点 + 血条 overlay, 并从 battle._units 移除.
# 释放一个单位的全部 3D 节点 + 血条 overlay, 并从 battle._units 移除.
func _edit_free_unit_nodes(u: Dictionary) -> void:
	for k in ["sprite", "shadow", "ring", "contact"]:
		var n = u.get(k, null)
		if is_instance_valid(n):
			n.queue_free()
	var br = u.get("bar_root", null)
	if is_instance_valid(br):
		br.queue_free()
	# 召唤体/投射物 这里不处理 (编辑态不会产生)

func _edit_delete_unit(u: Dictionary) -> void:
	_edit_free_unit_nodes(u)
	battle._arr_erase_unit(battle._units, u)

func _edit_clear() -> void:
	for u in battle._units.duplicate():
		_edit_free_unit_nodes(u)
	battle._units.clear()
	battle._projectiles.clear()
	for z in battle._lava_sys._lava_zones:                       # 清岩浆池(避免编辑重开残留)
		var d = z.get("disc", null)
		if d != null and is_instance_valid(d):
			d.queue_free()
	battle._lava_sys._lava_zones.clear()
	_edit_set_status("已清空")

# ▶开始: 把当前摆位生效为战斗. 为干净起见 (避免重复 _inject/_apply 叠加), 先快照摆位, 再做开战准备.
#   注: 编辑态摆放时已逐个 battle._spawn._make_unit, 但还没跑过 battle._inject_equipment/battle._spawn._apply_spawn_passives/battle._equip_sys._stats._eq_apply_all_stats,
#   所以这里补跑一次即可 (开战准备), 之后退出编辑态 → 模拟开始推进.
# ▶开始: 把当前摆位生效为战斗. 为干净起见 (避免重复 _inject/_apply 叠加), 先快照摆位, 再做开战准备.
#   注: 编辑态摆放时已逐个 battle._spawn._make_unit, 但还没跑过 battle._inject_equipment/battle._spawn._apply_spawn_passives/battle._equip_sys._stats._eq_apply_all_stats,
#   所以这里补跑一次即可 (开战准备), 之后退出编辑态 → 模拟开始推进.
func _edit_start_battle() -> void:
	if battle._units.is_empty():
		_edit_set_status("场上没有单位, 先摆几个再开始")
		return
	# 快照当前摆位 (⏸编辑 用它重新生成一份干净的)
	_edit_snapshot_setup()
	_edit_save_setup()   # 存盘: 重开调试场自动恢复上次摆位
	battle._inject_equipment()
	battle._spawn._apply_spawn_passives()
	battle._equip_sys._stats._eq_apply_all_stats()
	if battle._edit_full_energy:   # 装备/被动结算后再补满龟能→技能即就绪(不被_eq_apply_all_stats重置回充率覆盖)
		for u in battle._units:
			if u.get("side", "") == "left": _edit_apply_full_energy(u)
	battle._edit_mode = false
	battle._over = false
	if battle._edit_btn_start != null: battle._edit_btn_start.disabled = true
	if battle._edit_btn_edit != null: battle._edit_btn_edit.disabled = false
	_edit_set_status("战斗中 ... (点 ⏸编辑 暂停回摆位)")

# 从一条摆位快照重建单位: 小将按 role/level 走 minion spec(否则退化成默认龟), 右队假人锁血/不动, 友军按满龟能开关补能.
# 从一条摆位快照重建单位: 小将按 role/level 走 minion spec(否则退化成默认龟), 右队假人锁血/不动, 友军按满龟能开关补能.
func _edit_unit_from_setup(s: Dictionary) -> Dictionary:
	var side = str(s.get("side", "left"))
	var u: Dictionary
	# 训龟大师(用户2026-07-24): 自由摆位·带装配的主动
	if bool(s.get("trainer", false)) or str(s.get("id", "")) == battle.TRAINER_ID:
		u = battle._spawn._make_unit(battle.TRAINER_ID, side, s.get("pos", Vector2()), {"trainer": true})
		u["_tr_active"] = battle._valid_active(str(s.get("tr_active", "hook")))
		u["_tr_passive"] = ""
		return u
	if bool(s.get("minion", false)) or str(s.get("id", "")) == "__minion__":
		var role = str(s.get("role", "front"))
		var lvl = int(s.get("level", 1))
		var _el: bool = (role == "elite")   # 精英小将(用户2026-07-24)
		var _sp: Dictionary = {"minion": true, "elite": _el, "level": lvl}
		if not _el: _sp["role"] = role
		u = battle._spawn._make_unit("__minion__", side, s.get("pos", Vector2()), _sp)
		u["_edit_minion_role"] = role
		u["_edit_minion_lvl"] = lvl
	else:
		u = battle._spawn._make_unit(str(s.get("id", "basic")), side, s.get("pos", Vector2()))
	u["_edit_equips"] = s.get("equips", [])
	if side == "right":
		u["no_basic"] = true
		u["no_move"] = true
		u["active_skills"] = []
	u["maxHp"] = float(s.get("hp", u.get("maxHp", battle._edit_dummy_hp)))   # 血量: 左右都按 per-unit 存的(用户2026-07-24)
	u["hp"] = u["maxHp"]
	if not bool(s.get("killable", true)):
		u["_review_dummy"] = true   # 无敌沙包(per-unit·左右都可)
	if side == "left" and bool(s.get("fe", false)):   # 满龟能(per-unit)
		var cds: Dictionary = u.get("skill_cd", {})
		for _sk in u.get("active_skills", []): cds[str(_sk)] = 0.0
		u["skill_cd"] = cds
		u["echarge_perm"] = maxf(float(u.get("echarge_perm", 1.0)), 4.0)
		u["_edit_fe"] = true
	elif side == "left" and battle._edit_full_energy:
		_edit_apply_full_energy(u)
	return u

# ⏸编辑: 暂停回编辑态. 按开战前的摆位快照重新生成一份干净单位 (避免战斗中状态/护盾/DoT 残留).
# ⏸编辑: 暂停回编辑态. 按开战前的摆位快照重新生成一份干净单位 (避免战斗中状态/护盾/DoT 残留).
func _edit_back_to_edit() -> void:
	_edit_clear()
	for s in battle._edit_paused_setup:
		battle._units.append(_edit_unit_from_setup(s))
	battle._edit_mode = true
	battle._over = false
	if battle._edit_btn_start != null: battle._edit_btn_start.disabled = false
	if battle._edit_btn_edit != null: battle._edit_btn_edit.disabled = true
	_edit_set_status("已回编辑模式 (按摆位重新生成)")

func _edit_snapshot_setup() -> void:
	battle._edit_paused_setup.clear()
	for u in battle._units:
		battle._edit_paused_setup.append({
			"id": str(u["id"]),
			"side": str(u["side"]),
			"pos": Vector2(u["pos"]),
			"hp": float(u.get("maxHp", 500.0)),
			"killable": not bool(u.get("_review_dummy", false)),   # 无敌态: 左右都存(用户2026-07-24 per-unit)
			"fe": bool(u.get("_edit_fe", false)),                  # 满龟能态(per-unit)
			"equips": u.get("_edit_equips", []),
			"minion": str(u.get("id", "")) == "__minion__",   # 小将靠id判定(单位字典不存is_minion·只有is_elite)→存盘/JSON正确; 重建另有id兜底
			"role": str(u.get("_edit_minion_role", "front")),   # role=="elite" 即精英小将(用户2026-07-24)
			"level": int(u.get("_edit_minion_lvl", 1)),
			"trainer": bool(u.get("is_trainer", false)),        # 训龟大师(用户2026-07-24)
			"tr_active": str(u.get("_tr_active", "hook")),
		})

# ----------------------------------------------------------------------------
#  编辑面板 (代码构建, 无 .tscn). 子控件 mouse_filter=STOP → GUI 层吃掉点击, 不误摆到 UI 上.
# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------
#  编辑面板 (代码构建, 无 .tscn). 子控件 mouse_filter=STOP → GUI 层吃掉点击, 不误摆到 UI 上.
# ----------------------------------------------------------------------------
func _edit_mk_btn(label: String, cb: Callable, min_w: float = 0.0) -> Button:
	var b = Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 19)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(min_w, 46)   # 触摸友好高度
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

func _edit_lbl(t: String) -> Label:
	var l = Label.new(); l.text = t
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color("#9fb6c8"))
	return l

func _edit_val_lbl(w: float) -> Label:
	var l = Label.new()
	l.custom_minimum_size = Vector2(w, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color("#cfe6ff"))
	return l

func _edit_toggle_collapse() -> void:
	battle._edit_collapsed = not battle._edit_collapsed
	_edit_apply_collapse()

func _edit_apply_collapse() -> void:
	if battle._edit_body != null and is_instance_valid(battle._edit_body):
		battle._edit_body.visible = not battle._edit_collapsed
	if battle._edit_btn_collapse != null and is_instance_valid(battle._edit_btn_collapse):
		battle._edit_btn_collapse.text = "▶ 展开" if battle._edit_collapsed else "⊟ 折叠"

# ════════════════════════════════════════════════════════════════════
#  底部常驻笔刷栏 (用户2026-07-24: 取代模态选龟弹窗, 点选笔刷→连点连摆·不挡战场)
# ════════════════════════════════════════════════════════════════════
func _edit_brush_cell(key: String, icon_path: String, label: String) -> Button:
	var b = Button.new()
	b.custom_minimum_size = Vector2(54, 54)
	b.tooltip_text = label
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if icon_path != "" and ResourceLoader.exists(icon_path):
		b.icon = load(icon_path); b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 46)
	else:
		b.text = label; b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(func(): _edit_set_brush(key))
	battle._edit_brush_cells.append([b, key])
	return b

func _edit_current_brush_key() -> String:
	if battle._edit_pick_id == "__minion__":
		return "__minion__:" + battle._edit_minion_role
	return battle._edit_pick_id

func _edit_set_brush(key: String) -> void:
	if key.begins_with("__minion__:"):
		battle._edit_pick_id = "__minion__"
		battle._edit_minion_role = key.substr(11)   # front/back/elite
	else:
		battle._edit_pick_id = key
	_edit_refresh_brush_highlight()
	_edit_refresh_labels()
	_edit_set_status("笔刷: %s · 点空地摆放(可连点)" % _edit_brush_name(key))

func _edit_brush_name(key: String) -> String:
	if key == battle.TRAINER_ID: return "训龟大师"
	if key.begins_with("__minion__:"):
		return {"front": "近战小将·浪板", "back": "远程小将·火箭", "elite": "精英小将"}.get(key.substr(11), "小将")
	return str(battle._data_by_id.get(key, {}).get("name", key))

func _edit_refresh_brush_highlight() -> void:
	var cur = _edit_current_brush_key()
	for pair in battle._edit_brush_cells:
		var b: Button = pair[0]
		if not is_instance_valid(b): continue
		var on: bool = (str(pair[1]) == cur)
		var s = StyleBoxFlat.new()
		s.bg_color = Color(0.16, 0.22, 0.14, 1.0) if on else Color(0.09, 0.13, 0.19, 1.0)
		s.border_color = Color("#ffd93d") if on else Color(0.24, 0.30, 0.38, 1.0)
		s.set_border_width_all(3 if on else 1); s.set_corner_radius_all(6)
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_stylebox_override("hover", s)
		b.add_theme_stylebox_override("pressed", s)
		b.modulate = Color(1, 1, 1, 1) if on else Color(0.7, 0.74, 0.8, 1)

# ---- 网格弹层 (选装备; 选龟已改成底部笔刷栏) ----
# ---- 网格弹层 (选装备; 选龟已改成底部笔刷栏) ----
func _edit_make_popup(title_text: String) -> GridContainer:
	_edit_close_popup()
	var back = ColorRect.new()
	back.color = Color(0, 0, 0, 0.55)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	back.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: _edit_close_popup())
	battle._ui_layer.add_child(back)
	battle._edit_grid_popup = back
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.add_child(center)
	var panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.09, 0.14, 0.99)
	sb.border_color = Color("#ffd93d"); sb.set_border_width_all(2); sb.set_corner_radius_all(12)
	sb.content_margin_left = 16; sb.content_margin_right = 16; sb.content_margin_top = 14; sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	var vb = VBoxContainer.new(); vb.add_theme_constant_override("separation", 10); panel.add_child(vb)
	var hdr = HBoxContainer.new(); hdr.add_theme_constant_override("separation", 8); vb.add_child(hdr)
	var t = Label.new(); t.text = title_text; t.add_theme_font_size_override("font_size", 21); t.add_theme_color_override("font_color", Color("#ffd93d"))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(t)
	hdr.add_child(_edit_mk_btn("✕ 关闭", func(): _edit_close_popup(), 96))
	var sc = ScrollContainer.new()
	sc.custom_minimum_size = Vector2(700, 460)
	vb.add_child(sc)
	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	sc.add_child(grid)
	return grid

func _edit_close_popup() -> void:
	if battle._edit_grid_popup != null and is_instance_valid(battle._edit_grid_popup):
		battle._edit_grid_popup.queue_free()
	battle._edit_grid_popup = null

func _edit_grid_card(nm: String, icon_path: String, border: Color, cb: Callable) -> Button:
	var b = Button.new()
	b.custom_minimum_size = Vector2(128, 112)
	b.add_theme_font_size_override("font_size", 14)
	# ★手机端滑动(用户2026-07-22「调试场选装备选龟需要适配手机端的滑动」):
	#   GUI 事件遇 MOUSE_FILTER_STOP 就停止冒泡 → 永远到不了外层 ScrollContainer,
	#   于是 28 龟 / 59 装备的网格在触屏上【完全滑不动】。
	#   项目里已有同款教训与解法: CodexScene.gd:651「子控件吞掉拖动=手机滑不动·2026-07-18」。
	#   PASS: 触屏拖动透传给 ScrollContainer, 而 BaseButton 只处理 InputEventMouseButton,
	#   模拟鼠标点击照常生效 → 既能滑又能点。
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.text = nm
	b.clip_text = true
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	if icon_path != "" and ResourceLoader.exists(icon_path):
		b.icon = load(icon_path)
		b.expand_icon = true
	var sbn = StyleBoxFlat.new(); sbn.bg_color = Color(0.1, 0.13, 0.18, 0.95); sbn.border_color = border; sbn.set_border_width_all(2); sbn.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", sbn)
	if cb.is_valid(): b.pressed.connect(cb)
	return b

func _edit_open_turtle_grid() -> void:
	var grid = _edit_make_popup("选龟 · 点选要摆的龟")
	for id in battle.STATS.keys():
		var iid = str(id)
		var nm = str(battle._data_by_id.get(iid, {}).get("name", iid))
		var av = battle.AVATAR_DIR + iid + ".png"
		grid.add_child(_edit_grid_card(nm, av, Color("#8aa0b4"), func(): _edit_pick_turtle(iid)))

func _edit_pick_turtle(id: String) -> void:
	battle._edit_pick_id = id
	_edit_close_popup()
	_edit_refresh_labels()
	_edit_set_status("选龟: %s · 点空地摆放" % str(battle._data_by_id.get(id, {}).get("name", id)))

func _edit_rarity_color(eq: Dictionary) -> Color:   # 调试场装备色: 按费用(稀有度字段已废弃·用户2026-07-19)
	match int(eq.get("cost", 1)):
		5: return Color("#ffcf6b")
		4: return Color("#c77dff")
		3: return Color("#5aa9ff")
		2: return Color("#5fd08a")
		_: return Color("#9aa4ad")

func _edit_open_equip_grid() -> void:
	if battle._edit_sel_unit == null:
		_edit_set_status("先点一个单位选中, 再加装备")
		return
	var nm = str(battle._data_by_id.get(battle._edit_sel_unit.get("id", ""), {}).get("name", ""))
	var grid = _edit_make_popup("加装备到 %s · 点选(可连点多件)" % nm)
	for id in battle._review_console._dbg_equip_ids():
		var iid = str(id)
		var eq: Dictionary = DataRegistry.phase2_equipment_by_id.get(iid, {})
		var enm = str(eq.get("name", iid))
		var img = str(eq.get("img", ""))
		var ip = ("res://assets/sprites/" + img) if (img != "" and not img.begins_with("res://")) else img
		grid.add_child(_edit_grid_card(enm, ip, _edit_rarity_color(eq), func(): _edit_add_equip(iid)))

func _edit_select_unit(u) -> void:
	battle._edit_sel_unit = u
	_edit_refresh_equip_panel()
	if u != null:
		_edit_set_status("选中 %s · 加装备/删除" % str(battle._data_by_id.get(u.get("id", ""), {}).get("name", "")))

func _edit_refresh_equip_panel() -> void:
	if battle._edit_equip_box == null: return
	for c in battle._edit_equip_box.get_children(): c.queue_free()
	if battle._edit_sel_unit == null: return
	var nm = str(battle._data_by_id.get(battle._edit_sel_unit.get("id", ""), {}).get("name", ""))
	var side_t = "友军" if str(battle._edit_sel_unit.get("side", "")) == "left" else "假人"
	var hdr = HBoxContainer.new(); hdr.add_theme_constant_override("separation", 8); battle._edit_equip_box.add_child(hdr)
	var l = Label.new(); l.text = "选中: %s(%s)" % [nm, side_t]
	l.add_theme_font_size_override("font_size", 16); l.add_theme_color_override("font_color", Color("#9ae6b0"))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(l)
	hdr.add_child(_edit_mk_btn("🗑 删除", func(): _edit_delete_sel(), 96))
	hdr.add_child(_edit_mk_btn("取消", func(): _edit_select_unit(null), 80))
	var _sd: Dictionary = battle._data_by_id.get(str(battle._edit_sel_unit.get("id", "")), {})
	var _spool: Array = _sd.get("skillPool", [])
	if _spool.size() > 2:   # 有主动候选(3选1)
		var _curi = battle._resolve_chosen_index(str(battle._edit_sel_unit.get("id", "")), str(battle._edit_sel_unit.get("side", "")) == "left")
		var srow = HFlowContainer.new(); srow.add_theme_constant_override("h_separation", 6); srow.add_theme_constant_override("v_separation", 6); battle._edit_equip_box.add_child(srow)
		srow.add_child(_edit_lbl("技能"))
		for _si in range(1, _spool.size()):
			var _sidx: int = _si
			var _snm = str((_spool[_si] as Dictionary).get("name", "技%d" % _si))
			var _sb = _edit_mk_btn(_snm, func(): _edit_set_unit_skill(_sidx), 0)
			_sb.modulate = Color(1, 0.9, 0.4, 1) if _si == _curi else Color(0.58, 0.62, 0.68, 1)
			srow.add_child(_sb)
	# ── 单龟配置(用户2026-07-24: 血量/无敌/满龟能 逐只设·不再全局; 大师=主动技选择器) ──
	var _u: Dictionary = battle._edit_sel_unit
	if _u.get("is_trainer", false):
		var trow = HFlowContainer.new(); trow.add_theme_constant_override("h_separation", 6); trow.add_theme_constant_override("v_separation", 6); battle._edit_equip_box.add_child(trow)
		trow.add_child(_edit_lbl("主动技"))
		for _tk in ["hook", "fury_potion", "whistle", "glacier"]:
			var _tkk: String = _tk
			var _tb = _edit_mk_btn(str(battle.TRAINER_SKILLS[_tk]["name"]), func(): _edit_set_trainer_skill(_tkk), 0)
			_tb.modulate = Color(1, 0.9, 0.4, 1) if str(_u.get("_tr_active", "")) == _tk else Color(0.58, 0.62, 0.68, 1)
			trow.add_child(_tb)
	else:
		var hrow = HBoxContainer.new(); hrow.add_theme_constant_override("separation", 6); battle._edit_equip_box.add_child(hrow)
		hrow.add_child(_edit_lbl("血量"))
		hrow.add_child(_edit_mk_btn("−", func(): _edit_sel_adjust_hp(-500.0), 44))
		var _hl = Label.new(); _hl.text = "%d" % int(_u.get("maxHp", 0)); _hl.add_theme_font_size_override("font_size", 15); _hl.add_theme_color_override("font_color", Color("#ffe9a8")); _hl.custom_minimum_size = Vector2(80, 0); _hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hrow.add_child(_hl)
		hrow.add_child(_edit_mk_btn("+", func(): _edit_sel_adjust_hp(500.0), 44))
		var _inv: bool = _u.get("_review_dummy", false)
		hrow.add_child(_edit_mk_btn("无敌:%s" % ("开" if _inv else "关"), func(): _edit_sel_toggle_invincible(), 92))
		var _fe: bool = _u.get("_edit_fe", false)
		hrow.add_child(_edit_mk_btn("满龟能:%s" % ("开" if _fe else "关"), func(): _edit_sel_toggle_energy(), 110))
	var wrap = HFlowContainer.new(); wrap.add_theme_constant_override("h_separation", 6); wrap.add_theme_constant_override("v_separation", 6); battle._edit_equip_box.add_child(wrap)
	var eqs: Array = battle._edit_sel_unit.get("_edit_equips", [])
	for e in eqs:
		var eid = str(e.get("id", ""))
		var enm = str(DataRegistry.phase2_equipment_by_id.get(eid, {}).get("name", eid))
		var stv = int(e.get("star", 1))
		wrap.add_child(_edit_mk_btn("%s★%d ✕" % [enm, stv], func(): _edit_remove_equip(eid), 0))
	wrap.add_child(_edit_mk_btn("➕ 加装备", func(): _edit_open_equip_grid(), 120))

func _edit_set_unit_skill(idx: int) -> void:
	if battle._edit_sel_unit == null: return
	var id = str(battle._edit_sel_unit.get("id", ""))
	if GameState != null:
		GameState.loadouts[id] = idx
	for u in battle._units:                                       # 重解析该id所有已摆友方单位的主动技
		if str(u.get("id", "")) == id and str(u.get("side", "")) == "left":
			u["active_skills"] = battle._resolve_active_skills(id, true)
			u["skill_idx"] = 0
	var pool: Array = battle._data_by_id.get(id, {}).get("skillPool", [])
	var snm = str((pool[idx] as Dictionary).get("name", "")) if idx < pool.size() else ""
	_edit_set_status("技能 → %s" % snm)
	_edit_refresh_equip_panel()

## ── 单龟配置助手(用户2026-07-24: 血量/无敌/满龟能/大师主动 逐只设) ──
func _edit_set_trainer_skill(tk: String) -> void:
	if battle._edit_sel_unit == null: return
	battle._edit_sel_unit["_tr_active"] = battle._valid_active(tk)
	battle._edit_trainer_active = tk   # 记住 → 下次摆大师也用这个
	_edit_set_status("大师主动 → %s" % str(battle.TRAINER_SKILLS.get(tk, {}).get("name", tk)))
	_edit_refresh_equip_panel()

func _edit_sel_adjust_hp(d: float) -> void:
	if battle._edit_sel_unit == null: return
	battle._edit_sel_unit["maxHp"] = maxf(100.0, float(battle._edit_sel_unit.get("maxHp", 500.0)) + d)
	battle._edit_sel_unit["hp"] = battle._edit_sel_unit["maxHp"]
	_edit_refresh_equip_panel()

func _edit_sel_toggle_invincible() -> void:
	if battle._edit_sel_unit == null: return
	if battle._edit_sel_unit.get("_review_dummy", false): battle._edit_sel_unit.erase("_review_dummy")
	else: battle._edit_sel_unit["_review_dummy"] = true   # 无敌沙包(受击回满)
	_edit_refresh_equip_panel()

func _edit_sel_toggle_energy() -> void:
	if battle._edit_sel_unit == null: return
	var u: Dictionary = battle._edit_sel_unit
	if u.get("_edit_fe", false):
		u["echarge_perm"] = 1.0; u.erase("_edit_fe")
	else:
		var cds: Dictionary = u.get("skill_cd", {})
		for s in u.get("active_skills", []): cds[str(s)] = 0.0   # 技能即就绪
		u["skill_cd"] = cds
		u["echarge_perm"] = maxf(float(u.get("echarge_perm", 1.0)), 4.0); u["_edit_fe"] = true
	_edit_refresh_equip_panel()

func _edit_add_equip(iid: String) -> void:
	if battle._edit_sel_unit == null: return
	if not (battle._edit_sel_unit.get("_edit_equips") is Array): battle._edit_sel_unit["_edit_equips"] = []
	(battle._edit_sel_unit["_edit_equips"] as Array).append({"id": iid, "star": battle._edit_pick_star})
	var enm = str(DataRegistry.phase2_equipment_by_id.get(iid, {}).get("name", iid))
	_edit_set_status("+ %s ★%d" % [enm, battle._edit_pick_star])
	_edit_refresh_equip_panel()

func _edit_remove_equip(iid: String) -> void:
	if battle._edit_sel_unit == null: return
	var eqs: Array = battle._edit_sel_unit.get("_edit_equips", [])
	for i in range(eqs.size()):
		if str((eqs[i] as Dictionary).get("id", "")) == iid:
			eqs.remove_at(i); break
	_edit_refresh_equip_panel()

func _edit_delete_sel() -> void:
	if battle._edit_sel_unit == null: return
	var u = battle._edit_sel_unit
	_edit_select_unit(null)
	_edit_delete_unit(u)
	_edit_set_status("删除单位 (剩 %d)" % battle._units.size())

func _edit_toggle_side() -> void:
	battle._edit_pick_side = "right" if battle._edit_pick_side == "left" else "left"
	_edit_refresh_labels()

func _edit_adjust_hp(d: float) -> void:
	battle._edit_dummy_hp = maxf(100.0, battle._edit_dummy_hp + d)
	_edit_refresh_labels()

func _edit_toggle_killable() -> void:
	battle._edit_dummy_killable = not battle._edit_dummy_killable
	_edit_refresh_labels()

func _edit_toggle_full_energy() -> void:   # 满龟能开关(用户2026-07-18: 不用死磕攒龟能就能看放技): 对已摆的友军立即生效+新摆的也带
	battle._edit_full_energy = not battle._edit_full_energy
	for u in battle._units:
		if u.get("side", "") == "left":
			_edit_apply_full_energy(u)
	_edit_refresh_labels()
	_edit_set_status("满龟能 %s · 友军技能开局即就绪+快速回充" % ("开(可反复看放技)" if battle._edit_full_energy else "关(正常攒龟能)"))

# 让单位技能立刻就绪(skill_cd清零)并快速回充(echarge_perm提速)→ 反复看放技; 关则还原
# 让单位技能立刻就绪(skill_cd清零)并快速回充(echarge_perm提速)→ 反复看放技; 关则还原
func _edit_apply_full_energy(u: Dictionary) -> void:
	if u.get("active_skills", []).is_empty():
		return
	if battle._edit_full_energy:
		var cds: Dictionary = u.get("skill_cd", {})
		for s in u.get("active_skills", []):
			cds[str(s)] = 0.0            # 即就绪(免等满龟能)
		u["skill_cd"] = cds
		u["echarge_perm"] = maxf(float(u.get("echarge_perm", 1.0)), 4.0)   # 回充×4→放完约2-3秒又能放(反复观察)
		u["_edit_fe"] = true
	elif u.get("_edit_fe", false):
		u["echarge_perm"] = 1.0
		u.erase("_edit_fe")

func _edit_set_star(st: int) -> void:
	battle._edit_pick_star = clampi(st, 1, 3)
	_edit_refresh_labels()

func _edit_set_speed(idx: int) -> void:
	battle._edit_speed_idx = clampi(idx, 0, battle.EDIT_SPEEDS.size() - 1)
	Engine.time_scale = float(battle.EDIT_SPEEDS[battle._edit_speed_idx])
	_edit_refresh_labels()

func _edit_replay() -> void:
	if battle._edit_paused_setup.is_empty():
		_edit_set_status("还没开始过 · 先摆几个点▶开始")
		return
	_edit_back_to_edit()
	_edit_start_battle()

func _edit_refresh_labels() -> void:
	if battle._edit_btn_pick != null:
		if battle._edit_pick_id == "__minion__":
			battle._edit_btn_pick.text = "当前笔刷: %s" % ("近战小将·浪板" if battle._edit_minion_role == "front" else "远程小将·火箭")
		else:
			battle._edit_btn_pick.text = "选龟: %s" % str(battle._data_by_id.get(battle._edit_pick_id, {}).get("name", battle._edit_pick_id))
	if battle._edit_btn_side != null:
		battle._edit_btn_side.text = "左队(友军)" if battle._edit_pick_side == "left" else "右队(假人)"
	if battle._edit_btn_energy != null:
		battle._edit_btn_energy.text = "满龟能:开" if battle._edit_full_energy else "满龟能:关"
		battle._edit_btn_energy.modulate = Color(1, 0.9, 0.4, 1) if battle._edit_full_energy else Color(0.55, 0.6, 0.66, 1)
	if battle._edit_lbl_hp != null:
		var kt = "会死" if battle._edit_dummy_killable else "不死"
		battle._edit_lbl_hp.text = "%d(%s)" % [int(battle._edit_dummy_hp), kt]
	for i in range(battle._edit_star_btns.size()):
		(battle._edit_star_btns[i] as Button).modulate = Color(1, 0.9, 0.4, 1) if (i + 1) == battle._edit_pick_star else Color(0.55, 0.6, 0.66, 1)
	for i in range(battle._edit_speed_btns.size()):
		(battle._edit_speed_btns[i] as Button).modulate = Color(1, 0.9, 0.4, 1) if i == battle._edit_speed_idx else Color(0.55, 0.6, 0.66, 1)

func _edit_set_status(s: String) -> void:
	if battle._edit_lbl_status != null:
		battle._edit_lbl_status.text = s

func _edit_save_setup() -> void:
	var arr: Array = []
	var lds = {}
	for s in battle._edit_paused_setup:
		var pos: Vector2 = s.get("pos", Vector2())
		arr.append({"id": str(s.get("id", "")), "side": str(s.get("side", "")), "px": pos.x, "py": pos.y, "hp": float(s.get("hp", 500.0)), "killable": bool(s.get("killable", true)), "equips": s.get("equips", []), "minion": bool(s.get("minion", false)), "role": str(s.get("role", "front")), "level": int(s.get("level", 1))})
		var _id = str(s.get("id", ""))
		if GameState != null and GameState.loadouts.has(_id): lds[_id] = GameState.loadouts[_id]
	var f = FileAccess.open("user://debug_setup.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"units": arr, "loadouts": lds})); f.close()

func _edit_load_setup() -> void:
	if not FileAccess.file_exists("user://debug_setup.json"): return
	var f = FileAccess.open("user://debug_setup.json", FileAccess.READ)
	if f == null: return
	var txt = f.get_as_text(); f.close()
	var data = JSON.parse_string(txt)
	var arr: Array = []
	if data is Array:
		arr = data
	elif data is Dictionary:
		arr = (data as Dictionary).get("units", [])
		var _lds = (data as Dictionary).get("loadouts", {})
		if _lds is Dictionary and GameState != null:
			for _k in (_lds as Dictionary).keys():
				GameState.loadouts[str(_k)] = int(_lds[_k])
	if arr.is_empty(): return
	_edit_clear()
	for s in arr:
		if not (s is Dictionary): continue
		var sd = s as Dictionary
		var el: Array = []
		var eqs = sd.get("equips", [])
		if eqs is Array:
			for e in eqs:
				if e is Dictionary: el.append({"id": str(e.get("id", "")), "star": int(e.get("star", 1))})
		battle._units.append(_edit_unit_from_setup({
			"id": str(sd.get("id", "basic")),
			"side": str(sd.get("side", "left")),
			"pos": Vector2(float(sd.get("px", 400.0)), float(sd.get("py", 400.0))),
			"hp": float(sd.get("hp", 500.0)),
			"killable": bool(sd.get("killable", false)),
			"equips": el,
			"minion": bool(sd.get("minion", false)),
			"role": str(sd.get("role", "front")),
			"level": int(sd.get("level", 1)),
		}))
	_edit_set_status("已恢复上次摆位 (%d 单位)" % battle._units.size())

func _edit_exit_to_menu() -> void:
	Engine.time_scale = 1.0
	battle.DEBUG_EDIT = false
	battle.get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# ============================================================================
#  DEV 自截图 (SELFSHOT=<秒>): 等战斗跑起来 + frame_post_draw 保证入帧缓冲
# ============================================================================
#  Smolder ULT fire-wave: mother dragon looms + sweeping dragonfire wave (center hottest). VFXPREVIEW=smolder.
# ============================================================================
