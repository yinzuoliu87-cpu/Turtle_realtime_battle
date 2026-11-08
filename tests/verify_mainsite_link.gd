extends Node
## verify_mainsite_link.gd —— 设置页「龟投账号」登录绑定 + 换号收尾 + 文案红线(2026-11-08 · 方案书 20261107 §4.1)
##
## ① 登录状态机(假网关回包, 走真入口 start_link / poll_now / 轮询节点的回前台通知):
##    A pending → confirmed(switched:false): POST {网关}/app/link/start {device}, 带本人令牌; 打开的是回包里的确认页地址;
##      轮询 POST /app/link/poll {code}; 回 pending 仍等; 回前台立即查一次; confirmed ⇒ 已绑定、不再轮询、顺手刷新拥有的龟
##    B expired: 网关回 expired ⇒ 登录码已过期、不再轮询; 本机 5 分钟到点 ⇒ 不发请求直接过期; 网关回 ok:false ⇒ 过期
##    C switched: confirmed + switched:true + session ⇒ 等确认(本机身份与进度一个字不动); 取消 ⇒ 不换;
##      确认 ⇒ 换成 session 那个号(令牌 / refresh / 账号 id)、本机进度回到全新(旧号不合并)、不重走首次进入、记成已绑定;
##      目标号有邮箱 ⇒ 拉它的云存档(换设备同一段收尾)
## ② 设置页账号框那一行(真场景 Settings.tscn): 未绑定 =「龟投账号」+「未绑定」+「绑定」键 / 等待确认 =「取消」键 /
##    已绑定 =「已绑定」、没有按钮; 点「绑定」真发开始请求; 换号确认框写清不合并与没绑邮箱无法恢复、按钮是 card_button 皮,
##    点取消真不换、点确认真换; 这一行在设计框内、不压账号框里别的键; 屏上没有「主站」「龟币」「金额」
## ③ 删号: wipe_local 之后本地龟投绑定状态清掉(缓存文件删掉; 同一账号再登回来也不再说已绑定)
## ④ 文案红线(静态扫): 屏幕文案快照(gd + data)与教程步骤里没有「主站」「龟币」「金额」;
##    选龟页源码(去掉注释)里没有龟投入口 / 外链, 实建选龟页屏上没有「龟投」
## ⑤ 纯判据: parse / code_ok / url_ok / account_from_session / view_of
##
## 跑法: bash godot-quiet.sh res://tests/verify_mainsite_link.tscn --quit-after 500

const SB := preload("res://scripts/net/supabase.gd")
const ML := preload("res://scripts/net/mainsite_link.gd")
const AD := preload("res://scripts/net/account_delete.gd")
const ROW := preload("res://scripts/scenes/settings/mainsite_link_row.gd")
const DLG := preload("res://scripts/scenes/settings/mainsite_link_dialog.gd")
const SET_SCENE := "res://scenes/Settings.tscn"
const TS_SCENE := "res://scenes/TeamSelect.tscn"

const GW := "https://gw.test"
const ACC1 := "a1b2c3d4-1111-4222-8333-444455556666"
const ACC2 := "b2c3d4e5-2222-4333-8444-555566667777"
const ACC3 := "c3d4e5f6-3333-4444-8555-666677778888"
const CODE1 := "Lk7_zQ-9aB"
const URL1 := "https://www.example.test/game/link?code=Lk7_zQ-9aB"
const BANNED := ["主站", "龟币", "金额"]
const NEED := 85    # 分母: 断言条数一条不能少(少了 = 半路中止)

var _n := 0
var _fail := 0
var _reqs: Array = []
var _opened: Array = []
var _poll_replies: Array = []
var _me_reply := {"linked": false, "user_id": null, "owned": []}
var _start_reply := {}
var _hook_calls := 0
var _poll_replies_last: Dictionary = {}


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _frames(k: int) -> void:
	for i in range(k):
		await get_tree().process_frame


func _transport(m: String, u: String, h: PackedStringArray, b: String, cb: Callable) -> void:
	_reqs.append({"m": m, "u": u, "h": h, "b": b})
	var body := ""
	if u == GW + ML.P_START:
		body = JSON.stringify(_start_reply)
	elif u == GW + ML.P_POLL:
		var r: Dictionary = _poll_replies.pop_front() if not _poll_replies.is_empty() else {"ok": true, "status": "pending", "switched": false}
		_poll_replies_last = r
		body = JSON.stringify(r)
	elif u == GW + ML.P_PETS:
		body = JSON.stringify({"ok": true, "linked": true, "owned": ["basic", "stone"]})
	elif u.ends_with(ML.RPC_ME):
		body = JSON.stringify(_me_reply)
	elif u.find("/rest/v1/saves?") >= 0:
		body = "[]"
	else:
		cb.call({"ok": false, "code": 0, "body": ""})
		return
	cb.call({"ok": true, "code": 200, "body": body})


