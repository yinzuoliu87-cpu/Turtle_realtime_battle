# Godot 移植完整性盘点 (6-agent 审 2026-05-31) — 待补 backlog

> ## ⚠ 2026-07-19 核实：本文把 "side-based turn 引擎" 列为已做项，但 `docs/实时版路线图.md` 已判定它作废。
> 实时版无回合概念。阅读本文时请以 `docs/design/实时版-系统机制权威.md` 为准。


> 全量审 Godot vs PoC。**已做**: side-based turn 引擎 / damage 公式+受伤端减伤链 / buff / dot / 选目标 / 羁绊 / C组5系统(双头·熔岩·星能·赛博机甲·缩头召唤) / 凤凰复活 / 8件基础装备 / 飘字数值字号(100%同 PoC)。
> **下面是 6 个 agent 查出的待补清单, 按价值排序。1:1 PoC 不自创。**

---

## ⭐ P0 — 28龟技能/被动 (最大 gameplay 缺口, 约半数龟核心能力不工作)

### A. 落 fallback 的可主动施放技能 (被当通用 physical, 效果全错)
**默认 loadout 内 (一进场就用错)**: turtleShieldBash(basic) / bambooHeal(bamboo) / angelBless(angel) / bubbleShield·bubbleBind(bubble) / chestCount(chest) / crystalBurst(crystal) / diceAllIn(dice) / fortuneStrike·fortuneDice·fortuneAllIn(fortune) / gamblerBet(gambler) / ghostPhantom·ghostStorm(ghost) / hunterShot·hunterStealth(hunter) / lineLink·lineFinish(line) / phoenixShield(phoenix) / shellAbsorb·shellCopy(shell) / soulReap(headless)
**非默认池**: basicBarrage·basicChiWave·basicSlam / angelSmite / commonTeamShield(ice) / bubbleBurst·bubbleHeal / diceFlashStrike / fortuneBuyEquip·fortuneGainCoins / ghostPhase / phoenixPurify / rainbowReflect / stoneTaunt
> ⚠️ 无 atkScale 的(angelSmite/fortuneGainCoins/shellAbsorb/shellCopy/stoneTaunt/rainbowReflect/commonTeamShield/fortuneBuyEquip/diceFlashStrike)会被 fallback 强行打 1.0×ATK 物理 — 凭空伤害, 错误。

### B. 完全没做的 passive (14, 无任何代码引用)
- **登场期 AoE (核心定位缺失)**: frostAura(ice登场冰寒全敌6t+克熔岩/凤凰) / ghostCurse(ghost登场诅咒全敌3t)
- **开局/逐击增伤 (核心输出缺失)**: ninjaInstinct(开局+30%暴/+20%暴伤/+8穿) / judgement(angel每段命中+11%当前HP魔法) / basicTurtle(对稀有度增伤)
- **各龟特色机制**: stoneWall(受伤反弹; 岩层✅反伤❌) / bubbleStore(受伤存泡泡盾) / hunterKill(击杀窃取) / candySteal(偷窃) / undeadRage(无头亡灵狂暴 lifesteal+atkPerLost) / bambooCharge(隔回合蓄力) / inkMark(墨记) / gamblerBlood·gamblerMultiHit·rainbowPrism·pirateBarrage / auraAwaken(龟壳觉醒储能) / chestTreasure
- **经济类(依赖经济系统, 后做)**: fortuneGold

PoC 锚: skill-handlers.ts (if-链, 所有 type 有专属 handler) / passive-triggers.ts / BattleScene 登场.

---

## P1 — 引擎级系统 (用户点名, contained)
- **规则之日 ruleModifiers** ❌: data/battle-rules.json 已加载零消费。需 Rules helper (magicMult/burnMult/shieldMult/healMult/globalCritBonus) + applyRuleStart(狂暴/雷暴/装备日) + applyRulePerTurn(下雨天) + skill_handlers ~27 处乘 magicMult + 规则选择/徽章。PoC: rule-effects.ts。
- **伤害统计 battleStats** ❌: 整套 tracker (4维×4dmgType, 按 fighter 引用 key) + 各点埋 record(damage/kill/heal/shield) + 结算 DmgStatsPanel。PoC: systems/battle-stats.ts + DmgStatsPanel.ts。

---

## P2 — 装备 (装备通道缺)
- **6 件部分**(快): e_pearl 火球 / e_star 溢出转盾 / e_urchin 反伤 / e_jelly 25%眩晕 / e_octo 后排+20% / e_ghost 闪避给盾
- **14 件复杂**(需 side-end/施法后/死亡 装备通道): conch/dragon_egg/mini_crystal(_b)/thunder_shell/hourglass/dumbbell/fpga/amplifier/candle/revolver/laser_blade/doll/dart/wave
- **消耗品** 8 c_* + 2 special(口哨/糖果罐) ❌ 全无 + 无消耗品系统
- **PoC-only 6** (用户授权): incubator/stun_baton/bamboo_leaf/lightning_staff/turtle_helmet/turtle_sword + turtle_shell 属性
- LOOT_POOL: Godot 14 白名单 vs PoC 全 normal+unique(~33)

---

## P3 — 游戏模式
- ❌ 指定boss(boss-pick)+倍率 / 随机boss / 测试模式(6假人) / 快速单体调试 (后三是 DEV 功能, contained)
- ⚠️ 野生 AI 经济(攒币/AI开店/玩家商店/规则) / 深海关间(奖励选择/抉择事件/装备席) / 战斗内玩家操作层(ActionPanel 选技能+目标, 现全AI)
- ❌ 主菜单分层 + 设置/成就/战绩/教程

---

## P4 — UI/渲染 (大 UI 层)
- **图鉴 Codex** ❌: 仅龟列表雏形; 缺 装备/羁绊/状态/规则 4 tab + 技能 drill-down + 富文本详情
- **描述模板器** ❌: skill-text.ts ({N:ATK*1.3} 展开 + val-* 上色 + 30+关键词着色) 零移植, brief 当纯文本截断
- **状态徽章** ❌: 战斗中角色身上无 DoT/CC/buff 图标 (看不到挂了什么 debuff)
- **字体** ⚠️: m6x11 无 CJK/emoji, 中文靠系统回退未捆绑 → 跨平台(海外/Steam Linux/Mac)豆腐块风险, 需补 CJK+emoji 字体进 fallbacks
- **日志** ⚠️: 整行一色 vs PoC 9类内联着色 + 暴击橙 + DoT 逐跳行

---

## 实施顺序 (本批)
P0 被动(登场AoE+增击) → P0 fallback技能(默认loadout优先) → P1 规则+统计 → P2 装备6部分 → P3 test/solo/boss → P4 字体捆绑(快)+状态徽章。Codex全版+描述模板器+野生经济+ActionPanel = 大UI/系统层, 单独大批次。
