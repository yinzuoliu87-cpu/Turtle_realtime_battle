extends RefCounted
## 多入口选路(大陆中转 · 方案书 docs/plans/20261020-大陆中转.md §3, 2026-10-20 第一阶段)。
##
## ══════════════════════════════════════════════════════════════════════
##  这一层解决什么
## ══════════════════════════════════════════════════════════════════════
##   大陆玩家连不上 `*.supabase.co`(问题总表 F1)。只把地址换成中转 ⇒ 中转一挂全体掉线;
##   ⇒ 两条入口并存: 直连(Supabase 本身)+ 中转(`cn.turtlearena.xyz`, 纯转发, 只改 Host, server/relay/)。
##   启动时两条一起问一次 `service_status`(版本闸白名单里的只读表), **第一个回 2xx 的**胜出, 存 `user://net_route.cfg`;
##   下次启动先用上次那条, 后台再竞速一次纠正(只纠正这一次 ⇒ 会话内稳定)。
##
## ★只有【传输层失败】算坏(HTTPRequest 结果不是 SUCCESS 或 code = 0):
##   401 / 403 / 404 / 426 / 5xx 都是服务器真的回了话 —— 换一条路问到的还是同一个服务器, 切了也没用,
##   426 更是版本墙的事。当前那条连续 FAIL_SWITCH 次传输失败 ⇒ 换到另一条, 并重新竞速。
## ★★写请求永不跨路重发(方案书 R7 / D6): 第一条可能其实已经写进去了、只是回包丢了。
##   能换路重发的只有 `retry_safe`: GET / HEAD, 以及 `READ_RPCS` 里的只读 RPC。
##   ⚠ 比 `SupabaseNet.is_write_request` 更严: 那张表把 `/auth/v1/` 当「不是写」(时间穿越不拦身份),
##   但 `POST /auth/v1/signup` 发两次 = 两个匿名号, `refresh_token` 用两次 = 第二次 already_used 把会话判死 ⇒ 不重发。
## ★直播跟 API 走同一条(§3.5, 中转与 stream 同一台机器): `stream_base()`。
## ★令牌与入口无关(JWT 由 Supabase 签发与校验), 换路不登出。
##
## 配置(优先级从高到低):
##   直连 = 环境变量 TURTLE_SUPABASE(空白 = 整层停用, 门禁一律这么设)> ProjectSettings turtle/supabase_url
##   中转 = 环境变量 TURTLE_RELAY(空白 = 不用中转)> ProjectSettings turtle/relay_url > DEFAULT_RELAY
##   ⇒ 门禁 TURTLE_SUPABASE=" " ⇒ 一条都没有, 与改之前逐字相同(一个请求都不发, 也不竞速)。
##   ⚠ 设了 TURTLE_SUPABASE(指到假地址的门禁)而没设 TURTLE_RELAY ⇒ 只有一条, 也不竞速 —— 那 40 来个注入传输的门禁不受影响。
##   中转的 DNS 还没加的时候(cn 解析不到)它只会在竞速里输掉, 直连照常。
## 守卫: tests/verify_net_route_failover.gd

const ENV_URL := "TURTLE_SUPABASE"
const SETTING_URL := "turtle/supabase_url"
const ENV_RELAY := "TURTLE_RELAY"
const SETTING_RELAY := "turtle/relay_url"
const DEFAULT_RELAY := "https://cn.turtlearena.xyz"
## 直连的直播入口(server/stream/)。走中转时 = 中转 + "/streams"(server/relay/relay.caddy 转过去)。
const STREAM_DIRECT := "https://stream.turtlearena.xyz/streams"
## 直播地址的设置项(默认 = STREAM_DIRECT; 内测服包读 `turtle/stream_base.beta_server`, 方案书 20261020-内测服.md §4.4)。
const SETTING_STREAM := "turtle/stream_base"
const PROBE_PATH := "/rest/v1/service_status?select=*&limit=1"
const RACE_SEC := 4.0
const FAIL_SWITCH := 2
const SAVE_PATH := "user://net_route.cfg"
## 只读 RPC 表就用 `SupabaseNet.READ_RPCS`(不另抄一份)。运行期才 load: supabase.gd preload 本文件, 反过来 preload 就成环。
const SB_PATH := "res://scripts/net/supabase.gd"
const SELF_PATH := "res://scripts/net/net_route.gd"
## 正式服 / 内测服(构建期切, 地址与 key 一起换): `server_env.gd`。
const _SE := preload("res://scripts/net/server_env.gd")

