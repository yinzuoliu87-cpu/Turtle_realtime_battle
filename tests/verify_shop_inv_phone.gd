extends Node
## verify_shop_inv_phone.gd — 商店 / 背包【手机优先】版式门禁(2026-10-21)
##
## 由来: 用户 10-20「如果你看 ios 上的商店页面，你会发现什么」—— iPhone 6.1" 实拍:
##   宝箱只露半截、货架伸出屏幕、字 1~2 毫米、商人占半屏、返回键贴刘海、底栏贴底部横条;
##   背包 33 格只用几格、羁绊两种写法、「统领 ×2 · 小将 ×1」「后排」无解释。
##   方案书 docs/plans/20261018-商店背包合一.md「手机优先重排」一节。
##
## ★走真入口: 真的实例化 Shop.tscn / Inventory.tscn, 根视口真的设成三种比例, 安全区按真机数喂
##   (无头进程拿不到真机安全区 ⇒ SafeArea.override_insets, 产品里同一个函数在读):
##     19.5:9  1560×720  内缩 (111, 0, 111, 38)  = iPhone 6.1" 横屏 62pt / 21pt × (720 / 402)
##     16:9    1280×720  内缩 0
##     4:3     1280×960  内缩 (0, 0, 0, 25)      = iPad 底部横条 20pt × (960 / 768)
##   每种比例 × 每个状态(商店: 空闲 / 选中货架 / 选中宝箱; 背包: 空闲 / 选中装备 / 选中单位 / 阵容说明 / 站位)量:
##     ① 主体不出屏      可点的 + 有字的, 矩形 ⊆ 视口
##     ② 不进不安全区    同上, 矩形 ⊆ 视口 − 安全区内缩(刘海 / 圆角 / 底部横条)
##     ③ 字号 ≥ 20       Label / RichTextLabel / 有字的 Button(20 设计像素 ≈ iPhone 11pt)
##     ④ 可点区 ≥ 81     短边 ≥ 81(= 44pt); 挂了 TouchPad 子节点的按 TouchPad 取大(与 verify_ui_consistency 同口径)
##     ⑤ 两两不重叠      可点的 + 有字的(祖孙不算); 弹层(说明小卡 / 全屏遮罩)盖住的视为被遮, 只量弹层里的
##   另加: ⑥ 货架商品都在货柜里 ⑦ 背包格数 = 件数(不画空格) ⑧ 羁绊三处同一句 ⑨ 统领 / 小将 / 前排 / 后排有图例
##   每条都配分母(量了几个), 0 个 = 红。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_shop_inv_phone.tscn

const SHOP := preload("res://scenes/Shop.tscn")
const INV := preload("res://scenes/Inventory.tscn")
const SEED := preload("res://tests/_setup_appstore.gd")
const SHOP_GD := preload("res://scripts/scenes/ShopScene.gd")
const INV_GD := preload("res://scripts/scenes/InventoryScene.gd")
const P2T := preload("res://scripts/gamedata/phase2_types.gd")

const MIN_FONT := 20
const MIN_TAP := 81.0
const RATIOS := [
	{"name": "19.5:9", "vp": Vector2(1560, 720), "ins": Vector4(111, 0, 111, 38)},
	{"name": "16:9", "vp": Vector2(1280, 720), "ins": Vector4(0, 0, 0, 0)},
	{"name": "4:3", "vp": Vector2(1280, 960), "ins": Vector4(0, 0, 0, 25)},
]
const MIN_ASSERTS := 120

var _fail := 0
var _n := 0
var gs


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 GameState"); get_tree().quit(1); return
	print("=== 商店 / 背包 手机版式(三种比例 × 各状态) ===")
	for r in RATIOS:
		get_tree().root.size = Vector2i(r["vp"])
		SafeArea.override_insets = r["ins"]
		await _frames(2)
		var vp := Vector2(get_viewport().get_visible_rect().size)
		_ok("[%s] 分母: 根视口真的是这个比例" % r["name"], vp.is_equal_approx(r["vp"]), str(vp))
		## ★2026-10-21 用户「商店要这么搞」: 商店里没有背包那一排(不再有 bench 态)。
		for st in ["idle", "shelf"]:
			await _run_shop(r, st)
		for st in ["idle", "bench", "unit", "help", "formation"]:
			await _run_inv(r, st)
	SafeArea.override_insets = Vector4(-1, -1, -1, -1)
	await _check_synergy_text()
	print("")
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少该有 %d)" % [_n, MIN_ASSERTS])
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 商店 / 背包手机版式" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ══════════════════════════════════════════════════════════════
#  场景
# ══════════════════════════════════════════════════════════════

