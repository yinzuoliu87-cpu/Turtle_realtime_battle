# Phaser → Godot 迁移路线图

**起点**: 2026-05-30
**预估总工期**: 12-16 周（3-4 月）
**目标**: feature parity 后停 Phaser，Godot 版本上 Google Play + App Store（海外优先）

---

## 决策固定（再次确认）

| 项 | 决定 |
|---|---|
| 引擎 | **Godot 4.3 Standard**（不要 .NET 版） |
| 语言 | **GDScript**（不用 C#） |
| 平台 | 海外优先（Google Play / App Store / Steam Web），**放弃微信小游戏** |
| 策略 | **大爆炸**（暂停 Phaser 新功能，全力 Godot），并行只保留严重 bug 修 |
| 仓库 | 沿用方案 A 结构，在 `games/turtle-battle-godot/` 起新工程 |

---

## 12 周分阶段

### W1（**本周**）：环境 + 学习
**你**：
- 装 Godot 4.3 Standard
- 跟 GDQuest 4 小时入门 + Brackeys 45 分钟 2D 教程
- GDScript 基础 1 小时
- 选做：拖一只龟图，做 idle 动画练手

**我**：
- ✅ 骨架（project.godot / .gitignore / Main.tscn / README）
- ✅ Phaser PoC 加 NOTICE.md 冻结牌
- ⏳ 写数据转换脚本（TS → JSON）

**checkpoint**：周末你 F5 跑出来 "斗龟场 v2" 启动画面。

---

### W2：数据层迁移（核心 IP 第一次落地）
**我**：
- 写 `scripts/ts2godot/extract-data.mjs`，从 PoC 的 `src/data/*.ts` **静态字段**抽到 JSON：
  - `data/pets.json`（28 龟，含 hp/atk/def/skill 槽位/被动 type 等可序列化字段）
  - `data/equipment.json`（100+ 装备，apply 逻辑暂不迁，留 type 字段）
  - `data/synergies.json`（10 羁绊配置）
  - `data/achievements.json`（50 成就）
  - `data/status.json`（13 状态）
  - `data/skill-icons.json`
- Godot 自动加载：写 `autoload/DataRegistry.gd` 单例，启动读 JSON 入内存
- 1 个 Codex 风格 Scene 验证：列表显示 28 龟 + 名字 + 属性 + 头像

**你**：
- 跟我对 1 次：「列表显示 28 龟」跑通 = 数据层活了

---

### W3：战斗算法骨架（damage / calc / roll）
**我**：
- 翻译 `src/engine/damage.ts` → `scripts/engine/damage.gd`
  - calcEffArmor / calcEffMr / calcDmgMult / applyRawDamage / rollCrit
- 翻译 `src/engine/fighter.ts` → `scripts/engine/fighter.gd`
  - createFighter（带稀有度缩放、等级缩放）
- 写单元测试：1 只小龟打 1 只小龟，伤害符合 JS 公式

**你**：
- 不用做事，看 commit 验收

---

### W4：1 场战斗能跑（最小可玩 MVP）
**我**：
- Scene：`scenes/Battle.tscn`，6 个 Slot Node2D，HP 条 UI
- 出手：基础 attack 走 dealPhysical，飘字 + 减血 + 死亡 fade
- 双方 AI 对打（参考 `_reference/turtle-battle-js/js/ai.js`）
- BGM 接入

**你**：
- F5 看一场战斗跑完
- ✅ 这是第一个"哦真的不一样" 的 milestone

---

### W5-W6：技能 handler 第一波（25 个签名技能）
**我**：
- 翻译 `src/engine/skill-handlers.ts` 前 25 个最常用 type：
  - physical / magic / heal / shield / dot / bleed / poison / burn 这类核心
- VFX 接入：Godot AnimationPlayer + GPUParticles2D
- 选龟 Scene（TeamSelect）骨架

---

