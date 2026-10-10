extends Node
## verify_ghost_upload_retry.gd — E7 对手快照上传「落盘队列 + 回读销单 + 退避重试」
##   (母方案书 docs/plans/20260916-大轮赛制v2周赛制.md §8 E7; 用户 2026-09-17 拍板「本地持久化队列 + 退避重试」)
##
## 判据原文: 断网打完 ⇒ 快照进 `ghost_upload_pending` 并落盘; 重开 App、联网、进主菜单 ⇒
##   服务端回读得到**逐字相同**的那一份、单子销掉。积分赛 `ghosts` 与周六 `gauntlet_ghosts` 两条都量。
##
## ★全程走真入口: `Backend.upload_ghost` / `Backend.upload_gauntlet_ghost`(结算调的就是它们)入队;
##   「重开 App」= 清掉进程内静态状态 + `GameState._load()` 从盘上读回; 「进主菜单」= 真的实例化 MainMenu.tscn。
## ★网络是假的(`SupabaseNet._transport_for_test`), 但假的是**服务器**: 它真的按主键存下 POST 进来的行
##   (upsert)、按主键回读给你, 而且回读时**重排键**(jsonb 就会这样) —— 量的是「服务器上到底有没有那一份」。
##   不向任何外部服务发请求。
##
## 会 FAIL 的证明(反向验证, 方案见提交说明):
##   · 销单判据改成「2xx 就销」             ⇒ ④ 红
##   · 入队不落盘(去掉 `_enqueue` 的 save) ⇒ ① 盘上 红
##   · 主菜单不补传(去掉 MainMenu 那一行)   ⇒ ⑥ 红

