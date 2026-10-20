extends Node
## verify_account_delete.gd —— 应用内删除账号(2026-10-20 · App Store 审核指南 5.1.1(v))
##
## ① 设置页账号框里有「删除账号」(和「黑名单」), 在设计框内、不压别的键; 没拿到账号时不建
## ② 两步确认: 第一步写清删什么 / 什么保留 / 不可恢复, 只有「取消」「下一步」; 取消 ⇒ 关掉、什么都没发;
##    第二步「确认删除」先倒数(不可点), 绑了邮箱的写出邮箱
## ③ 没配后端 ⇒ 不发请求, 状态行说失败, 本机身份一个字不动
## ④ 网络失败(传输回 ok=false)⇒ 发了 1 次, 失败, 本机一个字不动, 可以再点
## ⑤ 服务端回 200 但 {ok:false, not_signed_in} ⇒ 判「登录失效」, 本机不动(2xx ≠ 删了)
## ⑥ 绑了邮箱的号会话死了 ⇒ 不发请求, 提示先邮箱登录
## ⑦ 成功: POST rpc/account_delete_self、正文 {}、带令牌 ⇒ 本机回到全新安装(身份 / 昵称 / 令牌 / 安装号 / 进度 / 头衔 /
##    上传队列全清, 音量保留)、本机文件(.bak / 对手池 / 录像 / 黑名单)删掉、会话令牌清空 ⇒ 回主菜单(= run/main_scene),
##    且首次进入流程的条件成立(onboarded=false、没打过、没战绩)
## ⑧ 纯判据 result_of 逐条
## ⑨ 服务端玩家 ID 算法(SQL 检查脚本里的 TAGVEC 三行)与客户端 phase2_config.player_tag 逐个相同;
##    迁移文件里删号函数只给 authenticated(anon 收回)

