extends Node
## verify_week_strip.gd — 本周赛程**七天全量** (2026-09-27 起; 2026-10-06 换成赛程页四张卡)
##
## ══════════════════════════════════════════════════════════════════════
##  为什么要这一份
## ══════════════════════════════════════════════════════════════════════
## 本周赛程是**玩家读「这周走到哪了」的那一页** —— 今天是什么、什么时候截止、周末进不进得去。
## 它是**按星期分支**的东西, 而本仓「判据挂在星期几上」已经栽过五次
## (v0.19.446 一轮修了四条; v0.19.458 的周日无限刷也是同一族)。
## ⇒ 判据不是「今天那张卡对不对」, 而是**七天各有确定答案**。
##
## ★2026-10-06 版式: 七格横条 → 整页 2×2 四张阶段卡(照荒野乱斗「CHOOSE EVENT」)。
##   判据跟着换, 但量的还是同三件事:
##   ① 四张卡 == 唯一出处 `phase_of_weekday` 的四个阶段(顺序、名字、哪几天)
##   ② 恰好一张是今天(金边), 而且就是注入的那一天
##   ③ 每张卡屏幕上的字 == **产品自己的** `week_card_info(阶段, 注入时刻)`
##      (不在门禁里重抄一遍那串 if —— 手抄的副本必然落后)
## ★只量 `WeekCards` 容器里的卡(按名字定位, 判据仍是阶段序列) ——
##   2026-09-27 探针扫全屏时把别处的标签也数了进来, **判据宽一格就会造出假 bug**。
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const SUN0 := 1789862400          # 2026-09-20 周日 00:00 UTC
const WD_LONG := ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
const PHASES := [P2.PHASE_REST, P2.PHASE_RANKED, P2.PHASE_GAUNTLET, P2.PHASE_FINALS]
## ★★2026-10-26 用户拍板闯关赛收盘 周六 23:00 → 周日 17:30 UTC(方案书 20261026b-周六流程.md §4 G) ⇒ 周日被一分为二。
##   钉点 = 周日 19:00(决赛日) + 周一~周六正午 + 周日 12:00(闯关赛收盘前), 共 8 个; 每个钉点自带「这一刻该是哪个阶段」。
##   ★期望阶段**写死**, 不再问 `phase_of_weekday(星期几)` —— 那张表回答的是「这一天叫什么」, 周日它只能答一个。
##   [标签, ISO 星期几, 时刻, 期望金边阶段]
const PINS := [
	["周日", 7, SUN0 + 19 * 3600, P2.PHASE_FINALS],
	["周一", 1, SUN0 + 1 * 86400 + 43200, P2.PHASE_REST],
	["周二", 2, SUN0 + 2 * 86400 + 43200, P2.PHASE_RANKED],
	["周三", 3, SUN0 + 3 * 86400 + 43200, P2.PHASE_RANKED],
	["周四", 4, SUN0 + 4 * 86400 + 43200, P2.PHASE_RANKED],
	["周五", 5, SUN0 + 5 * 86400 + 43200, P2.PHASE_RANKED],
	["周六", 6, SUN0 + 6 * 86400 + 43200, P2.PHASE_GAUNTLET],
	["周日上午", 7, SUN0 + 43200, P2.PHASE_GAUNTLET],
]

var _pass := 0
var _fail := 0


func _ok(nm: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [nm, detail])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [nm, detail])


## 一棵子树里的可读文字(去重, 保序)。★Button 也收: 周六/周日卡上的门是 Button。
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


## 一张卡**应该**有的字 —— 全部来自产品函数 `week_card_info`(锁着时副标题换成解锁条件)。
func _want_texts(info: Dictionary) -> Array:
	var w: Array = [str(info["time"]), "i", str(info["title"]),
		str(info["lock_text"]) if bool(info["locked"]) else str(info["days"])]
	for c in (info["chips"] as Array):
		w.append(str(c[0]))
		w.append(str(c[1]))
	for p in (info["points"] as Array):
		w.append(str(p))
	return w


