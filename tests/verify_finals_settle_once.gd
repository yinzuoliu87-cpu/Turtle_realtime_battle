extends Node
## verify_finals_settle_once.gd —— 周日「购物结束后统一结算、每场只算一次」(2026-10-12 · 方案书 docs/plans/20261012-周日统一结算.md)
##
## 原稿 §四「3 分钟备战购物 → 系统瞬间结算 → 全桶观看重放」; §五.2「共享种子结算一次 → 双方各自观看同一份重放」。
## 修的实操问题: S4 购物窗内就被对手打完 / 打的是周六快照; S6 两边各打各的、都算出自己赢。
## ① 纯函数: 购物窗内谁都不能打; 上半区购物结束即可; 下半区要再等宽限(= 服务端 finals_lower_grace_sec)
## ② 对阵图真入口: 同一场、同一时刻, 上半区能开打而下半区不能(每场只有一个人在算)
## ③ 上报带侧别: report_finals_if_any 把 finals_match.side 带进请求体与补报单
## ④ 服务端拒收「时候没到」⇒ 不记成报过了(留着补报); 其他拒收 ⇒ 记成结束
## ⑤ 购物窗内对阵图把我的阵容推上去(finals_update_snapshot); 窗外不推
## ⑥ 下半区等待时那一行说「本场结算中」
## ⑦ 服务端迁移: 购物窗内不给对手快照 / 不收上报; 下半区宽限; 不带侧别拒收; 快照只在购物窗内可改

