extends Node
## verify_finals_settle.gd — 周日决赛日的结算口径与购物窗 (E-B7, 2026-09-25)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## 原稿 §四 逐字两条：
##   · 桶内逐轮发放**对称轮次币** ⚙ 并刷新货架
##   · 备战购物 **3 分钟**
## 加上单败赛制的一条硬约束：**输了就是出局，不该再扣赛季的命**。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★★① **「没上线」那一半和「上线了」那一半同样要验**。
##     少了前者，这条分支就可能**提前生效** —— 而决赛日玩法还没做，
##     那正是 v0.19.428 修过的「限制全免而奖励照发」那个洞
##     （memory `fb-branch-to-an-unbuilt-mode-is-a-backdoor`）。
##     `PHASE_MODE_LIVE` 是 **const 字典改不动** ⇒ 判定抽成了
##     `settle_kind(phase, live)`，`live` 当参数才穷举得了两种状态。
## ★★② **「对称」要量成「赢和输拿的一样多」**，不是「发了钱」。
##     只断言「发了 8 币」的话，一个「赢 8 输 0」的实现照样绿。
## ★★③ 购物窗**不看本机时钟**：同一组服务端时刻、喂两个不同的本机时刻，
##     答案必须一模一样（与倒计时同一条纪律）。
## ★④ 每条都配分母：证明另一侧确实不同，免得「恒真」冒充「规则挡住了」。
##
## 跑法: <godot> --headless --path . res://tests/verify_finals_settle.tscn --quit-after 900

const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	GameState.test_mode = true
	print("=== 决赛日结算口径与购物窗 (E-B7) ===")
	_t_settle_kind()
	_t_shop_window()
	_t_shop_wiring()
	await _t_real_settle()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 决赛日结算" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 哪一套口径：phase × live 穷举
# ─────────────────────────────────────────────────────────────
func _t_settle_kind() -> void:
	print("── ① 用哪套结算口径(phase × 上线与否 穷举) ──")
	## ★★★没上线 ⇒ **一律积分赛**。这一条是那个洞的疫苗。
	_ok("① ★★★决赛日**没上线** ⇒ 按积分赛(不许限制全免而奖励照发)",
		P2C.settle_kind(P2C.PHASE_FINALS, false) == P2C.SETTLE_RANKED,
		P2C.settle_kind(P2C.PHASE_FINALS, false))
	_ok("① ★★决赛日**上线了** ⇒ 走决赛日口径",
		P2C.settle_kind(P2C.PHASE_FINALS, true) == P2C.SETTLE_FINALS,
		P2C.settle_kind(P2C.PHASE_FINALS, true))
	_ok("① 闯关赛没上线 ⇒ 也按积分赛(同一条闸, 不是只给决赛日开的)",
		P2C.settle_kind(P2C.PHASE_GAUNTLET, false) == P2C.SETTLE_RANKED)
	_ok("① 闯关赛上线了 ⇒ 走闯关赛口径",
		P2C.settle_kind(P2C.PHASE_GAUNTLET, true) == P2C.SETTLE_GAUNTLET)
	_ok("① 积分赛本身 ⇒ 积分赛", P2C.settle_kind(P2C.PHASE_RANKED, true) == P2C.SETTLE_RANKED)
	_ok("① 休赛日 ⇒ 积分赛(周一没有自己的玩法)",
		P2C.settle_kind(P2C.PHASE_REST, true) == P2C.SETTLE_RANKED)
	## ★空串 = 老档从没写过 `week_phase`。**必须按积分赛**, 不能落进任何一条特殊分支
	_ok("① ★老档(week_phase 是空串) ⇒ 积分赛, 不落进任何特殊分支",
		P2C.settle_kind("", true) == P2C.SETTLE_RANKED)
	_ok("① ★不认识的阶段 ⇒ 也按积分赛(默认值选错方向的代价不对称)",
		P2C.settle_kind("某个没见过的阶段", true) == P2C.SETTLE_RANKED)

	## ★★分母: 现在**实际**是什么状态 —— 把它打出来, 免得有人以为门禁在测线上行为
	var live_now := P2C.phase_mode_live(P2C.PHASE_FINALS)
	print("     现在 PHASE_MODE_LIVE[finals] = %s (上线那天改这一格)" % live_now)
	_ok("① ★★★现在决赛日**还没上线** —— 这条一旦变红, 说明有人翻了开关, "
		+ "该同时确认玩法真做完了", not live_now, str(live_now))


