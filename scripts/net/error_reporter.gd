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
## 「按下那颗已离树」那条报错详情里附的一行的开头(门禁 / 查库按它找)。
const TOUCH_TAG := "手指按下的控件(抬起或拖动时已离树): "

static var _inst: ErrorReporter = null
## 报错那一刻的场景(主线程 `_Watch._process` 每帧对一次; 报错可能来自任意线程 ⇒ 只在锁里读写)。
## ★2026-11-01: 原来行里的场景是**清队列**那一刻的(每 FLUSH_SEC 秒一次)——正式服「!is_inside_tree() @ can_process」
##   那几条「选龟屏」, 有两条是新号建号后 18 / 26 秒报上来的: 报错时人可能还在上一屏, 场景字段把人引到了错的屏。
static var _scene_now: String = ""
## 手指按下的那一颗控件, 抬起 / 拖动到达时已离树但没释放(= 引擎紧接着在同一个调用栈里报
##   `!is_inside_tree() @ can_process` 的前提, 见 tests/verify_touch_detach_on_release.gd 头注):
##   它**按下那一刻**的路径。`_Watch._input` 写、`_log_error` 读 —— 那条引擎报错没有脚本栈, 不附这个就只知道「有一处」。
static var _touch_gone: String = ""
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


## 纯函数: 上报的平台字段。陪练号(服务器上 `SIM_DRIVER=1` 的真账号)后面加「/bot」。
## ★2026-10-31: 正式服一周 179 条 unclean_exit 全是调度器正常停陪练号(直接杀进程 ⇒ 标记没删),
##   把真人闪退淹没了。分开之后查真人只看不带 /bot 的; 陪练号自己的报错照样在, 照样能查。
## ★不改服务端: platform 本来就是文本列(`report_client_errors` 只截 32 字)。
static func platform_of(os_name: String, is_bot: bool) -> String:
	return os_name + ("/bot" if is_bot else "")


## 纯函数: 这条是不是「手指抬起 / 拖动时按下的那颗已离树」那条引擎报错(scene/main/node.cpp `can_process` 第一行)。
static func is_touch_detach(function: String, code: String) -> bool:
	return function == "can_process" and code.find("is_inside_tree") >= 0


## 纯函数: 控件路径 → 上报用的文字。引擎自动起的名字(`@Button@1234`)序号每个进程都不同 ⇒ 抹掉, 同一处才落到同一个签名。
static func path_text(p: String) -> String:
	var re := RegEx.new()
	re.compile("@(\\d+)")
	return re.sub(p, "@#", true)


## 主线程记: 当前场景(`_Watch._process`)/ 按下那颗已离树(`_Watch._input`)。没装上报器 ⇒ 什么都不做。
static func _note_scene(s: String) -> void:
	if _inst == null:
		return
	_inst._mx.lock()
	_scene_now = s
	_inst._mx.unlock()


static func _note_touch_gone(p: String) -> void:
	if _inst == null:
		return
	_inst._mx.lock()
	_touch_gone = p
	_inst._mx.unlock()


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


