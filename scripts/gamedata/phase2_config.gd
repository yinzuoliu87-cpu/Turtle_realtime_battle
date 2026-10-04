extends RefCounted

## Phase2Config — 二阶段 经济/商店/双路龟蛋 数值集中地 (壳, 全占位)
##
## 用 preload 引 (不用 class_name):
##   const P2 = preload("res://scripts/gamedata/phase2_config.gd")
##
## 这里所有数字都是【占位】, 设计文档明确标"待实测调"。把它们集中在一个文件,
## 用户定稿后改这里一处即可。逻辑壳调用这些常量, 不把魔法数字散落各处。

# ─── 经济: 单一深海币, 每局重置 (沿用现有 GameState.battle_coins 容器) ───

# ─── V2 赛季 (阶段4) ─────────────────────────────────────────
## ★★2026-09-20 删掉了 `SEASON_DURATION_SEC := 432000`(5 天)。
##   它和下面整套周赛制**在同一份代码里互相打架**, 而两边各自都"对":
##     · 赛季靠它滚 —— `ensure_season()` 拿「距上次开赛满 5 天」判过期;
##     · 阶段靠星期几判 —— `phase_at_utc()` 周一休赛/周二~周五积分赛/周六闯关/周日决赛。
##   5 天与 7 天**永远不同步**: 第一轮周一开, 第二轮就从周六开、第三轮周四开……
##   于是「本赛季第几天」跟「今天星期几」越走越开, 而**积分赛配额 `ranked_used`
##   只在 `start_new_season()` 里清零** ⇒ 配额跟着 5 天滚、赛程跟着 7 天滚,
##   玩家会在周三被清配额、或者整整一周只领到一次配额。
##   ⇒ 赛季时长不再是一个"常量", 而是**自然周本身**(见 `week_anchor_utc`)。
##   钉住它的门禁: `tests/verify_week_roll.gd`。

# ─── 大轮赛制 v2 · 周赛制 (A 阶段, 2026-09-17) ───────────────────
## 方案书 docs/plans/20260916-大轮赛制v2周赛制.md + 20260916b-A阶段离线周赛骨架.md。
## 数值**全部来自用户原稿 §九 参数表**(docs/design/斗龟场大轮赛制方案v2-用户原稿.md),
## 不是我拍的; 被后续拍板覆盖的逐条标了出处。
##
## ⚠ **门禁不要断言「常量等于某个数」** —— 那是把参数抄两份(同族 memory
##   fb-refactor-creates-the-drift-it-removes)。这些常量的正确性由 A3~A7 的**行为门禁**间接守。

## 赛程: 一大轮 = 一个自然周。周一休赛(含版本维护窗口) / 周二~周五积分赛 /
## 周六闯关赛 / 周日决赛日。用 `Time.get_unix_time_from_system()` 的 UTC 星期几判定。
## ★★E2 拍板(2026-09-17): **时区写死 UTC, 不跟英国夏令时**。
##   原稿写的是「周五/周六 23:00 英国时间」, 而英国 3 月底~10 月底是 UTC+1、其余 UTC+0
##   ⇒ 跟着夏令时走的话收盘时刻一年会平移两次, 正好卡在最敏感的那一刻。
##   **代价是夏天英国人看到的是 00:00 而不是 23:00** —— 用户认了。
## ★倒计时**按玩家本地时区显示**(E4): 常量存 UTC, **换算只发生在显示层**,
##   赛程逻辑里一律不做时区换算 —— 两边都换算必然有一边忘。
const WEEK_CLOSE_HOUR_UTC := 23        # 收盘时刻(UTC 整点): 积分赛周五、闯关赛周六
## ★★E3 拍板: 收盘前这么久**不让开新局**, 闸设在点「开打」那一刻(**不是**点匹配) ——
##   摆位不限时, 闸设在匹配就盖不住。实测依据(9457 场): 纯战斗最长 225 秒 + 固定呈现 35 秒 ≈ 4.3 分钟,
##   10 分钟留足余量(用户选的, 不是我按 P99 卡的)。
const CLOSE_LOCKOUT_SEC := 600

## ══════════════════════════════════════════════════════════════════════
## ★★★匹配的**唯一一把尺子**: 双方【总场次完全相同】。没有窗口, 没有 ±N。
##
## 上游拍板 —— `docs/plans/20260916-大轮赛制v2周赛制.md:349` **D5**(2026-09-16):
##   「硬条件是**双方总场次相同**(不再按 9 档)」
## 用户 2026-09-26 复述同一条:
##   「从始至终应该都是同场次的人开打, 或者是补充了经济达到同场次的人开打,
##     **不应该有什么正负一**」「别再按9档, 给我彻底删掉」
##
## ★★★这里**不许再出现任何"窗口宽度"常量**。2026-09-25 我在这个位置写过一个
##   `MATCH_BATTLES_SPAN := 1`, 理由是「池子薄时只查等场次会查不到人」——
##   那个理由是**拉取**那一侧的(见下面 `PULL_BATTLES_AHEAD`), 我把它套到了
##   **选靶**这一侧, 于是 5 场次的人照旧会碰到 6 场次的, 而我还把「窗口必须对称」
##   焊成了门禁 ⇒ **给错误上了锁**。供给问题的正解是把池子做厚
##   (`SEED_VER` v12 已按【每个场次】重做: 0~24 每格 12 支), 不是把尺子放宽。
##
## ⇒ 选靶只有两级(`Backend.find_opponent`): 同场次 → 机器人。
##   「找不到同场次的人就往下找一格」也是正负一, 同样不许。
## ══════════════════════════════════════════════════════════════════════

## 【拉取】预取宽度 —— **纯备货, 绝不是匹配判据**。
##
## ★为什么只往前开、不往后开: 我现在 N 场, 打完这局就是 **N+1** 场 ⇒ 预取 N+1
##   是给【下一局】暖池子。而 N-1 我**永远不会再回去**, 拉回来一条都用不上
##   (匹配要求完全相同) ⇒ 往下开纯属白占 `PULL_LIMIT` 的名额。
## ★只有 `supabase.opponents_query()` 一处读它。选靶那一侧(`Backend.find_opponent`)
##   **一个字都不许读** —— 有 `tools/nine_bracket_audit.py` 守着。
const PULL_BATTLES_AHEAD := 1

## 积分赛(周二~周五)
const RANKED_QUOTA := 16               # 场次配额(用户 2026-09-30 定: 16 场 / 6 命)

## ★★命数上限。用户 2026-09-29 14:05 定方向、2026-09-30 拍板执行:
##   「现在是 24 场 8 条命对吧, 之后我们改为 16 场 6 条命了」。
##
## ★★★这两个数**咬着好几处**, 改之前算过一遍(不是只把字面量换掉):
##   ① `RANKED_BACKFILL_COINS` 的原稿是「固定数 + 满命×A」= 8 + 满命 ——
##      原来写死成 16(= 8 + 8), 命改成 6 之后它必须是 14。
##      ⇒ 已改成**从 HEARTS_MAX 推**, 不再写死(见下面那一行)。
##   ② `PROMOTE_WINS_SHIPPING` 原稿是 13, 而那个 13 是从 **24 场 + 8 命**推出来的
##      (注释原话:「胜率 >62%、场数 ≥21」)。16 场 6 命下 13 胜 = **81% 胜率、只允许输 3 场**,
##      比原稿严厉得多 ⇒ 已按**原稿的依据句(胜率 >62%)**重算成 10(见那一行)。
##   ③ 深海币公式 `8 + 余命 + 2×已失命 + 胜6` 整条读 `hearts`, **自动跟着变**
##      (满命胜的上限从 22 变 20), 不用改。
##   ★★**6 命 ⇒ 第 6 负淘汰 ⇒ 一个人最多打「胜数 + 5」场** ——
##     也就是说想用满 16 场配额, 得先有 11 胜。**命比配额更早卡住人**,
##     这一条在 8 命 24 场时也成立(要 16 胜才用得满), 口径没变。
const HEARTS_MAX := 6                  # 命数上限(输一场 -1, 0 = 淘汰)
## 补发地板/场: 原稿「固定数 + 满命×A」, **不含胜利奖**。
## ★★ 2026-09-30: 原来写死成 16(= 8 + 8×1) —— 那个第二个 8 就是**满命**。
##   命改成 6 之后它必须是 14, 而写死的话会**静默多补**。
##   ⇒ 改成从 `HEARTS_MAX` 推。这正是「抄一次永远落后」那一族。
const RANKED_BACKFILL_COINS := 8 + HEARTS_MAX
const RANKED_BACKFILL_XP := 2          # 补发经验/场(与实打每场 +2 同额)
## ══════════════════════════════════════════════════════════════════════
##  晋级线（2026-09-30 用户当场重定，**替换掉原稿的「前 30% + ≥13 胜保送」**）
## ══════════════════════════════════════════════════════════════════════
## 用户原话：「首先打完16场的人如果命数不是0那就可以晋级对吧」
##   → 「对啊，所以11胜也是晋级条件，那么其实**满足11胜且不出局就是唯一晋级条件**了啊，
##      然后剩下的场次如果没打，系统会在周六开始前补发经济啊」
##
## ★★★11 **不是第四个魔法数字** —— 它是前两个数算出来的：
##     PROMOTE_WINS = RANKED_QUOTA − (HEARTS_MAX − 1) = 16 − 5 = 11
##   含义：「把配额打满而**不被淘汰**所需的最少胜场」。
##   6 命 ⇒ 第 6 负淘汰 ⇒ 还活着就意味着输 ≤ 5 场；16 场里输 ≤5 ⇒ 胜 ≥ 11。
##   ⇒ 配额或命数以后再改，这条线自己跟着走，**不用有人记得来改它**。
##
## ★★为什么把原稿那两条都换掉：
##   · 原稿「前 30%」要一份**收盘时刻的全服终榜**（服务端排名）——
##     那部分从来没做，`PROMOTE_TOP_PCT` 全仓零读取，而且有一条判据专门守着它零读取。
##     新规则**不需要排名截断**（它是绝对线，不是相对线）⇒ 那个常量已删，
##     「我们不做排名截断」这件事改由本段文字承载。
##   · 原稿「≥13 胜保送」的 13 是从 **24 场 + 8 命** 推的（胜率 >62%、场数 ≥21）；
##     基数换成 16/6 之后那个数字失去依据。现在依据换成「打满且活着」，更好解释。
##   · 原来还有个临时值 5（测试者个位数时怕周六池空）与正式值两套并存，
##     切换时机靠人记得。**现在只有一个数，而且是算出来的** ⇒ 那一团乱一起消失。
##
## ⚠ **「不出局」这一条在当前数字下是冗余的**（11 胜 + 6 负 = 17 > 16，打不出来），
##   但仍然写出来：它是规则的一半，而冗余是「配额恰好等于 胜线+命−1」这个巧合带来的，
##   配额一改就不冗余了。判据 `PROMOTE_LINE_DERIVED` 里有一条专门断言这个冗余性质，
##   哪天它不再成立会当场红 —— 那时该重读这段而不是删断言。
##
## ★没打满配额的人：**照样能晋级**（11胜1负只打 12 场 ⇒ 晋级），
##   剩下 4 场由 `backfill_ranked_quota()` 在周六前折成币与经验补上。
##   ⇒ 补发机制在这条规则下**仍然是活的**（若当初定成「必须打满 16 场」它就永远付 0 了）。
const PROMOTE_WINS := RANKED_QUOTA - (HEARTS_MAX - 1)

