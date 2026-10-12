extends RefCounted
## feedback_net.gd —— 玩家主动提交的问题反馈(2026-10-12)。
##
## 由来(用户 2026-10-12):「人家如果遇到问题还要按你这个模版填？游戏内没有直接上传bug信息？」
##   商业游戏的做法: 设置 →「问题反馈」→ 类型 + 描述, 版本 / 设备等自动附带
##   (Supercell 设置→帮助与支持→报告问题; BGMI 设置→客服→Report)。界面在 `scripts/scenes/feedback_panel.gd`。
##
## ★上传走 `supabase.gd` 的现成机制(节点 `_spawn` → `_await_token` → `_http`), 形状照抄
##   `report_client_errors`; 写在这里而不改 supabase.gd。服务端 = `submit_feedback`
##   (`server/supabase/migrations/20261012c_player_feedback.sql`)。
## ★没配后端 ⇒ 一个请求都不发, 直接回失败(界面显示「提交失败」, 不假装成功)。
## ★服务端回 `false`(没登录 / 当天超 20 条 / 描述为空)也算失败 —— 2xx 不等于收下了
##   (memory `fb-200-ok-is-not-it-happened`)。
## ⚠ 时间穿越期间这是一条写请求 ⇒ 被 `_http` 出口拦下, 同样回失败(开发包专有, 正式包没有时间穿越)。

const SB := preload("res://scripts/net/supabase.gd")
const ER := preload("res://scripts/net/error_reporter.gd")
const RR := preload("res://scripts/systems/replay/replay_recorder.gd")

const RPC_PATH := "/rest/v1/rpc/submit_feedback"
const MSG_MAX := 500            # 描述最多几个字(服务端再截一次 1000)
const REPLAY_KEEP := 3          # 附带最近几场对局编号
const ERR_KEEP := 3000          # 最近报错最多带几个字(服务端 meta 总量 8000 字节)
## 问题类型的代码(界面文字在 feedback_panel.gd)。
const KIND_CRASH := "crash"
const KIND_DISPLAY := "display"
const KIND_GAMEPLAY := "gameplay"
const KIND_OTHER := "other"
## 描述为空时对玩家说的话。
const ERR_EMPTY := "请填写问题描述"

## 观测量: 真交给 `_http` 的条数(门禁分母)。
static var posts: int = 0


## 纯判据: 这段描述能不能提交。返回要对玩家说的错误; "" = 可以。
static func check_message(text: String) -> String:
	if text.strip_edges() == "":
		return ERR_EMPTY
	return ""


## 本机最近 `n` 场录像的编号(`user://replays/<uuid>.rpl`, 按修改时间新到旧)。
static func recent_replay_ids(n: int = REPLAY_KEEP) -> Array:
	var dir := DirAccess.open(RR.SAVE_DIR)
	if dir == null:
		return []
	var files: Array = []
	for fn in dir.get_files():
		if not fn.ends_with(".rpl"):
			continue
		var id: String = fn.get_basename()
		if not SB.is_uuid(id):
			continue
		files.append({"id": id, "t": int(FileAccess.get_modified_time(RR.SAVE_DIR + fn))})
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["t"]) > int(b["t"]))
	var out: Array = []
	for e in files.slice(0, n):
		out.append(str(e["id"]))
	return out


## 最近报错(ErrorReporter 落盘的那份摘要)。没有就 ""。
static func last_errors() -> String:
	if not FileAccess.file_exists(ER.LAST_PATH):
		return ""
	return FileAccess.get_file_as_string(ER.LAST_PATH).left(ERR_KEEP)


## 自动附带的信息(玩家不填)。
static func build_meta() -> Dictionary:
	return {
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"platform": OS.get_name(),
		"model": OS.get_model_name(),
		"os_version": OS.get_version(),
		"account": str(GameState.account_id),
		"replays": recent_replay_ids(),
		"last_errors": last_errors(),
	}


## RPC 正文: 恰好是函数的三个参数。
static func build_body(kind: String, message: String) -> Dictionary:
	return {"p_kind": kind, "p_message": message.strip_edges().left(MSG_MAX), "p_meta": build_meta()}


## 提交一条。`done(ok: bool)` 一定会被调一次。
static func submit(kind: String, message: String, done: Callable) -> void:
	if not SB.enabled() or check_message(message) != "":
		done.call(false)
		return
	var n = SB._spawn()
	if n == null:
		done.call(false)
		return
	_send(n, JSON.stringify(build_body(kind, message)), done)


static func _send(n, body: String, done: Callable) -> void:
	if not await n._await_token():
		n._bye()
		done.call(false)
		return
	posts += 1
	n._http("POST", SB.base_url().rstrip("/") + RPC_PATH, body, func(res: Dictionary) -> void:
		var code := int(res.get("code", 0))
		var ok: bool = bool(res.get("ok", false)) and code >= 200 and code < 300 \
			and str(res.get("body", "")).strip_edges() == "true"
		n._bye()
		done.call(ok),
		"Content-Type: application/json")