### W7-W8：剩余技能 handler（70+ 个）+ 装备 onHit/onTurn
- 把 100+ 技能 type 全翻完
- equipment-runtime.ts onHit/onTurnBegin/onDeath hook 全过

---

### W9：羁绊 + 战斗规则 + 状态系统
- synergies.ts 10 羁绊 tier2/tier3 effect
- rules.ts 7 战斗规则
- DoT/HoT/buff/debuff 系统

---

### W10：主菜单 + 闯关 + 商店
- MainMenu / Dungeon / Shop / Reward 全做出来
- localStorage（Godot 走 `user://savegame.json`）

---

### W11：图鉴 + 成就 + 设置 + 战斗结算
- Codex（已有 W2 雏形，完善）
- 成就解锁动画
- 结算战利品弹出

---

### W12：打磨 + 第一次 Android 导出
- 转场 / 粒子 / 触控适配
- 字体（开源像素中文）
- **第一次 Android export，装到你手机看效果**
- 申请 Google Play Developer 账号（25 USD 一次性）

---

## 总结里程碑

| 时点 | 能干啥 | 心态 |
|---|---|---|
| W1 末 | 你看到 Godot 启动画面 | "OK 装好了" |
| W4 末 | 一场战斗能跑 | "卧槽真的不一样" |
| W8 末 | 全套技能装备能玩 | "feature parity 50%" |
| W12 末 | 装到手机上玩 | "可以拿出去给人看了" |
| ~M4-5 | 第一次提交 Google Play | "等审核" |
| ~M5-6 | Google Play 上架 | "海外正式发布" |

---

## 风险 + 应对

| 风险 | 应对 |
|---|---|
| 学习曲线超预期，你 W1 还没跑通教程 | 我等你，不催；如卡 3 天以上一起 debug |
| W3-W4 翻译出来的伤害公式不对 | 写单元测试 + 跟 Phaser 输出 diff 校验 |
| Skill handler 翻译工作量爆炸（100+ 个） | 工作量诚实是大头，没有捷径；考虑批量代换助手脚本 |
| 美术资源不兼容 Godot | PNG 直接 import 没问题；.aseprite 用 Godot Asset Library 的 aseprite plugin |
| 你中途想加新功能 | **要忍住**——加新功能等 W12 后；现在功能集对齐 Phaser v1.0 即可 |

---

## 现有 Phaser 资产能搬什么？

| 项 | 可移植度 | 备注 |
|---|---|---|
| **数据**（pets/equipment/synergies/achievements/status） | ✅ 100% | 自动转 JSON |
| **战斗算法**（damage/fighter/dot/stats-recalc） | ✅ 70% | 翻译 GDScript，公式不变 |
| **技能 handler**（100+ 个） | ✅ 70% | 算法翻译，VFX 重做 |
| **装备 runtime**（onHit/onTurn） | ✅ 70% | 同上 |
| **美术 PNG**（28 龟 + 100+ 装备图 + 技能图 + BGM） | ✅ 100% | 直接复用 |
| **Scene / UI**（BattleScene / TeamSelectScene 等 20+ 个） | ❌ 0% | 全 Godot 节点重做 |
| **DOM 浮层**（DetailPanel / BattleTopRow 等） | ❌ 0% | Godot Control 节点重做 |
| **VFX**（src/vfx/skills.ts） | ❌ 30% | 算法保留，渲染换 Godot AnimationPlayer + Particles |

---

## 我承诺给你的

1. **每个 milestone 给你眼验机会**（commit + 视频 / 截图）
2. **每周对一次进度**（避免 3 个月后才发现方向走偏）
3. **数据 + 算法层 100% 我做**（你不用动）
4. **Scene / UI 层我做骨架**（你可以学着自己改 layout）
5. **学不会 / 跟不上 / 后悔了，随时叫停**——12 周不是绑死你

---

**起点已搭好，等你 Godot 装上来。**
