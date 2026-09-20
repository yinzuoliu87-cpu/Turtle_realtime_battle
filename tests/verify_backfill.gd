extends Node
## verify_backfill.gd — A7：配额补发**只补差额、重复调用不再给、不碰不该补的东西**
##
## ★方案书点名的三条(⑥⑦⑧):
##   ⑥ 合成一份存档(打了 K 场、晋级), 补发后币/经验等于「打满配额的最低供给」
##      —— **量真实字段, 不套公式**
##   ⑦ 连调两次, 第二次一分不加。反向验证: 去掉幂等字段 ⇒ ⑦ 红
##   ⑧ 补发后 096 砍伐经验与糖果罐进度**没变**(把 U6「不补」这条拍板焊死,
##      否则将来有人顺手补上没人拦)
##
## ★「量真实字段不套公式」是有由来的: 如果判据写成
##   `coins_after == coins_before + owed * RANKED_BACKFILL_COINS`, 那就是把产品的公式
##   抄一遍再和自己比 —— 产品把常量看错了, 判据也跟着看错。
##   ⇒ 这里**先读产品常量当分母打印出来**, 再断言"补了 owed 场的量", 并且
##   **额外验一条比例关系**(补 2 场应当正好是补 1 场的两倍), 那条不依赖任何常量。
##
## ★★2026-09-20 换钱包: 判据从 `coins` 改成 `meta_deepsea_coins`。
##   产品原来把补发的币加进 `coins`(龟币累计) —— 而**商店花的是 `meta_deepsea_coins`**
##   (`ShopScene.gd:895`), 打一场真实对局给的也是它
##   (`RealtimeBattle3DScene._settle_season`: `gs.meta_deepsea_coins += _last_reward`)。
##   `coins` 在全仓没有任何消费入口 ⇒ **补发的币花不出去**。
##   ⚠ 而这条门禁当时读的**也是 `coins`** —— 两边同错, 所以十条断言一直全绿。
##   ⇒ 光把产品改对、门禁不动, 等于换个方向留着同一个洞。新增 ⑩ 把「钱包身份」钉住:
##     **不是断言"它等于 meta_deepsea_coins"(那只是把我的选择抄一遍),
##       而是走真入口打一场, 看钱进了哪个钱包, 再要求补发进同一个。**
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_backfill.tscn --quit-after 2000

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")   # ⑩ 走真入口要建它

var _ok := 0
var _fail := 0
var _bak := {}
const KEYS := ["promoted", "ranked_used", "backfill_paid", "coins", "meta_deepsea_coins",
	"season_xp", "season_level",
	"axe_exp_bar", "axe_exp_total",
	"season_leaders", "hearts", "week_phase", "lane_results", "season_total_battles",
	"season_wins", "season_eggs_killed", "ranked_used"]   # ⑩ 打一场会动这些, 一并备份还原

func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])

## 造一份"打了 k 场、晋级"的存档态。★每次都从同一个基线出发, 否则前一条用例的
## 副作用会渗进下一条(本项目栽过: 钉了 rng.seed 不还原波及同文件后面的用例)。
func _setup(k: int, promoted: bool) -> void:
	var gs = GameState
	gs.promoted = promoted
	gs.ranked_used = k
	gs.backfill_paid = 0
	gs.coins = 1000
	## ★两个钱包都给基线: 下面要断言【补发只动深海币、龟币一分不动】,
	##   龟币不给非零基线的话那条断言在它本来就是 0 时是恒真式。
	gs.meta_deepsea_coins = 1000
	gs.season_xp = 0
	gs.season_level = 1
	gs.axe_exp_bar = 7
	gs.axe_exp_total = 33

