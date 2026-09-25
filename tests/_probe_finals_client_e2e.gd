extends Node
## DEV 探针: 让**真游戏客户端**连**真服务器**把决赛日那条链走一遍。
## ★不是门禁(下划线开头 ⇒ 不被自动发现; 要真网络 + 真账号)。
##
## ══════════════════════════════════════════════════════════════════════
##  为什么非有它不可
## ══════════════════════════════════════════════════════════════════════
## `tools/probe_finals_server.py` 验的是**服务端**那条链(Python 直接打 REST, 89/89)。
## 而客户端那半一直只有门禁: `verify_finals_feed` 106 条 + `verify_bracket_map` 58 条，
## 全部用**注入传输**喂假回包 —— 从来没有一次**真的连着服务器**跑过。
##
## 今天三个 bug 全是「各块单看都对、串起来断掉」。这一份就是把客户端那半也串一遍：
##   ① 真登录(匿名号) → ② 真 `finals_view` → ③ 真算对手是几号
##   → ④ 真 `finals_opponent` 拿快照 → ⑤ 真把 `dual_ghost` / `finals_match` 摆好
##
## ★⑤ 之后**不真打那一场** —— 打一局要几十秒且结果随机, 而「摆没摆对」才是这里要验的；
##   真打完之后报不报得上去由 `verify_finals_feed` ⑩(走真入口 `_settle_season`)守着。
##   **这条缺口是显式的, 不是忘了。**
##
## 跑法(要真网络):
##   TURTLE_E2E=1 <godot> --headless --path . res://tests/_probe_finals_client_e2e.tscn --quit-after 3000

const MAP := preload("res://scripts/scenes/BracketMapScene.gd")
const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

var _n := 0
var _bad := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_bad += 1
		print("  [FAIL] ", name, "  ", detail)


## 等一个条件成立（**墙钟**，不是帧数 —— 网络回包与帧率无关）。
func _wait(cond: Callable, sec: float, tag: String) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await get_tree().process_frame
		if bool(cond.call()):
			return true
	print("     [超时] 等 %s 等了 %.1f 秒" % [tag, sec])
	return false


