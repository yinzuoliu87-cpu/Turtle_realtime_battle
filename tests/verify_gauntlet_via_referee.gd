extends Node
## verify_gauntlet_via_referee.gd — 周六闯关交给服务器裁判(方案书 docs/plans/20261019-服务器裁判.md §3 ②)。
##
## 用户 10-19「周六周日让服务器记」; 问题总表 B1「断网点开战 ⇒ 不出本地成绩」。
## 全程走产品自己的入口: 匹配屏(真场景, 真计时器)→ `referee_run.gd` → 注入传输(不连网);
##   「服务器」那一份录像由 RefereeRunner(裁判机上跑的同一套代码)按客户端真交上来的两份快照真算出来。
##
## 段落:
##   A 开关开 · 一致: 交阵容(请求体四个形参)→ 轮询 → done ⇒ 播之前账已按服务器记完(战绩 = 服务器账本 / 币 / 战绩页挂录像号 / 单子清掉)
##     ⇒ 进战斗场是「播」(裁判局: 没有「回放」小签、没有播放控件)⇒ 放完走正常结算屏, 胜负 = 服务器
##   B ★服务器说输、本地重算说赢 ⇒ 记输、结算屏写「失败」(以服务器为准)
##   C 录像在本机对不上(改坏一个校验点)⇒ 停下, 结算屏照样按服务器结果出 + 「录像无法在本设备播放」; 战绩照记
##   D 断网点开战 ⇒ 屏上「连接服务器后才能比赛」, 不进战斗场、战绩 / 币 / 场次 / 战绩页一个都不动、没有待记账单
##   E 交上去之后断网 ⇒「下次打开时补记」、单子留着; 杀进程(匹配屏没了)⇒ 下次开主菜单补记一次, 再来一次不重复记
##   F 开关关 ⇒ 老路: 走到「去战斗场」那一步、一次都不交
## 每条判据都做过反向验证(改坏 → 红 → 逐字节还原), 见方案书「验收清单」那一行。

