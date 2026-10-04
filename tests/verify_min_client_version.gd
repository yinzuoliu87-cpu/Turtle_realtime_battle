extends Node
## verify_min_client_version.gd — E15 最低客户端版本(母方案书 §8.5 E15「客户端版本旧于服务端」)
##
## 判据原文: 服务端 `service_status.min_client_version` 高于本机 `application/config/version` ⇒
##   主菜单出一句**非阻塞**的「有新版本，请更新」; 不高于 ⇒ 一个字都不出。
##   版本按段比整数: 0.19.10 > 0.19.9(按字符串比会反过来)。
##
## ★走真入口: 假服务器回 `service_status` 那一行 → 实例化 MainMenu.tscn → 主菜单自己去问、自己轮询、自己飘字。
##   量的是**屏幕上那个 Label 出没出现**, 不是我插的计数器。不向任何外部服务发请求。
## ★分母: 「不该提示」的两种情形(相等 / 字典序更大但数值更小)必须**一个字都不出** —— 否则「找得到」是恒真式。
##
## 会 FAIL 的证明(反向验证):
##   · `version_less` 改成字符串比较       ⇒ ① 0.19.10/0.19.9 红, ③ 字典序那一格红
##   · 主菜单 `_sb_poll` 不调 take_update_hint ⇒ ② 红
##   · `state_from_response` 不读那一列      ⇒ ② 红

const SB := preload("res://scripts/net/supabase.gd")

var _fail := 0
var _n := 0
var _min := "0.0.0"
var _reqs := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _transport(m, u, _h, _b, cb) -> void:
	var url := str(u)
	_reqs += 1
	if url.find("/rest/v1/service_status") >= 0 and str(m) == "GET":
		_reqs += 1000
		cb.call({"ok": true, "code": 200, "body": JSON.stringify([
			{"id": 1, "maintenance": false, "notice": "", "min_client_version": _min}])})
		return
	cb.call({"ok": false, "code": 0, "body": ""})


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	GameState.test_mode = true
	_t_pure()
	var had_env: bool = OS.has_environment(SB.ENV_URL)
	var env0: String = OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	SB._transport_for_test = _transport
	_ok("★分母: 后端真的打开了", SB.enabled())

	var cv := str(ProjectSettings.get_setting("application/config/version", ""))
	var parts := cv.split(".")
	_ok("★分母: 本机版本是三段整数(%s)" % cv, parts.size() == 3 and parts[2].is_valid_int())
	var newer := "%s.%s.%d" % [parts[0], parts[1], int(parts[2]) + 1]
	var a := await _menu_case(newer)
	_ok("② ★★服务端要求 %s > 本机 %s ⇒ 主菜单出了那句提示" % [newer, cv], a["seen"], str(a))
	_ok("② 提示不挡手: 它是一个不吃点击的 Label(不是弹窗/遮罩)", a["ignore_mouse"], str(a))
	var b := await _menu_case(cv)
	_ok("③ 分母: 服务端真的回过话(相等那一格)", int(b["reqs"]) >= 1000, str(b))
	_ok("③ ★相等 ⇒ 一个字都不出", not b["seen"], str(b))
	if str(parts[2]).length() >= 2:
		var lex := "%s.%s.%s" % [parts[0], parts[1], "9".repeat(str(parts[2]).length() - 1)]
		var c := await _menu_case(lex)
		_ok("③ ★字典序更大、数值更小(%s vs %s) ⇒ 不提示(按字符串比就会错提示)" % [lex, cv], not c["seen"], str(c))
	_ok("② 开局拦截不受影响(提示与不提示时开局闸给的话一样)", str(a["block"]) == str(b["block"]),
		"%s | %s" % [a["block"], b["block"]])

	SB._transport_for_test = Callable()
	SB._reset_for_test()
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	if had_env:
		OS.set_environment(SB.ENV_URL, env0)
	else:
		OS.unset_environment(SB.ENV_URL)
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — E15 最低客户端版本" if _fail == 0 else "FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


func _t_pure() -> void:
	print("── ① 版本比较(纯函数) ──")
	var cases := [
		["0.19.9", "0.19.10", true],     # ★按字符串比会判 false
		["0.19.10", "0.19.9", false],
		["0.19.10", "0.19.10", false],
		["0.9.0", "0.10.0", true],
		["1.0.0", "0.99.99", false],
		["0.19", "0.19.0", false],       # 缺的段当 0
		["0.19", "0.19.1", true],
		["0.19.1", "", false],           # 看不懂 ⇒ 不提示
		["0.19.1", "0.19.x", false],
		["", "0.19.1", false],
	]
	for c in cases:
		var got: bool = SB.version_less(str(c[0]), str(c[1]))
		_ok("① %s < %s ⇒ %s" % [c[0], c[1], str(c[2])], got == bool(c[2]), "实际 %s" % str(got))
	var r := SB.state_from_response(true, 200, '[{"id":1,"maintenance":false,"notice":"","min_client_version":"0.20.1"}]')
	_ok("① 回包里那一列被读出来了", str(r.get("min", "")) == "0.20.1", str(r))
	var r2 := SB.state_from_response(true, 200, '[{"id":1,"maintenance":false,"notice":""}]')
	_ok("① 没有那一列 ⇒ 空(当作没要求)", str(r2.get("min", "x")) == "", str(r2))


## 一个情形: 设定服务端最低版本 → 开主菜单 → 逐帧找那句提示。
func _menu_case(minv: String) -> Dictionary:
	SB._reset_for_test()
	_min = minv
	_reqs = 0
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	get_tree().root.add_child(menu)
	var seen := false
	var ignore := false
	## 主菜单 _ready 自己发了那次 service_status(假服务器同步回包)。
	## ★不等那个 1 秒的轮询 Timer 自己响: 无头帧率极高, 1 秒墙钟会吃掉上千帧、撞门禁的帧预算。
	##   改成「确认 Timer 接的就是 _sb_poll」+ 替它响一次 —— 量的仍是主菜单自己的处理函数。
	var w := 0
	while w < 30 and SB.ask_count() == 0:
		await get_tree().process_frame
		w += 1
	var wired := false
	for ch in menu.get_children():
		if ch is Timer and not (ch as Timer).one_shot and (ch as Timer).is_connected("timeout", Callable(menu, "_sb_poll")):
			wired = true
	_ok("[%s] 分母: 主菜单问过服务状态 + 轮询 Timer 接的是 _sb_poll" % minv, SB.ask_count() >= 1 and wired,
		"ask=%d wired=%s" % [SB.ask_count(), str(wired)])
	menu._sb_poll()
	for _i in range(3):
		await get_tree().process_frame
	for ch in menu.get_children():
		if ch is Label and (ch as Label).text == SB.UPDATE_HINT:
			seen = true
			ignore = (ch as Label).mouse_filter == Control.MOUSE_FILTER_IGNORE
	var block: String = menu._battle_block_msg()
	menu.queue_free()
	for _i in range(4):
		await get_tree().process_frame
	return {"seen": seen, "ignore_mouse": ignore, "reqs": _reqs, "block": block, "min": minv}
