extends Node

## verify_tutorial_highlight.gd — 高亮遮罩 (用户 2026-07-23 教学阶段 B; 2026-10-07 去掉 mandatory/按钮)
##
## 现有引导只是黄框文字, 说"点头像"却没东西指着 —— 是说明书不是手把手。
## 本阶段加暗幕挖洞: 压暗全屏、目标处挖亮洞、其余挡点击。逼玩家只能点该点的地方。

const TutorialGuide := preload("res://scripts/scenes/TutorialGuide.gd")

var _fail: int = 0
var _fake_rect := Rect2(100, 200, 300, 60)


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _tutorial_anchor(name: String) -> Rect2:
	if name == "target_a":
		return _fake_rect
	return Rect2()


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


func _count_visible_masks(g: Node) -> int:
	var v: int = 0
	for n in _walk(g):
		if n is ColorRect and (n as ColorRect).get_script() == null and (n as ColorRect).visible:
			v += 1
	return v


func _ready() -> void:
	await get_tree().process_frame

	var g := TutorialGuide.new()
	add_child(g)
	var steps: Array = [
		{"text": "第一步 高亮 A", "highlight": "target_a", "advanceOn": "a"},
		{"text": "第二步 无高亮", "advanceOn": "b"},
	]
	g.start(steps, func() -> void: pass, Callable(self, "_tutorial_anchor"))
	for _i in range(TutorialGuide.STABLE_FRAMES + 3):
		await get_tree().process_frame

	# ① 2026-10-07: 引导条里一个按钮都没有(「跳过教程」在导演挂的外壳上, 不在引导条里)
	var n_btn: int = 0
	for n in _walk(g):
		if n is Button:
			n_btn += 1
	print("  [实测] 引导条里的按钮数: %d (应=0)" % n_btn)
	_ok("★引导条里没有任何按钮(下一步/知道了/跳过 全删)", n_btn == 0)

	# ② 暗幕四块 + 亮框
	var masks: Array = []
	var ring: ColorRect = null
	for n in _walk(g):
		if n is ColorRect:
			if (n as ColorRect).get_script() != null:
				ring = n
			else:
				masks.append(n)
	print("  [实测] 暗幕块数=%d 亮框=%s" % [masks.size(), ring != null])
	_ok("★有 4 块暗幕(挖洞用)", masks.size() == 4)
	_ok("★有亮边框", ring != null)
	_ok("★★第一步(带 highlight)暗幕可见(在压暗)", _count_visible_masks(g) == 4)

	if ring != null:
		var covers: bool = ring.position.x <= _fake_rect.position.x \
			and ring.position.y <= _fake_rect.position.y \
			and ring.position.x + ring.size.x >= _fake_rect.end.x \
			and ring.position.y + ring.size.y >= _fake_rect.end.y
		print("  [实测] 亮框 %s 罩住目标 %s ? %s" % [Rect2(ring.position, ring.size), _fake_rect, covers])
		_ok("★★挖的洞对准了目标矩形", covers)

	# ③ 切到第二步(无 highlight) → 整条不显示(没有目标就不挡人)
	g.notify("a")
	for _i in range(TutorialGuide.STABLE_FRAMES + 3):
		await get_tree().process_frame
	print("  [实测] 第二步(无 highlight)可见暗幕 = %d  显示=%s" % [_count_visible_masks(g), str(g.is_showing())])
	_ok("★无 highlight 的步不挖洞、不显示(暗幕不挡人)", _count_visible_masks(g) == 0 and not g.is_showing())

	# ④ 锚点解析空矩形 → 不挖空洞把全屏挡死
	var g2 := TutorialGuide.new()
	add_child(g2)
	g2.start([{"text": "坏锚点", "highlight": "不存在的名字", "advanceOn": "x"}], func() -> void: pass, Callable(self, "_tutorial_anchor"))
	await get_tree().process_frame
	print("  [实测] 坏锚点时可见暗幕 = %d (应=0, 否则全屏被挡死)" % _count_visible_masks(g2))
	_ok("★锚点解析失败时不挖空洞(退回无高亮)", _count_visible_masks(g2) == 0)

	# ⑤ ★空矩形的那条 WARNING 不许每帧刷 (2026-09-30)
	## 由来: 修台账 ⑧ 让摆位引导第一次真出场后, 当场量到一个【每帧连刷】的真形状 ——
	##   摆位第三步 highlight 的是「开打」钮, 玩家一按开打它就 visible=false ⇒ 锚点恒空
	##   ⇒ 这条 WARNING 一直刷到玩家点「完成」。日志被冲垮, 而它原本是用来报警的。
	## ★判据量的是产品自己的两个字段(`_hl_empty_frames` 计数 / `_hl_warned` 闩), 不是我插的标记:
	##   计数一直在涨 = 每帧都真的走到了那个分支(= 分母), 而闩只翻一次 = push_warning 只发了一条。
	## ⚠ 已知缺口: GDScript 数不到"引擎真打了几条 WARNING", 这里量的是产品自己那道闩。
	for _w in range(30):
		await get_tree().process_frame
	print("  [实测] 坏锚点 30 帧后: _hl_empty_frames=%d  _hl_warned=%s"
		% [int(g2._hl_empty_frames), str(g2._hl_warned)])
	_ok("★分母: 那个分支真的每帧都在走(空帧计数 > 宽限帧数, 否则下一条是空检查)",
		int(g2._hl_empty_frames) > int(TutorialGuide.HL_GRACE_FRAMES) + 10,
		"_hl_empty_frames=%d 宽限=%d" % [int(g2._hl_empty_frames), int(TutorialGuide.HL_GRACE_FRAMES)])
	_ok("★★空矩形警告只发一条(闩住了) —— 没这道闩就是每帧一条冲垮日志",
		bool(g2._hl_warned), "_hl_warned=%s" % str(g2._hl_warned))

	print("ALL PASS — 高亮遮罩" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
