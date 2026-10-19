extends RefCounted
## 服务器裁判 · 客户端网络层(2026-10-19 · 方案书 docs/plans/20261019-服务器裁判.md §3 ①②)。
##
## ★为什么单独一个文件: `supabase.gd` 贴着 3000 行上限(arch_budget), 新的网络代码不进它。
##   传输仍走它的唯一出口(`SupabaseNet._spawn()` → `_get_once` → `_http`): 时间穿越拦写 / 旧版本拦写 /
##   门禁注入 `_transport_for_test` / 等令牌 / 看门狗, 一样都不另写。
##
## 三条 RPC(服务端 `20261019_referee_jobs.sql` + `20261019b_referee_client_flags.sql`):
##   referee_flags()                     开关 {finals_on, gauntlet_on}(只读)
##   referee_submit_gauntlet(...)        周六点开战: 交阵容 + 对手快照 → 任务号 / 录像号(写)
##   referee_job_status(p_job_id)        查自己那一场算完没有(只读)
## 录像本体按录像号走老路(`SupabaseNet.fetch_match_async`, `matches` 表)。
##
## ★★开关的落盘副本 `GameState.referee_flags`: 断网冷启动也知道「上次问到时开着」⇒ 周六断网点开战照样拦住,
##   不会因为「问不到」就退回本地打出一场成绩(问题总表 B1)。从没问到过(全新安装 + 断网)⇒ 当作关(老路)。

const SB := preload("res://scripts/net/supabase.gd")

const K_FINALS := "finals_on"
const K_GAUNTLET := "gauntlet_on"

## 观测量(门禁分母): 本进程问过几次开关 / 交过几次阵容 / 查过几次任务。
static var flag_asks := 0
static var submits := 0
static var status_asks := 0


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


## 纯函数: `referee_flags` 回包 → {finals_on, gauntlet_on}; 问不到 ⇒ {}(保留上一次的)。
##   ★404 = 服务端没有这个函数(迁移没上)⇒ 明确是「关」, 不是「不知道」。
static func parse_flags(ok: bool, code: int, body: String) -> Dictionary:
	if not ok:
		return {}
	if code == 404:
		return {K_FINALS: false, K_GAUNTLET: false}
	if code < 200 or code >= 300:
		return {}
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Dictionary):
		return {}
	var d: Dictionary = j.data
	return {K_FINALS: bool(d.get(K_FINALS, false)), K_GAUNTLET: bool(d.get(K_GAUNTLET, false))}


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
	if nf == GameState.referee_flags:
		return
	GameState.referee_flags = nf
	GameState.save()


# ─────────────────────────────── 周六: 交阵容 ───────────────────────────────

## 纯函数: 请求体(键名 = 服务端形参)。
static func submit_body(week: int, snapshot: Dictionary, opponent: Dictionary, client_version: String) -> Dictionary:
	return {"p_week": week, "p_snapshot": snapshot, "p_opponent": opponent, "p_client_version": client_version}


## 纯函数: 交阵容的回包 → {"err": "" / 原因码, "job_id", "match_id", "gw", "gl"}。
##   原因码: offline(没发出去 / 没回来 / 被拦)· server · unavailable(404: 服务端没部署)·
##           服务端 reason 原样(off / update_required / wrong_week / closed / bad_snapshot / bad_opponent / finished / not_signed_in)。
static func parse_submit(ok: bool, code: int, body: String) -> Dictionary:
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
		return {"err": why if why != "" else "server", "gw": int(d.get("gw", -1)), "gl": int(d.get("gl", -1))}
	var jid = d.get("job_id", null)
	var mid := str(d.get("match_id", ""))
	if not (jid is int or jid is float) or int(jid) <= 0 or not SB.is_uuid(mid):
		return {"err": "server", "code": code}
	return {"err": "", "job_id": int(jid), "match_id": mid}


static func submit_gauntlet_async(week: int, snapshot: Dictionary, opponent: Dictionary, done: Callable) -> bool:
	if not SB.enabled():
		return false
	var n = SB._spawn()
	if n == null:
		return false
	submits += 1
	n._get_once("/rest/v1/rpc/referee_submit_gauntlet", "POST",
		JSON.stringify(submit_body(week, snapshot, opponent, ReplayRecorder.client_version())), done,
		func(res: Dictionary) -> Dictionary:
			return parse_submit(bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", ""))))
	return true


# ─────────────────────────────── 查任务 ───────────────────────────────

## 纯函数: `referee_job_status` 回包 → {"err": "", "status", "match_id", "won"(-1 不知道 / 0 / 1), "gw", "gl", "error"}。
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
		"error": str(d.get("error", "")) if d.get("error", null) is String else ""}


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
