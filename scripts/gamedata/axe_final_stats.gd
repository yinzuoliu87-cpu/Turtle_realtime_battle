class_name AxeFinalStats
extends RefCounted
## 四个最终造物的**全部数值**(2026-09-01·方案书六期)
##
## ★需求原文(用户 2026-08-31)逐字, 每个数都能指回下面那段引用:
##
##   亡灵之斧: 「价格增加1费，这个被动给斧头召唤物提供1200点最大生命值，5攻击力，
##             10护甲和10魔抗。被动为召唤物会拥有一个300码的环，在环内的敌人每秒损失
##             1%最大生命值魔法伤害，并每秒每存在一个敌人会使斧头召唤物回复0.3%最大生命值。
##             斧头召唤物死亡后2.5秒会带着40%最大生命值重生。」
##
##   炽天使:   「提供50点最大生命值，20攻击力，3护甲和3魔抗，300码射程。被动为每次普攻
##             附带8层灼烧层数。主动效果4秒里的猛砸将被替换为4秒内投掷10把斧头回旋镖，
##             不再获得减伤，半径大小为300码，沿着目标所在的一条直线直直飞过，
##             对接触的目标造成1ATK魔法伤害和8层灼烧层数。」
##
##   全息斧:   「提供400点最大生命值，5攻击力，3护甲和3魔抗，50%龟能充能速率。每次普攻
##             将为血量最低的友方单位提供60护盾值和5龟能。主动4秒内的猛砸将被替换为将斧头
##             插入地下4秒，转而获得30%减伤，期间释放全息法阵使600码内的友军每0.5秒回复
##             100生命值和5龟能，并友军在范围内还获得30%攻击速度。」
##
##   余烬:     「提供150点最大生命值，80攻击力，80%攻击速度和20%移速。斧头召唤物在普攻
##             攻击命中目标时会给目标施加一层余烬种子，每层种子提供0.5%余烬处决线，
##             无限叠加。召唤物会处决目标低于余烬斩杀线的敌人，通过这个被动处决一个单位
##             会使召唤物获得150点龟能。主动技能的4秒猛砸将被替换为余烬之光，转而使其
##             接下来4秒获得25%生命偷取，25%减伤和25%攻击速度，并免疫控制，这期间不会
##             锁龟能，再次释放会提供一个新的余烬之光，不会打扰到当前的buff，独立的4秒。」
##
## ★为什么单独一个纯数据文件: 数值和行为分开, 门禁可以直接喂数验公式而不建战斗场;
##   而且**一个裸数字都不许出现在行为代码里**(036 温泉蛋踩过"同一个数存两份必漂")。
## ★键与 `AxeEvolution.FINALS` 的 key 一一对应, 门禁焊死这条(少一个 = 那个造物没数值)。

## 每个造物给召唤物的**属性**。缺省的键 = 这个造物不给这一项。
##   hp/atk/def/mr 是加算; aspd_pct/move_pct/energy_rate_pct 是百分比。
## ★★这九个数原来只以字面量存在 STATS 里, 于是**文案引用不到它们** ——
##   商店/图鉴里想写"亡灵之斧 +1200 生命"就只能手抄一遍, 那就是"同一个数存两份"。
##   ⇒ 抽成常量, 且 **STATS 必须真的读这些常量**(只加常量不改 STATS = 白抽,
##   memory [[fb-refactor-creates-the-drift-it-removes]]: 60 个常量只为文案而活)。
const UNDEAD_HP := 1200.0
const UNDEAD_ATK := 5.0
const UNDEAD_DEF := 10.0
const SERAPH_HP := 50.0
const SERAPH_ATK := 20.0
const SERAPH_DEF := 3.0
const SERAPH_RANGE := 300.0
const HOLO_HP := 400.0
const HOLO_ATK := 5.0
const HOLO_DEF := 3.0
const HOLO_ENERGY_RATE := 0.50
const EMBER_HP := 150.0
const EMBER_ATK := 80.0
const EMBER_ASPD := 0.80
const EMBER_MOVE := 0.20

const STATS := {
	"undead": {"hp": UNDEAD_HP, "atk": UNDEAD_ATK, "def": UNDEAD_DEF, "mr": UNDEAD_DEF},
	"seraph": {"hp": SERAPH_HP, "atk": SERAPH_ATK, "def": SERAPH_DEF, "mr": SERAPH_DEF,
		"range": SERAPH_RANGE},
	"holo":   {"hp": HOLO_HP, "atk": HOLO_ATK, "def": HOLO_DEF, "mr": HOLO_DEF,
		"energy_rate_pct": HOLO_ENERGY_RATE},
	"ember":  {"hp": EMBER_HP, "atk": EMBER_ATK, "aspd_pct": EMBER_ASPD, "move_pct": EMBER_MOVE},
}

