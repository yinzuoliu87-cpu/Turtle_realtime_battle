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

## 赛程规则（E-B7 备战购物窗的判据住在那边，这一层只凑时刻不重写规则）。
## ★方向是单向的：`phase2_config` 里**零处**引用本文件，不会循环。
const _P2S := preload("res://scripts/gamedata/phase2_config.gd")

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
	_expires_at = 0
	_auth_inflight = false
	_session_lost = false


## 只给门禁用。空 Callable = 走真网络。
static var _transport_for_test: Callable = Callable()


## 纯函数: 一次 `/auth/v1/signup` 的回包 → 账号信息。**这才是要被逐条验的东西**。
## 返回 {"ok": bool, "account_id": String, "token": String, "is_anonymous": bool, "email": String}。
##
## ★失败一律返回 `ok=false` 且 `account_id=""` —— **不许编一个本地 id 顶上**。
##   那样会让「没登录成功」看起来像「登录成功了」, 而后果要等到上传快照
##   在服务端被 RLS 拒掉时才显形(那时已经隔了好几层)。
static func account_from_auth_response(ok: bool, code: int, body: String) -> Dictionary:
	var bad := {"ok": false, "account_id": "", "token": "", "is_anonymous": false, "email": "",
		"refresh": "", "expires_at": 0}
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
	## ★★`refresh_token` 与 `expires_at` 原来都被**扔掉**了 —— 于是 token 只活在内存里,
	##   重开 App 就没了(D-3c, 2026-09-21 查实)。`expires_at` 用服务端给的**绝对时刻**;
	##   老回包没有它时按 `expires_in` 从现在推算。
	var exp_at := int(dd.get("expires_at", 0))
	if exp_at <= 0 and int(dd.get("expires_in", 0)) > 0:
		exp_at = int(Time.get_unix_time_from_system()) + int(dd.get("expires_in", 0))
	return {
		"ok": true,
		"account_id": uid,
		"token": str(dd.get("access_token", "")),
		"is_anonymous": bool((user as Dictionary).get("is_anonymous", false)),
		"email": str((user as Dictionary).get("email", "")),
		"refresh": str(dd.get("refresh_token", "")),
		"expires_at": exp_at,
	}


## 把一次登录回包应用到全局 + 存档。返回是否成功。
static func apply_auth_response(ok: bool, code: int, body: String) -> bool:
	var r := account_from_auth_response(ok, code, body)
	_auth_tries += 1
	if not bool(r["ok"]):
		return false
	_store_session(r)
	return true


## ★★三条路(注册 / 验码 / 刷新)拿到会话后**都走这一个函数**落地。
##   原来注册与验码各写一份, 两份都漏了 refresh_token —— 手抄的副本必然一起漏。
##   ⚠ `auth_refresh` **紧跟着写盘**: refresh_token 每次刷新都会轮换,
##   拿到新的还没写盘就崩了 ⇒ 下次开机拿旧的去刷 ⇒ 过了服务端约 10 秒的
##   重用宽限就被拒 ⇒ 匿名号失效。写盘离拿到令牌越近, 这个窗口越小。
static func _store_session(r: Dictionary) -> void:
	_token = str(r.get("token", ""))
	_expires_at = int(r.get("expires_at", 0))
	_session_lost = false
	var gs = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/GameState") if Engine.get_main_loop() != null else null
	if gs != null:
		## D-8: 换了号 ⇒ 云存档版本号归零(那是旧号的; 不归零的话新号第一次推就撞冲突)
		if str(gs.account_id) != str(r.get("account_id", "")):
			gs.cloud_rev = 0
		gs.account_id = str(r.get("account_id", ""))
		gs.account_email = str(r.get("email", ""))
		if str(r.get("refresh", "")) != "":
			gs.auth_refresh = str(r["refresh"])
		gs.save()


## 需要的话去匿名登录一次。**已经有 account_id 就什么都不做** ——
## 每次开游戏都新建一个匿名账号的话, 服务端会被刷出一堆一次性账号(Supabase 自己也警告过这点)。
static func ensure_signed_in_async() -> void:
	if not enabled() or _auth_inflight:
		return
	var gs = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/GameState") if Engine.get_main_loop() != null else null
	if gs == null:
		return
	var a := session_action(str(gs.account_id), str(gs.account_email), _token, _expires_at,
		str(gs.auth_refresh), int(Time.get_unix_time_from_system()))
	match a:
		ACT_NONE:
			return
		ACT_LOST:
			_session_lost = true
			return
		ACT_REFRESH:
			var n = _spawn()
			if n != null:
				_auth_inflight = true
				n.refresh_session(str(gs.auth_refresh))
		ACT_SIGNUP:
			var n2 = _spawn()
			if n2 != null:
				_auth_inflight = true
				n2.sign_in_anonymous()


# ════════════════════════════════════════════════════════════
# D-3c 登录态续期(2026-09-21 查实的 bug)
# ════════════════════════════════════════════════════════════
## ★★原来的写法是「已经有 `account_id` 就什么都不做」, 而 access_token 只活在内存里 ⇒
##   **重开 App 之后再也没有 token** ⇒ 请求头退回 anon key ⇒ 写 `ghosts` 被 401 RLS 拒、
##   读 `ghosts` 拿到空列表; 不重开也会在 3600 秒后过期。
##   ⇒ v0.19.420~423 的后端接线**只在装机后第一个小时里真正工作**。
##   所有探针与门禁都没抓到, 因为它们全是「一个进程里从注册跑到底」, 从没模拟过重启。
##
## ★判定抽成纯函数 `session_action` —— 门禁逐条喂, 不需要网络。

const ACT_NONE := "none"          # token 还够用
const ACT_REFRESH := "refresh"    # 拿 refresh_token 续
const ACT_SIGNUP := "signup"      # 新建匿名号(从没登录过 / 匿名号的会话真的死了)
const ACT_LOST := "lost"          # 绑了邮箱的号会话死了 ⇒ 等玩家用邮箱重新登录

const REFRESH_MARGIN_SEC := 300   # 剩不到 5 分钟就续

static var _expires_at: int = 0
static var _auth_inflight: bool = false
static var _session_lost: bool = false


static func session_lost() -> bool:
	return _session_lost


static func token_expires_at() -> int:
	return _expires_at


## 纯函数: 现在该对会话做什么。
## ★★**绑了邮箱的号永远不会得到 ACT_SIGNUP** —— 那是静默换身份
##   (新号拿不到旧号的排名/战绩/云存档)。只能等玩家用邮箱把同一个号取回来。
static func session_action(account_id: String, email: String, token: String,
		expires_at: int, refresh: String, now: int) -> String:
	if account_id == "":
		return ACT_SIGNUP
	if token != "" and expires_at - now > REFRESH_MARGIN_SEC:
		return ACT_NONE
	if refresh != "":
		return ACT_REFRESH
	## 有号、没 token、也没 refresh_token:
	##   · v0.19.420~423 装过的老用户(那几版根本没存 refresh_token)
	##   · 或者刷新被服务端判死之后
	return ACT_SIGNUP if email == "" else ACT_LOST


## 服务端明确说「这个 refresh_token 死了」的那几种 error_code。
## ★**只认这几个**: 认不出来的一律当网络问题 —— 网络抖一下就把人登出,
##   比「多等一会儿再试」糟糕得多。
const DEAD_REFRESH_CODES := ["refresh_token_not_found", "refresh_token_already_used",
	"session_not_found", "session_expired", "user_not_found", "invalid_grant"]

const RK_OK := "ok"
const RK_NET := "net"     # 连不上 / 5xx / 限流 / 看不懂 ⇒ 什么都不动, 下次再试
const RK_DEAD := "dead"   # 服务端明确判死 ⇒ 这份登录真的失效了


## 纯函数: 一次刷新回包 → 三类之一。
## ★实测(2026-09-21): 乱码 refresh_token → 400 `refresh_token_not_found`。
static func refresh_kind(ok: bool, code: int, body: String) -> String:
	if ok and code >= 200 and code < 300:
		## 200 但解不出账号 ⇒ **当网络问题**, 不当成功也不当死 —— 看不懂的回包不许改身份。
		return RK_OK if bool(account_from_auth_response(ok, code, body)["ok"]) else RK_NET
	var j := JSON.new()
	if j.parse(body) == OK and j.data is Dictionary:
		var d: Dictionary = j.data
		var ec := str(d.get("error_code", d.get("error", "")))
		if DEAD_REFRESH_CODES.has(ec):
			return RK_DEAD
	return RK_NET


## 把一次刷新回包落地。返回三类之一。
static func apply_refresh_response(ok: bool, code: int, body: String) -> String:
	_auth_inflight = false
	var kind := refresh_kind(ok, code, body)
	var gs = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/GameState") if Engine.get_main_loop() != null else null
	match kind:
		RK_OK:
			var r := account_from_auth_response(ok, code, body)
			## ★刷新拿回来的必须是【同一个号】。不是 ⇒ 当网络问题, 什么都不动。
			if gs != null and str(gs.account_id) != "" and str(r["account_id"]) != str(gs.account_id):
				print("[SupabaseNet] 刷新回来的账号对不上(%s ≠ %s), 忽略" % [
					str(r["account_id"]).substr(0, 8), str(gs.account_id).substr(0, 8)])
				return RK_NET
			_store_session(r)
		RK_NET:
			print("[SupabaseNet] 续登录没成功(code=%d), 保留令牌下次再试" % code)
		RK_DEAD:
			_token = ""
			_expires_at = 0
			if gs != null:
				gs.auth_refresh = ""
				if str(gs.account_email) == "":
					## 匿名号: 这份身份救不回来了 ⇒ 下一拍重新匿名注册(本机存档不受影响)
					gs.account_id = ""
				else:
					## 绑了邮箱: **不许**自动建新号 —— 等玩家用邮箱把同一个号取回来
					_session_lost = true
				gs.save()
			print("[SupabaseNet] 登录已失效(code=%d)" % code)
	return kind


func refresh_session(refresh: String) -> void:
	if not enabled() or refresh == "":
		_auth_inflight = false
		_bye()
		return
	var url := base_url().rstrip("/") + "/auth/v1/token?grant_type=refresh_token"
	_http("POST", url, JSON.stringify({"refresh_token": refresh}),
		func(res):
			apply_refresh_response(bool(res.get("ok", false)), int(res.get("code", 0)),
				str(res.get("body", "")))
			_bye(),
		"Content-Type: application/json")


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
## ★上传失败**这一层**什么都不做: 不回滚、不弹窗。网络层第一原则 —— 永远不能把游戏搞坏。
## ★★E7(2026-10-04): 「失败就丢」改成了**落盘队列 + 回读销单 + 退避重试**, 但那一层不在这里 ——
##   在 `scripts/net/ghost_uploader.gd`(队列住在 `GameState.ghost_upload_pending`)。
##   这一层只多了一件事: 调用方给了 `done` ⇒ 发完再**回读**那一行, 告诉它「服务端真的有了没有」。
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


## 发一份快照。没配后端 / 没身份 / 缺场次 = 什么都不做(连节点都不建), 返回 false。
## `done` 空 = 发完就忘(老调用点 / 门禁); 给了 ⇒ 发完**回读**, `done.call(confirmed: bool, code: int)`
##   **每一条走掉的路恰好回调一次**(code = 插入那一下的 HTTP 码; 0 = 没发出去 / 没令牌)。
static func upload_ghost_async(row: Dictionary, done: Callable = Callable()) -> bool:
	if not enabled() or row.is_empty():
		return false
	var n = _spawn()
	if n == null:
		return false
	n.upload_ghost(row, done)
	return true


func upload_ghost(row: Dictionary, done: Callable = Callable()) -> void:
	_upload_snapshot_row("ghosts", row, done)


## ghosts / gauntlet_ghosts 两张表共用的「发 + (可选)回读」。
func _upload_snapshot_row(table: String, row: Dictionary, done: Callable) -> void:
	if not enabled() or row.is_empty():
		_snap_done(done, false, 0)
		_bye()
		return
	if not await _await_token():
		print("[SupabaseNet] 快照没传: 拿不到登录令牌(%s)" % table)
		apply_upload_response(false, 0)
		_snap_done(done, false, 0)
		_bye()
		return
	## ★`Prefer: resolution=merge-duplicates` = upsert。同键(同一个人·同一周·同一场次)
	##   再传就覆盖 —— D5「每场都传」靠的就是这个, 否则第二次传会撞主键报 409。
	var base := base_url().rstrip("/") + "/rest/v1/" + table
	_http("POST", base, JSON.stringify(row),
		func(res):
			## 测试时间里被出口拦下: 没发出去, 也不回读、不记上传失败 —— 单子原样留着等回到真实时间。
			if bool(res.get("blocked", false)):
				_snap_done(done, false, BLOCKED_CODE)
				_bye()
				return
			_log_upload_fail(table, res)
			var code := int(res.get("code", 0)) if bool(res.get("ok", false)) else 0
			apply_upload_response(bool(res.get("ok", false)), int(res.get("code", 0)))
			if not done.is_valid():
				_bye()
				return
			## ★★2xx 不算传成(memory fb-200-ok-is-not-it-happened): RLS / 代理改写 body / return=minimal
			##   都可能「回 2xx 而那一行不在或不是这一份」。销单的唯一判据是回读到**逐字相同**的快照。
			var q := snapshot_readback_query(table, row)
			if q == "":
				_snap_done(done, false, code)
				_bye()
				return
			_http("GET", base + "?" + q, "",
				func(res2):
					var good := snapshot_confirmed(bool(res2.get("ok", false)), int(res2.get("code", 0)),
						str(res2.get("body", "")), row.get("snapshot", {}))
					if not good:
						print("[SupabaseNet] 快照回读不到(%s) code=%d" % [table, int(res2.get("code", 0))])
					_snap_done(done, good, code)
					_bye()),
		"Prefer: resolution=merge-duplicates,return=minimal")


