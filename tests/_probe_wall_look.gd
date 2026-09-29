extends Node
## _probe_wall_look.gd — 登录墙「长什么样」的剖面探针 (2026-09-29)
##
## 只读: 不断言, 只把数打出来。用途:
##   ① 墙立起来时, self 下面还有哪些 Control 是可见的(背景到底在不在)
##   ② 每一步的行矩形 / 间隙 / band / 框高
##   ③ 说明文字**渲染后**真正占几行(靠猜字数会错)
##   ④ 键盘让位的净空除法: 每一档实测能装多高的 band
##
## 跑法: <godot> --headless --path . res://tests/_probe_wall_look.tscn --quit-after 900
const SET := preload("res://scripts/scenes/SettingsScene.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const SB := preload("res://scripts/net/supabase.gd")
const DEAD_URL := "http://127.0.0.1:9"
const KB_TIERS := [0.415, 0.520, 0.580]
const VP_MATRIX := [Vector2(1280.0, 720.0), Vector2(1560.0, 720.0), Vector2(1280.0, 960.0)]


func _wf(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	await _wf(2)
	GameState.test_mode = true
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	SB._reset_auth_for_test()
	GameState.account_email = ""
	GameState.account_id = "uid-probe"
	GameState.nickname = ""
	get_tree().root.size = Vector2i(1560, 720)
	await _wf(2)

	print("=== 文案事实源 ===")
	var body := str(P2C.login_wall_body())
	var ln := body.split("
")
	print("  login_wall_body() 源码行数 = %d" % ln.size())
	for i in range(ln.size()):
		print("    [%d] %d 字: %s" % [i, str(ln[i]).length(), str(ln[i])])
	print("  login_wall_head() = 「%s」" % str(P2C.login_wall_head()))

	var inst = (load("res://scenes/Settings.tscn") as PackedScene).instantiate()
	inst.acct_override = 1
	add_child(inst)
	await _wf(8)
	print("=== 墙立起来了吗: %s ===" % str(inst._email_layer != null))
	if inst._email_layer == null:
		get_tree().quit(0)
		return

	print("=== self 下面还剩什么可见的(背景在不在) ===")
	for ch in inst.get_children():
		if ch is Control:
			print("  %-14s %-12s visible=%s" % [str(ch.name).substr(0, 14),
				ch.get_class(), str((ch as Control).visible)])
	print("  遮罩层子节点:")
	for ch in (inst._email_layer as Node).get_children():
		var rr := ""
		if ch is Control:
			rr = str((ch as Control).get_global_rect())
		print("    %-14s %-14s %s" % [str(ch.name).substr(0, 14), ch.get_class(), rr])

	var box: Control = inst._email_box
	print("=== 框 ===")
	print("  box %s   视口 %s" % [str(box.get_global_rect()), str(get_tree().root.size)])

	for step in [1, 2]:
		inst._email_set_step(step)
		await _wf(3)
		print("=== 第 %d 步 ===" % step)
		var hot: Array = []
		for ch in (box as Node).get_children():
			if (ch is LineEdit or ch is BaseButton) and (ch as Control).is_visible_in_tree():
				hot.append(ch)
		hot.sort_custom(func(a, b): return (a as Control).position.y < (b as Control).position.y)
		var prev: Control = null
		for c in hot:
			var cc := c as Control
			var g := "—"
			if prev != null and cc.position.x < prev.position.x + prev.size.x 					and prev.position.x < cc.position.x + cc.size.x:
				g = "%+.0fpx" % (cc.position.y - (prev.position.y + prev.size.y))
			print("  %-16s %4.0f,%4.0f %4.0fx%3.0f  竖隙 %s" % [
				_lbl(cc), cc.position.x, cc.position.y, cc.size.x, cc.size.y, g])
			prev = cc
		var band: Vector2 = inst._email_ctl_band()
		print("  band = %.0f ~ %.0f  (高 %.0f)" % [band.x, band.y, band.y - band.x])
		for l in [["正文", inst._email_why], ["正文2", inst._email_why2], ["小字", inst._email_hint]]:
			var lb := l[1] as Label
			if lb == null:
				continue
			print("  %-5s visible=%-5s 渲染 %d 行  %4.0fx%3.0f  「%s」" % [str(l[0]),
				str(lb.is_visible_in_tree()), lb.get_line_count(), lb.size.x, lb.size.y,
				str(lb.text).replace("
", " / ")])

	inst._email_set_step(1)
	await _wf(3)
	print("=== 键盘让位的净空除法(每一档最多能装多高的 band) ===")
	var band1: Vector2 = inst._email_ctl_band()
	print("  现在的 band 高 = %.0f px   _KB_GAP = %.0f" % [band1.y - band1.x, inst._KB_GAP])
	for v in VP_MATRIX:
		for frac in KB_TIERS:
			var room: float = v.y - v.y * float(frac) - 2.0 * inst._KB_GAP
			print("  %dx%d kb %.1f%% ⇒ 净空 %.1f px  (三行 81 时 gap ≤ %.1f)" % [
				int(v.x), int(v.y), float(frac) * 100.0, room, (room - 3.0 * 81.0) / 2.0])

	print("PROBE DONE")
	inst.queue_free()
	await _wf(2)
	get_tree().quit(0)


func _lbl(c: Control) -> String:
	if c is Button:
		return str((c as Button).text)
	if c is LineEdit:
		return "[%s]" % str((c as LineEdit).placeholder_text)
	return str(c.name)
