extends Node
## verify_econ_paths —— S2: 背包 / 收入 / 对局进度全部走记账口(方案书 docs/plans/20261106-装备与深海币服务器记账.md §6)。
##
## 用户 2026-11-06「装备要改成伏击机装(= 服务器记账)了，这个要做。」S1 只接了商店; S2 把其余写入点全部收进
##   `EconLedger`。这条门禁量三件事:
##   ① 真入口(背包页的穿 / 卸 / 换人 / 卖 / 等级器 / 换位, GameState 的闯关 / 决赛 / 配额补发结算, 裁判结果单的宝箱 / 香火)
##     一路走下来, **哨兵一次都没响**(`econ_drift` 仍是 0) —— 每一笔资产变化都有对应的流水。
##   ② 退回开局、只按流水 `EconLedger.apply` 重放 ⇒ 资产 + 宝箱 / 香火与本机逐字节相同; 两遍重放相同。
##   ③ ★反向(哨兵会响): 用静态扫描看不见的别名写法往背包塞一件 / 经函数参数改卡池 ⇒ 存一次档, `econ_drift` 各 +1,
##     且记下是哪一块(bench / pool)。沙盒(`econ_quiet`)里同样的写法 ⇒ 不响、不记流水。
## 战斗里当场写的宝箱财宝值(chest_system.note_damage 那种)⇒ 不算漂移, 下一次存档补一条 `prog`(终值)。

const EL := preload("res://scripts/gamedata/econ_ledger.gd")
const InvScene := preload("res://scripts/scenes/InventoryScene.gd")
const P2T := preload("res://scripts/gamedata/phase2_types.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const KEYS := ["meta_deepsea_coins", "persistent_bench", "persistent_equipped", "dual_lineup", "equip_pool",
	"meta_shop_offer", "meta_shop_locked", "season_level", "season_xp", "season_leaders",
	"axe_exp_bar", "axe_exp_total", "axe_stage", "axe_final", "axe_syn_matches",
	"candy_jar_count", "candy_jar_broken", "candy_temp_levels",
	"chest_treasure_value", "chest_treasures_won", "incense_marks", "incense_charge"]

var _fails := 0
var _n := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	print(("  [PASS] " if c else "  [FAIL] ") + n + ("" if c or d == "" else "  " + d))
	if not c:
		_fails += 1