static func _snap_done(done: Callable, confirmed: bool, code: int) -> void:
	if done.is_valid():
		done.call(confirmed, code)


## 纯函数: 回读那一行要问的查询串(按主键)。账号必须是 uuid 形状 —— 它要拼进查询串。
static func snapshot_readback_query(table: String, row: Dictionary) -> String:
	var acc := str(row.get("account_id", ""))
	var wk := int(row.get("season_week", 0))
	if not is_uuid(acc) or wk <= 0:
		return ""
	if table == "ghosts" and int(row.get("battles", -1)) >= 0:
		return "account_id=eq.%s&season_week=eq.%d&battles=eq.%d&select=snapshot" % [acc, wk, int(row["battles"])]
	if table == "gauntlet_ghosts" and int(row.get("gw", -1)) >= 0 and int(row.get("gl", -1)) >= 0:
		return "account_id=eq.%s&season_week=eq.%d&gw=eq.%d&gl=eq.%d&select=snapshot" % [
			acc, wk, int(row["gw"]), int(row["gl"])]
	return ""


## 纯函数: 回读回包 → 服务端那一行的快照是不是**就是我发的这一份**。
## ★比的是规范化之后的 JSON(键排序): jsonb 会重排键, 但值一个字都不该变。
##   同键被别的上传覆盖成另一份 ⇒ 不算(那一份不是这张单子)。
static func snapshot_confirmed(ok: bool, code: int, body: String, sent) -> bool:
	if not ok or code < 200 or code >= 300 or not (sent is Dictionary) or (sent as Dictionary).is_empty():
		return false
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Array):
		return false
	var want := canonical_json(sent)
	for r in (j.data as Array):
		if r is Dictionary and (r as Dictionary).get("snapshot", null) is Dictionary \
				and canonical_json((r as Dictionary)["snapshot"]) == want:
			return true
	return false


## 走一遍 JSON 再按键排序输出 —— 两边都过同一道, 数字(int/float)的表示也就一致了。
static func canonical_json(v) -> String:
	var j := JSON.new()
	if j.parse(JSON.stringify(v)) != OK:
		return ""
	return JSON.stringify(j.data, "", true)


## ★★2026-10-04 上传前先要有**有效的**登录令牌。
##   由来: 10 个模拟号这周打了两百多场, 服务端 `ghosts` 里**一行都没有**(只读查实);
##   探针: 令牌为空时上传 ⇒ 请求头退回公共匿名钥匙 ⇒ 401 / 42501「违反行级权限」;
##   同一个号先续期拿到令牌再传 ⇒ 201。令牌只活在内存, 冷启动头几秒是空的, 约 1 小时过期;
##   原来上传那条路**不看令牌**就发, 失败也只记一个计数、不打日志 —— 所以一直没人发现。
## ⇒ 没有/快过期就先续(走产品自己的 `ensure_signed_in_async`), 等最多约 10 秒。
static func token_fresh(now: int) -> bool:
	return _token != "" and (_expires_at <= 0 or _expires_at - now > REFRESH_MARGIN_SEC)


func _await_token() -> bool:
	if token_fresh(int(Time.get_unix_time_from_system())):
		return true
	ensure_signed_in_async()
	## 续期一结束(成功或失败)就判定 —— 不白等满 10 秒(失败时屏幕会一直转「正在连线」)。
	for _i in range(600):
		if not is_inside_tree():
			return false
		await get_tree().process_frame
		if _token != "":
			return true
		if not _auth_inflight:
			break
	return _token != ""


## 上传被拒时把服务端原话打出来 —— 原来只记一个失败计数, 401 静默了一整周。
static func _log_upload_fail(table: String, res: Dictionary) -> void:
	var code := int(res.get("code", 0))
	if code >= 200 and code < 300:
		return
	print("[SupabaseNet] 上传 %s 被拒 code=%d %s" % [table, code, str(res.get("body", "")).left(200)])


# ═════════════════════════════════════════════════════════════
# E-A4 周六闯关赛: 另一张池子, 按【战绩标签】撮合
#
# ★★为什么不复用 ghosts 那一套: 两者的**匹配维度不是一回事** ——
#   ghosts 按「总场次」(D5 积分赛硬条件), 闯关赛按「战绩标签」(3-1 只碰 3-1, 永不跨标签)。
#   同一张表里放两个维度, 按场次查会捞到周六的行、反之亦然, 而且**静默**。
# ═════════════════════════════════════════════════════════════

## 纯函数: 快照 + 战绩 → 要 POST 的那一行。
## ★三条缺一不可的前提, 缺了就**不传**而不是填默认值 —— 填 0/空串会在服务端造出
##   一行"看起来合法"的垃圾, 还可能撞主键覆盖别人(与 `ghost_row_from_snapshot` 同一个理由)。
static func gauntlet_row_from_snapshot(snapshot: Dictionary, account_id: String,
		season_week: int, gw: int, gl: int, client_version: String) -> Dictionary:
	if account_id == "" or season_week <= 0 or gw < 0 or gl < 0:
		return {}
	if snapshot == null or snapshot.is_empty():
		return {}
	return {
		"account_id": account_id,
		"season_week": season_week,
		"gw": gw,
		"gl": gl,
		"snapshot": snapshot,
		"client_version": client_version,
	}


## 形状与回调约定同 `upload_ghost_async`。
static func upload_gauntlet_async(row: Dictionary, done: Callable = Callable()) -> bool:
	if not enabled() or row.is_empty():
		return false
	var n = _spawn()
	if n == null:
		return false
	n.upload_gauntlet(row, done)
	return true


func upload_gauntlet(row: Dictionary, done: Callable = Callable()) -> void:
	_upload_snapshot_row("gauntlet_ghosts", row, done)


## 纯函数: 拉同标签对手的查询串。
## ★★与积分赛那条 `opponents_query` 的**关键差别**: 那边是 `battles=in.(N, N+1)`
##   —— 允许差一场(池子薄时的让步); 这边是 `gw=eq.X&gl=eq.Y` **完全相等**,
##   原稿写死「永不跨标签」。放宽一格就等于让 3-1 打 3-2, 而那两个人的
##   经济供给差了一整场 —— 闯关赛的全部意义就是"同战绩的人互相淘汰"。
static func gauntlet_query(season_week: int, gw: int, gl: int, account_id: String) -> String:
	if season_week <= 0 or gw < 0 or gl < 0 or account_id == "":
		return ""
	return ("season_week=eq.%d&gw=eq.%d&gl=eq.%d&account_id=neq.%s" \
		+ "&select=snapshot,uploaded_at&order=uploaded_at.desc&limit=%d") % [
		season_week, gw, gl, account_id, PULL_LIMIT]


static func pull_gauntlet_async(season_week: int, gw: int, gl: int,
		account_id: String) -> void:
	if not enabled():
		return
	var q := gauntlet_query(season_week, gw, gl, account_id)
	if q == "":
		return
	_last_query = q                      ## 拉失败时日志要能打出【刚才问的那条】
	var n = _spawn()
	if n != null:
		n.pull_gauntlet(q)


func pull_gauntlet(q: String) -> void:
	if not enabled() or q == "":
		_bye()
		return
	## ★2026-10-04: 读也要令牌 —— 读规则是 auth.uid() is not null, 没令牌去拉服务端**不报错、只返回 0 行**,
	##   客户端就当成「没有对手」回落机器人(与上传 401 同一个根: 令牌只活在内存、冷启动为空、会过期)。
	if not await _await_token():
		print("[SupabaseNet] 没拉对手: 拿不到登录令牌(gauntlet_ghosts)")
		_bye()
		return
	## ★入池走的是与积分赛**同一个** `apply_pull_response()` ——
	##   那里已经把「解包 → 验快照 → 入池 → 存盘 → 记账」整条路封好了。
	##   手写第二份就是「手抄的副本必然落后」(我第一版就这么写的,
	##   而且调了两个不存在/签名不符的函数 —— GDScript 鸭子类型, 编译期不报)。
	var url := base_url().rstrip("/") + "/rest/v1/gauntlet_ghosts?" + q
	_http("GET", url, "",
		func(res):
			apply_pull_response(bool(res.get("ok", false)), int(res.get("code", 0)),
				str(res.get("body", "")))
			_bye())



# ═════════════════════════════════════════════════════════════
# D-4b 匹配: 从 `ghosts` 拉【同一周 + 同场次】的对手快照并入本地池
# ═════════════════════════════════════════════════════════════
## ★★**匹配路径一行网络代码都不许有**。这次拉取填的是【下一局】的池子 ——
##   本局的对手已经在 `Backend.find_opponent()` 里用现有本地池算出来了, 一步都不等网络。
##   这是「离线不退化」那条硬指标的落点: 断网时这整层是 no-op, 匹配照常跑。
##
## ★为什么拉 `battles in (N, N+1)` 而不是只拉 N:
##   · **N+1** 是主要目标 —— 我现在是 N 场, 打完这局就是 N+1 场,
##     下一次匹配要找的就是 N+1 场的人。拉回来的正好那时能用。
##   · **N 也要拉**, 因为场次并不总是涨的: `_settle_season` 里
##     `season_total_battles += 1` 在【非表演赛】分支里 ⇒
##     **0 命玩家打表演赛时场次不涨**, 会卡在同一个数反复打。
##     只拉 N+1 的话这类玩家的池子永远是空的, 一直打 bot。
##
## ★排除自己有两层, 且两层作用不同:
##   ① 服务端 `account_id=neq.<我>` —— 省带宽, 也是 D 方案书点名的口径。
##   ② 本地 `Backend._is_self_ghost()` —— 它的**第一判据就是 ghost_id 前缀**
##     (2026-08-27 就是踩了这个坑才加的): 自己那份从服务器绕一圈回来时
##     `origin` 会被盖成 `remote`, 只看 origin 就会**打到自己**。
##     id 是确定性的、绕多少圈都不变 —— 所以服务端那层挂了也不会穿帮。
##
## ⚠ 拉回来的快照**必须过 `RemotePool.snapshot_valid()`**(走 `ingest_remote` 就自带了)。
##   理由不是假想: `ghosts` 表**故意没给 delete 策略**(防「打不过就把自己撤下来」),
##   所以 2026-09-21 验 upsert 时写进去的探针行删不掉、还在库里。
##   池子里混进结构不全的行是**常态**，不是意外。

const PULL_LIMIT := 40

static var _pulls_ok: int = 0
static var _pulls_try: int = 0
## 最后一次拉取的账 —— **必须被打印**。静默丢弃 = 假装「同步成功了」
## 而池子其实一条没进(同 `RemotePool.ingest_remote` 那段注释)。
static var _last_pull: Dictionary = {"total": 0, "added": 0, "rejected": 0, "reasons": []}
## 最后一次发出去的查询串。★**拉取失败时必须打出来** ——
##   「拉回 0 份」有两种完全不同的原因(问错了 / 真没人)，
##   不把问题本身打出来就分不开，而这两种的修法南辕北辙。
static var _last_query: String = ""


static func pull_ok_count() -> int:
	return _pulls_ok


static func pull_try_count() -> int:
	return _pulls_try


static func last_pull_stats() -> Dictionary:
	return _last_pull.duplicate(true)


static func last_query() -> String:
	return _last_query


static func _reset_pull_for_test() -> void:
	_pulls_ok = 0
	_pulls_try = 0
	_last_pull = {"total": 0, "added": 0, "rejected": 0, "reasons": []}
	_last_query = ""


