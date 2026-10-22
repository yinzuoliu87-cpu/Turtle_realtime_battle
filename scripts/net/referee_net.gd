extends RefCounted
## 服务器裁判 · 客户端网络层(2026-10-19 · 方案书 docs/plans/20261019-服务器裁判.md §3 ①②)。
##
## ★为什么单独一个文件: `supabase.gd` 贴着 3000 行上限(arch_budget), 新的网络代码不进它。
##   传输仍走它的唯一出口(`SupabaseNet._spawn()` → `_get_once` → `_http`): 时间穿越拦写 / 旧版本拦写 /
##   门禁注入 `_transport_for_test` / 等令牌 / 看门狗, 一样都不另写。
##
## 三条 RPC(服务端 `20261019_referee_jobs.sql` + `20261019b_referee_client_flags.sql`):
##   referee_flags()                     开关 {finals_on, gauntlet_on}(只读); 20261019c 起多两个: stream_on / stream_version(逐帧直播 S5)
##   referee_gauntlet_start(...)         周六点开战: 交阵容 + 第几场 → 任务号 / 录像号 / 对手卡片(写; 对手与种子服务端定, 20261020c)
##   referee_job_status(p_job_id)        查自己那一场算完没有(只读; 20261020c 起多回 coins = 这一局的战斗内铸币)
##   referee_finals_coins(...)           周日查我在这一场的战斗内铸币(只读; 20261020d, 翻面之前回 pending)
## 逐帧直播(20261020 迁移, 只写文件、未上生产; 没上 = 404 ⇒ 两条都当没有):
##   referee_live_gauntlet()             本周周六正在算的裁判局(赛况板「观赛」, 只读): match_id / 双方名字 / 开始时刻 / 种子 / 版本
##   referee_request_restream(p_match_id) 开流之前算的裁判局请求补流(排一份「重放录流」任务; 写)
## 录像本体按录像号走老路(`SupabaseNet.fetch_match_async`, `matches` 表)。
##
## ★★开关的落盘副本 `GameState.referee_flags`: 断网冷启动也知道「上次问到时开着」⇒ 周六断网点开战照样拦住,
##   不会因为「问不到」就退回本地打出一场成绩(问题总表 B1)。从没问到过(全新安装 + 断网)⇒ 当作关(老路)。

const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

const K_FINALS := "finals_on"
const K_GAUNTLET := "gauntlet_on"
## 逐帧直播 S5(docs/plans/20261019-服务器逐帧直播.md §4 接线 / §5 录像): 开 ⇒ 看服务器算的局一律播状态流(手机一步 sim 都不跑);
##   关 / 问不到 / 服务端还没上 20261019c(回包里没有这两个键)⇒ 现行行为(录像本机重算), 一字不变。
##   `stream_version` = 裁判机从哪个客户端版本起才录流(""= 不限)。本机版本低于它 ⇒ 当作关(那一版服务器没录, 拉不到)。
const K_STREAM := "stream_on"
const K_STREAM_VER := "stream_version"

## 观测量(门禁分母): 本进程问过几次开关 / 交过几次阵容 / 查过几次任务。
static var flag_asks := 0
static var submits := 0
static var status_asks := 0
static var live_asks := 0
static var restream_asks := 0
static var coins_asks := 0


# ─────────────────────────────── 开关 ───────────────────────────────

## 当前认定的开关(存档里最后一次问到的那份)。没配后端 ⇒ 一律关(离线开发包没有服务器可交)。
static func flags() -> Dictionary:
	if not SB.enabled() or GameState == null:
		return {}
	var f = GameState.get("referee_flags")
	return f if f is Dictionary else {}


static func finals_on() -> bool:
	return bool(flags().get(K_FINALS, false))


static func gauntlet_on() -> bool:
	return bool(flags().get(K_GAUNTLET, false))


