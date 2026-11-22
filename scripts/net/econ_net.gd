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
static var stale_rolls := 0  # 发现本机流水是上一周的、先换了周的次数(门禁量)
## ★「忙」卡死自愈(11-22 LouisT01 反馈「刷新不了啊」): 每一趟提交的回调都会解开 busy, 但回调要等请求节点进树、拿到令牌;
##   万一回调永远不来(节点没进树 / 令牌一直等不到), busy 一直是真 ⇒ 之后每次刷新 / 掷货都当场「正忙」失败, 直到重开 App。
##   超过 BUSY_STALE_MS(请求看门狗 15 秒 + 等令牌 15 秒 + 余量)还没解开 ⇒ 当它卡死: 解开、计数、报一条诊断。
const BUSY_STALE_MS := 35000
static var busy_since := 0
static var stale_resets := 0  # 卡死自愈了几次(门禁量)
static var _drift_reported := 0  # 已经报过的哨兵漂移次数(只报新增的)


static func on() -> bool:
	return GameState != null and RN.econ_on() and not EL.quiet(GameState)


## 开局前还要等吗: 有没传的流水 / 有提交在路上。开关关着恒 false。
static func unsynced() -> bool:
	return on() and (_busy_now() or int(GameState.econ_up) < (GameState.econ_log as Array).size())


## 上传被服务器拒了(本机与服务器两份账不一致, 传多少次都一样)⇒ 只能按服务器那份对齐。
static func conflict() -> bool:
	return last_error == "mismatch" or last_error == "taken"


## 本机这份流水属于哪一周(= GameState.week_anchor_ts, 周一 00:00 UTC; 还没有锚点 ⇒ 当前周)。
## ★2026-11-17 改: 原来取「现在」的周 ⇒ App 挂后台跨了周一 0 点(回前台不换周, 只有冷启动 / 打完一局才换),
##   上周没传完的流水被盖上本周的周号补传, 服务器重放整周判 bt:over、客户端「装备已同步」死循环(正式服 iPad 号, 339 条)。
##   现在周号跟着流水走; 上传 / 要种子 / 对齐之前先 `roll_if_stale()` 换周(清掉旧流水), 旧流水一条都不上传。
##   服务端 econ_commit 另有一道闸(迁移 20261117: bt 超过本周总场次 ⇒ mismatch)。
static func week() -> int:
	var w := int(GameState.week_anchor_ts) if GameState != null else 0
	return w if w > 0 else P2C.week_anchor_utc(int(P2C.now_utc()))


## 本机这份流水是上一周的(App 挂后台跨了周一 0 点)⇒ 先换周再说。换周 = 冷启动那一步 GameState.ensure_season()
##   (清空 econ_log / econ_up / 场次…); 判据用 GameState.is_season_expired(), 不另写一份。返回是否换了。
static func roll_if_stale() -> bool:
	var gs = GameState
	if gs == null or not gs.is_season_expired():
		return false
	stale_rolls += 1
	gs.ensure_season()
	return true


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


## 整数值的浮点还原成整数(递归)。存档 JSON 读回来整数都成了浮点(种子 583806406 → 583806406.0),
##   原样上传字面是「583806406.0」; 服务器那份是「583806406」⇒ 11-21 周六服务器字面比判 mismatch, 陪练号「装备已同步」死循环
##   (服务器已改按数比: 迁移 20261121_econ_seed_numeric; 这里在源头再堵一道)。
static func ints(v):
	if v is float and is_finite(v) and v == floorf(v) and absf(v) < 9.0e15:
		return int(v)
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(ints(x))
		return a
	if v is Dictionary:
		var d: Dictionary = {}
		for k in v:
			d[k] = ints(v[k])
		return d
	return v


