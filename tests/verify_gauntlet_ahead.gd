extends Node
## verify_gauntlet_ahead.gd — 「这一周后面还有什么可打」那一族说谎级缺陷 (2026-09-28)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么 —— 三条**产品在对玩家说谎**的缺陷
## ══════════════════════════════════════════════════════════════════════
## ① 周二~周五: 已过晋级线的人被告知「💀 本大轮已出局 · 下周一开新的一轮」。
##    根因: `_gauntlet_ahead()` 问的是 `GameState.gauntlet_eligible()`(= `promoted`),
##    而 `promoted` 全仓**只有 `settle_ranked_close()` 一个写入点**, 那个函数开头就
##    「周五 23:00 UTC 之前直接 return」⇒ **周一~周五那一支结构上恒假**。
##    探针 `tests/_probe_promote_ahead.gd` 实测: `season_wins=20`(线=5)、配额打满、0 命
##    ⇒ 七天里「周六闯关赛见」**0 次出现**; 手动把 `promoted` 置 true 才出现在周一~周五。
##    ★最讽刺的是 `_gauntlet_ahead()` 自己的头注写着它就是为了防这件事
##      (「跟开关走就会对其中一个说谎」), 而那件事正发生在它身上。
##
## ② 周日: 状态行摆着 `♥ N/8` 与 `本周 N/24` —— **两个数周日全程冻结**
##    (`phase_uses_ranked_quota(FINALS)=false`; `finals_settle_sealed()`/`finals_reveal()`
##     一个字都不碰 `hearts`)。周六 2026-09-22 就为这件事修过并焊了门禁
##    (`verify_gauntlet.gd` ⑦「周六的读数里没有积分赛配额那个数」), **周日漏了**。
##
## ③ `_status_row()` 调 `_gauntlet_status_line()` **不传参** ⇒ 那一行读真实系统时钟,
##    而同文件的 `_battle_block_msg` / `_open_shop` / `_start_battle_flow` 都走
##    `_now_ts()`(可注入) ⇒ 那一行**一周只有一天会被门禁执行到**, 周六/周日两支改坏没人红。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★① 「晋级到底看什么」**查实而不是相信注释**: 扫源码点出 `promoted` 的写入点个数,
##     再走产品自己的 `settle_ranked_close()` 穷举胜场 0..线+5 看翻转点。
##     —— 「过了线就铁定晋级」这句话是 `_gauntlet_ahead_tail()` 敢说「周六闯关赛见」的
##     **唯一依据**; 将来加了名额上限/排名截断, 这一节就该红。
## ★② 七天全量 + **走真入口**(`_start_battle_flow()` / `_open_shop()` 读真的飘出来那行字),
##     不只调 `_msg_*()` —— 只调消息函数等于在测我自己新写的函数
##     (memory `fb-verify-must-run-the-real-path`)。
##     每条判据配一条**反向分母**: 同一个人差一场没过线时, 那句话必须变回「下周一」。
## ★③ 状态行走**真渲染路径**: 建三次 `MainMenu.tscn`, 各钉一个已知日期, 从场景树里
##     读那一行 Label 的字。改回「不传参」⇒ 三天的字全一样 ⇒ 这一节当场红。
## ★④ 顺带量**真实字宽**(框只有 `LEFT_W - 8` = 374px): 词换长了顶穿控件, 靠眼睛看不出来。
##
## 跑法: <godot> --headless --path . res://tests/verify_gauntlet_ahead.tscn --quit-after 900

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const MENU := preload("res://scripts/scenes/MainMenuScene.gd")

## 真实日历样本(UTC), 与 `verify_gauntlet` / `verify_week_season` ⑥ **同一周**
## —— 那边已把这几个时间戳与星期几核对过, 这里不另立一套(两份必然漂)。
const MON := 1789344000    # 2026-09-14 周一 00:00 UTC
const NOON := 43200
const THU := 1789603200    # 2026-09-17 周四 00:00
const SAT := 1789776000    # 2026-09-19 周六 00:00
const SUN := 1789862400    # 2026-09-20 周日 00:00
const WD := ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

## ★2026-10-05 第四轮: 周六/周日的当天读数住进「今天」模式卡第二行(去掉与卡标题重复的赛制名)。
##   框宽 = 模式卡第二行的宽(`MODE_SIZE.x - 36`), 字号 = `MODE_RULE_FONT`。★不抄数字, 从产品的常量算。
var ROW_BOX_W: float = float(MENU.MODE_SIZE.x) - 36.0
var ROW_FONT: int = int(MENU.MODE_RULE_FONT)
var L2_FONT: int = int(MENU.MODE_RULE_FONT)

