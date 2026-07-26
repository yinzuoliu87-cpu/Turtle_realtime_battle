# Phaser PoC → Godot v2 全量移植 Spec（4-agent 审计汇总）

> 2026-05-31 由 4 个并行 agent 审计 PoC 全部系统生成。这是后续移植的**权威参照**，改前先查这里。
> 数字全部从 `games/turtle-battle-poc/src/` 抠真值，附 PoC 行号供 grep。

---

## 0. 一句话结论

**所有 4 份报告交叉指向同一个瓶颈**：`recalc_stats` + `buff 系统` 是 15+ buff 和大多数技能的共同依赖。
**甜区是 T2 技能**：DoT 系统已做完（最贵预算已花），再加 5 类 debuff（stun/chilled/mrDown/atkDown/healReduce）即解锁 26 个技能 + 7 个元素龟。

### 推荐移植顺序（依赖链 + ROI）
```
1. StatsRecalc.gd        ← 15 buff 共用, 最大杠杆 (atkUp/defUp/mrUp/critUp/lifesteal/chilled...)
2. Buffs.gd autoload     ← buff CRUD + tick_duration + merge_mode
3. stun + next_actor跳过  ← 解锁所有 CC 系武器
4. apply_raw_damage 扩展  ← markedDmg/physImmune/dmgReduce/fear/hunterMark (照 PoC damage.ts 抄)
5. T1 技能字段补全        ← physical 加 defScale/mrScale (2 行), 立刻 +4 龟可玩
6. T2 批量 (26 个)        ← DoT/debuff 框架就绪后, 单 type <30 分钟
7. T3 选择器 (30 个)      ← 写 same_column/adjacent/same_row 3 helper 后批量
8. T4 状态机 (26 个)      ← 换形/召唤/redirect/特殊盾池
9. T5 VFX (30 个)         ← 最后, 没逻辑只有 VFX = 空壳
```

---

## 1. 装备系统 (46 件)

### 已实装 13 件 (W7 v1.1)
`e_blade, e_carapace, e_pearl, e_tooth, e_piercer, e_hammer, e_urchin, e_fire, e_jelly, e_anemone, e_octo, e_star, e_ripple`
- ⚠️ **e_urchin / e_jelly 是 flag-only**：字段 `_equipReflect/_equipStun` 已存但 on_hit 链未接，需补

### 推荐下一波 (难度 1-2, 纯数字无 VFX)
| id | 中文 | 公式 | hook | PoC 位置 |
|---|---|---|---|---|
| c_speed | 加速药水 | 遍历 skills cdLeft-1 | one_shot | equipment.ts:282 |
| c_emergency | 应急护盾 | shield += 80 | one_shot | equipment.ts:322 |
| c_heal | 治疗药水 | applyHeal(50 + maxHp×10%) | one_shot | equipment.ts:275 |
| c_firstaid | 急救包 | applyHeal(maxHp×15%) | one_shot | equipment.ts:328 |
| c_rage | 怒火药水 | atkUp buff baseAtk×25% 3t | one_shot | equipment.ts:314 |
| c_mark | 必中标记 | markedDmg buff 20% 2t | one_shot敌 | equipment.ts:343 |
| c_cleanse | 净化 | 去 12 类 debuff | one_shot | equipment.ts:335 |
| c_bomb | 炸弹 | 60 物理(def减), 不归属 | one_shot敌 | equipment.ts:291 |
| e_hourglass | 沙漏 | apply 时永久 cd-1 | on_attach | equipment.ts:187 |
| e_turtle_helmet | 小龟帽 | +70HP, 回合 applyHeal(25) | turn_begin | BS:5278 |
| e_turtle_shell | 小龟壳 | +5def+5mr, 非真伤 -2/击 | damage_hook | damage.ts:148 |

### 12 个移植陷阱 (PoC 踩过, 勿重蹈)
1. **e_hammer ATK** 必须在 recalcStats, 挂 onTurnBegin 会被抹
2. **e_anemone HoT** 是"本方回合开始"单次, 不能 per-actor (多动龟堆叠)
3. **e_jelly stun duration=2** (不是1, 1会立刻过期)
4. **e_pearl** 必须走 applyHeal (否则漏 healAmp/healReduce/star溢出/守护羁绊)
5. **e_octo backrow** 必须 calcDamage base 阶段 ×, 不能跳 armor 扣 HP
6. **e_carapace** +1/+1 per hit 不论件数 (cap 随件数), 旧版 N 件+N 双倍
7. **e_thunder_shell** 是"自回合末" 不是"受击反伤"
8. **e_hourglass** 永久 cd-1 在 apply 一次性, 不是 per-turn
9. **e_revolver** turn-begin 不消费子弹, 只 side-end + 敌死+1
10. **e_laser_blade** apply push 'laserSweep' 技能, 必须注册 handler
11. **e_star 溢出转盾** 收口到通用 lifesteal, 不单独 onHit (否则双吸)
12. **_lifestealPct → lifestealPct** 折叠在 recalc (÷100), 不两处消费

