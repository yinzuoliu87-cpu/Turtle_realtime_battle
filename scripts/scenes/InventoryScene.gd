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
const Phase2Minion = preload("res://scripts/engine/phase2_minion.gd")

var _sel_bench: int = -1   # 当前选中的背包装备索引 (-1=无)
var _dl_sel: Dictionary = {}   # 双路布阵选中框 {lane, idx} (点两个互换分路)

func _ready() -> void:
	_rebuild()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):   # ESC 返回主菜单 (与图鉴一致)
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

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

	_build_candy_jar()

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

# ─── 上部: 双路布阵 (上战场/下战场, 3统领+3小将分3+3; 点头像互换分路, 点小将切前/后排) ───
func _build_lineup(_leaders: Array) -> void:
	var hdr := Label.new()
	hdr.text = "双路布阵 — 点两像互换分路 · 小将[前/后]切类型 · 选背包装备点单位装备格=装(统领/小将都能装,点空格卸)"
	hdr.add_theme_font_size_override("font_size", 13); hdr.add_theme_color_override("font_color", Color("#9fb6c9"))
	hdr.position = Vector2(60, 84); hdr.size = Vector2(620, 20); add_child(hdr)
	var lineup := GameState.get_dual_lineup()
	for lane_info in [["上战场", "top", 116.0, Color("#ffd93d")], ["下战场", "bottom", 238.0, Color("#7fd0ff")]]:
		var lname := str(lane_info[0]); var lkey := str(lane_info[1]); var ly := float(lane_info[2]); var lcol: Color = lane_info[3]
		var arr: Array = lineup.get(lkey, [])
		var lead_n := 0
		for u in arr:
			if u is Dictionary and str(u.get("kind", "")) == "leader": lead_n += 1
		var ll := Label.new(); ll.text = "%s  (统领%d / 小将%d)" % [lname, lead_n, arr.size() - lead_n]
		ll.add_theme_font_size_override("font_size", 15); ll.add_theme_color_override("font_color", lcol)
		ll.position = Vector2(60, ly); ll.size = Vector2(240, 20); add_child(ll)
		for i in range(arr.size()):
			add_child(_dl_unit_box(lkey, i, arr[i], lead_n, Vector2(60 + i * 122, ly + 22)))

## 布阵单位框: 统领(立绘+名) / 小将(立绘+[前后排]toggle+精英标). 点框body=选中↔互换分路.
func _dl_unit_box(lane: String, idx: int, unit: Dictionary, lead_n: int, pos: Vector2) -> Control:
	var kind := str(unit.get("kind", "minion"))
	var sel := str(_dl_sel.get("lane", "")) == lane and int(_dl_sel.get("idx", -1)) == idx
	var is_elite := kind == "minion" and lead_n == 0 and _dl_first_minion_idx(lane) == idx
	var bg := Color("#13314a") if kind == "leader" else (Color("#4a3410") if is_elite else Color("#1a2230"))
	var bd := Color("#ffd93d") if sel else (Color("#2e5a7e") if kind == "leader" else (Color("#c79a3a") if is_elite else Color("#3a4658")))
	var box := _slot_panel(pos, bg, bd)
	box.size = Vector2(112, 96)
	var img_path := ""
	if kind == "leader":
		img_path = "res://assets/sprites/avatars/%s.png" % str(unit.get("id", ""))
	else:
		img_path = "res://assets/sprites/%s" % Phase2Minion.minion_img(is_elite, str(unit.get("role", "front")) == "back")
	if ResourceLoader.exists(img_path):
		var a := TextureRect.new(); a.texture = load(img_path)
		a.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; a.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		a.position = Vector2(34, 2); a.size = Vector2(44, 38); box.add_child(a)
	var nm := Label.new()
	if kind == "leader":
		var pet: Dictionary = DataRegistry.pet_by_id.get(str(unit.get("id", "")), {})
		nm.text = str(pet.get("name", unit.get("id", "")))
	else:
		nm.text = "精英小将" if is_elite else "小将"
	nm.add_theme_font_size_override("font_size", 11); nm.add_theme_color_override("font_color", Color("#e8f2ff"))
	nm.position = Vector2(0, 42); nm.size = Vector2(112, 14); nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(nm)
	# 装备格 + 装/卸按钮: leader读 persistent_equipped / 小将读 dual_lineup 条目.equips (战斗端都注入)
	var eqs: Array = []
	if kind == "leader":
		if GameState.persistent_equipped is Dictionary:
			eqs = GameState.persistent_equipped.get(str(unit.get("id", "")), [])
	elif unit.get("equips", null) is Array:
		eqs = unit.get("equips", [])
	var slots := P2.equip_slots_for_level(int(GameState.season_level))
	_draw_equip_cells(box, eqs, slots, 60.0)
	var eqbtn := Button.new()
	eqbtn.flat = true; eqbtn.focus_mode = Control.FOCUS_NONE
	eqbtn.tooltip_text = "选中背包装备→点这装上; 无选中→点这卸最后一件"
	eqbtn.position = Vector2(2, 57); eqbtn.size = Vector2(108, 15)
	eqbtn.pressed.connect(func():
		if _sel_bench >= 0:
			if kind == "leader": _equip_to(str(unit.get("id", "")), _sel_bench)
			else: _equip_minion(lane, idx, _sel_bench)
		else:
			if kind == "leader": _unequip_last(str(unit.get("id", "")))
			else: _unequip_minion_last(lane, idx))
	box.add_child(eqbtn)
	if kind == "minion":
		var role := str(unit.get("role", "front"))
		var tgl := Button.new()
		tgl.text = "前排·近战" if role == "front" else "后排·射击"
		tgl.add_theme_font_size_override("font_size", 11)
		tgl.position = Vector2(6, 74); tgl.size = Vector2(100, 18)
		tgl.pressed.connect(func(): _dl_toggle_role(lane, idx))
		box.add_child(tgl)
	for ch in box.get_children():
		if not (ch is Button):
			ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _dl_click(lane, idx))
	return box

