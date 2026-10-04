extends RefCounted
## E7(母方案书 docs/plans/20260916-大轮赛制v2周赛制.md §8 E7, 用户 2026-09-17 拍板「本地持久化队列 + 退避重试」):
##   对手快照(积分赛 `ghosts` / 周六 `gauntlet_ghosts`)上传 —— 先**落盘排队**, 再发;
##   服务端**回读到逐字相同的那一份**才销单。门禁 `tests/verify_ghost_upload_retry.gd`。
##
## ══════════════════════════════════════════════════════════════════════
##  为什么必须排队(原来是发完就忘)
## ══════════════════════════════════════════════════════════════════════
##   U11 之后每份快照**不可再生**: 它是「第 N 场那一刻的阵容」, 下一场阵容就变了。
##   丢一份 = 那个场次的池子里**永久缺一个对手**(方案书 §10.35 C7 末段)。
##   而上传那一刻可能: 没网 / 令牌刚过期 / 下一秒 App 被杀。
##
## ★形状照抄回放 S2 的上传队列 `scripts/systems/replay/replay_uploader.gd`(已过门禁 V7 的那一套),
##   差别只有三条, 都是因为这里存的是**行本身**而不是一个本地文件的指针:
##   ① 单子里带整份快照 + 那一刻的周号/场次/战绩标签(E7 调研 #4「事件自带上下文」:
##      补传时场次早变了, 用上传时刻的场次会让快照落进**错误的桶**, 比丢了还糟)
##   ② 同主键的新单子**顶掉**旧单子(服务端也是 upsert 覆盖, 旧那份发上去也会被盖掉)
##   ③ 退避: 同一进程里失败一次就把下次最早尝试时刻往后推(指数 + 抖动, E7 调研 #2);
##      重开 App 时这张表是空的 ⇒ 冷启动第一次开主菜单一定会补一次。
##
##   一条单子 = {tbl, wk, b, gw, gl, snap, cv, acc, t, n}:
##     tbl  "ghosts" / "gauntlet_ghosts"
##     wk   那一场的 `week_anchor_ts`(= season_week)
##     b    积分赛总场次(ghosts 的主键维; 周六 = -1)
##     gw/gl 周六战绩标签(gauntlet_ghosts 的主键维; 积分赛 = -1)
##     snap 那一刻的快照(`Backend.build_ghost_snapshot` 产物)
##     cv   那一刻的客户端版本
##     acc  那一刻的账号("" = 那时还没登录过 ⇒ 发的时候用当前账号)
##     t    入队时刻(只用于日志)
##     n    服务端回过话、却没回读确认的次数(到 MAX_TRIES 就放弃)
##
## ══════════════════════════════════════════════════════════════════════
##  销单只有两种
## ══════════════════════════════════════════════════════════════════════
##   ① 服务端回读到这一行、且快照逐字相同(`SupabaseNet.snapshot_confirmed`)。2xx 不算。
##   ② **结构上永远发不出去**的(`drop_reason`): 过了那一周 / 周六快照过了新鲜窗(匹配层不会再挑它) /
##      换了账号 / 单子残缺 / 服务端明确说这一行本身不合法(4xx 里的那几种) / 回了话却 MAX_TRIES 次都对不上。
##   没网 / 没令牌 / 5xx / 401 ⇒ **留着**, 下次开主菜单(或下一次入队)再补。

const SB := preload("res://scripts/net/supabase.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")

const TBL_LADDER := "ghosts"
const TBL_GAUNTLET := "gauntlet_ghosts"
## 队列上限。积分赛一周最多 24 场 + 周六最多 6 场 = 30; 满了丢最旧的(E7 调研 #5)。
const QUEUE_MAX := 30
## 一周的长度。`season_week` 是周一 00:00 UTC; 过了下周一, 没有人会再按这一周去匹配。
const WEEK_SEC := 7 * 86400
## 服务端回过话、却连着这么多次回读不到同一份 ⇒ 放弃(没网 / 没令牌不计数)。
const MAX_TRIES := 8
## 退避: 第 k 次失败后至少等 BACKOFF_BASE × 2^(k-1) 秒(封顶 BACKOFF_CAP), 再乘 [0.5, 1.0) 的抖动。
const BACKOFF_BASE := 30.0
const BACKOFF_CAP := 1800.0
## 服务端明确拒「这一行本身」的状态码 ⇒ 再发多少次都一样(400 坏请求 / 404 表不在 / 413 太大 / 422 约束不过)。
##   401/403(令牌问题) / 408 / 429 / 5xx 不在里面 —— 那些下次可能就好了。
const PERMANENT_CODES := [400, 404, 413, 422]

