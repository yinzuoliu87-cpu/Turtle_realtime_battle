extends Node
## verify_inventory_layout.gd — 背包页重排的守卫 (2026-08-15)
##
## ══════════════════════════════════════════════════════════════════
##  为什么每一条都在这里
## ══════════════════════════════════════════════════════════════════
## 这一轮改的是"玩家一眼看到的东西", 而这类改动最容易悄悄退回去 ——
## 谁顺手加一行标题、把某个数字改回 tier+1、把配色写死成"3 件 = 银",
## 界面看着还是那样, 只有玩家发现不对。所以判据一律落在
## **控件的真实矩形 / 真实文本 / 函数返回值** 上, 不断言我自己插的标记。
##
## ⚠ 已经踩过的两个坑, 别再走回去:
##   ① `RichTextLabel.fit_content = true` ⇒ `get_content_height() <= size.y` 恒成立,
##      "放不下就提示"永远不触发(假检查)。
##   ② `get_line_count()` / `get_visible_line_count()` 要等控件排完版才有值 ——
##      实测同一份代码在截图进程里读到 3、在另一个进程里读到 **0**;
##      刚建出来那一帧调它还会按【尚未设好的宽度】排, 给出一个看着挺像样的错数。
##      ⇒ 行数一律走 `Font.get_multiline_string_size()`(同步, 与进程无关)。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_inventory_layout.tscn --quit-after 1500

const InvScene := preload("res://scripts/scenes/InventoryScene.gd")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")
const INV_SRC := "res://scripts/scenes/InventoryScene.gd"
const SYN_SRC := "res://scripts/scenes/inventory/synergy_panel.gd"

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name)   # ★detail 只在 FAIL 时打 —— 否则 PASS 行读起来像失败
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _walk(n: Node, out: Array) -> void:
	if n is Control:
		out.append(n)
	for c in n.get_children():
		_walk(c, out)


func _all(sc: Node) -> Array:
	var out: Array = []
	_walk(sc, out)
	return out


## 该场景里所有可见文本(Label / RichTextLabel / Button)拼起来
func _texts(sc: Node) -> Array:
	var out: Array = []
	for c in _all(sc):
		if c is Label:
			out.append(str((c as Label).text))
		elif c is RichTextLabel:
			out.append(str((c as RichTextLabel).get_parsed_text()))
		elif c is Button:
			out.append(str((c as Button).text))
	return out


## 文案最长 / 最短的装备 id (分母: 拿中位数长度的件去测"放不下"永远绿)
func _extreme_ids() -> Array:
	var lo := ""
	var hi := ""
	var lo_n := 1 << 30
	var hi_n := -1
	for e in DataRegistry.phase2_equipment:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		if int(d.get("shopAvailable", 1)) == 0:
			continue                       # 羁绊赠送件不进背包交易路径
		var n: int = str(d.get("effectDesc1", "")).length()
		if n > hi_n:
			hi_n = n; hi = str(d.get("id", ""))
		if n < lo_n and n > 0:
			lo_n = n; lo = str(d.get("id", ""))
	return [lo, lo_n, hi, hi_n]


func _mk(sel: int) -> Node:
	var sc = InvScene.new()
	get_tree().root.add_child(sc)
	return sc


