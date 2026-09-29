extends Node
## _probe_settle_budget.gd — 结算屏【两处高度预算】穷举行数量一遍 (2026-09-29)
##
## 只回答一件事: 每一档行数下,
##   外层卡片滚动区的预算(_show_banner 的 scroll_max) 与
##   内层战报的预算(_stats_fit_body 的 avail)
## 各是多少、卡片溢出几像素、屏幕上有没有任何"还有更多"的提示。
##
## ★不推理, 全量真实节点: get_global_rect() / get_combined_minimum_size() /
##   VScrollBar.max_value-page / 祖先 clip_contents 矩形的交集。
##
## 跑法:
##   PB_W=1560 PB_H=720 PB_LO=7 PB_HI=16 APPDATA=<私有> NO_SAVE=1 TURTLE_SUPABASE=" " \
##   <godot> --headless --audio-driver Dummy --path . res://tests/_probe_settle_budget.tscn --quit-after 6000

const SCENE := "res://scenes/RealtimeBattle3D.tscn"

var _sc = null
var _base_children := 0


func _ready() -> void:
	await get_tree().process_frame
	var w: int = int(OS.get_environment("PB_W")) if OS.get_environment("PB_W") != "" else 1560
	var h: int = int(OS.get_environment("PB_H")) if OS.get_environment("PB_H") != "" else 720
	var lo: int = int(OS.get_environment("PB_LO")) if OS.get_environment("PB_LO") != "" else 7
	var hi: int = int(OS.get_environment("PB_HI")) if OS.get_environment("PB_HI") != "" else 16
	get_tree().root.content_scale_size = Vector2i(w, h)
	get_tree().root.size = Vector2i(w, h)
	for _q in range(4):
		await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	_sc = load(SCENE).instantiate()
	get_tree().root.add_child(_sc)
	for _i in range(30):
		await get_tree().process_frame
	## 停掉 sim —— 不然清 _units 会触发它自己的结算/死亡逻辑, 量到的就不是我摆的那一档。
	_sc.set_process(false)
	_sc.set_physics_process(false)
	await get_tree().process_frame
	_base_children = _sc._ui_layer.get_child_count()
	var vp: Vector2 = _sc.get_viewport().get_visible_rect().size
	print("")
	print("════ 视口 %s · _ui_layer 基线子节点 %d ════" % [str(vp), _base_children])
	print("  R=每侧单位数 | 表内总行 | 外层预算 | 卡片最小高 | 外层溢出 | 内层预算 | 内层内容 | 内层溢出 | 屏上可见滚动条 | 初始看得全/总行 | 提示")

	for r in range(lo, hi + 1):
		await _one(r, vp)

	_sc.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)


