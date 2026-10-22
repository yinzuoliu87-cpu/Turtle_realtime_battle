extends Node
## 背包宝箱龟属性小卡的「藏宝图」栏 + 战斗「战利品」浮层(2026-10-22)。
##
## 用户原话:「然后在哪里有显示获得的装备？图标？在哪里？背包可以看到吗？」「要显示啊」「考虑了5件满的吗」
##   「卡上画战利品？有位置吗，不去信息区？」「藏宝图横着另起一列」「这里的描述也得符合规矩」「就叫星辉？不对啊」
##
## 判据:
##   ① 0 件: 进度「财宝值 0 / 3000」+「还没开出战利品」, 一行战利品都没有
##   ② 2 件: 进度分母 = 第 3 箱阈值; 两行的名字 / 顺序 = 存档; 说明里 {C:} 全展开、数字对上代码常量
##   ③ 5 件最长组合(说明最长的五件): 「已开满 5 件」; 卡片在 720 设计框内(16:9 = 本测试的视口, 最窄的那种)
##   ④ 藏宝图在【右边另起一列】(用户「藏宝图横着另起一列」): 栏左沿在属性表右沿之右, 栏顶与卡头同高
##   ⑤ 别的龟的属性小卡没有藏宝图、宽度不变
##   ⑥ 15 件说明: 占位符全部能展开(引用的常量改名 / 删掉 ⇒ 红); 名字是回合制原名
##   ⑦ 战斗「战利品」浮层正文: 每件带图标 [img] + 名字, 空时一句话

const MIN_ASSERTS := 22
var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


## 摆好存档, 开背包, 点宝箱龟(真入口: 选中单位 ⇒ 弹属性小卡)。返回 [背包场景, 小卡]。
func _open_card(value: float, loot: Array, pid: String = "chest") -> Array:
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	gs.season_leaders = [pid, "stone", "bamboo"]
	gs.season_level = 6
	gs.persistent_equipped = {pid: [{"id": "p2eq_004", "star": 2}], "stone": [], "bamboo": []}
	gs.persistent_bench = []
	gs.dual_lineup = {}
	gs.chest_treasure_value = value
	gs.chest_treasures_won = loot.duplicate()
	var inv = load("res://scenes/Inventory.tscn").instantiate()
	add_child(inv)
	await _frames(8)
	var dl: Dictionary = gs.get_dual_lineup()
	for ln in ["top", "bottom"]:
		var arr: Array = dl.get(ln, [])
		for i in range(arr.size()):
			if arr[i] is Dictionary and str(arr[i].get("id", "")) == pid:
				inv._dl_click(ln, i)
	await _frames(8)
	return [inv, inv.find_child("UnitInspectCard", true, false)]


func _close(inv: Node) -> void:
	inv.queue_free()
	await _frames(3)


func _loot_rows(card: Node) -> Array:
	var out: Array = []
	for i in range(8):
		var r: Node = card.find_child("Loot_%d" % i, true, false)
		if r != null:
			out.append(r)
	return out


func _txt(n: Node) -> String:
	if n is RichTextLabel:
		return (n as RichTextLabel).get_parsed_text()
	if n is Label:
		return (n as Label).text
	return ""


