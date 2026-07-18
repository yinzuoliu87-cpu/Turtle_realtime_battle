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
var _vw: float = 1280.0   # 实际视口宽(手机expand后可达~1560): 顶栏/背包按真实宽铺开·不再左挤留空(2026-07-18)
var _press_pos := Vector2.ZERO   # 背包格触屏点选/滑动判定: 松开位移小才算点选(可滑动列表·2026-07-18)

func _ready() -> void:
	if OS.has_environment("INV_DEMO"):   # dev截图用: 内存填演示背包(不save·不碰真存档)
		_inject_demo_inventory()
	if OS.has_environment("PH_DEMO"):    # dev: 清统领模拟大轮开局 → 看统领1/2/3问号占位(不save)
		GameState.season_leaders = []
		GameState.dual_lineup = {}
	_rebuild()

func _inject_demo_inventory() -> void:   # 仅 INV_DEMO 环境: 填装备看满仓布局(不调 save)
	GameState.season_level = 8
	var ids := ["p2eq_001", "p2eq_004", "p2eq_005", "p2eq_007", "p2eq_009", "p2eq_011", "p2eq_013", "p2eq_014", "p2eq_016", "p2eq_017", "p2eq_021", "p2eq_022", "p2eq_028", "p2eq_032", "p2eq_035", "p2eq_039", "p2eq_044", "p2eq_048", "p2eq_050", "p2eq_052", "p2eq_005", "p2eq_007"]
	GameState.persistent_bench = []
	for i in range(ids.size()):
		GameState.persistent_bench.append({"id": ids[i], "star": (i % 3) + 1})
	var leaders := _lineup_ids()
	if leaders.size() > 0:
		GameState.persistent_equipped[str(leaders[0])] = [{"id": "p2eq_001", "star": 2}, {"id": "p2eq_005", "star": 1}, {"id": "p2eq_007", "star": 1}]
	var lineup := GameState.get_dual_lineup()
	for lk in ["top", "bottom"]:
		for u in lineup.get(lk, []):
			if u is Dictionary and str(u.get("kind", "")) == "minion":
				u["equips"] = [{"id": "p2eq_004", "star": 1}, {"id": "p2eq_009", "star": 2}]
				break
	GameState.dual_lineup = lineup

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):   # ESC 返回主菜单 (与图鉴一致)
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _rebuild() -> void:
	_vw = maxf(W, get_viewport_rect().size.x)   # 真实视口宽(手机expand后~1560)→顶栏/背包按此铺开
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
	title.position = Vector2(_vw / 2.0 - 220, 22); title.size = Vector2(440, 46)
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
	coin.position = Vector2(_vw - 260, 30); coin.size = Vector2(232, 32)
	coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(coin)

	_build_candy_jar()

	var leaders := _lineup_ids()
	_build_lineup(leaders)
	_build_synergy_panel(leaders)
	_build_bench()
	_build_op_bar()

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
const UBOX_W := 244.0   # 阵容单位框(再放大·填左侧空间+适手机点触·用户2026-07-19)
const UBOX_H := 116.0
const UBOX_GAP := 16.0