func _card(mm: Node, ph: String) -> Control:
	var box = mm.get("_week_box")
	if not is_instance_valid(box):
		return null
	return (box as Node).get_node_or_null(str(mm.WEEK_CARD_PREFIX) + ph) as Control


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
	print("=== 本周赛程七天全量 ===")
	var packed = load("res://scenes/MainMenu.tscn")
	_ok("★分母: 载得到 MainMenu.tscn", packed != null)
	if packed == null:
		_done()
		return

	var labels: Array = []
	for ph in PHASES:
		labels.append(str(P2.PHASE_LABEL.get(str(ph), "?")))
	_ok("★分母: 四个阶段名都取得到(取不到 = 下面全在比 '?')", not labels.has("?"), str(labels))

	var today_marks: Array = []
	for pin in PINS:
		var iso: int = int(pin[1])
		var tag: String = str(pin[0])
		var mm = packed.instantiate()
		var ts: int = int(pin[2])
		mm.strip_now_override = ts
		mm.clock_override_ts = ts
		add_child(mm)
		for _i in range(6):
			await get_tree().process_frame
		var box = mm.find_child(str(mm.WEEK_CARDS_NAME), true, false)
		_ok("%s ★分母: 赛程页的卡容器建出来了" % tag, box != null)
		if box == null:
			mm.queue_free()
			await get_tree().process_frame
			continue
		## ① 四张卡 == 四个阶段, 顺序就是一周的顺序
		var names: Array = []
		for c in box.get_children():
			if str(c.name).begins_with(str(mm.WEEK_CARD_PREFIX)):
				names.append(str(c.name).substr(str(mm.WEEK_CARD_PREFIX).length()))
		_ok("%s ★★恰好四张卡, 顺序 == 休赛/积分赛/闯关赛/决赛日" % tag, names == PHASES, str(names))
		## ② 恰好一张今天(金边), 且是 phase_of_weekday(今天)
		var todays: Array = []
		var bad: Array = []
		for ph in PHASES:
			var card := _card(mm, str(ph))
			if card == null:
				bad.append("%s: 卡不在" % ph)
				continue
			if card.get_node_or_null("TodayFrame") != null:
				todays.append(str(ph))
			## ③ 屏幕上的字 == week_card_info(阶段, 注入时刻)
			var info: Dictionary = mm.week_card_info(str(ph), ts)
			var got: Array = _texts(card)
			for w in _want_texts(info):
				if not got.has(w):
					bad.append("%s 缺「%s」" % [ph, w])
			## 已过去的阶段只说「已结束」; 以后的说「周X HH:MM 开始」
			var st: String = str(info["state"])
			if st == "past" and str(info["time"]) != str(mm.CARD_PAST_TEXT):
				bad.append("%s 过去了却写「%s」" % [ph, info["time"]])
			if st == "future" and not str(info["time"]).ends_with("开始"):
				bad.append("%s 还没到却写「%s」" % [ph, info["time"]])
		_ok("%s ★★★恰好一张卡是今天(金边)" % tag, todays.size() == 1, str(todays))
		var want_today: String = str(pin[3])
		_ok("%s ★★★金边那张就是今天的阶段「%s」" % [tag, want_today], todays == [want_today], str(todays))
		_ok("%s ★★★四张卡上的字 == `week_card_info(阶段, 注入时刻)`" % tag, bad.is_empty(), str(bad))
		today_marks.append(todays[0] if todays.size() == 1 else "")
		## 今天那张的时间 == 模式卡第三行(同一个 `_mode_countdown`)
		## ★2026-10-26 周末没资格(模式卡锁着)时第三格不是倒计时, 是去处(「观看全场赛况 »」/「观看对阵图 »」, 点卡直达)
		##   ⇒ 锁着时量「去处 == `_mode_locked_door` 那一扇」; 没锁时照旧量「== 今天那张的时间」。
		var tinfo: Dictionary = mm.week_card_info(want_today, ts)
		var l3: String = str(mm.mode_card_lines(ts)[2])
		if mm.mode_card_locked(ts) and str(mm._mode_locked_door(ts)) != "":
			var want_door: String = str(mm.MODE_WATCH_BOARD) if str(mm._mode_locked_door(ts)) == str(mm.WEEK_DOOR_BOARD) else str(mm.MODE_WATCH_BRACKET)
			_ok("%s ★模式卡锁着 ⇒ 第三格是观战去处(与 `_mode_locked_door` 同一扇)" % tag, l3 == want_door, "%s / %s" % [l3, want_door])
		else:
			_ok("%s ★今天那张的时间 == 模式卡倒计时那一行" % tag, str(tinfo["time"]) == l3, "%s / %s" % [tinfo["time"], l3])
		if iso == 6:
			await _info_taps(mm)
		## ★★周六已晋级 ⇒ 模式卡第三行说周日几点开打, 不再数闯关赛收盘(2026-10-10 周六实操)。没晋级的照旧(对照组)。
		## ★2026-10-26 周日上午也是闯关赛 ⇒ 两个闯关赛钉点都验
		if want_today == P2.PHASE_GAUNTLET:
			var gw0 := int(GameState.gauntlet_wins)
			var gl0 := int(GameState.gauntlet_losses)
			var pr0 = GameState.promoted
			GameState.promoted = true          # 量的是有资格的人那张卡(没资格时卡锁着, 第三格是观战去处, 见上一条)
			GameState.gauntlet_wins = 4
			GameState.gauntlet_losses = 0
			var l_in: String = str(mm.mode_card_lines(ts)[2])
			GameState.gauntlet_wins = 0
			var l_run: String = str(mm.mode_card_lines(ts)[2])
			GameState.gauntlet_wins = gw0
			GameState.gauntlet_losses = gl0
			GameState.promoted = pr0
			_ok("%s ★★已晋级 ⇒ 倒计时指向周日小组赛开打" % tag, l_in.begins_with("距" + P2.STAGE_GROUP + "开始"), l_in)
			_ok("%s 对照: 还在打 ⇒ 仍是闯关赛收盘倒计时" % tag, l_run.begins_with("距截止") or l_run.begins_with("已截止") or l_run.begins_with("今日"), l_run)
			if iso == 7:
				## ★★周日 12:00 → 当天 18:00 分组 = 6 小时整(原来按「下一阶段那天的 18:00」推, 周日上午会推到周一: 「1 天 6 小时」)
				_ok("%s ★★已晋级 ⇒ 距小组赛开始 = 6 小时 0 分(指当天 18:00, 不是下周)" % tag,
					l_in == "距%s开始 6 小时 0 分" % P2.STAGE_GROUP, l_in)
				_ok("%s ★对照: 还在打 ⇒ 距截止 = 5 小时 30 分(收盘 17:30)" % tag,
					l_run == "距截止 5 小时 30 分", l_run)
		mm.queue_free()
		await get_tree().process_frame

	## ④ 七天的金边不是一直挂在同一张上(全一样 = 注入时钟没生效, 上面全是恒真)
	var want_marks: Array = []
	for pin in PINS:
		want_marks.append(str(pin[3]))
	_ok("★★★八个钉点金边依次 == 日(19:00)~六 + 日(12:00) 的阶段(全一样 = 注入时钟没生效)", today_marks == want_marks,
		"实测 %s" % str(today_marks))

	await _one_clock(packed)
	await _ticks(packed)
	_done()