const SB := preload("res://scripts/net/supabase.gd")
const NET := preload("res://scripts/net/account_delete.gd")
const DLG := preload("res://scripts/scenes/settings/account_delete_dialog.gd")
const SET := preload("res://scripts/scenes/SettingsScene.gd")
const BL := preload("res://scripts/util/blocklist.gd")
const RR := preload("res://scripts/systems/replay/replay_recorder.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const SQL_CHECK := "res://server/supabase/tests/20261020b_account_delete_and_reports_check.sql"
const SQL_MIG := "res://server/supabase/migrations/20261020b_account_delete_and_reports.sql"
const FAKE_ACC := "f47ac10b-58cc-4372-a567-0e02b2c3d479"
const NEED := 54   # 分母: 断言条数一条不能少(少了 = 半路中止)

var _n := 0
var _fail := 0
var _got: Array = []
var _reply := [{"ok": true, "code": 200, "body": "{\"ok\": true}"}]
var _hook_calls: Array = []


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
	print("=== 删除账号 ===")
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		_ok("分母: GameState", false)
		_finish()
		return
	gs.test_mode = true

	## ① 没账号 ⇒ 不建
	gs.account_id = ""
	var s0: Control = SET.new()
	s0.acct_override = 1
	add_child(s0)
	await _frames(2)
	_ok("① 没拿到账号 ⇒ 不建「删除账号」", s0.find_child(SET.ACCT_ROW_PREFIX + SET.BTN_DELETE, true, false) == null)
	s0.queue_free()

	_seed_identity(gs)
	var sc: Control = SET.new()
	sc.acct_override = 1
	sc.after_delete_hook = func(dest: String) -> void: _hook_calls.append(dest)
	add_child(sc)
	await _frames(2)
	var del = sc.find_child(SET.ACCT_ROW_PREFIX + SET.BTN_DELETE, true, false)
	var blk = sc.find_child(SET.ACCT_ROW_PREFIX + SET.BTN_BLOCKLIST, true, false)
	_ok("① ★账号框里有「删除账号」", del is Button and (del as Button).text == SET.DELETE_LABEL, str(del))
	_ok("① 账号框里有「黑名单」", blk is Button and (blk as Button).text == SET.BLOCKLIST_LABEL, str(blk))
	if not (del is Button and blk is Button):
		_finish()
		return
	var r: Rect2 = (del as Button).get_rect()
	_ok("① 键在 1280×720 设计框内", Rect2(0, 0, 1280, 720).encloses(r) and Rect2(0, 0, 1280, 720).encloses((blk as Button).get_rect()), str(r))
	var hits: Array = []
	for b in sc.find_children("*", "Button", true, false):
		for x in [del, blk]:
			if b != x and (b as Button).get_rect().intersects((x as Button).get_rect()):
				hits.append(str((b as Button).name))
	_ok("① 不压别的键", hits.is_empty(), str(hits))

	## ② 第一步
	(del as Button).pressed.emit()
	await get_tree().process_frame
	var lay = sc.get_node_or_null(DLG.LAYER)
	_ok("② ★点了 ⇒ 确认框打开", lay is Control)
	if not (lay is Control):
		_finish()
		return
	var ttl = lay.find_child(DLG.TITLE, true, false)
	var body = lay.find_child(DLG.BODY, true, false)
	var nxt = lay.find_child(DLG.BTN_NEXT, true, false)
	var cnl = lay.find_child(DLG.BTN_CANCEL, true, false)
	var cfm = lay.find_child(DLG.BTN_CONFIRM, true, false)
	_ok("② 分母: 标题 / 说明 / 取消 / 下一步 / 确认 都建了", ttl is Label and body is Label and nxt is Button and cnl is Button and cfm is Button)
	if not (ttl is Label and body is Label and nxt is Button and cnl is Button and cfm is Button):
		_finish()
		return
	_ok("② 第一步标题「删除账号」", (ttl as Label).text == DLG.T_STEP1, (ttl as Label).text)
	var bt: String = (body as Label).text
	_ok("② ★第一步写清: 删账号 / 云端存档 / 排行榜 / 本机存档 / 不可恢复 / 录像里换成「已注销玩家」",
		bt.contains("账号") and bt.contains("云端存档") and bt.contains("排行榜") and bt.contains("本机存档")
		and bt.contains("无法恢复") and bt.contains("已注销玩家"), bt)
	_ok("② 第一步只有「取消」「下一步」(确认键藏着)", (nxt as Button).visible and (cnl as Button).visible and not (cfm as Button).visible)
	var p0: int = NET.posts
	(cnl as Button).pressed.emit()
	await _frames(2)
	_ok("② 取消 ⇒ 框关掉, 一个请求都没发", not is_instance_valid(lay) or lay.is_queued_for_deletion(), str(NET.posts - p0))
	_ok("② 取消 ⇒ 本机身份不动", str(gs.account_id) == FAKE_ACC)

	## ② 第二步
	(del as Button).pressed.emit()
	await get_tree().process_frame
	lay = sc.get_node_or_null(DLG.LAYER)
	cfm = lay.find_child(DLG.BTN_CONFIRM, true, false)
	nxt = lay.find_child(DLG.BTN_NEXT, true, false)
	ttl = lay.find_child(DLG.TITLE, true, false)
	body = lay.find_child(DLG.BODY, true, false)
	var st = lay.find_child(DLG.STATUS, true, false)
	(nxt as Button).pressed.emit()
	await get_tree().process_frame
	_ok("② ★第二步标题「确认删除账号」、确认键出现", (ttl as Label).text == DLG.T_STEP2 and (cfm as Button).visible and not (nxt as Button).visible, (ttl as Label).text)
	_ok("② ★第二步确认键先倒数、不可点", (cfm as Button).disabled and (cfm as Button).text.contains("3"), (cfm as Button).text)
	## 邮箱那一句: 设置页的注入态把邮箱恒当空(那是登录墙的条件), 这里直接开一个带邮箱的框量。
	var host2 := Control.new()
	add_child(host2)
	var lay2: Control = DLG.open(host2, "probe@example.com", Callable())
	(lay2.find_child(DLG.BTN_NEXT, true, false) as Button).pressed.emit()
	await get_tree().process_frame
	var b2 := (lay2.find_child(DLG.BODY, true, false) as Label).text
	_ok("② 第二步写出绑定的邮箱(没绑的不写)", b2.contains("probe@example.com") and not (body as Label).text.contains("邮箱"), b2)
	host2.queue_free()
	DLG.skip_countdown(lay)
	await get_tree().process_frame
	_ok("② 倒数结束 ⇒ 可点", not (cfm as Button).disabled and (cfm as Button).text == DLG.L_CONFIRM)

	## ③ 没配后端
	_ok("③ 分母: 门禁里后端没配", not SB.enabled())
	(cfm as Button).pressed.emit()
	await _frames(3)
	_ok("③ ★没配后端 ⇒ 不发请求", NET.posts == p0)
	_ok("③ 状态行说失败", (st as Label).text == DLG.MSG[NET.R_OFF], (st as Label).text)
	_ok("③ ★本机身份一个字不动", _identity_intact(gs))
	_ok("③ 失败后确认键可以再点", not (cfm as Button).disabled)

	## ④ 配上后端, 网络失败
	var env0 := OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "https://example.invalid")
	ProjectSettings.set_setting(SB.SETTING_KEY, "test-key")
	SB._reset_auth_for_test()
	SB._token = "probe-token"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	SB._transport_for_test = func(method: String, url: String, h: PackedStringArray, b: String, cb: Callable) -> void:
		_got.append({"m": method, "u": url, "h": h, "b": b})
		cb.call(_reply[0])
	_ok("④ 分母: 现在后端算配上了", SB.enabled())
	_reply[0] = {"ok": false, "code": 0, "body": ""}
	(cfm as Button).pressed.emit()
	await _frames(15)
	_ok("④ 网络失败: 真发了 1 次", _got.size() == 1, str(_got.size()))
	_ok("④ ★网络失败 ⇒ 状态行说网络不可用", (st as Label).text == DLG.MSG[NET.R_NET], (st as Label).text)
	_ok("④ ★网络失败 ⇒ 本机身份一个字不动", _identity_intact(gs))

	## ⑤ 200 但没删
	_reply[0] = {"ok": true, "code": 200, "body": "{\"ok\": false, \"reason\": \"not_signed_in\"}"}
	(cfm as Button).pressed.emit()
	await _frames(15)
	_ok("⑤ ★回 200 但 ok=false ⇒ 判登录失效、不清本机", (st as Label).text == DLG.MSG[NET.R_AUTH] and _identity_intact(gs), (st as Label).text)

	## ⑥ 会话死了
	SB._session_lost = true
	var n6 := _got.size()
	(cfm as Button).pressed.emit()
	await _frames(5)
	_ok("⑥ 绑了邮箱的号会话死了 ⇒ 不发请求、提示先登录", _got.size() == n6 and (st as Label).text == DLG.MSG[NET.R_AUTH], (st as Label).text)
	SB._session_lost = false

	## ⑦ 成功
	_make_local_files()
	_ok("⑦ 分母: 本机文件都造出来了", FileAccess.file_exists("user://savegame.json.bak") and FileAccess.file_exists("user://ghost_pool.json")
		and FileAccess.file_exists(RR.SAVE_DIR + "probe.rpl") and BL.is_blocked("#4PT53K"))
	_reply[0] = {"ok": true, "code": 200, "body": "{\"ok\": true, \"scrubbed\": {\"matches\": 2}}"}
	var w0: int = NET.wipes
	(cfm as Button).pressed.emit()
	await _frames(15)
	var last: Dictionary = _got[_got.size() - 1] if not _got.is_empty() else {}
	_ok("⑦ ★POST 到 rpc/account_delete_self、正文 {}", str(last.get("m", "")) == "POST"
		and str(last.get("u", "")).ends_with("/rest/v1/rpc/account_delete_self") and str(last.get("b", "")) == "{}", str(last.get("u", "")))
	_ok("⑦ 请求带的是本人令牌(不是公共钥匙)", "Authorization: Bearer probe-token" in Array(last.get("h", PackedStringArray())))
	_ok("⑦ ★成功 ⇒ 清理了一次", NET.wipes == w0 + 1, str(NET.wipes - w0))
	_ok("⑦ ★身份全清: 账号 / 邮箱 / 昵称 / 默认昵称 / 登录令牌 / 安装号",
		str(gs.account_id) == "" and str(gs.account_email) == "" and str(gs.nickname) == ""
		and str(gs.nickname_default) == "" and str(gs.auth_refresh) == "" and str(gs.install_uid) == "",
		"%s|%s|%s|%s" % [gs.account_id, gs.account_email, gs.nickname, gs.install_uid])
	_ok("⑦ ★进度全清: 币 / 战绩 / 头衔 / 赛季场次 / 背包 / 云版本号",
		int(gs.coins) == 0 and (gs.match_history as Array).is_empty() and (gs.titles as Array).is_empty()
		and int(gs.season_total_battles) == 0 and (gs.inventory as Array).is_empty() and int(gs.cloud_rev) == 0,
		"coins=%d titles=%d" % [int(gs.coins), (gs.titles as Array).size()])
	_ok("⑦ 上传队列清空(旧号的单子不能挂到新号上发)", (gs.ghost_upload_pending as Array).is_empty()
		and (gs.replay_upload_pending as Array).is_empty() and (gs.referee_pending as Dictionary).is_empty())
	_ok("⑦ 设备偏好保留(音量)", is_equal_approx(float(gs.bgm_volume), 0.33), str(gs.bgm_volume))
	_ok("⑦ ★会话令牌清空", SB.access_token() == "" and SB.token_expires_at() == 0)
	_ok("⑦ ★本机文件删掉: .bak / 对手池 / 录像 / 黑名单",
		not FileAccess.file_exists("user://savegame.json.bak") and not FileAccess.file_exists("user://ghost_pool.json")
		and not FileAccess.file_exists(RR.SAVE_DIR + "probe.rpl") and not FileAccess.file_exists(BL.PATH) and BL.count() == 0)
	_ok("⑦ 状态行「账号已删除」", (st as Label).text == DLG.MSG_OK, (st as Label).text)
	_ok("⑦ ★回主菜单(= 项目入口场景)", _hook_calls == [SET.AFTER_DELETE_SCENE]
		and SET.AFTER_DELETE_SCENE == str(ProjectSettings.get_setting("application/run/main_scene", "")), str(_hook_calls))
	## 首次进入流程的条件 —— 与 MainMenuScene._maybe_first_launch_tutorial 同一组判据
	_ok("⑦ ★首次进入流程条件成立: 没看过教程 / 没打过 / 没战绩",
		not bool(gs.onboarded) and int(gs.season_total_battles) == 0 and (gs.match_history as Array).is_empty())
	_ok("⑦ 首次进入: 显示名不再是旧号的(自己起的名 / 冻结的默认名都没了)",
		str(gs.default_nickname()) != "老默认名" and str(gs.default_nickname()) != "老昵称探针", str(gs.default_nickname()))

	SB._transport_for_test = Callable()
	SB._reset_auth_for_test()
	OS.set_environment(SB.ENV_URL, env0)
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	_ok("还原: 后端又是没配", not SB.enabled())

	## ⑧ 纯判据
	_ok("⑧ 2xx + ok:true ⇒ ok", NET.result_of(true, 200, "{\"ok\":true}") == NET.R_OK)
	_ok("⑧ 2xx + 正文 true(不是对象) ⇒ net", NET.result_of(true, 200, "true") == NET.R_NET)
	_ok("⑧ 2xx + 看不懂 ⇒ net", NET.result_of(true, 200, "<html>") == NET.R_NET)
	_ok("⑧ 401 / 403 ⇒ auth", NET.result_of(true, 401, "") == NET.R_AUTH and NET.result_of(true, 403, "") == NET.R_AUTH)
	_ok("⑧ 500 ⇒ net", NET.result_of(true, 500, "{\"ok\":true}") == NET.R_NET)
	_ok("⑧ 被出口拦下 ⇒ blocked", NET.result_of(false, 0, "", true) == NET.R_BLOCKED)
	_ok("⑧ ok:false 其他原因 ⇒ net", NET.result_of(true, 200, "{\"ok\":false,\"reason\":\"x\"}") == NET.R_NET)

	## ⑨ 服务端 / 客户端玩家 ID 同一个算法
	var vec := 0
	var vbad: Array = []
	var f := FileAccess.open(SQL_CHECK, FileAccess.READ)
	if f != null:
		for line in f.get_as_text().split("\n"):
			var ln := line.strip_edges()
			if ln.begins_with("-- TAGVEC "):
				var parts := ln.substr("-- TAGVEC ".length()).split(" ", false)
				if parts.size() == 2:
					vec += 1
					if P2.player_tag(parts[0]) != parts[1]:
						vbad.append("%s→%s≠%s" % [parts[0], P2.player_tag(parts[0]), parts[1]])
	_ok("⑨ 分母: SQL 检查脚本里读到 3 组 TAGVEC", vec == 3, str(vec))
	_ok("⑨ ★服务端 player_tag_of 的向量 == 客户端 player_tag", vbad.is_empty(), str(vbad))
	var mig := FileAccess.get_file_as_string(SQL_MIG)
	_ok("⑨ 迁移: 删号函数收回 anon、只授 authenticated",
		mig.contains("revoke execute on function public.account_delete_self() from anon;")
		and mig.contains("grant execute on function public.account_delete_self() to authenticated;"))
	_ok("⑨ 迁移: 删号函数只认 auth.uid()(不收参数)", mig.contains("function public.account_delete_self() returns jsonb")
		and mig.contains("uid   uuid := auth.uid();"))

	_finish()