const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const SB := preload("res://scripts/net/supabase.gd")
const BE := preload("res://scripts/net/backend.gd")
const BMS := preload("res://scripts/scenes/BracketMapScene.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _map(round_at: int, srv_now: int, me: int) -> Node:
	var m = BMS.new()
	add_child(m)
	await get_tree().process_frame
	m.set_bucket({"size": 2, "round": 1, "me": me, "names": ["甲龟", "乙龟"], "done": {}, "bucket": 4,
		"round_at": round_at, "srv_now": srv_now})
	## ★2026-10-19: 对阵图周一只看不打(用户「保留到周一」) ⇒ 钉在本周日(set_bucket / _ready 都会清, 所以放最后)。
	m._now_override = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 6 * 86400 + 20 * 3600
	await get_tree().process_frame
	return m


func _ready() -> void:
	await get_tree().process_frame
	print("=== 周日统一结算 ===")
	var S := P2C.FINALS_SHOP_SEC
	var G := P2C.FINALS_LOWER_GRACE_SEC
	var ra := 1000000
	## ① 纯函数
	_ok("① ★购物窗内上半区不能打", not P2C.finals_fight_open(ra, ra + S - 1, 0))
	_ok("① ★购物窗内下半区不能打", not P2C.finals_fight_open(ra, ra + S - 1, 1))
	_ok("① 上半区购物一结束就能打", P2C.finals_fight_open(ra, ra + S, 0))
	_ok("① ★下半区购物结束后仍要等宽限", not P2C.finals_fight_open(ra, ra + S + G - 1, 1))
	_ok("① 下半区宽限过后能代打", P2C.finals_fight_open(ra, ra + S + G, 1))
	_ok("① 侧别不对 / 没拿到时刻 ⇒ 不能打", not P2C.finals_fight_open(ra, ra + 99999, -1) and not P2C.finals_fight_open(0, 99999, 0))

	## ② 对阵图真入口(2 人组只有一场: 种子 0 = 上半区, 种子 1 = 下半区)
	var m0 = await _map(ra, ra + S + 10, 0)
	var m1 = await _map(ra, ra + S + 10, 1)
	_ok("② ★分母: 两个视角的侧别", m0.my_side(1, 0) == 0 and m1.my_side(1, 0) == 1, "%d / %d" % [m0.my_side(1, 0), m1.my_side(1, 0)])
	_ok("② ★★同一时刻: 上半区能开打", m0.should_fetch_opponent(1, 0))
	_ok("② ★★同一时刻: 下半区不能(每场只有一个人在算)", not m1.should_fetch_opponent(1, 0))
	var m1b = await _map(ra, ra + S + G + 10, 1)
	_ok("② 宽限过后下半区能代打", m1b.should_fetch_opponent(1, 0))
	var m0s = await _map(ra, ra + 30, 0)
	_ok("② ★购物窗内上半区也不能开打(S4)", not m0s.should_fetch_opponent(1, 0))

	## ⑥ 下半区等待那一行
	var tip: String = m1.settle_wait_tip(m1.cur())
	_ok("⑥ 下半区等待时说「本场结算中」", tip.begins_with("本场结算中"), tip)
	_ok("⑥ 上半区不说这一句", m0.settle_wait_tip(m0.cur()) == "")
	for x in [m0, m1, m1b, m0s]:
		x.queue_free()

	## ③ 上报带侧别(真入口 report_finals_if_any)
	var gs = get_node_or_null("/root/GameState")
	_ok("③ ★分母: GameState 在位", gs != null)
	if gs != null:
		gs.test_mode = true
		gs.finals_match = {"bucket": 4, "round": 1, "match": 0, "side": 1}
		gs.lane_results = {"top": "left", "bottom": "left"}
		BE.report_finals_if_any(true)
		var lr: Dictionary = BE.last_finals_report
		_ok("③ ★交给网络层的那一份带上报侧别 = 我的侧别", int(lr.get("rside", -9)) == 1, str(lr))
		_ok("③ 补报单也带着(断网补报时用)", int((gs.finals_report_pending as Dictionary).get("rside", -9)) == 1, str(gs.finals_report_pending))
		gs.finals_report_pending = {}
		gs.finals_pending_reveal = {}
	var body := SB.finals_report_body(1, 4, 1, 0, 1, 77, 0)
	_ok("③ 请求体带 p_reporter_side", int(body.get("p_reporter_side", -1)) == 0, str(body))
	_ok("③ 没有侧别 ⇒ 不带(服务端回 update_required)", not SB.finals_report_body(1, 4, 1, 0, 1, 77).has("p_reporter_side"))

	## ④ 拒收原因
	_ok("④ 解析拒收原因", SB.finals_report_reject("{\"ok\": false, \"reason\": \"upper_first\"}") == "upper_first")
	_ok("④ 收了 ⇒ 空", SB.finals_report_reject("{\"ok\": true}") == "")
	var env0 := OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	var acc0 := str(gs.account_id) if gs != null else ""
	if gs != null:
		gs.account_id = "uid-me"
	SB._token = "gate-token"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	var reply: Array = ["{\"ok\": false, \"reason\": \"shop_open\"}"]
	var sent: Array = []
	SB._transport_for_test = func(_m, u, _h, b, cb):
		sent.append({"u": str(u), "b": str(b)})
		cb.call({"ok": true, "code": 200, "body": reply[0]})
	_ok("④ ★分母: 后端打开了", SB.enabled())
	SB.finals_report_clear()
	SB._report_inflight = false
	SB.report_finals_async(777, 4, 1, 0, 1, 99, -1, 0)
	for _i in range(6):
		await get_tree().process_frame
	_ok("④ ★分母: 请求发出去了", sent.size() == 1, str(sent.size()))
	_ok("④ ★★服务端说「购物没结束」⇒ 不记成报过了(留着补报)", not SB.finals_reported(1, 0, 4))
	reply[0] = "{\"ok\": true}"
	SB._report_inflight = false
	SB.report_finals_async(777, 4, 1, 0, 1, 99, -1, 0)
	for _i in range(6):
		await get_tree().process_frame
	_ok("④ 收了 ⇒ 记成报过了", SB.finals_reported(1, 0, 4))

	## ⑤ 购物窗内推阵容(真入口: 对阵图轮询)
	sent.clear()
	SB.finals_snapshot_posts = 0
	BE._finals_snap_at = 0
	## 空阵容不推(防覆盖周六那份正式阵容) ⇒ 这里要有 3 只统领, 测完还原
	var leaders0 = GameState.season_leaders.duplicate(true)
	GameState.season_leaders = ["basic", "stone", "bamboo"]
	var srv := int(Time.get_unix_time_from_system())
	var mp = BMS.new()
	add_child(mp)
	await get_tree().process_frame
	mp._start_feed()
	mp.set_bucket({"size": 2, "round": 1, "me": 0, "names": ["甲龟", "乙龟"], "done": {}, "bucket": 4,
		"round_at": srv - 30, "srv_now": srv, "recv_at": srv})
	mp._bucket = mp.cur()
	mp._on_poll()
	for _i in range(6):
		await get_tree().process_frame
	_ok("⑤ ★★购物窗内对阵图把我的阵容推上去", SB.finals_snapshot_posts >= 1, "posts=%d" % SB.finals_snapshot_posts)
	var snap_req: Array = sent.filter(func(x): return str(x["u"]).ends_with("/rpc/finals_update_snapshot"))
	_ok("⑤ 推的是 finals_update_snapshot 且带组号与快照", snap_req.size() >= 1
		and str(snap_req[0]["b"]).find("\"p_bucket\":4") >= 0 and str(snap_req[0]["b"]).find("p_snapshot") >= 0,
		str(snap_req.map(func(x): return str(x["b"]).left(80))))
	SB.finals_snapshot_posts = 0
	BE._finals_snap_at = 0
	mp.set_bucket({"size": 2, "round": 1, "me": 0, "names": ["甲龟", "乙龟"], "done": {}, "bucket": 4,
		"round_at": srv - S - 30, "srv_now": srv, "recv_at": srv})
	mp._bucket = mp.cur()
	mp._on_poll()
	for _i in range(6):
		await get_tree().process_frame
	_ok("⑤ ★购物结束后不再推(阵容已锁定)", SB.finals_snapshot_posts == 0, "posts=%d" % SB.finals_snapshot_posts)
	mp.queue_free()
	GameState.season_leaders = leaders0
	SB._transport_for_test = Callable()
	SB.finals_report_clear()
	SB._report_inflight = false
	OS.set_environment(SB.ENV_URL, env0)
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	if gs != null:
		gs.account_id = acc0

	## ⑦ 服务端迁移(静态)
	var sql := FileAccess.get_file_as_string("res://server/supabase/migrations/20261012d_finals_settle_once.sql")
	_ok("⑦ ★分母: 迁移文件在", sql.length() > 2000)
	_ok("⑦ 购物窗时长 = 客户端常量", sql.find("select %d $$;      -- = 客户端 Phase2Config.FINALS_SHOP_SEC" % S) >= 0)
	_ok("⑦ 宽限 = 客户端常量", sql.find("select %d $$;      -- 购物结束后给上半区的时间" % G) >= 0)
	_ok("⑦ ★对手快照购物窗内不给", sql.find("'reason', 'shop_open'") >= 0 and sql.count("make_interval(secs => public.finals_shop_sec())") >= 3)
	_ok("⑦ ★下半区宽限", sql.find("p_reporter_side = 1 and now() < open_at + make_interval(secs => public.finals_lower_grace_sec())") >= 0)
	_ok("⑦ ★不带侧别拒收", sql.find("'update_required'") >= 0)
	_ok("⑦ 快照只在购物窗内可改", sql.find("if now() >= b.round_at + make_interval(secs => public.finals_shop_sec()) then") >= 0)

	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
