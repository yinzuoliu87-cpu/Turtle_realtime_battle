extends Node
## verify_quota_clock.gd — 主菜单一屏**只许有一条时钟**(2026-09-29)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么 —— 以及它是怎么被逼出来的
## ══════════════════════════════════════════════════════════════════════
## 病灶(探针 `tests/_probe_twoclocks.gd` 实测, 不是推理出来的):
##   `MainMenuScene._build_page_buttons()` 原来调 `GameState.ranked_quota_full()`
##   **不带参**, 而那个函数的兜底是**真实系统钟** —— 既不过屏内的 `clock_override_ts`,
##   也不过全局缝 `phase2_config.now_override_ts`。于是同一屏上有两条钟:
##
##     钉住周六(配额 24/24, 已晋级, 闯关 1-1) 实测:
##       状态行 L2 画的是「闯关赛 1-1 · 再赢 3 场晋级 / 再输 2 场出局」  ← 走 `_now_ts()`
##       商店那一行画的是「🔒 商店」(现在是方键角标 🔒)                    ← 走真实的周二
##       而 `_open_shop()` 自己的判据 `ranked_quota_full(_now_ts())` = false
##     ⇒ **锁画在屏幕上, 而那扇门是开的**。10 个构造时刻里 5 个两种写法答案相反。
##
## 修法: 「现在」在 `_ready` 里算**一次**(`paint_ts`), 往下传给
##   `_right_column → _status_row` / `_week_strip` / `_build_page_buttons` 三处;
##   `GameState.ranked_quota_full/gauntlet_can_play` 的兜底改走全局缝 `_P2.now_utc()`。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ① **喂不同入参必须得到不同答案** —— 本轮刚栽过的那个形状:「改了签名而函数体
##    还在读全局」⇒ 入参被默默丢掉、行为没变而门禁全绿(memory
##    `fb-changing-a-param-meaning-makes-gates-tautological`)。所以先证明这条缝真的通。
## ② **一屏上两处读数必须自洽**: 屏幕自己说的「今天是哪天」, 与「商店锁按哪天算的」
##    必须是同一天。量的是**真画出来的字**(`_status_row` / `_build_page_buttons` 的产物),
##    不是我复算一遍公式(memory `fb-write-without-reader-and-fake-gates`)。
## ③ **边界时刻逐个走**: 相位界两侧各取 1 秒(周五 23:59:59 / 周六 00:00:00 …)、
##    周界(周日 23:59:59 / 下周一 00:00:00)。★配一条**分母**: 这些时刻里
##    「打满」的答案必须**既有 true 也有 false**, 否则整组是空检查;
##    并且每一对边界两侧的答案必须**真的翻**了 —— 不翻就说明这条界根本没落在判据上。
## ④ **一屏只读一次钟**, 而且**传了入参之后一次都不许再读**:
##    计数器 `MainMenuScene._clock_reads` 数的是 `_now_ts()` 被叫了几次。
##    ⚠ 它单独不成判据(数的是我自己插的钩子, memory
##      `fb-gate-must-measure-requirement-not-my-hook`) ⇒ **必须与 ⑤ 的源码扫一起用**。
##    ★为什么量的是**第一次刷屏**(add_child 后 3 帧就读): `rebuild_week_strip()`
##      是**另一次刷屏**, 它重新读一次钟才是对的 —— 否则菜单开着过了午夜还在说昨天。
##      那个重建由 `_sb_poll` 每 1 秒一拍触发; 而门禁里 `TURTLE_SUPABASE=" "`
##      ⇒ `supabase.service_state()` 恒等 `ST_OFF` ⇒ `_sb_poll` 永远提前 return,
##      计数不会被它搂乱(这也是为何不拿“≤N”当判据)。
## ⑤ **源码扫**: 谁绕过 `_now_ts()` 直接读系统钟, 计数器是瞎的。所以另加一条静态判据:
##    `MainMenuScene.gd` 的**代码行**里 `Time.get_unix_time_from_system` 必须 0 次、
##    `_P2C.now_utc()` 只许出现 1 次(就在 `_now_ts()` 里)、
##    `ranked_quota_full()` / `gauntlet_can_play()` **不带参的写法**必须 0 次;
##    `GameState` 那两个函数体里也不许再就地读系统钟。
##
## 反向验证(2026-09-29 做过): 把 335 行改回 `ranked_quota_full()` 不带参 ⇒ ② 当场红,
## 且红的形状就是「画出来的锁 ≠ 入口的判据」。

