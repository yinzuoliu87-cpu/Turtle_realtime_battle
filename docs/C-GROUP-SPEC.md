# C 组系统移植规格 (5 龟状态机) — agent 审 PoC 提取, Godot 实现依据

> ## ⚠ 2026-07-19 核实：本文所指的中心扣血点 `Damage.apply_raw_damage` 已非现行路径。
> 实时版走 `RealtimeBattle3DScene.gd` 的 `_apply_damage_from`（普攻/技能主线）与 `_apply_damage`（DoT/真伤），两条各自独立扣盾扣血。


> 2026-05-31 6-agent 审 PoC 后整理。权威源 = `../turtle-battle-poc/src/`（skill-handlers.ts / pets.ts / BattleScene.ts / passive-triggers.ts / damage.ts），JS 参照 `../../_reference/turtle-battle-js/js/`。
> 数值锚见各节。所有"变身/换形"系列改 `base*` 再同步当前值，**recalc 不能抹掉**；多在 `Damage.apply_raw_damage` 中心扣血点挂累积。

---

## 1. two_head 双头龟「换形」(B级, hp415/atk50/def11/mr12/crit0.25, passive `twoHeadDual`)

**形态**: `melee` / `ranged`（默认 ranged）。主动技 `twoHeadSwitch` 触发，无计数。各换形技 cd4。

**字段**: `_twoHeadForm`、`_formHpGain/_formDefGain/_formMrGain/_formAtkLoss`（近战增量缓存）、`_rangedSkills`（远程技能备份）。

**切近战**（scale 从 passive 读，别硬编码）: maxHp+=round(atk×1.5)（hp 按比例 `hp×newMax/oldMax`）; baseDef+=round(atk×0.25); baseMr+=round(atk×0.25); baseAtk-=round(atk×0.3); shield+=round(atk×1.1)。换技能集=meleeSkills 按 `_equippedIdxs` 配对（滤 passiveSkill）, 备份 `_rangedSkills`, 换形技 cdLeft=4。switch-attack: target 1.2×atk 物理。
**切远程**: 用缓存增量减回（hp `min(maxHp, round(hp×newMax/oldMax))`）, 清缓存, 恢复 `_rangedSkills`, 换形技 cdLeft=4。switch-attack: 1.4×atk 物理 + `defDown`{value25,dur5}。
每次切换结尾调 `applyShiftSynergy`（羁绊, 未实装则 stub）。

**技能数值**:
- 魔法波 `twoHeadMagicWave`(已移植): 4段 atkScale0.4, 偶段物理/奇段真伤。
- 灵能冲击 `physical`(通用): cd4 AOE atkScale0.85 + hpPct15%。
- 切换近战/远程 `twoHeadSwitch`: 见上。
- 精神干扰 `twoHeadMindBlast`: cd3 atkScale1.0 magic + shieldBreakPct50%(扣当前盾) + healReduce50%/3t(dur4)。
- 锤击 `twoHeadHammer`: atkScale1.4 物理 + shieldFromDmgPct50%(按 raw dmg 加永久盾)。
- 吸收 `twoHeadAbsorb`: cd2, base=round(atk×0.6)+round(tMaxHp×8%) 物理; heal=round(atk×40%)+round(已损HP×18%)。
- 融合 `twoHeadFusion`(passiveSkill, 与切近战互斥): 登场一次性 maxHp+=round(atk×1.5)等同切近战增量, `_twoHeadFusion=true`, 不可换形。

**twoHeadResilience 受伤累积**(挂 `apply_raw_damage` 中心点): `finalDmg>0 && _twoHeadResilience && _twoHeadResStacks<20` → stacks++, baseDef+1/def+1, baseMr+1/mr+1。上限20。标记: 选了对应 idx 即 `_twoHeadResilience=true`。无飘字(面板徽章)。

