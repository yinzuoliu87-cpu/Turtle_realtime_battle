extends Node
## _autoplay.gd — 模拟真人的自动玩家 (方案书 docs/plans/20260727b-快照档位强度-自举机器人.md §4.A)
##
## 用户 2026-07-27:「机器人自己买和装备物品去打个30把, 每把情况记录好」
##
## 它做真玩家做的事, 全走数据层(不碰 UI, 不建 3D 窗口, 不等任何 tween):
##   匹配对手 → 打完整场双路 → 结算收币/扣命 → 逛商店(买经验+买装备) → 回背包(三合一+装/换) → 下一把
##
## 跑法(必须 headless —— 本机开 3D 窗口会蓝屏, memory project-machine-bsod-during-tests):
##   SHIP=1 DL_AUTOFIGHT=1 TURTLE_SEED=20260727 AUTOPLAY_MATCHES=30 \
##   <godot> --headless --audio-driver Dummy --path . res://tests/_autoplay.tscn
##
## 环境变量:
##   AUTOPLAY_MATCHES   打几把 (默认 30)
##   AUTOPLAY_STRATEGY  买装策略 merge_first(默认·最像真人) / greedy_cost / random
##   AUTOPLAY_OUT       报告输出目录 (默认 res://tools/autoplay/)
##   AUTOPLAY_TAG       报告文件名标签 (默认 run)
##   AUTOPLAY_NO_FOE_EQUIP=1  ★反向验证: 把对手装备全剥光 → 胜率必须飙到 ~100%,
##                            若仍在 50% 附近, 说明"对手装备"这条链根本没生效, 整份数据作废
##
## ★匹配只读 res:// 内置种子(Backend._load_seed), 【绝不】走 load_pool ——
##   load_pool → _ensure_seeded → save_pool(backend.gd:211) 光"读"池就会写玩家真实池。
## ★下划线前缀: run-tests.sh 只自动发现 verify_*.gd, 本工具不进门禁。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const P2EQ := preload("res://scripts/gamedata/phase2_equip.gd")

const FRAME_CAP := 60000        # 单场帧上限(det模式 1帧=1/60秒 → 1000游戏秒, 远超一场三路)
const SHELF := 10               # 货架卡数 (与 ShopScene 一致)
const EXCLUDE_RECENT := 3       # 排除最近几个对手 (与真实匹配一致)

var _rng := RandomNumberGenerator.new()
var _log: Array = []            # 每把一条记录
var _recent: Array = []         # 最近对手 ghost_id
var _strategy := "merge_first"
var _strip_foe := false
## ★测量模式(AUTOPLAY_KEEP_HEARTS=1): 每把后回满 8 命。
##   起因: 实测机器人第 13 把就把 8 命输光 → 进"表演赛"分支后 season_total_battles 不再增长
##   (RealtimeBattle3DScene.gd:7262) → 档位永远冻在 4, 档 5-8 量不到。
##   本模式回答的是「若玩家真能走到第 N 场, 他手上会是什么装备」—— 这是重设计档位装备阶梯的参照系。
##   回满 8 命(而非保 1 命)是为了停在"满命"经济区间: 逆风补偿会让残命收币多 ~35%, 拿它当基准会把敌人配得过强。
var _keep_hearts := false


# ── 强度口径: 与门禁 verify_bracket_gear._strength 完全同一条公式(改一处必须改两处) ──
func _item_strength(item) -> float:
	if not (item is Dictionary):
		return 0.0
	var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(str((item as Dictionary).get("id", "")), {})
	var cost := int(edef.get("cost", 0))
	if cost <= 0:
		return 0.0
	var star: int = maxi(1, int((item as Dictionary).get("star", 1)))
	var k := {1: 0.85, 2: 0.90, 3: 1.00, 4: 1.15, 5: 1.30}
	return float(cost) * pow(1.8, float(star - 1)) * float(k.get(cost, 1.0))


func _is_equip(item) -> bool:
	return item is Dictionary and str((item as Dictionary).get("kind", "")) != "item" \
		and DataRegistry.phase2_equipment_by_id.has(str((item as Dictionary).get("id", "")))


