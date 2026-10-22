extends Node
## 背包宝箱龟属性小卡的「藏宝图」栏 + 战斗「战利品」浮层(2026-10-22)。
##
## 用户原话:「然后在哪里有显示获得的装备？图标？在哪里？背包可以看到吗？」「要显示啊」「考虑了5件满的吗」
##   「卡上画战利品？有位置吗，不去信息区？」「藏宝图横着另起一列」「这里的描述也得符合规矩」「就叫星辉？不对啊」
##
## 判据:
##   ① 0 件: 「战利品 0/5」+ 进度「0 / 3000」, 一行战利品都没有(说法照对局信息面板, 不自编「还没开出」这类话)
##   ② 2 件: 进度分母 = 第 3 箱阈值; 两行的名字 / 顺序 = 存档; 说明里 {C:} 全展开、数字对上代码常量
##   ③ 5 件最长组合(说明最长的五件): 「战利品 5/5」、进度条不画(对局面板开满也不画); 卡片在屏内(16:9, 最窄的那种)
##   ④ 藏宝图在【右边另起一列】(用户「藏宝图横着另起一列」): 栏左沿在属性表右沿之右, 栏顶与卡头同高
##   ⑤ 别的龟的属性小卡没有藏宝图、宽度不变
##   ⑥ 15 件说明: 占位符全部能展开(引用的常量改名 / 删掉 ⇒ 红); 名字是回合制原名
##   ⑦ 战斗「战利品」浮层正文: 每件带图标 [img] + 名字, 空时一句话

const MIN_ASSERTS := 22
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
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


var _inv_vals := {}
var _greed_on_battle := false


func _check_battle_panel_matches(loot: Array, tag: String) -> void:
	var gs = get_node("/root/GameState")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await _frames(2)
	var lv: int = int(gs.battle_level_for("chest"))
	gs.debug_level = lv                                    # 背包小卡用的就是这个等级(battle_level_for)
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit("chest", "left", c)
	gs.debug_level = 0
	u["equips"] = [{"id": "p2eq_004", "star": 2}]
	## 照真实开局的次序(battle_spawn: _apply_spawn_passives 在 _eq_apply_all_stats 之前):
	##   宝箱账起点 = 存档(左方就是这样起账; 开发工具场默认空账, 这里补上) ⇒ 登场钩子(spawn_loot 回装 + 选了财宝炮击时的贪婪) ⇒ 装备属性
	var lg: Dictionary = s._chest_sys._ledger_of("left")
	lg["base_won"] = loot.duplicate()
	s._units.clear()
	s._units.append(u)
	s._spawn._apply_spawn_passive_one(u)
	for e in u["equips"]:
		s._equip_sys._stats._eq_apply_one_stats(u, str(e["id"]), int(e["star"]))
	s._recalc_stats(u)
	_greed_on_battle = bool(u.get("chest_greed", false))
	var tiles := {}
	for row in s._info_sys._info_stat_tiles(u):
		tiles[str(row[1])] = str(row[2])
	var want := {"hp": "%d" % int(u["maxHp"]), "atk": tiles.get("攻击", "?"), "def": tiles.get("护甲", "?"),
		"mr": tiles.get("魔抗", "?"), "crit": tiles.get("暴击", "?"), "critDmg": tiles.get("暴伤", "?")}
	_ok("%s ★分母: 等级 %d、对局单位六格都取到了、战利品回装了 %d 件" % [tag, lv, (u.get("chest_treasures", {}) as Dictionary).size()],
		lv >= 1 and not want.values().has("?") and (u.get("chest_treasures", {}) as Dictionary).size() == loot.size(), str(want))
	var diff: Array = []
	for k in want:
		if str(_inv_vals.get(k, "-")) != str(want[k]):
			diff.append("%s 背包「%s」/ 对局「%s」" % [k, _inv_vals.get(k, "-"), want[k]])
	_ok("%s ★★背包属性小卡六个数 == 对局信息面板(同等级 / 装备 / 战利品 / 技能选择)" % tag, diff.is_empty(), str(diff))
	s._units.clear()
	s.set_process(false)
	s.queue_free()
	await _frames(2)