## 闯关赛(周六)
const GAUNTLET_WINS_IN := 4            # 4 胜晋级
const GAUNTLET_LOSSES_OUT := 3         # 3 负出局
const GAUNTLET_QUOTA := 6              # 配额 6 场(原稿: 晋级率 ≈34%)
const GAUNTLET_BACKFILL_COINS := 8     # 补发地板/场(只补晋级者)
const GAUNTLET_BACKFILL_XP := 2
## ★周六**不掉命**(原稿:「每场照常结算深海币(无命, 公式退化为固定数 8)」) ——
##   积分赛那条公式 `8 + 余命 + 2×已失命 + 胜6` 整条都吃 `hearts`, 周六直接复用会算错。
const GAUNTLET_COINS_PER_MATCH := 8    # 周六每场固定深海币(不含胜负差, 原稿就是固定数)
const GAUNTLET_XP_PER_MATCH := 2       # 周六每场经验(与积分赛每场 +2 同额)

## ─── 周日决赛日(E-B7, 2026-09-25) ────────────────────────────
## ★★「**对称**轮次币」是原稿逐字（§四「桶内逐轮发放对称轮次币 ⚙ 并刷新货架」）——
##   同桶同轮**人人一样，不看输赢**。按输赢给差价就不叫对称了，
##   而且**输的人下一轮根本不存在**，给差价毫无意义。
## ★取 8：与周六同值。两者都是**无命模式**，周六那个 8 正是原稿说的
##   「公式退化为固定数」；决赛日没有理由比它高或低。原稿**没给这个数**，是我定的。
## ★积分赛那条公式 `8 + 余命 + 2×已失命 + 胜6` **整条都吃 hearts** ——
##   决赛日没有"命"这个维度，直接复用会按命算钱（与周六同一个坑）。
const FINALS_COINS_PER_ROUND := 8
const FINALS_XP_PER_ROUND := 2
## 备战购物窗（原稿：「3 分钟备战购物」）。从**本轮开始那一刻**算起。
const FINALS_SHOP_SEC := 180


## ─── 这一局该用哪套结算口径（E-B7, 2026-09-25）────────────────
## ★★抽成纯函数、把 `live` 做成**参数**，理由与 `MainMenuScene.close_block_kind()` 一样：
##   `PHASE_MODE_LIVE` 是 **const 字典，Godot 里改不动** ⇒ 门禁没法"临时把决赛日打开
##   再看一眼" ⇒ 不抽的话，「上线那天只改一个常量」这句话**只有到了那天才验证得了**。
## ★★★`live == false` ⇒ **一律按积分赛**。这一条是 v0.19.428 那个洞的疫苗：
##   玩法没做就分流过去，那一支不是"什么都不发生"，是**限制全免而奖励照发**
##   （memory `fb-branch-to-an-unbuilt-mode-is-a-backdoor`）。
## ★顺带把周六也收进来：原来结算那边是拿字面量 `== "gauntlet"` 比的，**没带这道闸** ——
##   周六现在是 live 所以没出事，但那是运气不是设计。
const SETTLE_RANKED := "ranked"
const SETTLE_GAUNTLET := "gauntlet"
const SETTLE_FINALS := "finals"

## 这一局算不算【表演赛】(无 stake: 不掉命/不计战/不上榜)。
##
## ★★★2026-09-27 抽成纯函数, 因为**顺序错过一次**: 结算里
##   `if _last_was_exhibition:` 原来排在 `elif _sk == SETTLE_GAUNTLET:` 前面,
##   而它只看 `is_eliminated()` ⇒ **0 命的人一律走表演赛**, 闯关赛/决赛日的记账全跳过。
##   探针实测(`tests/_probe_zero_heart_gauntlet.gd`): 0 命 + 已晋级 + 周六打赢一场,
##   战绩 **0胜→0胜**(根本没记) ⇒ 他永远到不了 4 胜, 进不了决赛日,
##   而周一~五的屏幕刚答应过他「💀 本大轮已出局 · **但你已晋级, 周六闯关赛见**」。
##
## ★★结算里的**顺序**也由这条判据定死: 闯关赛/决赛日那两支必须排在表演赛**前面**。
##   原来是 `if _last_was_exhibition: ... elif _sk == SETTLE_GAUNTLET:`,
##   闯关赛那一支对 0 命的人**永远轮不到**。
## ★判据: 表演赛只在**积分赛**那一档成立。原稿逐字, 闯关赛与决赛日都是「**不掉命**」——
##   命数这一维在它们身上不成立,「没命可押 = 表演赛」自然也不适用。
## ★★做成纯函数而不是就地 if: 门禁要能**读产品自己的答案**。第一版门禁自己
##   重算了一遍这条判据, 于是把判据退回成只看 `is_eliminated()` 也**不红**
##   —— 判据在测我自己写的副本(memory `fb-hand-rolled-copies-drift`)。
static func is_exhibition(eliminated: bool, sk: String) -> bool:
	return eliminated and sk == SETTLE_RANKED


static func settle_kind(phase: String, live: bool) -> String:
	if not live:
		return SETTLE_RANKED
	if phase == PHASE_GAUNTLET:
		return SETTLE_GAUNTLET
	if phase == PHASE_FINALS:
		return SETTLE_FINALS
	return SETTLE_RANKED


## 现在还能不能买东西（周日决赛日的备战窗）。
## ★★两个时刻都用**服务端**给的（`finals_view` 的 `round_at` 与 `now`）——
##   本机时钟偏了不该影响能不能买东西（与倒计时同一条纪律：
##   `parse_finals` 那里算剩余秒数用的也是服务端的时间差，不是本机绝对时刻）。
## ★做成纯函数而不是在屏幕里就地 if：只写在屏幕里的话，门禁只量得到"此刻"那一格，
##   窗外那一大段全是空检查（同 `phase_pending_note` 的理由）。
static func finals_shop_open(round_at: int, srv_now: int) -> bool:
	if round_at <= 0:
		return false                  # 还没拿到桶 ⇒ 谈不上开窗
	if srv_now < round_at:
		return false                  # 本轮还没开始
	return srv_now < round_at + FINALS_SHOP_SEC


## 距离购物窗关闭还有几秒；`<= 0` = 已经关了。★屏幕上要倒计时，用它。
static func finals_shop_left(round_at: int, srv_now: int) -> int:
	if not finals_shop_open(round_at, srv_now):
		return 0
	return maxi(0, round_at + FINALS_SHOP_SEC - srv_now)

## ─── 闯关赛规则(纯函数) ──────────────────────────────────────
## ★★放这里而不是 `GameState`: 匹配层(选同标签对手)、结算层(记战绩)、UI 层(显示还差几场)
##   **三处都要同一个答案**。就地各写一份 `if w >= 4` 就是同一判据存三份, 必然有一处落后
##   (memory `fb-hand-rolled-copies-drift`; 「周末三天无限刷」那个洞的成因之一正是这个)。

const GAUNTLET_RUNNING := "running"    # 还能打
const GAUNTLET_IN := "in"              # 晋级(≥4 胜)
const GAUNTLET_OUT := "out"            # 出局(≥3 负, 或打满配额仍未晋级)

## 战绩标签。★匹配的**唯一**维度: 只有标签完全相同者互配(3-1 只碰 3-1), 永不跨标签。
static func gauntlet_label(w: int, l: int) -> String:
	return "%d-%d" % [maxi(0, w), maxi(0, l)]

## 这个战绩现在是什么状态。
## ★「6 场封顶」不是独立规则, 是**推论**: 胜<4 且 负<3 最多只能是 3-2(5 场),
##   第 6 场必定落进 4-2(晋级) 或 3-3(出局)。所以下面那条 `w+l >= QUOTA`
##   在正常对局里**到不了** —— 它是存档被改坏时的兜底, 不是主判据。
static func gauntlet_state(w: int, l: int) -> String:
	if w >= GAUNTLET_WINS_IN:
		return GAUNTLET_IN
	if l >= GAUNTLET_LOSSES_OUT:
		return GAUNTLET_OUT
	if w + l >= GAUNTLET_QUOTA:
		return GAUNTLET_OUT            # 兜底: 存档异常时也不许无限打
	return GAUNTLET_RUNNING

## 还能不能再开一局(周六的开局闸)。
static func gauntlet_can_play(w: int, l: int) -> bool:
	return gauntlet_state(w, l) == GAUNTLET_RUNNING

## 闯关配额补发几场。**只补晋级者**(原稿: 4-0 补 2 / 4-1 补 1 / 4-2 不补; x-3 出局者不补)。
## ⚠ 没打满就到收盘(比如 2-1 那一刻周六结束) ⇒ 状态不是 `IN` ⇒ 不补(U-E4, 我 2026-09-22 定)。
static func gauntlet_backfill_owed(w: int, l: int) -> int:
	if gauntlet_state(w, l) != GAUNTLET_IN:
		return 0
	return maxi(0, GAUNTLET_QUOTA - (maxi(0, w) + maxi(0, l)))

## 匹配
const QUEUE_DEGRADE_SEC := 20          # 排队降级阈值: 真人 → 快照 → 机器人
const FRESH_SNAPSHOT_SEC := 1800       # 新鲜快照时窗 30 分钟 —— ★只用于**周六闯关赛**的兜底链(U3b);
                                       #   积分赛按 D10 **不加时间窗**, 改用「按上传时刻倒序取最新」

## 周日决赛日
## (桶容量不在客户端: 原 `BUCKET_CAP_PLAYERS := 32` 全仓零读者, 2026-10-04 删。
##  真值是服务端 `server/supabase/schema.sql` 的 `finals_bucket_size(n)` —— 分桶由 pg_cron `finals_seat` 在服务端做。)
const BUCKET_SHOP_SEC := 180           # 桶内购物 3 分钟(原稿)
## ★D11 拍板: 重放节奏 3 → **4 分钟**。9457 场实测纯战斗超 3 分钟只占 0.17%、**超 4 分钟 0 场**,
##   ⇒ 放宽到 4 分钟即可全覆盖, **不必做加速播、也不给对局设硬时限**(用户原话「不用给每场设置时限的」)。
const BUCKET_REPLAY_SEC := 240
const FINALS_START_HOUR_UTC := 20      # 冠军签表开赛 20:00(同样是 UTC, 见 E2)
## ★周日**分桶赛**几点开打(UTC) = 服务端 pg_cron `finals_seat` 的首个触发小时。
##   2026-10-04 从真库只读查到: jobid 5 `*/10 8-23 * * 0`(周日 08:00 起每 10 分钟分桶) ——
##   这条定时任务原来**只在服务端**, 仓库里一个字都没有; 已抄进 schema.sql 末尾注释。
##   ★2026-10-03 周六收盘后主菜单写「明天决赛日 · 本地 21:00 开打」(取的是上面冠军签表那个钟点),
##   晋级的人照着晚上 9 点才来, 白天的分桶赛就全错过了。
const FINALS_SEAT_HOUR_UTC := 8


