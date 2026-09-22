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
const SUN := 1789862400    # 2026-09-20 周日

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

	for k in _bak:
		_gs.set(k, _bak[k])
	_ok("★收尾: GameState 已还原", int(_gs.gauntlet_wins) == int(_bak["gauntlet_wins"]),
		"gauntlet_wins=%d" % int(_gs.gauntlet_wins))

	print("")
	print("  (共 %d 条断言)" % _n)
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
	_ok("③ ★分母: 闯关收盘时刻 = 周六 23:00(比积分赛收盘晚一天)",
		close_at == SAT + 23 * 3600 and close_at == int(P2.ranked_close_ts(MON)) + 86400,
		"闯关 %d / 积分 %d" % [close_at, int(P2.ranked_close_ts(MON))])

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
	_ok("④ ★周日也不放行(决赛日不是闯关赛)", not _gs.gauntlet_can_play(SUN + 3600))

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

	## ★★ 0 命: 周六放行、周四拦住 —— 同一个玩家同一秒, 只差日期
	_gs.hearts = 0
	var sat_msg: String = str(menu._battle_block_msg(SAT + 3600))
	var thu_msg: String = str(menu._battle_block_msg(THU + 3600))
	_ok("⑥ ★★0 命但有资格: 周六放行", sat_msg == "", "「%s」" % sat_msg)
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
		m_noelig.find("没晋级") >= 0, "「%s」" % m_noelig)
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
		l_sat.find("再赢 2") >= 0 and l_sat.find("再输 2") >= 0, "「%s」" % l_sat)
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
	_ok("⑦ 没资格 → 说没晋级", l_no.find("没晋级") >= 0, "「%s」" % l_no)
	_ok("⑦ ★四种状态说的不是同一句话",
		l_sat != l_in and l_in != l_out and l_out != l_no and l_sat != l_no)
	## ★★周六不该再摆「本周 N/24」—— 那个配额周六根本不动
	_ok("⑦ ★★周六的读数里没有积分赛配额那个数(它周六不动, 摆着只会误导)",
		l_sat.find("/%d" % int(P2.RANKED_QUOTA)) < 0, "「%s」" % l_sat)

	menu.queue_free()
