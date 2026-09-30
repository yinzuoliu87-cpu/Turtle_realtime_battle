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
## ★`equip_stats.gd` 故意没有 class_name(防 F5 未声明崩) ⇒ 必须 preload
const EquipStats := preload("res://scripts/gamedata/equip_stats.gd")
const INV_SRC := "res://scripts/scenes/InventoryScene.gd"
const SYN_SRC := "res://scripts/scenes/inventory/synergy_panel.gd"

var _n := 0
var _fail := 0

## 全绿时的断言条数。加/删断言时同步改这个数(它是"有没有被掐断"的分母)。
const MIN_ASSERTS := 64


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
		## ★★2026-09-28 从 `begins_with("⚙ 装备")` 改成**按节点名找**。
		##   原来那一版是**拿字面量当尺子**: 「⚙」2026-09-28 被换成了像素图标
		##   (`ui/icon-equip.png`, 理由见 `InventoryScene.CAP_ROW_NAME` 处注释) ⇒
		##   同一刻这条断言就找不到它了, 而 cap_r 全零会让 ⑤/⑤b 报成
		##   「三块没排成一条线 / 字号不够」—— 假 bug, 真原因是尺子没了。
		##   名字由产品自己出常量, 测试不拼字面量。
		elif c is Label and str(c.name) == str(InvScene.CAP_ROW_NAME):
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

	# ══ F. 底栏: 最长文案 → 两行摘要 + 明确说还有几行 + 【细看】按钮 ══
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
		##   **它现在就该一行不截地放得下**。全文由「细看」那一层承接(下面有断言)。
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
	## ══ ⑬ 全文的去处 —— 判据落在【按下去真的开出全文】, 不落在键上写着哪两个字 ══
	## ★★2026-09-28 重写。原判据是 `Button.text == "详情"`, 而这一刻那颗键的文案
	##   正从「详情」统一成「细看」(战斗信息框 `battle_hud.gd` 一直写「点开细看」)
	##   ⇒ 那条断言会**假红**, 而它本来要守的是"手机玩家有地方看到全文",
	##   跟那两个字毫无关系(memory [[fb-tests-pin-screen-words]])。
	##   ⇒ ① 按【产品自己出的节点名常量】找它 ② 真按一下, 看全文那一层有没有开出来。
	##   ★★为什么必须收掉弹框: 不收的话下面 H 段会同时存在两个 `EquipDetailBody`,
	##     ⑯~⑳ 量到的就不一定是 H 段自己开的那个 —— 那是一条会随机绿的假判据。
	var det_btn: Button = null
	for c in _all(sc):
		if c is Button and str(c.name) == str(InvScene.DETAIL_BTN_NAME):
			det_btn = c
	_ok("⑬ ★分母: 底栏那颗看全文的键在场(按节点名找, 不按按钮上的字)", det_btn != null)
	var det_opened := false
	var det_words := ""
	if det_btn != null:
		det_btn.pressed.emit()
		for _i in range(8):
			await get_tree().process_frame
		var pop: RichTextLabel = null
		for c in _all(sc):
			if c is RichTextLabel and str(c.name) == "EquipDetailBody":
				pop = c
		if pop != null:
			det_words = pop.get_parsed_text().strip_edges()
			det_opened = det_words.length() > 40
			var dim0: Node = pop.get_parent().get_parent()   # rt → box → dim
			if dim0 != null:
				dim0.queue_free()
			await get_tree().process_frame
	_ok("⑬b ★★按下它【真的开出全文那一层】(手机没有 hover, 全文只有这一个去处)",
		det_opened, "开出来 %d 字: %s" % [det_words.length(), det_words.substr(0, 30)])

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
		## ★★2026-09-28 从 `find("带来的属性")` 改成**量内容本身**。
		##   原判据钉的是段标题那几个字 —— 而这一刻标题正从「带来的属性」统一成「属性」
		##   (商店 `ShopScene._build_stat_rows` 与图鉴 `detail_views.gd:857` 一直只写两个字)
		##   ⇒ 那条会假红; 而它要守的东西是「手机上看得到属性数值 + 效果全文」,
		##   跟标题写什么字无关。⇒ 判据改成 `EquipStats.stat_lines()` 真实返回的
		##   【每一项名与值】都在屏上, 加效果全文的头一句也在屏上。
		var want_rows: Array = EquipStats.stat_lines(long_id, 1)
		var miss: Array = []
		for kv in want_rows:
			if dtxt.find(str(kv[0])) < 0 or dtxt.find(str(kv[1])) < 0:
				miss.append("%s %s" % [str(kv[0]), str(kv[1])])
		_ok("⑳ ★分母: 这件真有属性行可查(%d 项; 0 项 = 下面是空检查)" % want_rows.size(),
			want_rows.size() > 0)
		_ok("⑳ ★详情里逐项写着属性的【名与值】(原来只在 tooltip 里, 手机永远看不到)",
			miss.is_empty(), "缺 %d 项: %s" % [miss.size(), str(miss.slice(0, 4))])
		## 效果全文: 拿 `SkillText.equip_full()` 自己吐的**第一行前 14 字**当针 ——
		## 不找段标题、也不靠字数估。(`highlight_star` 只加 bbcode 标签, 而这里比的是
		##  `get_parsed_text()` = 标签剥掉之后的字 ⇒ 两边是同一串。)
		var full: String = SkillText.equip_full(DataRegistry.phase2_equipment_by_id.get(long_id, {}))
		var fl: String = str(full.strip_edges().split("\n", false)[0]) if full.strip_edges() != "" else ""
		var needle: String = fl.substr(0, 14)
		_ok("⑳b ★分母: 取到了效果全文的针(%d 字)" % needle.length(), needle.length() >= 8)
		_ok("⑳c ★详情里有【效果全文】(按全文自己的头一句找, 不按段标题找)",
			needle != "" and dtxt.find(needle) >= 0, "找不到「%s」" % needle)

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

	# ══ L. TOAST_SURVIVES: 提示必须【活过 _rebuild】并且真的看得见 ═══
	#
	# ★★★2026-09-29 查实的 bug: `equip_ops.gd` 里七处 `host._toast(...)` 的下一行都是
	#   `host._rebuild()`, 而 `_rebuild()` 开头把所有非浮层子节点 queue_free
	#   ⇒ 提示【生下来那一帧就被销毁】。实测(tests/_probe_toast_killed.gd):
	#       同帧立刻查 1 个 → +1 帧起 0 个 … 一直 0
	#   七条提示玩家一条都没看见过 —— 「装到上限点了没反应」的真根因。提示其实全写好了。
	#
	# ★判据【不】数"调了几次 _toast" —— 那是数我自己插的标记, 插一行数一行必绿。
	#   量的是产品自己的账: **那个节点还在不在 / 看不看得见 / 是不是被背景压住了**。
	await _check_toast_survives()

	# ══ M. SELL_NONZERO: 「卖出 +0」—— 东西没了, 一分钱不退 ════════
	await _check_sell_nonzero()

	# ══ N. EQUIP_CAP_SAME_SOURCE: 「装备 N / M」那个 M 必须是真上限 ══
	await _check_equip_cap_same_source()

	# ══ O. EQUIP_SLOT_PT: 21.7pt 的装备格 + 那条"44pt 卸下路径"到底通不通 ══
	await _check_equip_slot_pt()

	print("")
	## ★★断言条数的【地板】。低于它 = 有协程在半路被掐断 / 静默 abort ⇒ 判红。
	##   2026-09-29 在另一个门禁上当场撞到: 读一个不存在的成员会让协程【就地返回】,
	##   后面十条断言一条不跑, 而进程 rc=0 还打 ALL PASS(fb-null-readback-makes-test-silently-abort)。
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少该有 %d) —— 有东西在半路被掐断了, 别当绿灯"
			% [_n, MIN_ASSERTS])
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 背包页排版" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 它头上那层 CanvasLayer(没有 = 它就在内容那一层, 会被随后建的背景压住)
func _canvas_layer_of(n: Node) -> CanvasLayer:
	var p: Node = n
	while p != null:
		if p is CanvasLayer:
			return p as CanvasLayer
		p = p.get_parent()
	return null


