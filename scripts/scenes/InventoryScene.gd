extends Control

## InventoryScene — V2 局外背包 / 出战配置 (阶段2 UI 首版, 设计§十).
## 上部: 出战阵容 (上路/下路, 龟统领 + 小将占位); 下部: 装备管理 (背包 bench).
## 首版 = 布局 + 显示 (实时挤位/防吞/装备拖拽/3合1 后续迭代). 截图验证布局用.
## 数据: season_leaders(锁定3统领) 优先, 空则 lastLineup.json 末次阵容; persistent_bench(持久背包).

const W := 1280.0
const H := 720.0
const SLOT := 96.0
const GS := 74.0   # 阵容 6 格定位网格的格子尺寸
const P2 = preload("res://scripts/engine/phase2_config.gd")
const Phase2Types = preload("res://scripts/engine/phase2_types.gd")

var _sel_bench: int = -1   # 当前选中的背包装备索引 (-1=无)
var _sel_unit: Dictionary = {}   # 当前选中的阵容单位 {lane, slot} (摆位用)

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		c.visible = false   # 立即隐藏避免与新节点重叠 (queue_free 延到帧末, 不在信号中即时free防崩)
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Color("#0a1622")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 标题
	var title := Label.new()
	title.text = "🎒 背包 / 出战配置"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("#ffd93d"))
	title.position = Vector2(W / 2.0 - 220, 22); title.size = Vector2(440, 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	# 返回
	var back := Button.new()
	back.text = "← 返回"
	back.add_theme_font_size_override("font_size", 20)
	back.position = Vector2(28, 26); back.size = Vector2(120, 44)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	add_child(back)

	# 深海币 (右上)
	var coin := Label.new()
	coin.text = "💠 深海币 %d" % int(GameState.meta_deepsea_coins)
	coin.add_theme_font_size_override("font_size", 22)
	coin.add_theme_color_override("font_color", Color("#5fd0e0"))
	coin.position = Vector2(W - 260, 30); coin.size = Vector2(232, 32)
	coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(coin)

	var leaders := _lineup_ids()
	_build_lineup(leaders)
	_build_synergy_panel(leaders)
	_build_bench()
	_build_actions()

## 取出战 3 统领: season_leaders 优先, 空则 lastLineup.json.
func _lineup_ids() -> Array:
	if GameState.season_leaders is Array and (GameState.season_leaders as Array).size() > 0:
		return GameState.season_leaders.duplicate()
	if FileAccess.file_exists("user://lastLineup.json"):
		var f := FileAccess.open("user://lastLineup.json", FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text()); f.close()
			if parsed is Dictionary and (parsed as Dictionary).has("ids"):
				return (parsed["ids"] as Array).duplicate()
	return []

# ─── 上部: 出战阵容 (上路 / 下路) ───
func _build_lineup(leaders: Array) -> void:
	var hdr := Label.new()
	hdr.text = "出战阵容 — 每路 6 格定位 (前3后3) · 点单位→点格子摆位; 选装备时点龟=装上"
	hdr.add_theme_font_size_override("font_size", 15); hdr.add_theme_color_override("font_color", Color("#9fb6c9"))
	hdr.position = Vector2(60, 84); hdr.size = Vector2(630, 22); add_child(hdr)
	var assign := _lane_assign(leaders)
	GameState.lane_loadout = assign
	for lane in [["上路", "top", 60.0], ["下路", "bottom", 372.0]]:
		var lname := str(lane[0]); var lkey := str(lane[1]); var lx := float(lane[2])
		var ll := Label.new(); ll.text = lname
		ll.add_theme_font_size_override("font_size", 16); ll.add_theme_color_override("font_color", Color("#ffd93d"))
		ll.position = Vector2(lx, 112); ll.size = Vector2(120, 22); add_child(ll)
		for ri in range(2):
			var rkey := "front" if ri == 0 else "back"
			var rl := Label.new(); rl.text = "前排" if ri == 0 else "后排"
			rl.add_theme_font_size_override("font_size", 11); rl.add_theme_color_override("font_color", Color("#6a7585"))
			rl.position = Vector2(lx, 140 + ri * int(GS + 8) + int(GS / 2.0) - 8); rl.size = Vector2(32, 16); add_child(rl)
			for col in range(3):
				var sk := "%s-%d" % [rkey, col]
				add_child(_grid_slot(lkey, sk, str(assign.get(lkey, {}).get(sk, "")), Vector2(lx + 36 + col * (GS + 6), 140 + ri * (GS + 8))))

## 分路+定位: lane_loadout 优先, 缺则默认(前2龟上路前排, 3龟下路前排, 各路1小将后排中).
func _lane_assign(leaders: Array) -> Dictionary:
	var ll = GameState.lane_loadout
	if ll is Dictionary and (ll.has("top") or ll.has("bottom")):
		return (ll as Dictionary).duplicate(true)
	var a := {"top": {}, "bottom": {}}
	if leaders.size() >= 1: a["top"]["front-0"] = str(leaders[0])
	if leaders.size() >= 2: a["top"]["front-1"] = str(leaders[1])
	if leaders.size() >= 3: a["bottom"]["front-1"] = str(leaders[2])
	a["top"]["back-1"] = "__minion__"
	a["bottom"]["back-1"] = "__minion__"
	return a

func _grid_slot(lane: String, slot_key: String, pid: String, pos: Vector2) -> Control:
	var sel := str(_sel_unit.get("lane", "")) == lane and str(_sel_unit.get("slot", "")) == slot_key
	var is_min := pid == "__minion__"
	var occupied := pid != "" and not is_min
	var box := _slot_panel(pos, (Color("#13314a") if occupied else (Color("#1a1f28") if is_min else Color("#0e1923"))), (Color("#ffd93d") if sel else (Color("#2e5a7e") if occupied else Color("#2a3340"))))
	box.size = Vector2(GS, GS)
	if is_min:
		_slot_center_label(box, "小将", Color("#7a8595"))
	elif occupied:
		var pet: Dictionary = DataRegistry.pet_by_id.get(pid, {})
		var av := "res://assets/sprites/avatars/%s.png" % pid
		if ResourceLoader.exists(av):
			var a := TextureRect.new(); a.texture = load(av)
			a.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; a.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			a.position = Vector2(GS / 2.0 - 22, 4); a.size = Vector2(44, 38); box.add_child(a)
		var eqs: Array = GameState.persistent_equipped.get(pid, [])
		_draw_equip_cells(box, eqs, P2.equip_slots_for_level(int(GameState.season_level)), 45.0)   # 装备槽 → 可视小格 (替代"装N/M"文字)
		var nm := Label.new(); nm.text = str(pet.get("name", pid))
		nm.add_theme_font_size_override("font_size", 11); nm.add_theme_color_override("font_color", Color("#e8f2ff"))
		nm.position = Vector2(0, GS - 16); nm.size = Vector2(GS, 14); nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(nm)
	else:
		_slot_center_label(box, "·", Color("#3a4452"))
	for ch in box.get_children():
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _on_grid_click(lane, slot_key, pid))
	return box