## 正在路上的单子键(进程内)。同一条不并发发两次。
static var _inflight: Dictionary = {}
## 键 → 本进程里下一次最早能发的时刻(unix 秒)。不落盘: 冷启动一律先试一次。
static var _next_at: Dictionary = {}
## 键 → 本进程里连续失败几次(决定退避多长)。
static var _fails: Dictionary = {}
## 本进程回读确认过几条(观测量, 门禁分母用)。
static var confirmed_count := 0
## 退避抖动用的私有随机源 —— 不碰全局 RNG(全局那条是战斗确定性的纪律对象, tools/rng_discipline)。
static var _jitter := RandomNumberGenerator.new()


static func _now() -> int:
	return int(Time.get_unix_time_from_system())


static func _gs():
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node_or_null("/root/GameState") if ml != null and ml.root != null else null


# ─────────────────────────────── 入队(结算那一刻) ───────────────────────────────

## 积分赛那一份。`battles` = 快照里的 `season_total_battles`。
static func enqueue_ladder(snap: Dictionary, wk: int, battles: int, cv: String) -> bool:
	return _enqueue({"tbl": TBL_LADDER, "wk": wk, "b": battles, "gw": -1, "gl": -1, "snap": snap, "cv": cv})


## 周六那一份。`gw/gl` = 打完这一场之后的战绩标签。
static func enqueue_gauntlet(snap: Dictionary, wk: int, gw: int, gl: int, cv: String) -> bool:
	return _enqueue({"tbl": TBL_GAUNTLET, "wk": wk, "b": -1, "gw": gw, "gl": gl, "snap": snap, "cv": cv})


## 返回: 进队列了没有(没配后端 / 单子残缺 ⇒ false)。
## ★没配后端时**不排队**: 这一包根本没有服务器可传, 排了只会让存档背着一堆永远发不出去的快照。
static func _enqueue(e: Dictionary) -> bool:
	var gs = _gs()
	if gs == null or not SB.enabled():
		return false
	e["acc"] = str(gs.account_id)
	e["t"] = _now()
	e["n"] = 0
	if _malformed(e) != "":
		print("[GhostUp] 不排队(单子残缺): %s" % _malformed(e))
		return false
	var k := key_of(e)
	var q: Array = gs.ghost_upload_pending
	for i in range(q.size() - 1, -1, -1):
		if q[i] is Dictionary and key_of(q[i]) == k:
			q.remove_at(i)            # ②同主键: 新的顶掉旧的(服务端 upsert 也会这样盖)
	q.append(e)
	while q.size() > QUEUE_MAX:
		var gone = q.pop_front()
		print("[GhostUp] 上传队列满, 丢掉最旧的一条 %s" % (key_of(gone) if gone is Dictionary else "?"))
	_next_at.erase(k)
	_fails.erase(k)
	gs.save()                          # ★先落盘再发: 发的那一刻 App 被杀也不丢
	retry()
	return true


## 主键 = 表 + 账号 + 周 + 场次/标签。
static func key_of(e: Dictionary) -> String:
	return "%s|%s|%d|%d|%d|%d" % [str(e.get("tbl", "")), str(e.get("acc", "")), int(e.get("wk", 0)),
		int(e.get("b", -1)), int(e.get("gw", -1)), int(e.get("gl", -1))]


# ─────────────────────────────── 补传(主菜单每次打开 / 每次入队) ───────────────────────────────

## 过一遍队列: 结构上发不出去的销掉, 其余还没在路上、也不在退避期的各发一次。
static func retry() -> void:
	var gs = _gs()
	if gs == null:
		return
	var q: Array = gs.ghost_upload_pending
	if q.is_empty():
		return
	var now := _now()
	var acc := str(gs.account_id)
	var keep: Array = []
	var dropped := false
	for e in q:
		var why := drop_reason(e, now, acc)
		if why != "":
			print("[GhostUp] 上传单子销掉(发不出去): %s" % why)
			dropped = true
		else:
			keep.append(e)
	if dropped:
		gs.ghost_upload_pending = keep
		gs.save()
	if acc == "" or not SB.enabled():
		return               # 还没有账号 ⇒ 这次不发, 单子留着(主菜单那一句 ensure_signed_in 会去建)
	for e in keep:
		var k := key_of(e)
		if _inflight.has(k) or now < int(_next_at.get(k, 0)):
			continue
		var row := build_row(e, acc)
		if row.is_empty():
			continue
		## ★先标「在路上」再发(回放 S2 门禁 ⑦ 踩过): 令牌新鲜 + 回包同步时整条路在发的那一行返回之前就走完了。
		_inflight[k] = true
		var cb := func(confirmed: bool, code: int) -> void: _on_done(k, confirmed, code)
		var started: bool = SB.upload_ghost_async(row, cb) if str(e["tbl"]) == TBL_LADDER \
			else SB.upload_gauntlet_async(row, cb)
		if not started:
			_inflight.erase(k)