func _count(path: String) -> int:
	var k := 0
	for r in _reqs:
		if str(r["u"]).find(path) >= 0:
			k += 1
	return k


func _last(path: String) -> Dictionary:
	for i in range(_reqs.size() - 1, -1, -1):
		if str(_reqs[i]["u"]).find(path) >= 0:
			return _reqs[i]
	return {}


func _body(r: Dictionary) -> Dictionary:
	var j := JSON.new()
	if j.parse(str(r.get("b", ""))) == OK and j.data is Dictionary:
		return j.data
	return {}


func _b64url(s: String) -> String:
	return Marshalls.utf8_to_base64(s).replace("+", "-").replace("/", "_").replace("=", "")


func _jwt(claims: Dictionary) -> String:
	return _b64url(JSON.stringify({"alg": "HS256", "typ": "JWT"})) + "." + _b64url(JSON.stringify(claims)) + ".sig"


func _switch_reply(acc: String, mail: String, rt: String) -> Dictionary:
	var tok := _jwt({"sub": acc, "email": mail, "exp": int(Time.get_unix_time_from_system()) + 3600, "role": "authenticated"})
	return {"ok": true, "status": "confirmed", "switched": true, "session": {"access_token": tok, "refresh_token": rt}}


func _seed(gs, acc: String) -> void:
	gs.account_id = acc
	gs.account_email = ""
	gs.nickname = "旧号昵称"
	gs.auth_refresh = "rt-1"
	gs.coins = 999
	gs.season_total_battles = 5
	gs.match_history = [{"won": true}]
	gs.onboarded = true
	SB._token = "probe-token"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	SB._session_lost = false


## 开始登录并等到「等待确认」; 轮询节点的节拍停掉(量「回前台立即查」与轮询次数时不让 2 秒节拍掺进来)。
func _start_pending() -> void:
	_start_reply = {"ok": true, "code": CODE1, "url": URL1, "expires_in": 300}
	ML.start_link()
	await _frames(4)
	var p := ML.poller()
	if p != null:
		for c in p.get_children():
			if c is Timer:
				(c as Timer).paused = true


func _ready() -> void:
	await get_tree().process_frame
	print("=== 龟投账号登录绑定 ===")
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		_ok("分母: GameState", false)
		_finish()
		return
	gs.test_mode = true
	var env0 := OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "https://example.invalid")
	ProjectSettings.set_setting(SB.SETTING_KEY, "test-key")
	SB._reset_auth_for_test()
	SB._transport_for_test = _transport
	ML._reset_for_test()
	ML.gateway_override = GW
	ML.open_url_sink = func(u: String) -> void: _opened.append(u)
	_seed(gs, ACC1)
	_ok("分母: 后端与网关算配上了", SB.enabled() and ML.enabled())

	await _t_confirm(gs)
	await _t_expire(gs)
	await _t_switch(gs)
	await _t_settings(gs)
	_t_delete(gs)
	await _t_copy()
	_t_pure()

	ROW.after_switch_hook = Callable()
	ML.open_url_sink = Callable()
	ML.gateway_override = ""
	ML._reset_for_test()
	SB._transport_for_test = Callable()
	SB._reset_auth_for_test()
	OS.set_environment(SB.ENV_URL, env0)
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	_ok("还原: 后端又是没配", not SB.enabled())
	_finish()


