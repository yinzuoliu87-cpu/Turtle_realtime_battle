extends Node
## DEV 探针: 登录墙的**竖向剖面** —— 框里每一个子控件的 y / 高 / 与上一个的间隙,
## 加上「三档虚拟键盘 × 三种视口」下**可点元素被埋/被顶出去**的实测格子。
##
## 为什么要单独一份(`_probe_wall_hit` 已经有了热区那半):
##   那一份量的是「谁吃到这一点 / 按下去有没有事发生」, **没有量竖向的排布**。
##   而「瞄发验证码高 7px 就点进邮箱框」这个形状, 只有把**相邻间隙**摊成表才看得见。
##
## 这里**不推理**, 只打数字:
##   ① 框本体: 视口 / 框位置 / 框尺寸 / 离视口上下沿各剩多少
##   ② 框内**所有** Control 子节点(不只可点的)按 y 排序: y / 高 / 底 / 与上一个的间隙
##      —— 说明文字也要在表里, 因为压缩它是重排的手段之一
##   ③ 只看可点元素: 短边 px / pt(81px = 44pt) / 相邻间隙
##   ④ 可点元素竖向占的那一段(band) —— 键盘让位那道公式的分子就是它
##   ⑤ 键盘可行域: 让位后要同时满足「不被埋」「不顶出上沿」需要
##      band 高 ≤ av.y - kb - 2*_KB_GAP。**把这个上限和实测 band 并排打出来**。
##
## 跑法: <godot> --headless --path . res://tests/_probe_wall_vprofile.tscn --quit-after 3000

const SET := preload("res://scripts/scenes/SettingsScene.gd")
const SB := preload("res://scripts/net/supabase.gd")

const PX_PER_PT := 81.0 / 44.0
## 三档键盘(占视口高的比例)。依据全部写在这里, 不凭印象:
##   0.415 = iPhone 14/15 横屏 ASCII 键盘 162pt / 屏高 390pt(产品代码里已经用的那档)
##   0.520 = 同上加中文候选条(产品注释里写的「≈52%」那档)
##   0.580 = 窄屏 + 候选条的最坏一档(iPhone 13 mini 横屏 360pt 高, 键盘+候选条 ≈203pt)
const KB_TIERS := [0.415, 0.520, 0.580]
## 三种视口。1280x720 = 设计基准; 1560x720 = iPhone 横屏(canvas_items+expand 锁高);
## 1280x960 = iPad 4:3。
const VPS := [Vector2(1280, 720), Vector2(1560, 720), Vector2(1280, 960)]


