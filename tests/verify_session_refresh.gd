extends Node
## verify_session_refresh.gd — D-3c：登录态续期（2026-09-21 查实的 bug）
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## 原来 access_token 只活在内存里，`ensure_signed_in_async()` 见到已有 `account_id`
## 就直接返回 ⇒ **重开 App 之后再也没有 token** ⇒ 请求头退回 anon key ⇒
## 写 `ghosts` 被 401 RLS 拒（09-21 curl 实测）、读 `ghosts` 拿到空列表。
## ⇒ v0.19.420~423 的后端接线**只在装机后第一个小时里真正工作**。
##
## ★★为什么以前的门禁和探针全没抓到：它们全是「一个进程里从注册跑到底」，
##   **从没模拟过重启**。⑤ 就是补这一条的：进程里 token 是空的（= 刚开机），
##   存档里带着 `account_id` + `auth_refresh`，走真入口，量**真实发出去的请求头**。
##   反向验证：把 `ensure_signed_in_async` 改回「有 id 就返回」，⑤ 当场红。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★① `session_action` 纯函数逐条喂；★★**绑了邮箱的号穷举所有组合都拿不到 ACT_SIGNUP**
##   （那是静默换身份）。
## ★② 刷新回包三类：**只有服务端明确说死了才算死**，认不出来的一律当网络问题 ——
##   网络抖一下就把人登出，比多等一会儿糟糕得多。形状是 09-21 真打 Supabase 拿的：
##   乱码 refresh_token → 400 `refresh_token_not_found`。
## ★★④ 落地：网络失败 ⇒ 身份一个字不动；判死 ⇒ 匿名清号重建 / 绑定的保号等重登。
## ★⑥ 同一时刻只发一个刷新：refresh_token 会轮换，并发两个会让其中一个作废。

const SB := preload("res://scripts/net/supabase.gd")

const DEAD_URL := "http://127.0.0.1:9"

## 09-21 真发 `POST /auth/v1/token?grant_type=refresh_token` 拿回来的形状(令牌换成假值)
const REFRESH_OK := '{"access_token":"at-new","token_type":"bearer","expires_in":3600,"expires_at":%d,"refresh_token":"rt-new","user":{"id":"uid-R","aud":"authenticated","role":"authenticated","email":"","is_anonymous":true}}'
const REFRESH_DEAD := '{"code":400,"error_code":"refresh_token_not_found","msg":"Invalid Refresh Token: Refresh Token Not Found"}'

var _ok := 0
var _fail := 0
var _tree: SceneTree = null
var _bak := {}
const KEYS := ["account_id", "account_email", "auth_refresh", "install_uid", "season_id",
	"hearts", "ranked_used", "week_anchor_ts", "season_start_ts"]

var _reqs: Array = []
var _next := {}
var _hold := false
var _held: Array = []


func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])


func _spy(method, url, headers, body, cb) -> void:
	_reqs.append({"method": str(method), "url": str(url), "headers": headers, "body": str(body)})
	if _hold:
		_held.append(cb)
	else:
		cb.call(_next)


func _bearer(headers) -> String:
	for h in headers:
		var s := str(h)
		if s.begins_with("Authorization: Bearer "):
			return s.substr("Authorization: Bearer ".length())
	return ""


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _ready() -> void:
	_tree = get_tree()
	await get_tree().process_frame
	GameState.test_mode = true
	for k in KEYS:
		_bak[k] = GameState.get(k)
	print("=== D-3c 登录态续期 ===")
	_t_action()
	_t_kind()
	_t_parse()
	_t_apply()
	await _t_restart()
	await _t_inflight()
	_t_identity_line()
	SB._transport_for_test = Callable()
	OS.set_environment("TURTLE_SUPABASE", " ")
	SB._reset_auth_for_test()
	for k in KEYS:
		GameState.set(k, _bak[k])
	print("")
	print("  (共 %d 条断言)" % (_ok + _fail))
	print("ALL PASS — D-3c 登录续期" if _fail == 0 else "FAIL x%d" % _fail)
	if _tree != null:
		_tree.quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 该对会话做什么