func _slot_center_label(box: Control, txt: String, col: Color) -> void:
	var l := Label.new(); l.text = txt
	l.add_theme_font_size_override("font_size", 13); l.add_theme_color_override("font_color", col)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(l)
## 龟身装备槽可视化: 画 slots 个小格 (满格=该件稀有度色, 空格=暗轮廓), 居中一行. 替代"装N/M"文字.
func _draw_equip_cells(box: Control, eqs: Array, slots: int, y: float) -> void:
	var cw := 10.0
	var gap := 3.0
	var total := slots * cw + maxf(0.0, float(slots - 1)) * gap
	var x0 := box.size.x / 2.0 - total / 2.0
	for idx in range(slots):
		var cell := Panel.new()
		var csb := StyleBoxFlat.new()
		if idx < eqs.size():
			var eid := str((eqs[idx] as Dictionary).get("id", ""))
			var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
			csb.bg_color = _rarity_color(str(edef.get("rarity", "普通")))
			csb.border_color = Color(1, 1, 1, 0.45)
		else:
			csb.bg_color = Color(0, 0, 0, 0.35)
			csb.border_color = Color("#3a4452")
		csb.set_border_width_all(1); csb.set_corner_radius_all(2)
		cell.add_theme_stylebox_override("panel", csb)
		cell.position = Vector2(x0 + idx * (cw + gap), y)
		cell.size = Vector2(cw, cw)
		box.add_child(cell)

