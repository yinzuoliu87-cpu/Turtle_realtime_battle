extends Node
## verify_email_bind.gd — D-3b：补绑邮箱 + 换设备取回（2026-09-21）
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## 两条流程共用「发码 → 验码」两步，但**第二步的判据正好相反**：
##   · 补绑(bind)    —— 返回的 id **必须等于**当前 `account_id`（升级，不新建）
##   · 换设备(recover) —— 返回的 id **本来就不同**，那正是要换过去的那个
## 写成一个函数就必然有一半是错的，所以 ④⑤ 分开验、⑥ 再走一遍真落地。
##
## ★★最要命的那条是 ④：补绑时如果服务端返回了**另一个 id**（服务端新建了号），
##   接受它 = 把玩家的赛季身份换掉（排名 / 战绩 / 鬼影全断），而且**完全静默**。
##   宁可报失败让人重来。⑥ 就是量「拒绝之后 `account_id` 有没有被动过」。
##
## ★⑦ 用 `_transport` 注入把**真实请求截下来**（不碰网络）：
##   补绑必须打 `PUT /auth/v1/user`、换设备必须打 `POST /auth/v1/otp`，
##   验码的 `type` 必须是 `email_change` / `email`。
##   **两条路互换的话服务端会以 `otp_expired` 拒掉** —— 看起来像「码不对」，极难查。
##
## ⚠ **能验到哪为止**：发信与收信这一段门禁验不到（要有真邮箱）。
##   端点形状是 2026-09-21 真打 Supabase 拿到的：
##   `PUT /auth/v1/user` 与 `POST /auth/v1/otp` 对非法邮箱都返回
##   **400 `validation_failed`**；`POST /auth/v1/verify` 对乱码返回
##   **403 `otp_expired`**。②③ 喂的就是这几个真实形状，不是我编的。

const SB := preload("res://scripts/net/supabase.gd")

var _ok := 0
var _fail := 0
var _tree: SceneTree = null
var _bak := {}
const KEYS := ["account_id", "account_email"]


func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])


func _ready() -> void:
	_tree = get_tree()
	await get_tree().process_frame
	GameState.test_mode = true
	for k in KEYS:
		_bak[k] = GameState.get(k)
	print("=== D-3b 补绑邮箱 / 换设备取回 ===")
	_t_email_shape()
	_t_send_result()
	_t_verify_result()
	_t_accepts()
	_t_apply()
	_t_wire()
	for k in KEYS:
		GameState.set(k, _bak[k])
	SB.reset_email_flow()
	SB._reset_auth_for_test()
	print("")
	print("  (共 %d 条断言)" % (_ok + _fail))
	print("ALL PASS — D-3b 邮箱绑定" if _fail == 0 else "FAIL x%d" % _fail)
	if _tree != null:
		_tree.quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 邮箱格式: 挡住手滑, 省下那封发不起的信
# ─────────────────────────────────────────────────────────────
func _t_email_shape() -> void:
	print("── ① 邮箱格式(挡手滑·省发信配额) ──")
	var good := ["a@b.co", "turtlesupport32@gmail.com", "x.y+tag@sub.domain.co.uk"]
	var n_good := 0
	for e in good:
		if SB.email_looks_valid(e):
			n_good += 1
	_chk("① ★分母: %d 个正常邮箱全部放行(挡多了也是错)" % good.size(),
		n_good == good.size(), "放行 %d/%d" % [n_good, good.size()])

	var bad := [
		["没有 @", "abc.com"], ["两个 @", "a@b@c.com"], ["@ 在最前", "@b.com"],
		["域名没有点", "a@b"], ["域名以点结尾", "a@b."], ["域名连着两个点", "a@b..com"],
		["顶级域只有一位", "a@b.c"], ["中间有空格", "a b@c.com"],
		["有逗号", "a,b@c.com"], ["空串", ""],
	]
	var leaked := 0
	for b in bad:
		var v: bool = SB.email_looks_valid(str(b[1]))
		if v:
			leaked += 1
		_chk("① %s → 挡住" % str(b[0]), not v, str(b[1]))
	_chk("① ★★十种手滑一个都没漏(漏一个就浪费一封限流的信)", leaked == 0,
		"漏了 %d/10" % leaked)


