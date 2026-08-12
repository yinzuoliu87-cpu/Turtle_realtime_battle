extends Node
## verify_holy_shield_grant.gd — 盾羁绊赠送的【圣光护盾】装备（用户 2026-08-03 定）
##
## ★这条最容易出错的地方是"不占上限": 数装备件数的地方有好几处,
##   漏一处就出现"明明没满却装不上", 而玩家只会觉得"点了没反应"。
##
## 守五组：
##   ① 3 件盾送 1 个 / 6 件送 2 个 / <3 件不送
##   ② ★掉档【收回】—— 连装在龟身上的一起拿走(不然等于白嫖一件永久装备)
##   ③ ★不占全队容量, 也不占单只 3 件上限
##   ④ ★不进商店、不进私人池(shopAvailable=0)
##   ⑤ ★★它【没有类型】—— 给它"盾"就会「送盾→盾件数+1→档位涨→再送盾」无限循环
const EquipPoolS := preload("res://scripts/gamedata/equip_pool.gd")
const P2T := preload("res://scripts/gamedata/phase2_types.gd")
const Types := preload("res://scripts/gamedata/phase2_types.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const HOLY := "p2eq_095"

var _n := 0
var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null: print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 圣光护盾(羁绊赠送装备) ===")
	var SH := _shield_ids(9)
	_ok("★分母: 找到 %d 件盾类装备" % SH.size(), SH.size() >= 9)

	# ── ① 按【装在身上】的盾件数发放 ──
	#    ★2026-08-12 改: 原来这里把盾放 persistent_bench —— 那正是被修掉的错行为
	#    (买到 ≠ 装上; 见第 ⑧ 组)。计数域现在只认装上的, 所以这里也要真的装上。
	for cfg in [[0, 0], [2, 0], [3, 1], [5, 1], [6, 2], [9, 2]]:
		gs.start_new_season()
		gs.season_leaders = ["basic"]
		gs.persistent_equipped = {"basic": []}
		gs.persistent_bench = []
		for i in range(int(cfg[0])):
			(gs.persistent_equipped["basic"] as Array).append({"id": str(SH[i]), "star": 1})
		gs.sync_synergy_grants()
		_ok("① %d 件盾 → 送 %d 个圣光护盾" % [int(cfg[0]), int(cfg[1])],
			_count_holy(gs) == int(cfg[1]), "实得 %d" % _count_holy(gs))

	# ── ② 掉档收回(含装在龟身上的) ──
	gs.start_new_season()
	gs.season_leaders = ["basic"]
	gs.persistent_bench = []
	gs.persistent_equipped = {"basic": []}
	for i in range(3):
		(gs.persistent_equipped["basic"] as Array).append({"id": str(SH[i]), "star": 1})
	gs.sync_synergy_grants()
	# 把送的那件装到龟身上
	var gi := -1
	for i in range(gs.persistent_bench.size()):
		if str(gs.persistent_bench[i].get("id", "")) == HOLY: gi = i
	_ok("② 送的圣光护盾在背包里", gi >= 0)
	(gs.persistent_equipped["basic"] as Array).append(gs.persistent_bench[gi])
	gs.persistent_bench.remove_at(gi)
	_ok("② 装到龟身上后仍是 1 个", _count_holy(gs) == 1, "实得 %d" % _count_holy(gs))
	# 卸下一件【装在身上】的盾 → 只剩 2 件 → 掉档 → 应收回
	# ★2026-08-12 改: 原来这里删的是背包里的那件 —— 计数域已改成"只认装上的",
	#   删背包不再影响档位(这正是修好的行为), 所以要删身上的才叫掉档。
	for _i in range((gs.persistent_equipped["basic"] as Array).size() - 1, -1, -1):
		var _it = (gs.persistent_equipped["basic"] as Array)[_i]
		if not gs.is_synergy_grant(_it):
			(gs.persistent_equipped["basic"] as Array).remove_at(_i)
			break
	gs.sync_synergy_grants()
	_ok("② ★掉档后【装在龟身上的也被收回】", _count_holy(gs) == 0, "实得 %d" % _count_holy(gs))

	# ── ③ 不占容量 ──
	gs.start_new_season()
	gs.season_level = 3          # team_equip_cap = (3-1)*2 = 4
	gs.season_leaders = ["basic"]
	gs.persistent_equipped = {"basic": [
		{"id": str(SH[0]), "star": 1}, {"id": str(SH[1]), "star": 1}, {"id": HOLY, "star": 1}]}
	gs.persistent_bench = []
	_ok("③ ★全队计数跳过圣光护盾(装了 3 件但只算 2)",
		gs.team_equipped_count() == 2, "实得 %d" % gs.team_equipped_count())
	_ok("③ 全队上限 %d, 还装得下" % gs.team_equip_cap(), gs.team_has_equip_room())
	# 单只上限: _cap_count 跳过
	_ok("③ ★单只计数跳过圣光护盾(装了 3 件但只算 2 ⇒ 还能再装 1 件)",
		gs._cap_count(gs.persistent_equipped["basic"]) == 2,
		"实得 %d" % gs._cap_count(gs.persistent_equipped["basic"]))

	# ── ④ 不进商店/私人池 ──
	var in_shop := false
	for e in DataRegistry.phase2_equipment:
		if str((e as Dictionary).get("id", "")) == HOLY:
			in_shop = int((e as Dictionary).get("shopAvailable", 0)) == 1
	_ok("④ ★shopAvailable = 0(不上商店)", not in_shop)
	var pool: Dictionary = EquipPoolS.full_pool(DataRegistry.phase2_equipment)
	_ok("④ ★不在私人池里(池只收 shopAvailable==1)", not pool.has(HOLY))

	# ── ⑤ 没有类型(防无限循环) ──
	_ok("⑤ ★★圣光护盾【没有类型】—— 给它「盾」就会 送盾→盾数+1→档位涨→再送盾 无限循环",
		P2T.type_of(HOLY) == "", "实得类型「%s」" % P2T.type_of(HOLY))

	# ⑥ ★★不能卖(2026-08-12 用户问「背包里这个圣光护盾确定完全没问题了吗」⇒ 逐条路径查)
	#    实测过的现状: 卖它得 0 币、私人池不受影响、但会被 sync 立刻补发回来 ——
	#    玩家看到"点了卖→闪一下又回来→一分钱没有", 是 bug 观感。⇒ 卖出路径直接拦截。
	var src := FileAccess.get_file_as_string("res://scripts/scenes/inventory/equip_ops.gd")
	var sell_i: int = src.find("func _sell_selected")
	var seg: String = src.substr(sell_i, 700) if sell_i >= 0 else ""
	_ok("⑥ ★卖出路径里有羁绊赠送件的拦截(is_synergy_grant 早退)",
		sell_i >= 0 and seg.contains("is_synergy_grant") and seg.contains("return"),
		"片段长度 %d" % seg.length())
	_ok("⑥ ★分母: 拦截写在【加币之前】(写在后面等于先给钱再拦)",
		sell_i >= 0 and seg.find("is_synergy_grant") < seg.find("meta_deepsea_coins +="),
		"grant@%d coins@%d" % [seg.find("is_synergy_grant"), seg.find("meta_deepsea_coins +=")])
	# ⑦ ★合成: 最多只会同时存在 2 个(档3 送 2) ⇒ 永远凑不满 3 件 ⇒ 不会被三合一吃掉
	var max_grant := 0
	for n in [3, 6, 9]:
		gs.persistent_equipped = {"p": []}
		gs.persistent_bench = []
		for i in range(n):
			gs.persistent_equipped["p"].append({"id": str(SH[i]), "star": 1})
		gs.season_leaders = ["p"]
		gs.sync_synergy_grants()
		max_grant = maxi(max_grant, _count_holy(gs))
	_ok("⑦ ★最多同时 %d 个(<3) ⇒ 三合一永远凑不齐, 不会被合掉" % max_grant, max_grant < 3,
		"max=%d" % max_grant)

	# ⑧ ★★【买到 ≠ 装上】: 盾只躺在背包里不算数(2026-08-12 用户:
	#    「不是只有装备3盾才触发羁绊吗」「购买了和装备了不是两码事吗」)
	#    由来(实测确诊): shield_grant_count 原来把 persistent_bench 也算进计数域,
	#    而羁绊档位(Phase2Types.calc_active)只数【装在身上的】⇒ 3 件盾躺背包、档位 0,
	#    却白送 1 件圣光护盾(+250 生命 + 每 3 秒 55 圣盾)。两个计数域必须一致。
	gs.season_leaders = ["A"]
	gs.persistent_equipped = {"A": []}
	gs.dual_lineup = {}
	gs.persistent_bench = []
	for i in range(3):
		gs.persistent_bench.append({"id": str(SH[i]), "star": 1})
	gs.sync_synergy_grants()
	_ok("⑧ ★★3 件盾【只在背包】⇒ 一个圣光护盾都不送(买到 ≠ 装上)",
		_count_holy(gs) == 0 and gs.shield_grant_count() == 0,
		"送了 %d 个 · grant_count=%d" % [_count_holy(gs), gs.shield_grant_count()])
	## 与羁绊档位口径一致: 这时候档位也必须是 0
	var act0: Array = Types.calc_active([{"_p2_equips": gs.team_p2_equips_for_synergy()}])
	var tier0 := 0
	for a in act0:
		if str((a as Dictionary).get("type", "")) == "盾":
			tier0 = int((a as Dictionary).get("tier", 0))
	_ok("⑧ ★分母: 此时羁绊档位也是 0(两边同口径 —— 这正是要焊住的那件事)", tier0 == 0,
		"档%d" % tier0)
	## 装上之后两边【同时】变
	gs.persistent_bench = []
	for i in range(3):
		gs.persistent_equipped["A"].append({"id": str(SH[i]), "star": 1})
	gs.sync_synergy_grants()
	var act1: Array = Types.calc_active([{"_p2_equips": gs.team_p2_equips_for_synergy()}])
	var tier1 := 0
	for a in act1:
		if str((a as Dictionary).get("type", "")) == "盾":
			tier1 = int((a as Dictionary).get("tier", 0))
	_ok("⑧ 装到龟身上后: 档%d 且送出 %d 个 —— 两边同时成立" % [tier1, _count_holy(gs)],
		tier1 >= 1 and _count_holy(gs) == 1, "")

	# ⑨ ★一只龟身上放【两个】圣盾(用户点名的情形)
	gs.persistent_equipped = {"A": [], "B": []}
	gs.season_leaders = ["A", "B"]
	gs.persistent_bench = []
	for i in range(6):
		gs.persistent_equipped["A"].append({"id": str(SH[i]), "star": 1})
	gs.sync_synergy_grants()
	_ok("⑨ ★分母: 6 件盾 → 送 2 个", _count_holy(gs) == 2, "实得 %d" % _count_holy(gs))
	for i in range(gs.persistent_bench.size() - 1, -1, -1):
		if gs.is_synergy_grant(gs.persistent_bench[i]):
			(gs.persistent_equipped["B"] as Array).append(gs.persistent_bench[i])
			gs.persistent_bench.remove_at(i)
	var bb: Array = gs.persistent_equipped["B"]
	_ok("⑨ 两个圣盾装到同一只身上: 身上 %d 件而占位仍是 %d" % [bb.size(), gs._cap_count(bb)],
		bb.size() == 2 and gs._cap_count(bb) == 0, "")
	## 这只还能再装满 3 件真装备(共 5 件) —— 圣盾一格都不占
	var others: Array = []
	for e2 in DataRegistry.phase2_equipment:
		var oid := str((e2 as Dictionary).get("id", ""))
		if oid != HOLY and Types.type_of(oid) != "盾" and others.size() < 3:
			others.append(oid)
	for oid2 in others:
		if gs._cap_count(bb) < P2C.UNIT_EQUIP_CAP:
			bb.append({"id": str(oid2), "star": 1})
	_ok("⑨ 还能再装满 3 件真装备 ⇒ 身上共 %d 件、占位 %d" % [bb.size(), gs._cap_count(bb)],
		bb.size() == 5 and gs._cap_count(bb) == 3, "")
	## ★UI: 装备格【恒定 3 格】, 圣盾画成三格之后的"赠"徽章(不是第 4/5 个格子)
	var inv_src := FileAccess.get_file_as_string("res://scripts/scenes/InventoryScene.gd")
	_ok("⑨ ★UI: 三格恒定(调用处传的是 UNIT_EQUIP_CAP, 不是 cap+N)",
		inv_src.contains("_build_equip_cells(box, 60.0, eqs, P2.UNIT_EQUIP_CAP,"),
		"")
	_ok("⑨ ★UI: 赠送件另画徽章(金边+金角标)且能画 N 个, 画在三格【下面一行】不溢出卡片",
		inv_src.contains("for gi in range(grants.size())") and inv_src.contains("corner.color = Color(\"#ffd93d\")")
		and inv_src.contains("y + cw + 4.0"), "")

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 圣光护盾赠送" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

func _shield_ids(n: int) -> Array:
	var out: Array = []
	for e in DataRegistry.phase2_equipment:
		if P2T.type_of(str((e as Dictionary).get("id", ""))) == "盾":
			out.append(str((e as Dictionary).get("id", "")))
		if out.size() >= n: break
	return out

func _count_holy(gs) -> int:
	var n := 0
	for it in gs.persistent_bench:
		if it is Dictionary and str(it.get("id", "")) == HOLY: n += 1
	for pid in gs.persistent_equipped.keys():
		for it2 in gs.persistent_equipped[pid]:
			if it2 is Dictionary and str(it2.get("id", "")) == HOLY: n += 1
	return n
