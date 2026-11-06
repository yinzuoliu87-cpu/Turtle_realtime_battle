extends Node
## verify_econ_sync —— S4b: 开局时服务器拿快照比重放结果, 客户端怎么接(方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.5)。
##
## 用户 2026-11-06「装备要改成伏击机装(= 服务器记账)了，这个要做。」服务端 econ_check / 两个开局函数插的那一道
##   在 SQL 检查脚本里测(server/supabase/tests/20261106c_econ_state_check.sql, 32 条)。这里走真入口 —— 积分赛匹配会话
##   referee_run.start_ranked(), 假服务器按剧本回包 —— 量客户端:
##   A econ_pending(服务器还没重放完)⇒ 先补传流水、隔 2 秒自动重交; 第三次收了 ⇒ 建任务、屏上没出错
##   B ★econ_mismatch(本机改了存档: 多塞一件 3★、多 999 币)⇒ 拉服务器那份流水在本机重放对齐 ⇒ 作弊那部分没了、
##     本机资产 = 服务器流水重放的结果; 屏上「装备已同步，请重新开战」
##   C econ_invalid(服务器判第 2 条不合法)⇒ 先 econ_truncate(at 2)认它, 再拉剩下的那 2 条对齐
## 反向验证(手工, 见方案书): referee_run 不处理 econ_* ⇒ A / B 红。

const SB := preload("res://scripts/net/supabase.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const EL := preload("res://scripts/gamedata/econ_ledger.gd")
const EN := preload("res://scripts/net/econ_net.gd")
const DEAD_URL := "http://127.0.0.1:9"

var _fails := 0
var _n := 0
var _starts: Array = []        # 剧本: 每次 referee_ranked_start 回什么
var _start_n := 0
var _start_ms: Array = []
var _rows: Array = []          # 假服务器上的流水 [{seq, op}]
var _commits := 0
var _truncs: Array = []
var _gets := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	print(("  [PASS] " if c else "  [FAIL] ") + n + ("" if c or d == "" else "  " + d))
	if not c:
		_fails += 1


func _fake(_method, url, _headers, body, cb) -> void:
	var u := str(url)
	var j = JSON.parse_string(str(body)) if str(body) != "" else {}
	var b: Dictionary = j if j is Dictionary else {}
	if u.ends_with("/rest/v1/rpc/referee_ranked_start"):
		_start_n += 1
		_start_ms.append(Time.get_ticks_msec())
		var r: Dictionary = _starts[mini(_start_n - 1, _starts.size() - 1)]
		cb.call({"ok": true, "code": 200, "body": JSON.stringify(r)})
	elif u.ends_with("/rest/v1/rpc/econ_commit"):
		_commits += 1
		var from := int(b.get("p_from", 0))
		var ops: Array = b.get("p_ops", [])
		for i in range(ops.size()):
			if from + i >= _rows.size():
				_rows.append({"seq": from + i, "op": ops[i]})
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "next": _rows.size()})})
	elif u.ends_with("/rest/v1/rpc/econ_truncate"):
		_truncs.append(int(b.get("p_at", -1)))
		_rows = _rows.slice(0, int(b.get("p_at", 0)))
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "next": _rows.size()})})
	elif u.find("/rest/v1/econ_ops?") >= 0:
		_gets += 1
		cb.call({"ok": true, "code": 200, "body": JSON.stringify(_rows)})
	else:
		cb.call({"ok": true, "code": 200, "body": "{}"})


## 按墙钟等(重交间隔是真 2 秒; 无头一帧极快, 按帧数等会提前放弃)。
func _wait(cond: Callable, ms: int = 15000) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _canon(gs) -> String:
	return JSON.stringify({"a": EL.assets_of(gs), "p": EL.progress_of(gs)})


## 本周开局 + 一串真记账(锁统领 / 积分赛裁判发币 / 买经验 / 再一笔币)。返回那时的规整结果(= 服务器重放的应有结果)。
func _honest_week(gs) -> String:
	EconReplay.week_start(gs)
	gs.econ_log = []
	gs.econ_up = 0
	gs.season_total_battles = 2
	EL.rebase(gs)
	gs.econ({"op": "leaders", "ids": ["ninja", "dice", "pirate"]})
	gs.econ({"op": "income", "src": "ranked_ref", "coins": 30, "xp": 2, "axe": true, "candy": 0})
	gs.econ({"op": "buy_xp"})
	gs.econ({"op": "income", "src": "ranked_ref", "coins": 25, "xp": 2, "axe": true, "candy": 0})
	return _canon(gs)


func _new_run():
	var run = load("res://scripts/systems/replay/referee_run.gd").new()
	add_child(run)
	return run


