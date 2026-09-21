extends Node
## SupabaseNet — Supabase 后端接入层（D 阶段，2026-09-20）
##
## ══════════════════════════════════════════════════════════════════════
##  这一层解决什么
## ══════════════════════════════════════════════════════════════════════
## `remote_pool.gd` 现在只有**两态**：配了地址 / 没配地址。连不上就静默回落到本地池。
## 平时这是对的（网络层第一原则：永远不能把游戏搞坏），但**周一维护期是错的** ——
## 方案书 U7/§4.7 拍板「版本维护期放在周一休赛，停服 → 发版本 → 开服」，
## 而玩家那边只会看到「连不上」，以为游戏坏了。
## ⇒ 本层给出**三态**，把「没配后端」和「后端主动停服」**分开**。
##
## ★为什么另起一个文件而不是改 `remote_pool.gd`：
##   那一层走的是**旧后端协议**（`POST /ghost`、`GET /ghosts?bracket=`），
##   与 Supabase REST 不是一回事。两套协议塞进一个文件，只会让「现在到底在跟谁说话」说不清。
##   等 D-4 把对手池也搬过来之后，旧层整个退役 —— 那时删掉它比现在改它干净。
##
## ★配置与停用（与 `remote_pool` 同一套口径，那套是验证过的）：
##   `ProjectSettings["turtle/supabase_url"]` + `["turtle/supabase_anon_key"]`，
##   环境变量 `TURTLE_SUPABASE` 覆盖 URL。**空白串 = 整层停用**。
##   ⚠ 门禁进程一律 `TURTLE_SUPABASE=" "`（见 `run-tests.sh`）—— 否则 300 个测试会真的打网络。
##
## ★publishable key 是**公开值**：它设计上就要嵌进客户端，安全边界不在"藏住它"而在
##   服务端的 RLS（`server/supabase/schema.sql` 逐表开了，并且实测过冒充写入返回 403）。

const SETTING_URL := "turtle/supabase_url"
const SETTING_KEY := "turtle/supabase_anon_key"
const ENV_URL := "TURTLE_SUPABASE"

const TIMEOUT_SEC := 6.0

# ─────────────────────────────────────────────────────────────
# 三态（其实是五个取值 —— 把"还没问到"和"问不到"分开是有原因的，见下）
# ─────────────────────────────────────────────────────────────
## 没配后端。**这是有意关掉**（当前就是这个状态），玩家侧什么都不该显示。
const ST_OFF := "off"
## 配了，但这个进程还没问到过。**不等于出问题** —— 刚开机时就是它。
const ST_UNKNOWN := "unknown"
## 服务端在，且没在维护。
const ST_OK := "ok"
## ★服务端在，且**主动**说自己在维护。这一态存在的全部意义就是能跟下面那态分开。
const ST_MAINTENANCE := "maintenance"
## 配了地址但问不到（超时 / 5xx / DNS 挂）。与 MAINTENANCE 的区别：
## 一个是"我们知道，正在弄"，一个是"不知道怎么了"——给玩家看的话完全不同。
const ST_UNREACHABLE := "unreachable"

static var _state: String = ST_UNKNOWN
static var _notice: String = ""
static var _asked: int = 0        # ★分母: 问过几次(0 = 压根没发过, 别把它当成"问到了 OK")


static func base_url() -> String:
	if OS.has_environment(ENV_URL):
		return OS.get_environment(ENV_URL).strip_edges()
	return str(ProjectSettings.get_setting(SETTING_URL, "")).strip_edges()


static func anon_key() -> String:
	return str(ProjectSettings.get_setting(SETTING_KEY, "")).strip_edges()


## 本层是否启用。★URL **与** key 都要有 —— 只有 URL 没有 key 的话每条请求都会被
##   Supabase 以「No API key found」拒掉，那种"配了一半"比没配更难查。
static func enabled() -> bool:
	return base_url() != "" and anon_key() != ""


## 当前服务状态。没配后端时**永远返回 ST_OFF**，不暴露内部的 `_state`。
static func service_state() -> String:
	if not enabled():
		return ST_OFF
	return _state


## 维护公告文本（只有 ST_MAINTENANCE 时才有意义）。
static func notice_text() -> String:
	return _notice


## ★分母用: 本进程问过几次服务状态。门禁靠它区分「问到了」与「压根没问」。
static func ask_count() -> int:
	return _asked


