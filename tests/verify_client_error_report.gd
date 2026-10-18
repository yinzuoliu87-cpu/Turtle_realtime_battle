extends Node
## verify_client_error_report.gd —— 客户端报错上报(2026-10-11 · docs/plans/20261011-客户端报错上报.md 验收 1~5)
##
## ① GameState 开机就装上了(分母), 运行标记在
## ② push_error 一条 ⇒ 进队列, 字段齐(签名 / 类型 / 版本 / 平台 / 场景 / 消息 / 详情含调用栈)
## ③ 同一处报 100 次 ⇒ 只排 1 条
## ④ 没配后端 ⇒ 一个请求都不发
## ⑤ 配了后端(注入传输)⇒ POST 到 rpc/report_client_error, 正文恰好是函数的 7 个参数
## ⑥ 标记留着 ⇒ 下次启动排一条 unclean_exit(附上次报错摘要); 没标记 ⇒ 不排

const SB := preload("res://scripts/net/supabase.gd")
const ER := preload("res://scripts/net/error_reporter.gd")
const PARAMS := ["p_detail", "p_kind", "p_message", "p_platform", "p_scene", "p_sig", "p_version"]

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _emit_probe(tag: String) -> void:
	push_error("client-error-probe " + tag)


## 另外几个出处(签名按栈顶脚本帧算 ⇒ 每个场景要各自一行)
func _emit_b(i: int) -> void:
	push_error("client-error-probe B hp=%d" % i)


func _emit_c() -> void:
	push_error("client-error-probe C")


func _emit_d() -> void:
	push_error("client-error-probe D")


