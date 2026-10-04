extends Node
## verify_travel_no_write.gd — 测试时间(开发包时间穿越)里**一条写请求都不发到服务器**; 回到真实时间后照常补发
## (2026-10-04, 方案书 docs/plans/20261004-时间穿越测试.md §5 R7)
##
## ★为什么: iOS 测试包是 `--export-debug` ⇒ 测试者手上有时间穿越, 而它连的是**正式服**。
##   假周六打完一局 = 往生产写一份带假相位的真快照。拦截点只有一个: `SupabaseNet._http`(+ 旧后端 `RemotePool._http`)。
##
## ★量的是**真入口**发出去的请求(假服务器 = `SupabaseNet._transport_for_test`, 记下每一条真发出去的请求):
##   积分赛/周六快照(`Backend.upload_ghost` / `upload_gauntlet_ghost` → 上传队列) / 录像 `upload_match_async` /
##   决赛报名 `enter_finals_async` / 战报 `report_finals_async` / 问对手 `fetch_opponent_async`(往 finals_scout 插行) /
##   存档同步 `maybe_push_save` / 旧后端 `RemotePool.upload`。
## ★分母: 每条路径**都真的走到了出口**(被拦计数 +1), 不是在半路因为别的原因没发;
##   读请求(服务状态 / finals_view)在同一时刻**照常发出去**(证明拦的是写, 不是整个网络)。
## ★回到真实时间: 快照队列补发成功并销单(而且**不用等退避** —— 被拦不算失败), 存档/战报/报名照常发。
##
## 跑法:
##   APPDATA=<scratch> TURTLE_BACKEND=" " TURTLE_SUPABASE=" " \
##   <godot> --headless --path . res://tests/verify_travel_no_write.tscn --quit-after 3000