func _snap() -> Dictionary:
	var d := {}
	for k in KEYS:
		var v = GameState.get(k)
		d[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return d


func _put(d: Dictionary) -> void:
	for k in KEYS:
		var v = d[k]
		GameState.set(k, v.duplicate(true) if (v is Array or v is Dictionary) else v)


## 比的是记账口自己的规整口径(资产 + 宝箱 / 香火) —— 同一把尺子 S4 服务器也用。
func _canon() -> String:
	return JSON.stringify({"a": EL.assets_of(GameState), "p": EL.progress_of(GameState)})


func _replay(start: Dictionary, log: Array) -> Array:
	_put(start)
	var bad: Array = []
	for op in log:
		GameState.season_total_battles = int((op as Dictionary).get("bt", 0))
		var r: Dictionary = EL.apply(GameState, op)
		if not bool(r.get("ok", false)):
			bad.append("%s#%s:%s" % [str(op.get("op", "")), str(op.get("seq", "")), str(r.get("reason", ""))])
	return [_canon(), bad]


func _ids_of_type(t: String, n: int) -> Array:
	var out: Array = []
	for e in DataRegistry.phase2_equipment:
		var id := str((e as Dictionary).get("id", ""))
		if P2T.type_of(id) == t and int((e as Dictionary).get("shopAvailable", 0)) == 1:
			out.append(id)
		if out.size() >= n:
			break
	return out


## 背包里第一件 id(星)的下标
func _bi(id: String, star: int = 1) -> int:
	var b: Array = GameState.persistent_bench
	for i in range(b.size()):
		if b[i] is Dictionary and str(b[i].get("id", "")) == id and int(b[i].get("star", 1)) == star:
			return i
	return -1


func _minion_at(lane: String) -> int:
	var arr: Array = GameState.get_dual_lineup().get(lane, [])
	for i in range(arr.size()):
		if arr[i] is Dictionary and str(arr[i].get("kind", "")) == "minion":
			return i
	return -1


func _ready() -> void:
	await get_tree().process_frame
	var gs = GameState
	gs.test_mode = true                    # save() 不落盘(哨兵照样在 save() 开头跑)
	var sh: Array = _ids_of_type("盾", 3)
	var plain: Array = []
	for e in DataRegistry.phase2_equipment:
		var id := str((e as Dictionary).get("id", ""))
		if int((e as Dictionary).get("shopAvailable", 0)) == 1 and not P2T.type_of(id) in ["盾", "斧头"] \
				and id != "p2eq_096" and int((e as Dictionary).get("cost", 0)) == 1:
			plain.append(id)
	_ok("分母: 找到 3 件盾 + 2 件非盾非斧的 1 费装备", sh.size() == 3 and plain.size() >= 2, "盾 %s / 其它 %s" % [str(sh), str(plain.slice(0, 2))])
	if plain.size() < 2:
		print("FAILED: 分母不成立")
		get_tree().quit(1)
		return
	var A := str(plain[0])
	var B := str(plain[1])

	## ── 本周开局: 统领还没锁、阵容默认、背包里一些货 + 一个临时等级器 ──
	gs.econ_log = []
	gs.season_total_battles = 3
	gs.meta_deepsea_coins = 100
	gs.persistent_bench = [{"id": A, "star": 1}, {"id": A, "star": 1}, {"id": A, "star": 1},
		{"id": B, "star": 1}, {"id": B, "star": 1},
		{"id": sh[0], "star": 1}, {"id": sh[1], "star": 1}, {"id": sh[2], "star": 1},
		gs.TEMP_LEVELER_ITEM.duplicate()]
	gs.persistent_equipped = {}
	gs.equip_pool = {}
	gs.meta_shop_offer = []
	gs.meta_shop_locked = false
	gs.season_level = 6                    # 全队装备上限够装下面这些
	gs.season_xp = 0
	gs.season_leaders = []
	gs.dual_lineup = {}
	gs.axe_exp_bar = 0
	gs.axe_exp_total = 0
	gs.axe_stage = 0
	gs.axe_final = ""
	gs.axe_syn_matches = 0
	gs.candy_jar_count = 10
	gs.candy_jar_broken = false
	gs.candy_temp_levels = {}
	gs.chest_treasure_value = 0.0
	gs.chest_treasures_won = []
	gs.incense_marks = 0
	gs.incense_charge = 0
	gs.promoted = true
	gs.ranked_used = int(gs._P2.RANKED_QUOTA) - 2   # 配额补发: 还欠 2 场
	gs.backfill_paid = 0
	gs.hearts = int(gs._P2.HEARTS_MAX)
	EL.rebase(gs)
	gs.econ_drift = 0
	gs.econ_drift_note = ""
	var start := _snap()

	## ── 真入口 ──
	## 选龟页「开始」那一句(TeamSelectScene._on_start 原样): 锁统领 + 同步赠送件
	gs.econ({"op": "leaders", "ids": ["candy", "stone", "ice"]})
	var sc = InvScene.new()
	get_tree().root.add_child(sc)
	await get_tree().process_frame
	var ops = sc._inv_ops
	ops._equip_to("candy", _bi(A))         # 穿
	ops._equip_to("candy", _bi(A))
	ops._equip_to("stone", _bi(A))         # 第 3 件 A ⇒ 自动合成 2★(背包 + 身上一起算)
	var merged := false
	for pid in gs.persistent_equipped:
		for it in gs.persistent_equipped[pid]:
			if it is Dictionary and str(it.get("id", "")) == A and int(it.get("star", 1)) == 2:
				merged = true
	_ok("分母: 三件 A 真合成了 2★(穿装备会触发自动合成)", merged, str(gs.persistent_equipped))
	for s in sh:
		ops._equip_to("ice", _bi(str(s)))   # 3 盾 ⇒ 盾羁绊 ⇒ 圣光护盾赠送件(sync 在记账口里)
	var holy := 0
	for it in gs.persistent_bench:
		if gs.is_synergy_grant(it):
			holy += 1
	_ok("分母: 3 盾装上后背包里出现了圣光护盾(赠送件同步走记账口)", holy >= 1, "赠送件 %d" % holy)
	var mi := _minion_at("top")
	var mb := _minion_at("bottom")
	ops._equip_minion("top", mi, _bi(B))   # 小将穿
	ops._equip_to("ice", _bi("temp_leveler", 0))   # 临时等级器
	ops._unequip_at("ice", 0)              # 卸
	sc._swap_units("top", mi, "bottom", mb)    # 换位: 穿着 B 的那只小将挪到 bottom[mb]
	ops._move_worn("bottom", mb, 0, "top", 0)  # 按新地址把那件挪给 top 第 0 格的统领(没有换位流水 ⇒ 这个地址上的小将身上是空的)
	ops._equip_minion("bottom", mb, _bi(B))    # 小将再穿一件
	ops._unequip_minion_at("bottom", mb, 0)    # 小将卸
	sc._sel_bench = _bi(B)
	ops._sell_selected()                   # 卖
	sc.queue_free()
	## 结算(GameState 里战斗 / 裁判记账调的同一批函数)
	gs.gauntlet_settle(true)
	gs.finals_settle_sealed()
	gs.finals_reveal(false)
	var paid: int = gs.backfill_ranked_quota()
	_ok("分母: 配额补发真发了(2 场)", paid == 2, "paid=%d" % paid)
	RW.apply_chest(gs, {"value": 300.0, "won": ["t_a"]})
	RW.apply_incense(gs, {"marks": 2, "charge": 150})
	gs.econ({"op": "axe_exp", "n": 2})     # AxeSystem.on_death 那一句
	## 本机打的一局里宝箱龟当场写存档(chest_system.note_damage 的写法) ⇒ 下一次存档补一条 prog
	gs.chest_treasure_value = float(gs.chest_treasure_value) + 77.0
	gs.save()
	var live := _canon()
	var log: Array = (gs.econ_log as Array).duplicate(true)

	## ① 分母 + 哨兵没响
	var kinds := {}
	for op in log:
		var k := str((op as Dictionary).get("op", ""))
		kinds[k] = int(kinds.get(k, 0)) + 1
	print("  流水 %d 条: %s" % [log.size(), str(kinds)])
	var need := {"leaders": 1, "equip": 6, "unequip": 2, "move": 1, "swap": 1, "sell": 1, "leveler": 1,
		"income": 4, "chest": 1, "incense": 1, "axe_exp": 1, "prog": 1}
	var short: Array = []
	for k in need:
		if int(kinds.get(k, 0)) < int(need[k]):
			short.append("%s %d<%d" % [k, int(kinds.get(k, 0)), int(need[k])])
	_ok("① 分母: 每种操作都真落了流水", short.is_empty(), str(short))
	_ok("① ★真入口一路走下来哨兵一次都没响(econ_drift = 0)", int(gs.econ_drift) == 0,
		"drift=%d %s" % [int(gs.econ_drift), str(gs.econ_drift_note)])

	## ② 重放 = 本机
	var r1: Array = _replay(start, log)
	_ok("② 每条流水重放都成交", (r1[1] as Array).is_empty(), str(r1[1]))
	_ok("② ★重放结果与本机逐字节相同(%d 字节)" % live.length(), str(r1[0]) == live, _first_diff(live, str(r1[0])))
	var r2: Array = _replay(start, log)
	_ok("② 两遍重放逐字节相同", str(r2[0]) == str(r1[0]))
	## ②′ 反向: 拿掉换位那一条 ⇒ 重放必须对不上(证明小将地址真的靠这条流水)
	var no_swap: Array = []
	for op in log:
		if str((op as Dictionary).get("op", "")) != "swap":
			no_swap.append(op)
	var r3: Array = _replay(start, no_swap)
	_ok("②′ ★反向: 去掉换位那一条流水 ⇒ 重放与本机不同(判据不是恒真式)", str(r3[0]) != live)

	## ③ 反向: 哨兵会响
	_put(JSON.parse_string(JSON.stringify(_snap())))   # 当前状态原样(只为确认下面从干净起点量)
	EL.rebase(gs)
	var d0 := int(gs.econ_drift)
	var bench_alias: Array = gs.persistent_bench           # 静态扫描看不见的别名写法
	bench_alias.append({"id": A, "star": 1})
	gs.save()
	_ok("③ ★别名往背包塞一件 + 存档 ⇒ 哨兵 +1 且说是 bench", int(gs.econ_drift) == d0 + 1
		and str(gs.econ_drift_note).contains("bench"), "drift %d→%d note=%s" % [d0, int(gs.econ_drift), str(gs.econ_drift_note)])
	gs.ensure_equip_pool()
	EquipPool.take(gs.equip_pool, A, 1)                     # 经函数参数改卡池
	gs.save()
	_ok("③ ★经函数参数扣一张卡池 + 存档 ⇒ 哨兵再 +1 且说是 pool", int(gs.econ_drift) == d0 + 2
		and str(gs.econ_drift_note).contains("pool"), "drift=%d note=%s" % [int(gs.econ_drift), str(gs.econ_drift_note)])
	gs.save()
	_ok("③ 没再改 ⇒ 再存一次不重复记", int(gs.econ_drift) == d0 + 2, "drift=%d" % int(gs.econ_drift))
	gs.ensure_equip_pool()
	gs.save()
	_ok("③ 卡池懒补齐(ensure_equip_pool)不算漂移", int(gs.econ_drift) == d0 + 2, "drift=%d" % int(gs.econ_drift))
	## 沙盒: 同样的写法不响、记账也不落流水
	gs.econ_quiet = 1
	var n_log := (gs.econ_log as Array).size()
	bench_alias.append({"id": A, "star": 1})
	gs.save()
	gs.econ({"op": "income", "src": "t", "coins": 5})
	_ok("③ 沙盒(econ_quiet)里: 哨兵不响、记账不落流水", int(gs.econ_drift) == d0 + 2
		and (gs.econ_log as Array).size() == n_log, "drift=%d log %d→%d" % [int(gs.econ_drift), n_log, (gs.econ_log as Array).size()])
	gs.econ_quiet = 0

	print("  (共 %d 条断言)" % _n)
	print("ALL PASS" if _fails == 0 else "FAILED: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _first_diff(a: String, b: String) -> String:
	var da = JSON.parse_string(a)
	var db = JSON.parse_string(b)
	if not (da is Dictionary and db is Dictionary):
		return "?"
	for part in ["a", "p"]:
		for k in (da[part] as Dictionary):
			if JSON.stringify(da[part][k]) != JSON.stringify((db[part] as Dictionary).get(k)):
				return "%s.%s: 本机 %s / 重放 %s" % [part, k, JSON.stringify(da[part][k]).left(220), JSON.stringify((db[part] as Dictionary).get(k)).left(220)]
	return ""
