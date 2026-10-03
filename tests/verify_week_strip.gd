extends Node
## verify_week_strip.gd — 赛程条**七天全量** (2026-09-27)
##
## ══════════════════════════════════════════════════════════════════════
##  为什么要这一份
## ══════════════════════════════════════════════════════════════════════
## 赛程条是**玩家每天开游戏第一眼读的那行字** —— 今天是什么日子、这周走到哪了。
## 而它的可注入时钟 `strip_now_override` **全仓只有 1 处引用, 还在截图脚本里**
## ⇒ 它的每日内容**没有任何门禁扫过**, 而本仓「判据挂在星期几上」已经栽过五次
## (v0.19.446 一轮修了四条; v0.19.458 的周日无限刷也是同一族)。
##
## ★判据不是「今天那格对不对」那一格, 而是**七天各有确定答案**:
##   一天一天列会再漏一次 —— v0.19.458 漏的就是四天名单里没有的那一天。
##
## ★★只量**条内**那 7 格(`WeekStrip` 那个容器)。2026-09-27 探针扫全屏时
##   把右侧「今天是什么日子」指示块的标签也数了进来, 凭空多出一格
##   (x=812 vs 条内 x=126) ⇒ **判据宽一格就会造出假 bug**。
##   名字只用来定位, 判据仍是**相位序列**(与 `phase_of_weekday` 这个唯一出处比)。
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const SUN0 := 1789862400          # 2026-09-20 周日 00:00 UTC
## 星期几短名 —— 与产品 `MainMenuScene._WD_CN` 同形。日格靠它认。
const WD_CN := ["一", "二", "三", "四", "五", "六", "日"]
const WD_LONG := ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

var _pass := 0
var _fail := 0


func _ok(nm: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [nm, detail])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [nm, detail])


## 一棵子树里的可读文字(去重, 保序)。
## ★★**Button 也要收**: 周日的收盘块是 `_finals_entry()` 的一个 **Button**,
##   只收 Label 的话周日那一天永远量到空串 —— 那是**假的空值**,
##   会把「两边都是空」当成「两边一致」(memory `fb-gate-subject-never-constructed`)。
## ★去重: 描边文字会把同一句话生成好几份。
func _texts(n: Node) -> Array:
	var out: Array = []
	var st: Array = [n]
	while not st.is_empty():
		var c = st.pop_front()
		var t := ""
		if c is Label:
			t = str((c as Label).text)
		elif c is Button:
			t = str((c as Button).text)
		if t.strip_edges() != "" and not out.has(t):
			out.append(t)
		for ch in c.get_children():
			st.append(ch)
	return out


## 一个控件某个 slot 上挂的九宫格。没挂 / 挂的不是贴图 ⇒ null。
func _nine(c: Control, slot: String) -> StyleBoxTexture:
	if c == null or not c.has_theme_stylebox_override(slot):
		return null
	return c.get_theme_stylebox(slot) as StyleBoxTexture


## 贴图文件名(拿不到 ⇒ 空串)。★判据比**名字**不比“是不是贴图” ——
##   “挂了一张贴图”这种判据会把 `frame-rect.png` 也放过去, 而那张正是上次顶红的。
func _tex_name(sb: StyleBoxTexture) -> String:
	if sb == null or sb.texture == null:
		return ""
	return str(sb.texture.resource_path).get_file()


