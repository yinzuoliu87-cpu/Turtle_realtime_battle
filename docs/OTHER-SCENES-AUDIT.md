# OTHER-SCENES-AUDIT — 严格 1:1 迁移审计 (只读)

Phaser/TS PoC = 权威源, Godot = 迁移目标. 行号为打开文件确认的真实行号.
判定图例: **MISSING** = 整模块缺失 | **自创** = Godot 有 PoC 没有 | **行为不同** = 都有但逻辑/数值不一致 | **数值错** = 常量/公式错 | **迁移差异** = DOM↔Control 合理实现差(不算 bug).

文件:
- Codex: PoC `games/turtle-battle-poc/src/scenes/CodexScene.ts` ↔ Godot `scripts/scenes/CodexScene.gd`
- MainMenu: PoC `MainMenuScene.ts` ↔ Godot `MainMenuScene.gd`
- BattleEnd: PoC `BattleEndScene.ts` ↔ Godot `BattleEndScene.gd`
- Achievements: PoC `AchievementsScene.ts` ↔ Godot `AchievementsScene.gd`
- Record: PoC `RecordScene.ts` ↔ Godot `RecordScene.gd`
- Settings: PoC `SettingsScene.ts` ↔ Godot `SettingsScene.gd`

---

## 1. 图鉴 Codex

**结论**: 5 个 Tab + 列表 + 详情顶部区/属性条/被动条 数据 1:1, 布局常量基本逐值对齐. 但**详情的三类 drill-down (单技能详情 / 被动展开 / 形态切换) 全部缺失**, 装备**数值预览缺失**, 规则 Tab **少了"小商店物品池"虚拟入口整块 (含价格/分布/增益池)**, 羁绊详情**缺 tier 标签**与**"拥有此羁绊的龟"列表**, 等级系统未接 (恒 Lv1).

### 整模块缺失 / 自创 / 行为不同

- **技能单卡 drill-down (单技能详情页)** — Phaser `CodexScene.ts:455` renderSkillListSection 每张技能卡 `bg.on('pointerdown', …showPetDetail(pet, { skillIdx: i }))` → `CodexScene.ts:532` renderSkillDetailSection (← 返回 + 完整 detail 文本 + 滚动框) → Godot `CodexScene.gd:432` `_render_skill_cards` 只渲染卡片, 卡**无点击回调**, 无 `renderSkillDetailSection` 对应函数 → **MISSING (drill-down 整块)**. Godot 玩家点技能卡无反应, 只能看 brief, 看不到完整 detail.

- **被动展开 drill-down** — Phaser `CodexScene.ts:366-394` 被动条是 hitbox, 点击 toggle `view='passive'` → `CodexScene.ts:572` renderPassiveDetailSection 显示完整 `passive.desc` → Godot `CodexScene.gd:411-425` 画了被动条 + "点击查看 ▸" 文字, 但条**无点击交互**, 无 renderPassiveDetailSection → **MISSING**. "点击查看 ▸" 提示在 Godot 是死文字.

- **双形态龟 形态切换按钮** — Phaser `CodexScene.ts:401-432` 检测 `volcanoSkills`(熔岩龟变身)/`meleeSkills`(双头龟换形), 显示 "🌋 查看 火山形态技能"/"⚔️ 查看 近战形态技能" 切换按钮 + form-list 视图 → Godot `CodexScene.gd` 全无 form 概念 (`_render_skill_cards` 只读 `skillPool`) → **MISSING**. 双形态龟在 Godot 图鉴看不到第二套技能.

- **装备数值预览** — Phaser `CodexScene.ts:632-656` 扫 `eq.apply.toString()` 正则提取 `+N ATK/HP/DEF/MR/物穿/法穿` + `⊕烧伤/眩晕/流血...` 标签, 渲染 "数值预览" 区 → Godot `_show_equip` (`CodexScene.gd:496-519`) 只有 icon+名+类别+描述, **无数值预览**. 注: 这块 PoC 靠 JS 运行时 `Function.toString()` 正则, Godot(数据是 JSON) 无法照搬, 但仍是**功能缺失** (需改为读 JSON 字段实现) → **行为不同/MISSING**.

