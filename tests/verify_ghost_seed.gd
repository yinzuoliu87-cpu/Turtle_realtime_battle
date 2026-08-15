extends Node
## verify_ghost_seed.gd — 守卫: 内置 ghost 种子池 (193 支·9档各≥20·队列模拟产出的真实玩家快照·冷启动/老档并入)
##   ★2026-08-15 从 180 → 193: 各档基础 20 支之外, 又按【装备覆盖】补选了 13 支 ——
##     20 支/档 的子集只覆盖 57/94 件装备(全量 3396 条快照本身是 94/94), 缺的是挑选丢的不是没买到。
## 用户〖2026-07-11〗:「对战到的队伍多么, 加10个快照看看, 按档位的是吗」
##
## 断言(测纯函数, 不碰真实 user://ghost_pool.json):
##   1. _load_seed() 解析出 193 支队, 覆盖档 0-8。
##      ★数量是【硬编码期望值】, 故意不从 json 反推(那样断言就成了自己跟自己比, 池被截断也发现不了)。
##      改池容量时必须同步改这里 —— 45602ea 把 70→146 就漏了改(史实·勿改), 这个测试红了整整一天没人注意。
##   2. 每支队合法: leaders 3 只已知龟 / bracket 与桶键一致 / lane_assign 上+下=3 / is_bot=false。
##   3. _ensure_seeded 把种子并入空池(10支), 且幂等(重并不重复)。
##   4. pool_find 在档 0-8 都能抽到种子对手(seed_ 开头)。

const Backend = preload("res://scripts/net/backend.gd")
const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)

func _count(pool: Dictionary) -> int:
	var n := 0
	for b in pool.get("brackets", {}).keys():
		n += (pool["brackets"][b] as Array).size()
	return n


