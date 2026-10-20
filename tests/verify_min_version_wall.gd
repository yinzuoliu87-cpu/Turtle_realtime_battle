extends Node
## verify_min_version_wall.gd — 强制最低版本(2026-10-19 · 方案书 docs/plans/20261019-服务器裁判.md §4)
##
## 用户 10-19「需要强制最低版本」。判据:
##   本机版本(`application/config/version`, 三段按整数比) < 服务端 `service_status.min_client_version`
##   且这一进程真的问到了服务端 ⇒ 整屏挡墙(VersionWall)挡住、只留「前往更新」; 主菜单开局闸拒;
##   写请求一律不发。等于 / 高于 ⇒ 不挡。离线(问不到)⇒ 不挡。
##
## ★走真入口: 假服务器(注入传输)回 service_status 那一行 → 产品自己 `fetch_status_async` →
##   GameState 下常驻的那一面墙自己刷新。量的是**墙的可见性 + 一次真点击有没有穿过去 +
##   传输层真的收到了哪些请求**, 不是我插的计数器。不向任何外部服务发请求。
## ★每条「挡」都配一条「不挡」的对照(相等 / 更高 / 离线), 否则「挡住了」可以是恒真式。
##
## 会 FAIL 的证明(反向验证, 见报告):
##   · `version_less` 改成字符串比较            ⇒ ① 0.19.9/0.19.10 等格红
##   · `wall_decision` 去掉「问不到不挡」       ⇒ ② 离线格红、⑥ 红
##   · GameState 不 install 墙                  ⇒ ③ 分母红
##   · `_http` 不调 `update_blocks`              ⇒ ④ 写请求放行红
##   · `_battle_block_msg` 去掉版本那一条         ⇒ ③ 主菜单闸红

const SB := preload("res://scripts/net/supabase.gd")

var _fail := 0
var _n := 0
var _min := "0.0.0"
var _status_ok := true
var _post_code := 201
var _reqs: Array = []          # [{m, url, hdr}]


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _transport(m, u, h, _b, cb) -> void:
	var url := str(u)
	_reqs.append({"m": str(m), "url": url, "hdr": PackedStringArray(h)})
	if url.find("/rest/v1/service_status") >= 0 and str(m) == "GET":
		if not _status_ok:
			cb.call({"ok": false, "code": 0, "body": ""})
			return
		cb.call({"ok": true, "code": 200, "body": JSON.stringify([
			{"id": 1, "maintenance": false, "notice": "", "min_client_version": _min}])})
		return
	if url.find("/auth/v1/") >= 0:
		cb.call({"ok": false, "code": 0, "body": ""})   # 身份那条不碰: 令牌由本门禁直接给
		return
	if str(m) == "POST":
		cb.call({"ok": true, "code": _post_code, "body": '{"code":"PT426","message":"update_required"}' if _post_code == 426 else ""})
		return
	cb.call({"ok": false, "code": 0, "body": ""})


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	GameState.test_mode = true
	_t_pure()
	_t_decision()

	var had_env: bool = OS.has_environment(SB.ENV_URL)
	var env0: String = OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	var tok0: String = SB._token
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	SB._transport_for_test = _transport
	SB._token = "gate-token"
	SB._expires_at = 0
	_ok("★分母: 后端真的打开了(注入传输)", SB.enabled())

	var wall: VersionWall = GameState.get_node_or_null(VersionWall.NODE_NAME) as VersionWall
	_ok("③ ★分母: GameState 下常驻着那一面墙", wall != null)
	if wall != null:
		var cv := ReplayRecorder.client_version()
		var p := cv.split(".")
		_ok("★分母: 本机版本是三段整数(%s)" % cv, p.size() == 3 and p[2].is_valid_int())
		var higher := "%s.%s.%d" % [p[0], p[1], int(p[2]) + 1]
		var lower := "%s.%s.%d" % [p[0], p[1], maxi(int(p[2]) - 1, 0)]
		await _t_live(wall, higher, cv, lower)

	SB._transport_for_test = Callable()
	SB._reset_for_test()
	SB._token = tok0
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	if had_env:
		OS.set_environment(SB.ENV_URL, env0)
	else:
		OS.unset_environment(SB.ENV_URL)
	if wall != null:
		wall.refresh()
		_ok("收尾: 后端关掉后墙撤了(不污染同进程别的东西)", not wall.is_blocking())
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 强制最低版本挡墙" if _fail == 0 else "FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


