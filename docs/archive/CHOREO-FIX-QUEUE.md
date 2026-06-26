# 动画/演出 1:1 修复队列 (10h 自主run, 2026-06-08)

5-agent 逐技能审计(6轴: 施法位移/镜头/敌人击飞/节奏/出伤/VFX), PoC=唯一真值。一处一commit, 407测绿。

## ✅ 已修 (13 commit, 均 953测过+--import无错)
- 受击击退(全技能) / 施法tell(远程龟) / 血条拆HUD层 / 死亡 deathHop四段 / 龟派气波蓄力0.55s
- 龟派气波击飞错峰(波头到达) / ninjaBackstab停留1.1 / ghostPhantom撤180ms / lineLink墨线800ms
- turtleShieldBash 整段caster演出(chop+金弧+爆裂) / hunterShot 3箭 / aiPickSkills随从 / 三自创值纠正

## ✅ 倒计时 已港 (f8289562, 需F5): 30s计时条+超时转AI, 复用 _skill_chosen.emit(-1)→AI 安全路径, auto_play_debug不启用(不扰953测)。
## ⚠ 画布"不动": agent报"11场景aspect不一致"=误报#7 (项目默认EXPAND+战斗存还原=全程一致)。已做防御性修(退战斗断开size_changed连接, 6357aef4)。真·间歇bug需用户复现(哪场景/什么操作)。

## 🏁 动画/UI/逻辑 队列 — 余下"需用户"项: ① F5 验~20处手感+倒计时 ② 画布给复现步骤

## ✅✅ 8 个未实现装备 全部港完 (1:1 PoC + 单测, 1003 测过) — 真缺口已清零!
- thunder_shell(on_side_end电击真伤) · dragon_egg(on_turn_begin满3层喷火列) · mini_crystal A+B(on_side_end列/全敌魔光+结晶引爆)
- stun_baton + bamboo_leaf(**新建 post-cast 钩子** additive, 电棍电击眩晕+VFX/竹叶强袭回血+永久maxHp)
- lightning_staff(on_hit充能满100链式闪电≤4敌, +_castIsAoe标志) · incubator(4钩子进度+临时等级满100升上限3+5%base)
- **剩: VFX 缓项** (龙喷火横扫/水晶激光/雷杖锯齿闪电/竹叶强袭 的可见特效) — 逻辑/数值已1:1, 视觉需 F5 + 后补 VFX。

---
## (历史) 逻辑审计发现的真缺口 — 已全修
**8 个装备 equipment.json 有定义、商店可获得、曾 Godot 无 runtime 实现 = 买到不生效(已修)**:
- e_incubator(孵化器, normal) · e_stun_baton(电棍) · e_bamboo_leaf(竹叶) · e_lightning_staff(闪电杖)
- e_dragon_egg(龙蛋, unique, 注释明确"需飞行VFX"已知缓) · e_mini_crystal+_b(水晶球A/B) · e_thunder_shell(雷壳)
- 实现处=各自 PoC equipment.ts on_attach + BattleScene side-end/on-hit; 逐个港(每个需读PoC+on_side_end/on_hit+测)。
- ✅ **4/8 已港(均套现成钩子+单测+1:1, VFX缓)**:
  - e_thunder_shell 雷鸣贝壳(683c9c20, on_side_end电击真伤)
  - e_dragon_egg 龙蛋(5be5a587, on_turn_begin 满3层喷火列, 友+40/敌50魔+25灼)
  - e_mini_crystal A+B 迷你水晶球(4125559a, on_side_end 列/全敌魔光+迷你水晶层满3引爆14%, 共用 _mini_crystal_hit helper)
- ⚠ 顺带核实 crystallize mrDown **是实现的**(BattleScene.gd:3248-3258) = 羁绊agent误报#8。
- 🔴 **余 4/8 — 都需新基建(碰技能流程/统计/recalc, 风险高, 该配 F5 逐个做)**:
  - **e_stun_baton 电棍 + e_bamboo_leaf 竹叶**: 需加【post-cast 钩子】(技能结算后, BattleScene.gd:3716 _skill_post_impact 之后) + 渲染接入 + 单体/AOE目标判定。电棍=施法后电击(单体打该目标/AOE随机)30魔+眩1回, -1层(初3层); 竹叶=施法后强化攻击随机敌(35+20%maxHp魔), 回20%maxHp, 永久+100maxHp(消耗1充能)。
  - **e_incubator 孵化器**: 需 4 钩子(turn-begin+5 / 任意死亡 敌+10我+15 / 造伤×0.1 / 承伤×0.1) + 临时等级满100升(上限3, 每级+5%基础属性)→碰 StatsRecalc。
  - **e_lightning_staff 雷电法杖**: 需 _castIsAoe 标志接入(AOE充50%否则100%/...实为每段+25/AOE+12.5) + 每件独立充能数组 + 满100链式闪电(20魔跳≤4目标)。
- ⏳ 余 6 个都更复杂/需新基建(逐个评估):
  - e_stun_baton(电棍) / e_bamboo_leaf(竹叶): "**post-cast**"效果, 但 Godot 装备系统【无 post-cast 钩子】(只有 on_attach/on_hit/on_hit_as_target/on_turn_begin/on_side_end/on_death) → 需先加 post-cast 钩子基建。
  - e_incubator(孵化器): on-hit 累进度→越阈值给临时等级, 需进度基建。
  - e_lightning_staff(闪电杖): on-hit 充能→满100链式闪电跳≤4目标, 复杂。
  - e_mini_crystal+_b(水晶球): on_side_end 激光+结晶叠层→3层引爆, 复杂。
  - e_dragon_egg(龙蛋): on_turn_begin 3回合喷火, 代码注释明确"需飞行VFX"已知缓。