- **规则 Tab "小商店物品池"虚拟入口** — Phaser `CodexScene.ts:850-862` 在 7 条 battle-rules 之后追加一个 `🛒 小商店物品池` 行 → 点击 `CodexScene.ts:869` showShopPoolDetail (价格 BASE_PRICE / 每格稀有度分布 SLOT_DIST A~F / 增益池 BUFF_POOL 全清单) → Godot `_switch_tab` 的 `"rules"` 分支 (`CodexScene.gd:112-115`) 只遍历 `battle_rules`, **无 shop-pool 行, 无 showShopPoolDetail** → **MISSING (整块经济规格展示)**.

- **羁绊详情 tier 标签 + 拥有此羁绊的龟列表** — Phaser `showSynergyDetail` `CodexScene.ts:706-717` 显示 "2★ 激活 (2 只龟)"/"3★ 激活 (3 只龟)" 标签 + `CodexScene.ts:722-737` "拥有此羁绊的龟 (N)" 头像网格. Godot `_show_synergy` (`CodexScene.gd:522-532`) **有** "2★/3★ 激活" 文字 + tier desc (✓), 但**无"拥有此羁绊的龟"头像列表** → **MISSING (龟列表块)**.

- **等级系统未接 (恒 Lv1)** — Phaser 详情用 `getPetLevel(pet.id)` 显示实际等级 + `getLevelBonus` 乘进属性/技能占位 (`CodexScene.ts:265,301,324`). Godot `CodexScene.gd:368` `var lv = … if DataRegistry.has_method("get_pet_level") else 1`; DataRegistry **无** `get_pet_level` 方法(已 grep 确认) → 恒显示 "Lv 1"; `_ctx_for` (`CodexScene.gd:345`) 与属性 `m`(`:384`) 也**不乘等级加成** (只乘 RARITY_MULT). → **行为不同**: 图鉴永远 Lv1 数值. (注: 图鉴默认本就是 Lv1 展示, 影响有限; 但技能锁/等级加成在 PoC 是真特性.)

- **技能卡 等级锁 (🔒 / "Lv.N解锁" chip)** — Phaser `CodexScene.ts:467-491` idx3 需 Lv4、idx4 需 Lv7, 锁定卡灰显 + "Lv.N解锁" chip. Godot `_render_skill_cards` 无 `isLocked`/`unlockLv` 概念 → **MISSING (锁定视觉)**. (因等级恒 1, PoC 里 idx3/4 本会锁; Godot 全部当解锁渲染.)

- **滚动条 maxScroll** — Phaser 自管 `maxScrollY` + wheel 手动滚 (`CodexScene.ts:148-153`). Godot 用 `ListScroll`/`ScrollContainer` 容器 (`CodexScene.gd:7`) → **迁移差异 (合理)**.

### 数值/常量核对 (一致项, 抽样)
- Tab: 5 个 pets/equips/synergies/status/rules, 标签 emoji + `(N)` 计数 — Phaser `:87-93` ↔ Godot `:16-19,48-57` ✓ 一致.
- Tab 尺寸 170×36 间隔 8, active 0xffd93d — Phaser `:94-96,965` ↔ Godot `:43-45,68-83` ✓.
- 列表行 52/gap4/pad8, bg 0x1a2740@0.85, 描边稀有度@0.7 — Phaser `:183,189` ↔ Godot `:120-130,144` ✓.
- 详情立绘 170@(100,110); 名字 y30 32px; 稀有度 y75; tag x=midX+25+i×70 图y130(50×60) 文字y180 — Phaser `:278,301-318` ↔ Godot `:363-381` ✓.
- 4 属性条 statColX500 rowH42 valueX700 barsStartX716 方块 5×14 pitch7, divisor hp40/atk5/def2.5/mr2.5 — Phaser `:325-352` ↔ Godot `:385-405` ✓.
- 被动条 y=DIVIDER195+18 高50 0x12202a@0.55 边#58d3ff — Phaser `:360-388` ↔ Godot `:411-425` ✓.
- 技能卡 5 卡 168×260 gap8 起点(20,282), 默认边#06d6a0/普通#4a93d6 — Phaser `:461-475` ↔ Godot `:437-449` ✓.
- 装备 category 5 类 unique/special/normal/chest/consumable + 颜色/中文标签 — Phaser `:213-220` ↔ Godot `:199-205` ✓.
- 状态 4 类 dot/cc/buff/debuff + 颜色 — Phaser `:742-751` ↔ Godot `:222-226` ✓.
- 状态详情 formula 行 — Phaser `:813-819` ↔ Godot `:551-553` ✓ (有).
- 规则详情 icon92@(64,78) + 名 + "战斗规则" + 效果 desc — Phaser `:941-961` ↔ Godot `:556-571` ✓.

