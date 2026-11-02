extends Node
## 探针 2: 训龟大师【每个子控件 rect vs 框内容区】全剖面 —— 不猜, 量。
##
## ★ 为什么要第二份: 探针 1 只打了"卡多高/边带多厚/三样东西各占多高", 而门禁
##   `verify_ui_consistency._audit` 判的是**每一条文字/图 的 ink 矩形 与 最小包含框的
##   inner 矩形 的四边越出量取最大**。探针 1 打的量和门禁判的量**不是同一个量** ——
##   所以照探针 1 调 offset 会越调越偏(实测: 四边各 8 → 越界从 4 变 10)。
## ⇒ 这份探针直接复用门禁的 `_audit`(**同一把尺子**)拿判定清单, 再自己打一份
##   逐控件四边剖面, 好知道该动哪一边、动多少。
const UIC := preload("res://tests/verify_ui_consistency.gd")

var _aud = null


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await get_tree().process_frame
	var sc = load("res://scenes/TrainerConfig.tscn").instantiate()
	add_child(sc)
	## ⚠ UIC **不能常驻场景树**: 它 `_ready` 会自己把 12 个屏全审一遍(第一版探针就这样,
	##   打了一屏 MainMenu 的报告然后被 --quit-after 掐断, 训龟大师一个数都没量到)。
	##   ⇒ 只在调 `_audit`(它要 `get_viewport()`)的那一瞬间挂进树, 不 await, 马上摘掉 + free。
	_aud = UIC.new()
	var settled: bool = await _settle_local(sc)
	print("=== 版面稳住了吗: %s ===" % ("是" if settled else "★否(下面的数全不算数)"))

	# ── ① 门禁自己的判定清单(同一把尺子, 不是我另造的) ──
	add_child(_aud)
	var d: Dictionary = _aud._audit(sc)
	remove_child(_aud)
	var fr: Array = d["frame"]
	print("[门禁] 压边带 frame = %d 条   (基线 TrainerConfig=7, 目标 0)" % fr.size())
	for s in fr:
		print("        · %s" % str(s))
	## ★圆角/网页盒的**明细**(要 UICONS_DUMP=1) —— 只看个数改不动东西, 得知道是谁。
	for s2 in (d["hits"] as Array):
		print("        [圆角/网页盒] %s" % str(s2))
	print("[门禁] round=%d web=%d tap=%d overlap=%s spill=%s clip=%s stock=%s" % [
		int(d["round"]), int(d["web"]), (d["tap"] as Array).size(),
		str(d["overlap"]), str(d["spill"]), str(d["clip"]), str(d["stock"])])

	# ── ①.5 竖向还剩多少余量(决定"能不能把卡做高"而不是猜) ──
	var vp := Vector2(get_viewport().get_visible_rect().size)
	var area: float = vp.x * vp.y
	var bb := Rect2()
	var have := false
	var st0: Array = [sc]
	while not st0.is_empty():
		var n0 = st0.pop_back()
		if n0 is Control and (n0 as Control).is_visible_in_tree():
			var r0: Rect2 = (n0 as Control).get_global_rect()
			if r0.size.x >= 1.0 and r0.size.y >= 1.0 and r0.size.x * r0.size.y < area * 0.95:
				if have:
					bb = bb.merge(r0)
				else:
					bb = r0
					have = true
		for ch0 in n0.get_children():
			st0.append(ch0)
	print("[余量] 视口 %.0fx%.0f   内容 bbox y %.1f~%.1f (高 %.1f)  x %.1f~%.1f" % [
		vp.x, vp.y, bb.position.y, bb.end.y, bb.size.y, bb.position.x, bb.end.x])
	print("[余量] 上留 %.1f  下留 %.1f  ⇒ 竖向总共还能长 %.1f px(留 8px 安全边则 %.1f)" % [
		bb.position.y, vp.y - bb.end.y, bb.position.y + (vp.y - bb.end.y),
		bb.position.y + (vp.y - bb.end.y) - 16.0])

	# ── ② 逐控件四边剖面 ──
	print("=== 逐卡剖面(band=贴图量出的边带; over=四边越出 inner 的最大值, >2 门禁就红) ===")
	var st: Array = [sc]
	var cards: Array = []
	while not st.is_empty():
		var c = st.pop_back()
		if c is Button and c.has_theme_stylebox_override("normal"):
			var sb = c.get_theme_stylebox("normal")
			if sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null:
				cards.append(c)
		for ch in c.get_children():
			st.append(ch)
	cards.sort_custom(func(a, b):
		var ra: Rect2 = (a as Control).get_global_rect()
		var rb: Rect2 = (b as Control).get_global_rect()
		if absf(ra.position.y - rb.position.y) > 4.0:
			return ra.position.y < rb.position.y
		return ra.position.x < rb.position.x)
	for c in cards:
		_dump_card(c as Button)
	_aud.free()
	get_tree().quit(0)


