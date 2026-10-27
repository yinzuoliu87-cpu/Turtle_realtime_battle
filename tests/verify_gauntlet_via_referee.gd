extends Node
## verify_gauntlet_via_referee.gd — 周六闯关交给服务器裁判(方案书 docs/plans/20261019-服务器裁判.md §3 ②)。
##
## 用户 10-19「周六周日让服务器记」; 问题总表 B1「断网点开战 ⇒ 不出本地成绩」。
## 全程走产品自己的入口: 匹配屏(真场景, 真计时器)→ `referee_run.gd` → 注入传输(不连网);
##   「服务器」那一份录像由 RefereeRunner(裁判机上跑的同一套代码)按客户端真交上来的两份快照真算出来。
##
## 段落:
##   A 开关开 · 一致: 交阵容(请求体五个形参: 周 / 阵容 / 第几场 / 版本 / 规则版本 —— 没有对手、没有种子; 2026-10-20 起对手由服务端挑)
##     → VS 卡画的是服务端回的对手 → 轮询 → done ⇒ 播之前账已按服务器记完(战绩 = 服务器账本 / 币 = 场次币 + 服务器那一局的战斗内铸币 /
##     战绩页挂录像号 / 单子清掉)
##     ⇒ 进战斗场是「播」(裁判局: 没有「回放」小签、没有播放控件)⇒ 放完走正常结算屏, 胜负 = 服务器
##   B ★服务器说输、本地重算说赢 ⇒ 记输、结算屏写「失败」(以服务器为准)
##   C 录像在本机对不上(改坏一个校验点)⇒ 停下, 结算屏照样按服务器结果出 + 「录像无法在本设备播放」; 战绩照记
##   D 断网点开战 ⇒ 屏上「连接服务器后才能比赛」, 不进战斗场、战绩 / 币 / 场次 / 战绩页一个都不动、没有待记账单
##   E 交上去之后断网 ⇒「稍后自动记入战绩」、单子留着、匹配屏走主菜单那个出口(2026-10-22; 等到上限那一支见 verify_referee_wait_timeout);
##     杀进程(匹配屏没了)⇒ 下次开主菜单补记一次, 再来一次不重复记
##   F 开关关 ⇒ 老路: 走到「去战斗场」那一步、一次都不交
## A~F 每条判据都做过反向验证(改坏 → 红 → 逐字节还原), 见方案书「验收清单」那一行。
## ── 晋级仪式(2026-10-27 · 方案书 docs/plans/20261026c-周末弹窗美术.md; 只读排查路径 ⑤⑥: 这两条路第 4 胜原来一次仪式都不演) ──
##   A / C 回归: 第 2 胜 / 第 3 胜(差一胜)那一局 ⇒ 结算屏上不演晋级仪式
##   E2 ★E 补记的那一场正好是第 4 胜 ⇒ 真主菜单(current_scene)的 `_on_referee_resumed` 补演「闯关赛 → 决赛日」, 点掉再飘补记那句;
##      再查一次不再演; 对照: 补记的是输 / 补记的胜局不是第 4 胜 ⇒ 不演、当场飘字
##   G ★第 4 胜账已按服务器记、取录像失败(停在匹配屏「…录像无法在本设备播放」)⇒ 匹配屏补演、只演一次; 对照: 输了那一局 ⇒ 不演
##   ⚠ 这一组写成时本机禁跑 Godot(蓝屏排查中), 还没跑过、也还没做反向验证 —— 解禁后先跑通, 再按上面的规矩逐条改坏验红。
## ── 2026-10-27 周六改在线排队(docs/plans/20261027b-闯关赛在线瑞士轮.md)──
##   交阵容那一步换成 `gauntlet_queue_join`(锁阵容进队); 本门禁的假服务器让它当场配上(我是 a、对手 = 机器人池那一份),
##   之后的等结果 / 记账 / 播 / 补记一字不变 —— A~G 量的需求没变, 只是「交」的接口与形状变了:
##   请求体从 5 个键变 3 个(周 / 阵容 / 第几场), 版本与规则版本改走请求头(X-Client-Version / X-Rules-Ver, 服务端两个形参有默认值)。
##   排队本身(等待界面 / 心跳 / 取消 / 过期 / B 方)见 verify_gauntlet_online_queue。

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
const BP := preload("res://scripts/referee/bot_pool.gd")
const SC := preload("res://scripts/scenes/stage_ceremony.gd")
const WCC := preload("res://scripts/scenes/week_close_card.gd")
const MENU := preload("res://scripts/scenes/MainMenuScene.gd")
## 交阵容的那一条 RPC: 2026-10-27 起是进队(在线排队), 原来是 referee_gauntlet_start(当场回对手快照; 现在只在服务端没有排队时退回)
const START := "gauntlet_queue_join"

