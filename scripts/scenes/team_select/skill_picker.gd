class_name SkillPicker
extends RefCounted
## 选龟页·技能5选1选择器(dev注: 单选)
## 类内名不变;外部名加 battle.

var host

func _init(b) -> void:
	host = b

# ─── 技能 5选3 (PoC refreshDetailPanel 下块 1:1) ────────────────
func _build_skill_picker(pet: Dictionary) -> void:
	var pid: String = pet["id"]
	var pool: Array = pet.get("skillPool", [])
	var selected: Array = _get_panel_loadout(pid)

	# PoC .dp-section-title "技能"(14px金) + .dp-skill-count "选 3 (N/3)"(11px 白@.5 细体, 非金)
	var title_row = HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", host._sp(4))   # .dp-skill-count margin-left:4
	var title = Label.new()
	title.text = "技能"
	title.add_theme_font_size_override("font_size", host._sf(14))
	title.add_theme_color_override("font_color", Color("#ffd86b"))
	title_row.add_child(title)
	var count_lbl = Label.new()
	count_lbl.text = "%d 选 1 (主动/被动)" % maxi(1, pool.size() - 1)   # 普攻(idx0)外的候选数; 收敛成[普攻+3技]后=3选1
	count_lbl.add_theme_font_size_override("font_size", host._sf(11))   # PoC .dp-skill-count 11px
	count_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))   # rgba(255,255,255,.5)
	count_lbl.size_flags_vertical = Control.SIZE_SHRINK_END   # 底对齐近 baseline
	title_row.add_child(count_lbl)
	host._detail_bottom.add_child(title_row)

	# PoC .dp-skill-icons: flex-wrap 居中 (3+2) — 居中容器包 GridContainer
	var grid_center = CenterContainer.new()
	host._detail_bottom.add_child(grid_center)
	var icon_grid = GridContainer.new()
	icon_grid.columns = 3
	icon_grid.add_theme_constant_override("h_separation", host._sp(8))
	icon_grid.add_theme_constant_override("v_separation", host._sp(8))
	grid_center.add_child(icon_grid)

	for i in range(pool.size()):
		var sk: Dictionary = pool[i]
		var is_fixed: bool = i == 0
		var is_sel: bool = i in selected
		var ico = _make_skill_icon(pet, sk, i, is_fixed, is_sel)
		icon_grid.add_child(ico)

	# 已选技能名列表
	var sel_names = ""
	for i in selected:
		if i >= 0 and i < pool.size():
			sel_names += "✓ %s   " % pool[i].get("name", "?")
	var sel_lbl = Label.new()
	sel_lbl.text = sel_names
	sel_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sel_lbl.add_theme_font_size_override("font_size", host._sf(12))
	sel_lbl.add_theme_color_override("font_color", Color("#ffd86b"))
	sel_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host._detail_bottom.add_child(sel_lbl)