## ═══════════════════════════════════════════════════════════════════
##  ⑤★★★整屏同一天 —— **只注 `clock_override_ts`**, 不碰 `strip_now_override`
## ═══════════════════════════════════════════════════════════════════
## 上面把**两个** override 一起喂 ⇒ 就算赛程页挂着**自己那条时钟**也照样全绿。
## 2026-09-28 实测(`tests/_probe_mmclock.gd`, 修前): 只注 `clock_override_ts` 时七天里六天
## 标「今」的与注入日对不上(memory `fb-second-clock-drops-events`)。
## ★三处各自有判据: a) 金边那张 == 注入日  b) 今天那张的字 == `week_card_info(注入时刻)`
##   c) 模式卡第二行 == `_phase_status_line(注入时刻)`
func _one_clock(packed) -> void:
	print("--- ⑤ 整屏同一天(只注 clock_override_ts) ---")
	var marks: Array = []
	var times: Array = []
	var phase_lines := 0
	for pin in PINS:
		var iso: int = int(pin[1])
		var ts: int = int(pin[2])
		var mm = packed.instantiate()
		mm.clock_override_ts = ts          ## ★只注这一条
		add_child(mm)
		for _i in range(6):
			await get_tree().process_frame
		var tag: String = str(pin[0])
		## 赛程页默认藏着 ⇒ 量几何前先**真按一下模式卡**(走它自己那颗按钮的 pressed)。
		var mtap = mm.find_child("ModeTap", true, false)
		_ok("%s ★分母: 模式卡上有那颗按钮" % tag, mtap is BaseButton)
		if mtap is BaseButton:
			(mtap as BaseButton).pressed.emit()
		for _j in range(4):
			await get_tree().process_frame
		_ok("%s ★分母: `_now_ts()` 拿到的就是注入的那一刻" % tag,
			int(mm._now_ts()) == ts, "_now_ts=%d want=%d" % [int(mm._now_ts()), ts])
		var mk := ""
		for ph in PHASES:
			var card := _card(mm, str(ph))
			if card != null and card.get_node_or_null("TodayFrame") != null:
				mk = str(ph)
		marks.append(mk)
		var want_ph: String = str(pin[3])
		_ok("%s ★★★a) 金边那张 = 「%s」(只注整屏那条缝)" % [tag, want_ph], mk == want_ph, "实测「%s」" % mk)
		var card_t := _card(mm, want_ph)
		_ok("%s ★分母: 今天那张卡在" % tag, card_t != null)
		if card_t == null:
			mm.queue_free()
			await get_tree().process_frame
			continue
		var info: Dictionary = mm.week_card_info(want_ph, ts)
		times.append(str(info["time"]))
		var got: Array = _texts(card_t)
		var miss: Array = []
		for w in _want_texts(info):
			if not got.has(w):
				miss.append(w)
		_ok("%s ★★★b) 今天那张的字 == `week_card_info(注入时刻)`" % tag, miss.is_empty(), "缺 %s · 屏上 %s" % [str(miss), str(got)])
		## c) 周六/周日: 模式卡第二行 == 当天读数
		var want_l2: String = str(mm._phase_status_line(ts))
		if want_l2 != "":
			phase_lines += 1
			var two = mm.find_child(mm.MODE_CARD_NAME, true, false)
			_ok("%s ★分母: 模式卡在" % tag, two != null)
			if two != null:
				var ls: Array = _texts(two)
				var want_c: String = str(mm.mode_card_lines(ts)[1])
				_ok("%s ★★★c) 模式卡第二行 == `_phase_status_line(注入时刻)` 的后半句" % tag,
					want_c != "" and want_l2.ends_with(want_c) and ls.has(want_c), "想要「%s」, 屏上 %s" % [want_l2, str(ls)])
		## ⑦ 几何: 点开之后四张卡真看得见、整页在屏内、2×2 不重叠
		var rects: Array = []
		var vis := 0
		for ph in PHASES:
			var c := _card(mm, str(ph))
			if c != null:
				rects.append(c.get_global_rect())
				if c.is_visible_in_tree():
					vis += 1
		_ok("%s ⑦ ★点开模式卡之后四张卡都看得见" % tag, vis == 4, "%d" % vis)
		var inside := true
		var overlap := false
		for i in range(rects.size()):
			var r: Rect2 = rects[i]
			if r.position.x < 0.0 or r.position.y < 0.0 or r.end.x > 1280.0 or r.end.y > 720.0:
				inside = false
			for j in range(i + 1, rects.size()):
				if r.intersects(rects[j]):
					overlap = true
		_ok("%s ⑦ 四张卡整张在屏内(1280×720)、互不重叠" % tag, rects.size() == 4 and inside and not overlap, str(rects))
		if rects.size() == 4:
			_ok("%s ⑦ 排成 2×2(第一行两张同顶沿, 第二行在下面)" % tag,
				absf((rects[0] as Rect2).position.y - (rects[1] as Rect2).position.y) < 1.0
				and (rects[2] as Rect2).position.y > (rects[0] as Rect2).end.y
				and absf((rects[0] as Rect2).position.x - (rects[2] as Rect2).position.x) < 1.0, "")
		## ⑦e 周六 / 周日的门: 在当天那张卡上, 黄铜门牌, 接了处理函数
		## ★2026-10-26 门跟着**阶段**走(周日上午是闯关赛 ⇒ 挂「全场赛况」), 不再按星期几
		if want_ph == P2.PHASE_GAUNTLET or want_ph == P2.PHASE_FINALS:
			var dn: String = "GauntletBoardDoor" if want_ph == P2.PHASE_GAUNTLET else "BracketDoor"
			var door = card_t.find_child(dn, true, false)
			_ok("%s ⑦e ★分母: 门「%s」在今天那张卡上" % [tag, dn], door is Button)
			if door is Button:
				var sb = (door as Button).get_theme_stylebox("normal")
				var tex := ""
				if sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null:
					tex = str((sb as StyleBoxTexture).texture.resource_path).get_file()
				_ok("%s ⑦e 门挂着 `brass.png`(黄铜门牌)" % tag, tex == "brass.png", "实测「%s」" % tex)
				_ok("%s ⑦e ★★门接了处理函数(有按钮 ≠ 按了有用)" % tag,
					(door as Button).pressed.get_connections().size() >= 1, "")
				var want_m: String = "_open_gauntlet_board" if want_ph == P2.PHASE_GAUNTLET else "_open_bracket_map"
				var got_m := ""
				for cn in (door as Button).pressed.get_connections():
					got_m = (cn["callable"] as Callable).get_method()
				_ok("%s ⑦e ★门通到原来那一处(`%s`)" % [tag, want_m], got_m == want_m, got_m)
		mm.queue_free()
		await get_tree().process_frame

	_ok("★★★八个钉点金边位置 == 日(19:00)~六 + 日(12:00) 的阶段(全一样 = 赛程页还挂着自己那条时钟)",
		marks == [P2.PHASE_FINALS, P2.PHASE_REST, P2.PHASE_RANKED, P2.PHASE_RANKED, P2.PHASE_RANKED, P2.PHASE_RANKED, P2.PHASE_GAUNTLET,
			P2.PHASE_GAUNTLET],
		"八个钉点标在 %s" % str(marks))
	var ut: Dictionary = {}
	for t in times:
		ut[str(t)] = true
	## ★分母: 今天那张的时间七天至少 5 种(一种 = b) 在比一个恒量, 读哪条钟都能绿)
	_ok("★分母: 今天那张的时间七天至少有 5 种", ut.size() >= 5, "实测 %d 种: %s" % [ut.size(), str(ut.keys())])
	_ok("★分母: c) 真正比过的钉点 = 3(周六 / 周日上午 / 周日晚上)", phase_lines == 3, "实测 %d 个" % phase_lines)

	## ⑥ ★分母: **不注入**时赛程页跟真实时钟走。
	##   不验这一条的话, 把 `_week_cards` 里的 now 写死成一个常量也能让 ⑤ 全绿。
	var mm0 = packed.instantiate()
	add_child(mm0)
	for _k in range(6):
		await get_tree().process_frame
	var sys_ph: String = str(P2.phase_at_utc(int(Time.get_unix_time_from_system())))
	var mk0 := ""
	for ph in PHASES:
		var c0 := _card(mm0, str(ph))
		if c0 != null and c0.get_node_or_null("TodayFrame") != null:
			mk0 = str(ph)
	_ok("⑥ ★★不注入 ⇒ 金边那张 = 真实系统时钟的阶段", mk0 == sys_ph, "真实=%s 页上=%s" % [sys_ph, mk0])
	mm0.queue_free()
	await get_tree().process_frame


