extends RefCounted
## account_delete.gd —— 应用内删除账号(2026-10-20 · App Store 审核指南 5.1.1(v))。
##
## 由来: 方案书 docs/plans/20261020-AppStore上架.md §4.2 / D4。Apple 要求「支持建号就必须能在 App 内删号」,
##   自动建的游客号同样要能删, 只停用不算删, 不许要求发邮件 / 打电话。
## ★服务端 = `account_delete_self()`(server/supabase/migrations/20261020b_account_delete_and_reports.sql):
##   只删调用者本人(auth.uid()), 别人看得见的录像 / 对阵图 / 裁判任务里把昵称 / 头像 / 玩家 ID 抹成占位, 再删 auth 用户。
## ★上传走 `supabase.gd` 的现成机制(节点 `_spawn` → `_await_token` → `_http`), 形状照抄 `feedback_net.gd`;
##   supabase.gd 一行不改。
## ★服务端回 {ok:true} 才算删了(memory `fb-200-ok-is-not-it-happened`): 2xx 但正文不是 ok ⇒ 失败, 本机一个字不动。
## ★删成功 ⇒ `wipe_local()`: 本机存档整份回到全新安装的样子(只留音量 / 全屏这类设备偏好)、
##   清身份(账号 / 邮箱 / 昵称 / 登录令牌 / 安装号)、删本机录像 / 对手池 / 黑名单等文件 ⇒ 调用方回主菜单,
##   onboarded=false ⇒ 首次进入流程(教程选择框); 主菜单 `ensure_signed_in_async` 再建一个新的匿名号。
## ★删失败 ⇒ 本机一个字不动(账号还在服务器上, 清了本机就等于把人从自己的号里踢出去)。

const SB := preload("res://scripts/net/supabase.gd")
const BL := preload("res://scripts/util/blocklist.gd")
const RR := preload("res://scripts/systems/replay/replay_recorder.gd")

const RPC_PATH := "/rest/v1/rpc/account_delete_self"

## 结果代码(界面文字在 `account_delete_dialog.gd`)。
const R_OK := "ok"
const R_OFF := "off"          # 没配后端(正式包不会走到: 没配后端时账号框整块不建)
const R_NET := "net"          # 没网 / 拿不到令牌 / 5xx / 看不懂的回包
const R_AUTH := "auth"        # 登录失效(绑了邮箱的号会话死了) / 服务端说没登录
const R_BLOCKED := "blocked"  # 写请求被出口拦下(开发包时间穿越 / 版本过旧)

## 删号成功后要删掉的本机文件(存档本体由 GameState.save() 重写, `.bak` 里是旧身份, 单独删)。
const WIPE_FILES := ["user://savegame.json.bak", "user://ghost_pool.json", "user://ghost_pool.json.tmp", "user://lastLineup.json",
	"user://team_draft.json", "user://pending_match.bin", "user://last_errors.txt"]
## 删号后保留的存档键: 这台设备的偏好, 与账号无关。
const KEEP_KEYS := ["bgm_volume", "sfx_volume", "fullscreen"]

## 观测量(门禁分母): 真交给 `_http` 的条数 / 做过几次本机清理。
static var posts: int = 0
static var wipes: int = 0


## 纯判据: 一次删号回包 → 结果代码。
static func result_of(ok: bool, code: int, body: String, blocked: bool = false) -> String:
	if blocked:
		return R_BLOCKED
	if not ok or code == 0:
		return R_NET
	if code == 401 or code == 403:
		return R_AUTH
	if code < 200 or code >= 300:
		return R_NET
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Dictionary):
		return R_NET
	var d: Dictionary = j.data
	if bool(d.get("ok", false)):
		return R_OK
	return R_AUTH if str(d.get("reason", "")) == "not_signed_in" else R_NET


## 删号。`done(code: String)` 一定会被调一次; code == R_OK 时本机已清理完。
static func request(done: Callable) -> void:
	if not SB.enabled():
		done.call(R_OFF)
		return
	if SB.session_lost():
		done.call(R_AUTH)
		return
	var n = SB._spawn()
	if n == null:
		done.call(R_NET)
		return
	_send(n, done)


static func _send(n, done: Callable) -> void:
	if not await n._await_token():
		n._bye()
		done.call(R_AUTH if SB.session_lost() else R_NET)
		return
	posts += 1
	n._http("POST", SB.base_url().rstrip("/") + RPC_PATH, "{}", func(res: Dictionary) -> void:
		var r := result_of(bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", "")),
			bool(res.get("blocked", false)))
		n._bye()
		if r == R_OK:
			wipe_local()
		done.call(r),
		"Content-Type: application/json")


## 本机回到全新安装的样子(保留设备偏好)。★只在服务端确认删了之后调。
## ★「全新」取自 GameState 脚本自己的默认值(新建一个不入树的实例读它的 `_save_dict()`),
##   不在这里手抄一份字段清单 —— 抄一次永远落后一次(memory `fb-hand-rolled-copies-drift`);
##   `reset_save()` 也不能用: 它有意保留身份与头衔。
static func wipe_local() -> void:
	wipes += 1
	_clear_session()
	var gs = _gs()
	if gs != null:
		var keep := {}
		for k in KEEP_KEYS:
			keep[k] = gs.get(k)
		var fresh = gs.get_script().new()
		var d: Dictionary = fresh._save_dict()
		fresh.free()
		for k in KEEP_KEYS:
			d[k] = keep[k]
		gs._apply_save_dict(d)
		## 身份类字段 `_apply_save_dict` 也许按「设备本地键」跳过 ⇒ 这里逐个写死成空, 不依赖它的实现。
		gs.install_uid = ""
		gs.account_id = ""
		gs.account_email = ""
		gs.nickname = ""
		gs.nickname_default = ""
		gs.auth_refresh = ""
		gs.cloud_rev = 0
		gs.onboarded = false
		gs.replay_upload_pending = []
		gs.ghost_upload_pending = []
		gs.referee_pending = {}
		gs.save()
	for f in WIPE_FILES:
		_rm(str(f))
	var dir := DirAccess.open(RR.SAVE_DIR)
	if dir != null:
		for fn in dir.get_files():
			_rm(RR.SAVE_DIR + fn)
	BL.clear_all()


static func _clear_session() -> void:
	SB._token = ""
	SB._expires_at = 0
	SB._session_lost = false
	SB._auth_inflight = false
	SB._save_dirty = false
	SB._last_pushed_hash = ""
	SB._save_conflict_rev = -1
	SB._pull_state = ""
	SB.finals_clear()
	SB.finals_week_clear()
	SB.finals_report_clear()
	SB.opponent_clear()


static func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _gs():
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("/root/GameState")