const SB := preload("res://scripts/net/supabase.gd")
const GU := preload("res://scripts/net/ghost_uploader.gd")
const RP := preload("res://scripts/net/remote_pool.gd")
const Backend := preload("res://scripts/net/backend.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const ME := "11111111-2222-4333-8444-555555555555"
const MID := "aaaaaaaa-2222-4333-8444-555555555555"

var _fail := 0
var _n := 0
var _gs
var _reqs: Array = []          # 真发出去的每一条 {m, u}
var _rp_reqs: Array = []       # 旧后端那一层真发出去的
var _rows: Dictionary = {}     # 假服务器: 快照表 "表|周|场次|gw|gl" → snapshot


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


func _q(url: String, k: String) -> String:
	var i := url.find(k + "=eq.")
	return url.substr(i + len(k + "=eq.")).get_slice("&", 0) if i >= 0 else ""


func _tbl(url: String) -> String:
	if url.find("/rest/v1/gauntlet_ghosts") >= 0:
		return "gauntlet_ghosts"
	if url.find("/rest/v1/ghosts") >= 0:
		return "ghosts"
	return ""


## 假服务器: 快照两张表真存真回读; 其余写一律回 {ok:true}; 读回空表。
func _transport(m, u, _h, b, cb) -> void:
	var url := str(u)
	_reqs.append({"m": str(m), "u": url})
	var tbl := _tbl(url)
	if tbl != "" and str(m) == "POST":
		var j := JSON.new()
		j.parse(str(b))
		var r: Dictionary = j.data
		_rows["%s|%d|%d|%d|%d" % [tbl, int(r.get("season_week", 0)), int(r.get("battles", -1)),
			int(r.get("gw", -1)), int(r.get("gl", -1))]] = r.get("snapshot", {})
		cb.call({"ok": true, "code": 201, "body": ""})
		return
	if tbl != "" and str(m) == "GET":
		var k := "%s|%d|%d|%d|%d" % [tbl, int(_q(url, "season_week")),
			int(_q(url, "battles")) if _q(url, "battles") != "" else -1,
			int(_q(url, "gw")) if _q(url, "gw") != "" else -1,
			int(_q(url, "gl")) if _q(url, "gl") != "" else -1]
		var out := "[]"
		if _rows.has(k):
			out = "[{\"snapshot\":%s}]" % JSON.stringify(_rows[k], "", true)
		cb.call({"ok": true, "code": 200, "body": out})
		return
	if str(m) != "GET":
		cb.call({"ok": true, "code": 200, "body": "{\"ok\":true,\"rev\":1}"})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


func _rp_transport(m, u, _b, cb) -> void:
	_rp_reqs.append({"m": str(m), "u": str(u)})
	cb.call({"ok": true, "code": 200, "body": "{}"})


## 真发出去的请求里, 会写服务器的那些(判据走产品自己的 `is_write_request`)。
func _writes() -> Array:
	var out: Array = []
	for r in _reqs:
		if SB.is_write_request(str(r["m"]), str(r["u"])):
			out.append("%s %s" % [r["m"], str(r["u"]).get_slice("?", 0)])
	return out


func _sent(fragment: String, method: String = "") -> int:
	var c := 0
	for r in _reqs:
		if str(r["u"]).find(fragment) >= 0 and (method == "" or str(r["m"]) == method):
			c += 1
	return c


func _fresh_token() -> void:
	SB._token = "tok-gate"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	## ── 现场保存 ──
	var had_env: bool = OS.has_environment(SB.ENV_URL)
	var env0: String = OS.get_environment(SB.ENV_URL)
	var had_be: bool = OS.has_environment("TURTLE_BACKEND")
	var be0: String = OS.get_environment("TURTLE_BACKEND")
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	var k_off: int = P2.travel_offset_sec
	var k_read: bool = P2._travel_env_read
	var k_ovr: int = P2.now_override_ts
	P2.now_override_ts = 0
	OS.unset_environment("SHIP")

	## ── 假服务器 + 账号 ──
	_gs.test_mode = true
	_gs.reset_dual_lane()
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
	_gs.account_email = "gate@turtle.test"
	_gs.ghost_upload_pending = []
	_gs.finals_entered_week = 0
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._reset_save_sync_for_test()
	SB.finals_report_clear()
	GU._reset_for_test()
	_fresh_token()
	_ok("★分母: 后端真的打开了", SB.enabled())

	var wk: int = int(_gs.week_anchor_ts)
	var gid := Backend.player_ghost_id(int(_gs.season_id), _gs.season_leaders, int(_gs.season_total_battles))
	var snap := Backend.build_ghost_snapshot(gid, {"name": "门禁", "avatar": "basic", "id": gid})
	_ok("★分母: 快照造得出来", not snap.is_empty())

	# ════════════ ① 测试时间里: 写一条都不发 ════════════
	print("── ① 测试时间(周六 15:00)里走一遍每条写路径 ──")
	_ok("① ★分母: 穿越生效", P2.travel_to_weekday(6, 15, 0) and P2.travel_active())
	_reqs.clear()
	var b0: int = SB.travel_blocked_count
	var per: Dictionary = {}
	var last: int = b0

	Backend.upload_ghost(snap)                  # 积分赛结算调的
	await _frames(20)
	per["积分赛快照"] = SB.travel_blocked_count - last; last = SB.travel_blocked_count
	Backend.upload_gauntlet_ghost(1, 0)         # 周六结算调的
	await _frames(20)
	per["周六快照"] = SB.travel_blocked_count - last; last = SB.travel_blocked_count
	SB.upload_match_async({"match_id": MID, "left_account": ME, "replay": "eHg="}, func(_m, _o): pass)
	await _frames(20)
	per["录像"] = SB.travel_blocked_count - last; last = SB.travel_blocked_count
	SB.enter_finals_async(wk, "门禁", snap, 4, 0)
	await _frames(20)
	per["决赛报名"] = SB.travel_blocked_count - last; last = SB.travel_blocked_count
	SB.report_finals_async(wk, 0, 1, 0, 0, 123)
	await _frames(20)
	per["决赛战报"] = SB.travel_blocked_count - last; last = SB.travel_blocked_count
	SB.fetch_opponent_async(wk, 0, 1, 2)
	await _frames(20)
	per["问对手(插 finals_scout)"] = SB.travel_blocked_count - last; last = SB.travel_blocked_count
	SB.note_save_dirty()
	SB.maybe_push_save(true)
	await _frames(20)
	per["存档同步"] = SB.travel_blocked_count - last; last = SB.travel_blocked_count

	## 读: 同一时刻照常发
	SB.fetch_status_async()
	SB.fetch_finals_async(wk, 0)
	await _frames(20)

	## 旧后端那一层
	OS.set_environment("TURTLE_BACKEND", "http://rp.gate.local")
	var rp = RP.new()
	rp._transport = _rp_transport
	add_child(rp)
	rp.upload(snap)
	await _frames(5)
	var rp_blocked: int = _rp_reqs.size()

	var miss: Array = []
	for k in per.keys():
		if int(per[k]) < 1:
			miss.append(k)
	_ok("① ★分母: 7 条写路径每条都真的走到了出口、被拦下(不是半路因别的原因没发)", miss.is_empty(),
		"各路被拦条数 %s" % str(per))
	_ok("① ★★测试时间里发出去的写请求 = 0", _writes().is_empty(), str(_writes()))
	_ok("① ★分母: 读请求照常发出去(服务状态 GET + finals_view)", _sent("/service_status", "GET") >= 1
		and _sent("/rpc/finals_view") >= 1, "%d 条请求: %s" % [_reqs.size(), str(_reqs)])
	_ok("① 旧后端层(RemotePool)也不发", rp_blocked == 0, str(_rp_reqs))
	## 没发 ≠ 丢了: 每条路径都还记着「没发」
	_ok("① 快照队列两条都还在(没销单)", _gs.ghost_upload_pending.size() == 2, str(_gs.ghost_upload_pending.size()))
	_ok("① 被拦不记退避(回到真实时间后不用干等)", GU._next_at.is_empty() and GU._fails.is_empty(),
		"next_at=%s fails=%s" % [str(GU._next_at), str(GU._fails)])
	_ok("① 决赛报名没记成功", int(_gs.finals_entered_week) != wk)
	_ok("① 战报没记成功", not SB.finals_reported(1, 0))
	_ok("① 存档仍是待推(dirty)", SB._save_dirty and SB.saves_pushed() == 0)

	# ════════════ ② 回到真实时间: 照常补发 ════════════
	print("── ② 恢复真实时间后补发 ──")
	P2.travel_reset()
	_ok("② ★分母: 回到真实时间", not P2.travel_active())
	_reqs.clear()
	_fresh_token()
	GU.retry()                                   # 主菜单每次打开调的就是它
	await _frames(30)
	_ok("② ★快照队列补发: 两张表各 POST 一次", _sent("/rest/v1/ghosts", "POST") >= 1
		and _sent("/rest/v1/gauntlet_ghosts", "POST") >= 1, str(_writes()))
	_ok("② ★回读确认后销单(队列空)", _gs.ghost_upload_pending.is_empty(), str(_gs.ghost_upload_pending.size()))
	SB.maybe_push_save(true)
	SB.report_finals_async(wk, 0, 1, 0, 0, 123)
	SB.enter_finals_async(wk, "门禁", snap, 4, 0)
	await _frames(30)
	_ok("② 存档照常推上去", _sent("/rpc/push_save", "POST") >= 1 and SB.saves_pushed() >= 1)
	_ok("② 战报照常发出并记成功", _sent("/rpc/finals_report", "POST") >= 1 and SB.finals_reported(1, 0))
	_ok("② 报名照常发出", _sent("/rpc/finals_enter", "POST") >= 1)
	rp.upload(snap)
	await _frames(5)
	_ok("② 旧后端层照常发", _rp_reqs.size() >= 1, str(_rp_reqs))

	# ════════════ ③ 分类器 ════════════
	print("── ③ 写/读 分类 ──")
	var base := "http://x/rest/v1/"
	var table := [
		["GET", base + "ghosts?select=*", false], ["POST", base + "ghosts", true],
		["POST", base + "rpc/finals_view", false], ["POST", base + "rpc/finals_opponent", true],
		["POST", base + "rpc/push_save", true], ["POST", base + "rpc/finals_enter", true],
		["POST", base + "rpc/finals_report", true], ["POST", base + "rpc/some_new_rpc", true],
		["POST", "http://x/auth/v1/token?grant_type=refresh_token", false], ["PUT", "http://x/auth/v1/user", false],
		["PATCH", base + "saves", true], ["DELETE", base + "matches", true],
	]
	var bad: Array = []
	for row in table:
		if SB.is_write_request(str(row[0]), str(row[1])) != bool(row[2]):
			bad.append("%s %s" % [row[0], row[1]])
	_ok("③ 写/读分类(新 RPC 默认算写 / finals_opponent 算写 / 身份放行)", bad.is_empty(), str(bad))

	# ── 还原 ──
	rp.queue_free()
	SB._transport_for_test = Callable()
	SB._reset_auth_for_test()
	SB._reset_save_sync_for_test()
	SB.finals_report_clear()
	GU._reset_for_test()
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	if had_env:
		OS.set_environment(SB.ENV_URL, env0)
	else:
		OS.unset_environment(SB.ENV_URL)
	if had_be:
		OS.set_environment("TURTLE_BACKEND", be0)
	else:
		OS.unset_environment("TURTLE_BACKEND")
	P2.travel_offset_sec = k_off
	P2._travel_env_read = k_read
	P2.now_override_ts = k_ovr
	_finish()


func _finish() -> void:
	print("\n断言 %d 条, 失败 %d 条" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)