func _done() -> void:
	print("  ★分母: 本测试共 %d 条断言" % (_pass + _fail))
	if _fail == 0:
		print("ALL PASS — 本周赛程七天全量")
		get_tree().quit(0)
	else:
		print("FAIL x%d" % _fail)
		get_tree().quit(1)


## ⑥ 倒计时要走、22:50 要变「已截止」(2026-10-03 周六实操 S16:
##   22:36 和 22:49 两张截图都写「距收盘 24 分 18 秒」, 22:50 之后仍不显示已封盘)。
##   ★走产品自己的每秒轮询 `_sb_poll`, 只拨时钟, 不手动重建。
func _page_texts(mm) -> Array:
	## ★不按名字找: 重画时旧容器还没释放, 新的会被引擎自动改名。拿主菜单自己持有的那一个。
	var box = mm._week_box
	return _texts(box) if is_instance_valid(box) else []


func _ticks(packed) -> void:
	var sat: int = SUN0 + 6 * 86400               # 周六 00:00 UTC
	## ★★2026-10-26 闯关赛收盘挪到周日 17:30 UTC ⇒ 原来量「周六 22:30/22:40/22:55/23:05」的那组刻度
	##   整体搬到周日 17:00/17:10/17:25/17:35(收盘前 30 分 / 20 分 / 封盘窗内 / 收盘后)。量的还是同三件事:
	##   倒计时跟着走、封盘窗内显示「已截止」、收盘后页上换成下一阶段(不是休赛日)。
	var sun2: int = SUN0 + 7 * 86400              # 周日 00:00 UTC(与 sat 同一周)
	var mm = packed.instantiate()
	mm.strip_now_override = sun2 + 17 * 3600      # 17:00
	mm.clock_override_ts = mm.strip_now_override
	add_child(mm)
	for _i in range(6):
		await get_tree().process_frame
	var a: Array = _page_texts(mm)
	var has_cd := false
	for s in a:
		if str(s).begins_with("距截止"):
			has_cd = true
	_ok("⑥ ★分母: 周日 17:00 显示倒计时", has_cd, str(a))
	mm.strip_now_override = sun2 + 17 * 3600 + 10 * 60      # 过了 10 分钟
	mm._sb_poll()
	for _i in range(4):
		await get_tree().process_frame
	var b: Array = _page_texts(mm)
	var cd_b := ""
	for s in b:
		if str(s).begins_with("距截止"):
			cd_b = str(s)
	_ok("⑥ ★★过了 10 分钟倒计时跟着变(原 bug: 停在打开那一刻)", cd_b != "" and not a.has(cd_b), "%s → %s" % [str(a), str(b)])
	mm.strip_now_override = sun2 + 17 * 3600 + 25 * 60      # 17:25 已过封盘线(17:20)
	mm._sb_poll()
	for _i in range(4):
		await get_tree().process_frame
	_ok("⑥ ★★17:20 之后显示「已截止」", str(_page_texts(mm)).find("已截止") >= 0, str(_page_texts(mm)))
	## ★另一侧: 17:19 还没封(否则「一直显示已截止」也能让上一条绿)
	mm.strip_now_override = sun2 + 17 * 3600 + 19 * 60
	mm._sb_poll()
	for _i in range(4):
		await get_tree().process_frame
	_ok("⑥ ★另一侧: 17:19 还在倒计时、没有「已截止」",
		str(_page_texts(mm)).find("已截止") < 0 and str(_page_texts(mm)).find("距截止") >= 0, str(_page_texts(mm)))
	mm.strip_now_override = sun2 + 17 * 3600 + 35 * 60      # 17:35 已收盘
	mm._sb_poll()
	for _i in range(4):
		await get_tree().process_frame
	var c: Array = _page_texts(mm)
	## ★2026-10-03 实拍: 收盘后写着「休赛日 · 周二开赛 · 本日维护」, 而接下来是决赛日。
	## ★2026-10-26 收盘那一刻阶段就翻成决赛日 ⇒ 闯关赛那张「已结束」、决赛日那张成为今天(金边), 时间行指去对阵图;
	##   页上不许残留闯关赛的倒计时 / 「已截止」, 也不许写休赛日。
	var t_after: int = sun2 + 17 * 3600 + 35 * 60
	var gi: Dictionary = mm.week_card_info(P2.PHASE_GAUNTLET, t_after)
	var fi: Dictionary = mm.week_card_info(P2.PHASE_FINALS, t_after)
	var fcard := _card(mm, P2.PHASE_FINALS)
	var gcard := _card(mm, P2.PHASE_GAUNTLET)
	_ok("⑥ ★★周日 17:30 收盘后: 闯关赛那张已结束、决赛日那张成为今天(金边)",
		str(gi["state"]) == "past" and str(fi["state"]) == "now"
		and fcard != null and fcard.get_node_or_null("TodayFrame") != null
		and gcard != null and gcard.get_node_or_null("TodayFrame") == null,
		"闯关=%s 决赛=%s" % [str(gi["state"]), str(fi["state"])])
	_ok("⑥ ★★收盘后页上换成决赛日那一行(「%s」), 没有残留倒计时 / 已截止 / 休赛日" % str(fi["time"]),
		str(fi["time"]) != "" and c.has(str(fi["time"])) and c.has(str(mm.CARD_PAST_TEXT))
		and str(c).find("距截止") < 0 and str(c).find("已截止") < 0 and not c.has("休赛日"), str(c))
	mm.strip_now_override = SUN0 + 5 * 86400 + 23 * 3600 + 5 * 60   # 周五 23:05
	mm._sb_poll()
	for _i in range(4):
		await get_tree().process_frame
	var f: Array = _page_texts(mm)
	var sat_start: String = "%s 开始" % mm._local_wd_hhmm(sat)
	_ok("⑥ ★周五积分赛收盘后: 积分赛「今日已截止」+ 闯关赛那张写开始时刻", f.has("今日已截止") and f.has(sat_start), "要「%s」· %s" % [sat_start, str(f)])
	mm.queue_free()
	await get_tree().process_frame