# ═════════════════════════════════════════════════════════════
# D-3 账号: 匿名起步 + 补绑邮箱
# ═════════════════════════════════════════════════════════════
## ★★为什么必须有服务端账号, 而不是继续用 `GameState.install_uid`:
##   `install_uid` 是**这台机器**不是**这个人** —— 换设备即丢档, 而且它从不离开本机,
##   服务端没法拿它认人。D3 拍板的「匿名起步 + 补绑邮箱」要的是一个服务端身份。
##   ⇒ `install_uid` 保留, 但只当「首次匿名登录的本地凭据」, **不做主键**。
##
## ★★`account_id` 会进 `ghosts` 的主键 `(account_id, season_week, battles)`。
##   少了「谁」这一维, 两个人会在服务端**静默互相覆盖** ——
##   memory `fb-id-without-owner-dimension` 记的就是这个形状(A6/U11 补的是「第几场」)。

## 本进程的访问令牌(内存态, 不落盘)。★不存盘是有意的:
##   它有有效期, 存下来的多半是过期的, 而"拿着一个过期 token 以为自己登录着"
##   比每次重新匿名登录更难查。account_id 才是要持久化的东西(存在 GameState)。
static var _token: String = ""
static var _auth_tries: int = 0


static func access_token() -> String:
	return _token


## ★分母用: 本进程试过几次登录。0 = 压根没发过, 别把它读成"登录失败"。
static func auth_try_count() -> int:
	return _auth_tries


static func _reset_auth_for_test() -> void:
	_token = ""
	_auth_tries = 0


## 纯函数: 一次 `/auth/v1/signup` 的回包 → 账号信息。**这才是要被逐条验的东西**。
## 返回 {"ok": bool, "account_id": String, "token": String, "is_anonymous": bool, "email": String}。
##
## ★失败一律返回 `ok=false` 且 `account_id=""` —— **不许编一个本地 id 顶上**。
##   那样会让「没登录成功」看起来像「登录成功了」, 而后果要等到上传快照
##   在服务端被 RLS 拒掉时才显形(那时已经隔了好几层)。
static func account_from_auth_response(ok: bool, code: int, body: String) -> Dictionary:
	var bad := {"ok": false, "account_id": "", "token": "", "is_anonymous": false, "email": ""}
	if not ok or code < 200 or code >= 300:
		return bad
	## ★同 `state_from_response`: 用 `JSON.new().parse()` 而不是 `JSON.parse_string()`,
	##   后者遇到非 JSON 会往日志喷 ERROR, 而"网关返回一坨 HTML"是预期内的分支。
	var j := JSON.new()
	if j.parse(body) != OK:
		return bad
	var d = j.data
	if not (d is Dictionary):
		return bad
	var dd: Dictionary = d
	var user = dd.get("user", null)
	if not (user is Dictionary):
		return bad
	var uid := str((user as Dictionary).get("id", ""))
	if uid == "":
		return bad
	return {
		"ok": true,
		"account_id": uid,
		"token": str(dd.get("access_token", "")),
		"is_anonymous": bool((user as Dictionary).get("is_anonymous", false)),
		"email": str((user as Dictionary).get("email", "")),
	}


## 把一次登录回包应用到全局 + 存档。返回是否成功。
static func apply_auth_response(ok: bool, code: int, body: String) -> bool:
	var r := account_from_auth_response(ok, code, body)
	_auth_tries += 1
	if not bool(r["ok"]):
		return false
	_token = str(r["token"])
	var gs = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/GameState") if Engine.get_main_loop() != null else null
	if gs != null:
		gs.account_id = str(r["account_id"])
		gs.account_email = str(r["email"])
		gs.save()
	return true


## 需要的话去匿名登录一次。**已经有 account_id 就什么都不做** ——
## 每次开游戏都新建一个匿名账号的话, 服务端会被刷出一堆一次性账号(Supabase 自己也警告过这点)。
static func ensure_signed_in_async() -> void:
	if not enabled():
		return
	var gs = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/GameState") if Engine.get_main_loop() != null else null
	if gs != null and str(gs.account_id) != "":
		return                                  # 已有身份, 不重复建号
	var n = _spawn()
	if n != null:
		n.sign_in_anonymous()


# ═════════════════════════════════════════════════════════════
# D-4a 上传: 每场都传一份阵容快照到 `ghosts`
# ═════════════════════════════════════════════════════════════
## ★★主键 `(account_id, season_week, battles)` —— 三维缺一不可:
##   · `account_id` 「谁」 —— 少了它两个人在服务端**静默互相覆盖**
##     (memory `fb-id-without-owner-dimension`)
##   · `season_week` 「哪一周」—— 周锚点, 与客户端 `_P2.week_anchor_utc()` 同一口径
##   · `battles` 「第几场」—— D5 拍板的匹配硬条件是**双方总场次相同**
##   同键再传 = **覆盖**(upsert), 所以「每场都传」不会把池子撑爆: 一个人一周最多 N 行(N=他打的场数)。
##
## ★上传失败**什么都不做**: 不重试、不回滚、不碰存档、不弹窗。
##   网络层第一原则 —— 永远不能把游戏搞坏。本地池那步在这之前**已经**做完且一定成功。
static var _uploads_ok: int = 0
static var _uploads_try: int = 0