## 点格子: 选了装备+点龟=装备; 否则=单位摆位(无选中→选中, 已选中→移到该格, 占用则交换).
func _on_grid_click(lane: String, slot_key: String, pid: String) -> void:
	if _sel_bench >= 0 and pid != "" and pid != "__minion__":
		_equip_to(pid, _sel_bench)
		return
	var a: Dictionary = GameState.lane_loadout.duplicate(true) if GameState.lane_loadout is Dictionary else {"top": {}, "bottom": {}}
	if _sel_unit.is_empty():
		if pid != "":
			_sel_unit = {"lane": lane, "slot": slot_key}
		_rebuild()
		return
	var sl := str(_sel_unit.get("lane", "")); var sk := str(_sel_unit.get("slot", ""))
	if not a.has(lane): a[lane] = {}
	if not a.has(sl): a[sl] = {}
	var moving := str((a[sl] as Dictionary).get(sk, ""))
	var target := str((a[lane] as Dictionary).get(slot_key, ""))
	a[lane][slot_key] = moving
	if target != "":
		a[sl][sk] = target
	else:
		(a[sl] as Dictionary).erase(sk)
	GameState.lane_loadout = a
	_sel_unit = {}
	GameState.save()
	_rebuild()

## 龟统领格子: 立绘 + 名 + 装备数/槽.
func _turtle_slot(pet_id: String, pos: Vector2) -> Control:
	var box := _slot_panel(pos, Color("#13314a"), Color("#2e5a7e"))
	var pet: Dictionary = DataRegistry.pet_by_id.get(pet_id, {})
	var av_path := "res://assets/sprites/avatars/%s.png" % pet_id
	if ResourceLoader.exists(av_path):
		var av := TextureRect.new(); av.texture = load(av_path)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		av.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		av.position = Vector2(SLOT / 2.0 - 28, 24); av.size = Vector2(56, 46)
		box.add_child(av)
	var nm := Label.new()
	nm.text = str(pet.get("name", pet_id))
	nm.add_theme_font_size_override("font_size", 14)
	nm.add_theme_color_override("font_color", Color("#e8f2ff"))
	nm.position = Vector2(0, SLOT - 22); nm.size = Vector2(SLOT, 20)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(nm)
	var eqs: Array = GameState.persistent_equipped.get(pet_id, []) if GameState.persistent_equipped is Dictionary else []
	var slots := P2.equip_slots_for_level(int(GameState.season_level))
	var eq := Label.new()
	eq.text = "装备 %d/%d" % [eqs.size(), slots]
	eq.add_theme_font_size_override("font_size", 12)
	eq.add_theme_color_override("font_color", Color("#7fd0a0"))
	eq.position = Vector2(0, 4); eq.size = Vector2(SLOT, 18)
	eq.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(eq)
	for ch in box.get_children():
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 透传点击给 box
	box.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _on_turtle_click(pet_id))
	return box

func _minion_slot(pos: Vector2) -> Control:
	var box := _slot_panel(pos, Color("#1a1f28"), Color("#3a4452"))
	var l := Label.new()
	l.text = "小将\n占位"
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color("#6a7585"))
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(l)
	return box