const RACE_IDLE := "idle"
const RACE_RUNNING := "running"
const RACE_DONE := "done"

## 门禁用: 非空 ⇒ 入口表就是它(第 0 条当直连)。
static var routes_override: PackedStringArray = PackedStringArray()
## 门禁用: 非空 ⇒ 存到这里(默认 SAVE_PATH)。
static var save_path_override := ""

static var _cur := ""                  # 当前入口(base, 不带结尾 /)
static var _saved := false             # 当前入口来自上次存下的选择 ⇒ 不用等竞速
static var _race := RACE_IDLE
static var _queue: Array = []          # 竞速没出结果、又没有上次的选择时, 等着发的请求
static var _fails: Dictionary = {}     # base → 连续传输失败次数
static var _race_node: Node = null
static var _gen := 0                   # 竞速代号: 门禁强行定下入口后, 还在飞的那次竞速回来也不算数
## 观测量(门禁分母 / 网络诊断)
static var races := 0
static var switches := 0
static var alt_retries := 0
static var last_race: Array = []       # [{base, code, ms}] 最近一次竞速每条入口的结果
static var last_winner := ""
static var sends: Dictionary = {}      # base → 交给传输的请求数


static func _norm(s: String) -> String:
	return s.strip_edges().rstrip("/")


## 入口表。第 0 条 = 直连。空 = 整层停用。
static func routes() -> PackedStringArray:
	if not routes_override.is_empty():
		return routes_override
	var direct := ""
	if OS.has_environment(ENV_URL):
		direct = _norm(OS.get_environment(ENV_URL))
	else:
		direct = _norm(str(_SE.setting(SETTING_URL, "")))
	if direct == "":
		return PackedStringArray()
	var out := PackedStringArray([direct])
	var relay := ""
	if OS.has_environment(ENV_RELAY):
		relay = _norm(OS.get_environment(ENV_RELAY))
	elif _SE.is_beta():
		## ★内测服不走大陆中转: cn.turtlearena.xyz 只转发到正式服那台 Supabase(server/relay/), 走它 = 连回正式服。
		relay = ""
	elif not OS.has_environment(ENV_URL):
		relay = _norm(str(ProjectSettings.get_setting(SETTING_RELAY, DEFAULT_RELAY)))
	if relay != "" and relay != direct:
		out.append(relay)
	return out


static func multi() -> bool:
	return routes().size() > 1


## 当前入口。单入口 ⇒ 就是它(与改之前相同); 多入口 ⇒ 上次存下的 / 竞速选出的 / 还没选 ⇒ 直连。
static func current_base() -> String:
	var rs := routes()
	if rs.is_empty():
		return ""
	if rs.size() == 1:
		return rs[0]
	if _cur == "" or not rs.has(_cur):
		var s := _load_saved()
		_saved = s != "" and rs.has(s)
		_cur = s if _saved else rs[0]
	return _cur


## 直播入口: 当前走直连 ⇒ stream 自己的地址(内测服包 = `/beta/streams`); 走中转 ⇒ 中转/streams。
static func stream_base() -> String:
	var rs := routes()
	var c := current_base()
	if rs.size() > 1 and c != rs[0]:
		return c + "/streams"
	return stream_direct()


## 直连的直播地址: 设置 `turtle/stream_base`(内测服包换成 `.beta_server` 那一项), 没设 = STREAM_DIRECT。
static func stream_direct() -> String:
	var v := _norm(str(_SE.setting(SETTING_STREAM, STREAM_DIRECT)))
	return v if v != "" else STREAM_DIRECT