---

## 2. 主菜单 MainMenu

**结论**: 左栏 4 页折叠按钮 (main/online/local/custom) + 右墙龟币框 + 4 磁贴 + 入场动画 数据/布局 1:1 良好. 但 **DEV gate 行为反了** (Godot custom 页恒显示"测试模式", PoC 仅 `?dev=1`), **"← 返回龟投"母站链接缺失**, **联机按钮"敬请期待"toast 缺失**, **快速单体调试整入口缺失**, **教程入口是空函数 (无确认弹窗/无教程战斗)**.

### 缺失 / 自创 / 行为不同

- **教程磁贴 = 空函数** — Phaser 磁贴 "教程" → `confirmStartTutorial` (`MainMenuScene.ts:190,754`) 弹确认框 → `startTutorialBattle` 固定阵容 Lv7 vs Lv1 教程战斗 (`:776`). Godot `MainMenuScene.gd:266` `["ui/help-button", "教程", func(): pass]` → **MISSING**: 点教程磁贴**什么都不做**. (confirmStartTutorial + startTutorialBattle 全缺.)

- **DEV gate 行为相反 (测试模式恒显示)** — Phaser custom 子组 `MainMenuScene.ts:160-163`: "测试模式""快速单体调试" 仅 `if (DEV_VISIBLE)` 显示. Godot `MainMenuScene.gd:151` custom 页**硬编码**含 "测试模式" (`_on_test`), 且**无** DEV 判断 → **行为不同**: 正式构建里仍露出测试模式. 另 "快速单体调试" Godot **完全没有** → **MISSING**.

- **快速单体调试整入口** — Phaser `openSoloDebug` (`MainMenuScene.ts:634`) DOM 浮层选 1 龟 + 5 选 3 技能 → test 战斗. Godot 无对应 → **MISSING** (dev-only, 优先级低).

- **"← 返回龟投" 母站链接** — Phaser `MainMenuScene.ts:237-247` 左上角 "← 返回龟投" → `window.location.href = '../../index.html'`. Godot 无此节点 → **MISSING** (网页母站返回; Godot 桌面端语义不同 → 部分**迁移差异**, 但 PoC 网页版有, 列为缺失).

- **联机"敬请期待" toast** — Phaser online 页快速匹配/房间对战 disabled, 点击走 `showComingSoonToast` (`MainMenuScene.ts:142-143,873`). Godot `MainMenuScene.gd:147` online 页两按钮 `Callable()`(空)+`disabled=true`, `_frame_button` 对 disabled 不接任何回调 (`:204` `if not disabled and cb.is_valid()`) → **行为不同**: 点击**无任何反馈** (PoC 有 toast).

- **全屏询问弹窗 (maybeAskFullscreen)** — Phaser 进菜单 450ms 后弹 "全屏体验更佳" 弹窗 (每会话一次) → 再弹引导 (`MainMenuScene.ts:252,260`). Godot 无 → **MISSING**.

- **4 步新手引导 (showTutorial)** — Phaser 首启弹 4 步引导 (欢迎/组队/战斗/协同) localStorage 记一次 (`MainMenuScene.ts:790`). Godot 无 → **MISSING**.

- **整页过场动画 (flyOut/flyIn)** — Phaser 切页时当前页全部错峰飞出 + 目标页飞入 (`MainMenuScene.ts:389-436`). Godot `_show_page` 直接 `queue_free` 旧页 + 新页淡入 (`MainMenuScene.gd:138-174`), 无飞出过场 → **行为不同 (简化)**, 视觉手感差异.

- **龟币/战绩读取来源** — Phaser 读 `localStorage turtle-poc-progress-v1` (coins/wins/battles) + 战绩磁贴显 "N胜 N负" subValue (`MainMenuScene.ts:171-192`). Godot 读 `GameState.coins` (`:257`), 战绩磁贴 (`:268`) **无 subValue** (PoC 战绩磁贴带 recordValue 小字) → **行为不同 (小)**: Godot 磁贴不显示胜负小字.

- **入场动画常量** — 标题 delay250/dur550 scale0.85→1.1 EASE_MENU_IN — Phaser `:62-64` ↔ Godot `:127-130` ✓; 左栏按钮 delay 550+80i dur420 — Phaser `:118` ↔ Godot `:169-171` ✓; 右栏卡 delay 850+60i dur420 — Phaser `:201` ↔ Godot `:284-285` ✓. 布局 LEFT_CX240/BTN360×87/WALL16/TILE104/TSTEP120/TILE_TOP190 全 ✓.