## UTC 时刻 → 玩家本地「HH:MM」。★唯一一份: 主菜单与对阵图共用(原来只在主菜单里有一份)。
static func local_hhmm(utc_ts: int) -> String:
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0))   # 分钟
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(utc_ts + bias * 60)
	return "%02d:%02d" % [int(d.get("hour", 0)), int(d.get("minute", 0))]


## 周日分组(finals_seat)第一次跑之前吗? 服务端在这之前对「报了名还没分组」的人回 too_few, 不能照字面念给玩家。
## ★多给 15 分钟: cron 是每 10 分钟一次, 08:00 那一拍之后客户端还要过一个刷新周期才看得到桶。
static func finals_before_seating(ts: int) -> bool:
	if phase_at_utc(ts) != PHASE_FINALS:
		return false
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
	return int(d.get("hour", 0)) * 3600 + int(d.get("minute", 0)) * 60 < FINALS_SEAT_HOUR_UTC * 3600 + 15 * 60

## ─── 赛程判定(纯函数, 全部按 UTC) ────────────────────────────
## ★★E2 拍板: **赛程逻辑一律用 UTC, 时区换算只发生在显示层**。
##   两边都换算必然有一边忘 —— 那种 bug 一年只在夏令时切换那两天出现, 最难查。
## ★放在 phase2_config(纯数据/计算层)而不是主场景: 主菜单要用、A3 的配额分流要用、
##   将来服务端也要用同一套判定。抄两份必然漂(memory fb-hand-rolled-copies-drift)。

## 阶段名。★用短标识不用中文 —— 它会存进存档(GameState.week_phase)。
const PHASE_REST := "rest"          # 周一: 休赛 + 版本维护窗口
const PHASE_RANKED := "ranked"      # 周二~周五: 积分赛
const PHASE_GAUNTLET := "gauntlet"  # 周六: 闯关赛
const PHASE_FINALS := "finals"      # 周日: 决赛日

## ★★闯关赛(周六) / 决赛日(周日) / 休赛(周一) 的**玩法**上线了没有。
##
## 现在是 `false` —— 那三天只有常量和赛程条上的名字, **一行玩法都没有**。
## 而 `phase_at_utc()` 从 v0.19.417 起是真的会返回 gauntlet/finals/rest 的,
## 于是出现了一个洞(2026-09-22 查实, 见下面 `phase_uses_ranked_quota`):
##   那三天照常能开局、照常发奖、照常 `season_wins += 1`, 却**不吃积分赛配额** ——
##   一周七天里有三天是"无限场次的积分赛", 谁周末刷得多谁就上榜, 配额 24 场形同虚设。
##
## ⇒ 在玩法上线之前, 那几天**按积分赛规则走**(吃配额、赛程条上直说还没上线)。
##
## ★★2026-09-22 第二次改: 从**一个全局开关**拆成**一张按阶段的表**。
##   原来一个常量管三天。周六闯关赛(E-A)做完要翻 true, 而周日决赛日没做 ——
##   一起翻就会让**周日周一重新变成「限制全免而奖励照发」**, 那正是 v0.19.428 刚修的洞
##   (memory `fb-branch-to-an-unbuilt-mode-is-a-backdoor`)。
##   ⇒ 「上线了没有」是**每个阶段各自的事实**, 就得每个阶段各自记一格。
const PHASE_MODE_LIVE := {
	PHASE_REST: false,        # 周一休赛: 没有"休赛日玩法", 也不打算做
	PHASE_RANKED: true,       # 周二~周五积分赛: 本来就在跑
	PHASE_GAUNTLET: true,     # 周六闯关赛: E-A 已落地(2026-09-22)
	PHASE_FINALS: true,       # 周日决赛日: E-B1~B7 全落地(2026-09-25), 真客户端×真服务器验过
}

## 阶段还没上线时, 赛程条上挂哪句话。★各说各的:
##   周一是**设计上就没有玩法**(休赛), 说"开发中"是另一种谎; 周日是**真的在等开发**。
## ★★★2026-09-26 周一那句补了「算配额」三个字。
##
## 周一 00:00 UTC 正是换轮时刻(`start_new_season` 把 `ranked_used` 清 0),
## 而 `phase_uses_ranked_quota(PHASE_REST)` 返回 **true** ⇒ 周一是
## 「刚发了满额 24 场 + 照积分赛规则照常能打」的一天, 打的每一场**都算在本周那 24 场里**,
## 胜场也直接算进 `season_wins >= PROMOTE_WINS` 那条晋级硬线。
##
## 而原来屏幕上只说「休赛日 · 暂按积分赛规则」—— 一个字都没提这件事。
## 一个测试者周一兴致好打 24 场, 周二到周五点开打只会看到「本周配额 24 场已打满」,
## 而他完全不知道为什么。**说得不全和说错一样是缺陷。**
##
## ★★★2026-09-27 把「开发中 / 暂按 / 配额」三个词从屏幕上摘掉:
##   · 「玩法开发中」「暂按」是**开发备注**。玩家不需要知道我们做到哪了,
##     他要知道的只有一件事: **这天按什么规矩打**。而「暂」还顺带许了个不存在的期限。
##   · 「配额」是行政词(quota)。同一件事说成「本周场次」, 玩家不用翻译。
##   ⇒ 这里只留**陈述现状**的话。两句的后半句故意一字不差
##     (「按积分赛的规矩打」), 那是两天共同的那条信息。
const PHASE_PENDING_NOTE := {
	PHASE_REST: "休赛日 · 按积分赛的规矩打 · 这天打的算本周场次",
	PHASE_FINALS: "这天按积分赛的规矩打",
}

## 这个阶段的玩法上线了没有。
## ⚠ 不认识的阶段一律按 **true**(照常走积分赛规则) —— 默认值选错方向的代价不对称:
##   选 false 等于给未知阶段开后门。
static func phase_mode_live(phase: String) -> bool:
	return bool(PHASE_MODE_LIVE.get(phase, true))

## 这个阶段的场次, 要不要吃积分赛配额?
## ★★唯一事实源: `_settle_season()` 记账与 `GameState.ranked_quota_full()` 开闸
##   **必须是同一个答案** —— 两处各写一份 `if week_phase == "ranked"`, 就是同一判据存两份,
##   必然有一处落后(memory fb-hand-rolled-copies-drift; 这个洞第一次出现正是因为这样)。
## ⚠ 空串 = 赛程还没写进存档(老档/第一次开局) ⇒ 按积分赛计, 与 A3 的口径一致。
## ★判据走上面那张表 —— 不再是一个全局开关。
## ★也不再有「常量分支 + return」的形状(`tools/const_branch_audit.py` 判过一次红, 它是对的):
##   这里的 `if` 条件带运行期入参, 不是编译期恒定的。
static func phase_uses_ranked_quota(phase: String) -> bool:
	## 玩法**已上线**且不是积分赛 ⇒ 它有自己的配额(闯关赛 6 场), 不吃积分赛那 24 场。
	## 其余一律吃 —— 含空串(老档)、积分赛本身、以及**玩法还没上线**的那几天。
	if phase != "" and phase != PHASE_RANKED and phase_mode_live(phase):
		return false
	return true

## ══════════════════════════════════════════════════════════════════════
##  周日(决赛日)按下「开始对局」说什么。`""` = 不挡。
## ══════════════════════════════════════════════════════════════════════
## ★★★为什么非有这一支不可(2026-09-27 探针实测):
##   `_battle_block_msg` 里原来**只有周六那一支**, 周日一个分支都没有;
##   而 `phase_uses_ranked_quota(FINALS)` 因为「玩法已上线就不吃积分赛配额」返回 false
##   ⇒ 周日是唯一一天**不吃配额 + 没有拦截** = **可以无限刷积分赛**。
##   七天 × 配额打满实测: 只有周日是【可打】。
##
## ★后果不是假想: 匹配是**严格同场次**的(v0.19.447「硬条件=双方总场次完全相同」)
##   ⇒ 周日刷完的人, 场次停在别人都没有的数字上, **下周开局只能配到机器人**。
##
## ★原稿证实这不是设计(§六): 「休赛动线: 积分赛未晋级 / 闯关 3 负 / **周日出局**
##   → 观赛 + 押注」, 而表演赛在 U9(2026-09-16)被用户砍掉。
##
## ★做成**纯函数**而不是在主菜单里就地 if: 这句话一周只在周日出现,
##   只写在屏幕里的话门禁只量得到「今天」那一格
##   (本仓「判据挂在星期几上」已栽过五次, v0.19.446 一轮修了四条)。
## ★★★三种人各说各的 —— 2026-09-27 探针照出**同一个玩家前后矛盾**:
##     周一~五  💀 本大轮已出局 · **但你已晋级**, 周六闯关赛见
##     周日     🏆 今天是决赛日 · **本周没晋级** · 下周一开新的一轮
##   两处「晋级」不是一回事(①拿到闯关赛资格 ②进了决赛日), 而玩家读到的就是打架。
##   ⇒ 周日按**周一那句的口径**说: 「晋级」专指拿到闯关赛资格, 进决赛日叫「打进决赛日」。
##
## `entered` = 进了决赛日(闯关赛 4 胜) / `eligible` = 拿到过闯关赛资格
static func finals_block_msg(entered: bool, eligible: bool) -> String:
	if entered:
		## 进了决赛日: 他今天**有比赛**, 只是不在这个按钮后面 —— 要指路, 不是干挡。
		return "🏆 今天是决赛日 · 去【决赛日 → 看对阵图】打你那一场"
	if eligible:
		## 打过闯关赛但没打进 —— **不能说「没晋级」**, 周一~五刚夸过他「你已晋级」。
		return "🏆 今天是决赛日 · 闯关赛没打进决赛日 · 下周一开新的一轮"
	## 连闯关赛资格都没拿到。说清**下一次机会在哪**, 别让人以为坏了。
	return "🏆 今天是决赛日 · 本周没晋级 · 下周一开新的一轮"


## 这个阶段要不要在赛程条上挂一句"还没上线"? 返回空串 = 照常, 不用额外说明。
## ★做成纯函数(而不是在主菜单里就地 if)是为了能**七天全量测**:
##   只在主菜单里写, 门禁就只能量"今天"那一格, 一周里有四天是空检查。
static func phase_pending_note(phase: String) -> String:
	if phase_mode_live(phase):
		return ""
	## ★兜底那句与表里的同一个口径: **只说现在按什么规矩打**, 不报开发进度
	##   (见 PHASE_PENDING_NOTE 头注 2026-09-27 那段)。
	return str(PHASE_PENDING_NOTE.get(phase, "这天按积分赛的规矩打"))

