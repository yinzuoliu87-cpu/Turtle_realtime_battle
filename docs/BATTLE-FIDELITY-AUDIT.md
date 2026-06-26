# 战斗场景 1:1 保真审计 (2026-06-02, 6-agent cited)

PoC 权威源 = `games/turtle-battle-poc/src/`. Godot = `scripts/scenes/BattleScene.gd`.
每条都引了 Phaser 行号; 修前我逐条回源核验. 一条一 commit, 每修跑 336 测.

## 教训 (为什么之前没发现)
战斗是 ~15 个 Phaser 模块拼的 (DmgStatsPanel/DetailPanel/BattleStatsRail/turtle-hud/BattleTopRow...),
我建成单石 5400 行从没逐模块核对覆盖 → 整模块缺失我都不知道. 静态截图+逻辑单测结构上测不到
布局/交互/节奏. 防错法 = 逐模块 cited 双向 diff, agent 跑广度我回源核验.

## 修复清单 (按用户影响 × 我的把握 排序)

- [x] **F1 左侧塞满** — `_collect_bench_equips`(:5183) 返回全部 `_equipped_ids`(已穿装备) → rail 塞满金格.
  PoC bench = 未装备后备库存(benchInventory, 战斗中≈空, BenchRail.ts:182-183/311). Godot 开局全自动上身无后备 → 应返回 []. rail 渲染成空暗框=1:1.
- [x] **F2 血条敌我色 + 删自创变色** — Godot 自创"按血量红/黄/绿"(:4342-4348) + 全绿初始(:544). PoC 固定双色按敌我: 我方绿 #3deb9e/#1fb57f, 敌方**紫** #c084fc/#9d5be8 (scene-turtle-dom.ts:466-468/turtle-hud.ts:64-65), 从不按血量变色. 受击 trail 应红 #ff4d4d(:536 现灰).
- [x] **F3 伤害统计面板缺失** — 📊按钮(:4456)错接 `_on_log_toggle`. 需新建 DmgStatsPanel 等价 Control: top56 left12 w540, 4 tab(造成/承受/治疗/护盾) × 双列(我方/敌方) × stacked bar(红phys/蓝magic/白true). 数据层 battle_stats.gd 已 1:1 就绪(by_side). 过滤 isNeutral. 规格见 DmgStatsPanel.ts:26-229.
- [x] **F4 点龟无面板** — fighter view(Node2D)完全没接点击, 且无 DetailPanel 文件. PoC: sprite.setInteractive→showFighterDetail→DetailPanel.show(f,isAlly) (BattleScene.ts:1935-1939/3602-3614). 需: 给 `_make_slot_view` root 套 Control/Area2D 接点击(防 emulate_touch 坑, 用 InputEventMouseButton.pressed&&LEFT) + 新建 DetailPanel(920×540: header头像/Lv/名/羁绊tag/HP条 + 属性列 + 状态列 + 10装备格 + 技能tile + veil关闭+穿透防护). 规格 DetailPanel.ts.
- [x] **F5 出伤节奏** (announce+600 + turn-delay 400; AI额外500/DoT节奏=次级未做) — 主因: PoC 每次出手前 `showSkillAnnounce + 600ms`(BattleScene.ts:3367-3368/5126-5127), Godot `_take_turn`(:2377)直接进 windup 无前摇无横幅. 另: 回合后停 PoC endTurn 400ms(:8163) vs Godot TURN_DELAY_MS=600(:20,695); 敌AI出手前 PoC 500ms(:2348) Godot 无; DoT结算 PoC 600 vs Godot 200-300. hop曲线+站位布局已1:1.