### 剩余难度分布
- 难度 2 (4): hourglass, turtle_helmet, turtle_shell, bamboo_leaf
- 难度 3 (5): ghost, thunder_shell, stun_baton, turtle_sword, incubator
- 难度 4 (10): lightning_staff, dumbbell, dart, candle, revolver, dragon_egg, conch, fpga, amplifier, laser_blade
- 难度 5 (6): mini_crystal A/B, wave, doll, master_whistle, candy_jar
- 消耗品 8: c_* 全难度 1-2

---

## 2. 羁绊 (10) + 战斗规则 (7)

**门槛**: 阵容 tag ≥2 → tier2; ≥3 → tier3 (`synergies.ts:198`, 注意是 2/3 不是 2/4)

### 羁绊真公式
| 羁绊 | tier2(≥2) | tier3(≥3) | 时机/消费点 |
|---|---|---|---|
| 物理 | baseAtk×1.04 | baseAtk×1.08 + bleed flag (命中 atk×0.08 流血1t) | 战前 + damage.ts:275 |
| 法术 | magicPen+2 | magicPen+5 + 敌 baseMr-4 | 战前 |
| 守护 | guardAmp=0.05, shield+15 | guardAmp=0.10, shield+30 | amp 在 applyHeal ×(1+amp) |
| 元素 | elemDmgBoost=0.05 | =0.10 + team[0] burnTick | DoT结算 BS:8087 ⚠️读对面 |
| 刺杀 | crit+5% armorPen+2 + killBonus | crit+10% armorPen+3 + execute(hp<50% ×1.10) | damage.ts:57 |
| 运气 | dodge buff 5 | dodge 10 + 发equip | 战前 (grant 是PoC增强) |
| 召唤 | summonHpBoost 10% atkFlat+5 | 15% / +10 | spawn时读 BS:6622 |
| 财富 | coinPerTurn=4 | + shopDiscount 25% | 每回合 BS:5301 |
| 换形 | shiftShieldPct 5% | 10% + firstAtk 8% | 换形完成 synergies.ts:219 |
| 再生 | reviveBonus 15% | 25% + reviveAttack | 复活 BS:4117 |

### 战斗规则真值
| 规则 | 效果 | 消费 |
|---|---|---|
| 烈焰 fire | burnMult()=1.5 | applyBurn 层数 ×1.5 |
| 雷暴 thunder | 全体 crit+20% (战前一次性) | — |
| 铁壁 shield | shieldMult/healMult=1.3 | 所有 applyShield/Heal ×1.3 |
| 狂暴 rage | 双方 atk×1.2, def/mr×0.85 (战前) | — |
| 装备 equip | 双方第一只发1件 (周期未实装) | — |
| 雨夜 rain | 每回合 def/mr-N + 5N魔法 (N=turn) | rule-effects.ts:69 |
| 普通 normal | 无 | — |

### 推荐先做 5 个 (验证 hook 架构)
1. 正常+狂暴 (验证 apply_rule_start 一次性改 base, 零 hook)
2. 物理+法术 tier2 (验证 apply_team_synergies 纯数据)
3. 铁壁 (验证全局倍率, 复用最广)
4. 守护 (验证 Fighter flag Dictionary 模式)
5. 召唤 (验证 on_summon_spawn hook, 后续刺杀/换形/再生 预演)

---

## 3. Buff 系统 (31 类)

### 按消费点 chokepoint 归类
**A. apply_raw_damage 入口** (最关键): markedDmg, physImmune, dmgReduce, hunterMark + flag(_untargetable/_turtleShellBlock/_dmgBonusThisTurnPct/_isInBlackhole/_anemoneShield/_rockLayers/diamondStructure/crystalResonance/undeadLock + bubble/aura/lava/hiding 盾池)
**B. calc_damage**: fear + passive(basicTurtle/bonusDmgAbove60/assassinExecute/backrowBonus)
**C. recalc_stats** (15 buff): atkUp/atkDown/defUp/defDown/armorBreak/mrUp/mrDown/armorPen/critUp/critDmgUp/diceFateCrit/lifesteal/chiWaveActive/chilled
**D. apply_heal**: healReduce + 字段(rippleHealAmp/synergyGuardAmp/healMult)
**E. tick_dots** (已实装): burn/poison/bleed/curse
**F. roll_dodge**: dodge + dodgeCounter
**G. next_actor 跳过**: stun
**H. tick_hots**: hot
**I. trigger_on_hit_effects**: counter/reflect/trap/bubbleBind
**J. 目标选择**: taunt/stealth/redirectAll/blackhole

### Buff 优先级 (影响面 × 难度低)
1. **stun** — 8+ CC 技能依赖, 没它整条 CC 链废 → next_actor 加 `_stunUsed`
2. **atkUp/defUp/mrUp 三件套** — recalc 一锤 ~10 buff (含 down/critUp/lifesteal/chilled)
3. **dodge + dodgeCounter** — 鳞片/协同/e_ghost → _do_physical 顶部 roll_dodge
4. **markedDmg/physImmune/dmgReduce** — apply_raw_damage 顶部 3 if (照 damage.ts:137-189 抄)
5. **healReduce + hot** — 新增 Skill.apply_heal autoload + tick_hots

