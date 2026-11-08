extends Node
## mainsite_link.gd —— 龟投账号登录绑定(2026-11-08 · 方案书 docs/plans/20261107-龟战主站对接.md §4.1、
##   20261105c §4.1 / §2.10; 接口照主会话 11-08 定的契约 §1 / §2)。
##
## 流程: 设置页点「绑定」⇒ `start_link()` 调网关 `/app/link/start` 拿登录码与确认页地址 ⇒ 系统浏览器打开 ⇒
##   每 2 秒 `/app/link/poll`(5 分钟上限; App 切回前台立即查一次)⇒
##   · confirmed + switched:false ⇒ 绑到当前账号, 状态 = 已绑定
##   · confirmed + switched:true  ⇒ 这个龟投账号早绑在别的游戏账号上, 网关带回那个号的登录态;
##     先停在 ST_SWITCH_ASK 等玩家在弹窗里确认(本机旧号不合并), 确认后 `confirm_switch()` 换号
##   · expired ⇒ 登录码过期(服务端判, 或本机 5 分钟到点)
## ★换号收尾 = 「换设备」那段(supabase.gd `_store_session` + `pull_save_async`), 前面加两步:
##   先备份本机存档(`backup_save`)、再把本机回到全新安装的样子(`account_delete.wipe_local`)——
##   「本机旧号不合并」(20261105c §4.1): 不清的话, 目标号没有云存档时本机进度会原样挂到目标号名下。
## ★请求走 `supabase.gd` 的现成出口(节点 `_spawn` → `_await_token` → `_http`), 网关认 `Authorization: Bearer <令牌>`,
##   与 Supabase 请求同一组请求头; supabase.gd 一行不改。没配后端(门禁 `TURTLE_SUPABASE=" "`)⇒ 一个请求都不发。
## ★绑定状态按账号缓存在 `user://mainsite_link.json`(换号 / 删号后对不上账号 ⇒ 当作不知道, 重新问 `mainsite_me()`)。
## 守卫: tests/verify_mainsite_link.gd

const SB := preload("res://scripts/net/supabase.gd")
const _SE := preload("res://scripts/net/server_env.gd")
const _AD := preload("res://scripts/net/account_delete.gd")

## 网关地址(契约 §2)。内测服包(构建特性 beta_server)连内测那台; 开发进程可用环境变量指到本机假网关。
const GW_PROD := "https://arena.turtlearena.xyz"
const GW_BETA := "https://arena-beta.turtlearena.xyz"
const ENV_GW := "TURTLE_ARENA_GATEWAY"
const P_START := "/app/link/start"
const P_POLL := "/app/link/poll"
const P_PETS := "/app/pets/refresh"
const RPC_ME := "/rest/v1/rpc/mainsite_me"

const POLL_SEC := 2.0
## 等确认的上限(秒)。网关回的 expires_in 更短就用它的。
const CAP_SEC := 300
const CACHE_PATH := "user://mainsite_link.json"
## 登录码只许这种形状(契约 §2; 主站代码写死的同一条)。
const CODE_RE := "^[A-Za-z0-9_-]{4,64}$"
## 内部邮箱的后缀(主会话 11-08, A1 内测服实测): 服务器给匿名号签登录态(首次绑定 / 换号)时先补一个
##   `<账号ID>@link.turtlearena.xyz`(已确认), 号因此不再是匿名号 ⇒ 存档同步照常开(有意: 换设备登录同一个龟投账号进度能回来)。
##   ★它不是玩家自己绑的邮箱: 设置页不显示、不说「已绑定邮箱」, 换号确认框照「没绑邮箱」说(`user_email()`)。
const INTERNAL_MAIL := "@link.turtlearena.xyz"

## 状态
const ST_IDLE := "idle"
const ST_STARTING := "starting"        # /app/link/start 在路上
const ST_PENDING := "pending"          # 浏览器已打开, 轮询中
const ST_CONFIRMED := "confirmed"      # 绑定完成(含换号完成)
const ST_SWITCH_ASK := "switch_ask"    # 该龟投账号绑在别的号上, 等玩家确认换号
const ST_EXPIRED := "expired"          # 登录码过期
const ST_CANCELLED := "cancelled"      # 玩家取消 / 不换号
const ST_ERROR := "error"              # 开始登录失败(原因见 reason())

