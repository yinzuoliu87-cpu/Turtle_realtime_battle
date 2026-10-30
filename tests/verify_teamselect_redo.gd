extends Node
## verify_teamselect_redo.gd —— 选龟页整页重做(2026-10-30 · 方案书 docs/plans/20261030-选龟页重做.md §6)。
##
## 用户 10-30「你这还是一股浏览器的感觉啊」「锁定后的就不用去显示其他龟和稀有度了啊」「右侧4个属性感觉不用显示，或者不能去这么显示吧」。
##   A 全选版: 稀有度页签 7 个(无框: 各态 stylebox 都是空的)、龟池 = 全部龟、每张卡 = 背包同款框 + 稀有度字母(= 那只的稀有度)+ 实战等级
##   B 统领位 = 背包同款大卡(框 + 横幅 + 下沿木托); 出战键有皮(不是透明按钮)
##   C 右栏: 定位词 = turtle_stats.ROLE(「近战 · 坦克」), 不再常驻生命 / 攻击 / 护甲 / 魔抗四个数字
##   D 锁定版: 不显示龟池与页签、龟池不建卡; 页名「本大轮统领」; 撤下 / 沿用上次不显示; 常驻提示签; 三张统领卡比全选版大
##   E 背景: 旧版烤在桌面上的 6 卡槽 / 凹槽已铺回桌板(卡槽「+」那一格的像素与原图不同)