# ① A ─────────────────────────────────────────────────────────
func _t_confirm(gs) -> void:
	print("── ① A 等待确认 → 已绑定 ──")
	_reqs.clear()
	_opened.clear()
	_ok("A 分母: 开始前不知道绑没绑", ML.linked_state() == -1, str(ML.linked_state()))
	await _start_pending()
	var st := _last(ML.P_START)
	_ok("A ★点绑定 ⇒ POST {网关}/app/link/start", str(st.get("m", "")) == "POST" and str(st.get("u", "")) == GW + ML.P_START, str(st.get("u", "")))
	_ok("A 开始请求正文 = {device}(设备标识)", _body(st) == {"device": ML.device_id()}, str(_body(st)))
	_ok("A 带的是本人令牌(网关拿它换账号)", "Authorization: Bearer probe-token" in Array(st.get("h", PackedStringArray())))
	_ok("A ★状态 = 等待确认, 记下了登录码", ML.state() == ML.ST_PENDING and ML.code() == CODE1, ML.state())
	_ok("A ★系统浏览器打开的是回包里的确认页(且只开一次)", _opened == [URL1], str(_opened))
	var p := ML.poller()
	_ok("A 轮询节点挂在 root 上(换场景不断)", p != null and p.get_parent() == get_tree().root)
	var tm: Timer = null
	if p != null:
		for c in p.get_children():
			if c is Timer:
				tm = c
	_ok("A 轮询节拍 2 秒、接在 _on_tick 上", tm != null and is_equal_approx(tm.wait_time, ML.POLL_SEC) and ML.POLL_SEC == 2.0
		and tm.timeout.is_connected(p._on_tick))
	_poll_replies = [{"ok": true, "status": "pending", "switched": false}]
	ML.poll_now()
	await _frames(3)
	var pl := _last(ML.P_POLL)
	_ok("A 轮询 POST /app/link/poll {code}", str(pl.get("m", "")) == "POST" and _body(pl) == {"code": CODE1}, str(_body(pl)))
	_ok("A 回 pending ⇒ 仍在等", ML.state() == ML.ST_PENDING)
	if p != null:
		var n0 := _count(ML.P_POLL)
		_poll_replies = [{"ok": true, "status": "confirmed", "switched": false}]
		p.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
		await _frames(4)
		_ok("A ★回前台 ⇒ 立刻查了一次(不等 2 秒节拍)", _count(ML.P_POLL) == n0 + 1, "%d" % (_count(ML.P_POLL) - n0))
	_ok("A ★confirmed + switched:false ⇒ 已绑定", ML.state() == ML.ST_CONFIRMED and ML.linked_state() == 1, ML.state())
	_ok("A 身份没换", str(gs.account_id) == ACC1 and SB.access_token() == "probe-token")
	_ok("A 绑完顺手刷新拥有的龟(/app/pets/refresh)", _count(ML.P_PETS) >= 1 and ML.owned_ids() == ["basic", "stone"], str(ML.owned_ids()))
	var n1 := _count(ML.P_POLL)
	ML.poll_now()
	if p != null and is_instance_valid(p):
		p._on_tick()
	await _frames(3)
	_ok("A ★绑完不再轮询, 轮询节点自己退场", _count(ML.P_POLL) == n1 and ML.poller() == null, "%d" % (_count(ML.P_POLL) - n1))


# ① B ─────────────────────────────────────────────────────────
func _t_expire(_gs) -> void:
	print("── ① B 过期 ──")
	ML._reset_for_test()
	ML.gateway_override = GW
	await _start_pending()
	_ok("B 分母: 等待确认", ML.state() == ML.ST_PENDING)
	_poll_replies = [{"ok": true, "status": "expired", "switched": false}]
	ML.poll_now()
	await _frames(3)
	_ok("B ★网关回 expired ⇒ 登录码已过期", ML.state() == ML.ST_EXPIRED, ML.state())
	var n0 := _count(ML.P_POLL)
	ML.poll_now()
	await _frames(2)
	_ok("B 过期后不再轮询", _count(ML.P_POLL) == n0)
	_ok("B 过期 ⇒ 行上「登录码已过期」+ 可以重新绑定", ROW.view_of(ML.state(), ML.linked_state(), ML.reason(), false) == {
		"state": ROW.S_EXPIRED, "col": ROW.C_ERR, "btn": ROW.L_BIND, "btn_on": true, "act": "bind"})
	## 本机到点
	await _start_pending()
	_ok("B 过期之后能重新开始", ML.state() == ML.ST_PENDING and _opened.size() >= 2)
	ML.now_override = Time.get_unix_time_from_system() + float(ML.CAP_SEC) + 1.0
	var n1 := _count(ML.P_POLL)
	ML.poll_now()
	await _frames(2)
	_ok("B ★本机 5 分钟到点 ⇒ 不发请求直接过期", ML.state() == ML.ST_EXPIRED and _count(ML.P_POLL) == n1, ML.state())
	ML.now_override = 0.0
	## 网关明说这个码不行(ok:false)
	await _start_pending()
	_poll_replies = [{"ok": false, "reason": "bad_code"}]
	ML.poll_now()
	await _frames(3)
	_ok("B 网关回 ok:false ⇒ 过期(不再空等)", ML.state() == ML.ST_EXPIRED, ML.state())
	## 取消
	await _start_pending()
	ML.cancel_link()
	var n2 := _count(ML.P_POLL)
	ML.poll_now()
	await _frames(2)
	_ok("B 等待中点取消 ⇒ 登录已取消、不再轮询", ML.state() == ML.ST_CANCELLED and _count(ML.P_POLL) == n2, ML.state())


