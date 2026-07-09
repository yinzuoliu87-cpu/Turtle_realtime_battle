# Phase 4 — 全量回归结果（headless 逐龟单挑 sim）

> 验证 Phase 2 代码保真回补 17 项改动无运行时崩溃。自主 headless sim，无需人工。
> 复现：`REVIEW_TURTLE=<id> [REVIEW_SKILL=<idx>] Godot --headless res://scenes/RealtimeBattle3D.tscn --quit-after <N>`
> 判定：rc=0 且 stderr 无 `SCRIPT ERROR / Parse Error / null instance / Nonexistent / out of bounds / Invalid get|call|set`。
> （退出时的 `ObjectDB instances leaked` / `resources still in use` 是 Godot headless 正常清理噪声，非游戏错误。）

## 结果总览：**40/40 通过（0 崩溃）**

### 全 28 龟 默认轮转 sim（480 帧 ≈ 8s，各龟普攻+被动+默认技 idx1）
✅ basic stone bamboo angel ice ninja two_head ghost diamond fortune dice rainbow gambler hunter pirate
✅ candy bubble line lightning phoenix lava cyber crystal chest space hiding headless shell
→ **28/28 ok**

### 本轮 Phase 2 重改的 idx-2/3 技强制施放 sim（700 帧 ≈ 11.6s，`REVIEW_SKILL` 锁定该技·`_resolve_chosen_index` L6028 确认强制选中）
| 龟 | 技idx | 本campaign改动 | 结果 |
|---|---|---|---|
| diamond | 2 | 钻石滚球完整加速位移状态机 | ✅ |
| diamond | 3 | 钻石冲撞 | ✅ |
| crystal | 2 | 碎晶爆破 | ✅ |
| crystal | 3 | 水晶球 crystalBall（新接线+本体主动） | ✅ |
| pirate | 2 | 朗姆酒 HoT | ✅ |
| pirate | 3 | 海盗船 pirateShipPassive（新接线+撞击+霰弹） | ✅ |
| ice | 3 | 团队护盾 commonTeamShield（新接线） | ✅ |
| angel | 2 | 平等 angelEquality（重写·A级门控真伤+吸血+光柱） | ✅ |
| bubble | 1 | 泡泡盾（4s timed+三触发爆裂） | ✅ |
| fortune | 3 | 招财进宝升星精确 delta | ✅ |
| phoenix | 2 | 烫伤破盾顺序 | ✅ |
| chest | 3 | 财宝炮击（+15件专属战利品池 on-hit 钩子） | ✅ |
→ **12/12 ok**

## 结论
- 全 28 龟 + 12 项重改技 headless 运行时零崩溃 → 17 轮 Phase 2 改动运行时安全。
- `--headless --import` rc=0（每轮已验）→ 全工程解析零报错。

## 仍需人工 F5（sim 只验"不崩"，验不了"对不对/好不好看"）
- 手感/数值/平衡：钻石滚球速度、宝箱星辉绕护甲局限、泡泡盾多重盾 break、糖果自愈数值（封板未给·需用户定）。
- 视觉：所有 VFX 占位（`_skill_ring`/`_bolt_line`）→ Phase 3 AI 美术。
- 局外 UI：糖果罐显示/打碎/领奖弹窗、临时等级器使用 + 接入战斗 +1 级。
- 全流程：选龟→3选1→战斗 端到端（本 sim 走 REVIEW 直连战斗场，未过菜单流）。
