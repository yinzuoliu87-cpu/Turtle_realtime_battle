# 龟蛋改成「真单位」重构计划 (用户确认: 蛋=不行动的 fighter, 走正常战斗)

## 现状(错): _egg_attack_phase 假阶段
- `_wiped_side()`/`_side_has_alive_turtle()` 检测全灭 → `_egg_attack_phase(loser, terminal)`:
  spawn 一个 `egg_root` Node2D(emoji+手画血条), 循环 `egg_cur -= 胜方ATK` + 飘字 + 抖蛋。
- **蛋不是 fighter** → 不走伤害管线(防御/穿透/暴击/灼烧/吸血/装备联动全失效)、没真出手 = 用户报"什么技能没放就掉血"。
- `_isEgg` flag 已存在(回合循环跳过它不行动 / survivor 排除它) → 本就想做成"不行动单位", 没接完。

## 改法清单
1. **生成时机(关键)**: 战斗循环检测到某方真龟全灭 → **在 `_battle_ended`(left/right alive==0) 看到 0 存活【之前】立即 spawn 蛋 fighter** → 该方仍有 1 存活(蛋) → 战斗不结束、继续。
2. **蛋 fighter**: `{_isEgg:true, side:loser, alive:true, hp/maxHp:egg_hp[loser](带上路打剩的), atk:0, def/mr:?, skills:[], _passiveSkills:[], _slotKey:前排中央}` + append fighters[] + `_make_slot_view`(蛋立绘+血条) + `battle_stats.register`. 回合循环已跳 _isEgg(不出手)。
3. **挨打**: 胜方正常回合(技能/普攻)打蛋(唯一存活敌→targeting 自然选它), 走完整伤害管线 + 命中动画/飘字/on-hit链。
4. **胜负**: 蛋 hp→0 alive=false → 该方 0 存活 → 现有 `_battle_ended` 自然判败、本路结束。
5. **终极战场(×5增伤 + 每回合自损25%maxHP)**: 映射到蛋身上 — (a)受伤×5: 给蛋挂 markedDmg+400%(已有该 buff 机制) 或蛋极低 def; (b)自损: round-begin 给蛋扣 25%maxHP(DoT 或直接)。
6. **删除**: `_egg_attack_phase` + `egg_root`/手画血条/手动 egg_cur 循环。egg_hp 跨路累计改读/写蛋 fighter.hp。
7. **跨路累计**: 蛋每路重新 spawn, hp 用 `GameState.egg_hp[loser]`(上路打剩) 非满血; 本路结束把蛋剩血写回 egg_hp。

## 待用户拍板 (这几点定了我就重构)
- 蛋 **def/mr**? (0=纯血包 / 给点让技能-普攻差异体现)
- 蛋 **免斩杀/免控/免嘲讽**? (建议全免, 就是个挨打血包)
- 终极 **×5/自损** 用 buff 映射 还是保留专属处理?
- 蛋有没有**受击特效/被打碎动画**要求? (现仅抖+飘字)