func _item_txt(item) -> String:
	var eid := str((item as Dictionary).get("id", "?"))
	var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
	return "%s(%d费★%d)" % [str(edef.get("name", eid)), int(edef.get("cost", 0)), int((item as Dictionary).get("star", 1))]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame

	var gs = get_node_or_null("/root/GameState")
	var dr = get_node_or_null("/root/DataRegistry")
	if gs == null or dr == null:
		print("  [FAIL] 缺 GameState/DataRegistry autoload")
		get_tree().quit(1); return
	gs.test_mode = true   # 双保险: 绝不写玩家存档

	var n_matches := int(OS.get_environment("AUTOPLAY_MATCHES")) if OS.get_environment("AUTOPLAY_MATCHES").is_valid_int() else 30
	_strategy = OS.get_environment("AUTOPLAY_STRATEGY") if OS.get_environment("AUTOPLAY_STRATEGY") != "" else "merge_first"
	_strip_foe = OS.has_environment("AUTOPLAY_NO_FOE_EQUIP")
	_keep_hearts = OS.has_environment("AUTOPLAY_KEEP_HEARTS")
	var seed_txt := OS.get_environment("TURTLE_SEED")
	_rng.seed = int(seed_txt) if seed_txt.is_valid_int() else 20260727

	# ── 造一个真·新玩家 ──
	var all_ids: Array = []
	for p in dr.launch_pets:
		all_ids.append(str((p as Dictionary)["id"]))
	if all_ids.size() < 3:
		print("  [FAIL] 龟数据不足 3 只"); get_tree().quit(1); return
	var team: Array = all_ids.slice(0, 3)

	gs.season_leaders = team.duplicate()
	gs.left_team.assign(team)
	gs.season_total_battles = 0
	gs.season_level = 1
	gs.season_xp = 0
	gs.season_wins = 0
	gs.hearts = 8
	gs.meta_deepsea_coins = 0
	gs.persistent_bench = []
	gs.persistent_equipped = {}
	gs.dual_lineup = {}
	gs.get_dual_lineup()

	print("=== 自动玩家: 连打 %d 把 ===" % n_matches)
	print("  统领: %s | 策略: %s | 种子: %d%s%s" % [
		str(team), _strategy, int(_rng.seed),
		"  ★对手装备已剥光(反向验证)" if _strip_foe else "",
		"  ★测量模式(每把回满8命·量高档参照系)" if _keep_hearts else ""])
	print("  起始: 命=%d 币=%d 场次=%d 等级=%d 槽=%d" % [
		int(gs.hearts), int(gs.meta_deepsea_coins), int(gs.season_total_battles),
		int(gs.season_level), gs.team_equip_cap()])

	var seed_pool: Dictionary = Backend._load_seed()
	var seed_n := 0
	for b in seed_pool.get("brackets", {}).keys():
		seed_n += (seed_pool["brackets"][b] as Array).size()
	print("  种子池(只读 res://): %d 支队" % seed_n)
	if seed_n == 0:
		print("  [FAIL] 种子池空 → 分母 0, 整份数据无意义"); get_tree().quit(1); return

	var t_start := Time.get_ticks_msec()
	for i in range(n_matches):
		await _one_match(gs, seed_pool, i + 1)
		# 输光 8 条命 = 赛季淘汰; 真玩家此时进表演赛(奖励固定5), 继续打但没 stake → 照实记录, 不中断
	var elapsed := (Time.get_ticks_msec() - t_start) / 1000.0

	_write_report(gs, n_matches, elapsed)
	get_tree().quit(0)


