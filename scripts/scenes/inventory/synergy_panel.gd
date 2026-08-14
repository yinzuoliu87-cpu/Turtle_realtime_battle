class_name InvSynergy
extends RefCounted
## 背包·类型羁绊面板+详情弹框
## 类内名不变;外部名加 battle.

var host

func _init(b) -> void:
	host = b

## ★2026-08-11 收拢进 GameState.team_p2_equips_for_synergy(商店羁绊信息栏也要用同一份口径)。
func _team_equips_for_synergy() -> Array:
	return GameState.team_p2_equips_for_synergy()

## 羁绊名 —— **只用羁绊名本身**。
## ★`display_name()` 返回的是「弓箭·神射手」「灵物·召唤」这种带花名的显示名,
##   而那些花名游戏里其它任何地方都不出现(战斗/图鉴/装备文案都只说"弓箭""灵物"),
##   放在这里等于凭空发明一套词(用户 2026-08-15 点名不要)。⇒ 取 `·` 前那一半。
func _syn_name(t: String) -> String:
	var full := str(host.Phase2Types.display_name(t))
	var i := full.find("·")
	return full.substr(0, i) if i > 0 else full


## ── 档位配色(用户 2026-08-15 拍板)────────────────────────────────
## 面板上**不再出现"档1/档2/档位"这些字**, 强弱只用颜色表示: 铜 → 银 → 金 → 钻石。
##
## ★★映射必须【算】出来, 不许写死"3 件 = 银"。
##   本作两种档制并存: `[3,6,9]`(三档) 与 `[2,5,8,10]`(四档)。
##   规则是**顶档一律钻石、往下依次退**⇒ 第 i 档(0-based)取 COLORS[4 - N + i]。
##   于是三档类型自然从**银**开始(4-3+0=1), 四档类型从**铜**开始(4-4+0=0) ——
##   正是用户说的"3 就从银色开始", 而不是我去数件数。
##   ⚠ 手抄一份"哪个类型什么颜色"的表 = 抄一次永远落后一次:
##     `TYPES` 里的 tiers 一改, 那张表就悄悄错了(memory [[fb-hand-rolled-copies-drift]])。
const TIER_COLORS := ["#c87941", "#c6ced8", "#ffd93d", "#8ef0ff"]   # 铜 / 银 / 金 / 钻石
const TIER_COLOR_OFF := "#6b7686"                                   # 一档都没到
const SYN_ROW_H := 62.0        # 一行的高度(手机触摸目标下限 44; 用户「按钮别又矮又扁」→ 62)


## 某类型第 tier 档(1-based; 0 = 还没开启)的颜色。
func _tier_color(typ: String, tier: int) -> Color:
	if tier <= 0:
		return Color(TIER_COLOR_OFF)
	var n: int = ((host.Phase2Types.TYPES.get(typ, {}) as Dictionary).get("tiers", []) as Array).size()
	if n <= 0:
		return Color(TIER_COLOR_OFF)
	var idx: int = clampi(TIER_COLORS.size() - n + (tier - 1), 0, TIER_COLORS.size() - 1)
	return Color(str(TIER_COLORS[idx]))


## 进度右半句: 还能升就说【下一档要几件】, 到顶了就说【已满】。
## ★只说件数, 不说"档" —— 强弱由颜色表示(用户 2026-08-15:「整个不要档一档二」)。
func _next_tier_text(typ: String, n: int) -> String:
	var tiers: Array = (host.Phase2Types.TYPES.get(typ, {}) as Dictionary).get("tiers", [])
	for th in tiers:
		if n < int(th):
			return "%d 件升级" % int(th)
	return "已满"


