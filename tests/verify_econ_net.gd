extends Node
## verify_econ_net —— S3: 经济流水上服务器 · 客户端那一半(方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.2 / §4.4)。
##
## 用户 2026-11-06「装备要改成伏击机装(= 服务器记账)了，这个要做。」服务端 econ_commit 的规则(拒断号 / 种子绑序号 / 重试幂等)
##   在 SQL 沙盒与内测服回滚事务里测过(server/supabase/tests/20261106_econ_ops_check.sql, 25 条)。这条门禁量客户端:
##   ① 开关 econ_on 关着: 掷货 / 刷新 / 开罐当场用本机种子成交, 一个请求都不发(与 0.22.8 一字不差)
##   ② 开着(走真入口: 商店进店自动换货 / GameState.break_candy_jar_async / GameState._net_tick 那一拍的 EconNet.pump):
##     · 要种子那一趟带上还没传的流水, 要的是「下一条」; 等种子时货架清空、点买不理
##     · 种子到了 ⇒ 用服务器那个种子成交; 之后上传 ⇒ 服务器那份流水与本机逐条相同
##     · ★服务器那份流水从本周开局重放 = 本机状态(S4 服务器重放的前提在客户端这一侧成立)
##     · 断号(本机以为传过了、服务器没有)⇒ 回到服务器说的位置补传; 同时只有一个在路上(忙 ⇒ 当场拒)
##   ③ ★反向: 本机把已拿到种子的那一条改成别的种子再传 ⇒ 服务器拒(mismatch), 流水停在原处
## 假服务器 = 本文件 `_server`(照 20261106_econ_ops.sql 的判据逐条写; 只用来驱动客户端, 判据本身由 SQL 检查脚本守)。