## 该路首个小将 idx (0统领路首小将=精英)
func _dl_first_minion_idx(lane: String) -> int:
	var arr: Array = GameState.get_dual_lineup().get(lane, [])
	for i in range(arr.size()):
		if arr[i] is Dictionary and str(arr[i].get("kind", "")) == "minion":
			return i
	return -1

## 点布阵框: 选了装备+点统领=装备; 否则 无选中→选中, 已选中→与该框互换分路(跨/同路都行), 再点自己=取消.
func _dl_click(lane: String, idx: int) -> void:
	var arr: Array = GameState.get_dual_lineup().get(lane, [])
	var unit: Dictionary = arr[idx] if idx < arr.size() and arr[idx] is Dictionary else {}
	if _sel_bench >= 0 and str(unit.get("kind", "")) == "leader":
		_equip_to(str(unit.get("id", "")), _sel_bench)
		return
	if _sel_bench >= 0 and str(unit.get("kind", "")) == "minion":
		_equip_minion(lane, idx, _sel_bench)
		return
	if _dl_sel.is_empty():
		_dl_sel = {"lane": lane, "idx": idx}
		_rebuild(); return
	var sl := str(_dl_sel.get("lane", "")); var si := int(_dl_sel.get("idx", -1))
	_dl_sel = {}
	if sl == lane and si == idx:
		_rebuild(); return
	var a: Dictionary = GameState.get_dual_lineup().duplicate(true)
	var tmp = a[sl][si]
	a[sl][si] = a[lane][idx]
	a[lane][idx] = tmp
	GameState.dual_lineup = a
	GameState.save()
	_rebuild()

## 点小将[前/后]: 切前排(近战挥砍×1.4) ↔ 后排(远程射击×1.5)
func _dl_toggle_role(lane: String, idx: int) -> void:
	var a: Dictionary = GameState.get_dual_lineup().duplicate(true)
	var u = a[lane][idx]
	if u is Dictionary and str(u.get("kind", "")) == "minion":
		u["role"] = "back" if str(u.get("role", "front")) == "front" else "front"
		a[lane][idx] = u
		GameState.dual_lineup = a
		GameState.save()
		_rebuild()

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
# (旧 _on_grid_click 阵容格子已删, 双路布阵改用 _dl_click / _dl_toggle_role)

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
	hdr.text = "装备背包 (永不丢 · 战后全收)  —  点装备选中 → 点龟装上 · 再点龟身卸下 · 选中可卖 · 装/卸/买后自动三合一升星"
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
	if str(it.get("kind", "")) == "item":       # 消耗品(临时等级器): 不是装备, 不查装备表/不显星
		return _item_cell(it, idx, pos)
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

