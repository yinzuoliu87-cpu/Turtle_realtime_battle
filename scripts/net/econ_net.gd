extends RefCounted
## 局外经济流水上服务器 · 客户端那一半(方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.2 / §4.4 · S3; 服务端 20261106 / 20261106b)。
##
## ★开关 `econ_on`(RefereeNet.econ_on, 服务端 referee_flags 回)关着 ⇒ 这里什么都不往外发:
##   要种子的操作当场用本机种子成交(与 0.22.8 一字不差), 流水不上传。开关只在周一换周时开(方案书 §4.6), 内测服先开一整周对账。
## 开着:
##   ① 掷货 / 刷新 / 开糖果罐 = `seeded(op, 本机种子, done)`: 把还没传的流水 + 「我要下一条的种子」一起交给 econ_commit(一次往返),
##     拿到种子再 `EconLedger.do`。服务器只给紧接着已上传的下一条发种子, 发了就算这一笔已经发生(防「挑种子」, 见服务端头注)。
##   ② 其余操作照常即时记账; `pump()` 把还没传的那一截传上去(GameState._net_tick 每 20 秒那一拍调, 与云存档同一拍)。
##   ③ `GameState.econ_up` = 服务器已经有的条数(下一次从这里传)。重传是幂等的(服务端逐条比对), 所以 econ_up 不用急着落盘。

const SB := preload("res://scripts/net/supabase.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const EL := preload("res://scripts/gamedata/econ_ledger.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const KINDS := ["roll", "refresh", "candy"]
const BATCH := 400            # 一次最多传几条(服务端上限 500)
const RPC := "/rest/v1/rpc/econ_commit"

static var busy := false      # 同一时刻只有一个提交在路上(两个并发的种子请求会抢同一个序号)
static var commits := 0       # 发出去几次(门禁量「真发了」)
static var last_error := ""   # 最近一次失败的原因(mismatch / taken = 本机与服务器账不一致, S4 对齐)
static var adopts := 0       # 按服务器流水对齐了几次(门禁量)


static func on() -> bool:
	return GameState != null and RN.econ_on() and not EL.quiet(GameState)


## 开局前还要等吗: 有没传的流水 / 有提交在路上。开关关着恒 false。
static func unsynced() -> bool:
	return on() and (busy or int(GameState.econ_up) < (GameState.econ_log as Array).size())


## 上传被服务器拒了(本机与服务器两份账不一致, 传多少次都一样)⇒ 只能按服务器那份对齐。
static func conflict() -> bool:
	return last_error == "mismatch" or last_error == "taken"


## 本周锚点(与服务端 econ_week_now 同一个口径: 周一 00:00 UTC)。
static func week() -> int:
	return P2C.week_anchor_utc(int(P2C.now_utc()))


## 纯函数: econ_commit 回包 → {ok, reason, next, seq, seed, again, at}。
##   404 = 服务端没有这个函数(迁移没上)⇒ off; 断网 / 5xx / 看不懂 ⇒ net。
static func parse_commit(ok: bool, code: int, body: String) -> Dictionary:
	if not ok:
		return {"ok": false, "reason": "net"}
	if code == 404:
		return {"ok": false, "reason": "off"}
	if code < 200 or code >= 300:
		return {"ok": false, "reason": "net", "code": code}
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Dictionary):
		return {"ok": false, "reason": "net"}
	var d: Dictionary = j.data
	return {"ok": bool(d.get("ok", false)), "reason": str(d.get("reason", "")),
		"next": int(d.get("next", -1)), "seq": int(d.get("seq", -1)), "seed": int(d.get("seed", -1)),
		"again": bool(d.get("again", false)), "at": int(d.get("at", -1))}


## 还没传的那一截(从 econ_up 起, 最多 BATCH 条)。
static func pending_rows(gs) -> Array:
	var led: Array = gs.econ_log
	var from := clampi(int(gs.econ_up), 0, led.size())
	return led.slice(from, mini(led.size(), from + BATCH))