## 屏上文字里含 needle 的 Label(产品自己的账, 不是我插的标记)
func _toasts_on_screen(sc: Node, needle: String) -> Array:
	var hit: Array = []
	for c in _all(sc):
		if c is Label and str((c as Label).text).find(needle) >= 0:
			hit.append(c)
	return hit


func _check_toast_survives() -> void:
	const OPS_SRC := "res://scripts/scenes/inventory/equip_ops.gd"
	const NEEDLE := "已装满"
	## ★分母0: 这句话确实是产品的原文(有人改文案时, 红的是这条, 不是下面一堆谜语)
	var src := ""
	var fo := FileAccess.open(OPS_SRC, FileAccess.READ)
	if fo != null:
		src = fo.get_as_text(); fo.close()
	_ok("㉚ ★分母: %s 里真有「%s」这句提示" % [OPS_SRC.get_file(), NEEDLE],
		src.find(NEEDLE) >= 0 and src.find("host._toast(") >= 0)

	## 一只【装满 3 件】的统领 + 背包里还剩一件 ⇒ 再装 = 撞单只上限, 走 toast 那一支
	var ids: Array = DataRegistry.phase2_equipment_by_id.keys()
	var e0 := str(ids[0])
	GameState.season_leaders = ["basic", "stone", "bamboo"]
	GameState.persistent_equipped = {"basic": [
		{"id": e0, "star": 1}, {"id": e0, "star": 1}, {"id": e0, "star": 1}]}
	GameState.persistent_bench = [{"id": str(ids[1]), "star": 1}]
	var sc = _mk(-1)
	## ★真实场景里背包屏的根 Control 是【铺满视口】的(UIFrame._avail 头注也记着这一点),
	##   门禁里它默认 0x0 ⇒ 满铺背景 ColorRect 跟着缩成 0,
	##   下面那条「提示底下到底有没有背景压着」的分母就测不出东西(实测当场红)。
	sc.size = get_viewport().get_visible_rect().size
	for _i in range(10):
		await get_tree().process_frame

	var worn0: int = (GameState.persistent_equipped.get("basic", []) as Array).size()
	var bench0: int = GameState.persistent_bench.size()
	_ok("㉛ ★分母: 摆出了「装满了还要装」的局面(身上 %d 件 = 上限 %d, 背包还有 %d 件)"
		% [worn0, int(sc.P2.UNIT_EQUIP_CAP), bench0],
		worn0 == int(sc.P2.UNIT_EQUIP_CAP) and bench0 >= 1)
	_ok("㉜ ★分母: 触发前屏上本来没有这句提示",
		_toasts_on_screen(sc, NEEDLE).is_empty())

	sc._sel_bench = 0
	sc._inv_ops._equip_to("basic", 0)     # ← 点格子时走的就是这一行(InventoryScene.gd:608)
	## ★分母: 这次操作【真的】走到了会 toast 的那一支 —— 走到了就装不上(两边件数都没动)
	_ok("㉝ ★★分母: 那次操作真的撞上了上限分支(没装上 · 身上仍 %d / 背包仍 %d)" % [worn0, bench0],
		(GameState.persistent_equipped.get("basic", []) as Array).size() == worn0
		and GameState.persistent_bench.size() == bench0,
		"身上 %d / 背包 %d" % [(GameState.persistent_equipped.get("basic", []) as Array).size(),
			GameState.persistent_bench.size()])

	for _i in range(8):
		await get_tree().process_frame    # ★关键: queue_free 延到帧末 —— 要等过这几帧才算"活下来"

	var found: Array = _toasts_on_screen(sc, NEEDLE)
	_ok("㉞ ★★★TOAST_SURVIVES: 8 帧之后屏上仍然找得到那句提示(原来这里是 0 个)",
		found.size() == 1, "找到 %d 个" % found.size())
	if found.size() >= 1:
		var t: Label = found[0]
		var tr: Rect2 = t.get_global_rect()
		_ok("㉟ ★★TOAST_SURVIVES: 提示是可见的(整条链上没有谁被关掉 · alpha 没归零)",
			t.is_visible_in_tree() and t.modulate.a > 0.5,
			"visible_in_tree=%s alpha=%.2f" % [str(t.is_visible_in_tree()), t.modulate.a])
		_ok("㊱ ★TOAST_SURVIVES: 提示落在屏内(不是飘到视口外去了)",
			tr.position.x >= -1.0 and tr.position.y >= -1.0
			and tr.end.x <= get_viewport().get_visible_rect().size.x + 1.0,
			str(tr))
		## ★「活下来」还不够 —— `_rebuild()` 随后铺的满屏不透明背景比它【后】加,
		##   同一层的话提示就被压在底下(节点还在、visible 还是 true, 只是没人看得见)。
		var cl: CanvasLayer = _canvas_layer_of(t)
		var covered := false
		for c in _all(sc):
			if c is ColorRect and (c as ColorRect).color.a >= 0.99 \
					and (c as Control).get_global_rect().encloses(tr):
				covered = true
		_ok("㊲ ★分母: 提示那块地方底下真的有一层满铺不透明背景(所以「压不压住」这件事有意义)",
			covered)
		_ok("㊳ ★★TOAST_SURVIVES: 提示画在内容【之上】(自己一层 CanvasLayer · layer>0)",
			cl != null and cl.layer > 0,
			"没有 CanvasLayer" if cl == null else "layer=%d" % cl.layer)

		## 连点两下不许叠成一团糊(旧的收掉, 屏上永远只有一条)
		sc._sel_bench = 0
		sc._inv_ops._equip_to("basic", 0)
		for _i in range(4):
			await get_tree().process_frame
		_ok("㊴ ★再点一次只剩一条提示(旧的收掉, 不叠成一团糊)",
			_toasts_on_screen(sc, NEEDLE).size() == 1,
			"屏上 %d 条" % _toasts_on_screen(sc, NEEDLE).size())

	sc.queue_free()
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════════════
#  SELL_NONZERO —— 背包里那颗「卖出 +N」按钮, N 不许是 0
# ══════════════════════════════════════════════════════════════════════
## ★★这一节是**端到端**那一半(数据层那一半在 `verify_shop_layout` 里逐格穷举 96×3)。
##   台账 ⑶ 的原始实测: 选中木制长剑(1 费 ★1) → 按钮写「卖出 +0」→ 点下去
##   **装备从背包消失、深海币 4→4**。那不是「便宜」是白没。
##
## ★判据量的是**玩家看到的那颗按钮**和**账上真进的钱**, 不是卖价函数本身:
##   ① [分母] 真的摆出了当年那一格(1 费 ★1), 而且按钮建出来了
##   ② [分母·反证] 这一格在修复前的原式下确实算出 0(否则这条用例测的不是那个 bug)
##   ③ 按钮上的数 == `InvOps._sell_value()` 的返回值(屏上的价与真价同源)
##   ④ 按钮上的数 ≥ 1
##   ⑤ 真点下去, 深海币正好涨了那么多, 而且装备真的出账了(不是「钱没涨、东西没了」)
func _check_sell_nonzero() -> void:
	## 当年中招的那一格: 1 费、★1、能卖(羁绊赠送件走不到卖出路径)
	var one := ""
	for e in DataRegistry.phase2_equipment:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		if int(d.get("cost", 1)) == 1 and int(d.get("shopAvailable", 1)) != 0:
			one = str(d.get("id", ""))
			break
	var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(one, {})
	GameState.season_leaders = ["basic", "stone", "bamboo"]
	GameState.persistent_equipped = {}
	GameState.persistent_bench = [{"id": one, "star": 1}]
	GameState.meta_deepsea_coins = 4          # 台账里那一刻的币数
	var sc = _mk(-1)
	sc.size = get_viewport().get_visible_rect().size
	sc._sel_bench = 0                          # 选中它 ⇒ 底栏那排操作键才建
	sc._rebuild()
	for _i in range(8):
		await get_tree().process_frame
	var btn: Button = null
	for c in _all(sc):
		if c is Button and str((c as Button).text).begins_with("卖出 +"):
			btn = c as Button
	var shown := -1
	if btn != null:
		var tail := str(btn.text).substr(str(btn.text).find("+") + 1).strip_edges()
		if tail.is_valid_int():
			shown = int(tail)
	var it: Dictionary = {"id": one, "star": 1}
	var truth := int(sc._inv_ops._sell_value(it))
	## 修复前的原式 = 同一个 SELL_RATE, 只是没有地板价。
	## ★系数走事实源 `Phase2Config.SELL_RATE`, 不在测试里再抄一个 0.8。
	var raw := int(floor(float(int(edef.get("cost", 1)) * 1) * float(sc.P2.SELL_RATE)))
	_ok("㊵ ★分母: 摆出了当年中招的那一格 —— %s「%s」%d 费 ★1, 而且底栏那颗卖出键建出来了"
		% [one, str(edef.get("name", "?")), int(edef.get("cost", 1))],
		one != "" and int(edef.get("cost", 1)) == 1 and btn != null,
		"one=%s btn=%s" % [one, str(btn)])
	_ok("㊶ ★分母·反证: 这一格在修复前的原式 floor(费×星×0.8) 下确实算出 %d(=0 才说明测的是那个 bug)" % raw,
		raw == 0, "原式算出 %d ⇒ 这条用例测的不是那个 bug" % raw)
	_ok("㊷ ★★屏上写的「卖出 +%d」== InvOps._sell_value() 的 %d(屏上的价与真价同源)" % [shown, truth],
		shown == truth, "屏 %d vs 真 %d" % [shown, truth])
	_ok("㊸ ★★★SELL_NONZERO: 卖价不是 0 —— 要么给钱、要么别让卖, 不许「白没」(实测 +%d)" % shown,
		shown >= 1, "按钮写着「卖出 +%d」" % shown)
	if btn != null:
		var coin0 := int(GameState.meta_deepsea_coins)
		var bench0 := GameState.persistent_bench.size()
		btn.emit_signal("pressed")
		for _i in range(4):
			await get_tree().process_frame
		var d_coin := int(GameState.meta_deepsea_coins) - coin0
		var d_bench := bench0 - GameState.persistent_bench.size()
		_ok("㊹ ★★点下去: 深海币 %d→%d(+%d, 应 +%d) 且背包 %d→%d(真出账了)"
			% [coin0, int(GameState.meta_deepsea_coins), d_coin, shown,
				bench0, GameState.persistent_bench.size()],
			d_coin == shown and d_coin >= 1 and d_bench == 1,
			"币 +%d / 背包 -%d" % [d_coin, d_bench])
	sc.queue_free()
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════════════
#  EQUIP_CAP_SAME_SOURCE —— 背包屏那个「装备 N / M」的 M 必须是真上限
# ══════════════════════════════════════════════════════════════════════
## ★这一节是跨屏那件事的背包侧(商店侧在 `verify_shop_layout` 同名段)。
##   两边都拿 `GameState.team_equip_cap()` / `team_equipped_count()` 当尺子 ⇒
##   两屏的读数必然相等, 而且**等于真正拦人的那个数**
##   (原来商店自己数出恒等于 18, 背包写 12, 玩家照 18 去买、回来点空槽毫无反应)。
##
## ★★必须扫**多个等级**: 恒等于 18 的写法在 Lv10 上是对的 —— 单档测永远绿。
func _check_equip_cap_same_source() -> void:
	var caps: Dictionary = {}
	var bad: Array = []
	var found := 0
	GameState.season_leaders = ["basic", "stone", "bamboo"]
	GameState.persistent_equipped = {"basic": []}
	GameState.persistent_bench = []
	for L in [1, 3, 7, 10]:
		GameState.season_level = L
		var sc = _mk(-1)
		sc.size = get_viewport().get_visible_rect().size
		for _i in range(8):
			await get_tree().process_frame
		var pair := _cap_pair(sc)
		var want_cap := int(GameState.team_equip_cap())
		var want_used := int(GameState.team_equipped_count())
		caps[want_cap] = true
		if pair.is_empty():
			bad.append("Lv%d 读不到「装备 N / M」那一行" % L)
		else:
			found += 1
			print("     Lv%-2d 背包屏写「装备 %d / %d」   真上限 %d / 真已装 %d"
				% [L, pair[0], pair[1], want_cap, want_used])
			if pair[1] != want_cap:
				bad.append("Lv%d 屏上分母 %d ≠ team_equip_cap()=%d" % [L, pair[1], want_cap])
			if pair[0] != want_used:
				bad.append("Lv%d 屏上分子 %d ≠ team_equipped_count()=%d" % [L, pair[0], want_used])
		sc.queue_free()
		await get_tree().process_frame
	_ok("㊺ ★分母: 四档都读到了那一行(%d/4)" % found, found == 4)
	_ok("㊻ ★分母: 这四档的真上限有 %d 个不同值(全一样的话「恒等于 18」也能全绿)" % caps.size(),
		caps.size() >= 3, str(caps.keys()))
	_ok("㊼ ★★EQUIP_CAP_SAME_SOURCE: 背包屏的分母/分子 == team_equip_cap()/team_equipped_count(): %s"
		% ("四档全对上" if bad.is_empty() else str(bad)), bad.is_empty())
	## 羁绊赠品不占容量 ⇒ 装上去分子不许变(与商店侧同口径, 也与真正拦人的
	## `team_has_equip_room()` 同口径 —— 它走的就是跳过赠品的 `_cap_count`)
	GameState.season_level = 7
	GameState.persistent_equipped = {"basic": []}
	var sa = _mk(-1)
	sa.size = get_viewport().get_visible_rect().size
	for _i in range(8):
		await get_tree().process_frame
	var q0 := _cap_pair(sa)
	sa.queue_free()
	await get_tree().process_frame
	GameState.persistent_equipped = {"basic": [{"id": "p2eq_095", "star": 1}]}
	var sb = _mk(-1)
	sb.size = get_viewport().get_visible_rect().size
	for _i in range(8):
		await get_tree().process_frame
	var q1 := _cap_pair(sb)
	sb.queue_free()
	await get_tree().process_frame
	_ok("㊽ ★分母: 那件确实被 GameState 认成羁绊赠品, 而且真装到身上了(%d 件)"
		% (GameState.persistent_equipped.get("basic", []) as Array).size(),
		GameState.is_synergy_grant({"id": "p2eq_095", "star": 1})
		and (GameState.persistent_equipped.get("basic", []) as Array).size() == 1)
	_ok("㊾ ★★羁绊赠品不计入「已装」(装上前 %s / 装上后 %s) —— 两屏同口径" % [str(q0), str(q1)],
		q0.size() == 2 and q1.size() == 2 and q0[0] == q1[0] and q0[1] == q1[1])


