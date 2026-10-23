extends Node
## verify_referee_incense.gd — 093 香火石: 对手与服务器裁判局的刻痕 / 充能(2026-10-23 · 方案书 docs/plans/20261023-香火石四个问题.md 的 3)。
##
## 缺口: ①快照不带刻痕 ⇒ 对手的香火石刻痕一律按 0(当初理由「右方是 bot」早不成立);
##       ②裁判机上我方刻痕写死 0, 结果单也不带香火 ⇒ 周末服务器局里刻痕不生效、攒的充能进不了存档。
## 改法: 照宝箱龟(verify_referee_chest)那条链路 —— 快照带 incense_marks / incense_charge, 右方从快照起算,
##   裁判机左方从 A 的快照起算, 结果单带 incense / incense_b, 服务端 20261023 回给客户端, RefereeWatch.apply_incense 写存档。
##
## 判据(全程真入口, 不手算):
##   I1 分母: 真生产函数 build_ghost_snapshot 的快照带着我方起点刻痕 / 充能
##   I2 ★裁判: 结果单 incense 从 A 的起点往前走了(带石头的那只真打了伤害); incense_b ≥ B 快照里的刻痕(不是 0)
##   I3 ★同一局本机复算(「中途退出补打」resume 路)⇒ 终局指纹 = 裁判的; 本机存档的刻痕 / 充能 = 结果单的 incense;
##      ★★对手(右方)单位身上真的吃到了它快照里刻痕给的全队增伤(打别人快照时刻痕生效)
##   I4 ★客户端按服务器记账: status 回包(真解析器)交给 RefereeWatch.settle ⇒ 存档 = 结果单的 incense
##   I5 老服务端 / 坏形状 ⇒ 存档不动; 上一周的单子 ⇒ 不记; 迟到回包不倒退
##   I6 周日: on_finals_coins 同一周的单子记、第二次不重复、上一周不记

