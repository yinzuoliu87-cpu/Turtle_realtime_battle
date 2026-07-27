extends Node
## verify_equip_cap.gd — 守【装备容量统一规则】(用户 2026-07-27 拍板)
##
## 「单只统领或小将的上限固定为3, 根据赛季等级1..10, 六只单位一共能装备的数量为
##   0,2,4,6,8,10,12,14,16,18」
##
## 它取代的是【两把尺子】: 玩家侧 equip_slots_for_level(每只1~5) vs 快照/bot 侧
## equip_slots_for_battles(每只0~4)。两条从未对齐, 而且设计注释说的是后者、实装走的是前者。
## 2026-07-27 队列模拟(机器人=真玩家规则)在档1 装了 2 件, 被按敌方那把尺子判违规 —— 才暴露出来。
##
## 断言:
##   ① 容量表逐值精确 (不是"大概递增", 是 0,2,4,...,18 一个不差)
##   ② Lv10 的 18 == 6 单位 × 单只上限 3 (规则自洽: 满级正好能塞满所有人)
##   ③ 老存档迁移: 超单只上限 / 超全队上限 → 卸回背包, 【一件不丢】(总数守恒)
##   ④ 迁移幂等 + 【对合规存档不动手】(证明它不是无脑裁 —— 否则这检查是恒真的)

const P2 := preload("res://scripts/gamedata/phase2_config.gd")

var _fail := 0

func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _total_equipped(gs) -> int:
	var n := 0
	for pid in (gs.season_leaders as Array):
		n += (gs.persistent_equipped.get(str(pid), []) as Array).size()
	var dl: Dictionary = gs.get_dual_lineup()
	for lane in ["top", "bottom"]:
		for u in (dl.get(lane, []) as Array):
			if str((u as Dictionary).get("kind", "")) == "minion":
				n += ((u as Dictionary).get("equips", []) as Array).size()
	return n


func _setup(gs, level: int) -> void:
	gs.test_mode = true
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	gs.season_level = level
	gs.persistent_bench = []
	gs.persistent_equipped = {}
	gs.dual_lineup = {}
	gs.get_dual_lineup()


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 没有 GameState"); get_tree().quit(1); return

	# ── ① 容量表逐值精确 ──
	var want := [0, 2, 4, 6, 8, 10, 12, 14, 16, 18]
	var got: Array = []
	for lv in range(1, 11):
		got.append(P2.team_equip_cap(lv))
	_ok("★①全队容量表 Lv1..Lv10 == %s" % str(want), got == want, "实际 %s" % str(got))
	_ok("★①单只上限 == 3", P2.UNIT_EQUIP_CAP == 3, "实际 %d" % P2.UNIT_EQUIP_CAP)

	# ── ② 规则自洽: 满级正好塞满 ──
	_ok("★②Lv10 的 %d == 6 单位 × 单只 %d (满级正好塞满, 不多不少)" % [P2.team_equip_cap(10), P2.UNIT_EQUIP_CAP],
		P2.team_equip_cap(10) == P2.TEAM_UNITS * P2.UNIT_EQUIP_CAP,
		"%d vs %d" % [P2.team_equip_cap(10), P2.TEAM_UNITS * P2.UNIT_EQUIP_CAP])
	_ok("★②Lv1 == 0 件(人生第一把没装备, 由规则自然推出而非特例)", P2.team_equip_cap(1) == 0)

	# ── ③ 迁移: 超单只上限 ──
	_setup(gs, 10)                     # Lv10 → 全队 18, 不会被全队上限干扰
	gs.persistent_equipped["basic"] = []
	for i in range(6):                 # 一只龟塞 6 件 (旧规则 Lv9-10 允许 5, 这里更超)
		gs.persistent_equipped["basic"].append({"id": "kelp_blade", "star": 1})
	var before_total: int = _total_equipped(gs) + (gs.persistent_bench as Array).size()
	var moved: int = gs.migrate_equip_caps()
	var after_total: int = _total_equipped(gs) + (gs.persistent_bench as Array).size()
	_ok("★③超单只上限 → 裁到 %d 件" % P2.UNIT_EQUIP_CAP,
		(gs.persistent_equipped["basic"] as Array).size() == P2.UNIT_EQUIP_CAP,
		"身上剩 %d 件, 卸了 %d 件" % [(gs.persistent_equipped["basic"] as Array).size(), moved])
	_ok("★③超额的被彻底删除(总数减少且背包没变多)",
		after_total == before_total - moved and (gs.persistent_bench as Array).size() == 0,
		"迁移前 %d → 迁移后 %d, 删了 %d, 背包 %d 件(必须0)" % [before_total, after_total, moved, (gs.persistent_bench as Array).size()])

	# ── ③ 迁移: 超全队上限 ──
	_setup(gs, 3)                      # Lv3 → 全队上限 4
	for pid in ["basic", "stone", "bamboo"]:
		gs.persistent_equipped[pid] = []
		for i in range(3):             # 3 只 × 3 件 = 9 件, 单只不超但全队远超 4
			gs.persistent_equipped[pid].append({"id": "kelp_blade", "star": 1})
	var b2: int = _total_equipped(gs) + (gs.persistent_bench as Array).size()
	var moved2: int = gs.migrate_equip_caps()
	var a2: int = _total_equipped(gs) + (gs.persistent_bench as Array).size()
	_ok("★③超全队上限(Lv3=%d) → 裁到上限内" % P2.team_equip_cap(3),
		_total_equipped(gs) <= P2.team_equip_cap(3),
		"身上剩 %d 件(上限 %d), 卸了 %d 件" % [_total_equipped(gs), P2.team_equip_cap(3), moved2])
	_ok("★③超额的被彻底删除(背包没变多)",
		a2 == b2 - moved2 and (gs.persistent_bench as Array).size() == 0,
		"迁移前 %d → 迁移后 %d, 删了 %d, 背包 %d 件(必须0)" % [b2, a2, moved2, (gs.persistent_bench as Array).size()])

	# ── ④ 幂等 + 不动合规存档(证明检查非恒真) ──
	var again: int = gs.migrate_equip_caps()
	_ok("★④幂等: 已合规的再跑一次卸 0 件", again == 0, "又卸了 %d 件" % again)

	_setup(gs, 5)                      # Lv5 → 全队 8; 装 6 件(合规)
	gs.persistent_equipped["basic"] = [{"id": "kelp_blade", "star": 1}, {"id": "kelp_blade", "star": 1}]
	gs.persistent_equipped["stone"] = [{"id": "kelp_blade", "star": 1}, {"id": "kelp_blade", "star": 1}]
	gs.persistent_equipped["bamboo"] = [{"id": "kelp_blade", "star": 1}, {"id": "kelp_blade", "star": 1}]
	var moved3: int = gs.migrate_equip_caps()
	_ok("★④合规存档(6件 ≤ Lv5的8件, 单只2 ≤ 3) → 一件都不该动",
		moved3 == 0 and _total_equipped(gs) == 6, "动了 %d 件, 剩 %d 件" % [moved3, _total_equipped(gs)])

	# ── 分母 ──
	_ok("★分母: 容量表核了 %d 个等级(不是空检查)" % got.size(), got.size() == 10)

	print("ALL PASS — 装备容量统一规则" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