func _enter(ps: PackedScene, vp: Vector2) -> Control:
	SEED.run()
	gs.meta_shop_locked = false
	var sc: Control = ps.instantiate()
	add_child(sc)
	sc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	sc.position = Vector2.ZERO
	sc.size = vp
	await _frames(3)
	if sc.has_method("_rebuild"):
		sc.call("_rebuild")        # 按设好的尺寸重排一次(进场那一刻的尺寸可能还是默认)
	await _frames(4)
	return sc


func _leave(sc: Node) -> void:
	remove_child(sc)
	sc.free()
	await _frames(1)


func _run_shop(r: Dictionary, st: String) -> void:
	var vp: Vector2 = r["vp"]
	var sc := await _enter(SHOP, vp)
	var tag := "[%s 商店·%s]" % [r["name"], st]
	if st == "shelf":
		sc.set("_sel", 7)
		sc.call("_rebuild")
		await _frames(6)
		_ok(tag + " 分母: 说明小卡弹出来了", _find(sc, "InspectCard") != null and _find(sc, "BuyBtn") != null)
	## 主体下限 14: 宽货柜版商店只剩 货架 10 + 刷新 / 锁定 / 买经验 + 等级行(实测 17)。
	_audit(sc, r, tag, 14)
	if st == "idle":
		## ⑥ 货架商品都在货柜里, 货柜在视口里、底沿不过安全区
		var cab := _find(sc, "ShopCabinet") as Control
		_ok(tag + " 分母: 货柜在", cab != null)
		if cab != null:
			var cr := cab.get_global_rect()
			var bad: Array = []
			var k := 0
			for i in range(10):
				var it := _find(sc, "ShelfItem%d" % i) as Control
				if it == null:
					continue
				k += 1
				if not cr.grow(1.0).encloses(it.get_global_rect()):
					bad.append("ShelfItem%d %s" % [i, str(it.get_global_rect())])
			_ok(tag + " ⑥ 10 件商品都在货柜里", k == 10 and bad.is_empty(), "量了 %d 件 %s" % [k, str(bad)])
			var safe := _safe_rect(r)
			_ok(tag + " ⑥ 货柜不出屏、底沿不进底部横条", Rect2(Vector2.ZERO, vp).grow(1.0).encloses(cr)
				and cr.end.y <= safe.end.y + 1.0, "货柜 %s 安全区底 %.0f" % [str(cr), safe.end.y])
	await _leave(sc)


func _run_inv(r: Dictionary, st: String) -> void:
	var vp: Vector2 = r["vp"]
	var sc := await _enter(INV, vp)
	var tag := "[%s 背包·%s]" % [r["name"], st]
	match st:
		"bench":
			sc.call("_on_bench_click", 0)
			await _frames(4)
			_ok(tag + " 分母: 底部操作条建出来了(详情钮在)", _find(sc, str(INV_GD.DETAIL_BTN_NAME)) != null)
		"unit":
			sc.call("_dl_click", "top", 0)
			await _frames(4)
			_ok(tag + " 分母: 选中了一只单位", not (sc.get("_dl_sel") as Dictionary).is_empty())
		"help":
			sc.call("_show_lineup_help")
			await _frames(3)
		"formation":
			sc.get("_formation").open()
			await _frames(3)
			_ok(tag + " 分母: 站位面板开出来了", _find(sc, "FormationDone") != null)
	_audit(sc, r, tag, 3 if st == "help" else (8 if st == "formation" else 30))
	if st == "idle":
		## ⑦ 背包格数 = 件数(不再「至少铺满可视区」, 也不画补位的空格)
		var cells: Array = []
		var empties := 0
		var n_items: int = (gs.persistent_bench as Array).size() + (1 if gs.has_candy_jar() else 0)
		var grid := _bench_grid(sc)
		_ok(tag + " ⑦ 分母: 找到背包网格", grid != null)
		if grid != null:
			var per_row := 0
			var y0 := INF
			for ch in grid.get_children():
				if ch is Control and absf((ch as Control).size.x - float(INV_GD.SLOT)) < 1.0:
					cells.append(ch)
					y0 = minf(y0, (ch as Control).position.y)
			for ch in cells:
				if absf((ch as Control).position.y - y0) < 1.0:
					per_row += 1
			var expect: int = n_items
			_ok(tag + " ⑦ 背包格数 = 件数, 不画空格(%d 件 · 每行 %d)" % [n_items, per_row],
				per_row > 0 and cells.size() == expect, "实有 %d 格, 应为 %d" % [cells.size(), expect])
		## ⑨ 统领 / 小将 / 前排 / 后排讲得清
		##   ★2026-10-22 背包重做: 常驻图例撤了(竖卡版式没地方), 规则进「?」阵容说明的第一条;
		##   卡上本身也有: 统领卡写龟名、小将卡上就是【前排 / 后排】切换签。⇒ 量「?」里真画出来的字。
		sc.call("_show_lineup_help")
		await _frames(3)
		var leg := _text_of(sc)
		var miss: Array = []
		for w in ["统领：", "小将：", "前排", "后排"]:
			if leg.find(w) < 0:
				miss.append(w)
		_ok(tag + " ⑨「?」阵容说明讲清统领 / 小将 / 前排 / 后排", miss.is_empty(), "缺 %s" % str(miss))
		_ok(tag + " ⑨ 旧的「统领 ×N · 小将 ×N」计数不在了", _text_of(sc).find("统领 ×") < 0 and _text_of(sc).find("小将 ×") < 0)
	await _leave(sc)


