extends Node
## verify_settle_pages.gd — 结算屏【三页】门禁 (2026-10-04)
##
## 方案书 docs/plans/20261004-结算屏重做.md §6 验收清单; 用户 2026-10-04「行啊，做做看，别搞出ai味的就行」。
## 结算屏从「一张卡塞六样东西」改成 战果 / 我方 / 敌方 三页(scripts/scenes/battle/settle_screen.gd)。
##
## 两个逻辑视口各跑一遍(1280×720 = 电脑窗口; 1560×720 = 手机 2340×1080 / iPhone 横屏):
##   ① 第 1 页「战果」没有逐单位的表; 胜负 / 后果 / 各路 / 奖励 / MVP(带头像)都在
##   ② 我方/敌方页上 名字与数字的字号 ≥ 11pt —— 量的是渲染后 Label 的真实字号,
##      11pt 是 iOS HIG 的正文下限(外部尺子), **不读** settle_screen 的字号表
##   ③ 合计页 8 行全部在可视区里, 滚动条没有可滚的量, 屏上不出现「还有 N 只」
##   ④ 页签 / 分路切换 / 主按钮 触控高 ≥ 81 逻辑 px(= 44pt)
##   ⑤ 主按钮三页同一个位置, 完整在视口里
##   ⑥ 每一页都到得了: 真点页签(推鼠标事件, 引擎自己命中) + 左右滑动; 竖着拖不翻页
##   ⑦ 召唤物多到一页放不下(每侧 14 行): 只有这时才能滚, 提示数字 = 真看不到的行数, 滚到底最后一行看得见
##   ⑧ 周日封存: 标题「结果已封存」+ 副标题; **各路胜负不画**(各路胜负加起来就是总胜负)
##
## ★数据是合成的「双路 6v6」: 上路/下路两份快照, 合计每侧 8 行(3 统领 + 3 小将 + 龟蛋 + 训龟大师),
##   与方案书 §2.1 实测的真实对局同形(真实对局的实拍走 tests/_probe_settle_real.gd)。
##   合成而不打真对局: 门禁要确定性, 不吃随机阵容(memory fb-make-assertions-rng-insensitive)。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_settle_pages.tscn --quit-after 6000

