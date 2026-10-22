extends Node
## verify_referee_chest.gd — 服务器裁判局的宝箱龟进度回写存档(2026-10-22 · 方案书 docs/plans/20261022-宝箱龟整条链路修复.md 的 A)。
##
## 缺口: 周六闯关 / 周日决赛由裁判机算, 裁判机上宝箱龟照样攒财宝值、开箱, 但结果单不带宝箱、客户端记账也不碰
##   ⇒ 这些局的宝箱进度永远进不了存档(用户「宝箱整个是不是有bug啊」)。
## 改法: 照战斗内铸币 coins / coins_b 的通路 —— 裁判结果单带 `chest` / `chest_b`(ChestSystem.ledger_final),
##   服务端回给客户端(20261022b), `RefereeWatch.apply_chest` 写进存档。
##
## 判据(全程真入口, 不手算):
##   K1 分母: 我方带宝箱龟、起点 2800 ⇒ 裁判结果单 chest.value > 2800(攒到了); chest_b = B 的起点(机器人 0 / 空)
##   K2 ★同一局本机复算(「中途退出补打」resume 路)⇒ 终局指纹 = 裁判的; 本机存档的宝箱进度 = 结果单的 chest(逐个相同)
##   K3 ★客户端按服务器记账: status 回包(真解析器 RN.parse_status)交给 RefereeWatch.settle ⇒ 存档 = 结果单的 chest
##   K4 老服务端 / 坏形状: status 没有 chest ⇒ 存档不动; chest 形状不对(值为负 / won 不是字符串 / 超 5 件)⇒ 解析成 {}
##   K5 上一周的待记账单 ⇒ 不记(换周大轮已清零, 不能被迟到的回包写回去)
##   K6 周日: on_finals_coins 同一周的单子 ⇒ A / B 各记自己那份(侧由服务端认); 同一张单子第二次 ⇒ 不重复记; 上一周的单子 ⇒ 不记
##   K7 单一出口: 结果单读 ChestSystem.ledger_final(与本机记账同一本账)