# ══════════════════ 一把 ══════════════════
func _one_match(gs, seed_pool: Dictionary, idx: int) -> void:
	var rec := {}
	var b: int = Backend.bracket_for_battles(int(gs.season_total_battles))

	# ── 匹配 (与 find_opponent 同逻辑: 本档优先 → 只往【低】档回落 → bot 兜底; ±1 窗口已于 2026-07-27 废除) ──
	var ghost = null
	var from_bot := false
	for bb in range(b, -1, -1):
		ghost = Backend.pool_find(seed_pool, bb, _recent, _rng)
		if ghost != null: break
	if ghost == null:
		ghost = Backend.make_bot(b, _rng)
		from_bot = true
	ghost = (ghost as Dictionary).duplicate(true)   # 不改种子池原件

	if _strip_foe:      # 反向验证: 剥光对手装备(队长+小将)
		ghost["equipped"] = {}
		for lk in (ghost.get("minions", {}) as Dictionary).keys():
			for m in (ghost["minions"][lk] as Array):
				(m as Dictionary)["equips"] = []

	_recent.push_front(str(ghost.get("ghost_id", "")))
	while _recent.size() > EXCLUDE_RECENT:
		_recent.pop_back()

	# ── 赛前记账 ──
	rec["把次"] = idx
	rec["我方档位"] = b
	rec["我方等级"] = int(gs.season_level)
	rec["我方槽位"] = gs.team_equip_cap()
	rec["我方命"] = int(gs.hearts)
	rec["我方币_战前"] = int(gs.meta_deepsea_coins)
	rec["我方阵容"] = _my_lineup_txt(gs)
	rec["我方强度"] = _my_strength(gs)
	rec["我方件数"] = _my_item_count(gs)
	rec["对手id"] = str(ghost.get("ghost_id", "?"))
	rec["对手档位"] = int(ghost.get("bracket", -1))
	rec["对手是bot"] = from_bot
	rec["对手阵容"] = _foe_lineup_txt(ghost)
	rec["对手强度"] = _foe_strength(ghost)
	rec["对手件数"] = _foe_item_count(ghost)

	# ── 开打 ──
	gs.reset_dual_lane()
	gs.dual_active = true
	gs.dual_ghost = ghost
	var coins0 := int(gs.meta_deepsea_coins)

	var s = RB.new()
	add_child(s)
	var fr := 0
	while fr < FRAME_CAP and str(s._dl_state) != "done":
		await get_tree().process_frame
		fr += 1
	var reached: bool = str(s._dl_state) == "done"
	var winner := str(gs.dual_lane_winner())
	rec["跑到done"] = reached
	rec["帧数"] = fr
	rec["游戏秒"] = float(s._t)
	rec["逐路"] = str(gs.lane_results)
	rec["胜"] = (winner == "left")
	# ★自举原料: 战斗端上传用的快照 vs 玩家真实装备 —— 两者对不对得上, 用数据说话
	rec["快照equipped"] = str(Backend.build_ghost_snapshot("probe", {}).get("equipped", {}))
	# ★判完 done 先宽限几帧再释放场景 —— 否则正在飞的演出(大剑下劈/熔岩柱/忍者滑翔…)
	#   会在 await 之后撞上已释放的 battle, 刷 "Nonexistent function ... on previously freed"。
	#   实测那类报错都发生在【胜负判定之后】不影响数据, 但会污染致命报错计数。
	#   真实对局里场景会停在结算横幅上直到切场景, 本来就有这段宽限期; harness 原来一判 done 就腰斩。
	for _g in range(30):
		await get_tree().process_frame
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	rec["本把收币"] = int(gs.meta_deepsea_coins) - coins0
	rec["我方命_战后"] = int(gs.hearts)
	rec["已淘汰"] = bool(gs.is_eliminated())
	if _keep_hearts and int(gs.hearts) < 8:
		gs.hearts = 8    # 测量模式: 不让淘汰冻住 season_total_battles, 否则档 5-8 量不到

	# ── 逛商店 + 回背包 ──
	var shop := _shop_phase(gs)
	rec["出货"] = shop["offer_txt"]
	rec["买了"] = shop["bought_txt"]
	rec["花费"] = shop["spent"]
	rec["买经验次数"] = shop["xp_buys"]
	var eq := _equip_phase(gs)
	rec["装备动作"] = eq["txt"]
	rec["升星"] = eq["merged"]
	rec["我方币_战后"] = int(gs.meta_deepsea_coins)
	rec["我方强度_战后"] = _my_strength(gs)
	rec["我方件数_战后"] = _my_item_count(gs)
	rec["背包余"] = (gs.persistent_bench as Array).size()

	_log.append(rec)
	print("  #%2d 档%d %s | 我%.0f(%d件) vs 敌%.0f(%d件) | 币+%d→%d | 命%d | %d帧/%.0f秒 | 买:%s | 装:%s" % [
		idx, b, ("胜" if rec["胜"] else "负"),
		rec["我方强度"], rec["我方件数"], rec["对手强度"], rec["对手件数"],
		rec["本把收币"], rec["我方币_战后"], rec["我方命_战后"],
		fr, rec["游戏秒"], shop["bought_txt"], eq["txt"]])