## ① 版本比较纯函数: 穷举一张段值表的所有两两组合, 对照「逐段整数元组」比较。
func _t_pure() -> void:
	print("── ① version_less 穷举 ──")
	var fixed := [
		["0.19.9", "0.19.10", true],      # ★按字符串比会判 false
		["0.19.10", "0.19.9", false],
		["0.19.10", "0.19.10", false],
		["0.9.0", "0.10.0", true],
		["1.0.0", "0.99.99", false],
		["0.19", "0.19.0", false],
		["0.19", "0.19.1", true],
		["0.19.1", "", false],
		["0.19.1", "0.19.x", false],
		["", "0.19.1", false],
		["0.19.571", "0.20.0", true],
		[" 0.19.9 ", "0.19.10", true],
	]
	for c in fixed:
		var got: bool = VersionGate.version_less(str(c[0]), str(c[1]))
		_ok("① %s < %s ⇒ %s" % [c[0], c[1], str(c[2])], got == bool(c[2]), "实际 %s" % str(got))
	## 穷举: 每段取 {0,1,9,10,19,99,100}, 三段 ⇒ 343 个版本, 两两 117649 对。对照元组比较。
	var vals := [0, 1, 9, 10, 19, 99, 100]
	var vs: Array = []
	for a in vals:
		for b in vals:
			for c in vals:
				vs.append([a, b, c])
	var bad := 0
	var n_less := 0
	var first_bad := ""
	for x in vs:
		var sx := "%d.%d.%d" % x
		for y in vs:
			var want: bool = x[0] < y[0] or (x[0] == y[0] and (x[1] < y[1] or (x[1] == y[1] and x[2] < y[2])))
			if want:
				n_less += 1
			if VersionGate.version_less(sx, "%d.%d.%d" % y) != want:
				bad += 1
				if first_bad == "":
					first_bad = "%s vs %d.%d.%d" % [sx, y[0], y[1], y[2]]
	_ok("① 穷举 %d 对 · 其中「小于」%d 对(分母) · 不一致 0" % [vs.size() * vs.size(), n_less],
		bad == 0 and n_less > 0, "不一致 %d, 首个 %s" % [bad, first_bad])