**AI**: 无 pet-specific 覆盖（走通用; 换形 cd4=最高 cd, AI 偏频繁换形）。
**passive `twoHeadDual`**: no-op marker（**无每回合+3atk**, PoC 删了自创）。

---

## 2. lava 熔岩龟「变身/暴怒」(S级, hp390/atk40/def14/mr16, passive `lavaRage`)

**passive 字段**(pets): rageDmgPct25/rageTakenPct20/rageMax100/transformHpScale2.5/transformAtkScale0.2/transformDefScale0.2/transformMrScale0.2/transformAoeDmgScale1.2/transformDuration6。

**字段**: `_lavaRage`、`_lavaRageReady`、`_lavaTransformed`、`_lavaSpent`(变身瞬设true, 结束才清→可二次)、`_lavaTransformTurns`、缓存 `_lavaHpGain/_lavaAtkGain/_lavaDefGain/_lavaMrGain/_lavaSmallSkills/_lavaSmallName`。

**怒气累积**(变身中不累积):
- 攻击端(`passive-triggers` on-hit): `_lavaRage += round(显示伤害×25%)`, 钳100。
- 受伤端(`apply_raw_damage` 中心点): `_lavaRage += round(hpLoss×20%)`（只算 hpLoss, 打盾不积）。
- ≥100 → `_lavaRageReady=true`。

**触发变身**(`_lavaRageReady && !_lavaSpent`): 清怒, set spent/transformed, turns=6。基于变身前 atk(preAtk): hpGain=round(preAtk×2.5)/atkGain=round(preAtk×0.2)/defGain/mrGain 同0.2。应用同 two_head（base+=, hp 比例缩放）。切技能=volcanoSkills 按 _equippedIdxs 配对滤 passiveSkill, cdLeft=0。改名"火山龟"+换贴图。
**变身瞬间 AOE**: 全敌 round(变身后atk×1.2) magic(过魔抗+magicMult, 最低1); 非烧免疫敌施灼烧 round(atk×0.67)层 + 熔岩龟回 8% 已损HP/每敌。
**倒计时**: 每**回合**(非每行动, 用 turn 闸防 boss 双减) `_lavaTransformTurns--`; 归0还原(撤增量, hp 比例缩放, skills=_lavaSmallSkills, 名/贴图还原, spent=false 可再变, rage=0)。
**二次检查**: side-end 后再扫(DoT 回合外填满怒气)。

**强化 `lavaEnhancedRage`**(passiveSkill enhancesPassive): 战斗开始即 rage=100/ready=true → 首动立即变身。火山形态对应槽也占位被滤(火山少一槽)。

**火山技能**(基于变身后 atk): 烈焰重击 `volcanoSmash` round(atk×1.3)+round(maxHp×8%) 物理+20%吸血; 熔岩铠甲 `volcanoArmor` cd3 盾round(atk×0.9)+def/mr+round(base×20%)/3t+回15%已损HP; 火山爆发 `volcanoErupt` cd4 全体5段 each round(atk×0.22)+round(maxHp×3%) magic+灼烧+回总伤15%; 岩浆践踏 `volcanoStomp` cd3 全体 round(atk×0.8) magic+40%眩晕(dur2)+回10%已损HP。

**AI**: 无 pet-specific（变身被动触发, AI 不择时）。

---

## 3. shock — cyber 赛博龟「浮游炮/机甲」+ lightning 闪电龟「电击层」(两套独立系统)