func _ready() -> void:
	await get_tree().process_frame
	print("=== 背包页排版 ===")
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.size = Vector2i(1280, 720)
	for _q in range(4):
		await get_tree().process_frame

	GameState.test_mode = true          # ★绝不许写进玩家真存档
	var ex: Array = _extreme_ids()
	var short_id: String = str(ex[0])
	var long_id: String = str(ex[2])
	_ok("★分母: 找到文案最长/最短的装备 —— %s(%d 字) / %s(%d 字)"
		% [long_id, int(ex[3]), short_id, int(ex[1])],
		int(ex[3]) > 200 and int(ex[1]) < 90,
		"最长 %d 最短 %d ⇒ 分母不成立, 这组用例测不出东西" % [int(ex[3]), int(ex[1])])

	# ══ A. 顶部那块牌子必须是删掉的 ══════════════════════════════
	GameState.persistent_bench = [{"id": long_id, "star": 1}]
	var sc = _mk(-1)
	for _i in range(12):
		await get_tree().process_frame
	var txts: Array = _texts(sc)
	var has_title := false
	for t in txts:
		if str(t).find("出战配置") >= 0:
			has_title = true
	_ok("① 顶部「背包 / 出战配置」标题行已删(玩家是自己点进来的)", not has_title,
		"还能在界面上找到这块牌子")

	# ══ B. 没选中任何东西时, 底下不许留一整条空白 ═════════════════
	#     背包区必须自己铺到屏底 —— 那块地原来是"留给偶尔出现的操作条"的。
	var vp: float = 720.0
	var bench_bottom := 0.0
	for c in _all(sc):
		if c is ScrollContainer:
			bench_bottom = maxf(bench_bottom, (c as Control).get_global_rect().end.y)
	_ok("② 没选中时背包铺到屏底(底部留白 ≤ 24px, 原来空着 90px)",
		bench_bottom > 0.0 and vp - bench_bottom <= 24.0,
		"背包底 %.0f, 离屏底还有 %.0f px" % [bench_bottom, vp - bench_bottom])

	# ══ C. 背包格子铺满宽度(右边不许留空列) ══════════════════════
	var cells_right := 0.0
	var scroll_right := 0.0
	for c in _all(sc):
		if c is ScrollContainer:
			scroll_right = maxf(scroll_right, (c as Control).get_global_rect().end.y * 0.0 + (c as Control).get_global_rect().end.x)
	for c in _all(sc):
		if c is Panel and (c as Control).size.x == 96.0 and (c as Control).size.y == 96.0:
			cells_right = maxf(cells_right, (c as Control).get_global_rect().end.x)
	_ok("③ 背包格子铺满宽度(右侧空列 ≤ 12px; 原来固定间距留了 64px)",
		scroll_right > 0.0 and cells_right > 0.0 and scroll_right - cells_right <= 12.0,
		"格子右沿 %.0f / 滚动区右沿 %.0f, 空了 %.0f px" % [cells_right, scroll_right, scroll_right - cells_right])

	# ══ D. 深海币用真图标, 不是拿字符凑 ══════════════════════════
	var coin_tex := false
	for c in _all(sc):
		if c is TextureRect and (c as TextureRect).texture != null:
			if str((c as TextureRect).texture.resource_path).find("ic-deepsea") >= 0:
				coin_tex = true
	_ok("④ 深海币用商店同一张图标(ic-deepsea.png), 不是 ◆/💠 凑的", coin_tex,
		"没找到深海币图标的 TextureRect")
	var char_coin := false
	for t in txts:
		if str(t).find("◆") >= 0 or str(t).find("💠 深海币") >= 0:
			char_coin = true
	_ok("④b 界面上没有留下拿字符当币的旧写法", not char_coin)

	# ══ E. 右上角三块排成一条横线(不是上下堆着) ══════════════════
	var coin_r := Rect2()
	var cap_r := Rect2()
	var help_r := Rect2()
	for c in _all(sc):
		var r: Rect2 = (c as Control).get_global_rect()
		if c is TextureRect and (c as TextureRect).texture != null \
			and str((c as TextureRect).texture.resource_path).find("ic-deepsea") >= 0:
			coin_r = r
		elif c is Label and str((c as Label).text).begins_with("⚙ 装备"):
			cap_r = r
		elif c is Button and str((c as Button).text) == "?":
			help_r = r
	var row_ok: bool = coin_r.size.y > 0.0 and cap_r.size.y > 0.0 and help_r.size.y > 0.0 \
		and absf(coin_r.get_center().y - cap_r.get_center().y) <= 12.0 \
		and absf(coin_r.get_center().y - help_r.get_center().y) <= 12.0
	_ok("⑤ 深海币 / 装备容量 /「?」排成同一条横线(y 中心差 ≤12px)", row_ok,
		"币 %s / 容量 %s / ? %s" % [str(coin_r), str(cap_r), str(help_r)])
	_ok("⑤b 字号够大: 装备容量这一行至少 30px 高(原来 26 号框 18 号字)",
		cap_r.size.y >= 30.0, "只有 %.0f px" % cap_r.size.y)

	sc.queue_free()
	await get_tree().process_frame

	# ══ F. 底栏: 最长文案 → 两行摘要 + 明确说还有几行 + 【详情】按钮 ══
	sc = _mk(-1)
	for _i in range(10):
		await get_tree().process_frame
	sc.set("_sel_bench", 0)
	sc.call("_rebuild")
	for _i in range(8):
		await get_tree().process_frame
	var body: RichTextLabel = sc.get("_op_body")
	var more: Label = sc.get("_op_more")
	_ok("⑥ ★分母: 底栏真的画出了效果正文", body != null and is_instance_valid(body))
	if body != null and is_instance_valid(body):
		var br: Rect2 = body.get_global_rect()
		var bar: Control = body.get_parent() as Control
		var barr: Rect2 = bar.get_global_rect() if bar != null else Rect2()
		_ok("⑦ 正文框完整落在底栏内(不许冲出去)", br.end.y <= barr.end.y + 1.0,
			"正文底 %.0f > 底栏底 %.0f" % [br.end.y, barr.end.y])
		_ok("⑧ 底栏完整落在 720 设计框内", barr.end.y <= vp + 1.0,
			"底栏底 %.0f > %.0f" % [barr.end.y, vp])
		## ★★正文框高必须是【整行】的整数倍 —— 拍一个 40 的后果实拍见过:
		##   第三行被从中间切掉半条, 比不显示还难看。
		var lh: float = float(sc.call("_op_line_h", body))
		_ok("⑨ ★正文框高 = 整行的整数倍(%.0f / 行高 %.0f), 不会把某一行切成半条"
			% [br.size.y, lh], lh > 0.0 and absf(fmod(br.size.y, lh)) < 0.5,
			"框高 %.1f 行高 %.1f 余 %.2f" % [br.size.y, lh, fmod(br.size.y, lh)])
		## ★2026-08-19 改判据: 底栏现在放的是【一句话简述】(effectBrief), 不再是那段
		##   中位 129 字、最长 329 字的全文 —— 所以"放不下要明说"这条不再适用于底栏,
		##   **它现在就该一行不截地放得下**。全文由「详情」那一层承接(下面有断言)。
		##   判据的意思没变: **不许静默截断**。只是从"截断了要提示"变成"根本不截断"。
		var eb: String = SkillText.equip_brief(DataRegistry.phase2_equipment_by_id.get(long_id, {}))
		var total: int = int(sc.call("_op_total_lines", body, eb, br.size.x))
		var rows: int = int(InvScene.OP_BODY_ROWS)
		_ok("⑩ ★分母: 简述确实拿到了(空串 = 下面是空检查)", eb.strip_edges() != "",
			"%d 字" % eb.length())
		_ok("⑪ ★★最长那件的简述在底栏也放得下(%d 行 ≤ %d 行), 不需要截断" % [total, rows],
			total <= rows, "要 %d 行 > 能放 %d 行" % [total, rows])
		_ok("⑫ ★没截断就不该再挂「还有几行」的提示", more == null or not is_instance_valid(more),
			"仍挂着: %s" % ("无" if more == null else str(more.text)))
	var has_detail_btn := false
	for c in _all(sc):
		if c is Button and str((c as Button).text) == "详情":
			has_detail_btn = true
	_ok("⑬ ★底栏有【详情】按钮(全文的去处; 手机没有 hover, tooltip 等于不存在)", has_detail_btn)

	# ══ G. 短文案不许也挂"还有 N 行" ═════════════════════════════
	GameState.persistent_bench = [{"id": short_id, "star": 1}]
	sc.set("_sel_bench", 0)
	sc.call("_rebuild")
	for _i in range(8):
		await get_tree().process_frame
	var more2 = sc.get("_op_more")
	_ok("⑭ ★短文案【不】提示被裁(防止'永远显示提示'这种假实现)",
		more2 == null or not is_instance_valid(more2),
		"短文案(%s, %d 字)也提示被裁了" % [short_id, int(ex[1])])

	# ══ H. 详情框: 属性 + 全文, 且真的放得下 ═════════════════════
	GameState.persistent_bench = [{"id": long_id, "star": 1}]
	sc.set("_sel_bench", 0)
	sc.call("_rebuild")
	for _i in range(6):
		await get_tree().process_frame
	sc.call("_show_equip_detail", {"id": long_id, "star": 1})
	for _i in range(8):
		await get_tree().process_frame
	var det: RichTextLabel = null
	for c in _all(sc):
		if c is RichTextLabel and (c as RichTextLabel).name == "EquipDetailBody":
			det = c
	_ok("⑮ ★分母: 详情框建出来了", det != null)
	if det != null:
		var dr: Rect2 = det.get_global_rect()
		var dbox: Control = det.get_parent() as Control
		var dboxr: Rect2 = dbox.get_global_rect() if dbox != null else Rect2()
		_ok("⑯ 详情框不出 720 设计框", dboxr.position.y >= -1.0 and dboxr.end.y <= vp + 1.0,
			str(dboxr))
		_ok("⑰ 详情正文完整落在框内", dr.end.y <= dboxr.end.y + 1.0, "%s vs %s" % [str(dr), str(dboxr)])
		## ★"放得下"要量真实排版高度, 不是看它有没有滚动条
		var need: float = float(sc.call("_measured_text_h", det.get_parsed_text(), dr.size.x,
			int(InvScene.DETAIL_BODY_FS)))
		_ok("⑱ ★★最长那件的全文在详情框里【真的放得下】(要 %.0f px, 框给了 %.0f px)"
			% [need, dr.size.y], need <= dr.size.y + 1.0,
			"还差 %.0f px ⇒ 又是一次静默截断" % (need - dr.size.y))
		_ok("⑲ 详情正文仍可滚(万一以后文案再变长, 不静默吃字)", det.scroll_active)
		var dtxt: String = det.get_parsed_text()
		_ok("⑳ ★详情里有【属性加成】(原来只在 tooltip 里, 手机永远看不到)",
			dtxt.find("带来的属性") >= 0 and dtxt.find("效果") >= 0)

	sc.queue_free()
	await get_tree().process_frame

	# ══ I. 糖果罐档位: 不许 off-by-one ══════════════════════════
	##   `candy_jar_tier()` 返回的已经是 1~6(verify_candy_jar 逐区间焊死),
	##   界面上再 +1 会写出【第 7 档】这种不存在的档, 而且同一行右边给的奖励
	##   走的是 `candy_jar_tier_preview(tier)` = 真实档 ⇒ 数字和奖励自相矛盾。
	GameState.season_leaders = ["candy", "basic", "stone"]
	GameState.candy_jar_broken = false
	GameState.persistent_bench = []
	var jar_bad: Array = []
	for pair in [[0, 1], [6, 2], [11, 2], [12, 3], [18, 4], [24, 5], [30, 6]]:
		GameState.candy_jar_count = int(pair[0])
		var want: int = int(pair[1])
		var sc2 = _mk(-1)
		for _i in range(8):
			await get_tree().process_frame
		sc2.set("_sel_jar", true)
		sc2.call("_rebuild")
		for _i in range(6):
			await get_tree().process_frame
		var joined := ""
		for t in _texts(sc2):
			joined += str(t) + "\n"
		if joined.find("糖果罐 %d档" % want) < 0:
			jar_bad.append("count=%d 卡面没写「%d档」" % [int(pair[0]), want])
		if joined.find("第 %d 档" % want) < 0:
			jar_bad.append("count=%d 底栏没写「第 %d 档」" % [int(pair[0]), want])
		## 同一行里档位数字与奖励必须同档 —— 奖励取 preview(真实档)
		var prev: String = str(GameState.candy_jar_tier_preview(want))
		if prev != "" and joined.find(prev) < 0:
			jar_bad.append("count=%d 档位数字与奖励对不上(奖励应为「%s」)" % [int(pair[0]), prev])
		sc2.queue_free()
		await get_tree().process_frame
	_ok("㉑ ★★糖果罐档位显示 = candy_jar_tier() 本身(7 组区间逐个比, 无 off-by-one)",
		jar_bad.is_empty(), str(jar_bad.slice(0, 4)))
	GameState.candy_jar_count = 0

	# ══ J. 羁绊面板 ════════════════════════════════════════════
	var syn_host = _mk(-1)
	for _i in range(6):
		await get_tree().process_frame
	var syn = InvSynergy.new(syn_host)   # ★要真 host: _tier_color 走 host.Phase2Types
	## J-1 配色是【算】出来的: 三档类型从银开始 / 四档类型从铜开始 / 末档一律钻石
	var col_bad: Array = []
	var n3 := 0
	var n4 := 0
	for t in Phase2Types.TYPES:
		var typ := str(t)
		var tiers: Array = (Phase2Types.TYPES[typ] as Dictionary).get("tiers", [])
		if tiers.size() <= 1:
			continue                          # 香火只有 1 档, 首档=末档, 不参与首档判定
		var first: String = "#" + syn._tier_color(typ, 1).to_html(false)
		var last: String = "#" + syn._tier_color(typ, tiers.size()).to_html(false)
		if tiers.size() == 3:
			n3 += 1
			if first != InvSynergy.TIER_COLORS[1]:
				col_bad.append("%s(3档)首档应为银 %s, 实为 %s" % [typ, InvSynergy.TIER_COLORS[1], first])
		elif tiers.size() == 4:
			n4 += 1
			if first != InvSynergy.TIER_COLORS[0]:
				col_bad.append("%s(4档)首档应为铜 %s, 实为 %s" % [typ, InvSynergy.TIER_COLORS[0], first])
		if last != InvSynergy.TIER_COLORS[3]:
			col_bad.append("%s 末档应为钻石 %s, 实为 %s" % [typ, InvSynergy.TIER_COLORS[3], last])
	_ok("㉒ ★分母: 两种档制都在场(3 档 %d 个 / 4 档 %d 个)" % [n3, n4], n3 >= 5 and n4 >= 3)
	_ok("㉓ ★★档位配色按【档数】算出来(3 档从银起 / 4 档从铜起 / 末档一律钻石)",
		col_bad.is_empty(), str(col_bad.slice(0, 4)))
	## J-2 到顶了说"已满", 没到顶说【升级要几件】—— 数字取自 TYPES.tiers。
	## ★2026-08-15 用户当场否了"档"字:「整个不要档一档二而是以颜色」⇒ 文案从「下一档 N 件」
	##   改成「N 件升级」, 强弱只靠铜/银/金/钻石四色表示。判据跟着改, 并且【禁止"档"字回来】。
	var nx_bad: Array = []
	for t in Phase2Types.TYPES:
		var typ2 := str(t)
		var tiers2: Array = (Phase2Types.TYPES[typ2] as Dictionary).get("tiers", [])
		if tiers2.is_empty():
			continue
		var top: int = int(tiers2[tiers2.size() - 1])
		if str(syn._next_tier_text(typ2, top)) != "已满":
			nx_bad.append("%s 满档没写「已满」" % typ2)
		if str(syn._next_tier_text(typ2, 0)) != ("%d 件升级" % int(tiers2[0])):
			nx_bad.append("%s 0 件时没写「%d 件升级」(实得「%s」)" % [typ2, int(tiers2[0]), str(syn._next_tier_text(typ2, 0))])
		if str(syn._next_tier_text(typ2, 0)).find("档") >= 0:
			nx_bad.append("%s 的进度文案里还有「档」字" % typ2)
	_ok("㉔ ★进度文案只说件数(N 件升级 / 已满)且不含「档」字, 数字取自 TYPES.tiers",
		nx_bad.is_empty(), str(nx_bad.slice(0, 4)))
	## J-3 花名不许出现
	var fancy: Array = []
	for t in Phase2Types.TYPES:
		var typ3 := str(t)
		if str(syn._syn_name(typ3)).find("·") >= 0:
			fancy.append(typ3)
	_ok("㉕ ★羁绊名只用名本身, 不用「弓箭·神射手」这种花名", fancy.is_empty(), str(fancy))
	syn_host.queue_free()
	await get_tree().process_frame

	# ══ K. 面板上不许再出现「档1/档2/档位」 ═══════════════════════
	GameState.persistent_bench = [{"id": long_id, "star": 1}]
	GameState.persistent_equipped = {"basic": [
		{"id": "p2eq_001", "star": 1}, {"id": "p2eq_004", "star": 1}, {"id": "p2eq_005", "star": 1}]}
	var sc3 = _mk(-1)
	for _i in range(10):
		await get_tree().process_frame
	var bad_words: Array = []
	var syn_rows := 0
	var short_rows: Array = []
	for c in _all(sc3):
		if c is Label or c is RichTextLabel or c is Button:
			var s := ""
			if c is Label: s = str((c as Label).text)
			elif c is RichTextLabel: s = str((c as RichTextLabel).get_parsed_text())
			else: s = str((c as Button).text)
			for w in ["档位", "档1", "档2", "档3", "档4", "阈值"]:
				if s.find(str(w)) >= 0:
					bad_words.append("%s ← 「%s」" % [s.substr(0, 24), str(w)])
	for c in _all(sc3):
		## 羁绊行 = 挂了那句 tooltip 的 Panel(产品自己写的识别位, 不是我为测试加的)
		if c is Panel and str((c as Control).tooltip_text).find("点开看这个羁绊") >= 0:
			syn_rows += 1
			if (c as Control).size.y < 44.0:
				short_rows.append((c as Control).size.y)
	_ok("㉖ ★★界面文本里没有「档位 / 档1 / 阈值」这类字(强弱只用颜色表示)",
		bad_words.is_empty(), str(bad_words.slice(0, 4)))
	_ok("㉗ ★分母: 羁绊列真的画出了行(%d 行)" % syn_rows, syn_rows >= 1)
	_ok("㉘ ★羁绊按钮不许又矮又扁(每行 ≥44px 触摸目标)", short_rows.is_empty(),
		"有 %d 行矮于 44: %s" % [short_rows.size(), str(short_rows)])
	## 未激活但队里有件数的也要列出来 —— 否则"我装了 1 件法器"这件事界面上完全看不见
	var joined3 := ""
	for t in _texts(sc3):
		joined3 += str(t) + "\n"
	_ok("㉙ ★没激活但已有件数的羁绊也列出来(灰行), 玩家才知道离开启还有多远",
		joined3.find("件升级") >= 0, "一行「N 件升级」都没有")

	sc3.queue_free()
	await get_tree().process_frame

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 背包页排版" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
