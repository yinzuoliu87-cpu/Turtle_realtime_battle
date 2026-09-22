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
	return ("season_week=eq.%d&battles=in.(%d,%d)&account_id=neq.%s" \
		+ "&select=snapshot&order=uploaded_at.desc&limit=%d") % [
		season_week, battles, battles + 1, account_id, PULL_LIMIT]


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
		return {"ok": false, "reason": "本机还没有账号，先联网开一局再绑"}
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
		_email_state = EM_ERR
		_email_msg = "还没登录，先联网开一局再绑"
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
