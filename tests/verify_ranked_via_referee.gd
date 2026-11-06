extends Node
## verify_ranked_via_referee.gd — 积分赛交给服务器: 客户端走真入口(匹配屏 `_ready`), 只交阵容、照抄服务器的结果。
## 方案书 docs/plans/20261101c-积分赛服务器裁判.md §6(验收 V3 / V4)。假服务器 = `SupabaseNet._transport_for_test`(不碰网络)。
##
## S 开关开 + 积分赛日: 匹配屏真入口 ⇒ 发 referee_ranked_start(请求体只有 周 / 阵容 / 第几场; 第几场 = 本机场次)、
##   本机不挑对手(Backend.find_opponent 一次都没调、dual_ghost 没动)、VS 卡画服务器回的对手卡片、落积分赛待记账单;
##   查任务 pending → claimed(带种子 ⇒ 记下给跟播用)→ done ⇒ 命 / 胜 / 场次 / 配额 / 币全按服务器账本、经验 +2、战绩页一行;
##   ★整条路一个写 ghosts / matches 的请求都没有(成绩只有服务器写得进); 没进战斗场(陪练号「不看」那条)。
## J 拒收: stale / eliminated / quota_full ⇒ 本机按回包里的服务端账本对齐 + 屏上一句; closed ⇒「当前不在积分赛时段」;
##   断网 ⇒「连接服务器后才能比赛」、不出本地成绩; off ⇒ 记下开关关 ⇒ 本机挑的老路(分母: 这时 find_opponent 才被调)
## K 开关关 ⇒ 匹配屏走本机那条(一个积分赛请求都不发); 教程 / 切磋不走服务器
## M 主菜单对账: sync_ranked_ledger 按服务端账本改本机; 有挂着的单子 ⇒ 不问(先补记); 主菜单补记(resume_if_any)认积分赛单子
## D 陪练号同一路(静态): sim_driver 积分赛日开关开 ⇒ `_do_match_ranked`(盯同一个会话, 账记完不看 ⇒ 去商店)

