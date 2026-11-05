class_name VfxTiers
extends RefCounted
## 特效 / 打击感重要度 1~10(2026-11-04 · 方案书 docs/plans/20261104b-特效对标商业做法.md P2)。
## 学的是 Riot:「策划给每个技能 1~10 的视觉重要度, 特效按分做」「伤害越高越大、越亮、越抓眼」「什么都重要就什么都不重要」。
## ★一份事实源: 谁要按重要度分档(放技能声音量 / 命中火花大小 / 以后的特效强度)都来这里取, 不许各处自己按伤害绝对值判。
##   档位来源 = 技能龟能消耗(SkillEnergy 表头写明「消耗 ∝ 技能强度: 轻盾 / 治 / buff ~70 · 普通 ~95 · 全体 / 多段 ~120-140 · 大招 ~150-170」)。
##   个别技能要手调就写进 OVERRIDE 并写理由。门禁 verify_vfx_tiers。

const MINION_BASIC := 1
const BASIC := 2
const LIGHT := 4
const NORMAL := 5
const STRONG := 6
const ULTIMATE := 8

## stype → 档位(手调; 写理由)
const OVERRIDE := {}


## 一个主动技的重要度。cost = 该龟该技实际的龟能消耗(_skill_cost)。
static func of_skill(stype: String, cost: float) -> int:
	if OVERRIDE.has(stype):
		return int(OVERRIDE[stype])
	if cost >= 140.0:
		return ULTIMATE
	if cost >= 115.0:
		return STRONG
	if cost >= 85.0:
		return NORMAL
	return LIGHT


## 放技能声音量(乘在 cast_<龟> 上): 大招级原音量, 强技略轻, 普通 / 轻技再轻 —— 大事件之间也要分出主次。
static func cast_sfx_gain(tier: int) -> float:
	if tier >= ULTIMATE:
		return 1.0
	if tier >= STRONG:
		return 0.85
	return 0.7


## 命中火花(快环 + 亮星)大小倍数: 普攻那一档缩小 —— 一局里绝大多数命中是普攻, 不能和技能命中一样抢眼。
static func spark_scale(tier: int) -> float:
	return 0.75 if tier <= BASIC else 1.0