## 背包网格 = 背包那个 ScrollContainer 里的内容节点(装 96 格的那一层)
func _bench_grid(sc: Node) -> Control:
	for c in _all(sc):
		if c is ScrollContainer and (c as Control).is_visible_in_tree():
			var inner = (c as ScrollContainer).get_child(0) if (c as ScrollContainer).get_child_count() > 0 else null
			if inner is Control:
				for ch in (inner as Control).get_children():
					if ch is Control and absf((ch as Control).size.x - float(INV_GD.SLOT)) < 1.0:
						return inner
	return null


# ══════════════════════════════════════════════════════════════
#  五条判据
# ══════════════════════════════════════════════════════════════

func _safe_rect(r: Dictionary) -> Rect2:
	var vp: Vector2 = r["vp"]
	var ins: Vector4 = r["ins"]
	return Rect2(Vector2(ins.x, ins.y), vp - Vector2(ins.x + ins.z, ins.y + ins.w))


func _audit(sc: Control, r: Dictionary, tag: String, min_leaves: int) -> void:
	var vp: Vector2 = r["vp"]
	var screen := Rect2(Vector2.ZERO, vp)
	var safe := _safe_rect(r)
	var area := vp.x * vp.y
	## 弹层: 说明小卡(只遮它自己那块) / 全屏遮罩(遮掉全部)
	var overlay: Control = null
	for c in _all(sc):
		if not (c is Control) or not (c as Control).is_visible_in_tree():
			continue
		if str(c.name).ends_with("InspectCard"):   # 背包里改名 ItemInspectCard / UnitInspectCard
			overlay = c
		elif c is ColorRect and (c as Control).mouse_filter == Control.MOUSE_FILTER_STOP and (c as Control).get_child_count() > 0 \
				and (c as Control).size.x * (c as Control).size.y >= area * 0.8:
			overlay = c   # 站位面板的暗幕从顶栏下沿起(≈ 0.88 屏)
	var ov_rect: Rect2 = overlay.get_global_rect() if overlay != null else Rect2()
	var ov_full: bool = overlay != null and ov_rect.size.x * ov_rect.size.y >= area * 0.8
	var leaves: Array = []          # [控件, 有效矩形(剪过滚动区), 是否可点]
	var fonts_bad: Array = []
	var taps_bad: Array = []
	var n_font := 0
	var n_tap := 0
	for c in _all(sc):
		if not (c is Control):
			continue
		var ct := c as Control
		if not ct.is_visible_in_tree() or str(ct.name) == "TouchPad":
			continue
		var interactive: bool = _interactive(ct)
		var textual: bool = _text(ct) != ""
		if not interactive and not textual:
			continue
		var gr := ct.get_global_rect()
		if gr.size.x * gr.size.y >= area * 0.4:
			continue                     # 满铺层(点空白收起 / 遮罩本身)不算主体
		## 剪滚动区: 滚出视窗的那部分本来就看不见
		var sca := _scroll_ancestor(ct)
		if sca != null:
			gr = gr.intersection(sca.get_global_rect())
			if gr.size.x < 1.0 or gr.size.y < 1.0:
				continue
		## 被弹层盖住的不量(小卡: 与卡相交的; 全屏遮罩: 全部)
		if overlay != null and not overlay.is_ancestor_of(ct) and ct != overlay:
			if ov_full or gr.intersects(ov_rect):
				continue
		## 字号
		if textual:
			n_font += 1
			var fs := _font_px(ct)
			if fs < MIN_FONT:
				fonts_bad.append("%s「%s」%dpx" % [ct.name, _text(ct).left(10), fs])
		## 可点区
		if interactive:
			n_tap += 1
			var ew := ct.size.x
			var eh := ct.size.y
			var pad = ct.get_node_or_null("TouchPad")
			if pad is Control:
				ew = maxf(ew, (pad as Control).size.x)
				eh = maxf(eh, (pad as Control).size.y)
			if minf(ew, eh) < MIN_TAP - 0.5:
				taps_bad.append("%s %.0f×%.0f" % [ct.name, ew, eh])
		## 只把「不在可点控件里面」的那一层收进去量重叠(按钮里的字算按钮本身)
		if not _has_interactive_ancestor(ct, sc, area):
			leaves.append([ct, gr, interactive])
	_ok(tag + " 分母: 量了 %d 个主体(可点 %d · 有字 %d)" % [leaves.size(), n_tap, n_font], leaves.size() >= min_leaves and n_tap >= 1 and n_font >= 3)
	## ① 不出屏 ② 不进不安全区
	var off_bad: Array = []
	var unsafe_bad: Array = []
	for lf in leaves:
		var gr: Rect2 = lf[1]
		if not screen.grow(1.0).encloses(gr):
			off_bad.append("%s %s" % [(lf[0] as Node).name, str(gr)])
		elif not safe.grow(1.0).encloses(gr):
			unsafe_bad.append("%s %s" % [(lf[0] as Node).name, str(gr)])
	_ok(tag + " ① 主体不出屏", off_bad.is_empty(), str(off_bad.slice(0, 6)))
	_ok(tag + " ② 不进不安全区(刘海 / 圆角 / 底部横条)", unsafe_bad.is_empty(), str(unsafe_bad.slice(0, 6)))
	_ok(tag + " ③ 字号 ≥ %d(量了 %d 处)" % [MIN_FONT, n_font], fonts_bad.is_empty(), str(fonts_bad.slice(0, 8)))
	_ok(tag + " ④ 可点区短边 ≥ %.0f(量了 %d 个)" % [MIN_TAP, n_tap], taps_bad.is_empty(), str(taps_bad.slice(0, 8)))
	## ⑤ 两两不重叠
	var ov_bad: Array = []
	for i in range(leaves.size()):
		for j in range(i + 1, leaves.size()):
			var a: Control = leaves[i][0]
			var b: Control = leaves[j][0]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			var x: Rect2 = (leaves[i][1] as Rect2).intersection(leaves[j][1])
			if x.size.x >= 2.0 and x.size.y >= 2.0:
				ov_bad.append("%s「%s」<%s> × %s「%s」<%s> (%.0f×%.0f)" % [a.name, _text(a).left(6), a.get_parent().name, b.name, _text(b).left(6), b.get_parent().name, x.size.x, x.size.y])
	_ok(tag + " ⑤ 可点的 / 有字的两两不重叠(量了 %d 个)" % leaves.size(), ov_bad.is_empty(), str(ov_bad.slice(0, 6)))