const MENU := preload("res://scripts/scenes/MainMenuScene.gd")
const _P2 := preload("res://scripts/gamedata/phase2_config.gd")

## 2026-09-14 周一 00:00:00 UTC —— 本周锚点。往后逐日加 86400。
## ★不写「今天」: 判据一挂上真实星期几, 一周里就有几天是空检查(本文件的病灶正是这个)。
const MON := 1789344000
const D := 86400

var _n := 0
var _fail := 0
var _gs = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 递归收集**去重后**的 Label 文本(描边 = 同一句话 5 份, 只留一份)。
func _texts(n: Node, out: Array) -> void:
	if n is Label:
		var tx := str((n as Label).text)
		if not out.has(tx):
			out.append(tx)
	for c in n.get_children():
		_texts(c, out)


## 从 page_box 里读出【商店那颗键上画出来的所有字】(拼成一串)。"" = 没找到(分母断言用)。
## ★2026-10-05 第三轮: 商店从「🔒 商店」一行字变成方形图标键 —— 锁是键右上角的 🔒 角标、
##   理由是键右边那一行。所以按**整颗键的子树**收字, 不再找"含商店两个字的那一个 Label"。
func _shop_line(scene: Node) -> String:
	if scene.page_box == null:
		return ""
	for holder in scene.page_box.get_children():
		var all: Array = []
		_texts(holder, all)
		if all.has(str(MENU.SHOP_LABEL)):
			return " ".join(PackedStringArray(all))
	return ""


## 商店那颗键上**画没画锁**。2026-10-06: 锁从系统表情「🔒」Label 换成像素锁 TextureRect
##   (名字固定 `MainMenuScene.LOCK_ICON_NAME`) ⇒ 按名字在商店那颗键的子树里找, 不再找字。
func _shop_locked(scene: Node) -> bool:
	if scene.page_box == null:
		return false
	for holder in scene.page_box.get_children():
		var all: Array = []
		_texts(holder, all)
		if all.has(str(MENU.SHOP_LABEL)):
			return holder.find_child(str(MENU.LOCK_ICON_NAME), true, false) != null
	return false


## 只留【配额】这一条上锁理由: 满命(非淘汰) + 已打过第一场。
func _isolate_quota_reason() -> void:
	_gs.hearts = 8
	_gs.season_total_battles = 5


## 重建一次入口按钮(走**产品自己的** `_build_page_buttons(ts)`), 返回商店那一行的字。
func _repaint_entries(scene: Node, ts: int) -> String:
	for ch in scene.page_box.get_children():
		scene.page_box.remove_child(ch)
		ch.free()
	scene._build_page_buttons(ts)
	return _shop_line(scene)


## 走**产品自己的** `_status_row(ts)` 画一次状态行, 返回 [L1, L2]。
func _status_lines(scene: Node, ts: int) -> Array:
	## 2026-10-05 第四轮: `_status_row` 建玩家卡 + (吃配额的日子)开始战斗上方的计数条 ⇒ 收它新建的全部节点的字。
	var before: Array = scene.content_root.get_children()
	scene._status_row(ts)
	var tl: Array = []
	for ch in scene.content_root.get_children():
		if not before.has(ch):
			_texts(ch, tl)
			scene.content_root.remove_child(ch)
			ch.free()
	return tl


