extends Control
## settle_screen.gd — 战后结算屏【三页】: 战果 / 我方 / 敌方 (2026-10-04)
##
## 方案书: docs/plans/20261004-结算屏重做.md (用户 2026-10-04:「行啊，做做看，别搞出ai味的就行」)
##
## ═══ 为什么从「一张卡」改成「三页」═══
## 旧版把 胜负/后果/比分/奖励/两队战报/按钮 六样东西竖着塞进一张居中卡片:
##   · 表格排最后分高度, 实测只拿到屏高 23%(165px), 合计页 16 行首屏只见 10 行;
##   · 两队并排 ⇒ 一行 10 格, 字号放不大(13px = 手机上 7pt, iOS 最小线 11pt);
##   · 卡片按内容宽居中, 手机 1560 宽的视口左右空着 31%。
## ⇒ 横屏多的是【宽】, 缺的是【高】: 页签竖着放左边(只吃宽), 一队一页(行宽减半, 字能放大),
##   按钮钉在右下角(三页同一个位置, 永远在滚动区外面)。
##
## ═══ 只用项目现成的皮(用户:「别搞出ai味」)═══
##   · 正文底板 = 战斗信息面板那块九宫格金属框 `battlehud/panel-frame.png`
##   · 页签 / 分路切换 / 主按钮 = `UISkin.button()` 的木牌(`menu/frame-rect.png`), 与对阵图页签同一套
##   · 各路胜负 = 槽框 `slot-frame.png`; 表头 / MVP = 签牌 `chip-frame.png`
##   · 不新增任何素材; 不用圆角卡片/渐变/阴影/emoji 当图标
##
## ═══ 放这里的理由(CLAUDE.md §5)═══
## 结算屏不在 `_sim_step` 调用链上 ⇒ 不进主文件; `battle_hud.gd` 已 2994 行(上限 3000),
## 也放不下 ⇒ 单独一个文件。入口仍是 `battle_hud._show_banner()`(三个调用点不动),
## 按钮怎么长(教学导演 / 淘汰锁商店)仍在 `battle_hud._settle_buttons()`。
##
## ★本节点自己就是结算屏的根(全屏 Control, 吃掉点击不让它漏到底下的战场),
##   做成 Control 而不是 RefCounted 是因为要收【左右滑动】的输入(`_input`)。

const SPRITE_ROOT := "res://assets/sprites/"

## ── 尺寸表(逻辑 px)。手机横屏逻辑高恒为 720 ⇒ 1 逻辑 px = 390/720 = 0.542 pt ──
## ★这是这一屏字号的【唯一出处】, 门禁量的是渲染后 Label 的真实字号, 不读这张表。
const PT_PER_PX := 390.0 / 720.0      # iPhone 横屏高 390pt ÷ 720(info_panel.gd「44pt = 81px」同一条线)
const F_RESULT := 84       # 胜负大字            45.5pt
const F_RAIL := 40         # 左栏顶上的胜负        21.7pt
const F_TAB := 30          # 页签                16.3pt
const F_TEAM := 34         # 我方 / 敌方 标题      18.4pt
const F_SUB := 24          # 后果一句            13.0pt
const F_NAME := 22         # 表格名字            11.9pt (iOS 最小 11pt)
const F_NUM := 24          # 表格数字            13.0pt
const F_HEAD := 20         # 表头                10.8pt (表头允许略小于正文)
const F_CAP := 18          # 标签 / 小注          9.8pt
const F_SEG := 22          # 分路切换            11.9pt
const F_REWARD := 34       # 奖励数值            18.4pt
const F_LANE := 40         # 各路胜负            21.7pt
const F_BTN := 28          # 主按钮              15.2pt

const RAIL_W := 220.0
const TAB_H := 88.0                    # ≥ 81 = 44pt 触控线
const SEG_SIZE := Vector2(118, 81)
const BTN_SIZE := Vector2(240, 84)
const ROW_H := 42.0                    # 头像 40 + 2px 呼吸(8 行 + 表头正好落在页体里, 见门禁 verify_settle_pages)
const NAME_W := 320.0
const NUM_W := 124.0
const SWIPE_MIN := 110.0               # 横向移动超过这么多(逻辑 px)才算翻页