var _n := 0
var _fail := 0
var _gs = null
var _bak := {}


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	_gs.test_mode = true
	## ★跑完按字段还原 —— 门禁写 GameState 会落盘污染玩家存档(本仓栽过)。
	for k in ["promoted", "season_wins", "ranked_used", "hearts", "gauntlet_wins",
			"gauntlet_losses", "gauntlet_backfill_paid", "backfill_paid", "week_anchor_ts",
			"season_start_ts", "season_total_battles", "season_id", "season_level",
			"season_xp", "meta_deepsea_coins", "candy_jar_count", "season_eggs_killed",
			"titles", "week_phase", "axe_exp_bar", "axe_exp_total"]:
		_bak[k] = _gs.get(k)

	print("=== 「本周后面还有什么可打」三条说谎级缺陷 ===")
	_t_promote_rule()
	await _t_ahead_seven_days()
	_t_sunday_row()
	await _t_real_render()
	_t_locks()

	for k in _bak:
		_gs.set(k, _bak[k])
	_ok("★收尾: GameState 已还原(promoted / season_wins)",
		bool(_gs.promoted) == bool(_bak["promoted"]) \
			and int(_gs.season_wins) == int(_bak["season_wins"]),
		"promoted=%s season_wins=%d" % [str(_gs.promoted), int(_gs.season_wins)])
	## ★全局时间缝也要还原 —— 它是 static, 漏还原会波及同进程后面的用例。
	_ok("★收尾: phase2_config.now_override_ts 仍是 0", int(P2.now_override_ts) == 0,
		"now_override_ts=%d" % int(P2.now_override_ts))

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 本周后面还有什么可打" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 晋级到底看什么 —— 查实, 不是相信注释
# ─────────────────────────────────────────────────────────────
func _t_promote_rule() -> void:
	print("── ① 晋级条件查实(「过线 = 铁定晋级」这句话的依据) ──")
	var src: String = FileAccess.get_file_as_string("res://autoload/GameState.gd")
	_ok("① ★分母: 读到 GameState 源码", src.length() > 10000, "%d 字符" % src.length())

	## (a) `promoted` 的赋值行**逐行列出来**。判据是"能写成 true 的只有一处" ——
	##     多一处就意味着存在第二条晋级路径, 而那时「过线 = 铁定晋级」就不成立了。
	var writes: Array = []
	for line in src.split("\n"):
		var t: String = line.strip_edges()
		if t.begins_with("#") or t.begins_with("var promoted"):
			continue
		if t.find("promoted =") < 0:
			continue
		writes.append(t)
	print("     GameState 里 `promoted =` 的赋值行 %d 条(★分母):" % writes.size())
	for w in writes:
		print("       " + str(w))
	_ok("① ★分母: 真扫到了赋值行(0 条 = 我的扫法坏了, 不是代码干净)", writes.size() >= 3,
		"%d 条" % writes.size())
	var truthy: Array = []
	for w in writes:
		## 清零(换轮/重置存档)与存档还原不是"判定晋级", 排掉
		if str(w).find("= false") >= 0 or str(w).find("bool(data") >= 0:
			continue
		truthy.append(str(w))
	_ok("① ★★能把 promoted 写成 true 的地方**只有一处**(多一处 = 有第二条晋级路径)",
		truthy.size() == 1, str(truthy))
	_ok("① ★★那一处的判据就是 `gauntlet_line_reached()`(= season_wins ≥ 硬线), 没有别的项",
		truthy.size() == 1 and str(truthy[0]).find("gauntlet_line_reached()") >= 0, str(truthy))

	## (b) **没有排名截断** —— 这是「过线就一定晋级」成立的前提之一。
	##     ★★2026-09-30: 原稿的「前 30%」(`PROMOTE_TOP_PCT`) 已**整个删掉** ——
	##       用户当场把晋级线重定成「≥PROMOTE_WINS 胜且不出局」, 那是一条**绝对线**,
	##       按定义不需要排名截断。原来这里断言那个常量"零读取", 现在常量不存在了,
	##       断言得换成**它真的不存在** —— 否则这一节会变成对着一个空名字的恒真式。
	var files: Array = []
	_collect_gd("res://scripts", files)
	_collect_gd("res://autoload", files)
	_ok("① ★分母: 扫到 %d 个 .gd(少于 60 = 我的目录走法坏了)" % files.size(),
		files.size() >= 60, "%d 个" % files.size())
	var top_pct_hits: Array = []
	var floor_hits := 0
	for f in files:
		var s: String = FileAccess.get_file_as_string(f)
		for line in s.split("\n"):
			var t: String = line.strip_edges()
			if t.begins_with("#"):
				continue
			if t.find("PROMOTE_TOP_PCT") >= 0:
				top_pct_hits.append("%s: %s" % [f, t])
			if t.find("PROMOTE_WINS") >= 0 and t.find("const PROMOTE_WINS") < 0:
				floor_hits += 1
	## ★这一条只证明「扫法本身找得到读取点」(否则下一条是空检查) ⇒ 门槛 1 就够。
	_ok("① ★分母: 同一个扫法**找得到** PROMOTE_WINS 的读取点(%d 处) —— 否则下一条是空检查" % floor_hits,
		floor_hits >= 1, "%d 处" % floor_hits)
	_ok("① ★★没有排名截断: `PROMOTE_TOP_PCT`(前 30%) **连声明都不存在了**(2026-09-30 删)",
		top_pct_hits.is_empty(), str(top_pct_hits))

	## (c) 走**产品自己的** `settle_ranked_close()` 穷举胜场, 看翻转点在哪一格。
	var fl: int = int(P2.PROMOTE_WINS)
	var anchor: int = P2.week_anchor_utc(MON + NOON)
	var close_ts: int = P2.ranked_close_ts(anchor)
	_ok("① ★分母: 收盘时刻算得出来且在这一周内", close_ts > anchor and close_ts < anchor + 7 * 86400,
		"anchor=%d close=%d" % [anchor, close_ts])
	var flips: Array = []
	for w in range(0, fl + 6):
		_gs.week_anchor_ts = anchor
		_gs.promoted = false
		_gs.season_wins = w
		_gs.ranked_used = int(P2.RANKED_QUOTA)     # 配额打满 ⇒ 补发 0 场, 不给这一节掺币/经验噪声
		_gs.backfill_paid = 0
		_gs.settle_ranked_close(close_ts + 60)
		flips.append(1 if bool(_gs.promoted) else 0)
	var want: Array = []
	for w in range(0, fl + 6):
		want.append(1 if w >= fl else 0)
	print("     胜场 0..%d 收盘后 promoted = %s   (线 = %d)" % [fl + 5, str(flips), fl])
	_ok("① ★★晋级判据**只有胜场**: 穷举 0..%d, 翻转点一格不差落在 %d" % [fl + 5, fl],
		flips == want, "实测 %s / 期望 %s" % [str(flips), str(want)])
	_ok("① ★分母: 这一列里既有 0 也有 1(全 0 或全 1 = 那一维白分了)",
		flips.has(0) and flips.has(1), str(flips))
	_ok("① ★★没有名额上限: 胜场高出线 5 场照样全是 1(有上限的话尾部会掉回 0)",
		flips.slice(fl) == [1, 1, 1, 1, 1, 1], str(flips.slice(fl)))

	## (d) ★★★bug ① 的根因证据: **收盘前** promoted 恒假, 而线早就过了。
	_gs.promoted = false
	_gs.season_wins = fl + 15
	_gs.settle_ranked_close(close_ts - 60)
	_ok("① ★★★收盘前 promoted **恒假** ⇒ 周一~周五拿它当「还有东西打吗」的判据就是说谎",
		not bool(_gs.promoted), "season_wins=%d promoted=%s" % [
			int(_gs.season_wins), str(_gs.promoted)])
	_ok("① ★而 `gauntlet_line_reached()` 这时**已经是真的** —— 它才是收盘前能问的那个问题",
		_gs.gauntlet_line_reached(), "season_wins=%d 线=%d" % [int(_gs.season_wins), fl])
	_gs.season_wins = fl - 1
	_ok("① ★分母: 差一场时 `gauntlet_line_reached()` 必须是假(恒真 = 假判据)",
		not _gs.gauntlet_line_reached(), "season_wins=%d" % int(_gs.season_wins))


