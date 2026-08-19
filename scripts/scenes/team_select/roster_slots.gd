class_name RosterSlots
extends RefCounted
## 选龟页·6阵容槽(前3后3·建/刷/拖放·_mark_label和_sync_special_slots跨区共享留主场景)
## 类内名不变;外部名加 battle.

var host

func _init(b) -> void:
	host = b

func _build_slots() -> void:
	host._slot_nodes = []
	# 暗托盘: 盖住背景图烤死的 6 格 + 前/后排横幅, 留出干净 3 格区 (木框边沿保留)
	var tray = Panel.new()
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tb = StyleBoxFlat.new()
	tb.bg_color = Color8(42, 28, 17)            # 木盘色(比格子亮), 格子是更暗的内陷
	tb.set_corner_radius_all(host._sp(10))
	tb.border_width_top = 2; tb.border_width_bottom = 2; tb.border_width_left = 2; tb.border_width_right = 2
	tb.border_color = Color8(26, 17, 10)        # 内陷暗边, 给托盘一点深度
	tray.add_theme_stylebox_override("panel", tb)
	host.root.add_child(tray)
	host._place(tray, "slotBay")
	for i in range(3):
		var panel = PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		host.root.add_child(panel)
		host._place(panel, "slot%d" % i)
		# 空槽透明 (露出背景画好的 "+"); 填充后 _refresh_slots 换金边样式
		panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		# 整槽点击 → tap-swap
		var idx = i
		panel.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_on_slot_click(idx))
		# 拖放: 满槽可拖起 + 任意槽可作落点 (1:1 PoC slot draggable + drop)
		panel.set_drag_forwarding(_slot_drag.bind(panel, idx), _slot_can_drop, _slot_drop.bind(idx))
		# 内容容器
		var vb = VBoxContainer.new()
		vb.name = "Content"
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", host._sp(2))
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(vb)
		host._slot_nodes.append(panel)


func _refresh_slots() -> void:
	for i in range(3):
		var panel: PanelContainer = host._slot_nodes[i]
		var vb: VBoxContainer = panel.get_node("Content")
		for c in vb.get_children():
			c.queue_free()
		var id = host.team[i]
		if id == null:
			# 空槽: active(待填, 黄亮边)/ 否则暗格 (背景烤的 "+" 已被 slotBay 托盘盖住 → 代码画暗格 + "+")
			panel.add_theme_stylebox_override("panel", _slot_box("active") if i == host._active_slot_idx else _slot_box("empty"))
			var plus = Label.new()
			plus.text = "+"
			plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			plus.add_theme_font_size_override("font_size", host._sf(34))
			plus.add_theme_color_override("font_color", Color8(150, 120, 84))
			plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vb.add_child(plus)
			continue
		# 满槽/占位: selected(tap-swap 选中, PoC .fg-selected 金亮边)/ 否则普通 filled
		panel.add_theme_stylebox_override("panel", _slot_box("selected" if i == host._selected_slot_idx else "filled"))
		if host._is_special_mark(id):
			_fill_mark_slot(vb, id)
			continue
		var pet: Dictionary = DataRegistry.pet_by_id.get(id, {})
		if pet.is_empty():
			panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			continue
		# PoC .fg-turtle img width:70% — 槽宽(108*s)×0.7
		var av = TextureRect.new()
		var slot_av = host._sp(108 * 0.7)   # PoC img width:70% of slot (108 设计宽)
		av.custom_minimum_size = Vector2(slot_av, slot_av)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var av_path = "res://assets/sprites/avatars/%s.png" % id
		if ResourceLoader.exists(av_path):
			av.texture = load(av_path)
		vb.add_child(av)
		# PoC .fg-name font-size:10px
		var nm = Label.new()
		nm.text = pet.get("name", "?")
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", host._sf(10))
		nm.add_theme_color_override("font_color", host.RARITY_COLOR.get(pet.get("rarity", "C"), Color.WHITE))
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(nm)


## 槽样式 (1:1 PoC .fg-slot.filled/.fg-selected/.fg-active index.html:280-291)
## 三个统领槽的框。原来是纯色圆角盒 + StyleBoxFlat 的外发光, 一眼网页味;
## 现在跟 pet_grid 的龟卡用**同一张卡框**(84x121 本来就是卡的形状), 四个状态靠 modulate 分。
## ★StyleBoxTexture 没有 shadow_* —— "选中"原本全靠外发光顶出来, 换框后只能靠**过曝**,
##   所以选中态的 modulate 给到 2.2 而不是 1.5(HDR, >1 才是真的比周围亮一档)。
func _slot_box(kind: String) -> StyleBox:
	var sb = StyleBoxFlat.new()
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(host._sp(12))
	var tint := Color(1, 1, 1, 1)
	if kind == "empty":   # 实时空格: 暗内陷格 + 微木边 (替代背景图烤死的 "+" 格, 已被 slotBay 托盘盖住)
		sb.bg_color = Color8(24, 17, 12)
		sb.border_color = Color8(72, 50, 30)
		tint = Color(0.42, 0.34, 0.26, 1.0)          # 空槽: 压暗成"待填的凹坑"
	elif kind == "selected":   # PoC .fg-selected #ffcc00 + glow rgba(255,204,0,.55)
		sb.bg_color = Color(1, 204.0/255, 0, 0.18)
		sb.border_color = Color("#ffcc00")
		sb.shadow_color = Color(1, 204.0/255, 0, 0.55); sb.shadow_size = host._sp(6)
		tint = Color(2.2, 1.80, 0.55, 1.0)           # 选中: 过曝金(顶替原来的外发光)
	elif kind == "active":   # PoC .fg-active #fff3a0 + glow rgba(255,243,160,.6)
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color("#fff3a0")
		sb.shadow_color = Color(1, 243.0/255, 160.0/255, 0.6); sb.shadow_size = host._sp(6)
		tint = Color(2.1, 2.00, 1.30, 1.0)           # 待放入: 过曝的淡黄
	else:   # filled: 金边半透底 + 外发光
		sb.bg_color = Color(1, 216.0/255, 107.0/255, 0.1)
		sb.border_color = Color(1, 216.0/255, 107.0/255, 0.7)
		sb.shadow_color = Color(1, 216.0/255, 107.0/255, 0.3); sb.shadow_size = host._sp(4)
		tint = Color(1.35, 1.16, 0.72, 1.0)          # 已就位: 温金
	var tsb := UISkin.nine_if_big(host._sp(84), host._sp(116), "teamselect/card-frame.png", 14, sb)
	if tsb is StyleBoxTexture:
		(tsb as StyleBoxTexture).modulate_color = tint
	return tsb