# ─────────────────────────────────────────────────────────────
# ② 发码回包: 每种失败都要有一句人看得懂的话, 且各不相同
# ─────────────────────────────────────────────────────────────
func _t_send_result() -> void:
	print("── ② 发码回包(每种失败说清楚是哪种) ──")
	_chk("② 200 → 成功", bool(SB.send_code_result(true, 200, "{}").get("ok", false)))
	var cases := [
		["邮箱格式不对(实测 400)", false, 400,
			'{"code":400,"error_code":"validation_failed","msg":"Unable to validate email address: invalid format"}'],
		["邮箱已被占用", false, 422, '{"error_code":"email_exists"}'],
		["发太频繁", false, 429, '{"error_code":"over_email_send_rate_limit"}'],
		["取回时邮箱没注册过(实测 422)", false, 422,
			'{"code":422,"error_code":"otp_disabled","msg":"Signups not allowed for otp"}'],
		["发信服务没接上(官方错误码)", false, 400,
			'{"code":400,"error_code":"email_address_not_authorized","msg":"Email sending is not allowed for this address"}'],
		["测试域名(实测 400)", false, 400,
			'{"code":400,"error_code":"email_address_invalid","msg":"Email address is invalid"}'],
		["连不上", false, 0, ""],
		["网关吐了一坨 HTML", false, 502, "<html>502 Bad Gateway</html>"],
	]
	var says := {}
	for c in cases:
		var r: Dictionary = SB.send_code_result(bool(c[1]), int(c[2]), str(c[3]))
		says[str(c[0])] = str(r.get("reason", ""))
		_chk("② %s → 失败且有话说" % str(c[0]),
			not bool(r.get("ok", true)) and str(r.get("reason", "")) != "",
			str(r.get("reason", "")))
	## ★★判据不能写成「五种话互不相同」—— **那样宽一格**:
	##   兜底话术是「发送失败（%d）」**带着状态码插值**,
	##   所以一个所有分支都走兜底的偷懒实现 400/502 也各不相同,
	##   **照样能过**。(2026-09-21 反向验证 E4 当场抓出来的:
	##   改成兜底话术后这条断言没红。)
	## ⇒ 真正要守的是【玩家知道该怎么办】—— 每类失败都要有
	##   它自己那个可操作的关键词。分开的字符串只是副产品。
	var must := [
		["邮箱格式不对(实测 400)", "格式"],
		["邮箱已被占用", "别的账号"],
		["发太频繁", "频繁"],
		["连不上", "网络"],
		["取回时邮箱没注册过(实测 422)", "没有绑定过"],
		## ★这条挡的是「稍后再试」: 发信服务没接上时再试多少次都不会成功, 那句话是在误导玩家
		["发信服务没接上(官方错误码)", "还没开通"],
		["测试域名(实测 400)", "换一个"],
	]
	var miss := 0
	for m in must:
		var said := str(says.get(str(m[0]), ""))
		if not said.contains(str(m[1])):
			miss += 1
		_chk("② 「%s」的话里要有【%s】(告诉玩家该干嘛)" % [str(m[0]), str(m[1])],
			said.contains(str(m[1])), said)
	_chk("② ★★各类可排查的失败全都给了可操作的话(全走兜底当场红)",
		miss == 0, "缺 %d/%d" % [miss, must.size()])


