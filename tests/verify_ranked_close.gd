extends Node
## verify_ranked_close.gd — A7 收口：积分赛收盘之后的【惰性补算】(2026-09-20)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## A7「补发」在 2026-09-19 被判「已落地」（`verify_backfill.gd` 10 条全绿），
## 但它在真实游戏里**永远返回 0**，两个**各自独立**的原因：
##   1. `backfill_ranked_quota()` 生产侧**零调用者** —— 唯一的调用者是它自己的门禁；
##   2. `promoted` **从来没有任何代码写成 `true`**，而函数第一行就是 `if not promoted: return 0`。
## 这正是本项目记过的两个形状：[[fb-zero-caller-is-a-whole-class]] 与 [[fb-read-a-field-nobody-writes]]。
##
## 2026-09-20 拍板的补法（用户「所以呢」= 照我的建议做）：
##   · **时刻 = 积分赛收盘（UTC 周五 23:00）之后，玩家下一次打开游戏时惰性补算。**
##     不是"到点触发" —— 离线版**根本没有「收盘」这个事件**，没有服务器、没人在那一刻被叫醒。
##     而"下次打开时补算"这个形态 `GameState` 已经有了（`ensure_season()` 的换轮），零新增机制。
##   · **有效窗口 = 周五 23:00 ~ 周日 23:59（同一个自然周内），不做跨周补发。**
##     理由是硬的：`start_new_season()` 会清 `meta_deepsea_coins`，周一之后补上一周的币**当场作废**。
##     代价写在明处：整个周末一次没开游戏 = 拿不到补发。**这是有意的取舍，不是漏。**
##   · **`promoted` 离线版只用硬线「≥ PROMOTE_WINS 胜保送」** ——
##     原稿的「前 30%」要一份收盘时刻的全服终榜，离线版没有。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★① 收盘时刻拿**真实日历**验（2026-09-14 那一周的周五 = 09-18 23:00 UTC），
##     并且用**日期字符串**核对，不是自己再算一遍星期几去跟产品比。
## ★② 「收盘前不补 / 收盘后补」**两侧都要验**。真实时钟一周只有两天多落在窗口里，
##     所以这两侧走 `now_override` 注入（产品里那个参数只给门禁用，注释写明了）。
##     不注入的话另一侧是永久盲区 —— `verify_close_lockout` 就因为没处理这个每周必红两天。
## ★③ **注入口不能代替真入口**：⑥ 不注入、走 `ensure_season()`，
##     而且**期望值由「真实时钟 vs 收盘时刻」现算**，所以它星期几都不会误报
##     （强弱会变：在窗口里时它验"补了"，不在窗口里时它验"没补"，两边都正确）。
## ★④ 硬线判据配**分母**：12 胜与 13 胜两次只差 `season_wins` 一个字段，
##     只验 13 胜晋级的话，一个"恒为 true"的实现照样绿。
## ★⚠ 全程 `test_mode = true` 并量存档文件修改时刻 —— `ensure_season()` 内部会 `save()`。

const P2 := preload("res://scripts/gamedata/phase2_config.gd")

## 真实日历样本（UTC），与 `verify_week_roll` 同一周，那边已把日期核对过。
const MON := 1789344000        # 2026-09-14 00:00:00 周一 = 该周锚点
const FRI_CLOSE := 1789772400  # 2026-09-18 23:00:00 周五 —— 积分赛收盘

## ★★⑥ 会动闯关那三个字段(它要走 `settle_gauntlet_close()`) ⇒ 一并进备份名单。
##   漏登记的字段 = 门禁污染存档, 而 `test_mode` 只挡文件不挡内存(下一个用例读到脏值)。
const KEYS := ["promoted", "ranked_used", "backfill_paid", "coins", "meta_deepsea_coins",
	"season_xp", "season_level", "season_wins", "week_anchor_ts", "season_start_ts",
	"hearts", "season_id", "week_phase",
	"gauntlet_wins", "gauntlet_losses", "gauntlet_backfill_paid"]

var _ok := 0
var _fail := 0
var _bak := {}
var _gs = null


