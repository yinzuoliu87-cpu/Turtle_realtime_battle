class_name PetLevelsNet
extends RefCounted
## pet_levels_net.gd —— 我拥有哪些龟、每只几级（按龟等级 R1 / 拥有 ∪ 限免，2026-11-09 · 主站对接工作线 C）。
## 方案书：docs/plans/20261107-龟战主站对接.md §4.3 / §4.9、20261107b-龟等级与经验.md §4.4 / §4.5。
##
## 服务端 RPC `pet_levels_me()`（迁移 20261109b）= `mainsite_me()` 那一份（A1 的 mainsite_status：{ok, linked, user_id, owned, fetched_at}，
##   同一个函数）+ levels: {pet_key: {lv, xp}}。owned = 主站 /player 的缓存（mainsite_pets）；没绑定 ⇒ linked:false、owned:[]。
##   一个 RPC 把「拥有」和「等级」一起带回来（少一次请求：Supabase 出站流量 #23）。owned 里不是 28 只之一的键这里丢掉。
## ★走 `FriendsNet.call_rpc`（supabase.gd 现成的 _spawn → _await_token → _http），supabase.gd 不改（它快到 3000 行）。
## ★问到了 ⇒ 写 GameState.pet_lv（28 只全表：拥有的按服务器等级，其余 1 级 —— 限免龟固定 1 级、不涨）。
##   问不到 ⇒ 什么都不动（选龟页照上次的显示）。服务器裁判开算时会按服务器等级表重新盖章，本机这份只管显示 / 本机对局。
## ★B 的 `MainsiteLink`（设置页 / 绑定后 `mainsite_me` / 网关 `/app/pets/refresh`）每记一次当前号的拥有就调 `adopt_owned`，
##   选龟页立刻按新的拥有过滤。下面这几样按号记：换号（GameState.account_id 变了）⇒ 清空，拥有先取 B 那份按号缓存的。

const _FN := preload("res://scripts/net/friends_net.gd")

static var owned: Array = []
static var linked := false
## pet_key → {lv, xp}（只有服务器有记录的龟）
static var levels: Dictionary = {}
static var fetched := false
## 上面这几样是哪个号的(初值 = 一个不可能是账号的串 ⇒ 第一次用时一定对一次号)
static var _acc := "<unset>"
static var _inflight := false
static var _asked_at := -1000000
## 【门禁 / 实拍注入点】非空 ⇒ `fetch` 不联网、直接按它 adopt（形状同 `parse` 的产物）。
static var override: Dictionary = {}

## 选龟页开着时多久再问一次（主站那边可能刚买了龟）
const REFRESH_SEC := 20


## 回包 → {"linked", "owned", "levels"}；回包不像（没有 owned / levels）⇒ {}。纯函数（门禁直接喂）。
static func parse(res: Dictionary) -> Dictionary:
	var d: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	if not bool(res.get("ok", false)) or not (d.get("owned") is Array):
		return {}
	var own: Array = []
	for p in (d["owned"] as Array):
		if (p is String) and WeeklyFree.ALL.has(p) and not own.has(p):
			own.append(p)
	var lv := {}
	var src = d.get("levels", {})
	if src is Dictionary:
		for k in (src as Dictionary):
			var e = (src as Dictionary)[k]
			if not (e is Dictionary):
				continue
			var l = (e as Dictionary).get("lv", 1)
			var x = (e as Dictionary).get("xp", 0)
			lv[str(k)] = {"lv": clampi(int(l) if (l is int or l is float) else 1, 1, TurtleLevel.MAX),
				"xp": maxi(0, int(x) if (x is int or x is float) else 0)}
	return {"linked": bool(d.get("linked", false)), "owned": own, "levels": lv}


## 采用一份（parse 的产物）：更新本机缓存 + GameState.pet_lv。
static func adopt(p: Dictionary) -> void:
	if p.is_empty():
		return
	_sync_acc()
	linked = bool(p.get("linked", false))
	owned = (p.get("owned", []) as Array).duplicate()
	levels = (p.get("levels", {}) as Dictionary).duplicate(true)
	fetched = true
	_write_table()


## 只换拥有（网关刷新主站拥有之后）。等级不动。
static func adopt_owned(own: Array) -> void:
	_sync_acc()
	var o: Array = []
	for p in own:
		if WeeklyFree.ALL.has(str(p)) and not o.has(str(p)):
			o.append(str(p))
	owned = o
	_write_table()