## 纯函数: 拼匹配查询串。返回 "" 表示**不该拉**(缺身份 / 缺周 / 场次为负)。
## ★与 `ghost_row_from_snapshot` 同一条原则: 缺前提就什么都不做,
##   不拿 0 / 空串凑一个查询发出去 —— `account_id=neq.` 后面空着的话
##   PostgREST 会拿它当一个合法过滤器算, 结果是**把自己也拉回来**。
static func opponents_query(season_week: int, battles: int, account_id: String) -> String:
	if season_week <= 0 or battles < 0 or account_id == "":
		return ""
	## `select=snapshot` 只要快照那一列 —— 其余列(排序三键/版本号)客户端用不着,
	## 而快照本身已经带着它们。`order=uploaded_at.desc` 走的是 D-2 建好的
	## 索引 `(season_week, battles, uploaded_at desc)`。
	##
	## ★★★这个窗口是【预取】, **不是匹配判据**。区别是 2026-09-25 我栽的那个坑的全部:
	##   那次我把窗口改成上下对称 ±1, 理由写的是「池子薄时只查等场次会查不到人」——
	##   理由本身对(这是**拉取**这一侧的事), 但我顺手把同一个常量拿去给
	##   `Backend.find_opponent()` **选靶**用了 ⇒ 5 场次的人照旧打 6 场次的,
	##   而且我还把「窗口必须对称」焊成门禁, 等于**给错误上了锁**。
	##   现在匹配只认【完全相同】(D5), 选靶那一侧**一个字都不读这里**。
	##
	## ★★为什么只往前开(`battles .. battles + AHEAD`), 不往后开:
	##   我现在 N 场, 打完这局就是 **N+1** 场 ⇒ 预取 N+1 是给下一局暖池子。
	##   而 N-1 我**永远不会再回去**(场次只增不减), 拉回来的快照一条都匹配不上 ⇒
	##   往下开纯粹白占 `PULL_LIMIT` 的名额, 把真正有用的那一格挤掉。
	##   ⇒ 原来的 `in.(N, N+1)` 其实是对的; 我 09-25 改错的是它的**用途**, 不是它的形状。
	var ahead: int = int(_P2S.PULL_BATTLES_AHEAD)
	var vals: Array = []
	for n in range(battles, battles + ahead + 1):
		if n >= 0 and not vals.has(n):
			vals.append(n)
	return ("season_week=eq.%d&battles=in.(%s)&account_id=neq.%s" \
		+ "&select=snapshot&order=uploaded_at.desc&limit=%d") % [
		season_week, ",".join(vals.map(func(x): return str(x))), account_id, PULL_LIMIT]


## 纯函数: 从 REST 回包正文里把【快照】抽出来。
## ★回包是 `[{"snapshot": {...}}, ...]` —— 外层是**行**不是快照。
##   直接把行喂给 `ingest_remote` 的话每一条都会被 `snapshot_valid` 以
##   「缺 ghost_id」拒掉 —— 而那看起来像「服务端没数据」。
static func snapshots_from_body(body: String) -> Array:
	var parsed = JSON.parse_string(body)
	if not (parsed is Array):
		return []
	var out: Array = []
	for row in (parsed as Array):
		if not (row is Dictionary):
			continue
		var snap = (row as Dictionary).get("snapshot", null)
		if snap is Dictionary and not (snap as Dictionary).is_empty():
			out.append(snap)
	return out


## 把一次拉取回包并进本地池。返回统计(也存进 `_last_pull`)。
## ★拉取失败**什么都不做**: 不重试、不回滚、不碰存档、不弹窗。
##   池子空的后果只是打 bot(永久安全网), 不是把游戏搞坏。
static func apply_pull_response(ok: bool, code: int, body: String) -> Dictionary:
	_pulls_try += 1
	var st: Dictionary = {"total": 0, "added": 0, "rejected": 0, "reasons": []}
	if not (ok and code >= 200 and code < 300):
		print("[SupabaseNet] 拉对手失败(code=%d), 忽略 —— 照旧打本地池/bot\n              刚才问的是: %s" % [code, _last_query])
		_last_pull = st
		return st
	_pulls_ok += 1
	var RP = load("res://scripts/net/remote_pool.gd")
	var BE = load("res://scripts/net/backend.gd")
	if RP == null or BE == null:
		_last_pull = st
		return st
	var snaps: Array = snapshots_from_body(body)
	var pool: Dictionary = BE.load_pool()
	st = RP.ingest_remote(pool, snaps)
	if int(st["added"]) > 0:
		BE.save_pool(pool)
	print("[SupabaseNet] 拉回 %d 份, 入池 %d, 拒 %d %s"
		% [int(st["total"]), int(st["added"]), int(st["rejected"]), str(st["reasons"])])
	_last_pull = st
	return st


## 去拉一次对手。**发完就忘**; 没配后端 / 没身份 / 缺周 = 什么都不做(连节点都不建)。
static func pull_opponents_async(season_week: int, battles: int, account_id: String) -> void:
	if not enabled():
		return
	var q := opponents_query(season_week, battles, account_id)
	if q == "":
		return
	_last_query = q
	var n = _spawn()
	if n != null:
		n.pull_opponents(q)


func pull_opponents(query: String) -> void:
	if not enabled() or query == "":
		_bye()
		return
	## ★2026-10-04: 读也要令牌 —— 读规则是 auth.uid() is not null, 没令牌去拉服务端**不报错、只返回 0 行**,
	##   客户端就当成「没有对手」回落机器人(与上传 401 同一个根: 令牌只活在内存、冷启动为空、会过期)。
	if not await _await_token():
		print("[SupabaseNet] 没拉对手: 拿不到登录令牌(ghosts)")
		_bye()
		return
	var url := base_url().rstrip("/") + "/rest/v1/ghosts?" + query
	_http("GET", url, "",
		func(res):
			apply_pull_response(bool(res.get("ok", false)), int(res.get("code", 0)),
				str(res.get("body", "")))
			_bye())



# ═════════════════════════════════════════════════════════════
# D-3b 补绑邮箱 + 换设备取回
# ═════════════════════════════════════════════════════════════
## 两条流程共用「发码 → 验码」两步，但**第二步的判据正好相反**，别写成一个：
##
##   · 补绑(bind)    `PUT /auth/v1/user {email}` → 验码 →
##     ★★返回的 id **必须等于**当前 `account_id`。不等 = 服务端新建了号 ⇒
##       接受它就等于把玩家的赛季身份换掉了（排名/战绩/鬼影全断），而且是静默的。
##
##   · 换设备(recover) `POST /auth/v1/otp {email}` → 验码 →
##     返回的 id **本来就和本机当前的不同** —— 那正是要换过去的那个。
##
## ⚠⚠ **「绑邮箱」不等于「存档不丢」**（2026-09-21 核实）：
##   服务端五张表 `accounts / ghosts / matches / standings / service_status`
##   **没有一张存玩家存档**（`accounts` 只有 display_name/created_at/last_seen）。
##   龟等级、装备、深海币全在本机 `user://savegame.json`。
##   ⇒ 绑邮箱找回的是**赛季身份**，不是**存档**。UI 文案必须照这个说，
##     否则是在承诺一件架构上做不到的事。存档同步要不要做是另一件事（未决）。
##
## ★客户端先挡一道邮箱格式，是为了省**发信配额** ——
##   Supabase 内置 SMTP 限流很严，一个手滑的错别字就浪费一封、还要等。

const EM_IDLE := "idle"
const EM_SENDING := "sending"      # 正在请求发码
const EM_SENT := "sent"            # 码已发出, 等玩家输入
const EM_VERIFYING := "verifying"  # 正在验码
const EM_OK := "ok"
const EM_ERR := "err"

const FLOW_BIND := "bind"
const FLOW_RECOVER := "recover"

static var _email_state: String = EM_IDLE
static var _email_msg: String = ""
static var _email_pending: String = ""     # 正在绑/正在登录的那个邮箱
static var _email_flow: String = ""


static func email_state() -> String:
	return _email_state


static func email_msg() -> String:
	return _email_msg


static func email_pending() -> String:
	return _email_pending


static func email_flow() -> String:
	return _email_flow


static func reset_email_flow() -> void:
	_email_state = EM_IDLE
	_email_msg = ""
	_email_pending = ""
	_email_flow = ""


## 纯函数: 邮箱看起来合法吗。**不追求完全符合 RFC** —— 那既做不到也没必要;
## 这一道的唯一目的是**挡住手滑**，省下那封发不起的信。真正的判定在服务端。
static func email_looks_valid(s: String) -> bool:
	var e := s.strip_edges()
	if e.length() < 6 or e.length() > 254:
		return false
	if e.contains(" ") or e.contains(",") or e.contains("\t"):
		return false
	var at := e.find("@")
	if at <= 0 or at != e.rfind("@"):       # 必须有且只有一个 @, 且前面有东西
		return false
	var domain := e.substr(at + 1)
	if not domain.contains("."):
		return false
	if domain.begins_with(".") or domain.ends_with("."):
		return false
	if domain.contains(".."):
		return false
	return domain.substr(domain.rfind(".") + 1).length() >= 2


## 纯函数: 一次「发码」回包 → 给玩家看的结果。
## ★**每一种失败都要有一句玩家看得懂的话** —— 「发送失败」等于什么都没说,
##   而这几种的处理方式完全不同（改邮箱 / 换个邮箱 / 等一会儿 / 联系支持）。
## ★实测回包形状（2026-09-21 真打的）:
##   · 邮箱格式不对 → 400 `{"error_code":"validation_failed"}`
##   · 太频繁       → 429 `{"error_code":"over_email_send_rate_limit"}`
static func send_code_result(ok: bool, code: int, body: String) -> Dictionary:
	if ok and code >= 200 and code < 300:
		return {"ok": true, "reason": ""}
	var ec := ""
	var j := JSON.new()
	if j.parse(body) == OK and j.data is Dictionary:
		ec = str((j.data as Dictionary).get("error_code", ""))
	if code == 0:
		return {"ok": false, "reason": "连不上服务器，检查一下网络"}
	if ec == "validation_failed":
		return {"ok": false, "reason": "邮箱格式不对，再看一眼"}
	## ★发信服务还没接上时服务端回这个(官方错误码表原文: 默认发信服务只能发给组织成员)。
	##   原来这里没映射, 走兜底「发送失败, 稍后再试」——「稍后再试」是**错的**, 再试多少次都不会成功。
	if ec == "email_address_not_authorized":
		return {"ok": false, "reason": "邮件服务还没开通，暂时绑定不了（正在接入）"}
	if ec == "email_address_invalid":
		return {"ok": false, "reason": "这个邮箱用不了（示例/测试域名不支持），换一个试试"}
	if ec == "otp_disabled":
		## 取回时填了一个没绑定过的邮箱(实测 422, 见 send_code 里 create_user:false 那段)
		return {"ok": false, "reason": "这个邮箱没有绑定过账号，检查一下拼写"}
	if ec == "email_exists" or ec == "user_already_exists":
		return {"ok": false, "reason": "这个邮箱已经绑过别的账号了"}
	if code == 429 or ec == "over_email_send_rate_limit":
		return {"ok": false, "reason": "发得太频繁了，等几分钟再试"}
	return {"ok": false, "reason": "发送失败（%d），稍后再试" % code}


## 纯函数: 一次「验码」回包 → 结果。
## ★实测: 码错或过期 → 403 `{"error_code":"otp_expired"}`（**两种情况同一个码**，
##   所以话得把两种都说到，不能只说「验证码错误」让人以为是打错了）。
static func verify_code_result(ok: bool, code: int, body: String) -> Dictionary:
	var acc := account_from_auth_response(ok, code, body)
	if bool(acc["ok"]):
		return {"ok": true, "reason": "", "account_id": str(acc["account_id"]),
			"token": str(acc["token"]), "email": str(acc["email"])}
	var ec := ""
	var j := JSON.new()
	if j.parse(body) == OK and j.data is Dictionary:
		ec = str((j.data as Dictionary).get("error_code", ""))
	if code == 0:
		return {"ok": false, "reason": "连不上服务器，检查一下网络", "account_id": ""}
	if ec == "otp_expired" or code == 403:
		return {"ok": false, "reason": "验证码不对，或者已经过期了（重新发一次）", "account_id": ""}
	return {"ok": false, "reason": "验证失败（%d）" % code, "account_id": ""}


## ★★补绑专用: 验码成功之后，**还要问一句「这是不是同一个号」**。
##   不等 ⇒ 服务端新建了账号 ⇒ 接受它就是把玩家的赛季身份换掉（排名/战绩/鬼影全断）。
##   宁可报失败让人重来，也不能静默换号。
static func bind_accepts(res: Dictionary, current_account: String) -> Dictionary:
	if not bool(res.get("ok", false)):
		return {"ok": false, "reason": str(res.get("reason", "验证失败"))}
	var got := str(res.get("account_id", ""))
	if current_account == "":
		## ★同上: 登录墙之后「先开一局」是做不到的事, 不许再这么写(verify_login_wall ③ 守)。
		return {"ok": false, "reason": "本机还没有账号（正在连服务器），过两秒重新发一次验证码"}
	if got != current_account:
		return {"ok": false,
			"reason": "服务器返回的是另一个账号，没有绑成功（没动你的进度）"}
	return {"ok": true, "reason": ""}


## 换设备取回: 返回的 id **本来就和本机当前的不同** —— 那正是要换过去的那个。
## ⚠ 这里**只换身份**，不动本机存档 —— 服务端压根没存存档（见本节顶部长注释）。
static func recover_accepts(res: Dictionary) -> Dictionary:
	if not bool(res.get("ok", false)):
		return {"ok": false, "reason": str(res.get("reason", "验证失败"))}
	if str(res.get("account_id", "")) == "":
		return {"ok": false, "reason": "服务器没给账号，取回失败"}
	return {"ok": true, "reason": ""}