const TS := "res://scenes/TeamSelect.tscn"
const TurtleStats := preload("res://scripts/gamedata/turtle_stats.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _labels(n: Node) -> Array:
	var out: Array = []
	for c in n.find_children("*", "Label", true, false):
		if (c as Label).is_visible_in_tree():
			out.append(str((c as Label).text))
	return out


func _open(locked: bool) -> Node:
	GameState.test_mode = true
	if int(GameState.season_total_battles) <= 0:
		GameState.season_total_battles = 3
	GameState.tutorial_active = false
	GameState.season_leaders = ["lava", "stone", "ninja"] if locked else []
	var ts = (load(TS) as PackedScene).instantiate()
	add_child(ts)
	await _frames(30)
	return ts


func _ready() -> void:
	get_tree().root.size = Vector2i(1560, 720)
	await _frames(2)
	print("=== 选龟页重做 ===")

	# ── A / B / C 全选版 ──
	var ts = await _open(false)
	_ok("分母: 全选版(没锁)", not bool(ts._roster_locked))
	var tabs: Array = ts._rarity_btns
	var empty_skin := true
	for e in tabs:
		for st in ["normal", "hover", "pressed"]:
			if not ((e["btn"] as Button).get_theme_stylebox(st) is StyleBoxEmpty):
				empty_skin = false
	_ok("A ★稀有度页签 7 个, 没有框(各态 stylebox 都是空的)", tabs.size() == 7 and empty_skin, "%d 个" % tabs.size())
	var cards: Array = (ts._grid_flow as Node).get_children()
	_ok("A ★龟池 = 全部龟", cards.size() == DataRegistry.launch_pets.size(), "%d / %d" % [cards.size(), DataRegistry.launch_pets.size()])
	var bad_card := ""
	for c in cards:
		var pid := str((c as Node).get_meta("pet_id", ""))
		var pet: Dictionary = DataRegistry.pet_by_id.get(pid, {})
		var rt := (c as Node).get_node_or_null("RarityTag") as Label
		var lv := (c as Node).get_node_or_null("Level") as Label
		var fr := (c as Node).get_node_or_null("CardFrame") as TextureRect
		if rt == null or rt.text != str(pet.get("rarity", "?")) or lv == null \
				or lv.text != "Lv.%d" % GameState.battle_level_for(pid) or fr == null \
				or fr.texture == null or not str(fr.texture.resource_path).ends_with("inventory/unit-card.png"):
			bad_card = pid
			break
	_ok("A ★每张龟池卡: 背包同款框 + 稀有度字母 = 那只的稀有度 + 实战等级", cards.size() > 0 and bad_card == "", "不对的: %s" % bad_card)
	## B 统领位: 先放一只上去
	ts._on_pick_pet("lava")
	await _frames(4)
	var slot0: Control = ts._slot_nodes[0]
	var card0: Node = slot0.get_node_or_null("Content")
	var has_frame: bool = card0 != null and card0.get_node_or_null("CardFrame") != null
	var has_banner: bool = card0 != null and card0.get_node_or_null("NameBanner") != null
	var has_strip: bool = card0 != null and card0.get_node_or_null("LoadoutStrip") != null
	_ok("B ★统领位 = 背包同款大卡(框 + 名字横幅 + 下沿木托)", has_frame and has_banner and has_strip,
		"框 %s 横幅 %s 木托 %s" % [has_frame, has_banner, has_strip])
	var bn_txt := ""
	if has_banner:
		bn_txt = str((card0.get_node("NameBanner").get_node("Name") as Label).text)
	_ok("B 统领大卡横幅写的是这只龟的名字", bn_txt == str(DataRegistry.pet_by_id["lava"]["name"]), bn_txt)
	## 量「是像素金键那张贴图皮」, 不是「不透明」: 拿掉皮会退回主题默认按钮框(第一版这么量, 反向验证打不红)
	var sb_n: StyleBox = (ts._start_btn as Button).get_theme_stylebox("normal")
	_ok("B ★出战键有皮: 像素金键(贴图皮, 不是透明 / 主题默认框)", (ts._start_btn as Button).has_theme_stylebox_override("normal")
		and sb_n is StyleBoxTexture, str(sb_n))
	## C 右栏
	ts._set_detail_pet("stone")
	await _frames(3)
	var role := str(TurtleStats.ROLE.get("stone", ""))
	var dt: Array = _labels(ts._dt_stats)
	_ok("C ★右栏定位词 = turtle_stats.ROLE(「近战 · 坦克」)", role.length() >= 4 and dt.has("%s · %s" % [role.substr(0, 2), role.substr(2)]), str(dt))
	var nums := false
	for word in ["生命值", "攻击力", "护甲", "魔抗"]:
		for l in _labels(ts):
			if l == word:
				nums = true
	_ok("C ★右栏不再常驻生命 / 攻击 / 护甲 / 魔抗四个数字", not nums)
	var open_slot_h: float = slot0.size.y
	ts.queue_free()
	await _frames(3)

	# ── D 锁定版 ──
	ts = await _open(true)
	_ok("分母: 锁定版", bool(ts._roster_locked))
	var rail_vis := false
	for n in ts.find_children("RarityTabs", "", true, false):
		if (n as CanvasItem).is_visible_in_tree():
			rail_vis = true
	_ok("D ★锁定后不显示稀有度页签", not rail_vis and (ts._rarity_btns as Array).is_empty())
	_ok("D ★锁定后不显示龟池、也不建卡", ts._grid_flow == null or (not (ts._grid_flow as CanvasItem).is_visible_in_tree()
		and (ts._grid_flow as Node).get_child_count() == 0), "卡 %d" % ((ts._grid_flow as Node).get_child_count() if ts._grid_flow != null else -1))
	var title_ok := false
	for l in _labels(ts):
		if l == "本大轮统领":
			title_ok = true
	_ok("D 页名「本大轮统领」", title_ok)
	_ok("D 撤下 / 沿用上次不显示", not (ts._clear_btn as Control).visible and not (ts._last_btn as Control).visible)
	var hint := ts.find_child("LockedHint", true, false) as Label
	_ok("D 常驻提示签在", hint != null and hint.is_visible_in_tree() and hint.text == ts.LOCKED_HINT)
	var lk_h: float = (ts._slot_nodes[0] as Control).size.y
	_ok("D ★锁定版三张统领卡比全选版大(放大占龟池那一片)", lk_h >= open_slot_h * 1.4, "%.0f vs %.0f" % [lk_h, open_slot_h])
	_ok("D 三张都是这一轮的统领", Array(ts.team) == ["lava", "stone", "ninja"], str(ts.team))
	ts.queue_free()
	await _frames(3)

	# ── E 背景 ──
	var img: Image = (load("res://assets/sprites/bg/select-bg.png") as Texture2D).get_image()
	var src := Image.load_from_file(ProjectSettings.globalize_path("res://tools/art_src/select-bg-src.png"))
	_ok("E 分母: 源图在、尺寸相同", src != null and src.get_size() == img.get_size())
	if src != null and src.get_size() == img.get_size():
		## 旧版第一格卡槽中心的「+」(设计坐标 ~ (509, 255)) 与龟池凹槽中心(~ (710, 575)) 已不是原图的像素
		var diff := 0
		for p in [Vector2i(509, 255), Vector2i(1134, 255), Vector2i(710, 575), Vector2i(1365, 250)]:
			if not img.get_pixelv(p).is_equal_approx(src.get_pixelv(p)):
				diff += 1
		_ok("E ★旧版烤死的卡槽 / 凹槽 / 右栏格子已铺回桌板(4 处采样都与原图不同)", diff == 4, "%d / 4" % diff)
		_ok("E 左上羊皮纸原样保留(纸中心像素与原图相同)", img.get_pixel(270, 200).is_equal_approx(src.get_pixel(270, 200)))

	GameState.season_leaders = []
	print("分母: %d 条断言" % _n)
	print("ALL PASS — 选龟页重做 (%d/%d)" % [_n, _n] if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