- **设置入口** — main 页 "设置" → SettingsScene 两侧 ✓.

---

## 3. 战斗结算 BattleEnd

**结论**: 龟币公式 (胜 50+floor(总伤/100), 负 10)、runEnded/runWon 深海逻辑、7 列伤害统计表、按钮路由 1:1 对齐. 差异: Godot **自创了"平局"标题分支 + 胜利掉落 1 件装备 + loot 文字** (PoC 无), PoC 的**成就 toast / dungeon-best localStorage / best.turn&dmg 统计 / 再战传 loadout** 等收尾在 Godot 缺失或不同.

### 自创 / 缺失 / 行为不同

- **"平局" 标题分支 (自创)** — Godot `BattleEndScene.gd:79-81` `if tie: title="平局"`. PoC `BattleEndScene.ts:73,87` **只有 win/lose 二元** (`isWin ? '胜利' : '失败'`), 无平局态 → **自创**.
  > ⚠️**我核验(2026-06-03, 勿盲删)**: Godot 整队制 MAX_TURNS 会产生真平局 (`_show_result(true)` BattleScene:665) → tie 分支在处理真实状态. PoC 的 MAX_TURNS 用别的常量名/在别处定胜负(grep BattleScene.ts 无 MAX_TURNS/draw/tie 命中, 需深挖其超时判定). 直接删 tie 显示而不改判定 → 平局被错标. 真 1:1 需先对齐 PoC 超时定胜负逻辑. **暂留, 低影响(平局罕见)**.

- **胜利掉落装备 + loot 文字 (自创)** — Godot `:39-42` `if won: dropped = EquipmentRuntime.random_loot(); inventory.append` + `:97` 副文案附 "· 🎁 装备名". PoC **无任何战利品掉落** (奖励纯龟币; 深海装备走 RewardPickScene) → **自创** (代码注释自承 "过渡").
  > ⚠️**我核验(2026-06-03, 勿盲删)**: `GameState.inventory` 是**承重的** — BattleScene:298/370 开局把 inventory 装备**自动分给左队**. 此 loot drop 是 Godot **当前唯一能用的装备获取管线** (PoC 的 shop买→bench / reward→ 在 Godot 未接进 inventory). 盲删 → 玩家永远拿不到装备(除宝箱龟). **必须先把 shop/reward → inventory 接通(依赖 G1 经济决策)才能删此过渡**. 暂留.

- **成就 toast (showAchievementToasts) + tracker 挂钩** — Phaser `:158-168,202` 算 totalCrits/totalKills/allAlive → `tracker.onBattleEnd` → 新解锁成就右上角滑入 toast. Godot **无成就结算/无 toast** → **MISSING** (成就在结算时不会解锁/提示).

- **best.turn / best.dmg 统计** — Phaser `:134-135` 更新 progress.best (最快回合/最高伤害). Godot 无 best 统计字段更新 → **MISSING (数值统计)**.

- **dungeon-best localStorage + tracker.setBestDungeon** — Phaser `:149-155`. Godot 有 `best_dungeon_stage` 更新 (`:36-37`) 但**无成就 tracker.setBestDungeon** → **行为不同 (部分)**.

- **再战传 loadout/slots** — Phaser 再战 `scene.start('BattleScene', {leftTeam, leftSlots, mode, rule})` (`:191`). Godot `_on_rematch` (`:206`) single→TeamSelect, 否则→Battle, **不带 leftSlots/loadout** → **行为不同**: 再战阵型可能丢失.

- **标题文案** — Godot 胜利在深海末关显 "通关!" (`:82`), PoC 标题恒 "胜利", "通关" 在按钮 (`:187`) → **行为不同 (小)**.