func _build_lineup(_leaders: Array) -> void:
	var lineup := GameState.get_dual_lineup()
	var box_span := 3.0 * UBOX_W + 2.0 * UBOX_GAP
	# 标题「出战阵容」+ 右上"?"帮助(详细玩法按需弹·默认不铺教程字·用户2026-07-19)
	var sect := Label.new()
	sect.text = "出战阵容"
	sect.add_theme_font_size_override("font_size", 18)
	sect.add_theme_color_override("font_color", Color("#cfe0ef"))
	sect.position = Vector2(40, 62); sect.size = Vector2(140, 24); add_child(sect)
	# 上下文提示: 只在"选了装备 / 选了单位"时冒一句(非常驻教程)
	var ctx := ""
	var ctxcol := Color.WHITE
	if _sel_bench >= 0:
		ctx = "→ 点【龟 / 小将】装上它"; ctxcol = Color("#7fe39a")
	elif not _dl_sel.is_empty():
		ctx = "→ 再点另一个位置 = 互换战场"; ctxcol = Color("#ffd93d")
	if ctx != "":
		var ch := Label.new()
		ch.text = ctx; ch.add_theme_font_size_override("font_size", 15); ch.add_theme_color_override("font_color", ctxcol)
		ch.position = Vector2(150, 63); ch.size = Vector2(_vw - 520, 22); add_child(ch)
	var help := Button.new()
	help.text = "?"; help.tooltip_text = "怎么配阵容"
	help.add_theme_font_size_override("font_size", 16)
	var hsb := StyleBoxFlat.new(); hsb.bg_color = Color("#1a2634"); hsb.border_color = Color("#4a6a8a")
	hsb.set_border_width_all(1); hsb.set_corner_radius_all(13)
	help.add_theme_stylebox_override("normal", hsb); help.add_theme_stylebox_override("hover", hsb); help.add_theme_stylebox_override("pressed", hsb)
	help.add_theme_color_override("font_color", Color("#9fc0dd"))
	help.position = Vector2(124.0, 60.0); help.size = Vector2(24, 24)   # 紧挨「出战阵容」标题右侧, 不再挤战场带右上的计数
	help.pressed.connect(func(): _show_lineup_help())
	add_child(help)
	# 两条"战场带"(染色圆角底 + 战场名 + 编成计数) → 一眼看出上/下是两个各自开打的战场
	for lane_info in [["上战场", "top", 108.0, Color("#ffd93d"), Color(0.24, 0.19, 0.06)], ["下战场", "bottom", 254.0, Color("#7fd0ff"), Color(0.05, 0.14, 0.24)]]:
		var bf := str(lane_info[0]); var lkey := str(lane_info[1]); var by := float(lane_info[2])
		var lcol: Color = lane_info[3]; var bandbg: Color = lane_info[4]
		var arr: Array = lineup.get(lkey, [])
		var lead_n := 0
		for u in arr:
			if u is Dictionary and str(u.get("kind", "")) == "leader": lead_n += 1
		var band := Panel.new()
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(bandbg.r, bandbg.g, bandbg.b, 0.5)
		bsb.border_color = Color(lcol.r, lcol.g, lcol.b, 0.45)
		bsb.set_border_width_all(2); bsb.set_corner_radius_all(12)
		band.add_theme_stylebox_override("panel", bsb)
		band.position = Vector2(30, by - 24); band.size = Vector2(box_span + 20, UBOX_H + 28)
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(band)
		var ll := Label.new()
		ll.text = "%s  %s" % ["⬆" if lkey == "top" else "⬇", bf]
		ll.add_theme_font_size_override("font_size", 16); ll.add_theme_color_override("font_color", lcol)
		ll.position = Vector2(44, by - 21); ll.size = Vector2(180, 18); add_child(ll)
		var minion_n := arr.size() - lead_n
		var ctext := ""
		if lead_n > 0:
			ctext = "统领 ×%d" % lead_n
		if minion_n > 0:
			ctext += ("　　小将 ×%d" % minion_n) if ctext != "" else ("小将 ×%d" % minion_n)
		var cnt := Label.new()
		cnt.text = ctext
		cnt.add_theme_font_size_override("font_size", 13)
		cnt.add_theme_color_override("font_color", Color(lcol.r, lcol.g, lcol.b, 0.72))
		cnt.position = Vector2(30 + box_span + 20 - 200, by - 20); cnt.size = Vector2(186, 16)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; add_child(cnt)
		for i in range(arr.size()):
			add_child(_dl_unit_box(lkey, i, arr[i], lead_n, Vector2(40 + i * (UBOX_W + UBOX_GAP), by)))

