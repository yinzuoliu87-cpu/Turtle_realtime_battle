# 菜单/经济/现有场景补全 规格 (2-agent 抠 Phaser, 1:1 关键数据)

## Settings (SettingsScene.ts)
- 标题"设置"40px#ffd93d@(w/2,80); 返回←@(40,40). BGM标签@(w/2-190,190)+滑条380×8@(w/2,220)(轨#444/填#ffd93d/滑块28圆); SFX同@300/330. 全屏按钮@(w/2,410)260×50; 低画质@490; 重置存档@580; 成功提示✓ 16px#06d6a0.
- 存档键 turtle-poc-settings-v1 {bgmVol:0.4, sfxVol:0.6}. 重置删 team/progress/dungeon-best/tutorial-seen.
- Godot: 用 Audio autoload 音量 + GameState.reset_save. 滑条 HSlider.

## Achievements (achievements.ts) — 50项4类
- 标题"🏆 成就 N/50"36px@(w/2,50); 4Tab@110y(battle战斗/collect收集/progress进度/special特殊)130×36; 3列卡360×100; 解锁亮+✓绿/未解锁半透.
- 存档: turtle-poc-ach-unlocked-v1 [id...], turtle-poc-ach-stats-v1 {battles,wins,crits,totalDmg,...}.
- **战斗12**: first_win初战告捷(20)/win_10老兵(50)/win_50战神(200)/win_100不败传说(500)/battle_3热身(10)/battle_25熟手(80)/crit_100致命瞬间(50)/dmg_5k_battle高输出(60)/dmg_10k_battle怒火(120)/kills_5_battle收割者(40)/no_loss_battle完美防守(80)/one_turn_ko速战速决(100)
- **收集10**: first_equip初次装备(15)/equip_5小有家底(30)/equip_25收藏家(100)/try_5_pets尝鲜(20)/try_15_pets老朋友(80)/try_28_pets驯龟师(300)/coins_500小富翁(30)/coins_5000富豪(200)/shop_buy深海购物(15)/rare_equip神品入手(50)
- **进度10**: dungeon_1初入深海(20)/dungeon_2继续深入(30)/dungeon_3中流砥柱(50)/dungeon_4深渊回响(80)/dungeon_5征服BOSS(200)/dungeon_perfect完美通关(500)/codex_open翻阅图鉴(10)/tutorial_done入门完成(10)/custom_battle自定挑战(20)/all_rules通晓规则(100)
- **特殊18**: synergy_x2羁绊(20)/synergy_x3极致羁绊(60)/thorns_kill荆棘致命(40)/lifesteal_full生命汲取(30)/shield_break破甲(40)/burn_kill火葬(30)/curse_kill诅咒收割(40)/stun_3麻痹大师(30)/fireball_kill炎爆(25)/chain_kill_3雷链(25)/heal_aura_full光环治疗(30)/low_hp_win绝处逢生(100)/no_skill_win只用普攻(50)/turn_50持久战(80)/six_alive全员归来(150)/rebirth凤凰涅槃(50)/equip_4_one_pet武装到牙齿(60)/all_classes万能(80)

