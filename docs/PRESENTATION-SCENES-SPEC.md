# 表现层 + 场景流程 迁移规格 (2-agent 抠 Phaser 源, 1:1)

> 本文件是后续表现层/场景迁移的权威参照。所有坐标/数值/公式均 1:1 抽自 Phaser PoC, 不自创。

## A. 战斗表现层

### A1. 状态徽章
- PoC 用户已选: 头顶徽章**已删**, buff/debuff 全在详情面板。Godot **不做头顶徽章** (refreshStatusIcons 空操作)。

### A2. 回合横幅 (showCenterBanner / showSideTurnBanner)
- **中央横幅**: 屏幕中央, 主文 36px #ffd93d (font-weight 900, 字间距6px, 阴影 0 0 14px 金), 副文 14px #cdd。动画 0.9s: translateX(-30%)→0→+30% + opacity 0→1→1→0; 显示 durationMs 后 260ms 淡出。
  - 第N回合: "第 N 回合"/"Round N", 1100ms, #ffd93d
  - 回合3/6/9/12: "⚠ 第N回合·事件来袭"/"Event Round", 1400ms, #ffb01f
  - 回合4/8/12: "🛒 第N回合·商店"/"Shop Round", 1300ms, #7ec8ff
  - 回合1: "第N关", 1500ms, #ffd93d (闯关)
- **侧横幅 showSideTurnBanner** (beginSideTurn 每次切边): 左队"🐢 我方回合"从x=-260→width×0.30, 右队"👹 敌方回合"从width+260→width×0.70, y=height×0.30。30px白字黑描边4px, 背景#0a0e18@82% 边框3px(左绿#06d6a0/右红#ff6b6b)。入场280ms(Back.easeOut)+hold500ms+退场240ms(Cubic.easeIn)。

### A3. 飘字三色堆叠 (visual_dispatcher.ts) — 当前 Godot 全堆一起, 要修
- **FLOAT_STYLE**: phys-dmg #ff4444/22px, magic-dmg #4dabf7/22, true-dmg #fff/22, crit-* 同色/26px, heal #06d6a0/24, shield #fff/22, dot-dmg #4dabf7/18, dot-bleed #ff4444/18, counter-dmg #ffd93d/20, passive-num #7dffb3/16, debuff-label #ff9f43/14, dodge/miss #a0e8ff/16。
- **字号按数值**: <20→20px; 20-60→20+(a-20)/40×4; 60-400→24+(a-60)/340×11; ≥400→35px; 暴击×1.2。
- **三色固定行** (FLOAT_ROW_BY_CLS): 红phys=row0(最下), 蓝magic=row1, 白true/pierce=row2(最上)。非伤害: 盾/疗/泡=row3, dot/闪避=row4。ROW_HEIGHT=22px。
- **压缩堆叠**: bucket=round(x/40)|round(y/40); 窗口 DMG_STACK_WINDOW_MS=220ms 内同bucket的rank收集排序, yOffset=排序索引×22 (红蓝白紧凑叠)。非三色 STACK_WINDOW_MS=100ms 按到达顺序 count×22, 600ms后-1。
- **动画**: pop 50ms(scale0→1.6-2.5x按amount) + shrink 100ms(→holdScale 普通0.7/暴击1.0) + hold(暴击250ms/普通0) + flight 650ms(抛物线, 垂直初速普通-(22+r×10)/暴击-(10+r×8), 水平按屏幕侧±(12+r×14), gravity200) + fade末350ms。总 普通800/暴击1050ms。pool max 24。

### A4. VFX (资源已拷 assets/sprites/vfx/, .png+.json Aseprite格式)
- spritesheet 帧布局: bamboo-charge-orb 1024×128/8帧/100ms/128². burn-loop 1024×128/8帧. basic-slam-impact 1152×128/9帧. 其余自查 json。
- 灼烧overlay syncBurnOverlay: vfx-burn-loop 128² 8帧循环(800ms), SCREEN混合, depth=sprite+1, 跟随sprite.xy, burn buff有则显。
- 技能VFX映射: basicSlam→slam-impact, basicChiWave→chiwave, basicBarrage→barrage-bolt, bambooCharge→orb(650ms抛物)+burst, hunter→arrow(512×128飞行旋转), 自绘类: castCrystalBeam(红260ms→蓝350ms光束), drawLightningBolt(7段锯齿+噪声±26, 三层笔画, 70ms后220ms淡出), launchWaveSweep(wave-sweep 220×110, x=-120→width+120, 2000ms)。

## B. 场景流程 (BattleEnd/Dungeon/Reward/Choice/BossPick)

### B0. 导航全图
MainMenu →(mode) TeamSelect →(pve)Battle→BattleEnd→再战/菜单
 →(boss-pick)Battle前插 BossPick →Battle→BattleEnd
 →(dungeon) DungeonScene(stage1)→Battle→BattleEnd→(胜非末)RewardPick→(50%)ChoiceEvent→DungeonScene(stage+1)→… (胜末关stage5)→菜单 / (负)再战或菜单

