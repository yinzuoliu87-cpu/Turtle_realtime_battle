extends Node
## verify_econ_replay_job —— S4a: 裁判机上重放一个人本周的经济流水(方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.5)。
##
## 用户 2026-11-06「装备要改成伏击机装(= 服务器记账)了，这个要做。」判据:
##   ① 起点: 换周 `start_new_season` 之后的经济 = 全新 GameState 初值(EconReplay.week_start)。两边谁改了没跟上就红。
##      分母: 改之前的状态确实不是起点(否则恒真)。
##   ② 从本周开局走真入口(锁统领 / 闯关结算 + 裁判发币 / 商店进店掷货 + 买 / 背包穿装备 / 裁判结果单的宝箱 / 开糖果罐),
##      流水交给 EconReplay.run(strict)⇒ 每条都过、资产与宝箱香火的规整结果 = 本机逐字节; 按来源汇总的收入 = 本机记的那几笔。
##   ③ strict 不认的: 本机计分局的收入来源(match)/ 本机战斗写的宝箱终值(prog)⇒ 停在那一条、说出原因; 不 strict 照过。
##   ④ ★反向: 篡改流水(买一格空的 / 序号断了 / 不认识的操作)⇒ 停在那一条; 掷货种子 +1 ⇒ 结果与本机不同。
##   ⑤ 零副作用: 重放前后 GameState(capture_all)逐字节相同。
##   ⑥ 命令行入口 run_files(referee_main --econ-replay 调的那个)读写文件, 结果与 run 相同。

const EL := preload("res://scripts/gamedata/econ_ledger.gd")
const InvScene := preload("res://scripts/scenes/InventoryScene.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")

var _fails := 0
var _n := 0
## 这一周的服务器账本(闯关 1 场赢、发币 40 = 8 + 铸币 32、宝箱结果单 120)。收入核账本的判据在 verify_econ_server_check
var FACTS := {"gauntlet": {"n": 1, "w": 1, "minted": 32}, "chest": [{"value": 120.0, "won": ["t1"]}]}


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	print(("  [PASS] " if c else "  [FAIL] ") + n + ("" if c or d == "" else "  " + d))
	if not c:
		_fails += 1


func _canon(gs) -> String:
	return JSON.stringify({"a": EL.assets_of(gs), "p": EL.progress_of(gs)})


func _start_canon(gs) -> String:
	return JSON.stringify({"a": EL.assets_of(gs), "p": EL.progress_of(gs), "bt": int(gs.season_total_battles),
		"sb": int(gs.meta_shop_battles), "evo": gs.axe_evo_pending})


func _dirty(gs) -> void:
	gs.meta_deepsea_coins = 321
	gs.persistent_bench = [{"id": "p2eq_001", "star": 2}]
	gs.persistent_equipped = {"stone": [{"id": "p2eq_002", "star": 1}]}
	gs.equip_pool = {"p2eq_001": 3}
	gs.meta_shop_offer = [{"id": "p2eq_003"}]
	gs.meta_shop_battles = 7
	gs.meta_shop_locked = true
	gs.season_level = 6
	gs.season_xp = 5
	gs.season_leaders = ["stone", "ice", "candy"]
	gs.axe_exp_total = 40
	gs.axe_stage = 1
	gs.candy_jar_count = 12
	gs.candy_temp_levels = {"stone": 1}
	gs.chest_treasure_value = 99.0
	gs.incense_marks = 3
	gs.season_total_battles = 9