func _make_skill_icon(pet: Dictionary, sk: Dictionary, idx: int, is_fixed: bool, is_sel: bool) -> Control:
	var pid: String = pet["id"]
	var unlocked: Array = _available_skill_indices(pet)
	var is_locked: bool = not (idx in unlocked)   # 恒 false: _available_skill_indices 现在返回全部索引(等级解锁已移除)
	var dev_locked: bool = (not is_fixed) and idx != 1 and not sk.get("impl", false)   # 非默认候选: 未标impl:true(未实装)才"开发中"锁; 实装好的技解锁3选1

	var btn: Button = host.SkillTipButton.new()   # styled tooltip (PoC .dp-skill-tip 悬浮显名+CD+描述)
	btn.custom_minimum_size = Vector2(host._sp(64), host._sp(64))   # PoC .dp-skill-ico 64px (index.html:606)
	btn.tooltip_text = _skill_tooltip(pet, sk, idx)
	# 图标
	var icon_rel: String = str(sk.get("icon", ""))
	var tex: Texture2D = null
	if icon_rel != "":
		var full = "res://assets/sprites/" + icon_rel
		if ResourceLoader.exists(full):
			tex = load(full)
	if tex == null:
		var passive_raw = pet.get("passive")
		if sk.get("enhancesPassive", false) and passive_raw is Dictionary:
			var pi: String = DataRegistry.passive_icons.get((passive_raw as Dictionary).get("type", ""), "")
			if pi.ends_with(".png"):
				var pfull = "res://assets/sprites/" + pi
				if ResourceLoader.exists(pfull):
					tex = load(pfull)
	if tex != null:
		btn.icon = tex
		btn.expand_icon = true
	else:
		btn.text = str(sk.get("name", "?")).substr(0, 2)
		btn.add_theme_font_size_override("font_size", host._sf(10))

	# 边框态: 选中=金#ffd86b+发光 / 锁=暗 / 基础(fixed)=绿rgba(125,255,179,.6) (PoC index.html:631-632)
	var sbn = StyleBoxFlat.new()
	if is_sel:
		# PoC .dp-skill-ico.selected: bg rgba(255,216,107,.14) + 金边 + glow (index.html:631)
		sbn.bg_color = Color(1.0, 216.0 / 255.0, 107.0 / 255.0, 0.14)
		sbn.border_color = Color("#ffd86b")
		sbn.shadow_color = Color8(0xff, 0xd8, 0x6b, 102)   # box-shadow 0 0 10px rgba(255,216,107,.4)
		sbn.shadow_size = host._sp(8)
	elif is_fixed:
		# PoC .dp-skill-ico.fixed: bg rgba(125,255,179,.08) + 绿边 (index.html:632)
		sbn.bg_color = Color(125.0 / 255.0, 1.0, 179.0 / 255.0, 0.08)
		sbn.border_color = Color8(125, 255, 179, 153)   # rgba(125,255,179,.6)
	else:
		# PoC .dp-skill-ico 基础: bg rgba(255,255,255,.04) + 边 rgba(255,255,255,.1) (index.html:605-607)
		sbn.bg_color = Color(1, 1, 1, 0.04)
		sbn.border_color = Color(1, 1, 1, 0.1)
	sbn.set_border_width_all(2)
	sbn.set_corner_radius_all(host._sp(12))
	btn.add_theme_stylebox_override("normal", sbn)
	# hover: 金边高亮 (PoC .dp-skill-ico:hover border #ffd86b.7); locked 不高亮
	if is_locked:
		btn.add_theme_stylebox_override("hover", sbn)
	else:
		var sbh: StyleBoxFlat = sbn.duplicate()
		sbh.border_color = Color(1.0, 216.0 / 255.0, 107.0 / 255.0, 0.7)
		btn.add_theme_stylebox_override("hover", sbh)
	btn.add_theme_stylebox_override("pressed", sbn)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	if is_locked:
		btn.modulate = Color(1, 1, 1, 0.45)   # PoC .dp-skill-ico.locked opacity .45 (index.html:633)
		btn.tooltip_text = "已锁定"   # 【不可达】等级解锁已移除(2026-07-10); 分支留作将来若引入其它锁条件
	elif dev_locked:
		btn.modulate = Color(1, 1, 1, 0.5)
		btn.tooltip_text = "候选技开发中, 当前锁定默认签名技"

	# 角标 (PoC .ico-corner bottom-right, index.html:634-641): lock=Lv4/Lv7 / fixed=基础 / selected=✓
	if is_locked:
		btn.add_child(_make_skill_corner("锁", Color("#2a2f3a"), Color("#ccdddd")))   # 【不可达】同上
	elif dev_locked:
		btn.add_child(_make_skill_corner("开发中", Color("#3a2f2a"), Color("#ddc9a0")))
	elif is_fixed:
		btn.add_child(_make_skill_corner("基础", Color("#7dffb3"), Color("#0a2417")))
	elif is_sel:
		btn.add_child(_make_skill_corner("✓", Color("#ffd86b"), Color("#2a1605")))
	# 强化被动 "+" 角标 (PoC .ico-plus 右上金圈, index.html:614-618)
	if sk.get("enhancesPassive", false) or sk.get("iconPlus", false):
		btn.add_child(_make_ico_plus())

	var clickable: bool = not is_locked and not is_fixed and not dev_locked
	if clickable:
		var ix = idx
		var pi = pid
		btn.pressed.connect(func() -> void: _toggle_skill(pi, ix))
	else:
		btn.disabled = is_locked   # 基础(0) 可点但提示必选
		if is_fixed:
			btn.disabled = false
			var pi2 = pid
			btn.pressed.connect(func() -> void: host._flash_status("基础技能必选"))
		elif dev_locked:
			btn.disabled = false
			btn.pressed.connect(func() -> void: host._flash_status("该候选技开发中, 暂锁默认签名技"))
	# 点/触 技能图标 → 弹窗看名+龟能+描述 (手机无 hover 的唯一途径; 与选中互不影响)
	var _skinfo: String = _skill_tooltip(pet, sk, idx)
	if not btn.disabled:
		btn.pressed.connect(func() -> void: host._show_detail_popup_from(_skinfo, Color("#ffd86b"), btn.get_global_rect()))
	return btn


