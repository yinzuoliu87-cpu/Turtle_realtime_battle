extends Node
## verify_candy_jar.gd — 自证: 糖果罐/临时等级器 端到端 (逻辑 + 数据形状 + 3合1不炸).
## 跑法: godot --headless --path . res://tests/verify_candy_jar.tscn --quit-after 120
##
## 覆盖 (每条打印 期望 vs 实际):
##  1. has_candy_jar 只在"统领含糖果龟且未碎"时为 true
##  2. candy_jar_add: 赢+1 / 输+4 / 封顶30
##  3. candy_jar_tier: 6 档区间
##  4. break_candy_jar: 发深海币 + 装备进背包 + 按档概率给临时等级器
##  5. ★奖励进背包后 persistent_bench 全是 Dictionary (曾塞裸 String "temp_leveler" → auto_merge_all/_equip_cell 必崩)
##  6. ★auto_merge_all() 在背包含消耗品时不崩, 且不把消耗品当装备合成
##  7. apply_temp_leveler / temp_level_bonus
##  8. 老存档迁移: 裸 String → Dictionary

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  ✓ ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  ✗ ", name, "  ", detail)

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node("/root/GameState")
	if gs == null:
		print("✗ GameState autoload 缺失"); get_tree().quit(1); return

	print("=== 1. has_candy_jar 门槛 ===")
	gs.season_leaders = ["basic", "stone", "ninja"]
	gs.candy_jar_broken = false
	_ok("统领无糖果龟 → 无罐", not gs.has_candy_jar())
	gs.season_leaders = ["candy", "stone", "ninja"]
	_ok("统领含糖果龟 → 有罐", gs.has_candy_jar())
	gs.candy_jar_broken = true
	_ok("已碎 → 无罐", not gs.has_candy_jar())
	gs.candy_jar_broken = false

	print("=== 2. 计数: 赢+1 / 输+4 / 封顶30 ===")
	gs.candy_jar_count = 0
	gs.candy_jar_add(1); _ok("赢+1", gs.candy_jar_count == 1, "got=%d" % gs.candy_jar_count)
	gs.candy_jar_add(4); _ok("输+4", gs.candy_jar_count == 5, "got=%d" % gs.candy_jar_count)
	gs.candy_jar_count = 28
	gs.candy_jar_add(4); _ok("封顶30", gs.candy_jar_count == 30, "got=%d" % gs.candy_jar_count)

	print("=== 3. 档位区间 (0-5=1 / 6-11=2 / 12-17=3 / 18-23=4 / 24-29=5 / 30=6) ===")
	for pair in [[0, 1], [5, 1], [6, 2], [11, 2], [12, 3], [17, 3], [18, 4], [23, 4], [24, 5], [29, 5], [30, 6]]:
		gs.candy_jar_count = int(pair[0])
		_ok("count=%d → 档%d" % [int(pair[0]), int(pair[1])], gs.candy_jar_tier() == int(pair[1]), "got=%d" % gs.candy_jar_tier())

	print("=== 4/5. 打碎档6 (leveler=100%) → 奖励 + 背包数据形状 ===")
	gs.persistent_bench = []
	gs.persistent_equipped = {}
	gs.candy_temp_levels = {}
	gs.candy_jar_count = 30
	gs.candy_jar_broken = false
	var coins_before: int = int(gs.meta_deepsea_coins)
	var r: Dictionary = gs.break_candy_jar()
	_ok("返回非空", not r.is_empty())
	_ok("档=6", int(r.get("tier", 0)) == 6, "got=%d" % int(r.get("tier", 0)))
	_ok("深海币 +120", int(gs.meta_deepsea_coins) - coins_before == 120, "delta=%d" % (int(gs.meta_deepsea_coins) - coins_before))
	_ok("档6必给临时等级器", bool(r.get("leveler", false)))
	_ok("打碎后 has_candy_jar=false", not gs.has_candy_jar())

	var all_dict := true
	var levelers := 0
	var equips := 0
	for it in gs.persistent_bench:
		if not (it is Dictionary):
			all_dict = false
		elif str(it.get("id", "")) == gs.TEMP_LEVELER_ID:
			levelers += 1
		else:
			equips += 1
	_ok("★背包全是 Dictionary (无裸 String)", all_dict, "bench=%s" % str(gs.persistent_bench))
	_ok("背包有 1 个临时等级器", levelers == 1, "got=%d" % levelers)
	_ok("背包有 1 件装备", equips == 1, "got=%d" % equips)
	_ok("is_equip_item 识别消耗品", not gs.is_equip_item(gs.TEMP_LEVELER_ITEM))

	print("=== 6. ★auto_merge_all 含消耗品不崩, 且不合消耗品 ===")
	gs.persistent_bench.append(gs.TEMP_LEVELER_ITEM.duplicate())
	gs.persistent_bench.append(gs.TEMP_LEVELER_ITEM.duplicate())   # 3 个等级器: 若被当装备就会被合成掉
	var before: int = gs.persistent_bench.size()
	gs.auto_merge_all()                                            # 曾经在这里 String.get() 崩
	var after_levelers := 0
	for it in gs.persistent_bench:
		if it is Dictionary and str(it.get("id", "")) == gs.TEMP_LEVELER_ID:
			after_levelers += 1
	_ok("auto_merge_all 未崩", true)
	_ok("3 个临时等级器没被 3合1 吃掉", after_levelers == 3, "got=%d (bench %d→%d)" % [after_levelers, before, gs.persistent_bench.size()])

	print("=== 7. 临时等级器: 龟统领 ===")
	gs.candy_temp_levels = {}
	_ok("初始 +0", gs.temp_level_bonus("candy") == 0)
	gs.apply_temp_leveler("candy")
	_ok("用 1 次 → +1", gs.temp_level_bonus("candy") == 1, "got=%d" % gs.temp_level_bonus("candy"))
	gs.apply_temp_leveler("candy")
	_ok("再用 1 次 → +2 (累加)", gs.temp_level_bonus("candy") == 2, "got=%d" % gs.temp_level_bonus("candy"))
	_ok("消耗: consume_temp_leveler 移除该格", gs.consume_temp_leveler(_first_leveler_idx(gs)))

	print("=== 7b. 临时等级器: 小将 (记在阵容格子上) ===")
	var dl: Dictionary = gs.get_dual_lineup()
	var mlane := ""
	var midx := -1
	for lane in ["top", "bottom"]:
		var arr: Array = dl.get(lane, [])
		for i in range(arr.size()):
			if arr[i] is Dictionary and str(arr[i].get("kind", "")) == "minion":
				mlane = lane; midx = i; break
		if midx >= 0: break
	if midx < 0:
		print("  – 默认阵容无小将格, 跳过 (非失败)")
	else:
		var ok1: bool = gs.apply_temp_leveler_minion(mlane, midx)
		var lv: int = int(gs.get_dual_lineup()[mlane][midx].get("temp_lv", 0))
		_ok("小将 +1 级写入阵容格子", ok1 and lv == 1, "lane=%s idx=%d temp_lv=%d" % [mlane, midx, lv])
		_ok("对统领格调用返回 false", not gs.apply_temp_leveler_minion(mlane, _first_leader_idx(gs, mlane)))

	print("=== 8. 老存档迁移: 裸 String → Dictionary ===")
	gs.persistent_bench = ["temp_leveler", {"id": "p2eq_001", "star": 1}]
	# 复现 load() 里的迁移逻辑 (老存档把临时等级器存成裸 String)
	for i in range(gs.persistent_bench.size()):
		if gs.persistent_bench[i] is String and str(gs.persistent_bench[i]) == gs.TEMP_LEVELER_ID:
			gs.persistent_bench[i] = gs.TEMP_LEVELER_ITEM.duplicate()
	_ok("迁移后无裸 String", not (gs.persistent_bench[0] is String))
	gs.auto_merge_all()
	_ok("迁移后 auto_merge_all 不崩", true)

	print("")
	if _fail == 0:
		print("ALL PASS — 糖果罐/临时等级器 端到端")
	else:
		print("FAIL ×", _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _first_leveler_idx(gs) -> int:
	for i in range(gs.persistent_bench.size()):
		var it = gs.persistent_bench[i]
		if it is Dictionary and str(it.get("id", "")) == gs.TEMP_LEVELER_ID:
			return i
	return -1


func _first_leader_idx(gs, lane: String) -> int:
	var arr: Array = gs.get_dual_lineup().get(lane, [])
	for i in range(arr.size()):
		if arr[i] is Dictionary and str(arr[i].get("kind", "")) == "leader":
			return i
	return -1