## ══════════════════════════════════════════════════════════════════════
##  【门禁注入点】把「现在」钉死 —— 纯静态时间缝 (2026-09-27)
## ══════════════════════════════════════════════════════════════════════
## ★为什么非有它不可: 本文件里全部赛程判定(`phase_at_utc` / `week_anchor_utc` /
##   `close_left_sec` / `can_start_match_utc`)**本来就是纯函数、入参就是 ts** —— 钉得住。
##   钉不住的是**调用点**: 它们各自就地 `Time.get_unix_time_from_system()`
##   (2026-09-27 实测: scripts/+autoload/ 共 **23 处**读系统时钟(本函数自己不算),
##   其中 **16 处**喂给赛程/周锚点判定; 而
##   `MatchmakingScene._ready():82` 与 `Backend.gauntlet_pool_find():807` 两处
##   **就在匹配路径上** —— 前者决定走哪条匹配, 后者判快照新鲜度)。
##   于是跟相位相关的匹配判据只剩两种写法, 两种都不能进棘轮:
##     ① 不写 —— 现状: 匹配侧一条相位断言都没有;
##     ② 写成"今天是星期几"的形状 —— 本地绿 / CI 偶发红。
##        本仓「判据挂在星期几上」已栽过五次(v0.19.446 一轮修了四条)。
##
## ★样式**照抄仓库里现成的三个**, 一个字都不新发明:
##     `Backend.pool_override`(static Dictionary, 空 = 不生效)
##     `Supabase._transport_for_test`(static Callable, 无效 = 不生效)
##     `MainMenuScene.clock_override_ts`(int, 0 = 真实时钟)
##   三者的共同点就是这条缝的全部约定: **默认值就是"关"** ⇒ 玩家路径一字不动;
##   是 **static** ⇒ 活过场景切换 ⇒ **用完必须还原**(漏还原会波及同进程后面的用例)。
##
## ★为什么开在 phase2_config 而不是再给某个场景加一个: 时钟只能有一份。
##   `MainMenuScene.clock_override_ts` / `.strip_now_override` /
##   `BracketMapScene._now_override` / `TeamSelectScene.lockout_now_override` /
##   `GameState.settle_*(now_override)` 已经是**六份手抄的副本**
##   (memory `fb-hand-rolled-copies-drift`), 而它们**互不相通**:
##   主菜单把时钟钉在周六, 匹配那一屏照旧读真实时间 ⇒ 端到端根本对不上。
##
## ⚠ 这条缝**只给数字, 不含任何判定** —— 上面那些纯函数照旧只认自己的入参,
##   所以它不可能改变任何一条既有行为(`now_override_ts == 0` 时 `now_utc()`
##   逐字节等价于 `int(Time.get_unix_time_from_system())`)。
## ⚠ 只认 **> 0**: unix 0 (1970-01-01) 不是任何人想钉的时刻, 而"0 = 关"是上面三个先例的口径。
static var now_override_ts: int = 0

## 「现在」的 unix 秒(UTC)。优先级: `now_override_ts`(门禁钉死) > 开发包时间穿越 > 真实系统时钟。
## ★两个开关都关着时**逐字节等价**于 `int(Time.get_unix_time_from_system())`(穿越偏移恒 0)。
static func now_utc() -> int:
	if now_override_ts > 0:
		return now_override_ts
	var real: int = int(Time.get_unix_time_from_system())
	return real + _travel_offset(real)

## ══════════════════════════════════════════════════════════════════════
##  【开发包时间穿越】测赛程不用等日子 (2026-10-04)
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-10-04:「由于现在我们规定好了每周的哪些天是哪些比赛, 那测试的话我们只能等到
##   对应日期, 还是我们有什么更好的办法」。方案书 docs/plans/20261004-时间穿越测试.md。
##
## ★与 `now_override_ts` 的区别: 那个是**冻住**(门禁用, 时间不走); 这个是
##   「假起点 + 真实流逝」—— 存的是一个**偏移**, 时钟照常往前走(倒计时会走、收盘会到点)。
## ★两个入口, 落到同一个偏移上:
##   · 环境变量 `TURTLE_FAKE_NOW`(桌面): `2026-10-10T15:00Z` 或 `sat 15:00`(本周那天的 UTC 时刻)。
##     **只在第一次读时钟时读一次** —— 之后被「恢复真实时间」清掉就不会再从环境变量冒回来。
##   · 设置页「测试时间」(手机/桌面都能用): `travel_to_weekday()` / `travel_reset()`。
## ★★正式包绝不生效: 判据 `time_travel_allowed()` 复用项目现成的「是不是正式包」口径 ——
##   `OS.is_debug_build()`(release 导出模板下为 false)+ `SHIP` 环境变量强制按正式包语义
##   (同 `RealtimeBattle3DScene._review_demo()`)。**每次读时钟都判一次**, 不是只在设偏移时判。
##   ⚠ 不认 `DEVTOOLS`: 那个能让 release 包里出现调试场按钮, 而改时钟比进调试场危险得多
##     (它会让客户端往服务器报假时刻 —— 见方案书「已知风险」)。
## ⚠ 只改客户端。服务端的分组/推进(p_week、pg_cron)照真实时间走 —— 测那部分要在内测服手动触发。
const TRAVEL_ENV := "TURTLE_FAKE_NOW"
## 当前穿越偏移(秒, 假时刻 − 真实时刻)。0 = 没穿越。
static var travel_offset_sec: int = 0
## 环境变量读过没有(只读一次, 见上)。
static var _travel_env_read: bool = false

## 中文星期(ISO 1~7 → 下标 0~6)。主菜单赛程条与穿越角标共用这一份。
const WEEKDAY_CN := ["一", "二", "三", "四", "五", "六", "日"]
## 简写里认的星期几(英文三字母 / 中文「周X」)。
const _TRAVEL_WD := {
	"mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6, "sun": 7,
	"周一": 1, "周二": 2, "周三": 3, "周四": 4, "周五": 5, "周六": 6, "周日": 7,
}

## 这个包允许时间穿越吗。★正式包(release 导出) / `SHIP` 环境变量 ⇒ 恒 false。
static func time_travel_allowed() -> bool:
	return OS.is_debug_build() and not OS.has_environment("SHIP")

static func _travel_offset(real: int) -> int:
	if not time_travel_allowed():
		return 0
	if not _travel_env_read:
		_travel_env_read = true
		var raw: String = OS.get_environment(TRAVEL_ENV).strip_edges()
		if raw != "":
			var ts: int = parse_fake_now(raw, real)
			if ts > 0:
				travel_offset_sec = ts - real
				print("[Phase2Config] 时间穿越: %s=%s ⇒ %s" % [TRAVEL_ENV, raw, travel_label(ts)])
			else:
				push_warning("[Phase2Config] %s=%s 解析失败(要 2026-10-10T15:00Z 或 sat 15:00), 按真实时间走" % [TRAVEL_ENV, raw])
	return travel_offset_sec

## 现在是不是假时间(开发包里穿越了)。正式包恒 false。
static func travel_active() -> bool:
	return _travel_offset(int(Time.get_unix_time_from_system())) != 0

## 本周(真实时间所在那一周)第 wd 天(ISO 1~7)的 UTC h:m。
static func week_day_at(real: int, wd: int, h: int, m: int) -> int:
	return week_anchor_utc(real) + (wd - 1) * 86400 + h * 3600 + m * 60

## 把 `TURTLE_FAKE_NOW` 的写法解析成 unix 秒(UTC)。解析不了返回 -1。
##   · `2026-10-10T15:00Z` / `2026-10-10 15:00` / 带秒 `...15:00:30Z`
##   · `sat 15:00` / `周六 15:00` = **本周**(按真实时间 `real` 所在那一周)那天的 UTC 时刻
static func parse_fake_now(raw: String, real: int) -> int:
	var s: String = raw.strip_edges()
	var iso := RegEx.create_from_string("^(\\d{4})-(\\d{1,2})-(\\d{1,2})[T ](\\d{1,2}):(\\d{2})(?::(\\d{2}))?Z?$")
	var mm := iso.search(s)
	if mm != null:
		var h: int = int(mm.get_string(4))
		var mi: int = int(mm.get_string(5))
		var se: int = int(mm.get_string(6)) if mm.get_string(6) != "" else 0
		if h > 23 or mi > 59 or se > 59:
			return -1
		return int(Time.get_unix_time_from_datetime_dict({
			"year": int(mm.get_string(1)), "month": int(mm.get_string(2)), "day": int(mm.get_string(3)),
			"hour": h, "minute": mi, "second": se}))
	var short := RegEx.create_from_string("^(\\S+)\\s+(\\d{1,2}):(\\d{2})$")
	var ms := short.search(s)
	if ms != null:
		var key: String = ms.get_string(1).to_lower()
		var h2: int = int(ms.get_string(2))
		var m2: int = int(ms.get_string(3))
		if not _TRAVEL_WD.has(key) or h2 > 23 or m2 > 59:
			return -1
		return week_day_at(real, int(_TRAVEL_WD[key]), h2, m2)
	return -1

## 穿越到 `ts`(unix 秒, UTC), 之后从那一刻起照真实流逝往前走。正式包里什么都不做, 返回 false。
static func travel_to(ts: int) -> bool:
	if not time_travel_allowed() or ts <= 0:
		return false
	_travel_env_read = true
	travel_offset_sec = ts - int(Time.get_unix_time_from_system())
	return true

## 设置页那一屏用的: 穿越到本周第 wd 天的 UTC h:m。
static func travel_to_weekday(wd: int, h: int, m: int) -> bool:
	return travel_to(week_day_at(int(Time.get_unix_time_from_system()), wd, h, m))

## 「恢复真实时间」。★同时把环境变量标成读过 —— 否则清完下一次读时钟它又冒回来。
static func travel_reset() -> void:
	_travel_env_read = true
	travel_offset_sec = 0

## 「测试时间 周六 15:00 UTC」—— 主菜单角标与设置页共用。
static func travel_label(ts: int) -> String:
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
	return "测试时间 周%s %02d:%02d UTC" % [WEEKDAY_CN[iso_weekday_utc(ts) - 1],
		int(d.get("hour", 0)), int(d.get("minute", 0))]

## 主菜单角标要显示的字: 没穿越 ⇒ ""(角标不建)。
static func travel_badge_text() -> String:
	if not travel_active():
		return ""
	return travel_label(now_utc())

## unix 秒 → 星期几(1=周一 … 7=周日, ISO 口径)。
## ★Godot 的 `get_datetime_dict_from_unix_time` 返回的 `weekday` 是 0=周日,
##   与原稿的「周一~周日」口径差一位 —— 转成 ISO 免得每个调用点各转一次。
static func iso_weekday_utc(ts: int) -> int:
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
	var w: int = int(d.get("weekday", 0))     # 0=Sunday
	return 7 if w == 0 else w

