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
const RANKED_QUOTA := 24               # 场次配额(原稿: 与 8 命咬合, 16 胜双清)
const RANKED_BACKFILL_COINS := 16      # 补发地板/场: 原稿「固定数 + 满命×A」= 8 + 8×1, **不含胜利奖**
const RANKED_BACKFILL_XP := 2          # 补发经验/场(与实打每场 +2 同额)
const PROMOTE_TOP_PCT := 0.30          # 晋级线: 前 30%
## ★★硬线兜底: ≥N 胜保送。**原稿的正式值是 13**(`PROMOTE_WINS_FLOOR_SHIPPING`)。
## 现在取 5, 理由是算过的、不是随手改小:
##   一周 24 场配额 + 8 命 ⇒ 要拿 13 胜至少打 13 场且输不超过 8 场 ⇒ 胜率 >62%、场数 ≥21。
##   当前是 sideload 测试包、测试者个位数, **一个都到不了 13 胜 ⇒ 周六池空 ⇒ 闯关赛做了等于没做**。
## ⚠ 离线版**只有这条硬线**; 原稿的「前 30%」要一份收盘时刻的全服终榜(服务端排名),
##   那部分还没做 —— 做完之后把这里改回 `PROMOTE_WINS_FLOOR_SHIPPING`。
const PROMOTE_WINS_FLOOR := 5
const PROMOTE_WINS_FLOOR_SHIPPING := 13   # 原稿正式值(留在这里, 免得"临时值"变成永久值没人记得)

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
const BUCKET_CAP_PLAYERS := 32         # 桶容量; ★>16 → 32 人桶, ≤16 → 16 人桶依次减半(§4.6 自适应)
const BUCKET_SHOP_SEC := 180           # 桶内购物 3 分钟(原稿)
## ★D11 拍板: 重放节奏 3 → **4 分钟**。9457 场实测纯战斗超 3 分钟只占 0.17%、**超 4 分钟 0 场**,
##   ⇒ 放宽到 4 分钟即可全覆盖, **不必做加速播、也不给对局设硬时限**(用户原话「不用给每场设置时限的」)。
const BUCKET_REPLAY_SEC := 240
const FINALS_START_HOUR_UTC := 20      # 冠军签表开赛 20:00(同样是 UTC, 见 E2)

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
## 胜场也直接算进 `season_wins >= PROMOTE_WINS_FLOOR` 那条晋级硬线。
##
## 而原来屏幕上只说「休赛日 · 暂按积分赛规则」—— 一个字都没提这件事。
## 一个测试者周一兴致好打 24 场, 周二到周五点开打只会看到「本周配额 24 场已打满」,
## 而他完全不知道为什么。**说得不全和说错一样是缺陷。**
const PHASE_PENDING_NOTE := {
	PHASE_REST: "休赛日 · 暂按积分赛规则 · 打的算本周配额",
	PHASE_FINALS: "玩法开发中 · 暂按积分赛规则",
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

## 这个阶段要不要在赛程条上挂一句"还没上线"? 返回空串 = 照常, 不用额外说明。
## ★做成纯函数(而不是在主菜单里就地 if)是为了能**七天全量测**:
##   只在主菜单里写, 门禁就只能量"今天"那一格, 一周里有四天是空检查。
static func phase_pending_note(phase: String) -> String:
	if phase_mode_live(phase):
		return ""
	return str(PHASE_PENDING_NOTE.get(phase, "玩法开发中 · 暂按积分赛规则"))

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
const TITLE_SEMIFINAL := "semifinal"      # 四强: 周日打进四强
const TITLE_FINALS_DAY := "finals_day"    # 进决赛日: 周六闯关赛晋级
const TITLE_FULL_QUOTA := "full_quota"    # 积分赛满配额: 本周 24 场打满

## 显示名。★一个来源 —— 主菜单/排行榜/结算都从这儿取。
const TITLE_LABEL := {
	TITLE_CHAMPION: "冠军",
	TITLE_SEMIFINAL: "四强",
	TITLE_FINALS_DAY: "进决赛日",
	TITLE_FULL_QUOTA: "满配额",
}

## 展示顺序(含金量从高到低)。★不靠字典键序 —— Godot 字典有序但那是**插入序**,
##   谁手滑调一下常量位置显示就跟着变, 而这是**产品决定**不是实现细节。
const TITLE_ORDER := [TITLE_CHAMPION, TITLE_SEMIFINAL, TITLE_FINALS_DAY, TITLE_FULL_QUOTA]

## 这一档现在拿得到吗。★冠军/四强要周日玩法上线 —— 与门那一套同一条闸。
static func title_earnable(tid: String) -> bool:
	if tid == TITLE_CHAMPION or tid == TITLE_SEMIFINAL:
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
static func nickname_fallback(account_id: String) -> String:
	if account_id == "":
		return "龟主-0000"
	return "龟主-" + account_id.sha256_text().substr(0, 5)


## 最终显示名: 有昵称用昵称, 没有用兜底。**所有要显示玩家名字的地方都调它。**
static func display_name(nick: String, account_id: String) -> String:
	var s := nickname_clean(nick)
	if s.length() >= NICK_MIN:
		return s
	return nickname_fallback(account_id)


# ═══════════════════════════════════════════════════════════════
#  登录墙 (2026-09-24 · 用户「直接改为必须绑定账号吧」)
#
#  ★用户在三个选项里选的是**开局就必须绑, 没有 guest** ——
#    明确接受「没网 / 后端挂了就打不开」与「新玩家第一屏就是填邮箱」。
#  ★★**「后端没配置」不挡**: 那是 dev / 门禁状态, 不是玩家状态。
#    挡住它的话 384 条门禁当场全红、开发机上游戏根本打不开。
#    「没配」≠「没网」—— 出包时后端一定是配着的, 玩家永远遇不到「没配」;
#    而「配了但连不上」**照挡**(那正是用户选的代价)。
#  ★绑定走 `PUT /auth/v1/user`(**升级**现有匿名号, 同一个 id) ⇒
#    匿名号仍然是**技术引导步骤**(玩家看不见), 墙只是挡在它前面, 不重写认证。
# ═══════════════════════════════════════════════════════════════

## 现在该不该挡? ★纯函数, 门禁穷举用。
##   backend_on = `SupabaseNet.enabled()`(后端**配了没有**, 与连不连得上无关)
##   email      = `GameState.account_email`
static func login_wall_on(backend_on: bool, email: String) -> bool:
	if not backend_on:
		return false                      # ★后端没配 = dev/门禁, 不挡
	return email.strip_edges() == ""


## 墙上第一屏说什么。★老玩家升级过来会被挡一次 —— **第一句就得让他别慌**:
##   绑定是「升级同一个号」, 进度一个字节都不会变。
static func login_wall_head() -> String:
	return "绑定邮箱才能开始"


static func login_wall_body() -> String:
	return ("你的进度还在这台手机上 —— 绑定只是把它锁到这个邮箱上，"
		+ "换手机时能拿回来。\n收不到验证码？看看垃圾邮件，或者换一个邮箱重发。")