## 看服务器算的局要不要走状态流(开关开 且 本机版本 ≥ stream_version)。
static func stream_on() -> bool:
	var f := flags()
	if not bool(f.get(K_STREAM, false)):
		return false
	var v := str(f.get(K_STREAM_VER, ""))
	return v == "" or not VersionGate.version_less(str(ProjectSettings.get_setting("application/config/version", "")), v)


## 纯函数: `referee_flags` 回包 → {finals_on, gauntlet_on}; 问不到 ⇒ {}(保留上一次的)。
##   ★404 = 服务端没有这个函数(迁移没上)⇒ 明确是「关」, 不是「不知道」。
static func parse_flags(ok: bool, code: int, body: String) -> Dictionary:
	if not ok:
		return {}
	if code == 404:
		return {K_FINALS: false, K_GAUNTLET: false, K_STREAM: false, K_STREAM_VER: ""}
	if code < 200 or code >= 300:
		return {}
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Dictionary):
		return {}
	var d: Dictionary = j.data
	## stream_* 缺(服务端还是 20261019b 那一版)⇒ 关
	var sv = d.get(K_STREAM_VER, "")
	return {K_FINALS: bool(d.get(K_FINALS, false)), K_GAUNTLET: bool(d.get(K_GAUNTLET, false)),
		K_STREAM: bool(d.get(K_STREAM, false)) if d.get(K_STREAM, false) is bool else false,
		K_STREAM_VER: str(sv) if sv is String else ""}