## 选中的背包装备装到 pet_id (槽够才装).
func _equip_to(pet_id: String, bench_idx: int) -> void:
	var bench: Array = GameState.persistent_bench
	if bench_idx < 0 or bench_idx >= bench.size():
		_sel_bench = -1; _rebuild(); return
	if str((bench[bench_idx] as Dictionary).get("kind", "")) == "item":   # 临时等级器 → 该龟本大轮永久+1级
		GameState.apply_temp_leveler(pet_id)
		GameState.consume_temp_leveler(bench_idx)
		_sel_bench = -1
		_toast("临时等级器 → %s 本大轮 +1 级 (现 +%d)" % [pet_id, GameState.temp_level_bonus(pet_id)])
		_rebuild(); return
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

## 小将装备(实时新增): 存 dual_lineup[lane][idx].equips (id共享__minion__进不了persistent_equipped). 战斗端 _spawn_lane_side 读 .equips→_dl_equips 注入.
func _equip_minion(lane: String, idx: int, bench_idx: int) -> void:
	var bench: Array = GameState.persistent_bench
	if bench_idx < 0 or bench_idx >= bench.size():
		_sel_bench = -1; _rebuild(); return
	if str((bench[bench_idx] as Dictionary).get("kind", "")) == "item":   # 临时等级器 → 该小将本大轮永久+1级
		if GameState.apply_temp_leveler_minion(lane, idx):
			GameState.consume_temp_leveler(bench_idx)
			_toast("临时等级器 → 小将(%s路第%d格) 本大轮 +1 级" % [lane, idx + 1])
		_sel_bench = -1
		_rebuild(); return
	var a: Dictionary = GameState.get_dual_lineup().duplicate(true)
	if not a.has(lane) or idx < 0 or idx >= (a[lane] as Array).size():
		_sel_bench = -1; _rebuild(); return
	var u: Dictionary = a[lane][idx]
	if str(u.get("kind", "")) != "minion":
		_sel_bench = -1; _rebuild(); return
	var eqs: Array = u.get("equips", []) if u.get("equips", null) is Array else []
	if eqs.size() >= P2.equip_slots_for_level(int(GameState.season_level)):
		_sel_bench = -1; _rebuild(); return   # 槽满(跟 leader 同 equip_slots_for_level)
	eqs.append(bench[bench_idx])
	bench.remove_at(bench_idx)
	u["equips"] = eqs
	a[lane][idx] = u
	GameState.dual_lineup = a
	_sel_bench = -1
	GameState.auto_merge_all()   # 整理背包(小将装的不进合成池, 但背包其余照常3合1)
	GameState.save()
	_rebuild()

## 卸下小将最后一件装备 → 回背包.
func _unequip_minion_last(lane: String, idx: int) -> void:
	var a: Dictionary = GameState.get_dual_lineup().duplicate(true)
	if not a.has(lane) or idx < 0 or idx >= (a[lane] as Array).size():
		return
	var u: Dictionary = a[lane][idx]
	var eqs: Array = u.get("equips", []) if u.get("equips", null) is Array else []
	if eqs.is_empty():
		return
	GameState.persistent_bench.append(eqs.pop_back())
	u["equips"] = eqs
	a[lane][idx] = u
	GameState.dual_lineup = a
	GameState.auto_merge_all()
	GameState.save()
	_rebuild()

# ─── 动作区: 卖出选中 (三合一升星全自动, 无需按钮) ───
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

