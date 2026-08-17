extends Node
## verify_info_panel_fits.gd — 战斗信息面板【不许上下滑动 · 宽度不许跳】(2026-08-16)
##
## ══════════════════════════════════════════════════════════════════════════
##  由来(用户原话)
## ══════════════════════════════════════════════════════════════════════════
##   「更多属性不要直接放在这下面」「**不要向下撑开，不希望有要上下滑动的**」
##   「你没懂我意思啊，是**整个大框变窄**啊，图标肯定是正方的啊」
##
## 我以为这两条早就满足了 —— 门禁 65 条全绿, 结构六行也验过。
## 实拍量出来【两条都没满足】:
##   · 内容 780px 塞进 610px 的视口 ⇒ 面板一直是能滚的, 只是我没往下拖过
##   · 宝箱龟面板 432 宽、别的龟 312 宽 ⇒ 同一个界面两种宽度
##     (根因: `_add_body_text` 里写死 `custom_minimum_size = Vector2(380,0)`,
##      那是面板还 400 宽时代的数字, 收窄到 312 时没跟着改, 反过来把面板顶宽。)
##
## ★为什么原来的门禁接不住: 它们验的是"有没有这一节 / 文字对不对 / 数值实不实时",
##   **一条都没有量过总高度**。看不见的东西不会自己报错 —— 面板超出部分只是滚上去了。
##
## ★判据(量真实矩形, 不读源码):
##   ① 内容 VBox 的高 ≤ ScrollContainer 的高          —— 装得下 = 不用滚
##   ② 每只龟的面板宽度都相同                          —— 宽度不许跳
##   ③ 面板右边缘在屏内                                —— 别滑出去
##   逐只龟跑, 且【喂满】(三件装备 + 多个状态 + 各自的专属资源), 拿最坏情况量。
##
## 跑法: <godot> --headless --path . res://tests/verify_info_panel_fits.tscn --quit-after 3000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


## 一棵树里所有【可见的】Label(判断"字被切没切"必须逐个量真实矩形, 隐藏的不算)
func _walk_labels(root: Node) -> Array:
	var out: Array = []
	var st: Array = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is Label and (n as Control).is_visible_in_tree():
			out.append(n)
		for c in n.get_children():
			st.append(c)
	return out


## 一棵树里所有【可见的】ColorRect(分隔线判据用: 量真实高度, 不看源码)
func _walk_rects(root: Node) -> Array:
	var out: Array = []
	var st: Array = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is ColorRect and (n as Control).is_visible_in_tree():
			out.append(n)
		for c in n.get_children():
			st.append(c)
	return out


## 一棵树里所有【可见的】NinePatchRect(判"框画不画得出来"要量真实矩形)
func _walk_ninepatch(root: Node) -> Array:
	var out: Array = []
	var st: Array = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is NinePatchRect and (n as Control).is_visible_in_tree():
			out.append(n)
		for c in n.get_children():
			st.append(c)
	return out


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 面板里那两个关键容器: [ScrollContainer, 内容 VBox]。找不到返回 [null, null]。
func _panel_parts(panel: Control) -> Array:
	var sc: ScrollContainer = null
	var stack: Array = [panel]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is ScrollContainer:
			sc = n as ScrollContainer
			break
		for ch in n.get_children():
			stack.append(ch)
	if sc == null:
		return [null, null]
	for ch in sc.get_children():
		if ch is VBoxContainer:
			return [sc, ch]
	return [sc, null]