const SB := preload("res://scripts/net/supabase.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const MMK := preload("res://scripts/scenes/MatchmakingScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const MMK_SCENE := "res://scenes/Matchmaking.tscn"
const ME := "11111111-2222-4333-8444-555555555555"
const MID := "5b2c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
const CARD := "{\"profile\":{\"name\":\"kevin_99\",\"avatar\":\"ninja\",\"id\":\"g_x_b4\",\"tag\":\"#ABCDEF\"},\"leaders\":[\"ninja\",\"dice\",\"pirate\"]}"

var _fail := 0
var _n := 0
var _gs
var _start_mode := "ok"        # ok / stale / eliminated / quota_full / closed / off / offline
var _starts: Array = []        # 交上去的请求体
var _writes: Array = []        # 任何写 ghosts / matches 的请求(不该有)
var _status_seq: Array = []    # referee_job_status 依次回什么(最后一个重复)
var _status_asks := 0
var _ledger_body := ""
var _ledger_asks := 0
var _navs: Array = []
var _leaves: Array = []


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	## 本周周二 12:00(积分赛日)
	P2C.now_override_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 86400 + 12 * 3600
	OS.set_environment(SB.ENV_URL, "http://referee.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "referee-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._token = "tok"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	SceneNav.nav_for_test = func(p: String) -> void: _navs.append(p)
	MMK._may_leave_for_test = func(p: String) -> bool:
		_leaves.append(p)
		return false
	RW.skip_play = true                 # 账一记完就停(陪练号那条; 不取录像、不进战斗场)
	_ok("分母: 积分赛日(不是闯关日)、后端已配", P2C.phase_at_utc(P2C.now_utc()) == P2C.PHASE_RANKED and SB.enabled())
	await _t_server()
	await _t_reject()
	await _t_off_paths()
	await _t_menu()
	_t_sim_static()
	P2C.now_override_ts = 0
	OS.set_environment(SB.ENV_URL, " ")
	ProjectSettings.set_setting(SB.SETTING_KEY, "")
	SB._transport_for_test = Callable()
	SB._token = ""
	SceneNav.nav_for_test = Callable()
	MMK._may_leave_for_test = Callable()
	RW.skip_play = false
	_gs.referee_flags = {}
	_gs.referee_pending = {}
	_finish()


func _setup_gs() -> void:
	_gs.test_mode = true
	_gs.account_id = ME
	_gs.tutorial_active = false
	_gs.onboarded = true
	_gs.reset_dual_lane()
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.week_anchor_ts = P2C.week_anchor_utc(P2C.now_utc())
	_gs.season_start_ts = _gs.week_anchor_ts
	_gs.week_phase = P2C.PHASE_RANKED
	_gs.hearts = int(P2C.HEARTS_MAX)
	_gs.season_wins = 3
	_gs.season_total_battles = 4
	_gs.ranked_used = 4
	_gs.season_sweeps = 1
	_gs.season_eggs_killed = 3
	_gs.meta_deepsea_coins = 100
	_gs.season_xp = 0
	_gs.battles_total = 10
	_gs.battles_won = 5
	_gs.match_history = []
	_gs.referee_pending = {}
	_gs.replay_pending_id = ""
	_gs.referee_flags = {RN.K_FINALS: false, RN.K_GAUNTLET: false, RN.K_STREAM: false, RN.K_STREAM_VER: "", RN.K_RANKED: true}


func _led(b: int, w: int, h: int, s: int, e: int, u: int) -> String:
	return "{\"battles\":%d,\"wins\":%d,\"hearts\":%d,\"sweeps\":%d,\"eggs\":%d,\"used\":%d}" % [b, w, h, s, e, u]


func _transport(m, u, _h, b, cb) -> void:
	var url := str(u)
	if str(m) != "GET" and (url.find("/rest/v1/ghosts") >= 0 or url.find("/rest/v1/matches") >= 0
			or url.find("/rest/v1/gauntlet_ghosts") >= 0):
		_writes.append(url)
	if url.find("/rpc/referee_ranked_start") >= 0:
		_starts.append(JSON.parse_string(str(b)))
		match _start_mode:
			"ok":
				cb.call({"ok": true, "code": 200, "body": "{\"ok\":true,\"job_id\":41,\"match_id\":\"%s\",\"opp\":%s,\"ledger\":%s}"
					% [MID, CARD, _led(4, 3, 6, 1, 3, 4)]})
			"stale":
				cb.call({"ok": true, "code": 200, "body": "{\"ok\":false,\"reason\":\"stale\",\"ledger\":%s}" % _led(7, 5, 4, 2, 5, 7)})
			"eliminated":
				cb.call({"ok": true, "code": 200, "body": "{\"ok\":false,\"reason\":\"eliminated\",\"ledger\":%s}" % _led(9, 3, 0, 0, 3, 9)})
			"quota_full":
				cb.call({"ok": true, "code": 200, "body": "{\"ok\":false,\"reason\":\"quota_full\",\"ledger\":%s}" % _led(16, 11, 2, 1, 11, 16)})
			"closed":
				cb.call({"ok": true, "code": 200, "body": "{\"ok\":false,\"reason\":\"closed\"}"})
			"off":
				cb.call({"ok": true, "code": 200, "body": "{\"ok\":false,\"reason\":\"off\"}"})
			_:
				cb.call({"ok": false, "code": 0, "body": ""})
		return
	if url.find("/rpc/referee_job_status") >= 0:
		_status_asks += 1
		var body: String = str(_status_seq[0]) if _status_seq.size() > 0 else "{\"ok\":true,\"status\":\"pending\",\"kind\":\"ranked\"}"
		if _status_seq.size() > 1:
			_status_seq.pop_front()
		cb.call({"ok": true, "code": 200, "body": body})
		return
	if url.find("/rpc/referee_ranked_ledger") >= 0:
		_ledger_asks += 1
		cb.call({"ok": true, "code": 200, "body": _ledger_body})
		return
	if url.find("/rpc/referee_flags") >= 0:
		cb.call({"ok": true, "code": 200, "body": "{\"finals_on\":false,\"gauntlet_on\":false,\"ranked_on\":true}"})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


func _status(m) -> String:
	var l := m.find_child("RefereeStatus", true, false) as Label if m != null and is_instance_valid(m) else null
	return l.text if l != null else ""


func _open_mmk() -> Node:
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	await _frames(2)
	var m: Node = (load(MMK_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	return m


func _local_picks() -> int:
	return int(Backend.match_src_counts.get("exact", 0)) + int(Backend.match_src_counts.get("bot", 0))


# ─────────────────────────────── S 服务器那一路 ───────────────────────────────
func _t_server() -> void:
	print("── S 开关开: 交阵容 → 服务器挑对手 / 算 / 记账 → 本机照抄 ──")
	_setup_gs()
	_start_mode = "ok"
	_starts.clear()
	_writes.clear()
	_status_asks = 0
	_status_seq = [
		"{\"ok\":true,\"status\":\"pending\",\"match_id\":\"%s\",\"kind\":\"ranked\"}" % MID,
		"{\"ok\":true,\"status\":\"claimed\",\"match_id\":\"%s\",\"kind\":\"ranked\",\"seed\":123456}" % MID,
		("{\"ok\":true,\"status\":\"done\",\"match_id\":\"%s\",\"kind\":\"ranked\",\"seed\":123456,\"won\":false,\"coins\":0,\"score\":0,"
			+ "\"ranked\":{\"battles\":5,\"wins\":3,\"hearts\":5,\"sweeps\":1,\"eggs\":3,\"used\":5,\"reward\":15,\"sweep\":false}}") % MID,
	]
	## 「经验 +2」的期望值用同一个函数现算(等级可能刚好升一级)
	var lx0 := [int(_gs.season_level), int(_gs.season_xp)]
	_gs.add_season_xp(2)
	var lx_want := [int(_gs.season_level), int(_gs.season_xp)]
	_gs.season_level = lx0[0]
	_gs.season_xp = lx0[1]
	var sentinel := {"ghost_id": "sentinel", "leaders": ["dice"]}
	_gs.dual_ghost = sentinel
	var picks0 := _local_picks()
	var m: Node = await _open_mmk()
	var t0 := Time.get_ticks_msec()
	var seed_seen := -1
	var bill_kind := ""
	while Time.get_ticks_msec() - t0 < 30000:
		var run = m.get("_ref_run") if is_instance_valid(m) else null
		if run != null and is_instance_valid(run):
			if int(run.get("_seed_hint")) > 0:
				seed_seen = int(run.get("_seed_hint"))
			if bill_kind == "" and not (_gs.referee_pending as Dictionary).is_empty():
				bill_kind = str((_gs.referee_pending as Dictionary).get("kind", ""))
			if str(run.state) == RW.ST_SKIPPED:
				break
		await get_tree().process_frame
	var run2 = m.get("_ref_run")
	_ok("S1 ★分母: 匹配屏真入口发了恰好 1 次 referee_ranked_start", _starts.size() == 1, str(_starts.size()))
	var body: Dictionary = _starts[0] if _starts.size() > 0 and _starts[0] is Dictionary else {}
	var keys: Array = body.keys()
	keys.sort()
	_ok("S2 ★请求体只有 周 / 阵容 / 第几场(客户端没有任何参数位能报对手、种子、胜负、成绩)",
		keys == ["p_match_no", "p_snapshot", "p_week"], str(keys))
	var snap: Dictionary = body.get("p_snapshot", {}) if body.get("p_snapshot", null) is Dictionary else {}
	_ok("S3 第几场 = 本机场次(4)、周 = 本周锚点、阵容 = 本机三统领", int(body.get("p_match_no", -1)) == 4
		and int(body.get("p_week", 0)) == int(_gs.week_anchor_ts) and Array(snap.get("leaders", [])) == ["basic", "stone", "bamboo"],
		str(body.get("p_match_no")))
	_ok("S4 ★本机没挑对手(find_opponent 一次没调)、dual_ghost 没动", _local_picks() == picks0 and is_same(_gs.dual_ghost, sentinel),
		"%d → %d" % [picks0, _local_picks()])
	_ok("S5 VS 卡画的是服务器回的对手卡片", str((_gs.dual_opponent as Dictionary).get("name", "")) == "kevin_99"
		or str(((_gs.dual_opponent as Dictionary).get("profile", {}) as Dictionary).get("name", "")) == "kevin_99", str(_gs.dual_opponent))
	_ok("S6 交上去那一刻落了积分赛待记账单(kind = ranked)", bill_kind == RW.KIND_RANKED, bill_kind)
	_ok("S7 裁判开算(claimed)时记下服务器给的种子(跟播用, 不去问周六那份列表)", seed_seen == 123456, str(seed_seen))
	_ok("S8 ★分母: 查了 ≥ 3 次任务、走到「账已记完」", _status_asks >= 3 and run2 != null and str(run2.state) == RW.ST_SKIPPED,
		"%d 次 · %s" % [_status_asks, str(run2.state) if run2 != null else "?"])
	_ok("S9 ★命、胜、场次、配额、横扫、碎蛋 = 服务器账本(5、3、5、5、1、3)", int(_gs.hearts) == 5 and int(_gs.season_wins) == 3
		and int(_gs.season_total_battles) == 5 and int(_gs.ranked_used) == 5 and int(_gs.season_sweeps) == 1
		and int(_gs.season_eggs_killed) == 3, "%d/%d/%d/%d" % [int(_gs.hearts), int(_gs.season_wins), int(_gs.season_total_battles), int(_gs.ranked_used)])
	_ok("S10 ★币 = 服务器给的 15(本机不重算)、经验 +2、总场次 +1、战绩页一行(对手名 / 服务器录像)", int(_gs.meta_deepsea_coins) == 115
		and [int(_gs.season_level), int(_gs.season_xp)] == lx_want and lx_want != lx0
		and int(_gs.battles_total) == 11 and (_gs.match_history as Array).size() == 1
		and str(((_gs.match_history as Array)[0] as Dictionary).get("foe_name", "")) == "kevin_99"
		and str(((_gs.match_history as Array)[0] as Dictionary).get("replay_id", "")) == MID,
		"币 %d · 经验 %d · 总场次 %d" % [int(_gs.meta_deepsea_coins), int(_gs.season_xp), int(_gs.battles_total)])
	_ok("S11 单子销了(只记这一次)", (_gs.referee_pending as Dictionary).is_empty())
	_ok("S12 ★整条路一个写 ghosts / matches 的请求都没有(成绩只有服务器写)", _writes.is_empty(), str(_writes))
	_ok("S13 没进战斗场(本机一步 sim 都没跑)、没换屏", _navs.is_empty() and _leaves.is_empty() and get_tree().current_scene == m,
		"%s %s" % [str(_navs), str(_leaves)])
	m.queue_free()
	await _frames(3)


# ─────────────────────────────── J 拒收 ───────────────────────────────
func _reject_case(mode: String) -> Dictionary:
	_setup_gs()
	_start_mode = mode
	_starts.clear()
	_writes.clear()
	_navs.clear()
	_leaves.clear()
	var picks0 := _local_picks()
	var m: Node = await _open_mmk()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 12000:
		var run = m.get("_ref_run") if is_instance_valid(m) else null
		if run != null and is_instance_valid(run) and (str(run.state) == RW.ST_ERROR or str(run.state) == RW.ST_LOCAL) \
				and Time.get_ticks_msec() - t0 > 2500:
			break
		await get_tree().process_frame
	await _frames(40)
	var out := {"status": _status(m), "starts": _starts.size(), "picks": _local_picks() - picks0,
		"pending": (_gs.referee_pending as Dictionary).duplicate(), "writes": _writes.size(), "navs": _navs.duplicate()}
	if is_instance_valid(m):
		m.queue_free()
	await _frames(3)
	return out


func _t_reject() -> void:
	print("── J 拒收 / 断网 ──")
	var r := await _reject_case("stale")
	_ok("J1 ★stale ⇒ 本机按服务端账本对齐(7 场、5 胜、4 命、2 横扫、5 碎蛋、配额 7)、屏上「%s」、不落单子" % RW.TXT_STALE,
		int(_gs.season_total_battles) == 7 and int(_gs.season_wins) == 5 and int(_gs.hearts) == 4 and int(_gs.season_sweeps) == 2
		and int(_gs.season_eggs_killed) == 5 and int(_gs.ranked_used) == 7 and r["status"] == RW.TXT_STALE
		and (r["pending"] as Dictionary).is_empty(), str(r))
	r = await _reject_case("eliminated")
	_ok("J2 eliminated ⇒ 命对齐成 0、屏上「%s」" % RW.TXT_RANKED_ELIM, int(_gs.hearts) == 0 and r["status"] == RW.TXT_RANKED_ELIM, str(r))
	r = await _reject_case("quota_full")
	_ok("J3 quota_full ⇒ 配额对齐成 16、屏上「%s」" % RW.TXT_RANKED_QUOTA, int(_gs.ranked_used) == 16 and r["status"] == RW.TXT_RANKED_QUOTA, str(r))
	r = await _reject_case("closed")
	_ok("J4 closed ⇒ 屏上「%s」" % RW.TXT_RANKED_CLOSED, r["status"] == RW.TXT_RANKED_CLOSED, str(r))
	_setup_gs()
	var s0 := [int(_gs.hearts), int(_gs.season_wins), int(_gs.season_total_battles), int(_gs.meta_deepsea_coins), (_gs.match_history as Array).size()]
	r = await _reject_case("offline")
	var s1 := [int(_gs.hearts), int(_gs.season_wins), int(_gs.season_total_battles), int(_gs.meta_deepsea_coins), (_gs.match_history as Array).size()]
	_ok("J5 ★断网 ⇒「%s」、没有本地成绩(命 / 胜 / 场次 / 币 / 战绩页一个都不动)、本机没挑对手、没进战斗场" % RW.TXT_NEED_SERVER,
		r["status"] == RW.TXT_NEED_SERVER and s1 == s0 and int(r["picks"]) == 0 and (r["navs"] as Array).is_empty()
		and int(r["starts"]) == 1, "%s · %s → %s" % [str(r), str(s0), str(s1)])
	r = await _reject_case("off")
	_ok("J6 off ⇒ 记下开关关、退回本机挑的老路(分母: 这时 find_opponent 才被调 1 次、去战斗场)", not RN.ranked_on()
		and int(r["picks"]) == 1 and (r["navs"] as Array).has("res://scenes/RealtimeBattle3D.tscn"), str(r))


# ─────────────────────────────── K 开关关 / 教程 / 切磋 ───────────────────────────────
func _t_off_paths() -> void:
	print("── K 开关关 ⇒ 本机那条(老路一行不动, R 段另守) ──")
	_setup_gs()
	_gs.referee_flags = {RN.K_FINALS: false, RN.K_GAUNTLET: false, RN.K_RANKED: false}
	_starts.clear()
	_leaves.clear()
	var picks0 := _local_picks()
	var m: Node = await _open_mmk()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000 and _leaves.is_empty():
		await get_tree().process_frame
	_ok("K1 ★开关关 ⇒ 一个积分赛请求都不发、本机挑了 1 次、走到进战斗场那一步", _starts.is_empty() and _local_picks() == picks0 + 1
		and _leaves.has("res://scenes/RealtimeBattle3D.tscn"), "%d 次请求 · %s" % [_starts.size(), str(_leaves)])
	m.queue_free()
	await _frames(3)
	_setup_gs()
	var mm: Node = MMK.new()
	_gs.tutorial_active = true
	var tut: bool = mm._ranked_server_now()
	_gs.tutorial_active = false
	var on: bool = mm._ranked_server_now()
	mm.free()
	_ok("K2 新手教程沙盒里不走服务器(分母: 同一刻不在教程 ⇒ 走)", not tut and on)


# ─────────────────────────────── M 主菜单 ───────────────────────────────
func _t_menu() -> void:
	print("── M 主菜单: 按服务端账本对齐 / 补记 ──")
	_setup_gs()
	_ledger_body = "{\"ok\":true,\"week\":1,\"ledger\":%s}" % _led(9, 6, 3, 2, 6, 9)
	_ledger_asks = 0
	var got := [-1]
	RW.sync_ranked_ledger(func(ch: bool) -> void: got[0] = 1 if ch else 0)
	for _i in range(120):
		if got[0] >= 0:
			break
		await get_tree().process_frame
	_ok("M1 ★主菜单问到服务端账本 ⇒ 本机改成它(9 场、6 胜、3 命、配额 9)", got[0] == 1 and int(_gs.season_total_battles) == 9
		and int(_gs.season_wins) == 6 and int(_gs.hearts) == 3 and int(_gs.ranked_used) == 9 and _ledger_asks == 1, str(got))
	_gs.referee_pending = RW.ranked_bill(42, MID, int(_gs.week_anchor_ts), {})
	_ok("M2 有挂着的积分赛单子 ⇒ 不问账本(先补记那一局)", not RW.sync_ranked_ledger() and _ledger_asks == 1)
	_status_seq = [("{\"ok\":true,\"status\":\"done\",\"match_id\":\"%s\",\"kind\":\"ranked\",\"won\":true,\"coins\":3,"
		+ "\"ranked\":{\"battles\":10,\"wins\":7,\"hearts\":3,\"sweeps\":3,\"eggs\":7,\"used\":10,\"reward\":28,\"sweep\":true}}") % MID]
	var c0 := int(_gs.meta_deepsea_coins)
	var v := [{}]
	RW.resume_if_any(func(view: Dictionary) -> void: v[0] = view)
	for _i in range(120):
		if not (v[0] as Dictionary).is_empty():
			break
		await get_tree().process_frame
	_ok("M3 ★主菜单补记认积分赛单子: 按服务器账本记(10 场 / 7 胜 / 3 横扫)、币 +28、单子销了、补记那句是积分赛的",
		int(_gs.season_total_battles) == 10 and int(_gs.season_wins) == 7 and int(_gs.season_sweeps) == 3
		and int(_gs.meta_deepsea_coins) - c0 == 28 and (_gs.referee_pending as Dictionary).is_empty()
		and RW.resume_text(v[0]) == RW.TXT_RESUMED_RANKED_WIN, str(v[0]))
	_gs.referee_flags = {RN.K_FINALS: false, RN.K_GAUNTLET: false, RN.K_RANKED: false}
	_ok("M4 开关关 ⇒ 主菜单不问账本", not RW.sync_ranked_ledger() and _ledger_asks == 1)
	await _t_menu_weekend()


## 用户 2026-11-06 排查: 服务端账本只有积分赛那几场; 周六 / 周日主菜单一对账, 闯关 / 决赛加的场次与胜场就被覆盖回去
##   (货架因此不换货、胜场掉回去)。积分赛阶段照常对账是分母。
func _t_menu_weekend() -> void:
	_setup_gs()
	var P := RW.P2C
	var keep: int = P.now_override_ts
	var wk: int = int(_gs.week_anchor_ts)
	_gs.referee_flags = {RN.K_FINALS: false, RN.K_GAUNTLET: false, RN.K_RANKED: true}
	_gs.season_total_battles = 16
	_gs.season_wins = 11
	_ledger_body = "{\"ok\":true,\"week\":1,\"ledger\":%s}" % _led(16, 11, 3, 2, 11, 16)
	P.now_override_ts = wk + 4 * 86400 + 12 * 3600                    # 周五 12:00
	var a0 := _ledger_asks
	_ok("M5 分母: 周五(积分赛阶段)照常问账本", RW.sync_ranked_ledger() and _ledger_asks == a0 + 1, "asks %d→%d" % [a0, _ledger_asks])
	for _i in range(60):
		await get_tree().process_frame
	P.now_override_ts = wk + 5 * 86400 + 12 * 3600                    # 周六 12:00
	_gs.gauntlet_settle(true)                                         # 闯关赢一场 ⇒ 本机 17 场 12 胜
	var b1 := int(_gs.season_total_battles)
	var w1 := int(_gs.season_wins)
	a0 = _ledger_asks
	var sent: bool = RW.sync_ranked_ledger()
	for _i in range(60):
		await get_tree().process_frame
	_ok("M6 ★周六主菜单不拿积分赛账本覆盖闯关(本机 %d 场 %d 胜不变)" % [b1, w1], not sent and _ledger_asks == a0
		and int(_gs.season_total_battles) == b1 and int(_gs.season_wins) == w1 and b1 == 17 and w1 == 12,
		"发了=%s 现在 %d 场 %d 胜" % [str(sent), int(_gs.season_total_battles), int(_gs.season_wins)])
	P.now_override_ts = wk + 6 * 86400 + 12 * 3600                    # 周日 12:00
	a0 = _ledger_asks
	_ok("M7 周日同样不问", not RW.sync_ranked_ledger() and _ledger_asks == a0)
	P.now_override_ts = keep


# ─────────────────────────────── D 陪练号同一路(静态) ───────────────────────────────
func _t_sim_static() -> void:
	print("── D 陪练号(sim_driver)走同一个匹配屏会话 ──")
	var t := FileAccess.get_file_as_string("res://scripts/systems/sim/sim_driver.gd").replace("\r\n", "\n")
	_ok("D1 积分赛日开关开 ⇒ `_do_match_ranked`(在本机看对手卡那条之前)", t.contains("\tif _ranked_server():\n\t\tawait _do_match_ranked(mm)\n\t\treturn\n\t_acted_id = mm.get_instance_id()\n\tawait _sleep(3.2)"))
	var a := t.find("func _ranked_server() -> bool:")
	_ok("D2 判据与匹配屏同一个开关(RefereeNet.ranked_on)、教程不走", a >= 0 and t.substr(a, 200).contains("ranked_on()")
		and t.substr(a, 200).contains("tutorial_active"))
	var b := t.find("func _do_match_ranked(mm: Node) -> void:")
	var body := t.substr(b, 2600) if b >= 0 else ""
	_ok("D3 盯的是匹配屏那一个会话(_ref_run), 账记完不看(ST_SKIPPED)⇒ 去商店; SIM_SKIP_WATCH 同一个开关",
		body.contains("mm.get(\"_ref_run\")") and body.contains("rw.ST_SKIPPED") and body.contains("S_SHOP")
		and body.contains("SIM_SKIP_WATCH"))


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 积分赛交给服务器(客户端)" if _fail == 0 and _n >= 30 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