const SCENE := "res://scenes/RealtimeBattle3D.tscn"
const SS := preload("res://scripts/scenes/battle/settle_screen.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
## ★外部尺子(不是从产品里抄的): iOS HIG 正文最小 11pt; 触控最小 44pt。
##   pt 换算用「横屏逻辑高 720 = 390pt」—— 手机横屏逻辑高恒为 720(project.godot canvas_items + expand)。
const MIN_BODY_PT := 11.0
const MIN_HEAD_PT := 10.0
const TOUCH_PX := 81.0
const PT_PER_PX := 390.0 / 720.0

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] %s%s" % [name, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, detail])


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true                                  # 不许写真存档
	var bak := {"lane_results": gs.lane_results.duplicate(), "dual_active": gs.dual_active,
		"finals_pending_reveal": (gs.finals_pending_reveal as Dictionary).duplicate()}
	for v in [Vector2i(1280, 720), Vector2i(1560, 720)]:
		await _run(v)
	gs.lane_results = bak["lane_results"]
	gs.dual_active = bak["dual_active"]
	gs.finals_pending_reveal = bak["finals_pending_reveal"]
	print("")
	print("  (共 %d 条断言)" % _n)
	print("  (用了 %d 帧)" % Engine.get_process_frames())
	print("ALL PASS — 结算屏三页" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 一行快照(键名与产品 `_st_row` 一致)。
func _row(id: String, nm: String, multi: bool, d: int, t: int, hl: int, k: int, summon := false) -> Dictionary:
	return {"name": nm, "id": id, "is_summon": summon, "_st_multi": multi or summon, "rarity": "C",
		"alive": d % 2 == 0, "hp": 0.0, "maxHp": 100.0,
		"_st_dealt": d, "_st_taken": t, "_st_heal": hl, "_st_crit": 0, "_st_kills": k}


## 合成双路: 上路 = 2 统领 + 1 小将 + 龟蛋 + 大师; 下路 = 1 统领 + 2 小将 + 龟蛋 + 大师
## ⇒ 合计每侧 3 统领 + 3 小将(小将按路分身份) + 龟蛋 + 大师 = 8 行。
func _lane(lane: String, side: String, summons: int) -> Dictionary:
	var rows: Array = []
	var leaders: Array = ["stone", "bamboo"] if lane == "top" else ["hunter"]
	for i in range(leaders.size()):
		rows.append(_row(leaders[i], str(leaders[i]), false, 900 + 111 * i, 700, 0 if i == 0 else 120, i))
	for i in range(3 - leaders.size()):
		rows.append(_row("minion", "小将", true, 300 + 7 * i, 500, 0, 0))
	rows.append(_row("egg", "龟蛋", false, 0, 2200, 0, 0))
	rows.append(_row("trainer", "训龟大师", false, 40, 6, 0, 0))
	for i in range(summons):
		rows.append(_row("_summon_turret", "炮台", false, 60 + i, 30, 0, 0, true))
	return {"lane": lane, side: rows}


func _make_hist(summons: int) -> Array:
	var out: Array = []
	for lane in ["top", "bottom"]:
		var snap := {"lane": lane}
		snap.merge(_lane(lane, "left", summons if lane == "top" else 0))
		snap.merge(_lane(lane, "right", 0))
		out.append(snap)
	return out


func _open(sc, hist: Array, sealed: bool) -> Node:
	var gs = get_node_or_null("/root/GameState")
	if sc._hud._settle != null and is_instance_valid(sc._hud._settle):
		sc._hud._settle.queue_free()
	await get_tree().process_frame
	sc._st_lane_hist = hist
	sc._units.clear()
	gs.dual_active = true
	gs.lane_results = {"top": "right", "bottom": "left"}
	gs.finals_pending_reveal = {"round": 1, "match": 0} if sealed else {}
	sc._settled = false
	sc._hud._show_banner(true)
	## ★只等排版(数帧), 不等淡入 tween: 判据量的全是几何与文字, 与透明度无关;
	##   等墙钟会让无头高帧率下的帧数预算没个准(CLAUDE.md §2 frames_for 那个坑)。
	for _i in range(12):
		await get_tree().process_frame
	return sc._hud._settle


func _run(v: Vector2i) -> void:
	print("── 逻辑视口 %dx%d ──" % [v.x, v.y])
	get_tree().root.content_scale_size = v
	get_tree().root.size = v
	for _q in range(4):
		await get_tree().process_frame
	var sc = load(SCENE).instantiate()
	get_tree().root.add_child(sc)
	for _i in range(30):
		await get_tree().process_frame
	sc.set_process(false)                # 停掉 sim: 名单是这里摆的, 不许它自己打下去
	sc.set_physics_process(false)
	var vp: Vector2 = sc.get_viewport().get_visible_rect().size
	_ok("★分母: 视口真的是 %dx%d" % [v.x, v.y], vp.is_equal_approx(Vector2(v)), str(vp))
	var tag := "%d×%d" % [v.x, v.y]

	var scr = await _open(sc, _make_hist(0), false)
	_ok("[%s] ★分母: 结算屏建出来了, 三页" % tag, scr != null and (scr.pages as Array).size() == 3)
	if scr == null:
		sc.queue_free()
		return
	_ok("[%s] 默认停在第 1 页「战果」(不自动翻页)" % tag, scr.cur_page == 0 and (scr.pages[0] as Control).visible)

	## ── ① 第 1 页 ──
	var p1: Control = scr.pages[0]
	var g1: Array = []
	_collect_cls(p1, "GridContainer", g1)
	_ok("[%s] ① 第 1 页没有逐单位的表(GridContainer=0)" % tag, g1.is_empty(), "grids=%d" % g1.size())
	var t1: Array = _texts(p1, true)
	_ok("[%s] ① 第 1 页写着胜负「胜利」" % tag, t1.has("胜利"), str(t1).substr(0, 160))
	_ok("[%s] ① 后果一句在" % tag, t1.has(sc._hud._result_subtitle(true, get_node("/root/GameState"))))
	var lanes: Node = p1.find_child("LaneResults", true, false)
	_ok("[%s] ① 各路胜负: 两路两块牌" % tag, lanes != null and lanes.get_child_count() == 2)
	var mvp: Node = p1.find_child("MvpRow", true, false)
	var mvp_tex := false
	if mvp != null:
		for c in mvp.get_children():
			if c is TextureRect and (c as TextureRect).texture != null:
				mvp_tex = true
	_ok("[%s] ① 我方 MVP 一行在, 且带这只龟自己的头像" % tag, mvp != null and mvp_tex)
	var p1need: float = p1.get_combined_minimum_size().y
	_ok("[%s] ① 第 1 页内容放得进页体(%.0f ≤ %.0f)" % [tag, p1need, p1.size.y], p1need <= p1.size.y + 0.5)

	## ── ②③ 我方 / 敌方 ──
	var btn_pos: Array = []
	for pi in [1, 2]:
		scr.show_page(pi)
		for _i in range(6):
			await get_tree().process_frame
		var pg: Control = scr.pages[pi]
		var rows: Array = _rows_of(scr, pi)
		_ok("[%s] ★分母: 第 %d 页合计表 8 行" % [tag, pi + 1], rows.size() == 8, "rows=%d" % rows.size())
		var small: Array = []
		var nbody := 0
		for r in rows:
			for l in _labels(r.get_parent(), r):
				nbody += 1
				var pt: float = float((l as Label).get_theme_font_size("font_size")) * PT_PER_PX
				if pt < MIN_BODY_PT - 0.01:
					small.append("「%s」%.1fpt" % [(l as Label).text, pt])
		_ok("[%s] ② 第 %d 页 名字/数字 %d 个, 全部 ≥ %.0fpt" % [tag, pi + 1, nbody, MIN_BODY_PT],
			nbody >= 8 * 5 and small.is_empty(), str(small.slice(0, 6)))
		var hsmall: Array = []
		var g: Control = rows[0].get_parent() if not rows.is_empty() else null
		if g != null:
			for i in range(5):
				for l in _labels_in(g.get_child(i)):
					if float((l as Label).get_theme_font_size("font_size")) * PT_PER_PX < MIN_HEAD_PT:
						hsmall.append((l as Label).text)
		_ok("[%s] ② 第 %d 页 表头 ≥ %.0fpt" % [tag, pi + 1, MIN_HEAD_PT], g != null and hsmall.is_empty(), str(hsmall))
		var hidden := 0
		for r in rows:
			if not _clip_of(r, vp).encloses((r as Control).get_global_rect()):
				hidden += 1
		var bar: VScrollBar = (scr._scrolls[pi - 1] as ScrollContainer).get_v_scroll_bar()
		_ok("[%s] ③ 第 %d 页 8 行全部看得见、没有可滚的量(max %.0f ≤ page %.0f)" % [tag, pi + 1, bar.max_value, bar.page],
			hidden == 0 and bar.max_value <= bar.page + 0.5, "看不到 %d 行" % hidden)
		_ok("[%s] ③ 第 %d 页屏上没有「还有 N 只」" % [tag, pi + 1], str(scr.more_hint.text) == "", str(scr.more_hint.text))
		var segs: Array = scr._segs[pi - 1]
		_ok("[%s] 第 %d 页右上有 合计/上路/下路 三个切换, 默认合计" % [tag, pi + 1],
			segs.size() == 3 and str((segs[0] as Button).text) == "合计" and (scr._grids[pi - 1][0] as Control).visible)
		var short: Array = []
		for b in segs:
			if (b as Control).get_global_rect().size.y < TOUCH_PX:
				short.append((b as Button).text)
		_ok("[%s] ④ 第 %d 页分路切换高 ≥ %.0f" % [tag, pi + 1, TOUCH_PX], short.is_empty(), str(short))
		## 切到「上路」(5 行)再切回来 —— 切换真的换了表
		(segs[1] as Button).pressed.emit()
		for _i in range(4):
			await get_tree().process_frame
		_ok("[%s] 第 %d 页切到上路: 5 行" % [tag, pi + 1], _rows_of(scr, pi).size() == 5, "rows=%d" % _rows_of(scr, pi).size())
		(segs[0] as Button).pressed.emit()
		for _i in range(4):
			await get_tree().process_frame

	## ── ④⑤ 页签与主按钮 ──
	var tshort: Array = []
	for b in scr.tab_btns:
		var r: Rect2 = (b as Control).get_global_rect()
		if r.size.y < TOUCH_PX or r.size.x < TOUCH_PX:
			tshort.append("%s %s" % [(b as Button).text, str(r.size)])
	_ok("[%s] ④ 三个页签都 ≥ %.0f×%.0f" % [tag, TOUCH_PX, TOUCH_PX], (scr.tab_btns as Array).size() == 3 and tshort.is_empty(), str(tshort))
	var mains: Array = scr.btn_row.get_children()
	_ok("[%s] ★分母: 主按钮 2 个(前往商店 / 返回主菜单)" % tag, mains.size() == 2, str(mains.size()))
	var same := true
	var out: Array = []
	var first: Array = []
	for pi in range(3):
		scr.show_page(pi)
		for _i in range(4):
			await get_tree().process_frame
		for k in range(mains.size()):
			var r: Rect2 = (mains[k] as Control).get_global_rect()
			if pi == 0:
				first.append(r)
			elif not r.is_equal_approx(first[k]):
				same = false
			if not (mains[k] as Control).is_visible_in_tree():
				out.append("%s 在第 %d 页看不见" % [(mains[k] as Button).text, pi + 1])
			if r.position.x < 0 or r.position.y < 0 or r.end.x > vp.x or r.end.y > vp.y:
				out.append("%s@%s" % [(mains[k] as Button).text, str(r)])
			if r.size.y < TOUCH_PX:
				out.append("%s 高 %.0f" % [(mains[k] as Button).text, r.size.y])
	_ok("[%s] ⑤ 主按钮三页同一个位置" % tag, same)
	_ok("[%s] ⑤ 主按钮三页都看得见、完整在视口内、高 ≥ %.0f" % [tag, TOUCH_PX], out.is_empty(), str(out))

	## ── ⑥ 每一页都到得了: 真点页签 / 滑动 ──
	scr.show_page(0)
	await get_tree().process_frame
	var reached: Array = []
	for i in [2, 1, 0]:
		var c: Vector2 = (scr.tab_btns[i] as Control).get_global_rect().get_center()
		await _click(c, c)
		reached.append(scr.cur_page == i and (scr.pages[i] as Control).visible)
	_ok("[%s] ⑥ 点页签(引擎命中) 敌方→我方→战果 三页都到得了" % tag, reached == [true, true, true], str(reached))
	var mid := Vector2(vp.x * 0.6, vp.y * 0.45)
	await _click(mid, mid + Vector2(-300, 10))
	var a1: int = scr.cur_page
	await _click(mid, mid + Vector2(-300, -10))
	var a2: int = scr.cur_page
	await _click(mid, mid + Vector2(-300, 0))
	var a3: int = scr.cur_page
	await _click(mid, mid + Vector2(300, 0))
	var a4: int = scr.cur_page
	_ok("[%s] ⑥ 向左滑 → 我方 → 敌方 → 到头不动; 向右滑回我方" % tag, [a1, a2, a3, a4] == [1, 2, 2, 1], str([a1, a2, a3, a4]))
	await _click(mid, mid + Vector2(40, -260))
	_ok("[%s] ⑥ 竖着拖不翻页" % tag, scr.cur_page == 1, str(scr.cur_page))
	await _click(mid, mid + Vector2(-60, 0))
	_ok("[%s] ⑥ 横向挪一点点(< 翻页阈值)不翻页" % tag, scr.cur_page == 1, str(scr.cur_page))

	## ── ⑦ 召唤物多: 我方合计 8 + 6 = 14 行 ──
	scr = await _open(sc, _make_hist(6), false)
	scr.show_page(1)
	for _i in range(8):
		await get_tree().process_frame
	var rows7: Array = _rows_of(scr, 1)
	var hid7 := 0
	for r in rows7:
		if not _clip_of(r, vp).encloses((r as Control).get_global_rect()):
			hid7 += 1
	var bar7: VScrollBar = (scr._scrolls[0] as ScrollContainer).get_v_scroll_bar()
	_ok("[%s] ⑦ ★分母: 召唤物阵容我方合计 14 行, 真的放不下(看不到 %d 行)" % [tag, hid7], rows7.size() == 14 and hid7 > 0)
	_ok("[%s] ⑦ 这时才能滚(max %.0f > page %.0f)" % [tag, bar7.max_value, bar7.page], bar7.max_value > bar7.page + 0.5)
	_ok("[%s] ⑦ 提示数字 = 真看不到的行数" % tag, str(scr.more_hint.text) == SS.MORE_FMT % hid7, "「%s」 vs %d" % [scr.more_hint.text, hid7])
	(scr._scrolls[0] as ScrollContainer).scroll_vertical = int(bar7.max_value)
	for _i in range(6):
		await get_tree().process_frame
	var last: Control = rows7.back()
	_ok("[%s] ⑦ 滚到底: 最后一行看得见, 提示收掉" % tag,
		_clip_of(last, vp).encloses(last.get_global_rect()) and str(scr.more_hint.text) == "", str(scr.more_hint.text))
	scr.show_page(2)
	for _i in range(4):
		await get_tree().process_frame
	_ok("[%s] ⑦ 敌方(8 行)那页不受影响: 不滚、没提示" % tag,
		(scr._scrolls[1] as ScrollContainer).get_v_scroll_bar().max_value <= (scr._scrolls[1] as ScrollContainer).get_v_scroll_bar().page + 0.5
		and str(scr.more_hint.text) == "")

	## ── ⑧ 周日封存 ──
	scr = await _open(sc, _make_hist(0), true)
	var p8: Control = scr.pages[0]
	var t8: Array = _texts(scr, false)
	_ok("[%s] ⑧ 封存: 标题「结果已封存」" % tag, t8.has("结果已封存"))
	_ok("[%s] ⑧ 封存: 副标题逐字在" % tag, str(t8).find(P2C.finals_sealed_sub().split("\n")[0]) >= 0)
	var leak: Array = []
	for t in t8:
		if str(t) in ["胜利", "失败", "胜", "负"]:
			leak.append(t)
	_ok("[%s] ⑧ 封存: 整屏没有 胜利/失败/各路胜负" % tag, leak.is_empty() and p8.find_child("LaneResults", true, false) == null, str(leak))
	var gsx = get_node("/root/GameState")
	gsx.finals_pending_reveal = {}
	sc.queue_free()
	for _i in range(3):
		await get_tree().process_frame


## 推一次真实的鼠标「按下 → 移动 → 松开」, 让引擎自己做命中(页签)与本屏的滑动判定。
func _click(from: Vector2, to: Vector2) -> void:
	var vpt := get_viewport()
	var mm := InputEventMouseMotion.new()
	mm.position = from
	mm.global_position = from
	vpt.push_input(mm)
	var p := InputEventMouseButton.new()
	p.button_index = MOUSE_BUTTON_LEFT
	p.pressed = true
	p.position = from
	p.global_position = from
	vpt.push_input(p)
	await get_tree().process_frame
	var m2 := InputEventMouseMotion.new()
	m2.position = to
	m2.global_position = to
	m2.button_mask = MOUSE_BUTTON_MASK_LEFT
	vpt.push_input(m2)
	var r := InputEventMouseButton.new()
	r.button_index = MOUSE_BUTTON_LEFT
	r.pressed = false
	r.position = to
	r.global_position = to
	vpt.push_input(r)
	for _i in range(3):
		await get_tree().process_frame


## 第 pi 页当前看得见的那张表的行(名字格 HBoxContainer)。
func _rows_of(scr, pi: int) -> Array:
	var out: Array = []
	for g in scr._grids[pi - 1]:
		if not (g as Control).visible:
			continue
		for ch in (g as Node).get_children():
			if ch is HBoxContainer:
				out.append(ch)
	return out


## 一行的全部文字 Label = 名字格里的 + 后面紧跟的 4 个数值格(★「阵亡」「MVP」两个小角标不算正文)。
func _labels(grid: Node, row: Node) -> Array:
	var out: Array = []
	for l in row.get_children():
		if l is Label:
			out.append(l)
			break                       # 名字格里第一个 Label 是名字
	var i: int = row.get_index()
	for j in range(1, 5):
		var c = grid.get_child(i + j)
		if c is Label:
			out.append(c)
	return out


func _labels_in(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append(n)
	for c in n.get_children():
		out += _labels_in(c)
	return out


func _texts(root: Node, visible_only: bool) -> Array:
	var out: Array = []
	for l in _labels_in(root):
		if visible_only and not (l as Control).is_visible_in_tree():
			continue
		if str((l as Label).text).strip_edges() != "":
			out.append(str((l as Label).text))
	return out


func _collect_cls(n: Node, cls: String, out: Array) -> void:
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		_collect_cls(c, cls, out)


## 全部祖先 clip_contents 矩形的交集 —— 玩家真正看得见的那一块。
func _clip_of(c: Control, vp: Vector2) -> Rect2:
	var r := Rect2(Vector2.ZERO, vp)
	var p: Node = c
	while p != null:
		if p is Control and (p as Control).clip_contents:
			r = r.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	return r
