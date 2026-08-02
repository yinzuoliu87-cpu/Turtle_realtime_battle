extends Node
## verify_codex_browse.gd — 图鉴【每一条都点开一遍】(用户 2026-08-01 报「精英小将的描述都挤在一块」)
##
## ★这个门禁本身就是那次事故的产物。根因是 detail_views.gd 里写了 host.ceilf(...) ——
##   ceilf 是全局内建函数, 不是节点方法, 调用直接 SCRIPT ERROR, 于是那行的 return 永远执行不到,
##   每段正文都拿到同一个 y → 全叠在一起。
##   ★它【只在渲染精英小将详情时】才触发, 而当时没有任何门禁会去点开那几条 →
##     bug 从 2026-07-26 图鉴拆分那天一直活到用户报上来。
##
## ★判据不靠断言, 靠 run-tests.sh 的致命报错正则:
##   FATAL 里已经有 'SCRIPT ERROR|Nonexistent|Invalid call' —— 只要真把每条都点开,
##   任何一条渲染路径报错都会让本测试判红。所以这里的关键是【覆盖率】而不是断言数:
##   下面那条"点开数 == 条目数"的分母断言, 就是防止哪天列表变了却只点到前几条。
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_codex_browse.tscn

const SCN := preload("res://scenes/Codex.tscn")
const TABS := ["pets", "equips", "synergies", "status", "rules"]

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


# 详情内容层的实际高度(最低那个子节点的底边)。
func _content_h(inst) -> float:
	var b := 0.0
	for c in inst.detail.get_children():
		if c is Control:
			b = maxf(b, (c as Control).position.y + (c as Control).size.y)
	return b