## 次级 (高保真细节, 时间够再做)
- [x] **F6 血条深层 = 完整 1:1 重写**: 新建 HpBar(_draw) 复刻 turtle-hud — 88×5玻璃管(投影/粗黑框/暗红槽/顶高光底暗线) + 逐行竖向渐变 + 100·500刻度 + 多段盾(白普/金气场/青泡/紫海葵) + 受击红trail(hold200收500)/60ms白闪/横抖. 截图验静态(渐变+刻度)+动态(红trail).
- [~] F7 顶部行(部分): ✓规则徽章(返回键右侧药丸, F5可见非normal规则时); 余: 回合轨道timeline / 出手倒计时条.
- [x] F8 战斗日志封顶200段 (已修, 每回合trim最旧).
- [ ] F9 站位: 非16:9窗口 PoC 重算可见区(:818 resize), Godot 锁1280×720不重算(潜在, 非当前bug).
- [x] **F10 战斗龟头状态图标行** — 战斗中龟头上没有 buff/debuff 持续图标(中毒/眩晕/护盾/增益等), 只有一闪而过飘字 → 看不到谁带啥状态. PoC turtle-hud 交 statusGroup 渲染(13种 + chip). **数据已备**: `fighters[].buffs`=[{type,value,duration}]; 图标=`assets/sprites/status/<type>-icon.png`(burn/poison/bleed/chilled/dodge/counter...已在). **建前必读 PoC statusGroup/状态选择逻辑**(哪些buff显示·图标映射·层数/时长显示)别自创. 按 HpBar 那套做 StatusRow(_draw或Control行) + makeView建 + _refresh_slot调update.

## 分辨率 / 字体 (2026-06-03 用户问, 实测核验)
- ✅ 分辨率缩放**确实工作**: 实测 resize 窗口→1920×1080, `root.get_final_transform()` scale=**1.5×**(content_scale_mode=1 canvas_items, aspect=1 keep, resizable=true, 运行时核过). 用户"放大窗口没变化"=Godot4.5+编辑器默认嵌入游戏窗口(底部面板不缩放) → F11全屏/浮动窗口/导出版正常. **非bug, 别改 project.godot**.
- ✅ 主菜单字体 1:1: default_theme.tres = m6x11像素打底 + SystemFont CJK回退(微软雅黑/苹方/Noto), 同 PoC 字体栈.

## G 组 — 其他场景审计 (2026-06-02 第二轮 agent: TeamSelect/Shop/闯关流程)
- [ ] **G1 战中商店经济未驱动 [高/需用户定]** — `on_battle_turn_economy()`(1:1 PoC +10/turn+利息) 全工程**只测试调用, 回合循环从不调** → 玩家每回合不进币 → 商店买不起.
  **但** Godot `coins` 是持久钱包不per-battle重置(GameState.gd:82 文档化故意选择), PoC `this.coins` 局内钱包每场重置成 `_carryCoins`(BattleScene.ts:653). 盲接 +10/turn 进持久钱包会币跨场无限涨破坏平衡 → **需用户定** 接经济+改局内重置 vs 保持. 没盲改.
- [ ] **G2 野生敌AI购物未接线 [中]** — `plan_ai_shop`(1:1) 无调用方; `ai_gain_coins` 因 G1 也不触发 → 敌方永不买. 依赖 G1.
- [x] **G3 pve 规则之日 modal** — 选龟确认后 PoC 弹7卡+🎲规则(TeamSelectScene.ts:2008), Godot 从不弹 → `battle_rule` 永空, 规则系统在 pve 从不触发.
- [x] **G4 RewardPick buff池 2项缺crit** — PoC `速攻训练`(atk+8%&crit+10%)/`必胜信念`(crit+5%&atk+5%) 双加成, Godot 换单 `精钢之刃`(atk+8%) 丢crit. (待核 dungeon_bonus 是否支持双效果)
- [~] **G5 Dungeon 缺4信息块**(部分: ✓累积加成chip; 余 装备席chip/死龟✕复活/规则chip) — 累积加成chip/装备席chip/死龟✕+70%复活/整局规则chip (DungeonScene.ts). 纯显示.
- [ ] **G6 商店购买=自创自动指派** — `_shop_apply` 自动装最低血友; PoC 进bench玩家拖. 依赖 bench 拖拽系统(待专项).
- [ ] **G7 TeamSelect 槽交互简化 + 无等级系统** — drag&drop/tap-to-swap/点空槽activate 全缺(点满槽=直接删, 待bench专项); 等级系统缺(4/5技能永锁·属性不乘等级·Lv硬编码1)·owned过滤·sort下拉·mode-guide条 同根"无petState存档", 系统性后补.
- [x] **G8 商店重投费跨场不重置** — `_shop_reroll_cost` 不在每次开店重置回2 (PoC 每次open重置). 已修.

## 已确认 OK (非自创/已对齐, 勿动)
站位坐标/scale/脚底锚/画家序/朝向例外全1:1; 回合横幅1:1; 命中震屏阈值0.12对; 声音/术语面板1:1;
hop 1200ms/6帧/smoothstep/400ms命中同步1:1; HP数字文本(自创已隐藏)合规; battle_stats数据层1:1.