const SB := preload("res://scripts/net/supabase.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const RC := preload("res://scripts/scenes/battle/replay_controls.gd")
const LS := preload("res://scripts/systems/replay/live_spectate.gd")
const Backend := preload("res://scripts/net/backend.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const MMK := preload("res://scripts/scenes/MatchmakingScene.gd")
const MMK_SCENE := "res://scenes/Matchmaking.tscn"
const ME := "11111111-2222-4333-8444-555555555555"
const MID := "5b2c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"

var _fail := 0
var _n := 0
var _gs
var _flags_body := ""
var _hits := {}
var _submit_body: Dictionary = {}
var _job := 100
var _done := false
var _srv_won := false
var _srv_gw := 0
var _srv_gl := 0
var _offline_submit := false
var _offline_status := false
var _rec_b64 := ""                # 服务器 matches 行里的录像
var _rec: Dictionary = {}
var _a_won := false
var _left_hook := 0


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


func _hit(name: String) -> int:
	return int(_hits.get(name, 0))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	OS.set_environment("TURTLE_SEED", "")
	## 一个周六中午(时间缝; 用完还原)
	var sat: int = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 5 * 86400 + 12 * 3600
	P2C.now_override_ts = sat
	_setup_gs()
	OS.set_environment(SB.ENV_URL, "http://referee.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "referee-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._token = "tok"
	_ok("分母: 时间钉在周六、闯关赛上线", P2C.phase_at_utc(P2C.now_utc()) == P2C.PHASE_GAUNTLET
		and P2C.phase_mode_live(P2C.PHASE_GAUNTLET))
	_t_pure()
	await _t_a()
	if not _rec.is_empty():
		await _t_b()
		await _t_c()
	await _t_d()
	await _t_e()
	await _t_f()
	_cleanup()
	_finish()


func _setup_gs() -> void:
	_gs.test_mode = true
	_gs.account_id = ME
	_gs.tutorial_active = false
	_gs.onboarded = true
	_gs.reset_dual_lane()
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	## 我方每只统领 3 件 3 星(与 verify_referee_job_roundtrip R6 的强方同一造法) ⇒ 录像里甲方(我)赢 ——
	##   B 段要的正是「本机重算说赢、服务器说输」那一个方向。
	var shop: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			shop.append(str((e as Dictionary)["id"]))
	var k := 0
	var pe := {}
	for pid in _gs.season_leaders:
		var l: Array = []
		for _j in range(3):
			l.append({"id": str(shop[k % shop.size()]), "star": 3})
			k += 1
		pe[pid] = l
	_gs.persistent_equipped = pe
	_gs.week_anchor_ts = P2C.week_anchor_utc(P2C.now_utc())
	_gs.promoted = true
	_gs.hearts = int(P2C.HEARTS_MAX)
	_gs.gauntlet_wins = 1
	_gs.gauntlet_losses = 0
	_gs.referee_pending = {}
	_gs.referee_flags = {RN.K_FINALS: false, RN.K_GAUNTLET: true}
	_gs.dual_active = true


func _cleanup() -> void:
	P2C.now_override_ts = 0
	OS.set_environment(SB.ENV_URL, " ")
	ProjectSettings.set_setting(SB.SETTING_KEY, "")
	SB._transport_for_test = Callable()
	SB._token = ""
	MMK._may_leave_for_test = Callable()
	LS.pending = {}
	_gs.referee_flags = {}
	_gs.referee_pending = {}


func _transport(m, u, _h, b, cb) -> void:
	var url := str(u)
	if url.find("/auth/v1/") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({
			"access_token": "tok", "refresh_token": "r2", "expires_in": 3600,
			"user": {"id": ME, "is_anonymous": true}})})
		return
	var i := url.find("/rest/v1/rpc/")
	var rpc := url.substr(i + 13).split("?")[0] if i >= 0 else ""
	if rpc != "":
		_hits[rpc] = _hit(rpc) + 1
	match rpc:
		"referee_flags":
			cb.call({"ok": true, "code": 200, "body": _flags_body} if _flags_body != "" else {"ok": false, "code": 0, "body": ""})
			return
		"referee_submit_gauntlet":
			if _offline_submit:
				cb.call({"ok": false, "code": 0, "body": ""})
				return
			var j = JSON.parse_string(str(b))
			_submit_body = j if j is Dictionary else {}
			cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "job_id": _job, "match_id": MID})})
			return
		"referee_job_status":
			if _offline_status:
				cb.call({"ok": false, "code": 0, "body": ""})
				return
			if not _done:
				cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "pending", "match_id": MID})})
				return
			cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "done", "match_id": MID,
				"won": _srv_won, "score": 0, "gw": _srv_gw, "gl": _srv_gl, "error": null})})
			return
	if str(m) == "GET" and url.find("/rest/v1/matches?") >= 0 and url.find("match_id=eq." + MID) >= 0:
		_hits["matches_get"] = _hit("matches_get") + 1
		cb.call({"ok": true, "code": 200, "body": JSON.stringify([{"match_id": MID, "replay": _rec_b64}])})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


# ─────────────────────────────────────────────────────────────
func _t_pure() -> void:
	print("── 纯函数: 交阵容 / 查任务 回包 ──")
	var s := RN.parse_submit(true, 200, JSON.stringify({"ok": true, "job_id": 7, "match_id": MID}))
	_ok("交阵容: 任务号 + 录像号", str(s.get("err", "?")) == "" and int(s.get("job_id", 0)) == 7 and str(s.get("match_id", "")) == MID)
	_ok("交阵容: 服务端 reason 原样(off / update_required / closed …)", str(RN.parse_submit(true, 200, "{\"ok\":false,\"reason\":\"off\"}").get("err", "")) == "off"
		and str(RN.parse_submit(true, 200, "{\"ok\":false,\"reason\":\"closed\"}").get("err", "")) == "closed")
	_ok("交阵容: 断网 = offline / 404 = unavailable / 回包缺任务号 = server", str(RN.parse_submit(false, 0, "").get("err", "")) == "offline"
		and str(RN.parse_submit(true, 404, "").get("err", "")) == "unavailable"
		and str(RN.parse_submit(true, 200, "{\"ok\":true}").get("err", "")) == "server")
	var st := RN.parse_status(true, 200, JSON.stringify({"ok": true, "status": "done", "match_id": MID, "won": false, "gw": 3, "gl": 2}))
	_ok("查任务: done + 输 + 账本 3-2", str(st.get("status", "")) == "done" and int(st.get("won", -9)) == 0
		and int(st.get("gw", -1)) == 3 and int(st.get("gl", -1)) == 2)
	var st2 := RN.parse_status(true, 200, JSON.stringify({"ok": true, "status": "pending", "match_id": MID, "won": null}))
	_ok("查任务: 还在算 ⇒ 胜负不明(-1)", str(st2.get("status", "")) == "pending" and int(st2.get("won", 0)) == -1)
	var body := RN.submit_body(1, {"a": 1}, {"b": 2}, "9.9.9")
	_ok("请求体键名 = 服务端形参", body.has("p_week") and body.has("p_snapshot") and body.has("p_opponent") and body.has("p_client_version"))