## ② 挡不挡的纯判据: 状态 × 大小关系 × 服务端是否明说。
func _t_decision() -> void:
	print("── ② wall_decision ──")
	var cur := "0.19.9"
	var cases := [
		[SB.ST_OK, "0.19.10", false, true, "问到了 + 低于 ⇒ 挡"],
		[SB.ST_MAINTENANCE, "0.19.10", false, true, "维护中 + 低于 ⇒ 挡"],
		[SB.ST_OK, "0.19.9", false, false, "相等 ⇒ 不挡"],
		[SB.ST_OK, "0.19.8", false, false, "高于 ⇒ 不挡"],
		[SB.ST_OK, "", false, false, "服务端没要求 ⇒ 不挡"],
		[SB.ST_UNREACHABLE, "0.19.10", false, false, "★问不到(离线)⇒ 不挡"],
		[SB.ST_UNKNOWN, "0.19.10", false, false, "★还没问到 ⇒ 不挡"],
		[SB.ST_OFF, "0.19.10", true, false, "没配后端 ⇒ 不挡"],
		[SB.ST_UNREACHABLE, "", true, true, "服务端在别的请求上明说过 ⇒ 挡"],
	]
	for c in cases:
		var got: bool = SB.wall_decision(str(c[0]), str(c[1]), cur, bool(c[2]))
		_ok("② %s" % c[4], got == bool(c[3]), "state=%s min=%s said=%s ⇒ %s" % [c[0], c[1], str(c[2]), str(got)])
	_ok("② 426 回包 = 要更新", VersionGate.is_update_required_response({"code": 426, "body": ""}))
	_ok("② RPC 拒收 reason=update_required = 要更新",
		VersionGate.is_update_required_response({"code": 200, "body": '{"ok":false,"reason":"update_required"}'}))
	_ok("② 普通 403 不算", not VersionGate.is_update_required_response({"code": 403, "body": '{"code":"42501"}'}))
	_ok("② 没发出去(code 0)不算", not VersionGate.is_update_required_response({"code": 0, "body": "update_required"}))
	## 规则版本: 拉对手只拉同一规则版本; 排队单子带自己入队时的规则版本; 旧版本打出来的单子销掉
	var rv := int(preload("res://scripts/gamedata/phase2_config.gd").RULES_VER)
	var tag := "rules_ver=eq.%d" % rv
	_ok("② 积分赛拉对手的查询只要同一规则版本(%s)" % tag, SB.opponents_query(1789948800, 5, "uid-me").find(tag) >= 0)
	_ok("② 周六拉对手的查询只要同一规则版本", SB.gauntlet_query(1789948800, 3, 1, "uid-me").find(tag) >= 0)
	var GU := preload("res://scripts/net/ghost_uploader.gd")
	var now := int(Time.get_unix_time_from_system())
	var e := {"tbl": "ghosts", "wk": now - 3600, "b": 3, "gw": -1, "gl": -1, "snap": {"ghost_id": "g"}, "cv": "0.19.9", "acc": "", "n": 0}
	_ok("② 分母: 这张单子本身发得出去(不给最低版本时)", GU.drop_reason(e, now, "acc") == "", GU.drop_reason(e, now, "acc"))
	_ok("② 单子版本 0.19.9 < 最低 0.19.10 ⇒ 销单", GU.drop_reason(e, now, "acc", "0.19.10").begins_with("old_version"),
		GU.drop_reason(e, now, "acc", "0.19.10"))
	_ok("② 单子版本 = 最低 ⇒ 留着", GU.drop_reason(e, now, "acc", "0.19.9") == "")
	_ok("② 老单子没有 rv ⇒ 行里规则版本 0(新客户端拉不到)", int(GU.build_row(e, "acc").get("rules_ver", -1)) == 0)
	e["rv"] = rv
	_ok("② 单子带 rv ⇒ 行里就是它", int(GU.build_row(e, "acc").get("rules_ver", -1)) == rv)
	_ok("② 商店链接: iOS / Android 都是 https", VersionWall.store_url_for("iOS").begins_with("https://")
		and VersionWall.store_url_for("Android").begins_with("https://"),
		"%s | %s" % [VersionWall.store_url_for("iOS"), VersionWall.store_url_for("Android")])
	## 链接位优先级(2026-10-20 · 方案书 20261020-AppStore上架 §4.6): 正式页 > TestFlight 公开链接 > 首页。
	_ok("② iOS 链接位: 有 App ID ⇒ App Store 正式页", VersionWall.ios_store_url("123", "abc") == "https://apps.apple.com/app/id123",
		VersionWall.ios_store_url("123", "abc"))
	_ok("② iOS 链接位: 只有 TestFlight 代码 ⇒ 公开链接", VersionWall.ios_store_url("", "abc") == "https://testflight.apple.com/join/abc",
		VersionWall.ios_store_url("", "abc"))
	_ok("② iOS 链接位: 都空 ⇒ TestFlight 首页", VersionWall.ios_store_url("", "") == VersionWall.STORE_URL_IOS)
	_ok("② 桌面 / 网页退回 iOS 那一条", VersionWall.store_url_for("Windows") == VersionWall.store_url_for("iOS"))