## 递归收 .gd 路径。★不按"我以为的层级"走, 一路递到底
## (memory `fb-recursive-scan-not-structured-walk`)。
func _collect_gd(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var nm: String = d.get_next()
	while nm != "":
		if nm.begins_with("."):
			nm = d.get_next()
			continue
		var p: String = dir.path_join(nm)
		if d.current_is_dir():
			_collect_gd(p, out)
		elif nm.ends_with(".gd"):
			out.append(p)
		nm = d.get_next()
	d.list_dir_end()


# ─────────────────────────────────────────────────────────────
# ② 七天全量 × 真入口: 过了线的人不许被告知「本周完了」
# ─────────────────────────────────────────────────────────────
func _t_ahead_seven_days() -> void:
	print("── ② 收盘前七天全量(走真入口 _start_battle_flow / _open_shop) ──")
	var pk = load("res://scenes/MainMenu.tscn")
	_ok("② ★分母: 载得到 MainMenu.tscn", pk != null)
	if pk == null:
		return
	var mm = pk.instantiate()
	get_tree().root.add_child(mm)
	for _i in range(6):
		await get_tree().process_frame

	var fl: int = int(P2.PROMOTE_WINS)
	## ★★收盘前的**真实状态**: `promoted` 一定是 false(见 ①d)。这一节一个字都不手改它 ——
	##   手改 promoted 就是在测一个玩家周一~周五根本不可能处在的状态。
	_gs.promoted = false
	_gs.gauntlet_wins = 0
	_gs.gauntlet_losses = 0
	_gs.week_anchor_ts = P2.week_anchor_utc(MON + NOON)

	for grp in ["过线", "差一场"]:
		_gs.season_wins = fl if grp == "过线" else fl - 1
		## ★★命数**不手写, 由战绩推** —— 手写就会造出一个玩家不可能处在的状态。
		##   2026-09-30 晋级线改成「≥PROMOTE_WINS 胜 且 不出局」之后,
		##   原来这里写死的 `hearts = 0` 让「过线」那组变成
		##   **11 胜 + 0 命** —— 而那在新数字下**数学上不可能**:
		##   11 胜 + 6 负 = 17 场 > 16 配额, 而周六/周日都不掉命。
		##   ⇒ 造一个不可能的状态去测消息分支, 测的是一个玩家永远读不到的句子。
		## ★推出来之后两组正好各自落在有意义的状态上:
		##   · 过线   11胜5负 → 命 1, 还活着 → 该被指向周六
		##   · 差一场 10胜6负 → 命 0, 已淘汰 → 该说下周一
		##   「已淘汰」那条分支仍然被走到(由"差一场"那组), 没变成死代码。
		_gs.ranked_used = int(P2.RANKED_QUOTA)
		_gs.hearts = maxi(0, int(P2.HEARTS_MAX) - (int(_gs.ranked_used) - int(_gs.season_wins)))
		var said: Array = []                          # 周一~周五那五句
		for d in range(7):
			var ts: int = MON + d * 86400 + NOON
			mm.clock_override_ts = ts
			var pre: String = str(mm._battle_block_msg(ts))
			## ★分母 + 保命: 没被拦住的话 `_start_battle_flow()` 会 change_scene,
			##   当场把门禁自己拆掉(`get_tree()` 变 null, 后面一条都不跑且 rc=0)。
			if pre == "":
				_ok("② ★%s/%s: 竟然放行了(0 命 + 配额打满不该有任何一天能打)" % [grp, WD[d]], false)
				continue
			var kids0: Array = mm.get_children()
			mm._start_battle_flow()
			var toast := ""
			for ch in mm.get_children():
				if not kids0.has(ch) and ch is Label:
					toast = str((ch as Label).text)
					ch.queue_free()
			if toast == "":
				_ok("② ★%s/%s ★分母: 真入口没飘出那行字(演出没走到 = 下面全是空检查)" % [grp, WD[d]], false)
				continue
			print("     %-4s %s %-8s 「%s」" % [grp, WD[d], P2.phase_at_utc(ts), toast])
			## ★2026-10-05 周一休赛不开放对战(用户「周一哪来的比赛」) ⇒ 周一说休赛, 周二~周五四天说晋级/下周一。
			if d == 0:
				_ok("② ★%s/周一: 拦截说的是「今日休赛」" % grp, toast.find("休赛") >= 0, toast)
			elif d <= 4:
				said.append(toast)
		_ok("② ★分母(%s): 周二~周五四天都拿到了那句话" % grp, said.size() == 4, "%d 句" % said.size())
		var ok_ahead := 0
		var ok_next_week := 0
		for s in said:
			if str(s).find("闯关赛") >= 0 and str(s).find("下周一") < 0:
				ok_ahead += 1
			if str(s).find("下周一") >= 0 and str(s).find("闯关赛") < 0:
				ok_next_week += 1
		if grp == "过线":
			_ok("② ★★★过了晋级线的人, **周二~周五四天**都要被指向周六闯关赛, 一天都不许说「下周一」",
				ok_ahead == 4, "4 天里只有 %d 天说对" % ok_ahead)
		else:
			_ok("② ★分母: 差一场没过线的人, 四天都必须说「下周一」且**不许**提闯关赛(他周六打不了)",
				ok_next_week == 4, "4 天里只有 %d 天说对" % ok_next_week)

	## ★★另一条真入口: 商店那一把锁走 `_msg_quota_full()`。两个入口共用同一句话,
	##   只验一个入口 = 另一个改坏了没人红(它们 2026-09-17 之前就是各写一份的)。
	_gs.hearts = 8                                   # 不淘汰, 让闸落在"配额打满"这一条上
	_gs.ranked_used = int(P2.RANKED_QUOTA)
	_gs.season_total_battles = 24
	for grp2 in ["过线", "差一场"]:
		_gs.season_wins = fl if grp2 == "过线" else fl - 1
		mm.clock_override_ts = THU + NOON
		_ok("② ★分母(商店/%s): 这一刻确实配额打满(否则会切到商店场景)" % grp2,
			_gs.ranked_quota_full(mm.clock_override_ts), "ranked_used=%d" % int(_gs.ranked_used))
		var kids1: Array = mm.get_children()
		mm._open_shop()
		var t2 := ""
		for ch2 in mm.get_children():
			if not kids1.has(ch2) and ch2 is Label:
				t2 = str((ch2 as Label).text)
				ch2.queue_free()
		print("     商店/%-4s 周四 「%s」" % [grp2, t2])
		if grp2 == "过线":
			_ok("② ★★商店那一把锁也要指向周六(两个入口共用 `_msg_quota_full()`)",
				t2.find("闯关赛") >= 0 and t2.find("下周一") < 0, t2)
		else:
			_ok("② ★分母: 没过线时商店那句必须说「下周一」(恒说闯关赛 = 上一条白分)",
				t2.find("下周一") >= 0 and t2.find("闯关赛") < 0, t2)

	mm.clock_override_ts = 0
	mm.queue_free()
	await get_tree().process_frame


# ─────────────────────────────────────────────────────────────
# ③ 周日状态行: 不许摆两个周日绝不会动的数
# ─────────────────────────────────────────────────────────────
func _t_sunday_row() -> void:
	print("── ③ 周日状态行(照周六 2026-09-22 那条的样子补) ──")
	## (a) **依据先立住**: 那两个数周日真的不动 —— 量产品自己的账, 不引我的结论。
	_ok("③ ★分母: 周日不吃积分赛配额(产品自己的判据 phase_uses_ranked_quota)",
		not P2.phase_uses_ranked_quota(P2.PHASE_FINALS))
	_ok("③ ★分母: 而积分赛那几天**吃**(一律 false = 那一维白分了)",
		P2.phase_uses_ranked_quota(P2.PHASE_RANKED))
	_gs.hearts = 5
	_gs.ranked_used = 7
	var h0: int = int(_gs.hearts)
	var u0: int = int(_gs.ranked_used)
	_gs.finals_settle_sealed()
	_gs.finals_reveal(true)
	_ok("③ ★★打完一轮决赛日(走产品自己的 finals_settle_sealed + finals_reveal), " \
			+ "hearts 与 ranked_used **一个都没动** ⇒ 摆在状态行里只会误导",
		int(_gs.hearts) == h0 and int(_gs.ranked_used) == u0,
		"hearts %d→%d  ranked_used %d→%d" % [h0, int(_gs.hearts), u0, int(_gs.ranked_used)])

	## (b) 周日三态各说各的, 且**一个都不许**带那两个数。
	var m = MENU.new()
	_gs.promoted = true
	_gs.gauntlet_wins = 4
	_gs.gauntlet_losses = 1
	var s_in: String = str(m._phase_status_line(SUN + NOON))
	_gs.gauntlet_wins = 1
	_gs.gauntlet_losses = 3
	var s_try: String = str(m._phase_status_line(SUN + NOON))
	_gs.promoted = false
	_gs.gauntlet_wins = 0
	_gs.gauntlet_losses = 0
	var s_no: String = str(m._phase_status_line(SUN + NOON))
	print("     进了决赛日 「%s」" % s_in)
	print("     闯关赛止步 「%s」" % s_try)
	print("     本周没晋级 「%s」" % s_no)
	_ok("③ ★分母: 周日三态都拿到了非空读数(空串 = 回落到积分赛那一行, 缺陷照旧)",
		s_in != "" and s_try != "" and s_no != "")
	_ok("③ ★★★周日的读数里**没有积分赛配额那个数**(它周日不动, 摆着只会误导)",
		s_in.find("/%d" % int(P2.RANKED_QUOTA)) < 0 and s_try.find("/%d" % int(P2.RANKED_QUOTA)) < 0 \
			and s_no.find("/%d" % int(P2.RANKED_QUOTA)) < 0,
		"「%s」/「%s」/「%s」" % [s_in, s_try, s_no])
	_ok("③ ★★★周日的读数里**没有命那个数**(`finals_*` 一个字都不碰 hearts)",
		s_in.find("♥") < 0 and s_try.find("♥") < 0 and s_no.find("♥") < 0,
		"「%s」/「%s」/「%s」" % [s_in, s_try, s_no])
	_ok("③ ★三态两两不同(有一对一样 = 那一维白分了)",
		s_in != s_try and s_try != s_no and s_in != s_no)
	## 指路那一句住在同一张模式卡的倒计时行(「查看对阵图 »」), 读数这一行只说「已晋级」—— 一张卡上不说两遍。
	_gs.promoted = true
	_gs.gauntlet_wins = 4
	_gs.gauntlet_losses = 1
	var sun_card: String = " | ".join(PackedStringArray(m.mode_card_lines(SUN + NOON)))
	_gs.promoted = false
	_gs.gauntlet_wins = 0
	_gs.gauntlet_losses = 0
	_ok("③ ★进了决赛日的人要**指路**(模式卡上有对阵图的去处, 不在「开始战斗」后)",
		s_in.find("已晋级") >= 0 and sun_card.find("对阵图") >= 0, "%s / %s" % [s_in, sun_card])
	_ok("③ ★★打过闯关赛没打进的人: **不许说他「没晋级」**(周一~五刚夸过他已过晋级线) —— " \
			+ "与 `finals_block_msg(false, true)` 同一个口径",
		s_try.find("未晋级") < 0, s_try)
	_ok("③ ★连资格都没拿到的人: 说「没晋级」是对的", s_no.find("未晋级") >= 0, s_no)

	## (c) 分派真的按天走: 周一~周五回落(空串), 周六是闯关赛那一段, 周日是决赛日那一段。
	_gs.promoted = true
	_gs.gauntlet_wins = 2
	_gs.gauntlet_losses = 1
	var per_day: Array = []
	for d in range(7):
		per_day.append(str(m._phase_status_line(MON + d * 86400 + NOON)))
	print("     七天: %s" % str(per_day))
	var empties := 0
	for d in range(5):
		if str(per_day[d]) == "":
			empties += 1
	_ok("③ ★分母: 周一~周五五天全回落到积分赛那一行(非空 = 把别的天也换掉了)",
		empties == 5, "%d 天空串" % empties)
	_ok("③ ★周六那一段是闯关赛(2026-09-22 已有的行为不许被我改掉)",
		str(per_day[5]).find("闯关赛") >= 0, str(per_day[5]))
	_ok("③ ★周日那一段是决赛日", str(per_day[6]).find("决赛日") >= 0, str(per_day[6]))

	## (d) 字宽 —— ★★2026-09-28 改口径: 状态行拆成两行之后,
	##     相位段**自己占一整行**(17 号字, 框仍是 `LEFT_W - 8`), 身份段在它上面另一行。
	##     所以这里量的是「相位段一个人装不装得进 374」, 不再拼 `第 N 大轮 · Lv X` 那个前缀。
	##     ★真渲染的顶穿判据在 ④(量 Label 的真实 rect 包不包得住 holder) —— 这里是纯函数那一层,
	##     两层都要: 纯函数这层能穷举所有战绩组合, 真渲染那层才证明产品真的这么画。
	var f = m._bold_font()
	var over: Array = []
	for s0 in [s_in, s_try, s_no]:
		var s: String = MENU._strip_phase_head(str(s0), "决赛日")
		var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, L2_FONT).x
		print("     周日相位段 ink %6.1f / 框 %.0f  「%s」" % [w, ROW_BOX_W, s])
		if w > ROW_BOX_W:
			over.append("%.0f「%s」" % [w, s])
	_ok("③ ★★周日那三句都装得进那一行(顶穿就把词改短, 不许把框改宽)",
		over.is_empty(), str(over))
	## ★★★穷举**所有**闯关赛战绩组合(0..4 胜 × 0..3 负)的周六相位段 —— 门禁不许只量我手里这一种。
	##   周六那句是全屏最长的一行, 而战绩数字会变(再赢 N / 再输 N 两个数跟着变)。
	var wide: Array = []
	var sat_ts: int = MON + 5 * 86400 + NOON
	_gs.promoted = true
	var widest := 0.0
	for gw in range(0, int(P2.GAUNTLET_WINS_IN) + 1):
		for gl in range(0, int(P2.GAUNTLET_LOSSES_OUT) + 1):
			_gs.gauntlet_wins = gw
			_gs.gauntlet_losses = gl
			var sl: String = MENU._strip_phase_head(str(m._phase_status_line(sat_ts)), "闯关赛")
			var sw: float = f.get_string_size(sl, HORIZONTAL_ALIGNMENT_LEFT, -1, L2_FONT).x
			widest = maxf(widest, sw)
			if sw > ROW_BOX_W:
				wide.append("%d-%d %.0f「%s」" % [gw, gl, sw, sl])
	print("     周六相位段 20 种战绩里最宽 %.1f / 框 %.0f" % [widest, ROW_BOX_W])
	_ok("③ ★★★周六**所有**战绩组合的相位段都装得进 %.0f(它是全屏最长的一行)" % ROW_BOX_W,
		wide.is_empty(), str(wide))
	_ok("③ ★分母: 那 20 种真的量到了非零宽度(全 0 = 穷举白跑了)", widest > 100.0,
		"最宽 %.1f" % widest)
	## ★★分母「尺子是活的」: 拿**改之前那种一行写法**(身份段 + 相位段拼一行, 18 号字)再量一次,
	##   它必须仍然**量得出超框** —— 否则上面那一串 PASS 可能只是尺子坏了。
	##   (实测 485 / 框 374, 顶穿 111px, 正是这一版要修的那件事。)
	_gs.gauntlet_wins = 2
	_gs.gauntlet_losses = 1
	var one_line: String = "第 %d 大轮 · Lv %d   %s" % [
		int(_gs.season_id), int(_gs.season_level), str(m._phase_status_line(sat_ts))]
	var one_w: float = f.get_string_size(one_line, HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_FONT).x
	print("     (反证)旧的一行写法 ink %.1f / 框 %.0f 「%s」" % [one_w, ROW_BOX_W, one_line])
	_ok("③ ★分母: 尺子是活的 —— 旧的「拼成一行」写法在同一把尺子下**照旧超框 %.0fpx**" % (one_w - ROW_BOX_W),
		one_w > ROW_BOX_W, "%.0f > %.0f" % [one_w, ROW_BOX_W])
	m.free()


