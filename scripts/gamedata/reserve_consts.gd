class_name ReserveConsts
extends RefCounted
## 援军小将 —— 终极战场里一方没有任何幸存单位时代替出战(方案书 docs/plans/20261029-终极战场援军小将.md)。数值单一来源:
##   战斗(battle_spawn._make_unit / reserve_system)与图鉴文案都读这里, 不许各抄一份。
## 用户 2026-10-29 拍板: 1000 血 / 50 攻击 / 15 双抗 / 远程; 「玩家所战斗的每一个场次, 会使他的基础属性提升百分之四」;
##   龟能 135; 敌人前后左右各出现一道气波、四道同时往敌人中间走; 每道 100% 攻击力物理 + 该敌人 10% 最大生命值魔法。

const NAME := "援军小将"
const SKILL := "reserveConverge"
const SKILL_NAME := "四面合围"

const HP := 1000.0
const ATK := 50.0
const DEF := 15.0
const MR := 15.0
## 每打一场基础属性 +4%(线性, 按这一方本周已打场数 season_total_battles)。
const GROWTH_PER_BATTLE := 0.04
const MOVE := 105.0
const ATK_INTERVAL := 0.85
const RANGE := 400.0                ## 远程普攻射程(同远程小将)
const ENERGY := 135.0

const WAVES := 4
const WAVE_RADIUS := 260.0          ## 气波出现在目标前后左右多远
const WAVE_MAX_FLY := 900.0         ## 追踪气波最多飞这么远(追不上就消散)
const WAVE_OVERSHOOT := 60.0        ## (特效用)拖尾 / 预示线的长度参考: 出发半径之外再多画一段
const WAVE_SPEED := 380.0
const WAVE_HALF_W := 55.0
const WAVE_CATCHUP := 20.0         ## 往回补查(防迎面走来的敌人从两步之间穿过去; 见 battle_ballistics._first_on_segment)
const ATK_COEF := 1.0               ## 物理段: 100% 攻击力
const MAXHP_PCT := 0.10             ## 魔法段: 该敌人 10% 最大生命值(真实 maxHp, 不除 HP_MULT —— CLAUDE.md §3.1)
const CAST_RANGE := 600.0
const CAST_ROOT := 0.5              ## 施法定身


## 场数 ⇒ 属性倍率。1 + 0.04 × 场数: 乘加都是 IEEE-754 逐位一致的运算, 跨平台确定(不用 pow)。
static func growth_mult(battles: int) -> float:
	return 1.0 + GROWTH_PER_BATTLE * float(maxi(0, battles))


## 开战那一刻的底子(与 MinionCodex.base_stats 同形)。
static func base_stats(battles: int) -> Dictionary:
	var m := growth_mult(battles)
	return {"name": NAME, "rarity": "C", "crit": 0.0,
		"hp": HP * m, "atk": ATK * m, "def": DEF * m, "mr": MR * m}
