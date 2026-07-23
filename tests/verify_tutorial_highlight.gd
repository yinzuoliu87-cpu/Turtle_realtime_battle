extends Node

## verify_tutorial_highlight.gd — 高亮遮罩 + mandatory (用户 2026-07-23 教学阶段 B)
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
		{"text": "第一步 高亮 A", "highlight": "target_a"},
		{"text": "第二步 无高亮"},
	]
	g.start(steps, func() -> void: pass, true, Callable(self, "_tutorial_anchor"))
	await get_tree().process_frame

	# ① mandatory=true → 无"跳过"按钮
	var has_skip: bool = false
	for n in _walk(g):
		if n is Button and str((n as Button).text).contains("跳过"):
			has_skip = true
	print("  [实测] mandatory 首步按钮里有'跳过'吗: %s (应=false)" % has_skip)
	_ok("★首次强制无'跳过'按钮(mandatory)", not has_skip)

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

	# ③ 切到第二步(无 highlight) → 暗幕隐藏
	g._next()
	await get_tree().process_frame
	print("  [实测] 第二步(无 highlight)可见暗幕 = %d" % _count_visible_masks(g))
	_ok("★无 highlight 的步不挖洞(暗幕隐藏)", _count_visible_masks(g) == 0)

	# ④ 锚点解析空矩形 → 不挖空洞把全屏挡死
	var g2 := TutorialGuide.new()
	add_child(g2)
	g2.start([{"text": "坏锚点", "highlight": "不存在的名字"}], func() -> void: pass, true, Callable(self, "_tutorial_anchor"))
	await get_tree().process_frame
	print("  [实测] 坏锚点时可见暗幕 = %d (应=0, 否则全屏被挡死)" % _count_visible_masks(g2))
	_ok("★锚点解析失败时不挖空洞(退回无高亮)", _count_visible_masks(g2) == 0)

	print("ALL PASS — 高亮遮罩 + mandatory" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