static func upload_ok_count() -> int:
	return _uploads_ok


static func upload_try_count() -> int:
	return _uploads_try


static func _reset_upload_for_test() -> void:
	_uploads_ok = 0
	_uploads_try = 0


## 纯函数: 阵容快照 + 身份 → 要写进 `ghosts` 的那一行。**这才是要被逐条验的东西**。
## 返回 {} 表示**不该传**(缺身份 / 缺场次), 调用方据此跳过 —— 不许凑一行残的上去。
static func ghost_row_from_snapshot(snapshot: Dictionary, account_id: String,
		season_week: int, battles: int, client_version: String) -> Dictionary:
	## ★三条缺一不可的前提, 缺了就**不传**而不是填个默认值:
	##   填 0 / 填空串会在服务端造出一行"看起来是合法数据"的垃圾, 而且会把别人的行覆盖掉
	##   (主键撞上 `("", 0, 0)`)。宁可这一场不传。
	if account_id == "" or season_week <= 0 or battles < 0:
		return {}
	if snapshot == null or snapshot.is_empty():
		return {}
	return {
		"account_id": account_id,
		"season_week": season_week,
		"battles": battles,
		"snapshot": snapshot,
		"season_wins": int(snapshot.get("season_wins", 0)),
		"hearts": int(snapshot.get("hearts", 8)),
		"season_sweeps": int(snapshot.get("season_sweeps", 0)),
		"client_version": client_version,
	}


## 把一次上传回包记账。返回是否成功。
static func apply_upload_response(ok: bool, code: int) -> bool:
	_uploads_try += 1
	var good: bool = ok and code >= 200 and code < 300
	if good:
		_uploads_ok += 1
		## ★升的是 `RemotePool` 那面旗 —— 结算屏的消费方只有一个, 别再搞一面自己的。
		var RP = load("res://scripts/net/remote_pool.gd")
		if RP != null:
			RP.mark_upload_ok()
	return good


## 发一份快照。**发完就忘**; 没配后端 / 没身份 / 缺场次 = 什么都不做(连节点都不建)。
static func upload_ghost_async(row: Dictionary) -> void:
	if not enabled() or row.is_empty():
		return
	var n = _spawn()
	if n != null:
		n.upload_ghost(row)


func upload_ghost(row: Dictionary) -> void:
	if not enabled() or row.is_empty():
		_bye()
		return
	## ★`Prefer: resolution=merge-duplicates` = upsert。同键(同一个人·同一周·同一场次)
	##   再传就覆盖 —— D5「每场都传」靠的就是这个, 否则第二次传会撞主键报 409。
	var url := base_url().rstrip("/") + "/rest/v1/ghosts"
	_http("POST", url, JSON.stringify(row),
		func(res):
			apply_upload_response(bool(res.get("ok", false)), int(res.get("code", 0)))
			_bye(),
		"Prefer: resolution=merge-duplicates,return=minimal")


