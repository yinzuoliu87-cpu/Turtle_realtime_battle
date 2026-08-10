extends Node
## verify_inventory_text_fit.gd — 背包底栏的装备文案【不许被裁尾】(2026-08-11)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来: 2026-08-10 全表自查时发现的候选项 D
## ══════════════════════════════════════════════════════════════════
## `InventoryScene` 选中一件装备时，底栏用
##   `l.size = Vector2(bw - 320, 48)`
## 固定 **48 px 高**显示 `effectDesc1`。而新一批装备的文案普遍很长：
##   中位数 116 字 / 平均 122 / **最长 327 字（p2eq_084 手半剑）**。
## 14 号字 + 4 行距 ⇒ 一行约 18 px ⇒ 48 px 只装得下约 2.6 行。
##
## ★这条门禁**量真实对象**：拿 `RichTextLabel.get_content_height()`（引擎算出来的
##   真实排版高度）比它的框高，而不是我自己按"每行几个字"去估。
##   （memory [[fb-write-without-reader-and-fake-gates]]: 门禁模拟公式 ≠ 量真实对象。）
##
## ★分母：必须真的选中**最长的那一件**，否则拿中位数长度的件去测永远绿。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_inventory_text_fit.tscn --quit-after 1200

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 找出文案最长的那件装备
func _longest_id() -> String:
	var best := ""
	var bl := -1
	for e in DataRegistry.phase2_equipment:
		if not (e is Dictionary):
			continue
		var n: int = str((e as Dictionary).get("effectDesc1", "")).length()
		if n > bl:
			bl = n
			best = str((e as Dictionary).get("id", ""))
	return best


func _rich_labels(n: Node, out: Array) -> void:
	if n is RichTextLabel:
		out.append(n)
	for c in n.get_children():
		_rich_labels(c, out)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 背包底栏文案是否放得下 ===")
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.size = Vector2i(1280, 720)
	for _q in range(4):
		await get_tree().process_frame

	var eid: String = _longest_id()
	var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
	var txt_len: int = str(edef.get("effectDesc1", "")).length()
	_ok("★分母: 找到文案最长的装备 %s(%s) —— %d 字" % [eid, str(edef.get("name", "")), txt_len],
		txt_len > 200, "只有 %d 字 ⇒ 拿它测等于没测" % txt_len)

	# 把它放进背包并选中
	GameState.persistent_bench = [{"id": eid, "star": 1}]
	var sc = load("res://scenes/Inventory.tscn").instantiate()
	get_tree().root.add_child(sc)
	for _i in range(20):
		await get_tree().process_frame
	sc._sel_bench = 0
	sc._rebuild()
	for _i in range(10):
		await get_tree().process_frame

	var labs: Array = []
	_rich_labels(sc, labs)
	var target: RichTextLabel = null
	for l in labs:
		if str((l as RichTextLabel).text).find(str(edef.get("name", ""))) >= 0:
			target = l
			break
	_ok("★分母: 底栏真的显示出了这件装备的文案(找到那个 RichTextLabel)", target != null)
	if target != null:
		## ★★第一版我量的是 "内容高 ≤ 框高" —— **量错了对象**。
		##   `fit_content = true` 会让 RichTextLabel 自己长高, 于是两边永远相等(110 = 110),
		##   断言恒真。真正的毛病不是"裁尾"而是 **溢出** ——
		##   底栏只有 66 px 高、从 y=636 起, 而 label 长到 110 px ⇒ 底部直接冲出 720 设计框。
		##   ⇒ 改成量它的**真实屏幕矩形**: 不能冲出底栏、更不能冲出屏幕。
		var lr: Rect2 = target.get_global_rect()
		var bar: Control = target.get_parent() as Control
		var br: Rect2 = bar.get_global_rect() if bar != null else Rect2()
		var vp: Vector2 = get_tree().root.get_visible_rect().size
		print("    [探针] 文案框 %s / 底栏 %s / 视口高 %.0f" % [str(lr), str(br), vp.y])
		_ok("★★文案框不能冲出【底栏】(长 %.0f px 而底栏只有 %.0f px)"
			% [lr.size.y, br.size.y], lr.end.y <= br.end.y + 1.0,
			"文案底部 %.0f > 底栏底部 %.0f, 多出 %.0f px" % [lr.end.y, br.end.y, lr.end.y - br.end.y])
		_ok("★★文案框不能冲出【屏幕】(否则后几行直接在画面外)",
			lr.end.y <= vp.y + 1.0,
			"文案底部 %.0f > 视口高 %.0f, 多出 %.0f px" % [lr.end.y, vp.y, lr.end.y - vp.y])

	sc.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 背包文案放得下" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
