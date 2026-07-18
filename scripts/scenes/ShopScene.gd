extends Control

## ShopScene — V2 局外商店 (阶段2, 设计§五/§十一). 10 卡货架, 用 meta_deepsea_coins 买装备入持久背包.
## 刷新固定 2 币; 买价 = 装备 cost (几费卖几深海币, 1:1, 用户 2026-07-01); 出货档随赛季总战斗数. 复用 Phase2Equip.roll_shop 出货算法.

const W := 1280.0
const SLOT_W := 108.0
const SLOT_H := 132.0
const REFRESH_COST := 2
const PRICE_MULT := 1        # 售价 = 装备 cost (费) × 1 = 几费卖几深海币 (用户 2026-07-01; 原 ×3 占位已改)
const Phase2Equip = preload("res://scripts/engine/phase2_equip.gd")
const P2 = preload("res://scripts/engine/phase2_config.gd")

var _offer: Array = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if int(GameState.season_total_battles) <= 0:
		_build_locked()   # 商店锁: 本大轮未打第一场 → 不开店(用户2026-07-18「商店打完第一场后解锁」)
		return
	_rng.randomize()
	_roll()
	_rebuild()

## 商店上锁屏 (大轮开局·未打第一场): 提示 + 返回, 不出货架
func _build_locked() -> void:
	var vw := maxf(W, get_viewport_rect().size.x)
	var bg := ColorRect.new()
	bg.color = Color("#0a1622")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var lbl := Label.new()
	lbl.text = "🔒 商店未开\n\n本大轮打完第一场战斗后开店"
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color("#ffd93d"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.position = Vector2(vw / 2.0 - 320.0, 250.0); lbl.size = Vector2(640, 180)
	add_child(lbl)
	var back := Button.new()
	back.text = "← 返回"
	back.add_theme_font_size_override("font_size", 20)
	back.position = Vector2(28, 26); back.size = Vector2(120, 44)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	add_child(back)

func _shop_level() -> int:
	return clampi(int(GameState.season_level), 1, 10)   # 大轮等级驱动出货档 (用户 2026-06-27)

func _roll() -> void:
	# 用户2026-07-18: 已3星(满星)的装备不再出现在货架(买了也没用·避免占位)
	var maxed := _maxed_item_ids()
	var pool: Array = DataRegistry.phase2_equipment
	if not maxed.is_empty():
		pool = []
		for e in DataRegistry.phase2_equipment:
			if not maxed.has(str((e as Dictionary).get("id", ""))):
				pool.append(e)
	_offer = Phase2Equip.roll_shop(pool, _shop_level(), 10, _rng)

# 玩家已有 3 星(满星)的装备 id 集合(背包+统领已装+小将已装)→ 商店 roll 时排除
func _maxed_item_ids() -> Dictionary:
	var s := {}
	for it in GameState.persistent_bench:
		if it is Dictionary and int(it.get("star", 1)) >= 3: s[str(it.get("id", ""))] = true
	if GameState.persistent_equipped is Dictionary:
		for pid in GameState.persistent_equipped:
			for it2 in GameState.persistent_equipped[pid]:
				if it2 is Dictionary and int(it2.get("star", 1)) >= 3: s[str(it2.get("id", ""))] = true
	if GameState.has_method("get_dual_lineup"):
		var lineup: Dictionary = GameState.get_dual_lineup()
		for lk in ["top", "bottom"]:
			for u in lineup.get(lk, []):
				if u is Dictionary and u.get("equips") is Array:
					for it3 in u["equips"]:
						if it3 is Dictionary and int(it3.get("star", 1)) >= 3: s[str(it3.get("id", ""))] = true
	return s

func _price(edef: Dictionary) -> int:
	return maxi(1, int(edef.get("cost", 1))) * PRICE_MULT

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):   # ESC 返回主菜单 (与图鉴一致)
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _rebuild() -> void:
	for c in get_children():
		c.visible = false
		c.queue_free()
	var bg := ColorRect.new(); bg.color = Color("#0a1622")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)

	var title := Label.new(); title.text = "🛒 深海商店"
	title.add_theme_font_size_override("font_size", 32); title.add_theme_color_override("font_color", Color("#ffd93d"))
	title.position = Vector2(W / 2.0 - 160, 22); title.size = Vector2(320, 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(title)

	var back := Button.new(); back.text = "← 返回"; back.add_theme_font_size_override("font_size", 20)
	back.position = Vector2(28, 26); back.size = Vector2(120, 44)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")); add_child(back)

	var inv := Button.new(); inv.text = "🎒 背包"; inv.add_theme_font_size_override("font_size", 20)
	inv.position = Vector2(160, 26); inv.size = Vector2(120, 44)
	inv.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Inventory.tscn")); add_child(inv)

	var coin := Label.new(); coin.text = "💠 深海币 %d" % int(GameState.meta_deepsea_coins)
	coin.add_theme_font_size_override("font_size", 24); coin.add_theme_color_override("font_color", Color("#5fd0e0"))
	coin.position = Vector2(W - 280, 30); coin.size = Vector2(252, 34)
	coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; add_child(coin)
	# 大轮等级 + 买经验 (设计§五: 4费=4XP, 升级→出货档/装备槽涨)
	var lv := Label.new()
	lv.text = "大轮 Lv %d  (XP %d/%d)" % [int(GameState.season_level), int(GameState.season_xp), P2.xp_to_next(int(GameState.season_level))]
	lv.add_theme_font_size_override("font_size", 17); lv.add_theme_color_override("font_color", Color("#ffd93d"))
	lv.position = Vector2(W - 320, 64); lv.size = Vector2(292, 24); lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; add_child(lv)
	var bxp := Button.new(); bxp.text = "买经验 (4💠 → +4XP)"
	bxp.add_theme_font_size_override("font_size", 15)
	bxp.position = Vector2(W - 320, 92); bxp.size = Vector2(200, 36)
	bxp.pressed.connect(func(): if GameState.buy_season_xp(): _rebuild())
	add_child(bxp)

	var sub := Label.new(); sub.text = "10 卡货架 · 点卡购买 → 进背包 (Lv%d)" % _shop_level()
	sub.add_theme_font_size_override("font_size", 16); sub.add_theme_color_override("font_color", Color("#9fb6c9"))
	sub.position = Vector2(60, 90); sub.size = Vector2(400, 24); add_child(sub)
	_build_odds_row()   # ★#2: 出货概率(云顶式)

	var gx := 80.0
	var gy := 150.0
	for i in range(_offer.size()):
		var col := i % 5
		var row := i / 5
		add_child(_card(i, Vector2(gx + col * (SLOT_W + 24), gy + row * (SLOT_H + 28))))

	var rf := Button.new(); rf.text = "🔄 刷新 (-%d💠)" % REFRESH_COST
	rf.add_theme_font_size_override("font_size", 20)
	rf.position = Vector2(W / 2.0 - 110, gy + 2 * (SLOT_H + 28) + 16); rf.size = Vector2(220, 48)
	rf.pressed.connect(_on_refresh); add_child(rf)
	_build_bench_preview()
	_build_lineup_equips()   # 用户2026-07-18「商店里看不到装备在龟身上的东西」→ 右侧只读阵容+已装备面板

## ★#2 出货概率行(云顶式): 当前大轮等级下各费用档(1-5)的出货概率%. 每费用色=对应稀有度色, 0%淡显.
func _build_odds_row() -> void:
	var odds: Array = P2.shop_cost_odds(_shop_level())   # [费1% .. 费5%]
	var cost_cols := ["#9aa0b0", "#4ade80", "#60a5fa", "#c084fc", "#fbbf24"]   # 费1-5: 普通灰/精良绿/稀有蓝/史诗紫/传说金
	var row := HBoxContainer.new()
	row.position = Vector2(60, 116); row.size = Vector2(760, 24)
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	var lbl := Label.new(); lbl.text = "出货概率"
	lbl.add_theme_font_size_override("font_size", 15); lbl.add_theme_color_override("font_color", Color("#8aa0b4"))
	row.add_child(lbl)
	for c in range(5):
		var pct: int = int(odds[c]) if c < odds.size() else 0
		var chip := Label.new()
		chip.text = "%d费 %d%%" % [c + 1, pct]
		chip.add_theme_font_size_override("font_size", 16)
		var cc := Color(cost_cols[c])
		chip.add_theme_color_override("font_color", cc if pct > 0 else Color(cc.r, cc.g, cc.b, 0.28))
		row.add_child(chip)

## 商店下部背包预览 (设计§十一: 显装备管理方便对照/3合1; 详细操作回背包页).
func _build_bench_preview() -> void:
	var bench: Array = GameState.persistent_bench
	var bh := Label.new()
	bh.text = "我的背包 (%d 件)  —  回 🎒 背包页 装备/合星/卖" % bench.size()
	bh.add_theme_font_size_override("font_size", 15); bh.add_theme_color_override("font_color", Color("#9fb6c9"))
	bh.position = Vector2(80, 560); bh.size = Vector2(900, 22); add_child(bh)
	var n := mini(14, bench.size())
	for j in range(n):
		var it: Dictionary = bench[j]
		var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(it.get("id", "")), {})
		var cell := Panel.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color("#162230"); csb.border_color = _rarity_color(str(edef.get("rarity", "普通")))
		csb.set_border_width_all(2); csb.set_corner_radius_all(6)
		cell.add_theme_stylebox_override("panel", csb)
		cell.position = Vector2(80 + j * 72, 590); cell.size = Vector2(64, 64); add_child(cell)
		var img := str(edef.get("img", ""))
		if img != "" and ResourceLoader.exists("res://assets/sprites/" + img):
			var ic := TextureRect.new(); ic.texture = load("res://assets/sprites/" + img)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ic.position = Vector2(14, 6); ic.size = Vector2(36, 32); cell.add_child(ic)
		var st := Label.new(); st.text = "★".repeat(int(it.get("star", 1)))
		st.add_theme_font_size_override("font_size", 11); st.add_theme_color_override("font_color", Color("#ffd93d"))
		st.position = Vector2(0, 44); st.size = Vector2(64, 16); st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(st)
	if bench.is_empty():
		var e := Label.new(); e.text = "（空 — 上面买几件）"
		e.add_theme_font_size_override("font_size", 14); e.add_theme_color_override("font_color", Color("#5a6675"))
		e.position = Vector2(84, 592); e.size = Vector2(400, 22); add_child(e)