var _fail := 0
var _n := 0
var _gs
var _flags_body := ""
var _hits := {}
var _submit_body: Dictionary = {}
var _submit_hdr: Array = []       # 交阵容那一次的请求头(版本 / 规则版本 2026-10-27 起走这里)
var _job := 100
var _done := false
var _srv_won := false
var _srv_gw := 0
var _srv_gl := 0
var _offline_submit := false
var _offline_status := false
var _rec_b64 := ""                # 服务器 matches 行里的录像
var _srv_b: Dictionary = {}       # 门禁当服务器: 服务端挑的对手(机器人池那一份 + gl_ts)
var _srv_coins := 0               # 服务器那一局的战斗内铸币(裁判结果单 coins)
var _rec: Dictionary = {}
var _a_won := false
var _left_hook := 0
var _offline_match := false       # 取录像(matches)断网: 账已记、录像取不到 ⇒ 匹配屏停在「…录像无法在本设备播放」(G 段)
var _e_view: Dictionary = {}      # E 段主菜单补记回调拿到的那一份结果单(E2 段原样交给真主菜单)


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
	await _t_e2()
	await _t_f()
	await _t_g()
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
	## ★第一件是 035 黄铜齿轮(2026-10-20): 服务器那一局要有战斗内铸币, A 段才量得到「币 = 场次币 + 服务器的铸币」。
	var shop: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1 and str((e as Dictionary)["id"]) != "p2eq_035":
			shop.append(str((e as Dictionary)["id"]))
	var k := 0
	var pe := {}
	for pid in _gs.season_leaders:
		var l: Array = [{"id": "p2eq_035", "star": 3}]
		for _j in range(2):
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


func _transport(m, u, h, b, cb) -> void:
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
		START:
			if _offline_submit:
				cb.call({"ok": false, "code": 0, "body": ""})
				return
			var j = JSON.parse_string(str(b))
			_submit_body = j if j is Dictionary else {}
			_submit_hdr = Array(h) if (h is PackedStringArray or h is Array) else []
			## 进队当场配上(本格子有人在等 / 兜底到机器人池): 对手 = 机器人池那一份(场次 = max(本大轮场次, gw + gl), 与 SQL 同口径)
			var gw := int(_gs.gauntlet_wins)
			var gl := int(_gs.gauntlet_losses)
			_srv_b = BP.one(maxi(int(_gs.season_total_battles), gw + gl), gw, gl, 0)
			_srv_b["gl_ts"] = int(P2C.now_utc()) - 300
			cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "paired", "job_id": _job, "match_id": MID,
				"side": "a", "opp": {"profile": _srv_b["profile"], "leaders": _srv_b["leaders"]}, "gw": gw, "gl": gl})})
			return
		"referee_job_status":
			if _offline_status:
				cb.call({"ok": false, "code": 0, "body": ""})
				return
			if not _done:
				cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "pending", "match_id": MID})})
				return
			cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "done", "match_id": MID,
				"won": _srv_won, "score": 0, "gw": _srv_gw, "gl": _srv_gl, "coins": _srv_coins, "error": null})})
			return
	if str(m) == "GET" and url.find("/rest/v1/matches?") >= 0 and url.find("match_id=eq." + MID) >= 0:
		_hits["matches_get"] = _hit("matches_get") + 1
		if _offline_match:
			cb.call({"ok": false, "code": 0, "body": ""})
			return
		cb.call({"ok": true, "code": 200, "body": JSON.stringify([{"match_id": MID, "replay": _rec_b64}])})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


