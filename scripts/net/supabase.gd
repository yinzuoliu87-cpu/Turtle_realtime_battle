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


func _headers() -> PackedStringArray:
	var k := anon_key()
	return PackedStringArray([
		"apikey: " + k,
		"Authorization: Bearer " + k,
		"Accept: application/json",
	])


func _http(method: String, url: String, body: String, cb: Callable) -> void:
	if _transport.is_valid():
		_transport.call(method, url, _headers(), body, cb)
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
	var err := req.request(url, _headers(), _method_of(method), body)
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