## "" = 这条还发得出去; 否则是销单原因(英文短码: 只进日志, 不是玩家文案)。纯判据。
static func drop_reason(e, now: int, acc: String) -> String:
	if not (e is Dictionary):
		return "not_dict"
	var d: Dictionary = e
	var bad := _malformed(d)
	if bad != "":
		return bad
	var k := key_of(d)
	if now >= int(d["wk"]) + WEEK_SEC:
		return "week_over:%s" % k
	## 周六快照只在上传后 FRESH_SNAPSHOT_SEC 内会被匹配层挑中(`Backend.gauntlet_pool_find` 按快照自带的 gl_ts 过滤)
	##   ⇒ 过了这个窗口补上去也没人打得到。
	if str(d["tbl"]) == TBL_GAUNTLET and now - int((d["snap"] as Dictionary).get("gl_ts", 0)) > int(P2.FRESH_SNAPSHOT_SEC):
		return "stale:%s" % k
	var a := str(d.get("acc", ""))
	if a != "" and acc != "" and a != acc:
		return "other_account:%s" % k
	if int(d.get("n", 0)) >= MAX_TRIES:
		return "gave_up:%s" % k
	return ""


static func _malformed(d: Dictionary) -> String:
	var tbl := str(d.get("tbl", ""))
	if tbl != TBL_LADDER and tbl != TBL_GAUNTLET:
		return "bad_tbl:%s" % tbl
	if int(d.get("wk", 0)) <= 0:
		return "no_week"
	if not (d.get("snap", null) is Dictionary) or (d["snap"] as Dictionary).is_empty():
		return "no_snapshot"
	if tbl == TBL_LADDER and int(d.get("b", -1)) < 0:
		return "no_battles"
	if tbl == TBL_GAUNTLET and (int(d.get("gw", -1)) < 0 or int(d.get("gl", -1)) < 0):
		return "no_record_tag"
	return ""


## 单子 + 当前账号 → 要 POST 的那一行(走 SupabaseNet 现成的两个纯函数, 不另拼一份)。
static func build_row(e: Dictionary, acc: String) -> Dictionary:
	var a := str(e.get("acc", ""))
	var who := a if a != "" else acc
	if str(e.get("tbl", "")) == TBL_LADDER:
		return SB.ghost_row_from_snapshot(e["snap"], who, int(e["wk"]), int(e["b"]), str(e.get("cv", "")))
	return SB.gauntlet_row_from_snapshot(e["snap"], who, int(e["wk"]), int(e["gw"]), int(e["gl"]), str(e.get("cv", "")))


## 回调: 只有回读确认了才销单; 否则记一次失败、推后下次尝试。
static func _on_done(k: String, confirmed: bool, code: int) -> void:
	_inflight.erase(k)
	var gs = _gs()
	if gs == null:
		return
	var q: Array = gs.ghost_upload_pending
	var idx := -1
	for i in range(q.size()):
		if q[i] is Dictionary and key_of(q[i]) == k:
			idx = i
			break
	if confirmed:
		confirmed_count += 1
		_next_at.erase(k)
		_fails.erase(k)
		if idx >= 0:
			q.remove_at(idx)
			gs.save()
		return
	## 测试时间里被出口拦下(`SupabaseNet._http`) = 根本没发: 单子留着, 也不记失败/不退避 ——
	##   否则在假时间里多开几次主菜单, 回到真实时间后要白等最长 30 分钟才补发。
	if code == SB.BLOCKED_CODE:
		return
	var f := int(_fails.get(k, 0)) + 1
	_fails[k] = f
	var wait := minf(BACKOFF_CAP, BACKOFF_BASE * pow(2.0, f - 1)) * _jitter.randf_range(0.5, 1.0)
	_next_at[k] = _now() + int(wait)
	if idx < 0 or code <= 0:
		return               # 没发出去 / 没令牌: 不算服务端的账
	var e: Dictionary = q[idx]
	if code in PERMANENT_CODES:
		print("[GhostUp] 服务端拒了这一行本身(code=%d), 销单: %s" % [code, k])
		q.remove_at(idx)
	else:
		e["n"] = int(e.get("n", 0)) + 1
	gs.save()


## 只给门禁: 「重开 App」= 进程内状态清空。
static func _reset_for_test() -> void:
	_inflight.clear()
	_next_at.clear()
	_fails.clear()
	confirmed_count = 0