# ─────────────────────────────────────────────────────────────
func _t_pure() -> void:
	print("── 纯函数: 交阵容 / 查任务 回包 ──")
	var opp := {"profile": {"name": "kevin_99", "avatar": "ninja", "id": "g_x", "tag": "#ABCDEF"}, "leaders": ["ninja", "dice", "pirate"]}
	## 2026-10-27 起交阵容 = 进队(gauntlet_queue_join), 当场配上时回包同形(多 status / side); 量的需求不变
	var s := RN.parse_queue(true, 200, JSON.stringify({"ok": true, "status": "paired", "side": "a", "job_id": 7, "match_id": MID, "opp": opp}))
	_ok("交阵容: 任务号 + 录像号 + 对手卡片", str(s.get("err", "?")) == "" and int(s.get("job_id", 0)) == 7 and str(s.get("match_id", "")) == MID
		and str(((s.get("opp", {}) as Dictionary).get("profile", {}) as Dictionary).get("name", "")) == "kevin_99")
	_ok("交阵容: 服务端 reason 原样(off / update_required / closed …)", str(RN.parse_queue(true, 200, "{\"ok\":false,\"reason\":\"off\"}").get("err", "")) == "off"
		and str(RN.parse_queue(true, 200, "{\"ok\":false,\"reason\":\"closed\"}").get("err", "")) == "closed")
	_ok("交阵容: 断网 = offline / 404 = unavailable / 回包缺状态 = server", str(RN.parse_queue(false, 0, "").get("err", "")) == "offline"
		and str(RN.parse_queue(true, 404, "").get("err", "")) == "unavailable"
		and str(RN.parse_queue(true, 200, "{\"ok\":true}").get("err", "")) == "server")
	var st := RN.parse_status(true, 200, JSON.stringify({"ok": true, "status": "done", "match_id": MID, "won": false, "gw": 3, "gl": 2}))
	_ok("查任务: done + 输 + 账本 3-2", str(st.get("status", "")) == "done" and int(st.get("won", -9)) == 0
		and int(st.get("gw", -1)) == 3 and int(st.get("gl", -1)) == 2)
	var st2 := RN.parse_status(true, 200, JSON.stringify({"ok": true, "status": "pending", "match_id": MID, "won": null}))
	_ok("查任务: 还在算 ⇒ 胜负不明(-1)", str(st2.get("status", "")) == "pending" and int(st2.get("won", 0)) == -1)
	var body := RN.queue_join_body(1, {"a": 1}, 0)
	_ok("请求体键名 = 服务端形参(没有对手 / 种子; 版本走请求头)", body.keys() == ["p_week", "p_snapshot", "p_match_no"], str(body.keys()))


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
	var subs0 := _hit(START)
	var m: Node = await _open_mmk()
	var got := await _wait(func() -> bool: return _hit(START) > subs0)
	_ok("分母: 匹配屏交了阵容", got)
	if not got:
		return null
	await _wait(func() -> bool: return _status_text(m) == RW.TXT_SETTLING, 8000)
	_ok("等结果时屏上「%s」、单子已落存档" % RW.TXT_SETTLING, _status_text(m) == RW.TXT_SETTLING
		and int((_gs.referee_pending as Dictionary).get("job_id", -1)) == _job, _status_text(m))
	var nm := str((_srv_b.get("profile", {}) as Dictionary).get("name", ""))
	await _wait(func() -> bool: return _has_label(m, nm), 8000)
	_ok("★VS 卡上是服务端挑的对手「%s」(本机没挑)" % nm, nm != "" and _has_label(m, nm)
		and str((_gs.dual_opponent as Dictionary).get("name", "")) == nm)
	_ok("VS 卡下面那一行仍是「%s」(翻卡没把进度行弄丢)" % RW.TXT_SETTLING, _status_text(m) == RW.TXT_SETTLING, _status_text(m))
	if _rec.is_empty():
		## 第一次: 按客户端真交上来的两份快照, 由裁判程序真算(与裁判机同一套代码)
		var job: Dictionary = JSON.parse_string(JSON.stringify({"v": 1, "job_id": _job, "match_id": MID, "mode": "gauntlet",
			"key": {"week": 1}, "seed": 2000023, "client_version": _hdr_version(),
			"a": _submit_body.get("p_snapshot", {}), "b": _srv_b}))
		var res: Dictionary = await RefereeRunner.run(self, job)
		_rec_b64 = str(res.get("replay_b64", ""))
		_a_won = bool(res.get("a_won", false))
		_srv_coins = int(res.get("coins", 0))
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


## 交阵容那一次请求头里的版本(2026-10-27 起版本走请求头 X-Client-Version)。
func _hdr_version() -> String:
	for x in _submit_hdr:
		if str(x).begins_with(SB.HDR_CLIENT_VERSION + ":"):
			return str(x).substr(str(x).find(":") + 1).strip_edges()
	return ""


func _has_hdr(name: String, val: String) -> bool:
	for x in _submit_hdr:
		if str(x).begins_with(name + ":") and str(x).substr(str(x).find(":") + 1).strip_edges() == val:
			return true
	return false


func _has_label(root: Node, text: String) -> bool:
	for c in root.find_children("*", "Label", true, false):
		if is_instance_valid(c) and not (c as Node).is_queued_for_deletion() and str((c as Label).text) == text:
			return true
	return false


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
	## 逐层找: 胜负大字 10-27 起套在 ResultSlot 里(像素标题从左滑入), 不再是 PageResult 的直接子节点。
	for c in pr.find_children("*", "Label", true, false):
		if str((c as Label).text) == "胜利" or str((c as Label).text) == "失败":
			return (c as Label).text
	return ""


func _wait_settle(b: Node) -> bool:
	return await _wait(func() -> bool: return is_instance_valid(b) and b.find_child("SettleScreen", true, false) != null, 5000)


## host 下面直接挂着的整屏晋级仪式(`StageCeremony.play` 建的)。
##   ★按名字 + meta "to" 两样认: 同一个父节点下再建第二层, 引擎会把它改名成 @ColorRect@N, 只按名字数会漏掉「叠了两层」。
func _ceremonies(host: Node) -> Array:
	var out: Array = []
	if host == null or not is_instance_valid(host):
		return out
	for c in host.get_children():
		if not (c as Node).is_queued_for_deletion() and (str(c.name) == SC.NODE_NAME or (c as Node).has_meta("to")):
			out.append(c)
	return out