# ── 异步入口 ────────────────────────────────────────────────

## 第一步: 发码。`flow` = FLOW_BIND(补绑) 或 FLOW_RECOVER(换设备)。
static func send_code_async(email: String, flow: String) -> void:
	if not enabled():
		_email_state = EM_ERR
		_email_msg = "还没接后端"
		return
	var e := email.strip_edges()
	if not email_looks_valid(e):
		_email_state = EM_ERR
		_email_msg = "邮箱格式不对，再看一眼"
		return
	if flow == FLOW_BIND and _token == "":
		## ★★别教玩家「先联网开一局」—— v0.19.440 的登录墙就是**开局前**那一屏,
		##   他根本没法先开一局(实测: 全新安装点「发验证码」就撞这句,
		##   `tests/_probe_wall_deadlock.gd`)。
		##   这一步真实的情况只有一种: 身份还在路上(建匿名会话是一次 HTTP 往返)。
		## ⇒ ①自己踢一脚把它建起来(幂等, 已经在飞就什么都不做)
		##   ②照实说「在连」并让他重试 —— 连不上也照实说, 因为那时确实打不开游戏。
		ensure_signed_in_async()
		_email_state = EM_ERR
		_email_msg = "正在连服务器，过两秒再点一次（一直这样就是连不上，检查下网络）"
		return
	_email_state = EM_SENDING
	_email_msg = ""
	_email_pending = e
	_email_flow = flow
	var n = _spawn()
	if n != null:
		n.send_code(e, flow)


## 第二步: 验码。
static func verify_code_async(code_text: String) -> void:
	if not enabled() or _email_pending == "":
		return
	var c := code_text.strip_edges()
	if c == "":
		_email_state = EM_ERR
		_email_msg = "把邮件里那串数字填进来"
		return
	_email_state = EM_VERIFYING
	_email_msg = ""
	var n = _spawn()
	if n != null:
		n.verify_code(_email_pending, c, _email_flow)


func send_code(email: String, flow: String) -> void:
	if not enabled():
		_bye()
		return
	## 补绑走 `PUT /auth/v1/user`（**升级**现有匿名号，同一个 id）；
	## 换设备走 `POST /auth/v1/otp`（拿邮箱换一次登录）。**两条路不能互换**：
	## 拿 `/otp` 去"绑定"会新开一个号，玩家的赛季身份当场断掉。
	var bind: bool = (flow == FLOW_BIND)
	var url := base_url().rstrip("/") + ("/auth/v1/user" if bind else "/auth/v1/otp")
	## ★★取回时带 `create_user: false`: 不带的话, 打错一个字母的邮箱会被服务端当成
	##   **新用户注册**, 验码之后玩家以为取回了, 实际换成了一个空号。
	##   实测(2026-09-22): 没注册过的邮箱 + create_user:false → 422 `otp_disabled`,
	##   服务端直接拒、**不发信**(不耗那每小时 2 封的配额)。
	var body: Dictionary = {"email": email} if bind else {"email": email, "create_user": false}
	_http(("PUT" if bind else "POST"), url, JSON.stringify(body),
		func(res):
			var r := send_code_result(bool(res.get("ok", false)),
				int(res.get("code", 0)), str(res.get("body", "")))
			if bool(r["ok"]):
				_email_state = EM_SENT
				_email_msg = "验证码发到 %s 了，查收一下（也看看垃圾邮件）" % email
			else:
				_email_state = EM_ERR
				_email_msg = str(r["reason"])
			_bye(),
		"Content-Type: application/json")


func verify_code(email: String, code_text: String, flow: String) -> void:
	if not enabled():
		_bye()
		return
	var bind: bool = (flow == FLOW_BIND)
	## `type`: 补绑是**改邮箱**(`email_change`)，换设备是**用邮箱登录**(`email`)。
	## 填错的话服务端会以 `otp_expired` 拒掉 —— 看起来像"码不对"，极难查。
	var payload := {"email": email, "token": code_text,
		"type": ("email_change" if bind else "email")}
	var url := base_url().rstrip("/") + "/auth/v1/verify"
	_http("POST", url, JSON.stringify(payload),
		func(res):
			_apply_verify(bool(res.get("ok", false)), int(res.get("code", 0)),
				str(res.get("body", "")), flow)
			_bye(),
		"Content-Type: application/json")


## 验码回包 → 落地。抽成静态是为了**门禁能不碰网络就把两条流程各喂一遍**。
static func _apply_verify(ok: bool, code: int, body: String, flow: String) -> bool:
	var res := verify_code_result(ok, code, body)
	var gs = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/GameState") if Engine.get_main_loop() != null else null
	var cur := str(gs.account_id) if gs != null else ""
	var v := bind_accepts(res, cur) if flow == FLOW_BIND else recover_accepts(res)
	if not bool(v["ok"]):
		_email_state = EM_ERR
		_email_msg = str(v["reason"])
		return false
	var acc := account_from_auth_response(ok, code, body)
	if str(acc.get("email", "")) == "":
		acc["email"] = _email_pending
	_store_session(acc)
	_email_state = EM_OK
	_email_msg = ("邮箱绑好了" if flow == FLOW_BIND else "账号取回来了")
	## D-8: 补绑那一刻立刻推一次(云端还没有这个号的存档);
	##   取回则把那个号的云存档拉下来整体替换(替换前先备份)。
	if flow == FLOW_BIND:
		_save_dirty = true
		maybe_push_save(true)
	else:
		pull_save_async("recover")
	return true



# ═════════════════════════════════════════════════════════════
# D-8 存档同步 (2026-09-21 用户「需要存档同步的」)
# ═════════════════════════════════════════════════════════════
## ★为什么要做: D-3b 核实出服务端五张表没有一张存玩家存档 ⇒ 绑邮箱只能找回账号,
##   找不回龟和装备。玩家说「绑定邮箱」时期待的是后者。
##
## ★★判新旧**只看版本号**(`cloud_rev` ↔ 服务端 `save_rev`), 不看时间戳 —— 设备时钟不可信。
##   推送走服务端函数 `push_save`: 云端版本 ≠ 我上次见到的 ⇒ **拒绝并返回冲突**,
##   不覆盖。这一步在服务端原子完成, 客户端绕不过去(表上没给直接写的策略)。
##
## ★**只有绑了邮箱的号才同步**。匿名 = 本机, 也不存一堆永远取不回的数据。
## ★推送挂在 `GameState.save()` 上(标脏)+ 20 秒节拍, 而不是逐个挂「打完一局 / 买东西 /
##   换装备」—— 逐个挂必然漏一个(memory「手抄的副本必然落后」)。
## ★内容没变(哈希相同)不推: `save()` 被调得很勤(滑条松手也调), 不能每次都打服务器。

static var _save_dirty: bool = false
static var _save_inflight: bool = false
static var _last_pushed_hash: String = ""
## -1 = 没冲突; >= 0 = 冲突时云端的当前版本号(二选一要用)
static var _save_conflict_rev: int = -1
static var _saves_pushed: int = 0
## 最近一次拉取的结果: "" 没拉过 / "pulling" / "applied" / "empty" / "err"
static var _pull_state: String = ""


static func note_save_dirty() -> void:
	_save_dirty = true


static func save_conflict() -> bool:
	return _save_conflict_rev >= 0


static func saves_pushed() -> int:
	return _saves_pushed


static func pull_state() -> String:
	return _pull_state


static func _reset_save_sync_for_test() -> void:
	_save_dirty = false
	_save_inflight = false
	_last_pushed_hash = ""
	_save_conflict_rev = -1
	_saves_pushed = 0
	_pull_state = ""


## 这个号现在该不该同步存档。★四个条件缺一不可, 缺了就**什么都不发**。
static func sync_allowed(account_id: String, email: String, token: String) -> bool:
	return enabled() and account_id != "" and email != "" and token != ""


static func payload_hash(p: Dictionary) -> String:
	## ★`JSON.stringify(p, "", true)` 第三个参数 = 按键排序 —— 同一份内容键序不同也得同一个哈希,
	##   否则「没变却每 20 秒推一次」。
	return JSON.stringify(p, "", true).sha256_text()


## 纯函数: `push_save` 回包 → {kind, rev}。kind ∈ ok / conflict / net。
## ★服务端函数返回的是 `{"ok": bool, "rev": N, "reason": "..."}`(schema.sql 里写死的形状)。
##   **只有 reason == "conflict" 才算冲突**; 其余失败(没登录 / 太大 / 连不上 / 5xx /
##   看不懂)一律当网络问题 —— 冲突会让玩家二选一, 误判成冲突比多等一拍糟糕得多。
static func push_result(ok: bool, code: int, body: String) -> Dictionary:
	if not (ok and code >= 200 and code < 300):
		return {"kind": "net", "rev": -1}
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Dictionary):
		return {"kind": "net", "rev": -1}
	var d: Dictionary = j.data
	if bool(d.get("ok", false)):
		return {"kind": "ok", "rev": int(d.get("rev", -1))}
	if str(d.get("reason", "")) == "conflict":
		return {"kind": "conflict", "rev": int(d.get("rev", 0))}
	return {"kind": "net", "rev": -1}


## 纯函数: `GET /saves` 回包 → {kind, payload, rev}。kind ∈ found / empty / net。
## ★`empty` 与 `net` 要分开: 「云端没有这个号的存档」是一个**确定的答案**(该把本机的推上去),
##   「没拿到回包」不是 —— 把 net 当 empty 的话, 断网那一下会用本机的**覆盖**云端。
static func pull_result(ok: bool, code: int, body: String) -> Dictionary:
	if not (ok and code >= 200 and code < 300):
		return {"kind": "net", "payload": {}, "rev": -1}
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Array):
		return {"kind": "net", "payload": {}, "rev": -1}
	var rows: Array = j.data
	if rows.is_empty():
		return {"kind": "empty", "payload": {}, "rev": 0}
	var row = rows[0]
	if not (row is Dictionary) or not ((row as Dictionary).get("payload", null) is Dictionary):
		return {"kind": "net", "payload": {}, "rev": -1}
	return {"kind": "found", "payload": (row as Dictionary)["payload"],
		"rev": int((row as Dictionary).get("save_rev", 0))}


static func _gs():
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/GameState") if Engine.get_main_loop() != null else null


## 节拍器每 20 秒调一次; 切后台 / 关窗口时 `force = true` 立刻调。
static func maybe_push_save(force: bool = false) -> void:
	var gs = _gs()
	if gs == null or _save_inflight or save_conflict() or _pull_state == "pulling":
		return
	if not (_save_dirty or force):
		return
	if not sync_allowed(str(gs.account_id), str(gs.account_email), _token):
		return
	var p: Dictionary = gs.cloud_payload()
	var h := payload_hash(p)
	if h == _last_pushed_hash:
		_save_dirty = false
		return
	var n = _spawn()
	if n != null:
		_save_inflight = true
		n.push_save(p, int(gs.cloud_rev), h)


func push_save(p: Dictionary, expected_rev: int, h: String) -> void:
	if not enabled():
		_save_inflight = false
		_bye()
		return
	var url := base_url().rstrip("/") + "/rest/v1/rpc/push_save"
	var body := JSON.stringify({"p_payload": p, "p_expected_rev": expected_rev,
		"p_client_version": str(ProjectSettings.get_setting("application/config/version", ""))})
	_http("POST", url, body,
		func(res):
			apply_push_response(bool(res.get("ok", false)), int(res.get("code", 0)),
				str(res.get("body", "")), h)
			_bye(),
		"Content-Type: application/json")


static func apply_push_response(ok: bool, code: int, body: String, h: String) -> String:
	_save_inflight = false
	var r := push_result(ok, code, body)
	var gs = _gs()
	match str(r["kind"]):
		"ok":
			_saves_pushed += 1
			_last_pushed_hash = h
			_save_dirty = false
			if gs != null:
				gs.cloud_rev = int(r["rev"])
				gs.save()           # 只为把 cloud_rev 落盘; 它不在云存档里, 所以下一拍哈希不变、不会再推
		"conflict":
			## ★停推, 等玩家二选一。**不自动选** —— 两边都可能是玩家想要的那份进度。
			_save_conflict_rev = int(r["rev"])
			print("[SupabaseNet] 存档冲突: 云端是第 %d 版, 本机上次对上的是第 %d 版" % [
				int(r["rev"]), int(gs.cloud_rev) if gs != null else -1])
		_:
			print("[SupabaseNet] 存档没推上去(code=%d), 下一拍再试" % code)
	return str(r["kind"])


## 去拉云端存档。`tag` 写进备份文件名(recover / conflict)。
static func pull_save_async(tag: String) -> void:
	var gs = _gs()
	if gs == null or not sync_allowed(str(gs.account_id), str(gs.account_email), _token):
		return
	var n = _spawn()
	if n != null:
		_pull_state = "pulling"
		n.pull_save(str(gs.account_id), tag)


