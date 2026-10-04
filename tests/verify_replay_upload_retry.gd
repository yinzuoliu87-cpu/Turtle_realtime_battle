extends Node
## verify_replay_upload_retry.gd — 回放 S2 门禁 V7「上传与补传」(方案书 docs/plans/20261003-跨设备回放.md §6 V7)
##
## 判据原文: 断网打完 ⇒ 记录进 `replay_upload_pending` 并落盘; 重开 App、联网、进主菜单 ⇒
##   服务端回读得到这一行、单子销掉。
##   会 FAIL 的证明: 把销单判据改回「发过了就销」并让桩返回 2xx 但不落行 ⇒ 红。
##
## ★全程走真入口: 真战斗场打一局周六闯关赛(认输结束) → 结算里 `ReplayRecorder.on_settle` 自己入队;
##   「重开 App」= 清掉进程内静态状态 + `GameState._load()` 从盘上读回; 「进主菜单」= 真的实例化 MainMenu.tscn。
## ★网络是假的(`SupabaseNet._transport_for_test`), 但假的是**服务器**, 不是我插的计数器:
##   它真的存下 POST 进来的行、按 `match_id` 回读给你 —— 门禁量的是「服务器上到底有没有那一行、内容对不对」。
##   不向任何外部服务发请求。
##
## 段落:
##   ① 断网打完: 入队 + 落盘 + 一个字节都没往 matches 发
##   ② 重开 App: 队列从盘上读回来
##   ③ 有网但拿不到令牌: 不许用公共匿名钥匙写(一条 matches 请求都不许有), 单子留着
##   ④ ★服务端回 2xx 但没落行 ⇒ 单子必须留着(V7 的反证场景, 常驻)
##   ⑤ 服务端落了行但录像被截断 ⇒ 单子必须留着
##   ⑥ ★★进主菜单 ⇒ 服务端回读得到这一行、内容逐字对、单子销掉(内存与盘上都销)
##   ⑦ 上次其实已经插进去了(回包丢了) ⇒ 再发撞 409, 回读裁决 ⇒ 销单
##   ⑧ 结构上发不出去的单子销掉(过期 / 文件没了 / 换了号 / id 不是 uuid), 而且不发请求
##   ⑨ 客户端上限与 schema.sql 的约束是同一个数