## 点一下(与 verify_weekend_close_cards ⑨ 同一个造法: 直接对仪式那一层发鼠标按下)。
func _tap(n: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	n.gui_input.emit(ev)


## 主菜单上正飘着的那几行(`_toast` 建的: 直接挂在主菜单下的 Label; 同 verify_referee_wait_timeout `_toasts`)。
func _menu_toasts(menu: Node) -> Array:
	var out: Array = []
	if menu == null or not is_instance_valid(menu):
		return out
	for c in menu.get_children():
		if c is Label and not (c as Node).is_queued_for_deletion():
			out.append(str((c as Label).text))
	return out


func _is_menu(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() == MENU


## 真主菜单当 current_scene 建起来(收盘卡只在 current_scene == 主菜单时弹 —— 玩家真走到的那一屏)。
func _open_menu() -> Node:
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	await _frames(2)
	var mm: Node = (load(RW.MAIN_MENU) as PackedScene).instantiate()
	get_tree().root.add_child(mm)
	get_tree().current_scene = mm
	return mm


## 匹配屏上那一场(referee_run.gd)此刻的状态; 屏没了 / 还没建 = ""。
func _run_state(m) -> String:
	if m == null or not is_instance_valid(m):
		return ""
	var r = (m as Node).get("_ref_run")
	return str(r.state) if r != null and is_instance_valid(r) else ""


func _t_a() -> void:
	print("── A 开关开 · 服务器与本机一致 ──")
	_flags_body = "{\"finals_on\":false,\"gauntlet_on\":true}"
	var s0 := _snap()
	var b: Node = await _one_match(func() -> bool: return _a_won)
	## ★2026-10-27 改断言(量的需求不变: 服务端认得出「本周 / 我的阵容 / 第几场 / 版本 / 规则版本」, 客户端指定不了对手与种子):
	##   交阵容换成进队 gauntlet_queue_join(p_week, p_snapshot, p_match_no); 版本 / 规则版本从请求体挪到请求头。
	_ok("A ★请求体: 本周 / 我的阵容(三统领)/ 第几场 = gw + gl; 请求头: 本机版本 / 规则版本",
		int(_submit_body.get("p_week", 0)) == P2C.week_anchor_utc(P2C.now_utc())
		and ((_submit_body.get("p_snapshot", {}) as Dictionary).get("leaders", []) as Array).size() == 3
		and int(_submit_body.get("p_match_no", -1)) == int(s0["gw"]) + int(s0["gl"])
		and _has_hdr(SB.HDR_CLIENT_VERSION, ReplayRecorder.client_version())
		and _has_hdr(SB.HDR_RULES_VER, str(int(P2C.RULES_VER))), "%s / %s" % [str(_submit_body.keys()), str(_submit_hdr)])
	_ok("A ★请求体里没有对手 / 种子(客户端指定不了)", not _submit_body.has("p_opponent") and not _submit_body.has("p_seed")
		and _submit_body.size() == 3, str(_submit_body.keys()))
	_ok("A ★进了战斗场, 是「播」服务器那一份(裁判局), 不是本机打", b != null and b._replay.is_playing()
		and b._replay.is_live() and str(b._replay.live.kind) == LS.KIND_REFEREE and str(b._replay.rec.get("id", "")) == MID)
	if b == null:
		return
	var s1 := _snap()
	_ok("A ★播之前账已按服务器记完: 战绩 = 服务器账本 %d-%d" % [_srv_gw, _srv_gl],
		int(s1["gw"]) == _srv_gw and int(s1["gl"]) == _srv_gl)
	_ok("分母: 服务器那一局有战斗内铸币(我方带 035 齿轮: %d 枚)" % _srv_coins, _srv_coins > 0)
	_ok("A ★币 + 场次币 %d + 服务器那一局的铸币 %d、场次 +1、本大轮场次 +1" % [P2C.GAUNTLET_COINS_PER_MATCH, _srv_coins],
		int(s1["coins"]) == int(s0["coins"]) + int(P2C.GAUNTLET_COINS_PER_MATCH) + _srv_coins
		and int(s1["bt"]) == int(s0["bt"]) + 1 and int(s1["stb"]) == int(s0["stb"]) + 1, "%d → %d" % [int(s0["coins"]), int(s1["coins"])])
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
	## 晋级仪式回归: 这一局走过结算屏的晋级判据(闯关赛口径)、而且是胜局 —— 只是没到第 4 胜(否则这条是空检查)
	_ok("A 分母: 结算屏按闯关赛口径判过「是不是晋级那一局」(服务器判赢、%d-%d、还没到晋级线)" % [int(_gs.gauntlet_wins), int(_gs.gauntlet_losses)],
		shown and bool(b._had_season) and str(b._last_settle_kind) == P2C.SETTLE_GAUNTLET and _srv_won
		and str(_gs.gauntlet_state()) != P2C.GAUNTLET_IN, "kind=%s state=%s" % [str(b._last_settle_kind), str(_gs.gauntlet_state())])
	_ok("A ★回归: 普通胜局(第 %d 胜)⇒ 结算屏上不演晋级仪式" % int(_gs.gauntlet_wins), b.find_child(SC.NODE_NAME, true, false) == null)
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
	## 晋级仪式回归: 第 3 胜 = 差一胜晋级, 离判据边界最近的那一局
	_ok("C 分母: 结算屏按闯关赛口径判过晋级(服务器判赢、%d-%d、差一胜)" % [int(_gs.gauntlet_wins), int(_gs.gauntlet_losses)],
		b.find_child("SettleScreen", true, false) != null and bool(b._had_season) and str(b._last_settle_kind) == P2C.SETTLE_GAUNTLET
		and _srv_won and int(_gs.gauntlet_wins) == int(P2C.GAUNTLET_WINS_IN) - 1 and str(_gs.gauntlet_state()) != P2C.GAUNTLET_IN,
		"kind=%s %d-%d" % [str(b._last_settle_kind), int(_gs.gauntlet_wins), int(_gs.gauntlet_losses)])
	_ok("C ★回归: 第 %d 胜(还差一胜)⇒ 结算屏上不演晋级仪式" % int(_gs.gauntlet_wins), b.find_child(SC.NODE_NAME, true, false) == null)
	_job += 1


func _t_d() -> void:
	print("── D 断网点开战 ⇒ 不出本地成绩 ──")
	_offline_submit = true
	_flags_body = ""                  # 问开关也问不到(存档里那份: 开)
	var s0 := _snap()
	var subs0 := _hit(START)
	var m: Node = await _open_mmk()
	await _wait(func() -> bool: return _status_text(m) == RW.TXT_NEED_SERVER, 15000)
	_ok("D 分母: 真去交了(断网)", _hit(START) == subs0 + 1)
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
	var subs0 := _hit(START)
	var m: Node = await _open_mmk()
	await _wait(func() -> bool: return _hit(START) > subs0)
	## 匹配屏问不到结果会自己走主菜单那个出口: 缝拦在离开之前(记下出口), 这一段量的是「杀进程之后下次补记」
	var dests: Array = []
	MMK._may_leave_for_test = func(dest: String) -> bool:
		dests.append(dest)
		return false
	_offline_status = true
	await _wait(func() -> bool: return _status_text(m) == RW.TXT_LATER, 20000)
	_ok("E ★问不到结果 ⇒「%s」" % RW.TXT_LATER, _status_text(m) == RW.TXT_LATER, _status_text(m))
	_ok("E ★不停在匹配屏: 走主菜单那个出口(一次)", dests == [MMK.MENU_SCENE], str(dests))
	MMK._may_leave_for_test = Callable()
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
	## ★2026-10-26 打到第 4 胜那一场当场发「省下的场次」(GameState.gauntlet_promote_bonus, 按服务端战绩算) ⇒ 期望值里加上这一笔
	var bonus0: int = int(_gs.gauntlet_backfill_paid)
	var bonus_c: int = maxi(0, P2C.gauntlet_backfill_owed(_srv_gw, _srv_gl) - bonus0) * int(P2C.GAUNTLET_BACKFILL_COINS)
	var got: Array = []
	var sent: bool = RW.resume_if_any(func(v: Dictionary) -> void: got.append(v))
	await _wait(func() -> bool: return not got.is_empty(), 5000)
	_ok("E ★下次开主菜单: 查任务 ⇒ 补记一次(胜)", sent and got.size() == 1 and bool((got[0] as Dictionary).get("won", false)))
	_ok("E 补记后战绩 = 服务器账本、币 +%d + 铸币 %d + 晋级当场发 %d、单子清掉" % [P2C.GAUNTLET_COINS_PER_MATCH, _srv_coins, bonus_c], int(_gs.gauntlet_wins) == _srv_gw
		and int(_gs.gauntlet_losses) == _srv_gl and int(_gs.meta_deepsea_coins) == int(s0["coins"]) + int(P2C.GAUNTLET_COINS_PER_MATCH) + _srv_coins + bonus_c
		and (_gs.referee_pending as Dictionary).is_empty(), "战绩 %d-%d / 钱包 %d" % [int(_gs.gauntlet_wins), int(_gs.gauntlet_losses), int(_gs.meta_deepsea_coins)])
	## E2 段要的前提: 补记的这一场正好是第 4 胜(补记前 3 胜 ⇒ 补记后进入晋级 IN)。这一场没有结算屏, 仪式只能由补记那条路演。
	_ok("E ★分母: 补记的这一场正好是第 %d 胜(%d-%d → %d-%d · 闯关赛已晋级)" % [int(P2C.GAUNTLET_WINS_IN), int(s0["gw"]), int(s0["gl"]),
		int(_gs.gauntlet_wins), int(_gs.gauntlet_losses)], int(s0["gw"]) == int(P2C.GAUNTLET_WINS_IN) - 1
		and int(_gs.gauntlet_wins) == int(P2C.GAUNTLET_WINS_IN) and str(_gs.gauntlet_state()) == P2C.GAUNTLET_IN, str(_gs.gauntlet_state()))
	_e_view = (got[0] as Dictionary).duplicate(true) if got.size() == 1 else {}
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


## E2: E 补记的那一场正好是第 4 胜 ⇒ 主菜单补演晋级仪式(只读排查路径 ⑤: 原来 `_on_referee_resumed` 只飘一行字, 这次晋级永远看不到)。
##   ★走真主菜单(current_scene)的真回调 `_on_referee_resumed`, 交给它的是 E 段补记回调真拿到的那一份结果单;
##   补记本身(`resume_if_any` → `settle` → 回调)E 段量过, 主菜单开场 / 计时器接到这个回调见 verify_referee_wait_timeout B。
func _t_e2() -> void:
	print("── E2 主菜单补记的那一场正好是第 4 胜 ⇒ 补演晋级仪式, 点掉再飘补记那句 ──")
	var v: Dictionary = _e_view
	_ok("E2 分母: E 段补记回调拿到的结果单是胜、战绩已在晋级线上(%d-%d)、没有待记账单" % [int(_gs.gauntlet_wins), int(_gs.gauntlet_losses)],
		bool(v.get("won", false)) and str(_gs.gauntlet_state()) == P2C.GAUNTLET_IN and (_gs.referee_pending as Dictionary).is_empty(), str(v))
	if v.is_empty():
		return
	## 收盘卡(周五积分赛收盘后第一次进主菜单那一串)本周记成已弹: 它也是整屏, 晋级仪式会排队等它关掉 —— 这一段量的不是它
	var anchor: int = P2C.week_anchor_utc(P2C.now_utc())
	_gs.close_card_ranked_wk = anchor
	_gs.close_card_gauntlet_wk = anchor
	RW.notice = ""
	var mm: Node = await _open_menu()
	await _wait(func() -> bool: return is_instance_valid(mm) and mm.get("content_root") != null, 8000)
	await _frames(10)
	_ok("E2 分母: 真主菜单是 current_scene、建起来了、开场没有整屏仪式 / 收盘卡在场",
		_is_menu(mm) and get_tree().current_scene == mm and mm.get("content_root") != null
		and _ceremonies(mm).is_empty() and mm.get_node_or_null(WCC.NODE_NAME) == null, "仪式 %d 个" % _ceremonies(mm).size())
	if not _is_menu(mm) or mm.get("content_root") == null:
		return
	mm._on_referee_resumed(v)
	var cs: Array = _ceremonies(mm)
	var to_k := str((cs[0] as Node).get_meta("to", "")) if cs.size() == 1 else ""
	_ok("E2 ★补记的是第 %d 胜 ⇒ 主菜单上演晋级仪式(闯关赛 → 决赛日)" % int(P2C.GAUNTLET_WINS_IN), cs.size() == 1 and to_k == P2C.PHASE_FINALS,
		"仪式 %d 个 · to=%s" % [cs.size(), to_k])
	_ok("E2 演完再飘: 仪式开着时还没飘「%s」(一屏一件事)" % RW.TXT_RESUMED_WIN, not _menu_toasts(mm).has(RW.TXT_RESUMED_WIN), str(_menu_toasts(mm)))
	## 再查一次(主菜单查任务的计时器到点 / 再开一次主菜单那一查): 单子已清 ⇒ 不发、不回调 ⇒ 不会再演一遍
	var again: bool = RW.resume_if_any(Callable(mm, "_on_referee_resumed"))
	mm._referee_resume_tick()
	await _frames(10)
	_ok("E2 ★再查一次不再演第二遍(单子已清 ⇒ 不回调; 仪式仍只有 1 个)", not again and _ceremonies(mm).size() == 1,
		"发了=%s 仪式 %d 个" % [str(again), _ceremonies(mm).size()])
	if cs.size() != 1:
		mm.queue_free()
		await _frames(3)
		return
	_tap(cs[0] as Control)
	_ok("E2 ★点掉仪式 ⇒ 飘补记那句「%s」" % RW.TXT_RESUMED_WIN, _menu_toasts(mm).has(RW.TXT_RESUMED_WIN), str(_menu_toasts(mm)))
	await _frames(10)
	_ok("E2 仪式关掉了、之后没有再冒出一层", _ceremonies(mm).is_empty() and not is_instance_valid(cs[0]), "仪式 %d 个" % _ceremonies(mm).size())
	## 对照 1: 补记的是输。战绩同样摆在晋级线上(IN), 与上面只差胜负这一维 —— 判据丢了「赢」这一条就会红。
	var lose0: int = _menu_toasts(mm).count(RW.TXT_RESUMED_LOSE)
	mm._on_referee_resumed({"won": false, "reward": 0, "coins": 0, "gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses)})
	_ok("E2 对照: 补记的是输(战绩同在晋级线上, 只差胜负)⇒ 不演、当场飘「%s」" % RW.TXT_RESUMED_LOSE,
		_ceremonies(mm).is_empty() and _menu_toasts(mm).count(RW.TXT_RESUMED_LOSE) == lose0 + 1, str(_menu_toasts(mm)))
	## 对照 2: 补记的胜局不是第 4 胜(补记后 3-1)。与上面只差「到没到晋级线」这一维 —— 判据丢了战绩那一条就会红。
	var gw0 := int(_gs.gauntlet_wins)
	var gl0 := int(_gs.gauntlet_losses)
	_gs.gauntlet_wins = int(P2C.GAUNTLET_WINS_IN) - 1
	_gs.gauntlet_losses = 1
	var win0: int = _menu_toasts(mm).count(RW.TXT_RESUMED_WIN)
	mm._on_referee_resumed({"won": true, "reward": 0, "coins": 0, "gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses)})
	_ok("E2 对照: 补记的胜局不是第 %d 胜(%d-%d)⇒ 不演、当场飘「%s」" % [int(P2C.GAUNTLET_WINS_IN), int(_gs.gauntlet_wins),
		int(_gs.gauntlet_losses), RW.TXT_RESUMED_WIN], str(_gs.gauntlet_state()) != P2C.GAUNTLET_IN
		and _ceremonies(mm).is_empty() and _menu_toasts(mm).count(RW.TXT_RESUMED_WIN) == win0 + 1, str(_menu_toasts(mm)))
	_gs.gauntlet_wins = gw0
	_gs.gauntlet_losses = gl0
	await _frames(10)
	_ok("E2 两个对照之后也没有排队冒出来的仪式", _ceremonies(mm).is_empty(), "仪式 %d 个" % _ceremonies(mm).size())
	mm.queue_free()
	await _frames(3)


func _t_f() -> void:
	print("── F 开关关 ⇒ 老路 ──")
	_flags_body = "{\"finals_on\":false,\"gauntlet_on\":false}"
	_gs.referee_flags = {RN.K_FINALS: false, RN.K_GAUNTLET: false}
	var subs0 := _hit(START)
	_left_hook = 0
	MMK._may_leave_for_test = func(_dest: String) -> bool:
		_left_hook += 1
		return false
	var m: Node = await _open_mmk()
	await _wait(func() -> bool: return _left_hook > 0, 15000)
	_ok("F ★开关关: 走到「去战斗场」那一步(老路本机打)", _left_hook == 1)
	_ok("F ★一次都没交给服务器、屏上没有裁判那一行", _hit(START) == subs0 and _status_text(m) == "")
	MMK._may_leave_for_test = Callable()
	m.queue_free()
	await _frames(3)


## 跑一场「账已记、录像取不到」: 匹配屏 → 交阵容 → VS 卡 → 服务器算完(won、账本 gw-gl)⇒ 记账 ⇒ 取录像断网
##   ⇒ 停在匹配屏(ST_ERROR, 屏上「闯关 … · 录像无法在本设备播放」)。返回匹配屏; 等的都是墙钟(匹配屏有真计时器)。
func _one_unplayable(won: bool, gw: int, gl: int) -> Node:
	_done = false
	_offline_match = false
	_gs.referee_pending = {}
	var subs0 := _hit(START)
	var m: Node = await _open_mmk()
	await _wait(func() -> bool: return _hit(START) > subs0)
	await _wait(func() -> bool: return (_status_text(m) == RW.TXT_SETTLING
		and int((_gs.referee_pending as Dictionary).get("job_id", -1)) == _job), 8000)
	var nm := str((_srv_b.get("profile", {}) as Dictionary).get("name", ""))
	await _wait(func() -> bool: return _has_label(m, nm), 8000)
	_offline_match = true
	_srv_won = won
	_srv_gw = gw
	_srv_gl = gl
	_done = true
	await _wait(func() -> bool: return _run_state(m) == RW.ST_ERROR, 15000)
	_offline_match = false
	_job += 1
	return m


## G: 第 4 胜账已按服务器记完、录像却取不到(停在匹配屏, 只有一行状态字)⇒ 匹配屏补演晋级仪式, 只演一次
##   (只读排查路径 ⑥: 原来这一屏什么都不演, 周日收盘卡按设计也不再庆祝 ⇒ 这次晋级没有任何表示)。
func _t_g() -> void:
	print("── G 第 4 胜已记账、录像取不到 ⇒ 匹配屏补演晋级仪式(只演一次) ──")
	_flags_body = "{\"finals_on\":false,\"gauntlet_on\":true}"
	_gs.referee_flags = {RN.K_FINALS: false, RN.K_GAUNTLET: true}
	var dests: Array = []
	MMK._may_leave_for_test = func(dest: String) -> bool:
		dests.append(dest)
		return false
	## ① 3-1 → 服务器判赢、账本 4-1(第 4 胜)→ 取录像断网
	_gs.gauntlet_wins = int(P2C.GAUNTLET_WINS_IN) - 1
	_gs.gauntlet_losses = 1
	var subs0 := _hit(START)
	var mg0 := _hit("matches_get")
	var m: Node = await _one_unplayable(true, int(P2C.GAUNTLET_WINS_IN), 1)
	var run = m.get("_ref_run") if is_instance_valid(m) else null
	var view: Dictionary = (run.view as Dictionary) if run != null and is_instance_valid(run) else {}
	_ok("G ★分母: 交了一场、服务器判赢、账已记成第 %d 胜(闯关赛已晋级)、单子清了" % int(P2C.GAUNTLET_WINS_IN),
		_hit(START) == subs0 + 1 and bool(view.get("won", false)) and int(_gs.gauntlet_wins) == int(P2C.GAUNTLET_WINS_IN)
		and str(_gs.gauntlet_state()) == P2C.GAUNTLET_IN and (_gs.referee_pending as Dictionary).is_empty(),
		"view=%s %d-%d" % [str(view), int(_gs.gauntlet_wins), int(_gs.gauntlet_losses)])
	_ok("G ★分母: 真去取了录像、取不到 ⇒ 停在匹配屏「…%s」(没进战斗场)" % RW.TXT_UNPLAYABLE,
		_hit("matches_get") > mg0 and _run_state(m) == RW.ST_ERROR and _status_text(m).ends_with(RW.TXT_UNPLAYABLE)
		and get_tree().current_scene == m and not _is_battle(get_tree().current_scene), _status_text(m))
	var cs: Array = _ceremonies(m)
	var to_k := str((cs[0] as Node).get_meta("to", "")) if cs.size() == 1 else ""
	_ok("G ★匹配屏上演晋级仪式(闯关赛 → 决赛日)", cs.size() == 1 and to_k == P2C.PHASE_FINALS, "仪式 %d 个 · to=%s" % [cs.size(), to_k])
	## 只演一次: 同一个 ST_ERROR 再广播两次(状态行重画会走同一个回调)⇒ 不叠第二层
	if run != null and is_instance_valid(run):
		run.changed.emit()
		run.changed.emit()
	await _frames(5)
	_ok("G ★只演一次(状态再广播两次, 仍只有 1 个)", _ceremonies(m).size() == 1, "仪式 %d 个" % _ceremonies(m).size())
	_ok("G 停在匹配屏(没走「去战斗场」/「回主菜单」的出口)", dests.is_empty() and get_tree().current_scene == m, str(dests))
	if is_instance_valid(m):
		m.queue_free()
	await _frames(3)
	## ② 对照: 同样停在「账已记、播不了」, 账本同样落在晋级线上(4-2), 只差这一局是输 —— 判据丢了「赢」这一条就会红
	_gs.gauntlet_wins = int(P2C.GAUNTLET_WINS_IN) - 1
	_gs.gauntlet_losses = 1
	var m2: Node = await _one_unplayable(false, int(P2C.GAUNTLET_WINS_IN), 2)
	var run2 = m2.get("_ref_run") if is_instance_valid(m2) else null
	var view2: Dictionary = (run2.view as Dictionary) if run2 != null and is_instance_valid(run2) else {}
	_ok("G 对照 分母: 停在「…%s」、结果单是输、账本同在晋级线上(%d-%d)" % [RW.TXT_UNPLAYABLE, int(_gs.gauntlet_wins), int(_gs.gauntlet_losses)],
		_run_state(m2) == RW.ST_ERROR and not view2.is_empty() and not bool(view2.get("won", true))
		and str(_gs.gauntlet_state()) == P2C.GAUNTLET_IN and _status_text(m2).ends_with(RW.TXT_UNPLAYABLE), "view=%s" % str(view2))
	await _frames(5)
	_ok("G ★对照: 输了的那一局 ⇒ 匹配屏不演", _ceremonies(m2).is_empty(), "仪式 %d 个" % _ceremonies(m2).size())
	MMK._may_leave_for_test = Callable()
	if is_instance_valid(m2):
		m2.queue_free()
	await _frames(3)


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 周六闯关交给服务器" if _fail == 0 and _n >= 50 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