# ─────────────────────────────────────────────────────────────
func _t_action() -> void:
	print("── ① 会话该做什么(纯函数) ──")
	var now := 1_800_000_000
	var far := now + 3000
	var near := now + 60
	_chk("① 从没登录过 → 注册", SB.session_action("", "", "", 0, "", now) == SB.ACT_SIGNUP)
	_chk("① token 还够用 → 什么都不做", SB.session_action("uid", "", "tok", far, "rt", now) == SB.ACT_NONE)
	_chk("① token 快过期了 → 续", SB.session_action("uid", "", "tok", near, "rt", now) == SB.ACT_REFRESH)
	_chk("① ★★刚开机(内存里没 token)但存档里有 refresh_token → 续(这就是原来那个 bug 的现场)",
		SB.session_action("uid", "", "", 0, "rt", now) == SB.ACT_REFRESH,
		SB.session_action("uid", "", "", 0, "rt", now))
	_chk("① 老用户(v0.19.420~423 没存过 refresh_token)·匿名 → 重新注册",
		SB.session_action("uid", "", "", 0, "", now) == SB.ACT_SIGNUP)
	_chk("① ★绑了邮箱但没有 refresh_token → 等玩家用邮箱重登(不许建新号)",
		SB.session_action("uid", "a@b.co", "", 0, "", now) == SB.ACT_LOST)

	## ★★穷举: 绑了邮箱的号, 不管 token / 过期 / refresh 怎么组合, 都拿不到 SIGNUP
	var n := 0
	var bad: Array = []
	for tok in ["", "tok"]:
		for exp in [0, near, far]:
			for rt in ["", "rt"]:
				n += 1
				var a: String = SB.session_action("uid", "a@b.co", tok, exp, rt, now)
				if a == SB.ACT_SIGNUP:
					bad.append("%s/%d/%s" % [tok, exp - now, rt])
	_chk("① ★分母: 穷举了 12 种组合", n == 12, str(n))
	_chk("① ★★绑了邮箱的号 12 种组合里一次都没拿到「注册新号」(那是静默换身份)",
		bad.is_empty(), str(bad))


# ─────────────────────────────────────────────────────────────
# ② 刷新回包三类
# ─────────────────────────────────────────────────────────────
func _t_kind() -> void:
	print("── ② 刷新回包三类(只有服务端明说死了才算死) ──")
	var good := REFRESH_OK % (_now() + 3600)
	_chk("② 200 + 真实形状 → 成功", SB.refresh_kind(true, 200, good) == SB.RK_OK)
	_chk("② ★400 refresh_token_not_found(实测) → 死",
		SB.refresh_kind(true, 400, REFRESH_DEAD) == SB.RK_DEAD)
	_chk("② 400 refresh_token_already_used → 死",
		SB.refresh_kind(true, 400, '{"error_code":"refresh_token_already_used"}') == SB.RK_DEAD)
	var nets := [
		["连不上", false, 0, ""],
		["500", true, 500, '{"message":"boom"}'],
		["限流 429", true, 429, '{"error_code":"over_request_rate_limit"}'],
		["网关吐 HTML", true, 502, "<html>502</html>"],
		["400 但是认不出的 error_code", true, 400, '{"error_code":"something_new"}'],
		["200 但解不出账号", true, 200, '{"access_token":"x"}'],
	]
	var wrong := 0
	for c in nets:
		var k: String = SB.refresh_kind(bool(c[1]), int(c[2]), str(c[3]))
		if k != SB.RK_NET:
			wrong += 1
		_chk("② %s → 当网络问题(下次再试)" % str(c[0]), k == SB.RK_NET, k)
	_chk("② ★★六种「说不准」没有一种被当成「死了」(当成死 = 网络一抖就把人登出)",
		wrong == 0, "误判 %d/6" % wrong)


# ─────────────────────────────────────────────────────────────
# ③ 注册/刷新回包里的 refresh_token 不再被扔掉
# ─────────────────────────────────────────────────────────────
func _t_parse() -> void:
	print("── ③ refresh_token 不再被扔掉 ──")
	var r: Dictionary = SB.account_from_auth_response(true, 200, REFRESH_OK % 1790000000)
	_chk("③ ★★回包里的 refresh_token 被取出来了(原来整个扔掉)", str(r.get("refresh", "")) == "rt-new",
		str(r.get("refresh", "")))
	_chk("③ expires_at 用服务端给的绝对时刻", int(r.get("expires_at", 0)) == 1790000000,
		str(r.get("expires_at", 0)))
	var r2: Dictionary = SB.account_from_auth_response(true, 200,
		'{"access_token":"a","expires_in":3600,"refresh_token":"r","user":{"id":"u"}}')
	var d := int(r2.get("expires_at", 0)) - _now()
	_chk("③ 老回包只有 expires_in 时按它推算(3600 秒左右)", d > 3500 and d <= 3600, str(d))