## PoC .ico-corner (index.html:634-641): 图标右下角小圆角徽章, 探出 6px (bottom:-6 right:-6)。
func _make_skill_corner(txt: String, bg: Color, fg: Color) -> Control:
	var pc = PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(host._sp(8))
	sb.content_margin_left = host._sp(3); sb.content_margin_right = host._sp(3)
	sb.shadow_color = Color(0, 0, 0, 0.5); sb.shadow_size = host._sp(1); sb.shadow_offset = Vector2(0, host._sp(1))
	pc.add_theme_stylebox_override("panel", sb)
	var l = Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", host._sf(9))   # PoC .ico-corner 9px 800
	l.add_theme_color_override("font_color", fg)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pc.add_child(l)
	pc.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pc.position += Vector2(host._sp(6), host._sp(6))   # 探出右下 6px
	return pc


## PoC .ico-plus (index.html:614-618): 强化被动技能右上金圈 "+"。
func _make_ico_plus() -> Control:
	var pc = PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color("#ffd86b")
	sb.set_corner_radius_all(host._sp(9))
	sb.content_margin_left = host._sp(4); sb.content_margin_right = host._sp(4)
	sb.shadow_color = Color(0, 0, 0, 0.5); sb.shadow_size = host._sp(1); sb.shadow_offset = Vector2(0, host._sp(1))
	pc.add_theme_stylebox_override("panel", sb)
	var l = Label.new()
	l.text = "+"
	l.add_theme_font_size_override("font_size", host._sf(12))
	l.add_theme_color_override("font_color", Color("#2a1605"))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(l)
	pc.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pc.grow_vertical = Control.GROW_DIRECTION_END
	pc.position += Vector2(host._sp(6), -host._sp(6))   # 探出右上 (top:-6 right:-6)
	return pc


func _skill_tooltip(pet: Dictionary, sk: Dictionary, idx: int = -1) -> String:
	# 数值随存档等级 (1:1 PoC fakeF: base×getLevelBonus, lv=真实等级; 原硬编 lv:1+裸值=等级没同步)
	var tlv: int = GameState.get_pet_level(str(pet.get("id", "")))
	var tb: float = 1.0 + (tlv - 1) * 0.05
	var hp: int = roundi(pet.get("hp", 0) * tb)
	var atk: int = roundi(pet.get("atk", 0) * tb)
	var def_: int = roundi(pet.get("def", 0) * tb)
	var mr: int = roundi(pet.get("mr", pet.get("def", 0)) * tb)
	var fake_f = {"atk": atk, "def": def_, "mr": mr, "maxHp": hp, "crit": pet.get("crit", 0.25), "lv": tlv, "passive": pet.get("passive")}
	var brief: String = SkillText.render_bbcode(str(sk.get("brief", "")), fake_f, sk, 14)
	var head: String = str(sk.get("name", "?"))
	if host.SkillEnergy.is_active(str(sk.get("type", ""))):   # 龟能口径(无"CD"): 主动技显龟能花费, 攒满才放
		head += " (龟能%d)" % host._skill_energy(sk)
	var body = brief
	# 双形态配对技能 (PoC TeamSelectScene.ts:860-874): 换形龟显近战/火山对应技能
	if idx >= 0:
		var sk_name: String = str(sk.get("name", ""))
		var melee: Array = pet.get("meleeSkills", [])
		if idx < melee.size():
			var ms: Dictionary = melee[idx]
			if str(ms.get("name", "")) != sk_name and ms.get("name", "") != "":
				body += "\n近战：%s — %s" % [ms.get("name", ""), SkillText.render_bbcode(str(ms.get("brief", "")), fake_f, ms, 14)]
		var volcano: Array = pet.get("volcanoSkills", [])
		if idx < volcano.size() and not sk.get("passiveSkill", false):
			var vs: Dictionary = volcano[idx]
			if not vs.get("passiveSkill", false) and str(vs.get("name", "")) != sk_name and vs.get("name", "") != "":
				body += "\n火山：%s — %s" % [vs.get("name", ""), SkillText.render_bbcode(str(vs.get("brief", "")), fake_f, vs, 14)]
	return "%s\n%s" % [head, body]