static func _send(from: int, ops: Array, kind: String, done: Callable) -> bool:
	if not SB.enabled():
		return false
	var n = SB._spawn()
	if n == null:
		return false
	commits += 1
	var body := {"p_week": week(), "p_from": from, "p_ops": ints(ops), "p_kind": (kind if kind != "" else null)}
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
	if _busy_now():
		return {"ok": false, "reason": "busy"}
	roll_if_stale()                    # 上一周的流水不跟着这一趟传(换周后从本周空账起)
	## 先过一次哨兵: 它可能要补一条 prog(宝箱 / 香火终值)—— 那一条必须排在种子那一条前面、跟着这一趟一起传
	EL.check(gs, "seeded")
	var from := clampi(int(gs.econ_up), 0, (gs.econ_log as Array).size())
	var ops: Array = pending_rows(gs)
	var want := from + ops.size()
	if want != (gs.econ_log as Array).size():
		pump()                         # 积压超过一批: 先传一批, 这一下请玩家再点一次
		return {"ok": false, "reason": "backlog"}
	_take()
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
	if not on() or _busy_now() or not SB.enabled():
		done.call(false)
		return
	if roll_if_stale():
		at = -1                        # 换了周: 服务器说的「第 at 条」是上一周的账, 本周从头拉
	_take()
	if at < 0:
		_fetch_adopt(done)
		return
	var n = SB._spawn()
	if n == null:
		busy = false
		done.call(false)
		return
	## ★2026-11-17: 看截断结果再拉流水。原来不看 ⇒ 截断没生效(断网 / 5xx)也照拉, 把服务器判了不合法的那几条在本机重放
	##   (iPad 号背包冒出 4 件装备 + 6 深海币)。没生效 ⇒ 这次不对齐(done false = 「请连上服务器」), 下次开战再来;
	##   服务器回 not_invalid(账已经不是不合法的了, 比如另一台设备刚截过)⇒ 照常拉。
	n._get_once("/rest/v1/rpc/econ_truncate", "POST", JSON.stringify({"p_week": week(), "p_at": at}),
		func(r: Dictionary) -> void:
			if bool(r.get("ok", false)):
				_fetch_adopt(done)
				return
			busy = false
			last_error = str(r.get("reason", "net"))
			done.call(false),
		func(res: Dictionary) -> Dictionary:
			return parse_truncate(bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", ""))))


## 纯函数: econ_truncate 回包 → {ok, reason}。服务端 ok:true ⇒ 截了; ok:false + not_invalid ⇒ 账本来就没被判不合法, 也算可以拉;
##   别的(断网 / 5xx / 没登录 / 看不懂)⇒ 不行。
static func parse_truncate(ok: bool, code: int, body: String) -> Dictionary:
	if not ok or code < 200 or code >= 300:
		return {"ok": false, "reason": "net"}
	var j = JSON.parse_string(body)
	if not (j is Dictionary):
		return {"ok": false, "reason": "net"}
	var why := str((j as Dictionary).get("reason", ""))
	if bool((j as Dictionary).get("ok", false)) or why == "not_invalid":
		return {"ok": true, "reason": why}
	return {"ok": false, "reason": why if why != "" else "server"}


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
	_report_drift(gs)
	if not on() or _busy_now():
		return false
	if roll_if_stale():
		return false                   # 上一周的流水随换周清掉了, 一条都不传
	var ops: Array = pending_rows(gs)
	if ops.is_empty():
		return false
	var from := clampi(int(gs.econ_up), 0, (gs.econ_log as Array).size())
	_take()
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


static func _take() -> void:
	busy = true
	busy_since = Time.get_ticks_msec()


## busy 还算不算数: 卡了超过 BUSY_STALE_MS ⇒ 当它卡死, 解开并报一条诊断(见 BUSY_STALE_MS 头注)。
static func _busy_now() -> bool:
	if busy and Time.get_ticks_msec() - busy_since > BUSY_STALE_MS:
		busy = false
		stale_resets += 1
		last_error = "stale_busy"
		ErrorReporter.report("econ", "econ busy stuck %d ms" % (Time.get_ticks_msec() - busy_since),
			"commits=%d adopts=%d up=%d log=%d" % [commits, adopts, int(GameState.econ_up), (GameState.econ_log as Array).size()],
			"busy_stale")
	return busy


## 本机账本哨兵记到了流水之外的改动(econ_drift)⇒ 把那一条(哪个时刻、哪几块资产)报上来。
##   由来(11-22): 测试号 alex1997 服务器重放第 327 条「equip shell」判 full, 手机上却装上了 —— 两边账在更早就分岔了,
##   而漂移记录只存在手机存档里(GameState.econ_drift_note), 服务器这边看不到从哪一步开始。同一条记录每进程只报一次。
static func _report_drift(gs) -> void:
	if gs == null or int(gs.econ_drift) <= _drift_reported:
		return
	_drift_reported = int(gs.econ_drift)
	ErrorReporter.report("econ", "econ drift: " + str(gs.econ_drift_note),
		"drift=%d up=%d log=%d bt=%d" % [int(gs.econ_drift), int(gs.econ_up), (gs.econ_log as Array).size(), int(gs.season_total_battles)],
		"drift|" + str(gs.econ_drift_note))