const Backend := preload("res://scripts/net/backend.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const BP := preload("res://scripts/referee/bot_pool.gd")
const Inc := preload("res://scripts/systems/equip/incense_stone_system.gd")
const BATTLE := "res://scenes/RealtimeBattle3D.tscn"
const MID := "7a1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4d"
const SEED := 2000023
const M0 := 50          # 我方起点刻痕
const C0 := 3000        # 我方起点充能
const MB := 40          # 对手快照里的刻痕

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


## A 方快照(真生产函数): 上路统领带一块 3★ 香火石, 起点刻痕 M0 / 充能 C0。
func _snap_a() -> Dictionary:
	_gs.reset_dual_lane()
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	var shop: Array = []
	for e in DataRegistry.phase2_equipment:
		var id := str((e as Dictionary)["id"])
		if int((e as Dictionary).get("shopAvailable", 0)) == 1 and id != Inc.EID:
			shop.append(id)
	var k := 0
	var pe := {}
	for pid in _gs.season_leaders:
		var l: Array = []
		if pid == "basic":
			l.append({"id": Inc.EID, "star": 3})
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
	_gs.incense_marks = M0
	_gs.incense_charge = C0
	return Backend.build_ghost_snapshot("g_inc_a", {"name": "甲方", "avatar": "basic", "id": "g_inc_a"})


## B 方: 机器人快照, 但刻痕记成 MB(真人对手攒过香火的形状)。
func _snap_b() -> Dictionary:
	var b: Dictionary = BP.one(16, 0, 0, 0)
	b["gl_ts"] = int(P2C.now_utc()) - 300
	b["incense_marks"] = MB
	b["incense_charge"] = 500
	return b


func _job(a: Dictionary, b: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify({"v": 1, "job_id": 1, "match_id": MID, "mode": "gauntlet",
		"key": {"week": 1}, "seed": SEED, "client_version": ReplayRecorder.client_version(), "a": a, "b": b}))


func _total(m: int, c: int) -> int:
	return m * Inc.PER_MARK + c


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
	var keep0 := {"m": int(_gs.incense_marks), "c": int(_gs.incense_charge)}
	_t_parse()
	_t_bot_and_seed()
	P2C.now_override_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 5 * 86400 + 12 * 3600
	var a := _snap_a()
	_ok("★I1 快照带着我方起点刻痕 %d / 充能 %d(build_ghost_snapshot)" % [M0, C0],
		int(a.get("incense_marks", -1)) == M0 and int(a.get("incense_charge", -1)) == C0,
		"%s / %s" % [str(a.get("incense_marks")), str(a.get("incense_charge"))])

	# ── I2 裁判 ──
	var res: Dictionary = await RefereeRunner.run(self, _job(a, _snap_b()))
	_ok("分母 · 裁判算完(ok)", bool(res.get("ok", false)), str(res.get("error", "")))
	if not bool(res.get("ok", false)):
		_finish()
		return
	var inc: Dictionary = res.get("incense", {})
	var incb: Dictionary = res.get("incense_b", {})
	print("  [量] 裁判: winner=%s incense=%s incense_b=%s" % [str(res["winner"]), str(inc), str(incb)])
	_ok("★I2 结果单带 incense(形状 {marks, charge})", inc.has("marks") and inc.has("charge"), str(inc))
	_ok("★★I2 我方从快照起点(%d 道 + %d)往前走了: %d 道 + %d" % [M0, C0, int(inc.get("marks", 0)), int(inc.get("charge", 0))],
		_total(int(inc.get("marks", 0)), int(inc.get("charge", 0))) > _total(M0, C0))
	_ok("★★I2 对手从它的快照起算: incense_b 刻痕 %d ≥ 快照里的 %d(原来是 0)" % [int(incb.get("marks", 0)), MB],
		int(incb.get("marks", -1)) >= MB, str(incb))
	_ok("I2 结果单里的 incense 经客户端解析器原样认得", RN.parse_incense(inc) == {"marks": int(inc.get("marks", 0)), "charge": int(inc.get("charge", 0))})
	_ok("I2 裁判跑完 GameState 已还原(起点仍是 %d / %d)" % [M0, C0],
		int(_gs.incense_marks) == M0 and int(_gs.incense_charge) == C0, "%d / %d" % [int(_gs.incense_marks), int(_gs.incense_charge)])

	# ── I3 同一局本机复算 ──
	var rec: Dictionary = ReplayRecorder.decode(Marshalls.base64_to_raw(str(res["replay_b64"])))
	_ok("分母 · 裁判的录像解得开、带开打事件", not rec.is_empty() and (rec.get("events", []) as Array).size() > 0)
	var loc: Dictionary = await _local_settle(rec)
	print("  [量] 本机: finished=%s 刻痕 %d / 充能 %d · 对手单位最大增伤 %.3f" % [str(loc["finished"]), int(loc["marks"]), int(loc["charge"]), float(loc["foe_amp"])])
	_ok("分母 · 本机那一局真打到了结算(resume 模式)", bool(loc["finished"]) and bool(loc["settled"]))
	_ok("★I3 本机那一局与裁判是同一局(终局指纹相同)", str(loc["digest"]) == str(res["digest"]),
		"%s / %s" % [str(loc["digest"]), str(res["digest"])])
	_ok("★★I3 本机存档的刻痕 / 充能 = 结果单的 incense(%d+%d / %d+%d)" % [int(loc["marks"]), int(loc["charge"]),
		int(inc.get("marks", -1)), int(inc.get("charge", -1))],
		int(loc["marks"]) == int(inc.get("marks", -1)) and int(loc["charge"]) == int(inc.get("charge", -1)))
	_ok("★★I3 对手单位身上吃到了它快照刻痕给的全队增伤(≥ %d × %.1f%% = %.1f%%)" % [MB, Inc.TEAM_AMP * 100.0, MB * Inc.TEAM_AMP * 100.0],
		float(loc["foe_amp"]) >= MB * Inc.TEAM_AMP - 1e-6, "实测最大 %.3f" % float(loc["foe_amp"]))

	# ── I4 客户端按服务器结果记账 ──
	var won := str(res["winner"]) == "a"
	var body := {"ok": true, "status": "done", "won": won, "gw": 1 if won else 0, "gl": 0 if won else 1, "coins": 0, "incense": inc}
	var st := RN.parse_status(true, 200, JSON.stringify(body))
	_ok("分母 · status 回包解析出了 incense", not (st.get("incense", {}) as Dictionary).is_empty(), str(st.get("incense")))
	var k4 := _settle_with(st, true)
	_ok("★★I4 RefereeWatch.settle 后存档 = 服务器那一局(%d+%d)" % [int(k4["marks"]), int(k4["charge"])],
		int(k4["marks"]) == int(inc.get("marks", -1)) and int(k4["charge"]) == int(inc.get("charge", -1)))
	_ok("I4 分母: settle 真的记了这一单", not (k4["view"] as Dictionary).is_empty())

	# ── I5 老服务端 / 上一周 ──
	body.erase("incense")
	var k5 := _settle_with(RN.parse_status(true, 200, JSON.stringify(body)), true)
	_ok("★I5 status 里没有 incense(老服务端)⇒ 存档不动(仍是起点)",
		int(k5["marks"]) == M0 and int(k5["charge"]) == C0 and not (k5["view"] as Dictionary).is_empty())
	body["incense"] = inc
	var k5b := _settle_with(RN.parse_status(true, 200, JSON.stringify(body)), false)
	_ok("★I5 上一周交的单子 ⇒ 不记", (k5b["view"] as Dictionary).is_empty() and int(k5b["marks"]) == M0)

	# ── I6 周日 ──
	_t_finals()

	P2C.now_override_ts = 0
	_gs.incense_marks = keep0["m"]
	_gs.incense_charge = keep0["c"]
	_finish()


## 机器人 / 种子快照也带这两键(不露馅), 值 0 = 没养香火石。
func _t_bot_and_seed() -> void:
	var b: Dictionary = BP.one(16, 0, 0, 0)
	_ok("I1 机器人快照带两键、值为 0", b.has("incense_marks") and b.has("incense_charge")
		and int(b["incense_marks"]) == 0 and int(b["incense_charge"]) == 0, "%s / %s" % [str(b.get("incense_marks")), str(b.get("incense_charge"))])


## 回包解析(纯函数) + 只往前走(apply_incense)。
func _t_parse() -> void:
	var good := {"marks": 37, "charge": 1234}
	_ok("I5 解析: 合法 ⇒ 原样", RN.parse_incense(good) == good)
	_ok("I5 解析: JSON 里的整数(浮点形态)也认", RN.parse_incense({"marks": 37.0, "charge": 1234.0}) == good)
	_ok("I5 解析: 缺 / null / 不是对象 ⇒ {}", RN.parse_incense(null).is_empty() and RN.parse_incense("x").is_empty()
		and RN.parse_incense({}).is_empty())
	_ok("I5 解析: 负数 / 小数 / 超上限 ⇒ {}", RN.parse_incense({"marks": -1, "charge": 0}).is_empty()
		and RN.parse_incense({"marks": 1.5, "charge": 0}).is_empty()
		and RN.parse_incense({"marks": Inc.MARK_CAP + 1, "charge": 0}).is_empty()
		and RN.parse_incense({"marks": 0, "charge": Inc.PER_MARK + 1}).is_empty())
	var fc := RN.parse_finals_coins(true, 200, JSON.stringify({"ok": true, "status": "done", "coins": 3, "incense": good}))
	_ok("I5 周日回包也解析出 incense", fc.get("incense", {}) == good, str(fc))
	var fc0 := RN.parse_finals_coins(true, 200, JSON.stringify({"ok": true, "status": "done", "coins": 3}))
	_ok("I5 周日老回包(没有 incense)⇒ {}", (fc0.get("incense", {1: 1}) as Dictionary).is_empty())
	## 只往前走: 刻痕多 ⇒ 两个都换; 一样 ⇒ 充能取大; 少 ⇒ 不动(迟到的回包不能把进度倒退回去)
	var keep := {"m": int(_gs.incense_marks), "c": int(_gs.incense_charge)}
	_gs.incense_marks = 10
	_gs.incense_charge = 3000
	var c1 := RW.apply_incense(_gs, {"marks": 11, "charge": 100})
	_ok("I5 刻痕多 ⇒ 刻痕与充能都换成服务器的(11 / 100)", c1 and int(_gs.incense_marks) == 11 and int(_gs.incense_charge) == 100)
	var c2 := RW.apply_incense(_gs, {"marks": 11, "charge": 50})
	_ok("I5 刻痕一样、充能更少 ⇒ 不动", not c2 and int(_gs.incense_charge) == 100)
	var c3 := RW.apply_incense(_gs, {"marks": 9, "charge": 3999})
	_ok("I5 刻痕更少(迟到回包)⇒ 不动", not c3 and int(_gs.incense_marks) == 11 and int(_gs.incense_charge) == 100)
	_gs.incense_marks = keep["m"]
	_gs.incense_charge = keep["c"]


## 周日: on_finals_coins(真函数)按单子记香火。
func _t_finals() -> void:
	var keep := {"coins": int(_gs.meta_deepsea_coins), "l": (_gs.finals_coins_pending as Array).duplicate(true),
		"m": int(_gs.incense_marks), "c": int(_gs.incense_charge)}
	var wk := P2C.week_anchor_utc(int(P2C.now_utc()))
	var t := {"week": wk, "bucket": 3, "round": 1, "match": 0}
	_gs.finals_coins_pending = [t.duplicate()]
	_gs.incense_marks = 5
	_gs.incense_charge = 0
	var res := {"err": "", "status": "done", "coins": 2, "incense": {"marks": 77, "charge": 2222}}
	var n1 := RW.on_finals_coins(t, res)
	_ok("★I6 同一周的单子 ⇒ 记进存档(77 / 2222)", n1 >= 0 and int(_gs.incense_marks) == 77 and int(_gs.incense_charge) == 2222,
		"n=%d %d/%d" % [n1, int(_gs.incense_marks), int(_gs.incense_charge)])
	_gs.incense_marks = 5
	_gs.incense_charge = 0
	var n2 := RW.on_finals_coins(t, res)
	_ok("★I6 同一张单子第二次(已发过)⇒ 不重复记", n2 == -1 and int(_gs.incense_marks) == 5, "n=%d" % n2)
	var t_old := {"week": wk - 7 * 86400, "bucket": 4, "round": 1, "match": 0}
	_gs.finals_coins_pending = [t_old.duplicate()]
	var n3 := RW.on_finals_coins(t_old, res)
	_ok("★I6 上一周的单子 ⇒ 币照发但香火不记", n3 >= 0 and int(_gs.incense_marks) == 5, "n=%d %d" % [n3, int(_gs.incense_marks)])
	_gs.meta_deepsea_coins = keep["coins"]
	_gs.finals_coins_pending = keep["l"]
	_gs.incense_marks = keep["m"]
	_gs.incense_charge = keep["c"]


## 拿录像走「中途退出补打」那条复算路(同 verify_referee_chest._local_settle), 量本机存档里的香火 + 对手单位的增伤。
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
	var foe_amp := 0.0
	while f < 20000 and not bool(s._replay.finished):
		await get_tree().process_frame
		f += 1
		if f % 30 == 0:
			for u in s._units:
				if u is Dictionary and str((u as Dictionary).get("side", "")) == "right" and bool((u as Dictionary).get("alive", false)) \
						and not bool((u as Dictionary).get("_isEgg", false)):
					foe_amp = maxf(foe_amp, float((u as Dictionary).get("damage_amp", 0.0)))
	await get_tree().process_frame
	var out := {"finished": bool(s._replay.finished), "settled": str(s._replay.mode) == "resume" and bool(s.get("_had_season")),
		"digest": str((s._replay.rec.get("end", {}) as Dictionary).get("h", "")),
		"marks": int(_gs.incense_marks), "charge": int(_gs.incense_charge), "foe_amp": foe_amp}
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


## 客户端记账(真函数 RefereeWatch.settle): 存档摆回起点 → 摆一张待记账单 → 喂 status → 量香火。
func _settle_with(st: Dictionary, this_week: bool) -> Dictionary:
	var keep := {"gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses), "coins": int(_gs.meta_deepsea_coins), "hearts": int(_gs.hearts),
		"bt": int(_gs.battles_total), "bw": int(_gs.battles_won), "stb": int(_gs.season_total_battles),
		"mh": (_gs.match_history as Array).duplicate(true), "promoted": bool(_gs.promoted)}
	_gs.incense_marks = M0
	_gs.incense_charge = C0
	_gs.promoted = true
	_gs.gauntlet_wins = 0
	_gs.gauntlet_losses = 0
	_gs.hearts = int(P2C.HEARTS_MAX)
	_gs.week_anchor_ts = P2C.week_anchor_utc(int(P2C.now_utc()))
	var wk: int = P2C.week_anchor_utc(int(P2C.now_utc())) - (0 if this_week else 7 * 86400)
	_gs.referee_pending = {"job_id": 41, "match_id": MID, "week": wk, "foe": [], "foe_name": ""}
	var v: Dictionary = RW.settle(_gs, 41, st)
	var out := {"view": v, "marks": int(_gs.incense_marks), "charge": int(_gs.incense_charge)}
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
	_gs.incense_marks = M0
	_gs.incense_charge = C0
	return out


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 香火石: 对手与服务器局的刻痕" if _fail == 0 and _n >= 28 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