## unix 秒 → 它所在**自然周的锚点**(该周 UTC 周一 00:00:00 的 unix 秒)。
## ★★这是「一大轮」的定义本身 —— 赛季不再按"开赛后满 N 秒"滚, 而是
##   **锚点一变就是新的一周**。好处是它与 `phase_at_utc()` 的星期几判定天生同步:
##   同一个 `Time.get_unix_time_from_system()` 算出来的锚点和星期几不可能对不上。
## ★一周整 7×86400 秒 —— UTC 没有夏令时(E2 拍板时区写死 UTC 的另一个红利:
##   跟着英国时间走的话, 3 月底那一周只有 6×24+23 小时, 这个函数就得处理特例)。
static func week_anchor_utc(ts: int) -> int:
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
	var secs_today: int = int(d.get("hour", 0)) * 3600 + int(d.get("minute", 0)) * 60 + int(d.get("second", 0))
	return ts - secs_today - (iso_weekday_utc(ts) - 1) * 86400

## 这一刻属于哪个阶段(UTC)。
## ⚠ 只看星期几, **不看收盘时刻** —— 收盘那一刻之后到午夜之间算不算下一阶段,
##   是 E3「封盘」管的事(见 `can_start_match_utc`), 不在这里混着判。
static func phase_at_utc(ts: int) -> String:
	return phase_of_weekday(iso_weekday_utc(ts))

## 星期几(ISO 1~7) → 阶段。主菜单的「本周赛程条」要按天铺开, 不能只问"现在是哪个阶段";
## ★抽成一个函数是为了让**赛程表与实时判定共用同一份映射** —— 两份必然会漂。
static func phase_of_weekday(wd: int) -> String:
	match wd:
		1: return PHASE_REST
		6: return PHASE_GAUNTLET
		7: return PHASE_FINALS
		_: return PHASE_RANKED

## 阶段 → 玩家看到的名字。放这里(而不是各 UI 自己写一份)理由同上。
const PHASE_LABEL := {
	PHASE_REST: "休赛",
	PHASE_RANKED: "积分赛",
	PHASE_GAUNTLET: "闯关赛",
	PHASE_FINALS: "决赛日",
}

## 收盘日(ISO 星期几)。★抽成常量是因为**有两个地方要用同一个答案**:
##   `close_left_sec()`(从"现在"往前看还剩几秒) 与 `ranked_close_ts()`(从周锚点算出绝对时刻)。
##   就地各写一个 5, 就是"同一个数存两份"(memory `fb-hand-rolled-copies-drift`)。
const RANKED_CLOSE_WD := 5             # 积分赛: 周五 23:00 收盘
const GAUNTLET_CLOSE_WD := 6           # 闯关赛: 周六 23:00 收盘

## 本周【积分赛收盘】的绝对 unix 时刻(UTC 周五 23:00)。入参是**该周的锚点**(周一 00:00)。
## ★为什么要这个而不是复用 `close_left_sec`: 那个问的是"从现在还剩几秒"，
##   收盘之后它就变成负数、而且在周日会返回 -1(决赛日没有收盘概念) ——
##   拿它判"收盘过了没有"会在周六周日给出错的答案。这里要的是**一个固定的时间点**。
static func ranked_close_ts(week_anchor: int) -> int:
	return week_anchor + (RANKED_CLOSE_WD - 1) * 86400 + WEEK_CLOSE_HOUR_UTC * 3600

## 本周【闯关赛收盘】的绝对 unix 时刻(UTC 周六 23:00)。理由同上一个函数。
## ★两个函数只差一个星期几常量, 但**不能合并成"传星期几进来"** —— 调用点写 `close_ts(6)`
##   就等于把 `GAUNTLET_CLOSE_WD` 这个名字丢了, 下一个人得自己数星期几。
static func gauntlet_close_ts(week_anchor: int) -> int:
	return week_anchor + (GAUNTLET_CLOSE_WD - 1) * 86400 + WEEK_CLOSE_HOUR_UTC * 3600

## 距本阶段收盘还有几秒(UTC)。没有收盘概念的阶段返回 -1。
## 积分赛在**周五** 23:00 收盘、闯关赛在**周六** 23:00 —— 所以要先算"还有几天到收盘日"。
static func close_left_sec(ts: int) -> int:
	var ph := phase_at_utc(ts)
	var close_wd := 0
	if ph == PHASE_RANKED:
		close_wd = RANKED_CLOSE_WD
	elif ph == PHASE_GAUNTLET:
		close_wd = GAUNTLET_CLOSE_WD
	else:
		return -1           # 周一休赛 / 周日决赛日没有"收盘"
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
	var days: int = close_wd - iso_weekday_utc(ts)
	var secs_today: int = int(d.get("hour", 0)) * 3600 + int(d.get("minute", 0)) * 60 + int(d.get("second", 0))
	return days * 86400 + WEEK_CLOSE_HOUR_UTC * 3600 - secs_today

## 现在还能不能开新局? ★★E3: 收盘前 CLOSE_LOCKOUT_SEC 内封盘。
## ⚠ 调用点必须是**点「开打」那一刻**, 不是点匹配 —— 摆位不限时, 设在匹配就盖不住。
static func can_start_match_utc(ts: int) -> bool:
	var left := close_left_sec(ts)
	if left < 0:
		return true                      # 没有收盘概念的阶段不封盘
	return left > CLOSE_LOCKOUT_SEC

# ─── 商店 ───────────────────────────────────────────────────
const SMALL_SHOP_SLOTS := 10      # 小商店格数 (V2 §五: 一次展示10个, 用户 2026-06-25)
const SMALL_SHOP_EVERY_ROUNDS := 4  # 每 4 大回合开一次小商店
const SHOP_REFRESH_STEP := 0      # 0 = 不递增 (用户 2026-06-25: 刷新一直是 2 费)

# ─── 卖出退币 ──────────────────────────────────
## 卖价 = 费 × 星 × SELL_RATE, 向下取整, **至少 SELL_FLOOR**。
## ★★地板价的由来(2026-09-29 真机实测): 原式 `floor(cost * star * 0.8)` 在 1费1★ 上得 **0**
##   —— 96 件里 23 件是 1 费(全部可卖); 另有 1 件 0 费 —— p2eq_095 圣光护盾是羁绊赠品,
##   而 1 费正是出货率最高那一档 ⇒ 玩家点「卖出 +0」、东西从背包消失、币一分不涨。
##   卖出路径开头就早退, 它根本进不了交易。
##   那不是「便宜」是 **白没**: 一次点击、不可撤销、还没有确认框。
## ★为什么是【地板价】而不是改系数 / 四舍五入:
##   · 四舍五入: round(2×0.8)=2 ⇒ 2 费件变成**全额退款**, 买错没有代价;
##     3/4/5 费四舍五入与向下取整同值 ⇒ 它只为了修 1 费, 却顺手改了 2 费的经济。
##   · 抬系数: 一刀改全部 96 件的回收率, 为 23 件的取整误差动整套经济, 代价不成比例。
##   · 地板价 1: **只有 1费1★ 这一格从 0 变 1**, 其余 96×3 格一个数没动(门禁逐格核过)。
##     回收率 1/1 = 100% 也不构成套利: 买 1 费花 1 币 / 卖回 1 币, 最好情形是**打平**,
##     而换一批还要 2 币; 私人池那边买扣 1 张 / 卖退 1 张, 守恒也没破。
const SELL_RATE := 0.8
const SELL_FLOOR := 1

## 卖出退回的深海币。★单一事实源 —— 屏幕上写的价、真正进账的数只能从这里取。
static func sell_value(cost: int, star: int) -> int:
	return maxi(SELL_FLOOR, int(floor(float(maxi(1, cost) * maxi(1, star)) * SELL_RATE)))

# ─── 备战席 (背包栏) ─────────────────────────────────────────
const BENCH_CAP := 10             # 备战席容量

# ─── 局内等级 (TFT风, 用户 2026-06-12) ──────────────────────
## 每局重置的玩家等级 1-10; 绑定 ①龟蛋HP(=egg_hp(等级)) ②商店费用概率档(=SHOP_COST_ODDS[等级]) ③补位小将等级.
const MAX_LEVEL := 10
const PASSIVE_XP := 2            # 每大回合被动 XP (1:1 云顶: +2/回合)
const BUY_XP_AMOUNT := 4         # 买一次经验得的 XP (1:1 云顶: 4币=4XP)
const BUY_XP_COST := 4           # 买经验花的深海币 (1:1 云顶: 4币=4XP)
## 升到下一级所需XP (索引0=1→2 ... 8=9→10). 满级10不再升. 1:1 云顶TFT 升级曲线 (用户 2026-06-23 "抄云顶";
##   2/6/10/20/36/48/76/84 = TFT 经典各级升级XP; lv9→10 各赛季有别, 取估值 94).
const LEVEL_XP_THRESHOLDS := [2, 6, 10, 20, 36, 48, 76, 84, 94]

# ═══ 装备容量：统一规则 (用户 2026-07-27 拍板) ═══════════════════════
## 「单只统领或小将的上限固定为3, 根据赛季等级1..10, 六只单位一共能装备的数量为
##   0,2,4,6,8,10,12,14,16,18」
##
## ★取代原来【两把尺子】—— 它们从未对齐, 分歧一直没人发现, 因为两条路各管各的:
##   · 玩家侧走 equip_slots_for_level(赛季等级) → 每只 1~5 槽 (背包界面真正拦的是它)
##   · 快照/bot 侧走 equip_slots_for_battles(总战斗数) → 每只 0~4 槽 (只有 make_bot 和门禁在用)
##   于是: 玩家最多 5 槽/只而对手最多 4 槽/只; 玩家第一场就有 1 槽而对手 0 槽。
##   更讽刺的是 equip_slots_for_battles 的注释写着"V2 装备槽(设计§五)"—— 设计意图是按战斗数,
##   实装却走了按等级。2026-07-27 队列模拟撞出来: 机器人(真玩家规则)在档1 装了 2 件, 被门禁
##   (战斗数规则)判违规 —— 数据没错, 是断言的前提错了。
##
## 新规则两条约束, 完全自由分配(用户: 可以 3+3+3 堆满三个统领, 剩下的给小将):
##   ① 单只单位(统领或小将) ≤ UNIT_EQUIP_CAP
##   ② 全队 TEAM_UNITS 只【合计】 ≤ team_equip_cap(赛季等级)
## Lv10 的 18 = 6×3 正好把所有人塞满, 不多不少;
## Lv1 = 0 件 → 「人生第一把没装备」从特例变成规则的自然推论。
const UNIT_EQUIP_CAP := 3          # 单只统领/小将的装备上限 (固定, 不随等级变)
const TEAM_UNITS := 6              # 全队单位数 = 3 统领 + 3 小将 (每路 3 格 × 2 路)

## 全队合计装备上限 = (赛季等级-1) × 2 → Lv1..Lv10 = 0,2,4,6,8,10,12,14,16,18
static func team_equip_cap(level: int) -> int:
	return maxi(0, (clampi(level, 1, MAX_LEVEL) - 1) * 2)

