extends RefCounted
## 龟能 (技能资源) — 单一事实源, 战斗/图鉴/选龟 共用, 防口径分叉。
##
## 模型 (用户定): 龟能按【固定速率】一直充能; 每个技能有【龟能花费】; 攒够花费才放得出。
##   所谓"冷却"不是独立计时器 —— 是龟能充满该技花费所需的时间:
##       冷却秒数 = 龟能花费 ÷ 充能速率 = 龟能花费 × CD_FACTOR
##   即【冷却 与 龟能充能 是同一回事】。这里只存"花费", 时间是换算出来的; 头顶蓄力条 = 龟能条。
##   花费越高(大招)→ 攒越久 → "冷却"越长。便宜的(龟盾)→ 放得勤。
##
## 引用方式: const SkillEnergy := preload("res://scripts/systems/skill_energy.gd")  (不用 class_name, 防 F5 未声明崩)

const COST_DEFAULT := 95.0
const CD_FACTOR := 0.075    # 龟能花费 → 充满秒数 (=1/充能速率); 70≈5.3s · 95≈7s · 140≈10.5s · 170≈12.8s (对齐 Botworld 沙蝎)

# 各技龟能花费 (∝ 技能强度): 轻盾/治/buff~70 · 普通伤害/控~95 · 全体/多段/强~120-140 · 变身/梭哈/大招~150-170
const SKILL_COST := {
	# 签名招
	"turtleShieldBash": 70.0, "bambooHeal": 90.0, "angelBless": 75.0, "angelAscend": 80.0, "stoneRockShield": 100.0, "rockShockwave": 80.0, "stoneTaunt": 120.0, "iceFrost": 120.0,
	"ninjaBackstab": 95.0, "ghostStorm": 95.0, "ghostPhase": 80.0, "diamondFortify": 70.0, "diceAllIn": 120.0, "diceFlashStrike": 120.0,
	"gamblerBet": 100.0, "hunterStealth": 80.0, "pirateCannonBarrage": 130.0, "pirateRum": 120.0, "bubbleShield": 80.0, "bubbleBurst": 100.0,
	"lineLink": 90.0, "lineInkBomb": 120.0, "lightningSurgeBuff": 90.0, "phoenixShield": 90.0, "phoenixEnhancedRebirth": 120.0, "headlessFear": 110.0,
	"fortuneDice": 70.0, "fortuneBuyEquip": 60.0, "crystalBarrier": 75.0, "chestCount": 90.0, "starWave": 100.0, "starGravityWarp": 120.0,
	"twoHeadStrike": 100.0, "twoHeadDisrupt": 95.0, "twoHeadFusion": 110.0, "lavaSurge": 150.0, "cyberBeam": 100.0, "hidingDefend": 70.0, "shellAbsorb": 100.0,
	# 通用
	"shield": 70.0, "heal": 70.0,
	# 数据驱动伤害
	"basicBarrage": 140.0, "bambooLeaf": 90.0, "bambooSmack": 120.0, "bambooSpikes": 130.0, "angelEquality": 125.0,
	"iceSpike": 120.0, "ninjaShuriken": 95.0, "ninjaBomb": 100.0, "twoHeadMagicWave": 100.0,
	"ghostTouch": 95.0, "ghostPhantom": 95.0, "diamondPowerball": 100.0, "diamondSmash": 80.0, "fortuneStrike": 90.0,
	"diceAttack": 95.0, "rainbowStorm": 125.0, "gamblerCards": 100.0, "gamblerDraw": 80.0, "gamblerFateWheel": 80.0,
	"hunterShot": 90.0, "hunterBarrage": 100.0, "candyBarrage": 120.0, "candyHammer": 80.0, "candyBomb": 100.0, "lineSketch": 90.0,
	"lightningStrike": 95.0, "lightningBarrage": 140.0, "phoenixBurn": 90.0, "phoenixScald": 100.0,
	"lavaBolt": 90.0, "lavaQuake": 115.0, "lavaErupt": 80.0, "crystalSpike": 90.0, "crystalBurst": 115.0,
	"chestStorm": 100.0, "starBeam": 70.0, "headlessTendrils": 160.0, "headlessSoulStrike": 80.0, "shellStrike": 80.0,
	# Batch2 特殊
	"chestCannon": 120.0, "fortuneAllIn": 340.0, "starWormhole": 150.0, "lineFinish": 95.0,
	"cyberDeploy": 135.0, "bubbleBind": 70.0, "hidingCommand": 85.0, "shellCopy": 140.0, "diceFate": 90.0,
}

## 该技龟能花费 (缺省 95)
static func cost_of(stype: String) -> float:
	return float(SKILL_COST.get(stype, COST_DEFAULT))

## 该技充满需多少秒 (= 花费 × CD_FACTOR); 即"冷却秒数"
static func charge_secs(stype: String) -> float:
	return cost_of(stype) * CD_FACTOR

## 该技是不是"要花龟能的主动技" (在花费表里=主动; 普攻/被动不在表里走自己的节奏)
static func is_active(stype: String) -> bool:
	return SKILL_COST.has(stype)