# ─────────────────────────────────────────────────────────────
# ④ 真渲染路径 × 七天全量: 那一行说了什么 + 它到底有没有顶穿控件
#
#  ★★★2026-09-28 从三天扩到七天, 并加上**几何**那一维。
#    起因: 周六那句实测 ink **485px** 而框只有 `LEFT_W - 8` = **374px** ⇒ 顶穿 111px,
#    从 2026-09-22 那条读数上线起就在, 门禁一次都没量到 —— 因为**它一周只渲染一天**,
#    而 `verify_ui_consistency` / `verify_mainmenu_layout` 扫的都是「今天」那一屏。
#    ⇒ 判据必须**逐天钉死时钟**跑七遍, 不许再靠"今天正好是星期几"。
#
#  ★判据量的是**真实 rect**, 不是"我设了多大的 box":
#    `Control` 会把自己夹到 `get_combined_minimum_size()` ⇒ 给 Label 设 box 只是下限,
#    字比 box 宽时它照样长出去、一个错都不报(顶穿就是这么来的)。
#    ⇒ 唯一算数的问题是「这个 Label 的矩形还在 holder 里面吗」。
# ─────────────────────────────────────────────────────────────
func _find_row_texts(n: Node, out: Array) -> void:
	if n is Label:
		var t: String = str((n as Label).text)
		if t.find("大轮") >= 0 and not out.has(t):
			out.append(t)
	for c in n.get_children():
		_find_row_texts(c, out)