### 一致项
- 龟币公式 50+floor(dmg/100) / 10 — Phaser `:109` ↔ Godot `:28` ✓.
- runEnded/runWon 深海逻辑 — Phaser `:116-117` ↔ Godot `:29-30` ✓.
- 统计表 7 列 (龟/出伤/受伤/治疗/暴击/击杀/剩余) 列偏移 -360/-240/-150/-60/40/110/220, 表头13px, 分隔线780×1@headY+16, rowH28, 阵亡灰+"(阵亡)", 稀有度角标@-38 — Phaser `:226-267` ↔ Godot `:114-146` ✓.
- 按钮 220×50 @ height-90, 双按钮 cx∓130, 深海非末关 "选奖励→第N关" — Phaser `:174-198` ↔ Godot `:101-108` ✓ (PoC delayedCall 600 后建, Godot 直接建 → **迁移差异**).
- 背景: 相机底 #0a1726 + menu-bg 废墟图 + 0.7 黑遮罩 (此场景**唯一**真用 menu-bg.png) — Phaser `:77-84` ↔ Godot `:58-74` ✓.

---

## 4. 成就 Achievements

**结论**: 4 类 Tab + 3 列卡片网格 + 解锁态着色 + 数据 1:1, 布局常量逐值对齐, 无显著缺失. 唯一差异是 PoC 用手动 wheel 滚 + 几何 mask, Godot 用 ScrollContainer (合理迁移差异).

### 核对
- Tab 4 类 battle/collect/progress/special + 中文标签, 130×36 间隔 140, active 0xffd93d — Phaser `:8-10,37-50` ↔ Godot `:5,33-36,81-92` ✓.
- 标题 "🏆 成就 N/M" 36px stroke#1a1a2e 厚5 @ (W/2,50) — Phaser `:29` ↔ Godot `:25-29` ✓.
- 网格 gridX60 gridY170 gridW=W-120 gridH=H-200, 边#58d3ff@0.4 — Phaser `:53-55` ↔ Godot `:42-52` ✓.
- 卡片 3 列 360×100 gapX/Y 14, 解锁 alpha0.95 边#ffd93d / 未解锁 0.5 边#666 — Phaser `:64-76` ↔ Godot `:60-63,115-123` ✓.
- 卡内: emoji40@(-W/2+28) (未解锁 a0.3), 名16(-22), desc12(8) wrap(W-100), reward "🪙N"@(W/2-12,-H/2+14), "✓已解锁" 11px#06d6a0@(W/2-12,H/2-14) — Phaser `:79-108` ↔ Godot `:133-183` ✓.
- 返回 icon r18 黑0.55 边#58d3ff→hover#ffd93d — Phaser `:123` ↔ Godot `:199` ✓.
- 滚动: Phaser wheel 手动 + 几何 mask (`:117`) ↔ Godot ScrollContainer (`:55-59`) → **迁移差异 (合理)**.
- 数据源: Phaser `ACHIEVEMENTS`/`tracker.getUnlocked()` ↔ Godot `DataRegistry.achievements`/`GameState.achievements_unlocked` ✓.

---

## 5. 战绩 Record

**结论**: 总览卡 (总场/胜/负/胜率) + 最近 20 场列表 (结果/头像/模式/回合/相对时间) 数据与布局 1:1, 无显著缺失. PoC 用 DOM innerHTML, Godot 用 Container 树, 视觉等价.