## 布阵单位框(大改): 大立绘+名+可点装备格(点填充格=卸那件)+小将前后排角标. 选中装备时整框高亮"装这里". 点框body=装备(选中时)↔互换分路.
func _dl_unit_box(lane: String, idx: int, unit: Dictionary, lead_n: int, pos: Vector2) -> Control:
	var kind := str(unit.get("kind", "minion"))
	var pid := str(unit.get("id", ""))
	var is_ph := kind == "leader" and pid == ""   # 占位统领(大轮未选统领·id空) → 显示「统领N ?」
	var sel := str(_dl_sel.get("lane", "")) == lane and int(_dl_sel.get("idx", -1)) == idx
	var is_elite := kind == "minion" and lead_n == 0 and _dl_first_minion_idx(lane) == idx
	var can_equip := _sel_bench >= 0 and not is_ph   # 选了装备 → 此框可装(占位统领无真龟·不可装)
	var bg := Color("#22304a") if is_ph else (Color("#13314a") if kind == "leader" else (Color("#4a3410") if is_elite else Color("#1a2230")))
	var bd: Color
	if sel: bd = Color("#ffd93d")
	elif can_equip: bd = Color("#7fe39a")   # 选中装备时所有单位框高亮"装这里"(含小将→一眼可装)
	elif is_ph: bd = Color("#8a97a8")   # 占位统领: 灰蓝虚位感
	else: bd = (Color("#2e5a7e") if kind == "leader" else (Color("#c79a3a") if is_elite else Color("#3a4658")))
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg; sb.border_color = bd
	sb.set_border_width_all(4 if sel else (3 if can_equip else 2)); sb.set_corner_radius_all(8)
	box.add_theme_stylebox_override("panel", sb)
	box.position = pos; box.size = Vector2(UBOX_W, UBOX_H)
	if is_ph:
		var q := Label.new()
		q.text = "?"
		q.add_theme_font_size_override("font_size", 52)
		q.add_theme_color_override("font_color", Color("#9fb2c8"))
		q.position = Vector2(0, 0); q.size = Vector2(UBOX_W, 58)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(q)
	else:
		var img_path := ""
		if kind == "leader":
			img_path = "res://assets/sprites/avatars/%s.png" % pid
		else:
			img_path = "res://assets/sprites/%s" % Phase2Minion.minion_img(is_elite, str(unit.get("role", "front")) == "back")
		if ResourceLoader.exists(img_path):
			var a := TextureRect.new(); a.texture = load(img_path)
			a.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; a.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			a.position = Vector2(UBOX_W / 2.0 - 48, 2); a.size = Vector2(96, 56); a.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(a)
	var nm := Label.new()
	if is_ph:
		nm.text = "统领%d" % (int(unit.get("slot", idx)) + 1)
	elif kind == "leader":
		var pet: Dictionary = DataRegistry.pet_by_id.get(pid, {})
		nm.text = str(pet.get("name", pid))
	else:
		nm.text = "精英小将" if is_elite else "小将"
	nm.add_theme_font_size_override("font_size", 15); nm.add_theme_color_override("font_color", Color("#e8f2ff"))
	nm.position = Vector2(0, 60); nm.size = Vector2(UBOX_W, 18); nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nm.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(nm)
	# 装备格(可点卸那一件) — 占位统领无真龟, 不建装备格, 改提示
	if is_ph:
		var hint := Label.new()
		hint.text = "选龟后填入"
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", Color("#7f8fa0"))
		hint.position = Vector2(0, 88); hint.size = Vector2(UBOX_W, 16)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hint.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(hint)
	else:
		var eqs: Array = []
		if kind == "leader":
			if GameState.persistent_equipped is Dictionary:
				eqs = GameState.persistent_equipped.get(pid, [])
		elif unit.get("equips", null) is Array:
			eqs = unit.get("equips", [])
		var slots := P2.equip_slots_for_level(int(GameState.season_level))
		_build_equip_cells(box, 84.0, eqs, slots, kind == "leader", pid, lane, idx)
	# 小将 前排/后排 (清楚的可点标签 pill: 前排=橙/近战, 后排=青/射击) — 精英小将=统领替身, 不显前后排(用户2026-07-18)
	if kind == "minion" and not is_elite:
		var front := str(unit.get("role", "front")) == "front"
		var tgl := Button.new()
		tgl.text = "前排" if front else "后排"
		tgl.tooltip_text = "前排=近战挥砍 / 后排=远程射击 · 点切换"
		tgl.add_theme_font_size_override("font_size", 12)
		var tsb := StyleBoxFlat.new()
		tsb.bg_color = Color("#5a3410") if front else Color("#0f3646")
		tsb.border_color = Color("#e0954a") if front else Color("#4ab0d0")
		tsb.set_border_width_all(1); tsb.set_corner_radius_all(6)
		tgl.add_theme_stylebox_override("normal", tsb)
		tgl.add_theme_stylebox_override("hover", tsb)
		tgl.add_theme_stylebox_override("pressed", tsb)
		tgl.add_theme_color_override("font_color", Color("#ffdba8") if front else Color("#b8e8ff"))
		tgl.position = Vector2(UBOX_W - 58.0, 4.0); tgl.size = Vector2(54, 22)
		tgl.pressed.connect(func(): _dl_toggle_role(lane, idx))
		box.add_child(tgl)
	box.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _dl_click(lane, idx))
	return box