## ══════════════════════════════════════════════════════════════════════
## bot 的**赛季等级**(= 它的装备预算, 见 `Backend.make_bot`)。索引 = 等级-1,
## 值 = 到这个等级至少要打过多少场。
##
## ★★★这不是「9 档」的马甲, 两者问的是**不同的问题**:
##   · 9 档问「跟谁打」—— 已按 D5 彻底删除, 匹配只认同场次。
##   · 这张表问「bot 该多强」—— bot 必须有个强度, 而强度得跟进度挂钩。
##
## ★★曲线是**量出来的, 不是我拍的**: 拿 `data/ghost_seed.json` 里 396 条真人队列
##   快照(0~35 场次, 每格 12 支), 按场次统计【全队装备件数中位】, 再反解
##   `team_equip_cap` 得到等级。实测拟合(2026-09-26):
##     36 个场次里 **33 个完全命中**, 另 3 个(场次 4 / 17 / 21)差 1 件。
##   ⇒ `tools/bot_level_fit_audit.py` 每次门禁重新量一遍, 表一漂就红
##     (memory fb-hand-rolled-copies-drift: 手抄的副本必然落后, 所以给它配个读者)。
##
## ★★旧算法是 `bot_lv = 2 + bracket_for_battles(battles)`, 它在**场次 0** 那格是错的:
##   给 bot 算 Lv2 = 2 件装备, 而真人在人生第一把是 **0 件**(`UNIT_EQUIP_CAP` 头注
##   那条「Lv1 = 0 件 → 人生第一把没装备」)。⇒ 新表把 0 场次修回 Lv1 = 全裸。
## ★为什么没有 Lv2: 打完第一场就有币进商店, 实测中位直接是 4 件(= Lv3)。
##   Lv2 那一格在真实经济里**不存在**, 表如实反映(两个 1 并排)。
## ══════════════════════════════════════════════════════════════════════
const BOT_LV_MIN_BATTLES := [0, 1, 1, 3, 5, 9, 13, 18, 22, 28]

## 场次 → bot 赛季等级(1..MAX_LEVEL)。单调不减。
static func bot_level_for_battles(battles: int) -> int:
	var lv := 1
	for i in range(BOT_LV_MIN_BATTLES.size()):
		if battles >= int(BOT_LV_MIN_BATTLES[i]):
			lv = i + 1
	return clampi(lv, 1, MAX_LEVEL)

# ─── 敌方 AI 购物策略 (2026-06-24: AI 不再攒币不买) ─────────────
## AI 先留够这么多币当装备预算上限内才花钱买经验升级 (高于此阈值的盈余才用来买XP开槽);
## 保证 AI 永远留得起一轮装备, 不会把币全砸进升级而买不起货架。
const AI_GEAR_RESERVE := 12        # 买XP前先留 ≥ 这么多币给装备 (约 3~4 件 1 费货)
## AI 每次调用最多买几次经验 (防一次性把盈余全升完, 跟玩家逐回合节奏); 每次=BUY_XP_COST 币得 BUY_XP_AMOUNT XP。
const AI_MAX_XP_BUYS_PER_VISIT := 3

## 从 level 升到 level+1 所需 XP; level≥MAX_LEVEL → 极大(不可升).
static func xp_to_next(level: int) -> int:
	var i: int = clampi(level, 1, MAX_LEVEL) - 1
	if i < 0 or i >= LEVEL_XP_THRESHOLDS.size():
		return 999999
	return int(LEVEL_XP_THRESHOLDS[i])

# ─── 双路龟蛋战斗 (V3.2) ─────────────────────────────────────
const EGG_HP_BASE := 3000             # 龟蛋基地基础 HP (用户 2026-07-19: 2000→3000)
const EGG_HP_PER_AVG_LEVEL := 300     # + 300 × 大轮等级 (用户 2026-07-19: 100→300)

## 龟蛋 HP = 基础 + 每均等级增量 × 均等级.
static func egg_hp(avg_level: float) -> int:
	return EGG_HP_BASE + int(round(EGG_HP_PER_AVG_LEVEL * avg_level))

# ─── 商店费用概率: 随整局进度走 (用户 2026-06-12) ──────────────
## 把整局(上路+下路+终极战场)的总进度分 10 个档. 每档对【费用 1~5】(=普通/精良/稀有/史诗/传说)
## 给一套出现概率%(每行和=100). 档越高 → 高费概率越大, 低费越小 (TFT 风刷新曲线).
## 数值占位, 可整表替换调平衡. 用 stage_for_shop_visit 把"第几次开店"映射成档.
## 锚点(用户 2026-06-12): 档1=纯费1, 档2=75/25, 档3=55/35/10, 费3(稀有)档6起=35/40/33/26/20(峰档7),
## 费4(史诗)档5起=1/5/10/17/24/30, 费5(传说)档7起=1/9/17/25, 档10=10/15/20/30/25.
## 其余按云顶之弈Set17商店概率(TFT shop odds)的曲线形状补: 费3档4/5=15/20(TFT 3-cost L4/L5), 费1顺势降不平台.
## 费1非增, 费2峰档3后非增, 费4/5非减; 费3峰在档7. 行和=100.
const SHOP_COST_ODDS := [
	[100,  0,  0,  0,  0],   # 档1
	[ 75, 25,  0,  0,  0],   # 档2
	[ 55, 35, 10,  0,  0],   # 档3
	[ 52, 33, 15,  0,  0],   # 档4
	[ 48, 31, 20,  1,  0],   # 档5
	[ 33, 27, 35,  5,  0],   # 档6
	[ 26, 23, 40, 10,  1],   # 档7
	[ 22, 19, 33, 17,  9],   # 档8
	[ 16, 17, 26, 24, 17],   # 档9
	[ 10, 15, 20, 30, 25],   # 档10
]
const SHOP_STAGES := 10

## 某档的费用概率行 (费1..费5 的%). stage clamp 到 1..10.
static func shop_cost_odds(stage: int) -> Array:
	return SHOP_COST_ODDS[clampi(stage, 1, SHOP_STAGES) - 1]

## 按某档概率掷一个费用档 (1..5). r ∈ [0,1).
static func roll_cost_tier(stage: int, r: float) -> int:
	var odds: Array = shop_cost_odds(stage)
	var pick := clampf(r, 0.0, 0.999999) * 100.0
	var acc := 0.0
	for i in range(odds.size()):
		acc += float(odds[i])
		if pick < acc:
			return i + 1
	return odds.size()

## 第 n 次开店(从0起, 跨上/下/终极累计) → 档位. 第1次=档1, 封顶档10.
## (整局总开店次数 = 三战场各自每 SMALL_SHOP_EVERY_ROUNDS 回合开一次之和; 不预知总数, 按累计推进.)
static func stage_for_shop_visit(visit_index: int) -> int:
	return clampi(visit_index + 1, 1, SHOP_STAGES)

# ─── 终极战场 + 永恒 buff (G) ────────────────────────────────
const NO_DRAW := true                    # 无平局 (回合交替→总有先后)


# ═══════════════════════════════════════════════════════════════
#  头衔 (E-B5 · D12 四档 · 2026-09-24)
#
#  ★★头衔是**跨大轮唯一保留的资产** —— 大轮切换(`start_new_season`)与
#    清档(`reset_save`)都不许清。漏一处就是静默丢掉玩家唯一的永久东西。
#  ★存法定死: 一条 `{id, week}` —— **同一档同一周只记一条**。
#    存了 week 就意味着"带届数还是带计数"**只是渲染问题**, 随时能改。
#  ★后两档(四强/冠军)现在**拿不到**: 周日玩法没上线。规则照样写在这里,
#    判据也照样有门禁守 —— 让「没上线」是个可读状态, 而不是一段悄悄不执行的代码。
# ═══════════════════════════════════════════════════════════════
const TITLE_CHAMPION := "champion"        # 冠军: 周日夺冠
## ★★亚军(用户 2026-10-04「加『亚军』头衔」): 决赛那一场的输家。
##   原稿 §奖励 原话就是「冠军/亚军/四强/…逐档」, D12 当时只落了四档。
##   依据与冠军同源: 服务端 feed 里决赛那一格的 `done`(见 `Bracket.my_progress`)。
##   ★累加不顶替(D12「可累加的列表」+ 冠军本来就同时拿四强): 亚军同时保留四强。
const TITLE_RUNNER_UP := "runner_up"      # 亚军: 周日决赛告负
const TITLE_SEMIFINAL := "semifinal"      # 四强: 周日打进四强
const TITLE_FINALS_DAY := "finals_day"    # 进决赛日: 周六闯关赛晋级
const TITLE_FULL_QUOTA := "full_quota"    # 积分赛满配额: 本周 24 场打满

## 显示名。★一个来源 —— 主菜单/排行榜/结算都从这儿取。
const TITLE_LABEL := {
	TITLE_CHAMPION: "冠军",
	TITLE_RUNNER_UP: "亚军",
	TITLE_SEMIFINAL: "四强",
	TITLE_FINALS_DAY: "进决赛日",
	TITLE_FULL_QUOTA: "满配额",
}

## 展示顺序(含金量从高到低)。★不靠字典键序 —— Godot 字典有序但那是**插入序**,
##   谁手滑调一下常量位置显示就跟着变, 而这是**产品决定**不是实现细节。
const TITLE_ORDER := [TITLE_CHAMPION, TITLE_RUNNER_UP, TITLE_SEMIFINAL, TITLE_FINALS_DAY, TITLE_FULL_QUOTA]

## ══════════════════════════════════════════════════════════════════════
##  周日「结果封存」那一屏说什么(原稿 §五.5)
## ══════════════════════════════════════════════════════════════════════
## ★★做成纯函数而不是就地写在结算卡里: 只写在屏幕里的话, 门禁只量得到"此刻"那一格,
##   而这句话**一周只在周日出现**(同族已栽过四次: 判据挂在星期几上)。
## ★玩家在这一屏的三个问题, 三句话各答一个 —— 少答一个就等于没说:
##   ① 为什么不告诉我输赢 ② 什么时候知道 ③ 去哪看
## ★不承诺具体秒数: 揭晓时刻由服务端的轮次推进决定(`finals_round_sec`),
##   客户端说死一个数就会变成"说了做不到的事"。
static func finals_sealed_sub() -> String:
	return "双方同时开打 · 结果统一在本轮开播时揭晓\n去【决赛日 → 看对阵图】等翻面"


## 这一档现在拿得到吗。★冠军/四强要周日玩法上线 —— 与门那一套同一条闸。
static func title_earnable(tid: String) -> bool:
	if tid == TITLE_CHAMPION or tid == TITLE_RUNNER_UP or tid == TITLE_SEMIFINAL:
		return phase_mode_live(PHASE_FINALS)
	return tid == TITLE_FINALS_DAY or tid == TITLE_FULL_QUOTA


## 把一条头衔记录规范化成 `{id, week}`。★week 是**周一锚点**, 与赛程同口径。
static func title_row(tid: String, week: int) -> Dictionary:
	return {"id": str(tid), "week": int(week)}


## 这条记录已经在列表里了吗(同档同周算同一条)。
## ★去重判据只看 id + week —— 同一周把配额打满两次不该变成两个头衔。
static func title_has(list: Array, tid: String, week: int) -> bool:
	for r in list:
		if not (r is Dictionary):
			continue
		if str((r as Dictionary).get("id", "")) == str(tid) \
				and int((r as Dictionary).get("week", -1)) == int(week):
			return true
	return false


