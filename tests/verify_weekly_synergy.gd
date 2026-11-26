extends Node
## verify_weekly_synergy.gd —— 本周羁绊 16 抽 10 + 商店池版本(方案书 docs/plans/20261124d-16羁绊每周轮换.md §6)
##   A 104 周: 每周恰好 10 个、互不重复、都在 16 个之内; 与独立 Python 实现(tools/weekly_synergy_gold.py)的金标逐周相同
##   B 周锚点 ≤ 0(演示台 / 门禁)⇒ 16 个全在
##   C 池版本 1(老流水没有 pv)只出 001~096; 版本 2 按本周羁绊; 小木斧这类非大羁绊件永远能出
##   D 真掷货(EconLedger._roll)200 次: 版本 2 的货 100% 在本周池; 版本 1 的货 100% ≤ 096
##   E 经济流水 do() 每条都记 pv = 当前版本
##   F 对局池版本 == 经济池版本 · G 宝箱龟开箱 200 次 100% 在本周池 · H 魔法海螺也挂了过滤
const EL := preload("res://scripts/gamedata/econ_ledger.gd")
const WS := preload("res://scripts/gamedata/weekly_synergy.gd")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")

var _n := 0
var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _uniq(a: Array) -> bool:
	var d := {}
	for x in a:
		d[x] = true
	return d.size() == a.size()


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	print("=== 本周羁绊 16 抽 10 ===")
	var gold = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/weekly_synergy.json"))
	var weeks := 0
	var bad: Array = []
	for k in (gold as Dictionary).keys():
		weeks += 1
		var got: Array = WS.of_week(int(k))
		var uniq := {}
		for t in got:
			uniq[t] = true
		var all_in := true
		for t in got:
			if not WS.ALL.has(str(t)):
				all_in = false
		if got.size() != 10 or uniq.size() != 10 or not all_in or got != (gold[k] as Array):
			bad.append(k)
	_ok("A %d 周: 每周 10 个不重复、都在 16 个里、与 Python 金标逐周相同" % weeks, weeks == 104 and bad.is_empty(), "不对的周 %s" % str(bad.slice(0, 3)))
	var seen := {}
	for k in (gold as Dictionary).keys():
		for t in WS.of_week(int(k)):
			seen[t] = true
	_ok("A 104 周里 16 个羁绊都轮到过(纯随机不会有永远抽不到的)", seen.size() == 16, str(seen.size()))
	_ok("B 周锚点 0 ⇒ 16 个全在", WS.of_week(0).size() == 16)
	var lw: Array = WS.of_week(WS.LAUNCH_WEEK)
	var lw_new := 0
	for t in WS.LAUNCH_NEW:
		if lw.has(t):
			lw_new += 1
	var nx: Array = WS.of_week(WS.LAUNCH_WEEK + 7 * 86400)
	_ok("B2 上线周(11-30)保底: 6 个新羁绊全在 + 共 10 个不重复(%s) · 下一周照常纯随机" % "、".join(lw),
		lw_new == 6 and lw.size() == 10 and _uniq(lw) and nx.size() == 10)

	var wk := int((gold as Dictionary).keys()[1])   # 第二周(第一周是上线保底周, 6 个新羁绊全在 ⇒ 量不出「本周池外的新件」)
	var in_week: Array = WS.of_week(wk)
	var out_t := ""
	for t in WS.ALL:
		if not in_week.has(t):
			out_t = t
			break
	var out_item := ""
	var in_item := ""
	for e in DataRegistry.phase2_equipment:
		var id := str(e.get("id", ""))
		var ty: Array = Phase2Types.types_of(id)
		if out_item == "" and ty.size() == 1 and str(ty[0]) == out_t:
			out_item = id
		if in_item == "" and ty.size() == 1 and in_week.has(str(ty[0])) and int(id.trim_prefix("p2eq_")) > 96:
			in_item = id
	_ok("C 版本 2: 本周不在的羁绊(%s)的件 %s 不出 · 本周在的新件 %s 出 · 小木斧永远出" % [out_t, out_item, in_item],
		not WS.pool_ok(out_item, wk, 2) and WS.pool_ok(in_item, wk, 2) and WS.pool_ok("p2eq_096", wk, 2))
	_ok("C 版本 1: 001~096 照出(不轮换), 097 起一件不出", WS.pool_ok(out_item, wk, 1) == (int(out_item.trim_prefix("p2eq_")) <= 96) and not WS.pool_ok(in_item, wk, 1)
		and WS.pool_ok("p2eq_001", wk, 1))

	## D 真掷货
	var bk := {"wk": gs.week_anchor_ts, "offer": (gs.meta_shop_offer as Array).duplicate(true), "pool": (gs.equip_pool as Dictionary).duplicate(true),
		"bt": gs.meta_shop_battles, "lv": gs.season_level}
	gs.week_anchor_ts = wk
	gs.season_level = 10
	var bad2 := 0
	var bad1 := 0
	var n2 := 0
	var n1 := 0
	for i in range(200):
		gs.meta_shop_offer = []
		EL.apply(gs, {"op": "roll", "seed": 1000 + i, "pv": 2})
		for it in gs.meta_shop_offer:
			if it is Dictionary:
				n2 += 1
				if not WS.pool_ok(str(it["id"]), wk, 2):
					bad2 += 1
		gs.meta_shop_offer = []
		EL.apply(gs, {"op": "roll", "seed": 5000 + i})
		for it in gs.meta_shop_offer:
			if it is Dictionary:
				n1 += 1
				if int(str(it["id"]).trim_prefix("p2eq_")) > 96:
					bad1 += 1
	_ok("D 掷货 200 次: 版本 2 的 %d 件全在本周池 · 版本 1(无 pv)的 %d 件全 ≤ 096" % [n2, n1], n2 > 1000 and n1 > 1000 and bad2 == 0 and bad1 == 0,
		"越界 %d / %d" % [bad2, bad1])

	## E do() 记 pv
	var led0: int = (gs.econ_log as Array).size()
	gs.meta_shop_offer = []
	EL.do(gs, {"op": "roll", "seed": 7})
	var row = (gs.econ_log as Array).back() if (gs.econ_log as Array).size() > led0 else {}
	_ok("E 经济流水每条都记池版本 pv = %d" % EL.POOL_VER, row is Dictionary and int((row as Dictionary).get("pv", 0)) == EL.POOL_VER, str(row))
	## F 对局里随机给装备用的池版本 == 经济记账的池版本(两边各写了一个常量)
	_ok("F 对局池版本 BATTLE_PV(%d) == EconLedger.POOL_VER(%d)" % [WS.BATTLE_PV, EL.POOL_VER], WS.BATTLE_PV == EL.POOL_VER)
	## G 宝箱龟开箱真抽 200 次(替身战斗对象只给 pool_week / _battle_rng): 100% 在本周池; 周锚点 0 ⇒ 16 个全在、新件也出
	var src := GDScript.new()
	src.source_code = "extends RefCounted\nvar _battle_rng := RandomNumberGenerator.new()\nvar wk := 0\nfunc pool_week() -> int:\n\treturn wk\n"
	src.reload()
	var fb = src.new()
	fb._battle_rng.seed = 4242
	fb.wk = wk
	var chest := ChestSystem.new(fb)
	var cbad := 0
	var cn := 0
	for i in range(200):
		var eid: String = chest._chest_pick_equip([1, 2, 3, 4, 5])
		if eid != "":
			cn += 1
			if not WS.pool_ok(eid, wk, 2):
				cbad += 1
	fb.wk = 0
	var c0_new := 0
	for i in range(200):
		var eid0: String = chest._chest_pick_equip([1, 2, 3, 4, 5])
		if int(eid0.trim_prefix("p2eq_")) > 96 and not WS.pool_ok(eid0, wk, 2):
			c0_new += 1
	_ok("G 宝箱龟开箱 200 次: %d 件全在本周池(越界 %d) · 周锚点 0 时本周池外的件也出(%d 次)" % [cn, cbad, c0_new], cn == 200 and cbad == 0 and c0_new > 0)
	## H 魔法海螺小虫的 3 件随机装备也挂了同一个过滤(静态核: 产品代码里那一段真的调了 battle_ok)
	var eqsrc := FileAccess.get_file_as_string("res://scripts/systems/equip/equip_system.gd")
	var ci := eqsrc.find("func _conch_grant_equips")
	var cj := eqsrc.find("\nfunc ", ci + 10)
	_ok("H 魔法海螺小虫的随机装备也只出本周池(源码里挂了 WeeklySynergy.battle_ok)", ci > 0 and eqsrc.substr(ci, cj - ci).contains("WeeklySynergy.battle_ok("))
	## I 图鉴「本周不出」压暗(11-27): 判据与掷货同一个 pool_ok · 羁绊赠送(费用 0)不标 · 羁绊页只标 16 个轮换的
	var i_bad: Array = []
	var i_off := 0
	var i_on := 0
	for e in DataRegistry.phase2_equipment:
		var eid := str(e.get("id", ""))
		var want: bool = int(e.get("cost", 0)) > 0 and not WS.pool_ok(eid, wk, WS.BATTLE_PV)
		if CodexList.off_week_eq(e) != want:
			i_bad.append(eid)
		if want:
			i_off += 1
		elif int(e.get("cost", 0)) > 0:
			i_on += 1
	var syn_bad: Array = []
	for t in WS.ALL:
		if CodexList.off_week_syn(str(t)) == in_week.has(t):
			syn_bad.append(t)
	_ok("I 图鉴装备页: 压暗 %d 件 / 照常 %d 件, 与掷货判据逐件一致 · 羁绊页 16 个逐个一致 · 不轮换的类型不标" % [i_off, i_on],
		i_bad.is_empty() and syn_bad.is_empty() and i_off > 0 and i_on > 0 and not CodexList.off_week_syn("小木斧"), "%s %s" % [str(i_bad.slice(0, 5)), str(syn_bad)])
	## J 商店顶栏「本周羁绊」木牌: 图标恰好是本周那 10 个(按顺序) · 周锚点 0(演示 / 冷启动)⇒ 不挂
	var bt0: int = int(gs.season_total_battles)
	gs.season_total_battles = maxi(1, bt0)
	var shop = load("res://scenes/Shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	await get_tree().process_frame
	var icons: Array = []
	for n in shop.find_children("WeekSyn_*", "TextureRect", true, false):
		icons.append(str(n.name).trim_prefix("WeekSyn_"))
	var plq_n: int = shop.find_children("WeekSynPlaque", "", true, false).size()
	shop.queue_free()
	gs.week_anchor_ts = 0
	var shop0 = load("res://scenes/Shop.tscn").instantiate()
	add_child(shop0)
	await get_tree().process_frame
	var plq0: int = shop0.find_children("WeekSynPlaque", "", true, false).size()
	shop0.queue_free()
	gs.season_total_battles = bt0
	_ok("J 商店木牌: 图标 %d 个 = 本周 %d 个且同序 · 周锚点 0 不挂(%d)" % [icons.size(), in_week.size(), plq0],
		plq_n == 1 and icons == in_week and plq0 == 0, "%s vs %s" % [str(icons), str(in_week)])
	gs.week_anchor_ts = bk["wk"]
	gs.meta_shop_offer = bk["offer"]
	gs.equip_pool = bk["pool"]
	gs.meta_shop_battles = bk["bt"]
	gs.season_level = bk["lv"]

	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 本周羁绊 (%d 条)" % _n)
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