### cyber (passive `cyberDrone`: droneScale0.25/droneMaxAge5未用/maxDrones10/mechHpPerBase30/mechHpPerLv2/mechAtkPerBase4.5/mechAtkPerLv0.1)
**字段**: `_drones: Array[{age:0}]`（**用 .length 当 droneCount, 绝不加 _droneCount**）、`_cyberEnhanced`、`_mechFormed`、`_isMech`。
**每回合 side-end spawn+fire**(对 alive&cyberDrone&!_isMech): spawn `dronesPerTurn??1`(强化2)个至 `maxDrones??10`(强化20); **turn<=1 只spawn不fire**; turn>=2 每炮打1随机敌 round(atk×droneScale) 物理(吃甲, droneScale 强化0.12/普通0.25), 走 on-hit 链, 400ms 间隔。
**cyberDeploy**(cd2 selfCast): push min(deployCount3, maxD-len)个炮, 无伤害。
**cyberSwarmShield**(cd5 AOE友盾): perDronePct=强化10/普通15; totalScale=0.6+(pct/100)×droneCount; round(atk×totalScale) 永久盾给全友。(别名 cyberFirewall 同函数)
**激光枪 `physical`**(cd0): hits5 atkScale0.15 hpPct2.4。
**cyberBeam**(已移植): 读 _drones.length/_cyberEnhanced。
**强化 `cyberEnhancedDrone`**(passiveSkill): _cyberEnhanced=true, maxDrones10→20/droneScale0.25→0.12/dronesPerTurn1→2。
**机甲变身**(cyber 死亡 hook, droneCount>0&!_mechFormed): dc=len, lv=_level; maxHp=hp=round((30+2×lv)×dc); baseAtk=atk=round((4.5+0.1×lv)×dc); def=mr=(_cyberEnhanced?3×dc:0); crit0.25; 清其余/shield/buffs; alive=true; 名"机甲"🤖; passive→mechBody; skills→单技"机甲攻击"physical hits1 atkScale1.5; 每回合末自动攻最低血敌 1.5×atk 物理。
**AI**: 无 cyber 选技覆盖; 但 cyberDeploy=selfCast/cyberSwarmShield=aoeAlly 需标"不点敌目标"。

### lightning (passive `lightningStorm`: shockScale0.82/stackMax8) — 独立, 与 cyber 解耦
**电击层单源**: `_shockStacks: int`（**别用 buffs 并行存**）。
**每回合 side-end**: 持龟随机电1敌 round(atk×0.82×surgeBoost) 真伤穿透 + on-hit 链叠1层。
**满层引爆**(攻击方是闪电龟时 target stacks++; ==8 → round(atk×0.82×surgeBoost) 真伤+清零)。
**涌动**: `_lightningSurgeTurns`(2)/`_lightningShockBoostPct`(50) → 涌动内被动电击×1.5。
**未移植主动技**: lightningStrike(cd0 hits5 atkScale1.15 magic+splash25%+叠层, 已移植); lightningSurgeBuff(cd4 设surge+即时电 atk×0.82×1.5真伤); lightningBarrage(cd6 20次随机敌 arrowScale0.11 magic+叠层); lightningSurge(cd4 AOE 每层0.1×atk真伤+清层); lightningShield(cd3 self盾0.9×atk+在盾时受击反击0.1×atk magic+叠层)。

---

## 4. star 太空龟「星能」(**id=`space` 不是 star**, S级 hp449/atk45/def13/mr15, passive `starEnergy`)

**passive 真值**(读字段别用占位): chargeRate62/maxChargePct40/passiveFirePct30/burstPct100。
**字段**: `_starEnergy:int`(默认0)。`maxE=round(maxHp×40/100)`(现算不缓存)。
**累积**(addStarEnergy, 仅造成伤害时): `gain=round(显示伤害×62/100)`, `_starEnergy=min(maxE, cur+gain)`。每段伤害都充(beam每段/meteor每敌/blackhole/warp每敌/余烬本身)。
**被动 fireStarPassive**(5技能收尾各调1次): `fireDmg=round(_starEnergy×30/100)` true 无视防御, 走 on-hit 链, 命中后再充能。**⚠ JS 有 skipRefill(meteorBurst/warp 清空后余烬不回充), PoC 漏了 → Godot 应实现 skipRefill 避免永远满能**。