func _seed_identity(gs) -> void:
	gs.account_id = FAKE_ACC
	gs.account_email = "probe@example.com"
	gs.nickname = "老昵称探针"
	gs.nickname_default = "老默认名"
	gs.auth_refresh = "probe-refresh"
	gs.install_uid = "abcdefabcdef"
	gs.cloud_rev = 7
	gs.onboarded = true
	gs.coins = 999
	gs.season_total_battles = 12
	gs.match_history = [{"won": true}]
	gs.titles = [{"id": "champion", "week": 1}]
	(gs.inventory as Array).append("p2eq_001")
	gs.ghost_upload_pending = [{"k": 1}]
	gs.replay_upload_pending = [{"id": "x"}]
	gs.referee_pending = {"job_id": 1}
	gs.bgm_volume = 0.33


func _identity_intact(gs) -> bool:
	return str(gs.account_id) == FAKE_ACC and str(gs.account_email) == "probe@example.com" \
		and str(gs.nickname) == "老昵称探针" and str(gs.auth_refresh) == "probe-refresh" \
		and int(gs.coins) == 999 and bool(gs.onboarded)


func _make_local_files() -> void:
	for p in ["user://savegame.json.bak", "user://ghost_pool.json"]:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string("{\"account_id\": \"%s\"}" % FAKE_ACC)
		f.close()
	DirAccess.make_dir_recursive_absolute(RR.SAVE_DIR)
	var g := FileAccess.open(RR.SAVE_DIR + "probe.rpl", FileAccess.WRITE)
	g.store_string("x")
	g.close()
	BL._reset_cache_for_test()
	BL.add("#4PT53K", "被拉黑探针")


func _finish() -> void:
	_ok("★分母: 断言条数 = %d" % NEED, _n + 1 == NEED, str(_n + 1))
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(0 if _fail == 0 else 1)