## 背包屏「装备 N / M」那一行上的两个数。找不到 ⇒ 空数组(分母不成立)
## ★按节点名 `CAP_ROW_NAME` 找, 不按「装备」这两个字找(文案改了判据不许跟着废)。
func _cap_pair(sc: Node) -> Array:
	for c in _all(sc):
		if not (c is Label) or str(c.name) != str(InvScene.CAP_ROW_NAME):
			continue
		var t := str((c as Label).text)
		var parts: PackedStringArray = t.split("/")
		if parts.size() < 2:
			continue
		var a := str(parts[0]).replace("装备", "").strip_edges()
		var b := str(parts[1]).strip_edges()
		if a.is_valid_int() and b.is_valid_int():
			return [int(a), int(b)]
	return []


# ══════════════════════════════════════════════════════════════════════
#  EQUIP_SLOT_PT —— 龟身上那 18 个装备格不许是"最小的靶子干最要紧的活"
# ══════════════════════════════════════════════════════════════════════
## ★由来(2026-09-29 台账 ⑭): 「整屏最小的靶子恰好是主操作 —— 龟身上 18 个装备格
##   40×40px = **21.7pt**, 而同屏背包格是 **52pt**(差 2.4 倍); 相邻间隙只有 **2.2pt**。」
##   (换算: 视口高 720 ↔ iPhone 横屏 390pt ⇒ 1pt = 1.846px ⇒ iOS HIG 的 44pt = **81px**。)
##
## ★★真根因不是"格子小"(2026-09-30 探针实测, 三条数都在下面打出来):
##   格子做到 40 已经是**版式硬上限** —— 右列可用宽 = UBOX_W(244) − rx(110) − 右留白 6 = 128,
##   (128 − 2×gap 4) / 3 = **40.0 整**; 往外也没地方(单位区右沿 804 / 羁绊列左沿 828,
##   两条战场带 88..236 与 234..382 已互相压了 2px, 背包标题就在 386 ⇒ UBOX_H 一像素都涨不了)。
##   真问题是：**大的那条路根本没通**。`_build_unit_equip_bar()`(注释自称"44pt 达标路径")
##   原来读 `unit.get("equips")` —— 统领的装备住在 `GameState.persistent_equipped[pid]`,
##   所以对统领 `eqs` 恒空、就地 return ⇒ **选中统领卡时那条操作栏一个按钮都不建**。
##   实测: basic 带 3 件, 「卸下」按钮 **0 个 / 标题 0 条**; 同一刻小将 **2 个 190×81**。
##   ⇒ 统领要卸装备只剩那个 21.7pt 的格子, 而它**直接执行卸下**(偏一格就卸错一件, 且无提示)。
##
## ★★★所以判据分两层, 少一层都守不住:
##   ① 分母: 18 个格子真的在场、尺寸真的是 40×40(21.7pt), 且填充格数 == 身上装备件数
##   ② 点任何一个格子都是**非破坏性**的(身上/背包一件不动), 且它把这只单位【选中】
##   ③ 选中之后底部真的出现「卸下」键, 每颗短边 ≥ 81px(44pt)、全落在操作条里,
##      **数量 == 这只单位身上的件数**(少一颗就有一件只能靠小格子卸)
##   ④ ③ 对【统领】和【小将】分别验 —— 这正是原 bug 只坏一半的那一刀
const PX_PER_PT := 81.0 / 44.0     # 81px = 44pt (见 tests/_probe_touch.gd 的换算推导)
const TOUCH_MIN_PX := 81.0