func _slot_panel(pos: Vector2, bg: Color, border: Color) -> Panel:
	var box := Panel.new()   # Panel(非PanelContainer): 子节点自由定位, 不被容器拉伸成重叠
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg; sb.border_color = border
	sb.set_border_width_all(2); sb.set_corner_radius_all(8)
	box.add_theme_stylebox_override("panel", sb)
	box.position = pos
	box.size = Vector2(SLOT, SLOT)
	return box

# ─── 右侧: 类型羁绊 (装备类型激活, 设计§十) ───
func _build_synergy_panel(leaders: Array) -> void:
	var hdr := Label.new(); hdr.text = "类型羁绊 (同类型装备越多越强)"
	hdr.add_theme_font_size_override("font_size", 18); hdr.add_theme_color_override("font_color", Color("#9fb6c9"))
	hdr.position = Vector2(700, 86); hdr.size = Vector2(520, 26); add_child(hdr)
	var all_equips: Array = []
	for pid in leaders:
		for it in GameState.persistent_equipped.get(str(pid), []):
			all_equips.append(it)
	var active: Array = Phase2Types.calc_active([{"_p2_equips": all_equips}])
	if active.is_empty():
		var e := Label.new(); e.text = "（给龟装多件同类型装备 → 激活羁绊加成）"
		e.add_theme_font_size_override("font_size", 14); e.add_theme_color_override("font_color", Color("#5a6675"))
		e.position = Vector2(704, 124); e.size = Vector2(540, 22); add_child(e)
		return
	var y := 122.0
	for a in active:
		var t := str(a.get("type", ""))
		var chip := Panel.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color("#16263a"); csb.border_color = Color("#3e6a8e")
		csb.set_border_width_all(2); csb.set_corner_radius_all(8)
		chip.add_theme_stylebox_override("panel", csb)
		chip.position = Vector2(700, y); chip.size = Vector2(530, 58); add_child(chip)
		var nm := Label.new()
		nm.text = "%s %s  ×%d  (档 %d)" % [Phase2Types.emoji_of(t), Phase2Types.display_name(t), int(a.get("count", 0)), int(a.get("tier", 1))]
		nm.add_theme_font_size_override("font_size", 17); nm.add_theme_color_override("font_color", Color("#ffd93d"))
		nm.position = Vector2(12, 6); nm.size = Vector2(506, 24); chip.add_child(nm)
		var desc := Label.new(); desc.text = Phase2Types.tier_desc(t, int(a.get("tier", 1)))
		desc.add_theme_font_size_override("font_size", 12); desc.add_theme_color_override("font_color", Color("#bcd0e0"))
		desc.position = Vector2(12, 30); desc.size = Vector2(506, 24); desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		chip.add_child(desc)
		y += 66

# ─── 下部: 装备管理 (背包 bench) ───
func _build_bench() -> void:
	var hdr := Label.new()
	hdr.text = "装备背包 (永不丢 · 战后全收)  —  点装备选中 → 点龟装上 · 再点龟身卸下 · 选中可卖 · 下方一键合星"
	hdr.add_theme_font_size_override("font_size", 18)
	hdr.add_theme_color_override("font_color", Color("#9fb6c9"))
	hdr.position = Vector2(60, 352); hdr.size = Vector2(1000, 26)
	add_child(hdr)
	var bench: Array = GameState.persistent_bench if GameState.persistent_bench is Array else []
	var gx := 64.0
	var gy := 392.0
	var per_row := 11
	var i := 0
	for it in bench:
		var col := i % per_row
		var row := i / per_row
		add_child(_equip_cell(it, i, Vector2(gx + col * (SLOT + 8), gy + row * (SLOT + 28))))
		i += 1
	# 补空格子 → 背包始终呈完整网格 (整行对齐, 空槽=暗格显·, 至少一行)
	var total_cells := maxi(per_row, int(ceil(float(bench.size()) / float(per_row))) * per_row)
	while i < total_cells:
		var col2 := i % per_row
		var row2 := i / per_row
		add_child(_empty_bench_cell(Vector2(gx + col2 * (SLOT + 8), gy + row2 * (SLOT + 28))))
		i += 1
	if bench.is_empty():
		var hint := Label.new()
		hint.text = "（背包空 — 去商店买装备）"
		hint.add_theme_font_size_override("font_size", 14); hint.add_theme_color_override("font_color", Color("#5a6675"))
		hint.position = Vector2(64, 392 + SLOT + 34); hint.size = Vector2(600, 22); add_child(hint)