## 失败原因
const R_OFF := "off"          # 没配后端
const R_NET := "net"          # 连不上 / 5xx / 看不懂的回包
const R_AUTH := "auth"        # 登录失效 / 401 / 403
const R_BLOCKED := "blocked"  # 写请求被出口拦下(版本过旧 / 开发包时间穿越)
const R_BAD := "bad"          # 网关明确回 ok:false

## 观测量(门禁分母): 按路径数真交给 `_http` 的请求 / 打开过的地址 / 换号次数。
static var posts: Dictionary = {}
static var opened: Array = []
static var switches := 0

## 【门禁注入点】有效 ⇒ 打开地址时交给它, 不真开浏览器。默认无效 = 玩家路径。
static var open_url_sink: Callable = Callable()
## 【门禁注入点】非空 ⇒ 网关地址用它。
static var gateway_override := ""
## 【门禁注入点】> 0 ⇒ 「现在」用它(unix 秒), 量 5 分钟上限不用真等。
static var now_override := 0.0

static var _state: String = ST_IDLE
static var _reason: String = ""
static var _code: String = ""
static var _deadline: float = 0.0
static var _gen: int = 0
static var _poll_inflight := false
static var _me_inflight := false
static var _switch_acc: Dictionary = {}
static var _poller: Node = null
static var _cache: Dictionary = {}
static var _cache_loaded := false


# ─────────────────────────── 配置与纯判据 ───────────────────────────

static func gateway_base() -> String:
	if gateway_override != "":
		return gateway_override.rstrip("/")
	if SB.offline_dev():
		return ""
	if OS.is_debug_build() and OS.has_environment(ENV_GW):
		return OS.get_environment(ENV_GW).strip_edges().rstrip("/")
	return GW_BETA if _SE.is_beta() else GW_PROD


static func enabled() -> bool:
	return SB.enabled() and gateway_base() != ""


## 设备标识(契约 §3 `p_device`、§2 `device`; 主站拿它做同设备防小号)。网页版没有 ⇒ ""(= 不改)。
static func device_id() -> String:
	if OS.has_feature("web"):
		return ""
	return OS.get_unique_id().left(128)


## 这个邮箱是不是服务器补的内部邮箱(不是玩家自己绑的)。
static func is_internal_email(e: String) -> bool:
	return e.strip_edges().to_lower().ends_with(INTERNAL_MAIL)


## 当前账号**玩家自己绑的**邮箱(内部邮箱 ⇒ "")。界面上判「绑没绑邮箱」、显示邮箱一律取它。
static func user_email() -> String:
	var gs = SB._gs()
	var e := str(gs.account_email) if gs != null else ""
	return "" if is_internal_email(e) else e


static func _now() -> float:
	return now_override if now_override > 0.0 else Time.get_unix_time_from_system()


static func code_ok(code: String) -> bool:
	return RegEx.create_from_string(CODE_RE).search(code) != null


## 只开 https(开发进程另放行本机假网关的 http://127.0.0.1 / localhost)。地址里必须带着这次的登录码。
static func url_ok(url: String, code: String) -> bool:
	if not url.contains("code=" + code):
		return false
	if url.begins_with("https://"):
		return true
	return OS.is_debug_build() and (url.begins_with("http://127.0.0.1") or url.begins_with("http://localhost"))


## 纯判据: 一次网关 / RPC 回包 → {ok, reason, data}。2xx + JSON 对象才看正文; 网关的回包要 `ok:true`。
static func parse(res: Dictionary, need_ok: bool = true) -> Dictionary:
	if bool(res.get("blocked", false)):
		return {"ok": false, "reason": R_BLOCKED, "data": {}}
	var code := int(res.get("code", 0))
	if not bool(res.get("ok", false)) or code == 0:
		return {"ok": false, "reason": R_NET, "data": {}}
	if code == 401 or code == 403:
		return {"ok": false, "reason": R_AUTH, "data": {}}
	if code < 200 or code >= 300:
		return {"ok": false, "reason": R_NET, "data": {}}
	var j := JSON.new()
	if j.parse(str(res.get("body", ""))) != OK or not (j.data is Dictionary):
		return {"ok": false, "reason": R_NET, "data": {}}
	var d: Dictionary = j.data
	if need_ok and not bool(d.get("ok", false)):
		return {"ok": false, "reason": R_BAD, "data": d}
	return {"ok": true, "reason": "", "data": d}