func sign_in_anonymous() -> void:
	if not enabled():
		_bye()
		return
	var url := base_url().rstrip("/") + "/auth/v1/signup"
	_http("POST", url, "{}", func(res):
		apply_auth_response(
			bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", "")))
		_bye())


## 只给门禁用: 把状态清回初始。★产品代码不许调 —— 状态应当只由 `apply_status_response` 改。
static func _reset_for_test() -> void:
	_state = ST_UNKNOWN
	_notice = ""
	_asked = 0


# ─────────────────────────────────────────────────────────────
# 纯函数: 一次 /service_status 的回包 → 三态。**这才是本层真正要被验的东西**
#   —— 它不碰网络, 所以门禁能把每一条分支都喂到。
# ─────────────────────────────────────────────────────────────
## `ok` = 传输层成功, `code` = HTTP 状态码, `body` = 响应体。
## 返回 {"state": String, "notice": String}。
static func state_from_response(ok: bool, code: int, body: String) -> Dictionary:
	## 传输失败或非 2xx ⇒ 问不到。★**不要回落成 ST_OK** ——
	##   把"不知道"说成"正常"正是静默失败的源头。
	if not ok or code < 200 or code >= 300:
		return {"state": ST_UNREACHABLE, "notice": ""}
	## ★用 `JSON.new().parse()` 而不是 `JSON.parse_string()`:
	##   后者在内容不是 JSON 时会往日志里喷 `ERROR: Parse JSON failed`,
	##   而"网关返回了一坨 HTML"是**预期之内**的分支(门禁里就喂了这一种)。
	##   预期内的分支不该留下长得像故障的日志 —— 下一个人会照着它去查一个不存在的问题。
	var j := JSON.new()
	if j.parse(body) != OK:
		return {"state": ST_UNREACHABLE, "notice": ""}
	var parsed = j.data
	## PostgREST 取行返回的是**数组**。空数组 = 表里没那一行 ⇒ 当作问不到,
	## 而不是"没在维护" —— 那一行是 schema 里 insert 进去的, 不见了说明数据不对。
	if not (parsed is Array) or (parsed as Array).is_empty():
		return {"state": ST_UNREACHABLE, "notice": ""}
	var row = (parsed as Array)[0]
	if not (row is Dictionary):
		return {"state": ST_UNREACHABLE, "notice": ""}
	var m = (row as Dictionary).get("maintenance", false)
	if bool(m):
		return {"state": ST_MAINTENANCE, "notice": str((row as Dictionary).get("notice", ""))}
	return {"state": ST_OK, "notice": ""}


## 把一次回包应用到全局状态上。返回新状态。
static func apply_status_response(ok: bool, code: int, body: String) -> String:
	var r := state_from_response(ok, code, body)
	_state = str(r["state"])
	_notice = str(r["notice"])
	_asked += 1
	return _state


# ─────────────────────────────────────────────────────────────
# 传输: 唯一碰 HTTP 的地方(照抄 remote_pool 的形状, 含可注入的缝)
# ─────────────────────────────────────────────────────────────
## 可注入的传输。签名 func(method, url, headers: PackedStringArray, body, cb) -> void
## cb 收 {"ok": bool, "code": int, "body": String}。
var _transport: Callable = Callable()
var _autofree := false


static func _spawn():
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var n = new()
	n._autofree = true
	tree.root.add_child(n)
	return n


## 去问一次服务状态。**发完就忘**；没配后端 = 什么都不做（连节点都不建）。
static func fetch_status_async() -> void:
	if not enabled():
		return
	var n = _spawn()
	if n != null:
		n.fetch_status()


func fetch_status() -> void:
	if not enabled():
		_bye()
		return
	var url := base_url().rstrip("/") + "/rest/v1/service_status?select=*&limit=1"
	_http("GET", url, "", func(res):
		apply_status_response(
			bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", "")))
		_bye())


## ★★`Authorization` 用的是【登录后的 access_token】, 不是 anon key ——
##   这一条错了会静默要命: 写 `ghosts` 的 RLS 策略是 `account_id = auth.uid()`,
##   而拿 anon key 当 Bearer 时 `auth.uid()` 是 **null** ⇒ 每一次上传都 403,
##   而上传是"发完就忘"的 ⇒ **玩家侧完全无感, 池子里永远一行都没有**。
##   (2026-09-20 实测过这条策略: 冒充别人的 account_id 写 ghosts 返回 403 RLS violation。)
## ★没登录时回落到 anon key: `/auth/v1/signup` 与 `service_status` 这两条**本来就该**用它
##   (前者还没有身份, 后者的读策略是 `using (true)`)。
func _headers(extra: String = "") -> PackedStringArray:
	var k := anon_key()
	var bearer := _token if _token != "" else k
	var h := PackedStringArray([
		"apikey: " + k,
		"Authorization: Bearer " + bearer,
		"Accept: application/json",
	])
	if extra != "":
		h.append(extra)
	if extra != "" and extra.begins_with("Prefer"):
		h.append("Content-Type: application/json")
	return h


func _http(method: String, url: String, body: String, cb: Callable, extra: String = "") -> void:
	if _transport.is_valid():
		_transport.call(method, url, _headers(extra), body, cb)
		return
	## ★`is_inside_tree()` 必须判: HTTPRequest 不在树上时 `request()` 直接报错
	##   (旧后端那层踩过, 见 remote_pool 的同位置注释)。
	if not is_inside_tree():
		cb.call({"ok": false, "code": 0, "body": ""})
		return
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT_SEC
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, data: PackedByteArray):
		var okk: bool = (result == HTTPRequest.RESULT_SUCCESS)
		cb.call({"ok": okk, "code": code, "body": data.get_string_from_utf8()})
		req.queue_free())
	var err := req.request(url, _headers(extra), _method_of(method), body)
	if err != OK:
		cb.call({"ok": false, "code": 0, "body": ""})
		req.queue_free()


static func _method_of(m: String) -> int:
	match m.to_upper():
		"POST": return HTTPClient.METHOD_POST
		"PATCH": return HTTPClient.METHOD_PATCH
		"DELETE": return HTTPClient.METHOD_DELETE
		_: return HTTPClient.METHOD_GET


func _bye() -> void:
	if _autofree:
		queue_free()