func _rarity_color(rarity: String) -> Color:
	match rarity:
		"精良": return Color("#4ade80")
		"稀有": return Color("#60a5fa")
		"史诗": return Color("#c084fc")
		"传说": return Color("#fbbf24")
		_: return Color("#8a96a3")

func _empty_bench_cell(pos: Vector2) -> Control:
	var box := _slot_panel(pos, Color(0, 0, 0, 0.22), Color("#28323e"))
	_slot_center_label(box, "·", Color("#39434f"))
	for ch in box.get_children():
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box

func _equip_cell(it: Dictionary, idx: int, pos: Vector2) -> Control:
	var sel := idx == _sel_bench
	var eid := str(it.get("id", ""))
	var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
	var rcol := _rarity_color(str(edef.get("rarity", "普通")))
	var box := _slot_panel(pos, Color("#2a3a1c") if sel else Color("#1c2836"), Color("#ffd93d") if sel else rcol)
	var img := str(edef.get("img", ""))
	if img != "" and ResourceLoader.exists("res://assets/sprites/" + img):
		var ic := TextureRect.new(); ic.texture = load("res://assets/sprites/" + img)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.position = Vector2(SLOT / 2.0 - 22, 18); ic.size = Vector2(44, 36)
		box.add_child(ic)
	var nm := Label.new()
	nm.text = str(edef.get("name", eid))
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", Color("#e8f2ff"))
	nm.position = Vector2(2, SLOT - 36); nm.size = Vector2(SLOT - 4, 32)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(nm)
	var star := int(it.get("star", 1))
	var st := Label.new()
	st.text = "★".repeat(star)
	st.add_theme_font_size_override("font_size", 13)
	st.add_theme_color_override("font_color", Color("#ffd93d"))
	st.position = Vector2(0, 4); st.size = Vector2(SLOT, 18)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(st)
	for ch in box.get_children():
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.tooltip_text = "%s (%s)\n%s" % [str(edef.get("name", eid)), str(edef.get("rarity", "普通")), str(edef.get("effectDesc1", "（无主动效果）"))]
	box.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _on_bench_click(idx))
	return box


# ─── 交互: 点背包装备选中 → 点龟装上 (再点已选=取消; 点龟身无选中=卸最后一件回背包) ───
func _on_bench_click(idx: int) -> void:
	_sel_bench = -1 if _sel_bench == idx else idx
	_rebuild()

func _on_turtle_click(pet_id: String) -> void:
	if _sel_bench >= 0:
		_equip_to(pet_id, _sel_bench)
	else:
		_unequip_last(pet_id)

## 选中的背包装备装到 pet_id (槽够才装).
func _equip_to(pet_id: String, bench_idx: int) -> void:
	var bench: Array = GameState.persistent_bench
	if bench_idx < 0 or bench_idx >= bench.size():
		_sel_bench = -1; _rebuild(); return
	var eqs: Array = GameState.persistent_equipped.get(pet_id, [])
	if eqs.size() >= P2.equip_slots_for_level(int(GameState.season_level)):
		_sel_bench = -1; _rebuild(); return   # 槽满
	var item = bench[bench_idx]
	bench.remove_at(bench_idx)
	eqs.append(item)
	GameState.persistent_equipped[pet_id] = eqs
	_sel_bench = -1
	GameState.auto_merge_all()   # 装上后若凑够3件(背包+龟身)自动合星
	GameState.save()
	_rebuild()