## 主动上报一条诊断(不是引擎报错; 现在只有设备自检 `DeviceSelfcheck.report` 用)。
## 签名 = kind + key 的摘要: 同一进程同一签名只排一次; 不占 MAX_SIGS(那是给每帧刷的报错设的顶)。
## 返回 true = 进了上传队列(没装上报器 / 已排过 ⇒ false)。版本 / 平台在 `drain` 里补。
static func report(kind: String, message: String, detail: String, key: String) -> bool:
	if _inst == null:
		return false
	var sig := ("%s|%s" % [kind, key]).md5_text().left(16)
	_inst._mx.lock()
	if _inst._seen.has(sig):
		_inst._mx.unlock()
		return false
	_inst._seen[sig] = true
	_inst._queue.append({"p_sig": sig, "p_kind": kind, "p_message": message.left(MSG_MAX),
		"p_detail": detail.left(DETAIL_MAX)})
	queued_total += 1
	_inst._mx.unlock()
	return true


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
	_mx.lock()
	var touch: String = _touch_gone if is_touch_detach(function, code) else ""
	var scene_now: String = _scene_now
	_mx.unlock()
	## 这条引擎报错没有脚本栈 ⇒ 签名改按「按下的那一颗」算: 不同出处各占一行(同一处仍只报一次)
	var sig := sig_of(file, line, code, top_frame_of(bt) if bt != "" else touch)
	_mx.lock()
	captured_total += 1
	if _seen.has(sig) or _seen.size() >= MAX_SIGS:
		_mx.unlock()
		return
	_seen[sig] = true
	_mx.unlock()
	var row := row_of(function, file, line, code, rationale, error_type, bt)
	if touch != "":
		row["p_sig"] = sig
		row["p_detail"] = (str(row["p_detail"]) + "\n" + TOUCH_TAG + touch).left(DETAIL_MAX)
	if scene_now != "":
		row["p_scene"] = scene_now
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
	var plat := platform_of(OS.get_name(), OS.get_environment("SIM_DRIVER") == "1")
	for r in rows:
		r["p_version"] = ver
		r["p_platform"] = plat
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
	var _scene_id := -1
	## 触摸序号 → [按下那一颗的 instance id, 按下那一刻的路径文字]
	var _press: Dictionary = {}

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	## 手指: 按下时记下命中的那一颗(引擎这时已派完模拟鼠标左键, 悬停 = 手指下那一颗); 抬起 / 拖动到达时它若已离树
	##   (还没释放)⇒ 记给 `_log_error` —— 输入先过 `_input` 再进 GUI, 引擎那条报错紧跟在这之后。
	## ★只读不吞: 不 set_input_as_handled, 玩家路径上一个事件都不改。挂在自动加载底下 ⇒ 各屏自己的 `_input` 先跑。
	func _input(ev: InputEvent) -> void:
		if ev is InputEventScreenTouch:
			var st := ev as InputEventScreenTouch
			if st.pressed:
				var h: Control = get_viewport().gui_get_hovered_control() if is_inside_tree() else null
				_press[st.index] = [h.get_instance_id() if h != null else 0,
					ErrorReporter.path_text(str(h.get_path())) if h != null and h.is_inside_tree() else ""]
				ErrorReporter._note_touch_gone("")
			else:
				_check_touch(st.index)
				_press.erase(st.index)
		elif ev is InputEventScreenDrag:
			_check_touch((ev as InputEventScreenDrag).index)

	func _check_touch(idx: int) -> void:
		var p = _press.get(idx)
		var gone := ""
		if p is Array:
			var o: Object = instance_from_id(int(p[0])) if int(p[0]) != 0 else null
			if is_instance_valid(o) and o is Control and not (o as Control).is_inside_tree():
				gone = str(p[1])
		ErrorReporter._note_touch_gone(gone)

	func _process(delta: float) -> void:
		var cs := get_tree().current_scene if is_inside_tree() else null
		var sid := cs.get_instance_id() if cs != null else 0
		if sid != _scene_id:
			_scene_id = sid
			ErrorReporter._note_scene(cs.scene_file_path.get_file() if cs != null else "")
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
				## ★2026-10-23: 引擎下发这几条通知时是从根节点往下逐个传, 根节点此刻「忙」, 同步 add_child 必失败(正式服报错「Parent node is busy setting up children」)⇒ SupabaseNet._spawn 建的请求节点进不了树、请求当场判失败。一律延后到这一帧末尾再做。
				##   原来切后台那一刻的上传必失败 ⇒ 切后台前攒的报错全丢。
				call_deferred("_flush_now")
			NOTIFICATION_APPLICATION_RESUMED:
				var cs := get_tree().current_scene if is_inside_tree() else null
				ErrorReporter._write_flag(cs.scene_file_path.get_file() if cs != null else "")
			NOTIFICATION_EXIT_TREE:
				ErrorReporter._clear_flag()