## 可点: 按钮; 或挂了点击回调且吃鼠标的控件。滚动区本身不算(它是拖动区)。
func _interactive(c: Control) -> bool:
	if c is ScrollContainer:
		return false
	if c is BaseButton:
		return true
	return c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.gui_input.get_connections().size() > 0


## ★满铺的可点层(点空白收起 / 全屏遮罩)不算「按钮」—— 它下面的字是弹框里的字, 不是按钮上的字。
func _has_interactive_ancestor(c: Control, root: Node, area: float) -> bool:
	var p := c.get_parent()
	while p != null and p != root:
		if p is Control and _interactive(p as Control) 				and (p as Control).size.x * (p as Control).size.y < area * 0.4:
			return true
		p = p.get_parent()
	return false


func _scroll_ancestor(c: Control) -> ScrollContainer:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


## 控件上玩家读得到的字(去掉 bbcode); 纯图标字(← ? ▼)也算字, 一样要够大。
func _text(c: Control) -> String:
	var t := ""
	if c is Label:
		t = str((c as Label).text)
	elif c is RichTextLabel:
		t = str((c as RichTextLabel).get_parsed_text())
	elif c is Button:
		t = str((c as Button).text)
	return t.strip_edges()


func _font_px(c: Control) -> int:
	var px := 0
	if c is RichTextLabel:
		px = c.get_theme_font_size("normal_font_size")
		## 正文里用 [font_size=N] 改小的也算
		var raw := str((c as RichTextLabel).text)
		var at := raw.find("[font_size=")
		while at >= 0:
			var e := raw.find("]", at)
			var v := raw.substr(at + 11, e - at - 11)
			if v.is_valid_int():
				px = mini(px, int(v))
			at = raw.find("[font_size=", e)
	else:
		px = c.get_theme_font_size("font_size")
	return px