## 纯函数: JWT 的载荷(不验签 —— 只用来知道「这是哪个号」, 令牌真不真由服务端每次请求时验)。
static func jwt_claims(tok: String) -> Dictionary:
	var parts := tok.split(".")
	if parts.size() != 3:
		return {}
	var p := parts[1].replace("-", "+").replace("_", "/")
	while p.length() % 4 != 0:
		p += "="
	var raw := Marshalls.base64_to_raw(p)
	if raw.is_empty():
		return {}
	var j := JSON.new()
	if j.parse(raw.get_string_from_utf8()) != OK or not (j.data is Dictionary):
		return {}
	return j.data


## 纯函数: 网关回的 session → `supabase._store_session` 要的那份账号信息(形状同 `account_from_auth_response`)。
##   网关只给 {access_token, refresh_token}(契约 §2) ⇒ 账号 / 邮箱 / 到期从令牌载荷取; 网关另给了 user / expires_at 就以它为准。
static func account_from_session(s) -> Dictionary:
	var bad := {"ok": false, "account_id": "", "token": "", "email": "", "refresh": "", "expires_at": 0}
	if not (s is Dictionary):
		return bad
	var sd: Dictionary = s
	var tok := str(sd.get("access_token", ""))
	var rt := str(sd.get("refresh_token", ""))
	if tok == "" or rt == "":
		return bad
	var c := jwt_claims(tok)
	var uid := str(c.get("sub", ""))
	var mail := str(c.get("email", ""))
	var exp := int(c.get("exp", 0))
	if sd.get("user") is Dictionary:
		var u: Dictionary = sd["user"]
		if str(u.get("id", "")) != "":
			uid = str(u["id"])
		mail = str(u.get("email", mail))
	if int(sd.get("expires_at", 0)) > 0:
		exp = int(sd["expires_at"])
	if not SB.is_uuid(uid):
		return bad
	## 到期不明 ⇒ 0: `_await_token` 当场拿 refresh_token 续一次, 不凭空假定它还能用多久。
	return {"ok": true, "account_id": uid, "token": tok, "email": mail, "refresh": rt, "expires_at": exp}


# ─────────────────────────── 状态 ───────────────────────────

static func state() -> String:
	return _state


static func reason() -> String:
	return _reason


static func code() -> String:
	return _code


static func me_inflight() -> bool:
	return _me_inflight


## 等确认的那个账号 id(只给弹窗 / 门禁读; 换号前本机身份一个字不动)。
static func switch_target() -> String:
	return str(_switch_acc.get("account_id", ""))


static func _go(st: String, why: String = "") -> void:
	_state = st
	_reason = why


static func _reset_for_test() -> void:
	_gen += 1
	_go(ST_IDLE)
	_code = ""
	_deadline = 0.0
	_poll_inflight = false
	_me_inflight = false
	_switch_acc = {}
	posts = {}
	opened = []
	switches = 0
	now_override = 0.0
	if _poller != null and is_instance_valid(_poller):
		_poller.queue_free()
	_poller = null
	_cache = {}
	_cache_loaded = true


## 删号 / 门禁: 本机的登录过程与缓存一起清掉(文件由 `account_delete.WIPE_FILES` 删)。
static func clear_local() -> void:
	_gen += 1
	_go(ST_IDLE)
	_code = ""
	_switch_acc = {}
	_poll_inflight = false
	_me_inflight = false
	_cache = {}
	_cache_loaded = true


# ─────────────────────────── 绑定状态缓存 ───────────────────────────

static func _acc() -> String:
	var gs = SB._gs()
	return str(gs.account_id) if gs != null else ""


static func _load_cache() -> void:
	if _cache_loaded:
		return
	_cache_loaded = true
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(CACHE_PATH)) == OK and j.data is Dictionary:
		_cache = j.data


static func _save_cache() -> void:
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_cache))
		f.close()


## 把一次查询结果记到账号 `acc` 名下。`owned` = null ⇒ 保留原来那份。
static func _note(acc: String, linked: bool, user_id = null, owned = null) -> void:
	if acc == "":
		return
	_load_cache()
	if str(_cache.get("acc", "")) != acc:
		_cache = {"acc": acc, "owned": []}
	_cache["linked"] = linked
	if user_id != null:
		_cache["user_id"] = str(user_id)
	if owned is Array:
		var ids: Array = []
		for k in owned:
			if str(k) != "" and not ids.has(str(k)):
				ids.append(str(k))
		_cache["owned"] = ids
	_cache["t"] = int(Time.get_unix_time_from_system())
	_save_cache()


