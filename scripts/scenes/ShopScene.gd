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
	_rng.randomize()
	_roll()
	_rebuild()

func _shop_level() -> int:
	return clampi(int(GameState.season_level), 1, 10)   # 大轮等级驱动出货档 (用户 2026-06-27)

func _roll() -> void:
	_offer = Phase2Equip.roll_shop(DataRegistry.phase2_equipment, _shop_level(), 10, _rng)

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

	var sub := Label.new(); sub.text = "10 卡货架 · 点卡购买 → 进背包 · 大轮等级越高越易出高费装备 (Lv%d)" % _shop_level()
	sub.add_theme_font_size_override("font_size", 16); sub.add_theme_color_override("font_color", Color("#9fb6c9"))
	sub.position = Vector2(60, 92); sub.size = Vector2(900, 24); add_child(sub)

	var gx := 80.0
	var gy := 140.0
	for i in range(_offer.size()):
		var col := i % 5
		var row := i / 5
		add_child(_card(i, Vector2(gx + col * (SLOT_W + 24), gy + row * (SLOT_H + 28))))

	var rf := Button.new(); rf.text = "🔄 刷新 (-%d💠)" % REFRESH_COST
	rf.add_theme_font_size_override("font_size", 20)
	rf.position = Vector2(W / 2.0 - 110, gy + 2 * (SLOT_H + 28) + 16); rf.size = Vector2(220, 48)
	rf.pressed.connect(_on_refresh); add_child(rf)
	_build_bench_preview()

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