## 条内每一格的两行字: [星期几, 相位名(可能带「今」)]
func _cells(strip: Node) -> Array:
	var out: Array = []
	for cell in strip.get_children():
		var st: Array = [cell]
		var txt: Array = []
		while not st.is_empty():
			var n = st.pop_front()
			if n is Label and str((n as Label).text).strip_edges() != "":
				txt.append(str((n as Label).text))
			for ch in n.get_children():
				st.append(ch)
		## ★★只认**日格**: 首行是星期几短名。
		##   条里还合法地挂着一个**提示/倒计时块**(「本地 周六 00:00 收盘」+「距收盘 N 天」),
		##   它不是日格。第一版判据没分开, 七天里六天都报「8 格」——
		##   **判据宽一格就会造出假 bug**(与 2026-09-27 探针那次同一个坑)。
		if txt.size() >= 2 and WD_CN.has(str(txt[0])):
			out.append(txt)
	return out


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.season_total_battles = 5
		gs.ranked_used = 5
		gs.hearts = 3
	await get_tree().process_frame
	print("=== 赛程条七天全量 ===")
	var packed = load("res://scenes/MainMenu.tscn")
	_ok("★分母: 载得到 MainMenu.tscn", packed != null)
	if packed == null:
		_done()
		return

	## 唯一出处: 这一周七天各是什么相位
	var want: Array = []
	for wd in range(1, 8):
		want.append(str(P2.PHASE_LABEL.get(str(P2.phase_of_weekday(wd)), "?")))
	_ok("★分母: 七个相位名都取得到(取不到 = 下面全在比 '?')",
		not want.has("?"), str(want))

	var today_marks: Array = []
	for d in range(7):
		## d=0 是周日 ⇒ ISO 星期几 = 7; d=1..6 → 1..6
		var iso: int = 7 if d == 0 else d
		var mm = packed.instantiate()
		var ts: int = SUN0 + d * 86400 + 12 * 3600
		mm.strip_now_override = ts
		mm.clock_override_ts = ts
		add_child(mm)
		for _i in range(6):
			await get_tree().process_frame

		var box = mm.find_child("WeekStrip", true, false)
		_ok("%s ★分母: 赛程条建出来了" % WD_LONG[iso - 1], box != null)
		if box == null:
			mm.queue_free()
			await get_tree().process_frame
			continue
		var hb = null
		for c in box.get_children():
			if c is HBoxContainer:
				hb = c
				break
		_ok("%s ★分母: 条里有格子容器" % WD_LONG[iso - 1], hb != null)
		if hb == null:
			mm.queue_free()
			await get_tree().process_frame
			continue

		var cells: Array = _cells(hb)
		_ok("%s 恰好 7 格(不是 6 也不是 8)" % WD_LONG[iso - 1], cells.size() == 7,
			"实测 %d" % cells.size())

		## ① 相位序列必须与唯一出处一字不差
		var got: Array = []
		var marked := 0
		var marked_wd := -1
		for k in range(cells.size()):
			var nm: String = str((cells[k] as Array)[1])
			if nm.ends_with(" 今"):
				marked += 1
				marked_wd = k + 1
				nm = nm.substr(0, nm.length() - 2)
			got.append(nm)
		_ok("%s ★★相位序列 == `phase_of_weekday` 的答案" % WD_LONG[iso - 1],
			got == want, "实测 %s" % str(got))

		## ② 恰好一格标「今」, 且就是今天
		_ok("%s ★★★恰好一格标「今」" % WD_LONG[iso - 1], marked == 1, "标了 %d 格" % marked)
		_ok("%s ★★★标「今」的那格就是今天(第 %d 格)" % [WD_LONG[iso - 1], iso],
			marked_wd == iso, "标在第 %d 格" % marked_wd)
		today_marks.append(marked_wd)

		## ③ 星期几那一行也要对得上(格子顺序不许反)
		var wd_row: Array = []
		for k2 in range(cells.size()):
			wd_row.append(str((cells[k2] as Array)[0]))
		_ok("%s ★星期几那行是周一→周日" % WD_LONG[iso - 1], wd_row == WD_CN, str(wd_row))

		mm.queue_free()
		await get_tree().process_frame

	## ④ 七天标的格子必须各不相同 —— 全标在同一格 = 那个override根本没生效
	var uniq: Dictionary = {}
	for m in today_marks:
		uniq[int(m)] = true
	_ok("★★★七天标「今」的位置**各不相同**(全一样 = 注入时钟没生效, 上面全是恒真)",
		uniq.size() == today_marks.size() and today_marks.size() == 7,
		"七天标在 %s" % str(today_marks))

	await _one_clock(packed)
	await _ticks(packed)
	_done()