var _tall_h := 0.0
var _tall_tab := ""
var _tall_idx := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 图鉴逐条浏览(每条详情都渲染一遍) ===")
	var inst = SCN.instantiate()
	add_child(inst)
	for _i in range(60):
		await get_tree().process_frame

	var total := 0
	for tab in TABS:
		inst._switch_tab(tab)
		for _i in range(8):
			await get_tree().process_frame
		var cnt: int = inst._items.size()
		var opened := 0
		for idx in range(cnt):
			inst._select(idx)
			await get_tree().process_frame
			# 记录内容最高的那一条 —— 下面"可滚动"要用它当样本。
			# ★等一帧再量: RichTextLabel(fit_content) 的高度是布局之后才定的, 建完当帧读到 0。
			var h: float = _content_h(inst)
			if h > _tall_h:
				_tall_h = h; _tall_tab = tab; _tall_idx = idx
			opened += 1
		total += opened
		_ok("%s 页每一条都点开了 (%d/%d)" % [tab, opened, cnt], opened == cnt and cnt > 0,
			"条目 %d" % cnt)

	# ★分母: 全表条目数。少于这个说明列表没建全, 上面的"每条都点开"就是空检查。
	_ok("★分母: 五个页签合计点开 %d 条(≥100)" % total, total >= 100, "total=%d" % total)

	# ★精英小将必须真的被渲染到 —— 它在 pets 页【末尾】, 只点前几条永远碰不到,
	#   而 ceilf 那个 bug 恰恰只在它的详情里触发。
	inst._switch_tab("pets")
	for _i in range(8):
		await get_tree().process_frame
	var last: int = inst._items.size() - 1
	inst._select(last)
	for _i in range(4):
		await get_tree().process_frame
	var kids: int = inst.detail.get_child_count()
	_ok("★pets 末条(精英小将)详情真渲染出了内容", kids >= 5, "详情子节点 %d 个" % kids)

	# ── ★详情可滚动 (2026-08-03) ─────────────────────────────────────────
	# 2026-08-01 为了不让长条目画到屏幕外, 给详情框加了 clip_contents —— 副作用是
	#   【后半截直接看不见】(当时记为"已知限制: 极长条目会被裁掉尾部")。
	# 现在框内套了 ScrollContainer。这四条守的是: 框仍不溢出屏幕(旧目标不能丢) +
	#   内容真能滚到底(新目标) + ★真有条目超出框高(否则"能滚"是个空检查)。
	var sc: ScrollContainer = inst._detail_scroll
	var frame: Control = inst.detail_frame
	_ok("④ 详情框内套了 ScrollContainer 且纵向可滚",
		sc != null and sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO)
	var vp := inst.get_viewport().get_visible_rect().size
	var fr := frame.get_global_rect()
	_ok("④ 详情框仍然不溢出屏幕(2026-08-01 那条不能丢)",
		frame.clip_contents and fr.end.y <= vp.y + 0.5 and fr.end.x <= vp.x + 0.5,
		"框底 %.1f / 视口高 %.1f" % [fr.end.y, vp.y])
	# ★上面那条在无头下偏松(无头视口是方形 1280×1280, 比设计高 720 宽裕得多)。
	#   真正要守的是【框自己不被内容撑高】—— 内容 764 高时框必须还是 550。
	_ok("④ ★框高不随内容变(内容 %.0f 高时框仍是设计的 550)" % _tall_h,
		frame.size.y <= 550.5, "框高 %.1f" % frame.size.y)

	# ★分母: 全表里最高的那一条【必须真的超出框高】, 否则下面那条恒真。
	_ok("④ ★分母: 真有条目高过详情框(%s 第%d条 内容 %.0f > 框 %.0f)"
			% [_tall_tab, _tall_idx, _tall_h, frame.size.y],
		_tall_h > frame.size.y, "最高 %.0f / 框高 %.0f" % [_tall_h, frame.size.y])

	# 打开那一条, 滚到底, 看最后一行是不是真进了框。
	inst._switch_tab(_tall_tab)
	for _i in range(8):
		await get_tree().process_frame
	inst._select(_tall_idx)
	for _i in range(6):
		await get_tree().process_frame
	var vb := sc.get_v_scroll_bar()
	# ★两处反向验证踩出来的写法, 别改回去:
	#   ① 别喂 push_input(滚轮): 无头下 GUI 输入路由不到控件, 一格也不动 → 基线自己就红。
	#   ② 可视窗口要用【框】的高度, 不能用 sc.size.y ——
	#      把 vertical_scroll_mode 改成 DISABLED(=退回纯裁尾)时, ScrollContainer 会被
	#      子节点的最小高度撑到 778, 于是 "scroll+sc.size.y" 算出 778 ≥ 内容底 → 假绿灯,
	#      而玩家实际只看得见框里那 550。用 frame.size.y 才是玩家真正看得见的窗口。
	sc.scroll_vertical = int(vb.max_value)      # 滚到底
	await get_tree().process_frame
	var content_h := _content_h(inst)
	var bottom_visible: float = float(sc.scroll_vertical) + frame.size.y
	_ok("④ ★滚到底能看见内容最后一行(裁尾已解决)",
		bottom_visible >= content_h - 1.0,
		"滚到底可见到 %.0f / 内容底 %.0f (滚动条 max=%.0f)" % [bottom_visible, content_h, vb.max_value])

	# ── ⑤ ★装备行框色 = 费用色 ────────────────────────────────────────
	# 方案书 docs/plans/20260727-图鉴装备框色+调试场手机选龟.md 承诺过
	#   「headless 断言(框色取值正确 …)」, 但那条门禁【从来没建】(清单一直空着)。
	# 装备数据【没有 rarity 字段】, 框色一律来自费用(host.COST_COLOR) ——
	#   这正是当时测试人觉得"框色像有问题"的原因(同费用组必然同色)。这里焊死取值:
	#   谁哪天再把它接回一个不存在的品质字段, 会当场红。
	inst._switch_tab("equips")
	for _i in range(8):
		await get_tree().process_frame
	var rows: Array = []
	for w in inst.list_vbox.get_children():
		if w.get_child_count() > 0 and w.get_child(0) is Panel:
			rows.append(w.get_child(0))     # 行 = MarginContainer 里裹的 Panel; 组标题裹的是 Label
	_ok("⑤ 分母: 装备行数 == 条目数(%d)" % inst._items.size(),
		rows.size() == inst._items.size() and rows.size() >= 59,
		"行 %d / 条目 %d" % [rows.size(), inst._items.size()])
	var bad: Array = []
	for i in range(mini(rows.size(), inst._items.size())):
		var eq = inst._items[i]
		var want: Color
		if str(eq.get("category", "")) == "consumable":
			want = Color("#06d6a0")         # 消耗品单独一组, 固定绿
		else:
			want = Color(inst.COST_COLOR.get(int(eq.get("cost", 0)), "#4cc9f0"))
		want.a = 0.7                        # _add_simple_row 里描边统一压到 0.7
		var sb: StyleBoxFlat = rows[i].get_theme_stylebox("panel") as StyleBoxFlat
		var got: Color = sb.border_color
		if not got.is_equal_approx(want):
			bad.append("%s 期望 %s 实得 %s" % [str(eq.get("name", "?")), want.to_html(), got.to_html()])
	_ok("⑤ ★逐行框色 == 费用色(%d 行全对)" % rows.size(), bad.is_empty(),
		"不符 %d 行: %s" % [bad.size(), str(bad.slice(0, 3))])
	# 五档色必须两两不同 —— 全一样的话上面那条照样绿, 但玩家一档也分不出。
	var seen: Array = []
	for c in [1, 2, 3, 4, 5]:
		seen.append(str(inst.COST_COLOR.get(c, "")))
	var uniq: Array = []
	for c in seen:
		if not uniq.has(c):
			uniq.append(c)
	_ok("⑤ ★1~5 费五档色两两不同", uniq.size() == 5, str(seen))

	inst.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 图鉴逐条浏览" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