const PAGE_NAMES := ["战果", "我方", "敌方"]
## 表底「下面还有几只」—— 只有召唤物多到一页放不下时才出现(见 `_refresh_more`)。
## ★抽成常量: 门禁拿同一份格式串算「屏上该写的那句」, 不在测试里抄第二份。
const MORE_FMT := "▼ 还有 %d 只在下面 · 可上下滑动"

const COL_GOLD := Color("#ffd93d")
const COL_LOSS := Color("#ff6b6b")
const COL_DIM := Color("#7d8b9c")
const COL_SUB := Color("#9fb3c8")
const COL_ZERO := Color("#4e5b68")

var battle
var hud
var pages: Array = []                  # [Control] × 3
var tab_btns: Array = []               # 左栏三个页签
var btn_row: HBoxContainer             # 主按钮行 —— 由 battle_hud._settle_buttons() 往里放按钮
var more_hint: Label
var cur_page := 0
var _scrolls: Array = [null, null]     # 我方/敌方 各一个滚动区
var _grids: Array = [[], []]           # 我方/敌方 各自的分路表(合计/上路/下路…)
var _segs: Array = [[], []]            # 我方/敌方 各自的分路切换钮
var _sw_from := Vector2.ZERO
var _sw_on := false


## 建整屏。★调用前必须已经挂进树(要读真实视口尺寸和安全区)。
func build(b, h, won: bool, sealed: bool) -> void:
	battle = b
	hud = h
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP            # 结算是模态的: 点空白处不许漏到底下的战场
	## ★压在同层所有东西上面: 结算后战场上还会冒出飘字/提示(它们后入树 ⇒ 默认画在上面),
	##   实拍里就有一个伤害数字压在「我方」页签上。
	z_index = 50
	var gs = battle.get_node_or_null("/root/GameState")
	var views: Array = lane_views()

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.035, 0.06, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.92, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var sm: Vector4 = SafeArea.margins(vp, 6.0)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## ★左右边距相等 ⇒ 左栏 + 正文这一整组在真实视口里居中(verify_ui_layout ⑥ 量的就是它)
	m.add_theme_constant_override("margin_left", int(sm.x + 14))
	m.add_theme_constant_override("margin_right", int(sm.z + 14))
	m.add_theme_constant_override("margin_top", int(sm.y + 10))
	m.add_theme_constant_override("margin_bottom", int(sm.w + 10))
	add_child(m)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	m.add_child(hb)

	## ── 左栏: 胜负 + 三个页签 + 翻页提示 ──
	var rail := VBoxContainer.new()
	rail.custom_minimum_size = Vector2(RAIL_W, 0)
	rail.add_theme_constant_override("separation", 12)
	hb.add_child(rail)
	var word := _lbl("已封存" if sealed else ("胜利" if won else "失败"), F_RAIL,
		COL_SUB if sealed else (COL_GOLD if won else COL_LOSS), HORIZONTAL_ALIGNMENT_CENTER)
	word.custom_minimum_size = Vector2(0, 64)
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rail.add_child(word)
	for i in range(PAGE_NAMES.size()):
		var tb := _plank_btn(str(PAGE_NAMES[i]), Vector2(RAIL_W, TAB_H), F_TAB)
		var idx := i
		tb.pressed.connect(func() -> void: show_page(idx))
		rail.add_child(tb)
		tab_btns.append(tb)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_child(gap)
	var pager := _lbl("← 滑动翻页 →", F_CAP, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	pager.name = "Pager"
	rail.add_child(pager)

	## ── 右边: 金属框 = 页体 + 底部按钮行 ──
	var frame := PanelContainer.new()
	frame.name = "SettleFrame"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", frame_style())
	hb.add_child(frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	frame.add_child(col)
	var body := Control.new()
	body.name = "SettleBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.clip_contents = true          # 页内容万一比页体高也不许画到按钮上(门禁另量「放得下」)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(body)
	pages.append(_page_result(won, sealed, gs, views))
	pages.append(_page_team(0, "我方", Color("#7ec8ff"), views, "left"))
	pages.append(_page_team(1, "敌方", Color("#ff9a9a"), views, "right"))
	for p in pages:
		(p as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		body.add_child(p)

	## ★按钮行在页体【外面】: 三页同一个位置, 内容再长也顶不走它(用户 2026-08-12「我手机是钮点不到」)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 20)
	col.add_child(foot)
	more_hint = _lbl("", F_CAP + 2, COL_GOLD)
	more_hint.name = "SettleMoreHint"
	more_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	more_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(more_hint)
	btn_row = HBoxContainer.new()
	btn_row.name = "SettleButtons"
	btn_row.add_theme_constant_override("separation", 20)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	foot.add_child(btn_row)
	hud._banner_fade_in(foot, 0.5)
	## ★默认停在「战果」, 不自动翻页(方案书 U2): 玩家先看的是输赢和奖励, 而按钮就在这一页。
	show_page(0)


## 各路战报(与旧版 `_build_stats_panel` 同口径): 已打完的路走 `_st_lane_hist` 快照,
## 当前路读活的 `_units`。多于一路时最前面加一份「合计」。
## 返回 [{lane, title, left:[row], right:[row]}], 第 0 个是默认显示的那份。
func lane_views() -> Array:
	var lanes: Array = []
	for snap in battle._st_lane_hist:
		lanes.append({"lane": snap["lane"], "title": battle._LANE_CN.get(snap["lane"], str(snap["lane"])),
			"left": snap["left"], "right": snap["right"]})
	var cur := {"lane": "cur", "title": "", "left": [], "right": []}
	for u in battle._units:
		## 按【有效阵营】归栏 —— 归顺的龟在打原队, 战绩记在我方(全工程判敌我一律走 _eff_side)
		var sd = battle._eff_side(u)
		if sd == "left" or sd == "right":
			(cur[sd] as Array).append(battle._st_row(u))
	if not ((cur["left"] as Array).is_empty() and (cur["right"] as Array).is_empty()):
		var cl := str(GameState.current_lane) if GameState != null else ""
		cur["title"] = battle._LANE_CN.get(cl, "本场") if not lanes.is_empty() else "本场"
		lanes.append(cur)
	if lanes.size() > 1:
		return [{"lane": "all", "title": "合计",
			"left": hud._st_merge_all(lanes, "left"), "right": hud._st_merge_all(lanes, "right")}] + lanes
	return lanes


## 翻到第 i 页(越界就夹住: 第 1 页再往右滑不动, 第 3 页再往左滑不动)。
func show_page(i: int) -> void:
	cur_page = clampi(i, 0, pages.size() - 1)
	for k in range(pages.size()):
		(pages[k] as Control).visible = (k == cur_page)
	_mark(tab_btns, cur_page)
	_refresh_more.call_deferred()


## 我方/敌方页里切到第 k 份分路表。
func show_view(team: int, k: int) -> void:
	var gs: Array = _grids[team]
	for j in range(gs.size()):
		(gs[j] as Control).visible = (j == k)
	_mark(_segs[team], k)
	if _scrolls[team] != null:
		(_scrolls[team] as ScrollContainer).scroll_vertical = 0
	_refresh_more.call_deferred()


## ── 左右滑动翻页 ─────────────────────────────────────────────
## 手机上触摸会被引擎翻成鼠标事件(emulate_mouse_from_touch 默认开), 所以只认鼠标左键一种,
## 不然一次滑动会被触摸 + 模拟鼠标各算一次。
## ★判成翻页就把这次松手吃掉: 否则从页签上起手的一次滑动, 松手时还会顺带点中那个页签。
func _input(e: InputEvent) -> void:
	if not is_visible_in_tree() or not (e is InputEventMouseButton):
		return
	var mb := e as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_sw_from = mb.position
		_sw_on = true
		return
	if not _sw_on:
		return
	_sw_on = false
	var d: Vector2 = mb.position - _sw_from
	if absf(d.x) >= SWIPE_MIN and absf(d.x) > absf(d.y) * 1.5:
		show_page(cur_page + (1 if d.x < 0.0 else -1))
		get_viewport().set_input_as_handled()


## ── 第 1 页「战果」: 胜负 / 后果 / 各路 / 奖励 / 我方 MVP。★这一页没有任何逐单位的表。
func _page_result(won: bool, sealed: bool, gs, views: Array) -> Control:
	var v := VBoxContainer.new()
	v.name = "PageResult"
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 16)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## ① 胜负。★封存(周日决赛)时不宣布胜负 —— 两边各打对方快照, 两边都可能算出自己赢;
	##   由对阵图在下一轮开播时揭晓(判据在 battle_hud._banner_sealed(), 这里只画)。
	var big := _lbl("结果已封存" if sealed else ("胜利" if won else "失败"), F_RESULT,
		COL_GOLD if won and not sealed else (COL_SUB if sealed else COL_LOSS), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(big)
	big.modulate.a = 0.0
	big.scale = Vector2(1.25, 1.25)
	big.resized.connect(func() -> void: big.pivot_offset = big.size * 0.5)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(big, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.12)
	tw.tween_property(big, "modulate:a", 1.0, 0.30).set_delay(0.12)
	if sealed:
		var ss := _lbl(battle.Phase2Cfg.finals_sealed_sub(), F_CAP + 2, COL_SUB, HORIZONTAL_ALIGNMENT_CENTER)
		ss.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(ss)
	## ② 后果一句
	var sub := _lbl(hud._result_subtitle(won, gs), F_SUB, Color("#93a4b8"), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(sub)
	hud._banner_fade_in(sub, 0.26)
	## ②b 阵容上传成功的一次性提示(隐藏的 Label, 回执到了才亮)
	hud._attach_upload_flash(v)
	var fl: Control = v.get_child(v.get_child_count() - 1)
	if fl is Label:
		(fl as Label).add_theme_font_size_override("font_size", F_CAP + 2)
	## ③ 各路胜负, 一路一块槽框。★封存时不画: 各路胜负加起来就是总胜负。
	var lr = gs.get("lane_results") if gs != null else null
	if not sealed and battle._is_dual_lane_mode() and lr is Dictionary and not (lr as Dictionary).is_empty():
		var row := HBoxContainer.new()
		row.name = "LaneResults"
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 22)
		for ln in ["top", "bottom", "final"]:
			if (lr as Dictionary).has(ln):
				row.add_child(_lane_plate(str(battle._LANE_CN.get(ln, ln)), str(lr[ln])))
		v.add_child(row)
		hud._banner_fade_in(row, 0.34)
	## ④ 奖励块(产品自己的那一排, 只是字号放大)
	var chips: Control = hud._build_reward_chips(gs, F_CAP, F_REWARD)
	if chips != null:
		(chips as HBoxContainer).add_theme_constant_override("separation", 44)
		v.add_child(chips)
		hud._banner_fade_in(chips, 0.42)
	## ⑤ 我方 MVP: 头像 + 名字 + 打出(默认那份 = 合计 / 单路时的本场)
	var mine: Array = (views[0] as Dictionary)["left"] if not views.is_empty() else []
	var mi: int = hud._st_mvp_index(mine)
	if mi >= 0:
		var r: Dictionary = mine[mi]
		var mv := HBoxContainer.new()
		mv.name = "MvpRow"
		mv.alignment = BoxContainer.ALIGNMENT_CENTER
		mv.add_theme_constant_override("separation", 14)
		var tag := _mvp_tag("本场 MVP", F_CAP + 2)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mv.add_child(tag)
		mv.add_child(avatar(r, 64.0))
		var nm := _lbl(battle._st_name(r), F_TEAM - 4, Color("#ffffff"))
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mv.add_child(nm)
		var dl := _lbl("打出 %d" % int(r.get("_st_dealt", 0)), F_TEAM - 4, COL_GOLD)
		dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mv.add_child(dl)
		v.add_child(mv)
		hud._banner_fade_in(mv, 0.50)
	return v


## 一路的胜负牌: 槽框 + 路名(小字) + 胜/负(大字)。
func _lane_plate(lane_cn: String, who: String) -> Control:
	var box := PanelContainer.new()
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(0.08, 0.12, 0.18, 0.95)        # 直角不描边(贴图缺失时的兜底)
	fb.content_margin_left = 30; fb.content_margin_right = 30
	fb.content_margin_top = 10; fb.content_margin_bottom = 12
	var sb := UISkin.slot(fb, Color("#ffe7a0") if who == "left" else Color("#c9d3de"), who != "left")
	if sb is StyleBoxTexture:
		var st := sb as StyleBoxTexture
		st.content_margin_left = 30; st.content_margin_right = 30
		st.content_margin_top = 12; st.content_margin_bottom = 14
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 0)
	box.add_child(bv)
	bv.add_child(_lbl(lane_cn, F_CAP + 2, COL_SUB, HORIZONTAL_ALIGNMENT_CENTER))
	var res := "胜" if who == "left" else ("负" if who == "right" else "平")
	bv.add_child(_lbl(res, F_LANE, COL_GOLD if who == "left" else COL_LOSS, HORIZONTAL_ALIGNMENT_CENTER))
	return box


## ── 第 2/3 页: 一队一页。右上角切 合计/上路/下路; 表放在滚动区里 ——
##   8 行放得下就**不会**出现可滚的量; 召唤物多到放不下时才能滚, 并在按钮行左边写「还有 N 只」。
func _page_team(team: int, title: String, hc: Color, views: Array, side: String) -> Control:
	var v := VBoxContainer.new()
	v.name = "PageTeam%d" % team
	v.add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.custom_minimum_size = Vector2(0, SEG_SIZE.y)
	v.add_child(head)
	var t := _lbl(title, F_TEAM, hc)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	if views.size() > 1:                         # 只有一路就没有可切的
		for k in range(views.size()):
			var sb := _plank_btn(str(views[k]["title"]), SEG_SIZE, F_SEG)
			var kk := k
			sb.pressed.connect(func() -> void: show_view(team, kk))
			head.add_child(sb)
			(_segs[team] as Array).append(sb)
	var sc := ScrollContainer.new()
	sc.name = "TeamScroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	_scrolls[team] = sc
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(holder)
	for k in range(views.size()):
		var g := team_grid(battle, hud, views[k][side], "", hc)
		g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		holder.add_child(g)
		(_grids[team] as Array).append(g)
	if views.is_empty():
		holder.add_child(_lbl("这一场没有留下战报", F_SUB, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	## 溢出与否变了 / 玩家滑了 / 重排了 ⇒ 重写「还有 N 只」。包 call_deferred: 信号在排版中途发。
	var bar := sc.get_v_scroll_bar()
	bar.changed.connect(func() -> void: _refresh_more.call_deferred())
	bar.value_changed.connect(func(_x: float) -> void: _refresh_more.call_deferred())
	sc.resized.connect(func() -> void: _refresh_more.call_deferred())
	show_view(team, 0)
	return v


## 一队一张表: 5 列(名字 / 打出 / 扛住 / 治疗 / 击杀)。
## ★列名是用户定过的(2026-08-02 去掉暴击与剩余血量; 2026-09-28 改成主动语态短动词,
##   **不能退回「出伤 / 承伤」**); 零值印「·」(2026-10-02); MVP 按单位认(2026-09-29, 走 `_st_mvp_index`)。
## ★结构契约(门禁按它数格子): 表头 = 1 个 Label + 4 块栏牌; 每行 = 名字格(HBoxContainer) + 4 个数值 Label。
## static: `battle_hud._stats_column()` 委托到这里, 测试可以拿替身 battle 直接建一张。
static func team_grid(b, h, rows: Array, header: String, hc: Color) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	var hdrs := [header, "打出", "扛住", "治疗", "击杀"]
	for i in range(5):
		var l := _lbl(str(hdrs[i]), F_HEAD, hc if i == 0 else COL_GOLD,
			HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT)
		if i == 0:
			l.custom_minimum_size = Vector2(NAME_W, 0)
			grid.add_child(l)
			continue
		l.custom_minimum_size = Vector2(NUM_W - 8.0, 0)   # + 栏牌左右内边距 4+4 = NUM_W, 与数值格对齐
		grid.add_child(hdr_plate(l))
	var mvp_i: int = h._st_mvp_index(rows)
	for ri in range(rows.size()):
		var u: Dictionary = rows[ri]
		var dead: bool = not bool(u.get("alive", true))
		var is_sm: bool = bool(u.get("is_summon", false))
		var is_mvp: bool = ri == mvp_i and not is_sm
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		cell.custom_minimum_size = Vector2(NAME_W, ROW_H)
		var av := avatar(u, 40.0)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(av)
		var nm := _lbl(("└ " if is_sm else "") + b._st_name(u), F_NAME,
			Color("#888888") if dead else (Color("#cdd9c2") if is_sm else Color("#ffffff")))
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(nm)
		if dead:
			var dl := _lbl("阵亡", F_CAP, COL_DIM)
			dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cell.add_child(dl)
		if is_mvp:
			var tg := _mvp_tag("MVP", F_CAP)
			tg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cell.add_child(tg)
		grid.add_child(cell)
		var raw := [int(u.get("_st_dealt", 0)), int(u.get("_st_taken", 0)), int(u.get("_st_heal", 0)), int(u.get("_st_kills", 0))]
		for i in range(4):
			var c := _lbl(h.settle_cell_text(raw[i]), F_NUM,
				COL_ZERO if raw[i] == 0 else (Color("#888888") if dead else (COL_GOLD if is_mvp else Color("#e8f0f6"))),
				HORIZONTAL_ALIGNMENT_RIGHT)
			c.custom_minimum_size = Vector2(NUM_W, 0)
			c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			grid.add_child(c)
	return grid


## 单位头像: 统领用 avatars/<id>, 没有就退回全身图; 小将统一 minion; 召唤体不画(留空位对齐)。
static func avatar(r: Dictionary, sz: float) -> Control:
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(sz, sz)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var id := str(r.get("id", ""))
	var p := ""
	if bool(r.get("is_summon", false)):
		p = ""
	elif bool(r.get("_st_multi", false)):
		p = SPRITE_ROOT + "pets/minion.png"
	elif id != "":
		p = SPRITE_ROOT + "avatars/" + id + ".png"
		if not ResourceLoader.exists(p):
			p = SPRITE_ROOT + "pets/" + id + ".png"
	if p != "" and ResourceLoader.exists(p):
		tr.texture = load(p)
	return tr


## 表头栏牌(签牌九宫格 chip-frame, 偏金) —— 一行金色裸字压着几列数字就是 `<th>` 的长相。
static func hdr_plate(l: Label) -> Control:
	var box := PanelContainer.new()
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(0.16, 0.20, 0.27, 0.55)
	fb.content_margin_left = 4; fb.content_margin_right = 4
	fb.content_margin_top = 1; fb.content_margin_bottom = 1
	var sb := UISkin.nine("chip-frame.png", 7, fb)
	if sb is StyleBoxTexture:
		var st := sb as StyleBoxTexture
		st.modulate_color = Color(0.86, 0.80, 0.62)
		st.content_margin_left = 4; st.content_margin_right = 4
		st.content_margin_top = 2; st.content_margin_bottom = 2
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	return box


## MVP 金签牌(与排行榜「你」那块同一种做法: chip-frame 染金 + 深色字)。
static func _mvp_tag(text: String, fs: int) -> Control:
	var box := PanelContainer.new()
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(0.45, 0.34, 0.08, 1.0)
	fb.content_margin_left = 8; fb.content_margin_right = 8
	var sb := UISkin.nine("chip-frame.png", 7, fb)
	if sb is StyleBoxTexture:
		var st := sb as StyleBoxTexture
		st.modulate_color = Color(1.0, 0.86, 0.38)
		st.content_margin_left = 8; st.content_margin_right = 8
		st.content_margin_top = 1; st.content_margin_bottom = 1
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_lbl(text, fs, Color("#ffe9a8")))
	return box


## 结算屏底板 = 战斗信息面板那块九宫格金属框(深蓝金属 + 青内沿 + 四角铆钉)。
## 内边距: 框艺术约 14px 厚, 上下 30/32、左右 34。贴图缺失时退回直角细边的兜底。
static func frame_style() -> StyleBox:
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(0.035, 0.055, 0.085, 0.94)
	fb.border_color = Color(0.28, 0.44, 0.62, 0.50)
	fb.set_border_width_all(2)
	fb.set_corner_radius_all(0)
	fb.content_margin_left = 34; fb.content_margin_right = 34
	fb.content_margin_top = 22; fb.content_margin_bottom = 24
	var sb := UISkin.nine("panel-frame.png", 20, fb)
	if sb is StyleBoxTexture:
		var st := sb as StyleBoxTexture
		st.content_margin_left = 34; st.content_margin_right = 34
		st.content_margin_top = 28; st.content_margin_bottom = 28
	return sb


## 木牌按钮(页签 / 分路切换): 走共享皮层 `UISkin.button()`, 不在这里手写 StyleBox。
## 左边那条竖杠 `Mark` 是选中态 —— 选中不能只靠字色(那是网页 tab 的做法)。
func _plank_btn(text: String, sz: Vector2, fs: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = sz
	b.add_theme_font_size_override("font_size", fs)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UISkin.button(b)
	var mk := ColorRect.new()
	mk.name = "Mark"
	mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mk.color = COL_GOLD
	mk.position = Vector2(8, 10)
	mk.size = Vector2(5, sz.y - 20.0)
	b.add_child(mk)
	return b


## 一组木牌里第 sel 个点亮, 其余压暗。
func _mark(btns: Array, sel: int) -> void:
	for k in range(btns.size()):
		var b: Button = btns[k]
		var on := k == sel
		UISkin.button(b, Color.WHITE if on else Color(0.58, 0.62, 0.68))
		var fc := Color("#ffe7a0") if on else Color("#9fb3c8")
		for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(s, fc)
		var mk := b.get_node_or_null("Mark")
		if mk != null:
			(mk as CanvasItem).visible = on


## 当前队伍页里, 有几行压在可视区下面 ⇒ 写到按钮行左边; 一行都没压 ⇒ 清空。
## ★比的是【内容坐标】: 行的局部 position 累加 vs 滚动条自己的 value + page ——
##   两边同一套坐标、与跨帧排版无关(2026-09-29 用 global rect 比 clip 时量出过全错的数)。
func _refresh_more() -> void:
	if more_hint == null or not is_instance_valid(more_hint):
		return
	var below := 0
	if cur_page >= 1 and cur_page <= 2 and _scrolls[cur_page - 1] != null:
		var sc: ScrollContainer = _scrolls[cur_page - 1]
		var content: Control = sc.get_child(0)
		var bar: VScrollBar = sc.get_v_scroll_bar()
		var fold: float = bar.value + bar.page
		for g in _grids[cur_page - 1]:
			if not (g as Control).visible:
				continue
			for ch in (g as Node).get_children():
				if ch is HBoxContainer and local_bottom(ch as Control, content) > fold + 0.5:
					below += 1
	more_hint.text = (MORE_FMT % below) if below > 0 else ""


## 某一行的下沿在 content 坐标里的 y。
static func local_bottom(row: Control, content: Control) -> float:
	var y: float = row.size.y
	var p: Node = row
	while p != null and p != content and p is Control:
		y += (p as Control).position.y
		p = p.get_parent()
	return y


## 把一个主按钮(`battle._make_result_btn` 建的)换成这一屏的尺寸和木牌皮。
static func dress_btn(b: Button, tint: Color, fc: Color) -> void:
	b.custom_minimum_size = BTN_SIZE
	b.add_theme_font_size_override("font_size", F_BTN)
	UISkin.button(b, tint)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, fc)


static func _lbl(t: String, fs: int, c: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