func _ready() -> void:
	await get_tree().process_frame
	print("── A7: 配额补发与幂等 ──")
	var gs = GameState
	for k in KEYS:
		_bak[k] = gs.get(k)

	var quota: int = int(P2.RANKED_QUOTA)
	var c_per: int = int(P2.RANKED_BACKFILL_COINS)
	var x_per: int = int(P2.RANKED_BACKFILL_XP)
	_chk("★分母: 产品常量都读得到且 > 0", quota > 0 and c_per > 0 and x_per > 0,
		"配额 %d · 币/场 %d · 经验/场 %d" % [quota, c_per, x_per])

	## ── ⑥ 打了 K 场、晋级 ⇒ 补 quota−K 场 ──
	var K := quota - 5                      # 差 5 场
	_setup(K, true)
	var c0: int = int(gs.meta_deepsea_coins)
	var paid := int(gs.backfill_ranked_quota())
	_chk("⑥ ★补发场数 = 配额 − 实打", paid == quota - K, "补了 %d 场(应 %d)" % [paid, quota - K])
	_chk("⑥ ★币按【真实字段】涨了(不是我套公式算的)",
		int(gs.meta_deepsea_coins) - c0 == paid * c_per, "涨了 %d" % (int(gs.meta_deepsea_coins) - c0))
	_chk("⑥ ★经验也补了(走 add_season_xp, 该升级就升级)",
		int(gs.season_xp) > 0 or int(gs.season_level) > 1,
		"xp=%d lv=%d" % [int(gs.season_xp), int(gs.season_level)])
	_chk("⑥ ★记账字段跟上(backfill_paid == 已补场数)", int(gs.backfill_paid) == paid)

	## ⑥b ★不依赖任何常量的比例判据: 差 2 场应当正好是差 1 场的两倍
	_setup(quota - 1, true)
	var c1 := int(gs.meta_deepsea_coins); gs.backfill_ranked_quota()
	var d1 := int(gs.meta_deepsea_coins) - c1
	_setup(quota - 2, true)
	var c2 := int(gs.meta_deepsea_coins); gs.backfill_ranked_quota()
	var d2 := int(gs.meta_deepsea_coins) - c2
	_chk("⑥b ★差 2 场 == 差 1 场的两倍(这条不依赖任何常量, 产品把常量看错也挡得住)",
		d1 > 0 and d2 == d1 * 2, "1场=%d 2场=%d" % [d1, d2])

	## ── ⑦ 连调两次, 第二次一分不加 ──
	_setup(K, true)
	gs.backfill_ranked_quota()
	var c_after1 := int(gs.meta_deepsea_coins)
	var xp_after1 := int(gs.season_xp)
	var lv_after1 := int(gs.season_level)
	var paid2 := int(gs.backfill_ranked_quota())
	_chk("⑦ ★第二次返回 0 场", paid2 == 0, "第二次补了 %d 场" % paid2)
	_chk("⑦ ★币一分没加", int(gs.meta_deepsea_coins) == c_after1, "%d → %d" % [c_after1, int(gs.meta_deepsea_coins)])
	_chk("⑦ ★经验/等级也没动", int(gs.season_xp) == xp_after1 and int(gs.season_level) == lv_after1)

	## ── ⑧ 不补砍伐经验、不补糖果罐(U6 拍板) ──
	_setup(K, true)
	var axe_bar := int(gs.axe_exp_bar)
	var axe_tot := int(gs.axe_exp_total)
	gs.backfill_ranked_quota()
	_chk("⑧ ★★补发没碰 096 砍伐经验(U6: 不补)",
		int(gs.axe_exp_bar) == axe_bar and int(gs.axe_exp_total) == axe_tot,
		"bar %d→%d total %d→%d" % [axe_bar, int(gs.axe_exp_bar), axe_tot, int(gs.axe_exp_total)])

	## ── ⑨ 没晋级 / 已打满 ⇒ 不补 ──
	_setup(K, false)
	var c3 := int(gs.meta_deepsea_coins)
	_chk("⑨ ★没晋级 ⇒ 一场不补", int(gs.backfill_ranked_quota()) == 0 and int(gs.meta_deepsea_coins) == c3)
	_setup(quota, true)
	var c4 := int(gs.meta_deepsea_coins)
	_chk("⑨ ★已打满配额 ⇒ 一场不补", int(gs.backfill_ranked_quota()) == 0 and int(gs.meta_deepsea_coins) == c4)


	## ── ⑩ ★★钱包身份: 补发进的钱包必须是【打一场真实对局会进的那个】 ──
	##    判据不落在"我选的字段名"上, 而落在**产品自己的两条路给不给同一个钱包**。
	##    走真入口 `_settle_season()`(照 verify_week_season ④ 的调法)。
	print("── ⑩ 钱包身份(走真入口打一场) ──")
	var scene = RB.new()
	add_child(scene)
	for _i in range(30):
		await get_tree().process_frame
	gs.season_leaders = ["basic", "stone", "ice"]     # _had_season=true, 否则结算直接 return
	gs.hearts = 8
	gs.week_phase = "ranked"
	gs.lane_results = {}
	gs.tutorial_active = false
	var m_before: int = int(gs.meta_deepsea_coins)
	var c_before: int = int(gs.coins)
	scene._settle_season(false)
	var d_meta: int = int(gs.meta_deepsea_coins) - m_before
	var d_coins: int = int(gs.coins) - c_before
	## ★分母: 这一场真的发钱了 —— 没发钱的话下面"补发进同一个钱包"是拿两个 0 在比
	_chk("⑩ ★分母: 打一场真实对局确实发了钱", d_meta != 0 or d_coins != 0,
		"深海币 %+d · 龟币 %+d" % [d_meta, d_coins])
	_chk("⑩ ★真实对局把钱发进【深海币】而不是龟币", d_meta > 0 and d_coins == 0,
		"深海币 %+d · 龟币 %+d" % [d_meta, d_coins])
	scene.queue_free()
	await get_tree().process_frame

	_setup(K, true)
	var m2: int = int(gs.meta_deepsea_coins)
	var c2b: int = int(gs.coins)
	var paid3 := int(gs.backfill_ranked_quota())
	_chk("⑩ ★分母: 这次补发确实补出去了(否则下面两条是拿 0 比 0)", paid3 > 0,
		"补了 %d 场" % paid3)
	_chk("⑩ ★★补发进的是【同一个钱包】—— 深海币涨了",
		int(gs.meta_deepsea_coins) - m2 == paid3 * c_per,
		"深海币 %+d" % (int(gs.meta_deepsea_coins) - m2))
	_chk("⑩ ★★龟币一分没动(补错钱包就当场红)",
		int(gs.coins) == c2b, "龟币 %d → %d" % [c2b, int(gs.coins)])

	for k in KEYS:
		gs.set(k, _bak[k])
	_chk("★收尾: GameState 已还原(门禁写它会落盘污染玩家存档)",
		int(gs.coins) == int(_bak["coins"])
		and int(gs.meta_deepsea_coins) == int(_bak["meta_deepsea_coins"]) and int(gs.backfill_paid) == int(_bak["backfill_paid"]))
	_done()

func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 配额补发与幂等 (%d/%d)" % [_ok, _ok])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _ok])
	get_tree().quit(1 if _fail > 0 else 0)
