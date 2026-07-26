# 实装改动清单 · 批A (石头/钻石/骰子/双头) — 预分析产出 2026-07-08

> 并行分析员产出的精确改动清单(主控落地前须逐条对代码+设计复核, 非盲抄). 每龟: 3选1最终结构 + 关键新函数 + 接线 + 阻塞 + 歧义.

## ★★ 跨龟总阻塞(最先建) ★★
- **限时护盾原语**: `_grant_shield`(L7491)当前**永久盾**(无时长). 设计全局"通用护盾=4秒"影响 stone团队盾/diamond技一/凤凰熔岩盾/two_head锤击盾/雷盾等**几乎所有盾龟**.
  - **且: 我已提交的 雷盾(3A)/熔岩盾(3.5A)/凤凰盾 现在都是永久盾, 非设计的4~5秒** ← 真分歧, 建此原语时一并修正.
  - 改法: `_grant_shield(u, amt, dur:=0.0)`; dur>0 → 记 `shield_until`; 主tick到期清; dur=0=永久特例(嘲讽永久盾/shell). 边缘: 多源盾共存时single shield_until会整体过期(接受简化或按需精细).
- **位移状态机(渐进冲刺)**: diamond滚球(龙龟Q)/忍者冲击/薇恩翻滚/骰子(现用_dash_to瞬移近似OK) — 唯diamond滚球需真·加速滚动+沿途撞击+CC免疫态, 建议跨龟统一建, 不单造.
- **"加成放大"折入recalc**: diamond基础被动"全队甲魔抗加成×1.5"+技三"自身×2" 需改 _buff/_recalc 管线; 当前spawn flat+25%近似.