### 重要纠正 (勿照搬)
- **shield buff 是死 ledger** — 真盾走 fighter.shield 数值, buff 仅装饰
- **taunt/stealth 只 read 不 push** — 数据注册但无技能用, 先只做 read 端
- **armorBreak 与 defDown 同 case** — 别复制两分支
- **DoT 走层数模型(999) vs 普通 buff 走 turns** — 两套独立, DoT 别塞 Buffs.add
- **duration = turns+1** (push 时 caller 加 1, turn-begin tick 先 -1)

### Buffs.gd autoload API
```gdscript
Buffs.add(f, type, value, duration, merge_mode="overwrite", extras={})
Buffs.find(f, type) -> Dictionary or null  # 禁止 caller 自己 .find
Buffs.has(f, type) -> bool
Buffs.sum_value(f, type) -> int
Buffs.consume_one(f, type) -> int  # 一次性 buff
Buffs.remove_all(f, type) -> int
Buffs.tick_duration(f) -> Array  # 回合末 dur--, DoT(999)跳过
Buffs.reset_per_turn_flags(f)
# merge_mode: overwrite(取max) / stack(累加) / refresh(只刷dur) / ignore(已存在不加)
```

---

## 4. 技能 type (142 个 active handler)

### T1 — 现有 fallback 已能跑 (12) — **立刻清理**
physical/magic/shield/heal(已实装) + commonTeamShield/commonAtkBuff/bambooSpikes/headlessStorm/candyBarrage/diceAttack/fortuneStrike/phoenixPurify
- ⚠️ **physical 缺 defScale/mrScale 两行** (skill-handlers.ts:574-575)：石头龟伤害远低于描述。补了立刻 +4 龟

### T2 — 物理/魔法 + DoT/buff (26) — **甜区, DoT 已就绪**
phoenixBurn/lavaBolt/lavaSplash/lavaQuake/lavaSurge/iceFreeze/iceFrost/bambooSmack/phoenixScald/diceFate/lightningShield/lightningSurge/lightningBarrage/lightningStrike/starBeam/starMeteor/crystalBarrier/crystalBurst/diamondCollide/diamondSmash/diamondFortify/twoHeadFear/hunterMark/piratePlunder/bubbleBind/bubbleShield
- 涵盖 7 龟: 凤凰/熔岩/冰/雷/水晶/钻石/双头-恐吓 (元素系签名玩法)
- 单 type < 30 分钟 (复制 lavaBolt 模板换数字)

### T3 — 多段/AOE/横列选择器 (30)
需写 3 helper: `same_column_fighters`(横排) / `adjacent_fighters`(邻接) / `same_row_fighters`(_position整排)
basicChiWave/laserSweep/rockShockwave/cyberBeam/shellStrike/shellErode/ghostTouch/ghostStorm/iceSpike/bubbleBurst/bubbleHeal/lineSketch/lineInkBomb/lineFinish/... 等

### T4 — 状态机/换形/召唤 (26)
twoHeadSwitch(换形)/cyberDeploy(浮游炮)/stoneTaunt(redirect)/hidingDefend(限时盾池)/ghostPhase(物免)/shellCopy(抽敌技能)/angelSmite/... 优先 twoHeadSwitch+cyberDeploy+stoneTaunt (解锁最多龟)

### T5 — VFX 重度 (30) — 最后做
turtleShieldBash/basicSlam(KOF过肩摔)/ninjaImpact/cyberBeam/starBlackhole/basicBarrage/ninjaBomb/... 没逻辑只有 VFX = 空壳

### 关键发现
- buff push 后**必须立即 recalc_stats(caster)** 才本回合生效 (basicChiWave:903 / iceFrost:3624 踩过)
- 限时盾池 (lavaShield/hidingShield/bubbleShield) 是 fighter 私有字段, 不走 caster.shield — apply_raw_damage 加 4 分支

---

## 5. 已实装清单 (Godot 当前进度, 2026-05-31)

| 系统 | 状态 |
|---|---|
| 数据层 (28龟/46装备/10羁绊/50成就/13状态) | ✅ JSON + DataRegistry |
| Damage (calc_eff/calc_dmg_mult/apply_raw简版/crit) | ✅ W3, 46 单测 |
| FighterFactory (等级稀有度缩放) | ✅ W3 |
| SkillHandlers (physical/magic/heal/shield + AI + CD) | ✅ W5a |
| Dot.gd (burn/poison/bleed/curse 层数模型) | ✅ W7 |
| EquipmentRuntime (13件 on_attach/on_hit/on_hit_as_target/on_turn_begin) | ✅ W7 v1.1 |
| TeamSelect / MainMenu / 闯关 5关 / 存档 | ✅ W5b-W10 |
| 音效pitch分化 / 粒子 / HP滚动 / 暴击hit-stop震屏 | ✅ W6 Juice |
| **缺**: StatsRecalc / Buffs.gd / stun / dodge / apply_raw扩展 / 选择器 / 换形 / 召唤 | ⬜ 下一波 |