# 右侧只读面板: 出战阵容(上/下路6单位)每个龟/小将身上装了什么(用户2026-07-18「商店里看不到装备在龟身上的东西」)。在🎒背包页调整; 这里只看。
func _build_lineup_equips() -> void:
	var lineup: Dictionary = GameState.get_dual_lineup() if GameState.has_method("get_dual_lineup") else {}
	var px := 730.0
	var hdr := Label.new(); hdr.text = "🐢 出战阵容 · 已装备（回 🎒 背包页调整）"
	hdr.add_theme_font_size_override("font_size", 16); hdr.add_theme_color_override("font_color", Color("#9fb6c9"))
	hdr.position = Vector2(px, 148); hdr.size = Vector2(540, 22); add_child(hdr)
	var row := 0
	for lk in ["top", "bottom"]:
		for u in (lineup.get(lk, []) as Array):
			if not (u is Dictionary): continue
			var y := 178.0 + row * 56.0
			row += 1
			var is_leader := str(u.get("kind", "")) == "leader"
			var nm := ""
			if is_leader:
				nm = str(DataRegistry.pet_by_id.get(str(u.get("id", "")), {}).get("name", u.get("id", "龟")))
			elif bool(u.get("elite", false)):
				nm = "精英小将"
			else:
				nm = "近战小将" if str(u.get("role", "front")) == "front" else "远程小将"
			var nl := Label.new(); nl.text = "%s·%s" % ["上" if lk == "top" else "下", nm]
			nl.add_theme_font_size_override("font_size", 15); nl.add_theme_color_override("font_color", Color("#e8f2ff"))
			nl.position = Vector2(px, y + 16); nl.size = Vector2(122, 24); add_child(nl)
			var eqs: Array = []
			if is_leader:
				var pe = GameState.persistent_equipped.get(str(u.get("id", "")), []) if GameState.persistent_equipped is Dictionary else []
				if pe is Array: eqs = pe
			elif u.get("equips") is Array:
				eqs = u["equips"]
			if eqs.is_empty():
				var e := Label.new(); e.text = "（无装备）"
				e.add_theme_font_size_override("font_size", 13); e.add_theme_color_override("font_color", Color("#5a6675"))
				e.position = Vector2(px + 130, y + 18); e.size = Vector2(200, 22); add_child(e)
			else:
				for ci in range(mini(eqs.size(), 6)):
					var it: Dictionary = eqs[ci]
					var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(it.get("id", "")), {})
					var cell := Panel.new()
					var csb := StyleBoxFlat.new(); csb.bg_color = Color("#162230")
					csb.border_color = _rarity_color(str(edef.get("rarity", "普通"))); csb.set_border_width_all(2); csb.set_corner_radius_all(6)
					cell.add_theme_stylebox_override("panel", csb)
					cell.position = Vector2(px + 130 + ci * 56, y); cell.size = Vector2(50, 50)
					cell.tooltip_text = "%s ★%d" % [str(edef.get("name", "?")), int(it.get("star", 1))]
					add_child(cell)
					var img := str(edef.get("img", ""))
					if img != "" and ResourceLoader.exists("res://assets/sprites/" + img):
						var ic := TextureRect.new(); ic.texture = load("res://assets/sprites/" + img)
						ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
						ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
						ic.position = Vector2(9, 3); ic.size = Vector2(32, 30); ic.mouse_filter = Control.MOUSE_FILTER_IGNORE; cell.add_child(ic)
					var st := Label.new(); st.text = "★".repeat(int(it.get("star", 1)))
					st.add_theme_font_size_override("font_size", 10); st.add_theme_color_override("font_color", Color("#ffd93d"))
					st.position = Vector2(0, 35); st.size = Vector2(50, 14); st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					st.mouse_filter = Control.MOUSE_FILTER_IGNORE; cell.add_child(st)
	if row == 0:
		var e2 := Label.new(); e2.text = "（尚未编排出战阵容 · 去背包/选龟）"
		e2.add_theme_font_size_override("font_size", 14); e2.add_theme_color_override("font_color", Color("#5a6675"))
		e2.position = Vector2(px, 182); e2.size = Vector2(400, 22); add_child(e2)