## 单位身上的装备格一行: 填充格显图标·点它=卸那一件(无选中时); 选中装备时格子透传→点框body装备.
func _build_equip_cells(box: Control, y: float, eqs: Array, slots: int, is_leader: bool, pet_id: String, lane: String, idx: int) -> void:
	var cw := 30.0
	var gap := 6.0
	var total := float(slots) * cw + maxf(0.0, float(slots - 1)) * gap
	var x0 := UBOX_W / 2.0 - total / 2.0
	for ci in range(slots):
		var cell := Panel.new()
		var csb := StyleBoxFlat.new()
		var filled := ci < eqs.size()
		if filled:
			var eid := str((eqs[ci] as Dictionary).get("id", ""))
			var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
			csb.bg_color = _rarity_color(str(edef.get("rarity", "普通")))
			csb.border_color = Color(1, 1, 1, 0.5)
		else:
			csb.bg_color = Color(0, 0, 0, 0.35); csb.border_color = Color("#3a4452")
		csb.set_border_width_all(1); csb.set_corner_radius_all(3)
		cell.add_theme_stylebox_override("panel", csb)
		cell.position = Vector2(x0 + float(ci) * (cw + gap), y); cell.size = Vector2(cw, cw)
		if filled:
			var eid2 := str((eqs[ci] as Dictionary).get("id", ""))
			var edef2: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid2, {})
			var im := str(edef2.get("img", ""))
			if im != "" and ResourceLoader.exists("res://assets/sprites/" + im):
				var tr := TextureRect.new(); tr.texture = load("res://assets/sprites/" + im)
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				tr.position = Vector2(1, 1); tr.size = Vector2(cw - 2, cw - 2); tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cell.add_child(tr)
		if _sel_bench >= 0:
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 装备模式: 透传→点框body装上
		elif filled:
			cell.tooltip_text = "点击卸下这件 → 回背包"
			var cci := ci
			cell.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: (_unequip_at(pet_id, cci) if is_leader else _unequip_minion_at(lane, idx, cci)))
		else:
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 空格透传
		box.add_child(cell)

## 卸下统领第 cell_idx 件装备 → 回背包.
func _unequip_at(pet_id: String, cell_idx: int) -> void:
	var eqs: Array = GameState.persistent_equipped.get(pet_id, [])
	if cell_idx < 0 or cell_idx >= eqs.size():
		return
	GameState.persistent_bench.append(eqs[cell_idx])
	eqs.remove_at(cell_idx)
	GameState.persistent_equipped[pet_id] = eqs
	GameState.auto_merge_all()
	GameState.save()
	_rebuild()

## 卸下小将第 cell_idx 件装备 → 回背包.
func _unequip_minion_at(lane: String, idx: int, cell_idx: int) -> void:
	var a: Dictionary = GameState.get_dual_lineup().duplicate(true)
	if not a.has(lane) or idx < 0 or idx >= (a[lane] as Array).size():
		return
	var u: Dictionary = a[lane][idx]
	var eqs: Array = u.get("equips", []) if u.get("equips", null) is Array else []
	if cell_idx < 0 or cell_idx >= eqs.size():
		return
	GameState.persistent_bench.append(eqs[cell_idx])
	eqs.remove_at(cell_idx)
	u["equips"] = eqs
	a[lane][idx] = u
	GameState.dual_lineup = a
	GameState.auto_merge_all()
	GameState.save()
	_rebuild()

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
	var cw := 14.0   # 装备格加大(用户2026-07-18"拆卸装备太小"): 10→14·更易看清/点按
	var gap := 4.0
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
## 羁绊统计: 统领装备(persistent_equipped) + 小将装备(dual_lineup)·跟龟一样计入(用户2026-07-18)
func _team_equips_for_synergy() -> Array:
	var all_equips: Array = []
	for pid in _lineup_ids():
		for it in GameState.persistent_equipped.get(str(pid), []):
			all_equips.append(it)
	var lineup := GameState.get_dual_lineup()
	for lk in ["top", "bottom"]:
		for u in lineup.get(lk, []):
			if u is Dictionary and str(u.get("kind", "")) == "minion" and u.get("equips", null) is Array:
				for it in u.get("equips", []):
					all_equips.append(it)
	return all_equips