# ─────────────────────────────────────────────────────────────
# ② 购物窗：跟服务端的轮次时钟走
# ─────────────────────────────────────────────────────────────
func _t_shop_window() -> void:
	print("── ② 备战购物窗(3 分钟) ──")
	var r0 := 1000                      # 本轮开始时刻(服务端给的)
	var w: int = P2C.FINALS_SHOP_SEC
	_ok("② ★分母: 窗长就是原稿的 3 分钟", w == 180, str(w))
	_ok("② 开窗那一刻: 开", P2C.finals_shop_open(r0, r0))
	_ok("② 窗内: 开", P2C.finals_shop_open(r0, r0 + w - 1))
	_ok("② ★★整整 180 秒那一刻: **关**(闭区间会多给一秒, 全桶同步的事差一秒也是差)",
		not P2C.finals_shop_open(r0, r0 + w), str(w))
	_ok("② 窗后: 关", not P2C.finals_shop_open(r0, r0 + w + 120))
	_ok("② ★本轮还没开始(服务端时刻早于 round_at) ⇒ 关",
		not P2C.finals_shop_open(r0, r0 - 5))
	_ok("② ★还没拿到桶(round_at = 0) ⇒ 关, 不是开",
		not P2C.finals_shop_open(0, 999999))

	_ok("② 剩余秒数: 开窗那一刻 = 整个窗长",
		P2C.finals_shop_left(r0, r0) == w, str(P2C.finals_shop_left(r0, r0)))
	_ok("② 剩余秒数: 窗内递减", P2C.finals_shop_left(r0, r0 + 60) == w - 60,
		str(P2C.finals_shop_left(r0, r0 + 60)))
	_ok("② ★关了之后剩余 = 0(不是负数 —— 屏幕会把负数画成一串怪字)",
		P2C.finals_shop_left(r0, r0 + w + 500) == 0,
		str(P2C.finals_shop_left(r0, r0 + w + 500)))


# ─────────────────────────────────────────────────────────────
# ②' 购物窗接线: 客户端拿服务端的钟去判, 不看本机时钟
#
# ★★★这一节守的是「**同一组服务端时刻, 本机时钟偏多少都不影响**」——
#   备战购物窗是**全桶同步**的事, 本机时钟偏 10 分钟的人会比别人早关窗或晚关窗,
#   而他自己一点都察觉不到。
# ★判据落在 `SupabaseNet` 真的缓存下来的那份回包上, 不是我另喂一份。
# ─────────────────────────────────────────────────────────────
const SB := preload("res://scripts/net/supabase.gd")

func _t_shop_wiring() -> void:
	print("── ②' 购物窗接线(拿服务端的钟判, 不看本机钟) ──")
	## 造一段像真的回包: 本轮 round_at=1000 开始, 服务端现在 1060(开窗 60 秒了)
	var body := JSON.stringify({
		"ok": true, "bucket": 3, "n": 4, "round": 1, "closed": false,
		"round_at": 1000, "next_at": 1480, "now": 1060,
		"entrants": [{"seed": 0, "name": "甲", "account_id": "uid-me"},
			{"seed": 1, "name": "乙", "account_id": "uid-b"}],
		"done": {}})
	## ★两次翻译**只差本机时刻**(一个 5000、一个 90000) —— 服务端那三个数一模一样
	SB._finals_view = SB.parse_finals(true, 200, body, "uid-me", 5000)
	_ok("②' ★分母: round_at / srv_now 真的带出来了(否则下面全是空检查)",
		int(SB._finals_view.get("round_at", -1)) == 1000
			and int(SB._finals_view.get("srv_now", -1)) == 1060,
		str(SB._finals_view).substr(0, 120))
	_ok("②' 开窗 60 秒时: 还开着", SB.finals_shop_open_now(5000))
	_ok("②' 剩余 = 180 - 60 = 120 秒", SB.finals_shop_left_now(5000) == 120,
		str(SB.finals_shop_left_now(5000)))
	## 本机再走 60 秒 ⇒ 服务端也走了 60 秒 ⇒ 还剩 60
	_ok("②' 本机再走 60 秒 ⇒ 剩 60(用的是**时间差**)",
		SB.finals_shop_left_now(5060) == 60, str(SB.finals_shop_left_now(5060)))
	_ok("②' 本机走过 180 秒 ⇒ 窗关了", not SB.finals_shop_open_now(5000 + 180))

	## ★★★同一份回包, 换一个**差了一天**的本机时刻重新收包 ⇒ 答案必须一模一样
	SB._finals_view = SB.parse_finals(true, 200, body, "uid-me", 90000)
	_ok("②' ★★★本机时钟差了一天, 同一刻的答案**完全一样** —— 全桶同步的事不能看本机钟",
		SB.finals_shop_open_now(90000) and SB.finals_shop_left_now(90000) == 120,
		"开=%s 剩=%d" % [SB.finals_shop_open_now(90000), SB.finals_shop_left_now(90000)])

	## 没有桶(空缓存) ⇒ 一律关, 不是开
	SB.finals_clear()
	_ok("②' ★没拿到桶 ⇒ 关(默认值选错方向的代价不对称)", not SB.finals_shop_open_now(5000))
	_ok("②' ★没拿到桶 ⇒ 剩 0 不是负数", SB.finals_shop_left_now(5000) == 0)

	## ── 屏幕那一行说什么(纯函数, 三种状态各不相同) ──
	var MAP := preload("res://scripts/scenes/BracketMapScene.gd")
	var t_open := MAP.shop_tip(true, 125, true)
	_ok("②' 开着 ⇒ 说**还剩多久**(没有倒计时这一行就没价值)",
		t_open.find("2:05") >= 0, t_open)
	var t_shut := MAP.shop_tip(false, 0, true)
	_ok("②' 关了 ⇒ 说清在等什么(不是干巴巴一句「不能买」)",
		t_shut.find("等开打") >= 0, t_shut)
	_ok("②' ★★没桶 ⇒ 这一行**根本不出现**(空串), 不是显示一句废话",
		MAP.shop_tip(true, 100, false) == "", MAP.shop_tip(true, 100, false))
	_ok("②' ★三种状态说的不是同一句话", t_open != t_shut)