func _ready() -> void:
	## ★无头默认视口是 1280×1280(实测), 那样卡片怎么都在屏内 ⇒ ③ 量的不是最坏情况。先设成 16:9。
	get_window().size = Vector2i(1280, 720)
	await _frames(2)

	# ── ① 0 件 ──
	var r: Array = await _open_card(0.0, [])
	var card: Control = r[1]
	_ok("① ★分母: 宝箱龟属性小卡弹出", card != null)
	if card != null:
		_ok("① 进度「财宝值 0 / 3000」", _txt(card.find_child("TreasureProgress", true, false)) == "财宝值 0 / %d" % int(ChestLoot.THRESH[0]),
			_txt(card.find_child("TreasureProgress", true, false)))
		_ok("① 「还没开出战利品」", card.find_child("TreasureNone", true, false) != null)
		_ok("① 没有战利品行", _loot_rows(card).is_empty())
	await _close(r[0])

	# ── ② 2 件 ──
	r = await _open_card(7200.0, ["rum", "dagger"])
	card = r[1]
	_ok("② ★分母: 小卡弹出", card != null)
	if card != null:
		_ok("② 进度分母 = 第 3 箱阈值", _txt(card.find_child("TreasureProgress", true, false)) == "财宝值 7200 / %d" % int(ChestLoot.THRESH[2]),
			_txt(card.find_child("TreasureProgress", true, false)))
		var rows: Array = _loot_rows(card)
		_ok("② 两行战利品", rows.size() == 2, str(rows.size()))
		if rows.size() == 2:
			_ok("② 顺序 = 存档顺序, 名字取 ChestLoot", _txt(rows[0].find_child("Name", true, false)) == str(ChestLoot.NAME["rum"])
				and _txt(rows[1].find_child("Name", true, false)) == str(ChestLoot.NAME["dagger"]),
				"%s / %s" % [_txt(rows[0].find_child("Name", true, false)), _txt(rows[1].find_child("Name", true, false))])
			var d0 := _txt(rows[0].find_child("Desc", true, false))
			var d1 := _txt(rows[1].find_child("Desc", true, false))
			_ok("② ★说明里的 {C:} 全展开, 数字对上代码常量(朗姆酒 %s%% / 短刃 %s%%)" % [str(ChestSystem.RUM_HEAL_PCT * 100.0), str(ChestSystem.DAGGER_ATK * 100.0)],
				not d0.contains("{") and not d1.contains("{") and d0.contains("0.5%") and d1.contains("25%"), "%s | %s" % [d0, d1])
		## ⑧ 战利品算进属性(用户「要算」): 攻击力 = 本体 + 装备 + 战利品, 战利品那段 = (本体 + 装备) × 短刃 25%
		var va: Label = card.find_child("Val_atk", true, false) as Label
		var ba: RichTextLabel = card.find_child("Br_atk", true, false) as RichTextLabel
		var parts: PackedStringArray = (ba.get_parsed_text() if ba else "").replace("(", "").replace(")", "").split("+")
		var nums: Array = []
		for ps in parts:
			nums.append(int(ps.strip_edges()))
		_ok("⑧ ★攻击力拆成三段(本体 + 装备 + 战利品)且加起来 = 总值", va != null and nums.size() == 3
			and int(nums[0]) + int(nums[1]) + int(nums[2]) == int(va.text), "%s = %s" % [va.text if va else "-", str(nums)])
		if nums.size() == 3:
			_ok("⑧ ★战利品那段 = (本体 + 装备) × 短刃 %d%%" % roundi(ChestSystem.DAGGER_ATK * 100.0),
				absi(int(nums[2]) - roundi((int(nums[0]) + int(nums[1])) * ChestSystem.DAGGER_ATK)) <= 1, str(nums))
	await _close(r[0])

	# ── ③④ 5 件最长组合 ──
	## 选说明展开后最长的那一种组合(每档池里按字数挑最长的), 不是随手挑的五件。
	var worst: Array = []
	for g in [["basic", 2], ["adv", 2], ["legend", 1]]:
		var pool: Array = (ChestLoot.POOL[g[0]] as Array).duplicate()
		pool.sort_custom(func(a, b) -> bool: return ChestLoot.desc_plain(a).length() > ChestLoot.desc_plain(b).length())
		worst.append_array(pool.slice(0, int(g[1])))
	r = await _open_card(31000.0, worst)
	card = r[1]
	_ok("③ ★分母: 小卡弹出(五件 %s)" % str(worst), card != null)
	if card != null:
		_ok("③ 「已开满 5 件」", _txt(card.find_child("TreasureProgress", true, false)) == "已开满 5 件",
			_txt(card.find_child("TreasureProgress", true, false)))
		_ok("③ 五行战利品", _loot_rows(card).size() == 5, str(_loot_rows(card).size()))
		var vp: Vector2 = Vector2(get_viewport().get_visible_rect().size)
		var cr: Rect2 = card.get_global_rect()
		_ok("③ ★视口是 16:9(最窄的那种, 否则这条量的不是最坏情况)", absf(vp.x / vp.y - 16.0 / 9.0) < 0.02, str(vp))
		_ok("③ ★★5 件全开的卡片在屏内(上 ≥ 0, 下 ≤ %.0f, 右 ≤ %.0f)" % [vp.y, vp.x],
			cr.position.y >= -0.5 and cr.end.y <= vp.y + 0.5 and cr.end.x <= vp.x + 0.5, str(cr))
		var tm: Control = card.find_child("TreasureMap", true, false) as Control
		var grid: Control = card.find_child("UnitStatGrid", true, false) as Control
		_ok("④ 藏宝图栏与属性表都在", tm != null and grid != null)
		if tm != null and grid != null:
			_ok("④ ★藏宝图在属性表【右边】另起一列", tm.get_global_rect().position.x >= grid.get_global_rect().end.x,
				"%s vs %s" % [str(tm.get_global_rect()), str(grid.get_global_rect())])
			_ok("④ 藏宝图栏从卡顶开始(与卡头同高, 不压在属性表下面)", tm.get_global_rect().position.y < grid.get_global_rect().position.y,
				"%s vs %s" % [str(tm.get_global_rect().position.y), str(grid.get_global_rect().position.y)])
	await _close(r[0])

	# ── ⑤ 别的龟 ──
	r = await _open_card(5000.0, ["rum"], "basic")
	card = r[1]
	_ok("⑤ ★分母: 小龟的属性小卡弹出", card != null)
	if card != null:
		_ok("⑤ 别的龟没有藏宝图", card.find_child("TreasureMap", true, false) == null and card.find_child("TreasureProgress", true, false) == null)
		var iw: float = float(load("res://scripts/scenes/InventoryScene.gd").ITEM_CARD_W)
		_ok("⑤ 宽度仍是 ITEM_CARD_W", absf(card.size.x - iw) < 1.0, "%s vs %s" % [str(card.size.x), str(iw)])
	await _close(r[0])

	# ── ⑥ 15 件说明 / 名字 ──
	var all_ids: Array = []
	for g in ChestLoot.POOL:
		all_ids.append_array(ChestLoot.POOL[g])
	var bad: Array = []
	for tid in all_ids:
		var d := ChestLoot.desc_plain(str(tid))
		if d == "" or d.contains("{") or not d.ends_with("。"):
			bad.append("%s「%s」" % [tid, d])
	_ok("⑥ ★分母: 15 件", all_ids.size() == ChestSystem.TREASURE_TOTAL, str(all_ids.size()))
	_ok("⑥ ★15 条说明的 {C:} 全部能展开、以句号结尾", bad.is_empty(), str(bad))
	_ok("⑥ 名字是回合制原名(用户「就叫星辉？不对啊」)", str(ChestLoot.NAME["starlight"]) == "星际龟的星辉"
		and str(ChestLoot.NAME["thunder"]) == "闪电龟的雷刃" and str(ChestLoot.NAME["rum"]) == "海盗龟的小瓶朗姆酒")
	_ok("⑥ 星辉说明 = 用户原话「攻击和技能伤害转化为真实伤害」", ChestLoot.desc_plain("starlight") == "攻击和技能伤害转化为真实伤害。",
		ChestLoot.desc_plain("starlight"))

	# ── ⑦ 战斗浮层 ──
	var cs := ChestSystem.new(null)
	var body: String = cs.loot_detail_text({"rum": true, "crown": true})
	_ok("⑦ ★每件带图标(2 件 ⇒ 2 个 [img])", body.count("[img=") == 2 and body.contains(ChestLoot.icon_path("rum")), body.left(160))
	_ok("⑦ 名字在、说明 {C:} 展开", body.contains(str(ChestLoot.NAME["crown"])) and not body.contains("{C:"), body.left(160))
	_ok("⑦ 空时一句话", cs.loot_detail_text({}) == "还没开出战利品。", cs.loot_detail_text({}))

	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少该有 %d) —— 有东西在半路被掐断了, 别当绿灯" % [_n, MIN_ASSERTS])
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 藏宝图栏 / 战利品浮层" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