## 当前入口是不是中转(网络诊断 / 日志用)。
static func on_relay() -> bool:
	var rs := routes()
	return rs.size() > 1 and current_base() != rs[0]


## url 属于哪条入口(前缀); 不属于任何一条 ⇒ ""。
static func base_of(url: String) -> String:
	for b in routes():
		if url == b or url.begins_with(b + "/") or url.begins_with(b + "?"):
			return b
	return ""


## 把按任意一条入口拼出来的 url 换到当前入口上(调用方都是 `SupabaseNet.base_url() + 路径` 拼的,
##   拼的那一刻和真发出去的那一刻之间可能刚好换了路)。
static func rebase(url: String) -> String:
	var b := base_of(url)
	var c := current_base()
	if b == "" or c == "" or b == c:
		return url
	return c + url.substr(b.length())


## 另一条入口(两条时就是对面那条); 只有一条 ⇒ ""。
static func alt_of(base: String) -> String:
	var rs := routes()
	if rs.size() < 2:
		return ""
	var i := rs.find(base)
	return rs[(i + 1) % rs.size()] if i >= 0 else ""


## 纯函数: 这是不是传输层失败(连不上 / 超时 / 连接被重置)。服务器回了任何状态码都不算。
static func transport_failed(res: Dictionary) -> bool:
	if bool(res.get("blocked", false)):
		return false
	return not bool(res.get("ok", false)) or int(res.get("code", 0)) <= 0


## 纯函数: 这个请求能不能在另一条路上再发一次(见文件头: 比 is_write_request 更严)。
static func retry_safe(method: String, url: String) -> bool:
	var m := method.to_upper()
	if m == "GET" or m == "HEAD":
		return true
	if m != "POST":
		return false
	var i := url.find("/rest/v1/rpc/")
	if i < 0:
		return false
	var rpc := url.substr(i + "/rest/v1/rpc/".length()).split("?")[0]
	return (load(SB_PATH).READ_RPCS as Array).has(rpc)


## 记一次结果。传输失败 ⇒ 这条记一笔, 当前那条连着 FAIL_SWITCH 次 ⇒ 换路 + 重新竞速; 回了话 ⇒ 清零。
static func note(base: String, res: Dictionary, hdrs: PackedStringArray = PackedStringArray()) -> void:
	if base == "" or bool(res.get("blocked", false)):
		return
	if not transport_failed(res):
		_fails[base] = 0
		return
	_fails[base] = int(_fails.get(base, 0)) + 1
	if base == current_base() and int(_fails[base]) >= FAIL_SWITCH and multi():
		var alt := alt_of(base)
		if alt != "" and alt != base:
			print("[NetRoute] %s 连续 %d 次连不上 ⇒ 换到 %s" % [_label(base), int(_fails[base]), _label(alt)])
			_set_current(alt)
			_fails[base] = 0
			if _race != RACE_RUNNING:
				_race = RACE_IDLE
				kick(hdrs)


static func note_send(base: String) -> void:
	sends[base] = int(sends.get(base, 0)) + 1


## 现在要不要先等竞速(多入口、还没选出来、也没有上次的选择)。
static func pending() -> bool:
	if not multi():
		return false
	current_base()
	return not _saved and _race != RACE_DONE


## 等竞速出结果后再调 `f`(没在等 ⇒ 立刻调)。
static func when_ready(f: Callable) -> void:
	if pending():
		_queue.append(f)
	else:
		f.call()


## 需要的话起一次竞速(每个进程一次; 换路之后再一次)。`hdrs` = 请求头(apikey 等, 由 SupabaseNet 给)。
static func kick(hdrs: PackedStringArray) -> void:
	if _race != RACE_IDLE or not multi():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		_finish("", [])
		return
	_race = RACE_RUNNING
	var n := _Race.new()
	n.name = "NetRouteRace"
	n.bases = routes()
	n.hdrs = hdrs
	n.gen = _gen
	_race_node = n
	tree.root.add_child.call_deferred(n)