## 括号拆解「(25% + 35% + 75%)」⇒ [25, 35, 75]
func _nums(n: Node) -> Array:
	var out: Array = []
	if not (n is RichTextLabel):
		return out
	for ps in (n as RichTextLabel).get_parsed_text().replace("(", "").replace(")", "").replace("%", "").split("+", false):
		out.append(int(ps.strip_edges()))
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
		_ok("① 「战利品 0/5」(= 对局信息面板入口条的写法)", _txt(card.find_child("TreasureCount", true, false)) == "战利品 0/%d" % ChestLoot.THRESH.size(),
			_txt(card.find_child("TreasureCount", true, false)))
		_ok("① 进度「0 / 3000」", _txt(card.find_child("TreasureProgress", true, false)) == "0 / %d" % int(ChestLoot.THRESH[0]),
			_txt(card.find_child("TreasureProgress", true, false)))
		_ok("① 没有战利品行", _loot_rows(card).is_empty())
	await _close(r[0])

	# ── ② 2 件 ──
	r = await _open_card(7200.0, ["rum", "dagger"])
	card = r[1]
	_ok("② ★分母: 小卡弹出", card != null)
	if card != null:
		_ok("② 「战利品 2/5」+ 进度分母 = 第 3 箱阈值", _txt(card.find_child("TreasureCount", true, false)) == "战利品 2/%d" % ChestLoot.THRESH.size()
			and _txt(card.find_child("TreasureProgress", true, false)) == "7200 / %d" % int(ChestLoot.THRESH[2]),
			"%s | %s" % [_txt(card.find_child("TreasureCount", true, false)), _txt(card.find_child("TreasureProgress", true, false))])
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
		_ok("⑨ 反面: 暴击率没溢出时没有折算说明", card.find_child("CritOverNote", true, false) == null)
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
		_ok("③ 「战利品 5/5」, 进度条不画(对局面板开满也不画)", _txt(card.find_child("TreasureCount", true, false)) == "战利品 5/5"
			and card.find_child("TreasureProgress", true, false) == null and card.find_child("TreasureBar", true, false) == null,
			_txt(card.find_child("TreasureCount", true, false)))
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

	# ── ⑨ 暴击率溢出: 与战斗面板同一口径(用户 2026-10-22「要」)──
	##   身上 004(暴击)+ 骰子龟的血筛子 + 王者之冠 ⇒ 暴击率来源合计 > 100%
	r = await _open_card(31000.0, ["blood_dice", "dagger", "flint", "poison", "crown"])
	card = r[1]
	_ok("⑨ ★分母: 小卡弹出", card != null)
	if card != null:
		var vc: Label = card.find_child("Val_crit", true, false) as Label
		var vd: Label = card.find_child("Val_critDmg", true, false) as Label
		var bc := _nums(card.find_child("Br_crit", true, false))
		var bd := _nums(card.find_child("Br_critDmg", true, false))
		var raw_c := 0
		for x in bc:
			raw_c += int(x)
		_ok("⑨ ★分母: 暴击率各来源合计 %d%% > 100%%(否则这一组没测到溢出)" % raw_c, raw_c > 100, str(bc))
		_ok("⑨ ★暴击率封顶 100%(= 战斗面板)", vc != null and vc.text == "100%", vc.text if vc else "-")
		var sum_d := 0
		for x in bd:
			sum_d += int(x)
		_ok("⑨ ★暴击伤害括号多一段折算 = (合计 − 100%%) × %.1f, 各段加起来 = 总值" % DamageMath.CRIT_OVERFLOW,
			vd != null and bd.size() >= 2 and int(bd[bd.size() - 1]) == roundi((raw_c - 100) * DamageMath.CRIT_OVERFLOW)
			and "%d%%" % sum_d == vd.text, "%s = %s" % [vd.text if vd else "-", str(bd)])
		_ok("⑨ 溢出时有一行说明", card.find_child("CritOverNote", true, false) != null)
		for k in ["hp", "atk", "def", "mr", "crit", "critDmg"]:
			var vl: Label = card.find_child("Val_" + k, true, false) as Label
			_inv_vals[k] = vl.text if vl else "-"
	await _close(r[0])

	# ── ⑩ 背包小卡 == 对局信息面板(用户 2026-10-22「那对局内的么呢」)──
	##   同一只龟(等级 / 装备 / 战利品同 ⑨), 对局里走开局同一组函数把装备属性和战利品真加到单位上,
	##   再取信息面板那六格的字(info_panel._info_stat_tiles), 与背包小卡逐字比。
	await _check_battle_panel_matches(["blood_dice", "dagger", "flint", "poison", "crown"], "⑩")
	_ok("⑩ 反面: 没选财宝炮击时对局里没有贪婪", not _greed_on_battle)
	var no_greed := _inv_vals.duplicate()

	# ── ⑪ 选了财宝炮击 ⇒ 打包被动【贪婪】也算(用户 2026-10-22「有没有吃到贪婪被动啊」)──
	##   件数 = 身上装备 1 + 战利品 5 = 6 ⇒ 攻击 / 生命都该比 ⑩ 大; 与对局面板逐字相同。
	var gs = get_node("/root/GameState")
	var pool: Array = (DataRegistry.pet_by_id.get("chest", {}) as Dictionary).get("skillPool", [])
	var cannon := -1
	for i in range(pool.size()):
		if str((pool[i] as Dictionary).get("type", "")) == "chestCannon":
			cannon = i
	_ok("⑪ ★分母: 宝箱龟技能池里有财宝炮击", cannon >= 1, str(cannon))
	gs.loadouts["chest"] = cannon
	r = await _open_card(31000.0, ["blood_dice", "dagger", "flint", "poison", "crown"])
	card = r[1]
	if card != null:
		for k in ["hp", "atk", "def", "mr", "crit", "critDmg"]:
			var vl2: Label = card.find_child("Val_" + k, true, false) as Label
			_inv_vals[k] = vl2.text if vl2 else "-"
	await _close(r[0])
	_ok("⑪ ★选了财宝炮击 ⇒ 背包小卡的攻击力与最大生命值都变大(贪婪算进去了)",
		int(_inv_vals["atk"]) > int(no_greed["atk"]) and int(_inv_vals["hp"]) > int(no_greed["hp"]),
		"攻击 %s → %s · 生命 %s → %s" % [no_greed["atk"], _inv_vals["atk"], no_greed["hp"], _inv_vals["hp"]])
	await _check_battle_panel_matches(["blood_dice", "dagger", "flint", "poison", "crown"], "⑪")
	_ok("⑪ 对局里贪婪确实开了(分母)", _greed_on_battle)
	gs.loadouts.erase("chest")

	# ── ⑤ 别的龟 ──
	r = await _open_card(5000.0, ["rum"], "basic")
	card = r[1]
	_ok("⑤ ★分母: 小龟的属性小卡弹出", card != null)
	if card != null:
		_ok("⑤ 别的龟没有藏宝图", card.find_child("TreasureMap", true, false) == null and card.find_child("TreasureCount", true, false) == null)
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
	_ok("⑦ 空时正文为空(标题「战利品 0/5」已经说明, 不自编说明句)", cs.loot_detail_text({}) == "", cs.loot_detail_text({}))

	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少该有 %d) —— 有东西在半路被掐断了, 别当绿灯" % [_n, MIN_ASSERTS])
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 藏宝图栏 / 战利品浮层" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