## ═══════════════════════════════════════════════════════════════════
##  ⑤★★★整屏同一天 —— **只注 `clock_override_ts`**, 不碰 `strip_now_override`
## ═══════════════════════════════════════════════════════════════════
## 上面 ①~④ 把**两个** override 一起喂 ⇒ 就算赛程条挂着**自己那条时钟**也照样全绿。
## 而 2026-09-28 实测(`tests/_probe_mmclock.gd`, 修前): 只注 `clock_override_ts` 时
## **七天里有六天**条上标「今」的格与注入日对不上 —— 状态行已经改口说「闯关赛」,
## 条子底下还写着「一 休赛 今」。memory `fb-second-clock-drops-events`。
##
## ★三处各自有判据, 不拿一处代表整屏:
##   a) 条上标「今」的格 == 注入日
##   b) 收盘块 == **产品自己的** `_week_close_block(注入时刻)` 的文字
##      (不在这里重拄一遍那串 if —— 手抄的副本必然落后)
##   c) 状态行 L2 == `_phase_status_line(注入时刻)`
func _one_clock(packed) -> void:
	print("--- ⑤ 整屏同一天(只注 clock_override_ts) ---")
	var marks: Array = []
	var blocks: Array = []
	var phase_lines := 0
	for d in range(7):
		var iso: int = 7 if d == 0 else d
		var ts: int = SUN0 + d * 86400 + 12 * 3600
		var mm = packed.instantiate()
		mm.clock_override_ts = ts          ## ★只注这一条
		add_child(mm)
		for _i in range(6):
			await get_tree().process_frame
		var tag: String = WD_LONG[iso - 1]
		_ok("%s ★分母: `_now_ts()` 拿到的就是注入的那一刻" % tag,
			int(mm._now_ts()) == ts, "_now_ts=%d want=%d" % [int(mm._now_ts()), ts])

		## a) 条上标「今」的格
		var hb = null
		var box = mm.find_child("WeekStrip", true, false)
		if box != null:
			for c in box.get_children():
				if c is HBoxContainer:
					hb = c
					break
		_ok("%s ★分母: 条子建出来了" % tag, hb != null)
		if hb == null:
			mm.queue_free()
			await get_tree().process_frame
			continue
		var cells: Array = _cells(hb)
		_ok("%s ★分母: 恰好 7 格" % tag, cells.size() == 7, "实测 %d" % cells.size())
		var mk := -1
		for k in range(cells.size()):
			if str((cells[k] as Array)[1]).ends_with(" 今"):
				mk = k + 1
		marks.append(mk)
		_ok("%s ★★★a) 条上标「今」的那格 = 第 %d 格(只注整屏那条缝)" % [tag, iso],
			mk == iso, "实测第 %d 格" % mk)

		## b) 收盘块 —— 与**产品自己的函数**喂注入时刻的结果逐字比
		var got_blk: Array = []
		for cell in hb.get_children():
			var t2: Array = _texts(cell)
			if t2.is_empty():
				continue
			if t2.size() >= 2 and WD_CN.has(str(t2[0])):
				continue                     ## 日格, 不是收盘块
			got_blk = t2
		var want_node = mm._week_close_block(ts)
		var want_blk: Array = _texts(want_node)
		want_node.free()
		blocks.append(str(want_blk))
		_ok("%s ★分母: 收盘块有字(空的话下面是在比两个空数组)" % tag,
			not want_blk.is_empty() and not got_blk.is_empty(),
			"want=%s got=%s" % [str(want_blk), str(got_blk)])
		_ok("%s ★★★b) 收盘块 == `_week_close_block(注入时刻)`" % tag,
			got_blk == want_blk, "屏上=%s  产品函数=%s" % [str(got_blk), str(want_blk)])

		## c) 状态行 L2
		var want_l2: String = str(mm._phase_status_line(ts))
		if want_l2 != "":
			phase_lines += 1
			var two = mm.find_child(mm.STATUS_TWO_LINE, true, false)
			_ok("%s ★分母: 状态行那个具名容器在" % tag, two != null)
			if two != null:
				var ls: Array = _texts(two)
				_ok("%s ★★★c) 状态行 L2 == `_phase_status_line(注入时刻)`" % tag,
					ls.has(want_l2), "想要「%s」, 屏上 %s" % [want_l2, str(ls)])

		## ════ ⑦ 中间档九宫格接线 —— **素材画好了 ≠ 接上了** ════
		## 2026-09-28 接三处: 条子外框 `panel-wide-flat` / 今天那格 `panel-wide-on`
		## / 决赛日那扇门 `panel-wide`。
		## ★判据不是「我插了一行」 —— 而是**屏幕上那三个控件真挂着那张图**,
		##   外加**字块落在九宫格边框里面**(memory `fb-gate-must-measure-requirement-not-my-hook`)。
		var obx := _nine(box, "panel")
		_ok("%s ⑦a 条子外框挂着 `panel-wide-flat.png`(一个框, 不是七个)" % tag,
			_tex_name(obx) == "panel-wide-flat.png", "实测「%s」" % _tex_name(obx))
		var nined := 0
		var today_tex := ""
		var pad_ok := true
		var pad_txt := ""
		for cell in hb.get_children():
			if not (cell is Control):
				continue
			var tt: Array = _texts(cell)
			if not (tt.size() >= 2 and WD_CN.has(str(tt[0]))):
				continue
			var nb := _nine(cell as Control, "panel")
			if nb == null or nb.texture == null:
				continue
			nined += 1
			if str(tt[1]).ends_with(" 今"):
				today_tex = _tex_name(nb)
			## ★★字块必须落在**九宫格边框**里(边框读 `texture_margin` —— 那是真实的那圈金属)。
			##   这就是 `verify_ui_consistency` 「文字压边带」那条棘轮的同一件事, 只是量在源头:
			##   上一轮四版对照实测——格高不动 ⇒ 两行字 45px 装不进 54−16=38 的内容区。
			var mgn: float = nb.get_texture_margin(SIDE_TOP)
			var cr: Rect2 = (cell as Control).get_global_rect()
			var lt := 1.0e9
			var lb := -1.0e9
			var q: Array = [cell]
			while not q.is_empty():
				var nn = q.pop_back()
				if nn is Label and str((nn as Label).text).strip_edges() != "":
					var rr: Rect2 = (nn as Label).get_global_rect()
					lt = minf(lt, rr.position.y)
					lb = maxf(lb, rr.end.y)
				for ch3 in nn.get_children():
					q.append(ch3)
			pad_txt = "字 %.0f..%.0f  边框内沿 %.0f..%.0f (margin %.0f)" % [
				lt, lb, cr.position.y + mgn, cr.end.y - mgn, mgn]
			if lb <= lt or lt < cr.position.y + mgn or lb > cr.end.y - mgn:
				pad_ok = false
		_ok("%s ⑦b **恰好一格**套九宫格(七格全套=表格, 上一轮四版对照实拍否掉过)" % tag,
			nined == 1, "实测 %d 格" % nined)
		_ok("%s ⑦b 套的就是【今天】那格, 用的是 `panel-wide-on.png`" % tag,
			today_tex == "panel-wide-on.png", "实测「%s」" % today_tex)
		_ok("%s ⑦c 亮牌上那两行字落在九宫格边框**里面**" % tag, pad_ok, pad_txt)

		## ⑦d 几何 —— **七天都跑**。`verify_mainmenu_layout ④` 只量【真实今天】那一屏,
		##   而**周日**条子被 81px 的门撑到 95 高、顶沿与左栏栈底实测只差 **1px**:
		##   条子的 content_margin 多给 1 就压住入口, 而那一天一周只来一次。
		var pb: Control = mm.get("page_box")
		var stack_bot := -1.0e9
		if pb != null:
			for c4 in pb.get_children():
				if c4 is Control and (c4 as Control).visible:
					stack_bot = maxf(stack_bot, (c4 as Control).get_global_rect().end.y)
		var sr2: Rect2 = box.get_global_rect()
		_ok("%s ⑦d ★分母: 量到了左栏栈底(量不到 ⇒ 下一条是空检查)" % tag,
			stack_bot > 0.0, "栈底 %.0f" % stack_bot)
		_ok("%s ⑦d 条子不压住左栏入口(顶沿 ≥ 栈底−2)" % tag,
			sr2.position.y >= stack_bot - 2.0,
			"条顶 %.0f vs 栈底 %.0f" % [sr2.position.y, stack_bot])
		_ok("%s ⑦d 条子没掉出屏幕(底沿 ≤ 720) 且仍是【条】(高 ≤ 96)" % tag,
			sr2.end.y <= 720.0 and sr2.size.y <= 96.0,
			"底沿 %.0f 高 %.0f" % [sr2.end.y, sr2.size.y])

		## ⑦e 决赛日那扇门 —— 只有周日在场
		if iso == 7:
			var door: Button = null
			var q2: Array = [box]
			while not q2.is_empty():
				var n2 = q2.pop_back()
				if n2 is Button:
					door = n2 as Button
				for ch4 in n2.get_children():
					q2.append(ch4)
			_ok("%s ⑦e ★分母: 门在场(不在 ⇒ 下两条是空检查)" % tag, door != null)
			if door != null:
				var dn := _nine(door, "normal")
				_ok("%s ⑦e 门挂着 `panel-wide.png`" % tag,
					_tex_name(dn) == "panel-wide.png", "实测「%s」" % _tex_name(dn))
				## ★★不许退回 `UISkin.button()`: 它的 big 判据(短边≥56 且面积≥5000)
				##   会让 150×81 去挑 `menu/frame-rect.png`, 而那张**边带 27**,
				##   上下 55 装不下两行 15 号字 ⇒ 「文字压边带」当场 +1(棘轮只降不升)。
				_ok("%s ⑦e 门用的**不是** `frame-rect.png`(边带 27, 装不下两行字)" % tag,
					_tex_name(dn) != "frame-rect.png", "实测「%s」" % _tex_name(dn))

		mm.queue_free()
		await get_tree().process_frame

	var uq: Dictionary = {}
	for m in marks:
		uq[int(m)] = true
	_ok("★★★七天标「今」的位置各不相同(全一样 = 条子还挂着自己那条时钟)",
		uq.size() == 7 and marks.size() == 7, "七天标在 %s" % str(marks))
	## ★分母: 收盘块的期望值本身得**随天变** —— 七天一个样的话,
	##   b) 那条就是在比一个恒量, 条子读哪条时钟都能绿。
	var ub: Dictionary = {}
	for b in blocks:
		ub[str(b)] = true
	_ok("★分母: 收盘块的期望值七天至少有 5 种(一种 = b) 是空检查)",
		ub.size() >= 5, "实测 %d 种: %s" % [ub.size(), str(ub.keys())])
	## ★分母: 恰好两天有相位专属读数(周六闯关/周日决赛) —— c) 那条才不是空跑
	_ok("★分母: c) 真正比过的天数 = 2(周六/周日)", phase_lines == 2,
		"实测 %d 天" % phase_lines)

	## ⑥ ★分母: **不注入**时条子跟真实时钟走。
	##   不验这一条的话, 把 `_week_strip` 里的 now 写死成一个常量也能让 ⑤ 全绿。
	var mm0 = packed.instantiate()
	add_child(mm0)
	for _k in range(6):
		await get_tree().process_frame
	var sys_iso: int = P2.iso_weekday_utc(int(Time.get_unix_time_from_system()))
	var mk0 := -1
	var hb0 = null
	var bx0 = mm0.find_child("WeekStrip", true, false)
	if bx0 != null:
		for c0 in bx0.get_children():
			if c0 is HBoxContainer:
				hb0 = c0
				break
	_ok("★分母: 不注入时条子也建出来了", hb0 != null)
	if hb0 != null:
		var cs0: Array = _cells(hb0)
		for k0 in range(cs0.size()):
			if str((cs0[k0] as Array)[1]).ends_with(" 今"):
				mk0 = k0 + 1
		_ok("⑥ ★★不注入 ⇒ 条上标「今」的格 = 真实系统时钟的星期几",
			mk0 == sys_iso, "真实=%d 条上=%d" % [sys_iso, mk0])
	mm0.queue_free()
	await get_tree().process_frame


