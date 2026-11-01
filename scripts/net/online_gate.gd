extends RefCounted
class_name OnlineGate
## 游戏必须联网 · 判据(2026-11-01 · 方案书 docs/plans/20261101b-游戏必须联网.md)。
##
## 用户 2026-11-01:「我们不应该有什么这种本地排名，我们这个游戏就一定要是要联网的，就是不可能说断网还可以匹配，
##   断网可以打，这是肯定不行的，不能有什么这种本地。」
## ⇒ 正式包里，凡是要服务器作数的事（匹配 / 对战 / 教程 / 切磋 / 排行榜 / 购买）都先过这一道：
##   连得上 ⇒ 照常往下走（同步，一帧都不等）；连不上 ⇒ 弹「无法连接服务器」框（`OnlineWall`），带「重试」「返回」，
##   重试连上了才接着做原来那一步。不给任何本地替代。
##
## ★开发缝只在开发构建里有（`required()` 为假的那几种）：门禁 / 开发机的 `TURTLE_SUPABASE=" "`、调试场、VFXLAB、
##   SIM 号都跑在调试构建上；离线测试包（导出特性 `offline_dev`，`supabase.gd` 整层停用）另算。
##   正式包（release 导出模板）`OS.is_debug_build()` 恒假 ⇒ 这些缝一个都走不到。
##   判据与 `phase2_config.time_travel_allowed()` 同一个口径（不认 `SHIP` / `DEVTOOLS`：
##   冒烟门禁 `SHIP=1` 要在后端关着时整局打通，那是开发机上跑的调试构建）。
## ★「连得上」= 这一道自己在 `FRESH_MS` 之内亲眼看到过服务状态 OK + 令牌新鲜（不是开机时问到过一次就算数）。
##   主菜单开着十分钟后断网，再点「开始战斗」也会先去问一次 —— 否则状态停在旧的 OK 上，等于没拦。
## 门禁：tests/verify_online_only.gd（模拟正式包 + 传输回「连不上」，逐个入口点下去）。

const SB := preload("res://scripts/net/supabase.gd")

## 需要联网的那件事（拼进框里那一句：「%s需要连接服务器。」）。
const WHAT_MATCH := "对战"
const WHAT_RANK := "排行榜"
const WHAT_BUY := "购买"
const WHAT_TUTORIAL := "新手教程"
const WHAT_SPAR := "切磋"

## 「亲眼看到 OK」之后多久内不再问（毫秒）。连着买几件东西不必每件都问一次。
const FRESH_MS := 20000

## 【门禁注入点】true ⇒ 按正式包判（门禁在调试构建里模拟正式包）。默认 false ⇒ 玩家路径一字不动。
## ⚠ static，活过场景切换 —— 用完必须还原。
static var release_override: bool = false

## 上一次亲眼看到「连得上」的时刻（`Time.get_ticks_msec()`）。-1 = 本进程还没看到过。
static var _ok_ms: int = -1
## 观测量（门禁分母）：拦下过几次 / 放行过几次。
static var blocked_count: int = 0
static var passed_count: int = 0


## 这个包是不是必须联网。★正式包恒真；调试构建 / 离线测试包为假（开发缝）。
static func required() -> bool:
	if release_override:
		return true
	return not (OS.is_debug_build() or SB.offline_dev())


## 开发缝（只在 `required()` 为假时）：本地快照池排行榜等开发用的本地那一路只许从这里放行。
static func dev_offline_ok() -> bool:
	return not required()


## 此刻算不算「连得上」：后端配了、服务状态 OK、令牌新鲜、不要求更新，而且是 `FRESH_MS` 之内亲眼看到的。
static func ready_now() -> bool:
	return verdict() == "ok" and _ok_ms >= 0 and Time.get_ticks_msec() - _ok_ms <= FRESH_MS


## 只看网络层现在的状态（不看新不新鲜）。返回：ok / off / unreachable / maintenance / update / session / token。
static func verdict() -> String:
	if not SB.enabled():
		return "off"
	var st: String = SB.service_state()
	if st == SB.ST_MAINTENANCE:
		return "maintenance"
	if st != SB.ST_OK:
		return "unreachable" if st == SB.ST_UNREACHABLE else "unknown"
	if SB.update_required():
		return "update"
	if SB.session_lost():
		return "session"
	if not SB.token_fresh(int(Time.get_unix_time_from_system())):
		return "token"
	return "ok"


## 记一笔「刚亲眼看到连得上」（`OnlineWall` 问到 OK 时调）。
static func note_ok() -> void:
	_ok_ms = Time.get_ticks_msec()


## 只给门禁：清掉「看到过」那一笔（模拟过了很久、要重新问）。
static func _reset_for_test() -> void:
	_ok_ms = -1
	blocked_count = 0
	passed_count = 0


## 要做一件需要联网的事之前调。
##   返回 true ⇒ 放行（调用方照常往下走，同步）；
##   返回 false ⇒ 已在 host 上弹「无法连接服务器」框（先去问一次服务器），调用方就地 return；
##     问到连得上 ⇒ 框自己关掉并调 `resume`（调用方把「原来那一步」交进来，通常就是它自己）；
##     「返回」⇒ 关框，调 `on_back`（没给就只关框）。
static func check(host: Node, what: String, resume: Callable, on_back: Callable = Callable()) -> bool:
	if not required() or ready_now():
		passed_count += 1
		return true
	blocked_count += 1
	OnlineWall.open(host, what, resume, on_back, true)
	return false