# ① C ─────────────────────────────────────────────────────────
func _t_switch(gs) -> void:
	print("── ① C 换号 ──")
	ML._reset_for_test()
	ML.gateway_override = GW
	_seed(gs, ACC1)
	await _start_pending()
	_poll_replies = [_switch_reply(ACC2, "", "rt-2")]
	ML.poll_now()
	await _frames(3)
	_ok("C ★confirmed + switched:true ⇒ 等玩家确认", ML.state() == ML.ST_SWITCH_ASK and ML.switch_target() == ACC2, ML.state())
	_ok("C ★确认之前本机身份与进度一个字不动", str(gs.account_id) == ACC1 and SB.access_token() == "probe-token"
		and str(gs.auth_refresh) == "rt-1" and int(gs.coins) == 999)
	ML.decline_switch()
	_ok("C 取消 ⇒ 不换号、登录已取消", ML.state() == ML.ST_CANCELLED and str(gs.account_id) == ACC1 and int(gs.coins) == 999)
	_ok("C 取消之后 confirm 不生效", not ML.confirm_switch() and str(gs.account_id) == ACC1)
	await _start_pending()
	_poll_replies = [_switch_reply(ACC2, "", "rt-2")]
	ML.poll_now()
	await _frames(3)
	var s0 := ML.switches
	var saves0 := _count("/rest/v1/saves")
	var want_tok := str(((_poll_replies_last as Dictionary).get("session", {}) as Dictionary).get("access_token", ""))
	_ok("C 分母: 又到了等确认", ML.state() == ML.ST_SWITCH_ASK and want_tok != "")
	_ok("C ★确认 ⇒ 换了", ML.confirm_switch() and ML.switches == s0 + 1)
	_ok("C ★换成 session 那个号: 账号 id / 令牌 / refresh", str(gs.account_id) == ACC2 and SB.access_token() == want_tok
		and str(gs.auth_refresh) == "rt-2", str(gs.account_id))
	_ok("C ★旧号不合并: 本机进度回到全新(币 / 场次 / 战绩 / 昵称)", int(gs.coins) == 0 and int(gs.season_total_battles) == 0
		and (gs.match_history as Array).is_empty() and str(gs.nickname) == "", "coins=%d" % int(gs.coins))
	_ok("C 换号不重走首次进入流程", bool(gs.onboarded))
	_ok("C ★新号记成已绑定", ML.state() == ML.ST_CONFIRMED and ML.linked_state() == 1)
	await _frames(3)
	_ok("C 目标号没绑邮箱 ⇒ 不拉云存档(没有可拉的)", _count("/rest/v1/saves") == saves0)
	## 目标号有邮箱 ⇒ 拉它的云存档(换设备那段收尾)
	await _start_pending()
	_poll_replies = [_switch_reply(ACC3, "c3@example.com", "rt-3")]
	ML.poll_now()
	await _frames(3)
	ML.confirm_switch()
	await _frames(4)
	var sv := _last("/rest/v1/saves")
	_ok("C ★目标号有邮箱 ⇒ 拉它的云存档(GET saves?account_id=eq.<新号>)", str(sv.get("m", "")) == "GET"
		and str(sv.get("u", "")).contains("account_id=eq." + ACC3) and str(gs.account_email) == "c3@example.com", str(sv.get("u", "")))
	## session 坏了
	ML._reset_for_test()
	ML.gateway_override = GW
	await _start_pending()
	_poll_replies = [{"ok": true, "status": "confirmed", "switched": true, "session": {"access_token": "x", "refresh_token": "y"}}]
	ML.poll_now()
	await _frames(3)
	_ok("C session 认不出账号 ⇒ 登录失败, 不换号", ML.state() == ML.ST_ERROR and str(gs.account_id) == ACC3, ML.state())


# ② ─────────────────────────────────────────────────────────
func _open_settings() -> Control:
	var inst: Control = (load(SET_SCENE) as PackedScene).instantiate()
	add_child(inst)
	inst.set_anchors_preset(Control.PRESET_TOP_LEFT)
	inst.size = Vector2(1280, 720)
	await _frames(6)
	return inst


func _txt(root: Node, nm: String) -> String:
	var n = root.find_child(nm, true, false)
	if n is Label:
		return (n as Label).text
	if n is Button:
		return (n as Button).text
	return "<无>"


func _all_texts(root: Node, out: Array) -> void:
	if root is Label and (root as Label).visible:
		out.append((root as Label).text)
	elif root is Button and (root as Button).visible:
		out.append((root as Button).text)
	for c in root.get_children():
		_all_texts(c, out)