## 当前账号绑没绑: 1 绑了 / 0 没绑 / -1 不知道(没问过, 或缓存是别的号的)。
static func linked_state() -> int:
	var acc := _acc()
	if acc == "":
		return 0
	_load_cache()
	if str(_cache.get("acc", "")) != acc or not _cache.has("linked"):
		return -1
	return 1 if bool(_cache["linked"]) else 0


## 当前账号拥有的龟(pet_key; 上次 `mainsite_me` / `refresh_pets` 的结果)。不知道 ⇒ []。
static func owned_ids() -> Array:
	_load_cache()
	if str(_cache.get("acc", "")) != _acc():
		return []
	return (_cache.get("owned", []) as Array).duplicate()


# ─────────────────────────── 网络 ───────────────────────────

## 调网关。`done(r)` 一定会被调一次(r 形状见 `parse`)。
static func _gw_post(path: String, body: Dictionary, done: Callable) -> void:
	if not enabled():
		done.call({"ok": false, "reason": R_OFF, "data": {}})
		return
	var n = SB._spawn()
	if n == null:
		done.call({"ok": false, "reason": R_NET, "data": {}})
		return
	_send(n, gateway_base() + path, path, JSON.stringify(body), true, done)


static func _send(n, url: String, tag: String, body: String, need_ok: bool, done: Callable) -> void:
	if not await n._await_token():
		n._bye()
		done.call({"ok": false, "reason": R_AUTH if SB.session_lost() else R_NET, "data": {}})
		return
	posts[tag] = int(posts.get(tag, 0)) + 1
	n._http("POST", url, body, func(res: Dictionary) -> void:
		var r := parse(res, need_ok)
		n._bye()
		done.call(r),
		"Content-Type: application/json")


## 问服务器「当前号绑没绑、有哪些龟」(`mainsite_me()`, 契约 §1)。设置页每次打开问一次。
static func refresh_me(done: Callable = Callable()) -> void:
	var cb := done if done.is_valid() else func(_r: Dictionary) -> void: pass
	if not SB.enabled() or _me_inflight:
		cb.call({"ok": false, "reason": R_OFF if not SB.enabled() else "busy", "data": {}})
		return
	var n = SB._spawn()
	if n == null:
		cb.call({"ok": false, "reason": R_NET, "data": {}})
		return
	_me_inflight = true
	var acc := _acc()
	var g := _gen
	_send(n, SB.base_url().rstrip("/") + RPC_ME, RPC_ME, "{}", false, func(r: Dictionary) -> void:
		_me_inflight = false
		if bool(r["ok"]) and g == _gen and acc == _acc():
			var d: Dictionary = r["data"]
			_note(acc, bool(d.get("linked", false)), d.get("user_id", ""), d.get("owned", []))
		cb.call(r))


## 刷新拥有的龟(网关调龟投 `/player`, 写服务器缓存; 契约 §2)。龟等级 / 限免那一线(C)也调它。
static func refresh_pets(done: Callable = Callable()) -> void:
	var cb := done if done.is_valid() else func(_r: Dictionary) -> void: pass
	var acc := _acc()
	var g := _gen
	_gw_post(P_PETS, {}, func(r: Dictionary) -> void:
		if bool(r["ok"]) and g == _gen and acc == _acc():
			var d: Dictionary = r["data"]
			_note(acc, bool(d.get("linked", false)), null, d.get("owned", []))
		cb.call(r))


# ─────────────────────────── 登录 ───────────────────────────

## 点「绑定」。已经在登录中 ⇒ 不重复开。
static func start_link() -> void:
	if _state == ST_STARTING or _state == ST_PENDING or _state == ST_SWITCH_ASK:
		return
	if not enabled():
		_go(ST_ERROR, R_OFF)
		return
	_gen += 1
	var g := _gen
	_code = ""
	_switch_acc = {}
	_go(ST_STARTING)
	_gw_post(P_START, {"device": device_id()}, func(r: Dictionary) -> void:
		if g != _gen:
			return                                  # 等回包的时候玩家已经取消了
		if not bool(r["ok"]):
			_go(ST_ERROR, str(r["reason"]))
			return
		var d: Dictionary = r["data"]
		var c := str(d.get("code", ""))
		var url := str(d.get("url", ""))
		if not code_ok(c) or not url_ok(url, c):
			_go(ST_ERROR, R_BAD)
			return
		var ttl := int(d.get("expires_in", CAP_SEC))
		_code = c
		_deadline = _now() + float(clampi(ttl if ttl > 0 else CAP_SEC, 1, CAP_SEC))
		_go(ST_PENDING)
		_open(url)
		_ensure_poller())