func pull_save(account_id: String, tag: String) -> void:
	if not enabled():
		_pull_state = "err"
		_bye()
		return
	var url := base_url().rstrip("/") + "/rest/v1/saves?select=payload,save_rev&account_id=eq." \
		+ account_id.uri_encode()
	_http("GET", url, "",
		func(res):
			apply_pull_save(bool(res.get("ok", false)), int(res.get("code", 0)),
				str(res.get("body", "")), tag)
			_bye())


## 拉回来之后落地。返回 kind。
##   · found ⇒ **先备份本机**, 再整体替换; 冲突解除
##   · empty ⇒ 云端还没有这个号的存档 ⇒ 版本号归 0, 把本机的推上去
##   · net   ⇒ 什么都不动(**绝不**当成 empty —— 那会用本机的覆盖云端)
static func apply_pull_save(ok: bool, code: int, body: String, tag: String) -> String:
	var r := pull_result(ok, code, body)
	var gs = _gs()
	var kind := str(r["kind"])
	match kind:
		"found":
			if gs != null:
				gs.backup_save(tag)
				gs.apply_cloud_payload(r["payload"], int(r["rev"]))
				_last_pushed_hash = payload_hash(gs.cloud_payload())
			_save_conflict_rev = -1
			_save_dirty = false
			_pull_state = "applied"
		"empty":
			if gs != null:
				gs.cloud_rev = 0
			_save_conflict_rev = -1
			_save_dirty = true
			_pull_state = "empty"
		_:
			_pull_state = "err"
			print("[SupabaseNet] 云存档没拉下来(code=%d), 本机存档没动" % code)
	return kind


## 冲突二选一 ①: 用云端的(本机上次同步之后的进度会被换掉, 换之前先备份)。
static func resolve_conflict_use_cloud() -> void:
	pull_save_async("conflict")


## 冲突二选一 ②: 用这台的覆盖云端(另一台设备上的进度会被覆盖)。
## ★拿冲突时服务端告诉我们的那个版本号当 expected —— 等于明确说「我知道云端是第 N 版, 就要覆盖它」。
##   这之间要是**又**有别的设备推了, 服务端会再报一次冲突, 不会误覆盖。
static func resolve_conflict_use_local() -> void:
	var gs = _gs()
	if gs == null or not save_conflict():
		return
	gs.cloud_rev = _save_conflict_rev
	_save_conflict_rev = -1
	_last_pushed_hash = ""
	_save_dirty = true
	maybe_push_save(true)