func _t_settings(gs) -> void:
	print("── ② 设置页账号框 ──")
	ML._reset_for_test()
	ML.gateway_override = GW
	_seed(gs, ACC1)
	_me_reply = {"linked": false, "user_id": null, "owned": []}
	var me0 := _count(ML.RPC_ME)
	var s: Control = await _open_settings()
	var row = s.find_child(ROW.N_ROW, true, false)
	var btn = s.find_child(ROW.N_BTN, true, false)
	_ok("② 分母: 账号框里建了龟投那一行", row is Control and btn is Button)
	if not (row is Control and btn is Button):
		s.queue_free()
		return
	_ok("② 进页问了一次 mainsite_me(POST rpc)", _count(ML.RPC_ME) == me0 + 1 and str(_last(ML.RPC_ME).get("m", "")) == "POST")
	_ok("② ★未绑定: 「龟投账号」+「未绑定」+「绑定」键", _txt(s, ROW.N_HEAD) == "龟投账号" and _txt(s, ROW.N_STATE) == "未绑定"
		and (btn as Button).visible and (btn as Button).text == "绑定" and not (btn as Button).disabled,
		"%s / %s / %s" % [_txt(s, ROW.N_HEAD), _txt(s, ROW.N_STATE), (btn as Button).text])
	## 版面: 设计框内 / 不压账号框里的别的键
	var rr: Rect2 = (row as Control).get_rect()
	var hits: Array = []
	for b in s.find_children("*", "Button", true, false):
		if b == btn or not (b as Button).visible:
			continue
		if (b as Control).get_global_rect().intersects((row as Control).get_global_rect()):
			hits.append(str(b.name))
	_ok("② 这一行在 1280×720 设计框内、不压别的键", Rect2(0, 0, 1280, 720).encloses(rr) and hits.is_empty(), "%s %s" % [rr, hits])
	var bad: Array = []
	var texts: Array = []
	_all_texts(s, texts)
	for t in texts:
		for w in BANNED:
			if str(t).contains(w):
				bad.append(t)
	_ok("② 屏上没有「主站」「龟币」「金额」(扫了 %d 条字)" % texts.size(), bad.is_empty() and texts.size() >= 15, str(bad))
	## 点「绑定」
	var st0 := _count(ML.P_START)
	_start_reply = {"ok": true, "code": CODE1, "url": URL1, "expires_in": 300}
	(btn as Button).pressed.emit()
	await _frames(5)
	_ok("② ★点「绑定」真发了开始请求、浏览器打开确认页", _count(ML.P_START) == st0 + 1 and _opened.back() == URL1)
	_ok("② ★等待确认: 状态「等待确认」+「取消」键", _txt(s, ROW.N_STATE) == "等待确认" and (btn as Button).text == "取消"
		and not (btn as Button).disabled, _txt(s, ROW.N_STATE))
	## 换号确认框(真点)。当前号带着内部邮箱(解绑过的号会留着它): 不算玩家绑过邮箱 ⇒ 照「没绑邮箱」说。
	gs.account_email = ACC1 + "@link.turtlearena.xyz"
	_poll_replies = [_switch_reply(ACC2, "", "rt-2")]
	ML.poll_now()
	await _frames(4)
	var lay = s.get_node_or_null(DLG.LAYER)
	_ok("② ★该龟投账号绑着别的号 ⇒ 设置页上弹换号确认框", lay is Control)
	if lay is Control:
		var body := _txt(lay, DLG.BODY)
		_ok("② 确认框标题「切换账号」", _txt(lay, DLG.TITLE) == "切换账号")
		_ok("② ★确认框写清: 本机当前进度不会合并 / 没绑邮箱切换后无法恢复", body.contains("本机当前进度不会合并到该账号")
			and body.contains(DLG.B_NOMAIL) and body == DLG.body_text(false), body)
		_ok("② 有邮箱的号不印「无法恢复」那句", not DLG.body_text(true).contains(DLG.B_NOMAIL))
		var cb = lay.find_child(DLG.BTN_CANCEL, true, false)
		var okb = lay.find_child(DLG.BTN_OK, true, false)
		var sk = (okb as Button).get_theme_stylebox("normal") if okb is Button else null
		_ok("② 框里的按钮是 card_button 皮(不是木牌)", sk is StyleBoxFlat and (sk as StyleBoxFlat).bg_color.is_equal_approx(Color("#6a3f1c"))
			and (okb as Button).text == "确认切换" and (cb as Button).text == "取消")
		(cb as Button).pressed.emit()
		await _frames(3)
		_ok("② ★点取消 ⇒ 框关、不换号、行上「登录已取消」", s.get_node_or_null(DLG.LAYER) == null and str(gs.account_id) == ACC1
			and _txt(s, ROW.N_STATE) == "登录已取消" and (btn as Button).text == "绑定", _txt(s, ROW.N_STATE))
		## 再来一次, 点确认
		(btn as Button).pressed.emit()
		await _frames(5)
		_poll_replies = [_switch_reply(ACC2, "", "rt-2")]
		ML.poll_now()
		await _frames(4)
		lay = s.get_node_or_null(DLG.LAYER)
		_hook_calls = 0
		ROW.after_switch_hook = func() -> void: _hook_calls += 1
		if lay is Control:
			(lay.find_child(DLG.BTN_OK, true, false) as Button).pressed.emit()
			await _frames(3)
		_ok("② ★点确认切换 ⇒ 换成那个号、重开设置页一次", str(gs.account_id) == ACC2 and _hook_calls == 1, "%s %d" % [gs.account_id, _hook_calls])
		ROW.after_switch_hook = Callable()
	s.queue_free()
	await _frames(2)
	## 已绑定
	_me_reply = {"linked": true, "user_id": "GEACjjPJERy", "owned": ["basic"]}
	var s2: Control = await _open_settings()
	var b2 = s2.find_child(ROW.N_BTN, true, false)
	_ok("② ★已绑定: 「龟投账号」+「已绑定」、没有按钮", _txt(s2, ROW.N_HEAD) == "龟投账号" and _txt(s2, ROW.N_STATE) == "已绑定"
		and b2 is Button and not (b2 as Button).visible, _txt(s2, ROW.N_STATE))
	s2.queue_free()
	await _frames(2)
	await _t_internal_mail(gs)
	## 服务器说没绑(别处解绑过)⇒ 本机缓存跟着改
	_me_reply = {"linked": false, "user_id": null, "owned": []}
	var s3: Control = await _open_settings()
	_ok("② 服务器说没绑 ⇒ 行上跟着变回「未绑定」", _txt(s3, ROW.N_STATE) == "未绑定" and ML.linked_state() == 0, _txt(s3, ROW.N_STATE))
	s3.queue_free()
	await _frames(2)
	## 没配后端 ⇒ 整行不建(与账号框同一族)
	SB._transport_for_test = Callable()
	OS.set_environment(SB.ENV_URL, " ")
	var s4: Control = await _open_settings()
	_ok("② 没配后端 ⇒ 龟投那一行不建", s4.find_child(ROW.N_ROW, true, false) == null)
	s4.queue_free()
	await _frames(2)
	OS.set_environment(SB.ENV_URL, "https://example.invalid")
	SB._transport_for_test = _transport