const SB := preload("res://scripts/net/supabase.gd")
const GU := preload("res://scripts/net/ghost_uploader.gd")
const Backend := preload("res://scripts/net/backend.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const ME := "11111111-2222-4333-8444-555555555555"
const OTHER := "99999999-2222-4333-8444-555555555555"

var _fail := 0
var _n := 0
var _gs
var _mode := "down"            # down / authfail / nostore / alter / ok / reject400 / err500
var _reqs: Array = []          # 每一条真发出去的请求 {m, u, bearer, body}
var _rows: Dictionary = {}     # 假服务器: "表|主键" → 行


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


func _tbl_of(url: String) -> String:
	if url.find("/rest/v1/gauntlet_ghosts") >= 0:
		return "gauntlet_ghosts"
	if url.find("/rest/v1/ghosts") >= 0:
		return "ghosts"
	return ""


func _pk_row(tbl: String, r: Dictionary) -> String:
	if tbl == "ghosts":
		return "%s|%s|%d|%d" % [tbl, str(r.get("account_id", "")), int(r.get("season_week", 0)), int(r.get("battles", -1))]
	return "%s|%s|%d|%d-%d" % [tbl, str(r.get("account_id", "")), int(r.get("season_week", 0)),
		int(r.get("gw", -1)), int(r.get("gl", -1))]


func _q(url: String, k: String) -> String:
	var i := url.find(k + "=eq.")
	return url.substr(i + len(k + "=eq.")).get_slice("&", 0) if i >= 0 else ""


## 假服务器。只认快照两张表与续登录; 主菜单顺手发的其它请求一律空表 200。
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
	var tbl := _tbl_of(url)
	if tbl != "" and str(m) == "POST":
		if _mode == "reject400":
			cb.call({"ok": true, "code": 400, "body": "{\"code\":\"PGRST204\"}"})
			return
		if _mode == "err500":
			cb.call({"ok": true, "code": 500, "body": "oops"})
			return
		var j := JSON.new()
		if j.parse(str(b)) != OK or not (j.data is Dictionary):
			cb.call({"ok": true, "code": 400, "body": "bad json"})
			return
		var row: Dictionary = j.data
		if _mode == "alter":
			(row["snapshot"] as Dictionary)["name"] = "被改写了"
		if _mode != "nostore":
			_rows[_pk_row(tbl, row)] = row          # upsert: 同主键覆盖
		cb.call({"ok": true, "code": 201, "body": ""})
		return
	if tbl != "" and str(m) == "GET" and url.find("account_id=eq.") >= 0:
		var r := {"account_id": _q(url, "account_id"), "season_week": int(_q(url, "season_week")),
			"battles": int(_q(url, "battles")) if _q(url, "battles") != "" else -1,
			"gw": int(_q(url, "gw")) if _q(url, "gw") != "" else -1,
			"gl": int(_q(url, "gl")) if _q(url, "gl") != "" else -1}
		var k := _pk_row(tbl, r)
		var out := "[]"
		if _rows.has(k):
			## jsonb 会重排键: 回读时按键排序输出, 客户端不许依赖键序
			out = "[{\"snapshot\":%s}]" % JSON.stringify((_rows[k] as Dictionary)["snapshot"], "", true)
		cb.call({"ok": true, "code": 200, "body": out})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


func _snap_reqs(method: String = "", tbl: String = "") -> Array:
	var out: Array = []
	for r in _reqs:
		var t := _tbl_of(str(r["u"]))
		if t != "" and (tbl == "" or t == tbl) and (method == "" or str(r["m"]) == method):
			out.append(r)
	return out


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


## ★★周六快照只进 `gauntlet_ghosts`, 不许往积分赛的 `ghosts` 排队(2026-10-10 周六实操查实):
##   原来 `upload_gauntlet_ghost` 里那句 `upload_ghost(snap)` 也排进了 ladder ⇒ 每场闯关赛给积分赛表写一行第 17、18…场,
##   服务端周榜(每人取最新一行)周六还在变。①段里看不出来: 它那一条恰好与积分赛那条同场次、按键去重合掉了。
func _t_gauntlet_not_ladder() -> void:
	print("── ⑪ 周六快照不进积分赛表 ──")
	_mode = "down"
	_gs.ghost_upload_pending = []
	_gs.season_total_battles = 17           # 周六打到第 17 场: 与任何积分赛那一条都不同场次, 去重合不掉
	Backend.upload_gauntlet_ghost(2, 0)
	await _frames(10)
	var keys := _queue_keys()
	_ok("⑪ 分母: 周六那份进了队列", keys.size() >= 1, str(keys))
	_ok("⑪ ★★只有 gauntlet_ghosts 一条, 没有 ghosts 那条", keys.size() == 1 and str(keys[0]).begins_with("gauntlet_ghosts|"), str(keys))
	_gs.ghost_upload_pending = []


func _queue_keys() -> Array:
	var out: Array = []
	for e in _gs.ghost_upload_pending:
		out.append(GU.key_of(e) if e is Dictionary else "?")
	return out


## 盘上那份存档里的队列(不是内存里的) —— 「落盘」的判据只能量盘。
func _disk_queue() -> Array:
	var f := FileAccess.open(_gs.SAVE_PATH, FileAccess.READ)
	if f == null:
		return []
	var j := JSON.new()
	var okp: bool = j.parse(f.get_as_text()) == OK
	f.close()
	if not okp or not (j.data is Dictionary):
		return []
	var q = (j.data as Dictionary).get("ghost_upload_pending", [])
	return q if q is Array else []


func _disk_keys() -> Array:
	var out: Array = []
	for e in _disk_queue():
		out.append(GU.key_of(e) if e is Dictionary else "?")
	return out


## 「重开 App」: 进程内的一切(令牌 / 在路上 / 退避表 / 内存里的队列)清掉, 只剩盘。
func _restart() -> void:
	SB._reset_auth_for_test()
	GU._reset_for_test()
	_gs.ghost_upload_pending = []
	_gs._load()
	_gs.auth_refresh = "r1"
	_gs.account_id = ME


func _setup_gs() -> void:
	_gs.reset_dual_lane()
	_gs.test_mode = false                  # ★要量真存档: 门禁每个测试一份独立 user://
	_gs.tutorial_active = false
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
	_gs.season_total_battles = 5
	_gs.account_id = ME
	_gs.account_email = ""
	_gs.auth_refresh = "r1"
	_gs.ghost_upload_pending = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	var had_env: bool = OS.has_environment(SB.ENV_URL)
	var env0: String = OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	## ★先量「后端关着」: 没服务器可传的包不许排队(否则存档背一堆永远发不出去的快照)
	_setup_gs()
	OS.set_environment(SB.ENV_URL, " ")
	_ok("⓪ 分母: 后端关着", not SB.enabled())
	_ok("⓪ 后端关着 ⇒ 不排队", not GU.enqueue_ladder({"x": 1}, int(_gs.week_anchor_ts), 3, "v")
		and _gs.ghost_upload_pending.is_empty())

	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	_ok("★分母: 后端真的打开了(关着的话下面全是空检查)", SB.enabled())

	var keys: Array = await _t_offline()
	if keys.size() == 2:
		_t_restart(keys)
		await _t_no_token(keys)
		await _t_bad_server(keys, "nostore", "④ ★服务端回 2xx 但没落行")
		await _t_bad_server(keys, "alter", "⑤ 服务端落了行但不是这一份")
		await _t_menu_ok(keys)
	await _t_backoff()
	await _t_server_codes()
	await _t_structural()
	_t_dedupe_cap()
	await _t_gauntlet_not_ladder()

	SB._transport_for_test = Callable()
	SB._reset_auth_for_test()
	GU._reset_for_test()
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	if had_env:
		OS.set_environment(SB.ENV_URL, env0)
	else:
		OS.unset_environment(SB.ENV_URL)
	_finish()


# ① ───────────────────────────────────────────────────────────
func _t_offline() -> Array:
	print("── ① 断网: 积分赛 + 周六各打完一场(真入口) ──")
	_mode = "down"
	_reqs.clear()
	var gid := Backend.player_ghost_id(int(_gs.season_id), _gs.season_leaders, int(_gs.season_total_battles))
	var snap := Backend.build_ghost_snapshot(gid, {"name": "门禁", "avatar": "basic", "id": gid})
	_ok("① 分母: 快照造得出来、带着场次", not snap.is_empty() and int(snap.get("season_total_battles", -1)) == 5,
		str(snap.get("season_total_battles", null)))
	Backend.upload_ghost(snap)                  # 积分赛结算调的就是它
	Backend.upload_gauntlet_ghost(1, 0)         # 周六结算调的就是它
	await _frames(30)
	var keys := _queue_keys()
	_ok("① ★两份快照都进了上传队列(积分赛 + 周六)", keys.size() == 2
		and str(keys[0]).begins_with("ghosts|") and str(keys[1]).begins_with("gauntlet_ghosts|"), str(keys))
	_ok("① ★★队列落盘了(读的是盘上的存档文件)", _disk_keys() == keys, str(_disk_keys()))
	_ok("① 分母: 真的试过联网(续登录请求发出去了, 只是断网)", _reqs.size() >= 1, "%d 条请求" % _reqs.size())
	_ok("① 断网时一条快照请求都没有", _snap_reqs().is_empty(), str(_snap_reqs()))
	_ok("① 队列是设备本地的: 不进云存档", not _gs.cloud_payload().has("ghost_upload_pending"))
	_ok("① 单子自带那一刻的上下文(周号 / 场次 / 标签 / 账号)",
		keys.size() == 2 and int(_gs.ghost_upload_pending[0]["b"]) == 5
		and int(_gs.ghost_upload_pending[1]["gw"]) == 1 and int(_gs.ghost_upload_pending[1]["gl"]) == 0
		and int(_gs.ghost_upload_pending[0]["wk"]) == int(_gs.week_anchor_ts)
		and str(_gs.ghost_upload_pending[0]["acc"]) == ME)
	return keys


# ② ───────────────────────────────────────────────────────────
func _t_restart(keys: Array) -> void:
	print("── ② 重开 App: 队列从盘上读回来 ──")
	_restart()
	_ok("② ★★重开之后单子还在(从盘上读回)", _queue_keys() == keys, str(_queue_keys()))
	_ok("② 分母: 重开时令牌是空的(冷启动)", SB.access_token() == "")


# ③ ───────────────────────────────────────────────────────────
func _t_no_token(keys: Array) -> void:
	print("── ③ 有网但拿不到令牌 ──")
	_mode = "authfail"
	_reqs.clear()
	GU.retry()
	await _frames(30)
	_ok("③ 分母: 真的去续过登录", _reqs.size() >= 1 and str(_reqs[0]["u"]).find("/auth/v1/token") >= 0, str(_reqs))
	_ok("③ ★★拿不到令牌 ⇒ 一条快照请求都没有(不许拿公共匿名钥匙去写)", _snap_reqs().is_empty(), str(_snap_reqs()))
	_ok("③ 单子留着", _queue_keys() == keys, str(_queue_keys()))
	_ok("③ 不在路上了(下次还能再补)", GU._inflight.is_empty(), str(GU._inflight))
	_ok("③ 没令牌不算服务端的账(n 不涨)", int(_gs.ghost_upload_pending[0].get("n", -1)) == 0)
	_restart()


# ④⑤ ─────────────────────────────────────────────────────────
func _t_bad_server(keys: Array, mode: String, title: String) -> void:
	print("── %s ──" % title)
	_mode = mode
	_reqs.clear()
	_rows.clear()
	GU.retry()
	await _frames(30)
	var posts: Array = _snap_reqs("POST")
	var gets: Array = _snap_reqs("GET")
	var tag := title.left(1)
	_ok("%s · 分母: 两张表的插入都发出去了、带的是这个号的令牌" % tag,
		posts.size() == 2 and str(posts[0]["bearer"]) == "tok-new" and str(posts[1]["bearer"]) == "tok-new"
		and _snap_reqs("POST", "ghosts").size() == 1 and _snap_reqs("POST", "gauntlet_ghosts").size() == 1, str(posts.size()))
	_ok("%s · 分母: 两条都回读过" % tag, gets.size() == 2, str(gets.size()))
	if mode == "alter":
		_ok("%s · 分母: 服务端那两行确实在(只是内容不是这一份)" % tag, _rows.size() == 2)
	_ok("%s ⇒ ★★单子必须留着(2xx 不算传成)" % title, _queue_keys() == keys, str(_queue_keys()))
	_ok("%s ⇒ 盘上的单子也还在" % tag, _disk_keys() == keys, str(_disk_keys()))
	_rows.clear()
	_restart()


# ⑥ ───────────────────────────────────────────────────────────
func _t_menu_ok(keys: Array) -> void:
	print("── ⑥ 联网、进主菜单 ⇒ 服务端回读得到这两份、单子销掉 ──")
	_mode = "ok"
	_reqs.clear()
	_rows.clear()
	var want: Array = []
	for e in _gs.ghost_upload_pending:
		want.append((e as Dictionary)["snap"].duplicate(true))
	## E7 调研 #4「事件自带上下文」: 补传时场次早变了 —— 行必须按**单子里**那一场拼, 不按此刻的
	_gs.season_total_battles = 9
	var c0: int = GU.confirmed_count
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	get_tree().root.add_child(menu)                 # ★真入口: 主菜单 _ready 自己去补传
	var w := 0
	while w < 300 and not _gs.ghost_upload_pending.is_empty():
		await get_tree().process_frame
		w += 1
	await _frames(5)
	_ok("⑥ 分母: 主菜单真的发了两条插入(没有它下面全是空检查)", _snap_reqs("POST").size() == 2,
		"%d 条" % _snap_reqs("POST").size())
	var k1 := "ghosts|%s|%d|5" % [ME, int(_gs.week_anchor_ts)]
	var k2 := "gauntlet_ghosts|%s|%d|1-0" % [ME, int(_gs.week_anchor_ts)]
	_ok("⑥ ★★服务端真的有这两行, 而且落在**那一场**的格子里(第 5 场, 不是此刻的第 9 场; 周六 1-0)",
		_rows.has(k1) and _rows.has(k2), str(_rows.keys()))
	var same := _rows.has(k1) and _rows.has(k2) and want.size() == 2 \
		and SB.canonical_json(_rows[k1]["snapshot"]) == SB.canonical_json(want[0]) \
		and SB.canonical_json(_rows[k2]["snapshot"]) == SB.canonical_json(want[1])
	_ok("⑥ ★服务端那两份快照 = 入队那一刻的两份(逐字)", same)
	_ok("⑥ 行带着版本号", _rows.has(k1) and str(_rows[k1].get("client_version", ""))
		== str(ProjectSettings.get_setting("application/config/version", "")))
	_ok("⑥ ★★单子销掉了(内存)", _gs.ghost_upload_pending.is_empty(), str(_queue_keys()))
	_ok("⑥ ★★单子销掉了(盘上)", _disk_queue().is_empty(), str(_disk_keys()))
	_ok("⑥ 回读确认计数 +2", GU.confirmed_count == c0 + 2, "%d → %d" % [c0, GU.confirmed_count])
	_ok("⑥ 销完单不留「在路上」的标记", GU._inflight.is_empty(), str(GU._inflight))
	menu.queue_free()
	_gs.season_total_battles = 5
	await _frames(4)


# ⑦ ───────────────────────────────────────────────────────────
func _t_backoff() -> void:
	print("── ⑦ 退避: 失败后同一进程里不立刻再捶; 到点再发 ──")
	_restart()
	_mode = "nostore"
	_rows.clear()
	_reqs.clear()
	var wk := int(_gs.week_anchor_ts)
	GU.enqueue_ladder({"ghost_id": "bk", "season_total_battles": 7}, wk, 7, "v")
	await _frames(20)
	_ok("⑦ 分母: 入队那一下就发了一次", _snap_reqs("POST").size() == 1, str(_snap_reqs("POST").size()))
	var k: String = _queue_keys()[0] if _queue_keys().size() == 1 else ""
	_ok("⑦ 服务端回了话却没对上 ⇒ n = 1(落盘)", _disk_queue().size() == 1 and int(_disk_queue()[0].get("n", 0)) == 1)
	var nxt := int(GU._next_at.get(k, 0))
	var now := int(Time.get_unix_time_from_system())
	_ok("⑦ ★下次最早尝试被推后了(在 [0.5, 1.0] × BACKOFF_BASE 之内)",
		nxt >= now + int(GU.BACKOFF_BASE * 0.5) - 2 and nxt <= now + int(GU.BACKOFF_BASE) + 2, "%d s" % (nxt - now))
	_reqs.clear()
	GU.retry()
	await _frames(10)
	_ok("⑦ ★退避期内再补 ⇒ 一条请求都不发", _snap_reqs().is_empty(), str(_snap_reqs().size()))
	GU._next_at[k] = 0                         # 「时间到了」: 把下次最早时刻拨回过去(不另开时钟缝)
	_mode = "ok"
	GU.retry()
	await _frames(20)
	_ok("⑦ ★到点再补 ⇒ 发了、销单", _snap_reqs("POST").size() == 1 and _gs.ghost_upload_pending.is_empty(),
		"%d 条 / 队列 %s" % [_snap_reqs("POST").size(), str(_queue_keys())])


# ⑧ ───────────────────────────────────────────────────────────
func _t_server_codes() -> void:
	print("── ⑧ 服务端拒「这一行本身」⇒ 销; 5xx ⇒ 留着 ──")
	var wk := int(_gs.week_anchor_ts)
	for mode in ["reject400", "err500"]:
		_restart()
		_mode = mode
		_reqs.clear()
		GU.enqueue_ladder({"ghost_id": mode, "season_total_battles": 8}, wk, 8, "v")
		await _frames(20)
		_ok("⑧ [%s] 分母: 插入发出去了" % mode, _snap_reqs("POST").size() == 1)
		if mode == "reject400":
			_ok("⑧ ★400 ⇒ 再发多少次都一样 ⇒ 销单(内存与盘上)",
				_gs.ghost_upload_pending.is_empty() and _disk_queue().is_empty(), str(_queue_keys()))
		else:
			_ok("⑧ ★500 ⇒ 留着、n+1", _gs.ghost_upload_pending.size() == 1
				and int(_gs.ghost_upload_pending[0].get("n", 0)) == 1, str(_gs.ghost_upload_pending))
	_gs.ghost_upload_pending = []
	_gs.save()


# ⑨ ───────────────────────────────────────────────────────────
func _t_structural() -> void:
	print("── ⑨ 结构上发不出去的单子销掉、且不发请求 ──")
	_restart()
	_mode = "ok"
	var now := int(Time.get_unix_time_from_system())
	var wk: int = P2.week_anchor_utc(now)
	var fresh := now - 60
	var cases := {
		"那一周过完了": {"tbl": "ghosts", "wk": wk - 7 * 86400, "b": 3, "gw": -1, "gl": -1, "snap": {"x": 1}, "acc": ME, "n": 0},
		"周六快照过了新鲜窗": {"tbl": "gauntlet_ghosts", "wk": wk, "b": -1, "gw": 2, "gl": 1,
			"snap": {"gl_ts": now - int(P2.FRESH_SNAPSHOT_SEC) - 5}, "acc": ME, "n": 0},
		"换了号": {"tbl": "ghosts", "wk": wk, "b": 3, "gw": -1, "gl": -1, "snap": {"x": 1}, "acc": OTHER, "n": 0},
		"试满了": {"tbl": "ghosts", "wk": wk, "b": 4, "gw": -1, "gl": -1, "snap": {"x": 1}, "acc": ME, "n": GU.MAX_TRIES},
		"没有快照": {"tbl": "ghosts", "wk": wk, "b": 5, "gw": -1, "gl": -1, "snap": {}, "acc": ME, "n": 0},
		"积分赛没场次": {"tbl": "ghosts", "wk": wk, "b": -1, "gw": -1, "gl": -1, "snap": {"x": 1}, "acc": ME, "n": 0},
		"表名不认识": {"tbl": "matches", "wk": wk, "b": 3, "gw": -1, "gl": -1, "snap": {"x": 1}, "acc": ME, "n": 0},
	}
	for name in cases:
		var why: String = GU.drop_reason(cases[name], now, ME)
		_ok("⑨ [%s] 判出销单原因" % name, why != "", why)
	_gs.ghost_upload_pending = cases.values().duplicate(true)
	_reqs.clear()
	GU.retry()
	await _frames(20)
	_ok("⑨ 分母: 进去之前队列里有 %d 条" % cases.size(), cases.size() == 7)
	_ok("⑨ ★全部销掉", _gs.ghost_upload_pending.is_empty(), str(_queue_keys()))
	_ok("⑨ ★一条快照请求都没发", _snap_reqs().is_empty(), str(_snap_reqs()))
	_ok("⑨ 对照: 本周、本号、积分赛 ⇒ 不销(判据不是一律销)", GU.drop_reason(
		{"tbl": "ghosts", "wk": wk, "b": 3, "gw": -1, "gl": -1, "snap": {"x": 1}, "acc": ME, "n": GU.MAX_TRIES - 1}, now, ME) == "")
	_ok("⑨ 对照: 周六快照还新鲜 ⇒ 不销", GU.drop_reason(
		{"tbl": "gauntlet_ghosts", "wk": wk, "b": -1, "gw": 2, "gl": 1, "snap": {"gl_ts": fresh}, "acc": ME, "n": 0}, now, ME) == "")
	_ok("⑨ 对照: 那一场打的时候还没登录(acc 空) ⇒ 不销", GU.drop_reason(
		{"tbl": "ghosts", "wk": wk, "b": 3, "gw": -1, "gl": -1, "snap": {"x": 1}, "acc": "", "n": 0}, now, ME) == "")


# ⑩ ───────────────────────────────────────────────────────────
func _t_dedupe_cap() -> void:
	print("── ⑩ 同主键顶掉旧单子; 队列有上限 ──")
	_restart()
	_mode = "down"
	var wk := int(_gs.week_anchor_ts)
	GU.enqueue_ladder({"v": "旧"}, wk, 11, "v")
	GU.enqueue_ladder({"v": "新"}, wk, 11, "v")
	_ok("⑩ ★同一场传两次 ⇒ 队列里只有一条、是新的那份",
		_gs.ghost_upload_pending.size() == 1 and str(_gs.ghost_upload_pending[0]["snap"]["v"]) == "新",
		str(_gs.ghost_upload_pending.size()))
	_gs.ghost_upload_pending = []
	for i in range(GU.QUEUE_MAX + 5):
		GU.enqueue_ladder({"i": i}, wk, i, "v")
	var q: Array = _gs.ghost_upload_pending
	_ok("⑩ ★队列封顶 QUEUE_MAX(%d)" % GU.QUEUE_MAX, q.size() == GU.QUEUE_MAX, str(q.size()))
	_ok("⑩ 丢的是最旧的(留下的第一条是第 5 场)", q.size() > 0 and int(q[0]["b"]) == 5, str(q[0]["b"]) if q.size() > 0 else "")
	_ok("⑩ 盘上也封顶", _disk_queue().size() == GU.QUEUE_MAX, str(_disk_queue().size()))
	_gs.ghost_upload_pending = []
	_gs.save()


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · 用了 %d 帧)" % [_n, Engine.get_process_frames()])
	if _fail == 0:
		print("ALL PASS — E7 快照上传队列")
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
