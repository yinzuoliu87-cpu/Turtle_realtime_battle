extends RefCounted
## finals_qualified.gd —— 本周晋级名单(2026-11-01 · 方案书 docs/plans/20261101e-决赛日文案与赛前页.md)。
## 用户 2026-11-01 看对阵图:「未晋级的玩家是看不到别人的分组吗？…作为玩家看到的东西是什么呢？」
##   18:00 分组之前, 没晋级的观众一个组都看不到(服务端 finals_week_view 此时 buckets = [])
##   ⇒ 赛前页要「本周晋级名单(人数 + 名字)」。
## 服务端 RPC `finals_qualified_list(p_week)`(迁移 20261101e): {ok, week, now, seated, n, list: [{name, tag, avatar, gw, gl, me}]}。
##   只下发名字 / 玩家 ID / 头像 / 闯关战绩, 不下发阵容。
## ★走 `FriendsNet.call_rpc`(supabase.gd 现成的 _spawn → _await_token → _http), supabase.gd 不改(它快到 3000 行)。
## ★服务端没部署(404) / 问不到 ⇒ 名单为空, 赛前页只留倒计时与赛程(不报错、不弹窗)。

const _FN := preload("res://scripts/net/friends_net.gd")

## 周锚点 → {"n": int, "list": [{name, tag, avatar, gw, gl, me}], "seated": bool}
static var _cache: Dictionary = {}
static var _inflight: Dictionary = {}
static var _asked_at: Dictionary = {}       # 周锚点 → 上次发请求的本机秒(Time.get_ticks_msec / 1000)
## 【门禁 / 实拍注入点】非空 ⇒ `cached()` 一律回它(不联网)。形状同 `_cache` 的值。
static var override: Dictionary = {}

## 名单在分组前会变(晋级的人陆续报到): 赛前页开着时每隔这么久再问一次。
const REFRESH_SEC := 60


static func cached(week: int) -> Dictionary:
	if not override.is_empty():
		return override
	return _cache.get(week, {}) as Dictionary


## 回包 → {"n", "list", "seated"}; 不是 {ok:true} ⇒ {}。纯函数(门禁直接喂)。
static func parse(res: Dictionary) -> Dictionary:
	if not bool(res.get("ok", false)):
		return {}
	var d: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	var out: Array = []
	for it in (d.get("list", []) if d.get("list", []) is Array else []):
		if not (it is Dictionary):
			continue
		out.append({"name": str(it.get("name", "")), "tag": str(it.get("tag", "")),
			"avatar": str(it.get("avatar", "")), "gw": int(it.get("gw", 0)), "gl": int(it.get("gl", 0)),
			"me": bool(it.get("me", false))})
	return {"n": maxi(int(d.get("n", out.size())), out.size()), "list": out, "seated": bool(d.get("seated", false))}


## 去问一次(同一周在途不叠; 距上次不到 REFRESH_SEC 秒不再问)。`done` 问到了才调(无参, 下一拍)。
static func fetch(week: int, done: Callable = Callable()) -> void:
	if not override.is_empty() or week <= 0 or bool(_inflight.get(week, false)):
		return
	var now := Time.get_ticks_msec() / 1000
	if _asked_at.has(week) and now - int(_asked_at[week]) < REFRESH_SEC:
		return
	_asked_at[week] = now
	_inflight[week] = true
	_FN.call_rpc("finals_qualified_list", {"p_week": week}, func(res: Dictionary) -> void:
		_inflight[week] = false
		var p := parse(res)
		## 问到了才回调(问不到 = 缓存不变, 屏不用重画); 延到下一拍 —— 断网时 call_rpc 当场回调, 别在调用方重画到一半时再重画
		if not p.is_empty():
			_cache[week] = p
			if done.is_valid():
				done.call_deferred())
