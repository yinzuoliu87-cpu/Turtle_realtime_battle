extends Node
## verify_referee_coins.gd — 周六服务器局发战斗内铸币(2026-10-20 · 方案书 docs/plans/20261019-服务器裁判.md 决策记录)。
##
## 缺口: 本机打完一局, `_settle_season` 把奇械羁绊铸币 + 035 黄铜齿轮加进奖励; 服务器算的周六局一枚都没发
##   (客户端记账在播之前, 拿不到本机重算的数)。改法: 裁判结果单带 `coins`(读与本机结算同一个出口 `EquipTickSystem.match_minted`),
##   服务端记进账本, 客户端 `RefereeWatch.settle` 按它发。
##
## 判据(全程真入口, 不手算):
##   K1 分母: 我方三只统领各带一件 3 星 035 齿轮 ⇒ 裁判那一局 coins > 0
##   K2 ★同一局本机跑: 拿裁判的录像走「中途退出补打」那条复算路(`resume` 模式 = 本机真打到结算, `_settle_season` 真跑)
##      ⇒ 终局指纹 = 裁判的; 本机这一局的奖励 `_last_reward` = 场次币 8 + 裁判的 coins(逐枚相同); 存档里的币也多这么多
##   K3 ★客户端按服务器记账: 同一局交给 `RefereeWatch.settle`(status 里的 coins = 裁判的)⇒ 币的增量 = K2 本机那一局的增量
##   K4 客户端不自报 / 不重算: settle 只认 status 里的 coins —— 战斗场里留着的铸币计数、status 里没有 coins(老服务端)⇒ 0;
##      负数 / 字符串 ⇒ 0; 出局那一局 ⇒ 一枚不发(与本机 `_settle_season` 同一条)
##   K5 对照: 不带齿轮 ⇒ 裁判 coins = 0(证明 K1 的数不是凭空来的)
##   K6 单一出口: `_settle_season` 与 `RefereeRunner` 都调 `EquipTickSystem.match_minted`, 主文件里不再有就地相加
## 每条判据做过反向验证(改坏 → 红 → 逐字节还原), 见方案书决策记录 10-20 那一条。