## 等确认时点「取消」: 停止轮询(登录码留给它自己过期)。
static func cancel_link() -> void:
	if _state != ST_STARTING and _state != ST_PENDING:
		return
	_gen += 1
	_code = ""
	_go(ST_CANCELLED)


static func _open(url: String) -> void:
	opened.append(url)
	if open_url_sink.is_valid():
		open_url_sink.call(url)
		return
	OS.shell_open(url)


## 查一次结果。轮询节拍、回前台、门禁都走这一个入口; 已经有一条在路上 ⇒ 不叠。
static func poll_now() -> void:
	if _state != ST_PENDING or _poll_inflight:
		return
	if _now() >= _deadline:
		_gen += 1
		_go(ST_EXPIRED)
		return
	_poll_inflight = true
	var g := _gen
	_gw_post(P_POLL, {"code": _code}, func(r: Dictionary) -> void:
		_poll_inflight = false
		if g != _gen or _state != ST_PENDING:
			return
		if bool(r["ok"]):
			apply_poll(r["data"])
		elif str(r["reason"]) == R_BAD:
			_gen += 1
			_go(ST_EXPIRED)                   # 网关明说这个码不行了(不认识 / 已用过)
		## 连不上 / 401 ⇒ 下一拍再查, 到点算过期
		)


## 一次轮询回包落地(抽出来让门禁不碰网络也能逐条喂)。返回落地后的状态。
static func apply_poll(d: Dictionary) -> String:
	match str(d.get("status", "")):
		"confirmed":
			_gen += 1
			if bool(d.get("switched", false)):
				var acc := account_from_session(d.get("session", null))
				if not bool(acc["ok"]):
					_go(ST_ERROR, R_BAD)
				else:
					_switch_acc = acc
					_go(ST_SWITCH_ASK)
			else:
				_note(_acc(), true)
				_go(ST_CONFIRMED)
				refresh_pets()
		"expired":
			_gen += 1
			_go(ST_EXPIRED)
		"cancelled", "canceled":
			_gen += 1
			_go(ST_CANCELLED)
		_:
			if _now() >= _deadline:
				_gen += 1
				_go(ST_EXPIRED)
	return _state


## 玩家在弹窗里点了「确认切换」。返回是否换了。
## ★顺序: 备份本机存档 → 本机回到全新安装(旧号不合并) → 落新号的登录态 → 拉新号的云存档(有才拉)。
static func confirm_switch() -> bool:
	if _state != ST_SWITCH_ASK or not bool(_switch_acc.get("ok", false)):
		return false
	var acc: Dictionary = _switch_acc
	_switch_acc = {}
	var gs = SB._gs()
	if gs != null:
		gs.backup_save("mainsite")
	_AD.wipe_local()
	if gs != null:
		gs.onboarded = true        # 这台设备上早就进过游戏: 换号不重走首次进入流程
	SB._store_session(acc)
	_note(str(acc["account_id"]), true)
	switches += 1
	SB.pull_save_async("recover")
	_go(ST_CONFIRMED)
	refresh_pets()
	return true


## 玩家在弹窗里点了「取消」: 本机一个字不动。
static func decline_switch() -> void:
	if _state != ST_SWITCH_ASK:
		return
	_switch_acc = {}
	_go(ST_CANCELLED)


# ─────────────────────────── 轮询节点(挂在 root, 换场景不断) ───────────────────────────

static func _ensure_poller() -> void:
	if _poller != null and is_instance_valid(_poller) and not _poller.is_queued_for_deletion():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var n = new()
	n.name = "MainsiteLinkPoller"
	_poller = n
	TreeJoin.join_deferred(n)


## 门禁读: 轮询节点在不在。
static func poller() -> Node:
	return _poller if _poller != null and is_instance_valid(_poller) else null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var t := Timer.new()
	t.wait_time = POLL_SEC
	t.autostart = true
	t.timeout.connect(_on_tick)
	add_child(t)


func _on_tick() -> void:
	if _state != ST_PENDING:
		if _poller == self:
			_poller = null
		queue_free()
		return
	poll_now()


## 从浏览器切回来: 立刻查一次, 不等下一拍。
## ★推迟到帧末: 引擎下发这几条通知时 root 正忙(TreeJoin 头注), 这里虽然也是推迟挂树, 一律推迟最省心。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		Callable(get_script(), &"poll_now").call_deferred()