## 右侧羁绊列: 一行一个**按钮**, 按钮上只有【羁绊名】+【进度】, 点开才看详细效果。
##
## ★2026-08-15 三处改动(用户):
##   ① 标题「类型羁绊」→「羁绊」——「类型」是 p2eq-types.json 的内部字段名, 玩家侧不该出现。
##   ② `×4` → `4 件`; 未激活的写「2 件 · 3 件开启」—— 只陈述事实, 不写"还差1件就生效!"
##      那种带感叹号的推销话术, 也不写"阈值"这种策划表术语。
##   ③ **队伍里已有件数但还没激活的也列出来**(灰按钮) —— 原来只列已激活的,
##      于是"我装了 2 件弓箭"这件事在面板上**完全看不见**, 玩家不知道自己离开启还有多远。
##      一件都没有的类型不列(10 个全列是噪音)。
## ★按钮高度 44 —— 手机触摸目标下限(用户在商店骂过"又矮又扁")。
func _build_synergy_panel(_leaders: Array) -> void:
	var w: float = host.SYN_W
	var x0: float = host.SYN_X
	var hdr = Label.new(); hdr.text = "羁绊"
	hdr.add_theme_font_size_override("font_size", 22); hdr.add_theme_color_override("font_color", Color("#cfe0ef"))
	hdr.position = Vector2(x0, host.SYN_TOP); hdr.size = Vector2(w, 26); host.add_child(hdr)
	var cy: float = host.SYN_TOP + 32.0
	if host._sel_bench >= 0:   # 装备模式上下文提示: 引导玩家凑同类型激活/升档羁绊(用户2026-07-19)
		var ctx = Label.new(); ctx.text = "给同一只装多件同类型 → 开启羁绊 / 升一档"
		ctx.add_theme_font_size_override("font_size", 15); ctx.add_theme_color_override("font_color", Color("#7fe39a"))
		ctx.position = Vector2(x0, cy); ctx.size = Vector2(w, 20); ctx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; host.add_child(ctx)
		cy += 24.0
	var team: Array = [{"_p2_equips": _team_equips_for_synergy()}]
	var active: Array = host.Phase2Types.calc_active(team)
	## ★件数口径必须和 `calc_active` 一致(它按装备 id 去重、且一件多类型都算),
	##   否则同一行的"4 件"和"档1"会打架。`raw_counts` 是**另一套口径**(不去重·只取首要类型)
	##   ⇒ 这里自己按 calc_active 的规矩数一遍, 不用 raw_counts。
	var counts: Dictionary = {}
	var seen: Dictionary = {}
	for it in _team_equips_for_synergy():
		if not (it is Dictionary):
			continue
		var iid := str((it as Dictionary).get("id", ""))
		if seen.has(iid):
			continue
		seen[iid] = true
		for t in host.Phase2Types.types_of(iid):
			if host.Phase2Types.TYPES.has(t):
				counts[t] = int(counts.get(t, 0)) + 1
	var tier_of: Dictionary = {}
	for a in active:
		tier_of[str(a.get("type", ""))] = int(a.get("tier", 0))
	## 排序: 已开启的在前(档高优先), 然后按件数多的在前
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b):
		var ta: int = int(tier_of.get(a, 0)); var tb: int = int(tier_of.get(b, 0))
		if ta != tb:
			return ta > tb
		return int(counts[a]) > int(counts[b]))
	if keys.is_empty():
		var e = Label.new(); e.text = "还没有羁绊。\n给同一只龟 / 小将装多件同类型装备就会开启。"
		e.add_theme_font_size_override("font_size", 17); e.add_theme_color_override("font_color", Color("#6c7d8e"))
		e.position = Vector2(x0, cy); e.size = Vector2(w, 60); e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; host.add_child(e)
		return
	## ★不写"强度 铜→银→金→钻石"这类图例(用户 2026-08-15:「不要用文字写强度铜银什么的去掉啊,
	##   我是说羁绊框和本体的颜色可以去变」)。颜色本身就是信号, 再配一行说明反而是啰嗦。
	##   ⇒ 档位色**同时上到框(底色+描边)和本体(图标+名字+件数)**上, 一眼分得出强弱。
	## 列表放进滚动区: 10 个类型全有件数时一屏放不下(要 660px, 这一列只有约 230px)。
	var list_h: float = host.SYN_BOTTOM - 8.0 - cy
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(x0, cy)
	scroll.custom_minimum_size = Vector2(w, list_h); scroll.size = Vector2(w, list_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	host.add_child(scroll)
	var inner = Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.custom_minimum_size = Vector2(w - 4.0, float(keys.size()) * (SYN_ROW_H + 10.0))
	scroll.add_child(inner)
	var y := 0.0
	for t in keys:
		var typ := str(t)
		var n: int = int(counts[typ])
		var tier: int = int(tier_of.get(typ, 0))
		var on: bool = tier > 0
		var col: Color = _tier_color(typ, tier)
		var chip = Panel.new()
		var csb = StyleBoxFlat.new()
		## 框: 底色按档位色压暗(0.16→0.22 更看得出来), 描边直接用档位色。
		csb.bg_color = Color(col.r * 0.30, col.g * 0.30, col.b * 0.32, 0.95) if on else Color("#10161f")
		## 未激活压到 #333c47 —— 原来用同一个 col 只是变暗, 与"银"几乎分不开(实拍确认)。
		csb.border_color = col if on else Color("#333c47")
		csb.set_border_width_all(3 if on else 2); csb.set_corner_radius_all(8)
		chip.add_theme_stylebox_override("panel", csb)
		chip.position = Vector2(0, y); chip.size = Vector2(w - 8.0, SYN_ROW_H)
		chip.tooltip_text = "点开看这个羁绊每一档给什么"
		inner.add_child(chip)
		var nm = Label.new()
		nm.text = "%s %s" % [host.Phase2Types.emoji_of(typ), _syn_name(typ)]
		nm.add_theme_font_size_override("font_size", 20)
		nm.add_theme_color_override("font_color", col)           # 名字 = 当前档位色
		nm.position = Vector2(14, 0); nm.size = Vector2(150, SYN_ROW_H)
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE; chip.add_child(nm)
		## 进度只有两个数: 现在几件 / 下一档要几件(到顶就是"已满")。不写"档"。
		var cnt = Label.new()
		cnt.text = "%d 件" % n
		cnt.add_theme_font_size_override("font_size", 20)
		## 件数也吃档位色(本体跟着变) —— 未激活才用灰。
		cnt.add_theme_color_override("font_color", col if on else Color("#8a97a8"))
		cnt.position = Vector2(w - 8.0 - 34.0 - 200.0, 0); cnt.size = Vector2(80, SYN_ROW_H)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE; chip.add_child(cnt)
		var nxt = Label.new()
		nxt.text = _next_tier_text(typ, n)
		nxt.add_theme_font_size_override("font_size", 16)
		nxt.add_theme_color_override("font_color", Color("#8ef0ff") if nxt.text == "已满" else Color("#7f8fa0"))
		nxt.position = Vector2(w - 8.0 - 34.0 - 116.0, 0); nxt.size = Vector2(116, SYN_ROW_H)
		nxt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		nxt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nxt.mouse_filter = Control.MOUSE_FILTER_IGNORE; chip.add_child(nxt)
		var arw = Label.new(); arw.text = "›"
		arw.add_theme_font_size_override("font_size", 22)
		arw.add_theme_color_override("font_color", col if on else Color("#4a5766"))
		arw.position = Vector2(w - 8.0 - 24.0, 0); arw.size = Vector2(18, SYN_ROW_H)
		arw.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		arw.mouse_filter = Control.MOUSE_FILTER_IGNORE; chip.add_child(arw)
		chip.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _show_synergy_popup(typ, tier))
		y += SYN_ROW_H + 10.0