func _one(per: int, vp: Vector2) -> void:
	# ── 清掉上一轮的结算幕 ──
	var kids: Array = _sc._ui_layer.get_children()
	for i in range(kids.size() - 1, _base_children - 1, -1):
		(kids[i] as Node).queue_free()
	await get_tree().process_frame
	# ── 摆这一档的名单 ──
	_sc._units.clear()
	var made := 0
	for side in ["left", "right"]:
		for k in range(per):
			var u = _sc._spawn._make_unit("green", side, _sc.ARENA.position + _sc.ARENA.size * 0.5
				+ Vector2(-260.0 + 34.0 * float(k), -140.0 + 120.0 * (0.0 if side == "left" else 1.0)))
			if u is Dictionary:
				u["_st_dealt"] = 1000 + 137 * k
				u["_st_taken"] = 500 + 91 * k
				u["_st_heal"] = 40 * k
				u["_st_kills"] = k % 3
				if not _sc._arr_has_unit(_sc._units, u):
					_sc._units.append(u)
				made += 1
	for _i in range(4):
		await get_tree().process_frame
	_sc._settled = false
	_sc._hud._show_banner(true)
	for _i in range(14):
		await get_tree().process_frame

	var shell: Control = _find_shell(_sc._ui_layer)
	if shell == null:
		print("  R=%2d  结算卡没建出来 —— 本档不算数" % per)
		return
	var scrolls: Array = []
	_collect(shell, "ScrollContainer", scrolls)
	if scrolls.size() < 2:
		print("  R=%2d  只找到 %d 个 ScrollContainer —— 本档不算数" % [per, scrolls.size()])
		return
	var outer: ScrollContainer = scrolls[0]
	var inner: ScrollContainer = scrolls[1]
	var card: Control = null
	for c in outer.get_children():
		if c is VBoxContainer:
			card = c
			break
	var card_min: float = card.get_combined_minimum_size().y if card != null else -1.0
	var outer_view: float = outer.size.y
	var outer_over: float = maxf(0.0, card_min - outer_view)
	var inner_min: float = inner.custom_minimum_size.y
	var inner_content: float = 0.0
	var bd: Control = null
	for c in inner.get_children():
		if c is Control:
			bd = c
			break
	if bd != null:
		for c in bd.get_children():
			if c is Control and (c as Control).visible:
				inner_content = maxf(inner_content, (c as Control).size.y)
	var inner_over: float = maxf(0.0, inner_content - inner.size.y)

	# ── 屏上真的看得见的竖滚动条(在视口内、宽度>0) ──
	var bars: Array = []
	_collect_bars(shell, bars, vp)

	# ── 初始状态(玩家刚进屏, 一下都没滑)有几行完整可见 ──
	var rows: Array = []
	var grids: Array = []
	_collect(shell, "GridContainer", grids)
	for g in grids:
		if not (g as Control).is_visible_in_tree():
			continue
		for ch in (g as Node).get_children():
			if ch is HBoxContainer:
				rows.append(ch)
	var vis := 0
	for rr in rows:
		if _clip_rect(rr, vp).encloses((rr as Control).get_global_rect()):
			vis += 1

	# ── 屏幕上有没有任何"还有更多"的提示 ──
	var hint: String = _find_hint(shell, vp)
	## ★诊断: 强制再刷一次, 看数字会不会变 —— 变了就是"刷得太早/没再刷", 不是算错
	_sc._hud._settle_refresh_more()
	await get_tree().process_frame
	await get_tree().process_frame
	var hint2: String = _find_hint(shell, vp)
	var inner_bar: VScrollBar = inner.get_v_scroll_bar()
	print("      [诊断] 内层 rect=%s  clip=%s  bar max=%.0f page=%.0f val=%.0f  刷一次后=%s"
		% [str(inner.get_global_rect()), str(_clip_rect(inner, vp)),
		   inner_bar.max_value, inner_bar.page, inner_bar.value, hint2])

	print("  R=%2d | %3d | %6.0f | %7.0f | %+5.0f | %6.0f | %6.0f | %+5.0f | %d根%s | %d/%d | %s"
		% [per, rows.size(), _outer_budget_probe(vp), card_min, outer_over,
		   inner_min, inner_content, inner_over,
		   bars.size(), (" 宽%s" % str(bars)) if not bars.is_empty() else "",
		   vis, rows.size(), hint])


## 复算一遍 _show_banner 里那个 scroll_max —— 只为把它印出来对账, 判据不靠它。
func _outer_budget_probe(vp: Vector2) -> float:
	var sm: Vector4 = SafeArea.margins(vp, 6.0)
	return maxf(180.0, vp.y - 62.0 - 70.0 - sm.y - sm.w - 40.0)


## 任何一个"还有更多"的可见提示: 文字里带 ▼/更多/滑动/拖动/还有 的 Label。
func _find_hint(root: Node, vp: Vector2) -> String:
	var st: Array = [root]
	while not st.is_empty():
		var n = st.pop_back()
		if n is Label and (n as Control).is_visible_in_tree():
			var t: String = str((n as Label).text)
			for kw in ["▼", "▲", "更多", "滑动", "拖动", "还有", "SCROLL"]:
				if t.find(kw) >= 0:
					var rr: Rect2 = (n as Control).get_global_rect()
					var ok: bool = _clip_rect(n, vp).encloses(rr)
					return "「%s」%s" % [t, "可见" if ok else "★被裁掉"]
		for ch in n.get_children():
			st.append(ch)
	return "无"


func _clip_rect(c: Control, vp: Vector2) -> Rect2:
	var r := Rect2(Vector2.ZERO, vp)
	var p: Node = c
	while p != null:
		if p is Control and (p as Control).clip_contents:
			r = r.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	return r


func _collect(n: Node, cls: String, out: Array) -> void:
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children(true):
		_collect(c, cls, out)


func _collect_bars(n: Node, out: Array, vp: Vector2) -> void:
	if n is VScrollBar and (n as Control).is_visible_in_tree():
		var r: Rect2 = (n as Control).get_global_rect()
		if r.size.x > 0.5 and r.size.y > 0.5 and Rect2(Vector2.ZERO, vp).intersects(r):
			out.append("%.0fpx" % r.size.x)
	for c in n.get_children(true):
		_collect_bars(c, out, vp)


func _find_shell(n: Node) -> Control:
	for c in n.get_children():
		if c is CenterContainer:
			for d in (c as Node).get_children():
				if d is PanelContainer:
					return d
	return null
