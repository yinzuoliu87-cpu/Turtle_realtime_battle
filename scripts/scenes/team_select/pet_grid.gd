class_name PetGrid
extends RefCounted
## 选龟页·龟卡片网格(填充/建卡·稀有度badge和立绘helper留主场景共享)
## 类内名不变;外部名加 battle.

var host

func _init(b) -> void:
	host = b

func _refresh_grid() -> void:
	for c in host._grid_flow.get_children():
		c.queue_free()
	# active 稀有度按钮 (PoC .pg-rarity-btn.active = 金渐变填充 + 深字)
	for rb in host._rarity_btns:
		var b: Button = rb["btn"]
		host._style_rarity_btn(b, rb["key"] == host.filter_rarity)

	var pets: Array = DataRegistry.launch_pets.duplicate()
	# ★教学模式: 只显 3 只教学龟(用户2026-07-23"选龟时下面只显示教学用的三只龟"), 免得新手又懵。
	var _td = host.get_node_or_null("/root/TutorialDirector")
	if _td != null and _td.is_active():
		var keep: Array = _td.FIXED_TEAM
		var filt: Array = []
		for p2 in pets:
			if str(p2.get("id", "")) in keep:
				filt.append(p2)
		if not filt.is_empty():
			pets = filt
	# rarity filter
	if host.filter_rarity != "all":
		var filtered: Array = []
		for p in pets:
			if p.get("rarity", "") == host.filter_rarity:
				filtered.append(p)
		pets = filtered
	# sort by rarity (PoC default)
	pets.sort_custom(func(a, b): return host.RARITY_ORDER.find(a.get("rarity", "C")) < host.RARITY_ORDER.find(b.get("rarity", "C")))

	for pet in pets:
		host._grid_flow.add_child(_make_pet_card(pet))
	# 锁定态: 候选池灰显(去强调) — 表明本大轮不能改阵容; 卡片仍可点=查看详情/调技能, 只是不入队.
	host._grid_flow.modulate = Color(1, 1, 1, 0.55) if host._roster_locked else Color(1, 1, 1, 1)