## ⑥ 每张卡右上角的「i」点了都要有回应: 走真入口(那颗 Button 的 pressed), 量**真飘出来的那行字**。
##   并量触摸线(短边 ≥ 81 = 44pt 的宽; 高至少盖住整条暗带)。
func _info_taps(mm: Node) -> void:
	var got: Dictionary = {}
	var found := 0
	for ph in PHASES:
		var card := _card(mm, str(ph))
		var tap = card.find_child("CardInfoTap", true, false) if card != null else null
		if not (tap is Button):
			_ok("⑥ 「%s」那张有 i 按钮" % ph, false)
			continue
		found += 1
		var r: Rect2 = (tap as Control).get_global_rect()
		_ok("⑥ 「%s」i 的点击区宽 ≥ 81" % ph, r.size.x >= 81.0, "%.0f×%.0f" % [r.size.x, r.size.y])
		var before: Array = mm.get_children()
		(tap as Button).pressed.emit()
		var txt := ""
		for ch in mm.get_children():
			if not before.has(ch):
				if ch is Label:
					txt = str((ch as Label).text)
				ch.queue_free()
		var lab: String = str(P2.PHASE_LABEL.get(str(ph), "?"))
		_ok("⑥ ★★点「%s」的 i → 真飘出一行, 说的是这个阶段" % lab, txt != "" and txt.begins_with(lab), "「%s」" % txt)
		got[txt] = true
	_ok("⑥ ★分母: 四张卡都找到了 i", found == 4, "%d" % found)
	_ok("⑥ ★分母: 四句各不相同(都一样 = 没按阶段分)", got.size() == 4, "%d 种" % got.size())
