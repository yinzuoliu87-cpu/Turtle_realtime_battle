# 双路龟蛋 PvP 架构设计

> ## ⛔ 2026-07-19 核实：本文的**前提已整个不成立**
> 通篇建立在「回合制 → 输入率极低 → 不需要实时同步」之上，而现行是**实时自动战斗**。
> 协议 `TURN_BEGIN` / `ACTION{skillIdx}`、「某路全灭 → 3 回合攻蛋」（实时版是团灭后 **10 秒窗口**）均不适用；
> 引用的 `skill_handlers.gd` / `BattleScene.gd` 都已删除。
> **现行 PvP 形态 = 异步 ghost 快照 + bot 兜底**（`scripts/engine/backend.gd` 的 `find_opponent`/`make_bot`/`bracket_for_battles` + `data/ghost_seed.json` 146 支种子队），不是本文讨论的房主权威 lockstep。


> 用户 2026-06-12: 双路龟蛋会用在 PvP, 先想清楚怎么搞再继续接战斗 (别把单机用完即弃的逻辑硬塞进去).

## 为什么 PvP 在本作很可行
- **回合制** → 输入率极低 → 对延迟极不敏感 → 不需要实时同步/预测回滚/插值. 一回合传一次意图即可.
- 战斗逻辑已基本在 `scripts/engine/*`(damage/skill_handlers/buffs/dot/stats_recalc/...) 与 `BattleScene`(编排+动画) **分离** → 结算可无头跑、产出"事件流"供两端渲染. 这是 PvP/回放/服务器权威的基础.

## 权威模型: 服务器/房主【权威 + 事件驱动】(不走确定性 lockstep)
- **选它的理由**: Godot 浮点运算 / Dictionary 迭代序 跨端难保证逐位一致 → 确定性 lockstep 易 desync; 回合制带宽极小, 直接传"回合结算事件"既便宜又稳; 且权威结算天然防一类作弊(客户端改内存不改结果).
- **起步**: 房主客户端当权威 (P2P, 一方跑 sim), 另一端纯渲染. **后期**: 同一份 `engine/` 逻辑搬到专用服务器无头跑, 客户端不变.
- **不选 lockstep**: 否则要把所有 float/迭代/RNG 做成跨端逐位确定, 成本高、脆.

## 对局流程 (PvP)
1. **匹配/房间** → 双方各带 6 龟 + 备战席结算后的身上装备 入场.
2. **分路暗选 (commit-reveal 防偷看)**: 各自把 6 龟分上/下路 → 本地算 `commitment = sha256(规范化分路 + salt)` 先交换; 双方都提交后再 `reveal(分路, salt)`; 各自校验对方 reveal 的 hash == 之前 commitment → 杜绝"看到对方分路再改自己". 揭晓写入双方 `lane_assign` / `enemy_lane_assign`.
3. **龟蛋 HP** 各按自己 3 龟均等级初始化 (权威算后下发).
4. **上路战斗**(回合制): 权威广播 `TURN_BEGIN(side, 可动龟)` → 该 side 控制方本地选(选龟 picker + 技能 + 目标) → 发 `ACTION` → 权威校验合法性(可动/技能解锁/龟能够付/目标合法) → 结算 → 广播 `RESULT` 事件序列(damage/heal/death/buff/...) → 两端按事件演出. AI side 由权威跑 AI.
5. 某路全灭 → 3 回合攻蛋(权威累计 `egg_hp` 下发) → 下路同理 → 待命回复 → 终极战场(3 情况) → 败蛋 ×5/自损. 全程**权威算 state, 客户端只渲染**.
6. **断线重连**: 权威持 match snapshot(lane_assign/egg_hp/各龟 state/turn/current_lane/seed), 重连下发快照续战.

## 回合协议
- `TURN_BEGIN { side, actableIds[] }`
- 控制方 → `ACTION { actorId, skillIdx, targetIds[] }`  (非法/超时 → 权威用现有"超时自动出手"AI 兜底)
- 权威 → `RESULT { events: [ {type, ...} ...] }`  两端顺序演出
- 关键: 客户端**只发意图、只渲染**; 命中/暴击/伤害数都由权威定.

## 落地到代码的解耦 (按依赖排序, 渐进)
- **P0 (本次, 纯逻辑可测、不碰网络)**:
  - 分路暗选 `commit-reveal` 原语 (`phase2_pvp.gd`).
  - `side_controllers` 配置 (left/right 各是 local/ai/remote) + `battle_seed` + match 快照序列化 (`GameState`).
  - 回合动作 `ACTION` 的构造/解析 (`make_action` / 读字段).
- **P1**: BattleScene 输入来源抽象 —— 现 `_is_player_controlled(f)` 二分 → `controller_for(side)` 三态(local→picker / ai→现有AI / remote→等权威事件).
- **P2**: 结算产出**事件流** + 客户端事件渲染 (渐进重构: 让 damage/skill apply 先 emit 事件, BattleScene 消费). 同时把散落的 `randi/randf/randomize` 收口到单一 `battle_seed` RNG(可复现/回放/校验).
- **P3**: 接网络层 (房主权威 P2P 用 Godot ENet `MultiplayerAPI`, 或后端) + 匹配 + 重连.

## 反作弊
- 权威结算: 客户端改内存不改结果.
- 分路 commit-reveal: 防偷看对方分路.
- 动作合法性权威校验: 冷却/龟能/技能解锁/目标合法.

## 与单机的关系
- 单机(打 AI) = PvP 的退化: `side_controllers = {left:local, right:ai}`, 权威=本机.
- 所以**先把双路单机按"权威+事件"的形状搭**, PvP 只是把 right 从 ai 换成 remote、权威从本机换成房主/服务器. 别写"单机专用、PvP 要推翻"的逻辑.