const Backend := preload("res://scripts/net/backend.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const BP := preload("res://scripts/referee/bot_pool.gd")
const BATTLE := "res://scenes/RealtimeBattle3D.tscn"
const MID := "7a1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4c"
const SEED := 2000023
const BASE := 2800.0

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


## A 方快照(真生产函数 build_ghost_snapshot): 三统领里带宝箱龟, 起点财宝值 BASE、还没开过箱。
func _snap_a() -> Dictionary:
	_gs.reset_dual_lane()
	_gs.season_leaders = ["chest", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	var shop: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			shop.append(str((e as Dictionary)["id"]))
	var k := 0
	var pe := {}
	for pid in _gs.season_leaders:
		var l: Array = []
		while l.size() < 3:
			l.append({"id": str(shop[k % shop.size()]), "star": 3})
			k += 1
		pe[pid] = l
	_gs.persistent_equipped = pe
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "chest"}, {"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone"}, {"kind": "leader", "slot": 2, "id": "bamboo"},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	_gs.season_level = 6
	_gs.chest_treasure_value = BASE
	_gs.chest_treasures_won = []
	return Backend.build_ghost_snapshot("g_chest_a", {"name": "甲方", "avatar": "chest", "id": "g_chest_a"})


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
	_t_parse()
	## 一个周六中午(时间缝; 用完还原)
	P2C.now_override_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 5 * 86400 + 12 * 3600
	var a := _snap_a()
	_ok("分母: A 快照带着起点财宝值 %.0f" % BASE, float(a.get("chest_treasure_value", -1.0)) == BASE, str(a.get("chest_treasure_value")))

	# ── K1 裁判 ──
	var res: Dictionary = await RefereeRunner.run(self, _job(a, _snap_b()))
	_ok("分母 · 裁判算完(ok)", bool(res.get("ok", false)), str(res.get("error", "")))
	if not bool(res.get("ok", false)):
		_finish()
		return
	var ch: Dictionary = res.get("chest", {})
	var chb: Dictionary = res.get("chest_b", {})
	print("  [量] 裁判: winner=%s digest=%s chest=%s chest_b=%s" % [str(res["winner"]), str(res["digest"]), str(ch), str(chb)])
	_ok("★K1 结果单带 chest(形状 {value, won})", ch.has("value") and ch.has("won") and ch["won"] is Array, str(ch))
	_ok("★★K1 我方宝箱龟这一局攒到了: value %.0f > 起点 %.0f" % [float(ch.get("value", 0.0)), BASE], float(ch.get("value", 0.0)) > BASE)
	_ok("K1 B 方没有宝箱龟 ⇒ chest_b = B 的起点(机器人 0 / 空)", float(chb.get("value", -1.0)) == 0.0
		and (chb.get("won", [1]) as Array).is_empty(), str(chb))
	_ok("K1 结果单里的 chest 经客户端解析器原样认得(RN.parse_chest)", RN.parse_chest(ch) == {"value": float(ch.get("value", 0.0)),
		"won": ch.get("won", [])})
	_ok("K1 裁判跑完 GameState 已还原(起点仍是 %.0f)" % BASE, float(_gs.chest_treasure_value) == BASE, str(_gs.chest_treasure_value))

	# ── K2 同一局本机复算 ──
	var rec: Dictionary = ReplayRecorder.decode(Marshalls.base64_to_raw(str(res["replay_b64"])))
	_ok("分母 · 裁判的录像解得开、带开打事件", not rec.is_empty() and (rec.get("events", []) as Array).size() > 0)
	var loc: Dictionary = await _local_settle(rec)
	print("  [量] 本机: finished=%s digest=%s 宝箱 %.0f / %s" % [str(loc["finished"]), str(loc["digest"]), float(loc["value"]), str(loc["won"])])
	_ok("分母 · 本机那一局真打到了结算(resume 模式)", bool(loc["finished"]) and bool(loc["settled"]))
	_ok("★K2 本机那一局与裁判是同一局(终局指纹相同)", str(loc["digest"]) == str(res["digest"]),
		"%s / %s" % [str(loc["digest"]), str(res["digest"])])
	_ok("★★K2 本机存档的财宝值 = 结果单的 chest.value(%.0f / %.0f)" % [float(loc["value"]), float(ch.get("value", 0.0))],
		float(loc["value"]) == float(ch.get("value", -1.0)))
	_ok("★★K2 本机存档的已开战利品 = 结果单的 chest.won(%s / %s)" % [str(loc["won"]), str(ch.get("won", []))],
		loc["won"] == ch.get("won", []))

	# ── K3 客户端按服务器结果记账 ──
	var won := str(res["winner"]) == "a"
	var body := {"ok": true, "status": "done", "won": won, "gw": 1 if won else 0, "gl": 0 if won else 1, "coins": 0, "chest": ch}
	var st := RN.parse_status(true, 200, JSON.stringify(body))
	_ok("分母 · status 回包解析出了 chest", not (st.get("chest", {}) as Dictionary).is_empty(), str(st.get("chest")))
	var k3 := _settle_with(st, true)
	_ok("★★K3 RefereeWatch.settle 后存档的财宝值 = 服务器那一局(%.0f / %.0f)" % [float(k3["value"]), float(ch.get("value", 0.0))],
		float(k3["value"]) == float(ch.get("value", -1.0)))
	_ok("★★K3 存档的已开战利品 = 服务器那一局", k3["won"] == ch.get("won", []), str(k3["won"]))
	_ok("K3 分母: settle 真的记了这一单(回了结算屏口径)", not (k3["view"] as Dictionary).is_empty())

	# ── K4 老服务端 / 坏形状 ──
	body.erase("chest")
	var k4 := _settle_with(RN.parse_status(true, 200, JSON.stringify(body)), true)
	_ok("★K4 status 里没有 chest(老服务端 / 老裁判程序)⇒ 存档不动(仍是起点 %.0f / 空)" % BASE,
		float(k4["value"]) == BASE and (k4["won"] as Array).is_empty() and not (k4["view"] as Dictionary).is_empty())

	# ── K5 上一周的单子 ──
	body["chest"] = ch
	var k5 := _settle_with(RN.parse_status(true, 200, JSON.stringify(body)), false)
	_ok("★K5 上一周交的单子 ⇒ 不记(settle 回 {}、存档不动)", (k5["view"] as Dictionary).is_empty() and float(k5["value"]) == BASE)

	# ── K6 周日 ──
	_t_finals()

	P2C.now_override_ts = 0
	_finish()


## K7 单一出口(静态)。
func _t_single_source() -> void:
	var run := FileAccess.get_file_as_string("res://scripts/referee/referee_runner.gd")
	var chest := FileAccess.get_file_as_string("res://scripts/systems/skills/chest_system.gd")
	_ok("分母 · 读得到裁判跑局 / 宝箱系统", run.length() > 1000 and chest.length() > 1000)
	_ok("★K7 结果单的 chest / chest_b 读 ChestSystem.ledger_final(与本机记账同一本账)",
		run.find("battle._chest_sys.ledger_final(side)") >= 0 and run.find("res[\"chest\"] = _chest_of(battle, \"left\")") >= 0
		and run.find("res[\"chest_b\"] = _chest_of(battle, \"right\")") >= 0 and chest.find("func ledger_final(") >= 0)


## K4 回包解析(纯函数)。
func _t_parse() -> void:
	var good := {"value": 4521.0, "won": ["wood_shield"]}
	_ok("K4 解析: 合法 ⇒ 原样", RN.parse_chest(good) == good)
	_ok("K4 解析: 整数值也认(JSON 里 4521)", RN.parse_chest({"value": 4521, "won": []}) == {"value": 4521.0, "won": []})
	_ok("K4 解析: 缺 / null / 不是对象 ⇒ {}", RN.parse_chest(null).is_empty() and RN.parse_chest("x").is_empty()
		and RN.parse_chest({}).is_empty())
	_ok("K4 解析: 值为负 ⇒ {}", RN.parse_chest({"value": -1.0, "won": []}).is_empty())
	_ok("K4 解析: won 里有不是字符串的 ⇒ {}", RN.parse_chest({"value": 1.0, "won": [3]}).is_empty())
	_ok("K4 解析: 超过 %d 件 ⇒ {}" % ChestSystem.CHEST_MAX_OPEN,
		RN.parse_chest({"value": 1.0, "won": ["a", "b", "c", "d", "e", "f"]}).is_empty())
	var fc := RN.parse_finals_coins(true, 200, JSON.stringify({"ok": true, "status": "done", "coins": 3, "chest": good}))
	_ok("K4 周日回包也解析出 chest", fc.get("chest", {}) == good, str(fc))
	var fc0 := RN.parse_finals_coins(true, 200, JSON.stringify({"ok": true, "status": "done", "coins": 3}))
	_ok("K4 周日老回包(没有 chest)⇒ chest = {}", (fc0.get("chest", {1: 1}) as Dictionary).is_empty())


## K6 周日: on_finals_coins(真函数)按单子记宝箱进度。
func _t_finals() -> void:
	var keep := {"coins": int(_gs.meta_deepsea_coins), "l": (_gs.finals_coins_pending as Array).duplicate(true),
		"v": float(_gs.chest_treasure_value), "w": (_gs.chest_treasures_won as Array).duplicate()}
	var wk := P2C.week_anchor_utc(int(P2C.now_utc()))
	var t := {"week": wk, "bucket": 3, "round": 1, "match": 0}
	_gs.finals_coins_pending = [t.duplicate()]
	_gs.chest_treasure_value = 100.0
	_gs.chest_treasures_won = []
	var res := {"err": "", "status": "done", "coins": 2, "chest": {"value": 3333.0, "won": ["dagger"]}}
	var n1 := RW.on_finals_coins(t, res)
	_ok("★K6 同一周的单子 ⇒ 记进存档(3333 / [dagger])", n1 >= 0 and float(_gs.chest_treasure_value) == 3333.0
		and _gs.chest_treasures_won == ["dagger"], "n=%d %.0f %s" % [n1, float(_gs.chest_treasure_value), str(_gs.chest_treasures_won)])
	_gs.chest_treasure_value = 100.0
	_gs.chest_treasures_won = []
	var n2 := RW.on_finals_coins(t, res)
	_ok("★K6 同一张单子第二次(已发过)⇒ 不重复记", n2 == -1 and float(_gs.chest_treasure_value) == 100.0, "n=%d" % n2)
	var t_old := {"week": wk - 7 * 86400, "bucket": 4, "round": 1, "match": 0}
	_gs.finals_coins_pending = [t_old.duplicate()]
	var n3 := RW.on_finals_coins(t_old, res)
	_ok("★K6 上一周的单子 ⇒ 币照发(既有口径)但宝箱进度不记", n3 >= 0 and float(_gs.chest_treasure_value) == 100.0,
		"n=%d %.0f" % [n3, float(_gs.chest_treasure_value)])
	_gs.meta_deepsea_coins = keep["coins"]
	_gs.finals_coins_pending = keep["l"]
	_gs.chest_treasure_value = keep["v"]
	_gs.chest_treasures_won = keep["w"]


## 拿录像走「中途退出补打」那条复算路(同 verify_referee_coins._local_settle), 量本机存档里的宝箱进度。
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
	_gs.ensure_season()
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
		"value": float(_gs.chest_treasure_value), "won": (_gs.chest_treasures_won as Array).duplicate()}
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