func _done() -> void:
	print("  ★分母: 本测试共 %d 条断言" % (_pass + _fail))
	if _fail == 0:
		print("ALL PASS — 赛程条七天全量")
		get_tree().quit(0)
	else:
		print("FAIL x%d" % _fail)
		get_tree().quit(1)


## ⑥ 倒计时要走、22:50 要变「已封盘」(2026-10-03 周六实操 S16:
##   22:36 和 22:49 两张截图都写「距收盘 24 分 18 秒」, 22:50 之后仍不显示已封盘)。
##   ★走产品自己的每秒轮询 `_sb_poll`, 只拨时钟, 不手动重建。
func _strip_texts(mm) -> Array:
	## ★不按名字找: 重画时旧条还没释放, 新条会被引擎自动改名。拿主菜单自己持有的那一条。
	var box = mm._week_box
	return _texts(box) if is_instance_valid(box) else []


func _ticks(packed) -> void:
	var sat: int = SUN0 + 6 * 86400               # 周六 00:00 UTC
	var mm = packed.instantiate()
	mm.strip_now_override = sat + 22 * 3600 + 30 * 60      # 22:30
	mm.clock_override_ts = mm.strip_now_override
	add_child(mm)
	for _i in range(6):
		await get_tree().process_frame
	var a: Array = _strip_texts(mm)
	var has_cd := false
	for s in a:
		if str(s).begins_with("距收盘"):
			has_cd = true
	_ok("⑥ ★分母: 22:30 显示倒计时", has_cd, str(a))
	mm.strip_now_override = sat + 22 * 3600 + 40 * 60      # 过了 10 分钟
	mm._sb_poll()
	for _i in range(4):
		await get_tree().process_frame
	var b: Array = _strip_texts(mm)
	var cd_b := ""
	for s in b:
		if str(s).begins_with("距收盘"):
			cd_b = str(s)
	_ok("⑥ ★★过了 10 分钟倒计时跟着变(原 bug: 停在打开那一刻)", cd_b != "" and not a.has(cd_b), "%s → %s" % [str(a), str(b)])
	mm.strip_now_override = sat + 22 * 3600 + 55 * 60      # 22:55 已过封盘线
	mm._sb_poll()
	for _i in range(4):
		await get_tree().process_frame
	_ok("⑥ ★★22:50 之后显示「已封盘」", _strip_texts(mm).has("已封盘"), str(_strip_texts(mm)))
	mm.strip_now_override = sat + 23 * 3600 + 5 * 60       # 23:05 已收盘
	mm._sb_poll()
	for _i in range(4):
		await get_tree().process_frame
	var c: Array = _strip_texts(mm)
	## ★2026-10-03 实拍: 周六收盘后写着「休赛日 · 周二开赛 · 本日维护」, 而明天是决赛日
	_ok("⑥ ★★周六 23:00 收盘后写「今日已收盘」并说明天是决赛日(不是休赛日)", c.has("今日已收盘") and not c.has("休赛日") and str(c).find("明天决赛日 · 本地 %s 开打" % mm._local_hhmm(mm._utc_today_at(sat + 86400, int(P2.FINALS_SEAT_HOUR_UTC)))) >= 0, str(c))
	mm.strip_now_override = SUN0 + 5 * 86400 + 23 * 3600 + 5 * 60   # 周五 23:05
	mm._sb_poll()
	for _i in range(4):
		await get_tree().process_frame
	_ok("⑥ ★周五积分赛收盘后说明天闯关赛", str(_strip_texts(mm)).find("明天闯关赛") >= 0, str(_strip_texts(mm)))
	mm.queue_free()
	await get_tree().process_frame