# ══════════════════ 商店 ══════════════════
## 真玩家逛商店: ①盈余买经验升级(开槽+提出货档) ②买装备
func _shop_phase(gs) -> Dictionary:
	var spent := 0
	var xp_buys := 0

	# ① 买经验: 留够装备预算(AI_GEAR_RESERVE)后的盈余才升级 —— 复用项目自己的"像玩家"口径(phase2_config.gd:53)
	while xp_buys < P2.AI_MAX_XP_BUYS_PER_VISIT \
			and int(gs.season_level) < P2.MAX_LEVEL \
			and int(gs.meta_deepsea_coins) >= P2.AI_GEAR_RESERVE + P2.BUY_XP_COST:
		if not gs.buy_season_xp():
			break
		xp_buys += 1
		spent += P2.BUY_XP_COST

	# ② 出货 (与 ShopScene 同口径: 大轮等级驱动出货档, 满3星的不再出)
	var maxed := _maxed_ids(gs)
	var pool: Array = []
	for e in DataRegistry.phase2_equipment:
		if not maxed.has(str((e as Dictionary).get("id", ""))):
			pool.append(e)
	var stage: int = clampi(int(gs.season_level), 1, 10)
	var offer: Array = P2EQ.roll_shop(pool, stage, SHELF, _rng)

	var offer_txt: Array = []
	for e in offer:
		if e != null:
			offer_txt.append("%s%d费" % [str((e as Dictionary).get("name", "?")), int((e as Dictionary).get("cost", 1))])

	# ③ 按策略买
	var bought: Array = []
	var order: Array = _buy_order(gs, offer)
	for i in order:
		var e = offer[i]
		if e == null:
			continue
		var price: int = maxi(1, int((e as Dictionary).get("cost", 1)))
		if int(gs.meta_deepsea_coins) < price:
			continue
		gs.meta_deepsea_coins -= price
		spent += price
		(gs.persistent_bench as Array).append({"id": str((e as Dictionary).get("id", "")), "star": 1})
		gs.auto_merge_all()
		bought.append("%s%d费" % [str((e as Dictionary).get("name", "?")), price])
		offer[i] = null

	return {
		"offer_txt": " ".join(PackedStringArray(offer_txt)),
		"bought_txt": ("·".join(PackedStringArray(bought)) if not bought.is_empty() else "—"),
		"spent": spent, "xp_buys": xp_buys,
	}


## 买入优先级 (返回货架下标序).
func _buy_order(gs, offer: Array) -> Array:
	var idxs: Array = []
	for i in range(offer.size()):
		if offer[i] != null:
			idxs.append(i)
	match _strategy:
		"random":
			for i in range(idxs.size() - 1, 0, -1):
				var j: int = _rng.randi() % (i + 1)
				var t = idxs[i]; idxs[i] = idxs[j]; idxs[j] = t
		"greedy_cost":
			idxs.sort_custom(func(a, b): return int(offer[a].get("cost", 1)) > int(offer[b].get("cost", 1)))
		_:   # merge_first: 先补能凑三合一的同款, 再按费用从高到低
			var owned := _owned_1star_counts(gs)
			idxs.sort_custom(func(a, b):
				var ka: int = int(owned.get(str(offer[a].get("id", "")), 0))
				var kb: int = int(owned.get(str(offer[b].get("id", "")), 0))
				var pa: int = (2 if ka == 2 else (1 if ka == 1 else 0))   # 差1件成星 > 差2件 > 全新
				var pb: int = (2 if kb == 2 else (1 if kb == 1 else 0))
				if pa != pb:
					return pa > pb
				return int(offer[a].get("cost", 1)) > int(offer[b].get("cost", 1)))
	return idxs