## Record (match-history.ts)
- 标题"📊 战绩"36px@(w/2,50); 总览卡760宽@100y 4列(总场/胜#06d6a0/负#ff6b6b/胜率#ffd93d 各30px); 列表最近20场36px行(胜绿左边框/负红, 头像34×34, 模式#9cf, 回合, 相对时间).
- 存档: turtle-poc-progress-v1{battles,wins}, turtle-poc-matches-v1 MatchRecord[]{result,lineup[],mode,turn,ts} 封顶50最新在前.
- 模式标签: pve野生/dungeon深海闯关/custom自定义/boss-pick指定Boss/test测试. 相对时间: <1min刚刚/<1h X分钟前/<1d X小时前/else X天前.

## Shop (ShopOverlay.ts / shop-quick.ts) — 战中3回合(turn4/8/12)
- 全屏rgba(8,12,20,.82)blur5; 面板min(94vw,1040)×min(78vh,560) border#78aaff; 头部"🛒小商店"17px#ffd93d+龟币#aef0ff+倒计时⏳(红<10s); 3列商品卡 bg rgba(20,30,45,.7); 购买按钮渐变#58a6ff→#2d6fce; 跳过按钮100%宽.
- 基准价 buff16/consumable24/normal32/unique41; price=基准×1.25^shopIndex×(0.9~1.1). 重投费2→+1递增. 财富羁绊tier3 -25%.
- 倒计时30s. 稀有度边框 normal灰/unique金glow/consumable青/buff绿/reroll紫.
- **12增益BUFF_POOL**: q_blade锋利之刃(全队atkUp10/3T)/q_shield灵龟之盾(defUp15/3T)/q_lifesteal嗜血药剂(lifesteal15/3T)/q_swift疾风之策(cdDown1/1T)/q_hawk鹰眼(critUp15/2T)/q_critdmg致命一击(critDmgUp25/2T)/q_dodge闪避之灵(dodge10/2T)/q_rage怒火药水(单龟atkUp baseAtk×25%/3T)/q_emergency应急护盾(单龟+80盾)/q_firstaid急救包(单龟+maxHp×15%)/q_cleanse净化(单龟移除debuff)/q_mark必中标记(敌单markedDmg20/2T). 装备池=EQUIP_POOL按category筛.

## MainMenu (MainMenuScene.ts) — 设计台1280×720
- 2级菜单: 主(在线/本地/设置) → 本地子(深海闯关/自定义) → 自定义子(野生pve/指定Boss boss-pick/[DEV]测试test/[DEV]快速单体调试solo).
- 标题@(240,130)360×203 scale1.1; 主按钮组中心x=240 cy=324, 按钮360×87 间距12, 从左-560滑入(delay550+80i cubic.out); 右栏龟币框@(w-16-76,78)152宽 + 4磁贴@x=w-WALL 竖排y=190/310/430/550 各104²(图鉴codex/教程tutorial/成就ach/战绩record) 从右+560滑入(delay850+60i).
- 子菜单整页过场: flyOut(自下230ms cubic.in alpha0) + flyIn(下+160 320ms back.out).
- 快速单体调试: DOM浮层选龟+5选3 → Battle(mode=test, leftTeam=[1龟], slots=[front-1]).

## TeamSelect (TeamSelectScene.ts) — 设计台1647×955 zoom1.17 offsetY76
- regionLayout: title(587,76,330,30)/back(431,76,96,36)/clear(1021,79,78,29)/last(1109,79,94,29)/synergy(183,114,407,262)/slot0-5(y174,h156, x=455/582/707/842/962/1082 前3后3)/frontLabel(591,121)/backLabel(973,121)/grid(160,375,1050,403)/detailTop(1250,136,230,293)/detailBottom(1255,431,214,262)/start(1255,714,214,68).
- **技能5选3锁定**: idx0-2永开, idx3需Lv4, idx4需Lv7. skillUnlockLevel(i)=i<=2?1:(i==3?4:7). loadout存 turtle-poc-loadout-v1 {petId:[3idx]}. 默认[0,1,2]★绿框.
- **羁绊预览**: picked≥2 → calcActiveSynergies(picked.tags) 按tier降序, 图标+×数 hover显tier2/3效果.
- 属性条量化 divisor: HP40/ATK5/DEF2.5/MR2.5. 确认按钮文字 placed0"请选3只龟"/1-2"还需选N只"/3"⚔开始冒险".
- 双形态龟: meleeSkills/volcanoSkills 配对, Panel显"近战形态/火山形态".

## Codex (CodexScene.ts) — 5Tab
- Tab: 龟/装备/羁绊/状态/规则, tabW170 gap8 居中@y; 左列表280×405(白边蓝描) + 右详情920×405(黄描); wheel滚动.
- 龟详情: 立绘170² + 名"Lv N. 名字"32px黄 + 稀有度标签 + tag图标×4(50×60) + 4属性行(icon+label+value黄24+方格条 divisor40/5/2.5/2.5) + 被动chip(bg#12202a边#58d3ff h50 "被动·名 点击查看▸") + 技能5卡168×260(default绿/locked灰+Lv.N/normal蓝) / 单技能详情 / 被动详情. 双形态切换按钮.
- 装备Tab: category分组(unique/special/normal/chest/consumable)色边+图标32+名; 详情大图120+category chip+desc(':' 加粗蓝/'※'灰斜)+数值preview(regex扫apply源码). CAT_COLOR/CAT_LABEL.
- 羁绊Tab: SYNERGY_TAGS列表 标签PNG+名; 详情大标签+tier2/3两列+拥有龟网格(10列).
- 状态Tab: category分组(dot/cc/buff/debuff)icon+名; 详情大icon100+category+desc. (DataRegistry.status_defs)
- 规则Tab: BATTLE_RULES列表(原作详情缺). (DataRegistry.battle_rules)
- 数据源: DataRegistry.all_equipment / synergies(synergies.gd SYNERGY_TAGS) / status_defs / battle_rules 均已加载.