func _ready() -> void:
	await get_tree().process_frame
	print("=== 战斗信息面板: 装得下(不用滚) + 宽度不跳 ===")
	## ★★视口必须焊死成设计尺寸 1280×720。
	##   第一版没焊, 无头默认视口是 **1280×1280 的正方形** ⇒ 滚动视口高 1170,
	##   而最高的龟才 595 —— 怎么塞都装得下, 断言【永远绿】。
	##   实测确认它是假门禁: 往面板里注入一个 300px 高的空块, 5 条断言照样全 PASS。
	##   (memory fb-verify-check-can-fail: 报"通过"之前先证明它会 FAIL。
	##    同 verify_info_panel_live 的做法, 那边也踩过同一个坑。)
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._units.clear()
	s._edit_mode = false
	s._over = false
	s.set_process(false)

	var ids: Array = []
	for k in DataRegistry.pet_by_id.keys():
		ids.append(str(k))
	ids.sort()
	_ok("★分母: 拿到全部龟的 id(不是空表)", ids.size() >= 20, "共 %d 只" % ids.size())

	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var widths: Dictionary = {}
	var overflow: Array = []
	var offscreen: Array = []
	var tap_short: Array = []
	var no_basic: Array = []
	var hint_squashed: Array = []
	var stat_noicon: Array = []
	var skill_noicon: Array = []
	var det_bad: Array = []
	var tint_bad: Array = []
	var bar_noframe: Array = []
	var round_bad: Array = []
	var font_sizes: Array = []
	var en_mix: Array = []
	var clipped: Array = []
	var clip_seen: int = 0
	var sep_lone: Array = []
	var sep_seen: int = 0
	var outline_box: Array = []
	var tex_missing: Array = []
	var tex_seen: int = 0
	var stock_btn: Array = []
	var btn_seen: int = 0
	var np_flat: Array = []
	var np_seen: int = 0
	## ★★分母计数器(2026-08-17 自审补): 下面几条判据的【被测对象本身可能不存在】——
	##   那时集合是空的, `is_empty()` 照样为真 ⇒ 断言一路绿着骗人。
	##   (上一轮在图鉴那条上刚栽过: 图鉴被切到别的 Tab ⇒ 扫 28 只也是 0 张, 靠分母才发现。)
	var n_hint := 0        # 扫到几个"结论文字"标签
	var n_stylebox := 0    # 扫到几个挂了 stylebox 的控件
	var n_skill := 0       # 扫到几个技能(查图标用)
	var n_statrow := 0     # 扫到几行主要属性
	var tap_seen := 0
	var tap_min := 99999.0
	var measured := 0

	for pid in ids:
		var u: Dictionary = s._spawn._make_unit(str(pid), "left", c)
		## ★喂满 —— 空面板量不出最坏情况(条是空的、槽是空的、状态一个没有)。
		##   面板高度是随内容长的, 拿空壳量等于没量。
		u["hp"] = float(u.get("maxHp", 1000)) * 0.62
		## ★装备的真格式是 [{id, star}] 的字典数组, 不是 id 字符串数组 ——
		##   喂错格式会让产品代码 `e as Dictionary` 每只龟报一次 cast 错误(实测 28 条),
		##   而断言照样全绿: 这是【测试数据错】伪装成产品报错, 门禁的致命正则才逮住它。
		## ★★至少有一件【带局内读数】的(2026-08-17): 原来这三件 004/021/040 在
		##   `EquipReadouts` 两张表里**一个都没有** ⇒ 槽底那行读数 Label 根本不会被造出来
		##   ⇒ 下面的字号档数、读数宽度这些判据**扫不到那一档**, 断言看着绿实际没覆盖。
		##   (今晚第三次栽在同一形状: 判据本身没错, 是被测对象没造出来。)
		##   093 香火石两张表都有 ⇒ 走紧凑式那条路径, 是最能撑爆槽的一件。
		u["equips"] = [{"id": "p2eq_004", "star": 2}, {"id": "p2eq_093", "star": 1},
			{"id": "p2eq_040", "star": 3}]
		u["shield"] = 240.0
		u["burn_stacks"] = 7.0
		u["slow_until"] = s._t + 99.0
		u["slow_mult"] = 0.6
		## ★喂【这只龟自己的】那一种专属资源。
		##   第一版只喂金币 ⇒ 熔岩龟的怒气条没算进去, 实拍底部被切而门禁全绿(最坏情况没喂到 = 白测)。
		##   第二版给所有龟同时喂金币+怒气 ⇒ 又走到另一头: 一只龟【最多只有一种】专属资源,
		##   同时挂两条是游戏里不存在的状态, 拿它当判据会逼版式为不可能的情况让路。
		##   ⇒ 按 id 对号入座, 这才是真正的最坏情况。
		match str(pid):
			"lava":    u["rage"] = 30.0
			"space":   u["star_energy"] = float(u.get("maxHp", 1000)) * 0.18
			## ⚠★2026-08-17 订正: 这里原来写的是 `shell_storage` / `bubble_val` ——
			##   **全仓 0 次出现**, 是测试里凭空编的字段名(面板读的是 `store_energy` / `bubble_store`)。
			##   后果: 这两只龟的**专属资源行从来没被建出来**, 也就是说它们的【最坏版式
			##   从来没被量过】—— 断言一直绿着, 但绿的是两只"少了一行"的假龟。
			##   (今晚第五次"判据没错、被测对象不在场"。喂给被测对象的字段名, 要按【消费侧】抄。)
			"shell":   u["store_energy"] = float(u.get("maxHp", 1000)) * 0.25
			"bubble":  u["bubble_store"] = float(u.get("maxHp", 1000)) * 0.5
			"chest":   u["dmg_dealt"] = 800.0
			"fortune": u["gold"] = 37.0
		s._units.clear()
		s._units.append(u)
		s._hud._show_unit_info_panel(u)
		## 布局要走完一帧才有真实矩形 —— 刚 add_child 时全是 0。
		await get_tree().process_frame
		await get_tree().process_frame
		## ★面板是【从右侧滑入】的, 等两帧量到的是半路位置 ——
		##   第一版就这么写, 28 只龟量出 28 个不同的 x(1156/1173/1177/1201…),
		##   看起来像"面板出界了", 其实是我在动画中途拿的尺。
		##   这里【不等 tween 完成信号】(CLAUDE.md §3.5: 无头下 tween 推不动), 而是
		##   轮询真实矩形, 连续 3 帧不动就算到位; 上限 180 帧防死循环。
		if s._info_panel != null and is_instance_valid(s._info_panel):
			var _last := -99999.0
			var _still := 0
			var _w := 0
			while _w < 180 and _still < 3:
				await get_tree().process_frame
				_w += 1
				var _x: float = (s._info_panel as Control).position.x
				if absf(_x - _last) < 0.01:
					_still += 1
				else:
					_still = 0
					_last = _x
		var panel = s._info_panel
		if panel == null or not is_instance_valid(panel):
			overflow.append("%s: 面板没建出来" % pid)
			continue
		var parts := _panel_parts(panel)
		var sc = parts[0]
		var vb = parts[1]
		if sc == null or vb == null:
			overflow.append("%s: 找不到滚动容器/内容容器" % pid)
			continue
		measured += 1
		var need: float = (vb as Control).get_combined_minimum_size().y
		var have: float = (sc as Control).size.y
		if need > have:
			overflow.append("%s 内容 %.0f > 视口 %.0f (超 %.0f)" % [pid, need, have, need - have])
		if measured <= 3 or need > have:
			print("    [分母] %s: 内容 %.0f / 视口 %.0f / 面板 %.0fx%.0f / 父区 %.0fx%.0f" % [
				pid, need, have, (panel as Control).size.x, (panel as Control).size.y,
				(panel as Control).get_parent_area_size().x,
				(panel as Control).get_parent_area_size().y])
		widths[str(pid)] = (panel as Control).size.x
		## 点开一次描述框, 量它多高(只在前 6 只上做, 够了)
		if measured <= 6:
			var _ent2: Array = s._info_sys._skill_bar_entries(u)
			if not _ent2.is_empty():
				var _e: Dictionary = _ent2[_ent2.size() - 1]
				s._info_sys._show_detail(panel, "gate_%s" % pid, str(_e.get("name", "")),
					str(_e.get("desc", "")), _e, u)
				await get_tree().process_frame
				await get_tree().process_frame
				var _ovn = panel.get_node_or_null("DetailOverlay")
				var _bx = null if _ovn == null else _ovn.get_node_or_null("Box")
				if _bx == null:
					det_bad.append("%s: 找不到描述框" % pid)
				else:
					var _bh: float = (_bx as Control).size.y
					var _ph: float = (panel as Control).size.y
					if _bh > _ph * 0.75 or _bh < 60.0:
						det_bad.append("%s: 框高 %.0f / 面板 %.0f" % [pid, _bh, _ph])
				if _ovn != null:
					(_ovn as Control).visible = false
		## ★资源条的【结论那句】必须真的看得见 —— 有宽度, 不是被弹簧挤成 1px。
		##   实拍抓到过: 「攒满变火山形态」在树里好端端存在, 量出来 1x17 ⇒ 屏幕上一个像素都没有。
		##   判据量【真实矩形宽度】, 不是"文本非空"(文本一直非空, 那条断言永远绿)。
		var _hst: Array = [panel]
		while not _hst.is_empty():
			var _hn: Node = _hst.pop_back()
			if _hn is Label:
				var _lt := str((_hn as Label).text)
				if _lt.find("攒满") >= 0 or _lt.find("每点") >= 0:
					n_hint += 1
					if (_hn as Control).size.x < 20.0:
						hint_squashed.append("%s: 「%s」只有 %.0fpx 宽" % [pid, _lt, (_hn as Control).size.x])
			for _hc in _hn.get_children():
				_hst.append(_hc)
		for _sr in s._info_sys._info_stat_rows_main(u):
			n_statrow += 1
			var _ip2 := str((_sr as Array)[0])
			if _ip2 == "" or not ResourceLoader.exists(_ip2):
				stat_noicon.append("%s: 「%s」图标=%s" % [pid, str((_sr as Array)[1]), _ip2 if _ip2 != "" else "(空)"])
		## 中英夹杂: 收面板里所有可见文本, 剔掉白名单后不该再有英文词
		if measured <= 6:
			var _ste: Array = [panel]
			var _re := RegEx.new()
			_re.compile("[A-Za-z]{2,}")
			while not _ste.is_empty():
				var _ne: Node = _ste.pop_back()
				if _ne is Label and (_ne as Control).is_visible_in_tree():
					var _tx := str((_ne as Label).text)
					var _clean := _tx.replace("Lv", "").replace("LV", "")
					if _re.search(_clean) != null:
						en_mix.append("%s: 「%s」" % [pid, _tx.substr(0, 18)])
				for _ce in _ne.get_children():
					_ste.append(_ce)
		## ── 带 clip_text 的标签不许真的被截掉(2026-08-17) ────────────────────
		##   ★由来: 把面板字号从 6 档并成 4 档时, 技能名 11 → 12px。技能名槽宽写死 88 且
		##     `clip_text = true` ⇒ 字号一涨就可能【无声地】被切掉尾字, 屏幕上看着像个短名字。
		##     `clip_text` 的整个作用就是"宁可切也不撑开布局", 所以它永远不会报错。
		##   ★判据量【真实字符串像素宽 vs 真实矩形宽】: 拿这个 Label 自己的字体和字号去算,
		##     不数字符数(中/英/数字宽度差很多), 也不搜源码。
		##   ⚠ 只查 clip_text 的 —— 会自动换行(autowrap)的标签本来就该多行, 不是截断。
		for _cn in _walk_labels(panel):
			var _cl := _cn as Label
			if not _cl.clip_text or _cl.autowrap_mode != TextServer.AUTOWRAP_OFF:
				continue
			var _ct := str(_cl.text).strip_edges()
			if _ct == "" or _cl.size.x <= 1.0:
				continue
			clip_seen += 1
			var _cf: Font = _cl.get_theme_font("font")
			if _cf == null:
				continue
			var _cw: float = _cf.get_string_size(_ct, HORIZONTAL_ALIGNMENT_LEFT, -1,
				_cl.get_theme_font_size("font_size")).x
			if _cw > _cl.size.x + 0.5:
				clipped.append("%s: 「%s」需 %.0fpx / 只有 %.0fpx" % [pid, _ct, _cw, _cl.size.x])

		## ── 分隔线必须是【凹刻双色】, 不许退回一条平线(2026-08-17) ──────────
		##   ★由来: 面板里的框/槽/签全换成像素金属之后, 只剩分隔线还是
		##     `ColorRect` 一条 1px 白 8% —— `<hr>` 的长相, 最后一处网页味。
		##     现在是【上暗下亮】紧挨的两条(光从上打下来的刻痕)。
		##   ★判据落在【真实节点的高度与颜色】: 面板里每一条 1px 高的 ColorRect
		##     都必须有一个同为 1px 的同胞 —— 落单的那条就是退回平线了。
		##     (不搜源码: 分隔线是运行时建的, 源码里搜不出"现在画了几条"。)
		for _sn in _walk_rects(panel):
			var _sr := _sn as ColorRect
			if _sr.size.y > 1.5 or _sr.size.y < 0.5:
				continue
			sep_seen += 1
			var _sib := 0
			for _c in _sr.get_parent().get_children():
				if _c is ColorRect and (_c as ColorRect).size.y <= 1.5:
					_sib += 1
			if _sib < 2:
				sep_lone.append("%s: 1px 线在 %s 下落单(同胞 %d 条) —— 退回平线了" % [pid, _sr.get_parent().name, _sib])

		## 字号: 收集面板里所有可见 Label 的真实 font_size
		if measured <= 6:
			var _stf: Array = [panel]
			while not _stf.is_empty():
				var _nf: Node = _stf.pop_back()
				if _nf is Label and (_nf as Control).is_visible_in_tree():
					var _sz: int = (_nf as Label).get_theme_font_size("font_size")
					if not font_sizes.has(_sz):
						font_sizes.append(_sz)
				for _cf in _nf.get_children():
					_stf.append(_cf)
		## 面板里【不许有圆角 CSS 方块】—— 圆角矩形是网页的长相, 用户点名骂过"网页味"。
		##   面板/槽/条都换成硬边像素框之后, 只剩状态签还是平滑抗锯齿的圆角胶囊(实拍放大才看见)。
		##   ★判据量【真实 StyleBox 的圆角半径】, 不搜源码 —— 源码里 set_corner_radius_all 有好几处,
		##     哪几处真正生效要看运行时挂上去的是哪个 stylebox(有九宫格时兜底那份根本不显示)。
		if measured <= 6:
			var _st6: Array = [panel]
			while not _st6.is_empty():
				var _n6: Node = _st6.pop_back()
				if _n6 is Control:
					for _slot in ["panel", "normal", "background", "fill"]:
						if not (_n6 as Control).has_theme_stylebox_override(_slot):
							continue
						var _sb = (_n6 as Control).get_theme_stylebox(_slot)
						n_stylebox += 1
						if _sb is StyleBoxFlat and (_sb as StyleBoxFlat).corner_radius_top_left > 0:
							round_bad.append("%s: %s 的 %s 圆角 %d" % [pid, _n6.get_class(), _slot,
								(_sb as StyleBoxFlat).corner_radius_top_left])
						## ★★【四边描边 + 半透明填充】= CSS `border:1px solid` + `rgba()` 的长相,
						##   也就是用户说的"网页味"里除圆角之外的另一半。状态签原来就是这个组合。
						##   ⚠ 判据必须是**四边都有边框且底半透明** —— 第一版只判"有上边框",
						##     结果把我自己给血条填充加的【顶部 3px 液面高光】(单边、底不透明)
						##     当成网页盒报了 6 个。**判据宽一格就制造假 bug**(今晚第二次)。
						if _sb is StyleBoxFlat:
							var _f6 := _sb as StyleBoxFlat
							if _f6.border_width_top > 0 and _f6.border_width_bottom > 0 									and _f6.border_width_left > 0 and _f6.border_width_right > 0 									and _f6.bg_color.a < 0.95:
								outline_box.append("%s: %s 的 %s(边%d 底a%.2f)" % [pid, _n6.get_class(),
									_slot, _f6.border_width_top, _f6.bg_color.a])
				for _c6 in _n6.get_children():
					_st6.append(_c6)
		## 条框: 找所有 NinePatchRect, 每个都要有 texture
		if measured <= 6:
			var _np := 0
			var _bad := 0
			var _st5: Array = [panel]
			while not _st5.is_empty():
				var _n5: Node = _st5.pop_back()
				if _n5 is NinePatchRect:
					_np += 1
					if (_n5 as NinePatchRect).texture == null:
						_bad += 1
				for _c5 in _n5.get_children():
					_st5.append(_c5)
			## ★★九宫格【画得出来吗】—— 有贴图 ≠ 看得见(2026-08-17 实拍抓到)。
			##   资源条(泡泡/怒气/星能/储能)确实调了 `_bar_frame`, 但那一行只有 14px 高,
			##   而条框九宫格上下边距 7+7 = 14 ⇒ **中段一行不剩, 框被压没** ——
			##   屏幕上是裸的色块压黑底, 正是用户「血条龟能条都跟网页一样」那条抱怨。
			##   而上面那条 `bar_noframe` 只数"有没有贴图", **这种退化它查不到**。
			##   判据: 渲染出来的高/宽必须 **大于** 上下/左右边距之和, 否则中段是负的。
			##   (同一个坑今晚第二次: 头像框 64px 源塞进 56px 目标也是它。)
			for _n7 in _walk_ninepatch(panel):
				var _p7 := _n7 as NinePatchRect
				if _p7.texture == null or _p7.size.y <= 0.0:
					continue
				np_seen += 1
				var _mv: float = _p7.patch_margin_top + _p7.patch_margin_bottom
				var _mh: float = _p7.patch_margin_left + _p7.patch_margin_right
				if _p7.size.y <= _mv or _p7.size.x <= _mh:
					np_flat.append("%s: %s 实高%.0f/边距和%.0f 宽%.0f/%.0f" % [pid,
						_p7.texture.resource_path.get_file(), _p7.size.y, _mv, _p7.size.x, _mh])
			if _np == 0:
				bar_noframe.append("%s: 一个条框都没有(下面是空检查)" % pid)
			elif _bad > 0:
				bar_noframe.append("%s: %d/%d 个条框没贴图" % [pid, _bad, _np])
		## ── 今晚做的四张素材必须【真的挂在活面板上】(2026-08-17) ──────────
		##   ★由来: 一个晚上把面板从"网页味"改成金属框, 靠的是 5 张九宫格贴图。
		##     以后有人图省事把某一处换回 `StyleBoxFlat`, **界面只是变回网页样, 不报任何错** ——
		##     正是今晚开头那批"绿着的假门禁"同一个形状。
		##   ★判据量【运行时真的挂上去的贴图路径】: 遍历活面板, 收集
		##     NinePatchRect.texture 与 StyleBoxTexture.texture 的 resource_path。
		##     **不查文件存在** —— 文件在、没人挂, 玩家照样看不到(写进去了没人读)。
		if measured <= 6:
			var _mounted: Dictionary = {}
			var _stq: Array = [panel]
			while not _stq.is_empty():
				var _nq: Node = _stq.pop_back()
				if _nq is NinePatchRect and (_nq as NinePatchRect).texture != null:
					_mounted[(_nq as NinePatchRect).texture.resource_path.get_file()] = true
				if _nq is Control:
					for _sl in ["panel", "normal", "background", "fill"]:
						if not (_nq as Control).has_theme_stylebox_override(_sl):
							continue
						var _sx = (_nq as Control).get_theme_stylebox(_sl)
						if _sx is StyleBoxTexture and (_sx as StyleBoxTexture).texture != null:
							_mounted[(_sx as StyleBoxTexture).texture.resource_path.get_file()] = true
				## ★探针: Button 若【没有 stylebox 覆盖】, 用的就是 Godot 默认主题 ——
				##   圆角纯色, 是"没游戏味"最直接的来源。上面那条网页盒判据先查
				##   has_theme_stylebox_override, 所以**根本扫不到它们**(判据的盲区)。
				if _nq is Button:
					btn_seen += 1
					if not (_nq as Control).has_theme_stylebox_override("normal"):
						stock_btn.append("%s「%s」" % [pid, str((_nq as Button).text).substr(0, 6)])
				for _cq in _nq.get_children():
					_stq.append(_cq)
			tex_seen = maxi(tex_seen, _mounted.size())
			for _need in ["panel-frame.png", "slot-frame.png", "bar-frame.png",
					"chip-frame.png", "portrait-frame.png"]:
				if not _mounted.has(_need) and not tex_missing.has(_need):
					tex_missing.append(_need)

		## 被动槽的紫调: 取【最上面那一排】三个 88px 槽(技能栏), 后两格应相同、第一格应不同
		if measured <= 6:
			var _slots: Array = []
			var _sk2: Array = [panel]
			while not _sk2.is_empty():
				var _n2: Node = _sk2.pop_back()
				if _n2 is PanelContainer:
					var _cc2 := _n2 as Control
					if _cc2.size.y > 80.0 and _cc2.size.y < 96.0 and _cc2.size.x > 80.0 and _cc2.size.x < 96.0:
						_slots.append(_n2)
				for _c2 in _n2.get_children():
					_sk2.append(_c2)
			## 技能三槽在装备三槽【上面】⇒ 取 y 最小的那一排
			var _ymin: float = 1e9
			for _s3 in _slots:
				_ymin = minf(_ymin, (_s3 as Control).global_position.y)
			var _row: Array = []
			for _s4 in _slots:
				if absf((_s4 as Control).global_position.y - _ymin) < 4.0:
					_row.append(_s4)
			## 同一排里按 x 从左到右(被动在最左)
			for _a in range(_row.size()):
				for _b in range(_row.size() - 1 - _a):
					if (_row[_b] as Control).global_position.x > (_row[_b + 1] as Control).global_position.x:
						var _t3 = _row[_b]; _row[_b] = _row[_b + 1]; _row[_b + 1] = _t3
			if _row.size() >= 3:
				var m0: Color = (_row[0] as CanvasItem).self_modulate
				var m1: Color = (_row[1] as CanvasItem).self_modulate
				var m2: Color = (_row[2] as CanvasItem).self_modulate
				var base: float = absf(m1.r - m2.r) + absf(m1.g - m2.g) + absf(m1.b - m2.b)
				var diff: float = absf(m0.r - m1.r) + absf(m0.g - m1.g) + absf(m0.b - m1.b)
				if diff <= base + 0.15:
					tint_bad.append("%s: 被动差 %.3f / 同款基线 %.3f" % [pid, diff, base])
			else:
				tint_bad.append("%s: 技能排只找到 %d 个槽(下面是空检查)" % [pid, _row.size()])
		## ★三格里【每一格都要有图标】—— 空图标 = 槽里一片空白, 而它是可点的大方块。
		##   实测 2026-08-17: 112 个技能里有 2 个(凤凰「强化涅槃」/ 熔岩「熔岩爆发」)
		##   连 icon 字段都没有。和增伤/减伤同一类洞: 空值不报错, 只查错值等于放过它。
		##   ⚠ 判据不能只看【当前选中的那一个】主动技 —— 技能槽一次只显示一个,
		##     而 3 选 1 的另外两个【同样会出现在槽里】。第一版只遍历 _skill_bar_entries,
		##     结果那两个真的没图标的技能压根没被走到, 断言当场"全绿"。
		##     ⇒ 遍历【整个技能池】, 每一个都要有图标。
		var _pet: Dictionary = DataRegistry.pet_by_id.get(str(pid), {})
		for _sk in (_pet.get("skillPool", []) as Array):
			if not (_sk is Dictionary):
				continue
			n_skill += 1
			if s._info_sys._skill_icon_path(_sk as Dictionary) == "":
				skill_noicon.append("%s·%s" % [pid, str((_sk as Dictionary).get("name", ""))])
		## ★技能栏必须【三格齐】: 被动 / 普攻 / 携带的主动技。
		##   实测 2026-08-16: 28 只里 17 只只有两格 —— 普攻槽的判据写成"type 必须是
		##   physical/magic", 而 17 只龟的普攻 type 是自己的名字(lavaBolt/iceSpike…) ⇒ 静默消失。
		##   面板上表现为右边空一格, 不报错、不红任何门禁。
		var _ent: Array = s._info_sys._skill_bar_entries(u)
		var _has_basic := false
		for _e in _ent:
			if str((_e as Dictionary).get("name", "")).find("(普攻)") >= 0:
				_has_basic = true
		if not _has_basic:
			no_basic.append(str(pid))
		if _ent.size() < 3:
			no_basic.append("%s 技能栏只有 %d 格" % [pid, _ent.size()])
		## 可点条目 = mouse_filter 为 STOP 的 PanelContainer(技能槽/装备槽/入口条都是这么建的)。
		var _st: Array = [panel]
		while not _st.is_empty():
			var _n: Node = _st.pop_back()
			if _n is PanelContainer and (_n as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
				var _h: float = (_n as Control).size.y
				tap_seen += 1
				if _h < tap_min:
					tap_min = _h
				if _h > 0.0 and _h < 32.0:
					tap_short.append("%s 有个可点条只有 %.0fpx 高" % [pid, _h])
			for _c in _n.get_children():
				_st.append(_c)
		## ★尺子要和被测概念同一套坐标(memory fb-3d-quality-bar-tentacle)。
		##   面板挂在 CanvasLayer 上, `get_global_rect()` 给的是【那一层的】坐标,
		##   拿 `get_viewport().size` 去比是两把尺子混用 —— 第一版就这么写, 28 只全"出界",
		##   而实拍面板明明好端端在屏幕右侧。用面板自己的父级可用区当分母才对得上。
		var pa: Vector2 = (panel as Control).get_parent_area_size()
		var px: float = (panel as Control).position.x
		var pw: float = (panel as Control).size.x
		if px < -1.0 or px + pw > pa.x + 1.0:
			offscreen.append("%s [x %.0f..%.0f] 可用宽 %.0f" % [pid, px, px + pw, pa.x])
		s._hud._close_info_panel()
		await get_tree().process_frame

	_ok("★分母: 真的量到了每一只(不是 0 只)", measured >= 20, "量了 %d 只" % measured)

	# ── ① 装得下 ────────────────────────────────────────────────────────────
	_ok("★★每只龟的面板内容都【装得进视口】—— 不用上下滑动(用户明令)",
		overflow.is_empty(), "超出的: %s" % str(overflow.slice(0, 6)))

	# ── ② 宽度不跳 ──────────────────────────────────────────────────────────
	var wset: Dictionary = {}
	for k in widths.keys():
		wset[str(widths[k])] = true
	_ok("★★所有龟的面板【宽度一致】—— 换只龟不许换个宽度",
		wset.size() == 1, "出现了 %d 种宽度: %s" % [wset.size(), str(wset.keys())])

	_ok("★★每只龟的技能栏都是【三格齐】(被动/普攻/技能) —— 普攻槽不许静默消失",
		no_basic.is_empty(), "缺格的: %s" % str(no_basic.slice(0, 6)))

	_ok("★分母: 真的扫到了结论文字标签(0 个 = 下面是空检查)", n_hint > 0, "扫到 %d 个" % n_hint)
	_ok("★资源条的结论文字真的看得见(没被弹簧挤成 1px)",
		hint_squashed.is_empty(), "被挤没的: %s" % str(hint_squashed.slice(0, 4)))

	## ★主要 8 项属性【每一项都要有图标, 且文件真的在盘上】。
	##   由来: 增伤/减伤两项的图标位一直是空串 —— 面板上那两行光秃秃一个图标都没有,
	##   而旁边六项都有。不是"没做完", 是【没人发现】: 空字符串不报错、不红任何门禁
	##   (同 data_integrity 那条"空值和错值是两类病, 只查后者等于放过前者")。
	## ── 描述框不许铺满整个面板 ────────────────────────────────────────────
	##   ★由来 2026-08-17(实拍): 描述框是 `PanelContainer` 的直接子节点, 而
	##     **容器会强行把子节点拉满自己的内容区** ⇒ 代码里写好的 `offset_top = -300`
	##     一个像素都没生效, 浮层从面板顶铺到底(约 640px), 内容只占顶部 20%,
	##     下面一大片带边框的空白, 看着像没做完。
	##   ★判据量【真实矩形】: 框高 ≤ 面板高的 75%(留出上面的头像/血条/槽还看得见),
	##     且 ≥ 60px(不能塌成一条缝)。断言"框存在"守不住这个 —— 它一直都存在。
	_ok("★★点开的描述框【不铺满面板】(上面的头像/条/槽还看得见)",
		det_bad.is_empty(), "不对的: %s" % str(det_bad.slice(0, 4)))

	## ── 被动槽要和另外两个【看得出不一样】────────────────────────────────
	##   ★由来: 技能栏三格长得一模一样, 被动那格靠 self_modulate 上一层紫调区分。
	##     这种纯视觉的东西【重构时最容易悄悄丢】, 而丢了不报任何错。
	##   ★判据用【同款之间的差】当噪声基线: 普攻 vs 技能应当完全相同(基线 0),
	##     被动那一档必须明显大于基线 —— 只断言"被动有 self_modulate"守不住
	##     (设成和别人一样的值也算"有")。
	##   实拍佐证(1280×720): 被动框内圈 RGB(39,51,104) / 另两格 (46,70,93), 色距 23.7 vs 基线 0.0。
	## ── 条框贴图必须真的加载上 ────────────────────────────────────────────
	##   ★由来(第 1 轮的坑): 新 PNG 没有 `.import` 时 `ResourceLoader.exists()` 返回 false,
	##     `_bar_frame()` 直接返回 null ⇒ 框根本不建, **而且一句报错都没有**。
	##     当时是靠实拍才发现"框没换上"。
	##   ★判据: 每条资源条底下都要有一个 NinePatchRect 且它的 texture 非空。
	##     只断言"节点在"守不住 —— 贴图丢了节点照样在(它就是个空壳)。
	##   ★实拍佐证: 把 bar-frame.png 临时挪走后重拍, 血条纵向明暗跨度 160 → 72、
	##     逐行平均差 28.8 ⇒ 框确实在画, 不是摆设。
	## ── 字号层级不许发散 ────────────────────────────────────────────────
	##   ★由来: 实测面板里同时用了 6 种字号(21/14/13/12/11/10), 其中 13 与 12 几乎分不出 ——
	##     而且【同一类信息用了两个号】: 资源行的「30 / 100」是 13, 隔 20 像素的龟能条
	##     「63 / 115」是 12。收成 5 档后一档只表示一种角色:
	##     21 标题 / 14 正文 / 12 次要 / 11 说明 / 10 角标。
	##   ★判据量【真实 Label 的 font_size】, 不搜源码 —— 源码里的 override 有的会被主题顶掉。
	## ── 面板里不许中英夹杂 ──────────────────────────────────────────────
	##   ★由来: 实测面板可见文本 31 条, 含英文的 2 条 ——「HP  507 / 819」与「友军 · S · Lv 1」。
	##     再量全游戏: **HP 只有面板这两处**(别处一律"生命/最大生命值"), 而 **Lv 有 6 处以上**
	##     (LV UP / Lv%d / Lv%d×%d) 是既有约定 ⇒ 改 HP、留 Lv。**是量出来的, 不是我觉得。**
	##   ★判据量【渲染出来的文本】不搜源码 —— 源码里的字符串未必都显示。
	_ok("★面板里不中英夹杂(白名单: Lv/★, 游戏既有约定)", en_mix.is_empty(),
		"夹英文的: %s" % str(en_mix.slice(0, 4)))

	_ok("★分母: 真的量到了九宫格框(0 个 = 空检查)", np_seen >= 10, "量了 %d 个" % np_seen)
	_ok("★★没有【被压扁到画不出来】的九宫格(边距和 ≥ 实际尺寸 = 中段是负的)",
		np_flat.is_empty(), "压扁的: %s" % str(np_flat.slice(0, 5)))

	_ok("★分母: 真的扫到了按钮(0 个 = 空检查)", btn_seen >= 6, "扫到 %d 个" % btn_seen)
	_ok("★★面板里没有【用 Godot 默认主题】的按钮(圆角纯色 = 最直接的「没游戏味」)",
		stock_btn.is_empty(), "还是默认皮的: %s" % str(stock_btn.slice(0, 6)))
	_ok("★分母: 面板上真的挂了九宫格贴图(0 张 = 空检查)", tex_seen >= 4,
		"挂了 %d 张不同的贴图" % tex_seen)
	_ok("★★五张面板素材都真的挂在活面板上(文件在≠有人挂)", tex_missing.is_empty(),
		"没挂上的: %s" % str(tex_missing))

	_ok("★★面板里没有【四边描边 + 半透明填充】的网页盒(直角只是必要条件)",
		outline_box.is_empty(), "还剩: %s" % str(outline_box.slice(0, 5)))
	_ok("★分母: 真的扫到了 1px 分隔线(0 条 = 空检查)", sep_seen >= 3,
		"扫到 %d 条" % sep_seen)
	_ok("★★分隔线是凹刻双色(上暗下亮), 不是一条平线 —— 平线是 <hr> 的长相", sep_lone.is_empty(),
		"落单的: %s" % str(sep_lone.slice(0, 4)))

	_ok("★分母: 真的量到了带 clip_text 的标签(0 个 = 空检查)", clip_seen >= 20,
		"量了 %d 个" % clip_seen)
	_ok("★★没有【被 clip_text 无声切掉】的标签(字号一涨最先出事的就是它)", clipped.is_empty(),
		"被切的: %s" % str(clipped.slice(0, 5)))

	_ok("★分母: 真的扫到了字号(至少 3 档才谈得上层级)", font_sizes.size() >= 3,
		"扫到 %d 档" % font_sizes.size())
	_ok("★面板字号不超过 5 档(一档只表示一种角色)", font_sizes.size() <= 5,
		"实得 %d 档: %s" % [font_sizes.size(), str(font_sizes)])

	_ok("★分母: 真的扫到了 stylebox(0 个 = 下面是空检查)", n_stylebox > 0, "扫到 %d 个" % n_stylebox)
	_ok("★面板里没有圆角 CSS 方块(圆角矩形是网页的长相)",
		round_bad.is_empty(), "还有圆角的: %s" % str(round_bad.slice(0, 4)))

	_ok("★★血条/龟能条的九宫格框贴图真的加载上了(丢 .import 会静默失效)",
		bar_noframe.is_empty(), "没贴图的: %s" % str(bar_noframe.slice(0, 4)))

	_ok("★★被动槽与普攻/技能槽【看得出不一样】(同款之间是基线)",
		tint_bad.is_empty(), "不对的: %s" % str(tint_bad.slice(0, 4)))

	_ok("★分母: 真的逐个查了技能图标(0 个 = 空检查)", n_skill >= 20, "查了 %d 个技能" % n_skill)
	_ok("★★技能三槽每一格都有图标(空图标 = 可点的大方块里一片空白)",
		skill_noicon.is_empty(), "缺图标的: %s" % str(skill_noicon.slice(0, 6)))
	_ok("★分母: 真的逐行查了主要属性(0 行 = 空检查)", n_statrow >= 20, "查了 %d 行" % n_statrow)
	_ok("★主要 8 项属性每项都配了图标, 且文件在盘上", stat_noicon.is_empty(),
		"缺图标的: %s" % str(stat_noicon.slice(0, 6)))

	# ── ③ 可点条目不许小到点不准 ───────────────────────────────────────────
	##   ★由来: 为了让宝箱龟装进视口, 我把「更多属性 / 战利品」这两条【可点】的入口
	##     从 46px 压到 26px —— 26px = 14pt, 而触控目标下限是 44pt(1pt = 1.846px ⇒ 81px)。
	##     省高度省到点不准, 是本末倒置。这条断言就是拦我自己再犯。
	##   ★44pt 这个理想值【现在达不到】(两条 44pt = 162px, 面板高度预算给不起) ——
	##     所以判据定在 32px 并把差距写在这里: 这是【登记在案的缺口】, 不是没想到。
	##     长条横向 280px 很好命中, 纵向偏矮是权衡后的选择。
	print("    [分母] 扫到可点条目 %d 个, 最矮 %.0fpx" % [tap_seen, tap_min])
	## ★★这一条才是重点: 面板里【点得动的东西有几个】。
	##   用户要的是「这些图标点击出现描述」「装备也是点击出现描述框」。
	##   2026-08-16 实测: 每只龟只有 1 个可点(就是面板本身), 六个槽和入口条全是 IGNORE ——
	##   根因是 `_info_passthrough` 为了手机竖滑, 把"除 Button 外一律 IGNORE"无差别刷了一遍,
	##   而重做后的可点元素【一个 Button 都没有】(全是 PanelContainer + gui_input)。
	##   ⇒ 代码里 _show_detail 写得好好的, 但点上去永远到不了它(memory fb-verify-must-run-the-real-path)。
	##   判据: 每只龟至少 6 个(3 技能槽 + 3 装备槽), 加入口条通常 7~8。
	_ok("★★每只龟的槽/入口都【真的点得动】(不是被透传刷成 IGNORE)",
		measured > 0 and tap_seen >= measured * 6,
		"共 %d 个 / %d 只 = 每只 %.1f 个(至少要 6)" % [tap_seen, measured,
			float(tap_seen) / maxf(1.0, float(measured))])
	_ok("★可点入口条不低于 32px(理想 44pt=81px, 差距已登记)",
		tap_short.is_empty(), "太矮的: %s" % str(tap_short.slice(0, 4)))

	# ── ④ 在屏内 ────────────────────────────────────────────────────────────
	_ok("★面板整个在屏幕内(没滑出右边)", offscreen.is_empty(),
		"出界的: %s" % str(offscreen.slice(0, 4)))

	s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言 · 覆盖 %d 只龟)" % [_n, measured])
	if _fail == 0:
		print("ALL PASS — 信息面板装得下且宽度一致")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