## 当前手上(背包+龟身+小将)每个 id 的 1 星件数 —— 凑三合一看这个
func _owned_1star_counts(gs) -> Dictionary:
	var c := {}
	for it in _all_my_items(gs):
		if int((it as Dictionary).get("star", 1)) == 1:
			var k := str((it as Dictionary).get("id", ""))
			c[k] = int(c.get(k, 0)) + 1
	return c


func _maxed_ids(gs) -> Dictionary:
	var m := {}
	for it in _all_my_items(gs):
		if int((it as Dictionary).get("star", 1)) >= 3:
			m[str((it as Dictionary).get("id", ""))] = true
	return m


# ══════════════════ 背包: 装 / 换 ══════════════════
func _equip_phase(gs) -> Dictionary:
	var acts: Array = []
	var merged_before := _star_sum(gs)
	var slots: int = P2.UNIT_EQUIP_CAP   # 2026-07-27 统一规则: 单只上限3, 另受全队预算约束

	# ① 统领: 空槽优先装背包里最强的
	for pid in (gs.season_leaders as Array):
		var p := str(pid)
		var eqs: Array = (gs.persistent_equipped as Dictionary).get(p, [])
		while eqs.size() < slots:
			var bi := _best_bench_idx(gs)
			if bi < 0:
				break
			var item = (gs.persistent_bench as Array)[bi]
			(gs.persistent_bench as Array).remove_at(bi)
			eqs.append(item)
			acts.append("%s←%s" % [p, _item_txt(item)])
		(gs.persistent_equipped as Dictionary)[p] = eqs

	# ② 换装: 背包里最强的 > 身上最弱的 → 换 (用户「装上装备或更换装备」)
	for pid in (gs.season_leaders as Array):
		var p := str(pid)
		var eqs: Array = (gs.persistent_equipped as Dictionary).get(p, [])
		if eqs.is_empty():
			continue
		var guard := 0
		while guard < 8:
			guard += 1
			var bi := _best_bench_idx(gs)
			if bi < 0:
				break
			var wi := 0
			for i in range(eqs.size()):
				if _item_strength(eqs[i]) < _item_strength(eqs[wi]):
					wi = i
			var cand = (gs.persistent_bench as Array)[bi]
			if _item_strength(cand) <= _item_strength(eqs[wi]):
				break
			var old = eqs[wi]
			eqs[wi] = cand
			(gs.persistent_bench as Array)[bi] = old
			acts.append("%s换%s→%s" % [p, _item_txt(old), _item_txt(cand)])
		(gs.persistent_equipped as Dictionary)[p] = eqs

	# ③ 小将: 统领装满后还有货 → 装小将 (敌方快照的小将也带装备, 不装就是白送强度)
	var dl: Dictionary = gs.get_dual_lineup()
	for lane in ["top", "bottom"]:
		var arr: Array = dl.get(lane, [])
		for i in range(arr.size()):
			var u: Dictionary = arr[i]
			if str(u.get("kind", "")) != "minion":
				continue
			var meqs: Array = u.get("equips", []) if u.get("equips", null) is Array else []
			while meqs.size() < slots:
				var bi := _best_bench_idx(gs)
				if bi < 0:
					break
				var item = (gs.persistent_bench as Array)[bi]
				(gs.persistent_bench as Array).remove_at(bi)
				meqs.append(item)
				acts.append("小将%s%d←%s" % [lane, i, _item_txt(item)])
			u["equips"] = meqs
			arr[i] = u
		dl[lane] = arr
	gs.dual_lineup = dl

	gs.auto_merge_all()
	var merged: int = _star_sum(gs) - merged_before
	return {"txt": ("·".join(PackedStringArray(acts)) if not acts.is_empty() else "—"), "merged": merged}