static func _finish(winner: String, rlog: Array, gen: int = -1) -> void:
	if gen >= 0 and gen != _gen:
		return
	_race = RACE_DONE
	_race_node = null
	races += 1
	last_race = rlog
	last_winner = winner
	if winner != "" and routes().has(winner):
		if winner != current_base():
			print("[NetRoute] 竞速: %s 先到 ⇒ 换过去" % _label(winner))
			_set_current(winner)
		else:
			_save(winner)
	var q := _queue
	_queue = []
	for f in q:
		(f as Callable).call()


static func _set_current(b: String) -> void:
	if b != _cur:
		switches += 1
	_cur = b
	_saved = true
	_save(b)


static func _label(b: String) -> String:
	var rs := routes()
	return ("direct" if rs.size() > 0 and b == rs[0] else "relay") + "(" + b + ")"


static func _path() -> String:
	return save_path_override if save_path_override != "" else SAVE_PATH


static func _load_saved() -> String:
	var cf := ConfigFile.new()
	if cf.load(_path()) != OK:
		return ""
	return _norm(str(cf.get_value("route", "base", "")))


static func _save(b: String) -> void:
	var cf := ConfigFile.new()
	cf.set_value("route", "base", b)
	cf.set_value("route", "at", int(Time.get_unix_time_from_system()))
	cf.save(_path())


## 网络诊断(方案书 §3.7)读这一份。
static func status() -> Dictionary:
	return {"routes": routes(), "current": current_base(), "relay": on_relay(), "race": _race,
		"last_race": last_race, "winner": last_winner, "switches": switches, "fails": _fails.duplicate()}


## 门禁用: 清空本进程状态(入口表与存档路径照旧由调用方设)。
static func _reset_for_test() -> void:
	_gen += 1
	_race_node = null
	_cur = ""
	_saved = false
	_race = RACE_IDLE
	_queue = []
	_fails = {}
	races = 0
	switches = 0
	alt_retries = 0
	last_race = []
	last_winner = ""
	sends = {}


## 门禁用: 直接定下当前入口、不竞速(注入传输的那几段用)。
static func _force_for_test(b: String) -> void:
	_gen += 1
	_cur = b
	_saved = true
	_race = RACE_DONE


## 竞速节点: 每条入口一个 HTTPRequest 同时发, 第一个 2xx 胜出; 都回完或 RACE_SEC 到点 ⇒ 收尾。
class _Race extends Node:
	var bases: PackedStringArray = PackedStringArray()
	var hdrs: PackedStringArray = PackedStringArray()
	var gen := 0
	var _t0 := 0
	var _log: Array = []
	var _left := 0
	var _winner := ""
	var _done := false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_t0 = Time.get_ticks_msec()
		for b in bases:
			var r := HTTPRequest.new()
			r.timeout = RACE_SEC
			add_child(r)
			var base: String = b
			r.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _d: PackedByteArray) -> void:
				_on(base, result, code))
			if r.request(base + PROBE_PATH, hdrs) == OK:
				_left += 1
			else:
				_log.append({"base": base, "code": 0, "ms": 0})
		if _left == 0:
			_end()

	func _on(base: String, result: int, code: int) -> void:
		var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
		_log.append({"base": base, "code": code if result == HTTPRequest.RESULT_SUCCESS else 0,
			"ms": Time.get_ticks_msec() - _t0})
		_left -= 1
		if ok and _winner == "":
			_winner = base
			_end()       # ★第一个 2xx 就收尾: 不等慢的那条(大陆直连可能要等满超时)
		elif _left <= 0:
			_end()

	func _process(_dt: float) -> void:
		if not _done and Time.get_ticks_msec() - _t0 > int((RACE_SEC + 1.0) * 1000.0):
			_end()

	func _end() -> void:
		if _done:
			return
		_done = true
		load(SELF_PATH)._finish(_winner, _log, gen)
		queue_free()