# ─────────────────────────────────────────────────────────────
# ③ 验码回包
# ─────────────────────────────────────────────────────────────
func _t_verify_result() -> void:
	print("── ③ 验码回包 ──")
	var body := '{"access_token":"tok123","user":{"id":"uid-A","email":"a@b.co","is_anonymous":false}}'
	var r: Dictionary = SB.verify_code_result(true, 200, body)
	_chk("③ ★分母: 成功时解得出 id / token / email",
		bool(r.get("ok", false)) and str(r.get("account_id", "")) == "uid-A"
		and str(r.get("token", "")) == "tok123" and str(r.get("email", "")) == "a@b.co", str(r))

	var bad := [
		["码错或过期(实测 403)", 403, '{"code":403,"error_code":"otp_expired","msg":"Token has expired or is invalid"}'],
		["连不上", 0, ""],
		["200 但没有 user", 200, '{"access_token":"t"}'],
		["200 但 user 没 id", 200, '{"user":{"email":"a@b.co"}}'],
		["一坨 HTML", 200, "<html>ok</html>"],
	]
	var leaked := 0
	for b in bad:
		var rr: Dictionary = SB.verify_code_result(true, int(b[1]), str(b[2]))
		if bool(rr.get("ok", false)) or str(rr.get("account_id", "")) != "":
			leaked += 1
		_chk("③ %s → 失败且【不编一个 id 出来】" % str(b[0]),
			not bool(rr.get("ok", true)) and str(rr.get("account_id", "")) == "",
			str(rr.get("reason", "")))
	_chk("③ ★★五种失败一个都没编出 id(编一个的话「没验上」会看起来像「验上了」)",
		leaked == 0, "违例 %d/5" % leaked)


# ─────────────────────────────────────────────────────────────
# ④⑤ ★★两条流程的判据【正好相反】
# ─────────────────────────────────────────────────────────────
func _t_accepts() -> void:
	print("── ④⑤ 补绑要求同一个号 / 换设备就是要换号 ──")
	var same := {"ok": true, "account_id": "uid-A", "token": "t", "email": "a@b.co"}
	var other := {"ok": true, "account_id": "uid-B", "token": "t", "email": "a@b.co"}

	_chk("④ ★分母: 返回同一个 id 时补绑【接受】",
		bool(SB.bind_accepts(same, "uid-A").get("ok", false)))
	var v: Dictionary = SB.bind_accepts(other, "uid-A")
	_chk("④ ★★返回【另一个】id 时补绑必须【拒绝】(接受=静默把赛季身份换掉)",
		not bool(v.get("ok", true)), str(v.get("reason", "")))
	_chk("④ 拒绝时要说清「没动你的进度」(不然玩家不知道现在是什么状态)",
		str(v.get("reason", "")).contains("没动"), str(v.get("reason", "")))
	_chk("④ 本机还没有账号时不许绑(没有「当前 id」可比 ⇒ 等于没判)",
		not bool(SB.bind_accepts(same, "").get("ok", true)),
		str(SB.bind_accepts(same, "").get("reason", "")))

	_chk("⑤ ★★换设备时返回【另一个】id 是【预期】—— 接受",
		bool(SB.recover_accepts(other).get("ok", false)))
	_chk("⑤ 换设备但服务器没给 id → 拒绝",
		not bool(SB.recover_accepts({"ok": true, "account_id": ""}).get("ok", true)))
	_chk("⑤ 验码本身失败 → 拒绝, 且把原因原样带出来",
		not bool(SB.recover_accepts({"ok": false, "reason": "验证码不对"}).get("ok", true)))

	## ★★这两条合起来才有意义: 写成同一个判据的话, 总有一半是错的。
	_chk("④⑤ ★★同一份回包在两条流程里结论【相反】(证明不是同一个判据)",
		not bool(SB.bind_accepts(other, "uid-A").get("ok", true))
		and bool(SB.recover_accepts(other).get("ok", false)))


# ─────────────────────────────────────────────────────────────
# ⑥ ★★真落地: 拒绝之后 account_id 一个字都不许动
# ─────────────────────────────────────────────────────────────
func _t_apply() -> void:
	print("── ⑥ 真落地(拒绝之后不许动身份) ──")
	var other := '{"access_token":"t2","user":{"id":"uid-B","email":"a@b.co"}}'
	var same := '{"access_token":"t3","user":{"id":"uid-A","email":"a@b.co"}}'

	GameState.account_id = "uid-A"
	GameState.account_email = ""
	var applied: bool = SB._apply_verify(true, 200, other, SB.FLOW_BIND)
	_chk("⑥ ★★补绑撞上【别的 id】→ 不接受", not applied)
	_chk("⑥ ★★而且 account_id【一个字都没动】(这才是真正要守的东西)",
		str(GameState.account_id) == "uid-A", GameState.account_id)
	_chk("⑥ 邮箱也没被写进去(没绑成功就不能显示成绑了)",
		str(GameState.account_email) == "", GameState.account_email)
	_chk("⑥ 状态是错误态且有话说", SB.email_state() == SB.EM_ERR and SB.email_msg() != "",
		SB.email_msg())

	GameState.account_id = "uid-A"
	applied = SB._apply_verify(true, 200, same, SB.FLOW_BIND)
	_chk("⑥ ★分母: 同一个 id 时补绑【成功】(否则上面是空检查)", applied)
	_chk("⑥ 绑成功后邮箱写进存档", str(GameState.account_email) == "a@b.co",
		GameState.account_email)
	_chk("⑥ id 还是原来那个(升级不是换号)", str(GameState.account_id) == "uid-A")

	GameState.account_id = "uid-LOCAL"
	GameState.account_email = ""
	applied = SB._apply_verify(true, 200, other, SB.FLOW_RECOVER)
	_chk("⑥ ★★换设备取回 → 接受, 且 account_id 换成服务器给的那个", applied
		and str(GameState.account_id) == "uid-B", GameState.account_id)


