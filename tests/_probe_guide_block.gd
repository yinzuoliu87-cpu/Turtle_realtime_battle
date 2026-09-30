extends Node
## _probe_guide_block.gd — 台账 ⑧ 修好之后那层【挡点击的暗幕】到底挡住了谁(探针, 不进门禁)。
##
## 修 ⑧ 之前这层浮层从没在玩家面前出现过 ⇒ 它的交互路径**一次都没被走过**。
## 本仓教训「拦住人的同时别拦住解锁动作」: 首次教学是 mandatory(**没有跳过钮**),
## 摆位这三步里唯一的出路就是提示条上那颗「下一步 ▶ / 完成 ✓」。要是它也被自家暗幕挡住,
## 玩家就永久卡在摆位屏(开打钮也被挡) —— 比原 bug 狠得多。
##
## 量的是引擎自己的命中测试(`gui_get_hovered_control()` 就是决定这一下点击给谁的那套),
## 外加一次真 `push_input` 点击看步数有没有前进。
##
## 跑法: SHIP=1 TURTLE_SUPABASE=" " <godot> --headless --path . res://tests/_probe_guide_block.tscn --quit-after 2000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null
var _g = null


func _hover_at(p: Vector2) -> Control:
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	get_viewport().push_input(mm)
	return get_viewport().gui_get_hovered_control()


func _who(p: Vector2) -> String:
	var c := _hover_at(p)
	if c == null:
		return "null(没有控件吃它 ⇒ 落到场景/3D 输入)"
	var tag := c.get_class()
	if _g != null:
		for i in (_g._mask as Array).size():
			if is_same(c, (_g._mask as Array)[i]):
				tag += " = 暗幕[%d]★挡住" % i
	if c is Button:
		tag += " = 按钮「%s」" % str((c as Button).text)
	return tag


func _click(p: Vector2) -> void:
	_hover_at(p)
	for down in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = down
		mb.position = p
		mb.global_position = p
		get_viewport().push_input(mb)
	await get_tree().process_frame


func _next_btn() -> Button:
	var kids: Array = (_g._btn_row as HBoxContainer).get_children()
	return kids[kids.size() - 1] as Button if not kids.is_empty() else null