# ─────────────────────────────────────────────────────────────
func _open_mmk() -> Node:
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	await _frames(2)
	var m: Node = (load(MMK_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	return m


func _status_text(m: Node) -> String:
	if m == null or not is_instance_valid(m):
		return ""
	var l := m.find_child("RefereeStatus", true, false) as Label
	return l.text if l != null else ""


func _is_battle(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() == RB


## 等到某个条件成立(墙钟上限; 匹配屏自己有 4.8 秒的真计时器)。
func _wait(pred: Callable, ms: int = 15000) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		if pred.call():
			return true
		await get_tree().process_frame
	return pred.call()


func _snap() -> Dictionary:
	return {"gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses), "coins": int(_gs.meta_deepsea_coins),
		"bt": int(_gs.battles_total), "bw": int(_gs.battles_won), "stb": int(_gs.season_total_battles),
		"mh": (_gs.match_history as Array).size(), "pending": (_gs.referee_pending as Dictionary).duplicate()}


## 跑一场: 匹配屏 → 交阵容 → (门禁当服务器: 裁判算 / 或直接给结果) → done ⇒ 等进战斗场。返回战斗场(没进 = null)。
func _one_match(srv_won_fn: Callable, tamper: bool = false) -> Node:
	_done = false
	_submit_body = {}
	var subs0 := _hit("referee_submit_gauntlet")
	var m: Node = await _open_mmk()
	var got := await _wait(func() -> bool: return _hit("referee_submit_gauntlet") > subs0)
	_ok("分母: 匹配屏交了阵容", got)
	if not got:
		return null
	await _wait(func() -> bool: return _status_text(m) == RW.TXT_SETTLING, 5000)
	_ok("等结果时屏上「%s」、单子已落存档" % RW.TXT_SETTLING, _status_text(m) == RW.TXT_SETTLING
		and int((_gs.referee_pending as Dictionary).get("job_id", -1)) == _job, _status_text(m))
	if _rec.is_empty():
		## 第一次: 按客户端真交上来的两份快照, 由裁判程序真算(与裁判机同一套代码)
		var job: Dictionary = JSON.parse_string(JSON.stringify({"v": 1, "job_id": _job, "match_id": MID, "mode": "gauntlet",
			"key": {"week": 1}, "seed": 2000023, "client_version": str(_submit_body.get("p_client_version", "")),
			"a": _submit_body.get("p_snapshot", {}), "b": _submit_body.get("p_opponent", {})}))
		var res: Dictionary = await RefereeRunner.run(self, job)
		_rec_b64 = str(res.get("replay_b64", ""))
		_a_won = bool(res.get("a_won", false))
		var raw: PackedByteArray = load("res://scripts/systems/replay/replay_fetcher.gd").decode_b64(_rec_b64)
		_rec = ReplayRecorder.decode(raw) if not raw.is_empty() else {}
		_ok("分母: 裁判按交上来的快照算完一场(%d 步, 甲方%s)" % [int(res.get("steps", 0)), "胜" if _a_won else "负"],
			bool(res.get("ok", false)) and not _rec.is_empty(), str(res.get("error", "")))
		if _rec.is_empty():
			return null
	var r2: Dictionary = _rec.duplicate(true)
	if tamper:
		var cps: Array = r2["cps"]
		cps[4] = "0000000000000000"
	_rec_b64 = RU.upload_b64(r2)
	_srv_won = bool(srv_won_fn.call())
	_srv_gw = int(_gs.gauntlet_wins) + (1 if _srv_won else 0)
	_srv_gl = int(_gs.gauntlet_losses) + (0 if _srv_won else 1)
	_done = true
	var ok := await _wait(func() -> bool: return _is_battle(get_tree().current_scene), 20000)
	return get_tree().current_scene if ok else null


func _play_to_end(b: Node) -> void:
	b.set_process(false)
	var guard := 0
	while guard < 4000 and not b._replay.finished and b._replay.diverged_at < 0:
		b._process(0.13)
		guard += 1
		if guard % 6 == 0:
			await get_tree().process_frame


func _settle_title(b: Node) -> String:
	var pr: Node = b.find_child("PageResult", true, false)
	if pr == null:
		return ""
	for c in pr.get_children():
		if c is Label and (str((c as Label).text) == "胜利" or str((c as Label).text) == "失败"):
			return (c as Label).text
	return ""


func _wait_settle(b: Node) -> bool:
	return await _wait(func() -> bool: return is_instance_valid(b) and b.find_child("SettleScreen", true, false) != null, 5000)


func _t_a() -> void:
	print("── A 开关开 · 服务器与本机一致 ──")
	_flags_body = "{\"finals_on\":false,\"gauntlet_on\":true}"
	var s0 := _snap()
	var b: Node = await _one_match(func() -> bool: return _a_won)
	_ok("A ★请求体: 本周 / 我的阵容(三统领)/ 对手快照 / 本机版本",
		int(_submit_body.get("p_week", 0)) == P2C.week_anchor_utc(P2C.now_utc())
		and ((_submit_body.get("p_snapshot", {}) as Dictionary).get("leaders", []) as Array).size() == 3
		and (_submit_body.get("p_opponent", {}) as Dictionary).has("lane_assign")
		and str(_submit_body.get("p_client_version", "")) == ReplayRecorder.client_version(), str(_submit_body.keys()))
	_ok("A ★进了战斗场, 是「播」服务器那一份(裁判局), 不是本机打", b != null and b._replay.is_playing()
		and b._replay.is_live() and str(b._replay.live.kind) == LS.KIND_REFEREE and str(b._replay.rec.get("id", "")) == MID)
	if b == null:
		return
	var s1 := _snap()
	_ok("A ★播之前账已按服务器记完: 战绩 = 服务器账本 %d-%d" % [_srv_gw, _srv_gl],
		int(s1["gw"]) == _srv_gw and int(s1["gl"]) == _srv_gl)
	_ok("A 币 +%d、场次 +1、本大轮场次 +1" % P2C.GAUNTLET_COINS_PER_MATCH, int(s1["coins"]) == int(s0["coins"]) + int(P2C.GAUNTLET_COINS_PER_MATCH)
		and int(s1["bt"]) == int(s0["bt"]) + 1 and int(s1["stb"]) == int(s0["stb"]) + 1)
	var row: Dictionary = (_gs.match_history as Array)[0] if not (_gs.match_history as Array).is_empty() else {}
	_ok("A 战绩页多一行、挂服务器录像号、结果 = 服务器", int(s1["mh"]) == int(s0["mh"]) + 1 and str(row.get("replay_id", "")) == MID
		and str(row.get("result", "")) == ("win" if _srv_won else "lose"), str(row))
	_ok("A 待记账单已清", (s1["pending"] as Dictionary).is_empty())
	b._process(0.02)
	await _frames(2)
	var found: Array = []
	for nm in [RC.N_PAUSE, RC.N_SPEED, RC.N_TIME, "ReplayStrip", "ReplayMark"]:
		if b.find_child(nm, true, false) != null:
			found.append(nm)
	_ok("A ★像看正在打的比赛: 没有「回放」小签、没有暂停 / 倍速 / 进度条", found.is_empty(), str(found))
	await _play_to_end(b)
	_ok("A 放完: 不分叉", b._replay.finished and b._replay.diverged_at < 0, str(b._replay.diverge_why))
	var shown := await _wait_settle(b)
	_ok("A ★放完走正常结算屏(不是回放收尾卡)", shown and b.find_child(RC.N_CARD, true, false) == null)
	_ok("A ★结算屏胜负 = 服务器(%s)" % ("胜利" if _srv_won else "失败"), _settle_title(b) == ("胜利" if _srv_won else "失败"), _settle_title(b))
	_ok("A 回放的「退出」/ 状态牌收起", b.find_child("ReplayControls", true, false) == null
		or not (b.find_child("ReplayControls", true, false) as Control).visible)
	_ok("A 账没有在结算屏再记一遍", int(_gs.gauntlet_wins) == _srv_gw and int(_gs.gauntlet_losses) == _srv_gl
		and (_gs.match_history as Array).size() == int(s0["mh"]) + 1)
	_job += 1


func _t_b() -> void:
	print("── B 服务器说输 · 本机重算说赢 ⇒ 以服务器为准 ──")
	var s0 := _snap()
	var b: Node = await _one_match(func() -> bool: return not _a_won)
	_ok("B ★分母: 录像里我赢、服务器说我输(录像: %s / 服务器: %s)" % ["胜" if _a_won else "负", "胜" if _srv_won else "负"],
		_a_won and not _srv_won and b != null)
	if b == null:
		return
	_ok("B ★战绩按服务器记(%s)" % ("胜" if _srv_won else "负"),
		int(_gs.gauntlet_wins) == int(s0["gw"]) + (1 if _srv_won else 0) and int(_gs.gauntlet_losses) == int(s0["gl"]) + (0 if _srv_won else 1)
		and str(((_gs.match_history as Array)[0] as Dictionary).get("result", "")) == ("win" if _srv_won else "lose"))
	await _play_to_end(b)
	_ok("B 放完(录像自洽, 不分叉)", b._replay.finished and b._replay.diverged_at < 0)
	await _wait_settle(b)
	_ok("B ★结算屏写服务器的结果「%s」" % ("胜利" if _srv_won else "失败"), _settle_title(b) == ("胜利" if _srv_won else "失败"), _settle_title(b))
	_job += 1


func _t_c() -> void:
	print("── C 录像在本机对不上 ──")
	var s0 := _snap()
	var b: Node = await _one_match(func() -> bool: return _a_won, true)
	_ok("C 分母: 进了战斗场", b != null)
	if b == null:
		return
	_ok("C 战绩照记(服务器)", int(_gs.gauntlet_wins) + int(_gs.gauntlet_losses) == int(s0["gw"]) + int(s0["gl"]) + 1)
	await _play_to_end(b)
	_ok("C ★分母: 第 5 个校验点停下(%d 步)" % int(b._replay.diverged_at), b._replay.diverged_at > 0)
	await _wait_settle(b)
	_ok("C ★结算屏照样出、胜负 = 服务器", _settle_title(b) == ("胜利" if _srv_won else "失败"), _settle_title(b))
	var note := b.find_child("RefereeUnplayable", true, false) as Label
	_ok("C ★结算屏上写「%s」" % RW.TXT_UNPLAYABLE, note != null and note.text == RW.TXT_UNPLAYABLE)
	_job += 1


func _t_d() -> void:
	print("── D 断网点开战 ⇒ 不出本地成绩 ──")
	_offline_submit = true
	_flags_body = ""                  # 问开关也问不到(存档里那份: 开)
	var s0 := _snap()
	var subs0 := _hit("referee_submit_gauntlet")
	var m: Node = await _open_mmk()
	await _wait(func() -> bool: return _status_text(m) == RW.TXT_NEED_SERVER, 15000)
	_ok("D 分母: 真去交了(断网)", _hit("referee_submit_gauntlet") == subs0 + 1)
	_ok("D ★屏上「%s」" % RW.TXT_NEED_SERVER, _status_text(m) == RW.TXT_NEED_SERVER, _status_text(m))
	await _frames(60)
	_ok("D ★没进战斗场(没有本地对局)", not _is_battle(get_tree().current_scene) and get_tree().current_scene == m)
	var s1 := _snap()
	_ok("D ★战绩 / 币 / 场次 / 战绩页一个都没动、没有待记账单", s1 == s0, "%s → %s" % [str(s0), str(s1)])
	_offline_submit = false


func _t_e() -> void:
	print("── E 交上去之后断网 / 杀进程 ⇒ 下次补记 ──")
	_flags_body = "{\"finals_on\":false,\"gauntlet_on\":true}"
	_done = false
	var s0 := _snap()
	var subs0 := _hit("referee_submit_gauntlet")
	var m: Node = await _open_mmk()
	await _wait(func() -> bool: return _hit("referee_submit_gauntlet") > subs0)
	_offline_status = true
	await _wait(func() -> bool: return _status_text(m) == RW.TXT_LATER, 20000)
	_ok("E ★问不到结果 ⇒「%s」" % RW.TXT_LATER, _status_text(m) == RW.TXT_LATER, _status_text(m))
	_ok("E 单子留着(这一场)、战绩没动", int((_gs.referee_pending as Dictionary).get("job_id", -1)) == _job
		and int(_gs.gauntlet_wins) == int(s0["gw"]) and int(_gs.gauntlet_losses) == int(s0["gl"]))
	## 杀进程: 匹配屏没了(待记账单在存档里)
	m.queue_free()
	await _frames(3)
	_offline_status = false
	_done = true
	_srv_won = true
	_srv_gw = int(s0["gw"]) + 1
	_srv_gl = int(s0["gl"])
	var got: Array = []
	var sent: bool = RW.resume_if_any(func(v: Dictionary) -> void: got.append(v))
	await _wait(func() -> bool: return not got.is_empty(), 5000)
	_ok("E ★下次开主菜单: 查任务 ⇒ 补记一次(胜)", sent and got.size() == 1 and bool((got[0] as Dictionary).get("won", false)))
	_ok("E 补记后战绩 = 服务器账本、币 +%d、单子清掉" % P2C.GAUNTLET_COINS_PER_MATCH, int(_gs.gauntlet_wins) == _srv_gw
		and int(_gs.gauntlet_losses) == _srv_gl and int(_gs.meta_deepsea_coins) == int(s0["coins"]) + int(P2C.GAUNTLET_COINS_PER_MATCH)
		and (_gs.referee_pending as Dictionary).is_empty())
	var s1 := _snap()
	var again: bool = RW.resume_if_any(func(v: Dictionary) -> void: got.append(v))
	await _frames(30)
	_ok("E ★再开一次不重复记(没有单子 ⇒ 不发)", not again and got.size() == 1 and _snap() == s1)
	## 同一单被匹配屏那条路记过之后, 主菜单那条路拿到同一个结果也不再记
	_ok("E ★记账只认单子上那个任务号(重复回包 = 不记)", RW.settle(_gs, _job, {"won": 1, "gw": 9, "gl": 9}).is_empty() and _snap() == s1)
	## 单子上是另一个任务(比如重新开战之后)⇒ 旧任务的回包不许记到这一单上
	_gs.referee_pending = {"job_id": 777, "match_id": MID, "week": P2C.week_anchor_utc(P2C.now_utc())}
	_ok("E ★单子是 777、回包是 %d ⇒ 不记、单子不动" % _job, RW.settle(_gs, _job, {"won": 1, "gw": 9, "gl": 9}).is_empty()
		and int((_gs.referee_pending as Dictionary).get("job_id", -1)) == 777 and int(_gs.gauntlet_wins) == _srv_gw)
	## 换周: 上一周交的那一场不记进这一周
	_gs.referee_pending = {"job_id": 555, "match_id": MID, "week": P2C.week_anchor_utc(P2C.now_utc()) - 7 * 86400}
	_ok("E 上一周的单子 ⇒ 不记、销单", RW.settle(_gs, 555, {"won": 1, "gw": 9, "gl": 9}).is_empty()
		and (_gs.referee_pending as Dictionary).is_empty() and int(_gs.gauntlet_wins) == _srv_gw)
	_job += 1


func _t_f() -> void:
	print("── F 开关关 ⇒ 老路 ──")
	_flags_body = "{\"finals_on\":false,\"gauntlet_on\":false}"
	_gs.referee_flags = {RN.K_FINALS: false, RN.K_GAUNTLET: false}
	var subs0 := _hit("referee_submit_gauntlet")
	_left_hook = 0
	MMK._may_leave_for_test = func(_dest: String) -> bool:
		_left_hook += 1
		return false
	var m: Node = await _open_mmk()
	await _wait(func() -> bool: return _left_hook > 0, 15000)
	_ok("F ★开关关: 走到「去战斗场」那一步(老路本机打)", _left_hook == 1)
	_ok("F ★一次都没交给服务器、屏上没有裁判那一行", _hit("referee_submit_gauntlet") == subs0 and _status_text(m) == "")
	MMK._may_leave_for_test = Callable()
	m.queue_free()
	await _frames(3)


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 周六闯关交给服务器" if _fail == 0 and _n >= 50 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