## 渲染特殊占位槽内容 (1:1 PoC .fg-summon TeamSelectScene.ts:591-598): 随从?/水晶球img/糖果炸弹emoji + 彩色名
func _fill_mark_slot(vb: VBoxContainer, mark: String) -> void:
	var nm_text = ""
	var nm_color = Color.WHITE
	if mark == host.SUMMON_MARK:
		nm_text = "随从"; nm_color = Color("#ffc850")
		var q = Label.new()
		q.text = "?"
		q.add_theme_font_size_override("font_size", host._sf(28))
		q.add_theme_color_override("font_color", Color("#ffc850"))
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(q)
	elif mark == host.CRYSTAL_BALL_MARK:
		nm_text = "水晶球"; nm_color = Color("#9b6bff")
		var img = TextureRect.new()
		img.custom_minimum_size = Vector2(host._sp(32), host._sp(32))
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cb = "res://assets/sprites/pets/crystal-ball.png"
		if ResourceLoader.exists(cb):
			img.texture = load(cb)
		vb.add_child(img)
	else:   # CANDY_BOMB_MARK
		nm_text = "糖果炸弹"; nm_color = Color("#ff6bd8")
		var e = Label.new()
		e.text = "🍬💣"
		e.add_theme_font_size_override("font_size", host._sf(22))
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(e)
	var nm = Label.new()
	nm.text = nm_text
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", host._sf(10))
	nm.add_theme_color_override("font_color", nm_color)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)


func _on_slot_click(idx: int) -> void:
	if host._roster_locked:
		if host.team[idx] != null and not host._is_special_mark(host.team[idx]):
			host._set_detail_pet(str(host.team[idx]))   # 锁定态: 点槽=查看该龟(调技能), 不换位/不移除
		return
	var id = host.team[idx]
	var is_mark: bool = id != null and host._is_special_mark(id)
	# === 满槽路径 ===
	if id != null:
		if host._selected_slot_idx == -1:
			host._selected_slot_idx = idx           # 首次 tap: 选中
			host._active_slot_idx = -1
			_refresh_slots()
			return
		if host._selected_slot_idx == idx:
			host._selected_slot_idx = -1            # 二次 tap 同槽: 取消选中 + 移除 (mark 不移)
			if not is_mark:
				host.team[idx] = null
				host._sync_special_slots()
				host._save_team()
			host._refresh_after_team()
			return
		# 二次 tap 不同满槽: SWAP
		var other = host._selected_slot_idx
		var other_is_mark: bool = host._is_special_mark(host.team[other])
		if is_mark or other_is_mark:
			# mark 只能移到空格, 不能与满槽互换 (PoC:1609)
			var mark_from = other if other_is_mark else idx
			var target = idx if other_is_mark else other
			var mark_value = host.team[mark_from]
			if host.team[target] != null:
				host._flash_status("%s 不能被替换" % host._mark_label(mark_value))
				host._selected_slot_idx = -1
				_refresh_slots()
				return
			host.team[target] = mark_value
			host.team[mark_from] = null
		else:
			# 普通 swap
			var tmp = host.team[other]
			host.team[other] = host.team[idx]
			host.team[idx] = tmp
		host._selected_slot_idx = -1
		host._save_team()
		host._refresh_after_team()
		return
	# === 空槽路径 ===
	# (a) 有选中满槽 → 把已选龟移到这 (PoC:1640)
	if host._selected_slot_idx >= 0 and host.team[host._selected_slot_idx] != null:
		host.team[idx] = host.team[host._selected_slot_idx]
		host.team[host._selected_slot_idx] = null
		host._selected_slot_idx = -1
		host._sync_special_slots()
		host._save_team()
		host._refresh_after_team()
		return
	# (b) 空槽 toggle active — 下次点卡片入此槽 (PoC:1651)
	host._selected_slot_idx = -1
	host._active_slot_idx = -1 if host._active_slot_idx == idx else idx
	_refresh_slots()


func _slot_drag(_at_pos: Vector2, panel: Control, idx: int) -> Variant:
	if host._roster_locked:
		return null   # 大轮锁定: 禁槽间换位
	var id = host.team[idx]
	if id == null:
		return null
	panel.set_drag_preview(host._make_drag_preview(str(id)))
	return {"pet_id": str(id)}


func _slot_can_drop(_at_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("pet_id")


## drop 到槽 (drop_func; bind → (at_pos, data, idx))
func _slot_drop(_at_pos: Vector2, data: Variant, idx: int) -> void:
	if data is Dictionary and (data as Dictionary).has("pet_id"):
		host._on_drop_pet(str((data as Dictionary)["pet_id"]), idx)


## 拖放落点处理 (1:1 PoC onDropPet TeamSelectScene.ts:1160)
