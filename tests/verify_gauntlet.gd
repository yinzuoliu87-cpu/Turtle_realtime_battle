extends Node
## verify_gauntlet.gd — 周六闯关赛 (E-A, 2026-09-22)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## 原稿 §三 逐字：「4 胜晋级 / 3 负出局」「配额 6 场」「每场照常结算深海币(**无命**,
## 公式退化为固定数 8) + 经验 2」「补发只发晋级者: 4-0 补 2、4-1 补 1、4-2 不补」。
##
## `gauntlet_wins/losses` 在 A 阶段就声明好了, 但**零读零写**整整一周 ——
## 「写了没人读」是本仓一整类缺口(memory `fb-zero-caller-is-a-whole-class`)。
## 所以这份门禁的重点不是"函数算得对不对", 是**产品真的会走到它**。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★① 规则层**穷举**所有能到达的战绩(w 0~4 × l 0~3), 不抽查 ——
##     缺口的形状就是"某一格判错了"。顺带打印分母: 到底枚举了多少格。
## ★② 结算走**真入口** `RealtimeBattle3DScene._settle_season()`,
##     量的是产品自己的账(`gauntlet_wins` / `hearts` / `meta_deepsea_coins`),
##     不是我插的标记(memory `fb-gate-must-measure-requirement-not-my-hook`)。
## ★③ **不掉命**这条要配分母: 先证明同一条路在积分赛阶段**会**掉命 ——
##     否则"打完还是 8 命"可能只是因为那一场压根没结算。
## ★④ 补发同样走真入口 `settle_gauntlet_close(注入时刻)`, 并验**幂等**
##     (连调两次只给一次钱) 与**窗口**(收盘前不给)。
## ★⑤ 开局闸走 `GameState.gauntlet_can_play(注入时刻)`, 四种状态各验一遍。
##
## 跑法: <godot> --headless --path . res://tests/verify_gauntlet.tscn --quit-after 900

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")