## 石头龟(stone) — 3选1=[打击普攻 | 岩石护盾 | 岩石之躯 | 嘲讽]; 基础被动=坚壁反弹
- 普攻打击 ✅(STATS L83 0.7A+1.5DEF+0.8MR已对).
- **技一 岩石护盾** `stoneRockShield` 100龟能 🆕合并(现岩石护甲type=shield + 磐石type=heal 两条→合1): 全队盾`0.2A+5%maxHp`(4秒·待限时盾) + 自身def/mr各+20%(pct,5秒). `_sk_stone_rock_shield`: for _allies_of→_grant_shield(o,atk*0.2+maxHp*0.05,4.0); _buff(u,def,0.2,true,5.0); _buff(u,mr,0.2,true,5.0).
- **技二 岩石之躯** `rockShockwave` 80龟能 🆕: 被动(选此才有)每受伤+1岩层(上限30·每层+1%减伤+2%体型) + 主动横排带(perp投影法·仿_eq_water_wave L8963)对前方带内敌`(0.5DEF+0.5MR)×(1+0.04×层)物理`+`1%×层`概率眩晕1.5s+击飞.
- **技三 嘲讽** `stoneTaunt` 120龟能(现pets70→改120) 🆕: 500码内敌4秒硬嘲讽(_taunt L7599现成) + 自身1A永久盾 + 自身0.5×护甲%减伤4秒 + 3.5s后砸地(K'Sante Q3式·400码敌1A魔法+击飞2s·_pending_shots延时) + 砸完才充能(casting_until锁能).
- 接线: _IMPL/match/SkillEnergy 增 stoneRockShield/rockShockwave/stoneTaunt; _SELF_CAST增stoneRockShield(stoneTaunt已在); spawn增rockShockwave岩层init; 删死函数_sk_stone_armor(L6245).
- **歧义(待用户)**: ①基础被动"每2.5s永久涨甲"(L7952)新设计没提→删涨甲只留反弹? (我倾向删,岩层归技二) ②砸地击飞2s靠vy_mult+F5 ③横排带宽暂halfwidth90.

## 钻石龟(diamond) — 3选1=[钻石切割普攻 | 坚不可摧 | 钻石滚球 | 钻石冲撞]; 基础被动=钻石结构
- 普攻钻石切割 ✅(STATS L90). 基础被动: 自身每段-18%✅(L5241); "全队+50%甲抗加成"现被简化成spawn flat+25%(L7868)=需recalc折入才忠实(见总阻塞).
- **技一 坚不可摧** `diamondFortify` 70龟能 🔧: 现`_sk_diamond_unbreak`L6391给+20%pct+永久盾→改: 20%maxHp盾(4秒·待限时盾) + def/mr各+20%×ATK(flat,5秒): `_buff(u,def,atk*0.2,false,5.0)`.
- **技二 钻石滚球** `diamondPowerball` 100龟能 🆕阻塞: 龙龟Q(蜷球0→满速4s加速滚向最近敌·CC免疫·撞击点120码AOE伤害/控按移速插值[0速0.1DEF+0.1MR+2%maxHp→满速1.0+1.0+20%]+击飞1s&眩晕插值; 被动100码内无敌免费滚). **需位移状态机**(见总阻塞).
- **技三 钻石冲撞** `diamondSmash` 80龟能 🆕: 主动`100%DEF+100%MR+10%ATK物理+9层流血`(_apply_dot_stacks bleed 9现成); 被动(选此才有)强化钻石结构(自身+100%+受击再-20%甲-10%魔抗减伤). 现役`diamondCollide`(L6201)是另一技非此, 删.
- 接线: _IMPL/match/SkillEnergy 增diamondPowerball/diamondSmash, 删diamondCollide; spawn修基础被动+增diamondSmash强化分支.
- **歧义(待用户)**: ①**坚不可摧龟能 SkillEnergy=70 vs pets.json=50 不一致→统一到? (建议70)** ②基础被动全队+50%做真recalc还是留flat近似 ③滚球免费滚vs主动滚龟能门控互斥.

## 骰子龟(dice) — 3选1=[骰子攻击普攻 | 命运骰子 | 孤注一掷 | 稳定骰子]; 被动=赌徒之血✅. **无阻塞新系统**
- **远程→近战翻转(必改)**: STATS L56 `[false,145,0.6,400]`→`[true,145,0.6,70]`; BASIC_ATK L92 `{phys:0.9,critflat:55,hits:3}`→`{phys:0.9,critflat:60,hits:1}`(6000%暴击flat·单段·暴击管线现成双吃).
- 技一 命运骰子 `diceFate`✅微调: L7470 `crit_fate_until=_t+5.0`→`+999.0`(持续到下次技能重掷).
- **技二 孤注一掷** `diceAllIn` 🔧全体→前方120°/300码镰刀扇形斩(dir.dot判定·仿_phoenix_flame_cone)+30%吸血; 从_SELF_CAST删diceAllIn.
- **技三 稳定骰子** `diceFlashStrike` ~120龟能 🆕: 掷骰1-6→(4+点数)次短冲刺(刀妹Q·_dash_to现成)每次朝最近/残血敌0.9A物理吃暴击·全灭提前结束; 打包被动"真正的赌徒"(选此→spawn双抗全转等量护穿·仿lava gate).
- 接线: match/IMPL/SkillEnergy增diceFlashStrike; 删死条目diceAttack(L6203/5998/skill_energy L30).
- **歧义**: ①稳定骰子每段是否-10%递减(pets有falloffPct:10, 设计没提→按无递减) ②多刺是否分帧铺开(视觉).

## 双头龟(two_head) — ★28龟最重·整套换形架构推翻重建★
- 现代码=旧"选套1/2/3+切换即技能"模型, 与新设计"双生自动切形态+3选1各带形态变体"**根本不同**, 需重写.
- 3选1=[普攻(形态变体:远程灵能弹1.2A/近战挥砍0.9A) | 灵能冲击/锤击`twoHeadPsiStrike` | 精神干扰/吸收`twoHeadMindBlast` | 融合`twoHeadFusion`(被动锁形态+坚韧+主动魔法波)]; 被动=双生(远程起手+每技后自动切形态+位移+切换攻击补正).
- **远程起手改**: STATS L55 `[true,145,0.85,70]`→`[false,145,0.85,400]`; 普攻按形态运行时覆盖(仿lava L2665).
- **核心新增 `_two_head_after_cast`**(技一二末尾调,融合不调): 切形态+属性互换(_two_head_apply_melee L6673现成)+切远程(远离350+1.4A物理+破甲25%4s)/切近战(_dash_to+0.6A魔法+1.1A盾).
- 坚韧被动 gate: L5339 加 `and u.get("two_fused",false)`(只融合才有).
- 接线大改: 删twoHeadSwitch/twoHeadFear(错映射headless)/twoHeadMagicWave独立; 加twoHeadPsiStrike/twoHeadMindBlast/twoHeadFusion; pets.json结构性重构(灵能冲击type=physical会被排除轮转!必改active type); 退役_sk_two_head旧函数.
- **歧义**: ①融合态用哪种普攻 ②4秒盾(待限时盾原语) ③切远程350位移撞墙(已ARENA clamp,F5看) ④pets.json灵能冲击type必须改.
- **建议**: 单独commit批次 + F5验切形态节奏/位移手感.

## 落地顺序建议
1. 先建**限时护盾原语**(修正已提交盾 + 解锁多龟) — 待用户点头
2. 骰子(无阻塞·中等) → 石头(现成拼·缺美术) → 钻石(技一二三, 滚球阻塞待位移系统) → 双头(最重·单独批)
3. 用户须先拍: 石头坚壁vs岩层 / 钻石坚不可摧龟能70vs50
