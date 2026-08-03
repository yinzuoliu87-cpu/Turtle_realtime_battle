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

	# ── ① 按盾件数发放 ──
	for cfg in [[0, 0], [2, 0], [3, 1], [5, 1], [6, 2], [9, 2]]:
		gs.start_new_season()
		gs.season_leaders = ["basic"]
		gs.persistent_equipped = {"basic": []}
		gs.persistent_bench = []
		for i in range(int(cfg[0])):
			gs.persistent_bench.append({"id": str(SH[i]), "star": 1})
		gs.sync_synergy_grants()
		_ok("① %d 件盾 → 送 %d 个圣光护盾" % [int(cfg[0]), int(cfg[1])],
			_count_holy(gs) == int(cfg[1]), "实得 %d" % _count_holy(gs))

	# ── ② 掉档收回(含装在龟身上的) ──
	gs.start_new_season()
	gs.season_leaders = ["basic"]
	gs.persistent_bench = []
	for i in range(3):
		gs.persistent_bench.append({"id": str(SH[i]), "star": 1})
	gs.sync_synergy_grants()
	# 把送的那件装到龟身上
	var gi := -1
	for i in range(gs.persistent_bench.size()):
		if str(gs.persistent_bench[i].get("id", "")) == HOLY: gi = i
	_ok("② 送的圣光护盾在背包里", gi >= 0)
	gs.persistent_equipped = {"basic": [gs.persistent_bench[gi]]}
	gs.persistent_bench.remove_at(gi)
	_ok("② 装到龟身上后仍是 1 个", _count_holy(gs) == 1, "实得 %d" % _count_holy(gs))
	# 卖掉一件盾 → 只剩 2 件 → 掉档 → 应收回
	gs.persistent_bench.remove_at(0)
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
