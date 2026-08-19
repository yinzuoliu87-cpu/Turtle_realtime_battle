class_name DetailPanel
extends RefCounted
## 选龟页·右栏详情面板渲染(立绘/属性/被动·_set_detail_pet协调器留主场景)
## 类内名不变;外部名加 battle.

var host

func _init(b) -> void:
	host = b

func _build_detail_region() -> void:
	# 上区: 立绘/名字/属性/被动 各自独立成块 (可拖可缩·用户2026-07-18); 内容由 _refresh_detail 填
	host._dt_portrait = _make_detail_panel("dtPortrait")
	host._dt_name = _make_detail_panel("dtName")
	host._dt_stats = _make_detail_panel("dtStats")
	host._dt_passive = _make_detail_panel("dtPassive")

	# 下块 (技能 3选1)
	var bot_panel = PanelContainer.new()
	host.root.add_child(bot_panel)
	host._place(bot_panel, "detailBottom")
	bot_panel.add_theme_stylebox_override("panel", host._dark_panel())
	host._detail_bottom = VBoxContainer.new()
	host._detail_bottom.alignment = BoxContainer.ALIGNMENT_CENTER   # PoC #poc-detail-bottom justify-center
	host._detail_bottom.add_theme_constant_override("separation", host._sp(10))
	bot_panel.add_child(host._detail_bottom)


## 建一个独立信息子块面板 (透明底·按 RL key 放置·登记进编辑器·不挡下层点击)
func _make_detail_panel(key: String) -> PanelContainer:
	var p = PanelContainer.new()
	host.root.add_child(p)
	host._place(p, key)
	p.add_theme_stylebox_override("panel", host._dark_panel())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.clip_contents = true
	return p