## 真实日历样本(UTC), 与 verify_week_season ⑥ 同一周, 那边已把日期核对过。
const MON := 1789344000    # 2026-09-14 周一
const THU := 1789603200    # 2026-09-17 周四
const SAT := 1789776000    # 2026-09-19 周六 00:00
const SUN := 1789862400    # 2026-09-20 周日 00:00
## ★★2026-10-26 用户拍板闯关赛收盘从「周六 23:00」挪到「周日 17:30 UTC」(方案书 20261026b-周六流程.md §4 G)
##   ⇒ 周日 17:30 之前仍是闯关赛, 之后才是决赛日。「周日 = 决赛日」的样本一律钉在 19:00(收盘之后、分组 18:00 之后);
##   周日上午那一半另有自己的断言(⑩), 不让「周日」两个字同时代表两个阶段。
const SUN_EVE := SUN + 19 * 3600    # 2026-09-20 周日 19:00 —— 决赛日
const SUN_NOON := SUN + 12 * 3600   # 2026-09-20 周日 12:00 —— 仍是闯关赛

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
	for k in ["gauntlet_wins", "gauntlet_losses", "gauntlet_backfill_paid", "promoted",
			"week_phase", "hearts", "meta_deepsea_coins", "season_wins", "ranked_used",
			"season_total_battles", "week_anchor_ts", "season_start_ts", "season_leaders",
			"lane_results", "season_level", "season_xp"]:
		_bak[k] = _gs.get(k)

	print("=== 周六闯关赛 (E-A) ===")
	_t_rules()
	await _t_settle()
	_t_backfill()
	_t_entry_gate()
	_t_menu_gate()
	_t_sunday_close()

	for k in _bak:
		_gs.set(k, _bak[k])
	_ok("★收尾: GameState 已还原", int(_gs.gauntlet_wins) == int(_bak["gauntlet_wins"]),
		"gauntlet_wins=%d" % int(_gs.gauntlet_wins))

	print("")
	print("  (共 %d 条断言)" % _n)

	## ══════════════════════════════════════════════════════════════════════
	##  ⑧ ★★★开局闸【七天全量】—— 不许有哪一天漏成「无限打」(2026-09-27)
	## ══════════════════════════════════════════════════════════════════════
	## §⑤ 那一节写的是「四天 × 各种状态」, 而**漏掉的恰好是周日**。
	## 探针(`tests/_probe_week_playable.gd`)七天 × 配额打满量出来:
	##     周日   phase=finals    吃配额=false → 【可打】   ← 唯一一天
	##     周一~五 rest/ranked     吃配额=true  → 挡住
	##     周六   phase=gauntlet  吃配额=false → 挡住(有专门分支)
	## 根因: `_battle_block_msg` 里只有周六那一支; 而 `phase_uses_ranked_quota(FINALS)`
	## 因为「玩法已上线就不吃积分赛配额」返回 false ⇒ 周日**不吃配额 + 没有拦截**。
	##
	## ★后果不是假想: 匹配是**严格同场次**的(v0.19.447「硬条件=双方总场次完全相同」)
	##   ⇒ 周日刷完的人场次停在别人都没有的数字上, **下周开局只能配到机器人**。
	##
	## ★★所以这一节的判据不是「周日要挡住」那一格, 而是**七天各有确定答案**:
	##   一天一天列会再漏第二次 —— 这次漏的就是四天名单里没有的那一天。
	print("  ── ⑧ 开局闸七天全量 ──")
	var _pk8 = load("res://scenes/MainMenu.tscn")
	_ok("⑧ ★分母: 载得到 MainMenu.tscn", _pk8 != null)
	var _mm8 = _pk8.instantiate()
	get_tree().root.add_child(_mm8)
	await get_tree().process_frame
	var _g8 = get_node_or_null("/root/GameState")
	_ok("⑧ ★分母: 拿到 GameState", _g8 != null)
	if _g8 != null:
		_g8.test_mode = true
		## 配额打满 + 没晋级 = **最该被挡住的那个人**
		_g8.ranked_used = 9999
		_g8.season_total_battles = 24
		_g8.season_wins = 0
		_g8.hearts = 3
		_g8.gauntlet_wins = 0
		_g8.gauntlet_losses = 0
		var _open: Array = []
		var _ph_seen := {}
		for _ts in _week_pins():
			var _m: String = str(_mm8._battle_block_msg(_ts))
			var _ph: String = str(P2.phase_at_utc(_ts))
			_ph_seen[_ph] = true
			print("     %-9s %s" % [_ph, ("【可打】★" if _m == "" else _m.substr(0, 30))])
			if _m == "":
				_open.append(_ph)
		## ★2026-10-26 周日正午已是闯关赛 ⇒ 七个正午只覆盖三个阶段; 多钉一个周日 19:00, 决赛日那一支才真被执行到
		_ok("⑧ ★分母: 钉的 %d 个时刻走遍四个阶段(少了决赛日 = 漏的那一天又没人验)" % _week_pins().size(),
			_ph_seen.size() == 4 and _ph_seen.has(P2.PHASE_FINALS), str(_ph_seen.keys()))
		_ok("⑧ ★★★配额打满 + 没晋级 ⇒ **七天一天都不许放行**(漏一天就是无限刷)",
			_open.is_empty(), "放行的: %s" % str(_open))

		## ★分母: 判据不是恒真 —— 同一个人配额没打满时, 工作日必须放行
		_g8.ranked_used = 0
		var _weekday_open := 0
		for _ts2 in _week_pins():
			if str(_mm8._battle_block_msg(_ts2)) == "":
				_weekday_open += 1
		_ok("⑧ ★分母: 配额没打满时**确实有天能打**(恒挡的判据 = 假绿)",
			_weekday_open >= 4, "能打 %d 天" % _weekday_open)

		## ★周日那句话要**指路**, 不是干挡 —— 已晋级的人今天有比赛, 只是不在这个按钮后面
		## ★★★三种人各说各的。2026-09-27 探针照出**同一个玩家前后矛盾**:
		##     周一~五  💀 本大轮已出局 · **但你已晋级**, 周六闯关赛见
		##     周日     🏆 今天是决赛日 · **本周没晋级** · 下周一开新的一轮
		##   两处「晋级」不是一回事(①拿到闯关赛资格 ②进了决赛日), 玩家读到的就是打架。
		##   ⇒ 判据钉住「**打过闯关赛但没打进的人, 不许被说成『没晋级』**」。
		var _sun_in: String = P2.finals_block_msg(true, true)
		var _sun_try: String = P2.finals_block_msg(false, true)
		var _sun_no: String = P2.finals_block_msg(false, false)
		_ok("⑧ ★进了决赛日: 那句话要**指到决赛日那一屏**", _sun_in.find("决赛日") >= 0, _sun_in)
		_ok("⑧ ★★★打过闯关赛没打进的人: **不许说他「没晋级」**(周一~五刚夸过他已晋级)",
			_sun_try.find("未晋级") < 0, _sun_try)
		_ok("⑧ ★他那句要说清**卡在哪一关**(闯关赛)", _sun_try.find("闯关赛") >= 0, _sun_try)
		_ok("⑧ ★连资格都没有的人: 说「本周没晋级」是对的", _sun_no.find("未晋级") >= 0, _sun_no)
		_ok("⑧ ★三句话两两不同(有一对一样 = 那一维白分了)",
			_sun_in != _sun_try and _sun_try != _sun_no and _sun_in != _sun_no,
			"%s / %s / %s" % [_sun_in.substr(0, 18), _sun_try.substr(0, 18), _sun_no.substr(0, 18)])
		_ok("⑧ ★三句话都要说清下一步(指路或说下周)",
			(_sun_in.find("决赛日") >= 0) and (_sun_try.find("下周") >= 0) and (_sun_no.find("下周") >= 0))
	_mm8.queue_free()
	await get_tree().process_frame


	## ══════════════════════════════════════════════════════════════════════
	##  ⑨ ★★★0 命的人在周六/周日, 结算走哪一支 (2026-09-27)
	## ══════════════════════════════════════════════════════════════════════
	## 结算里 `if _last_was_exhibition:`(= `is_eliminated()`)原来**排在**
	## `elif _sk == SETTLE_GAUNTLET:` 前面 ⇒ **0 命的人一律走表演赛**,
	## 闯关赛/决赛日的记账全被跳过。探针实测(`_probe_zero_heart_gauntlet`):
	##     3 命 → 走闯关赛, 打赢 0胜→1胜
	##     0 命 → 走表演赛, 打赢 0胜→**0胜**(战绩根本没记)
	##
	## ★这不是边角: 命数矩阵量出来 0 命的人**只有一格能打** —— 周六 + 已晋级 +
	##   闯关赛没打完, 而周一~五的屏幕刚答应过他「**但你已晋级, 周六闯关赛见**」。
	##   他去了, 打赢也不记 ⇒ **永远到不了 4 胜, 进不了决赛日**。
	##
	## ★判据量的是**产品自己的那条判据**(`is_eliminated() and _sk == SETTLE_RANKED`),
	##   而且**七天全量** —— 只验周六那一格, 周日那一半会再漏一次(v0.19.458 的教训)。
	print("  ── ⑨ 0 命的人结算走哪一支(七天全量) ──")
	var _g9 = get_node_or_null("/root/GameState")
	_ok("⑨ ★分母: 拿到 GameState", _g9 != null)
	if _g9 != null:
		_g9.test_mode = true
		var _bad: Array = []
		var _ranked_exh := 0
		var _sk_seen := {}
		for _ts9 in _week_pins():
			var _ph: String = str(P2.phase_at_utc(_ts9))
			var _sk: String = str(P2.settle_kind(_ph, P2.phase_mode_live(_ph)))
			## 产品的判据: 表演赛只在积分赛那一档成立
			## ★读**产品自己的判据**, 不自己重算一遍(第一版就是重算的, 于是变异不红)
			var _exh: bool = P2.is_exhibition(true, _sk)          # true = 这个人 0 命
			_sk_seen[_sk] = true
			if _sk == P2.SETTLE_GAUNTLET or _sk == P2.SETTLE_FINALS:
				if _exh:
					_bad.append("%s(%s)" % [_ph, _sk])
			elif _exh:
				_ranked_exh += 1
		_ok("⑨ ★分母: 钉的时刻里闯关赛与决赛日两种结算都真出现过(只有一种 = 另一半没验)",
			_sk_seen.has(P2.SETTLE_GAUNTLET) and _sk_seen.has(P2.SETTLE_FINALS), str(_sk_seen.keys()))
		_ok("⑨ ★★★0 命的人在**闯关赛/决赛日**不许被判成表演赛(判成了 = 战绩/封存全不记)",
			_bad.is_empty(), "被判成表演赛的: %s" % str(_bad))
		_ok("⑨ ★分母: 而在**积分赛**那几天他确实算表演赛(一律不算 = 那一维白分了)",
			_ranked_exh >= 4, "%d 天" % _ranked_exh)

		## ★★端到端: 0 命 + 周六 + 已晋级, 打赢一场**战绩必须 +1**
		_g9.hearts = 0
		_g9.promoted = true
		_g9.gauntlet_wins = 0
		_g9.gauntlet_losses = 0
		_g9.week_phase = P2.PHASE_GAUNTLET
		var _sk2: String = str(P2.settle_kind(str(_g9.week_phase),
			P2.phase_mode_live(str(_g9.week_phase))))
		var _exh2: bool = P2.is_exhibition(_g9.is_eliminated(), _sk2)
		_ok("⑨ ★分母: 这个人确实 0 命且今天是闯关赛", _g9.is_eliminated() and _sk2 == P2.SETTLE_GAUNTLET)
		if not _exh2 and _sk2 == P2.SETTLE_GAUNTLET:
			_g9.gauntlet_settle(true)
		_ok("⑨ ★★★0 命 + 已晋级, 周六打赢一场 ⇒ **战绩记上了**(不记 = 他永远到不了 4 胜)",
			int(_g9.gauntlet_wins) == 1, "%d 胜" % int(_g9.gauntlet_wins))
		_g9.hearts = 3
		_g9.gauntlet_wins = 0

	print("ALL PASS — 周六闯关赛" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 规则层: 穷举所有能到达的战绩格
# ─────────────────────────────────────────────────────────────
func _t_rules() -> void:
	print("── ① 规则(穷举 w 0~4 × l 0~3) ──")
	var seen := 0
	var running: Array = []
	var ins: Array = []
	var outs: Array = []
	for w in range(0, 5):
		for l in range(0, 4):
			seen += 1
			var st: String = P2.gauntlet_state(w, l)
			var lab: String = P2.gauntlet_label(w, l)
			if st == P2.GAUNTLET_RUNNING:
				running.append(lab)
			elif st == P2.GAUNTLET_IN:
				ins.append(lab)
			else:
				outs.append(lab)
	print("  ① 枚举 %d 格 → 还能打 %d / 晋级 %d / 出局 %d" % [
		seen, running.size(), ins.size(), outs.size()])
	_ok("① ★分母: 真枚举了 20 格", seen == 20, "%d 格" % seen)

	## ★期望**写死**, 不引被测函数算一遍 —— 那是拿它当尺子。
	##   4 胜晋级 ⇒ 4-0/4-1/4-2/4-3 都是 in(4-3 在正常对局里到不了, 但规则上胜优先);
	##   3 负出局 ⇒ 胜<4 且 负==3;
	##   其余都还能打。
	_ok("① ★晋级格 = 4-0/4-1/4-2/4-3(胜优先于负)",
		ins == ["4-0", "4-1", "4-2", "4-3"], str(ins))
	_ok("① ★出局格 = 0-3/1-3/2-3/3-3(胜不足 4 而负满 3)",
		outs == ["0-3", "1-3", "2-3", "3-3"], str(outs))
	_ok("① ★还能打的格正好 12 个(20 − 4 晋级 − 4 出局)", running.size() == 12,
		"%d 个: %s" % [running.size(), str(running)])

	## ★「6 场封顶」是推论不是独立规则: 胜<4 且 负<3 最多 3-2(5 场)
	var max_running := 0
	for lab in running:
		var parts: PackedStringArray = lab.split("-")
		max_running = maxi(max_running, int(parts[0]) + int(parts[1]))
	_ok("① ★还能打的格里场数最多 5(⇒ 第 6 场必定收尾, 不会有第 7 场)",
		max_running == 5, "最多 %d 场(%s)" % [max_running, str(running)])

	## 补发: 只补晋级者, 4-0 补 2 / 4-1 补 1 / 4-2 不补 / x-3 不补
	_ok("① 补发 4-0 → 2 场", P2.gauntlet_backfill_owed(4, 0) == 2,
		"%d" % P2.gauntlet_backfill_owed(4, 0))
	_ok("① 补发 4-1 → 1 场", P2.gauntlet_backfill_owed(4, 1) == 1,
		"%d" % P2.gauntlet_backfill_owed(4, 1))
	_ok("① 补发 4-2 → 0 场", P2.gauntlet_backfill_owed(4, 2) == 0,
		"%d" % P2.gauntlet_backfill_owed(4, 2))
	_ok("① ★出局者一场都不补(3-3)", P2.gauntlet_backfill_owed(3, 3) == 0,
		"%d" % P2.gauntlet_backfill_owed(3, 3))
	_ok("① ★没打完就到收盘也不补(2-1, U-E4)", P2.gauntlet_backfill_owed(2, 1) == 0,
		"%d" % P2.gauntlet_backfill_owed(2, 1))


# ─────────────────────────────────────────────────────────────
# ② 结算(走真入口): 记战绩 / 不掉命 / 固定 8 币 / 不吃积分赛配额
# ─────────────────────────────────────────────────────────────
func _t_settle() -> void:
	print("── ② 结算(走真入口 _settle_season) ──")
	var scene = RB.new()
	add_child(scene)
	for _i in range(30):
		await get_tree().process_frame

	_gs.season_start_ts = int(Time.get_unix_time_from_system())
	_gs.season_leaders = ["basic", "stone", "ice"]     # _had_season = true
	_gs.lane_results = {}
	_gs.hearts = 8
	_gs.ranked_used = 0
	_gs.gauntlet_wins = 0
	_gs.gauntlet_losses = 0
	_gs.meta_deepsea_coins = 0
	_gs.week_phase = "gauntlet"

	## ★分母: 先证明这一场**真的结算了**(不是因为没走到而"什么都没变")
	var tb0: int = int(_gs.season_total_battles)
	scene._settle_season(true)
	_ok("② ★分母: 这一场真的结算了(总场次 +1)",
		int(_gs.season_total_battles) == tb0 + 1,
		"%d → %d" % [tb0, int(_gs.season_total_battles)])
	_ok("② 赢一场 → 闯关战绩 1-0", int(_gs.gauntlet_wins) == 1 and int(_gs.gauntlet_losses) == 0,
		P2.gauntlet_label(int(_gs.gauntlet_wins), int(_gs.gauntlet_losses)))
	_ok("② ★不掉命(周六无命)", int(_gs.hearts) == 8, "hearts=%d" % int(_gs.hearts))
	_ok("② ★每场固定 8 币(不含胜负差)", int(_gs.meta_deepsea_coins) == 8,
		"币=%d" % int(_gs.meta_deepsea_coins))
	_ok("② ★不吃积分赛配额", int(_gs.ranked_used) == 0, "ranked_used=%d" % int(_gs.ranked_used))

	scene._settle_season(false)
	_ok("② 输一场 → 闯关战绩 1-1", int(_gs.gauntlet_wins) == 1 and int(_gs.gauntlet_losses) == 1,
		P2.gauntlet_label(int(_gs.gauntlet_wins), int(_gs.gauntlet_losses)))
	_ok("② ★输了也不掉命", int(_gs.hearts) == 8, "hearts=%d" % int(_gs.hearts))
	_ok("② ★输了也是 8 币(公式退化成固定数)", int(_gs.meta_deepsea_coins) == 16,
		"币=%d" % int(_gs.meta_deepsea_coins))

	## ★★分母(关键): 同一条路在**积分赛**阶段**会**掉命 ——
	##   没有这一条, 上面"不掉命"可能只是因为那一场压根没走到扣命那一行。
	_gs.week_phase = "ranked"
	var h0: int = int(_gs.hearts)
	scene._settle_season(false)
	_ok("② ★★分母: 同一条路在积分赛阶段【会】掉命(证明上面不是空检查)",
		int(_gs.hearts) == h0 - 1, "%d → %d" % [h0, int(_gs.hearts)])
	_ok("② ★分母: 积分赛阶段【会】吃配额", int(_gs.ranked_used) == 1,
		"ranked_used=%d" % int(_gs.ranked_used))

	## ★★原稿写的是「每场结算深海币 + 经验 2 + **货架刷新**」。
	##   刷新的真实机制是: 商店开场比 `meta_shop_battles` 与 `season_total_battles`,
	##   不相等就重掷(`ShopScene._restore_offer()`)。所以判据落在**那两个数对不对得上**,
	##   不落在"我推理它会刷" —— 我之前把这条登记成 ❓ 未验就是因为没量过。
	print("── ②b 周六打完一场 → 货架会不会换 ──")
	_gs.week_phase = "gauntlet"
	_gs.meta_shop_battles = int(_gs.season_total_battles)   # 假装货架是刚掉的
	_ok("②b ★分母: 打之前两个数相等(货架不该换)",
		int(_gs.meta_shop_battles) == int(_gs.season_total_battles),
		"shop=%d total=%d" % [int(_gs.meta_shop_battles), int(_gs.season_total_battles)])
	scene._settle_season(true)
	_ok("②b ★周六打完一场 → 两个数对不上了(商店下次开场会重掷货架)",
		int(_gs.meta_shop_battles) != int(_gs.season_total_battles),
		"shop=%d total=%d" % [int(_gs.meta_shop_battles), int(_gs.season_total_battles)])

	scene.queue_free()
	await get_tree().process_frame


# ─────────────────────────────────────────────────────────────
# ③ 补发(走真入口 settle_gauntlet_close): 窗口 / 幂等 / 只补晋级者
# ─────────────────────────────────────────────────────────────
func _t_backfill() -> void:
	print("── ③ 闯关配额补发 ──")
	_gs.week_anchor_ts = MON
	_gs.gauntlet_backfill_paid = 0
	_gs.gauntlet_wins = 4
	_gs.gauntlet_losses = 0                       # 4-0 ⇒ 该补 2 场
	_gs.meta_deepsea_coins = 0

	var close_at: int = int(P2.gauntlet_close_ts(MON))
	## ★2026-10-26 改: 原为「周六 23:00(比积分赛收盘晚一天)」。期望**写死**用户拍板的那一刻, 不引产品常量。
	_ok("③ ★分母: 闯关收盘时刻 = 周日 17:30(积分赛周五 23:00 收盘之后 42.5 小时)",
		close_at == SUN + 17 * 3600 + 30 * 60
			and close_at == int(P2.ranked_close_ts(MON)) + 42 * 3600 + 30 * 60,
		"闯关 %s / 积分 %s" % [Time.get_datetime_string_from_unix_time(close_at, true),
			Time.get_datetime_string_from_unix_time(int(P2.ranked_close_ts(MON)), true)])

	## 收盘前: 一分不给
	var paid0: int = int(_gs.settle_gauntlet_close(close_at - 60))
	_ok("③ ★收盘前一分钟: 不补", paid0 == 0 and int(_gs.meta_deepsea_coins) == 0,
		"补了 %d 场, 币=%d" % [paid0, int(_gs.meta_deepsea_coins)])

	## 收盘后: 补 2 场
	var paid1: int = int(_gs.settle_gauntlet_close(close_at + 60))
	_ok("③ 收盘后 4-0 → 补 2 场", paid1 == 2, "补了 %d 场" % paid1)
	_ok("③ ★钱落在【玩家真花得出去的那本】meta_deepsea_coins 上",
		int(_gs.meta_deepsea_coins) == 2 * int(P2.GAUNTLET_BACKFILL_COINS),
		"币=%d(应为 %d)" % [int(_gs.meta_deepsea_coins), 2 * int(P2.GAUNTLET_BACKFILL_COINS)])

	## 幂等: 再调一次不再给
	var coins_before: int = int(_gs.meta_deepsea_coins)
	var paid2: int = int(_gs.settle_gauntlet_close(close_at + 120))
	_ok("③ ★幂等: 再调一次补 0 场、一分不多给", paid2 == 0
		and int(_gs.meta_deepsea_coins) == coins_before,
		"补了 %d 场, 币 %d → %d" % [paid2, coins_before, int(_gs.meta_deepsea_coins)])

	## 出局者: 不补
	_gs.gauntlet_wins = 3
	_gs.gauntlet_losses = 3
	_gs.gauntlet_backfill_paid = 0
	var coins_b2: int = int(_gs.meta_deepsea_coins)
	var paid3: int = int(_gs.settle_gauntlet_close(close_at + 60))
	_ok("③ ★出局(3-3): 一场都不补", paid3 == 0 and int(_gs.meta_deepsea_coins) == coins_b2,
		"补了 %d 场" % paid3)

	## ★两笔账不许互相吃额度: 积分赛的已补计数动了, 闯关这边不受影响
	_gs.gauntlet_wins = 4
	_gs.gauntlet_losses = 1                       # 4-1 ⇒ 该补 1 场
	_gs.gauntlet_backfill_paid = 0
	_gs.backfill_paid = 99                        # 积分赛那边"已补很多"
	var coins_b3: int = int(_gs.meta_deepsea_coins)
	var paid4: int = int(_gs.settle_gauntlet_close(close_at + 60))
	_ok("③ ★★积分赛已补 99 场也不影响闯关补发(两笔账各记各的)",
		paid4 == 1 and int(_gs.meta_deepsea_coins) == coins_b3 + int(P2.GAUNTLET_BACKFILL_COINS),
		"补了 %d 场, 币 +%d" % [paid4, int(_gs.meta_deepsea_coins) - coins_b3])


# ─────────────────────────────────────────────────────────────
# ④ 开局闸: 只有周六 + 有资格 + 还没收尾 才放行
# ─────────────────────────────────────────────────────────────
func _t_entry_gate() -> void:
	print("── ④ 开局闸 ──")
	_gs.promoted = true
	_gs.gauntlet_wins = 1
	_gs.gauntlet_losses = 1
	_ok("④ 周六 + 有资格 + 1-1 → 放行", _gs.gauntlet_can_play(SAT + 3600))
	_ok("④ ★分母: 同样的状态在周四【不】放行(闸真的看日期)",
		not _gs.gauntlet_can_play(THU + 3600))
	## ★2026-10-26: 周日 17:30 前仍是闯关赛 ⇒ 周日正午放行; 收盘后(19:00 决赛日)不放行。两侧各验一次。
	_ok("④ ★周日 12:00(闯关赛收盘前) → 放行", _gs.gauntlet_can_play(SUN_NOON))
	_ok("④ ★周日 19:00 不放行(决赛日不是闯关赛)", not _gs.gauntlet_can_play(SUN_EVE))

	_gs.promoted = false
	_ok("④ ★没资格 → 不放行", not _gs.gauntlet_can_play(SAT + 3600))
	_gs.promoted = true

	_gs.gauntlet_wins = 4
	_gs.gauntlet_losses = 0
	_ok("④ ★已晋级(4-0) → 不放行(打到此为止)", not _gs.gauntlet_can_play(SAT + 3600))
	_gs.gauntlet_wins = 1
	_gs.gauntlet_losses = 3
	_ok("④ ★已出局(1-3) → 不放行", not _gs.gauntlet_can_play(SAT + 3600))

	## ★0 命**不**挡闯关赛: 5 胜 + 8 负 = 13 场, 完全可能既淘汰又晋级
	_gs.gauntlet_wins = 2
	_gs.gauntlet_losses = 1
	_gs.hearts = 0
	_ok("④ ★★0 命但有资格 → 照样能打(余命在终榜里只是第二排序键)",
		_gs.gauntlet_can_play(SAT + 3600), "hearts=%d" % int(_gs.hearts))
	_ok("④ ★分母: 这个状态确实是「已淘汰」(证明上一条不是因为没淘汰)",
		_gs.is_eliminated(), "hearts=%d" % int(_gs.hearts))


# ─────────────────────────────────────────────────────────────
# ⑤ 主菜单开局闸: 走真函数 `_battle_block_msg(注入时刻)`
#    ★★为什么单列这一节: `_start_battle_flow()` 原来直接读系统时钟 ⇒
#      **周六那条分支只有周六跑门禁才会被执行**。实测变异(把周六分支整个关掉)
#      一条门禁都没红 —— 判据没错, 是被测对象不在场
#      (memory `fb-gate-subject-never-constructed`)。
#      现在喂已知日期, 四天 × 各种状态都真跑一遍。
# ─────────────────────────────────────────────────────────────
func _t_menu_gate() -> void:
	print("── ⑤ 主菜单开局闸(喂已知日期) ──")
	var packed = load("res://scenes/MainMenu.tscn")
	if packed == null:
		_ok("⑥ ★分母: 载得到 MainMenu.tscn", false)
		return
	var menu = packed.instantiate()
	get_tree().root.add_child(menu)

	## 底座: 有资格、没打完、满命、配额没满
	_gs.promoted = true
	_gs.gauntlet_wins = 1
	_gs.gauntlet_losses = 1
	_gs.hearts = 8
	_gs.ranked_used = 0

	_ok("⑥ 周六 + 有资格 + 1-1 → 放行(空串)",
		str(menu._battle_block_msg(SAT + 3600)) == "", str(menu._battle_block_msg(SAT + 3600)))
	_ok("⑥ 周四同样放行(积分赛没打满配额)",
		str(menu._battle_block_msg(THU + 3600)) == "", str(menu._battle_block_msg(THU + 3600)))
	## ★2026-10-26: 闯关赛打到周日 17:30 ⇒ 周日正午走的是闯关赛那支, 同样放行
	_ok("⑥ ★周日 12:00(闯关赛收盘前) + 有资格 + 1-1 → 放行",
		str(menu._battle_block_msg(SUN_NOON)) == "", str(menu._battle_block_msg(SUN_NOON)))

	## ★★ 0 命: 周六放行、周四拦住 —— 同一个玩家同一秒, 只差日期
	_gs.hearts = 0
	var sat_msg: String = str(menu._battle_block_msg(SAT + 3600))
	var thu_msg: String = str(menu._battle_block_msg(THU + 3600))
	_ok("⑥ ★★0 命但有资格: 周六放行", sat_msg == "", "「%s」" % sat_msg)
	var sun_noon_msg: String = str(menu._battle_block_msg(SUN_NOON))
	_ok("⑥ ★★0 命但有资格: 周日 12:00(闯关赛收盘前)同样放行", sun_noon_msg == "", "「%s」" % sun_noon_msg)
	_ok("⑥ ★★同一个玩家周四被拦(淘汰锁) —— 两套闸真的不同",
		thu_msg != "", "「%s」" % thu_msg)
	_gs.hearts = 8

	## 没资格 / 已晋级 / 已出局: 周六各拦各的, 而且话不一样
	_gs.promoted = false
	var m_noelig: String = str(menu._battle_block_msg(SAT + 3600))
	_gs.promoted = true
	_gs.gauntlet_wins = 4
	_gs.gauntlet_losses = 0
	var m_in: String = str(menu._battle_block_msg(SAT + 3600))
	_gs.gauntlet_wins = 1
	_gs.gauntlet_losses = 3
	var m_out: String = str(menu._battle_block_msg(SAT + 3600))
	_ok("⑥ 没资格 → 拦住且说「没晋级」",
		m_noelig.find("未晋级") >= 0, "「%s」" % m_noelig)
	_ok("⑥ 已晋级(4-0) → 拦住且带战绩标签",
		m_in != "" and m_in.find("4-0") >= 0, "「%s」" % m_in)
	_ok("⑥ 已出局(1-3) → 拦住且带战绩标签",
		m_out != "" and m_out.find("1-3") >= 0, "「%s」" % m_out)
	_ok("⑥ ★三种拦法说的不是同一句话",
		m_noelig != m_in and m_in != m_out and m_noelig != m_out)

	## ── ⑦ 周六常驻读数(E-A7) —— 同样喂已知日期 ──
	print("── ⑦ 主菜单周六读数 ──")
	_gs.promoted = true
	_gs.gauntlet_wins = 2
	_gs.gauntlet_losses = 1
	var l_sat: String = str(menu._gauntlet_status_line(SAT + 3600))
	var l_thu: String = str(menu._gauntlet_status_line(THU + 3600))
	_ok("⑦ ★分母: 周四返回空串(读数只在周六接管)", l_thu == "", "「%s」" % l_thu)
	_ok("⑦ 周六 2-1 → 带战绩标签", l_sat.find("2-1") >= 0, "「%s」" % l_sat)
	_ok("⑦ ★★带**还差几场**(再赢 2 / 再输 2) —— 光有「2-1」不告诉玩家还剩多少机会",
		l_sat.find("晋级还需 2 胜") >= 0 and l_sat.find("剩余 2 负") >= 0, "「%s」" % l_sat)
	_gs.gauntlet_wins = 4
	_gs.gauntlet_losses = 1
	var l_in: String = str(menu._gauntlet_status_line(SAT + 3600))
	_gs.gauntlet_wins = 1
	_gs.gauntlet_losses = 3
	var l_out: String = str(menu._gauntlet_status_line(SAT + 3600))
	_gs.promoted = false
	var l_no: String = str(menu._gauntlet_status_line(SAT + 3600))
	_ok("⑦ 已晋级 → 说晋级", l_in.find("已晋级") >= 0, "「%s」" % l_in)
	_ok("⑦ 已出局 → 说出局", l_out.find("已出局") >= 0, "「%s」" % l_out)
	_ok("⑦ 没资格 → 说没晋级", l_no.find("未晋级") >= 0, "「%s」" % l_no)
	_ok("⑦ ★四种状态说的不是同一句话",
		l_sat != l_in and l_in != l_out and l_out != l_no and l_sat != l_no)
	## ★★周六不该再摆「本周 N/24」—— 那个配额周六根本不动
	_ok("⑦ ★★周六的读数里没有积分赛配额那个数(它周六不动, 摆着只会误导)",
		l_sat.find("/%d" % int(P2.RANKED_QUOTA)) < 0, "「%s」" % l_sat)

	## ── ⑦b ★★★周日那一半(2026-09-28) ──
	## 上面那一条 2026-09-22 只为周六焊上了, 而**周日一模一样**:
	##   `phase_uses_ranked_quota(FINALS)=false` ⇒ `ranked_used` 周日一整天不动;
	##   `finals_settle_sealed()` / `finals_reveal()` 一个字都不碰 `hearts`。
	## 真实 UTC 周日实拍到的就是「第 1 大轮 · Lv 1   ♥ 3/8   本周 7/24」——**两个数全冻着**。
	## ★这一对判据**必须挨着放**: 周六那一条独自躺了六天, 漏的正是它旁边那一格
	##   (同族: 本文件 ⑧ 的七天全量、⑨ 的七天全量都是这么补出来的)。
	## ★完整的周日覆盖(三态 / 指路 / 真渲染 / 字宽)在 `tests/verify_gauntlet_ahead.gd` ③④,
	##   这里只留与上面严格对称的那一条, 免得同一组判据在两个文件里各写一份。
	_gs.promoted = true
	_gs.gauntlet_wins = 2
	_gs.gauntlet_losses = 1
	## ★2026-10-26: 「周日那一半」= 决赛日 = 周日 17:30 之后 ⇒ 钉 19:00(原来钉 01:00, 现在那是闯关赛)
	var l_sun: String = str(menu._phase_status_line(SUN_EVE))
	_ok("⑦b ★分母: 周日真有自己的读数(空串 = 回落到积分赛那一行, 缺陷照旧)",
		l_sun != "", "「%s」" % l_sun)
	_ok("⑦b ★★★周日的读数里没有积分赛配额那个数(它周日不动, 摆着只会误导)",
		l_sun.find("/%d" % int(P2.RANKED_QUOTA)) < 0, "「%s」" % l_sun)
	_ok("⑦b ★★★周日的读数里也没有命那个数(finals 结算一个字都不碰 hearts)",
		l_sun.find("♥") < 0, "「%s」" % l_sun)
	_ok("⑦b ★周六与周日说的不是同一句话", l_sat != l_sun,
		"周六「%s」/ 周日「%s」" % [l_sat, l_sun])
	## ★2026-10-26 另一侧: 周日正午还在闯关赛 ⇒ 读数与周六**是同一句**(同一个战绩), 不许提前说成决赛日
	var l_sun_noon: String = str(menu._phase_status_line(SUN_NOON))
	_ok("⑦b ★★周日 12:00 的读数 == 周六那句闯关赛读数(收盘前还是闯关赛)", l_sun_noon == l_sat,
		"周日正午「%s」/ 周六「%s」" % [l_sun_noon, l_sat])
	_gs.promoted = false

	menu.queue_free()


## 一周的钉点: 周日~周六各天正午 + 周日 19:00。
## ★2026-10-26 周日正午已是闯关赛 ⇒ 只钉正午的话决赛日那一支一次都不执行(「七天全量」名不副实); 多钉一个 SUN_EVE。
func _week_pins() -> Array:
	var out: Array = []
	for d in range(7):
		out.append(SUN + d * 86400 + 12 * 3600)
	out.append(SUN_EVE)
	return out


# ─────────────────────────────────────────────────────────────
# ⑩ ★★2026-10-26 闯关赛收盘挪到周日 17:30 UTC —— 收盘两侧逐分钟钉住
#    用户「截止时间不如改到周日桶赛之前呢」→ 选周日 17:30(分组 18:00 前半小时), 方案书 20261026b-周六流程.md §4 G。
#    ★期望全部**写死**成用户拍板的那几分钟(17:19 / 17:29 / 17:31), 不引 GAUNTLET_CLOSE_MIN_UTC / CLOSE_LOCKOUT_SEC ——
#      拿被测常量当尺子, 常量改回 23:00 这一节照样绿。
# ─────────────────────────────────────────────────────────────
func _t_sunday_close() -> void:
	print("── ⑩ 周日 17:30 闯关赛收盘 ──")
	var gc: int = int(P2.gauntlet_close_ts(MON))
	var gd: Dictionary = Time.get_datetime_dict_from_unix_time(gc)
	_ok("⑩ ★★gauntlet_close_ts = ISO 周日 17:30:00 UTC(且在同一周)",
		P2.iso_weekday_utc(gc) == 7 and int(gd.get("hour", -1)) == 17 and int(gd.get("minute", -1)) == 30
			and int(gd.get("second", -1)) == 0 and P2.week_anchor_utc(gc) == MON,
		Time.get_datetime_string_from_unix_time(gc, true))

	var t1719: int = SUN + 17 * 3600 + 19 * 60
	var t1729: int = SUN + 17 * 3600 + 29 * 60
	var t1731: int = SUN + 17 * 3600 + 31 * 60
	_ok("⑩ ★周日 17:19 = 闯关赛, 且还能开新局(离收盘 11 分钟, 在封盘窗外)",
		P2.phase_at_utc(t1719) == P2.PHASE_GAUNTLET and P2.can_start_match_utc(t1719),
		"%s / can_start=%s" % [P2.phase_at_utc(t1719), str(P2.can_start_match_utc(t1719))])
	_ok("⑩ ★★周日 17:29 = 闯关赛, 但已封盘(收盘前 10 分钟内不许开新局)",
		P2.phase_at_utc(t1729) == P2.PHASE_GAUNTLET and not P2.can_start_match_utc(t1729),
		"%s / can_start=%s" % [P2.phase_at_utc(t1729), str(P2.can_start_match_utc(t1729))])
	_ok("⑩ ★★周日 17:31 = 决赛日(收盘那一刻阶段就翻过去)",
		P2.phase_at_utc(t1731) == P2.PHASE_FINALS, P2.phase_at_utc(t1731))
	_ok("⑩ ★收盘那一秒两侧: 17:29:59 闯关赛 / 17:30:00 决赛日",
		P2.phase_at_utc(SUN + 17 * 3600 + 30 * 60 - 1) == P2.PHASE_GAUNTLET
			and P2.phase_at_utc(SUN + 17 * 3600 + 30 * 60) == P2.PHASE_FINALS,
		"%s → %s" % [P2.phase_at_utc(SUN + 17 * 3600 + 30 * 60 - 1), P2.phase_at_utc(SUN + 17 * 3600 + 30 * 60)])
	_ok("⑩ 距收盘: 周日 12:00 → 5 小时 30 分", P2.close_left_sec(SUN_NOON) == 5 * 3600 + 30 * 60,
		"实得 %d 秒" % P2.close_left_sec(SUN_NOON))

	## ★旧规则不许残留: 周六 23:00 之后原来是「已收盘、到午夜都封」, 现在那一刻还在闯关赛中途
	var sat2330: int = SAT + 23 * 3600 + 30 * 60
	_ok("⑩ ★★旧规则不残留: 周六 23:30 仍是闯关赛且能开新局(原来这一刻已收盘)",
		P2.phase_at_utc(sat2330) == P2.PHASE_GAUNTLET and P2.can_start_match_utc(sat2330),
		"%s / can_start=%s / left=%d" % [P2.phase_at_utc(sat2330), str(P2.can_start_match_utc(sat2330)),
			P2.close_left_sec(sat2330)])

	## 产品自己的闯关赛开局闸(GameState.gauntlet_can_play)跟着同一条界翻
	_gs.promoted = true
	_gs.gauntlet_wins = 1
	_gs.gauntlet_losses = 1
	_gs.hearts = 8
	_ok("⑩ ★gauntlet_can_play: 17:29 放行 / 17:31 不放行(阶段闸跟着收盘那一刻翻)",
		_gs.gauntlet_can_play(t1729) and not _gs.gauntlet_can_play(t1731),
		"17:29=%s 17:31=%s" % [str(_gs.gauntlet_can_play(t1729)), str(_gs.gauntlet_can_play(t1731))])