func _ready() -> void:
	await get_tree().process_frame
	print("=== 决赛日 · 真客户端 × 真服务器 ===")
	if OS.get_environment("TURTLE_E2E") != "1":
		print("  (没带 TURTLE_E2E=1 ⇒ 不打真网络, 直接退出)")
		get_tree().quit(0)
		return
	GameState.test_mode = true

	## ① 真登录: 走产品自己的匿名注册那条路
	SB._reset_auth_for_test()
	## ★★两趟跑: 第一趟开一个新匿名号并把 account_id + refresh_token 写盘;
	##   第二趟(包装器造完桶之后)**拿 refresh_token 续登录** —— 那正是产品
	##   「重开 App 之后」走的那条路, 顺带把它也验了([[fb-restart-is-a-separate-scenario]])。
	var seed_f := "user://e2e_ident.json"
	var reuse := OS.get_environment("E2E_PHASE") == "2"
	if reuse and FileAccess.file_exists(seed_f):
		var jf := FileAccess.open(seed_f, FileAccess.READ)
		var jd = JSON.parse_string(jf.get_as_text())
		jf.close()
		if jd is Dictionary:
			GameState.account_id = str((jd as Dictionary).get("id", ""))
			GameState.auth_refresh = str((jd as Dictionary).get("rt", ""))
		print("     [第二趟] 拿上一趟的身份续登录: %s…" % str(GameState.account_id).substr(0, 8))
	else:
		GameState.account_id = ""
		GameState.auth_refresh = ""
	_ok("① ★分母: 后端配置读得到(否则下面全是空检查)", SB.enabled(), SB.base_url().substr(0, 28))
	SB.ensure_signed_in_async()
	var got := await _wait(func(): return SB._token != "", 25.0, "匿名登录")
	_ok("① ★★真的登上了(产品自己的 ensure_signed_in_async, 不是我伪造 token)",
		got and SB._token != "" and str(GameState.account_id) != "",
		"account_id=%s…" % str(GameState.account_id).substr(0, 8))
	if not got:
		_finish()
		return
	## 第一趟: 把身份写盘给包装器用, 然后就结束 —— 桶还没造, 再往下全是空检查
	if not reuse:
		var wf := FileAccess.open(seed_f, FileAccess.WRITE)
		wf.store_string(JSON.stringify({"id": str(GameState.account_id),
			"rt": str(GameState.auth_refresh)}))
		wf.close()
		print("     [第一趟] 身份已写盘, 交给包装器造桶; 再跑一趟 E2E_PHASE=2")
		_finish()
		return

	## ② 造一个只有我自己的桶 —— 用**真周号**(客户端 `week_anchor_utc` 算的那个),
	##    否则 `fetch_finals_async` 查的周和我造的周对不上, 查出来是空的。
	var wk := P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	print("     本周锚点(客户端算的) = %d" % wk)
	print("     ⚠ 这一步要管理员 SQL 造桶, 由外面的 python 包装器做; 本探针只负责【客户端那半】")

	## ③ 真取数
	SB.finals_clear()
	SB.fetch_finals_async(wk, -1)
	var ok2 := await _wait(func(): return SB.finals_tried(), 25.0, "finals_view 回包")
	var v: Dictionary = SB.finals_cached()
	_ok("③ ★★真的问到了服务端(不是注入的假回包)", ok2, "tried=%s" % SB.finals_tried())
	_ok("③ ★★拿到了我自己那个桶", int(v.get("size", 0)) >= 2, str(v).substr(0, 170))
	if int(v.get("size", 0)) < 2:
		print("     (没有桶 ⇒ 后面没法验; 先让包装器造桶再跑)")
		_finish()
		return
	_ok("③ ★回包带了桶号与 round_at(问对手 / 购物窗都要用)",
		int(v.get("bucket", -1)) >= 0 and int(v.get("round_at", 0)) > 0,
		"bucket=%d round_at=%d" % [int(v.get("bucket", -1)), int(v.get("round_at", 0))])

	## ④ 把真回包喂进真场景, 让它自己算对手
	var m = MAP.new()
	m.set_bucket(v)
	add_child(m)
	await get_tree().process_frame
	var me := int(v.get("me", -1))
	_ok("④ ★★场景认出了「我」(种子 %d)" % me, me >= 0, str(me))
	var r := int(v.get("round", 1))
	var my_m := -1
	for mm in range(8):
		if m.is_my_match(r, mm):
			my_m = mm
			break
	_ok("④ ★★算出了我在第 %d 轮的第几场" % r, my_m >= 0, str(my_m))
	var foe := m.my_opponent_seed(r, my_m) if my_m >= 0 else -1
	_ok("④ ★★算出对手是几号种子", foe >= 0, str(foe))
	_ok("④ ★该不该去问服务端 = 是", my_m >= 0 and m.should_fetch_opponent(r, my_m))

	## ⑤ 真去要对手快照
	SB.opponent_clear()
	SB._opp_inflight = false
	SB.fetch_opponent_async(wk, int(v.get("bucket", -1)), r, foe)
	var ok3 := await _wait(func(): return SB.opponent_tried(), 25.0, "finals_opponent 回包")
	var o: Dictionary = SB.opponent_cached()
	_ok("⑤ ★★★真的从服务器拿到了对手快照 —— 这条链在今天之前是断的",
		ok3 and bool(o.get("ok", false)) and (o.get("snapshot", {}) as Dictionary).size() > 0,
		str(o).substr(0, 170))

	## ⑥ 摆盘: 真场景自己把 dual_ghost / finals_match 摆好(不真打那一场, 见文件头)
	if bool(o.get("ok", false)):
		GameState.dual_ghost = {}
		GameState.finals_match = {}
		var side := m.my_side(r, my_m)
		_ok("⑥ ★算出我在这一场的哪一侧", side == 0 or side == 1, str(side))
		_ok("⑥ ★★★报结果时该报的 winner_side: 赢=%d 输=%d(两者必须不同)" % [
			m.winner_side_for(r, my_m, true), m.winner_side_for(r, my_m, false)],
			m.winner_side_for(r, my_m, true) != m.winner_side_for(r, my_m, false)
				and m.winner_side_for(r, my_m, true) == side)
	m.queue_free()
	await get_tree().process_frame
	_finish()


func _finish() -> void:
	SB._reset_auth_for_test()
	print("")
	print("  (共 %d 条, 失败 %d)" % [_n, _bad])
	print("CLIENT E2E OK" if _bad == 0 else "CLIENT E2E FAIL x%d" % _bad)
	get_tree().quit(1 if _bad > 0 else 0)
