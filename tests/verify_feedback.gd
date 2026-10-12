extends Node
## verify_feedback.gd —— 游戏内「问题反馈」(2026-10-12)
##
## ① 设置页真的有「问题反馈」键(开发包 + 正式包两种条件都建), 在屏内, 不压别的键
## ② 点它 ⇒ 弹框打开(类型四选一 / 描述框 / 提交 / 取消); 再点不叠第二个
## ③ 描述为空 ⇒ 提交被拦下, 状态行写「请填写问题描述」, 一个请求都不发
## ④ 没配后端 ⇒ 不发请求, 状态行写提交失败
## ⑤ 配了后端(注入传输)⇒ POST 到 rpc/submit_feedback, 正文恰好 p_kind/p_message/p_meta,
##    meta 带 version/platform/model/os_version/account/replays/last_errors, 类型是选中的那个; 回 true ⇒「已提交」
## ⑥ 服务端回 false(超限 / 没登录)⇒ 判失败
## ⑦ 描述最多 500 字(界面截 + 正文截)

const SB := preload("res://scripts/net/supabase.gd")
const ER := preload("res://scripts/net/error_reporter.gd")
const RR := preload("res://scripts/systems/replay/replay_recorder.gd")
const NET := preload("res://scripts/net/feedback_net.gd")
const PANEL := preload("res://scripts/scenes/feedback_panel.gd")
const SET := preload("res://scripts/scenes/SettingsScene.gd")
const PARAMS := ["p_kind", "p_message", "p_meta"]
const META_KEYS := ["account", "last_errors", "model", "os_version", "platform", "replays", "version"]

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _frames(k: int) -> void:
	for i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	print("=== 问题反馈 ===")
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	## ① 设置页上的键
	var sc: Control = SET.new()
	add_child(sc)
	await _frames(2)
	var fb = sc.find_child(SET.FEEDBACK_BTN, true, false)
	_ok("★设置页有「问题反馈」键(开发包条件)", fb is Button and (fb as Button).text == "问题反馈", str(fb))
	if not (fb is Button):
		_finish()
		return
	var r: Rect2 = (fb as Button).get_rect()
	_ok("键在 1280×720 设计框内", Rect2(0, 0, 1280, 720).encloses(r), str(r))
	var hits: Array = []
	for b in sc.find_children("*", "Button", true, false):
		if b != fb and (b as Button).get_rect().intersects(r):
			hits.append(str((b as Button).name))
	_ok("不压别的键", hits.is_empty(), str(hits))
	SET.release_override = true
	var sc_rel: Control = SET.new()
	add_child(sc_rel)
	await get_tree().process_frame
	SET.release_override = false
	_ok("★正式包条件下也有这颗键", sc_rel.find_child(SET.FEEDBACK_BTN, true, false) is Button)
	sc_rel.queue_free()

	## ② 打开
	(fb as Button).pressed.emit()
	await get_tree().process_frame
	var lay = sc.get_node_or_null(PANEL.LAYER)
	_ok("★点了 ⇒ 弹框打开", lay is Control)
	(fb as Button).pressed.emit()
	await get_tree().process_frame
	var n_lay := 0
	for c in sc.get_children():
		if str(c.name).begins_with(PANEL.LAYER):
			n_lay += 1
	_ok("再点不叠第二个", n_lay == 1, str(n_lay))
	if not (lay is Control):
		_finish()
		return
	var ed = lay.find_child(PANEL.EDIT, true, false)
	var st = lay.find_child(PANEL.STATUS, true, false)
	var sub = lay.find_child(PANEL.SUBMIT, true, false)
	_ok("★分母: 描述框 / 状态行 / 提交 / 取消都在", ed is TextEdit and st is Label and sub is Button
		and lay.find_child(PANEL.CANCEL, true, false) is Button)
	var kinds := 0
	for k in PANEL.KINDS:
		if lay.find_child(PANEL.KIND_PREFIX + str(k[0]), true, false) is Button:
			kinds += 1
	_ok("类型四选一: 4 颗都在", kinds == 4, str(kinds))
	if not (ed is TextEdit and st is Label and sub is Button):
		_finish()
		return

	## ③ 空描述
	var p0: int = NET.posts
	(ed as TextEdit).text = "   \n "
	(sub as Button).pressed.emit()
	await _frames(3)
	_ok("★描述为空 ⇒ 被拦下", (st as Label).text == NET.ERR_EMPTY, (st as Label).text)
	_ok("空描述不发请求", NET.posts == p0)

	## ④ 没配后端
	_ok("★分母: 门禁里后端没配", not SB.enabled())
	(ed as TextEdit).text = "战斗中闪退 probe-4"
	(sub as Button).pressed.emit()
	await _frames(3)
	_ok("★没配后端 ⇒ 不发请求", NET.posts == p0)
	_ok("没配后端 ⇒ 显示提交失败", (st as Label).text == PANEL.MSG_FAIL, (st as Label).text)

	## ⑤ 配了后端
	## 造 4 份本机录像 + 一份最近报错(测完删掉 / 还原)
	DirAccess.make_dir_recursive_absolute(RR.SAVE_DIR)
	var fake_ids: Array = []
	for i in range(4):
		var id: String = RR.new_id()
		var f := FileAccess.open(RR.SAVE_DIR + id + ".rpl", FileAccess.WRITE)
		f.store_string("x")
		f.close()
		fake_ids.append(id)
	var had_last := FileAccess.file_exists(ER.LAST_PATH)
	var last0 := FileAccess.get_file_as_string(ER.LAST_PATH) if had_last else ""
	var lf := FileAccess.open(ER.LAST_PATH, FileAccess.WRITE)
	lf.store_string("[script] feedback-probe-last-error")
	lf.close()

	var got: Array = []
	var reply := ["true"]
	var env0 := OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "https://example.invalid")
	ProjectSettings.set_setting(SB.SETTING_KEY, "test-key")
	SB._reset_auth_for_test()
	SB._token = "fresh"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	SB._transport_for_test = func(method: String, url: String, _h: PackedStringArray, body: String, cb: Callable) -> void:
		got.append({"m": method, "u": url, "b": body})
		cb.call({"ok": true, "code": 200, "body": reply[0]})
	_ok("★分母: 现在后端算配上了", SB.enabled())
	var kb = lay.find_child(PANEL.KIND_PREFIX + NET.KIND_DISPLAY, true, false)
	(kb as Button).pressed.emit()
	(ed as TextEdit).text = "排行榜名字重叠 probe-5"
	(sub as Button).pressed.emit()
	await _frames(15)
	_ok("★发了 1 个请求", got.size() == 1, str(got.size()))
	if got.size() == 1:
		_ok("POST 到 rpc/submit_feedback", got[0]["m"] == "POST"
			and str(got[0]["u"]).ends_with("/rest/v1/rpc/submit_feedback"), str(got[0]["u"]))
		var j = JSON.parse_string(str(got[0]["b"]))
		var bk: Array = (j as Dictionary).keys() if j is Dictionary else []
		bk.sort()
		_ok("★正文恰好是 3 个参数", bk == PARAMS, str(bk))
		if bk == PARAMS:
			var meta = j["p_meta"]
			var mk: Array = (meta as Dictionary).keys() if meta is Dictionary else []
			mk.sort()
			_ok("★meta 字段齐", mk == META_KEYS, str(mk))
			if mk == META_KEYS:
				_ok("版本 = project.godot", str(meta["version"]) == str(ProjectSettings.get_setting("application/config/version")), str(meta["version"]))
				_ok("平台", str(meta["platform"]) == OS.get_name(), str(meta["platform"]))
				_ok("设备型号", str(meta["model"]) == OS.get_model_name(), str(meta["model"]))
				_ok("系统版本", str(meta["os_version"]) == OS.get_version())
				_ok("账号", str(meta["account"]) == str(GameState.account_id))
				var reps: Array = meta["replays"] if meta["replays"] is Array else []
				var all_fake := true
				for x in reps:
					if not fake_ids.has(str(x)):
						all_fake = false
				_ok("★最近对局: 4 份里取 3 个编号", reps.size() == 3 and all_fake, str(reps))
				_ok("最近报错带上了", str(meta["last_errors"]).find("feedback-probe-last-error") >= 0)
			_ok("类型 = 选中的「画面 / 显示」", str(j["p_kind"]) == NET.KIND_DISPLAY, str(j["p_kind"]))
			_ok("描述原文", str(j["p_message"]) == "排行榜名字重叠 probe-5", str(j["p_message"]))
	_ok("★回 true ⇒ 显示已提交", (st as Label).text == PANEL.MSG_OK, (st as Label).text)

	## ⑥ 服务端回 false
	reply[0] = "false"
	var res := [null]
	NET.submit(NET.KIND_OTHER, "probe-6", func(ok: bool) -> void: res[0] = ok)
	await _frames(15)
	_ok("★服务端回 false ⇒ 判失败", res[0] == false, str(res[0]))
	_ok("分母: 这次也真发了", got.size() == 2, str(got.size()))

	SB._transport_for_test = Callable()
	SB._reset_auth_for_test()
	OS.set_environment(SB.ENV_URL, env0)
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	for id in fake_ids:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RR.SAVE_DIR + str(id) + ".rpl"))
	if had_last:
		var rf := FileAccess.open(ER.LAST_PATH, FileAccess.WRITE)
		rf.store_string(last0)
		rf.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ER.LAST_PATH))
	_ok("还原: 后端又是没配", not SB.enabled())

	## ⑦ 500 字
	var long := "长".repeat(600)
	_ok("正文截到 500 字", str(NET.build_body(NET.KIND_OTHER, long)["p_message"]).length() == NET.MSG_MAX)
	(ed as TextEdit).text = long
	(ed as TextEdit).text_changed.emit()
	_ok("★输入框截到 500 字", (ed as TextEdit).text.length() == NET.MSG_MAX, str((ed as TextEdit).text.length()))
	_ok("尺子会响: 600 字的判据是能红的", long.length() == 600)

	sc.queue_free()
	_finish()


func _finish() -> void:
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