## 按**节点名**抓一块(名字从产品常量取)。★不按"第几个子节点"定位 —— 那种抓法一加节点就漂, 而且漂了还是绿的。
func _named(n: Node, nm: String) -> Node:
	if str(n.name) == nm:
		return n
	for c in n.get_children():
		var r: Node = _named(c, nm)
		if r != null:
			return r
	return null


func _all_labels(n: Node, out: Array) -> void:
	if n is Label:
		out.append(n)
	for c in n.get_children():
		_all_labels(c, out)


func _t_real_render() -> void:
	print("── ④ 真渲染路径 × 七天: 钉死日期建 MainMenu, 量那一行的字与矩形 ──")
	var pk = load("res://scenes/MainMenu.tscn")
	_ok("④ ★分母: 载得到 MainMenu.tscn", pk != null)
	if pk == null:
		return
	_gs.promoted = true
	_gs.gauntlet_wins = 2
	_gs.gauntlet_losses = 1
	_gs.hearts = 3
	_gs.ranked_used = 7
	## ★大轮/等级取**两位数**: 「第 9 大轮」与「第 99 大轮」不一样宽, 拿最窄的那种量等于没量。
	_gs.season_id = 99
	_gs.season_level = 99
	var got := {}                # 星期 → L1 身份行
	var l2 := {}                 # 星期 → L2 今天行
	var spill: Array = []        # 顶穿 holder 的 Label
	var built := 0
	print("     %-4s %-7s %-7s  %s" % ["天", "框宽", "最宽ink", "两行各说什么"])
	for d in range(7):
		var mm = pk.instantiate()
		## ★注入必须在 add_child **之前** —— `_ready()` 一进树就跑, 之后再设已经晚了。
		mm.clock_override_ts = MON + d * 86400 + NOON
		get_tree().root.add_child(mm)
		## ★等布局落定: `Control` 的最小尺寸是**延迟**算的, 拍早了量到的是 box 不是 ink。
		for _i in range(24):
			await get_tree().process_frame
		## 2026-10-05 第四轮: L1 = 玩家卡里的「第 N 大轮」那一行; L2 = 今天的读数 ——
		##   吃配额的日子在开始战斗上方的计数条(`TODAY_COUNTER_NAME`), 周六/周日在模式卡(赛制名 + 第二行)。
		var card_n: Node = _named(mm, str(MENU.CARD_NAME))
		var cnt_n: Node = _named(mm, str(MENU.TODAY_COUNTER_NAME))
		var mode_n: Node = _named(mm, str(MENU.MODE_CARD_NAME))
		if card_n == null or mode_n == null:
			_ok("④ ★分母(%s): 场景树里找得到玩家卡与模式卡" % WD[d], false)
			mm.queue_free()
			await get_tree().process_frame
			continue
		built += 1
		var sl_n: Node = _named(card_n, str(MENU.SEASON_LINE_NAME))
		got[WD[d]] = str((sl_n as Label).text) if sl_n is Label else ""
		var l2t := ""
		var holders: Array = [card_n, mode_n]
		if cnt_n != null:
			holders.append(cnt_n)
			var tc: Array = []
			_all_labels(cnt_n, tc)
			var parts: Array = []
			for lb in tc:
				parts.append(str((lb as Label).text))
			l2t = "   ".join(PackedStringArray(parts))
		else:
			var mt_n: Node = _named(mode_n, "ModeTitle")
			var mr_n: Node = _named(mode_n, "ModeRule")
			if mt_n is Label and mr_n is Label:
				l2t = "%s %s" % [(mt_n as Label).text, (mr_n as Label).text]
		l2[WD[d]] = l2t
		## ★★★几何: 每一块里**每一个** Label 的矩形都必须还在那一块里面(字比框宽时 Label 照样长出去、不报错)。
		var labs: Array = []
		var widest := 0.0
		var hr := Rect2()
		for h_n in holders:
			var hr_h: Rect2 = (h_n as Control).get_global_rect()
			var labs_h: Array = []
			_all_labels(h_n, labs_h)
			labs.append_array(labs_h)
			for lb2 in labs_h:
				var lr: Rect2 = (lb2 as Control).get_global_rect()
				widest = maxf(widest, (lb2 as Control).get_combined_minimum_size().x)
				if not hr_h.encloses(lr):
					spill.append("%s 「%s」rect x %.0f..%.0f y %.0f..%.0f / %s x %.0f..%.0f y %.0f..%.0f" % [
						WD[d], str((lb2 as Label).text).substr(0, 24),
						lr.position.x, lr.end.x, lr.position.y, lr.end.y, str(h_n.name),
						hr_h.position.x, hr_h.end.x, hr_h.position.y, hr_h.end.y])
			if h_n == mode_n:
				hr = hr_h
		_ok("④ ★分母(%s): 那几块里真的有 Label(0 个 = 下面全是空检查)" % WD[d],
			labs.size() >= 3, "%d 个" % labs.size())
		## ★★「尺子是活的」: 框宽与 ink 宽**两个数都打出来**, 不许只打 PASS。
		print("     %-4s %-7.0f %-7.0f  L1「%s」 / L2「%s」" % [
			WD[d], hr.size.x, widest, str(got[WD[d]]), l2t])
		mm.queue_free()
		await get_tree().process_frame

	_ok("④ ★分母: 七天都建出来了那一块(少一天 = 那一天从没被量过)", built == 7, "%d/7" % built)
	_ok("④ ★分母: 七天都读到了 L1 身份行", got.size() == 7 and not got.values().has(""), str(got))
	_ok("④ ★分母: 七天都读到了 L2 今天行(空串 = 第二行根本没建)",
		l2.size() == 7 and not l2.values().has(""), str(l2))

	## ── ★★★这一版的主判据: 一个字都不许顶穿控件 ──
	_ok("④ ★★★七天里没有任何一段文字顶穿状态行(周六那句原来超框 111px)",
		spill.is_empty(), "%d 条: %s" % [spill.size(), str(spill.slice(0, 4))])

	## ── L1 身份行: 七天**一个字不变**(它无条件; 有分支就又是一条"一周只走一天的代码") ──
	var l1set := {}
	for k in got:
		l1set[str(got[k])] = true
	_ok("④ ★★L1 身份行七天同字(它无条件, 不跟星期几走)", l1set.size() == 1, str(l1set.keys()))
	_ok("④ ★L1 里**没有**命与本周场次那两个数(它们周六周日冻着, 属于 L2)",
		str(got.get("周一", "")).find("♥") < 0
			and str(got.get("周一", "")).find("/%d" % int(P2.RANKED_QUOTA)) < 0,
		str(got.get("周一", "")))

	## ── L2 今天行: 跟着可注入时钟走(bug ③ 的判据) ──
	var l2set := {}
	for k2 in l2:
		l2set[str(l2[k2])] = true
	_ok("④ ★★★L2 一周里**至少三种**说法(积分赛/闯关赛/决赛日) —— "
			+ "`_status_row()` 改回「不传参」立刻七天全一样",
		l2set.size() >= 3, "%d 种: %s" % [l2set.size(), str(l2set.keys())])
	_ok("④ ★分母: 周一~周五那五天说的是同一句(它们同属积分赛口径)",
		str(l2.get("周一", "")) == str(l2.get("周五", ""))
			and str(l2.get("周二", "")) == str(l2.get("周四", "")), str(l2))
	_ok("④ ★周四(积分赛)那一行摆的是命 + 本周配额",
		str(l2.get("周四", "")).find("本周对战 %d/%d" % [
			int(_gs.ranked_used), int(P2.RANKED_QUOTA)]) >= 0, str(l2.get("周四", "")))
	_ok("④ ★周四那一行也摆着命", str(l2.get("周四", "")).find("♥") >= 0, str(l2.get("周四", "")))
	_ok("④ ★周六那一行是闯关赛读数", str(l2.get("周六", "")).find("闯关赛") >= 0,
		str(l2.get("周六", "")))
	_ok("④ ★★★周日那一行是决赛日读数, 而且**不带**那两个冻着的数",
		str(l2.get("周日", "")).find("决赛日") >= 0
			and str(l2.get("周日", "")).find("♥") < 0
			and str(l2.get("周日", "")).find("/%d" % int(P2.RANKED_QUOTA)) < 0,
		str(l2.get("周日", "")))
	_ok("④ ★★周六那一行也**不带**那两个数(2026-09-22 已有的行为, 分母: 不是我新加的)",
		str(l2.get("周六", "")).find("♥") < 0
			and str(l2.get("周六", "")).find("/%d" % int(P2.RANKED_QUOTA)) < 0,
		str(l2.get("周六", "")))


