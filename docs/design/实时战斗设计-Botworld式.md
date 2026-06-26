# 斗龟场 实时版 — 战斗设计（Botworld 式实时自走棋）

> 2026-06-27 立项。从回合制版 fork，**局外层全复用**，**战斗从回合制重做成实时**。本文是战斗设计 + 改造路线图。

## 一、Botworld 战斗模型（参照原型）
**实时「定位型自走棋」**（比 TFT 动作化）：
1. **战前布置**：双方同时把单位放进竞技场（位置），看不到对方 → 站位是核心。
2. **战斗中全自动**：单位自己跑（**索敌=最近敌人**，近战追/远程风筝/坦克顶前）+ 到射程按攻速自动普攻。**玩家不直接控单位移动**。
3. **玩家在战斗中 = 主动放技能/武器**：自己决定**何时放 + 放哪**（瞄准落点），技能要**充能/读条**，还能引敌进地图陷阱。
4. **7 角色决定 AI 行为**：追击/闪避/格斗/坦克/狙击/泼溅/辅助。
5. **胜负 = 消灭对方全队**。

### Botworld bot 技能参考（设计龟技能的模板）
每 bot = 普攻 + 1 特色技能；按角色：
- 坦克: 反伤回血/推+眩晕/正面减伤/控场连招/极限吸伤
- 泼溅(AoE): 多目标/击退/自爆溅射/机动AoE核/眩晕
- 狙击(远程): 稳定DPS/玻璃炮(要敌静止)/高爆单发
- 追击(冲脸): 最高伤脆皮/最高DPS免控突进/高血抛敌
- 闪避(风筝): 贴脸AoE/近距全AoE/强控/隐身
- 格斗: 1v1眩晕锁/超高伤需配合/劫持敌方单位
- 辅助: 治疗+buff/伤害buff+眩晕/RNG技能

## 二、龟实时战斗设计（映射到本游戏）
- **入场站位** = 复用局外 **6 格定位网格**（前3后3）→ 实时战场初始坐标。
- **自动移动+索敌**：龟实时移动，索敌最近敌人；**龟类型→Botworld 角色**决定走位（物理近战=追击/守护=坦克顶前/法术=狙击拉距离/泼溅=AoE躲后/治疗=辅助）。
- **自动普攻**：到射程按**攻速 CD**自动打（启用 pets.json 废弃的 `cd` 字段当攻击/技能间隔）。
- **龟能改实时**：`_energy += regen×delta` 每秒回；技能 `_energy>=energyCost` → **够了自动放 或 玩家点放+瞄落点**（保留玩家主动性 = Botworld 的核心乐趣）。
- **胜负** = 消灭对方全队/凿穿龟蛋。

## 三、引擎事实（agent 核实, 行号针对本仓库 BattleScene.gd 17160行）
**逻辑层白捡复用**（已同步纯逻辑/与回合无关）:
- `SkillHandlers.execute`(skill_handlers.gd:35, ~120 type 分支, **0 await**, 输入fighter dict输出effects) — "触发后算什么"完全复用
- `Damage.*`(calc_damage/apply_raw_damage/暴击/护甲) · `Buffs/Dot/StatsRecalc/Synergies/Equipment`(状态机+钩子, 改按秒衰减)
- fighter dict(fighter.gd:163, 普通Dict, **已有 `_energy/_maxEnergy/cdLeft/_position/_slotKey`** 天生适配实时)
- 数据 pets.json(28龟 skillPool/`energyCost`蓝耗/`cd:0`正好启用当实时CD/maxEnergy/tags)
- 目标选择 `_pick_enemy_target/_alive_enemies/SlotHelpers` · VFX `_play_*` + `_enqueue_display` 队列骨架

**必须重写**(回合制驱动):
- `_battle_loop`(1725)+`_run_side_turn`(1921): `while turn: for side: await` 281个串行await → **`_process(delta)` 全局tick**, 删 side整队/`turn`计数/`TURN_DELAY_MS`
- `_take_turn`(6665) await链(announce→windup→execute→VFX→post→death→display-drained 串行阻塞~2-3s/动作) → **fire-and-forget并行**, 删 `_await_display_drained` 对推进的阻塞(10684)
- 龟能"每侧回合+40%" → 每秒回; `ai_pick` "回合选一技能" → 实时轮询能放就放
- `turn` 死绑(环境事件3/6/9/12·商店%4·回能≥2·决胜局>30·buff持续N回合·CD每round) → 全改**计时器/秒**
- `_check_end`(8245) 回合边界轮询 → 每tick查
- **移动+索敌系统从零做**(回合制是6格站桩, 纯新增)

**最难拆**: ①await串行链解耦(多龟同帧出手血条/飘字race指数放大, memory记的塌帧问题在并发下放大) ②`_side_end`(4112) DoT对敌/HoT本侧/复活/召唤级联钩子绑"一侧回合末" → 改时间tick+事件 ③`turn`计数全局死绑 ④移动索敌从零

## 四、改造路线图（分阶段）
- **阶段0 · 实时tick最小骨架**(起点): BattleScene 加 `_tick_combat(delta)`(挂已存在的`_process`10132): 每龟 `_atkCdLeft-=delta` 到点→选最近敌(复用`_pick_enemy_target`)→够龟能(`_can_afford_energy`6630已存在)就 `execute`(**直接复用**)→异步播VFX(`_enqueue_display`复用)→重置CD; 龟能 `_energy+=regen×delta`; 停用`_battle_loop`的while/for/await; `_check_end`改每帧查。**目标: 龟静止站位但实时自动普攻+够能量自动放技能跑起来**(逻辑三大件白捡)
- **阶段1 · 移动+索敌**: 6格静态 → 实时坐标移动, 龟类型→角色决定追/风筝/顶前/拉距离; 射程内才攻击
- **阶段2 · 玩家放技能**: 龟能满→玩家点放+瞄落点(AoE) (保留Botworld主动性); 默认够了自动放
- **阶段3 · 回合绑定系统迁移**: side-end DoT/HoT/召唤 → 时间tick衰减+事件; buff "N回合"→ "N秒"; 决胜局怒气按秒; 环境事件按秒
- **阶段4 · 28龟+59装备效果按实时重设计**: 每龟分配Botworld角色 + 技能重设计(普攻+特色技能); 装备效果按实时触发
- **阶段5 · VFX/动画实时化**: 攻击/技能视觉并行不阻塞; 多龟同帧出手的显示race治理

**原则**: 阶段0先用复用的三大件(execute/damage/display)把"实时自动战斗"跑通验证手感, 再逐步加移动/玩家技能/迁移回合系统/重设计效果。