## ②′ 内部邮箱(主会话 11-08): 服务器给绑定 / 换号的号补 `<账号ID>@link.turtlearena.xyz` ——
##   设置页不出现这个邮箱、不说「已绑定：邮箱」, 龟投那一行说已绑定; 进度照常同步(不说「无法恢复」); 邮箱框 / 删号框也不带出来。
func _t_internal_mail(gs) -> void:
	print("── ②′ 内部邮箱的号 ──")
	var acc := str(gs.account_id)
	var imail := acc + "@link.turtlearena.xyz"
	gs.account_email = imail
	_me_reply = {"linked": true, "user_id": "GEACjjPJERy", "owned": ["basic"]}
	_ok("②′ 分母: 内部邮箱认得出(大小写不论)、普通邮箱不算", ML.is_internal_email(imail) and ML.is_internal_email("X@LINK.TurtleArena.xyz")
		and not ML.is_internal_email("a@turtlearena.xyz") and not ML.is_internal_email("lisa@example.com"))
	_ok("②′ ★进度照常同步(非匿名号, 有意如此)", SB.sync_allowed(acc, imail, "probe-token"))
	var s: Control = await _open_settings()
	var texts: Array = []
	_all_texts(s, texts)
	var leak: Array = []
	for t in texts:
		if str(t).contains("turtlearena") or str(t).contains(acc + "@") or str(t).begins_with("已绑定："):
			leak.append(t)
	_ok("②′ ★设置页屏上不出现内部邮箱、不说「已绑定：邮箱」(扫了 %d 条字)" % texts.size(), leak.is_empty() and texts.size() >= 15, str(leak))
	_ok("②′ ★龟投那一行: 已绑定", _txt(s, ROW.N_STATE) == "已绑定" and _txt(s, ROW.N_HEAD) == "龟投账号", _txt(s, ROW.N_STATE))
	_ok("②′ 邮箱那张卡: 未绑定邮箱 + 云端同步已开启(不说「无法恢复」)", _txt(s, "AcctRowSub") == "未绑定邮箱"
		and _txt(s, "AcctRowNote") == "云端同步已开启，可在其他设备登录恢复进度", "%s / %s" % [_txt(s, "AcctRowSub"), _txt(s, "AcctRowNote")])
	_ok("②′ 邮箱键是「绑定邮箱」(不是「更换邮箱」)", _txt(s, "AcctRowBtnBind") == "绑定邮箱", _txt(s, "AcctRowBtnBind"))
	var bb = s.find_child("AcctRowBtnBind", true, false)
	if bb is Button:
		(bb as Button).pressed.emit()
		await _frames(3)
	var ed = s.get("_email_edit")
	_ok("②′ 点「绑定邮箱」: 邮箱输入框不预填内部邮箱", ed is LineEdit and (ed as LineEdit).text == "", str((ed as LineEdit).text) if ed is LineEdit else "没开框")
	s.queue_free()
	await _frames(2)
	var s2: Control = await _open_settings()
	var db = s2.find_child("AcctRowBtnDelete", true, false)
	var body2 := "<没开框>"
	if db is Button:
		(db as Button).pressed.emit()
		await _frames(2)
		var lay = s2.get_node_or_null("AccountDeleteLayer")
		if lay is Control:
			(lay.find_child("AccountDeleteNext", true, false) as Button).pressed.emit()
			await _frames(2)
			body2 = _txt(lay, "AccountDeleteBody")
	_ok("②′ 删号确认框第二步不带出内部邮箱", body2 != "<没开框>" and not body2.contains("turtlearena") and not body2.contains("邮箱"), body2)
	_ok("②′ 换号确认框按「没绑邮箱」说(内部邮箱不算)", ML.user_email() == "")
	s2.queue_free()
	await _frames(2)
	gs.account_email = ""