func sign_in_anonymous() -> void:
	if not enabled():
		## ★★**请求没发出去就必须把闸放开**(2026-09-28 穷举同族时抓到)。
		##   `_auth_inflight` 是调用方 `ensure_signed_in_async` **进门之前**就置上的,
		##   而这条早退原来不清它 ⇒ 一旦走到, `_auth_inflight` **永久为真**
		##   ⇒ 之后每一次 `ensure_signed_in_async` 都在第一行 return ⇒ **这个进程再也拿不到 token**
		##   ⇒ 存档不同步 / 周日看不到分组(且屏幕只会说「连不上」, 因为它确实连不上了)。
		##   旁证: 同文件 `refresh_session` 的同一条早退**是**清的 —— 两份手抄的副本漏了一份。
		## ★门禁: `tests/verify_notoken_finals.gd` ⑤(拿掉这一行, 那一条当场红)。
		_auth_inflight = false
		_bye()
		return
	var url := base_url().rstrip("/") + "/auth/v1/signup"
	_http("POST", url, "{}", func(res):
		_auth_inflight = false
		apply_auth_response(
			bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", "")))
		_bye())


## 只给门禁用: 把状态清回初始。★产品代码不许调 —— 状态应当只由 `apply_status_response` 改。
static func _reset_for_test() -> void:
	_state = ST_UNKNOWN
	_notice = ""
	_asked = 0
	_min_client = ""
	_update_hinted = false


# ─────────────────────────────────────────────────────────────
# E15 最低客户端版本(母方案书 §8.5 E15「客户端版本旧于服务端」)
#   服务端 `service_status.min_client_version`(schema.sql §5)早就有了, 客户端原来一直不读。
#   ★只**提示**、不拦: 方案书 E15 写的是「无设计」, 没有任何一处拍板过「旧版本不许打」;
#     拦人是另一个决定(还要配商店跳转与停服文案), 不由这一层顺手做掉。
# ─────────────────────────────────────────────────────────────
## 服务端要求的最低版本("" = 还没问到 / 没要求)。
static var _min_client: String = ""
## 本进程已经提示过一次了(主菜单每秒轮询一次, 不能每秒弹一句)。
static var _update_hinted := false
const UPDATE_HINT := "有新版本，请更新"


## 纯函数: 版本串 a 是否**严格低于** b。按「.」分段逐段比**整数**(0.19.10 > 0.19.9),
##   段数不同时缺的段当 0(0.19 == 0.19.0)。任何一段不是纯数字 ⇒ 判 false(看不懂就不提示, 不吓人)。
static func version_less(a: String, b: String) -> bool:
	var pa := a.strip_edges().split(".")
	var pb := b.strip_edges().split(".")
	for p in pa + pb:
		if not (p as String).is_valid_int() or int(p) < 0:
			return false
	for i in range(maxi(pa.size(), pb.size())):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x < y
	return false


## 该不该提示「有新版本」。没配后端 / 没问到 / 服务端没要求 ⇒ false。
static func update_available() -> bool:
	return enabled() and _min_client != "" and version_less(str(ProjectSettings.get_setting("application/config/version", "")), _min_client)


## 主菜单轮询用: 该提示且本进程还没提示过 ⇒ true(并记下已提示)。
static func take_update_hint() -> bool:
	if _update_hinted or not update_available():
		return false
	_update_hinted = true
	return true


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
	## E15: 同一行里顺手带回「最低客户端版本」(列缺失 / null ⇒ "", 当作没要求)。
	var mv = (row as Dictionary).get("min_client_version", "")
	var minv := str(mv) if mv is String else ""
	if bool(m):
		return {"state": ST_MAINTENANCE, "notice": str((row as Dictionary).get("notice", "")), "min": minv}
	return {"state": ST_OK, "notice": "", "min": minv}


## 把一次回包应用到全局状态上。返回新状态。
static func apply_status_response(ok: bool, code: int, body: String) -> String:
	var r := state_from_response(ok, code, body)
	_state = str(r["state"])
	_notice = str(r["notice"])
	## ★问不到时**保留上一次问到的**最低版本(不把「不知道」说成「没要求」, 也不凭空提示)。
	if r.has("min"):
		_min_client = str(r["min"])
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
	## ★只给门禁用: 让真入口(`ensure_signed_in_async` 等)自己 spawn 的节点也走注入的传输,
	##   这样门禁量的是**真实发出去的请求**(方法/地址/请求头/正文), 不是我插的计数器。
	if _transport_for_test.is_valid():
		n._transport = _transport_for_test
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


## ══════════════════════════════════════════════════════════════════════
##  【时间穿越期间不写服务器】(2026-10-04) —— 全仓所有 Supabase 请求的唯一出口就是下面这个 `_http`
## ══════════════════════════════════════════════════════════════════════
## ★为什么: iOS 测试包是 `--export-debug`(`ios-build.yml:66`) ⇒ 测试者手上的包**有**时间穿越,
##   而它连的是**正式服**。假周六打完一局 = 往生产快照池/决赛表写一行带假相位的真数据,
##   别的真玩家会匹配到它、`finals_seat` 会把它当真分组。
## ★拦在**出口**, 不在每个写入口前面各加一个 if —— 漏一个就是一条生产写入, 而写入口还会继续加。
## ★只拦写: 读(拉对手 / 排行榜 / `finals_view` / 服务状态 / 回读)照常发。
##   身份(`/auth/v1/`: 匿名登录 / 续期 / 邮箱验证码)也照常 —— 那与时间无关, 拦了连读都读不了。
## ★被拦下的请求回 `{ok:false, code:0, blocked:true}` —— 与「没网」同形状 ⇒ 每条上传路径原本就把它
##   当成「还没发出去」留着(快照/回放队列不销单、存档保持 dirty、决赛报名/战报不记成功),
##   回到真实时间后照常补发。快照队列另外认 `BLOCKED_CODE`, 不为这次「没发」记退避。
## 判定成「读」的 RPC。★白名单而不是黑名单: 新加的 RPC 默认算写(漏登记的代价是假时间里读不到, 不是写进生产)。
##   ⚠ `finals_opponent` **不是**读 —— 它往 `finals_scout` 插一行(每人每轮只能问一个种子), 所以不在这里。
const READ_RPCS := ["finals_view"]
## 快照上传被时间穿越拦下时交给回调的 code(区别于没网的 0)。
const BLOCKED_CODE := -1
## 本进程里被拦下的写请求条数(观测量 / 门禁分母)。
static var travel_blocked_count: int = 0

## 纯函数: 这个请求会不会**写**服务器。
static func is_write_request(method: String, url: String) -> bool:
	if method.to_upper() == "GET":
		return false
	if url.find("/auth/v1/") >= 0:
		return false
	var i := url.find("/rest/v1/rpc/")
	if i >= 0:
		var rpc := url.substr(i + "/rest/v1/rpc/".length()).split("?")[0]
		return not READ_RPCS.has(rpc)
	return true

## 时间穿越中 + 写请求 ⇒ 不发。
static func travel_blocks(method: String, url: String) -> bool:
	return _P2S.travel_active() and is_write_request(method, url)


func _http(method: String, url: String, body: String, cb: Callable, extra: String = "") -> void:
	if travel_blocks(method, url):
		travel_blocked_count += 1
		print("[SupabaseNet] 测试时间中, 写请求不发(回到真实时间后补): %s %s" % [method, url.get_slice("?", 0)])
		cb.call({"ok": false, "code": 0, "body": "", "blocked": true})
		return
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


## ★★★2026-09-28 **这张表里原来没有 `PUT`**, 而绑定邮箱走的正是 `PUT /auth/v1/user`
##   ⇒ 它掉进 `_: return METHOD_GET`, 被**悄悄降级成 GET**。
## ★为什么这个 bug 能一直活着、而且全链路看起来都正常:
##   `GET /auth/v1/user` 是**合法端点**(返回当前用户) ⇒ 服务端回 **200**,
##   但它**把请求体整个忽略** ⇒ 不改邮箱、不发信。
##   而 `send_code_result` 只看状态码, 2xx 即判成功 ⇒ 屏幕报「验证码发到 X 了」。
##   **于是: 服务端没撒谎(GET 本来就该这样), 客户端也没写错(2xx 就是成功),
##   错的是这一行把 PUT 变成了 GET。玩家侧的表现是「点了没反应、永远收不到码」。**
## ★实测证据(2026-09-28, 逐条走真网络):
##   · 手写 `METHOD_PUT` 的请求 ⇒ 回包带 `new_email` + `email_change_sent_at`, Gmail 真发出去
##   · 走本函数的请求(N=3) ⇒ 回包**没有** `new_email`, Gmail 发件记录里一封都没有
##   · 两者的方法/地址/四个请求头/正文**逐字相同** —— 唯一差别就是这里
## ★它为什么没被 grep 发现: 调用处是 `_http(("PUT" if bind else "POST"), …)` ——
##   **方法是动态拼的**, 按字面量搜 `_http("PUT"` 一个都搜不到。
## ★★兜底从 `METHOD_GET` 改成**出声**: 静默兜底正是这个 bug 的藏身处 ——
##   一个拼错的方法名会变成一次「成功的 GET」, 而不是一次看得见的失败。
static func _method_of(m: String) -> int:
	match m.to_upper():
		"GET": return HTTPClient.METHOD_GET
		"POST": return HTTPClient.METHOD_POST
		"PUT": return HTTPClient.METHOD_PUT
		"PATCH": return HTTPClient.METHOD_PATCH
		"DELETE": return HTTPClient.METHOD_DELETE
		_:
			push_error("[Supabase] 不认识的 HTTP 方法 %s —— 退回 GET(这会静默丢掉请求体)" % m)
			return HTTPClient.METHOD_GET


func _bye() -> void:
	if _autofree:
		queue_free()


## ─────────────────────────────────────────────────────────────
## 周日决赛日: 去服务端问「我那个桶现在什么样」
##
## ★★**对阵规则不在服务端。** 它只给三件事: 桶里几个人 / 现在第几轮 / 哪几场谁赢了。
##   「谁打谁 / 谁轮空 / 打几轮」全部由本机 `bracket.gd` 算 —— 同一判据存两份必然漂。
## ★★**不剧透靠"拿不到"**: 服务端的 `finals_view` 只下发 round < 当前轮 的结果,
##   当前轮的胜负**根本不在回包里**。客户端这边没有任何"拿到了但不显示"的逻辑 ——
##   那种写法一个渲染 bug 就漏, 而且没人会发现漏了。
## ─────────────────────────────────────────────────────────────
static var _finals_view: Dictionary = {}
static var _finals_inflight := false
## ★「问过一次了没有」。没有它, 屏幕分不清**还没回来**和**回来了但我没桶** ——
##   两种情况该说的话完全不同(「正在连线」vs「本周没有你的桶」)。
static var _finals_tried := false


static func finals_cached() -> Dictionary:
	return _finals_view


static func finals_tried() -> bool:
	return _finals_tried


# ─────────────────────────────────────────────────────────────
# E-B4 对手快照(2026-09-25)
#
# ★为什么要有这条路: 快照一直写在 `finals_entrants.snapshot` 里, 但**没有任何人读得回来**
#   (`finals_view` 不下发它) ⇒ 不在线的对手没法被代打 ⇒ 那一场没人报结果
#   ⇒ `finals_advance` 永远不翻面 ⇒ **整个桶永久卡死**。
#
# ★★这条路**每人每轮只能用一次**(服务端 `finals_scout` 记账, 先到先得)。
#   所以客户端要在**确定对手是谁之后**才问 —— 问错了就浪费掉这一轮唯一的机会。
#   对手由本机 `bracket.gd` 算(对阵规则只有客户端这一份在算)。
# ─────────────────────────────────────────────────────────────
static var _opp: Dictionary = {}
static var _opp_inflight := false
## ★与 `_finals_tried` 同一个道理: 分得清「还没回来」和「回来了但拿不到」。
static var _opp_tried := false


static func opponent_cached() -> Dictionary:
	return _opp


static func opponent_tried() -> bool:
	return _opp_tried


static func opponent_clear() -> void:
	_opp = {}
	_opp_tried = false


## 把 `finals_opponent` 的回包翻译成「能不能打、拿谁打」。**纯函数** ——
## 门禁直接喂一段回包字符串就能验, 不用网络(与 `parse_finals` 同一套做法)。
##
## 回包: {ok:true, seed, name, snapshot} / {ok:false, reason, [seed]}
## 产出: {ok, seed, name, snapshot, reason, asked}
##   · `reason` 原样带出来 —— 屏幕要按它说不同的话(「这一轮你已经看过 3 号了」
##     和「你不在这个桶里」是两回事)
##   · `asked` = 服务端说我这一轮**实际**问过的那个号(只有 already_asked 时才有)。
##     ★它存在的意义: 客户端能拿它和「我算出来的对手」对一下 —— 对不上就说明
##     两边的对阵图算出了不同答案, 那是个该被看见的事故, 不该静默。
static func parse_opponent(ok: bool, code: int, body: String) -> Dictionary:
	if not ok or code < 200 or code >= 300:
		return {"ok": false, "reason": "net"}
	## ★用 `JSON.new().parse()` 而不是 `JSON.parse_string()`: 后者解析失败会往
	##   stderr 喷一条 `ERROR: Parse JSON failed`。这里**本来就要能处理坏正文**
	##   (服务端 5xx 时回的可能是 HTML), 每次都喷一条错等于给日志灌噪声 ——
	##   而门禁是靠扫日志里的错误形态判红的, 噪声多了真错就藏得住。
	var _p := JSON.new()
	if _p.parse(body) != OK or not (_p.data is Dictionary):
		return {"ok": false, "reason": "bad_body"}
	var d: Dictionary = _p.data
	if not bool(d.get("ok", false)):
		var out := {"ok": false, "reason": str(d.get("reason", "?"))}
		if d.has("seed"):
			out["asked"] = int(d.get("seed", -1))
		return out
	## ★空快照要当成**拿不到**, 不是「拿到了一个空阵容」——
	##   后者会让代打打一场 0 人对局, 而且看起来像"对手太弱"。
	var snap = d.get("snapshot", {})
	if not (snap is Dictionary) or (snap as Dictionary).is_empty():
		return {"ok": false, "reason": "empty_snapshot", "seed": int(d.get("seed", -1))}
	return {"ok": true, "seed": int(d.get("seed", -1)),
		"name": str(d.get("name", "")), "snapshot": snap}


static func fetch_opponent_async(week: int, bucket: int, round_no: int, seed: int) -> void:
	var gs = _gs()
	if gs == null or _opp_inflight:
		return
	## ★与报名/看桶同一道闸: 只要「服务端认得出你是谁」。**不是** `sync_allowed`
	##   (那是存档同步的闸, 要绑邮箱 —— 用错会让访客静默打不了, 这个洞犯过一次)。
	## ★★2026-10-04: 没令牌不再直接放弃 —— 交给节点先续期再发(`_await_token`, 最多约 10 秒)。
	##   令牌只活在内存, 冷启动后立刻点进对阵图那几秒是空的; 原来这里标「试过了」就结束, 对手拉不到。
	if str(gs.account_id) == "":
		_opp_tried = true
		return
	var n = _spawn()
	if n != null:
		_opp_inflight = true
		n.fetch_opponent(week, bucket, round_no, seed)


# ─────────────────────────────────────────────────────────────
# E-B6 报结果（2026-09-25）
#
# ★`finals_report` 这个 RPC 从 2026-09-23 就在服务端，而**客户端一个调用者都没有**
#   ⇒ 没有任何一场比赛的结果能被报上去 ⇒ 对阵图永远停在第 1 轮，
#   E-B4 的补判会把每一场都判给 side 0 —— 冠军是一个从没打过的人。
#
# ★★`p_winner_side` 收的是「**哪一侧**赢」(0/1)，不是「谁赢」。
#   算它的是 `BracketMapScene.winner_side_for()`（那里有上半/下半/跨轮的判据）——
#   这一层**不重新算一遍**，只负责发出去。
# ─────────────────────────────────────────────────────────────
static var _report_inflight := false
static var _report_done: Dictionary = {}     # "r-m" → true，本进程报过的场次


## 组包。**纯函数** —— 键名与服务端对不上是这类接口最常见的死法，门禁直接验它。
static func finals_report_body(week: int, bucket: int, round_no: int,
		match_no: int, winner_side: int, seed_used: int) -> Dictionary:
	return {"p_week": week, "p_bucket": bucket, "p_round": round_no,
		"p_match": match_no, "p_winner_side": winner_side, "p_seed": seed_used}


static func finals_reported(round_no: int, match_no: int) -> bool:
	return bool(_report_done.get("%d-%d" % [round_no, match_no], false))


static func finals_report_clear() -> void:
	_report_done.clear()
	_report_inflight = false


static func report_finals_async(week: int, bucket: int, round_no: int,
		match_no: int, winner_side: int, seed_used: int) -> void:
	var gs = _gs()
	if gs == null or _report_inflight:
		return
	## ★`winner_side` 只能是 0/1。`-1` 是 `winner_side_for()` 说的「我没资格报」——
	##   把它发出去服务端会回 `bad_side`，但更要紧的是**这一步就该拦住**：
	##   能发出去就意味着"不是我的场"也能报，那是把老缺口(桶级校验)又放大一格。
	if winner_side != 0 and winner_side != 1:
		return
	## ★与报名/看桶同一道闸：只要「服务端认得出你是谁」。**不是** `sync_allowed`。
	## ★★2026-10-04: 没令牌时交给节点先续期再发(同 fetch_opponent), 不在这里放弃。
	if str(gs.account_id) == "":
		return
	## ★同一场只报一次：服务端是 `on conflict do nothing`（先到先得），
	##   客户端这边再挡一层是为了**不把重复请求当成正常流量**——
	##   结算路径会被重入（投降/重开结算屏），没这道闸就会一场报好几次。
	if finals_reported(round_no, match_no):
		return
	var n = _spawn()
	if n != null:
		_report_inflight = true
		## ★★★**不在这里标「报过了」**。2026-09-27 查实: 原来这一行在请求**发出去之前**
		##   就标上了, 而回调又把回包丢掉(`func(_res)`) ⇒ 网络失败 / 服务端拒绝时
		##   客户端照样认为报过了, 而 `report_finals_if_any` 只在结算时调一次、没有重试
		##   ⇒ 那一场的结果**永远到不了服务端**, 晋级只能靠 960 秒宽限兜,
		##   **可能把错的人送进下一轮**。
		##   —— 与 v0.19.446 修掉的**报名漏报**同一个形状(「发了就不管」)。
		## ⇒ 标记移进**成功**那一支(见 `report_finals` 的回调)。
		n.report_finals(week, bucket, round_no, match_no, winner_side, seed_used)


func report_finals(week: int, bucket: int, round_no: int,
		match_no: int, winner_side: int, seed_used: int) -> void:
	if not enabled() or not await _await_token():
		_report_inflight = false
		_bye()
		return
	_http("POST", base_url().rstrip("/") + "/rest/v1/rpc/finals_report",
		JSON.stringify(finals_report_body(week, bucket, round_no, match_no,
			winner_side, seed_used)),
		func(res):
			_report_inflight = false
			## ★★只有**真报成了**才记账。服务端是 `on conflict do nothing`(先到先得),
			##   所以重复报一次无害, 而**漏报**是会把错的人送进下一轮的。
			##   ⇒ 宁可多报一次, 不可漏一次。
			var code := int(res.get("code", 0))
			if bool(res.get("ok", false)) and code >= 200 and code < 300:
				_report_done["%d-%d" % [round_no, match_no]] = true
			_bye(),
		"Content-Type: application/json")


func fetch_opponent(week: int, bucket: int, round_no: int, seed: int) -> void:
	if not enabled() or not await _await_token():
		_opp_inflight = false
		_opp_tried = true
		_bye()
		return
	var url := base_url().rstrip("/") + "/rest/v1/rpc/finals_opponent"
	var body := JSON.stringify({"p_week": week, "p_bucket": bucket,
		"p_round": round_no, "p_seed": seed})
	_http("POST", url, body,
		func(res):
			_opp_inflight = false
			_opp_tried = true
			_opp = parse_opponent(bool(res.get("ok", false)), int(res.get("code", 0)),
				str(res.get("body", "")))
			_bye(),
		"Content-Type: application/json")


static func finals_clear() -> void:
	_finals_view = {}
	_finals_inflight = false
	_finals_tried = false


static func fetch_finals_async(week: int, bucket: int) -> void:
	var gs = _gs()
	if gs == null or _finals_inflight:
		return
	## ★★**访客(guest)也看得到自己的桶** —— 与报名那道闸同时改(用户 2026-09-24 拍板)。
	##   只改一道就是「能进不能看」或「能看进不去」, 都是半截。
	##   判据是「服务端认得出你是谁」: 服务端 `finals_view` 里 `auth.uid() is null` 也拦,
	##   这里只是省一次白跑。**不是** `sync_allowed`(那是存档同步的闸, 要绑邮箱)。
	if str(gs.account_id) == "" or _token == "":
		## ★标成「问过了」: 这一屏此刻不会有数据了, 屏幕不该永远停在「还在找」(实拍抓到的)。
		_finals_tried = true
		## ★★★**请求一个字节都没发出去 ⇒ 这是「问不到」, 不是「你没这一组」**(2026-09-28)。
		##   原来这里只标 tried、`_finals_view` 留空**且没有 reason** ⇒
		##   `BracketMapScene._empty_kind()` 的前几道判据全躲过(`finals_tried()` 已真 →
		##   reason 不是 UNREACHABLE → reason 不是 too_few) ⇒ 掉到兜底那一档
		##   (「确实没有你这一组 · 周六晋级才进得来」)—— **对一个真打进决赛日的人说谎**
		##   (探针实测: promoted=true / gauntlet_state=in / 闯关赛 4-0, 屏幕照样这么说)。
		## ★为什么不是边角: `_token` **只活在内存、从不落盘**(见本文件 D-3c 那一段)
		##   ⇒ **每次冷启动都是空的**; 而周日主菜单那扇进对阵图的门第一帧就能点,
		##   恢复要等 `BracketMapScene.REFRESH_SEC` ⇒ **最长 30 秒都在说这句假话**。
		## ★这是 2026-09-27 修过的同一个 bug 的另一半: 那次修的是**回包**侧
		##   (「问不到就别抹掉好数据、别说成你没这一组」), **请求侧这一半漏了**。
		##   同族对照: 上面 `fetch_opponent_async` 的同一道闸标 tried 后, `opponent_tip()`
		##   说的是「过两秒再点一次」—— 一条说人话, 只有这条说「你不行」。
		## ⚠ **只在一份好数据都没有时才写**: 2026-09-27 刚焊死「问不到别抹掉上一份好视图」,
		##   两者必须共存 —— 否则周日打到一半 token 过期, 签表会从屏幕上消失。
		## ★门禁: `tests/verify_notoken_finals.gd` ②③④(三条变异全红)。它**不抄屏幕字面量**,
		##   量的是「请求侧这一句必须与回包侧『问不到』那一句完全相同」。
		if _finals_view.is_empty():
			_finals_view = {"reason": UNREACHABLE}
		return
	var n = _spawn()
	if n != null:
		_finals_inflight = true
		n.fetch_finals(week, bucket)


func fetch_finals(week: int, bucket: int) -> void:
	if not enabled():
		_finals_inflight = false
		## ★**防御性, 不是承重**(2026-09-23 反向验证查实): `sync_allowed()` 自己就含
		##   `enabled()`, 所以后端没配时 `fetch_finals_async` 那道闸**先拦住了**,
		##   这一行正常跑不到(把它改坏, 一条断言都不红)。
		##   留着是为两次调用之间环境变了的竞态; 不要拿它当“有人守”。
		_finals_tried = true
		_bye()
		return
	var gs = _gs()
	var mine := str(gs.account_id) if gs != null else ""
	var url := base_url().rstrip("/") + "/rest/v1/rpc/finals_view"
	var body := JSON.stringify({"p_week": week, "p_bucket": bucket})
	_http("POST", url, body,
		func(res):
			_finals_inflight = false
			_finals_tried = true
			var _pv: Dictionary = parse_finals(bool(res.get("ok", false)), int(res.get("code", 0)),
				str(res.get("body", "")), mine, int(Time.get_unix_time_from_system()))
			## ★★★**问不到就别动上一份好数据**。原来一律覆盖 ⇒ 周日打到一半网络抖一下,
			##   签表**从屏幕上消失**, 换成「本周没有你的桶」, 30 秒后才回来。
			##   ⇒ 只有「问到了」才换; 问不到时留着旧的继续画(下一拍会重试)。
			if str(_pv.get("reason", "")) == UNREACHABLE and not _finals_view.is_empty():
				pass
			else:
				_finals_view = _pv
			_bye(),
		"Content-Type: application/json")


## ★把回包翻译成桶地图要的形状。**纯函数** —— 门禁直接喂一段回包字符串就能验,
##   不用网络、不用登录(memory `fb-verify-must-run-the-real-path` 的另一半:
##   网络那半由 `_transport_for_test` 量真请求, 翻译这半在这里量)。
##
## 回包(服务端): {n, round, closed, round_at, next_at, now, entrants:[{seed,name,account_id}], done:{"r-m":side}}
## 屏幕要的:     {size, round, done, names(按种子排), me(我的种子), closed, left, recv_at}
## 「问不到」的统一标记。★做成常量而不是到处写字面量: 产品与门禁读同一处。
const UNREACHABLE := "unreachable"


static func parse_finals(ok: bool, code: int, body: String, my_account: String,
		recv_at: int) -> Dictionary:
	## ★★★「**问不到**」≠「**问到了, 答案是没有**」。
	##   返回裸 `{}` 的话, 屏幕会走到「本周没有你的桶 · 周六闯关赛晋级才进得来」——
	##   **对一个已晋级的人说谎**(2026-09-27 查实)。
	##   本仓 2026-09-25 已经为「有资格但人不够」拆过一次(`too_few`), 这是同一条规矩。
	if not ok or code < 200 or code >= 300:
		return {"reason": UNREACHABLE}
	## ★同 `parse_opponent`: 用 `JSON.new().parse()` 而不是 `JSON.parse_string()` ——
	##   后者解析失败会往 stderr 喷一条 `ERROR: Parse JSON failed`, 而这里**本来就要
	##   能处理坏正文**(5xx 时服务端回的可能是 HTML)。门禁靠扫日志里的错误形态判红,
	##   每次都喷一条等于给日志灌噪声, 真错就藏得住了。
	var _p := JSON.new()
	if _p.parse(body) != OK or not (_p.data is Dictionary):
		## 5xx 时服务端回的可能是 HTML —— 那也是「问不到」, 不是「你没桶」。
		return {"reason": UNREACHABLE}
	if not bool((_p.data as Dictionary).get("ok", false)):
		## ★★2026-09-25「有资格但人不够」要单独带出来, 不能和「没资格」混成一个空字典。
		##   `finals_seat` 对 1 个人**故意不建桶**(一人一桶 = 没有对手的冠军), 于是那个
		##   **确实周六 4 胜晋级了**的人拿到的是「没有你的桶」, 屏幕照它说
		##   「周六闯关赛晋级才进得来」—— 在告诉他一件假事。
		##   ⇒ 只有这一个理由要带出来; 其余(没报名 / 没登录 / 坏正文)照旧回 `{}`,
		##     「屏幕上说人话、不画半张图」那条老判据一字不动。
		##   ★不带 `size` 键 ⇒ `int(v.get("size", 0))` 仍是 0, 画图那侧的判断不受影响。
		## ★2026-10-04: 服务端新增 `not_seated`(本周一个桶都还没有 = 还没到分组时间), 同样要带出来。
		if str((_p.data as Dictionary).get("reason", "")) == "not_seated":
			return {"reason": "not_seated",
				"entered": int((_p.data as Dictionary).get("entered", 0))}
		if str((_p.data as Dictionary).get("reason", "")) == "too_few":
			return {"reason": "too_few",
				"entered": int((_p.data as Dictionary).get("entered", 0))}
		return {}
	return _bucket_from(_p.data, my_account, recv_at)


## 服务端一个组的字典 → 对阵图要的形状。★`finals_view`(我这一组) 与 `finals_week_view`(观赛·本周所有组)
##   **共用这一份** —— 两条路各写一份翻译, 抄一次就永远落后一次(memory fb-hand-rolled-copies-drift)。
static func _bucket_from(d: Dictionary, my_account: String, recv_at: int) -> Dictionary:
	var n := int(d.get("n", 0))
	if n <= 0:
		return {}
	## 名字按**种子**落位(不靠回包的顺序 —— 顺序是服务端的实现细节, 种子才是约定)
	var names: Array = []
	names.resize(n)
	## ★玩家 ID(2026-10-04): 回包本来就带每个人的 account_id ⇒ 在本机现算, 服务端一个字不用改。
	##   算法与设置页那串**同一个**(`_P2S.player_tag`), 所以这里看到的号就是那个人在他自己设置页看到的号。
	var tags: Array = []
	tags.resize(n)
	for i in range(n):
		names[i] = "?"
		tags[i] = ""
	var me := -1
	for e in (d.get("entrants", []) as Array):
		var ed: Dictionary = e if e is Dictionary else {}
		var sd := int(ed.get("seed", -1))
		if sd < 0 or sd >= n:
			continue
		names[sd] = str(ed.get("name", "?"))
		tags[sd] = _P2S.player_tag(str(ed.get("account_id", "")))
		if my_account != "" and str(ed.get("account_id", "")) == my_account:
			me = sd
	## `done` 的值过一遍 int() —— JSON 解出来是浮点, 直接当 side 用会在比较时出错
	## ★★第二道锁(2026-10-04 观赛): 服务端只下发「已翻面」的轮次(`closed or round < 当前轮`),
	##   这里照同一条规矩再筛一遍 —— 观赛把**所有组**的结果都摆到每个人眼前,
	##   服务端哪天写错一行, 漏出去的就不是一个人的一场, 而是全服每一组的当前轮。
	##   对守规矩的回包这一段是空操作(门禁 `verify_bracket_spectate` 两头都量)。
	var rnd := maxi(1, int(d.get("round", 1)))
	var closed := bool(d.get("closed", false))
	var raw_done: Dictionary = d.get("done", {}) if d.get("done", {}) is Dictionary else {}
	var done: Dictionary = {}
	for k in raw_done:
		if not closed and int(str(k).get_slice("-", 0)) >= rnd:
			continue
		done[str(k)] = int(raw_done[k])
	## ★倒计时用**服务端的时间差**, 不用本机绝对时钟 —— 设备时钟不对时倒计时照样准
	var srv_now := int(d.get("now", 0))
	var nxt := int(d.get("next_at", 0))
	var left: int = maxi(0, nxt - srv_now) if (srv_now > 0 and nxt > 0) else -1
	## ★`bucket` 一定要带出来(E-B4): 客户端查桶时传的是 `-1`(「我那个桶」),
	##   **真正的桶号只有回包里有**。而 `finals_opponent` 必须传准确的桶号 ——
	##   没有它就只能再往返一次去问, 那会出现「查到桶号、桶却没了」的中间态
	##   (服务端当初把这两件事并进一次往返, 正是为了避开它)。
	return {"size": n, "round": rnd, "done": done,
		"names": names, "tags": tags, "me": me, "closed": closed,
		"left": left, "recv_at": recv_at, "bucket": int(d.get("bucket", -1)),
		## ★E-B7 备战购物窗要的两个数。**都用服务端的** ——
		##   `round_at` 是本轮开始时刻，`srv_now` 是收包那一刻服务端的钟。
		##   有了这两个，本机只需要算**过了多久**（时间差），不必相信本机的绝对时钟
		##   （与上面 `left` 同一条纪律：本机时钟偏了也不影响，只要它走得不快不慢）。
		"round_at": int(d.get("round_at", 0)), "srv_now": int(d.get("now", 0))}


# ─────────────────────────────────────────────────────────────
# 观赛 · 本周所有组(2026-10-04, 用户「改」)
#
# ★为什么要有这条: `finals_view(week, -1)` 只回「我那个组」; 没晋级的人回 `not_entered`,
#   整个周日只看得到一把锁。原案 D13「观赛四块全做」, 而周日对阵本来就是公开的
#   (`finals_buckets` 的读策略写着「观赛是公开的」)。
# ★服务端 RPC `finals_week_view(p_week)`: 本周每个组的 {bucket, n, round, closed, entrants(seed/name/account_id),
#   done(只含已翻面)}。**不含快照/阵容**。SQL 在 schema.sql 同名函数处。
# ★★没上线时(404 / 函数不存在) 一律当「这条路暂时没有」—— 屏幕退回「未晋级」那一把锁,
#   不报错、不弹窗; 上线那一刻下一次轮询就自动变成观赛, 客户端不用再发版。
# ─────────────────────────────────────────────────────────────
static var _finals_week: Dictionary = {}
static var _finals_week_inflight := false


static func finals_week_cached() -> Dictionary:
	return _finals_week


static func finals_week_clear() -> void:
	_finals_week = {}
	_finals_week_inflight = false


static func fetch_finals_week_async(week: int) -> void:
	var gs = _gs()
	if gs == null or _finals_week_inflight:
		return
	## 闸与 `fetch_finals_async` 同一条: 服务端认得出你是谁才去问(`auth.uid() is null` 它也拦)。
	if str(gs.account_id) == "" or _token == "":
		return
	var n = _spawn()
	if n != null:
		_finals_week_inflight = true
		n.fetch_finals_week(week)


func fetch_finals_week(week: int) -> void:
	if not enabled():
		_finals_week_inflight = false
		_bye()
		return
	var gs = _gs()
	var mine := str(gs.account_id) if gs != null else ""
	_http("POST", base_url().rstrip("/") + "/rest/v1/rpc/finals_week_view",
		JSON.stringify({"p_week": week}),
		func(res):
			_finals_week_inflight = false
			var pw: Dictionary = parse_finals_week(bool(res.get("ok", false)), int(res.get("code", 0)),
				str(res.get("body", "")), mine, int(Time.get_unix_time_from_system()))
			## ★同 `fetch_finals`: 问不到就别抹掉上一份好数据(网络抖一下观赛图不许消失)。
			if pw.has("buckets") or _finals_week.is_empty():
				_finals_week = pw
			_bye(),
		"Content-Type: application/json")


## 回包 → `{"buckets": [与 parse_finals 同形状的组, 按组号排], "srv_now"}`; 拿不到 → `{"reason": ...}`(没有 buckets 键)。
## ★**纯函数**, 门禁直接喂回包字符串。
## ★404 / 函数不存在(服务端还没部署这条 RPC) ⇒ `reason = "unavailable"`, 不是「问不到」——
##   前者不会自己好, 屏幕不该说「每 30 秒再看一次」。
static func parse_finals_week(ok: bool, code: int, body: String, my_account: String,
		recv_at: int) -> Dictionary:
	if code == 404:
		return {"reason": "unavailable"}
	if not ok or code < 200 or code >= 300:
		return {"reason": UNREACHABLE}
	var _p := JSON.new()
	if _p.parse(body) != OK or not (_p.data is Dictionary):
		return {"reason": UNREACHABLE}
	var d: Dictionary = _p.data
	if not bool(d.get("ok", false)):
		return {"reason": str(d.get("reason", "unavailable"))}
	var out: Array = []
	for b in (d.get("buckets", []) if d.get("buckets", []) is Array else []):
		if not (b is Dictionary):
			continue
		var one: Dictionary = _bucket_from(b, my_account, recv_at)
		if int(one.get("size", 0)) > 1:
			out.append(one)
	out.sort_custom(func(x, y): return int(x.get("bucket", 0)) < int(y.get("bucket", 0)))
	return {"buckets": out, "srv_now": int(d.get("now", 0)), "recv_at": recv_at}


## 收到回包时还剩几秒 → 现在还剩几秒。★用的是「收包时剩多少」减「本机过了多久」,
##   两个都是**时间差**, 所以本机时钟偏了也不影响(只要它走得不快不慢)。
static func finals_left(now_local: int) -> int:
	var v := _finals_view
	if v.is_empty() or int(v.get("left", -1)) < 0:
		return -1
	return maxi(0, int(v["left"]) - (now_local - int(v.get("recv_at", now_local))))


## 现在**服务端**的钟大概是几点。= 收包时服务端说的时刻 + 本机从那时起过了多久。
## ★★为什么不直接用本机时钟: 备战购物窗是**全桶同步**的事，
##   本机时钟偏 10 分钟的人会比别人早关窗或晚关窗，而他自己一点都察觉不到。
##   这里只用**时间差**（本机走得不快不慢就够），绝对时刻一律听服务端的。
static func finals_srv_now(now_local: int) -> int:
	var v := _finals_view
	if v.is_empty() or int(v.get("srv_now", 0)) <= 0:
		return 0
	return int(v["srv_now"]) + (now_local - int(v.get("recv_at", now_local)))


## 备战购物窗现在开着吗 / 还剩几秒。★判据本身在 `phase2_config.finals_shop_open()`
##   （纯函数、门禁穷举过），这一层只负责**把两个时刻凑齐**，不重写规则。
static func finals_shop_open_now(now_local: int) -> bool:
	var v := _finals_view
	if v.is_empty():
		return false
	return _P2S.finals_shop_open(int(v.get("round_at", 0)), finals_srv_now(now_local))


static func finals_shop_left_now(now_local: int) -> int:
	var v := _finals_view
	if v.is_empty():
		return 0
	return _P2S.finals_shop_left(int(v.get("round_at", 0)), finals_srv_now(now_local))


## ─────────────────────────────────────────────────────────────
## 周日决赛日: 报到(周六晋级的人把自己 + 阵容快照交给服务端)
## ★服务端 `finals_enter` 是 **upsert**: 每场都报没坏处, 还顺带让阵容与战绩保持最新。
## ★晋级线在**服务端**判 —— 客户端说"我晋级了"这句话本身不作数。
## ─────────────────────────────────────────────────────────────
static var _enter_inflight := false


## 组包。★纯函数 ⇒ 门禁直接比对字段, 不用网络。
static func finals_enter_body(week: int, name: String, snapshot: Dictionary,
		gw: int, gl: int) -> Dictionary:
	return {"p_week": week, "p_name": name, "p_snapshot": snapshot,
		"p_gw": gw, "p_gl": gl}


static func enter_finals_async(week: int, name: String, snapshot: Dictionary,
		gw: int, gl: int) -> void:
	var gs = _gs()
	if gs == null or _enter_inflight:
		return
	## ★★**访客(guest)也能报名** —— 用户 2026-09-24 拍板「guest 应该也能打周六周日」。
	##   ⚠ 这里**不能**用 `sync_allowed()`: 那是**存档同步**的闸(要绑邮箱 ——
	##     「匿名号一个字节都不往云上推」是隐私承诺)。我接线时用错了闸,
	##     后果是**匿名号周六赢了、周日静默进不去**: 人打赢了, 什么提示都没有。
	##   ★决赛日真正需要的只有「服务端认得出你是谁」: 匿名号在 Supabase 里有
	##     **真的 auth.users 行 + token**, `finals_enter` 里的 `auth.uid()` 照样成立。
	##   ★名字: 访客没昵称 ⇒ 对阵图上显示确定性兜底短码(见 `player_display_name`)。
	##   ★参考 Super Auto Pets(2026-09-24 查): 它**不靠权限分层**, 靠**可靠性分层** ——
	##     guest 什么都能玩, 但官方明说 unverified; 有真实事故: 崩溃后 guest 被换成新号,
	##     原进度再也拿不回来。⇒ 该防的不是"让不让 guest 打", 是"guest 的身份会不会丢"。
	if str(gs.account_id) == "" or _token == "":
		return
	var n = _spawn()
	if n != null:
		_enter_inflight = true
		n.enter_finals(finals_enter_body(week, name, snapshot, gw, gl))


## 纯函数: 一次「报名」回包 → 这一周算不算报上了。
## ★`already_seated` 也算**没报上**(桶已经切了而我不在里面 ⇒ 补报也进不去了),
##   它与「网络失败」要分开: 前者不该再重试, 后者该。
static func finals_enter_ok(ok: bool, code: int, body: String) -> bool:
	if not ok or code < 200 or code >= 300:
		return false
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Dictionary):
		return false
	return bool((j.data as Dictionary).get("ok", false))