const SB := preload("res://scripts/net/supabase.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const EL := preload("res://scripts/gamedata/econ_ledger.gd")
const EN := preload("res://scripts/net/econ_net.gd")
const DEAD_URL := "http://127.0.0.1:9"
const KEYS := ["meta_deepsea_coins", "persistent_bench", "persistent_equipped", "dual_lineup", "equip_pool",
	"meta_shop_offer", "meta_shop_locked", "meta_shop_battles", "season_level", "season_xp", "season_leaders",
	"axe_exp_bar", "axe_exp_total", "axe_stage", "axe_final", "axe_syn_matches",
	"candy_jar_count", "candy_jar_broken", "candy_temp_levels",
	"chest_treasure_value", "chest_treasures_won", "incense_marks", "incense_charge"]

var _fails := 0
var _n := 0
var _rows: Array = []          # 假服务器的流水(序号 = 下标)
var _src: Array = []           # 每条是谁写的: client / server
var _reqs: Array = []          # 收到的 econ_commit 请求体
var _seed_k := 0
var _hold: Array = []          # 扣着不回的回包(量「等种子」那一刻)
var _holding := false


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	print(("  [PASS] " if c else "  [FAIL] ") + n + ("" if c or d == "" else "  " + d))
	if not c:
		_fails += 1


func _snap() -> Dictionary:
	var d := {}
	for k in KEYS:
		var v = GameState.get(k)
		d[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return d


func _put(d: Dictionary) -> void:
	for k in KEYS:
		var v = d[k]
		GameState.set(k, v.duplicate(true) if (v is Array or v is Dictionary) else v)


## 假服务器: econ_commit(照 SQL 的判据)
func _server(body: Dictionary) -> Dictionary:
	var from := int(body.get("p_from", -1))
	var ops: Array = body.get("p_ops", []) if body.get("p_ops") is Array else []
	var kind = body.get("p_kind", null)
	var nxt := _rows.size()
	if int(body.get("p_week", 0)) != EN.week():
		return {"ok": false, "reason": "week"}
	if from < 0 or from > nxt:
		return {"ok": false, "reason": "gap", "next": nxt}
	for i in range(ops.size()):
		var at := from + i
		if at < nxt:
			var have: Dictionary = _rows[at]
			var op: Dictionary = ops[i]
			if str(_src[at]) == "server":
				if str(op.get("op", "")) != str(have.get("op", "")) or int(op.get("seed", -1)) != int(have.get("seed", -2)):
					return {"ok": false, "reason": "mismatch", "at": at, "next": nxt}
			elif JSON.stringify(op) != JSON.stringify(have):
				return {"ok": false, "reason": "mismatch", "at": at, "next": nxt}
	for i in range(ops.size()):
		var at2 := from + i
		if at2 < nxt:
			if str(_src[at2]) == "server":
				_rows[at2] = (ops[i] as Dictionary).duplicate(true)
		else:
			_rows.append((ops[i] as Dictionary).duplicate(true))
			_src.append("client")
	nxt = maxi(nxt, from + ops.size())
	if kind == null:
		return {"ok": true, "next": nxt}
	var at3 := from + ops.size()
	if at3 < nxt:
		if str(_src[at3]) == "server" and str((_rows[at3] as Dictionary).get("op", "")) == str(kind):
			return {"ok": true, "seq": at3, "seed": int((_rows[at3] as Dictionary)["seed"]), "again": true, "next": nxt}
		return {"ok": false, "reason": "taken", "at": at3, "next": nxt}
	_seed_k += 1
	var seed := 700000 + _seed_k * 7919
	_rows.append({"op": str(kind), "seed": seed})
	_src.append("server")
	return {"ok": true, "seq": at3, "seed": seed, "next": at3 + 1}


func _fake(method, url, _headers, body, cb) -> void:
	if not str(url).ends_with("/rest/v1/rpc/econ_commit"):
		cb.call({"ok": true, "code": 200, "body": "{}"})
		return
	var j = JSON.parse_string(str(body))
	var b: Dictionary = j if j is Dictionary else {}
	_reqs.append(b)
	var resp := {"ok": true, "code": 200, "body": JSON.stringify(_server(b))}
	if _holding:
		_hold.append([cb, resp])
		return
	cb.call(resp)


func _release() -> void:
	_holding = false
	var h := _hold.duplicate()
	_hold.clear()
	for x in h:
		(x[0] as Callable).call(x[1])


func _wait(cond: Callable, frames: int = 240) -> bool:
	for _i in range(frames):
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


## 流水逐条比(序号对齐; 回包是 JSON 解出来的 ⇒ 整数成了 3.0, 按值比)
func _same_rows() -> Array:
	var led: Array = GameState.econ_log
	var bad: Array = []
	if led.size() != _rows.size():
		bad.append("条数 本机 %d / 服务器 %d" % [led.size(), _rows.size()])
	for i in range(mini(led.size(), _rows.size())):
		if JSON.stringify(EL._norm(led[i])) != JSON.stringify(EL._norm(_rows[i])):   # 数值按值比(同 jsonb: 3 = 3.0)
			bad.append("#%d 本机 %s / 服务器 %s" % [i, JSON.stringify(led[i]).left(120), JSON.stringify(_rows[i]).left(120)])
	return bad


func _ready() -> void:
	await get_tree().process_frame
	var gs = GameState
	gs.test_mode = true
	var flags0 = gs.referee_flags
	## 本周开局: 打过 3 场、500 深海币、统领含糖果龟(有罐)、货架从没掷过
	gs.econ_log = []
	gs.econ_up = 0
	gs.season_total_battles = 3
	gs.meta_deepsea_coins = 500
	gs.persistent_bench = []
	gs.persistent_equipped = {}
	gs.equip_pool = {}
	gs.meta_shop_offer = []
	gs.meta_shop_battles = -1
	gs.meta_shop_locked = false
	gs.season_level = 3
	gs.season_xp = 0
	gs.season_leaders = ["candy", "stone", "ice"]
	gs.dual_lineup = {}
	gs.candy_jar_count = 25
	gs.candy_jar_broken = false
	gs.candy_temp_levels = {}
	EL.rebase(gs)
	var start := _snap()

	## ── ① 开关关着: 不发请求, 当场成交 ──
	gs.referee_flags = {}
	var c0 := EN.commits
	var r_off: Dictionary = EN.seeded({"op": "refresh"}, 4242, func(_r: Dictionary) -> void: pass)
	_ok("① 开关关: 换一批当场成交(本机种子), 不挂起", bool(r_off.get("ok", false)) and not r_off.has("pending")
		and int((gs.econ_log as Array)[-1].get("seed", -1)) == 4242, str(r_off))
	_ok("① 开关关: 一个请求都没发, pump 也不发", EN.commits == c0 and not EN.pump(), "commits %d→%d" % [c0, EN.commits])
	## 退回开局, 下面开着开关从头来
	_put(start)
	gs.econ_log = []
	gs.econ_up = 0
	EL.rebase(gs)

	## ── ② 开关开着 ──
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	SB._reset_auth_for_test()
	SB.apply_auth_response(true, 200,
		'{"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1","user":{"id":"uid-econ","email":"e@x.co"}}')
	SB._transport_for_test = _fake
	gs.referee_flags = {RN.K_FINALS: false, RN.K_GAUNTLET: false, RN.K_RANKED: false, RN.K_ECON: true}
	_ok("② 分母: 开关开 + 后端配上 ⇒ EconNet.on()", EN.on() and SB.enabled())
	gs.econ({"op": "lock", "on": true})
	gs.econ({"op": "lock", "on": false})
	_ok("② 分母: 本机先记了两条(还没传)", (gs.econ_log as Array).size() == 2 and int(gs.econ_up) == 0)
	## 进店 ⇒ 该换货 ⇒ 要种子(扣着回包, 量「等」的那一刻)
	_holding = true
	var shop = load("res://scripts/scenes/ShopScene.gd").new()
	add_child(shop)
	await _wait(func() -> bool: return _hold.size() >= 1)
	var b0: Dictionary = _reqs[-1] if not _reqs.is_empty() else {}
	_ok("② ★进店要种子那一趟: 从 0 起带上没传的两条、要的是 roll", int(b0.get("p_from", -1)) == 0
		and (b0.get("p_ops", []) as Array).size() == 2 and str(b0.get("p_kind", "")) == "roll", JSON.stringify(b0).left(200))
	var coins_w := int(gs.meta_deepsea_coins)
	shop._on_buy(0)
	_ok("② ★等种子时货架是空的、点买不理(钱一个不动)", bool(shop._econ_wait) and (shop._offer as Array).is_empty()
		and int(gs.meta_deepsea_coins) == coins_w)
	var busy_r: Dictionary = EN.seeded({"op": "refresh"}, 1, func(_r: Dictionary) -> void: pass)
	_ok("② 同时只有一个在路上: 这时候再要种子 ⇒ busy", str(busy_r.get("reason", "")) == "busy", str(busy_r))
	_release()
	await _wait(func() -> bool: return not bool(shop._econ_wait))
	var led: Array = gs.econ_log
	_ok("② ★种子到了: 货架换上、第 2 条 = roll 且种子是服务器发的那个", not bool(shop._econ_wait)
		and (shop._offer as Array).size() > 0 and led.size() == 3 and str(led[2].get("op", "")) == "roll"
		and int(led[2].get("seed", -1)) == int((_rows[2] as Dictionary).get("seed", -2)) and int(gs.econ_up) == 2,
		"log=%d up=%d" % [led.size(), int(gs.econ_up)])
	shop.queue_free()
	## 买一件(本机即时记账), 再开罐(要种子)
	for i in range((gs.meta_shop_offer as Array).size()):
		if gs.meta_shop_offer[i] is Dictionary and bool(gs.econ({"op": "buy", "slot": i}).get("ok", false)):
			break
	var got := [null]
	gs.break_candy_jar_async(func(rw: Dictionary) -> void: got[0] = rw)
	await _wait(func() -> bool: return got[0] != null)
	_ok("② 开罐(GameState.break_candy_jar_async): 等到奖励, 用的是服务器种子", got[0] is Dictionary and not (got[0] as Dictionary).is_empty()
		and str((gs.econ_log as Array)[-1].get("op", "")) == "candy"
		and int((gs.econ_log as Array)[-1].get("seed", -1)) == int((_rows[-1] as Dictionary).get("seed", -2)), str(got[0]))
	## 20 秒那一拍(test_mode 下 _net_tick 不跑, 这里直接调它调的那一句)
	gs.econ({"op": "lock", "on": true})
	EN.pump()
	await _wait(func() -> bool: return not EN.busy)
	_ok("② ★上传之后服务器那份流水与本机逐条相同", _same_rows().is_empty(), str(_same_rows()))
	_ok("② econ_up 跟到本机流水末尾", int(gs.econ_up) == (gs.econ_log as Array).size(), "up=%d log=%d" % [int(gs.econ_up), (gs.econ_log as Array).size()])
	## ★服务器那份流水从本周开局重放 = 本机
	var live := JSON.stringify({"a": EL.assets_of(gs), "p": EL.progress_of(gs)})
	var keep := _snap()
	var keep_log: Array = (gs.econ_log as Array).duplicate(true)
	_put(start)
	gs.referee_flags = {}
	var bad: Array = []
	for row in _rows:
		gs.season_total_battles = int((row as Dictionary).get("bt", 0))
		if not bool(EL.apply(gs, row).get("ok", false)):
			bad.append(str((row as Dictionary).get("op", "")))
	var replayed := JSON.stringify({"a": EL.assets_of(gs), "p": EL.progress_of(gs)})
	_ok("② ★服务器那份流水从开局重放 ⇒ 每条成交、与本机逐字节相同(%d 字节, %d 条)" % [live.length(), _rows.size()],
		bad.is_empty() and replayed == live, "不成交 %s" % str(bad))
	_put(keep)
	gs.econ_log = keep_log
	gs.referee_flags = {RN.K_FINALS: false, RN.K_GAUNTLET: false, RN.K_RANKED: false, RN.K_ECON: true}
	EL.rebase(gs)
	## 断号: 本机以为传到第 N 条(其实服务器只有更少)⇒ 回到服务器说的位置补传
	gs.econ({"op": "lock", "on": false})
	gs.econ_up = (gs.econ_log as Array).size()          # 假装最后一条已经传过(其实没有)
	gs.econ({"op": "lock", "on": true})
	EN.pump()
	await _wait(func() -> bool: return not EN.busy)
	_ok("② 断号 ⇒ 服务器回 gap, econ_up 退回服务器那一条", EN.last_error == "gap" and int(gs.econ_up) == _rows.size(),
		"err=%s up=%d server=%d" % [EN.last_error, int(gs.econ_up), _rows.size()])
	EN.pump()
	await _wait(func() -> bool: return not EN.busy)
	_ok("② 再传一次就补齐了", _same_rows().is_empty() and int(gs.econ_up) == (gs.econ_log as Array).size(), str(_same_rows()))

	## ── ③ 反向: 拿到的种子改掉再传 ⇒ 服务器拒 ──
	var n_srv := _rows.size()
	var t: Dictionary = {}
	gs.econ_up = 0
	for i in range((gs.econ_log as Array).size()):
		if str((gs.econ_log[i] as Dictionary).get("op", "")) == "roll":
			t = gs.econ_log[i]
			break
	var real_seed := int(t.get("seed", 0))
	t["seed"] = real_seed + 1                           # 作弊: 换个种子
	EN.pump()
	await _wait(func() -> bool: return not EN.busy)
	_ok("③ ★本机改了服务器发的种子再传 ⇒ mismatch, 服务器那份一条没多", EN.last_error == "mismatch" and _rows.size() == n_srv,
		"err=%s rows %d→%d" % [EN.last_error, n_srv, _rows.size()])
	t["seed"] = real_seed

	## 收尾
	SB._transport_for_test = Callable()
	OS.set_environment("TURTLE_SUPABASE", " ")
	SB._reset_auth_for_test()
	gs.referee_flags = flags0
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS" if _fails == 0 else "FAILED: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
