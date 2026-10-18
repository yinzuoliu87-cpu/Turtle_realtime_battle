class_name ErrorReporter
extends Logger
## error_reporter.gd —— 客户端报错上报(2026-10-11 · 方案书 docs/plans/20261011-客户端报错上报.md)
##
## 用户 2026-10-11:「你有后台能够收集任何问题和反馈吗」「做，今晚你自己安排时间做」
## ★原来脚本报错 / 引擎报错 / 闪退只写在玩家本机日志里, 一条都不上传 ⇒ 内测玩家不说, 我们就不知道。
##
## ★接法: `OS.add_logger()`(Godot 4.5+ 引擎接口), 由 GameState._ready 调 `install()`。
## ★`_log_error` 可能来自任意线程 ⇒ 只往带锁的队列里塞; 主线程每 FLUSH_SEC 秒清一次队列再发。
## ★★回调里绝不 print / push_error —— 会递归回到自己。
## ★同一进程同一签名只报一次, 每进程最多 MAX_SIGS 个签名 ⇒ 每帧刷的报错也只占一行。
## ★闪退: 开局写 FLAG, 正常退出 / 切后台删掉、回前台再写 ⇒ 下次启动还在 = 上次没正常退出。
## ★没配后端(门禁 / 离线)= 只进队列不发; 时间穿越中由 SupabaseNet._http 按写请求拦下。

const _SB := preload("res://scripts/net/supabase.gd")
## 回放对不上那条警告的开头(与 `ReplayRecorder._diverge` 的 push_warning 同一个字面量)。
const REPLAY_MISMATCH_TAG := "[Replay] 第 "

const MAX_SIGS := 30
const FLUSH_SEC := 10.0
const MSG_MAX := 1000
const DETAIL_MAX := 4000
const BT_FRAMES := 12
const FLAG_PATH := "user://running.flag"
## 本进程碰到过的报错摘要 —— 只在出新签名时写(≤ MAX_SIGS 次), 下次启动若判成闪退就附上它。
const LAST_PATH := "user://last_errors.txt"
const LAST_KEEP := 10
const KIND_ERROR := "error"
const KIND_SCRIPT := "script"
const KIND_SHADER := "shader"
const KIND_UNCLEAN := "unclean_exit"

static var _inst: ErrorReporter = null
## 观测量 / 门禁分母
static var captured_total: int = 0     # 收到的报错条数(含重复签名)
static var queued_total: int = 0       # 进了上传队列的条数(去重后)
static var sent_rows: Array = []       # 交给网络层的每一行(门禁读)

var _mx := Mutex.new()
var _queue: Array = []
var _seen: Dictionary = {}
var _last: Array = []


## 装上(只装一次)。`host` = 拿来挂定时器和收前后台通知的节点(GameState)。
static func install(host: Node) -> void:
	if _inst != null:
		return
	_inst = ErrorReporter.new()
	_inst._check_unclean_exit()
	_write_flag()
	OS.add_logger(_inst)
	var w := _Watch.new()
	w.name = "ErrorReporterWatch"
	host.add_child(w)


static func instance() -> ErrorReporter:
	return _inst


## 纯函数: 签名。有脚本调用栈 ⇒ 用栈顶那一帧「脚本文件:行」; 没有 ⇒ 用「文件:行:错误原文」。
## ★为什么不直接用 file:line(2026-10-11 门禁实测): push_error 报上来的 file:line 一律是引擎里
##   `core/variant/variant_utility.cpp:1024` ⇒ 全游戏的 push_error 共用一个出处, 只能靠消息区分,
##   而消息常带数值(「hp=123」)⇒ 一处 bug 刷出几十个签名、挤满 MAX_SIGS。栈顶脚本帧才是真出处。
static func sig_of(file: String, line: int, code: String, top_frame: String = "") -> String:
	if top_frame != "":
		return top_frame.md5_text().left(16)
	return ("%s:%d:%s" % [file, line, code]).md5_text().left(16)


## 纯函数: 调用栈文本(每行「文件:行 @ 函数」)→ 栈顶「文件:行」; 没有 ⇒ ""。
static func top_frame_of(backtrace: String) -> String:
	if backtrace == "":
		return ""
	return backtrace.get_slice(String.chr(10), 0).get_slice(" @ ", 0)


static func kind_of(error_type: int) -> String:
	match error_type:
		Logger.ERROR_TYPE_SCRIPT:
			return KIND_SCRIPT
		Logger.ERROR_TYPE_SHADER:
			return KIND_SHADER
		_:
			return KIND_ERROR


## 纯函数: 这条警告是不是「回放对不上」(唯一上报的警告)。
static func is_replay_mismatch(code: String, rationale: String) -> bool:
	return code.begins_with(REPLAY_MISMATCH_TAG) or rationale.begins_with(REPLAY_MISMATCH_TAG)


