extends RefCounted
## report_net.gd —— 昵称举报 + 「我的昵称被重置了吗」(2026-10-20 · App Store 审核指南 1.2)。
##
## 服务端(server/supabase/migrations/20261020b_account_delete_and_reports.sql):
##   · `report_nickname(p_tag, p_name, p_context)`: 写一行举报。同一人对同一玩家 ID 24 小时一次, 每人每天最多 20 条。
##     被举报者的账号由服务端按玩家 ID 在快照池里反查 —— 客户端不传账号(传了也不该信)。
##   · `my_nickname_reset()`: 管理员处理举报时把某个昵称重置过 ⇒ 开机查到自己当前的昵称在里面 ⇒
##     清掉 `GameState.nickname`(显示回默认昵称), 并给主菜单一句提示。
## ★上传走 `supabase.gd` 的现成机制(`_spawn` → `_await_token` → `_http`), 形状照抄 `feedback_net.gd`; supabase.gd 不改。
## ★回包正文 {ok:true} 才算举报成功(memory `fb-200-ok-is-not-it-happened`)。

const SB := preload("res://scripts/net/supabase.gd")
const _P2 := preload("res://scripts/gamedata/phase2_config.gd")

const RPC_REPORT := "/rest/v1/rpc/report_nickname"
const RPC_RESET := "/rest/v1/rpc/my_nickname_reset"

## 在哪一屏举报的(服务端只收这几个, 其余记成空)。
const CTX_LEADERBOARD := "leaderboard"
const CTX_BOARD := "gauntlet_board"
const CTX_BRACKET := "bracket"
const CTX_BATTLE := "battle"

## 结果代码(界面文字在 `player_menu.gd`)。
const R_OK := "ok"
const R_DUP := "duplicate"
const R_LIMIT := "limit"
const R_SELF := "self"
const R_FAIL := "fail"

## 主菜单那句提示。
const MSG_NICK_RESET := "昵称已被重置为默认昵称"

## 观测量(门禁分母)。
static var report_posts: int = 0
static var reset_posts: int = 0


## 纯判据: 举报回包 → 结果代码。
static func report_result(ok: bool, code: int, body: String) -> String:
	if not ok or code < 200 or code >= 300:
		return R_FAIL
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Dictionary):
		return R_FAIL
	var d: Dictionary = j.data
	if bool(d.get("ok", false)):
		return R_OK
	var r := str(d.get("reason", ""))
	return r if r in [R_DUP, R_LIMIT, R_SELF] else R_FAIL


## RPC 正文: 恰好是函数的三个参数。
static func report_body(tag: String, name: String, ctx: String) -> Dictionary:
	return {"p_tag": tag, "p_name": name.strip_edges().left(40), "p_context": ctx}


## 举报一个昵称。`done(code: String)` 一定会被调一次。
static func report(tag: String, name: String, ctx: String, done: Callable) -> void:
	if not SB.enabled() or not _P2.tag_valid(tag) or name.strip_edges() == "":
		done.call(R_FAIL)
		return
	var n = SB._spawn()
	if n == null:
		done.call(R_FAIL)
		return
	_send_report(n, JSON.stringify(report_body(tag, name, ctx)), done)


static func _send_report(n, body: String, done: Callable) -> void:
	if not await n._await_token():
		n._bye()
		done.call(R_FAIL)
		return
	report_posts += 1
	n._http("POST", SB.base_url().rstrip("/") + RPC_REPORT, body, func(res: Dictionary) -> void:
		var r := report_result(bool(res.get("ok", false)), int(res.get("code", 0)), str(res.get("body", "")))
		n._bye()
		done.call(r),
		"Content-Type: application/json")


## 纯判据: 重置回包 + 我现在的昵称 ⇒ 要不要清掉。
static func nickname_was_reset(ok: bool, code: int, body: String, current: String) -> bool:
	var cur := _P2.nickname_clean(current)
	if cur == "" or not ok or code < 200 or code >= 300:
		return false
	var j := JSON.new()
	if j.parse(body) != OK or not (j.data is Dictionary):
		return false
	var names = (j.data as Dictionary).get("names", [])
	if not (names is Array):
		return false
	for x in names:
		if _P2.nickname_clean(str(x)) == cur:
			return true
	return false


## 开机查一次。被重置过 ⇒ 清掉自己起的昵称(回到默认昵称)并落盘, `done(true)`; 其余一律 `done(false)`。
## ★自己没起过名(`nickname == ""`)⇒ 一个请求都不发: 默认昵称不会被举报到需要重置(它来自屏蔽过词的生成器)。
static func check_nickname_reset(done: Callable = Callable()) -> void:
	var gs = SB._gs()
	if not SB.enabled() or gs == null or str(gs.nickname) == "":
		if done.is_valid():
			done.call(false)
		return
	var n = SB._spawn()
	if n == null:
		if done.is_valid():
			done.call(false)
		return
	_send_reset(n, gs, done)


static func _send_reset(n, gs, done: Callable) -> void:
	if not await n._await_token():
		n._bye()
		if done.is_valid():
			done.call(false)
		return
	reset_posts += 1
	n._http("POST", SB.base_url().rstrip("/") + RPC_RESET, "{}", func(res: Dictionary) -> void:
		var hit := nickname_was_reset(bool(res.get("ok", false)), int(res.get("code", 0)),
			str(res.get("body", "")), str(gs.nickname))
		n._bye()
		if hit:
			print("[Report] 昵称「%s」已被管理员重置 ⇒ 换回默认昵称" % str(gs.nickname))
			gs.nickname = ""
			gs.save()
		if done.is_valid():
			done.call(hit),
		"Content-Type: application/json")