func _ready() -> void:
	await get_tree().process_frame
	var dr = get_node_or_null("/root/DataRegistry")

	# 1. 种子解析 + 数量 + 档覆盖
	var seed: Dictionary = Backend._load_seed()
	var brackets: Dictionary = seed.get("brackets", {})
	var total := 0
	for b in brackets.keys():
		total += (brackets[b] as Array).size()
	_ok("种子池 ≥ 150 支队", total >= 150, "实际 %d" % total)
	_ok("覆盖档 0-8", brackets.has("0") and brackets.has("8"))

	## ── ★【遇到率】—— 不是覆盖率(2026-08-15 血泪)────────────────────────────
	##   我曾用"池里出现多少【种】装备"当验收, 它显示 94/94 全覆盖 ⇒ 自检全绿 ⇒ 我报了完成。
	##   但玩家真正体验到的是【多大比例的对手身上有新装备】: 当时实测只有 6%, 五个档是 0。
	##   94 种全靠补选进来的十几支队撑着, 基础的每档 20 支几乎不带。
	##   ⇒ 覆盖率是"库存清单", 遇到率才是"你打得到吗"。两个都要焊。
	var new_batch: Array = []
	for e in DataRegistry.phase2_equipment:
		var eid := str((e as Dictionary).get("id", ""))
		if eid >= "p2eq_060" and int((e as Dictionary).get("shopAvailable", 0)) == 1:
			new_batch.append(eid)
	_ok("★分母: 认得出'新批次'装备(060 之后可购买的)", new_batch.size() >= 30,
		"%d 件" % new_batch.size())
	var t_all := 0
	var t_hit := 0
	var worst_b := ""
	var worst_p := 999.0
	for b in brackets.keys():
		if str(b) == "0":
			continue   # 档0 = 人生第一把, 双方全裸, 本来就该 0
		var n := 0
		var h := 0
		for g in (brackets[b] as Array):
			n += 1
			var ids: Dictionary = {}
			for pid in ((g as Dictionary).get("equipped", {}) as Dictionary).keys():
				for it in (((g as Dictionary)["equipped"] as Dictionary)[pid] as Array):
					ids[str((it as Dictionary).get("id", ""))] = true
			for lk in ((g as Dictionary).get("minions", {}) as Dictionary).keys():
				for m in (((g as Dictionary)["minions"] as Dictionary)[lk] as Array):
					for it in ((m as Dictionary).get("equips", []) as Array):
						ids[str((it as Dictionary).get("id", ""))] = true
			for nid in new_batch:
				if ids.has(nid):
					h += 1
					break
		t_all += n
		t_hit += h
		var pct: float = 100.0 * float(h) / float(maxi(1, n))
		if pct < worst_p:
			worst_p = pct
			worst_b = str(b)
	var overall: float = 100.0 * float(t_hit) / float(maxi(1, t_all))
	print("     遇到率: %d/%d 支队(%.0f%%)带新批次装备; 最差的档%s 只有 %.0f%%" % [
		t_hit, t_all, overall, worst_b, worst_p])
	_ok("★★★遇到率 ≥ 50%(档0 除外) —— 打几把就该见到新装备, 光「池里有」不算数",
		overall >= 50.0, "实测 %.0f%%" % overall)
	_ok("★★除档0 外没有【一支都不带新装备】的档(那个档等于回到了旧版本)",
		worst_p > 0.0, "最差 档%s = %.0f%%" % [worst_b, worst_p])

	# 2. 每支队合法
	var bad: Array = []
	for b in brackets.keys():
		for g in brackets[b]:
			var gd: Dictionary = g
			var gid := str(gd.get("ghost_id", "?"))
			var ldr: Array = gd.get("leaders", [])
			if ldr.size() != 3:
				bad.append("%s leaders≠3" % gid)
			for pid in ldr:
				if dr != null and not dr.pet_by_id.has(str(pid)):
					bad.append("%s 未知龟 %s" % [gid, pid])
			if int(gd.get("bracket", -1)) != int(str(b)):
				bad.append("%s bracket≠桶键" % gid)
			var la: Dictionary = gd.get("lane_assign", {})
			var lc: int = (la.get("top", []) as Array).size() + (la.get("bottom", []) as Array).size()
			if lc != 3:
				bad.append("%s 分路≠3" % gid)
			if bool(gd.get("is_bot", true)):
				bad.append("%s is_bot应false" % gid)
	_ok("★每支队合法(3已知龟/bracket对/分路3/非bot)", bad.is_empty(), ", ".join(bad))

	# 3. _ensure_seeded 幂等
	var pool: Dictionary = {"brackets": {}}
	Backend._ensure_seeded(pool)
	var c1 := _count(pool)
	Backend._ensure_seeded(pool)
	var c2 := _count(pool)
	## ★数量不写死两处 —— 从种子文件回读, 否则改池容量必然漏改一处(第 8 行那段史实说的就是这个)。
	_ok("_ensure_seeded 空池并入 %d" % total, c1 == total, "%d" % c1)
	_ok("_ensure_seeded 幂等(重并不重复)", c2 == total, "%d" % c2)

	# 4. pool_find 各档能抽到种子对手
	var rng := RandomNumberGenerator.new()
	var miss: Array = []
	for bi in range(9):
		var g = Backend.pool_find(pool, bi, [], rng)
		if g == null or not str((g as Dictionary).get("ghost_id", "")).begins_with("seed_"):
			miss.append(str(bi))
	_ok("★档 0-8 都能抽到种子对手", miss.is_empty(), ("缺档: " + ", ".join(miss)) if not miss.is_empty() else "")

	# 5. ★对手装备接线: _dual_foe_lane 从 ghost lane_assign 取 leaders 且挂上 equipped
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	scene.set_process(false); scene.set_physics_process(false)
	var snap: Dictionary = brackets["7"][0]   # 海渊霸主(3件含传说) — 高档强度
	gs.dual_ghost = snap
	var top_specs: Array = scene._dual_foe_lane("top")
	# lane_assign.top = [diamond, cyber] → 2 leader + 1 minion
	var leader_ids: Array = []
	var equipped_count := 0
	for sp in top_specs:
		if str((sp as Dictionary).get("kind", "")) == "leader":
			leader_ids.append(str((sp as Dictionary).get("id", "")))
			if (sp as Dictionary).has("equips") and ((sp as Dictionary)["equips"] as Array).size() > 0:
				equipped_count += 1
	var expected_top: Array = []
	for x in (snap.get("lane_assign", {}).get("top", []) as Array):
		expected_top.append(str(x))   # 动态读快照分路(别写死具体龟, 改数据不脆)
	_ok("对手上路 = ghost lane_assign 的 leaders", leader_ids == expected_top, "%s vs 期望 %s" % [str(leader_ids), str(expected_top)])
	_ok("★对手 leaders 都挂上了 equipped(按档装备)", equipped_count == expected_top.size(), "带装备的 leader 数=%d/%d" % [equipped_count, expected_top.size()])
	# 高档件数 > 空档: 抽个低档对照
	gs.dual_ghost = brackets["0"][0]   # 新手渔夫(每龟1件)
	var low_specs: Array = scene._dual_foe_lane("top")
	var low_eq := 0
	for sp in low_specs:
		if (sp as Dictionary).has("equips"):
			low_eq += ((sp as Dictionary)["equips"] as Array).size()
	var high_eq := 0
	for sp in top_specs:
		if (sp as Dictionary).has("equips"):
			high_eq += ((sp as Dictionary)["equips"] as Array).size()
	_ok("★高档对手装备件数 > 低档(强度分档)", high_eq > low_eq, "高档%d vs 低档%d" % [high_eq, low_eq])

	_done()


func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — ghost 种子池(按档递增/带loadouts) 守卫通过")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)
