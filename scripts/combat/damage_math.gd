class_name DamageMath
extends RefCounted

## 暴击率溢出 100% 的部分, 每 1 点转成多少暴击伤害
## (文案: "暴击机率超过 100% 的部分, 每 1% 转化为 1.5% 暴击伤害")。
const CRIT_OVERFLOW := 1.5
## 战斗纯数学 (SIM · 无节点 · 可 headless 单测) —— 结构治理·切片2 的【模式验证】。
##
## 大厂做法(Riot「gameplay-deterministic·纯逻辑隔离」/ Cliffski「SIM 与 GUI 分家」):
## 把 25k 行 god file(RealtimeBattle3DScene) 里【纯算式】逐步搬到无节点模块, 主场景只调静态函数。
## 好处: ①可单测(不等 tween、不碰节点) ②去重(同一算式原本逐字散在多处→漂移风险) ③给"确定性 sim"铺路。
##
## 这是第一刀·只搬一个反复重复的算式(暴击倍率), 证明"纯逻辑能从 god file 抽出并单测"。
## 后续再逐个搬(减伤/闪避/斩杀线…), 每搬一个都门禁全绿 + 与原地行为逐位一致。

## 暴击伤害倍率。
## crit_dmg 为基础倍率(默认 1.5); 暴击率(crit_chance)溢出 100% 的部分, 每 1% → +1.5% 暴伤。
## 例: crit_chance=1.2(120%), crit_dmg=1.5 → 1.5 + (0.2)*1.5 = 1.8。
## 与 god file 原地公式逐字一致: crit_dmg + maxf(0.0, crit-1.0) * 1.5。
static func crit_multiplier(crit_chance: float, crit_dmg: float) -> float:
	return crit_dmg + maxf(0.0, crit_chance - 1.0) * CRIT_OVERFLOW

## 护甲/魔抗 → 伤害倍率(经典递减曲线, 常数 K=40)。resist 已含穿透后的净值。
## resist≥0: 减伤 → 1 - resist/(resist+40)  (resist=40→0.5·resist=120→0.25·resist=0→1.0)
## resist<0(负护甲/魔抗): 增伤 → 1 + |resist|/(|resist|+40)  (resist=-40→1.5)
## 与 god file 原地公式逐字一致(原散在 3 处: _resolve_dmg 9075 / _atk_dmg 9094 / 18817)。
static func resist_multiplier(resist: float) -> float:
	if resist >= 0.0:
		return 1.0 - resist / (resist + 40.0)
	return 1.0 + absf(resist) / (absf(resist) + 40.0)

## 穿透后的净抗性: 先按百分比穿透(pen_pct), 再减固定穿透(flat_pen)。可为负(过穿→增伤·配合 resist_multiplier)。
## base_resist = 目标护甲(def)或魔抗(mr)[·削甲通道处理后]; pen_pct/flat_pen = 攻击者的对应穿透。
## 与 god file 原地公式逐字一致(原散在 3 处: _resolve_dmg 魔法9071/物理9074 · _atk_dmg 9093)。
static func effective_resist(base_resist: float, pen_pct: float, flat_pen: float) -> float:
	return base_resist * (1.0 - pen_pct) - flat_pen