# 已拥有该装备件数(背包+统领已装+小将已装): 商店卡标"已有N"→知道再买几件凑3合1升星(用户2026-07-18"看不到已装备/不知道多少件才2/3星")
func _owned_count(item_id: String) -> int:
	if item_id == "": return 0
	var n := 0
	for it in GameState.persistent_bench:
		if it is Dictionary and str(it.get("id", "")) == item_id: n += 1
	if GameState.persistent_equipped is Dictionary:
		for pid in GameState.persistent_equipped:
			for it2 in GameState.persistent_equipped[pid]:
				if it2 is Dictionary and str(it2.get("id", "")) == item_id: n += 1
	if GameState.has_method("get_dual_lineup"):
		var lineup: Dictionary = GameState.get_dual_lineup()
		for lk in ["top", "bottom"]:
			for u in lineup.get(lk, []):
				if u is Dictionary and u.get("equips", null) is Array:
					for it3 in u["equips"]:
						if it3 is Dictionary and str(it3.get("id", "")) == item_id: n += 1
	return n

func _rarity_color(rarity: String) -> Color:
	match rarity:
		"精良": return Color("#4ade80")
		"稀有": return Color("#60a5fa")
		"史诗": return Color("#c084fc")
		"传说": return Color("#fbbf24")
		_: return Color("#8a96a3")