func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])


## 摆一个「本周锚点 = MON、打了 K 场、赢了 W 场、还没补过」的干净局面
func _setup(k: int, wins: int) -> void:
	_gs.week_anchor_ts = MON
	_gs.season_start_ts = MON
	_gs.ranked_used = k
	_gs.season_wins = wins
	_gs.backfill_paid = 0
	_gs.promoted = false
	_gs.meta_deepsea_coins = 1000
	_gs.coins = 1000
	_gs.season_xp = 0
	_gs.season_level = 1


func _ready() -> void:
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		print("  [FAIL] 缺 autoload GameState")
		get_tree().quit(1)
		return
	_gs.test_mode = true
	_chk("★分母: test_mode 已置位(ensure_season 内部会 save())", bool(_gs.test_mode))
	var save_p: String = str(_gs.SAVE_PATH)
	var had: bool = FileAccess.file_exists(save_p)
	var mtime0: int = FileAccess.get_modified_time(save_p) if had else -1
	for k in KEYS:
		_bak[k] = _gs.get(k)

	print("=== A7 积分赛收盘惰性补算 ===")
	_t_close_ts()
	_t_both_sides()
	_t_wins_floor()
	_t_idempotent()
	_t_real_entry()
	_t_one_clock()

	for k in KEYS:
		_gs.set(k, _bak[k])
	var mtime1: int = FileAccess.get_modified_time(save_p) if FileAccess.file_exists(save_p) else -1
	_chk("★收尾: GameState 已还原, 且存档文件没被写过",
		int(_gs.meta_deepsea_coins) == int(_bak["meta_deepsea_coins"])
		and FileAccess.file_exists(save_p) == had and mtime1 == mtime0,
		"mtime %d → %d" % [mtime0, mtime1])

	print("")
	print("  (共 %d 条断言)" % (_ok + _fail))
	print("ALL PASS — 积分赛收盘惰性补算" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 收盘时刻算得对不对(拿真实日历当样本)
# ─────────────────────────────────────────────────────────────
func _t_close_ts() -> void:
	print("── ① 收盘时刻 = 该周周五 23:00 UTC ──")
	var got: int = P2.ranked_close_ts(MON)
	var s := Time.get_datetime_string_from_unix_time(got, true)
	## ★分母: 用日期字符串核对, 不是自己再算一遍星期几去跟产品比
	_chk("① ★分母: 锚点 MON 印出来是 2026-09-14",
		Time.get_datetime_string_from_unix_time(MON, true).begins_with("2026-09-14"),
		Time.get_datetime_string_from_unix_time(MON, true))
	_chk("① 收盘时刻印出来就是 2026-09-18T23:00:00(周五)",
		s.begins_with("2026-09-18") and s.ends_with("23:00:00"), s)
	_chk("① 与写死的真值一致", got == FRI_CLOSE, "实得 %d / 应为 %d" % [got, FRI_CLOSE])
	_chk("① ★收盘落在锚点之后 4 天 23 小时(不是 3 天也不是 5 天)",
		got - MON == 4 * 86400 + 23 * 3600, "差 %d 秒" % (got - MON))


# ─────────────────────────────────────────────────────────────
# ② 收盘【前】不补 / 收盘【后】补 —— 两侧都验(靠 now_override 注入)
# ─────────────────────────────────────────────────────────────
func _t_both_sides() -> void:
	print("── ② 收盘前后两侧 ──")
	var K := int(P2.RANKED_QUOTA) - 5      # 差 5 场
	var W := int(P2.PROMOTE_WINS)    # 够晋级

	## —— 收盘前一秒 ——
	_setup(K, W)
	var m0: int = int(_gs.meta_deepsea_coins)
	var paid_before: int = int(_gs.settle_ranked_close(FRI_CLOSE - 1))
	_chk("② ★收盘前一秒: 一场不补", paid_before == 0, "补了 %d 场" % paid_before)
	_chk("② ★收盘前一秒: 币一分没加", int(_gs.meta_deepsea_coins) == m0,
		"%d → %d" % [m0, int(_gs.meta_deepsea_coins)])
	_chk("② ★收盘前一秒: promoted 也不许被翻(晋级判定同样属于收盘那一刻)",
		not bool(_gs.promoted), "promoted=%s" % str(_gs.promoted))

	## —— 收盘那一秒 ——
	_setup(K, W)
	var m1: int = int(_gs.meta_deepsea_coins)
	var paid_at: int = int(_gs.settle_ranked_close(FRI_CLOSE))
	_chk("② ★收盘那一秒: 补了 配额−实打 场", paid_at == int(P2.RANKED_QUOTA) - K,
		"补了 %d 场(应 %d)" % [paid_at, int(P2.RANKED_QUOTA) - K])
	_chk("② ★收盘那一秒: 深海币真的涨了",
		int(_gs.meta_deepsea_coins) - m1 == paid_at * int(P2.RANKED_BACKFILL_COINS),
		"涨了 %d" % (int(_gs.meta_deepsea_coins) - m1))
	_chk("② ★收盘那一秒: promoted 被翻成 true", bool(_gs.promoted))
	## ★★分母: 两侧确实给出了不同的答案 —— 否则这道闸根本不存在
	_chk("② ★★分母: 前后两侧答案不同(证明闸是真的)", paid_before != paid_at,
		"前 %d 场 / 后 %d 场" % [paid_before, paid_at])

	## —— 周日仍在窗口内(不是"只有周五那一刻才补") ——
	_setup(K, W)
	var paid_sun: int = int(_gs.settle_ranked_close(MON + 6 * 86400 + 12 * 3600))
	_chk("② 周日中午仍补得到(窗口是收盘~周日, 不是一个瞬间)", paid_sun == paid_at,
		"周日补了 %d 场" % paid_sun)


# ─────────────────────────────────────────────────────────────
# ③ promoted 走硬线「≥ PROMOTE_WINS 胜」, 且配分母
# ─────────────────────────────────────────────────────────────
func _t_wins_floor() -> void:
	print("── ③ 晋级硬线 ──")
	var floor_w: int = int(P2.PROMOTE_WINS)
	var K := int(P2.RANKED_QUOTA) - 5

	_setup(K, floor_w - 1)
	var paid_lo: int = int(_gs.settle_ranked_close(FRI_CLOSE))
	var promo_lo: bool = bool(_gs.promoted)

	_setup(K, floor_w)
	var paid_hi: int = int(_gs.settle_ranked_close(FRI_CLOSE))
	var promo_hi: bool = bool(_gs.promoted)

	_chk("③ 差一胜(%d 胜) ⇒ 不晋级、一场不补" % (floor_w - 1),
		not promo_lo and paid_lo == 0, "promoted=%s 补了 %d 场" % [str(promo_lo), paid_lo])
	_chk("③ 刚好够(%d 胜) ⇒ 晋级、补发" % floor_w,
		promo_hi and paid_hi > 0, "promoted=%s 补了 %d 场" % [str(promo_hi), paid_hi])
	## ★★分母: 两次**只差 season_wins 一个字段**, 答案就翻面 —— 否则"恒为 true"也能绿
	_chk("③ ★★分母: 两次只差 season_wins 一个字段, 结论就不同",
		promo_lo != promo_hi, "%d 胜=%s / %d 胜=%s" % [floor_w - 1, str(promo_lo), floor_w, str(promo_hi)])


# ─────────────────────────────────────────────────────────────
# ④ 幂等: 同一周内反复打开游戏不许反复领
# ─────────────────────────────────────────────────────────────
func _t_idempotent() -> void:
	print("── ④ 同一周内不许重复领 ──")
	var K := int(P2.RANKED_QUOTA) - 5
	_setup(K, int(P2.PROMOTE_WINS))
	var first: int = int(_gs.settle_ranked_close(FRI_CLOSE))
	var m: int = int(_gs.meta_deepsea_coins)
	var second: int = int(_gs.settle_ranked_close(FRI_CLOSE + 3600))
	_chk("④ ★分母: 第一次确实补出去了", first > 0, "第一次 %d 场" % first)
	_chk("④ 第二次返回 0 场", second == 0, "第二次 %d 场" % second)
	_chk("④ 第二次币一分没加", int(_gs.meta_deepsea_coins) == m,
		"%d → %d" % [m, int(_gs.meta_deepsea_coins)])


# ─────────────────────────────────────────────────────────────
# ⑤ 走【真入口】ensure_season() —— 不注入时间, 期望值由真实时钟现算
#    ★这条星期几都不会误报: 在窗口里就验"补了", 不在窗口里就验"没补"。
# ─────────────────────────────────────────────────────────────
func _t_real_entry() -> void:
	print("── ⑤ 真入口 ensure_season()(不注入时间) ──")
	var now: int = int(Time.get_unix_time_from_system())
	var anchor: int = P2.week_anchor_utc(now)
	var close: int = P2.ranked_close_ts(anchor)
	var in_window: bool = now >= close
	print("     现在 %s · 本周收盘 %s · %s" % [
		Time.get_datetime_string_from_unix_time(now, true),
		Time.get_datetime_string_from_unix_time(close, true),
		"【在窗口内】" if in_window else "【还没收盘】"])

	## 摆成"本周、打了 K 场、够晋级、没补过" —— 锚点用**当前周**, 这样 ensure_season 不会滚轮
	var K := int(P2.RANKED_QUOTA) - 5
	_gs.week_anchor_ts = anchor
	_gs.season_start_ts = anchor
	_gs.ranked_used = K
	_gs.season_wins = int(P2.PROMOTE_WINS)
	_gs.backfill_paid = 0
	_gs.promoted = false
	_gs.meta_deepsea_coins = 1000
	var sid0: int = int(_gs.season_id)
	var m0: int = int(_gs.meta_deepsea_coins)

	_gs.ensure_season()

	## ★分母: 这次调用没有顺手滚轮(滚了的话下面量到的就不是补发)
	_chk("⑤ ★分母: ensure_season 没有滚轮(锚点就是本周)", int(_gs.season_id) == sid0,
		"season_id %d → %d" % [sid0, int(_gs.season_id)])
	var d: int = int(_gs.meta_deepsea_coins) - m0
	if in_window:
		_chk("⑤ ★★在窗口内: 真入口自己把补发做了(证明 ensure_season 真的调了 settle_ranked_close)",
			d == 5 * int(P2.RANKED_BACKFILL_COINS) and bool(_gs.promoted),
			"深海币 %+d · promoted=%s" % [d, str(_gs.promoted)])
	else:
		_chk("⑤ 还没收盘: 真入口一分不补(闸在真入口这条路上也生效)",
			d == 0 and not bool(_gs.promoted),
			"深海币 %+d · promoted=%s" % [d, str(_gs.promoted)])


# ─────────────────────────────────────────────────────────────
# ⑥ ★★★整条链同一天 —— 钉住**全局缝** `phase2_config.now_override_ts`,
#    然后走产品自己的**不传参**入口。两个入口 + 相位函数必须说的是同一天。
#
# ★★为什么非要这一段(2026-09-28): 这两个函数的兜底原来是**就地**
#   `int(Time.get_unix_time_from_system())` —— 它们和全局缝**互不相通**。
#   实测(`tests/_probe_oneclock.gd`, 修前): 缝钉「周日 21:00」而不传 `now_override`
#   ⇒ `settle_ranked_close()` 返回 **0 场**、`settle_gauntlet_close()` 也 **0 场**,
#   而同一刻 `phase_at_utc(now_utc())` 已经说 `finals` —— **整条链说的不是同一天**。
#   修后同一次实测: 5 场 / 2 场 / `finals`。memory `fb-second-clock-drops-events`。
#
# ★这一段**与真实星期几完全无关**: 锚点用写死的 MON, 注入值也从 MON 算 ⇒ CI 上不会偶发红。
# ★`now_override`(每个函数自己那个参数)**一处都不写** —— 走的正是玩家路径那条兜底。
# ─────────────────────────────────────────────────────────────
func _t_one_clock() -> void:
	print("── ⑥ 整条链同一天(全局缝 now_override_ts) ──")
	## ★★分母之零: 产品默认必须是"缝关着" —— 缝要是默认开着, 下面全部无意义。
	_chk("⑥ ★分母: 产品默认 now_override_ts == 0(缝默认关着)",
		int(P2.now_override_ts) == 0, "now_override_ts=%d" % int(P2.now_override_ts))

	var pin_sun: int = MON + 6 * 86400 + 21 * 3600    # 2026-09-20 21:00 周日
	var pin_mon: int = MON + 10 * 3600                # 2026-09-14 10:00 周一
	## ★先验尺子: 两个注入值本身确实是周日 / 周一, 而且一个在两道收盘线之后、一个在之前。
	##   (用日期字符串核对, 不自己再算一遍星期几 —— 与 ① 同一口径。)
	_chk("⑥ ★分母: 注入值 A 印出来是 2026-09-20(周日) 21:00",
		Time.get_datetime_string_from_unix_time(pin_sun, true) == "2026-09-20 21:00:00"
		and int(P2.iso_weekday_utc(pin_sun)) == 7,
		Time.get_datetime_string_from_unix_time(pin_sun, true))
	_chk("⑥ ★分母: 注入值 B 印出来是 2026-09-14(周一) 10:00",
		Time.get_datetime_string_from_unix_time(pin_mon, true) == "2026-09-14 10:00:00"
		and int(P2.iso_weekday_utc(pin_mon)) == 1,
		Time.get_datetime_string_from_unix_time(pin_mon, true))
	_chk("⑥ ★分母: A 在两道收盘线**之后**、B 在**之前**(否则下面量的不是这道闸)",
		pin_sun > int(P2.ranked_close_ts(MON)) and pin_sun > int(P2.gauntlet_close_ts(MON))
		and pin_mon < int(P2.ranked_close_ts(MON)) and pin_mon < int(P2.gauntlet_close_ts(MON)),
		"A=%d B=%d 积分线=%d 闯关线=%d" % [pin_sun, pin_mon,
			int(P2.ranked_close_ts(MON)), int(P2.gauntlet_close_ts(MON))])

	var a := _one_clock_probe(pin_sun)
	var b := _one_clock_probe(pin_mon)
	print("     A 注 %s → 缝说 %s / 积分赛补 %d 场 / 闯关赛补 %d 场" % [
		Time.get_datetime_string_from_unix_time(pin_sun, true), str(a["phase"]),
		int(a["ranked"]), int(a["gauntlet"])])
	print("     B 注 %s → 缝说 %s / 积分赛补 %d 场 / 闯关赛补 %d 场" % [
		Time.get_datetime_string_from_unix_time(pin_mon, true), str(b["phase"]),
		int(b["ranked"]), int(b["gauntlet"])])

	## —— 缝本身说的那一天(这是另外两处必须对上的那个答案) ——
	_chk("⑥ ★分母: 缝钉住 A 之后 now_utc() 就是 A, 相位=决赛日",
		int(a["now"]) == pin_sun and str(a["phase"]) == str(P2.PHASE_FINALS),
		"now=%d 相位=%s" % [int(a["now"]), str(a["phase"])])
	_chk("⑥ ★分母: 缝钉住 B 之后 now_utc() 就是 B, 相位=休赛",
		int(b["now"]) == pin_mon and str(b["phase"]) == str(P2.PHASE_REST),
		"now=%d 相位=%s" % [int(b["now"]), str(b["phase"])])

	## —— 两个产品入口(都**不传参**)必须跟着缝走 ——
	_chk("⑥ ★★★注周日: `settle_ranked_close()` 不传参也认得出已收盘(补 配额−实打 场)",
		int(a["ranked"]) == int(P2.RANKED_QUOTA) - (int(P2.RANKED_QUOTA) - 5)
		and bool(a["promoted"]),
		"补了 %d 场 promoted=%s" % [int(a["ranked"]), str(a["promoted"])])
	_chk("⑥ ★★★注周日: `settle_gauntlet_close()` 不传参也认得出已收盘(4-0 补 2 场)",
		int(a["gauntlet"]) == 2, "补了 %d 场" % int(a["gauntlet"]))
	_chk("⑥ ★★★注周一: 两个入口都说【还没收盘】(一场不补)",
		int(b["ranked"]) == 0 and int(b["gauntlet"]) == 0 and not bool(b["promoted"]),
		"积分 %d / 闯关 %d / promoted=%s" % [int(b["ranked"]), int(b["gauntlet"]), str(b["promoted"])])

	## —— ★★★「同一天」本身: 两个入口的答案与**缝说的那一天**逐一对上 ——
	##   期望值由产品自己的 `ranked_close_ts` / `gauntlet_close_ts` 现算(不手抄公式)。
	for row in [a, b]:
		var n: int = int(row["now"])
		var want_r: bool = n >= int(P2.ranked_close_ts(MON))
		var want_g: bool = n >= int(P2.gauntlet_close_ts(MON))
		_chk("⑥ ★★★同一天: 缝=%s ⇒ 积分赛入口口径一致(应%s 实%s)" % [
				Time.get_datetime_string_from_unix_time(n, true),
				"已收盘" if want_r else "未收盘", "已收盘" if int(row["ranked"]) > 0 else "未收盘"],
			(int(row["ranked"]) > 0) == want_r)
		_chk("⑥ ★★★同一天: 缝=%s ⇒ 闯关赛入口口径一致(应%s 实%s)" % [
				Time.get_datetime_string_from_unix_time(n, true),
				"已收盘" if want_g else "未收盘", "已收盘" if int(row["gauntlet"]) > 0 else "未收盘"],
			(int(row["gauntlet"]) > 0) == want_g)

	## ★★分母: 注入前后**本来就该不同** —— 两个注入值给出的答案必须不一样,
	##   否则上面那组"口径一致"是在一个对时间不敏感的样本上量的, 永远绿。
	_chk("⑥ ★★分母: A/B 两个注入值给出的答案确实不同(不是对时间不敏感的样本)",
		int(a["ranked"]) != int(b["ranked"]) and int(a["gauntlet"]) != int(b["gauntlet"])
		and str(a["phase"]) != str(b["phase"]),
		"积分 %d/%d · 闯关 %d/%d · 相位 %s/%s" % [int(a["ranked"]), int(b["ranked"]),
			int(a["gauntlet"]), int(b["gauntlet"]), str(a["phase"]), str(b["phase"])])

	## ★缝是 **static** ⇒ 活过场景切换 ⇒ 用完必须还原, 否则波及同进程后面的用例。
	P2.now_override_ts = 0
	_chk("⑥ ★收尾: 缝已还原成 0(static 的东西漏还原会波及后面的用例)",
		int(P2.now_override_ts) == 0 and absi(int(P2.now_utc()) - int(Time.get_unix_time_from_system())) <= 2,
		"now_override_ts=%d" % int(P2.now_override_ts))


## 钉住缝, 摆一个干净局面, 走两个**不传参**的产品入口, 把它们说的话收回来。
func _one_clock_probe(pin: int) -> Dictionary:
	P2.now_override_ts = pin
	## 积分赛那一侧
	_setup(int(P2.RANKED_QUOTA) - 5, int(P2.PROMOTE_WINS))
	var r: int = int(_gs.settle_ranked_close())            # ★不传 now_override
	var promo: bool = bool(_gs.promoted)
	## 闯关赛那一侧(4-0 ⇒ 该补 2 场)
	_setup(int(P2.RANKED_QUOTA) - 5, int(P2.PROMOTE_WINS))
	_gs.gauntlet_wins = 4
	_gs.gauntlet_losses = 0
	_gs.gauntlet_backfill_paid = 0
	var g: int = int(_gs.settle_gauntlet_close())          # ★不传 now_override
	return {"now": int(P2.now_utc()), "phase": str(P2.phase_at_utc(int(P2.now_utc()))),
		"ranked": r, "gauntlet": g, "promoted": promo}