## 让墙自己去问一次服务状态(走产品的 `_fetch` → `fetch_status_async`), 等回包落地。
func _ask(wall: VersionWall) -> int:
	SB._reset_for_test()
	wall._last_fetch_ms = -100000
	var f0 := wall.fetch_count
	## ★入口用「从后台回前台」那一条通知 —— 它就是产品里回前台重新判的那条路。
	wall._notification(NOTIFICATION_APPLICATION_RESUMED)
	var w := 0
	while w < 30 and SB.ask_count() == 0:
		await get_tree().process_frame
		w += 1
	await get_tree().process_frame
	await get_tree().process_frame
	return wall.fetch_count - f0


## 往视口左上角推一次真的鼠标点击; 返回探针按钮是否被按到。
func _click_through(probe: Button) -> bool:
	var hits := [0]
	var cb := func() -> void: hits[0] += 1
	probe.pressed.connect(cb)
	var pos := Vector2(24, 24)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev)
		await get_tree().process_frame
	probe.pressed.disconnect(cb)
	return hits[0] > 0


func _t_live(wall: VersionWall, higher: String, cv: String, lower: String) -> void:
	## 一颗铺满全屏的探针按钮, 放在普通层 —— 墙不在时点得到它, 墙在时点不到。
	var probe_layer := CanvasLayer.new()
	probe_layer.layer = VersionWall.LAYER - 10   # 高于主菜单各层、低于墙
	add_child(probe_layer)
	var probe := Button.new()
	probe.set_anchors_preset(Control.PRESET_FULL_RECT)
	probe.flat = true
	probe_layer.add_child(probe)
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(menu)
	for _i in range(4):
		await get_tree().process_frame
	var scene0 = get_tree().current_scene

	## ── 低于最低版本 ──
	print("── ③ 低于最低版本(服务端要 %s, 本机 %s) ──" % [higher, cv])
	_min = higher
	_status_ok = true
	var asked := await _ask(wall)
	_ok("③ ★分母: 回前台真的去问了服务状态", asked >= 1 and SB.ask_count() >= 1, "fetch=%d ask=%d" % [asked, SB.ask_count()])
	_ok("③ ★★墙挡住了", wall.is_blocking())
	var blocker := wall.get_node_or_null("Blocker") as Control
	var btn := wall.find_child("GoUpdate", true, false) as Button
	var vp := get_viewport().get_visible_rect().size
	_ok("③ 墙铺满整个视口", blocker != null and blocker.get_global_rect().size.distance_to(vp) < 1.0,
		"%s vs %s" % [str(blocker.get_global_rect().size) if blocker else "null", str(vp)])
	_ok("③ 墙吃点击(MOUSE_FILTER_STOP)", blocker != null and blocker.mouse_filter == Control.MOUSE_FILTER_STOP)
	var btns: Array = wall.find_children("*", "BaseButton", true, false)
	_ok("③ 墙上只有一颗按钮「前往更新」", btns.size() == 1 and btn != null and btn.visible and btn.text == VersionWall.TXT_BUTTON,
		"按钮 %d 颗" % btns.size())
	_ok("③ 按钮换过皮(不是 Godot 默认皮)", btn != null and btn.has_theme_stylebox_override("normal"))
	var vtxt := (wall.find_child("Versions", true, false) as Label).text
	_ok("③ 墙上写着两个版本号", vtxt.find(cv) >= 0 and vtxt.find(higher) >= 0, vtxt)
	_ok("③ ★★一次真点击穿不过墙(探针没被按到)", not await _click_through(probe))
	var urls: Array = []
	wall.open_url_for_test = func(u: String) -> void: urls.append(u)
	btn.pressed.emit()
	_ok("③ 「前往更新」打开本平台的商店链接", urls.size() == 1 and str(urls[0]) == VersionWall.store_url_for(OS.get_name()), str(urls))
	wall.open_url_for_test = Callable()
	_ok("③ ★★主菜单开局闸: 拒, 理由就是需要更新", str(menu._battle_block_msg()) == VersionWall.TXT_TITLE, str(menu._battle_block_msg()))
	var mode0 = GameState.mode
	GameState.mode = "gate_probe"
	menu._start_battle_flow()
	await get_tree().process_frame
	_ok("③ ★★点开始战斗: 没进对局(模式没被改、场景没换)", GameState.mode == "gate_probe" and get_tree().current_scene == scene0,
		"mode=%s" % GameState.mode)
	GameState.mode = mode0
	## 写请求被拦在出口
	print("── ④ 挡住期间不许上传 ──")
	var hdr_ok := false
	for r in _reqs:
		for h in (r["hdr"] as PackedStringArray):
			if h == "%s: %s" % [SB.HDR_CLIENT_VERSION, cv]:
				hdr_ok = true
	_ok("④ 请求头带着 %s: %s" % [SB.HDR_CLIENT_VERSION, cv], hdr_ok)
	var row := SB.ghost_row_from_snapshot({"ghost_id": "g", "season_total_battles": 3}, "11111111-2222-3333-4444-555555555555", 1789948800, 3, cv)
	_ok("④ 行里带着规则版本 rules_ver", int(row.get("rules_ver", -1)) == int(preload("res://scripts/gamedata/phase2_config.gd").RULES_VER), str(row.get("rules_ver")))
	var nb0 := SB.update_blocked_count
	var posts0 := _count_posts("/rest/v1/ghosts")
	SB.upload_ghost_async(row)
	for _i in range(4):
		await get_tree().process_frame
	_ok("④ ★★快照上传没发出去", _count_posts("/rest/v1/ghosts") == posts0, "POST ghosts %d→%d" % [posts0, _count_posts("/rest/v1/ghosts")])
	_ok("④ 分母: 是被版本闸拦的(计数 +1)", SB.update_blocked_count > nb0, "%d→%d" % [nb0, SB.update_blocked_count])
	_ok("④ 读请求不拦(拉对手的查询照常是 GET)", not SB.update_blocks("GET", "http://x/rest/v1/ghosts?a=1"))
	_ok("④ 报错上报照常放行(诊断白名单)", not SB.update_blocks("POST", "http://x/rest/v1/rpc/report_client_error"))
	_ok("④ 决赛战报被拦", SB.update_blocks("POST", "http://x/rest/v1/rpc/finals_report"))
	_ok("④ 录像上传被拦", SB.update_blocks("POST", "http://x/rest/v1/matches"))
	_ok("④ 云存档被拦", SB.update_blocks("POST", "http://x/rest/v1/rpc/push_save"))

	## 布局: 16:9 与 19.5:9 下整块内容在视口内、正文不溢出
	print("── ⑤ 布局 ──")
	for v in [Vector2i(1280, 720), Vector2i(1560, 720)]:
		var sv := SubViewport.new()
		sv.size = v
		sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(sv)
		var w2 := VersionWall.new()
		sv.add_child(w2)
		for _i in range(4):
			await get_tree().process_frame
		var box := w2.find_child("Box", true, false) as Control
		var body := w2.find_child("Body", true, false) as Label
		var b2 := w2.find_child("GoUpdate", true, false) as Control
		var r := box.get_global_rect() if box else Rect2()
		var inside: bool = box != null and r.position.x >= 0 and r.position.y >= 0 and r.end.x <= v.x and r.end.y <= v.y
		var lines_fit: bool = body != null and body.get_line_count() * body.get_line_height() <= body.size.y + 1.0
		_ok("⑤ %dx%d: 墙显示着, 内容块在视口内" % [v.x, v.y], w2.is_blocking() and inside, str(r))
		_ok("⑤ %dx%d: 正文不溢出(%d 行)" % [v.x, v.y, body.get_line_count() if body else -1], lines_fit)
		_ok("⑤ %dx%d: 按钮热区够大(≥ 44 高)" % [v.x, v.y], b2 != null and b2.size.y >= 44.0 and b2.get_global_rect().end.y <= v.y,
			str(b2.get_global_rect()) if b2 else "null")
		sv.queue_free()
		await get_tree().process_frame

	## ── 等于 ──
	print("── ⑥ 等于 / 高于 / 离线 ⇒ 不挡 ──")
	_min = cv
	await _ask(wall)
	_ok("⑥ 分母: 问到了(相等)", SB.service_state() == SB.ST_OK, SB.service_state())
	_ok("⑥ ★相等 ⇒ 不挡", not wall.is_blocking())
	_ok("⑥ ★相等 ⇒ 点击穿得过去(对照组: 探针被按到)", await _click_through(probe))
	_ok("⑥ 相等 ⇒ 主菜单闸不因版本拒", str(menu._battle_block_msg()) != VersionWall.TXT_TITLE, str(menu._battle_block_msg()))
	var posts1 := _count_posts("/rest/v1/ghosts")
	SB.upload_ghost_async(row)
	for _i in range(4):
		await get_tree().process_frame
	_ok("⑥ 相等 ⇒ 快照上传真的发出去了(对照组)", _count_posts("/rest/v1/ghosts") > posts1)
	_min = lower
	await _ask(wall)
	_ok("⑥ ★本机更高(服务端要 %s)⇒ 不挡" % lower, SB.service_state() == SB.ST_OK and not wall.is_blocking())
	## ── 离线 ──
	_min = higher
	_status_ok = false
	await _ask(wall)
	_ok("⑥ 分母: 这一次确实问不到", SB.service_state() == SB.ST_UNREACHABLE, SB.service_state())
	_ok("⑥ ★★离线(问不到)⇒ 不挡", not wall.is_blocking())
	## 先问到「低于」再断网: 也不挡(不把上一次的答案当成现在的)
	_status_ok = true
	await _ask(wall)
	_ok("⑥ 分母: 先问到了「低于」(挡)", wall.is_blocking())
	_status_ok = false
	wall._last_fetch_ms = -100000
	var a0 := SB.ask_count()
	wall._notification(NOTIFICATION_APPLICATION_RESUMED)
	for _i in range(4):
		await get_tree().process_frame
	_ok("⑥ 回前台再问一次、这次断网 ⇒ 撤墙", SB.ask_count() > a0 and not wall.is_blocking(), "ask %d→%d state=%s" % [a0, SB.ask_count(), SB.service_state()])

	## ── 服务端在别的请求上回 426 ──
	print("── ⑦ 服务端拒收(426)⇒ 挡 ──")
	SB._reset_for_test()
	_post_code = 426
	var n = SB._spawn()
	n._http("POST", SB.base_url() + "/rest/v1/rpc/finals_report", "{}", func(_r): pass, "Content-Type: application/json")
	for _i in range(3):
		await get_tree().process_frame
	_ok("⑦ 状态行没问到, 但服务端回了 426 ⇒ 挡", SB.service_state() == SB.ST_UNKNOWN and wall.is_blocking(), SB.service_state())
	_post_code = 201
	_status_ok = true
	_min = cv
	await _ask(wall)
	_ok("⑦ 之后问到「不再要求」⇒ 撤墙", not wall.is_blocking())
	n.queue_free()

	menu.queue_free()
	probe_layer.queue_free()
	for _i in range(3):
		await get_tree().process_frame


func _count_posts(path: String) -> int:
	var c := 0
	for r in _reqs:
		if str(r["m"]) == "POST" and str(r["url"]).find(path) >= 0:
			c += 1
	return c