# ─────────────────────────────────────────────────────────────
# ④ ★★落地: 网络失败不动身份; 判死分匿名/绑定两条路
# ─────────────────────────────────────────────────────────────
func _t_apply() -> void:
	print("── ④ 落地(网络失败不动身份·判死分两条路) ──")
	# 网络失败
	SB._reset_auth_for_test()
	GameState.account_id = "uid-R"
	GameState.account_email = "a@b.co"
	GameState.auth_refresh = "rt-keep"
	var k1: String = SB.apply_refresh_response(false, 0, "")
	_chk("④ ★分母: 这次确实判成了网络问题", k1 == SB.RK_NET, k1)
	_chk("④ ★★网络失败 ⇒ account_id / 邮箱 / refresh_token 一个字都没动",
		str(GameState.account_id) == "uid-R" and str(GameState.account_email) == "a@b.co"
		and str(GameState.auth_refresh) == "rt-keep",
		"%s / %s / %s" % [GameState.account_id, GameState.account_email, GameState.auth_refresh])
	_chk("④ 网络失败不算登录失效", not SB.session_lost())

	# 判死 · 绑了邮箱
	var k2: String = SB.apply_refresh_response(true, 400, REFRESH_DEAD)
	_chk("④ ★分母: 这次确实判成了死", k2 == SB.RK_DEAD, k2)
	_chk("④ ★★绑了邮箱的号判死 ⇒ 账号【保留】(不许换号)", str(GameState.account_id) == "uid-R",
		GameState.account_id)
	_chk("④ ★★而且标成「登录已失效」, 等玩家用邮箱重登", SB.session_lost())
	_chk("④ 死掉的 refresh_token 被清掉(不然每拍都拿它去撞)", str(GameState.auth_refresh) == "",
		GameState.auth_refresh)

	# 判死 · 匿名
	SB._reset_auth_for_test()
	GameState.account_id = "uid-A"
	GameState.account_email = ""
	GameState.auth_refresh = "rt-dead"
	SB.apply_refresh_response(true, 400, REFRESH_DEAD)
	_chk("④ ★匿名号判死 ⇒ 清掉 account_id(下一拍重新匿名注册)", str(GameState.account_id) == "",
		GameState.account_id)
	_chk("④ 匿名号判死不标「失效」(没有邮箱可以重登, 标了也没用)", not SB.session_lost())

	# 成功 · 但回来的是另一个号
	SB._reset_auth_for_test()
	GameState.account_id = "uid-X"
	GameState.auth_refresh = "rt-x"
	var k3: String = SB.apply_refresh_response(true, 200, REFRESH_OK % (_now() + 3600))
	_chk("④ ★刷新回来的是【另一个号】⇒ 不接受, 当网络问题", k3 == SB.RK_NET, k3)
	_chk("④ ★而且身份一个字没动", str(GameState.account_id) == "uid-X"
		and str(GameState.auth_refresh) == "rt-x", GameState.account_id)


