# 战斗技能动画/节奏 1:1 移植 — 工作清单

## ⚠️⚠️ 2026-06-05 架构修正 (用户: "忍者放技能每帧完全不一样" → "明显所有龟都有问题")
**根因 (4-agent 全28龟逐行审计确认, 系统性非单龟)**: 旧版把每个技能拆 `_skill_windup(播完位移)→execute(一次性算全部伤害)→post(击飞)` 三段顺序; 而 PoC skill-handlers.ts 是一条 async 链, 在动画确切毫秒穿插命中。更深: `skill_handlers.gd` 在**数据层**就把 N 段命中累加成单个 effect → 多段技能塌缩成「**一个数字、同帧、伤害与动画脱钩**」。
**已修 (8 commit, 336测全程绿)**:
- ✅ **渲染地基**: effect 可带 `segments[]`(value/dmg_type/is_crit/delay/y_off/hp_after/shield_after); 渲染层 `_play_damage_segments`/`_render_one_segment` 按 delay 错开飘字 + 血条逐段下降(`update_state`/`_refresh_slot` 加 hp/shield override → 每段自动触发红 trail); **display-segments 与 logic-effects 分离** → procs/统计/单测按聚合 value 不变。
- ✅ **全 ~20 多段 handler 接段数据**: `_do_physical`(hitStaggerMs 默认500) + `_multi_hit_result` 加 segments 参 + `_seg_push` 助手; 节奏逐一引 PoC 行号(物理500/骰子400/虫洞120/弹幕280/背刺3戳/冰锥物魔交替180/魔波物→真180/shell phys-true交替650/闪电700/...); 弹幕类(candy280/cannon300/lineSketch200/dice400/gamblerDraw220)走 _do_physical 加 `hitStaggerMs` 数据。
- ✅ **3 处真·颜色/数值 bug**: rainbowStorm 真伤段(40%ATK)整段丢失→新建专用 handler 补; bubbleBurst/lineFinish 物理段错显蓝→拆双段各自 dmg_type。
- ✅ **VFX 帧率表** `VFX_FPS`(PoC frameRate): ghost 10/cyber-beam 8.33/lightning 9/burn 10/... (原默认12偏快20%)。
- ✅ **熔岩变身演出**: 震屏+全屏橙闪+28粒子ADD爆 (原只染色)。
- ✅ **通用普攻挥击动作帧**: ACTION_PETS(basic120/ghost64/ninja throw/golem74) playAction('attack') 12fps + `_play_action_sheet_overlay` 缩放改对齐 avatar 显示高(修 120≠64 放大)。
- ✅ **burn-loop 燃烧叠层**: `_sync_burn_overlays` 每帧同步(8帧10fps, ADD 近似 SCREEN)。
- ✅ ninja dash/backstab 18→10fps, ghost phase 13→10fps, ninja冲击身后单位补击飞。
**剩余 (长尾, 需 F5 眼验手感)**:
- ⬜ **Phase4 签名技深度毫秒时序**(需动 windup/execute 架构, 让命中真插进动画中段): ninjaImpact 擦身穿过目标X那帧命中 / ninjaBackstab 精确 500-800-1100ms(现地基给 0/500/1000) / cyberBeam beam发射+360ms中段命中 / starBlackhole 旋涡应先于伤害(现伤害先算)。
- ⬜ **cyberBeam 贯穿全屏光束**(现只在目标点播小图; PoC 从 caster 拉伸到屏边 720ms 横扫)。
- ⬜ **telegraph 飘字**: 炮击!/+穿甲/-X破盾 (次要风味)。
- 注: 多数多段技能的"N个数字+逐段血条+正确颜色"已由地基修好; Phase4 是把命中"插进动画中段"的最后 10%。

---


## ✅ 已完成 (2026-06-01 自主run)
- **基建**: lunge/lunge_return/juggle物理(buildJugglePhysics 1:1)/knockup_hop/pulse_avatar/fire_arrow/action_sheet_overlay/follow_vfx/draw_ink_link/lightning_strike/blackhole_vfx/camera_focus/screen_shake/cut-in.
- **全身立绘+idle**: _make_slot_view 读 pets.json img+sprite.frameW/H, 全龟全身 sheet + idle 循环(PoC fps); 10 无元数据龟用静态全身PNG.
- **28/28 龟技能 choreography**: 批次1-6 全做完, 按 skill.type 在 _skill_windup/_skill_post_impact 分派. 铁律=SKIP_POSITIONAL_HOP 只含 basicSlam/basicChiWave/ninjaImpact/ninjaBackstab; 其余有type技能25px hop; 裸physical 80px. 复杂: 龟盾14段击飞/龟派气波滑排+波+juggle/过肩摔抛物/忍者dash-backstab-bomb-shuriken/幽灵phantom/cyberBeam KOF/star wormhole+blackhole/猎人箭/线条墨线/天降闪电等.
- **收尾**: 镜头zoom/pan(chiwave/cyberBeam; slam无zoom=PoC P155已删)/cut-in青闪0x3c8cff/barrage staggered bolt/墨线_process逐帧/朝向例外hiding+mech. Camera2D+limits, UI在CanvasLayer不受影响.
- 全程 298/298 单测; import 零错; 静态布局未被相机破坏(已截图验).