func _card(idx: int, pos: Vector2) -> Control:
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	var bought: bool = _offer[idx] == null
	sb.bg_color = Color("#11202e") if not bought else Color("#0c141c")
	sb.border_color = (_rarity_color(str((_offer[idx] as Dictionary).get("rarity", "普通"))) if not bought else Color("#1a2630"))
	sb.set_border_width_all(2); sb.set_corner_radius_all(8)
	box.add_theme_stylebox_override("panel", sb)
	box.position = pos; box.size = Vector2(SLOT_W, SLOT_H)
	if bought:
		var sold := Label.new(); sold.text = "已购"
		sold.add_theme_color_override("font_color", Color("#4a5663")); sold.add_theme_font_size_override("font_size", 16)
		sold.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; sold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sold.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(sold)
		return box
	var edef: Dictionary = _offer[idx]
	var cost := Label.new(); cost.text = "%d 费" % int(edef.get("cost", 1))
	cost.add_theme_font_size_override("font_size", 12); cost.add_theme_color_override("font_color", Color("#9fb6c9"))
	cost.position = Vector2(0, 6); cost.size = Vector2(SLOT_W, 18); cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cost)
	var img := str(edef.get("img", ""))
	if img != "" and ResourceLoader.exists("res://assets/sprites/" + img):
		var ic := TextureRect.new(); ic.texture = load("res://assets/sprites/" + img)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.position = Vector2(SLOT_W / 2.0 - 26, 26); ic.size = Vector2(52, 44)
		box.add_child(ic)
	var nm := Label.new(); nm.text = str(edef.get("name", edef.get("id", "?")))
	nm.add_theme_font_size_override("font_size", 13); nm.add_theme_color_override("font_color", Color("#e8f2ff"))
	nm.position = Vector2(2, 74); nm.size = Vector2(SLOT_W - 4, 28)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(nm)
	var owned := _owned_count(str(edef.get("id", "")))   # 已拥有件数(凑3件同款同星→自动升星)
	if owned > 0:
		var oc := Label.new(); oc.text = "已有%d" % owned
		oc.add_theme_font_size_override("font_size", 12); oc.add_theme_color_override("font_color", Color("#ffd93d") if owned >= 2 else Color("#9fb6c9"))
		oc.position = Vector2(SLOT_W - 66, 6); oc.size = Vector2(60, 18); oc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(oc)
	var price := _price(edef)
	var afford := int(GameState.meta_deepsea_coins) >= price
	var pr := Label.new(); pr.text = "💠 %d" % price
	pr.add_theme_font_size_override("font_size", 16)
	pr.add_theme_color_override("font_color", Color("#5fd0e0") if afford else Color("#ff6b6b"))
	pr.position = Vector2(0, SLOT_H - 30); pr.size = Vector2(SLOT_W, 24); pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(pr)
	for ch in box.get_children():
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.tooltip_text = "%s (%d费 · %s)\n%s" % [str(edef.get("name", "?")), int(edef.get("cost", 1)), str(edef.get("rarity", "普通")), str(edef.get("effectDesc1", ""))]
	box.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _on_buy(idx))
	return box

func _on_buy(idx: int) -> void:
	if idx < 0 or idx >= _offer.size() or _offer[idx] == null:
		return
	var edef: Dictionary = _offer[idx]
	var price := _price(edef)
	if int(GameState.meta_deepsea_coins) < price:
		return   # 买不起
	GameState.meta_deepsea_coins -= price
	GameState.persistent_bench.append({"id": str(edef.get("id", "")), "star": 1})
	GameState.auto_merge_all()   # 买后自动 3 合 1 (背包+龟身一起算)
	_offer[idx] = null
	GameState.save()
	_rebuild()

func _on_refresh() -> void:
	if int(GameState.meta_deepsea_coins) < REFRESH_COST:
		return
	GameState.meta_deepsea_coins -= REFRESH_COST
	_roll()
	GameState.save()
	_rebuild()
