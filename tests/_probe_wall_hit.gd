extends Node
## DEV 探针: 登录墙上**每一个可点元素的真实热区 + 谁能吃到这一点 + 按下去有没有事发生**。
##
## 由来: 用户真机报「邮箱注册没用, app 里操作没反应」。发信层(手工 PUT 200 · 两个邮箱都收到)
## 与客户端逻辑(`_probe_wall_live` 真后端实测 sending→sent)都已排除 ⇒ 剩下触摸层这一条没查过。
##
## 这里**不推理**, 把数字打出来:
##   ① 每个可点元素的全局矩形 / 短边 px / 短边 pt(81px = 44pt) / mouse_filter
##   ② 引擎在那一点**实际选中的控件**(`gui_get_hovered_control`) —— 不是看 mouse_filter 猜
##   ③ 推真 `InputEventMouseButton` 进去, 看**产品状态**变没变
##   ④ 虚拟键盘那条: 键盘占屏底 X% 时, 哪些元素被埋掉
##
## 跑法: <godot> --headless --path . res://tests/_probe_wall_hit.tscn --quit-after 3000

const SET := preload("res://scripts/scenes/SettingsScene.gd")
const SB := preload("res://scripts/net/supabase.gd")

## 1pt = 81/44 px(本仓触控线 TOUCH_MIN = 81px = 44pt, 见 top_bar.gd / verify_ui_consistency)
const PX_PER_PT := 81.0 / 44.0

var _reqs: Array = []


func _spy(method, url, _headers, body, cb) -> void:
	_reqs.append({"method": str(method), "url": str(url), "body": str(body)})
	cb.call({"ok": false, "code": 0, "body": ""})