# ── 亡灵之斧 ──────────────────────────────────────────────────
const UNDEAD_RING_R := 300.0        # 环半径(码)
const UNDEAD_RING_TICK := 1.0       # 每秒结算一次
const UNDEAD_RING_MAXHP_PCT := 0.01 # 环内敌人每秒掉 1% 最大生命【魔法伤害】
const UNDEAD_LEECH_PCT := 0.003     # 每秒·每个环内敌人, 自己回 0.3% 最大生命
const UNDEAD_REVIVE_DELAY := 2.5    # 死后多久重生
const UNDEAD_REVIVE_HP_PCT := 0.40  # 带多少最大生命回来

# ── 炽天使 ────────────────────────────────────────────────────
const SERAPH_BURN_ON_HIT := 8       # 每次普攻附带 8 层灼烧
const SERAPH_BOOMERANGS := 10       # 主动: 4 秒内投 10 把
const SERAPH_CAST_TIME := 4.0       # 那 4 秒(替换掉猛砸的蓄力)
const SERAPH_BOOM_R := 300.0        # 「半径大小为300码」—— 回旋镖的作用半宽
const SERAPH_BOOM_ATK := 1.0        # 1×ATK 魔法伤害
const SERAPH_BOOM_BURN := 8         # 命中再加 8 层灼烧
## ★「不再获得减伤」—— 炽天使的主动**没有**被动6那 70% 减伤。写成常量而不是"漏掉",
##   否则下一个人看不出这是有意的(需求原话: 「不再获得减伤」)。
const SERAPH_CHARGE_DR := 0.0

# ── 全息斧 ────────────────────────────────────────────────────
const HOLO_ONHIT_SHIELD := 60.0     # 普攻给【血量最低的友方】60 护盾
const HOLO_ONHIT_ENERGY := 5.0      # 并给 5 龟能
const HOLO_PLANT_TIME := 4.0        # 插地 4 秒
const HOLO_PLANT_DR := 0.30         # 期间 30% 减伤(不是被动6的 70%)
const HOLO_AURA_R := 600.0          # 法阵半径
const HOLO_AURA_TICK := 0.5         # 每 0.5 秒一跳
const HOLO_AURA_HEAL := 100.0       # 每跳回 100 生命
const HOLO_AURA_ENERGY := 5.0       # 每跳给 5 龟能
const HOLO_AURA_ASPD := 0.30        # 范围内友军 +30% 攻速

# ── 余烬 ──────────────────────────────────────────────────────
const EMBER_SEED_PER_HIT := 1       # 每次普攻命中挂 1 层种子
const EMBER_SEED_EXEC_PCT := 0.005  # 每层 +0.5% 处决线(**无上限**)
const EMBER_EXEC_ENERGY := 150.0    # 处决一个 → 召唤物 +150 龟能
const EMBER_LIGHT_TIME := 4.0       # 余烬之光持续 4 秒
const EMBER_LIGHT_LIFESTEAL := 0.25 # 25% 生命偷取
const EMBER_LIGHT_DR := 0.25        # 25% 减伤
const EMBER_LIGHT_ASPD := 0.25      # 25% 攻速


## 某个造物给的某项属性(没有 = 0)。★行为代码一律走这里取, 不许自己写数。
static func stat(final_key: String, field: String) -> float:
	var d = STATS.get(final_key, null)
	if not (d is Dictionary):
		return 0.0
	return float((d as Dictionary).get(field, 0.0))


## 余烬处决线: `stacks` 层种子 = 目标最大生命的百分之多少。
## ★纯函数、无上限(需求「无限叠加」) —— 门禁直接喂层数验, 并验它**真的不封顶**。
static func ember_exec_pct(stacks: int) -> float:
	return EMBER_SEED_EXEC_PCT * float(maxi(0, stacks))


## 目标现在该不该被余烬处决。
## ★判据是 `hp <= maxHp × 处决线`(**含等号**) —— 恰好在线上就该处决。
##   边界写错一格是这类功能最常见的 bug, 门禁两侧各量一次。
static func ember_should_execute(hp: float, max_hp: float, stacks: int) -> bool:
	if max_hp <= 0.0 or stacks <= 0:
		return false
	return hp <= max_hp * ember_exec_pct(stacks)


## 亡灵环这一跳: 环内 `n_enemies` 个敌人时, 召唤物回多少血。
static func undead_leech(max_hp: float, n_enemies: int) -> float:
	return max_hp * UNDEAD_LEECH_PCT * float(maxi(0, n_enemies))


## 亡灵环这一跳对单个敌人的伤害(按**目标**的最大生命算)。
static func undead_tick_dmg(target_max_hp: float) -> float:
	return target_max_hp * UNDEAD_RING_MAXHP_PCT
