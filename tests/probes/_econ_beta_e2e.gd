extends Node
## 局外经济记账全链路实测(方案书 docs/plans/20261106-装备与深海币服务器记账.md · S5 之前的一次冒烟)。由 tools/econ_beta_smoke.py 起, 不单独跑。
##
## 真客户端代码(EconNet / referee_run / 商店记账)走真网络连内测服真数据库; 重放由编排脚本用轮询器原函数 + 真 Godot 做。不碰裁判机、不碰正式服。
##   A 老实的玩家: 积分赛结算 → 进店掷货(服务器发种子)→ 买 → 穿 → 开局 ⇒ 过比对(服务器回 no_opponent = 走到了比对之后)
##   B 改存档多塞一件 3★ + 999 币 ⇒ 服务器拒、本机按服务器流水对齐、作弊那部分没了; 再开局过比对
##   C 伪造一笔 99999 币的收入并上传 ⇒ 重放判那一条不合法 ⇒ 客户端截断对齐、币回到原来; 再开局过比对
##   D 服务器发了种子、本机没成交(闪退)⇒ 不卡开局

const EL := preload("res://scripts/gamedata/econ_ledger.gd")
const EN := preload("res://scripts/net/econ_net.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const SB := preload("res://scripts/net/supabase.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const MID := "5b2c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"

var _fails := 0
var _n := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	print(("  [PASS] " if c else "  [FAIL] ") + n + ("" if d == "" else "  " + d))
	if not c:
		_fails += 1


func _canon(gs) -> String:
	return JSON.stringify({"a": EL.assets_of(gs), "p": EL.progress_of(gs)})


func _wait(cond: Callable, ms: int = 60000) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


## 走真入口开一局, 等到有结果。返回 {msg, ms, passed(过了比对 = 服务器回 no_opponent 或真建了任务)}。
func _start() -> Dictionary:
	var run = load("res://scripts/systems/replay/referee_run.gd").new()
	add_child(run)
	var t0 := Time.get_ticks_msec()
	run.start_ranked()
	await _wait(func() -> bool: return str(run.state) == RW.ST_ERROR or int(run.job_id) > 0, 90000)
	var out := {"msg": str(run.msg), "ms": Time.get_ticks_msec() - t0, "job": int(run.job_id),
		"passed": str(run.msg) == RW.TXT_NO_MATCH or int(run.job_id) > 0}
	run.queue_free()
	await get_tree().process_frame
	return out


func _ready() -> void:
	await get_tree().process_frame
	## ★硬保险: 不是内测服就退出, 一个请求都不发(这个探针会写数据、开局、改流水, 绝不能连到正式服)
	if not load("res://scripts/net/server_env.gd").is_beta():
		printerr("[E2E] 不是内测服(要 TURTLE_SERVER=beta + debug 构建), 退出, 未发任何请求")
		get_tree().quit(3)
		return
	var gs = GameState
	gs.test_mode = true
	var auth := FileAccess.get_file_as_string(OS.get_environment("E2E_AUTH"))
	_ok("分母: 连的是内测服(TURTLE_SERVER=beta)、后端配上、登录成功", SB.enabled() and SB.apply_auth_response(true, 200, auth))
	var fl := [false]
	RN.refresh_flags_async(func(_r = null) -> void: fl[0] = true)
	await _wait(func() -> bool: return RN.econ_on(), 15000)
	_ok("分母: 真开关 econ_on 从内测服读到了开着", EN.on(), str(gs.referee_flags))

	var wk := P2.week_anchor_utc(int(P2.now_utc()))
	gs.start_new_season()
	gs.week_anchor_ts = wk
	gs.econ_log = []
	gs.econ_up = 0
	EL.rebase(gs)

	## ── A 老实的玩家 ──
	gs.econ({"op": "leaders", "ids": ["candy", "stone", "ice"]})
	gs.referee_pending = RW.ranked_bill(77, MID, wk, {})
	var v: Dictionary = RW.settle_ranked(gs, 77, {"status": "done", "won": 1, "coins": 0,
		"ranked": {"battles": 1, "wins": 1, "hearts": RW.P2C.HEARTS_MAX, "sweeps": 0, "eggs": 1, "used": 1, "reward": 20}})
	_ok("A 分母: 积分赛结算记了账(币 %d)" % int(gs.meta_deepsea_coins), not v.is_empty() and int(gs.meta_deepsea_coins) == 20)
	var got := [{}]
	var r0: Dictionary = EN.seeded({"op": "roll"}, 0, func(r: Dictionary) -> void: got[0] = r)
	_ok("A 进店掷货走服务器要种子", bool(r0.get("pending", false)), str(r0))
	await _wait(func() -> bool: return not (got[0] as Dictionary).is_empty(), 15000)
	_ok("A ★服务器发了种子、货架有货", bool((got[0] as Dictionary).get("ok", false)) and not (gs.meta_shop_offer as Array).is_empty(), str(got[0]))
	var bought := 0
	for slot in range(6):
		if bought < 1 and bool(gs.econ({"op": "buy", "slot": slot}).get("ok", false)):
			bought += 1
	var k := -1
	for i in range((gs.persistent_bench as Array).size()):
		if k < 0 and gs.persistent_bench[i] is Dictionary and str((gs.persistent_bench[i] as Dictionary).get("kind", "")) != "item":
			k = i
	var eq: Dictionary = gs.econ({"op": "equip", "pid": "candy", "bench": k})
	_ok("A 分母: 买了 1 件、穿上了", bought == 1 and bool(eq.get("ok", false)), "bought=%d k=%d %s" % [bought, k, str(eq)])
	var honest := _canon(gs)
	var a := await _start()
	_ok("A ★老实玩家开局过比对(用时 %d 毫秒, 含等重放)" % int(a["ms"]), bool(a["passed"]), str(a))
	_ok("A 流水全到了服务器", int(gs.econ_up) == (gs.econ_log as Array).size(), "up=%d log=%d" % [int(gs.econ_up), (gs.econ_log as Array).size()])

	## ── B 改存档 ──
	(gs.persistent_equipped["candy"] as Array).append({"id": "p2eq_050", "star": 3})
	gs.meta_deepsea_coins = int(gs.meta_deepsea_coins) + 999
	_ok("B 分母: 本机确实改过了", _canon(gs) != honest)
	var b := await _start()
	_ok("B ★改存档 ⇒ 服务器拒、屏上「%s」" % RW.TXT_ECON_SYNCED, str(b["msg"]) == RW.TXT_ECON_SYNCED, str(b))
	_ok("B ★对齐之后作弊那部分没了(本机 = 老实时的资产)", _canon(gs) == honest, _canon(gs).left(200))
	var b2 := await _start()
	_ok("B 对齐之后再开局过比对", bool(b2["passed"]), str(b2))

	## ── C 伪造收入 ──
	var n0 := (gs.econ_log as Array).size()
	gs.econ({"op": "income", "src": "ranked_ref", "coins": 99999, "xp": 2, "axe": true, "candy": 2})
	_ok("C 分母: 本机多了 99999 币", int(gs.meta_deepsea_coins) >= 99999, str(gs.meta_deepsea_coins))
	var c := await _start()
	_ok("C ★伪造收入 ⇒ 重放判不合法、截断对齐", str(c["msg"]) == RW.TXT_ECON_SYNCED, str(c))
	_ok("C ★币回到原来、流水退回 %d 条" % n0, _canon(gs) == honest and (gs.econ_log as Array).size() == n0,
		"币 %d log %d" % [int(gs.meta_deepsea_coins), (gs.econ_log as Array).size()])
	var c2 := await _start()
	_ok("C 截断之后再开局过比对", bool(c2["passed"]), str(c2))

	## ── D 闪退留下的种子行 ──
	var done := [false]
	EN._send(int(gs.econ_up), [], "refresh", func(_r: Dictionary) -> void: done[0] = true)
	await _wait(func() -> bool: return done[0], 15000)
	_ok("D 分母: 服务器发了种子、本机没成交", done[0] and (gs.econ_log as Array).size() == n0)
	var d := await _start()
	_ok("D ★尾部种子行不卡开局", bool(d["passed"]), str(d))

	gs.referee_flags = {}
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS" if _fails == 0 else "FAILED: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