## 每一档各拿了几次 → `{id: 次数}`。主菜单那一行的「冠军 ×3」就是它。
static func title_counts(list: Array) -> Dictionary:
	var out: Dictionary = {}
	for r in list:
		if not (r is Dictionary):
			continue
		var tid := str((r as Dictionary).get("id", ""))
		if tid == "":
			continue
		out[tid] = int(out.get(tid, 0)) + 1
	return out


## 最高的那一档(含计数)。空列表 → 空串。
## ★主菜单只放这一个: 那一行宽 382px, 完整串接在战绩后面会溢出;
##   而玩家要一眼看到的本来就是**最硬的那个**, 列全反而谁都看不清。
##   完整列表走 `title_line()`(战绩屏/排行榜)。
static func title_top(list: Array) -> String:
	var cnt := title_counts(list)
	for tid in TITLE_ORDER:
		var n: int = int(cnt.get(tid, 0))
		if n > 0:
			var nm := str(TITLE_LABEL.get(tid, tid))
			return nm if n == 1 else "%s ×%d" % [nm, n]
	return ""


## 主菜单/排行榜那一行的文字。★空列表返回空串 —— 由调用方决定"没头衔时显示什么",
##   在这里塞一句「暂无头衔」就等于把文案决定焊死在规则层。
## 例: `冠军 ×2 · 四强 · 满配额 ×5`(只拿过一次的不写 ×1 —— ×1 是噪声)。
static func title_line(list: Array) -> String:
	var cnt := title_counts(list)
	var parts: Array = []
	for tid in TITLE_ORDER:
		var n: int = int(cnt.get(tid, 0))
		if n <= 0:
			continue
		var nm := str(TITLE_LABEL.get(tid, tid))
		parts.append(nm if n == 1 else "%s ×%d" % [nm, n])
	return " · ".join(parts)


# ═══════════════════════════════════════════════════════════════
#  玩家昵称 (2026-09-24 · 用户「这个在创建账号应该一起吧」)
#
#  ★挂在**绑定邮箱**那一屏 —— 那是玩家唯一感知得到的「创建账号」时刻:
#    首启建匿名号是**静默**的, 全程没有任何账号界面。
#  ★没绑邮箱的匿名号**不强制** —— 它本来也不进决赛日, 用兜底短码就够。
#  ★规则只在这里写一份: 输入框校验 / 存档 / 上传 / 对阵图四处都调它。
# ═══════════════════════════════════════════════════════════════
const NICK_MIN := 2                # 一个字也能认人吗? 不能 —— 至少两个
const NICK_MAX := 8                # 对阵图那一格放得下的上限(8 个汉字 ≈ 96px)

## 规范化: 去首尾空白 + 把内部连续空白压成一个 + 丢掉控制字符。
## ★**先规范化再判长度** —— 否则「  a  」这种能靠空白凑够长度。
static func nickname_clean(raw: String) -> String:
	var out := ""
	var prev_sp := false
	for ch in raw.strip_edges():
		var c := int(ch.unicode_at(0))
		if c < 32 or c == 127:
			continue                      # 控制字符: 换行/制表/退格 —— 一律丢掉
		if ch == " " or ch == "\u3000":
			if prev_sp:
				continue                  # 连续空白压成一个
			prev_sp = true
			out += " "
			continue
		prev_sp = false
		out += ch
	return out.strip_edges()


## 规范化之后合不合法。★判的是**规范化后的**串, 与 `nickname_clean` 成对使用。
static func nickname_valid(raw: String) -> bool:
	var s := nickname_clean(raw)
	return s.length() >= NICK_MIN and s.length() <= NICK_MAX


## 不合法时该对玩家说什么。★空串 = 合法(调用方据此判断要不要报错)。
static func nickname_error(raw: String) -> String:
	var s := nickname_clean(raw)
	if s.length() < NICK_MIN:
		return "名字太短了 —— 至少 %d 个字" % NICK_MIN
	if s.length() > NICK_MAX:
		return "名字太长了 —— 最多 %d 个字(现在 %d 个)" % [NICK_MAX, s.length()]
	return ""


## 没设昵称时显示什么。★确定性: 同一个账号每次算出来都一样。
##   取**哈希**不取前缀 —— id 有公共前缀时取前缀会让所有人重名
##   (2026-09-24 门禁当场拓出来的)。
## ★★2026-10-04 换形(用户「换成随机像人的昵称」): 原来是「龟主-xxxxx」短码 ——
##   一眼就是没起名的号(周日实况 6 个真人号全叫这个)。现在从**预填名生成器**
##   (`nickname_suggest_at`, 机器人也用它)里按哈希挑一个 ⇒ 同一个号永远同一个名字。
## ★★这里只是**生成器**(纯函数)。玩家真正显示的默认名由 `GameState.default_nickname()`
##   第一次调用时生成并存进**独立字段** `nickname_default`(用户 2026-10-04 拍板), 之后不再变 ——
##   池子(pets.json)增改也不会把它换掉。
## ★★老玩家: 存档里 `nickname == ""` 就是「没自己起过名」⇒ 下次开游戏生成新名并冻结;
##   自己起过名的(`nickname` 非空, 哪怕起的就是「龟主-xxxxx」)一个字都不碰。
## ⚠ 别把默认名写进 `GameState.nickname` —— 写了就分不清「默认」和「自己起的」。
static func nickname_fallback(account_id: String) -> String:
	if account_id == "":
		return NICK_LAST_RESORT
	var h := account_id.sha256_text()
	## 两段互不重叠的哈希分别挑定语/名头。★`hex_to_int` 读 7 位(28 bit)不会溢出成负数。
	return nickname_suggest_at(h.substr(0, 7).hex_to_int(), h.substr(7, 7).hex_to_int())


## 连种子都没有(既没账号也没安装号)时的名字。★不能再走 `nickname_suggest_at` ——
##   它自己的兜底就是回到这里, 走了会互相递归。
const NICK_LAST_RESORT := "小龟主"


## 默认名用哪个种子。★账号优先(换设备找回账号 ⇒ 名字跟着账号走, 服务端那份对得上);
##   还没拿到账号(首启离线 / 没配后端)时用**本机安装号**, 免得所有离线新人同名。
static func nickname_seed(account_id: String, install_uid: String) -> String:
	return account_id if account_id != "" else install_uid


# ═══════════════════════════════════════════════════════════════
#  玩家 ID —— 「名字可以重, ID 分得开」(用户 2026-10-04「行啊，做做看，别搞出ai味的就行」)
#
#  ★名字不唯一(池子 336 个, 而且玩家能自己改), 同名的两个人靠这串短码区分 ——
#    Clash Royale 的 `#2PP` 玩家标签就是这个做法。**它只管"看得出是两个人"**,
#    真正的身份仍然是 account_id(主键 / 去重 / 匹配记账一律用它, 不用这串)。
#  ★形状 `#` + 6 位, 字母表 28 个: 数字 2~9 + 大写辅音(去掉全部元音 A E I O U, 再去掉 L)。
#    · 0/O、1/I/L 在小字号里分不清 ⇒ 都不要(Crockford base32 的思路, 再严一点)
#    · 元音全去掉 ⇒ 拼不出单词(`#FAKE22` / `#DEAD..` 这种巧合); Clash Royale 的标签字母表也没有元音
#    ⇒ 28^6 ≈ 4.82 亿种。为什么不用纯 6 位数字(老卡片上那种 `#195060`):
#    10^6 = 100 万种, 1 万个账号按生日碰撞要撞出约 **50 对**(n²/2N), 而这里约 **0.10 对**。
#  ★撞了会怎样: 两个人显示同一串 —— 只是看起来像, 什么都不会合并
#    (没有任何代码拿这串当键)。同名又同号的概率再乘 1/336。
#  ★纯函数、确定性: 同一个身份串在任何设备上算出同一个号, 不存盘、不上传 account_id 本身
#    (sha256 单向, 从号推不回账号)。
# ═══════════════════════════════════════════════════════════════
const TAG_ALPHABET := "23456789BCDFGHJKMNPQRSTVWXYZ"
const TAG_LEN := 6
## 加盐: 与 `nickname_fallback` 用的同一个 account_id 摘要分开(否则名字与号码相关联)。
const TAG_SALT := "turtle-id:"


## 身份串 → `#XXXXXX`。空串返回 ""(调用方自己决定没有身份时显示什么)。
static func player_tag(identity: String) -> String:
	if identity == "":
		return ""
	var h := (TAG_SALT + identity).sha256_text()
	## 48 bit(12 位十六进制) 远大于 28^6 ≈ 2^28.8 ⇒ 取模偏差可忽略; 不会溢出成负数。
	var v: int = h.substr(0, 12).hex_to_int()
	var out := ""
	for i in range(TAG_LEN):
		out = TAG_ALPHABET[v % TAG_ALPHABET.length()] + out
		v /= TAG_ALPHABET.length()
	return "#" + out


## 是不是一串合法的玩家 ID(`#` + 6 位、全在字母表里)。
static func tag_valid(s: String) -> bool:
	if s.length() != TAG_LEN + 1 or not s.begins_with("#"):
		return false
	for i in range(1, s.length()):
		if TAG_ALPHABET.find(s[i]) < 0:
			return false
	return true


## 「这串名字里哪些需要带上 ID 才分得开」—— 出现两次及以上的那些名字。
## ★界面只在**真的重名**时才把号码摆出来(排行榜 / 对阵图), 不往每个名字后面贴 #号。
static func names_needing_tag(names: Array) -> Dictionary:
	var cnt := {}
	for n in names:
		var k := str(n)
		cnt[k] = int(cnt.get(k, 0)) + 1
	var out := {}
	for k in cnt.keys():
		if int(cnt[k]) >= 2:
			out[k] = true
	return out


## 最终显示名: 有昵称用昵称, 没有用兜底。**所有要显示玩家名字的地方都调它。**
static func display_name(nick: String, account_id: String) -> String:
	var s := nickname_clean(nick)
	if s.length() >= NICK_MIN:
		return s
	return nickname_fallback(account_id)