## 纯函数: 一条报错 → 要上传的那一行(场景 / 版本 / 平台在主线程补)。
static func row_of(function: String, file: String, line: int, code: String, rationale: String,
		error_type: int, backtrace: String) -> Dictionary:
	var msg := rationale if rationale != "" else code
	var where := "%s:%d @ %s" % [file, line, function]
	return {
		"p_sig": sig_of(file, line, code, top_frame_of(backtrace)),
		"p_kind": kind_of(error_type),
		"p_message": msg.left(MSG_MAX),
		"p_detail": (where + ("\n" + backtrace if backtrace != "" else "")).left(DETAIL_MAX),
	}


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	## 警告一律不收, 只有一种例外: 回放对不上(`ReplayRecorder._diverge` 的「[Replay] 第 N 步…停止播放」)。
	##   ★2026-10-19: 结果改由服务器算之后, 手机看录像 = 本机照录像重算; iPhone(ARM)与服务器(x86)只要分叉,
	##   玩家就会看到「录像里赢、服务器判输」。原来这条只显示在屏幕上、不上报 ⇒ 内测一周 iOS 1102 条报错里
	##   一条回放的都没有, 证明不了没出过。收进来后每看一次录像都是一次真机核对。
	if error_type == Logger.ERROR_TYPE_WARNING and not is_replay_mismatch(code, rationale):
		return
	var bt := ""
	for b in script_backtraces:
		if b == null or b.is_empty():
			continue
		for i in range(mini(b.get_frame_count(), BT_FRAMES)):
			bt += "%s:%d @ %s\n" % [b.get_frame_file(i), b.get_frame_line(i), b.get_frame_function(i)]
	bt = bt.strip_edges()
	var sig := sig_of(file, line, code, top_frame_of(bt))
	_mx.lock()
	captured_total += 1
	if _seen.has(sig) or _seen.size() >= MAX_SIGS:
		_mx.unlock()
		return
	_seen[sig] = true
	_mx.unlock()
	var row := row_of(function, file, line, code, rationale, error_type, bt)
	_mx.lock()
	_queue.append(row)
	queued_total += 1
	_last.append("[%s] %s | %s" % [row["p_kind"], row["p_message"], str(row["p_detail"]).get_slice("\n", 0)])
	if _last.size() > LAST_KEEP:
		_last.pop_front()
	var snap := "\n".join(_last)
	_mx.unlock()
	var f := FileAccess.open(LAST_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(snap)
		f.close()


# zero-caller-ok: Logger 引擎虚函数, 由引擎调; 留空 = 不收 print
func _log_message(_message: String, _error: bool) -> void:
	pass


## 主线程: 取走队列, 补上版本 / 平台 / 场景, 交给网络层。返回这次交出去的行。
func drain(scene: String) -> Array:
	_mx.lock()
	var rows := _queue.duplicate()
	_queue.clear()
	_mx.unlock()
	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	for r in rows:
		r["p_version"] = ver
		r["p_platform"] = OS.get_name()
		if not r.has("p_scene"):
			r["p_scene"] = scene
	return rows


func flush(scene: String) -> void:
	var rows := drain(scene)
	if rows.is_empty():
		return
	sent_rows.append_array(rows)
	_SB.report_client_errors_async(rows)


## 上次启动留下的标记还在 ⇒ 上次没正常退出 ⇒ 排一条 unclean_exit, 附上次的报错摘要。
func _check_unclean_exit() -> void:
	if not FileAccess.file_exists(FLAG_PATH):
		return
	var prev := FileAccess.get_file_as_string(FLAG_PATH)
	var last := FileAccess.get_file_as_string(LAST_PATH) if FileAccess.file_exists(LAST_PATH) else ""
	var row := {
		"p_sig": sig_of("unclean_exit", 0, prev.get_slice("\n", 0)),
		"p_kind": KIND_UNCLEAN,
		"p_message": "上次运行没有正常退出(闪退 / 卡死被结束 / 前台被系统杀)",
		"p_detail": ("上次启动: " + prev + ("\n最近报错:\n" + last if last != "" else "\n最近报错: 无")).left(DETAIL_MAX),
		"p_scene": prev.get_slice("\n", 1),
	}
	_queue.append(row)
	queued_total += 1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LAST_PATH))


## 标记内容: 第 1 行版本, 第 2 行当前场景(切场景时不更新 —— 只记开局那一刻, 够用来认版本)。
static func _write_flag(scene: String = "") -> void:
	var f := FileAccess.open(FLAG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("%s\n%s\n%d" % [str(ProjectSettings.get_setting("application/config/version", "")),
			scene, int(Time.get_unix_time_from_system())])
		f.close()


static func _clear_flag() -> void:
	if FileAccess.file_exists(FLAG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FLAG_PATH))


## 主线程那一半: 定时清队列 + 收前后台 / 退出通知。
class _Watch extends Node:
	var _acc := 0.0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		_acc += delta
		if _acc < ErrorReporter.FLUSH_SEC:
			return
		_acc = 0.0
		_flush_now()

	func _flush_now() -> void:
		var r := ErrorReporter.instance()
		if r == null:
			return
		var cs := get_tree().current_scene if is_inside_tree() else null
		r.flush(cs.scene_file_path.get_file() if cs != null else "")

	func _notification(what: int) -> void:
		match what:
			NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
				ErrorReporter._clear_flag()
				_flush_now()
			NOTIFICATION_APPLICATION_RESUMED:
				var cs := get_tree().current_scene if is_inside_tree() else null
				ErrorReporter._write_flag(cs.scene_file_path.get_file() if cs != null else "")
			NOTIFICATION_EXIT_TREE:
				ErrorReporter._clear_flag()