## 卸下 pet_id 最后一件装备 → 回背包.
func _unequip_last(pet_id: String) -> void:
	var eqs: Array = GameState.persistent_equipped.get(pet_id, [])
	if eqs.is_empty():
		return
	GameState.persistent_bench.append(eqs.pop_back())
	GameState.persistent_equipped[pet_id] = eqs
	GameState.auto_merge_all()   # 卸回背包后自动 3 合 1 (背包+龟身一起算)
	GameState.save()
	_rebuild()

# ─── 动作区: 一键合星 + 卖出选中 ───
func _build_actions() -> void:
	var hint := Label.new(); hint.text = "✨ 3 件同款同星 自动合成升星 (跟以前一样)"
	hint.add_theme_font_size_override("font_size", 14); hint.add_theme_color_override("font_color", Color("#7a8595"))
	hint.position = Vector2(64, 644); hint.size = Vector2(360, 24); add_child(hint)
	if _sel_bench >= 0 and _sel_bench < GameState.persistent_bench.size():
		var sit: Dictionary = GameState.persistent_bench[_sel_bench]
		var sdef: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(sit.get("id", "")), {})
		var dnm := Label.new(); dnm.text = "▶ %s  ★%d  (%s · %d费)" % [str(sdef.get("name", "")), int(sit.get("star", 1)), str(sdef.get("rarity", "普通")), int(sdef.get("cost", 1))]
		dnm.add_theme_font_size_override("font_size", 16); dnm.add_theme_color_override("font_color", Color("#ffd93d"))
		dnm.position = Vector2(64, 520); dnm.size = Vector2(1140, 22); add_child(dnm)
		var ddesc := Label.new(); ddesc.text = str(sdef.get("effectDesc1", "（无主动效果）"))
		ddesc.add_theme_font_size_override("font_size", 13); ddesc.add_theme_color_override("font_color", Color("#bcd0e0"))
		ddesc.position = Vector2(64, 546); ddesc.size = Vector2(1140, 44); ddesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(ddesc)
		var sv := _sell_value(GameState.persistent_bench[_sel_bench])
		var sl := Button.new(); sl.text = "💰 卖出选中 (+%d💠)" % sv
		sl.add_theme_font_size_override("font_size", 18)
		sl.position = Vector2(340, 636); sl.size = Vector2(240, 44)
		sl.pressed.connect(_sell_selected); add_child(sl)

func _sell_value(item: Dictionary) -> int:
	var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(item.get("id", "")), {})
	var cost := maxi(1, int(edef.get("cost", 1)))
	var star := maxi(1, int(item.get("star", 1)))
	return int(floor(cost * star * 0.8))

func _sell_selected() -> void:
	if _sel_bench < 0 or _sel_bench >= GameState.persistent_bench.size():
		return
	GameState.meta_deepsea_coins += _sell_value(GameState.persistent_bench[_sel_bench])
	GameState.persistent_bench.remove_at(_sel_bench)
	_sel_bench = -1
	GameState.save()
	_rebuild()

## 一键合星: 同 id+star 满 3 → 去 3 加 1(star+1), 反复扫到无可合 (满3星不再合).
func _merge_all() -> void:
	var changed := true
	while changed:
		changed = false
		var counts := {}
		for it in GameState.persistent_bench:
			var k := "%s|%d" % [str(it.get("id", "")), int(it.get("star", 1))]
			counts[k] = int(counts.get(k, 0)) + 1
		for k in counts.keys():
			if int(counts[k]) < 3:
				continue
			var parts := str(k).split("|")
			var iid := str(parts[0])
			var star := int(parts[1])
			if star >= 3:
				continue
			var removed := 0
			var i := 0
			while i < GameState.persistent_bench.size() and removed < 3:
				var it: Dictionary = GameState.persistent_bench[i]
				if str(it.get("id", "")) == iid and int(it.get("star", 1)) == star:
					GameState.persistent_bench.remove_at(i); removed += 1
				else:
					i += 1
			GameState.persistent_bench.append({"id": iid, "star": star + 1})
			changed = true
			break
	GameState.save()
	_rebuild()