func _w(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _tappable(c: Control) -> bool:
	return c is BaseButton or c is Range or c is LineEdit or c is TextEdit


func _label_of(c: Control) -> String:
	if c is Button:
		return "钮「%s」" % str((c as Button).text)
	if c is LineEdit:
		return "框「%s」" % str((c as LineEdit).placeholder_text)
	if c is Label:
		var t := str((c as Label).text).replace("\n", "⏎")
		return "字“%s”" % t.substr(0, 16)
	return "(%s)" % c.name


func _make_wall() -> Node:
	OS.set_environment("TURTLE_SUPABASE", "http://127.0.0.1:9")
	SB._reset_auth_for_test()
	GameState.test_mode = true
	GameState.account_email = ""
	GameState.account_id = "uid-vprof"
	var st = (load("res://scenes/Settings.tscn") as PackedScene).instantiate()
	st.acct_override = 1
	add_child(st)
	return st


func _box_of(st) -> Control:
	if st._email_layer == null or not is_instance_valid(st._email_layer):
		return null
	for ch in (st._email_layer as Node).get_children():
		if ch is Panel:
			return ch as Control
	return null


func _profile(tag: String, vp: Vector2, step: int = 1) -> void:
	print("")
	print("══════ %s  视口 %dx%d  第 %d 步 ══════" % [tag, int(vp.x), int(vp.y), step])
	get_tree().root.size = Vector2i(vp)
	await _w(2)
	var st = _make_wall()
	await _w(10)
	var box := _box_of(st)
	print("  分母: 墙在场=%s  框在场=%s" % [str(st._email_layer != null), str(box != null)])
	if box == null:
		st.queue_free()
		await _w(2)
		return
	if step == 2:
		## ★走**产品自己的入口**把墙推到第二步(不另开测试后门)。
		st._email_set_step(2)
		await _w(3)
	## `verify_ui_consistency` 的分母是「这一屏可见控件 ≥ MIN_CTRL(登录墙)=10」
	## ⇒ 分两步之后另一步的控件是隐的, 这个数会变小, 必须当场量。
	var vis := 0
	var stk: Array = [st]
	while not stk.is_empty():
		var n = stk.pop_back()
		if n is Control and (n as Control).is_visible_in_tree():
			vis += 1
		for ch in (n as Node).get_children():
			stk.append(ch)
	print("  `verify_ui_consistency` 口径的**可见控件数** = %d  (MIN_CTRL 登录墙 = 10)" % vis)
	var av: Vector2 = st._email_avail()
	print("  _email_avail() = %.0fx%.0f   框 pos=(%.0f, %.0f)  size=%.0fx%.0f"
		% [av.x, av.y, box.position.x, box.position.y, box.size.x, box.size.y])
	print("  框上沿离视口顶 %.0fpx   框下沿离视口底 %.0fpx"
		% [box.get_global_rect().position.y,
			vp.y - (box.get_global_rect().position.y + box.size.y)])

	## ② 框内所有 Control 子节点按 y 排序
	var kids: Array = []
	for ch in box.get_children():
		if ch is Control and (ch as Control).is_visible_in_tree():
			kids.append(ch)
	kids.sort_custom(func(a, b): return (a as Control).position.y < (b as Control).position.y)
	print("  ── 框内竖向剖面(框内局部坐标) ──")
	print("     %-4s %-5s %-5s %-6s %-26s %s" % ["y", "高", "底", "间隙", "是什么", "可点?短边"])
	var prev_bot: float = -1.0
	for c in kids:
		var cc := c as Control
		var y: float = cc.position.y
		var h: float = cc.size.y
		var gap: String = "  —" if prev_bot < 0.0 else "%+4.0f" % (y - prev_bot)
		var tap: String = ""
		if _tappable(cc):
			var mn: float = minf(cc.size.x, cc.size.y)
			tap = "★可点 短边 %.0fpx = %.1fpt" % [mn, mn / PX_PER_PT]
		print("     %-4.0f %-5.0f %-5.0f %-6s %-26s %s" % [y, h, y + h, gap, _label_of(cc).substr(0, 24), tap])
		prev_bot = maxf(prev_bot, y + h)

	## ③ 只看可点元素的相邻间隙
	var taps: Array = []
	for c in kids:
		if _tappable(c as Control):
			taps.append(c)
	print("  ── 可点元素之间的竖直间隙(玩家瞄错就点进隔壁的那一维) ──")
	for i in range(taps.size()):
		var a := taps[i] as Control
		var mn: float = minf(a.size.x, a.size.y)
		var g: String = ""
		if i > 0:
			var p := taps[i - 1] as Control
			g = "与上一个间隙 %+.0fpx" % (a.position.y - (p.position.y + p.size.y))
		print("     #%d %-24s y=%-5.0f h=%-4.0f 短边 %.0fpx=%.1fpt  %s"
			% [i + 1, _label_of(a).substr(0, 22), a.position.y, a.size.y, mn, mn / PX_PER_PT, g])

	## ④ band
	var band: Vector2 = st._email_ctl_band()
	print("  ── 可点元素竖向占的那一段(键盘让位公式的分子) ──")
	print("     band = 顶 %.0f → 底 %.0f, 高 %.0f  (框高 %.0f)"
		% [band.x, band.y, band.y - band.x, box.size.y])

	## ⑤ 键盘可行域 + 实测让位
	print("  ── 键盘让位: 三档 ──")
	for kb_frac in KB_TIERS:
		var kb: float = av.y * kb_frac
		var room: float = av.y - kb - 2.0 * 8.0      ## 8 = SettingsScene._KB_GAP
		SET.vkb_override_vp = kb
		await _w(3)
		var kb_top: float = vp.y - kb
		var buried: Array = []
		var above: Array = []
		for c in taps:
			var r: Rect2 = (c as Control).get_global_rect()
			if r.position.y + r.size.y > kb_top:
				buried.append("%s@%.0f" % [_label_of(c as Control).substr(0, 10), r.position.y])
			if r.position.y < 0.0:
				above.append(_label_of(c as Control).substr(0, 10))
		print("     kb %.1f%% = %.0fpx (顶边 y=%.0f) | band 高 %.0f vs 可行上限 %.0f %s | 框挪到 y=%.0f"
			% [kb_frac * 100.0, kb, kb_top, band.y - band.x, room,
				("✓" if (band.y - band.x) <= room else "✗超"), box.position.y])
		print("        被埋: %s   顶出上沿: %s" % [str(buried), str(above)])
	SET.vkb_override_vp = -1.0
	await _w(3)
	print("     收起键盘后框回到 y=%.0f" % box.position.y)
	st.queue_free()
	await _w(2)


## 「设置里主动绑定/取回」那一档(可关闭)。两条流程各量两步。
func _dialog_profile() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	await _w(2)
	OS.set_environment("TURTLE_SUPABASE", "http://127.0.0.1:9")
	GameState.test_mode = true
	GameState.account_email = "me@x.co"      ## 绑过了 ⇒ 不开墙, 走"自己点开"那一档
	var st = (load("res://scenes/Settings.tscn") as PackedScene).instantiate()
	add_child(st)
	await _w(8)
	for flow in ["bind", "recover"]:
		st._open_email_dialog(flow)
		await _w(6)
		var box := _box_of(st)
		if box == null:
			print("  [!] %s 对话框没建起来" % flow)
			continue
		for step in [1, 2]:
			st._email_set_step(step)
			await _w(3)
			print("")
			print("══════ 可关闭对话框 flow=%s 第 %d 步 ══════" % [flow, step])
			print("  框 size=%.0fx%.0f  pos=(%.0f, %.0f)" % [box.size.x, box.size.y,
				box.position.x, box.position.y])
			var rows: Array = []
			for ch in box.get_children():
				if (ch is LineEdit or ch is BaseButton) and (ch as Control).is_visible_in_tree():
					rows.append(ch)
			rows.sort_custom(func(a, b): return (a as Control).position.y < (b as Control).position.y)
			for c in rows:
				var cc := c as Control
				var mn: float = minf(cc.size.x, cc.size.y)
				print("     %-22s x=%-4.0f y=%-4.0f %.0fx%.0f  短边 %.0fpx=%.1fpt"
					% [_label_of(cc).substr(0, 20), cc.position.x, cc.position.y,
						cc.size.x, cc.size.y, mn, mn / PX_PER_PT])
			var band: Vector2 = st._email_ctl_band()
			var room: float = 720.0 - 720.0 * 0.520 - 16.0
			print("     band 高 %.0f  vs 中文键盘那档(52%%)上限 %.0f  %s"
				% [band.y - band.x, room, ("✓" if (band.y - band.x) <= room else "✗超")])
		st._email_layer.queue_free()
		st._email_layer = null
		st._email_box = null
		await _w(3)
	st.queue_free()
	await _w(2)


func _ready() -> void:
	await _w(2)
	print("=== 登录墙竖向剖面探针 ===")
	print("触摸线: 81px = 44pt  (1pt = %.4fpx)" % PX_PER_PT)
	for i in range(VPS.size()):
		await _profile("剖面 %d" % (i + 1), VPS[i])
	## 第二步也要量一遍 —— 它有自己的三行(验证码/确认/回上一步), 键盘也照样弹着。
	for i in range(VPS.size()):
		await _profile("剖面 %d-第二步" % (i + 1), VPS[i], 2)
	## ★**设置页里主动打开**的那一档(可关闭)也要量: 它多一个「关闭」,
	##   而候选 A 把「关闭」**并排**放在主按钮右边(占了新的一行就是四行, 中文键盘那档当场破)。
	await _dialog_profile()
	print("")
	print("PROBE DONE")
	get_tree().quit(0)
