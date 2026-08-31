class_name AxeEvolution
extends RefCounted
## 小木斧的【进化档位表】—— 纯数据, 没有行为 (用户 2026-08-31)
##
## ★这份表是小木斧一切数值的**唯一事实源**。装备属性、召唤物属性、进化阈值、
##   商店售价、斧头配色索引全从这里取; 别在别处再存一份(036 温泉蛋刚踩过
##   "同一个数存两份必漂"的坑, 它有两个写入点)。
##
## ★需求原文(用户 2026-08-31)节选:
##   「小木斧（1费）：为携带者提供20最大生命值，10攻击力，2护甲，2魔抗。
##     会有一个斧头召唤物（初始为木斧）登场，近战，普攻造成1ATK，攻速为0.8每秒。
##     斧头召唤物拥有500+已收集的经验值最大生命值，30+0.05已收集的经验值攻击力，
##     5护甲和5魔抗」
##   「满80经验值进化为石斧，满110铁斧，满130金斧，满160钻石斧，
##     此后积攒400经验值来完成一次最终进化。」
##
## ★已拍板的两条口径:
##   · 未决点 ⑥「已收集的经验值」= **历史累计**(`axe_exp_total`), 不是当前进度条。
##     ⇒ 进度条进化时清零、累计值只增不减; 大轮重置时两个都归零。
##     否则每次进化召唤物反而变弱, 进化成了惩罚。
##   · 未决点 ③ 费用**封顶 5 费** —— 本作出货表 `roll_cost_tier` 只认 1~5。
##     木斧 1 费, 每进化 +1 ⇒ 石2/铁3/金4/钻5, 最终造物**不再 +1**(仍是 5)。

## ── 档位 ──────────────────────────────────────────────────────
## 顺序即进化顺序。`need` = 从**上一档**升到本档需要攒够的进度条(需求给的是每段独立的阈值,
## 不是累计到 160 —— 见方案书「出入」第 6 条)。木斧是起点所以 need = 0。
const STAGES := [
	{"key": "wood",    "name": "木斧",   "need": 0,   "cost": 1},
	{"key": "stone",   "name": "石斧",   "need": 80,  "cost": 2},
	{"key": "iron",    "name": "铁斧",   "need": 110, "cost": 3},
	{"key": "gold",    "name": "金斧",   "need": 130, "cost": 4},
	{"key": "diamond", "name": "钻石斧", "need": 160, "cost": 5},
]
## 钻石斧之后再攒这么多, 才能做最终进化(四选一)。
const FINAL_NEED := 400

## 四个最终造物。**都是 5 费**(封顶, 未决点 ③)。
const FINALS := [
	{"key": "undead",   "name": "亡灵之斧", "cost": 5},
	{"key": "seraph",   "name": "炽天使",   "cost": 5},
	{"key": "holo",     "name": "全息斧",   "cost": 5},
	{"key": "ember",    "name": "余烬",     "cost": 5},
]

## ── 经验来源(需求字面值) ──────────────────────────────────────
const EXP_ON_BUY := 15          # 在商店里买这件装备
const EXP_ON_MATCH := 10        # 打完一整场对局(未决点 ②: 不论有没有走到决胜)
const EXP_ON_KILL := 2          # 斧头击杀, 或 3 秒内参与击杀
const ASSIST_WINDOW := 3.0      # "参与击杀"的时间窗(秒)

## ── 装备给携带者的属性(需求字面值·不随进化变) ────────────────
const OWNER_HP := 20.0
const OWNER_ATK := 10.0
const OWNER_DEF := 2.0
const OWNER_MR := 2.0

## ── 斧头召唤物 ────────────────────────────────────────────────
## 基础(木斧): 血 500 + 累计经验; 攻 30 + 0.05×累计经验; 双抗 5; 近战 1ATK 0.8 攻速
const MINION_HP_BASE := 500.0
const MINION_HP_PER_EXP := 1.0
const MINION_ATK_BASE := 30.0
const MINION_ATK_PER_EXP := 0.05
const MINION_DEF := 5.0
const MINION_MR := 5.0
const MINION_ASPD := 0.8

## 被动 3/4/5/6 每解锁一条给召唤物的加成(需求: 每条都是同样这四个数)。
const PASSIVE_HP := 50.0
const PASSIVE_ATK := 5.0
const PASSIVE_DEF := 3.0
const PASSIVE_MR := 3.0

## ── 通用主动(所有档位共有) ────────────────────────────────────
const ACTIVE_ENERGY := 140.0     # 龟能消耗
const ACTIVE_HEAL_PCT := 0.05    # 回复 5% 最大生命
const ACTIVE_SHIELD_PCT := 0.05  # 并给自己 5% 最大生命的护盾

## ── 被动 2(木斧就解锁): 普攻窃取目标护盾 ──────────────────────
const SHIELD_STEAL_PCT := 0.10   # 偷 10%, **转成普通护盾**给自己(特殊护盾也转)


## 本档索引 → 这一档的定义。越界钳住(防"最终进化后索引跑出去"把游戏搞崩)。
static func stage(i: int) -> Dictionary:
	return STAGES[clampi(i, 0, STAGES.size() - 1)]


## 从第 `i` 档升到第 `i+1` 档要攒够多少进度。已经是最后一档 → 返回最终进化的 400。
static func need_for_next(i: int) -> int:
	if i + 1 < STAGES.size():
		return int(STAGES[i + 1]["need"])
	return FINAL_NEED


## 召唤物在【历史累计经验 = exp_total】时的最大生命 / 攻击力。
## ★纯函数, 门禁直接调它验数 —— 不必打一场真战斗去撞。
static func minion_hp(exp_total: int, passives_unlocked: int = 0) -> float:
	return MINION_HP_BASE + MINION_HP_PER_EXP * float(exp_total) \
		+ PASSIVE_HP * float(maxi(0, passives_unlocked))


static func minion_atk(exp_total: int, passives_unlocked: int = 0) -> float:
	return MINION_ATK_BASE + MINION_ATK_PER_EXP * float(exp_total) \
		+ PASSIVE_ATK * float(maxi(0, passives_unlocked))


## 第 `i` 档解锁了几条【带属性的】被动。被动 2(木斧)不给属性, 被动 3~6 各给一份
## ⇒ 木斧 0 条、石斧 1 条、铁斧 2 条、金斧 3 条、钻石斧 4 条。
static func passives_at(i: int) -> int:
	return clampi(i, 0, STAGES.size() - 1)