func _dump_step(tag: String) -> void:
	var idx: int = int(_g._idx)
	var hl: String = str(_g._cur_hl)
	var vis := 0
	for m in (_g._mask as Array):
		if (m as Control).visible:
			vis += 1
	var nb := _next_btn()
	print("── %s 步 %d/%d  highlight=%s  可见暗幕=%d/4  出路钮=「%s」@%s ──" % [
		tag, idx + 1, int((_g._steps as Array).size()), (hl if hl != "" else "(无)"), vis,
		(str(nb.text) if nb != null else "无"),
		(str(nb.get_global_rect()) if nb != null else "-")])
	var go = _s._dl_go_btn
	print("    「开打」钮 rect=%s visible=%s" % [str(go.get_global_rect()), str(go.visible)])
	if nb != null:
		print("    点「%s」那一点  → %s" % [str(nb.text), _who(nb.get_global_rect().get_center())])
	print("    点「开打」那一点   → %s" % _who(go.get_global_rect().get_center()))
	print("    点我方半场中心     → %s" % _who(Rect2(_s._tutorial_anchor("field")).get_center()))


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	var td = get_node_or_null("/root/TutorialDirector")
	if gs == null or td == null:
		print("[FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame

	gs.tutorial = true
	gs.tutorial_active = true
	gs.tutorial_stage = "match1"
	gs.tutorial_mandatory = true
	var lt: Array[String] = []
	for id in td.FIXED_TEAM:
		lt.append(str(id))
	gs.season_leaders = lt.duplicate()
	gs.left_team.assign(lt)
	gs.dual_lineup = {}
	gs.reset_dual_lane()
	td.arm_battle_sandbox()
	DualLaneFlow.NO_PRESENT = true

	_s = RB.new()
	add_child(_s)
	var w := 0
	while w < 600 and str(_s._dl_state) != "place":
		await get_tree().process_frame
		w += 1
	_g = _s._tutorial
	print("[分母] _dl_state=%s  引导实例=%s  mandatory=%s  步数=%d" % [
		str(_s._dl_state), str(_g != null),
		(str(_g._mandatory) if _g != null else "-"),
		(int((_g._steps as Array).size()) if _g != null else 0)])
	if _g == null:
		print("[FAIL] 引导没挂上, 后面没得量"); get_tree().quit(1); return
	# 等布局落定(首帧容器还没算 rect, 洞会是空的 —— 见 TutorialGuide._apply_highlight 那段注释)
	for _i in range(20):
		await get_tree().process_frame

	# ── 逐步走: 每步先看命中测试, 再真点一下出路钮 ──
	var n_steps: int = int((_g._steps as Array).size())
	for st in range(n_steps):
		_dump_step("步%d" % (st + 1))
		var hl: String = str(_g._cur_hl)
		var last: bool = int(_g._idx) == n_steps - 1
		# ★只有本步高亮的【不是】开打钮时, 开打才该被挡住 —— 真点一下看 _dl_state 动不动
		if hl != "" and hl != "go_button":
			var before_state: String = str(_s._dl_state)
			await _click((_s._dl_go_btn as Button).get_global_rect().get_center())
			print("    ⇒ 真点「开打」: %s → %s  %s" % [before_state, str(_s._dl_state),
				("✓挡住了" if str(_s._dl_state) == "place" else "★★漏挡")])
		elif hl == "":
			print("    (本步无 highlight ⇒ 按设计不挖洞不挡任何东西, 不测开打)")
		if last:
			# ★最后一步 highlight 的就是开打钮 —— 玩家照提示按下去, 引导该自己收掉
			print("    ⇒ 最后一步: 照提示真按「开打」")
			await _click((_s._dl_go_btn as Button).get_global_rect().get_center())
			for _k in range(10):
				await get_tree().process_frame
			print("    _dl_state=%s  引导还在吗=%s %s" % [str(_s._dl_state), str(is_instance_valid(_g)),
				("✓按开打就收掉了" if not is_instance_valid(_g) else "★★还挂着(会每帧刷空矩形警告+说假话)")])
			break
		var idx0: int = int(_g._idx)
		var nb := _next_btn()
		if nb == null:
			print("    ★★没有出路钮 ⇒ 死局"); break
		await _click(nb.get_global_rect().get_center())
		if not is_instance_valid(_g):
			print("    ⇒ 点完出路钮: 引导已收掉")
			break
		print("    ⇒ 点完出路钮: _idx %d → %d %s" % [idx0, int(_g._idx),
			("✓前进了" if int(_g._idx) > idx0 else "★★没动 = 出路钮被自家暗幕挡住 = 死局")])
		for _j in range(6):
			await get_tree().process_frame

	print("── 收尾 ──")
	print("  引导还在吗 = %s" % str(is_instance_valid(_g)))
	print("  tut_overlay 节点数 = %d" % get_tree().get_nodes_in_group("tut_overlay").size())
	print("  _dl_state = %s (fight = 真开打了)" % str(_s._dl_state))
	# 引导收掉后, 暗幕也该一起没了 → 场上任何一点都不再被它吃掉
	print("  引导收掉后 点屏幕中心 → %s" % _who(Vector2(640, 360)))

	# ── 反向角: 最后一步的 highlight 目标被藏起来时, 警告刷几条 ──
	print("── 空矩形警告的节流(最后一步 highlight=go_button, 而开打钮此刻已隐藏) ──")
	var g2 = load("res://scripts/scenes/TutorialGuide.gd").new()
	add_child(g2)
	g2.start([{"text": "指着一个不存在的锚点", "highlight": "__不存在的名字__"}],
		func() -> void: pass, true, Callable(_s, "_tutorial_anchor"))
	for _m in range(30):
		await get_tree().process_frame
	print("  30 帧之后: _hl_empty_frames=%d  _hl_warned=%s (warned 只该是 1 次, 不是 30 条)" % [
		int(g2._hl_empty_frames), str(g2._hl_warned)])
	g2.queue_free()

	_s.queue_free()
	await get_tree().process_frame
	print("PROBE DONE")
	get_tree().quit(0)