## 问一次开关, 问到就写进存档(变了才存)。`done.call(flags)` 恰好一次({} = 没问到)。返回 false = 没发(没配后端)。
static func refresh_flags_async(done: Callable = Callable()) -> bool:
	if not SB.enabled():
		return false
	var n = SB._spawn()
	if n == null:
		return false
	flag_asks += 1
	n._get_once("/rest/v1/rpc/referee_flags", "POST", "{}",
		func(res: Dictionary) -> void:
			note_flags(res)
			if done.is_valid():
				done.call(res),
		func(res: Dictionary) -> Dictionary:
			return parse_flags(bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", ""))))
	return true


## 把问到的开关记进存档(空 = 没问到, 不动)。
static func note_flags(f: Dictionary) -> void:
	if GameState == null or not f.has(K_FINALS):
		return
	var nf := {K_FINALS: bool(f[K_FINALS]), K_GAUNTLET: bool(f.get(K_GAUNTLET, false))}
	## 只改周日 / 周六其中一个的调用方(周六服务端回 off)不带 stream_* ⇒ 沿用存档里那份, 别把直播开关顺手关掉
	var old: Dictionary = GameState.referee_flags if GameState.referee_flags is Dictionary else {}
	nf[K_STREAM] = bool(f.get(K_STREAM, old.get(K_STREAM, false)))
	nf[K_STREAM_VER] = str(f.get(K_STREAM_VER, old.get(K_STREAM_VER, "")))
	if nf == GameState.referee_flags:
		return
	GameState.referee_flags = nf
	GameState.save()


# ─────────────────────────────── 周六: 开战(服务器挑对手) ───────────────────────────────
## ★2026-10-20(方案书 docs/plans/20261019-服务器裁判.md 决策记录「10-20 用户授权自定：周六对手改服务器挑」):
##   客户端只交「我的阵容 + 我要打第 N 场」; 对手(同标签真人 → 机器人)、种子都由服务端 `referee_gauntlet_start` 定,
##   客户端**没有任何参数位**能指定对手或种子。回包里带对手卡片(名字 / 头像 / 号 / 三统领), 真人与机器人同一形状。
##   旧的交阵容接口(客户端连对手快照一起交, 20261019 那一版)在服务端开了 `gauntlet_server_pick` 之后一律回 update_required。

## 纯函数: 请求体(键名 = 服务端形参)。`match_no` = 我认为这是本周第几场闯关(0 起 = gw + gl), 服务端拿它对账本防重交。
static func start_body(week: int, snapshot: Dictionary, match_no: int, client_version: String, rules_ver: int) -> Dictionary:
	return {"p_week": week, "p_snapshot": snapshot, "p_match_no": match_no,
		"p_client_version": client_version, "p_rules_ver": rules_ver}


## 纯函数: 对手卡片(服务端回的 `opp`)⇒ 匹配屏 `_opponent_from_ghost` 吃的形状 {profile{name, avatar, id, tag}, leaders}。
##   只留这几个键(服务端也只回这几个); 形状不对 ⇒ {}。
static func card_of(opp) -> Dictionary:
	if not (opp is Dictionary):
		return {}
	var o: Dictionary = opp
	var pf: Dictionary = {}
	if o.get("profile") is Dictionary:
		for k in ["name", "avatar", "id", "tag"]:
			var v = (o["profile"] as Dictionary).get(k, null)
			if v is String:
				pf[k] = v
	var ldr: Array = []
	if o.get("leaders") is Array:
		for x in (o["leaders"] as Array):
			if x is String and ldr.size() < 3:
				ldr.append(x)
	if ldr.is_empty():
		return {}
	return {"profile": pf, "leaders": ldr}


## 纯函数: 开战的回包 → {"err": "" / 原因码, "job_id", "match_id", "opp"(卡片), "gw", "gl"}。
##   原因码: offline(没发出去 / 没回来 / 被拦)· server · unavailable(404: 服务端没部署)·
##           服务端 reason 原样(off / update_required / wrong_week / closed / bad_snapshot / finished / stale / no_opponent / not_signed_in)。
##   ★stale = 我报的第 N 场与服务端账本对不上(本机战绩落后), 回包带账本上的 gw / gl。
static func parse_start(ok: bool, code: int, body: String) -> Dictionary:
	if not ok:
		return {"err": "offline"}
	if code == 404:
		return {"err": "unavailable"}
	if code < 200 or code >= 300:
		return {"err": "server", "code": code}
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Dictionary):
		return {"err": "server", "code": code}
	var d: Dictionary = j.data
	var gw := int(d.get("gw", -1)) if (d.get("gw", null) is float or d.get("gw", null) is int) else -1
	var gl := int(d.get("gl", -1)) if (d.get("gl", null) is float or d.get("gl", null) is int) else -1
	if not bool(d.get("ok", false)):
		var why := str(d.get("reason", "server"))
		return {"err": why if why != "" else "server", "gw": gw, "gl": gl}
	var jid = d.get("job_id", null)
	var mid := str(d.get("match_id", ""))
	var card := card_of(d.get("opp", null))
	if not (jid is int or jid is float) or int(jid) <= 0 or not SB.is_uuid(mid) or card.is_empty():
		return {"err": "server", "code": code}
	return {"err": "", "job_id": int(jid), "match_id": mid, "opp": card, "gw": gw, "gl": gl}


static func start_gauntlet_async(week: int, snapshot: Dictionary, match_no: int, done: Callable) -> bool:
	if not SB.enabled():
		return false
	var n = SB._spawn()
	if n == null:
		return false
	submits += 1
	n._get_once("/rest/v1/rpc/referee_gauntlet_start", "POST",
		JSON.stringify(start_body(week, snapshot, match_no, ReplayRecorder.client_version(), int(P2C.RULES_VER))), done,
		func(res: Dictionary) -> Dictionary:
			return parse_start(bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", ""))))
	return true


# ─────────────────────────────── 查任务 ───────────────────────────────

## 纯函数: `referee_job_status` 回包 → {"err": "", "status", "match_id", "won"(-1 不知道 / 0 / 1), "gw", "gl", "coins", "error"}。
##   `coins` = 服务器算的这一局里我方(左)的战斗内铸币(奇械 / 齿轮); 缺 / 不是非负整数(服务端还没上 20261020c)⇒ 0。
##   `chest` = 这一局结束时我方宝箱龟的进度(20261022b; 见 parse_chest), 没有 ⇒ {}。
##   原因码同上; 服务端 reason(no_job / not_signed_in)原样。
static func parse_status(ok: bool, code: int, body: String) -> Dictionary:
	if not ok:
		return {"err": "offline"}
	if code == 404:
		return {"err": "unavailable"}
	if code < 200 or code >= 300:
		return {"err": "server", "code": code}
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Dictionary):
		return {"err": "server", "code": code}
	var d: Dictionary = j.data
	if not bool(d.get("ok", false)):
		var why := str(d.get("reason", "server"))
		return {"err": why if why != "" else "server"}
	var w = d.get("won", null)
	return {"err": "", "status": str(d.get("status", "")), "match_id": str(d.get("match_id", "")),
		"won": (1 if bool(w) else 0) if w is bool else -1,
		"gw": int(d.get("gw", -1)) if d.get("gw", null) is float or d.get("gw", null) is int else -1,
		"gl": int(d.get("gl", -1)) if d.get("gl", null) is float or d.get("gl", null) is int else -1,
		"coins": maxi(0, int(d.get("coins", 0))) if d.get("coins", null) is float or d.get("coins", null) is int else 0,
		"chest": parse_chest(d.get("chest", null)),
		"error": str(d.get("error", "")) if d.get("error", null) is String else ""}


## 纯函数: 回包里的 `chest`(20261022b 起: 这一局结束时我方宝箱龟的进度)→ {"value": 财宝值, "won": [战利品 id]};
##   缺 / 形状不对(不是对象 · value 不是非负数 · won 不是字符串列表 · 超过 CHEST_MAX_OPEN 件)⇒ {}(当没有, 不动存档)。
static func parse_chest(v) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var val = (v as Dictionary).get("value", null)
	var won = (v as Dictionary).get("won", null)
	if not (val is float or val is int) or float(val) < 0.0 or not (won is Array):
		return {}
	if (won as Array).size() > ChestSystem.CHEST_MAX_OPEN:
		return {}
	var ids: Array = []
	for w in (won as Array):
		if not (w is String) or str(w) == "":
			return {}
		ids.append(str(w))
	return {"value": float(val), "won": ids}


static func job_status_async(job_id: int, done: Callable) -> bool:
	if not SB.enabled() or job_id <= 0:
		return false
	var n = SB._spawn()
	if n == null:
		return false
	status_asks += 1
	n._get_once("/rest/v1/rpc/referee_job_status", "POST", JSON.stringify({"p_job_id": job_id}), done,
		func(res: Dictionary) -> Dictionary:
			return parse_status(bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", ""))))
	return true


# ─────────────────────────────── 逐帧直播: 正在算的裁判局 / 补流 ───────────────────────────────

## 纯函数: `referee_live_gauntlet` 回包 → {"rows": [...]}(形状同赛况板的直播行 `live_board_query`: match_id / started_at /
##   updated_at / client_version / lp / rp, 另有 referee = true 与 seed); 拿不到 ⇒ {"reason": unavailable(404 没部署) / offline / server}。
##   ★服务端只回双方 profile 的名字 / 头像 / #ID, 不回快照(阵容 / 装备)。
static func parse_live(ok: bool, code: int, body: String) -> Dictionary:
	if not ok:
		return {"reason": "offline"}
	if code == 404:
		return {"reason": "unavailable"}
	if code < 200 or code >= 300:
		return {"reason": "server"}
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Array):
		return {"reason": "server"}
	var rows: Array = []
	for r0 in (j.data as Array):
		if not (r0 is Dictionary) or not SB.is_uuid(str((r0 as Dictionary).get("match_id", ""))):
			continue
		var r: Dictionary = (r0 as Dictionary).duplicate(true)
		var sd = r.get("seed", null)
		if not (sd is float or sd is int) or int(sd) <= 0:
			continue
		r["seed"] = int(sd)
		r["referee"] = true
		rows.append(r)
	return {"rows": rows}


static func live_gauntlet_async(done: Callable) -> bool:
	if not SB.enabled():
		return false
	var n = SB._spawn()
	if n == null:
		return false
	live_asks += 1
	n._get_once("/rest/v1/rpc/referee_live_gauntlet", "POST", "{}", done,
		func(res: Dictionary) -> Dictionary:
			return parse_live(bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", ""))))
	return true


## 纯函数: `referee_request_restream` 回包 → {"err": "", "status": pending / claimed / done / failed} 或 {"err": 原因码}。
##   原因码: offline · server · unavailable(404: 服务端没部署)· 服务端 reason 原样(not_signed_in / no_match / not_referee /
##           no_job / no_version / busy)。
static func parse_restream(ok: bool, code: int, body: String) -> Dictionary:
	if not ok:
		return {"err": "offline"}
	if code == 404:
		return {"err": "unavailable"}
	if code < 200 or code >= 300:
		return {"err": "server"}
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Dictionary):
		return {"err": "server"}
	var d: Dictionary = j.data
	if not bool(d.get("ok", false)):
		var why := str(d.get("reason", "server"))
		return {"err": why if why != "" else "server"}
	return {"err": "", "status": str(d.get("status", ""))}


static func request_restream_async(match_id: String, done: Callable) -> bool:
	if not SB.enabled() or not SB.is_uuid(match_id):
		return false
	var n = SB._spawn()
	if n == null:
		return false
	restream_asks += 1
	n._get_once("/rest/v1/rpc/referee_request_restream", "POST", JSON.stringify({"p_match_id": match_id}), done,
		func(res: Dictionary) -> Dictionary:
			return parse_restream(bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", ""))))
	return true


# ─────────────────────────────── 周日: 我在这一场的战斗内铸币 ───────────────────────────────
## ★2026-10-20(服务端 `20261020d_finals_coins.sql`): 周日服务器算的局, 裁判结果单带两侧各自的铸币(coins / coins_b),
##   服务端按 auth.uid() 认我是哪一侧、翻面之前不回数。客户端只报「哪一场」, 不报侧、不报数。

## 纯函数: 请求体(键名 = 服务端形参)。
static func finals_coins_body(week: int, bucket: int, r: int, m: int) -> Dictionary:
	return {"p_week": week, "p_bucket": bucket, "p_round": r, "p_match": m}


## 纯函数: `referee_finals_coins` 回包 → {"err": "", "status": pending / done, "coins"} 或 {"err": 原因码}。
##   原因码: offline · server · unavailable(404: 服务端没上 20261020d)· 服务端 reason 原样(not_signed_in / no_bucket / not_in_match)。
##   `coins` 缺 / 不是非负整数 ⇒ 0。
static func parse_finals_coins(ok: bool, code: int, body: String) -> Dictionary:
	if not ok:
		return {"err": "offline"}
	if code == 404:
		return {"err": "unavailable"}
	if code < 200 or code >= 300:
		return {"err": "server", "code": code}
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Dictionary):
		return {"err": "server", "code": code}
	var d: Dictionary = j.data
	if not bool(d.get("ok", false)):
		var why := str(d.get("reason", "server"))
		return {"err": why if why != "" else "server"}
	var st := str(d.get("status", ""))
	if st != "pending" and st != "done":
		return {"err": "server", "code": code}
	var c = d.get("coins", null)
	return {"err": "", "status": st, "coins": maxi(0, int(c)) if (c is float or c is int) else 0,
		"chest": parse_chest(d.get("chest", null))}


static func finals_coins_async(week: int, bucket: int, r: int, m: int, done: Callable) -> bool:
	if not SB.enabled():
		return false
	var n = SB._spawn()
	if n == null:
		return false
	coins_asks += 1
	n._get_once("/rest/v1/rpc/referee_finals_coins", "POST", JSON.stringify(finals_coins_body(week, bucket, r, m)), done,
		func(res: Dictionary) -> Dictionary:
			return parse_finals_coins(bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", ""))))
	return true