func _ready() -> void:
	await get_tree().process_frame
	var gs = GameState
	gs.test_mode = true

	## ── ① 起点 ──
	_dirty(gs)
	var dirty := _start_canon(gs)
	gs.start_new_season()
	var by_season := _start_canon(gs)
	_dirty(gs)
	EconReplay.week_start(gs)
	var by_fresh := _start_canon(gs)
	_ok("① 分母: 改之前的状态确实不是起点", dirty != by_season)
	_ok("① ★换周之后的经济 = 全新 GameState 初值(重放起点)", by_season == by_fresh,
		"换周 %s / 初值 %s" % [by_season.left(160), by_fresh.left(160)])

	## ── ② 本周开局走真入口 ──
	gs.start_new_season()
	gs.econ_log = []
	gs.econ_up = 0
	EL.rebase(gs)
	gs.econ_drift = 0
	gs.econ({"op": "leaders", "ids": ["candy", "stone", "ice"]})       # 选龟页「开始」
	gs.gauntlet_settle(true)                                          # 闯关一场(大轮经验 / 斧头 / 糖果罐)
	gs.econ({"op": "income", "src": "gauntlet_ref", "coins": 40})     # 裁判结果单那一笔币(RefereeWatch.settle)
	var shop = load("res://scripts/scenes/ShopScene.gd").new()
	add_child(shop)                                                   # 打过一场 ⇒ 进店掷货
	var bought: Array = []
	for i in range(10):
		if bought.size() >= 2:
			break
		if i < shop._offer.size() and shop._offer[i] != null:
			var c0 := int(gs.meta_deepsea_coins)
			shop._on_buy(i)
			if int(gs.meta_deepsea_coins) < c0:
				bought.append(i)
	shop.queue_free()
	var sc = InvScene.new()
	get_tree().root.add_child(sc)
	await get_tree().process_frame
	for k in range((gs.persistent_bench as Array).size()):
		if gs.persistent_bench[k] is Dictionary and str((gs.persistent_bench[k] as Dictionary).get("kind", "")) != "item":
			sc._inv_ops._equip_to("candy", k)                         # 背包穿一件
			break
	sc.queue_free()
	RW.apply_chest(gs, {"value": 120.0, "won": ["t1"]})               # 裁判结果单的宝箱进度
	var jar: Dictionary = gs.break_candy_jar()                        # 开糖果罐(闯关赢了 +2 ⇒ 有罐)
	var log: Array = (gs.econ_log as Array).duplicate(true)
	var live := _canon(gs)
	var kinds := {}
	for row in log:
		kinds[str(row.get("op", ""))] = int(kinds.get(str(row.get("op", "")), 0)) + 1
	print("  流水 %d 条: %s" % [log.size(), str(kinds)])
	_ok("② 分母: 锁统领 / 收入 ≥2 / 掷货 / 买 2 / 穿 / 宝箱 / 开罐都落了流水", int(kinds.get("leaders", 0)) == 1
		and int(kinds.get("income", 0)) >= 2 and int(kinds.get("roll", 0)) >= 1 and int(kinds.get("buy", 0)) == 2
		and int(kinds.get("equip", 0)) == 1 and int(kinds.get("chest", 0)) == 1 and int(kinds.get("candy", 0)) == 1
		and not jar.is_empty(), str(kinds))
	_ok("② 分母: 哨兵一次没响(这段全走记账口)", int(gs.econ_drift) == 0, str(gs.econ_drift_note))
	var cap0: Dictionary = ReplayRecorder.capture_all()
	var res: Dictionary = EconReplay.run(gs, {"rows": log, "strict": true, "facts": FACTS})
	_ok("② ★strict 重放: 每条都过", int(res.get("upto", -1)) == log.size() and int(res.get("bad_at", 0)) == -1,
		"upto=%d bad_at=%d why=%s" % [int(res.get("upto", -1)), int(res.get("bad_at", 0)), str(res.get("why", ""))])
	var rep := JSON.stringify({"a": res.get("assets", {}), "p": res.get("progress", {})})
	_ok("② ★重放出的资产 + 宝箱香火 = 本机逐字节(%d 字节)" % live.length(), rep == live, "重放 %s" % rep.left(200))
	var inc: Dictionary = res.get("income", {})
	_ok("② 按来源汇总的收入 = 本机记的那几笔(裁判发币 40 / 闯关经验 %d)" % int(gs._P2.GAUNTLET_XP_PER_MATCH),
		int((inc.get("gauntlet_ref", {}) as Dictionary).get("coins", -1)) == 40
		and int((inc.get("gauntlet", {}) as Dictionary).get("xp", -1)) == int(gs._P2.GAUNTLET_XP_PER_MATCH), str(inc))
	## ⑤ 零副作用
	_ok("⑤ ★重放前后 GameState 逐字节相同(capture_all)", var_to_bytes(ReplayRecorder.capture_all()) == var_to_bytes(cap0))

	## ── ③ strict 不认的 ──
	gs.econ({"op": "income", "src": "match", "coins": 7})               # 本机计分局那条路的收入
	var log2: Array = (gs.econ_log as Array).duplicate(true)
	var r2: Dictionary = EconReplay.run(gs, {"rows": log2, "strict": true, "facts": FACTS})
	_ok("③ strict: 本机计分局的收入(src=match)⇒ 停在那一条", int(r2.get("bad_at", -1)) == log2.size() - 1
		and str(r2.get("why", "")) == "src:match" and int(r2.get("upto", -1)) == log2.size() - 1, str(r2.get("why", "")))
	_ok("③ 不 strict(开关关着那一周)照过", int(EconReplay.run(gs, {"rows": log2, "strict": false}).get("bad_at", 0)) == -1)
	gs.chest_treasure_value = float(gs.chest_treasure_value) + 33.0  # 本机战斗当场写宝箱值(chest_system 那种)
	gs.save()                                                         # 哨兵补一条 prog
	var log3: Array = (gs.econ_log as Array).duplicate(true)
	## 单量 prog: 干净的那 %d 条 + 这一条 prog(序号接上)⇒ strict 正好停在 prog 上
	var prow: Dictionary = (log3[-1] as Dictionary).duplicate(true)
	prow["seq"] = log.size()
	var log_p: Array = log.duplicate(true)
	log_p.append(prow)
	var r3: Dictionary = EconReplay.run(gs, {"rows": log_p, "strict": true, "facts": FACTS})
	_ok("③ strict: 本机战斗的宝箱终值(prog)⇒ 停在那一条", str(prow.get("op", "")) == "prog"
		and int(r3.get("bad_at", -1)) == log.size() and str(r3.get("why", "")) == "local_only:prog", str(r3.get("why", "")))
	var r3b: Dictionary = EconReplay.run(gs, {"rows": log3, "strict": false})
	_ok("③ 不 strict: prog 照过, 宝箱值跟到本机", int(r3b.get("bad_at", 0)) == -1
		and JSON.stringify(r3b.get("progress", {})) == JSON.stringify(EL.progress_of(gs)), str(r3b.get("why", "")))

	## ── ④ 反向: 篡改流水 ──
	var t_buy: Array = log.duplicate(true)
	var bi := -1
	for i in range(t_buy.size()):
		if str(t_buy[i].get("op", "")) == "buy":
			bi = i
			break
	(t_buy[bi] as Dictionary)["slot"] = 99                            # 买一格不存在的
	var r4: Dictionary = EconReplay.run(gs, {"rows": t_buy, "strict": true, "facts": FACTS})
	_ok("④ ★篡改: 买一格不存在的 ⇒ 停在那一条(apply 不成交)", int(r4.get("bad_at", -1)) == bi
		and str(r4.get("why", "")).begins_with("apply:buy"), str(r4.get("why", "")))
	var t_seq: Array = log.duplicate(true)
	t_seq.remove_at(2)                                                # 中间少一条 ⇒ 序号断了
	_ok("④ 序号断了 ⇒ 停在断开那一条", str(EconReplay.run(gs, {"rows": t_seq, "strict": true, "facts": FACTS}).get("why", "")) == "seq")
	var t_op: Array = log.duplicate(true)
	(t_op[0] as Dictionary)["op"] = "gift"
	_ok("④ 不认识的操作 ⇒ 停在那一条", str(EconReplay.run(gs, {"rows": t_op, "strict": true, "facts": FACTS}).get("why", "")) == "op:gift")
	var t_seed: Array = log.duplicate(true)
	for row in t_seed:
		if str(row.get("op", "")) == "roll":
			row["seed"] = int(row["seed"]) + 1
			break
	var r5: Dictionary = EconReplay.run(gs, {"rows": t_seed, "strict": false})
	_ok("④ ★掷货种子 +1 ⇒ 重放结果与本机不同(判据不是恒真式)",
		JSON.stringify({"a": r5.get("assets", {}), "p": r5.get("progress", {})}) != live or int(r5.get("bad_at", -1)) >= 0)

	## ── ⑥ 命令行入口 ──
	var inp := OS.get_user_data_dir().path_join("econ_replay_in.json")
	var outp := OS.get_user_data_dir().path_join("econ_replay_out.json")
	var f := FileAccess.open(inp, FileAccess.WRITE)
	f.store_string(JSON.stringify({"rows": log, "strict": true, "facts": FACTS}))
	f.close()
	var code := EconReplay.run_files(self, inp, outp)
	var back = JSON.parse_string(FileAccess.get_file_as_string(outp))
	_ok("⑥ run_files(referee_main --econ-replay): 退出码 0、结果文件里的指纹 = run 的", code == 0 and back is Dictionary
		and str((back as Dictionary).get("fp", "")) == str(res.get("fp", "?")), "code=%d" % code)
	DirAccess.remove_absolute(inp)
	DirAccess.remove_absolute(outp)
	var src := FileAccess.get_file_as_string("res://scripts/referee/referee_main.gd")
	_ok("⑥ referee_main 认 --econ-replay 并调 EconReplay.run_files", src.contains("args.has(\"econ-replay\")")
		and src.contains("EconReplay.run_files(self"))

	print("  (共 %d 条断言)" % _n)
	print("ALL PASS" if _fails == 0 else "FAILED: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