# ③ ─────────────────────────────────────────────────────────
func _t_delete(gs) -> void:
	print("── ③ 删号清掉绑定 ──")
	ML._reset_for_test()
	gs.account_id = ACC1
	ML._note(ACC1, true, "GEACjjPJERy", ["basic"])
	_ok("③ 分母: 删号前已绑定、缓存文件在", ML.linked_state() == 1 and FileAccess.file_exists(ML.CACHE_PATH))
	AD.wipe_local()
	_ok("③ ★删号后缓存文件删掉", not FileAccess.file_exists(ML.CACHE_PATH))
	_ok("③ ★删号后不再说已绑定", ML.linked_state() != 1 and ML.owned_ids().is_empty(), str(ML.linked_state()))
	gs.account_id = ACC1
	_ok("③ ★同一账号 id 再出现也不沿用删号前的绑定(当作不知道, 重新问服务器)", ML.linked_state() == -1, str(ML.linked_state()))


# ④ ─────────────────────────────────────────────────────────
func _banned_hits(lines: Array) -> Array:
	var out: Array = []
	for ln in lines:
		for w in BANNED:
			if str(ln).contains(w):
				out.append(str(ln))
				break
	return out


## 去掉 GDScript 注释(引号里的 # 不算), 只看代码。
func _code_only(src: String) -> String:
	var out := PackedStringArray()
	for line in src.split("\n"):
		var q := ""
		var cut := line.length()
		var i := 0
		while i < line.length():
			var ch := line[i]
			if q != "":
				if ch == "\\":
					i += 2
					continue
				if ch == q:
					q = ""
			elif ch == "\"" or ch == "'":
				q = ch
			elif ch == "#":
				cut = i
				break
			i += 1
		out.append(line.substr(0, cut))
	return "\n".join(out)


const TS_BAN := ["龟投", "turtlebet", "mainsite", "shell_open", "MainsiteLink", "mainsite_link", "turtlearena", "http://", "https://"]


func _ts_hits(src: String) -> Array:
	var code := _code_only(src)
	var out: Array = []
	for w in TS_BAN:
		if code.contains(w):
			out.append(w)
	return out


func _t_copy() -> void:
	print("── ④ 文案红线 ──")
	var lines: Array = []
	for p in ["res://tests/golden/gd_text_snapshot.txt", "res://tests/golden/text_snapshot.txt"]:
		for ln in FileAccess.get_file_as_string(p).split("\n"):
			if str(ln).strip_edges() != "":
				lines.append(ln)
	var gd := FileAccess.get_file_as_string("res://tests/golden/gd_text_snapshot.txt")
	_ok("④ 分母: 文案快照读到 ≥ 1500 行, 且已收进这一线的新文案(龟投账号 / 等待确认 / 不合并那句)", lines.size() >= 1500
		and gd.contains("|龟投账号") and gd.contains("|等待确认") and gd.contains(DLG.B_NOMERGE), "%d 行" % lines.size())
	lines.append(FileAccess.get_file_as_string("res://data/tutorial-steps.json"))
	var hits := _banned_hits(lines)
	_ok("④ ★全部玩家可见文字里没有「主站」「龟币」「金额」", hits.is_empty(), str(hits.slice(0, 5)))
	_ok("④ 尺子自检: 一句「登录主站账号」/「龟币 100」会被抓到", _banned_hits(["x|lit|登录主站账号", "x|lit|龟币 100", "x|lit|绑定"]).size() == 2)
	## 选龟页: 源码(去注释)
	var files: Array = ["res://scripts/scenes/TeamSelectScene.gd"]
	var d := DirAccess.open("res://scripts/scenes/team_select")
	if d != null:
		for fn in d.get_files():
			if fn.ends_with(".gd"):
				files.append("res://scripts/scenes/team_select/" + fn)
	var ts_bad: Array = []
	for f in files:
		var h := _ts_hits(FileAccess.get_file_as_string(f))
		if not h.is_empty():
			ts_bad.append("%s %s" % [f.get_file(), h])
	_ok("④ 分母: 选龟页源码 ≥ 5 个文件", files.size() >= 5, str(files.size()))
	_ok("④ ★选龟页源码里没有龟投入口 / 外链 / 打开浏览器", ts_bad.is_empty(), str(ts_bad))
	_ok("④ 尺子自检: 外链与打开浏览器会被抓到, 注释里提一句不算", _ts_hits("\tOS.shell_open(\"https://x\")").size() >= 2
		and _ts_hits("\t## 选龟页不放龟投链接\n\tvar c := \"#ffb454\"  # 龟投").is_empty())
	## 选龟页: 实建, 屏上的字
	var gs = get_node_or_null("/root/GameState")
	gs.season_leaders = []
	var ts: Node = (load(TS_SCENE) as PackedScene).instantiate()
	add_child(ts)
	await _frames(6)
	var texts: Array = []
	_all_texts(ts, texts)
	var on_screen: Array = []
	for t in texts:
		if str(t).contains("龟投") or str(t).contains("turtlebet") or str(t).contains("http"):
			on_screen.append(t)
	_ok("④ ★实建选龟页: 屏上没有「龟投」字样与链接(扫了 %d 条字)" % texts.size(), on_screen.is_empty() and texts.size() >= 10, str(on_screen))
	ts.queue_free()
	await _frames(2)