**starMeteor 流星**(cd, AOE): round(atk×1.0) magic+暴击+mrDown{20,3t}/敌+充能; **满能爆发**(>=maxE): burstDmg=round(_starEnergy×100/100) 全敌真伤, energy=0; 收尾 fire。
**starBlackhole 黑洞**: isLastEnemy(敌<=1): HP%<=15→斩杀(true hp+99999); 否则1.8×atk magic。非最后敌: 1.0×atk magic+踢黑洞(push blackhole{dur2}+stun{dur2}, `_isInBlackhole=true`/`_stunUsed=false`)。充能+fire。
  **黑洞标记**: `_isInBlackhole` **每帧跟随 buff**(alive && 有blackhole buff), buff 没了自动false。dur2→side-end减1→下回合开始<=1清, 飘"脱离黑洞"(禁锢1完整回合)。影响: 单体不可选+胜负不算在场, stun跳手, 被动仍触发。
**starGravityWarp 扭曲**(cd, AOE atkScale0.8): 全敌0.8×atk magic+充能; **满能换位**(>=maxE): F0↔B2/F1↔B1/F2↔B0 改 _slotKey+_position, energy=0, 发'star-gravity-warp'事件→重 layout。收尾 fire。
**starBeam 星光**(hits3 atkScale0.4 currentHpPct6): 每段 round(atk×0.4)+round(tHp×6/100) magic+暴击+充能; 收尾 fire。**⚠ wormhole buff 加成是死代码勿移植**。
**starWormhole**(已移植但**确保保留 turnDmgPct 回合加成** `(1+10/100×turn)`): hits4 atkScale1.5, 自身 magicPen+=round(6+0.5×lv), target 横排全敌 4段平摊, 命中击飞, 收尾 fire。

**AI 覆盖**: starMeteor: cur<maxE→避开(选others cd最大), cur>=maxE→强制meteor; starGravityWarp: >=maxE 才允许否则换。
**VFX**: 满能换位/爆发**别加"星能爆发!/扭曲!"喊话浮字**(用户已删), 只保留伤害数字。

---

## 5. hiding 缩头龟「召唤随从」(SS级 hp515/atk37/def20/mr21/crit0.25, passive `summonAlly` hpPct40/maxRarity"A") — C组最复杂

**技能池5**: 0攻击`physical`(命中后自身defUp round(def×0.2)/2t); 1防御`hidingDefend`cd3; 2指挥`hidingCommand`cd3; 3强化随从`hidingBuffSummon`cd4 selfCast; 4强化喊龟`hidingEnhancedSummon` passiveSkill。

**召唤生成**(战斗开始扫 passive.type=='summonAlly' → spawnSummonAlly):
- 候选: validRarities(maxRarity A→[C,B,A]); 从 ALL_PETS 滤 rarity∈valid && id∉已上场, 随机抽1(空→不召唤)。
- createFighter 真龟(属性来自被抽中龟自身)。**血覆写**: maxHp=hp=round(hpBasis×hpPct/100), hpBasis=`_summonHpBase ?? owner.maxHp`。
- 技能 aiPickSkills(按主人等级, idx0/1/2恒解锁, idx3 lv>=4, idx4 lv>=7, ~30%含1被动); **必滤 SUMMON_SPAWNS_UNIT**{pirateShipPassive,crystalBall,candyBombPassive,cyberEnhancedDrone,hidingEnhancedSummon}; 全滤→defaultSkills; cdLeft=0。
- **占槽**: `_savedSummonSlot` 优先(未被活体占) → 否则**后排优先序** `[back-2,back-1,back-0,front-2,front-1,front-0]` 第一个空(used=本队活体_slotKey, 死龟槽可复用) → 满则不召唤。落位 set _slotKey+_position。**不用前排优先的通用 findEmptySlot**。
- **标记**: `_isSummon=true`/`_owner=owner`/`_level=owner._level`, 反向 `owner._summon=summon`(关键, 漏则永久"随从已亡")。