## GameState 里某个函数的**函数体**源码(从 `func <名>(` 到下一个顶格 `func `)。
func _func_body(src: String, sig_head: String) -> String:
	var i: int = src.find(sig_head)
	if i < 0:
		return ""
	var j: int = src.find("\nfunc ", i + sig_head.length())
	return src.substr(i, (j - i) if j > i else -1)


## 只留**代码行**(整行注释扔掉) —— 不然注释里提一句 `ranked_quota_full()` 也算命中。
func _code_only(src: String) -> String:
	var out: PackedStringArray = []
	for ln in src.split("\n"):
		if str(ln).strip_edges().begins_with("#"):
			continue
		out.append(str(ln))
	return "\n".join(out)


func _ready() -> void:
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		print("  [FAIL] 缺 GameState autoload")
		get_tree().quit(1)
		return
	_gs.test_mode = true                  # 不许写真存档(memory `fb-debug-stage-writes-real-save`)
	print("=== 主菜单一屏只许一条时钟 ===")

	# 备份要动的字段, 跑完还原
	var k_h: int = int(_gs.hearts)
	var k_b: int = int(_gs.season_total_battles)
	var k_u: int = int(_gs.ranked_used)
	var k_p = _gs.promoted
	var k_gw: int = int(_gs.gauntlet_wins)
	var k_gl: int = int(_gs.gauntlet_losses)
	var k_seam: int = int(_P2.now_override_ts)

	_ok("★分母: 全局时间缝默认关着(now_override_ts == 0) —— 否则下面全是在量别人留下的状态",
		k_seam == 0, "now_override_ts=%d" % k_seam)

	# ══════════════════════════════════════════════════════════════
	#  ① 这条缝真的通吗 —— 喂不同入参必须得到不同答案
	# ══════════════════════════════════════════════════════════════
	_isolate_quota_reason()
	_gs.ranked_used = int(_P2.RANKED_QUOTA)          # 配额打满
	_gs.promoted = true                               # 有闯关赛资格
	_gs.gauntlet_wins = 1
	_gs.gauntlet_losses = 1
	var T_THU: int = MON + 3 * D
	var T_SAT: int = MON + 5 * D + 43200
	_ok("① ★分母: 两个时刻的阶段确实不同(ranked vs gauntlet)",
		_P2.phase_at_utc(T_THU) == _P2.PHASE_RANKED \
			and _P2.phase_at_utc(T_SAT) == _P2.PHASE_GAUNTLET,
		"周四=%s 周六=%s" % [_P2.phase_at_utc(T_THU), _P2.phase_at_utc(T_SAT)])
	var q_thu: bool = _gs.ranked_quota_full(T_THU)
	var q_sat: bool = _gs.ranked_quota_full(T_SAT)
	_ok("① ranked_quota_full: 喂不同入参 → 不同答案(证明入参没被默默丢掉)",
		q_thu != q_sat, "周四=%s 周六=%s" % [str(q_thu), str(q_sat)])
	_ok("① ranked_quota_full: 方向也对(积分赛日打满=true / 闯关赛日不吃配额=false)",
		q_thu and not q_sat, "周四=%s 周六=%s" % [str(q_thu), str(q_sat)])
	var g_thu: bool = _gs.gauntlet_can_play(T_THU)
	var g_sat: bool = _gs.gauntlet_can_play(T_SAT)
	_ok("① gauntlet_can_play: 喂不同入参 → 不同答案", g_thu != g_sat,
		"周四=%s 周六=%s" % [str(g_thu), str(g_sat)])
	_ok("① gauntlet_can_play: 方向也对(只有周六放行)", g_sat and not g_thu,
		"周四=%s 周六=%s" % [str(g_thu), str(g_sat)])
	## ★★兜底也必须听全局缝 —— 这两个函数原来是全仓唯一不听它的时钟判据。
	_P2.now_override_ts = T_SAT
	var q_seam_sat: bool = _gs.ranked_quota_full()
	_P2.now_override_ts = T_THU
	var q_seam_thu: bool = _gs.ranked_quota_full()
	_P2.now_override_ts = 0
	_ok("① ★不带参时也走全局缝(不再就地读系统钟): 缝一动答案就跟着动",
		q_seam_thu != q_seam_sat and q_seam_thu == q_thu and q_seam_sat == q_sat,
		"缝=周四 → %s / 缝=周六 → %s" % [str(q_seam_thu), str(q_seam_sat)])
	_ok("① ★收尾: 全局缝已还原成 0", int(_P2.now_override_ts) == 0)

	# ══════════════════════════════════════════════════════════════
	#  ② + ④ 真建一屏: 屏幕说的「今天」与商店锁按的「今天」必须是同一天
	# ══════════════════════════════════════════════════════════════
	var days := [
		["周四·积分赛", MON + 3 * D + 43200, "本周"],
		["周六·闯关赛", MON + 5 * D + 43200, "闯关赛"],
		["周日·决赛日", MON + 6 * D + 43200, "决赛日"],
	]
	for row in days:
		var tag: String = str(row[0])
		var pin: int = int(row[1])
		var want_word: String = str(row[2])
		var scene = MENU.new()
		scene.clock_override_ts = pin          # ★必须在 _ready 之前钉(paint_ts 在那里算)
		add_child(scene)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame

		# ── 分母: 这一屏真建起来了(否则下面全是空检查) ──
		var built: bool = scene.content_root != null and scene.page_box != null
		_ok("② [%s] ★分母: 这一屏真建起来了" % tag, built,
			"content_root=%s page_box=%s" % [str(scene.content_root != null), str(scene.page_box != null)])
		if not built:
			scene.queue_free()
			continue
		var strip: Node = scene.content_root.find_child(str(MENU.WEEK_CARDS_NAME), true, false)   # 赛程页四张卡(2026-10-06 从七格横条换成整页)
		var shop_txt: String = _shop_line(scene)
		## 「今天」读数: 吃配额的日子在开始战斗上方的计数条; 周六/周日在模式卡里(2026-10-05 第四轮)。
		var two: Node = scene.content_root.find_child(str(MENU.TODAY_COUNTER_NAME), true, false)
		if two == null:
			two = scene.content_root.find_child(str(MENU.MODE_CARD_NAME), true, false)
		var l2 := ""
		if two != null:
			var tl: Array = []
			_texts(two, tl)
			l2 = " | ".join(PackedStringArray(tl))
		_ok("② [%s] ★分母: 三处读数都画出来了(状态行 L2 / 赛程条 / 商店那一行)" % tag,
			l2 != "" and strip != null and shop_txt != "",
			"L2=「%s」 strip=%s 商店=「%s」" % [l2, str(strip != null), shop_txt])

		# ── ④ 一屏只读一次钟 ──
		_ok("④ [%s] ★一屏只问了一次「现在几点」" % tag,
			int(scene._clock_reads) == 1, "_clock_reads=%d" % int(scene._clock_reads))

		# ── ② 屏幕说的「今天」 vs 商店锁按的「今天」 ──
		_ok("② [%s] 状态行 L2 说的就是钉住那一天" % tag,
			l2.find(want_word) >= 0, "要有「%s」· 实际「%s」" % [want_word, l2])
		var painted_lock: bool = _shop_locked(scene)
		var entry_says: bool = _gs.ranked_quota_full(pin)
		_ok("② [%s] ★★画出来的锁 = _open_shop() 真正的判据(一屏不许两条钟)" % tag,
			painted_lock == entry_says,
			"画出来「%s」(锁=%s) · ranked_quota_full(钉住那刻)=%s" % [
				shop_txt, str(painted_lock), str(entry_says)])
		## ★同一屏的第三处: 「开始战斗」被拦的那句话也必须按同一天算。
		## ★尺子是「那句话提没提**配额**」, 不是「拦没拦」 —— 周六/周日还有自己的
		##   拦截理由(闯关赛闸 / 决赛日闸), 拿「拦没拦」当尺子会把那两条也算进来,
		##   于是只剩周四一天作数(剩下两天是空检查)。
		##   现在三天都真在判: 周四必须提配额, 周六/周日必须不提。
		var blk: String = str(scene._battle_block_msg(pin))
		var want_block: bool = _gs.ranked_quota_full(pin)
		_ok("② [%s] 「开始战斗」那句话提不提配额, 也跟同一天" % tag,
			(blk.find("配额") >= 0) == want_block,
			"拦=「%s」· 打满=%s" % [blk, str(want_block)])

		# ── ④(续) 传了入参之后**一次都不许再读钟**
		#    ★这一条专抓「改了签名而函数体还在读全局」: 入参被默默丢掉时计数会涨。
		var reads0: int = int(scene._clock_reads)
		var _l: Array = _status_lines(scene, pin)
		var _s2: String = _repaint_entries(scene, pin)
		_ok("④ [%s] ★带参调用三处画面函数 → 计数一次都没涨(入参没被丢掉)" % tag,
			int(scene._clock_reads) == reads0,
			"调用前 %d → 调用后 %d" % [reads0, int(scene._clock_reads)])
		_ok("④ [%s] ★分母: 那两次重画真的产出了东西(否则上一条是空检查)" % tag,
			_l.size() >= 2 and _s2 != "",
			"状态行 %d 行 · 商店「%s」" % [_l.size(), _s2])

		scene.queue_free()
		await get_tree().process_frame

	# ══════════════════════════════════════════════════════════════
	#  ③ 边界时刻逐个走(相位界两侧各 1 秒 + 周界)
	# ══════════════════════════════════════════════════════════════
	var scene_b = MENU.new()
	scene_b.clock_override_ts = MON + 3 * D + 43200
	add_child(scene_b)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if scene_b.page_box == null:
		_ok("③ ★分母: 边界用的那一屏建起来了", false, "page_box == null")
	else:
		var edges := [
			["周一 00:00:00", MON],
			["周四 12:00:00", MON + 3 * D + 43200],
			["周五 23:59:59", MON + 5 * D - 1],
			["周六 00:00:00", MON + 5 * D],
			["周六 23:59:59", MON + 6 * D - 1],
			["周日 00:00:00", MON + 6 * D],
			["周日 23:59:59", MON + 7 * D - 1],
			["下周一 00:00:00", MON + 7 * D],
		]
		var n_true := 0
		var n_false := 0
		var asked := 0
		var answers: Array = []
		for e in edges:
			var tag2: String = str(e[0])
			var t: int = int(e[1])
			var painted: bool = _repaint_entries(scene_b, t) != "" and _shop_locked(scene_b)
			var says: bool = _gs.ranked_quota_full(t)
			asked += 1
			answers.append(says)
			if says:
				n_true += 1
			else:
				n_false += 1
			_ok("③ [%s · %s] 画出来的锁 = 入口的判据" % [tag2, _P2.phase_at_utc(t)],
				painted == says, "画=%s 判=%s" % [str(painted), str(says)])
		_ok("③ ★分母: 构造了 %d 个边界时刻, 每个都被【画】和【判】各问了一次" % asked,
			asked == edges.size() and asked == 8, "asked=%d" % asked)
		_ok("③ ★分母: 这组时刻的答案**既有 true 也有 false**(否则整组是空检查)",
			n_true > 0 and n_false > 0, "true=%d false=%d" % [n_true, n_false])
		## ★每一对边界两侧必须**真的翻**了 —— 不翻就说明这条界没落在判据上,
		##   那一对就等于测了两遍同一个点(memory `fb-judge-must-fit-the-shape`)。
		var pairs := [[2, 3, "周五末→周六初"], [5, 6, "周六末→周日初(同为不吃配额, 不该翻)"],
			[6, 7, "周日末→下周一初(周界)"]]
		for pr in pairs:
			var i0: int = int(pr[0])
			var i1: int = int(pr[1])
			var must_flip: bool = str(pr[2]).find("不该翻") < 0
			var flipped: bool = bool(answers[i0]) != bool(answers[i1])
			_ok("③ 边界 %s: %s" % [str(pr[2]), "答案确实翻了" if must_flip else "答案确实没翻"],
				flipped == must_flip, "%s → %s" % [str(answers[i0]), str(answers[i1])])
	scene_b.queue_free()
	await get_tree().process_frame

	# ══════════════════════════════════════════════════════════════
	#  ⑤ 源码扫 —— 谁绕过 `_now_ts()` 直接读钟, ④ 的计数器是瞎的
	# ══════════════════════════════════════════════════════════════
	var mm_raw := FileAccess.get_file_as_string("res://scripts/scenes/MainMenuScene.gd")
	_ok("⑤ ★分母: 读到了 MainMenuScene.gd 源码", mm_raw.length() > 10000,
		"%d 字节" % mm_raw.length())
	var mm := _code_only(mm_raw)
	_ok("⑤ ★分母: 扔掉整行注释后还剩大半(切过头的话下面全是空检查)",
		mm.length() > mm_raw.length() / 3, "%d / %d 字节" % [mm.length(), mm_raw.length()])
	_ok("⑤ MainMenuScene 代码行里**一次都不许**就地读系统钟",
		mm.count("Time.get_unix_time_from_system") == 0,
		"%d 处" % mm.count("Time.get_unix_time_from_system"))
	_ok("⑤ `_P2C.now_utc()` 只许出现 1 次(就在 `_now_ts()` 里, 全屏唯一的真实钟入口)",
		mm.count("_P2C.now_utc()") == 1, "%d 处" % mm.count("_P2C.now_utc()"))
	_ok("⑤ 不许有**不带参**的 `ranked_quota_full()` —— 那正是 2026-09-29 修掉的那条",
		mm.count("ranked_quota_full()") == 0, "%d 处" % mm.count("ranked_quota_full()"))
	_ok("⑤ 不许有**不带参**的 `gauntlet_can_play()`",
		mm.count("gauntlet_can_play()") == 0, "%d 处" % mm.count("gauntlet_can_play()"))
	## ★分母: 这条扫描抓得住东西吗 —— 带参的那些必须**扫得到**, 否则 needle 写错了也全绿。
	_ok("⑤ ★分母: 带参的 `ranked_quota_full(` 确实扫得到(needle 没写错)",
		mm.count("ranked_quota_full(") >= 2, "%d 处" % mm.count("ranked_quota_full("))

	var gs_raw := FileAccess.get_file_as_string("res://autoload/GameState.gd")
	_ok("⑤ ★分母: 读到了 GameState.gd 源码", gs_raw.length() > 10000,
		"%d 字节" % gs_raw.length())
	for sig in ["func ranked_quota_full(", "func gauntlet_can_play("]:
		var body := _code_only(_func_body(gs_raw, sig))
		_ok("⑤ ★分母: 切出了 `%s` 的函数体" % sig, body.length() > 40,
			"%d 字节" % body.length())
		_ok("⑤ `%s` 的兜底走全局缝, 不就地读系统钟" % sig,
			body.count("Time.get_unix_time_from_system") == 0 \
				and body.count("_P2.now_utc()") == 1,
			"系统钟 %d 处 / now_utc %d 处" % [
				body.count("Time.get_unix_time_from_system"), body.count("_P2.now_utc()")])

	# ── 还原 ──
	_gs.hearts = k_h
	_gs.season_total_battles = k_b
	_gs.ranked_used = k_u
	_gs.promoted = k_p
	_gs.gauntlet_wins = k_gw
	_gs.gauntlet_losses = k_gl
	_P2.now_override_ts = k_seam
	_ok("★收尾: 动过的字段都还原了(含全局缝)",
		int(_gs.ranked_used) == k_u and int(_P2.now_override_ts) == k_seam)

	if _fail == 0:
		print("ALL PASS — 主菜单一屏只许一条时钟 (%d/%d)" % [_n, _n])
	else:
		print("FAILED: %d/%d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
