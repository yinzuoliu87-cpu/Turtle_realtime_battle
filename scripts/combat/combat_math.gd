class_name CombatMath
extends RefCounted
## 战斗通用小算式 (SIM · 无节点 · 可 headless 单测) —— combat/ 模块之一。
## 收纳跨系统反复出现的纯小公式(不属于 DamageMath 伤害结算、也不属于 UnitScaling 属性缩放的那些)。
## 与同族一样: 从 god file 抽出、去重、可单测、与原地行为逐位一致。

## 叠层衰减: 每次衰减到 80%(向下取整)。原逐字散在 3 处(18838/18845/18849)。
static func decay_stacks(stacks: int) -> int:
	return floori(stacks * 0.8)

## 血量分数 hp / max(1, maxHp)(钳分母防除零)。原逐字散在 4 处(7009/18896/23486/23589)。
static func hp_frac(hp: float, maxhp: float) -> float:
	return hp / maxf(1.0, maxhp)

## 技能就绪度 0..1: 冷却剩 cd、总冷却 max_cd → 1 - cd/max(0.01,max_cd), 钳到 [0,1]。
## 原逐字散在 2 处(24423/24757)。
static func cooldown_ready(cd: float, max_cd: float) -> float:
	return clampf(1.0 - (cd / maxf(0.01, max_cd)), 0.0, 1.0)