**hidingEnhancedSummon**(登场期, 早于召唤): `_enhancedSummon=true`, `_summonHpBase=maxHp`(减半前), hpLoss=round(maxHp×0.5), maxHp=max(1,maxHp-hpLoss), hp同步, passive.hpPct 40→110。结果: 本体剩50%, 随从血=原始maxHp×110%。

**召唤物独立 AI summonAutoAction**(每回合末每随从跑1次; 指挥让它额外跑1次):
- ready=cdLeft0(空→return); enemyViews=敌活&!_untargetable(空→return); allyViews=本方活(owner不在则补)。
- SELF_TYPES{phoenixShield,fortuneDice,hidingDefend,hidingCommand,cyberDeploy,cyberBuff,ghostPhase,diamondFortify,diceFate,chestCount,bambooHeal,volcanoArmor,crystalBarrier}; ALLY_TYPES{heal,shield,bubbleShield,angelBless}。
- **优先级**: ①healS且(自己hp%<0.35||owner活&owner hp%<0.35)→heal; ②shieldS: selfCast→自己shield<20&hp%<0.6; 否则盟友shield<20&hp%<0.6; ③selfS非空&rand<0.3→随机self; ④dmgS非空→cd降序, dmgS[0].cd>0&rand<0.8取最高cd否则随机; ⑤ready[0]; 选中hidingCommand→换非command(防递归)。
- **选目标**: SELF/selfCast→自己; ALLY→盟友hp%最低; 否则敌: pool=enemy, 非ignoreRow有前排只打前排, taunt强制, 否则hp%升序 lowest(undeadLock回避 / hp%<0.2&rand<0.9补刀 / rand<0.7 lowest / 否则随机)。
- 执行 runSkillHandler 不走 endTurn(防再入), 行动后结算死亡。

**hidingCommand**(cd3): 读_summon(无/死→飘"随从已亡"); 有→立即 summonAutoAction(summon) 额外1次(回合末仍常规1次=本回合2次)。
**hidingBuffSummon**(cd4 selfCast): _summon活→push 4buff dur2: atkUp round(summon.baseAtk×0.10)/defUp baseDef×0.10/mrUp baseMr×0.10/lifesteal10/critUp20(锚_baseCrit防复利)。
**hidingDefend**(cd3): `_hidingShieldVal+=round(maxHp×0.20)`, `_hidingShieldTurns=4`, `_hidingShieldHealPct=20`; 回合末tick turns-1, 归0时 heal=round(剩余盾×20/100) owner回血清盾。

**缩头/选目标**: 三 chokepoint 查 `_isSummon` 挡敌方单体(玩家选/AI选), **AOE+回合被动伤害不挡**(getEnemies 不排_isSummon); 随从可被己方 heal/buff。`_untargetable`=完全不可选+免伤+胜负排除(≠_isSummon 只挡单体)。缩头龟本体无减伤/不可选(隐藏的是随从)。
**级联死亡**: owner 死→随从 alive=false/hp=0 + 跑随从死亡被动。
**AI 覆盖**: 主AI选 hidingCommand/hidingBuffSummon 时 _summon 不存活→换技能。
**isNonActor**: 随从非玩家可控, 玩家回合不进操作队列。

---

## 实现顺序 / 依赖
two_head(最自包含, 无召唤/死亡 hook) → lava(怒气累积挂中心扣血点) → shock(cyber 需 side-end hook+死亡 hook; lightning 独立) → star(_starEnergy+黑洞+换位事件) → hiding(需召唤框架+占槽+独立AI+级联死亡, 最重)。
公共依赖: 多数变身改 base* 后需 recalc 不抹; 怒气/坚韧/电击层挂 `Damage.apply_raw_damage` 中心点; side-end hook(已在 turn 引擎留 TODO); passiveSkill enhancesPassive 装载守卫; on-hit 链扩展; 死亡 hook; 羁绊(未实装则 stub)。