# 右侧类型羁绊(大改): 只显名称+档位, 点击弹框看完整效果; 计入小将装备.
func _build_synergy_panel(leaders: Array) -> void:
	var w := 300.0                    # 羁绊窄列(用户2026-07-18"不要这么多空间")·靠右
	var x0 := _vw - w - 28.0
	var hdr := Label.new(); hdr.text = "类型羁绊"
	hdr.add_theme_font_size_override("font_size", 17); hdr.add_theme_color_override("font_color", Color("#9fb6c9"))
	hdr.position = Vector2(x0, 100); hdr.size = Vector2(w, 24); add_child(hdr)
	var cy := 132.0
	if _sel_bench >= 0:   # 装备模式上下文提示: 引导玩家凑同类型激活/升档羁绊(用户2026-07-19)
		var ctx := Label.new(); ctx.text = "▸ 给同一只装多件同类型 → 激活 / 升档"
		ctx.add_theme_font_size_override("font_size", 13); ctx.add_theme_color_override("font_color", Color("#7fe39a"))
		ctx.position = Vector2(x0, 126); ctx.size = Vector2(w, 18); ctx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(ctx)
		cy = 152.0
	var active: Array = Phase2Types.calc_active([{"_p2_equips": _team_equips_for_synergy()}])
	if active.is_empty():
		var e := Label.new(); e.text = "（给龟 / 小将装多件同类型装备 → 激活羁绊）"
		e.add_theme_font_size_override("font_size", 13); e.add_theme_color_override("font_color", Color("#5a6675"))
		e.position = Vector2(x0, cy); e.size = Vector2(w, 40); e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(e)
		return
	var y := cy
	for a in active:
		var t := str(a.get("type", ""))
		var tier := int(a.get("tier", 1))
		var chip := Panel.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color("#16263a"); csb.border_color = Color("#3e6a8e")
		csb.set_border_width_all(2); csb.set_corner_radius_all(8)
		chip.add_theme_stylebox_override("panel", csb)
		chip.position = Vector2(x0, y); chip.size = Vector2(w, 40); add_child(chip)
		var nm := Label.new()
		nm.text = "%s %s  ×%d   档%d" % [Phase2Types.emoji_of(t), Phase2Types.display_name(t), int(a.get("count", 0)), tier]
		nm.add_theme_font_size_override("font_size", 16); nm.add_theme_color_override("font_color", Color("#ffd93d"))
		nm.position = Vector2(12, 8); nm.size = Vector2(w - 40, 24); nm.mouse_filter = Control.MOUSE_FILTER_IGNORE; chip.add_child(nm)
		var arw := Label.new(); arw.text = "›"; arw.add_theme_font_size_override("font_size", 20); arw.add_theme_color_override("font_color", Color("#7fb0d8"))
		arw.position = Vector2(w - 26, 4); arw.size = Vector2(18, 30); arw.mouse_filter = Control.MOUSE_FILTER_IGNORE; chip.add_child(arw)
		chip.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _show_synergy_popup(t, tier))
		y += 48.0

## 羁绊详情弹框: 1/2/3 档效果全列, 当前档高亮. 点暗幕/关闭 关.
func _show_synergy_popup(type_key: String, cur_tier: int) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: dim.queue_free())
	add_child(dim)
	var bw := 620.0; var bh := 320.0
	var box := Panel.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ffd93d")
	sb.set_border_width_all(3); sb.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(_vw / 2.0 - bw / 2.0, 190.0); box.size = Vector2(bw, bh)
	box.mouse_filter = Control.MOUSE_FILTER_STOP   # 框内不穿透关闭
	dim.add_child(box)
	var ttl := Label.new(); ttl.text = "%s %s   (当前 档%d)" % [Phase2Types.emoji_of(type_key), Phase2Types.display_name(type_key), cur_tier]
	ttl.add_theme_font_size_override("font_size", 24); ttl.add_theme_color_override("font_color", Color("#ffd93d"))
	ttl.position = Vector2(24, 18); ttl.size = Vector2(bw - 48, 34); box.add_child(ttl)
	var y := 66.0
	for ti in [1, 2, 3]:
		var d := str(Phase2Types.tier_desc(type_key, ti))
		if d.strip_edges() == "":
			continue
		var l := Label.new(); l.text = "档%d:  %s" % [ti, d]
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", Color("#ffd93d") if ti == cur_tier else Color("#9fb0c0"))
		l.position = Vector2(24, y); l.size = Vector2(bw - 48, 66); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(l)
		y += 72.0
	var ok := Button.new(); ok.text = "关闭"; ok.add_theme_font_size_override("font_size", 18)
	ok.position = Vector2(bw / 2.0 - 60, bh - 52); ok.size = Vector2(120, 40)
	ok.pressed.connect(func(): dim.queue_free())
	box.add_child(ok)