## 这一周报名已经**确认成功**了吗。
static func finals_entered(week: int) -> bool:
	var gs = _gs()
	return gs != null and week > 0 and int(gs.finals_entered_week) == week


func enter_finals(body: Dictionary) -> void:
	if not enabled():
		_enter_inflight = false
		_bye()
		return
	var wk: int = int(body.get("p_week", 0))
	_http("POST", base_url().rstrip("/") + "/rest/v1/rpc/finals_enter",
		JSON.stringify(body),
		func(res):
			_enter_inflight = false
			## ★★把结果记下来 —— 原来这里什么都不做(发了就不管), 于是
			##   「周六第 4 胜那一刻网络抖一下」= 周日静默进不去、且无从自救。
			##   见 `GameState.finals_entered_week` 的长注释。
			if finals_enter_ok(bool(res.get("ok", false)), int(res.get("code", 0)),
					str(res.get("body", ""))):
				var gs2 = _gs()
				if gs2 != null and wk > 0:
					gs2.finals_entered_week = wk
					gs2.save()
			_bye(),
		"Content-Type: application/json")


# ═════════════════════════════════════════════════════════════
# 跨设备回放 S2(2026-10-04): 一局录像写进 `matches`, **回读确认**才算传成
#   方案书 docs/plans/20261003-跨设备回放.md §4.6 / V7。队列与重试在
#   `scripts/systems/replay/replay_uploader.gd`; 这里只管「发 + 回读」这一次。
# ═════════════════════════════════════════════════════════════