## 客户端记账(真函数 RefereeWatch.settle): 存档摆回起点 → 摆一张待记账单 → 喂 status → 量宝箱进度。
##   this_week = false ⇒ 单子标成上一周交的。
func _settle_with(st: Dictionary, this_week: bool) -> Dictionary:
	var keep := {"gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses), "coins": int(_gs.meta_deepsea_coins), "hearts": int(_gs.hearts),
		"bt": int(_gs.battles_total), "bw": int(_gs.battles_won), "stb": int(_gs.season_total_battles),
		"mh": (_gs.match_history as Array).duplicate(true), "promoted": bool(_gs.promoted)}
	_gs.chest_treasure_value = BASE
	_gs.chest_treasures_won = []
	_gs.promoted = true
	_gs.gauntlet_wins = 0
	_gs.gauntlet_losses = 0
	_gs.hearts = int(P2C.HEARTS_MAX)
	_gs.week_anchor_ts = P2C.week_anchor_utc(int(P2C.now_utc()))
	var wk: int = P2C.week_anchor_utc(int(P2C.now_utc())) - (0 if this_week else 7 * 86400)
	_gs.referee_pending = {"job_id": 41, "match_id": MID, "week": wk, "foe": [], "foe_name": ""}
	var v: Dictionary = RW.settle(_gs, 41, st)
	var out := {"view": v, "value": float(_gs.chest_treasure_value), "won": (_gs.chest_treasures_won as Array).duplicate()}
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
	_gs.chest_treasure_value = BASE
	_gs.chest_treasures_won = []
	return out


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 服务器局宝箱龟进度回写存档" if _fail == 0 and _n >= 25 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