# ─── 技能 5选3 逻辑 (PoC getPanelLoadout / toggleSkillInPanel 1:1) ──
## 实时版 = 【3选1】: idx0 普攻常驻, idx1..3 三个候选【全部可选, 无等级门槛】。
##
## ★2026-07-10 移除了 idx3 需 Lv.4 / idx4 需 Lv.7 的等级解锁 —— 那是回合制 PoC 的
##   `getPetLevel + skillUnlockLevel` 残留, 与用户的 3选1 设计直接冲突:
##     〖用户 2026-06-30 13:16 逐字〗"这只龟现在是3个技能选一个来登场, 其他龟我也会慢慢的
##       将4个可选改为3可选来降低复杂度和提升维护性"
##   而 `pet_levels` 默认 1 且"只调试面板改" → 实机上 idx3 永远 locked,
##   `clickable = not is_locked ...` 使它点不动 → 所谓"3选1"实际是【2选1】, 第三个候选谁也选不到。
##   transcript 里 "解锁" 命中 0 次 = 用户从没要过技能等级解锁。
func _available_skill_indices(pet: Dictionary) -> Array:
	var pool: Array = pet.get("skillPool", [])
	var idxs: Array = []
	for i in range(pool.size()):
		idxs.append(i)
	return idxs


# 4选1: 当前选中的那个候选索引 (1..4); skillPool[0]=普攻不参与选.
# 4选1: 当前选中的那个候选索引 (1..4); skillPool[0]=普攻不参与选.
func _chosen_candidate(pid: String, pet: Dictionary) -> int:
	var unlocked: Array = _available_skill_indices(pet)
	var lo = GameState.loadouts.get(pid, null)
	var idx = -1
	if lo is int or lo is float:
		idx = int(lo)
	elif lo is Array and not (lo as Array).is_empty():   # 兼容旧"选3"数组: 取首个非普攻
		for v in lo:
			if int(v) >= 1:
				idx = int(v); break
	if idx < 1 or not (idx in unlocked):                 # 无效/未解锁 → 默认首个解锁的候选
		idx = -1
		for u in unlocked:
			if int(u) >= 1:
				idx = int(u); break
		if idx < 0:
			idx = 1
	return idx

func _get_panel_loadout(pid: String) -> Array:
	var pet: Dictionary = DataRegistry.pet_by_id.get(pid, {})
	if pet.is_empty():
		return []
	return [_chosen_candidate(pid, pet)]   # 单选 → [选中候选] (供图标高亮)


func _toggle_skill(pid: String, idx: int) -> void:
	var pet: Dictionary = DataRegistry.pet_by_id.get(pid, {})
	if pet.is_empty():
		return
	if idx == 0:
		host._flash_status("普攻自动施放, 无需选择")        # skillPool[0]=普攻
		return
	var unlocked: Array = _available_skill_indices(pet)
	if not (idx in unlocked):
		host._flash_status("该技能已锁定")   # 【不可达】等级解锁已移除(2026-07-10)
		return
	# 3选1: idx1=默认签名技恒可选; idx2/3 候选需 impl:true(与按钮层 dev_locked L1250 同一门控)。
	#   旧的 `if idx != 1` 一刀切拦截是陈旧死码, 与 impl 标记矛盾(28龟 idx2/3 全 impl:true) → 已拆, 改成逐技校验。
	var pool: Array = pet.get("skillPool", [])
	if idx < 0 or idx >= pool.size():
		return
	var sk: Dictionary = pool[idx]
	if idx != 1 and not bool(sk.get("impl", false)):
		host._flash_status("该候选技开发中, 暂锁默认签名技")
		return
	GameState.loadouts[pid] = idx                       # 3选1: 单选, 点哪个就替换成哪个
	host._refresh_slots()
	host._refresh_confirm()
	host._refresh_detail()


# ══════════════════════════════════════════════════════════════
# 编队交互
# ══════════════════════════════════════════════════════════════