# ─────────────────────────────────────────────────────────────
# ⑤ 周六那两把锁: 都要指下一步(是什么 / 什么时候)
# ─────────────────────────────────────────────────────────────
func _t_locks() -> void:
	print("── ⑤ 周六两把锁指不指下一步 ──")
	var m = MENU.new()
	_gs.promoted = false
	_gs.gauntlet_wins = 0
	_gs.gauntlet_losses = 0
	var l_no: String = str(m._msg_gauntlet_block())
	_gs.promoted = true
	_gs.gauntlet_wins = 4
	_gs.gauntlet_losses = 1
	var l_in: String = str(m._msg_gauntlet_block())
	_gs.gauntlet_wins = 1
	_gs.gauntlet_losses = 3
	var l_out: String = str(m._msg_gauntlet_block())
	print("     没晋级 「%s」" % l_no)
	print("     已晋级 「%s」" % l_in)
	print("     已出局 「%s」" % l_out)
	_ok("⑤ ★分母: 三把锁都非空且两两不同",
		l_no != "" and l_in != "" and l_out != "" \
			and l_no != l_in and l_in != l_out and l_no != l_out)
	## ★★判据量的是「**有没有指下一步**」这件事, 不是某个字面量:
	##   同族的每一句都带下一步(「下周一开新的一轮」/「周六闯关赛见」), 只有这两把锁没带。
	_ok("⑤ ★★没晋级那句: 原来只说「要积分赛拿到资格」, 而它指的积分赛**本周已经过去了** " \
			+ "⇒ 必须写清是下周一",
		l_no.find("下周一") >= 0, l_no)
	_ok("⑤ ★而且把门槛说出来(线在 PROMOTE_WINS, 不许抄数字)",
		l_no.find("%d 胜" % int(P2.PROMOTE_WINS)) >= 0, l_no)
	_ok("⑤ ★★★刚晋级那句: 必须告诉他**明天有决赛日**(不说 ⇒ 他周日不来, 座位空着桶还可能卡住)",
		l_in.find("决赛日") >= 0 and (l_in.find("明天") >= 0 or l_in.find("周日") >= 0), l_in)
	_ok("⑤ ★已出局那句本来就带下一步(分母: 这一维不是我新加的)",
		l_out.find("下周一") >= 0, l_out)
	m.free()