static func _write_table() -> void:
	var gs = _gs()
	if gs == null:
		return
	var flat := {}
	for k in levels:
		flat[k] = int((levels[k] as Dictionary).get("lv", 1))
	gs.pet_lv = TurtleLevel.full_table(owned, flat)


## 本机还没有等级表、而这一号要按拥有 ∪ 限免过滤 ⇒ 先按「全 1 级」(= 服务器眼里限免龟的等级), 问到了再换。
static func ensure_default() -> void:
	_sync_acc()
	var gs = _gs()
	if gs == null or not filter_on():
		return
	if (gs.pet_lv as Dictionary).is_empty():
		gs.pet_lv = TurtleLevel.full_table(owned, {})


## 去问一次（在途不叠；距上次不到 REFRESH_SEC 秒不再问）。`done` 问到了才调（无参，下一拍）。
static func fetch(done: Callable = Callable()) -> void:
	if not override.is_empty():
		adopt(override)
		if done.is_valid():
			done.call_deferred()
		return
	_sync_acc()
	if _inflight or not filter_on():
		return
	var now := Time.get_ticks_msec() / 1000
	if now - _asked_at < REFRESH_SEC:
		return
	_asked_at = now
	_inflight = true
	_FN.call_rpc("pet_levels_me", {}, func(res: Dictionary) -> void:
		_inflight = false
		var p := parse(res)
		if not p.is_empty():
			adopt(p)
			if done.is_valid():
				done.call_deferred())


## 这一号要不要按「拥有 ∪ 限免」过滤：登录了后端（有账号）且不在教学里。
##   没有后端（本机开发 / 门禁 TURTLE_SUPABASE=" "）⇒ 不过滤（不碰任何现有流程）；服务器裁判照样把关。
static func filter_on() -> bool:
	var gs = _gs()
	if gs == null or str(gs.get("account_id")) == "":
		return false
	var ml = Engine.get_main_loop()
	var td = (ml as SceneTree).root.get_node_or_null("/root/TutorialDirector") if ml is SceneTree else null
	if td != null and td.has_method("is_active") and bool(td.is_active()):
		return false
	return true


## 本周能上场的：拥有 ∪ 限免（`WeeklyFree.allowed_ids`，种子 = 我的账号 + 本周锚点）。
static func allowed_now() -> Array:
	_sync_acc()
	var gs = _gs()
	if gs == null:
		return WeeklyFree.ALL.duplicate()
	return WeeklyFree.allowed_ids(str(gs.get("account_id")), int(gs.get("week_anchor_ts")), owned)


## 选龟页角标：要过滤、且这只不是拥有的 ⇒ 它是限免龟。
static func is_free_pick(pid: String) -> bool:
	return filter_on() and not owned.has(pid) and allowed_now().has(pid)


## 陪练号 / 自动选龟：want 里能上场的按原顺序留下，不够 n 只再按 allowed 的顺序补。不过滤 ⇒ 原样。
static func fill_allowed(want: Array, n: int = 3) -> Array:
	if not filter_on():
		return want.duplicate()
	var ok := allowed_now()
	var out: Array = []
	for p in want:
		if ok.has(str(p)) and not out.has(str(p)) and out.size() < n:
			out.append(str(p))
	for p in ok:
		if out.size() < n and not out.has(str(p)):
			out.append(str(p))
	return out


## 换号了(删号 / 换号收尾 / 龟投账号登录)⇒ 上一个号的拥有 / 等级作废; 拥有先取 B 那份按号缓存的(上次 mainsite_me / pets/refresh)。
static func _sync_acc() -> void:
	var gs = _gs()
	var a := str(gs.get("account_id")) if gs != null else ""
	if a == _acc:
		return
	_acc = a
	linked = false
	levels = {}
	fetched = false
	_asked_at = -1000000
	var ML = load("res://scripts/net/mainsite_link.gd")
	owned = (ML.owned_ids() as Array).filter(func(k) -> bool: return WeeklyFree.ALL.has(str(k))) if ML != null else []


static func _gs():
	var ml = Engine.get_main_loop()
	return (ml as SceneTree).root.get_node_or_null("/root/GameState") if ml is SceneTree else null