func _all(n: Node) -> Array:
	var out: Array = []
	var st: Array = [n]
	while not st.is_empty():
		var x: Node = st.pop_back()
		out.append(x)
		for ch in x.get_children():
			st.append(ch)
	return out


func _find(n: Node, nm: String) -> Node:
	for x in _all(n):
		if str(x.name) == nm and (not (x is CanvasItem) or (x as CanvasItem).is_visible_in_tree()):
			return x
	return null


func _text_of(n: Node) -> String:
	var s := ""
	for x in _all(n):
		if x is Control and (x as Control).is_visible_in_tree():
			s += _text(x as Control) + "|"
	return s


# ══════════════════════════════════════════════════════════════
#  ⑧ 羁绊三处同一句
# ══════════════════════════════════════════════════════════════

## 商店左栏 / 背包羁绊列 / 出战页 chip: 同一个类型、同一件数时, 读到的是同一句。
## ★不在这里抄一份写法 —— 拿产品三处真画出来的字比, 外加它们都等于 Phase2Types.progress_text。
func _check_synergy_text() -> void:
	SEED.run()
	var rows: Array = gs.synergy_rows()
	_ok("⑧ 分母: 种子里有羁绊", rows.size() >= 2, "%d 条" % rows.size())
	var want: Array = []
	for r in rows:
		want.append(P2T.progress_text(str(r["t"]), int(r["n"]), int(r["tier"]), int(r["need"]), int(r.get("tiers_n", 0))))
	get_tree().root.size = Vector2i(1280, 720)
	var shop: Control = SHOP.instantiate(); add_child(shop)
	var inv: Control = INV.instantiate(); add_child(inv)
	for _i in range(6):
		await get_tree().process_frame
	var shop_txt := _rtl_texts(shop)
	var inv_txt := _rtl_texts(inv)
	var miss: Array = []
	var in_shop: Array = []
	for w in want:
		if shop_txt.find(w) >= 0:
			in_shop.append(w)
		if inv_txt.find(w) < 0:
			miss.append("背包缺「%s」" % w)
	_ok("⑧ ★背包羁绊同一句(%d 条)" % want.size(), want.size() >= 2 and miss.is_empty(), str(miss))
	## ★2026-10-21 用户「商店里为什么会显示背包的装备和羁绊？」: 羁绊只在背包页, 商店里一条都不画。
	_ok("⑧ ★商店里没有羁绊", in_shop.is_empty(), str(in_shop))
	_ok("⑧ 背包不再写「N 件升级」", inv_txt.find("件升级") < 0)
	var ts_src := FileAccess.get_file_as_string("res://scripts/scenes/TeamSelectScene.gd")
	_ok("⑧ 出战页 chip 走同一个写法函数", ts_src.find("Phase2Types.progress_text(") >= 0)
	remove_child(shop); shop.free()
	remove_child(inv); inv.free()


func _rtl_texts(n: Node) -> String:
	var s := ""
	for x in _all(n):
		if x is RichTextLabel and (x as Control).is_visible_in_tree():
			var line := str((x as RichTextLabel).get_parsed_text()).strip_edges()
			## 背包窄列: 同一句拆两行, 星档在同一块里的 TierStars(字不变, 拼回来比)
			var stars: Node = (x as Node).get_parent().get_node_or_null("TierStars")
			if stars is Label:
				line += " " + str((stars as Label).text)
			s += line + "|"
	return s