# ─────────────────────────────────────────────────────────────
# ⑤ ★★★模拟重启, 走真入口, 量真实发出去的请求
# ─────────────────────────────────────────────────────────────
func _t_restart() -> void:
	print("── ⑤ 模拟重启: 内存里没 token, 存档里有 refresh_token ──")
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	_chk("⑤ ★分母: 这一段里后端是启用的", SB.enabled(), SB.base_url())
	var anon := SB.anon_key()
	_chk("⑤ ★分母: anon key 不是空的(否则下面「不等于 anon key」是恒真式)", anon != "")

	## 「刚开机」: static 的 _token 是空的(= 新进程), 存档里带着身份与续期令牌
	SB._reset_auth_for_test()
	GameState.account_id = "uid-R"
	GameState.account_email = ""
	GameState.auth_refresh = "rt-old"
	_chk("⑤ ★分母: 现在内存里确实没有 token(= 刚开机)", SB.access_token() == "")

	_reqs.clear()
	_hold = false
	_next = {"ok": true, "code": 200, "body": REFRESH_OK % (_now() + 3600)}
	SB._transport_for_test = _spy
	SB.ensure_signed_in_async()
	await get_tree().process_frame

	_chk("⑤ ★分母: 真入口确实发出了请求", _reqs.size() >= 1, str(_reqs.size()))
	var r0: Dictionary = _reqs[0] if _reqs.size() > 0 else {}
	_chk("⑤ ★★开机后发的是【续登录】不是【注册新号】",
		str(r0.get("url", "")).ends_with("/auth/v1/token?grant_type=refresh_token"),
		str(r0.get("url", "")))
	_chk("⑤ 拿的是存档里那个 refresh_token", str(r0.get("body", "")).contains("rt-old"),
		str(r0.get("body", "")))
	_chk("⑤ ★★续上之后内存里有 token 了", SB.access_token() == "at-new", SB.access_token())
	_chk("⑤ ★★轮换后的新 refresh_token 写回了存档(不写回, 下次开机就拿作废的去刷)",
		str(GameState.auth_refresh) == "rt-new", GameState.auth_refresh)
	_chk("⑤ 还是同一个号", str(GameState.account_id) == "uid-R", GameState.account_id)

	## ★★★就是这一条能抓住原来那个 bug: 重启之后发一个需要登录的真请求, 看它带的是什么
	var row: Dictionary = SB.ghost_row_from_snapshot({"ghost_id": "g", "season_total_battles": 3},
		"uid-R", 1789948800, 3, "t")
	_next = {"ok": true, "code": 201, "body": ""}
	var before := _reqs.size()
	SB.upload_ghost_async(row)
	await get_tree().process_frame
	_chk("⑤ ★分母: 上传请求真的发出去了", _reqs.size() == before + 1,
		"%d → %d" % [before, _reqs.size()])
	var h = _reqs[_reqs.size() - 1].get("headers", []) if _reqs.size() > before else []
	var b := _bearer(h)
	_chk("⑤ ★★★重启后的上传请求带的是【登录拿到的 token】", b == "at-new", b.substr(0, 12))
	_chk("⑤ ★★★而【不是】anon key(原来就是这样被 401 拒的)", b != anon, b.substr(0, 12))
	SB._transport_for_test = Callable()


# ─────────────────────────────────────────────────────────────
# ⑥ 同一时刻只发一个刷新
# ─────────────────────────────────────────────────────────────
func _t_inflight() -> void:
	print("── ⑥ 同一时刻只发一个刷新(refresh_token 会轮换) ──")
	SB._reset_auth_for_test()
	GameState.account_id = "uid-R"
	GameState.auth_refresh = "rt-1"
	_reqs.clear()
	_held.clear()
	_hold = true
	SB._transport_for_test = _spy
	SB.ensure_signed_in_async()
	SB.ensure_signed_in_async()
	SB.ensure_signed_in_async()
	await get_tree().process_frame
	_chk("⑥ ★★连调三次, 只发出去一个(并发两个会让其中一个的令牌作废)", _reqs.size() == 1,
		str(_reqs.size()))
	## 放行那一个, 之后应当能再发
	for cb in _held:
		cb.call({"ok": false, "code": 0, "body": ""})
	_held.clear()
	_hold = false
	_next = {"ok": false, "code": 0, "body": ""}
	SB.ensure_signed_in_async()
	await get_tree().process_frame
	_chk("⑥ ★分母: 上一个回来之后能再发(不是永久卡死)", _reqs.size() == 2, str(_reqs.size()))
	SB._transport_for_test = Callable()


# ─────────────────────────────────────────────────────────────
# ⑦ refresh_token 走身份线: 清档保留, 切轮不动
# ─────────────────────────────────────────────────────────────
func _t_identity_line() -> void:
	print("── ⑦ refresh_token 走身份线 ──")
	GameState.account_id = "uid-R"
	GameState.auth_refresh = "rt-keep"
	GameState.ranked_used = 5
	GameState.start_new_season()
	_chk("⑦ ★分母: 切轮确实执行了(对照组 ranked_used 清零)", int(GameState.ranked_used) == 0)
	_chk("⑦ ★切大轮不动 refresh_token", str(GameState.auth_refresh) == "rt-keep",
		GameState.auth_refresh)
	GameState.hearts = 3
	GameState.reset_save()
	_chk("⑦ ★分母: 清档确实执行了(hearts 回 8)", int(GameState.hearts) == 8)
	_chk("⑦ ★★清档保留 refresh_token(清掉 = 这台设备的登录跟着没了)",
		str(GameState.auth_refresh) == "rt-keep", GameState.auth_refresh)
