extends RefCounted

## Phase2Config — 二阶段 经济/商店/双路龟蛋 数值集中地 (壳, 全占位)
##
## 用 preload 引 (不用 class_name):
##   const P2 = preload("res://scripts/engine/phase2_config.gd")
##
## 这里所有数字都是【占位】, 设计文档明确标"待实测调"。把它们集中在一个文件,
## 用户定稿后改这里一处即可。逻辑壳调用这些常量, 不把魔法数字散落各处。

# ─── 经济: 单一深海币, 每局重置 (沿用现有 GameState.battle_coins 容器) ───
const COIN_PER_ROUND := 10        # 占位: 每大回合基础产出 (现有经济同值)
const INTEREST_PER := 5           # 占位: 每持有 5 币生 1 利息
const INTEREST_CAP := 10          # 占位: 利息上限/回合
const COIN_ON_KILL := 2           # 占位: 击杀敌方单位奖励
const COIN_ON_LANE_WIN := 15      # 占位: 打赢一路奖励

# ─── V2 赛季 (阶段4) ─────────────────────────────────────────
const SEASON_DURATION_SEC := 432000   # 赛季时长 = 5 天 (设计§一; 占位, 调试可快进)

# ─── 商店 ───────────────────────────────────────────────────
const SMALL_SHOP_SLOTS := 10      # 小商店格数 (V2 §五: 一次展示10个, 用户 2026-06-25)
const SMALL_SHOP_EVERY_ROUNDS := 4  # 每 4 大回合开一次小商店
const SHOP_REFRESH_BASE := 2      # 刷新固定花费 (云顶式 flat 2, 不随同回合刷新次数递增)
const SHOP_REFRESH_STEP := 0      # 0 = 不递增 (用户 2026-06-25: 刷新一直是 2 费)
const BIG_SHOP_BETWEEN_LANES := true  # 大商店在上下路之间开 (卖消耗品)

# ─── 备战席 (背包栏) ─────────────────────────────────────────
const BENCH_CAP := 10             # 备战席容量
const DEPLOY_WINDOW_SEC := 30     # 出手前布置窗口 (拖装备到龟身)
const SLOTS_PER_TURTLE := 5       # 每龟装备槽

# ─── 局内等级 (TFT风, 用户 2026-06-12) ──────────────────────
## 每局重置的玩家等级 1-10; 绑定 ①龟蛋HP(=egg_hp(等级)) ②商店费用概率档(=SHOP_COST_ODDS[等级]) ③补位小将等级.
const MAX_LEVEL := 10
const PASSIVE_XP := 2            # 每大回合被动 XP (1:1 云顶: +2/回合)
const BUY_XP_AMOUNT := 4         # 买一次经验得的 XP (1:1 云顶: 4币=4XP)
const BUY_XP_COST := 4           # 买经验花的深海币 (1:1 云顶: 4币=4XP)
const DUAL_COIN_PER_ROUND := 10        # 每大回合局内币基础产出 (用户 2026-06-23: 5→10)
const DUAL_INTEREST_RATE := 0.20       # 每回合利息 = 持有深海币 × 20% (用户 2026-06-23)
const DUAL_INTEREST_CAP := 10          # 利息部分上限 +10/回合
## 升到下一级所需XP (索引0=1→2 ... 8=9→10). 满级10不再升. 1:1 云顶TFT 升级曲线 (用户 2026-06-23 "抄云顶";
##   2/6/10/20/36/48/76/84 = TFT 经典各级升级XP; lv9→10 各赛季有别, 取估值 94).
const LEVEL_XP_THRESHOLDS := [2, 6, 10, 20, 36, 48, 76, 84, 94]

## 每个统领可装备槽数 = 随局内等级逐步开放 (用户 2026-06-12): 1-2级1 / 3-4级2 / 5-6级3 / 7-8级4 / 9-10级5.
static func equip_slots_for_level(level: int) -> int:
	return clampi(ceili(level / 2.0), 1, 5)

## V2 装备槽: 按本赛季总战斗数开放 (设计§五, 用户 2026-06-26). ≤1战=0槽/≤3=1/≤5=2/≤8=3/>8=4.
static func equip_slots_for_battles(total_battles: int) -> int:
	if total_battles <= 1:
		return 0
	if total_battles <= 3:
		return 1
	if total_battles <= 5:
		return 2
	if total_battles <= 8:
		return 3
	return 4

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
const LANES := ["top", "bottom"]      # 上路 / 下路
const EGG_HP_BASE := 2000             # 龟蛋基地基础 HP (用户 2026-06-23: 翻倍 1000→2000)
const EGG_HP_PER_AVG_LEVEL := 100     # + 100 × 双方均等级 (用户 2026-06-23: 翻倍 50→100)
const LANE_HEAL_PCT := 0.30           # 每路结束, 幸存龟回复"已损HP"的 30%
const MINION_FILL := true             # 不足 3 龟的一路, 用小将补位

## 龟蛋 HP = 基础 + 每均等级增量 × 均等级.
static func egg_hp(avg_level: float) -> int:
	return EGG_HP_BASE + int(round(EGG_HP_PER_AVG_LEVEL * avg_level))

## 刷新花费: 固定 SHOP_REFRESH_BASE (云顶式 flat 2). STEP=0 → n 不影响, 恒 2.
static func shop_refresh_cost(n: int) -> int:
	return SHOP_REFRESH_BASE + SHOP_REFRESH_STEP * maxi(0, n)

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
const FINAL_LOSER_EGG_DMG_MULT := 5.0    # 败方蛋登场: 增伤 ×5
const FINAL_LOSER_EGG_SELF_LOSS := 0.25  # 败方蛋: 每回合自损 25% maxHP
const EGG_ATTACK_ROUNDS := 3             # 某路一方全灭, 存活方获 N 回合自由攻蛋 (§4)
const STANDBY_RECOVER_PCT := 0.30        # 待命回复: 存活单位回已损HP的 30% (§5)
const ETERNAL_AFTER_ROUND := 30          # 单场第 30 回合后触发"永恒"叠加 (每场独立计)
const ETERNAL_LEADER_STACK := 0.50       # 存活统领每回合 +50% 增伤/受伤 (仅统领, 小将/蛋不吃)
const NO_DRAW := true                    # 无平局 (回合交替→总有先后)

## 终极战场内 败方蛋登场后 单次攻蛋最终伤害 = 原始 ×5 (仅此阶段; 统领决战/上下路攻蛋仍 1×).
static func egg_final_hit(raw: int) -> int:
	return int(round(raw * FINAL_LOSER_EGG_DMG_MULT))

## 终极战场内 败方蛋每回合自损 = 25% maxHP.
static func egg_self_loss(egg_max_hp: int) -> int:
	return int(round(egg_max_hp * FINAL_LOSER_EGG_SELF_LOSS))

## 待命回复量: 已损失生命的 30% (只补已损部分, 不超上限).
static func standby_recover(cur_hp: int, max_hp: int) -> int:
	return int(round(maxi(0, max_hp - cur_hp) * STANDBY_RECOVER_PCT))

## 永恒 buff 伤害系数: N 层 → ×(1 + 0.5N) (造成与受到各自乘).
static func eternal_mult(stacks: int) -> float:
	return 1.0 + ETERNAL_LEADER_STACK * maxi(0, stacks)