func _make_pet_card(pet: Dictionary) -> Control:
	var pid: String = pet["id"]
	var rarity: String = pet.get("rarity", "C")
	var rcolor: Color = host.RARITY_COLOR.get(rarity, Color.WHITE)
	var selected = pid in host.team

	# PoC .pet-card 卡 = 纯 Control 叠层: 背景框(满) + 内容(padding内缩, 上→下 头像→meta) + badge(相对卡) + 被动(相对头像)
	var card = Control.new()
	# 宽=填满行均分(≥116, 1:1 PoC minmax(116,1fr) 卡拉伸); 高 ~116. 原固定116²方卡左packed留白=用户报"布局不同"
	card.custom_minimum_size = Vector2(host._grid_card_w, host._sp(116))
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb = StyleBoxFlat.new()
	if selected:
		sb.bg_color = Color(1, 216.0/255, 107.0/255, 0.1)
		sb.border_color = Color("#ffd86b")
	else:
		sb.bg_color = Color(74.0/255, 40.0/255, 16.0/255, 0.4)
		sb.border_color = Color(1, 216.0/255, 107.0/255, 0.2)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(host._sp(12))
	# 背景框铺满卡 (Panel; 让 badge/被动可绝对叠在卡边而非被 padding 推偏)
	var bg = Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", sb)
	card.add_child(bg)
	# ★手机端滑动(用户2026-07-22「选龟页面也是」):
	#   Control 默认 MOUSE_FILTER_STOP → GUI 事件不冒泡到外层 ScrollContainer, 龟池在触屏上滑不动。
	#   而 :848 又把滚动条设成 SHOW_NEVER(注释还写着"滚动仍启用(手机拖)") → 手机上【完全没有滚动手段】。
	#   解法照抄项目已实机验证的模板 InventoryScene.gd:651: PASS + 按下/抬起位移阈值判点选。
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var _press = {"p": Vector2.ZERO}
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_press["p"] = ev.position
			elif ev.position.distance_to(_press["p"]) < 16.0:   # 位移小才算点选, 否则那是在滑列表
				host._set_detail_pet(pid)
				host._on_pick_pet(pid))
	# 拖放: 卡片可拖入编队槽 (1:1 PoC .pet-card draggable=true)
	# ★手机上必须关掉: Godot 原生 DnD 一旦启动就吃掉手指移动, 滚动永远抢不过它。
	#   触屏改走"点卡片(上面的 _on_pick_pet) → 点槽位"两步。
	if not SafeArea.is_mobile():
		card.set_drag_forwarding(host._card_drag.bind(card, pid), Callable(), Callable())

	# 内容: MarginContainer(满卡 + PoC padding:10px 8px 8px) → VBox(头像 → meta, 顶对齐自然流)
	var pad_wrap = MarginContainer.new()
	pad_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad_wrap.add_theme_constant_override("margin_left", host._sp(8))
	pad_wrap.add_theme_constant_override("margin_right", host._sp(8))
	pad_wrap.add_theme_constant_override("margin_top", host._sp(10))
	pad_wrap.add_theme_constant_override("margin_bottom", host._sp(8))
	pad_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(pad_wrap)
	var vb = VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_BEGIN   # 头像在上 meta 紧随 (PoC 自然流, 非垂直居中)
	vb.add_theme_constant_override("separation", host._sp(4))   # PoC .pet-avatar margin-bottom:4
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad_wrap.add_child(vb)

	# 头像区 (PoC .pet-avatar min-height:76 position:relative → 被动相对它定位)
	var av_area = Control.new()
	av_area.custom_minimum_size = Vector2(0, host._sp(76))
	av_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	av_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(av_area)
	# 72px 全身 idle 动画 (1:1 PoC buildPetImgHTML(pet,72); 默认 paused, hover/selected 才播)
	var av = TextureRect.new()
	av.set_anchors_preset(Control.PRESET_FULL_RECT)
	av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host._apply_pet_idle_texture(av, pet, selected)
	av_area.add_child(av)
	# 被动图标 (PoC .pet-passive-icon: 相对**头像**右上探出 top:-8 right:-8)
	var passive_raw = pet.get("passive")
	if passive_raw is Dictionary and not (passive_raw as Dictionary).is_empty():
		var pi_path: String = DataRegistry.passive_icons.get((passive_raw as Dictionary).get("type", ""), "")
		if pi_path.ends_with(".png"):
			var full = "res://assets/sprites/" + pi_path
			if ResourceLoader.exists(full):
				var pcirc = PanelContainer.new()
				pcirc.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var pc_sb = StyleBoxFlat.new()
				pc_sb.bg_color = Color(10.0/255, 14.0/255, 24.0/255, 1.0)
				pc_sb.set_corner_radius_all(host._sp(17))
				pc_sb.content_margin_left = host._sp(4); pc_sb.content_margin_right = host._sp(4)
				pc_sb.content_margin_top = host._sp(4); pc_sb.content_margin_bottom = host._sp(4)
				pcirc.add_theme_stylebox_override("panel", pc_sb)
				var pic = TextureRect.new()
				pic.texture = load(full)
				pic.custom_minimum_size = Vector2(host._sp(26), host._sp(26))   # PoC img 26px
				pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
				pcirc.add_child(pic)
				pcirc.set_anchors_preset(Control.PRESET_TOP_RIGHT)
				pcirc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
				pcirc.grow_vertical = Control.GROW_DIRECTION_END
				av_area.add_child(pcirc)
				pcirc.position += Vector2(host._sp(8), -host._sp(8))   # 探出右上 right:-8 top:-8

	# meta 行: Lv + 名 同一行 (PoC .pet-meta flex baseline center gap5)
	var meta = HBoxContainer.new()
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	meta.add_theme_constant_override("separation", host._sp(5))
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lv = Label.new()
	lv.text = "Lv.%d" % GameState.get_pet_level(pid)   # PoC pet-card lv=getPetLevel
	lv.add_theme_font_size_override("font_size", host._sf(11))
	lv.add_theme_color_override("font_color", Color("#ffd86b"))   # PoC .pet-lv #ffd86b
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(lv)
	var nm = Label.new()
	nm.text = pet.get("name", "?")
	nm.add_theme_font_size_override("font_size", host._sf(13))   # PoC .pet-name 13px (无色=浅色继承)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(nm)
	vb.add_child(meta)

	# 稀有度 badge (PoC .pet-rarity-badge 相对**卡片** top:6 left:6) — 挂 card 绝对定位, 渲染最上层
	var badge = host._make_rarity_badge(rarity, rcolor)
	badge.position = Vector2(host._sp(6), host._sp(6))
	card.add_child(badge)

	# hover (1:1 PoC .pet-card:hover translateY(-2)+金边+柔光; 非选中 idle hover才播)
	var base_border: Color = sb.border_color
	card.mouse_entered.connect(func() -> void:
		if not is_instance_valid(card): return
		if card.get_meta("hovered", false): return
		card.set_meta("hovered", true)
		card.set_meta("rest_y", card.position.y)
		sb.border_color = Color("#ffd86b")
		sb.shadow_color = Color(1.0, 216.0 / 255.0, 107.0 / 255.0, 0.18)
		sb.shadow_size = host._sp(6)
		sb.shadow_offset = Vector2(0, host._sp(4))
		var t = av.get_meta("idle_tw", null)
		if t is Tween and (t as Tween).is_valid(): (t as Tween).play()
		var tw = card.create_tween()
		tw.tween_property(card, "position:y", card.position.y - 2.0 * host._s(), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT))
	card.mouse_exited.connect(func() -> void:
		if not is_instance_valid(card): return
		if not card.get_meta("hovered", false): return
		card.set_meta("hovered", false)
		sb.border_color = base_border
		sb.shadow_size = 0
		if not selected:
			var t = av.get_meta("idle_tw", null)
			if t is Tween and (t as Tween).is_valid():
				(t as Tween).pause()
				if av.texture is AtlasTexture:
					var at = av.texture as AtlasTexture
					at.region = Rect2(0, 0, at.region.size.x, at.region.size.y)
		var rest_y: float = card.get_meta("rest_y", card.position.y)
		var tw = card.create_tween()
		tw.tween_property(card, "position:y", rest_y, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT))

	return card


## 给 TextureRect 装龟的全身 idle 动画 (1:1 PoC buildPetImgHTML: pet.img 全身 sheet + sprite{} 帧).
##   有 sprite{frameW} → AtlasTexture 逐帧循环(同战斗 makeView 的 fps 公式); 无 sprite{} → 静态 body PNG;
##   img 缺 → avatars 头像回退。PoC 卡片/立绘是会 idle 跳动的全身龟, 非静态头像。