func _w(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _interactive(c: Control) -> bool:
	if c is BaseButton or c is Range or c is LineEdit or c is TextEdit:
		return true
	for cn in c.gui_input.get_connections():
		var o = cn.get("callable").get_object()
		if o == null:
			continue
		if o == c:
			continue
		if o is Node and c.is_ancestor_of(o as Node):
			continue
		return true
	return false


func _label_of(c: Control) -> String:
	if c is Button:
		return str((c as Button).text)
	if c is LineEdit:
		return "<输入框 placeholder=%s>" % str((c as LineEdit).placeholder_text)
	return "(%s)" % c.name


func _mf(c: Control) -> String:
	match c.mouse_filter:
		Control.MOUSE_FILTER_STOP: return "STOP"
		Control.MOUSE_FILTER_PASS: return "PASS"
		_: return "IGNORE"


## 引擎在 `p` 这一点真正选中的控件是谁 —— 推一个真 MouseMotion 进去让 GUI 系统自己算。
func _who_eats(p: Vector2) -> String:
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	get_viewport().push_input(mm)
	var h = get_viewport().gui_get_hovered_control() if get_viewport().has_method("gui_get_hovered_control") else null
	if h == null:
		return "<无>"
	return "%s/%s「%s」" % [h.get_class(), h.name, _label_of(h as Control).substr(0, 10)]


func _click(p: Vector2) -> void:
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.position = p
	d.global_position = p
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = p
	u.global_position = p
	get_viewport().push_input(d)
	get_viewport().push_input(u)


func _collect(root: Node) -> Array:
	var out: Array = []
	var st: Array = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is Control and (n as Control).is_visible_in_tree() and _interactive(n as Control):
			out.append(n)
		for ch in n.get_children():
			st.append(ch)
	return out


## 谁画在 a 上面且盖住了 a 的 ≥25% —— 照 verify_ios_ui 的判据搬(同一口径才好对账)。
func _blocker(root: Node, target: Control) -> String:
	var br: Rect2 = target.get_global_rect()
	var barea: float = br.size.x * br.size.y
	if barea <= 1.0:
		return ""
	var st: Array = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		for ch in n.get_children():
			st.append(ch)
		if not (n is Control) or n == target:
			continue
		var c := n as Control
		if not c.is_visible_in_tree() or c.modulate.a <= 0.05:
			continue
		if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if target.is_ancestor_of(c) or c.is_ancestor_of(target):
			continue
		var inter: Rect2 = c.get_global_rect().intersection(br)
		if inter.size.x * inter.size.y < barea * 0.25:
			continue
		if not _above(c, target):
			continue
		return "%s/%s" % [c.get_class(), c.name]
	return ""


func _above(a: Control, b: Control) -> bool:
	var pa: Node = a
	while pa != null and not pa.is_ancestor_of(b):
		pa = pa.get_parent()
	if pa == null:
		return false
	var ca: Node = a
	while ca != null and ca.get_parent() != pa:
		ca = ca.get_parent()
	var cb: Node = b
	while cb != null and cb.get_parent() != pa:
		cb = cb.get_parent()
	if ca == null or cb == null or ca == cb:
		return false
	if ca is CanvasItem and cb is CanvasItem and (ca as CanvasItem).z_index != (cb as CanvasItem).z_index:
		return (ca as CanvasItem).z_index > (cb as CanvasItem).z_index
	return ca.get_index() > cb.get_index()


func _dump(tag: String, vp: Vector2) -> void:
	print("")
	print("══════ %s   视口 %dx%d ══════" % [tag, int(vp.x), int(vp.y)])
	get_tree().root.size = Vector2i(vp)
	await _w(2)
	GameState.test_mode = true
	GameState.account_email = ""
	## ★★用**真场景文件**, 不用 `SET.new()` —— 第一版用 SET.new() 量出遮罩 0x0,
	##   那是探针自己造的假象: 脚本裸实例没有 .tscn 里的铺满锚点。
	var st = (load("res://scenes/Settings.tscn") as PackedScene).instantiate()
	st.acct_override = 1
	add_child(st)
	await _w(8)
	print("  墙建起来了吗: _email_layer=%s" % str(st._email_layer != null))
	print("  根 Control rect=%s" % str((st as Control).get_global_rect()))
	var _df = st.get_node_or_null("DesignFrame")
	print("  DesignFrame: %s  visible=%s"
		% [str(_df != null), str((_df as Control).visible) if _df != null else "-"])
	if st._email_layer == null:
		st.queue_free()
		return
	var box: Control = null
	for ch in (st._email_layer as Node).get_children():
		if ch is Panel:
			box = ch as Control
	print("  遮罩 rect=%s  mf=%s" % [str((st._email_layer as Control).get_global_rect()),
		_mf(st._email_layer as Control)])
	if box != null:
		print("  对话框 rect=%s(视口居中应为 x=%.0f)" % [str(box.get_global_rect()),
			(vp.x - box.size.x) * 0.5])
	var items := _collect(st)
	print("  ── 可点元素 %d 个 ──" % items.size())
	print("  %-26s %-9s %-24s %-7s %-6s %-28s %s"
		% ["文字", "类", "全局rect", "短边px", "pt", "谁吃到中心这一点", "被谁盖(≥25%)"])
	for it in items:
		var c := it as Control
		var r: Rect2 = c.get_global_rect()
		var mn: float = minf(r.size.x, r.size.y)
		print("  %-26s %-9s %-24s %-7.0f %-6.1f %-28s %s"
			% [_label_of(c).substr(0, 24), c.get_class(),
				"%.0f,%.0f %.0fx%.0f" % [r.position.x, r.position.y, r.size.x, r.size.y],
				mn, mn / PX_PER_PT, _who_eats(r.get_center()), _blocker(st, c)])
	## 虚拟键盘: iOS 横屏键盘约占屏高 45%~55%。列出会被埋掉的元素。
	print("  ── 虚拟键盘(占屏底 kb%%)会埋掉谁 ──")
	print("  DisplayServer.virtual_keyboard_get_height() = %d (无头下恒 0, 只证接口在)"
		% DisplayServer.virtual_keyboard_get_height())
	for kb in [0.40, 0.45, 0.50, 0.55]:
		var top: float = vp.y * (1.0 - kb)
		var buried: Array = []
		for it in items:
			var r: Rect2 = (it as Control).get_global_rect()
			if r.position.y + r.size.y > top:
				buried.append(_label_of(it as Control).substr(0, 14))
		print("    键盘占 %.0f%% (顶边 y=%.0f) ⇒ 被埋: %s" % [kb * 100.0, top, str(buried)])
	## ★★键盘**让位后**还埋不埋: 注入真实键盘高度, 让产品自己挪, 再重量一遍。
	print("  ── 让位之后(注入 vkb_override_vp) ──")
	for kb in [0.415, 0.50, 0.55]:
		SET.vkb_override_vp = vp.y * kb
		await _w(3)
		var top: float = vp.y * (1.0 - kb)
		var buried: Array = []
		for it in items:
			var r: Rect2 = (it as Control).get_global_rect()
			if r.position.y + r.size.y > top:
				buried.append("%s@%.0f" % [_label_of(it as Control).substr(0, 8), r.position.y])
		print("    键盘 %.1f%%(顶边 %.0f) ⇒ 框挪到 y=%.0f, 仍被埋: %s"
			% [kb * 100.0, top, (box.position.y if box != null else -1.0), str(buried)])
	SET.vkb_override_vp = -1.0
	await _w(3)
	print("    收起键盘后框回到 y=%.0f" % (box.position.y if box != null else -1.0))
	print("  ── 纯函数 _vkb_to_vp(物理px → 视口单位) ──")
	print("    iPhone14 横屏 3x: 键盘 162pt=486px / 窗口 390pt=1170px, 视口 %dx%d ⇒ %.1f 视口单位"
		% [int(vp.x), int(vp.y), SET._vkb_to_vp(486.0, vp, Vector2(1560.0, 1170.0))])
	print("    无头 window=(0,0) ⇒ %.1f (不许除零)" % SET._vkb_to_vp(486.0, vp, Vector2.ZERO))
	st.queue_free()
	await _w(2)


func _press_tests() -> void:
	print("")
	print("══════ 按下去真的有事发生吗 ══════")
	get_tree().root.size = Vector2i(1280, 720)
	await _w(2)
	OS.set_environment("TURTLE_SUPABASE", "http://127.0.0.1:9")
	SB._reset_auth_for_test()
	GameState.test_mode = true
	GameState.account_email = ""
	GameState.account_id = "uid-probe"
	var st = (load("res://scenes/Settings.tscn") as PackedScene).instantiate()
	st.acct_override = 1
	add_child(st)
	await _w(8)
	print("  分母: 墙在场=%s  发码钮在场=%s  确认钮在场=%s"
		% [str(st._email_layer != null), str(st._email_send_btn != null),
			str(st._email_ok_btn != null)])
	if st._email_send_btn == null:
		st.queue_free()
		return
	st._email_edit.text = "probe@example.com"

	## ── ① 分母: 不按, 状态会自己变吗 ──
	SB.reset_email_flow()
	await _w(30)
	print("  ① 分母(等 30 帧不按): state=%s (该还是 idle)" % SB.email_state())

	## ── ② 分母: 点**空白遮罩**(不是按钮)会有事发生吗 ──
	var dimr: Rect2 = (st._email_layer as Control).get_global_rect()
	_click(Vector2(dimr.position.x + 20.0, dimr.position.y + 20.0))
	await _w(6)
	print("  ② 分母(点空白遮罩左上角): state=%s (该还是 idle —— 否则我的注入本身在乱改状态)"
		% SB.email_state())

	## ── ③ 真点「发验证码」 ──
	var sr: Rect2 = st._email_send_btn.get_global_rect()
	print("  ③ 发码钮 rect=%s  disabled=%s  mf=%s"
		% [str(sr), str(st._email_send_btn.disabled), _mf(st._email_send_btn)])
	_click(sr.get_center())
	await _w(6)
	print("  ③ 点完「发验证码」: state=%s  msg=「%s」" % [SB.email_state(), SB.email_msg()])

	## ── ④ 真点「确认」。先把它推到可用态(EM_ERR 也算), 并给 _email_pending ──
	SB._reset_auth_for_test()
	SB._token = "tok-probe"
	SB._transport_for_test = _spy
	SB.reset_email_flow()
	SB.send_code_async("probe@example.com", SB.FLOW_BIND)
	await _w(10)
	st._email_poll()
	GameState.nickname = "阿龟"
	st._nick_edit.text = "阿龟"
	st._code_edit.text = "12345678"
	print("  ④ 分母: 按之前 state=%s  确认钮 disabled=%s  _email_pending=「%s」"
		% [SB.email_state(), str(st._email_ok_btn.disabled), SB._email_pending])
	var before := SB.email_state()
	await _w(20)
	_reqs.clear()
	print("  ④ 分母(再等 20 帧不按): state=%s  发出的请求 %d 条 (该都没动)"
		% [SB.email_state(), _reqs.size()])
	var okr: Rect2 = st._email_ok_btn.get_global_rect()
	_click(okr.get_center())
	await _w(6)
	var _u4: Array = []
	for r in _reqs:
		_u4.append(str(r.get("url", "")).replace("http://127.0.0.1:9", ""))
	## ★状态 err→err 不是「没反应」: 注入的传输是**同步**回包的, VERIFYING 当帧就落回 ERR。
	##   ⇒ 判据换成「真的发出了验码请求」—— 那是记录下来的, 不会被时间清掉。
	print("  ④ 点完「确认」: state=%s→%s  发出的请求=%s" % [before, SB.email_state(), str(_u4)])

	## ── ⑤ 输入框: 点一下能不能拿到焦点(拿不到 = 打不了字) ──
	for e in [["昵称", st._nick_edit], ["邮箱", st._email_edit], ["验证码", st._code_edit]]:
		var le: LineEdit = e[1]
		if le == null:
			continue
		le.release_focus()
		var er: Rect2 = le.get_global_rect()
		_click(er.get_center())
		await _w(3)
		print("  ⑤ 点「%s」框: has_focus=%s  (rect=%s)"
			% [str(e[0]), str(le.has_focus()), str(er)])
	SB._transport_for_test = Callable()
	st.queue_free()
	await _w(2)


## `verify_ios_ui` / `verify_click_targets_alive` 是**照它们自己的办法**载 Settings 的
## (不注入 `acct_override`, 门禁又给 `TURTLE_SUPABASE=" "`) —— 墙到底在不在场?
func _gate_blindness() -> void:
	print("")
	print("══════ 两个触摸门禁载 Settings 时, 墙在场吗 ══════")
	GameState.test_mode = true
	GameState.account_email = ""
	print("  SB.enabled()=%s  (门禁给 TURTLE_SUPABASE=\" \")" % str(SB.enabled()))
	var st = (load("res://scenes/Settings.tscn") as PackedScene).instantiate()
	add_child(st)
	await _w(8)
	var items := _collect(st)
	var names: Array = []
	for it in items:
		names.append(_label_of(it as Control).substr(0, 12))
	print("  不注入 acct_override ⇒ _email_layer=%s" % str(st._email_layer != null))
	print("  这一屏扫到的可点元素 %d 个: %s" % [items.size(), str(names)])
	st.queue_free()
	await _w(2)


func _ready() -> void:
	await _w(2)
	print("=== 登录墙触摸层探针 ===")
	await _gate_blindness()
	await _dump("A. iPhone 横屏", Vector2(1560, 720))
	await _dump("B. 1280x720 基准", Vector2(1280, 720))
	await _dump("C. iPad 4:3", Vector2(1280, 960))
	await _press_tests()
	print("PROBE DONE")
	get_tree().quit(0)