func _ready() -> void:
	await get_tree().process_frame
	var gs = GameState
	gs.test_mode = true
	var flags0 = gs.referee_flags
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	SB._reset_auth_for_test()
	SB.apply_auth_response(true, 200,
		'{"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1","user":{"id":"uid-sync","email":"s@x.co"}}')
	SB._transport_for_test = _fake
	gs.referee_flags = {RN.K_FINALS: false, RN.K_GAUNTLET: false, RN.K_RANKED: true, RN.K_ECON: true}
	_ok("分母: 记账开关开 + 积分赛开关开 + 后端配上", EN.on() and RN.ranked_on() and SB.enabled())

	## ── A econ_pending ⇒ 补传 + 自动重交 ──
	var truth := _honest_week(gs)
	_rows = []
	_starts = [{"ok": false, "reason": "econ_pending", "have": 0, "need": 4},
		{"ok": false, "reason": "econ_pending", "have": 2, "need": 4},
		{"ok": true, "job_id": 4242, "match_id": "5b2c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b",
			"opp": {"profile": {"name": "x", "avatar": "ninja", "id": "g_x", "tag": "t"}, "leaders": ["ninja"]},
			"ledger": {"battles": 2, "wins": 1, "hearts": 6, "sweeps": 0, "eggs": 1, "used": 2}}]
	_start_n = 0
	_start_ms = []
	var c0 := _commits
	var run = _new_run()
	run.start_ranked()
	await _wait(func() -> bool: return _start_n >= 3 and int(run.job_id) == 4242)
	_ok("A ★econ_pending 两次 ⇒ 自动重交到第三次被收(建了任务 4242)", _start_n == 3 and int(run.job_id) == 4242,
		"交了 %d 次 job=%d state=%s msg=%s" % [_start_n, int(run.job_id), str(run.state), str(run.msg)])
	_ok("A 重交间隔约 2 秒(不是连发)", _start_ms.size() >= 2 and int(_start_ms[1]) - int(_start_ms[0]) >= 1500,
		str(_start_ms))
	_ok("A 等的时候把本机流水传上去了(服务器那份 = 本机 %d 条)" % (gs.econ_log as Array).size(),
		_commits > c0 and _rows.size() == (gs.econ_log as Array).size())
	_ok("A 被收之后重交计数归零", int(run.econ_tries) == 0)
	run.queue_free()
	gs.referee_pending = {}

	## ── B econ_mismatch ⇒ 按服务器流水对齐 ──
	truth = _honest_week(gs)
	_rows = []
	for i in range((gs.econ_log as Array).size()):
		_rows.append({"seq": i, "op": (gs.econ_log[i] as Dictionary).duplicate(true)})
	gs.econ_up = _rows.size()
	## 本机改存档(不走记账口): 多 999 币、背包多塞一件 3★
	gs.meta_deepsea_coins = int(gs.meta_deepsea_coins) + 999
	(gs.persistent_bench as Array).append({"id": "p2eq_050", "star": 3})
	_ok("B 分母: 改过之后本机与服务器那份确实不同", _canon(gs) != truth)
	_starts = [{"ok": false, "reason": "econ_mismatch", "what": "worn:ninja", "ledger": {}}]
	_start_n = 0
	var a0 := EN.adopts
	run = _new_run()
	run.start_ranked()
	await _wait(func() -> bool: return str(run.state) == RW.ST_ERROR)
	_ok("B ★econ_mismatch ⇒ 拉了服务器流水对齐(GET 一次)", EN.adopts == a0 + 1 and _gets >= 1, "adopts %d→%d gets=%d" % [a0, EN.adopts, _gets])
	_ok("B ★对齐之后本机资产 = 服务器流水重放的结果(多的 999 币和那件 3★ 没了)", _canon(gs) == truth,
		"本机 %s" % _canon(gs).left(160))
	_ok("B 本机流水换成服务器那份、econ_up 跟上", (gs.econ_log as Array).size() == _rows.size() and int(gs.econ_up) == _rows.size())
	_ok("B 屏上「%s」" % RW.TXT_ECON_SYNCED, str(run.msg) == RW.TXT_ECON_SYNCED, str(run.msg))
	run.queue_free()

	## ── C econ_invalid(at 2)⇒ 先截再对齐 ──
	truth = _honest_week(gs)
	_rows = []
	for i in range((gs.econ_log as Array).size()):
		_rows.append({"seq": i, "op": (gs.econ_log[i] as Dictionary).duplicate(true)})
	gs.econ_up = _rows.size()
	_starts = [{"ok": false, "reason": "econ_invalid", "at": 2, "why": "apply:buy_xp:coins", "ledger": {}}]
	_start_n = 0
	_truncs = []
	run = _new_run()
	run.start_ranked()
	await _wait(func() -> bool: return str(run.state) == RW.ST_ERROR)
	_ok("C ★econ_invalid at 2 ⇒ 先 econ_truncate(at 2)", _truncs == [2], str(_truncs))
	_ok("C 再拉剩下的 2 条对齐: 本机流水 2 条、econ_up 2", (gs.econ_log as Array).size() == 2 and int(gs.econ_up) == 2,
		"log=%d up=%d" % [(gs.econ_log as Array).size(), int(gs.econ_up)])
	run.queue_free()

	SB._transport_for_test = Callable()
	OS.set_environment("TURTLE_SUPABASE", " ")
	SB._reset_auth_for_test()
	gs.referee_flags = flags0
	gs.referee_pending = {}
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS" if _fails == 0 else "FAILED: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