func _best_bench_idx(gs) -> int:
	var best := -1
	var bs := 0.0
	var bench: Array = gs.persistent_bench
	for i in range(bench.size()):
		if not _is_equip(bench[i]):
			continue
		var s := _item_strength(bench[i])
		if s > bs:
			bs = s; best = i
	return best


# ══════════════════ 记账辅助 ══════════════════
func _all_my_items(gs) -> Array:
	var out: Array = []
	for it in (gs.persistent_bench as Array):
		if _is_equip(it): out.append(it)
	for p in (gs.persistent_equipped as Dictionary).keys():
		for it in ((gs.persistent_equipped as Dictionary)[p] as Array):
			if _is_equip(it): out.append(it)
	var dl: Dictionary = gs.get_dual_lineup()
	for lane in ["top", "bottom"]:
		for u in (dl.get(lane, []) as Array):
			for it in ((u as Dictionary).get("equips", []) as Array):
				if _is_equip(it): out.append(it)
	return out


func _star_sum(gs) -> int:
	var n := 0
	for it in _all_my_items(gs):
		n += int((it as Dictionary).get("star", 1))
	return n


## 我方"上场强度" = 统领身上 + 小将身上 (背包里的不算 —— 没装上就不产生战力)
func _my_strength(gs) -> float:
	var t := 0.0
	for p in (gs.persistent_equipped as Dictionary).keys():
		for it in ((gs.persistent_equipped as Dictionary)[p] as Array):
			t += _item_strength(it)
	var dl: Dictionary = gs.get_dual_lineup()
	for lane in ["top", "bottom"]:
		for u in (dl.get(lane, []) as Array):
			for it in ((u as Dictionary).get("equips", []) as Array):
				t += _item_strength(it)
	return t


func _my_item_count(gs) -> int:
	var n := 0
	for p in (gs.persistent_equipped as Dictionary).keys():
		n += ((gs.persistent_equipped as Dictionary)[p] as Array).size()
	var dl: Dictionary = gs.get_dual_lineup()
	for lane in ["top", "bottom"]:
		for u in (dl.get(lane, []) as Array):
			n += ((u as Dictionary).get("equips", []) as Array).size()
	return n


func _foe_strength(ghost: Dictionary) -> float:
	var t := 0.0
	for p in (ghost.get("equipped", {}) as Dictionary).keys():
		for it in ((ghost["equipped"] as Dictionary)[p] as Array):
			t += _item_strength(it)
	for lk in (ghost.get("minions", {}) as Dictionary).keys():
		for m in (ghost["minions"][lk] as Array):
			for it in ((m as Dictionary).get("equips", []) as Array):
				t += _item_strength(it)
	return t


func _foe_item_count(ghost: Dictionary) -> int:
	var n := 0
	for p in (ghost.get("equipped", {}) as Dictionary).keys():
		n += ((ghost["equipped"] as Dictionary)[p] as Array).size()
	for lk in (ghost.get("minions", {}) as Dictionary).keys():
		for m in (ghost["minions"][lk] as Array):
			n += ((m as Dictionary).get("equips", []) as Array).size()
	return n


func _my_lineup_txt(gs) -> String:
	var parts: Array = []
	for pid in (gs.season_leaders as Array):
		var p := str(pid)
		var items: Array = []
		for it in ((gs.persistent_equipped as Dictionary).get(p, []) as Array):
			items.append(_item_txt(it))
		parts.append("%s[%s]" % [p, ("·".join(PackedStringArray(items)) if not items.is_empty() else "裸")])
	var dl: Dictionary = gs.get_dual_lineup()
	var mn: Array = []
	for lane in ["top", "bottom"]:
		for u in (dl.get(lane, []) as Array):
			if str((u as Dictionary).get("kind", "")) != "minion":
				continue
			var its: Array = []
			for it in ((u as Dictionary).get("equips", []) as Array):
				its.append(_item_txt(it))
			mn.append("%s:%s" % [lane, ("·".join(PackedStringArray(its)) if not its.is_empty() else "裸")])
	return "%s ‖ 小将 %s" % [" ".join(PackedStringArray(parts)), " ".join(PackedStringArray(mn))]