# ─────────────────────────────────────────────────────────────
# ⑦ ★★两条流程打的是不同的端点 —— 用 _transport 截真实请求(不碰网络)
# ─────────────────────────────────────────────────────────────
func _t_wire() -> void:
	print("── ⑦ 两条流程的端点 / type 不许互换 ──")
	var seen := {"method": "", "url": "", "body": ""}
	var spy := func(method, url, _headers, body, _cb) -> void:
		seen["method"] = str(method)
		seen["url"] = str(url)
		seen["body"] = str(body)

	var env_bak := OS.get_environment("TURTLE_SUPABASE")
	OS.set_environment("TURTLE_SUPABASE", "http://127.0.0.1:9")
	_chk("⑦ ★分母: 这一段里后端是【启用】的", SB.enabled(), SB.base_url())

	var n1 = SB.new()
	n1._transport = spy
	n1.send_code("a@b.co", SB.FLOW_BIND)
	_chk("⑦ ★分母: 请求真的发出来了(截到了 url)", str(seen["url"]) != "", str(seen["url"]))
	_chk("⑦ ★★补绑打的是 PUT /auth/v1/user(【升级】现有号)",
		str(seen["method"]) == "PUT" and str(seen["url"]).ends_with("/auth/v1/user"),
		"%s %s" % [seen["method"], seen["url"]])
	_chk("⑦ 补绑的正文里没有 create_user(那是 /otp 的参数, PUT /user 不认)",
		not str(seen["body"]).contains("create_user"), str(seen["body"]))
	n1.free()

	var n2 = SB.new()
	n2._transport = spy
	n2.send_code("a@b.co", SB.FLOW_RECOVER)
	_chk("⑦ ★★换设备打的是 POST /auth/v1/otp(拿邮箱换一次登录)",
		str(seen["method"]) == "POST" and str(seen["url"]).ends_with("/auth/v1/otp"),
		"%s %s" % [seen["method"], seen["url"]])
	_chk("⑦ ★★换设备带了 create_user:false(不带 = 打错字的邮箱被注册成新空号)",
		str(seen["body"]).contains('"create_user":false'), str(seen["body"]))
	n2.free()

	var n3 = SB.new()
	n3._transport = spy
	n3.verify_code("a@b.co", "123456", SB.FLOW_BIND)
	_chk("⑦ ★★补绑验码 type = email_change(填 email 会被当成码过期, 极难查)",
		str(seen["url"]).ends_with("/auth/v1/verify")
		and str(seen["body"]).contains('"type":"email_change"'), str(seen["body"]))
	n3.free()

	var n4 = SB.new()
	n4._transport = spy
	n4.verify_code("a@b.co", "123456", SB.FLOW_RECOVER)
	_chk("⑦ ★★换设备验码 type = email",
		str(seen["body"]).contains('"type":"email"'), str(seen["body"]))
	_chk("⑦ 码带进去了", str(seen["body"]).contains('"token":"123456"'), str(seen["body"]))
	n4.free()

	OS.set_environment("TURTLE_SUPABASE", env_bak)
	_chk("★收尾: 后端地址已还原", OS.get_environment("TURTLE_SUPABASE") == env_bak)