## 阵容玩法帮助弹窗 (把原来常驻的教程字收到这·按需看)
func _show_lineup_help() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: dim.queue_free())
	add_child(dim)
	var bw := 560.0; var bh := 306.0
	var box := Panel.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ffd93d")
	sb.set_border_width_all(3); sb.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(_vw / 2.0 - bw / 2.0, 180.0); box.size = Vector2(bw, bh)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.add_child(box)
	var ttl := Label.new(); ttl.text = "怎么配出战阵容"
	ttl.add_theme_font_size_override("font_size", 22); ttl.add_theme_color_override("font_color", Color("#ffd93d"))
	ttl.position = Vector2(24, 18); ttl.size = Vector2(bw - 48, 30); box.add_child(ttl)
	var body := Label.new()
	body.text = "· 上/下是两个各自开打的战场, 分兵布置\n· 点两个单位 = 互换它们的战场 / 位置\n· 点小将的【前排 / 后排】= 近战挥砍 ↔ 远程射击\n· 点下方背包里的装备 → 再点龟 / 小将 = 装上\n· 点单位身上的装备格 = 卸下回背包\n· 3 件同款同星装备自动合成升星"
	body.add_theme_font_size_override("font_size", 15); body.add_theme_color_override("font_color", Color("#cfe0ef"))
	body.position = Vector2(24, 58); body.size = Vector2(bw - 48, bh - 120); body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(body)
	var ok := Button.new(); ok.text = "知道了"; ok.add_theme_font_size_override("font_size", 17)
	ok.position = Vector2(bw / 2.0 - 60, bh - 52); ok.size = Vector2(120, 40)
	ok.pressed.connect(func(): dim.queue_free())
	box.add_child(ok)


