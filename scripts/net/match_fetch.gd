extends RefCounted
## 取录像的两条读(纯函数): 按 match_id 取 `matches` 那一行 / 周日按坐标取 `finals_replay()`。
## 2026-10-20 从 supabase.gd 原样挪出(那个文件贴着 arch_budget 3000 行上限), 只多了一项 `referee`。
##   发请求仍在 supabase.gd(`fetch_match` / `fetch_finals_replay_async`, 等令牌 + 看门狗 + 恰好一次)。
##
## ★`referee`(逐帧直播, 方案书 docs/plans/20261019-服务器逐帧直播.md §4.1 / §5): 这一场是不是**服务器裁判算的**。
##   判据只有一条: 服务端写回时 `matches.result` 里带 `referee: true`(`referee_complete`, schema.sql)。
##   客户端自己上传的那一行没有这个键 ⇒ false。周日 `finals_replay()` 由 20261020 迁移多回一个 `referee` 键;
##   服务端还是旧版(没有这个键)⇒ false, 调用方照旧按自己知道的(`known`)走。
##   用途: `stream_watch.route` 拿它当「已知裁判局」——裁判局永不本机重算。

const SB_PATH := "res://scripts/net/supabase.gd"   # 运行期才 load: supabase.gd preload 本文件, 反过来 preload 就成环


static func _uuid(s: String) -> bool:
	return load(SB_PATH).is_uuid(s)


## `matches.result`(jsonb)那一格 → 是不是服务器裁判局。
static func referee_of(result) -> bool:
	if not (result is Dictionary):
		return false
	var rf = (result as Dictionary).get("referee", false)
	return (rf is bool) and bool(rf)


## 纯函数: 取那一行要问的查询串。`replay`(录像本体)+ `result`(只为认出裁判局: `referee_of`)。
##   版本号在录像里, 解出来由 `ReplayRecorder.play` 统一比(只有一处判据, 不在列上再比一遍)。
static func match_fetch_query(match_id: String) -> String:
	if not _uuid(match_id):
		return ""
	return "match_id=eq.%s&select=match_id,replay,result" % match_id


## 纯函数: 一次取回的回包 → {"err": 原因码, "b64": 录像, "code": HTTP 码, "referee": 裁判局?}。
##   原因码: "" 取到了 / "offline" 请求没出去或没回来 / "server" 服务端非 2xx 或回了不是 JSON 数组 /
##          "missing" 没有这一行(到期被清了或从没传上来) / "corrupt" 有这一行但录像列是空的。
## ★每一种都要给玩家**不同的一句话**(见 replay_fetcher.gd 的 MSG) —— 归成一句「出错了」等于没说。
static func parse_fetched_match(ok: bool, code: int, body: String, match_id: String) -> Dictionary:
	if not ok:
		return {"err": "offline", "code": code}
	if code < 200 or code >= 300:
		return {"err": "server", "code": code}
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Array):
		return {"err": "server", "code": code}
	for r in (j.data as Array):
		if r is Dictionary and str((r as Dictionary).get("match_id", "")) == match_id:
			var b = (r as Dictionary).get("replay", null)
			if b is String and (b as String) != "":
				return {"err": "", "b64": b, "code": code, "referee": referee_of((r as Dictionary).get("result", null))}
			return {"err": "corrupt", "code": code}
	return {"err": "missing", "code": code}


## 纯函数: `finals_replay` 的请求体。键名与服务端对不上是这类接口最常见的死法, 门禁直接验它。
static func finals_replay_body(week: int, bucket: int, round_no: int, match_no: int) -> Dictionary:
	return {"p_week": week, "p_bucket": bucket, "p_round": round_no, "p_match": match_no}


## 纯函数: `finals_replay` 回包 → {"err": "", "b64", "match_id", "referee"} 或 {"err": 原因码}。
##   原因码: offline / server / unavailable(函数没部署: 404) / not_revealed / no_result / no_replay / no_bucket / corrupt。
static func parse_finals_replay(ok: bool, code: int, body: String) -> Dictionary:
	if not ok:
		return {"err": "offline", "code": code}
	if code == 404:
		return {"err": "unavailable", "code": code}
	if code < 200 or code >= 300:
		return {"err": "server", "code": code}
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Dictionary):
		return {"err": "server", "code": code}
	var d: Dictionary = j.data
	if not bool(d.get("ok", false)):
		var why := str(d.get("reason", "server"))
		return {"err": why if why != "" else "server", "code": code}
	var mid := str(d.get("match_id", ""))
	var b = d.get("replay", null)
	if not _uuid(mid) or not (b is String) or (b as String) == "":
		return {"err": "corrupt", "code": code}
	return {"err": "", "b64": b, "match_id": mid, "code": code, "referee": referee_of(d)}