# ============================================================================
#  糖果罐（糖果龟被动 · 局外经济行 · 用户2026-07-07设计）
#  · 大轮开始时若锁定统领含糖果龟 → 拥有 1 个糖果罐
#  · 赢一局计数 +1 / 输一局 +4（逆风快攒）· 封顶 30
#  · 随时可打碎领奖: 计数越高档位越高(6档) → 深海币 + 装备(按档费/星) + 临时等级器(按档概率)
#  · 打碎后本大轮消失
#  逻辑全在 GameState: has_candy_jar / candy_jar_count / candy_jar_tier / break_candy_jar
# ============================================================================
func _build_candy_jar() -> void:
	if not GameState.has_candy_jar():
		return                                   # 统领没锁糖果龟(或已碎) → 不显示这行
	var cnt: int = int(GameState.candy_jar_count)
	var tier: int = GameState.candy_jar_tier()
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2a1c36"); sb.border_color = Color("#e79bd6")
	sb.set_border_width_all(2); sb.set_corner_radius_all(8)
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(620, 20); box.size = Vector2(380, 52)
	box.tooltip_text = "打碎后本大轮消失。\n当前档位奖励: %s" % GameState.candy_jar_tier_preview(tier)
	add_child(box)

	var lb := Label.new()
	lb.text = "🍬 糖果罐  %d/30  ·  档%d" % [cnt, tier]
	lb.add_theme_font_size_override("font_size", 18)
	lb.add_theme_color_override("font_color", Color("#ffd6f2"))
	lb.position = Vector2(12, 4); lb.size = Vector2(220, 24)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lb)

	var sub := Label.new()
	sub.text = GameState.candy_jar_tier_preview(tier)
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color("#c9a8c0"))
	sub.position = Vector2(12, 28); sub.size = Vector2(272, 20)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(sub)

	var btn := Button.new()
	btn.text = "打碎"
	btn.add_theme_font_size_override("font_size", 16)
	btn.position = Vector2(292, 10); btn.size = Vector2(76, 32)
	btn.pressed.connect(_on_break_jar)
	box.add_child(btn)


func _on_break_jar() -> void:
	var r: Dictionary = GameState.break_candy_jar()
	if r.is_empty():
		return
	_show_jar_reward(r)


func _show_jar_reward(r: Dictionary) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ffd93d")
	sb.set_border_width_all(3); sb.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(W / 2.0 - 260, H / 2.0 - 150); box.size = Vector2(520, 300)
	dim.add_child(box)

	var ttl := Label.new()
	ttl.text = "🍬 糖果罐碎了！  (档%d)" % int(r.get("tier", 1))
	ttl.add_theme_font_size_override("font_size", 26)
	ttl.add_theme_color_override("font_color", Color("#ffd93d"))
	ttl.position = Vector2(0, 20); ttl.size = Vector2(520, 36)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ttl)

	var lines: Array = ["💠 深海币  +%d" % int(r.get("coins", 0))]
	var eid := str(r.get("equip", ""))
	if eid != "":
		var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
		lines.append("🗡 装备  %s  %s  → 进背包" % [str(edef.get("name", eid)), "★".repeat(int(r.get("star", 1)))])
	if bool(r.get("leveler", false)):
		lines.append("🔼 临时等级器 ×1  → 进背包 (点它再点一只龟/小将, 本大轮 +1 级)")

	var y := 80.0
	for t in lines:
		var l := Label.new()
		l.text = str(t)
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", Color("#e8f2ff"))
		l.position = Vector2(40, y); l.size = Vector2(440, 30)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
		y += 46.0

	var ok := Button.new()
	ok.text = "收下"
	ok.add_theme_font_size_override("font_size", 20)
	ok.position = Vector2(200, 234); ok.size = Vector2(120, 44)
	ok.pressed.connect(func(): dim.queue_free(); _rebuild())
	box.add_child(ok)


# 消耗品格子 (临时等级器): 不是装备 → 不查装备表/不显星/不参与3合1
func _item_cell(it: Dictionary, idx: int, pos: Vector2) -> Control:
	var sel := idx == _sel_bench
	var box := _slot_panel(pos, Color("#2a3a1c") if sel else Color("#26203a"), Color("#ffd93d") if sel else Color("#a98bd8"))
	var ic := Label.new()
	ic.text = "🔼"
	ic.add_theme_font_size_override("font_size", 30)
	ic.position = Vector2(0, 16); ic.size = Vector2(SLOT, 36)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ic)
	var nm := Label.new()
	nm.text = "临时等级器"
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", Color("#e6d8ff"))
	nm.position = Vector2(2, SLOT - 36); nm.size = Vector2(SLOT - 4, 32)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(nm)
	for ch in box.get_children():
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.tooltip_text = "临时等级器 (糖果罐战利品)\n选中它 → 点一只龟统领或小将 → 该单位【本大轮】永久 +1 级 (切大轮重置)"
	box.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _on_bench_click(idx))
	return box


# 轻量提示条 (1.4s 后淡出) — 临时等级器等一次性反馈
func _toast(msg: String) -> void:
	var l := Label.new()
	l.text = msg
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color("#ffd93d"))
	l.position = Vector2(W / 2.0 - 300, 96); l.size = Vector2(600, 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)