## `match_id` 只认 uuid 的形状 —— 它要拼进回读的查询串, 别的字符一律不放行。
static func is_uuid(s: String) -> bool:
	var re := RegEx.new()
	re.compile("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
	return re.search(s) != null


## 纯函数: 回读那一行要问的查询串。★连 `replay` 一起取回来 —— 判据是「服务端那一份
##   与我发的逐字相同」, 不只是「有这么一行」(被截断的录像回读得到, 但播不了)。
static func match_readback_query(match_id: String) -> String:
	if not is_uuid(match_id):
		return ""
	return "match_id=eq.%s&select=match_id,replay" % match_id


## 纯函数: 回读回包 → 这一行**真的在服务端、且录像逐字相同**吗。
## ★★这是销单的唯一判据(memory fb-200-ok-is-not-it-happened): 插入那一下回 201 不算 ——
##   RLS 拒掉、`return=minimal` 吞掉、代理改写 body(memory fb-local-proxy-corrupts-post-body)
##   都可能「回 2xx 而那一行不在」。
static func match_confirmed(ok: bool, code: int, body: String, match_id: String, replay_b64: String) -> bool:
	if not ok or code < 200 or code >= 300 or match_id == "" or replay_b64 == "":
		return false
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Array):
		return false
	for r in (j.data as Array):
		if r is Dictionary and str((r as Dictionary).get("match_id", "")) == match_id \
				and str((r as Dictionary).get("replay", "")) == replay_b64:
			return true
	return false


## 发一行录像。返回 false = 连节点都没建(没配后端 / 行不完整), 调用方别把它记成「在路上」。
## `done.call(match_id: String, confirmed: bool)` —— **每一条走掉的路都会回调一次**。
static func upload_match_async(row: Dictionary, done: Callable) -> bool:
	if not enabled() or not is_uuid(str(row.get("match_id", ""))) or str(row.get("replay", "")) == "":
		return false
	var n = _spawn()
	if n == null:
		return false
	n.upload_match(row, done)
	return true


func upload_match(row: Dictionary, done: Callable) -> void:
	var mid := str(row.get("match_id", ""))
	## ★★没有**这个账号的**令牌就不发: 退回公共匿名钥匙去写只会被 RLS 拒(401 / 42501),
	##   而且那是「看起来发过了」的一次空转(见 `_await_token` 头注, 2026-10-04 查实)。
	if not enabled() or not await _await_token():
		print("[SupabaseNet] 录像没传: 拿不到登录令牌(matches)")
		done.call(mid, false)
		_bye()
		return
	var gs = _gs()
	var acc: String = str(gs.account_id) if gs != null else ""
	if acc == "" or str(row.get("left_account", "")) != acc:
		## 行是按「现在这个号」拼的; 拼完到发出之间换了号 ⇒ RLS 必拒, 不发。
		print("[SupabaseNet] 录像没传: 账号对不上(matches)")
		done.call(mid, false)
		_bye()
		return
	var base := base_url().rstrip("/") + "/rest/v1/matches"
	## ★插入的回包**不看**: 2xx 不算数(见 `match_confirmed`); 409(上次其实已经插进去了、
	##   只是回包丢了)也不算失败 —— 两种情况都交给下面那次回读裁决。
	_http("POST", base, JSON.stringify(row),
		func(res):
			_log_upload_fail("matches", res)
			_http("GET", base + "?" + match_readback_query(mid), "",
				func(res2):
					var good := match_confirmed(bool(res2.get("ok", false)), int(res2.get("code", 0)),
						str(res2.get("body", "")), mid, str(row.get("replay", "")))
					if not good:
						print("[SupabaseNet] 录像回读不到(matches) code=%d" % int(res2.get("code", 0)))
					done.call(mid, good)
					_bye()),
		"Prefer: return=minimal")


# ═════════════════════════════════════════════════════════════
# 跨设备回放 S3(2026-10-04): 按 match_id 把那一行的录像**取回来**(看回放用)
#   方案书 docs/plans/20261003-跨设备回放.md S3。拿到之后怎么解、怎么播在
#   `scripts/systems/replay/replay_fetcher.gd`; 这里只管「取 + 判回包」这一次。
# ═════════════════════════════════════════════════════════════

## 取录像的总时限(秒, 墙钟)。★「点了回放之后一直转」是这一屏最怕的形状
##   (memory: 永远显示「正在连线」的那一屏) ⇒ 不论卡在续登录还是卡在请求上, 到点**必定回调一次**。
##   15 = 续登录最多约 10 秒(`_await_token`) + 一次请求的 `TIMEOUT_SEC` 6 秒里留的余量。
const MATCH_FETCH_TIMEOUT_SEC := 15.0
## 只给门禁用: > 0 时替代上面那个(门禁不该真等 15 秒)。
static var match_fetch_timeout_for_test := 0.0


## 纯函数: 取那一行要问的查询串。只要 `replay` 一列 —— 版本号在录像里, 解出来由
##   `ReplayRecorder.play` 统一比(只有一处判据, 不在列上再比一遍)。
static func match_fetch_query(match_id: String) -> String:
	if not is_uuid(match_id):
		return ""
	return "match_id=eq.%s&select=match_id,replay" % match_id


## 纯函数: 一次取回的回包 → {"err": 原因码, "b64": 录像, "code": HTTP 码}。
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
				return {"err": "", "b64": b, "code": code}
			return {"err": "corrupt", "code": code}
	return {"err": "missing", "code": code}


## 取一行录像。返回 false = 连节点都没建(没配后端 / id 不是 uuid), 调用方自己出提示。
## `done.call(res: Dictionary)`(形状同 `parse_fetched_match`, 另有 "no_token" / "timeout")——
##   **每一条走掉的路恰好回调一次**; 调用方已经离场(`done` 失效)就不回调。
static func fetch_match_async(match_id: String, done: Callable) -> bool:
	if not enabled() or not is_uuid(match_id):
		return false
	var n = _spawn()
	if n == null:
		return false
	n.fetch_match(match_id, done)
	return true


func fetch_match(match_id: String, done: Callable) -> void:
	var st := {"done": false}
	var fin := func(res: Dictionary) -> void:
		if bool(st["done"]):
			return
		st["done"] = true
		if done.is_valid():
			done.call(res)
	## ★看门狗挂在**本节点自己身上**(Timer 子节点), 不用 `get_tree().create_timer` ——
	##   后者活得比本节点久, 闭包捕获的东西先没了就喷 Lambda capture(tools/tree_timer_audit.py)。
	var tm := Timer.new()
	tm.one_shot = true
	tm.wait_time = match_fetch_timeout_for_test if match_fetch_timeout_for_test > 0.0 else MATCH_FETCH_TIMEOUT_SEC
	add_child(tm)
	tm.timeout.connect(func() -> void: fin.call({"err": "timeout", "code": 0}))
	tm.start()
	## ★★不拿公共匿名钥匙去读: `matches` 的读策略是 `auth.uid() is not null`,
	##   匿名钥匙读回来是 0 行 ⇒ 会被误报成「服务器上没有这场」(与 S2 上传同一个理由)。
	if not await _await_token():
		fin.call({"err": "no_token", "code": 0})
		_bye()
		return
	if bool(st["done"]):
		_bye()                 # 看门狗已经替它回过话了; 别再发请求
		return
	var url := base_url().rstrip("/") + "/rest/v1/matches?" + match_fetch_query(match_id)
	_http("GET", url, "",
		func(res):
			var r := parse_fetched_match(bool(res.get("ok", false)), int(res.get("code", 0)),
				str(res.get("body", "")), match_id)
			if str(r.get("err", "")) != "":
				print("[SupabaseNet] 录像没取到(matches) %s code=%d" % [str(r["err"]), int(r.get("code", 0))])
			fin.call(r)
			_bye())