static func _send(from: int, ops: Array, kind: String, done: Callable) -> bool:
	if not SB.enabled():
		return false
	var n = SB._spawn()
	if n == null:
		return false
	commits += 1
	var body := {"p_week": week(), "p_from": from, "p_ops": ops, "p_kind": (kind if kind != "" else null)}
	n._get_once(RPC, "POST", JSON.stringify(body), done,
		func(res: Dictionary) -> Dictionary:
			return parse_commit(bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", ""))))
	return true


## 要种子的操作。`op` = {"op": roll / refresh / candy, …}(不带 seed); `local_seed` = 开关关着时用的本机种子。
## 返回: 开关关着 ⇒ 当场成交, 返回 EconLedger.do 的结果(★不调 done);
##       开着 ⇒ 返回 {"pending": true}, 拿到种子成交后调 `done.call(结果)`; 发不出去 / 正忙 ⇒ 当场返回 {ok: false, reason}。
static func seeded(op: Dictionary, local_seed: int, done: Callable) -> Dictionary:
	var gs = GameState
	var row: Dictionary = op.duplicate(true)
	if not on():
		row["seed"] = local_seed
		return EL.do(gs, row)
	if not str(row.get("op", "")) in KINDS:
		return {"ok": false, "reason": "bad_kind"}
	if busy:
		return {"ok": false, "reason": "busy"}
	## 先过一次哨兵: 它可能要补一条 prog(宝箱 / 香火终值)—— 那一条必须排在种子那一条前面、跟着这一趟一起传
	EL.check(gs, "seeded")
	var from := clampi(int(gs.econ_up), 0, (gs.econ_log as Array).size())
	var ops: Array = pending_rows(gs)
	var want := from + ops.size()
	if want != (gs.econ_log as Array).size():
		pump()                         # 积压超过一批: 先传一批, 这一下请玩家再点一次
		return {"ok": false, "reason": "backlog"}
	busy = true
	var sent := _send(from, ops, str(row["op"]), func(r: Dictionary) -> void:
		busy = false
		if not bool(r.get("ok", false)):
			last_error = str(r.get("reason", "net"))
			if last_error == "gap" and int(r.get("next", -1)) >= 0:
				gs.econ_up = int(r.get("next", -1))   # 服务器说它只有这么多 ⇒ 下一趟从那里补
			done.call({"ok": false, "reason": last_error})
			return
		if int(r.get("seq", -1)) != want or (gs.econ_log as Array).size() != want:
			last_error = "moved"           # 等种子的时候本机又记了别的(界面在等, 正常走不到)
			done.call({"ok": false, "reason": "moved"})
			return
		gs.econ_up = want                  # 之前那几条服务器已经有了
		row["seed"] = int(r.get("seed", 0))
		done.call(EL.do(gs, row)))
	if not sent:
		busy = false
		return {"ok": false, "reason": "net"}
	return {"pending": true}


## 本机按服务器那份流水对齐(S4b: 开局回 econ_mismatch / econ_invalid)。`at` ≥ 0 = 服务器判第 at 条不合法 ⇒ 先认它、把那条起作废
##   (econ_truncate), 再拉流水在本机重放(EconReplay.adopt)。`done.call(对齐了没有)` 恰好一次。
static func adopt_async(at: int, done: Callable) -> void:
	if not on() or busy or not SB.enabled():
		done.call(false)
		return
	busy = true
	if at < 0:
		_fetch_adopt(done)
		return
	var n = SB._spawn()
	if n == null:
		busy = false
		done.call(false)
		return
	n._get_once("/rest/v1/rpc/econ_truncate", "POST", JSON.stringify({"p_week": week(), "p_at": at}),
		func(_r: Dictionary) -> void: _fetch_adopt(done),
		func(res: Dictionary) -> Dictionary: return res)


static func _fetch_adopt(done: Callable) -> void:
	var n = SB._spawn()
	if n == null:
		busy = false
		done.call(false)
		return
	adopts += 1
	last_error = ""
	n._get_once("/rest/v1/econ_ops?select=seq,op&week=eq.%d&order=seq.asc&limit=50000" % week(), "GET", "",
		func(res: Dictionary) -> void:
			busy = false
			if not bool(res.get("ok", false)):
				done.call(false)
				return
			EconReplay.adopt(GameState, res.get("rows", []))
			GameState.save()
			done.call(true),
		func(res: Dictionary) -> Dictionary:
			return parse_rows(bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", ""))))


## 纯函数: 读 econ_ops 的回包([{seq, op}, …] 按序号)⇒ {ok, rows: [op 带上 seq]}; 序号不连续 / 看不懂 ⇒ ok false。
static func parse_rows(ok: bool, code: int, body: String) -> Dictionary:
	if not ok or code < 200 or code >= 300:
		return {"ok": false}
	var j = JSON.parse_string(body)
	if not (j is Array):
		return {"ok": false}
	var rows: Array = []
	for x in j:
		if not (x is Dictionary) or not ((x as Dictionary).get("op") is Dictionary) or int((x as Dictionary).get("seq", -1)) != rows.size():
			return {"ok": false}
		var op: Dictionary = ((x as Dictionary)["op"] as Dictionary).duplicate(true)
		op["seq"] = rows.size()
		rows.append(op)
	return {"ok": true, "rows": rows}


## 把还没传的流水传上去(开关关 / 正忙 / 没有要传的 ⇒ 不发)。返回是否发了。
static func pump() -> bool:
	var gs = GameState
	if not on() or busy:
		return false
	var ops: Array = pending_rows(gs)
	if ops.is_empty():
		return false
	var from := clampi(int(gs.econ_up), 0, (gs.econ_log as Array).size())
	busy = true
	var sent := _send(from, ops, "", func(r: Dictionary) -> void:
		busy = false
		if bool(r.get("ok", false)):
			last_error = ""
			gs.econ_up = clampi(int(r.get("next", from)), 0, (gs.econ_log as Array).size())
			return
		last_error = str(r.get("reason", "net"))
		if last_error == "gap" and int(r.get("next", -1)) >= 0:
			gs.econ_up = int(r.get("next", -1)))
	if not sent:
		busy = false
	return sent