## 给 Label 加投影 (近似 CSS text-shadow)
# ─── 右栏详情 ──────────────────────────────────────────────────
func _refresh_detail() -> void:
	for cont in [host._dt_portrait, host._dt_name, host._dt_stats, host._dt_passive, host._detail_bottom]:
		if cont != null:
			for c in cont.get_children():
				c.queue_free()
	if host.detail_pet_id == "":
		return
	var pet: Dictionary = DataRegistry.pet_by_id.get(host.detail_pet_id, {})
	if pet.is_empty():
		return
	var rarity: String = pet.get("rarity", "C")
	var rcolor: Color = host.RARITY_COLOR.get(rarity, Color.WHITE)
	# 数值=base×getLevelBonus(1+(lv-1)×0.05), 仅等级加成不乘稀有(1:1 PoC TeamSelectScene.ts:788-792).
	# 原 Godot 用裸 base + 硬编 Lv.1 → 有等级的龟数值/等级都不对.
	var det_lv: int = GameState.get_pet_level(host.detail_pet_id)
	var lv_bonus: float = 1.0 + (det_lv - 1) * 0.05
	var hp: int = roundi(pet.get("hp", 0) * lv_bonus)
	var atk: int = roundi(pet.get("atk", 0) * lv_bonus)
	var def_: int = roundi(pet.get("def", 0) * lv_bonus)
	var mr: int = roundi(pet.get("mr", pet.get("def", 0)) * lv_bonus)

	# ── 上块: 立绘(居中+底部辉光) + 名/稀有/Lv 行 + 2列属性 + 被动 ──
	# PoC .dp-portrait: 高156 居中 + 底部 radial 金色辉光; 全身 idle 动画
	# 立绘外包一层等高(156)壳, 壳内底部叠 radial 金辉光(behind) + 立绘(front), 不改 VBox 布局.
	var portrait_wrap = Control.new()
	portrait_wrap.custom_minimum_size = Vector2(0, host._sp(156))   # PoC .dp-portrait height:156
	portrait_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_wrap.clip_contents = true
	# 底部 radial 金色辉光 (PoC index.html:563: radial-gradient(ellipse at 50% 80%, rgba(255,216,107,.12), transparent 70%))
	var glow = TextureRect.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	var grad = Gradient.new()
	grad.set_color(0, Color(1.0, 216.0 / 255.0, 107.0 / 255.0, 0.12))   # rgba(255,216,107,.12)
	grad.set_color(1, Color(1.0, 216.0 / 255.0, 107.0 / 255.0, 0.0))    # transparent 70%
	var gtex = GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.8)            # ellipse at 50% 80% (近底部)
	gtex.fill_to = Vector2(0.5, 0.8 + 0.7)        # transparent 70% → 半径 0.7 (纵向)
	gtex.width = 256
	gtex.height = 256
	glow.texture = gtex
	portrait_wrap.add_child(glow)
	# PoC 立绘 = buildPetImgHTML(pet,124) 124px 帧, img max-height 150 (ts:810 / index.html:565).
	#   不撑满壳: 居中一个 124×150(×s) 盒, KEEP_ASPECT_CENTERED 不变形/不放大.
	var portrait = TextureRect.new()
	portrait.set_anchors_preset(Control.PRESET_CENTER)
	var pw = float(host._sp(124))
	var ph = float(host._sp(150))
	portrait.size = Vector2(pw, ph)
	portrait.position = Vector2(-pw * 0.5, -ph * 0.5)   # 居中 (anchor 中心 + 自身一半偏移)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host._apply_pet_idle_texture(portrait, pet)
	portrait_wrap.add_child(portrait)            # 立绘在辉光之上
	host._dt_portrait.add_child(portrait_wrap)

	# PoC .dp-name-row: 居中, 名 + 填充稀有 badge + Lv
	var name_row = HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", host._sp(8))
	var nm = Label.new()
	nm.text = pet.get("name", "?")
	nm.add_theme_font_size_override("font_size", host._sf(20))
	nm.add_theme_color_override("font_color", rcolor)
	name_row.add_child(nm)
	name_row.add_child(host._make_rarity_badge(rarity, rcolor, 12))   # PoC .dp-rarity 填充底 font:12px
	var lvl = Label.new()
	lvl.text = "Lv.%d" % det_lv
	lvl.add_theme_font_size_override("font_size", host._sf(13))
	lvl.add_theme_color_override("font_color", Color("#ffd86b"))
	name_row.add_child(lvl)
	host._dt_name.add_child(name_row)

	# PoC .dp-stats: 2 列网格 (1fr 1fr)
	var stats_grid = GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", host._sp(12))
	stats_grid.add_theme_constant_override("v_separation", host._sp(4))
	stats_grid.add_child(_stat_row("res://assets/sprites/stats/hp-icon.png", "生命值", hp))
	stats_grid.add_child(_stat_row("res://assets/sprites/stats/atk-icon.png", "攻击力", atk))
	stats_grid.add_child(_stat_row("res://assets/sprites/stats/def-icon.png", "防御力", def_))
	stats_grid.add_child(_stat_row("res://assets/sprites/stats/mr-icon.png", "魔抗", mr))
	host._dt_stats.add_child(stats_grid)

	# 被动 chip (PoC .dp-passive-chip: 绿底圆角框 + 图标 + 名(#7dffb3) + "被动" pill)
	var passive_raw = pet.get("passive")
	if passive_raw is Dictionary and not (passive_raw as Dictionary).is_empty():
		var passive: Dictionary = passive_raw
		var chip = PanelContainer.new()
		var chip_sb = StyleBoxFlat.new()
		chip_sb.bg_color = Color(125.0/255, 1, 179.0/255, 0.08)
		chip_sb.border_color = Color(125.0/255, 1, 179.0/255, 0.28)
		chip_sb.set_border_width_all(1)
		chip_sb.set_corner_radius_all(host._sp(8))
		chip_sb.content_margin_left = host._sp(8); chip_sb.content_margin_right = host._sp(8)   # PoC .dp-passive-chip padding:5px 8px (L/R 8)
		chip_sb.content_margin_top = host._sp(5); chip_sb.content_margin_bottom = host._sp(5)   # T/B 5
		## 换成金属小框(和图鉴/背包的 chip 同一张), 绿色留在 modulate 里 —— 被动一眼还是绿的。
		var chip_tex := UISkin.nine("chip-frame.png", 7, chip_sb)
		if chip_tex is StyleBoxTexture:
			(chip_tex as StyleBoxTexture).modulate_color = Color(0.62, 1.45, 0.92, 1.0)
			(chip_tex as StyleBoxTexture).content_margin_left = host._sp(8)
			(chip_tex as StyleBoxTexture).content_margin_right = host._sp(8)
			(chip_tex as StyleBoxTexture).content_margin_top = host._sp(5)
			(chip_tex as StyleBoxTexture).content_margin_bottom = host._sp(5)
		chip.add_theme_stylebox_override("panel", chip_tex)
		var prow = HBoxContainer.new()
		prow.add_theme_constant_override("separation", host._sp(6))
		var pi_path: String = DataRegistry.passive_icons.get(passive.get("type", ""), "")
		if pi_path != "" and pi_path.ends_with(".png"):
			var full = "res://assets/sprites/" + pi_path
			if ResourceLoader.exists(full):
				var pic = TextureRect.new()
				pic.texture = load(full)
				pic.custom_minimum_size = Vector2(host._sp(34), host._sp(34))   # 被动图标调大(用户2026-07-18·原22)
				pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				prow.add_child(pic)
		var pnm = Label.new()
		pnm.text = passive.get("name", "被动")
		pnm.add_theme_font_size_override("font_size", host._sf(17))   # 被动名调大(用户2026-07-18·原13)
		pnm.add_theme_color_override("font_color", Color("#7dffb3"))
		pnm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prow.add_child(pnm)
		# "被动" pill
		var tag_pc = PanelContainer.new()
		var tag_sb = StyleBoxFlat.new()
		tag_sb.bg_color = Color(125.0/255, 1, 179.0/255, 0.18)
		tag_sb.set_corner_radius_all(host._sp(4))
		tag_sb.content_margin_left = host._sp(5); tag_sb.content_margin_right = host._sp(5)
		tag_sb.content_margin_top = host._sp(1); tag_sb.content_margin_bottom = host._sp(1)
		tag_pc.add_theme_stylebox_override("panel", tag_sb)
		var tag_lbl = Label.new()
		tag_lbl.text = "被动"
		tag_lbl.add_theme_font_size_override("font_size", host._sf(10))
		tag_lbl.add_theme_color_override("font_color", Color("#7dffb3"))
		tag_pc.add_child(tag_lbl)
		prow.add_child(tag_pc)
		chip.add_child(prow)
		# 被动描述只在 hover 看 (1:1 PoC ts:796/825 "悬浮看描述 省空间") — 不常驻铺文字(撑爆面板的自创)
		var fake_f = {"atk": atk, "def": def_, "mr": mr, "maxHp": hp, "crit": pet.get("crit", 0.25), "lv": det_lv, "passive": passive}
		chip.tooltip_text = "%s\n%s" % [passive.get("name", "被动"), SkillText.render_bbcode(str(passive.get("brief", "")), fake_f, passive, 14)]
		# 内容 IGNORE 鼠标 → 整 chip 捕获 hover 出 tooltip
		prow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pnm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 点/触 被动 → 弹窗看描述 (PC 悬停之外再补点按, 手机唯一途径)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		var _passive_tip: String = chip.tooltip_text
		chip.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				host._show_detail_popup_from(_passive_tip, Color("#7dffb3"), chip.get_global_rect()))
		host._dt_passive.add_child(chip)

	# ── 下块: 技能 3选1 ──
	host._skill_picker._build_skill_picker(pet)


func _stat_row(icon_path: String, label: String, val: int) -> HBoxContainer:
	# PoC .dp-stat: icon + 标签(灰,占满) + 值(白,右对齐)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", host._sp(6))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ResourceLoader.exists(icon_path):
		var ic = TextureRect.new()
		ic.texture = load(icon_path)
		ic.custom_minimum_size = Vector2(host._sp(16), host._sp(16))
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(ic)
	var lbl = Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", host._sf(13))
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var v = Label.new()
	v.text = str(val)
	v.add_theme_font_size_override("font_size", host._sf(13))
	v.add_theme_color_override("font_color", Color(1, 1, 1))
	row.add_child(v)
	return row