### B1. BattleEndScene (BattleEndScene.ts:1-294)
- 入参: result, playerStats[]{id,name,rarity,alive,hp,maxHp,dmgDealt,dmgTaken,healDone,crits,kills}, turn, leftTeam, mode, rule, dungeonStage, playerHpSnapshot, benchInventoryIds, coins
- 布局(1920×1080): 背景menu-bg+黑0.7; 标题88px(胜#ffd93d/负#ff5050, scale0→1); 副标题160y 16px#aaa "{turn}回合·{rule}"; 表头240y 7列(龟-360/出伤-240/受伤-150/治疗-60/暴击40/击杀110/剩余HP220, 13px#ffd93d); 分隔线256y; 数据行268+i×28(存活#fff/阵亡#888); 龟币奖励 height-180 28px#ffd93d "🪙+{reward}", 副 height-148 12px#888; 按钮 height-90 220×50 文#3a1f00描#ffe4a0。
- **龟币公式**: 胜=50+floor(totalDmg/100), 负=10。
- 逻辑: isDungeon=mode==dungeon&&stage>0; isLast=stage==5; runEnded=!isDungeon||!isWin||isLast; runWon=isWin&&(!isDungeon||isLast)。深海中途胜不计battles/wins只累coins。
- 按钮路由: dungeon胜非末→[选奖励→第stage+1关→RewardPick, 主菜单]; dungeon胜末→[🏆通关→菜单]; 其它→[再战→Battle, 主菜单]。
- 存档(progress): coins+=reward; battles++/wins++仅runEnded/runWon; best{turn,dmg}; dungeon_best=max。

### B2. DungeonScene (DungeonScene.ts:1-382)
- **难度倍率 DUNGEON_STAGES**: 关1=0.85/0.85/0.85, 关2=1.0/1.0/1.0, 关3=1.1/1.1/1.1, 关4=1.2/1.2/1.2, 关5BOSS=3.0hp/1.25atk/1.4def, 敌数 非boss3/boss1。
- 敌pool: cfg.pool空→ALL_PETS排除玩家阵容; shuffle取enemyCount。
- HP继承: alive龟下关回满maxHp; 死龟下关 maxHp×70%复活 alive=true。snapshot含 equipIds+growth。
- 布局: 标题40px#ffd93d@50y; 进度条600×40@110y 5段(已过#4ade80/当前#ffd93d/曾过#c77dff/未过#444, 末关未过#8b1a1a); 难度芯片3段(HP/ATK/DEF, ×值<1.1#aaa/1.1-2#ffd93d/≥2#ff6b6b); 阵容预览 我方480/敌方1440 龟卡64²; 开始按钮 240×56。

### B3. RewardPickScene (RewardPickScene.ts:1-255) — 闯关3选1
- TeamBonus{kind:'atk'|'hp'|'crit'|'lifesteal'|'shield'|'equip'|'heal', value?, equipId?}
- 卡片×3: 480/960/1440 @540y, 280×360, emoji64px@-110 + 标题24px#ffd93d@-30 + 描述14px@20 + "点击选择"13px#aaa; 边框3px(r.color/hover#ffd93d 4px), hover scale1.04@120ms。
- **12 buff**: 锋利之刃atk+10%, 霸者之握atk+15%, 坚韧之躯hp+50, 生命之力hp+100, 致命直觉crit+25%, 精准之眼crit+15%, 血液链接lifesteal+20%, 深海护甲shield+30, 钢铁护壁shield+60, 速攻训练atk+8%&crit+10%, 生命偷取图腾lifesteal+8%, 必胜信念crit+5%&killbonus+5%atk, 强者勋章hp+50。治疗"潮汐治愈"满血+30盾。
- 装备子选(modal): EQUIP_POOL排consumable/chest随机3, 720×320面板, 跳过→atk+6%。
- 导航: nextStage∈{2,4}且random<0.5→ChoiceEventScene 否则DungeonScene。

### B4. ChoiceEventScene (ChoiceEventScene.ts:1-209) — 50%触发
- 随机选 CHOICE_EVENTS 之一。卡片排一行 280×200, 标题22px#ffd93d + 描述14px + 边框(opt.color/hover#ffd93d)。
- **神龛shrine**: 献祭血肉(hp-50,atk+25%)/神圣加持(hp+50,crit+10%)/虔诚之心(shield+30,lifesteal+5%)/离开。
- **神秘商人merchant**: 稀有装备(equip __unique_random__)/赌博(50%装备/50%无)/离开。
- 导航→DungeonScene(stage=nextStage)。

### B5. BossPickScene (BossPickScene.ts:1-132)
- 标题42px#ffd93d "指定Boss"; 副"选1只龟成为Boss(3.5×HP/1.2×ATK/1.4×DEF·MR)"; 网格7列, 单卡140², 龟图72² + 名13px + 稀有度角标; 候选=ALL_PETS排玩家3龟; hover scale1.06。
- **Boss倍率**: 3.5hp/1.2atk/1.4def。→Battle(mode=boss-pick, bossId)。

### B6. GameState 需补字段
- dungeon_bonuses:Array / dungeon_bench_inventory:Array / dungeon_rule:String
- dungeon_carry 扩展为完整快照(hp/maxHp/shield/alive/position/equipIds/growth) 或拆分字典