const Backend := preload("res://scripts/net/backend.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const BP := preload("res://scripts/referee/bot_pool.gd")
const BATTLE := "res://scenes/RealtimeBattle3D.tscn"
const MID := "7a1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
const SEED := 2000023
const GEAR := "p2eq_035"

var _fail := 0
var _n := 0
var _gs


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


## A 方快照(真生产函数 build_ghost_snapshot)。gear = 每只统领第一件换成 3 星 035 齿轮。
func _snap_a(gear: bool) -> Dictionary:
	_gs.reset_dual_lane()
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	var shop: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1 and str((e as Dictionary)["id"]) != GEAR:
			shop.append(str((e as Dictionary)["id"]))
	var k := 0
	var pe := {}
	for pid in _gs.season_leaders:
		var l: Array = []
		if gear:
			l.append({"id": GEAR, "star": 3})
		while l.size() < 3:
			l.append({"id": str(shop[k % shop.size()]), "star": 3})
			k += 1
		pe[pid] = l
	_gs.persistent_equipped = pe
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic"}, {"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone"}, {"kind": "leader", "slot": 2, "id": "bamboo"},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	_gs.season_level = 6
	return Backend.build_ghost_snapshot("g_coins_a", {"name": "甲方", "avatar": "basic", "id": "g_coins_a"})


## B = 服务端机器人池里的一份(与服务端挑中后同形: 补 gl_ts)。
func _snap_b() -> Dictionary:
	var b: Dictionary = BP.one(16, 0, 0, 0)
	b["gl_ts"] = int(P2C.now_utc()) - 300
	return b


func _job(a: Dictionary, b: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify({"v": 1, "job_id": 1, "match_id": MID, "mode": "gauntlet",
		"key": {"week": 1}, "seed": SEED, "client_version": ReplayRecorder.client_version(), "a": a, "b": b}))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	_gs.test_mode = true
	_gs.tutorial_active = false
	_t_single_source()
	## 一个周六中午(时间缝; 用完还原)
	P2C.now_override_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 5 * 86400 + 12 * 3600
	var b := _snap_b()
	_ok("分母: B 是服务端池里的机器人(三统领、分路合法)", (b.get("leaders", []) as Array).size() == 3 and not Backend.ghost_lanes_broken(b))

	# ── K1 裁判 ──
	var res: Dictionary = await RefereeRunner.run(self, _job(_snap_a(true), b))
	_ok("分母 · 裁判算完(ok)", bool(res.get("ok", false)), str(res.get("error", "")))
	if not bool(res.get("ok", false)):
		_finish()
		return
	var coins := int(res.get("coins", -1))
	print("  [量] 裁判: winner=%s steps=%d digest=%s coins=%d" % [str(res["winner"]), int(res["steps"]), str(res["digest"]), coins])
	_ok("★K1 带齿轮 ⇒ 结果单 coins > 0(%d)" % coins, coins > 0)
	_ok("K1 coins 是非负整数(结果单里的类型)", res.get("coins") is int)

	# ── K2 同一局本机跑到结算 ──
	var rec: Dictionary = ReplayRecorder.decode(Marshalls.base64_to_raw(str(res["replay_b64"])))
	_ok("分母 · 裁判的录像解得开、带开打事件", not rec.is_empty() and (rec.get("events", []) as Array).size() > 0)
	var loc: Dictionary = await _local_settle(rec)
	print("  [量] 本机: finished=%s digest=%s reward=%d minted=%d 存档币 +%d" % [str(loc["finished"]), str(loc["digest"]),
		int(loc["reward"]), int(loc["minted"]), int(loc["meta_delta"])])
	_ok("分母 · 本机那一局真打到了结算(resume 模式、_settle_season 跑了)", bool(loc["finished"]) and bool(loc["settled"]))
	_ok("★K2 本机那一局与裁判是同一局(终局指纹相同)", str(loc["digest"]) == str(res["digest"]),
		"%s / %s" % [str(loc["digest"]), str(res["digest"])])
	_ok("★★K2 本机这一局的铸币 = 裁判结果单的 coins(%d / %d)" % [int(loc["minted"]), coins], int(loc["minted"]) == coins)
	_ok("★K2 本机奖励 = 场次币 %d + 铸币 %d" % [P2C.GAUNTLET_COINS_PER_MATCH, coins],
		int(loc["reward"]) == int(P2C.GAUNTLET_COINS_PER_MATCH) + coins, str(loc["reward"]))
	_ok("K2 存档里的币多了同样多", int(loc["meta_delta"]) == int(loc["reward"]))

	# ── K3 客户端按服务器结果记账 ──
	var won := str(res["winner"]) == "a"
	var k3 := _settle_with({"won": 1 if won else 0, "gw": 1 if won else 0, "gl": 0 if won else 1, "coins": coins}, 0, 0)
	_ok("★★K3 RefereeWatch.settle 发的币 = 本机那一局(%d / %d)" % [int(k3["delta"]), int(loc["meta_delta"])],
		int(k3["delta"]) == int(loc["meta_delta"]) and int((k3["view"] as Dictionary).get("coins", -1)) == coins)
	_ok("K3 结算屏口径: reward = 场次币 + coins", int((k3["view"] as Dictionary).get("reward", -1)) == int(P2C.GAUNTLET_COINS_PER_MATCH) + coins)

	# ── K4 客户端不自报 / 不重算 ──
	var k4a := _settle_with({"won": 1, "gw": 1, "gl": 0}, 0, 0)
	_ok("★K4 status 里没有 coins(老服务端)⇒ 只发场次币(不拿本机任何计数补)", int(k4a["delta"]) == int(P2C.GAUNTLET_COINS_PER_MATCH), str(k4a["delta"]))
	var k4b := _settle_with({"won": 1, "gw": 1, "gl": 0, "coins": -5}, 0, 0)
	_ok("K4 coins 负数 ⇒ 当 0", int(k4b["delta"]) == int(P2C.GAUNTLET_COINS_PER_MATCH))
	var st_s := RN.parse_status(true, 200, JSON.stringify({"ok": true, "status": "done", "won": true, "gw": 1, "gl": 0, "coins": "99"}))
	var st_n := RN.parse_status(true, 200, JSON.stringify({"ok": true, "status": "done", "won": true, "gw": 1, "gl": 0, "coins": -4}))
	var st_ok := RN.parse_status(true, 200, JSON.stringify({"ok": true, "status": "done", "won": true, "gw": 1, "gl": 0, "coins": 13}))
	var st_none := RN.parse_status(true, 200, JSON.stringify({"ok": true, "status": "done", "won": true, "gw": 1, "gl": 0, "coins": null}))
	_ok("K4 回包解析: 13 ⇒ 13 / 字符串 ⇒ 0 / 负数 ⇒ 0 / null ⇒ 0", int(st_ok["coins"]) == 13 and int(st_s["coins"]) == 0
		and int(st_n["coins"]) == 0 and int(st_none["coins"]) == 0)
	var k4c := _settle_with({"won": 0, "gw": 0, "gl": 1, "coins": coins}, 0, 0, 0)
	_ok("★K4 已淘汰(0 命)⇒ 一枚不发(含铸币; 与 _settle_season 同一条 is_eliminated)", int(k4c["delta"]) == 0
		and int((k4c["view"] as Dictionary).get("reward", -1)) == 0 and int((k4c["view"] as Dictionary).get("coins", -1)) == coins)
	var src := FileAccess.get_file_as_string("res://scripts/net/referee_net.gd")
	## 2026-10-27 周六交阵容改成进队(gauntlet_queue_join, 旧的 start_body 已删): 量的需求不变 —— 请求体里没有币数这一维
	_ok("K4 交阵容的请求体里没有币数这一维(进队 queue_join_body 键)", not RN.queue_join_body(1, {}, 0).has("p_coins")
		and src.find("\"p_coins\"") < 0)

	# ── K5 对照 ──
	var res0: Dictionary = await RefereeRunner.run(self, _job(_snap_a(false), b))
	_ok("★K5 对照: 不带齿轮 ⇒ coins = 0(%d)" % int(res0.get("coins", -1)), bool(res0.get("ok", false)) and int(res0.get("coins", -1)) == 0)

	P2C.now_override_ts = 0
	_finish()


## K6 单一出口(静态)。
func _t_single_source() -> void:
	var main := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var run := FileAccess.get_file_as_string("res://scripts/referee/referee_runner.gd")
	_ok("分母 · 读得到主文件 / 裁判跑局", main.length() > 10000 and run.length() > 1000)
	_ok("★K6 本机结算读 EquipTickSystem.match_minted(self)", main.count("EquipTickSystem.match_minted(self)") == 1)
	_ok("★K6 裁判结果单读同一个出口", run.find("res[\"coins\"] = EquipTickSystem.match_minted(battle)") >= 0)
	_ok("K6 主文件里不再就地相加铸币(_gadget_syn.minted / gear_minted 不出现)", main.find("_gadget_syn.minted(") < 0
		and main.find("gear_minted()") < 0)


## 拿录像走「中途退出补打」那条复算路: GameState 摆成录像开局那一刻(A 方), 周六口径, 战斗场 resume 模式真打到 `_settle_season`。
func _local_settle(rec: Dictionary) -> Dictionary:
	var backup: Dictionary = ReplayRecorder.capture_all()
	var keep := {"wp": str(_gs.week_phase), "promoted": bool(_gs.promoted), "gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses),
		"coins": int(_gs.meta_deepsea_coins), "wk": int(_gs.week_anchor_ts)}
	ReplayRecorder.apply_state(rec.get("state", {}))
	_gs.week_anchor_ts = P2C.week_anchor_utc(int(P2C.now_utc()))
	_gs.week_phase = P2C.PHASE_GAUNTLET
	_gs.promoted = true
	_gs.gauntlet_wins = 0
	_gs.gauntlet_losses = 0
	_gs.ensure_season()                   # 先把惰性补算吃掉(之后再量币的增量)
	var c0 := int(_gs.meta_deepsea_coins)
	AbandonedMatch.pending_resume = {"rec": rec.duplicate(true), "loss": false, "text": ""}
	var s = (load(BATTLE) as PackedScene).instantiate()
	add_child(s)
	var sub = s.get("_sub")
	if is_instance_valid(sub) and sub is SubViewport:
		(sub as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	var f := 0
	while f < 20000 and not bool(s._replay.finished):
		await get_tree().process_frame
		f += 1
	await get_tree().process_frame
	var out := {"finished": bool(s._replay.finished), "settled": str(s._replay.mode) == "resume" and bool(s.get("_had_season")),
		"digest": str((s._replay.rec.get("end", {}) as Dictionary).get("h", "")),
		"reward": int(s._last_reward), "minted": int(s._last_reward) - int(P2C.GAUNTLET_COINS_PER_MATCH),
		"meta_delta": int(_gs.meta_deepsea_coins) - c0}
	s.queue_free()
	for _i in range(3):
		await get_tree().process_frame
	AbandonedMatch.pending_resume = {}
	for n in backup:
		var v = backup[n]
		_gs.set(str(n), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	_gs.week_phase = keep["wp"]
	_gs.promoted = keep["promoted"]
	_gs.gauntlet_wins = keep["gw"]
	_gs.gauntlet_losses = keep["gl"]
	_gs.meta_deepsea_coins = keep["coins"]
	_gs.week_anchor_ts = keep["wk"]
	return out


## 客户端记账(真函数 RefereeWatch.settle): 摆一张待记账单 → 喂 status → 量币的增量。
func _settle_with(st: Dictionary, gw0: int, gl0: int, hearts: int = -1) -> Dictionary:
	var keep := {"gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses), "coins": int(_gs.meta_deepsea_coins), "hearts": int(_gs.hearts),
		"bt": int(_gs.battles_total), "bw": int(_gs.battles_won), "stb": int(_gs.season_total_battles),
		"mh": (_gs.match_history as Array).duplicate(true), "promoted": bool(_gs.promoted)}
	_gs.promoted = true
	_gs.gauntlet_wins = gw0
	_gs.gauntlet_losses = gl0
	_gs.hearts = hearts if hearts >= 0 else int(P2C.HEARTS_MAX)
	_gs.week_anchor_ts = P2C.week_anchor_utc(int(P2C.now_utc()))
	_gs.referee_pending = {"job_id": 31, "match_id": MID, "week": P2C.week_anchor_utc(int(P2C.now_utc())), "foe": [], "foe_name": ""}
	var c0 := int(_gs.meta_deepsea_coins)
	var v: Dictionary = RW.settle(_gs, 31, st)
	var d := int(_gs.meta_deepsea_coins) - c0
	_gs.gauntlet_wins = keep["gw"]
	_gs.gauntlet_losses = keep["gl"]
	_gs.meta_deepsea_coins = keep["coins"]
	_gs.battles_total = keep["bt"]
	_gs.battles_won = keep["bw"]
	_gs.season_total_battles = keep["stb"]
	_gs.match_history = keep["mh"]
	_gs.promoted = keep["promoted"]
	_gs.hearts = keep["hearts"]
	_gs.referee_pending = {}
	return {"view": v, "delta": d}


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 周六服务器局发战斗内铸币" if _fail == 0 and _n >= 20 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