## 这一只单位身上的装备件数 —— 拿产品自己的读法(`InventoryScene._unit_equips`) 反问,
## 测试不在这里手抄一份"统领看 persistent_equipped / 小将看 equips"的副本。
func _worn_n(sc: Node, unit: Dictionary) -> int:
	return (sc.call("_unit_equips", unit) as Array).size()


func _mini_cells(sc: Node) -> Array:
	var out: Array = []
	for c in _all(sc):
		var ctl: Control = c
		if ctl is Panel and absf(ctl.size.x - ctl.size.y) < 0.5 \
			and ctl.size.x >= 20.0 and ctl.size.x <= 60.0:
			out.append(ctl)
	return out


func _unload_buttons(sc: Node) -> Array:
	var out: Array = []
	for c in _all(sc):
		if c is Button and str((c as Button).text).begins_with("卸下"):
			out.append(c)
	return out


## 给一个 Control 派一次真的左键按下(走它自己的 `gui_input`) —— 不调内部函数,
## 量的是玩家真按下去会发生什么。
func _tap(c: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = c.size * 0.5
	c.gui_input.emit(ev)


## 全队(统领 + 小将)身上的装备总数 —— 破坏性检查的"账"
func _worn_total() -> int:
	var n := 0
	if GameState.persistent_equipped is Dictionary:
		for pid in GameState.persistent_equipped:
			n += (GameState.persistent_equipped[pid] as Array).size()
	var dl: Dictionary = GameState.get_dual_lineup()
	for lane in ["top", "bottom"]:
		for u in (dl.get(lane, []) as Array):
			if u is Dictionary and u.get("equips", null) is Array:
				n += (u["equips"] as Array).size()
	return n


func _check_equip_slot_pt() -> void:
	print("")
	GameState.season_leaders = ["basic", "stone", "bamboo"]
	GameState.persistent_equipped = {
		"basic": [{"id": "p2eq_001", "star": 1}, {"id": "p2eq_002", "star": 1}, {"id": "p2eq_003", "star": 1}],
		"stone": [{"id": "p2eq_004", "star": 1}],
	}
	GameState.dual_lineup = {}
	var dl0: Dictionary = GameState.get_dual_lineup()
	var minion_n := 0
	for lane in ["top", "bottom"]:
		for u in (dl0.get(lane, []) as Array):
			if u is Dictionary and str(u.get("kind", "")) == "minion":
				u["equips"] = [{"id": "p2eq_005", "star": 1}, {"id": "p2eq_006", "star": 1}]
				minion_n += 1
	GameState.dual_lineup = dl0
	GameState.persistent_bench = [{"id": "p2eq_007", "star": 1}]

	var sc = _mk(-1)
	for _i in range(14):
		await get_tree().process_frame

	# ── ① 分母: 18 个格子在场, 尺寸就是 40×40, 而同屏背包格是 96 ──
	var minis: Array = _mini_cells(sc)
	var sizes := {}
	for m in minis:
		sizes["%.0f" % (m as Control).size.x] = int(sizes.get("%.0f" % (m as Control).size.x, 0)) + 1
	var slot_px: float = float(InvScene.SLOT)
	var mini_px: float = 0.0
	for m in minis:
		mini_px = maxf(mini_px, (m as Control).size.x)
	var filled: Array = []
	for m in minis:
		if (m as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			filled.append(m)
	var worn0: int = _worn_total()
	print("  [EQUIP_SLOT_PT 分母] 迷你格 %d 个 尺寸分布 %s ⇒ %.0fpx = %.1fpt ; 背包格 %.0fpx = %.1fpt ; 可点的 %d 个 / 全队在身装备 %d 件"
		% [minis.size(), str(sizes), mini_px, mini_px / PX_PER_PT, slot_px, slot_px / PX_PER_PT,
		   filled.size(), worn0])
	_ok("EQUIP_SLOT_PT ① ★分母: 6 个单位 × %d 格 = %d 个迷你格全在场"
		% [int(InvScene.P2.UNIT_EQUIP_CAP), 6 * int(InvScene.P2.UNIT_EQUIP_CAP)],
		minis.size() == 6 * int(InvScene.P2.UNIT_EQUIP_CAP),
		"只扫到 %d 个(分布 %s)" % [minis.size(), str(sizes)])
	_ok("EQUIP_SLOT_PT ① ★分母: 它们确实小于触控下限(%.0fpx = %.1fpt < 81px = 44pt) —— 否则本节整节是空检查"
		% [mini_px, mini_px / PX_PER_PT], mini_px > 0.0 and mini_px < TOUCH_MIN_PX,
		"迷你格 %.0fpx 已经 ≥ 81px, 那这一节该重写" % mini_px)
	_ok("EQUIP_SLOT_PT ① ★分母: 身上有装备的格子数 == 全队在身件数(%d)" % worn0,
		filled.size() == worn0, "可点 %d 件 vs 在身 %d 件" % [filled.size(), worn0])

	# ── ② 点每一个格子: 一件都不许被卸掉, 而且必须【选中】了某只单位 ──
	var bench_before: int = GameState.persistent_bench.size()
	var destroyed: Array = []
	var selected := 0
	var tapped := 0
	## ★★只记**位置**不记节点引用: 每一轮都要 `_rebuild()`(把 `_dl_sel` 清回去),
	##   而 `_rebuild()` 会 `queue_free` 掉全部子节点 ⇒ 上一轮拿的 Control 下一轮就是
	##   freed object(实测 `SCRIPT ERROR: Trying to cast a freed object`, 协程当场中止、
	##   后面四条断言一条没跑)。位置是数据, 活得过重建。
	var spots: Array = []
	for m in filled:
		spots.append((m as Control).get_global_rect().position)
	for sp in spots:
		var w_before: int = _worn_total()
		var b_before: int = GameState.persistent_bench.size()
		sc.set("_dl_sel", {})
		sc.call("_rebuild")
		for _i in range(6):
			await get_tree().process_frame
		## _rebuild 换了节点, 按位置重新拿到"同一个格子"
		var again: Control = null
		for c in _mini_cells(sc):
			if (c as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE \
				and (c as Control).get_global_rect().position.distance_to(sp as Vector2) < 1.0:
				again = c
		if again == null:
			continue
		tapped += 1
		_tap(again)
		for _i in range(6):
			await get_tree().process_frame
		if _worn_total() != w_before or GameState.persistent_bench.size() != b_before:
			destroyed.append("格@%s: 在身 %d→%d 背包 %d→%d" % [
				str(sp), w_before, _worn_total(), b_before, GameState.persistent_bench.size()])
		if not (sc.get("_dl_sel") as Dictionary).is_empty():
			selected += 1
	print("  [EQUIP_SLOT_PT ②] 逐个点了 %d / %d 个格子: 破坏了 %d 次 / 选中成功 %d 次 ; 背包 %d→%d"
		% [tapped, spots.size(), destroyed.size(), selected, bench_before,
		   GameState.persistent_bench.size()])
	_ok("EQUIP_SLOT_PT ② ★分母: 每个有装备的格子都真按到了(%d / %d)" % [tapped, spots.size()],
		spots.size() > 0 and tapped == spots.size())
	_ok("EQUIP_SLOT_PT ② 21.7pt 的格子**没有一个**是破坏性的(逐个点 %d 次, 卸掉 0 件)" % tapped,
		destroyed.is_empty(), "; ".join(destroyed.slice(0, 3)))
	_ok("EQUIP_SLOT_PT ② 点格子把那只单位【选中】了(%d / %d 次)" % [selected, tapped],
		tapped > 0 and selected == tapped)

	# ── ③④ 统领 / 小将各自都有 81px(44pt) 的卸下路径, 且数量 == 在身件数 ──
	var dl: Dictionary = GameState.get_dual_lineup()
	var kinds_seen := {}
	var bad: Array = []
	for lane in ["top", "bottom"]:
		var arr: Array = dl.get(lane, [])
		for i in range(arr.size()):
			if not (arr[i] is Dictionary):
				continue
			var unit: Dictionary = arr[i]
			var want: int = _worn_n(sc, unit)
			if want <= 0:
				continue
			var kind := str(unit.get("kind", ""))
			sc.set("_dl_sel", {"lane": lane, "idx": i})
			sc.call("_rebuild")
			for _i in range(8):
				await get_tree().process_frame
			var btns: Array = _unload_buttons(sc)
			kinds_seen[kind] = int(kinds_seen.get(kind, 0)) + 1
			## ★★条子本身: 不许伸出 720 设计框, 也不许压在背包格子上。
			##   两件都是真踩过的 —— 81px 的键硬塞进 80 高的条 ⇒ 底沿 725(出屏 5px);
			##   而 `_bench_bottom()` 当年没跟上这条新操作条 ⇒ 背包照样铺到 712, 被它压住。
			if btns.size() > 0:
				var bar0: Control = (btns[0] as Node).get_parent() as Control
				if bar0 != null:
					var br: Rect2 = Rect2(bar0.position, bar0.size)
					if br.end.y > 720.5:
						bad.append("%s/%s#%d: 操作条底沿 %.0f 伸出 720 设计框" % [lane, kind, i, br.end.y])
					for sco in _all(sc):
						if sco is ScrollContainer:
							var sr2: Rect2 = Rect2((sco as Control).position, (sco as Control).size)
							if sr2.intersects(br):
								bad.append("%s/%s#%d: 操作条 %s 压在背包滚动区 %s 上"
									% [lane, kind, i, str(br), str(sr2)])
			if btns.size() != want:
				bad.append("%s/%s#%d(%s): 在身 %d 件, 卸下键 %d 个"
					% [lane, kind, i, str(unit.get("id", "")), want, btns.size()])
				continue
			for b in btns:
				var bs: Vector2 = (b as Control).size
				if minf(bs.x, bs.y) < TOUCH_MIN_PX:
					bad.append("%s/%s#%d: 卸下键只有 %.0f×%.0f(短边 %.1fpt)"
						% [lane, kind, i, bs.x, bs.y, minf(bs.x, bs.y) / PX_PER_PT])
				var bar: Control = (b as Node).get_parent() as Control
				if bar != null and not bar.get_global_rect().grow(1.0).encloses((b as Control).get_global_rect()):
					bad.append("%s/%s#%d: 卸下键伸出操作条 %s / %s"
						% [lane, kind, i, str((b as Control).get_global_rect()), str(bar.get_global_rect())])
	print("  [EQUIP_SLOT_PT ③④] 验过的单位类型: %s ; 不合格 %d 条" % [str(kinds_seen), bad.size()])
	_ok("EQUIP_SLOT_PT ③ ★分母: 统领与小将【两类】都验到了(%s) —— 原 bug 只坏统领那一半, 少验一类就照样绿"
		% str(kinds_seen),
		int(kinds_seen.get("leader", 0)) >= 1 and int(kinds_seen.get("minion", 0)) >= 1)
	_ok("EQUIP_SLOT_PT ④ 每只带装备的单位: 卸下键数 == 在身件数, 每颗短边 ≥ 81px(44pt), 且不伸出操作条",
		bad.is_empty(), " / ".join(bad.slice(0, 4)))
	sc.queue_free()
	await get_tree().process_frame