## ⏳ 剩余 (非动画/需眼验)
- **手感/节奏 F5 眼验**: hop节奏/镜头瞬间/dash apex — 动画动态, 数值已引PoC行但丝滑度需真机看.
- **_inkLink turns衰减/到期transfer**: 引擎层stub(羁绊6条effect未实装之一, memory已记), 表现层逐帧跟随已做.
- **宝箱雷刃VFX**: 待 chestTreasure装备变种logic移植后接(可复用_play_lightning_strike).

---
# (原工作清单存档)


> 静态层(所有 UI 场景 + 战斗布局 + idle 序列帧)已逐像素对齐 Phaser 并提交。
> 本文档是**最后一大块**: 战斗的**演出层**(技能动画/节奏/敌人怎么动)。

## 现状 (Godot 缺什么)
- Godot 技能流程: `_take_turn` → `SkillHandlers.execute`(纯逻辑+伤害) → `_play_skill_vfx`(目标处放个 VFX). **无演出编排**。
- 缺: caster 前冲/位移(lunge)、命中时序、击飞/抛物(juggle)物理、每技能的 VFX 序列+节奏、受击反馈节奏。
- Phaser 有完整编排: 每龟 `attackAnim` 元数据(pets.ts:152/747/1079) + 每技能 handler 里的 tween 编排 + juggle 关键帧。

## 权威源 (照搬, 不自创)
- `poc/src/scenes/BattleScene.ts` — 演出主体: 攻击编排、basicChiWave 滑到目标排(ts:3459)、juggle 关键帧(ts:166 ascent vy=-640/gravity g=1300/slam rot=-82°/lie 280ms/recover 220ms)、VFX 序列、receiveHit 节奏。
- `poc/src/engine/skill-handlers.ts` — 每技能的 api.* 演出调用(floatNum 已1:1; lunge/vfx/knockup/sleep 时序待移植). 小龟5技能: 攻击/龟盾(shieldBash 5段时序 ts:644)/打击(barrage)/龟派气波(chiwave ts:1018,3459)/过肩摔(slam juggle).
- `poc/src/data/pets.ts` `attackAnim{}` — 每龟攻击动作元数据(前冲距离/帧/时序). Godot data 应已同步, 但没用。
- VFX 资源: Godot `assets/sprites/vfx/` + `pets/animations/<id>/<action>.png`(忍者 dash/backstab, 幽灵 phase 等 action sheet, BootScene.ts:130-142 列了帧宽高).

## 移植步骤 (建议顺序)
1. **基建原语** (新 helper, 别堆进 BattleScene 巨文件):
   - `lunge(caster_node, target_pos, fwd_px, dur)` — caster 前冲再归位 (PoC 通用 hop 25px).
   - `juggle(target_node, keyframes)` — 击飞抛物物理 (照 ts:166-194 关键帧: ascent/gravity/slam/lie/recover).
   - `play_action_sheet(node, sheet, fw, fh, fps)` — 播一次性 action 序列帧 (忍者dash等).
   - VFX 时序: `_play_skill_vfx` 扩成可带 延迟/多段/跟随.
2. **接到技能流程**: `_take_turn` 里 execute 前后插演出: caster lunge → 命中点 VFX+伤害飘字(已有) → 受击 flash(已有 2503) → 归位。按 skill.type 选编排。
3. **逐技能 choreography**: 从小龟5技能开始(用户点名), 读 PoC 对应 handler 的时序/位移/VFX, 1:1 到 Godot。再 28 龟×各技能。
4. **全身 sprite sheet (资源其实都在!)**: 已查实 — `assets/sprites/pets/<id>.png` 全身 sheet 都在, 且 `data/pets.json` 每龟有 `img` + `sprite{frameW,frameH}` 元数据 (例: stone 5000×500/frameW500=10帧; bamboo 10帧; angel 1984×200/frameW248=8帧; basic img=animations/basic/idle.png 64²). **不是资源缺口, 是 `_make_slot_view` 没用**: 现在用 `avatars/<id>.png` 头像。改成: 从 DataRegistry 读该龟 `img`+`sprite.frameW/frameH` → 载 sheet → `hframes=sheet_w/frameW` → idle 循环(10fps)。这样**所有龟**全身立绘+idle动画统一(取代我现在只处理 4 个 animations/<id>/idle.png 的临时码, BattleScene.gd:369-410)。注意缩放: box/frameH。脚底锚定不变。

## 比对验证 (已搭好)
- `SHOT_SETUP=test SHOTDIFF=<秒> SHOT_OUT=res://_shot.png Godot --path . --resolution 1280x720 res://scenes/Battle.tscn`
- `python diffcrop.py ph-battle.png _shot.png x y w h scale out.png` → Read.
- 动画是动态的: 截多个时间点(SHOTDIFF=不同秒)对节奏; 或 F5 眼验手感。
- 改完必跑 `bash run-tests.sh` 仍 298/298 (别破坏战斗逻辑)。

## 铁律
严格 1:1 PoC, **不自创**。数值/时序/位移/帧率都引 PoC 源码行。引擎天生差异(CSS/字体bold)近似并注明。