## 和 UIC `_settle` 逐字同一套(墙钟·连续 6 帧矩形和不变), 只是不需要 UIC 在树上。
func _settle_local(root: Node) -> bool:
	var last := -1.0
	var same := 0
	var t0: float = float(Time.get_ticks_msec()) / 1000.0
	while float(Time.get_ticks_msec()) / 1000.0 - t0 < UIC.MAX_WAIT:
		await get_tree().process_frame
		if float(Time.get_ticks_msec()) / 1000.0 - t0 < UIC.MIN_WAIT:
			continue
		var acc := 0.0
		var st: Array = [root]
		while not st.is_empty():
			var n: Node = st.pop_back()
			if n is Control and (n as Control).is_visible_in_tree():
				var r := (n as Control).get_global_rect()
				acc += r.position.x + r.position.y * 3.0 + r.size.x * 7.0 + r.size.y * 11.0
			for ch in n.get_children():
				st.append(ch)
		if absf(acc - last) < 0.5:
			same += 1
			if same >= 6:
				return true
		else:
			same = 0
		last = acc
	return false


func _dump_card(card: Button) -> void:
	var r: Rect2 = card.get_global_rect()
	var sb = card.get_theme_stylebox("normal")
	var band: float = _aud._band_of((sb as StyleBoxTexture).texture)
	var inner := Rect2(r.position + Vector2(band, band), r.size - Vector2(band, band) * 2.0)
	print("[卡] %.0fx%.0f @(%.0f,%.0f)  band=%.1f  inner y %.1f~%.1f (高 %.1f) x %.1f~%.1f (宽 %.1f)" % [
		r.size.x, r.size.y, r.position.x, r.position.y, band,
		inner.position.y, inner.end.y, inner.size.y,
		inner.position.x, inner.end.x, inner.size.x])
	var st: Array = [card]
	var need: float = 0.0
	while not st.is_empty():
		var k = st.pop_front()
		if k is VBoxContainer:
			var vr: Rect2 = (k as Control).get_global_rect()
			print("     VBox      rect y %.1f~%.1f (高 %.1f)  x %.1f~%.1f (宽 %.1f)  sep=%d" % [
				vr.position.y, vr.end.y, vr.size.y, vr.position.x, vr.end.x, vr.size.x,
				(k as VBoxContainer).get_theme_constant("separation")])
		elif k is Label and str((k as Label).text).strip_edges() != "":
			var lb := k as Label
			var ir: Rect2 = _aud._ink_rect(lb)
			var cr: Rect2 = lb.get_global_rect()
			print("     字「%-4s」fs=%-3d 控件 y %.1f~%.1f  ink y %.1f~%.1f x %.1f~%.1f  行数 %d/%d  %s" % [
				str(lb.text), lb.get_theme_font_size("font_size"),
				cr.position.y, cr.end.y, ir.position.y, ir.end.y, ir.position.x, ir.end.x,
				lb.get_visible_line_count(), lb.get_line_count(), _over(ir, inner)])
			need = maxf(need, _over_val(ir, inner))
		elif k is TextureRect and (k as TextureRect).texture != null:
			var tex := k as TextureRect
			var ar: Rect2 = _aud._art_rect(tex)
			var cr2: Rect2 = tex.get_global_rect()
			print("     图<%s> 控件 %.0fx%.0f y %.1f~%.1f  画出来 %.0fx%.0f y %.1f~%.1f x %.1f~%.1f  %s" % [
				str(tex.name), cr2.size.x, cr2.size.y, cr2.position.y, cr2.end.y,
				ar.size.x, ar.size.y, ar.position.y, ar.end.y, ar.position.x, ar.end.x,
				_over(ar, inner)])
			need = maxf(need, _over_val(ar, inner))
		for ch in k.get_children():
			st.append(ch)
	print("     ⇒ 这张卡最大越界 = %.1f px" % need)


func _over_val(a: Rect2, inner: Rect2) -> float:
	return maxf(maxf(inner.position.y - a.position.y, a.end.y - inner.end.y),
		maxf(inner.position.x - a.position.x, a.end.x - inner.end.x))


func _over(a: Rect2, inner: Rect2) -> String:
	var t: float = inner.position.y - a.position.y
	var b: float = a.end.y - inner.end.y
	var l: float = inner.position.x - a.position.x
	var rr: float = a.end.x - inner.end.x
	var mx: float = maxf(maxf(t, b), maxf(l, rr))
	return "越出[上%+.1f 下%+.1f 左%+.1f 右%+.1f] max=%+.1f%s" % [t, b, l, rr, mx,
		"  ★红" if mx > 2.0 else ""]