## 羁绊详情弹框：**该类型的全部档位**逐条列出，当前档高亮。点暗幕/关闭 关。
##
## ★★2026-08-04 重写。原来这里有两个都会让玩家【看不到已经写好的内容】的毛病：
##   ① `for ti in [1, 2, 3]` —— **档数写死成 3**。而奇械/法器/灵物/遗物是 `[2,5,8,10]`
##      四档 ⇒ **这四个类型的顶档在背包里根本不画**。
##   ② 每档一个**固定 66px** 的 Label（620 宽 · 14 号字 ≈ 每行 40 字 · 约容 3 行 = 120 字），
##      而逐类型评审后文案变长了：盾档1 209 字、弓箭三档 189/163/164、遗物 147/124/160…
##      ⇒ **10 个类型里 6 个被截断**。
##   ⇒ 现在：档数读 `TIER_DESCS` 的真实长度；文案放 RichTextLabel + 滚动，
##      框高按内容算并钳在视口内（同图鉴详情那边的做法）。
##
## ⚠ 别再写死任何"3 档" —— `TYPES` 里两种档制并存（`[3,6,9]` 与 `[2,5,8,10]`），
##   写死一个就等于把另一种的最后一档藏起来，而且【不报错、不留痕】。
func _show_synergy_popup(type_key: String, cur_tier: int) -> void:
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: dim.queue_free())
	host.add_child(dim)

	var descs: Array = host.Phase2Types.TIER_DESCS.get(type_key, [])
	var thresh: Array = (host.Phase2Types.TYPES.get(type_key, {}) as Dictionary).get("tiers", [])
	# 拼一段 bbcode：每档一小节，当前档高亮。★档数来自数据，不是写死的 [1,2,3]。
	var bb := ""
	for i in range(descs.size()):
		var txt: String = str(descs[i])
		if txt.strip_edges() == "":
			continue
		var th: int = int(thresh[i]) if i < thresh.size() else 0
		## 档号用【颜色】表示, 不写"档1/档2"(用户 2026-08-15) —— 与右侧按钮同一套色。
		var tcol: String = "#" + _tier_color(type_key, i + 1).to_html(false)
		var col: String = "#e8f2ff" if (i + 1) == cur_tier else "#8a97a8"
		var mark: String = "  ◀ 现在这档" if (i + 1) == cur_tier else ""
		bb += ("" if bb == "" else "

") + "[color=%s][b]%d 件[/b][/color][color=%s]%s[/color]\n[color=%s]%s[/color]" % [
			tcol, th, tcol, mark, col, txt]

	var bw := 620.0
	# 框高按内容估：每档标题 + 文案行数。估多了下面 minf 会钳住，估少了 RichTextLabel 自己能滚。
	var body_h: float = 0.0
	for d in descs:
		body_h += 26.0 + ceilf(float(str(d).length()) / 38.0) * 20.0
	# ⚠ 上限用设计框高 `host.H`（1280×720 的那个 720），**不是 `host._vh`** ——
	#   InventoryScene 上【没有 `_vh` 这个字段】（只有 `_vw`），写 `_vh` 会恒为 0
	#   ⇒ maxf 兜到 280、每个类型的框都一样矮，等于白改。
	#   本屏是"内容锁 1280×720 居中"的设计框口径（`_rebuild` 注释），所以按 H 算才对得上。
	var bh: float = clampf(body_h + 130.0, 260.0, host.H - 120.0)

	var box = Panel.new()
	var sb = StyleBoxFlat.new(); sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ffd93d")
	sb.set_border_width_all(3); sb.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(host._vw / 2.0 - bw / 2.0, maxf(24.0, host.H / 2.0 - bh / 2.0))
	box.size = Vector2(bw, bh)
	box.mouse_filter = Control.MOUSE_FILTER_STOP   # 框内不穿透关闭
	dim.add_child(box)

	var ttl = Label.new()
	## ★标题里也不写"档" —— 每一段本来就以【N 件】开头, 强弱看颜色。
	##   cur_tier 可能是 0(未开启的羁绊现在也能点开看), 那就直接说还没开启。
	ttl.text = "%s %s%s" % [host.Phase2Types.emoji_of(type_key), _syn_name(type_key),
		"   还没开启" if cur_tier <= 0 else ""]
	ttl.add_theme_font_size_override("font_size", 24)
	ttl.add_theme_color_override("font_color", _tier_color(type_key, cur_tier))
	ttl.position = Vector2(24, 18); ttl.size = Vector2(bw - 48, 34); box.add_child(ttl)

	# ★RichTextLabel + 滚动：文案再长也不会被吃掉（原来是固定 66px 的 Label，直接截断）
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = false
	rt.scroll_active = true
	rt.add_theme_font_size_override("normal_font_size", 15)
	rt.add_theme_font_size_override("bold_font_size", 15)
	rt.position = Vector2(24, 62)
	rt.size = Vector2(bw - 48, bh - 62 - 62)
	rt.text = bb
	box.add_child(rt)

	var ok = Button.new(); ok.text = "关闭"; ok.add_theme_font_size_override("font_size", 18)
	ok.position = Vector2(bw / 2.0 - 60, bh - 52); ok.size = Vector2(120, 40)
	ok.pressed.connect(func(): dim.queue_free())
	box.add_child(ok)


## 阵容玩法帮助弹窗 (把原来常驻的教程字收到这·按需看)
