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

## 积分赛(周二~周五)
const RANKED_QUOTA := 24               # 场次配额(原稿: 与 8 命咬合, 16 胜双清)
const RANKED_BACKFILL_COINS := 16      # 补发地板/场: 原稿「固定数 + 满命×A」= 8 + 8×1, **不含胜利奖**
const RANKED_BACKFILL_XP := 2          # 补发经验/场(与实打每场 +2 同额)
const PROMOTE_TOP_PCT := 0.30          # 晋级线: 前 30%
const PROMOTE_WINS_FLOOR := 13         # 硬线兜底: ≥13 胜保送(比例自伸缩 + 硬线)

## 闯关赛(周六)
const GAUNTLET_WINS_IN := 4            # 4 胜晋级
const GAUNTLET_LOSSES_OUT := 3         # 3 负出局
const GAUNTLET_QUOTA := 6              # 配额 6 场(原稿: 晋级率 ≈34%)
const GAUNTLET_BACKFILL_COINS := 8     # 补发地板/场(只补晋级者)
const GAUNTLET_BACKFILL_XP := 2

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
## ⇒ 在玩法上线之前, 这三天**按积分赛规则走**(吃配额、赛程条上直说"玩法开发中")。
##   把开关做成常量而不是就地写死, 是为了让"上线那天要改回去的地方"只有这一个字:
##   改成 `true`, 下面两个函数立刻恢复方案书 A3 设计的分流行为。
const WEEKEND_MODES_LIVE := false

## 这个阶段的场次, 要不要吃积分赛配额?
## ★★唯一事实源: `_settle_season()` 记账与 `GameState.ranked_quota_full()` 开闸
##   **必须是同一个答案** —— 两处各写一份 `if week_phase == "ranked"`, 就是同一判据存两份,
##   必然有一处落后(memory fb-hand-rolled-copies-drift; 这个洞第一次出现正是因为这样)。
## ⚠ 空串 = 赛程还没写进存档(老档/第一次开局) ⇒ 按积分赛计, 与 A3 的口径一致。
## ★写成「恒假分支在上、兜底在下」而不是 `if not WEEKEND_MODES_LIVE: return true`:
##   后者是**恒真常量分支 + return**, 会把下面那行吞成死代码 ——
##   `tools/const_branch_audit.py` 当场判红(实测红过一次), 而它是对的。
##   这个形状与仓里其余 5 个 A/B 开关一致: 暗着的是**还没上线的那一支**。
static func phase_uses_ranked_quota(phase: String) -> bool:
	if WEEKEND_MODES_LIVE:
		return phase == "" or phase == PHASE_RANKED
	return true                   # 玩法没上线 ⇒ 七天都是积分赛, 都吃配额

## 这个阶段要不要在赛程条上挂一句"还没上线"? 返回空串 = 照常, 不用额外说明。
## ★做成纯函数(而不是在主菜单里就地 if)是为了能**七天全量测**:
##   只在主菜单里写, 门禁就只能量"今天"那一格, 一周里有四天是空检查。
static func phase_pending_note(phase: String) -> String:
	if WEEKEND_MODES_LIVE or phase == PHASE_RANKED:
		return ""
	return "玩法开发中 · 暂按积分赛规则"

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