const SB := preload("res://scripts/net/supabase.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const Backend := preload("res://scripts/net/backend.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ME := "11111111-2222-4333-8444-555555555555"

var _fail := 0
var _n := 0
var _gs
var _mode := "down"            # down / authfail / nostore / truncate / ok
var _reqs: Array = []          # 每一条真发出去的请求 {m, u, bearer, body}
var _rows: Dictionary = {}     # 假服务器上的 matches 表: match_id → 行


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _bearer(h) -> String:
	for line in (h as PackedStringArray):
		if str(line).begins_with("Authorization: Bearer "):
			return str(line).substr(len("Authorization: Bearer "))
	return ""


## 假服务器。只认 matches 与续登录; 主菜单顺手发的其它请求一律空表 200。
func _transport(m, u, h, b, cb) -> void:
	var url := str(u)
	_reqs.append({"m": str(m), "u": url, "bearer": _bearer(h), "body": str(b)})
	if _mode == "down":
		cb.call({"ok": false, "code": 0, "body": ""})
		return
	if url.find("/auth/v1/token") >= 0:
		if _mode == "authfail":
			cb.call({"ok": false, "code": 0, "body": ""})
		else:
			cb.call({"ok": true, "code": 200, "body": JSON.stringify({
				"access_token": "tok-new", "refresh_token": "r2", "expires_in": 3600,
				"user": {"id": ME, "is_anonymous": true}})})
		return
	if url.find("/rest/v1/matches") >= 0 and str(m) == "POST":
		var j := JSON.new()
		if j.parse(str(b)) != OK or not (j.data is Dictionary):
			cb.call({"ok": true, "code": 400, "body": "bad json"})
			return
		var row: Dictionary = j.data
		var id := str(row.get("match_id", ""))
		if _rows.has(id):
			cb.call({"ok": true, "code": 409, "body": "{\"code\":\"23505\"}"})
			return
		if _mode == "truncate":
			row["replay"] = str(row.get("replay", "")).left(100)
		if _mode != "nostore":
			_rows[id] = row
		cb.call({"ok": true, "code": 201, "body": ""})
		return
	if url.find("/rest/v1/matches?") >= 0 and str(m) == "GET":
		var out: Array = []
		var k := url.find("match_id=eq.")
		var id2 := url.substr(k + len("match_id=eq.")).get_slice("&", 0) if k >= 0 else ""
		if _rows.has(id2):
			out.append({"match_id": id2, "replay": str((_rows[id2] as Dictionary).get("replay", ""))})
		cb.call({"ok": true, "code": 200, "body": JSON.stringify(out)})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


func _match_reqs(method: String = "") -> Array:
	var out: Array = []
	for r in _reqs:
		if str(r["u"]).find("/rest/v1/matches") >= 0 and (method == "" or str(r["m"]) == method):
			out.append(r)
	return out


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _queue_ids() -> Array:
	var out: Array = []
	for e in _gs.replay_upload_pending:
		out.append(str((e as Dictionary).get("id", "")) if e is Dictionary else "?")
	return out


## 盘上那份存档里的队列(不是内存里的) —— 「落盘」的判据只能量盘。
func _disk_queue_ids() -> Array:
	var f := FileAccess.open(_gs.SAVE_PATH, FileAccess.READ)
	if f == null:
		return ["<没有存档文件>"]
	var j := JSON.new()
	var okp: bool = j.parse(f.get_as_text()) == OK
	f.close()
	if not okp or not (j.data is Dictionary):
		return ["<存档读不出>"]
	var out: Array = []
	for e in (j.data as Dictionary).get("replay_upload_pending", []):
		out.append(str((e as Dictionary).get("id", "")) if e is Dictionary else "?")
	return out


## 「重开 App」: 进程内的一切(令牌 / 在路上的标记 / 内存里的队列)清掉, 只剩盘。
func _restart() -> void:
	SB._reset_auth_for_test()
	RU._inflight.clear()
	_gs.replay_upload_pending = []
	_gs._load()
	_gs.auth_refresh = "r1"


func _setup_gs() -> void:
	_gs.reset_dual_lane()
	_gs.test_mode = false                  # ★要量真存档: 门禁每个测试一份独立 user://
	_gs.tutorial_active = false
	_gs.week_phase = "gauntlet"
	_gs.week_anchor_ts = P2.week_anchor_utc(int(Time.get_unix_time_from_system()))
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261004
	_gs.dual_ghost = Backend.make_bot(3, rng)
	_gs.dual_active = true
	_gs.account_id = ME
	_gs.account_email = ""
	_gs.auth_refresh = "r1"
	_gs.replay_upload_pending = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	OS.set_environment("TURTLE_SEED", "")
	var had_env: bool = OS.has_environment(SB.ENV_URL)
	var env0: String = OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	_ok("★分母: 后端真的打开了(关着的话下面全是空检查)", SB.enabled())
	_setup_gs()

	await _t_offline_battle()
	var id: String = str(_gs.match_history[0].get("replay_id", "")) if not (_gs.match_history as Array).is_empty() else ""
	if id != "" and _queue_ids().has(id):
		await _t_restart(id)
		await _t_no_token(id)
		await _t_bad_server(id, "nostore", "④ ★服务端回 2xx 但没落行")
		await _t_bad_server(id, "truncate", "⑤ 服务端落了行但录像被截断")
		await _t_menu_ok(id)
		await _t_duplicate(id)
	await _t_structural()
	_t_schema()

	SB._transport_for_test = Callable()
	SB._reset_auth_for_test()
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	if had_env:
		OS.set_environment(SB.ENV_URL, env0)
	else:
		OS.unset_environment(SB.ENV_URL)
	_ok("★收尾: 后端已关回去", not SB.enabled() or had_env)
	_finish()


# ① ───────────────────────────────────────────────────────────
func _t_offline_battle() -> void:
	print("── ① 断网打完一局周六闯关赛(认输) ──")
	_mode = "down"
	_reqs.clear()
	var hist0: int = (_gs.match_history as Array).size()
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await _frames(2)
	_ok("① 分母: 这一局在录(周六闯关赛)", str(s._replay.mode) == "rec", str(s._replay.mode))
	for _i in range(20):
		s._process(0.016)
		await get_tree().process_frame
	s._do_surrender()                       # 真入口: 认输确认钮调的就是它
	var w := 0
	while w < 600 and (_gs.match_history as Array).size() == hist0:
		await get_tree().process_frame
		w += 1
	await _frames(30)                        # 让上传那条路(续登录失败 → 放弃)走完
	var id: String = str(_gs.match_history[0].get("replay_id", "")) if (_gs.match_history as Array).size() > hist0 else ""
	_ok("① 分母: 结算记了战绩、挂上了回放 id(uuid)", SB.is_uuid(id), id)
	_ok("① ★录像进了上传队列", _queue_ids().has(id), str(_queue_ids()))
	_ok("① ★★队列落盘了(读的是盘上的存档文件)", _disk_queue_ids().has(id), str(_disk_queue_ids()))
	_ok("① 分母: 真的试过联网(续登录请求发出去了, 只是断网)", _reqs.size() >= 1, "%d 条请求" % _reqs.size())
	_ok("① 断网时一条 matches 请求都没有", _match_reqs().is_empty(), str(_match_reqs()))
	_ok("① 队列是设备本地的: 不进云存档", not _gs.cloud_payload().has("replay_upload_pending"))
	_ok("① 本地录像文件在", not ReplayRecorder.load_record(id).is_empty())
	s.queue_free()
	await _frames(4)


# ② ───────────────────────────────────────────────────────────
func _t_restart(id: String) -> void:
	print("── ② 重开 App: 队列从盘上读回来 ──")
	_restart()
	_ok("② ★★重开之后单子还在(从盘上读回)", _queue_ids() == [id], str(_queue_ids()))
	_ok("② 分母: 重开时令牌是空的(冷启动)", SB.access_token() == "")


# ③ ───────────────────────────────────────────────────────────
func _t_no_token(id: String) -> void:
	print("── ③ 有网但拿不到令牌 ──")
	_mode = "authfail"
	_reqs.clear()
	RU.retry()
	await _frames(30)
	var anon := 0
	for r in _match_reqs():
		if str(r["bearer"]) != "tok-new":
			anon += 1
	_ok("③ 分母: 真的去续过登录", _reqs.size() >= 1 and str(_reqs[0]["u"]).find("/auth/v1/token") >= 0, str(_reqs))
	_ok("③ ★★拿不到令牌 ⇒ 一条 matches 请求都没有(不许拿公共匿名钥匙去写)",
		_match_reqs().is_empty() and anon == 0, str(_match_reqs()))
	_ok("③ 单子留着", _queue_ids() == [id], str(_queue_ids()))
	_ok("③ 不在路上了(下次还能再补)", not RU._inflight.has(id))
	_restart()


# ④⑤ ─────────────────────────────────────────────────────────
func _t_bad_server(id: String, mode: String, title: String) -> void:
	print("── %s ──" % title)
	_mode = mode
	_reqs.clear()
	_rows.clear()
	RU.retry()
	await _frames(30)
	var posts: Array = _match_reqs("POST")
	var gets: Array = _match_reqs("GET")
	_ok("%s · 分母: 插入真的发出去了、带的是这个号的令牌" % title.left(1),
		posts.size() == 1 and str(posts[0]["bearer"]) == "tok-new", str(posts))
	_ok("%s · 分母: 也回读过" % title.left(1), gets.size() == 1, str(gets))
	if mode == "truncate":
		_ok("%s · 分母: 服务端那一行确实在(只是录像被截断)" % title.left(1), _rows.has(id))
	_ok("%s ⇒ ★★单子必须留着(2xx 不算传成)" % title, _queue_ids() == [id], str(_queue_ids()))
	_ok("%s ⇒ 盘上的单子也还在" % title.left(1), _disk_queue_ids().has(id), str(_disk_queue_ids()))
	_rows.clear()
	_restart()


# ⑥ ───────────────────────────────────────────────────────────
func _t_menu_ok(id: String) -> void:
	print("── ⑥ 联网、进主菜单 ⇒ 服务端回读得到这一行、单子销掉 ──")
	_mode = "ok"
	_reqs.clear()
	_rows.clear()
	var c0: int = RU.confirmed_count
	var local: Dictionary = ReplayRecorder.load_record(id)
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	get_tree().root.add_child(menu)                 # ★真入口: 主菜单 _ready 自己去补传
	var w := 0
	while w < 300 and _queue_ids().has(id):
		await get_tree().process_frame
		w += 1
	await _frames(5)
	var posts: Array = _match_reqs("POST")
	_ok("⑥ 分母: 主菜单真的发了插入(没有它下面全是空检查)", posts.size() == 1, "%d 条" % posts.size())
	_ok("⑥ 插入带的是这个号的令牌, 不是公共匿名钥匙",
		posts.size() == 1 and str(posts[0]["bearer"]) == "tok-new")
	_ok("⑥ ★★服务端真的有这一行", _rows.has(id), str(_rows.keys()))
	_ok("⑥ ★★单子销掉了(内存)", not _queue_ids().has(id), str(_queue_ids()))
	_ok("⑥ ★★单子销掉了(盘上)", not _disk_queue_ids().has(id), str(_disk_queue_ids()))
	_ok("⑥ 回读确认计数 +1", RU.confirmed_count == c0 + 1)
	## 令牌新鲜 + 回包同步时, 整条路在 `upload_match_async` 返回之前就走完了 ——
	##   「在路上」要是发完才标, 就会在销单之后被写回去、永远卡住(第一版就是这样, ⑦ 红过)。
	_ok("⑥ 销完单不留「在路上」的标记(否则这一 id 以后再也不补)", RU._inflight.is_empty(), str(RU._inflight))
	var row: Dictionary = _rows.get(id, {})
	var up: Dictionary = ReplayRecorder.decode(Marshalls.base64_to_raw(str(row.get("replay", ""))))
	_ok("⑥ 分母: 服务端那份录像解得开", not up.is_empty() and not local.is_empty())
	var same := not up.is_empty()
	for k in ["v", "client_version", "seed", "events", "cps", "end", "id"]:
		if var_to_bytes(up.get(k)) != var_to_bytes(local.get(k)):
			same = false
			print("    差在 ", k)
	_ok("⑥ ★服务端那份录像 = 本地那份(种子/事件/校验点/终局逐字节)", same)
	var lg: Dictionary = (local.get("state", {}) as Dictionary).get("dual_ghost", {})
	var ug: Dictionary = (up.get("state", {}) as Dictionary).get("dual_ghost", {})
	_ok("⑥ 分母: 本地那份里对手带着机器人标记", bool(lg.get("is_bot", false)))
	_ok("⑥ ★服务端那份里认不出机器人(录像里 / right_snapshot / right_account 都没有)",
		not ug.has("is_bot") and not ug.has("ghost_id") and ug.size() > 0
		and not (row.get("right_snapshot", {}) as Dictionary).has("is_bot")
		and not (row.get("right_snapshot", {}) as Dictionary).has("ghost_id")
		and row.get("right_account", "x") == null, str(row.get("right_snapshot", {}).keys()))
	_ok("⑥ 行的其余列: 我是 left / 周号 / 阶段 / 种子 / 版本 / 胜负",
		str(row.get("left_account", "")) == ME
		and int(row.get("season_week", 0)) == int(_gs.week_anchor_ts)
		and str(row.get("phase", "")) == "gauntlet"
		and int(row.get("seed", -1)) == int(local.get("seed", -2))
		and str(row.get("client_version", "")) == ReplayRecorder.client_version()
		and (row.get("result", {}) as Dictionary).get("won", true) == false
		and bool((row.get("result", {}) as Dictionary).get("surrendered", false))
		and (row.get("left_snapshot", {}) as Dictionary).size() > 0, str(row.keys()))
	menu.queue_free()
	await _frames(4)


# ⑦ ───────────────────────────────────────────────────────────
func _t_duplicate(id: String) -> void:
	print("── ⑦ 上次其实插进去了(回包丢了) ⇒ 再发撞 409, 回读裁决 ──")
	## 服务器上那一行还在(⑥ 留下的); 把单子放回去 = 「回包丢了, 客户端以为没传成」。
	_ok("⑦ 分母: 服务器上已经有这一行", _rows.has(id))
	_gs.replay_upload_pending = [{"id": id, "wk": int(_gs.week_anchor_ts), "acc": ME, "t": 0, "ls": {"x": 1}}]
	_mode = "ok"
	_reqs.clear()
	SB._reset_auth_for_test()
	RU.retry()
	await _frames(30)
	_ok("⑦ 分母: 又发了一次插入(撞主键)", _match_reqs("POST").size() == 1)
	_ok("⑦ ★409 不算失败: 回读得到 ⇒ 销单", _queue_ids().is_empty(), str(_queue_ids()))


# ⑧ ───────────────────────────────────────────────────────────
func _t_structural() -> void:
	print("── ⑧ 结构上发不出去的单子销掉、且不发请求 ──")
	_mode = "ok"
	_rows.clear()
	SB._reset_auth_for_test()
	_gs.account_id = ME
	var now := int(Time.get_unix_time_from_system())
	var wk_now: int = P2.week_anchor_utc(now)
	## 造一份真的本地录像(过期 / 换号 两条要它在, 不然原因会变成「文件没了」)
	var real_id: String = ReplayRecorder.save_record({"v": ReplayRecorder.FORMAT_V,
		"client_version": ReplayRecorder.client_version(), "seed": 7, "state": {}, "events": [], "cps": [],
		"end": {"s": 1, "h": "x", "won": true}})
	var cases := {
		"过期": {"id": real_id, "wk": wk_now - 9 * 86400, "acc": ME, "t": 0, "ls": {}},
		"换号": {"id": real_id, "wk": wk_now, "acc": "99999999-2222-4333-8444-555555555555", "t": 0, "ls": {}},
		"文件没了": {"id": ReplayRecorder.new_id(), "wk": wk_now, "acc": ME, "t": 0, "ls": {}},
		"id 不是 uuid": {"id": "abc&select=*", "wk": wk_now, "acc": ME, "t": 0, "ls": {}},
		"没有周号": {"id": real_id, "wk": 0, "acc": ME, "t": 0, "ls": {}},
	}
	for name in cases:
		var e: Dictionary = cases[name]
		_ok("⑧ [%s] 判出销单原因" % name, RU.drop_reason(e, now, ME) != "", RU.drop_reason(e, now, ME))
	_gs.replay_upload_pending = cases.values().duplicate(true)
	_reqs.clear()
	RU.retry()
	await _frames(30)
	_ok("⑧ 分母: 进去之前队列里有 %d 条" % cases.size(), cases.size() == 5)
	_ok("⑧ ★全部销掉", _queue_ids().is_empty(), str(_queue_ids()))
	_ok("⑧ ★一条 matches 请求都没发", _match_reqs().is_empty(), str(_match_reqs()))
	var good := {"id": real_id, "wk": wk_now, "acc": ME, "t": 0, "ls": {}}
	_ok("⑧ 对照: 同一份录像、本周、本号 ⇒ 不销(判据不是一律销)", RU.drop_reason(good, now, ME) == "",
		RU.drop_reason(good, now, ME))
	_ok("⑧ 对照: 那一场打的时候还没登录(acc 空) ⇒ 不销", RU.drop_reason(
		{"id": real_id, "wk": wk_now, "acc": "", "t": 0, "ls": {}}, now, ME) == "")


# ⑨ ───────────────────────────────────────────────────────────
func _t_schema() -> void:
	print("── ⑨ schema.sql 与客户端同一个上限 ──")
	var f := FileAccess.open("res://server/supabase/schema.sql", FileAccess.READ)
	var sql := f.get_as_text() if f != null else ""
	_ok("⑨ 分母: 读到 schema.sql", sql.length() > 1000)
	_ok("⑨ matches 加了 replay 列", sql.contains("alter table public.matches add column if not exists replay text"))
	_ok("⑨ ★约束上限 = REPLAY_MAX_B64(%d)" % RU.REPLAY_MAX_B64,
		sql.contains("octet_length(replay) between 1 and %d" % RU.REPLAY_MAX_B64))


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · 用了 %d 帧)" % [_n, Engine.get_process_frames()])
	if _fail == 0:
		print("ALL PASS — 回放 S2 上传与补传 (V7)")
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