### 核对
- 标题 "📊 战绩" 36px stroke 厚5 @(W/2,50) + 返回 icon — Phaser `:42-46` ↔ Godot `:16-23` ✓.
- 总览卡 bg rgba(20,32,40,.82) 边2px#2e4a5e 圆角12; 4 格 总场#fff/胜#06d6a0/负#ff6b6b/胜率#ffd93d, 数值30px+标签12px#9ab — Phaser `:49-61` ↔ Godot `:40-57,92-108` ✓.
- 胜率 = round(wins/battles×100) — Phaser `:39` ↔ Godot `:29` ✓.
- 列表标题 "最近对局 (N)" 13px#58d3ff, 最多 20, max-height430 滚动 — Phaser `:71-72` ↔ Godot `:60-70` ✓.
- 行: bg rgba(20,32,40,.7) 左边框4px (胜#06d6a0/负#ff5c5c) 圆角6; 胜/负15px宽30 + 头像34×34圆角6边#2e4a5e gap4 + 模式12px#9cf + 回合11px#778宽46 + 相对时间11px#667宽64 — Phaser `:80-98` ↔ Godot `:112-178` ✓.
- 相对时间 刚刚/分钟前/小时前/天前 阈值 60k/3.6M/86.4M — Phaser `:15-21` ↔ Godot `:201-211` ✓.
- 模式标签 MODE_LABEL (pve/dungeon/custom/boss/boss-pick/test) — Phaser `:10-13` ↔ Godot `:5-6` ✓ (Godot 多 "single"→"野生" 别名, 合理).
- 空态 "还没有对局记录，去打一场吧！" 14px#789 — Phaser `:66` ↔ Godot `:79-85` ✓.
- 数据源 localStorage progress/match-history ↔ GameState.battles_total/won/match_history ✓.

---

## 6. 设置 Settings

**结论**: BGM/SFX 滑条 + 全屏 + 低画质 + 重置存档 + 底部提示 布局 1:1, 行为基本对齐. 差异: **底部提示文案 "设置自动保存到 localStorage" 在 Godot 语义错** (Godot 存的是 user:// 不是 localStorage, 属字面照搬); **低画质模式 Godot 是纯摆设** (无 backdrop-filter, 仅切 label, 代码自承); 全屏走 DisplayServer 而非 DOM (合理引擎差异).

### 核对 / 差异
- 标题 "设置" 40px stroke厚5 @(W/2,80) + 返回 icon — Phaser `:40-45` ↔ Godot `:17-21` ✓.
- BGM 滑条 @(W/2,220) init=bgmVol, SFX 滑条 @(W/2,330) init=sfxVol + 即时播放 demo — Phaser `:48-61` ↔ Godot `:24-28` ✓ (SFX demo: PoC `sfx-hit`, Godot `hit_physical` — 合理映射).
- 滑条 track w380 h8 #444 + fill#ffd93d + handle r14#ffd93d + 百分比 monospace#ffd93d + 点轨道跳 — Phaser `:94-128` ↔ Godot `:86-140` ✓.
- 全屏按钮 @(W/2,410) 文案 "⛶ 退出全屏"/"⛶ 全屏" — Phaser `:64` (DOM fullscreen) ↔ Godot `:31,45-49` (DisplayServer window mode) → **迁移差异 (合理)**.
- 低画质 @(W/2,490) "🪶 低画质模式: 开(流畅)/关(高画质)" — Phaser `:70-75` 真切 `setPerfLite` 关 backdrop blur. Godot `:33-35,52-62` **仅切 label, 无实际效果** (无 backdrop-filter 概念, 代码注释自承) → **行为不同 (功能空转)**.
- 重置存档 @(W/2,580) + "✓ 存档已清空" alpha tween 200ms hold1500 — Phaser `:78-87` ↔ Godot `:38,72-82` ✓ (PoC 清 4 个 localStorage key, Godot `GameState.reset_save()` — 合理映射).
- 底部提示 @(W/2,H-40) 11px#888 "设置自动保存到 localStorage" — Phaser `:89` ↔ Godot `:41-42` → **文案语义错 (小)**: Godot 不用 localStorage, 字面照搬误导.
- 按钮 btn-frame 260×50 18px#3a1f00 stroke#ffe4a0 hover1.05/press0.96 — Phaser `:131-152` ↔ Godot `:154-198` ✓.
- PoC `getStoredVolumes` 导出供别处读音量 — 数据存 GameState, 迁移等价.

---

## 汇总: 最严重问题 (按影响)

1. [部分修✓技能+被动drill-down弹窗] **[Codex] 三类详情 drill-down** (单技能详情 / 被动展开 / 双形态切换) — 玩家点技能卡/被动条无反应, 看不到完整 detail 文本, 双形态龟第二套技能不可见. (CodexScene.gd:432 起)
2. **[Codex] 规则 Tab "小商店物品池" 整块缺失** — 价格/每格稀有度分布/增益池清单 (v0.9.9 经济规格) 在 Godot 图鉴完全没有.
3. **[MainMenu] 教程磁贴 = 空函数 (`func(): pass`)** + 全屏询问弹窗 + 4 步新手引导 全缺 — 新玩家无任何引导路径.
4. **[MainMenu] DEV gate 反了** — "测试模式" 在 Godot 正式构建恒显示 (PoC 仅 ?dev=1); "快速单体调试" 整缺.
5. **[BattleEnd] 自创了胜利掉装备 + 平局分支** (PoC 无), 同时缺成就结算 toast / best.turn&dmg 统计 — 与 PoC 经济/成就行为不一致.

次要: Codex 等级系统未接(恒 Lv1)/技能锁缺/装备数值预览缺/羁绊"拥有此羁绊的龟"列表缺; MainMenu 联机按钮点击无 toast 反馈 + 返回母站链接缺 + 整页过场简化; Settings 低画质空转 + 底部 "localStorage" 文案语义错. Achievements / Record 两场景 1:1 良好, 无显著缺失.