# ⑤ ─────────────────────────────────────────────────────────
func _t_pure() -> void:
	print("── ⑤ 纯判据 ──")
	_ok("⑤ parse: 2xx + ok:true ⇒ ok", bool(ML.parse({"ok": true, "code": 200, "body": "{\"ok\":true,\"code\":\"abcd\"}"})["ok"]))
	_ok("⑤ parse: 2xx + ok:false ⇒ bad", ML.parse({"ok": true, "code": 200, "body": "{\"ok\":false}"})["reason"] == ML.R_BAD)
	_ok("⑤ parse: 401 ⇒ auth / 500 ⇒ net / 连不上 ⇒ net / 被拦 ⇒ blocked",
		ML.parse({"ok": true, "code": 401, "body": ""})["reason"] == ML.R_AUTH
		and ML.parse({"ok": true, "code": 500, "body": "{\"ok\":true}"})["reason"] == ML.R_NET
		and ML.parse({"ok": false, "code": 0, "body": ""})["reason"] == ML.R_NET
		and ML.parse({"ok": false, "code": 0, "body": "", "blocked": true})["reason"] == ML.R_BLOCKED)
	_ok("⑤ parse: mainsite_me 不要求 ok 字段", bool(ML.parse({"ok": true, "code": 200, "body": "{\"linked\":true}"}, false)["ok"]))
	_ok("⑤ 登录码形状 ^[A-Za-z0-9_-]{4,64}$", ML.code_ok("abcd") and ML.code_ok("A_b-9") and not ML.code_ok("abc")
		and not ML.code_ok("ab cd") and not ML.code_ok("x".repeat(65)))
	_ok("⑤ 只开 https 且带着这次的登录码", ML.url_ok("https://x.test/game/link?code=abcd", "abcd")
		and not ML.url_ok("https://x.test/game/link?code=zzzz", "abcd") and not ML.url_ok("javascript:alert(1)?code=abcd", "abcd")
		and not ML.url_ok("http://evil.test/?code=abcd", "abcd"))
	var a := ML.account_from_session({"access_token": _jwt({"sub": ACC2, "email": "m@x.y", "exp": 2000000000}), "refresh_token": "r"})
	_ok("⑤ session → 账号: 从令牌载荷取 id / 邮箱 / 到期", bool(a["ok"]) and a["account_id"] == ACC2 and a["email"] == "m@x.y"
		and int(a["expires_at"]) == 2000000000 and a["refresh"] == "r", str(a))
	_ok("⑤ session 缺 refresh / id 不是 uuid / 不是对象 ⇒ 不认",
		not bool(ML.account_from_session({"access_token": _jwt({"sub": ACC2})})["ok"])
		and not bool(ML.account_from_session({"access_token": _jwt({"sub": "nope"}), "refresh_token": "r"})["ok"])
		and not bool(ML.account_from_session(null)["ok"]))
	_ok("⑤ view_of: 不知道绑没绑且正在问 ⇒ 连接中、键不可点", ROW.view_of(ML.ST_IDLE, -1, "", true)["state"] == ROW.S_CONNECTING
		and not bool(ROW.view_of(ML.ST_IDLE, -1, "", true)["btn_on"]))
	_ok("⑤ view_of: 开始失败按原因说(连不上 / 登录失效)", ROW.view_of(ML.ST_ERROR, 0, ML.R_NET, false)["state"] == "无法连接服务器"
		and ROW.view_of(ML.ST_ERROR, 0, ML.R_AUTH, false)["state"] == "登录已失效")


func _finish() -> void:
	print("")
	_ok("分母: 断言条数 ≥ %d(少了 = 半路中止)" % NEED, _n >= NEED, str(_n))
	if _fail == 0:
		print("ALL PASS — 龟投账号登录绑定(%d 条)" % _n)
	else:
		print("FAIL x%d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