- **结论**: 简单套现成钩子的(thunder_shell)已港; 余 6 个需 post-cast 钩子/进度/充能/结晶 等基建+VFX, 是逐个的专注活(建议每个一条、配 F5 验可见效果)。
- (e_turtle_helmet/sword/shell 已实现 1:1, 非缺口)

## ✅ 逻辑层其余全 1:1 (已核实, 非误报)
- 羁绊 20/22 (运气 grant flag 两边都stub=1:1); 状态 28/33 (atkUp/crystalResonance/hunterPoison 都在, agent的"missing"是误报#8-10); 25装备1:1; 消耗品1:1。
- **e_carapace/e_blade per-segment on-hit = 对的**(keyed off effect.hits = PoC per-hit, 我刻意设计的, agent"HIGH risk"是误判)。

## ⚠ 已核实的 agent 误报 (本就1:1, 没改) — 6个
选龟入场动画+CTA(index.html:328/658) / 主队敌人技能(PoC主队不走aiPickSkills) / 商店财富折扣(apply_wealth_discount已1:1) / ghostStorm(段500ms+VFX都在) / hunterBarrage(走_play_barrage_bolts已发整排) / ninjaBomb时长(并行tween, awaited 800+400=1200ms已1:1, agent误当串行)

## ⏳ 队列(已记 PoC 出处+值, 待执行)
- **turtleShieldBash 缺整段 windup** [高]: 砍劈440ms+金弧VFX320ms+爆裂280ms+护盾dome/rim(PoC ts:681-730). Godot 只有击飞14段, 无 _skill_windup case. 需补编排.
- **ghostStorm 缺 windup case** [高]: 落到通用ranged → 丢2连500ms stagger + ghost-storm 8帧VFX(PoC ts:1457-1498). 需补 _skill_windup case.
- **ninjaBackstab 停留** 0.9s→1.1s (PoC ts:2018, gd:4198).
- **ghostPhantom** 删多加的 180ms windup(PoC 无此等待, gd:4110).
- **ninjaBomb** 总时长 ~1060→1200ms(fuse/settle, PoC ~1200).
- **hunter 箭** hunterShot/Barrage 现发1支引导箭, PoC 每命中发整排箭(salvo, ts:2725/4976+vfx). 需逐hit发箭.
- **gamblerBet 脉冲** 现 windup 脉冲1次, PoC 每段(7次)脉冲(ts:4744).
- **lineLink 收尾** 280ms→800ms(PoC ts:5310).
- **龟派气波 juggle stagger**: 现全列同时弹, PoC 按波头碰撞逐个弹(ts:1047-1055); + 缺开场2飘字(+暴/爆,+吸血/穿甲 ts:905-906); + 每段 shake(90,0.0025)+白闪140ms(ts:952-955).

## ⚠ 非bug(别误改)
- agent 多处报"floatNum vs segments结构 DIVERGE" = Godot分段系统, 出伤窗口已验1:1(颜色/字号/弹跳/堆叠/节奏全对齐, 见 feedback). 视觉等价, 不动.
- 镜头 shake 强度 PoC 0.008/0.012 vs Godot 8.0/12.0 = 单位换算(Phaser分数→Godot像素), 疑似一致, 先不动, 待F5.
- star/cyber 4技能(黑洞/虫洞/引力/能量炮): agent 报基本 1:1(cyberBeam KOF cut-in/zoom/juggle逐项对上). 仅 starWormhole portal VFX 存疑.
- basicSlam/basicBarrage: 1:1.

## 大盘审计结果 (3 UI/AI agent + 验证, 2026-06-08)

### ⚠ 铁律: agent 只读 .ts, PoC 视觉一半在 index.html CSS → 每条"缺失/自创"必须再核对 index.html 才能动手 (否则删掉忠实代码)
- **选龟入场动画+CTA脉冲**: agent 报"自创", **核对 index.html:328/658-694 = 真有(pocSelectCtaPulse + poc-sel-title-drop等)** → **1:1忠实, 别删!** (差点误删)

### 对局内 UI (10/13 MATCH, 0自创)
- ✓ 有: 技能框/动作面板(可交互)/伤害统计面板(4tab)/战斗日志/回合横幅/规则徽章/工具栏/装备席/币pill/羁绊chip/选龟框/详情卡
- ✗ 缺(需先验PoC是否真启用再补): **倒计时 turn timer bar**(BattleTopRow.ts:226 setTurnTimer 绿黄红+≤10s脉冲) · **回合 timeline**(5节点) · **取消选靶按钮**("←返回选技能")
### AI (人机)
- ✓ 放技能/选技能 ai_pick 1:1; ✓ 装装备 plan_ai_shop 1:1(**会装, 用户担心不成立**)
- ✗ **aiPickSkills 没移植** → 敌人永远[0,1,2], 不会5选3随机带技能 (pet-level.ts:60-89). 待港.
### 菜单
- 商店: 缺 财富synergy -25% 折扣. 图鉴: 详情技能可能read-only(待验是否PoC可选). 闯关: 100% 1:1. 选龟: 1:1(见上).
- **"画布有时不动" 根因**: 11场景没设 content_scale_aspect → battle cover-zoom 模式泄漏到下一场景. 修法待定(菜单FIT vs 现EXPAND, 别重引黑边).
