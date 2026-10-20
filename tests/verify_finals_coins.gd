extends Node
## verify_finals_coins.gd — 周日决赛服务器局照常发战斗内铸币(2026-10-20 · 方案书 docs/plans/20261019-服务器裁判.md R8)。
##
## 缺口: 本机打(老路)时 `_settle_season` 把奇械羁绊铸币 + 035 黄铜齿轮加进奖励; 服务器算的周日局一枚都没发 ——
##   结果单只带左方(A)的 `coins`, 右方(B)没人算; 周日客户端也不查任务, 连 A 那一份也没人取。
## 改法: 裁判结果单多带 `coins_b`(右方, 同一个出口 `EquipTickSystem.match_minted(battle, "right")`) ⇒ 服务端记账本 ⇒
##   双方客户端点开自己那一场时记待取单(`RefereeWatch.finals_seal`), 翻面后问 `referee_finals_coins`(服务端按账号认侧), 按回包发。
##
## 判据(全程真入口, 不手算):
##   F1 分母: 周日任务单(mode = finals), 两侧各带齿轮(A 三件 3 星 / B 两件 1~2 星)⇒ 结果单 coins > 0、coins_b > 0, 都是整数
##   F2 ★同一局本机跑: 拿裁判录像走「中途退出补打」复算路真打到 `_settle_season`(终局指纹 = 裁判的):
##      本机奖励里的铸币 = coins(逐枚相同); 本机右方这一局的铸币 = coins_b(右方逐帧读同一个出口, 左方同法读出来 = 本机结算那个数 ⇒ 读法本身对)
##   F3 ★双方客户端按服务器记账: A 记 coins、B 记 coins_b(真函数 finals_seal → on_finals_coins), 同一张单子再来一次不重复发;
##      没翻面(pending)/ 问不到 ⇒ 不发、单子留着; 出局那一局 ⇒ 一枚不发; 与我无关(not_in_match)⇒ 销单不发
##   F4 客户端不自报 / 老服务端兼容: 请求体只有四个坐标(没有币数、没有侧); 回包缺 coins / 负数 / 字符串 ⇒ 0; 404 ⇒ 留着
##   F5 对照: 两侧都不带齿轮 ⇒ coins = coins_b = 0
##   F6 单一出口 + 接线(静态): 裁判写 coins_b 读同一个出口; 对阵图点开自己那一场把周号交给 finals_seal;
##      对阵图 / 主菜单都调 claim_finals_coins; 迁移 20261020d 逐字在 schema.sql 里(只一次)、键名与客户端一致
## 每条判据做过反向验证(改坏 → 红 → 逐字节还原), 见方案书决策记录 10-20 那一条。