# ─────────────────────────────────────────────────────────────
# ③ 真结算：走真入口 `_settle_season()`
# ─────────────────────────────────────────────────────────────
func _t_real_settle() -> void:
	print("── ③ 真结算(走真入口 _settle_season) ──")
	var scene = RB.new()
	add_child(scene)
	for _i in range(30):
		await get_tree().process_frame
	## ★★`season_leaders` 与周锚点要在**场景建好之后**设 —— 建场景那 30 帧会清掉它,
	##   而周锚点写死成旧值会让 `ensure_season()` 当成换轮、开新赛季把 leaders 清空
	##   (E-B6 那次七条断言全红就是这么来的)。
	GameState.season_leaders = ["basic", "fortune", "ninja"]
	GameState.week_anchor_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))

	## ★★★决赛日**现在没上线** ⇒ 结算必须**照旧按积分赛**。
	##   少了这一条, 那条新分支提前生效也没人发现。
	GameState.week_phase = P2C.PHASE_FINALS
	GameState.hearts = 8
	var q0 := int(GameState.ranked_used)
	scene._settle_season(false)
	_ok("③ ★★★没上线时: 输了**照旧掉命**(证明新分支没有提前生效)",
		int(GameState.hearts) == 7, str(GameState.hearts))
	_ok("③ ★★没上线时: 照旧**吃积分赛配额**",
		int(GameState.ranked_used) == q0 + 1,
		"%d → %d" % [q0, int(GameState.ranked_used)])

	## ★分母: 换成闯关赛(它**已经上线**) ⇒ 不掉命、不吃配额 ——
	##   证明上面两条是"没上线"挡的, 不是"这套闸根本不工作"
	GameState.week_phase = P2C.PHASE_GAUNTLET
	GameState.hearts = 8
	var q1 := int(GameState.ranked_used)
	scene._settle_season(false)
	_ok("③ ★★分母: 闯关赛(已上线)输了**不掉命** —— 证明这套闸真的会分流",
		int(GameState.hearts) == 8, str(GameState.hearts))
	_ok("③ ★分母: 闯关赛不吃积分赛配额",
		int(GameState.ranked_used) == q1, "%d → %d" % [q1, int(GameState.ranked_used)])

	## ★★决赛日那套记账本身(`finals_settle`)单独量 —— 它上线那天才会被调到,
	##   但规则现在就得对, 不然上线那天才发现就晚了。
	print("── ④ 决赛日记账本身(上线那天才会被调到, 规则现在就得对) ──")
	var h0 := int(GameState.hearts)
	var coin_win := int(GameState.finals_settle(true))
	## ★★★**赢和输都要量**。第一版只量了赢那一次 ⇒ 把 `if not won: lose_heart()`
	##   注进去**一条都不红**（反向验证当场发现）——
	##   而「掉命」本来就只可能发生在**输**的那一支。判据没卡住那个形状。
	_ok("④ ★决赛日记账: **赢**了不扣命",
		int(GameState.hearts) == h0, "%d → %d" % [h0, int(GameState.hearts)])
	var coin_lose := int(GameState.finals_settle(false))
	_ok("④ ★★★决赛日记账: **输**了也不扣命(单败: 输了就是出局, 不该再扣赛季的命)",
		int(GameState.hearts) == h0, "%d → %d" % [h0, int(GameState.hearts)])
	_ok("④ ★★★**对称**轮次币: 赢和输拿的**一样多**(原稿逐字「对称」) —— "
		+ "只断言「发了 8 币」的话, 「赢 8 输 0」照样绿",
		coin_win == coin_lose, "赢 %d / 输 %d" % [coin_win, coin_lose])
	_ok("④ ★分母: 而且真的是 8(与周六同值, 都是无命模式)",
		coin_win == int(P2C.FINALS_COINS_PER_ROUND) and coin_win == 8, str(coin_win))
	_ok("④ ★★决赛日的币**不等于**积分赛那条公式算出来的(否则等于没分流)",
		coin_win != 8 + int(GameState.hearts) + 2 * maxi(0, 8 - int(GameState.hearts)) + 6,
		str(coin_win))
	scene.queue_free()
	await get_tree().process_frame
