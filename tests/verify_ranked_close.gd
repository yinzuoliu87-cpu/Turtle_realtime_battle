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
##   · **`promoted` 离线版只用硬线「≥ PROMOTE_WINS_FLOOR 胜保送」** ——
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

const KEYS := ["promoted", "ranked_used", "backfill_paid", "coins", "meta_deepsea_coins",
	"season_xp", "season_level", "season_wins", "week_anchor_ts", "season_start_ts",
	"hearts", "season_id", "week_phase"]

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
	var W := int(P2.PROMOTE_WINS_FLOOR)    # 够晋级

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
# ③ promoted 走硬线「≥ PROMOTE_WINS_FLOOR 胜」, 且配分母
# ─────────────────────────────────────────────────────────────
func _t_wins_floor() -> void:
	print("── ③ 晋级硬线 ──")
	var floor_w: int = int(P2.PROMOTE_WINS_FLOOR)
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
	_setup(K, int(P2.PROMOTE_WINS_FLOOR))
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
	_gs.season_wins = int(P2.PROMOTE_WINS_FLOOR)
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