func _ready() -> void:
	await get_tree().process_frame
	print("=== 客户端报错上报 ===")
	var r: ErrorReporter = ER.instance()
	_ok("★分母: GameState 开机已装上 ErrorReporter", r != null)
	if r == null:
		get_tree().quit(1)
		return
	_ok("运行标记在(闪退判据的前提)", FileAccess.file_exists(ER.FLAG_PATH))
	r.drain("")   # 清掉开机时可能排进来的

	## ② 一条
	var cap0: int = ER.captured_total
	var q0: int = ER.queued_total
	_emit_probe("A")
	_ok("★push_error 被 Logger 接住", ER.captured_total == cap0 + 1, "captured %d→%d" % [cap0, ER.captured_total])
	_ok("进了队列", ER.queued_total == q0 + 1)
	var rows: Array = r.drain("SomeScene.tscn")
	_ok("★分母: 取出 1 行", rows.size() == 1, str(rows.size()))
	if rows.size() == 1:
		var row: Dictionary = rows[0]
		var keys: Array = row.keys()
		keys.sort()
		_ok("★字段恰好是 RPC 的 7 个参数", keys == PARAMS, str(keys))
		_ok("消息是报错原文", str(row["p_message"]).find("client-error-probe A") >= 0, str(row["p_message"]))
		_ok("签名 16 位", str(row["p_sig"]).length() == 16)
		_ok("类型合法", [ER.KIND_ERROR, ER.KIND_SCRIPT, ER.KIND_SHADER].has(str(row["p_kind"])), str(row["p_kind"]))
		_ok("版本 = project.godot", str(row["p_version"]) == str(ProjectSettings.get_setting("application/config/version")))
		_ok("平台", str(row["p_platform"]) == OS.get_name())
		_ok("场景", str(row["p_scene"]) == "SomeScene.tscn")
		_ok("★详情带调用栈(找得到出事的测试函数)", str(row["p_detail"]).find("_emit_probe") >= 0, str(row["p_detail"]).left(200))

	## ②b ★2026-10-19 回放对不上 = 唯一上报的警告(服务器裁判: 每看一次录像都是一次真机核对)
	var qw: int = ER.queued_total
	push_warning("普通警告不上报 probe")
	_ok("②b 普通警告不进队列", ER.queued_total == qw, "排了 %d" % (ER.queued_total - qw))
	push_warning("[Replay] 第 4321 步: 终局对不上 —— 停止播放")
	_ok("②b ★★回放对不上的警告进队列", ER.queued_total == qw + 1, "排了 %d" % (ER.queued_total - qw))
	var rows_w: Array = r.drain("RealtimeBattle3D.tscn")
	_ok("②b 那一行的消息是回放对不上原文", rows_w.size() == 1 and str(rows_w[0]["p_message"]).begins_with(ER.REPLAY_MISMATCH_TAG), str(rows_w.size()))
	var rec_src := FileAccess.get_file_as_string("res://scripts/systems/replay/replay_recorder.gd")
	_ok("②b ★口径: 录像器真的用这个开头报对不上(改了那边这条就红)",
		rec_src.find('push_warning("%s%%d 步' % ER.REPLAY_MISMATCH_TAG) >= 0)

	## ③ 去重 —— 同一行、消息带不同数值(原来按「文件:行:原文」签名时这会刷出 100 个签名)
	var q1: int = ER.queued_total
	for i in range(100):
		_emit_b(i)
	_ok("★同一处报 100 次(消息各不相同)只排 1 条", ER.queued_total == q1 + 1, "排了 %d" % (ER.queued_total - q1))
	_ok("但 100 次都被接住了(分母)", ER.captured_total >= cap0 + 101)
	r.drain("")

	## ④ 没配后端
	_ok("★分母: 门禁里后端没配", not SB.enabled())
	var p0: int = SB.client_error_posts
	_emit_c()
	r.flush("X.tscn")
	await get_tree().process_frame
	_ok("★没配后端 ⇒ 不发请求", SB.client_error_posts == p0)

	## ⑤ 配了后端
	var got: Array = []
	var env0 := OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "https://example.invalid")
	ProjectSettings.set_setting(SB.SETTING_KEY, "test-key")
	SB._reset_auth_for_test()
	SB._token = "fresh"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	SB._transport_for_test = func(method: String, url: String, _h: PackedStringArray, body: String, cb: Callable) -> void:
		got.append({"m": method, "u": url, "b": body})
		cb.call({"ok": true, "code": 200, "body": "true"})
	_ok("★分母: 现在后端算配上了", SB.enabled())
	_emit_d()
	r.flush("Y.tscn")
	for i in range(10):
		await get_tree().process_frame
	_ok("★发了 1 个请求", got.size() == 1, str(got.size()))
	if got.size() == 1:
		_ok("POST 到 rpc/report_client_error", got[0]["m"] == "POST" and str(got[0]["u"]).ends_with("/rest/v1/rpc/report_client_error"), str(got[0]["u"]))
		var j = JSON.parse_string(str(got[0]["b"]))
		var bk: Array = (j as Dictionary).keys() if j is Dictionary else []
		bk.sort()
		_ok("★正文恰好是 7 个参数", bk == PARAMS, str(bk))
		_ok("正文里是这条报错", j is Dictionary and str(j.get("p_message", "")).find("client-error-probe D") >= 0)
	SB._transport_for_test = Callable()
	SB._reset_auth_for_test()
	OS.set_environment(SB.ENV_URL, env0)
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)

	## ⑥ 闪退判据(新实例, 不装进 OS —— 只验判定)
	var f := FileAccess.open(ER.LAST_PATH, FileAccess.WRITE)
	f.store_string("[script] 上次的报错")
	f.close()
	ER._write_flag("Battle.tscn")
	var r2 := ErrorReporter.new()
	r2._check_unclean_exit()
	var u: Array = r2.drain("")
	_ok("★标记留着 ⇒ 排 1 条 unclean_exit", u.size() == 1 and str(u[0]["p_kind"]) == ER.KIND_UNCLEAN, str(u))
	if u.size() == 1:
		_ok("附上次报错摘要", str(u[0]["p_detail"]).find("上次的报错") >= 0)
		_ok("记下开局场景", str(u[0]["p_scene"]) == "Battle.tscn", str(u[0]["p_scene"]))
	ER._clear_flag()
	var r3 := ErrorReporter.new()
	r3._check_unclean_exit()
	_ok("★反面: 没标记 ⇒ 不排", r3.drain("").is_empty())
	ER._write_flag()   # 还原: 本进程仍在运行

	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