# ─── 下部: 装备背包 (大改: 可滑动列表·铺满宽·大格; 说明移到底部操作条) ───
func _build_bench() -> void:
	var hdr := Label.new()
	hdr.text = "装备背包　(可上下滑动)"
	hdr.add_theme_font_size_override("font_size", 18)
	hdr.add_theme_color_override("font_color", Color("#9fb6c9"))
	hdr.position = Vector2(40, 386); hdr.size = Vector2(_vw - 80, 26)
	add_child(hdr)
	var bench: Array = GameState.persistent_bench if GameState.persistent_bench is Array else []
	var gx := 40.0
	var top := 418.0
	var pitch := SLOT + 16.0
	var scroll_w := _vw - 2.0 * gx
	var scroll_h := 630.0 - top             # 到操作条上方
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(gx, top)
	scroll.custom_minimum_size = Vector2(scroll_w, scroll_h); scroll.size = Vector2(scroll_w, scroll_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # 隐滚动条·保留拖动滚动(用户2026-07-19·跟选龟一致)
	add_child(scroll)
	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_PASS   # 触屏拖动透传→ScrollContainer 滚动
	scroll.add_child(content)
	var per_row := maxi(8, int(scroll_w / (SLOT + 8.0)))
	var cpitch := SLOT + 8.0
	var min_rows := int(ceil(scroll_h / pitch))                       # 至少铺满可视区
	var used_rows := int(ceil(float(maxi(bench.size(), 1)) / float(per_row)))
	var total_cells := maxi(min_rows, used_rows) * per_row
	content.custom_minimum_size = Vector2(scroll_w - 4.0, float(int(ceil(float(total_cells) / float(per_row)))) * pitch)
	var i := 0
	for it in bench:
		var col := i % per_row
		var row := i / per_row
		content.add_child(_equip_cell(it, i, Vector2(float(col) * cpitch, float(row) * pitch)))
		i += 1
	while i < total_cells:
		var col2 := i % per_row
		var row2 := i / per_row
		content.add_child(_empty_bench_cell(Vector2(float(col2) * cpitch, float(row2) * pitch)))
		i += 1
	if bench.is_empty():
		var hint := Label.new()
		hint.text = "（背包空 — 去商店买装备）"
		hint.add_theme_font_size_override("font_size", 14); hint.add_theme_color_override("font_color", Color("#5a6675"))
		hint.position = Vector2(6, 6); hint.size = Vector2(600, 22); hint.mouse_filter = Control.MOUSE_FILTER_IGNORE; content.add_child(hint)

# ─── 底部选中操作条 (大改: 替代满屏文字说明; 选中装备才显名/效果/卖出/取消) ───
func _build_op_bar() -> void:
	if _sel_bench < 0 or _sel_bench >= GameState.persistent_bench.size():
		return   # 无选中装备 → 不显底部操作条(原那行"3件同款合成"已收进"?"帮助·用户2026-07-19)
	var by := 636.0
	var bar := Panel.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color("#101c2a"); sb.border_color = Color("#2a3a4e")
	sb.set_border_width_all(2); sb.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("panel", sb)
	var bw := _vw - 48.0
	bar.position = Vector2(24, by); bar.size = Vector2(bw, 66); add_child(bar)
	if _sel_bench >= 0 and _sel_bench < GameState.persistent_bench.size():
		var sit: Dictionary = GameState.persistent_bench[_sel_bench]
		if str(sit.get("kind", "")) == "item":
			var l := Label.new(); l.text = "🔼 临时等级器已选  →  点一只 龟 / 小将,本大轮永久 +1 级"
			l.add_theme_font_size_override("font_size", 16); l.add_theme_color_override("font_color", Color("#e6d8ff"))
			l.position = Vector2(16, 20); l.size = Vector2(bw - 320, 28); l.mouse_filter = Control.MOUSE_FILTER_IGNORE; bar.add_child(l)
		else:
			var sdef: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(sit.get("id", "")), {})
			var l := Label.new()
			l.text = "▶ %s  ★%d  (%s)   —— 点上方【龟 / 小将】装上   ·   %s" % [str(sdef.get("name", "")), int(sit.get("star", 1)), str(sdef.get("rarity", "普通")), str(sdef.get("effectDesc1", ""))]
			l.add_theme_font_size_override("font_size", 14); l.add_theme_color_override("font_color", Color("#ffd93d"))
			l.position = Vector2(16, 10); l.size = Vector2(bw - 320, 48); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.mouse_filter = Control.MOUSE_FILTER_IGNORE; bar.add_child(l)
			var sv := _sell_value(sit)
			var sell := Button.new(); sell.text = "💰 卖出 +%d💠" % sv
			sell.add_theme_font_size_override("font_size", 16)
			sell.position = Vector2(bw - 290, 14); sell.size = Vector2(170, 38)
			sell.pressed.connect(_sell_selected); bar.add_child(sell)
		var cancel := Button.new(); cancel.text = "取消"
		cancel.add_theme_font_size_override("font_size", 16)
		cancel.position = Vector2(bw - 108, 14); cancel.size = Vector2(92, 38)
		cancel.pressed.connect(func(): _sel_bench = -1; _rebuild()); bar.add_child(cancel)

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
	box.mouse_filter = Control.MOUSE_FILTER_PASS   # 空格也透传拖动→可滑动
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
	_wire_bench_tap(box, idx)
	return box


# 背包格点选: 透传拖动给 ScrollContainer(可滑动) + 松开位移小才算点选(滑动不误选).
# ★仅认 mouse: 触屏由 emulate_mouse_from_touch(默认开) 自动转 mouse → 若同时收 touch 会【双触发】, 而 _on_bench_click 是 toggle → 选中瞬间又被切回=装不上(用户2026-07-18"背包怎么装装备"). 只认mouse则每次点选恰一次.
func _wire_bench_tap(box: Control, idx: int) -> void:
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_press_pos = ev.position
			elif ev.position.distance_to(_press_pos) < 16.0:
				_on_bench_click(idx))

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
	box.position = Vector2(_vw - 400.0, 58.0); box.size = Vector2(372, 44)   # 右上·避开居中标题(2026-07-18大改)
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
	_wire_bench_tap(box, idx)
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