const Backend := preload("res://scripts/net/backend.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const BATTLE := "res://scenes/RealtimeBattle3D.tscn"
const MID := "5b2c7d1e-3f4a-4b6c-8d9e-0a1b2c3d4e5f"
const SEED := 3100041
const GEAR := "p2eq_035"
const MIG := "res://server/supabase/migrations/20261020d_finals_coins.sql"
const SCHEMA := "res://server/supabase/schema.sql"
const MARK_BEGIN := "-- >>> BEGIN finals_coins 20261020d >>>"
const MARK_END := "-- <<< END finals_coins 20261020d <<<"
const WEEK := 1760918400

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


## 一份快照(真生产函数 build_ghost_snapshot)。`gear` = 每只统领第一件换成几星齿轮(0 = 不带)。
func _snap(leaders: Array, gear: Array, nm: String) -> Dictionary:
	_gs.reset_dual_lane()
	_gs.season_leaders = leaders.duplicate()
	_gs.left_team.assign(_gs.season_leaders)
	var shop: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1 and str((e as Dictionary)["id"]) != GEAR:
			shop.append(str((e as Dictionary)["id"]))
	var k := 0
	var pe := {}
	for i in range(leaders.size()):
		var l: Array = []
		if int(gear[i]) > 0:
			l.append({"id": GEAR, "star": int(gear[i])})
		while l.size() < 3:
			l.append({"id": str(shop[k % shop.size()]), "star": 3})
			k += 1
		pe[leaders[i]] = l
	_gs.persistent_equipped = pe
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": leaders[0]}, {"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": leaders[1]}, {"kind": "leader", "slot": 2, "id": leaders[2]},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	_gs.season_level = 6
	return Backend.build_ghost_snapshot("g_" + nm, {"name": nm, "avatar": str(leaders[0]), "id": "g_" + nm})


func _job(a: Dictionary, b: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify({"v": 1, "job_id": 7, "match_id": MID, "mode": "finals",
		"key": {"week": WEEK, "bucket": 0, "round": 1, "match": 0}, "seed": SEED,
		"client_version": ReplayRecorder.client_version(), "a": a, "b": b}))


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
	_t_static()
	_t_parse()
	P2C.now_override_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 6 * 86400 + 12 * 3600   # 一个周日中午
	var a := _snap(["basic", "stone", "bamboo"], [3, 3, 3], "amy")
	var b := _snap(["ninja", "dice", "pirate"], [1, 2, 0], "hal")

	# ── F1 裁判 ──
	var res: Dictionary = await RefereeRunner.run(self, _job(a, b))
	_ok("分母 · 裁判算完(ok)", bool(res.get("ok", false)), str(res.get("error", "")))
	if not bool(res.get("ok", false)):
		_finish()
		return
	var ca := int(res.get("coins", -1))
	var cb := int(res.get("coins_b", -1))
	print("  [量] 裁判: winner=%s steps=%d digest=%s coins=%d coins_b=%d" % [str(res["winner"]), int(res["steps"]), str(res["digest"]), ca, cb])
	_ok("★F1 A(左)带齿轮 ⇒ coins > 0(%d)" % ca, ca > 0)
	_ok("★F1 B(右)带齿轮 ⇒ coins_b > 0(%d)" % cb, cb > 0)
	_ok("F1 coins / coins_b 都是整数(结果单里的类型)", res.get("coins") is int and res.get("coins_b") is int)
	_ok("F1 两侧的数不是同一个读数(A 三件 3 星 / B 两件低星)", ca != cb, "%d / %d" % [ca, cb])

	# ── F2 同一局本机跑 ──
	var rec: Dictionary = ReplayRecorder.decode(Marshalls.base64_to_raw(str(res["replay_b64"])))
	_ok("分母 · 裁判的录像解得开、带开打事件", not rec.is_empty() and (rec.get("events", []) as Array).size() > 0)
	var loc: Dictionary = await _local_settle(rec)
	print("  [量] 本机: finished=%s digest=%s reward=%d minted=%d 左方逐帧最大=%d 右方逐帧最大=%d" % [str(loc["finished"]),
		str(loc["digest"]), int(loc["reward"]), int(loc["minted"]), int(loc["max_l"]), int(loc["max_r"])])
	_ok("分母 · 本机那一局真打到了结算(resume 模式、_settle_season 跑了)", bool(loc["finished"]) and bool(loc["settled"]))
	_ok("★F2 本机那一局与裁判是同一局(终局指纹相同)", str(loc["digest"]) == str(res["digest"]),
		"%s / %s" % [str(loc["digest"]), str(res["digest"])])
	_ok("★★F2 A: 本机结算的铸币 = 结果单 coins(%d / %d)" % [int(loc["minted"]), ca], int(loc["minted"]) == ca)
	_ok("F2 读法标定: 左方逐帧读出口的最大值 = 本机结算那个数(%d / %d)" % [int(loc["max_l"]), int(loc["minted"])],
		int(loc["max_l"]) == int(loc["minted"]))
	_ok("★★F2 B: 本机这一局右方的铸币 = 结果单 coins_b(%d / %d)" % [int(loc["max_r"]), cb], int(loc["max_r"]) == cb)
	_ok("F2 本机结算后两侧都归零(整场结束清账, 下一场不串)", int(loc["after_l"]) == 0 and int(loc["after_r"]) == 0)

	# ── F3 双方客户端按服务器记账 ──
	var fa := _client_flow(ca)
	_ok("★★F3 A 的客户端: 翻面后发 coins(%d / %d)" % [int(fa["delta"]), ca], int(fa["delta"]) == ca and int(fa["n"]) == ca)
	_ok("F3 A 的待取单在点开那一刻记下(四个坐标 + 未发)", bool(fa["ticket_ok"]))
	_ok("★F3 同一张单子再来一次不重复发(-1、币不动)", int(fa["again_n"]) == -1 and int(fa["again_delta"]) == 0)
	_ok("F3 没翻面(pending)/ 问不到 ⇒ 不发、单子留着", bool(fa["pending_kept"]))
	_ok("F3 同一场再点一次不重记单子(还是一张)", int(fa["tickets"]) == 1)
	var fb := _client_flow(cb)
	_ok("★★F3 B 的客户端: 翻面后发 coins_b(%d / %d)" % [int(fb["delta"]), cb], int(fb["delta"]) == cb and int(fb["n"]) == cb)
	var fe := _client_flow(ca, 0)
	_ok("★F3 已淘汰(0 命)⇒ 一枚不发(与 _settle_season 同一条 is_eliminated), 单子销掉", int(fe["delta"]) == 0 and int(fe["n"]) == 0)
	var fx := _client_flow(ca, -1, {"err": "not_in_match"})
	_ok("F3 服务端说与我无关(not_in_match)⇒ 销单、不发", int(fx["delta"]) == 0 and int(fx["n"]) == 0)
	var fo := _client_flow(ca, -1, {"err": "unavailable"})
	_ok("F4 服务端没上迁移(404 ⇒ unavailable)⇒ 留着、不发", int(fo["delta"]) == 0 and int(fo["n"]) == -1)
	var fw := _client_flow(ca, -1, {}, -1)
	_ok("F3 没有周号(老调用)⇒ 不记单子(不会拿错的周去问)", int(fw["tickets"]) == 0)

	# ── F5 对照 ──
	var a0 := _snap(["basic", "stone", "bamboo"], [0, 0, 0], "amy")
	var b0 := _snap(["ninja", "dice", "pirate"], [0, 0, 0], "hal")
	var res0: Dictionary = await RefereeRunner.run(self, _job(a0, b0))
	_ok("★F5 对照: 两侧都不带齿轮 ⇒ coins = coins_b = 0(%d / %d)" % [int(res0.get("coins", -1)), int(res0.get("coins_b", -1))],
		bool(res0.get("ok", false)) and int(res0.get("coins", -1)) == 0 and int(res0.get("coins_b", -1)) == 0)

	P2C.now_override_ts = 0
	_finish()


## F6 静态: 单一出口 + 接线 + SQL 对账。
func _t_static() -> void:
	var run := FileAccess.get_file_as_string("res://scripts/referee/referee_runner.gd")
	var bm := FileAccess.get_file_as_string("res://scripts/scenes/BracketMapScene.gd")
	var mm := FileAccess.get_file_as_string("res://scripts/scenes/MainMenuScene.gd")
	var et := FileAccess.get_file_as_string("res://scripts/systems/equip/equip_tick_system.gd")
	_ok("分母 · 读得到裁判跑局 / 对阵图 / 主菜单 / 装备 tick", run.length() > 1000 and bm.length() > 10000 and mm.length() > 10000 and et.length() > 10000)
	_ok("★F6 裁判结果单 coins_b 读同一个出口(右方)", run.find("res[\"coins_b\"] = EquipTickSystem.match_minted(battle, \"right\")") >= 0)
	_ok("★F6 出口两侧都算: 奇械 + 齿轮都按 side 取", et.find("battle._gadget_syn.minted(side)) + int(battle._equip_tick_sys.gear_minted(side))") >= 0)
	_ok("★F6 对阵图点开自己那一场把周号交给 finals_seal", bm.find("_RW.finals_seal(GameState, int(lv.get(\"bucket\", -1)), r, m, feed_week())") >= 0)
	_ok("★F6 对阵图 / 主菜单都调 claim_finals_coins", bm.find("_RW.claim_finals_coins(") >= 0 and mm.find(".claim_finals_coins(") >= 0)
	var mig := FileAccess.get_file_as_string(MIG)
	var sch := FileAccess.get_file_as_string(SCHEMA)
	_ok("分母 · 迁移文件与 schema.sql 都读得到", mig.length() > 1000 and sch.length() > 10000)
	var seg := _seg(mig)
	_ok("★F6 迁移首尾标记各一; schema.sql 里同一段逐字相同、只出现一次", seg != "" and mig.count(MARK_BEGIN) == 1 and mig.count(MARK_END) == 1
		and sch.count(MARK_BEGIN) == 1 and _seg(sch) == seg)
	var a0 := sch.find(MARK_BEGIN)
	_ok("★F6 schema.sql 里最后一个 referee_complete 定义落在本段内(整份重放时生效的是记 coins_b 的版本)",
		a0 > 0 and sch.rfind("create or replace function public.referee_complete(") > a0)
	var rc := _fn(seg, "referee_complete")
	_ok("F6 写回读结果单的键 = 裁判写的键(coins_b)、夹 0..999",
		rc.find("p_result->'coins_b'") >= 0 and rc.find("(p_result->>'coins_b')::numeric between 0 and 999") >= 0)
	var fc := _fn(seg, "referee_finals_coins")
	_ok("F6 查币接口: 形参 = 客户端请求体的四个键", seg.find("referee_finals_coins(p_week bigint, p_bucket int, p_round int, p_match int)") >= 0
		and RN.finals_coins_body(1, 2, 3, 4).keys() == ["p_week", "p_bucket", "p_round", "p_match"])
	_ok("F6 查币接口: 回的 status 只有 pending / done(= 客户端认的两个)、侧由 auth.uid() 认",
		fc.find("'status', 'pending'") >= 0 and fc.find("'status', 'done'") >= 0 and fc.find("auth.uid()") >= 0
		and fc.find("'coins' else 'coins_b'") >= 0)
	_ok("F6 查币接口: 不剧透判据与 finals_view 同一条(closed or round < 当前轮)", fc.find("b.closed or p_round < b.round") >= 0)
	_ok("F6 查币接口只给 authenticated", seg.find("grant execute on function public.referee_finals_coins(bigint, int, int, int) to authenticated;") >= 0
		and seg.find("revoke all on function public.referee_finals_coins(bigint, int, int, int) from public, anon;") >= 0)


## F4 回包解析(纯函数)。
func _t_parse() -> void:
	var ok7 := RN.parse_finals_coins(true, 200, JSON.stringify({"ok": true, "status": "done", "coins": 7}))
	var pend := RN.parse_finals_coins(true, 200, JSON.stringify({"ok": true, "status": "pending"}))
	var s := RN.parse_finals_coins(true, 200, JSON.stringify({"ok": true, "status": "done", "coins": "9"}))
	var neg := RN.parse_finals_coins(true, 200, JSON.stringify({"ok": true, "status": "done", "coins": -4}))
	var nul := RN.parse_finals_coins(true, 200, JSON.stringify({"ok": true, "status": "done", "coins": null}))
	var odd := RN.parse_finals_coins(true, 200, JSON.stringify({"ok": true, "status": "weird", "coins": 5}))
	var nf := RN.parse_finals_coins(true, 404, "")
	var off := RN.parse_finals_coins(false, 0, "")
	var why := RN.parse_finals_coins(true, 200, JSON.stringify({"ok": false, "reason": "not_in_match"}))
	_ok("★F4 回包解析: done 7 ⇒ 7 / pending 不带数", str(ok7.get("err")) == "" and str(ok7.get("status")) == "done" and int(ok7.get("coins")) == 7
		and str(pend.get("status")) == "pending")
	_ok("F4 回包解析: 字符串 / 负数 / null ⇒ 0", int(s.get("coins", -1)) == 0 and int(neg.get("coins", -1)) == 0 and int(nul.get("coins", -1)) == 0)
	_ok("F4 回包解析: 认不得的 status ⇒ server; 404 ⇒ unavailable; 没发出去 ⇒ offline; reason 原样",
		str(odd.get("err")) == "server" and str(nf.get("err")) == "unavailable" and str(off.get("err")) == "offline"
		and str(why.get("err")) == "not_in_match")
	var body := RN.finals_coins_body(WEEK, 0, 1, 0)
	var src := FileAccess.get_file_as_string("res://scripts/net/referee_net.gd")
	_ok("★F4 请求体只有四个坐标(没有币数、没有侧)", body.size() == 4 and not body.has("p_coins") and not body.has("p_side")
		and src.find("\"p_coins\"") < 0 and src.find("\"p_side\"") < 0)


## 一个客户端走一遍: 点开自己那一场(finals_seal 记单)→ 没翻面 → 翻面(按服务器的数发)→ 再来一次。
##   `hearts` < 0 ⇒ 满命; `st` 非空 ⇒ 翻面那一次的回包换成它; `week` = 交给 finals_seal 的周号。
func _client_flow(coins: int, hearts: int = -1, st: Dictionary = {}, week: int = WEEK) -> Dictionary:
	var keep := {"coins": int(_gs.meta_deepsea_coins), "hearts": int(_gs.hearts), "bt": int(_gs.battles_total),
		"stb": int(_gs.season_total_battles), "fcp": (_gs.finals_coins_pending as Array).duplicate(true),
		"fpr": (_gs.finals_pending_reveal as Dictionary).duplicate(true)}
	_gs.hearts = hearts if hearts >= 0 else int(P2C.HEARTS_MAX)
	_gs.finals_coins_pending = []
	_gs.finals_pending_reveal = {}
	RW.finals_seal(_gs, 0, 1, 0, week)
	_gs.finals_pending_reveal = {}
	RW.finals_seal(_gs, 0, 1, 0, week)                    # 同一场又点一次(待揭晓单已被清): 单子不该多一张
	var tickets := (_gs.finals_coins_pending as Array).size()
	var t := {"week": week, "bucket": 0, "round": 1, "match": 0}
	var tk_ok := tickets == 1 and int((_gs.finals_coins_pending[0] as Dictionary).get("week", -1)) == week \
		and not bool((_gs.finals_coins_pending[0] as Dictionary).get("paid", true))
	var c0 := int(_gs.meta_deepsea_coins)
	var p1 := RW.on_finals_coins(t, {"err": "", "status": "pending"})
	var p2 := RW.on_finals_coins(t, {"err": "offline"})
	var pending_kept := p1 == -1 and p2 == -1 and int(_gs.meta_deepsea_coins) == c0 and tickets == 1 \
		and not bool((_gs.finals_coins_pending[0] as Dictionary).get("paid", true))
	var n := RW.on_finals_coins(t, st if not st.is_empty() else {"err": "", "status": "done", "coins": coins})
	var delta := int(_gs.meta_deepsea_coins) - c0
	var c1 := int(_gs.meta_deepsea_coins)
	var again := RW.on_finals_coins(t, {"err": "", "status": "done", "coins": coins})
	var out := {"delta": delta, "n": n, "again_n": again, "again_delta": int(_gs.meta_deepsea_coins) - c1,
		"pending_kept": pending_kept, "tickets": tickets, "ticket_ok": tk_ok}
	_gs.meta_deepsea_coins = keep["coins"]
	_gs.hearts = keep["hearts"]
	_gs.battles_total = keep["bt"]
	_gs.season_total_battles = keep["stb"]
	_gs.finals_coins_pending = keep["fcp"]
	_gs.finals_pending_reveal = keep["fpr"]
	return out


## 拿录像走「中途退出补打」那条复算路(同 verify_referee_coins): 周六口径真打到 `_settle_season`。
##   右方没有本机结算 ⇒ 逐帧读同一个出口 `match_minted(battle, "right")` 取这一局的最大值(铸币只增不减, 整场结束才清);
##   左方同法读一遍, 与本机结算真加进奖励的那个数对账 ⇒ 读法本身是对的。
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
	var max_l := 0
	var max_r := 0
	while f < 20000 and not bool(s._replay.finished):
		max_l = maxi(max_l, EquipTickSystem.match_minted(s, "left"))
		max_r = maxi(max_r, EquipTickSystem.match_minted(s, "right"))
		await get_tree().process_frame
		f += 1
	await get_tree().process_frame
	var out := {"finished": bool(s._replay.finished), "settled": str(s._replay.mode) == "resume" and bool(s.get("_had_season")),
		"digest": str((s._replay.rec.get("end", {}) as Dictionary).get("h", "")),
		"reward": int(s._last_reward), "minted": int(s._last_reward) - int(P2C.GAUNTLET_COINS_PER_MATCH),
		"max_l": max_l, "max_r": max_r,
		"after_l": EquipTickSystem.match_minted(s, "left"), "after_r": EquipTickSystem.match_minted(s, "right")}
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


func _seg(t: String) -> String:
	var a := t.find(MARK_BEGIN)
	var b2 := t.find(MARK_END)
	return t.substr(a, b2 + MARK_END.length() - a) if a >= 0 and b2 > a else ""


func _fn(t: String, name: String) -> String:
	var a := t.find("create or replace function public.%s(" % name)
	if a < 0:
		return ""
	var b2 := t.find("end $$;", a)
	return t.substr(a, b2 - a) if b2 > a else ""


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 周日决赛服务器局发战斗内铸币" if _fail == 0 and _n >= 35 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