# ═══════════════════════════════════════════════════════════════
#  预填一个名字 —— 让玩家**一个字都不打**也能过去 (2026-09-29)
#
#  ★由来: 逐像素量过的 13 屏参考里, 取名那一步的设计目标是「不打字也能过」——
#    Sonic Rumble 预填 `Player_561962` 直接点 OK; Monster Hunter Stories /
#    Lapis / Worms 给一个 Generate 钮; Cat Game 重名时给三个候选让你点;
#    Angry Birds Match 直接发一个 `AwesomeHyacinth`。
#    而我们原来是**空框 + 一行规则**, 玩家开局第一件事就是用虚拟键盘打中文。
#  ★★名字要**像这个游戏的**, 不是 `Player_561962`:
#    定语从 `data/pets.json` 的龟名里剥出来(去掉尾巴的「龟」/「乌龟」),
#    名头用本仓自己的词: `龟主` 就是 `nickname_fallback` 已经在用的那个词,
#    `统领` / `小将` 是本作的单位定位, `大师` 出自「训龟大师」。
#  ★★★池子**跟着 pets.json 走**, 不在这里抄一份龟名 ——
#    抄一份就等于以后加的龟悄悄不进池(memory `fb-hand-rolled-copies-drift`)。
# ═══════════════════════════════════════════════════════════════
const NICK_HEADS := ["龟主", "龟王", "统领", "小将", "大师", "教头"]
## 「换一个」那颗钮的字。★写在这里而不是屏上: 门禁要拿它找那颗钮,
##   两边各写一份就成了「改了屏上那个字门禁还在找旧的」。
const NICK_REROLL := "换一个"
## 词表的**唯一出口**。★定语池故意不列在这里 —— 它整张从 `stem_src`
##   摸出来(见 `nickname_stems`), 列在这里就是拄一份永远落后的副本。
const NICK_WORDS := {
	"heads": NICK_HEADS,
	"stem_src": "res://data/pets.json",
}
## 只在**读不到 pets.json** 时用(dev / 裸实例)。不是第二份事实源, 所以故意只留几个。
const NICK_STEM_FALLBACK := ["小", "石头", "忍者", "闪电", "海盗", "彩虹"]


## 定语池。两个来源, **都在 `data/pets.json` 里**:
##   ① 28 个龟名剥掉尾巴的那个「龟」/「乌龟」(石头 / 彩虹 / 海盗…)
##   ② 28 个被动技名(不屈 / 坚壁 / 涅槃 / 水晶共鸣…) —— 它们本来就是这个游戏
##     自己的词, 拼上名头读起来就是个头衔(「不屈龟主」「水晶共鸣大师」)。
## ★★为什么要两个来源: 只拿龟名是 28×6 = **168** 个名字, 按生日碰撞算,
##   10 个人里就有 24% 的概率撞名; 加上被动技名是 56×6 = **336**, 降到 12%。
##   (参考里的 `Player_561962` 是拿**数字**拉开的, 而本轮明确不要那种名字 ⇒
##    不加数字的前提下, 撞名只能缩小不能消灭。撞了也只是重名, 玩家改得掉:
##    本仓任何一处都没有昵称唯一性约束。)
## ★去重 —— 两处剥出同一个词时池子不该有两份。
static func nickname_stems() -> Array:
	var out: Array = []
	for p in DataRegistry.all_pets:
		var pd := p as Dictionary
		var nm := str(pd.get("name", "")).strip_edges()
		if nm.ends_with("乌龟"):
			nm = nm.substr(0, nm.length() - 2)
		elif nm.ends_with("龟"):
			nm = nm.substr(0, nm.length() - 1)
		if nm != "" and not out.has(nm):
			out.append(nm)
		var pas := str((pd.get("passive", {}) as Dictionary).get("name", "")).strip_edges()
		if pas != "" and not out.has(pas):
			out.append(pas)
	return out if not out.is_empty() else NICK_STEM_FALLBACK.duplicate()


## 第 (si, hi) 个候选名。★**纯函数** —— 门禁据此穷举全池, 证明每一个都合法。
## ★龟名要是长到装不下名头就**截短**, 不是丢掉: 丢掉等于新龟悄悄不进池。
static func nickname_suggest_at(si: int, hi: int) -> String:
	var stems: Array = nickname_stems()
	if stems.is_empty():
		return nickname_fallback("")
	var stem := str(stems[posmod(si, stems.size())])
	var head := str(NICK_HEADS[posmod(hi, NICK_HEADS.size())])
	var room: int = maxi(NICK_MAX - head.length(), 1)
	if stem.length() > room:
		stem = stem.substr(0, room)
	var s := nickname_clean(stem + head)
	return s if nickname_valid(s) else nickname_fallback("")


## 池子一共多少个候选。★门禁的分母: N=0 就是空检查。
static func nickname_suggest_count() -> int:
	return nickname_stems().size() * NICK_HEADS.size()


## 命名随机源。裸的全局 `randi()` 会被 `tools/rng_discipline.py` 判红 ——
##   那条棘轮护的是「战斗 sim 的确定性不被悄悄回退」, 取名字虽然不在 sim 路径上,
##   但规矩是**不许裸全局 RNG**, 一处都不例外(留一个口子就没有棘轮了)。
static var _nick_rng := RandomNumberGenerator.new()

## 随便给一个候选名。★`avoid` 里那个**不许再给** —— 「换一个」按下去还是同一个名字,
##   就是本仓最忌的那种「点了没反应」。池子只剩一个时才会重复(这里 336 个)。
static func nickname_suggest(avoid: String = "") -> String:
	var n: int = nickname_suggest_count()
	if n <= 0:
		return nickname_fallback("")
	var heads: int = NICK_HEADS.size()
	var av := nickname_clean(avoid)
	var start: int = _nick_rng.randi() % n
	for k in range(n):
		var idx: int = (start + k) % n
		var s := nickname_suggest_at(idx / heads, idx % heads)
		if s != av:
			return s
	return nickname_suggest_at(start / heads, start % heads)


# ═══════════════════════════════════════════════════════════════
#  绑定邮箱 (2026-09-29 · 用户「那就不用必须绑定吧」)
#
#  ★★★这一节 2026-09-29 整段掉头。原来叫【登录墙】, 依据是用户 2026-09-24 的
#    「直接改为必须绑定账号吧」; 而**同一个用户在 2026-09-29 推翻了自己那句话**:
#      「那就不用必须绑定吧，是游客模式吗，其他的你自己推进」
#    ⇒ 后一句在后, 按后一句办。**墙不再拦人。**
#
#  ★「游客模式」这个词不准: 游戏**本来就给每个人发一个匆名账号**
#    (`account_id` + token, `SupabaseNet.sign_in_anonymous()`), 见 `account_email` 自己的注释
#    「"" = 匆名账号, 换设备会丢档」。三道闸分得很清楚:
#      · 排位 / 报名 / 看桶 / 周赛事 / 传鬼魂 → 「服务端认得出你是谁」⇒ **匆名号够**
#      · 云存档同步 → `SupabaseNet.sync_allowed()` = id/email/token 三者齐 ⇒ **这条才要邮箱**
#    ⇒ 邮箱**唯一**买到的是「换手机能接回来」。所以旧标题「绑定邮箱才能开始」
#      本身就是夸大的 —— 不绑也能开始。
#
#  ★★`sync_allowed()` **一个字没动**: 拆的是墙, 不是「云存档要邮箱」这条规则。
#    动它会让匆名号去写别人的档(memory `fb-id-without-owner-dimension`)。
# ═══════════════════════════════════════════════════════════════

## 【WALL_SOFT】墙还拦不拦人。**false = 不拦** —— 2026-09-29 那句话在代码里的唯一落点。
##
## ★★为什么不把那条分支删干净, 而是留一个常量: 门禁那条「拦不住人」的判据
##   必须能**反向验证** —— 把这一个字翻成 true, 墙当场回来, 那条判据当场红,
##   而且红的形状就是「走不过去」。删干净了就再也证不了它不是恒真式
##   (memory `fb-gate-must-measure-requirement-not-my-hook`)。
## ★★判据只有这一处。谁想再上墙, 改这一个常量 —— 不许在主菜单/设置页各判一份
##   (memory `fb-branch-to-an-unbuilt-mode-is-a-backdoor` 同一条纪律: 用命名常量挡住)。
const WALL_BLOCKS := false


## 该不该**请**他绑邮箱(非阻塞)? ★纯函数, 门禁穷举用。
##   backend_on = `SupabaseNet.enabled()`(后端**配了没有**, 与连不连得上无关)
##   email      = `GameState.account_email`
## ★★**「后端没配置」不算**: 那是 dev / 门禁状态, 不是玩家状态。
##   (拆墙之前这一条拦住的话 400 条门禁当场全红; 拆墙之后它只会在开发机的
##    主菜单上挂一句用不上的提示。同一个理由, 结论不变。)
static func bind_needed(backend_on: bool, email: String) -> bool:
	if not backend_on:
		return false
	return email.strip_edges() == ""


## 还该不该**拦**人? ★ 2026-09-29 起**恒假** —— 见 `WALL_BLOCKS`。
## ★条件本身不再拄一遍, 就是 `bind_needed` 那一条 —— 两处各写一份必然漂。
static func login_wall_on(backend_on: bool, email: String) -> bool:
	return WALL_BLOCKS and bind_needed(backend_on, email)


## 主菜单上那一句**非阻塞**的提示(拆墙之后唯一还会主动找玩家的地方)。
##
## ★★★为什么必须有它: 拆墙的代价是「一批人永远不绑, 换手机就丢档」——
##   用户是看过参考数据之后接受这个取舍的, 而缓解**只能**靠这一句。
##   ⇒ 它说的是**事实**(没备份) + **一个动作**(绑定), 不威胁、不拦路。
## ★不许退回成拦路: 它就是主菜单上一个可点元素, 点了去绑定屏, 不点照常玩。
## ★字**只在这一处**, 主菜单不自己拼 —— 抄一次永远落后一次。
static func bind_nudge_text() -> String:
	return "进度没备份 · 绑定邮箱"


## 绑定屏第一屏说什么。
## ★★★ 2026-09-29 换掉「绑定邮箱才能开始」—— **那句话本身就是假的**:
##   不绑也能开始(见本节头注那三道闸)。现在标题只说**绑了买到什么**。
static func login_wall_head() -> String:
	return "绑定邮箱，换手机也接得回来"


## 绑定屏上那段话。★**一行一句、按步分发**: 第一步印前面那些, 最后一句留给第二步
##   (`SettingsScene._email_why` / `_email_why2` 就是按换行切的)。
##
## ════════════════════════════════════════════════════════════════════
##  2026-09-29 改了两次: 先把「不做会失去什么」换成「这一步能得到什么」,
##  再(拆墙之后)把「不绑就接不回来」降成一句**陈述**, 并明说**不绑也能玩**。
## ════════════════════════════════════════════════════════════════════
## ★量出来的依据: 13 屏逐像素参考里, 「以后还能改」这句话到处都是 ——
##   Pokémon HOME「you can change this later, too!」/ Nier「This can be
##   changed later.」/ Octopath / Smash Legends / Sonic Rumble。
##   它干的事是**把这一步的心理成本压下去**。
##   而**参考里没有一屏是靠恐吓把人推过去的**。
## ★★「没绑邮箱换手机就接不回来」这个**事实不许删** —— 用户 2026-09-24 点名
##   「这一点要在 UI 上说清楚」。改的是**说法**(陈述 + 可逆), 不是事实本身。
## ★★第一句只说**买到什么**; 「不绑也能玩」摆第二句 —— 那是 2026-09-29 之后的真话,
##   写上去等于把这一屏自己的性质讲清楚: 它是个邀请, 不是一道闸。
static func login_wall_body() -> String:
	return ("绑上邮箱，换手机或重装都能把进度接回来。"
		+ "\n不绑也能玩 —— 只是换了手机接不回来；邮箱和名字以后随时能改。"
		+ "\n收不到验证码？看看垃圾邮件，或回上一步换个邮箱重发。")