func _foe_lineup_txt(ghost: Dictionary) -> String:
	var parts: Array = []
	for pid in (ghost.get("leaders", []) as Array):
		var p := str(pid)
		var items: Array = []
		for it in ((ghost.get("equipped", {}) as Dictionary).get(p, []) as Array):
			items.append(_item_txt(it))
		var lv: int = int((ghost.get("pet_levels", {}) as Dictionary).get(p, 1))
		parts.append("%s(Lv%d)[%s]" % [p, lv, ("·".join(PackedStringArray(items)) if not items.is_empty() else "裸")])
	var mn: Array = []
	for lk in (ghost.get("minions", {}) as Dictionary).keys():
		for m in (ghost["minions"][lk] as Array):
			var its: Array = []
			for it in ((m as Dictionary).get("equips", []) as Array):
				its.append(_item_txt(it))
			mn.append("%s%s:%s" % [str(lk), ("·精英" if (m as Dictionary).get("elite", false) else ""),
				("·".join(PackedStringArray(its)) if not its.is_empty() else "裸")])
	return "%s ‖ 小将 %s" % [" ".join(PackedStringArray(parts)), " ".join(PackedStringArray(mn))]


# ══════════════════ 报告 ══════════════════
func _write_report(gs, n: int, elapsed: float) -> void:
	var dir := OS.get_environment("AUTOPLAY_OUT")
	if dir == "":
		dir = "res://tools/autoplay"
	var tag := OS.get_environment("AUTOPLAY_TAG")
	if tag == "":
		tag = "run"
	if _strip_foe:
		tag += "-剥光对手"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir) if dir.begins_with("res://") else dir)

	var wins := 0
	var done := 0
	for r in _log:
		if r["胜"]: wins += 1
		if r["跑到done"]: done += 1

	# ── 汇总打印(即使写文件失败也看得到) ──
	print("")
	print("=== 汇总 (%d 把, 墙钟 %.1f 秒) ===" % [n, elapsed])
	print("  跑完整场: %d/%d  (不足 = 数据有洞, 别信胜率)" % [done, n])
	print("  胜率: %d/%d = %.1f%%" % [wins, n, 100.0 * wins / maxf(1.0, float(n))])
	print("  终态: 命=%d 币=%d 等级=%d 槽=%d 场次=%d 淘汰=%s" % [
		int(gs.hearts), int(gs.meta_deepsea_coins), int(gs.season_level),
		gs.team_equip_cap(), int(gs.season_total_battles), str(gs.is_eliminated())])
	print("  终局阵容: %s" % _my_lineup_txt(gs))
	print("  ★分母: 记录 %d 条 (0 = 空跑, 整份报告无意义)" % _log.size())

	# 按档汇总
	print("")
	print("  档位  场次  胜  胜率    我均强度  敌均强度  强度差")
	var by_b := {}
	for r in _log:
		var b: int = int(r["我方档位"])
		if not by_b.has(b):
			by_b[b] = {"n": 0, "w": 0, "me": 0.0, "foe": 0.0}
		by_b[b]["n"] += 1
		by_b[b]["w"] += (1 if r["胜"] else 0)
		by_b[b]["me"] += float(r["我方强度"])
		by_b[b]["foe"] += float(r["对手强度"])
	var keys: Array = by_b.keys(); keys.sort()
	for b in keys:
		var d: Dictionary = by_b[b]
		var cnt: float = maxf(1.0, float(d["n"]))
		print("   %2d  %4d %3d %5.0f%%  %9.1f %9.1f %+8.1f" % [
			b, d["n"], d["w"], 100.0 * d["w"] / cnt, d["me"] / cnt, d["foe"] / cnt, (d["me"] - d["foe"]) / cnt])

	# ── 落盘 ──
	var md := "# 自动玩家 %d 把实录\n\n" % n
	md += "- 策略 `%s` · 种子 `%d` · 墙钟 %.1f 秒%s\n" % [_strategy, int(_rng.seed), elapsed,
		"\n- ★**对手装备已剥光(反向验证)**" if _strip_foe else ""]
	md += "- 胜率 **%d/%d = %.1f%%** · 跑完整场 %d/%d\n" % [wins, n, 100.0 * wins / maxf(1.0, float(n)), done, n]
	md += "- 终态: 命 %d · 币 %d · 等级 %d(槽 %d) · 淘汰 %s\n\n" % [
		int(gs.hearts), int(gs.meta_deepsea_coins), int(gs.season_level),
		gs.team_equip_cap(), str(gs.is_eliminated())]
	md += "## 逐把\n\n"
	for r in _log:
		md += "### 第 %d 把 — %s (档%d)\n\n" % [int(r["把次"]), ("胜" if r["胜"] else "负"), int(r["我方档位"])]
		md += "- **我方** Lv%d(槽%d) 命%d 币%d → 强度 **%.1f** (%d件)\n  - %s\n" % [
			int(r["我方等级"]), int(r["我方槽位"]), int(r["我方命"]), int(r["我方币_战前"]),
			float(r["我方强度"]), int(r["我方件数"]), str(r["我方阵容"])]
		md += "- **对手** %s (档%d%s) → 强度 **%.1f** (%d件)\n  - %s\n" % [
			str(r["对手id"]), int(r["对手档位"]), "·bot" if r["对手是bot"] else "",
			float(r["对手强度"]), int(r["对手件数"]), str(r["对手阵容"])]
		md += "- **结果** %s · 逐路 %s · %d帧/%.0f游戏秒 · 收币 +%d · 战后命 %d\n" % [
			("胜" if r["胜"] else "负"), str(r["逐路"]), int(r["帧数"]), float(r["游戏秒"]),
			int(r["本把收币"]), int(r["我方命_战后"])]
		md += "- **商店** 出货: %s\n  - 买入: %s (花 %d · 买经验 %d 次)\n" % [
			str(r["出货"]), str(r["买了"]), int(r["花费"]), int(r["买经验次数"])]
		md += "- **背包** %s · 升星净增 %d · 战后强度 %.1f(%d件) · 背包余 %d\n" % [
			str(r["装备动作"]), int(r["升星"]), float(r["我方强度_战后"]), int(r["我方件数_战后"]), int(r["背包余"])]
		md += "- 上传快照的 equipped 字段: `%s`\n\n" % str(r["快照equipped"])

	var md_path := "%s/%s-%d把.md" % [dir, tag, n]
	var f := FileAccess.open(md_path, FileAccess.WRITE)
	if f != null:
		f.store_string(md); f.close()
		print("  报告: %s" % md_path)
	else:
		print("  [WARN] 报告写不出: %s" % md_path)

	var csv := "把次,我方档位,我方等级,我方槽位,我方命,胜,我方强度,我方件数,对手id,对手档位,对手强度,对手件数,收币,花费,买经验次数,升星,战后强度,战后件数,背包余,帧数,游戏秒\n"
	for r in _log:
		csv += "%d,%d,%d,%d,%d,%d,%.2f,%d,%s,%d,%.2f,%d,%d,%d,%d,%d,%.2f,%d,%d,%d,%.1f\n" % [
			int(r["把次"]), int(r["我方档位"]), int(r["我方等级"]), int(r["我方槽位"]), int(r["我方命"]),
			(1 if r["胜"] else 0), float(r["我方强度"]), int(r["我方件数"]),
			str(r["对手id"]), int(r["对手档位"]), float(r["对手强度"]), int(r["对手件数"]),
			int(r["本把收币"]), int(r["花费"]), int(r["买经验次数"]), int(r["升星"]),
			float(r["我方强度_战后"]), int(r["我方件数_战后"]), int(r["背包余"]),
			int(r["帧数"]), float(r["游戏秒"])]
	var csv_path := "%s/%s-%d把.csv" % [dir, tag, n]
	var f2 := FileAccess.open(csv_path, FileAccess.WRITE)
	if f2 != null:
		f2.store_string(csv); f2.close()
		print("  CSV : %s" % csv_path)
