# PoC 保真度全量审计 (2026-06-09, 用户要求"每处都与 PoC 一致")

标准: Godot 必须与 `games/turtle-battle-poc/` 行为+像素 1:1。每条带 PoC + Godot 出处。
状态: ✅已修 / 🔧部分 / 🔴待做 / ✓核实1:1(无需动). **可见/交互项标"需F5"=逻辑改了但屏幕得用户验.**

---
## 🚨 用户F5报8项问题 逐个修 (2026-06-11) — 5 commit, 1021测过, 多项需F5/高分屏验
**方法**: agent备料(团队选/背景/动作面板/流程4路) 但**逐条核源码**改正agent误报(背景off-screen误算/初始装备误报). 引PoC行号.
1. **图鉴每只龟数值不对** ✅真bug: CodexScene 硬编 `RARITY_MULT={S:1.5,SS:1.75,SSS:2.0}` = 自创错值(应=rarity-mult.json {S:1.09…}, 同 fighter.gd:127+PoC pets.ts) → 全图鉴 stat/技能数虚高且≠实战. 改用 `DataRegistry.rarity_mult`; `_ctx_for` 补等级加成+真实lv(1:1 petToCtx). 水晶 atk 66→48.
2. **点龟/装备卡一下** ✅: PreloadCache 原只warm头像/技能图标 → 图鉴详情 load 全身大sheet(pets/*.png 500²×11帧)+装备120px图 冷加载卡帧. 补warm: 全身立绘+装备图标+羁绊标签+stat图标.
3. **很多地方技能没有框** ✅: 图鉴技能卡图标原裸图 → 补金框socket(深底+金边2px radius8, 1:1 skillIconHtml).
4. **选龟列表布局/5. 右信息区位置不同** 🔧: agent核 regionLayout 实1:1(116²卡/7列/区域坐标全对); 感知"不同"主因=背景木板下移(content跟着移). 随#6一并修. 余 filter渐变/locked灰度/hover位移=need-art/shader/polish, 需F5指具体.
6. **背景木板下移** 🔧真bug: PoC oy=76=translate真实px(scale后); Godot canvas_items stretch下 STAGE_OFFSET 被content-scale放大→高分屏多下移. 修 _stage_to_screen 偏移×(逻辑/真实)折算→渲染恰76真实px(720p=原值不回归). **需高分屏F5验**. (agent报木板off-screen=漏算+size/2误判, 实际中心一直=vp中心+76正确.)
7. **施法面板有问题** 🔧部分: 冷却行 10px#8899aa→11px#aaa@.7(ActionPanel.ts:338). 余 panel/卡渐变底+disabled grayscale=need-art/shader; 选靶取消已有右键/Esc+提示(缺可点"返回"钮=小polish). **"问题"具体待F5指**.
8. **技能放完跳场景timing压根没对** ✅真bug: _show_result 原 BGM(0.5)+立即change_scene→砍最后一击演出. 改1:1 PoC endBattle(:8650): 隐操作面板+BGM 0.6淡出+等600ms再切+多入口守卫.
**结论**: 1/2/3/8=确诊真bug已修; 4/5/6=偏移放大连带, 已principled修需高分屏F5; 7=部分修余need-art. 渐变/grayscale/blur类一律need-art标F5.

## 🔬 图鉴+多面板逐元素1:1核对修 (2026-06-11, 用户"图鉴仔细核对感觉还有不一样"+"把清单都修完") — 6 commit, 1021测过, 视觉F5
**方法**: 读 PoC scenes/*.ts 完整源(CSS+render) vs Godot, 逐元素diff; agent备料但**逐条核源码**(剔除need-art渐变阴影 + 改正agent 3处误报). 全程引PoC行号.
- **图鉴 CodexScene** (3处真偏差): ①被动条点击 Godot弹modal(自创)→改**内联展开/收起**(1:1 view='passive' renderPassiveDetailSection:394/572)+hint"点击查看▸"↔"收起▾"金+选中黄边; 删死代码_show_codex_detail_modal ②技能详情内联**重排**(renderSkillDetailSection:532-568): 返回钮紫150→蓝#1a2740/#58d3ff 100×32@(70,296) · 标题行图标40+★默认绿+名**32px**金+CD20绿(原名22px多行) · 正文#ccc15→**#fff13** ③DetailBg/Detail 宽920(右距20)→**900(右距40对称)**.
- **伤害统计 DmgStatsPanel** (DmgStatsPanel.ts CSS): tab 13→14/圆角6→8/padding5·4→8·0/补1px边/inactive#c9d1d9→**#8b949e** · active补#8fc4ff边 · close20→**22** · ds-name13→**15**. (面板540宽=508+16×2 已对, agent误报)
- **规则选 _show_rule_pick_modal** (TeamSelectScene.ts:2008-2067): 标题补**🎯** · 金光shadow · 名14→**15** · 卡padding→L/R12·T/B14 · 随机钮"随机一个🎲"→**"🎲随机一个"**+紫底#2a1a40金边radius8居中 · 卡hover金边+scale1.04.
- **帮助 HelpPanel** (HelpPanel.ts): close16→**18** · img图标24→**20**(置24格). (19条help-item文案/网格2列 已1:1)
- **商店卡 _make_shop_card** (ShopOverlay.ts:128-168): 边2→**1px** · padding10→14/14/14/12 · 名15→**14** · desc minH40→**44** · 买钮补蓝底radius7白字13+disabled灰.
- **装备席 BenchRail** (BenchRail.ts:116-124): emoji28→**30** · 图标铺满52→**41居中**(content_margin5.5).
- **信息面板 装备格/技能tile/hint** (DetailPanel.ts) — **去自创绿/蓝配色**: 装备格单行HBox40→**5×2 Grid 62**金底 · 技能区标题绿→**金#ffd86b** · _detail_skill_tile socket绿/蓝→**统一金边64**/名11→**15**/被动标绿底→**纯紫#c77dff**/CD灰→**红#ff6b6b**/+角标黄→**绿#06d6a0黑边17** · hint12白.4→**10#666**.
- **核实无需改(agent误报)**: 羁绊chip ×N=20px(.tier非.tag44 emoji兜底) · 初始装备img=122(PoC cell134内img122 已对) · 信息面板header/属性/状态区(前轮已1:1).
- **余 need-art (StyleBoxFlat做不出, 标F5/美术)**: 各面板CSS linear-gradient底(伤害统计/tab active/商店买钮/羁绊金银chip/bench rail木纹)·backdrop blur·inset多层阴影·drop-shadow滤镜·立绘辉光2层composite·空装备格dashed边·初始装备radial glow/divider渐变线.

## 🤖 自主审计轮 (2026-06-11, 无人值守 ~每1h一轮, 本地Godot验证, 提交feat分支)
### 🏁 自主轮结束 (2026-06-11 ~09:20Z, 达用户设的09:04Z/+4h上限) — **不再 ScheduleWakeup, 彻底停**
**本会话共18轮**: 系统层7审(运气grant修, 余1:1) → 信息面板逐子区1:1(尺寸/border/稀有度/头部/左右栏/描述色) → 深海5项1:1核 → 7场景bg漂移bug → **视觉层自创清剿**(暴击+8飘字+窃取=10处 / 装备label措辞 / 死代码命中粒子 / 图片全对账agent扫=无错图) → 对局内等级徽章去自创边框+补bold → 倒计时条形状重建.
**余 backlog(待续/F5, 见下各段)**: 其它面板全部(结算/行动卡/商店卡/羁绊/装备席/状态栏/伤害统计/帮助设置/初始装备选/规则选/图鉴/选龟/主菜单) · boss模式视觉 · 装备特效(海浪e_wave) · 海盗船召唤(缺功能) · _sm小图标 · 图片位置分辨率 · 信息面板金框(需美术) · 倒计时渐变+脉冲(需美术) · **140技能完整出招编排**(最大) · 面板/动画自创对账复扫.
**全程**: 92提交全在 feat/godot-chest-treasure-variants(未动main/未push), 1021测全过. 视觉项均标"需F5"未claim已验.
### 🐌 切场景卡顿修复 (2026-06-11 用户报"进图鉴/其它页卡一下", 结束后追加)
- **病根**: 10个场景每次进入都 `load(menu-bg-tile 1946²).get_image().resize(512²,LANCZOS)` 在主线程, 几十ms → 每次切场景都卡帧.
- **修**: PreloadCache 加 `menu_bg_tile_tex()` 缓存缩放结果(resize只做一次, 启动warm时预付), 10场景(MainMenu/Codex/TeamSelect/Dungeon/ChoiceEvent/RewardPick/BossPick/Settings/Record/Achievements)改为复用缓存纹理, 不再各自重缩. 1021测过, 卡顿改善需F5.

### 轮1 ✅完成 (多段出伤节奏全覆盖, 已提交feat分支, 1021测过):
- coalesce路: gamblerBet=160 · chestSmash=400 · chestStorm=280 · diceAttack=400 · 万能牌=220 (hitStaggerMs, 均=PoC await sleep值).
- hunter_shot: 原聚合1飘字 → 改 _seg_push 真per-hit segments(240ms/段=PoC箭飞).
- 核实已正确(无需动): crystal_burst(_seg_push 500)/fortune_strike(300)/ghost_storm(500) 早用segments; _do_physical用seg_list(hitStaggerMs).
- **结论: 三路(seg_list/_seg_push/coalesce)覆盖全多段技能, 节奏均按PoC确切值.**
### 轮2 ✅完成:
- #13 场景切换卡顿: 新增 PreloadCache autoload 后台预热全立绘/技能图标/select-bg 缓存(1:1 PoC BootScene预载), 切场景不再冷加载卡帧.

### 轮3 ✅ 运气羁绊 grant 实装 (之前"只剩F5"结论下早了 — 系统层仍有真缺口)
- _synergyLuckGrantConsumable/Equip 在 synergies.gd set 但全项目无read端 → 运气羁绊"第1回合发物品"整效果失效. 补 _grant_luck_synergy(apply_team后): 发消耗品(t2)+装备(t3)到装备席+清flag. 1:1 PoC:6034.
- 核实其余羁绊effect全已实装(换形via apply_shift / 刺杀/元素/守护/财富/召唤/再生/物理/法术 数值=PoC synergies.ts逐项对).
- **教训: 系统层(羁绊/装备/buff/AI)仍可能有"set了flag从不read"类未实装, 继续审别只盯F5视觉.**
### 轮4: 装备系统审 = ✓无真缺口 (flag扫描假阳性已澄清)
- set-never-read 扫出 9 装备字段(_equipFpga/_equipAmplifier/_equipMiniCrystalB/Hourglass/LaserBlade/Dumbbell/Doll/chestRevive/chestRumPct)疑未实装, 逐个核**全是假阳性**: 这些装备效果 Godot 走 **eq_id 派发**(on_attach/on_turn_begin/on_hit 各 case 实装), `_equipXxx` flag 只是冗余状态记录, 效果正常(e_amplifier:657/e_fpga:665 4态/_dmgBonusThisTurnPct→damage.gd:82). **方法论: set-never-read 扫描只对"flag作唯一机制"的系统(如羁绊)有效; eq_id/type 派发的系统(装备/buff/dot)会假阳性, 需核派发端.**
- 运气羁绊(轮3)真缺口=因羁绊用flag唯一机制无eq_id替代.
### 轮5: buff/DoT 系统审 = ✓无缺口
- stats_recalc 处理全 stat buff: atkUp/atkDown · defUp/defDown(63行与armorBreak合并case) · mrUp/mrDown · critUp/critDmgUp · lifesteal · armorPen · chilled · chiWaveActive · diamondStructure — 覆盖完整.
- dot.gd tick 全 4 类 DoT (burn衰减1/3 / poison·bleed 1/4 / curse turns--) + burn免疫(_burnImmune/passive.burnImmune); 伤害公式 burn=value+maxHp×0.001×value 等.
- 特殊: fear(damage.gd:76 攻击者被恐惧→对来源物理/魔法-value%真伤不减) · healReduce(_heal_to) · dmgReduce(damage.gd) · dodge(rollDodge) 均应用.
### 轮6: AI 决策系统审 = ✓无缺口
- ai_pick(skill_handlers:3548) 与 PoC BattleScene.ts:2611-2705 逐项对: heal阈值0.4(hard0.35, normal恒0.4两边同) · shield<30 · 输出65%ult组/35%随机(按cd降序取top-cd组) · 没输出走第1ready技能.
- pet-specific 覆盖全在: starEnergy(满星才meteor/warp) · bubbleBurst(需bubbleStore>0) · hidingCommand/BuffSummon(需随从活) · phoenixPurify(队友有可净化debuff才用) · fortuneGold(3阶段经济AI). 1:1 PoC 2646-2705.
### 轮7: 商店系统审 = ✓无缺口
- shop_data.roll vs PoC shop-quick.ts rollShopItems 逐项对: SLOT_DIST 5槽稀有度分布完全相同(A buff40/cons25/normal20/unique15 … E 15/15/30/40) · price=BASE_PRICE[rarity]×1.25^shopIndex×(0.9+rng×0.2) max(1,round) 相同 · F重投格. BUFF_POOL 12项(7team+5single)结构同PoC.
### 🟩 系统层 1:1 阶段结论 (轮7后)
**已审 7 大系统, 仅运气羁绊1处真缺口(已修); 其余全1:1**: 技能handler19/19 · 多段出伤节奏(三路) · 羁绊×10(运气grant补) · 装备(eq_id派发) · buff/DoT · AI决策 · 商店. **这套 Godot 移植系统层非常扎实, 1:1 基本完成.** ~~后续轮转逐龟数值spot-check~~ → **用户2026-06-11重定向: 系统层够了, 转做面板 UI 1:1**(见下).

### 🎯 面板 1:1 重做 (用户 2026-06-11 强令: 逐面板照 PoC 代码核 布局/交互/颜色一模一样/字体/大小/坐标分辨率适配; 修掉自创; 全在剩余轮内到05:38Z)
**方法(每面板)**: ①定位 PoC 构建代码(scenes/*.ts 的 DOM/CSS) ②列 PoC 该面板**全部子元素**(不只delta) ③逐元素读精确值 color(#hex)/font-size/font-family/宽高/padding/坐标 ④diff Godot: 多=删自创/少=补/值不符=改 ⑤引PoC行号 ⑥parse+test ⑦commit ⑧**视觉项标"需F5"不claim已验**. Godot canvas_items stretch 已做分辨率适配, 关键基准值(1280×720基)对上 PoC 720基.
**PoC面板源**: DetailPanel.ts(信息1988行)/ActionPanel.ts/DmgStatsPanel.ts/HelpPanel.ts/ShopOverlay.ts + 图鉴选龟各Scene.ts.
**清单(战斗内→图鉴→选龟→菜单)**:
- [进行中]**信息面板**_build_fighter_detail(8539): ✅尺寸920×540+padding19/15(轮8) ✅border色→#5c4a1c+稀有色保留为glow shadow(轮9, DetailPanel.ts:96) ✅稀有度色已1:1(_rarity_color=PoC RARITY全对, 无需改) ✅corner14 ✅**头部子区**(轮10): 名字24→22白#e6edf3(原误用稀有色)/Lv→金#fff3a0前缀同号22/移除自创灰"Lv·稀有度"子行/加右侧大号稀有度字28px(weight900粗体近似需F5)/HP块宽220→490(PoC520·54%)右推/head gap14→12 — DetailPanel.ts:142-179; ✅**左栏stats子区**(轮11): 8属性2列网格chip(atk/吸血/护甲/魔抗/暴击/暴伤/穿甲/法穿)结构=PoC fdp-stats; grid gap h14→10·v6→12(PoC gap'12px 10px'行12列10)/chip gap5→7(fdp-stat gap7)/值14px#e6edf3已对 — DetailPanel.ts:266-282; ✅**右栏status子区**(轮12): st标题13px#ffd93d已对(缺3px金竖条::before→需F5) / defc防御网格gap14·6→10·12(上轮漏) / "无"标签12白.35→11px#666(fdp-none) / status flow gap6→5(fdp-buffs gap5) / buff tag(_status_tag) corner5→4·icon14→13(fdp-buff-tag radius4/img13), 11px/border1px/padding2·6/同色 已对 — DetailPanel.ts:300-317; ⬜剩子区diff(装备/技能/hint) ⬜字体m6x11; **🎨需美术/F5(StyleBoxFlat做不出)**: 金色内嵌边框(inset#ffe9a8 2px/#c79a36 4px/黑槽→需嵌套StyleBox或NinePatch) · bg竖渐变#1a2236→#0b0f1b(需GradientTexture) · 四角金铆钉(::after radial-gradient→需贴图)
- [x]胜负结算 = ✅核实1:1(BattleEndScene.gd, _show_result只收数据切BattleEnd.tscn): 标题88px金#ffd93d/红#ff5050/平局+scale0.3→1 back.out 500ms入场动画(=PoC ts:87-94) · 遮罩黑0.7 · 龟币28px#ffd93d · 副标12px#888 · 统计表headers13px#ffd93d+分隔线780×1 · 按钮220×50. 全对PoC无需改. · [x]行动/技能卡_make_skill_card: card本身已1:1(bg rgba(44,56,86,.72)/border2px rgba(120,140,180,.42)/radius11/padding10·12 全对ActionPanel.ts:111-115); **修: icon原裸TextureRect无框 → 套PoC .skill-icon框(47×47/radius8/border1px白.22/bg黑.32/cover, ts:124-131) + emoji兜底字号32→28**. 余disabled PoC grayscale(.7)Godot只opacity.5(需shader). · [ ]商店卡_make_shop_card(2107)vs ShopOverlay.ts · [x]羁绊chip(emoji vs图标已解决=图标对): PoC BattleStatsRail.ts:278-281 chip主用**图标tags/<tag>标签.png**, emoji仅404 onerror回退 → Godot用图标=对(没瞎改成emoji!). border2px(t3#ffe066/t2#f2f5fb)✓ radius14✓ ×N20px✓ 文字色#1a2030/#3a2606✓. **修: icon原固定50×50→height50/width auto保长宽比(PoC:172注释明说固定50×50压扁非方标签是bug已改)**. 余金银底PoC是3段渐变(StyleBoxFlat纯色近似)需F5. _show_synergy_detail modal 另核. · [ ]装备席/卡_build_bench_rail/_make_equip_card/_show_equip_popup · [ ]状态栏_build_stats_rail(7223) · [ ]伤害统计_build_dmg_stats_panel(7866)vs DmgStatsPanel.ts · [ ]帮助/设置_show_help_panel/_build_sound_panel vs HelpPanel.ts · [ ]初始装备选_show_initial_equip_pick_modal · [ ]规则选_show_rule_pick_modal/_make_rule_card
- [x大体1:1]图鉴 CodexScene: **值层核实1:1** — title 48px#ffd93d(.tscn) / LIST_W 280 / listBg黑.4·detailBg黑.6(.tscn=PoC) / 边框色 / 入场动画(list-360 detail+360 back.out) / 列表行 bg#1a2740@.85·头像40·名15px·稀有度14px monospace — 全对 PoC CodexScene.ts:107-199. **唯一差: 列表头像 PoC圆形(addCircularAvatar)Godot方形** → 需圆形遮罩shader(canvas_item discard length(UV-.5)>.5), 但shader无法headless验(写错头像消失)→ **待能F5的轮做, 别盲加**. 同理info面板/战绩头像也方. drill-down详情/_show_synergy/_show_shop_pool 子项另核.
- [部分]选龟: **_make_synergy_chip 核实≈1:1**(icon 28×28 contain✓ / count×N 13px#ffd86b✓ / corner9 / t3色255,217,61@.12·.6 / 默认bg#1c1208@.6 / gap3 / padding左5右8 — 全引PoC index.html:495-514; **补上下padding4(原漏)**; 余count缺bold800=FontVariation复杂暂记). ⬜_build_synergy_region/_build_detail_region/_make_pet_card 子区另核. · [ ]主菜单布局/按钮

### 🎬 战斗演出编排 1:1 (用户 2026-06-11 强令: 每个技能 移动/镜头/位置/受伤反应 都照 PoC 代码, 不许"通用兜底"; 自主轮延长到 09:04Z/+4h)
**现状**: 三套原语已有且引PoC行号 — 镜头(_camera_focus origin-zoom 1.2× ts:1001/_camera_reset/_screen_cutin_flash/_play_screen_shake引cam.shake) · 移动(_attack_hop引playAttackHop ts:3416/_lunge±80引ts:3518/_lunge_return引ts:3590) · 受伤(flash+juggle击飞+掉血trail 已核1:1). 专属编排技能(全套PoC): basicChiWave气波滑排/basicSlam过肩摔/turtleShieldBash龟盾chop/ninjaImpact·Backstab·Bomb·Shuriken/ghostPhase虚化/ghostPhantom/cyberBeam能量大炮KOF.
**两个真缺口(待逐技能修)**:
1. **`_SELF_DRIVE_SKILLS` "暂用通用前冲"兜底** — 非PoC专属, 要逐个换成该技能PoC编排.
2. **通用 attack-hop 路径不带镜头 zoom** — PoC对该技能是否focus/zoom需逐个核(可能漏了焦点推进).
**动画接线(用户已为部分龟做帧)**: animations/ 有帧的龟= basic/ghost/ninja/treasure_golem(各 attack/hurt/death/knockup/run/idle); ice目录空(未做). ACTION_PETS=basic/ghost/ninja/golem 已对上. **每轮扫目录**: 有帧的龟确保全状态接线(attack出招/hurt受伤/knockup击飞/run移动/death), 新增龟动画自动捡入ACTION_PETS.
**方法**: 每轮取1技能, 读PoC skill-handlers.ts/pet.js演出代码(位移px/时序ms/镜头zoom·focus/受伤juggle) → Godot复刻精确值引行号 → 消灭"暂用" → parse+test+commit. 视觉/手感标"需F5". **已做编排技能清单**(逐轮补): (轮13起记)

### 🌊 深海(dungeon)模式审计 (用户2026-06-11问: 关间继承/敌人选龟·等级·站位) = ✅全5项1:1, 无需修
1. **关间继承**(GameState dungeon_carry_*): 存活龟→回满HP / 阵亡龟→70%HP复活(PoC:1498-1503) · 币carry_coins(PoC _carryCoins) · 身上装备carry_equips(HP结算前重装, PoC:1487-1496) · 装备席carry_bench. 1:1.
2. **敌人选龟**(GameState.setup_next_dungeon_stage): 全龟池排除我方阵容→shuffle→BOSS关1只/普通3只. 1:1 PoC pickStageEnemies(dungeon.js:155).
3. **敌人等级**(BattleScene:356-360): =玩家队伍平均(round, clamp1-10). 1:1 PoC computeAvgFromSaved/effectiveSideLevel(:1143-1156).
4. **难度倍率**(BattleScene:301-307): 关1=0.85 / 关2=1.0 / 关3=1.1 / 关4=1.2 / 关5BOSS=hp3.0·atk1.25·def1.4. 1:1 PoC DUNGEON_STAGES.
5. **站位**(SlotHelpers.auto_assign_slots): effHp降序 + 菱形阵A(front-1/back-0/back-2)/B(front-0/front-2/back-1) 50/50; n=1→front-1; 缩头召唤effHp×0.5. 1:1 slot-helpers.ts(代码注明曾自创front-0/front-2分支已删).
### 🐢 绿底bg静止bug 已修 (用户报: 深海关之间画布不动) — 7场景(Dungeon/ChoiceEvent/RewardPick/BossPick/Settings/Record/Achievements)的menu-bg-tile加menuBgDrift漂移(-512→0/25s linear, 1:1 index.html:79/90); 原FULL_RECT静态. TeamSelect(select-bg主体)未动. 视觉需F5.
### 🚨 P0 视觉层自创对账 (2026-06-11 用户抓出'💥暴击!'自创飘字后, 担心"刚刚所有东西都得重查") — **最高优先, 先于其它backlog**
**分层判断**: 逻辑/数据层(羁绊/装备/buff·DoT/AI/深海/商店/技能handler/stats)=code-compared + 1021测覆盖, **可信不用重扫**(暴击是视觉附加非逻辑). **视觉层(飘字/label/面板/动画/粒子)=自创高发, 系统扫**.
**方法(有界, PoC=ground truth)**: 视觉层每元素 → 列PoC有什么 → **Godot有但PoC没有=自创→删**(带PoC证据); PoC有=保留(引行号). 扫得完(PoC定义完整集).
**进度**:
- [x] 暴击飘字: '💥暴击!' = 自创(PoC普通暴击无飘字, 仅数字×1.2+音效) → 已删, 保留计数. (2026-06-11)
- [x] **飘字/label 全对账**(agent扫~76点 + 我核实): 修8处 — 删自创(✨气场觉醒→改log/🤖机甲组装/💀亡灵不灭/🌋恢复小形态: PoC只log不飘) + 改措辞(🔥涅槃重生→🐦凤凰重生 ts4340 / 🐚海螺复活→🐛化形小虫 ts4479 / 去💎不朽前缀 ts5361 / 缩头+N🛡→生命→改_spawn_float_text heal绿 ts7877). [x]🎯窃取!(轮14): 改飘属性明细"+N攻+N甲+N抗+NHP"(passive-num) + 补PoC漏的log"🏹猎杀吸收!"(BattleScene.ts:4732-4739). 决胜局"⚔怒气"=授权自创不动. **飘字自创对账全清✓**(暴击+8处+窃取 = 共10处).
- [x] **装备飘字label措辞**(轮15, equipment_runtime:656-685): "讯放大器"→"📡放大器 +N% 增伤"(捕获pct) / FPGA00简写+独立heal float → 单条"🔧FPGA-00 +NHP +2甲/抗"(去重复heal float, 1:1 PoC单passive) / FPGA01→"🔧FPGA-01 +5 ATK +4% 生命偷取" / FPGA10→"🔧FPGA-10 本回合 +15% 增伤" / FPGA11→"🔧FPGA-11 本回合 -25% 受伤" (1:1 PoC:5435-5472). **余: PoC这些飘字色=#9af6ff青, _spawn_passive_text若不支持per-effect色则记需F5/补色参**.
- [x] **图片全对账**(agent扫): ✅ **全1:1无错图** — 28立绘/技能icon/被动38/装备46/状态13/规则7/背景/羁绊tag/菜单 全对, 无张冠李戴/无自创占位. 小项: mech.png=同图复制(非缺陷)/orphan battle资产两边都没用. 
- [ ] **海盗船召唤未实装**(agent发现): PoC spawnPirateShip(BattleScene.ts:6644)召唤船实体(battle/pirate-ship.png)+"海盗船登场!"crit-label飘字, Godot无(只注释BattleScene.gd:4321). 缺功能, 排轮次.
- [ ] **_sm小图标变体没用**(agent发现): PoC HUD/徽章/装备chip 用 equip/_sm·passive/_sm·status/_sm 下采样小图, Godot 用全尺寸. 同图不同尺寸=尺寸保真项(用户要shape/size), 核各处该用_sm的改用.
- [x已实装需F5] **海浪 e_wave 横扫 VFX**(用户问): 效果早已实装; **新增横扫动画 _play_wave_sweep**(wave-sweep.png 220×110, x -120→1400/2000ms linear, 被扫行y(home_pos.y-40), alpha入.9hold出, z100, 加slots_root; _fire_side_end_equipment 检e_wave触发). 1:1 PoC launchWaveSweep. **层级z100/行y偏移-40/世界x范围1400 精度需F5微调**. 原缺横扫动画. PoC launchWaveSweep(vfx/skills.ts:324): **贴图 vfx-wave-sweep(Godot assets/sprites/vfx/wave-sweep.png 已存在✓不需美术) 220×110, depth45, x 从 -120 → 屏宽+120, dur=2000ms, y=被扫行均值y(rowKey 0/1/2 → yPct 41/55/69 同高度横排), 青#6bccff→白渐变兜底, alpha 入0→.9→出0**. 实装: BattleScene._fire_side_end_equipment(2725) 检 e_wave 触发的行 → 新 helper _play_wave_sweep(row_y) (Sprite2D + tween x 2s + alpha). **难点: 从 equipment_runtime e_wave 效果回传被扫行 → row_y. 从零搭, 建议 fresh context 做避免 row-y/时序/图层出错.**
- [ ] 其它装备 VFX 逐个核 (miniCrystalB 旋转激光 等, PoC ts:7466 "复杂VFX单独round").
- [x] **粒子复扫**(轮16): Godot仅2处CPUParticles2D — 3568=合法(引PoC quantity28 ADD burst), 6130 `_spawn_hit_particles`=自创死代码(0调用, 命中火花PoC无)→删整函数. _make_decay_curve仍被3582合法burst用保留. **粒子层无残留自创✓**.
- [ ] 面板自创元素对账(每面板列PoC全子元素 diff, 见🎯面板清单) · 动画/编排自创对账(见🎬段)
**信心重建**: 不再泛说"1:1完成"; 每条 = "PoC:行号有此元素→保留" 或 "PoC无→自创删". 扫完出一份逐元素vsPoC对账表.

### 📋 用户报告待办 backlog (2026-06-11, 自主轮逐项做) — **全局原则: 形状+颜色+位置+大小+数值+分辨率 全 1:1 PoC, 不许只对数值/不许自创**
- [x] **信息面板描述颜色**(轮13): 技能/被动描述 popup(_show_skill_desc_popup) default_color #bccdde→**#cccccc**(1:1 PoC fdp-detail-box/passive-brief/skill-brief #ccc). 装备弹窗desc已#ddd=PoC .edp-body✓. 标题色已对.
- [ ] **信息面板图片位置**: 头像/技能icon/装备icon/羁绊tag 排布位置+大小, PoC考虑了分辨率(--poc-ui-scale=innerH/720等比) — 核 Godot 基准坐标 vs PoC.
- [x] **倒计时形状**(轮18, BattleTopRow.ts:226-245): 重建 Godot _show_turn_timer_bar — 180×16方条@(550,64) → **280×13/圆角7/2px白边.22/bg rgba(8,12,20,.85)/居中top146** (Panel+StyleBoxFlat); fill→Panel圆角5/内嵌276×9/≤10红#ff3b3b ≤20橙#ffb01f else绿#2bd66f(纯色近似渐变起色); 文字10px/800白(原11px). 值30/max30+"⏱Ns"已对. **余: PoC绿/红/橙是渐变(StyleBoxFlat纯色近似)+urgent≤10s脉冲动画(timerPulse红glow)未做 → 🎨需GradientTexture/补脉冲tween, F5**.
- [x] **伤害统计条形状**(用户疑"方的条吗"=对, 已修): Godot _make_ds_bar 原用裸ColorRect HBox=方角; PoC .ds-bar-wrap=height12/border-radius4/overflow hidden → 改圆角Panel(corner4)包裹+clip_contents+透明余量露圆角轨. 段色已对(物理红.6/法术蓝.6/真伤). **余: 左端首段ColorRect方角(Godot rect-clip不round-clip)轻微+面板宽/标题等其它子元素未逐一核 → 需F5**.
- [x] **对局内等级显示**(轮17): 场上龟身等级徽章已实装(HP条左 _make_slot_view:736). 核PoC turtle-hud.ts:182: 10px/boss13✓ #ffd93d✓ bg#2a1d12✓ 右对齐✓; **修偏差: Godot自创金色border+corner3(PoC Phaser text bg纯矩形无边框无圆角)→去掉; 漏bold→补**. 余padding近似记需F5微调.
- [x] **Boss模式视觉** = ✅核实1:1无需改: boss立绘baseScale=0.9×1.417×1.5=**1.913**(box153)=PoC ts:602 ✓ / HP条**160×8×border3**=PoC turtle-hud ✓ / 名字前缀**"BOSS "**=PoC ts:326/1215 ✓ / 倍率boss-pick3.5·dungeon3.0已见 ✓. (选boss界面 BossPickScene 网格140格另算, 未逐元素核.)

### (旧) 自主轮"结束"判断 (已推翻, 见轮3):
**所有能 headless 验证(parse+1021测)的 1:1 工作已完成**: 效果层技能handler 19/19 · 战斗反馈(飘字字体/多段出伤节奏全handler按PoC时序/掉血trail) · 等级系统+调试面板 · 图鉴内联 · 去自创粒子 · #13卡顿预载. 全提交 feat/godot-chest-treasure-variants 分支(未动main), 全程 1021/1021 测过。
**余项(待用户 F5 眼验/微调, 自主无渲染轮做不了)**:
- per-skill `_skill_windup` 出招动作逐技能是否逐帧 1:1 PoC(动画手感, 必须眼看)
- per-hit 箭/弹/拖尾等 VFX 视觉
- 飘字 embolden(0.5)/ 多段 stagger 手感是否到位
- 选龟/信息面板 像素级配色/间距 细节
- 彩虹蛇/选龟木板cover 等本轮新增视觉项的实际观感
**给用户**: F5 进游戏验上述视觉项; 看哪个具体不对, 指出来我照对应 PoC 代码改。代码层保真已尽(headless可验范围)。

---
## 🔥🔥 技能 handler 系统审计 (2026-06-10, 5agent扫全28龟 handler vs 数据 vs PoC) — 找到~18处"数据/PoC有、Godot handler漏实现"的真bug
**根因模式**: (A) 多技能被路由到裸 `_do_physical`/`_do_heal`(skill_handlers.gd:102-105), 只算伤害/治疗, 丢掉数据字段暗示的附加效果(自盾/自疗/穿甲/墨迹/critBonus/targetCurrentHpPct); (B) 一批"强化被动 passiveSkill/enhancesPassive"在 Godot `_apply_start_passives`(BattleScene.gd:3503)无 case(只处理 lava/cyber/hiding/twoHead), 其 flag 被读却从不写; (C) angelBless 派发丢 target; (D) `_calc_heal_amount` 无字段兜底回10%maxHp → 给纯buff/hot技能(磐石/朗姆酒)塞未描述治疗.
### ✅ 已修 (17/19, 全部 1021测过, 需F5):
- A1✅龟盾80%永久盾 · A2✅天使祝福给友军 · A3✅磐石甲抗buff去乱回血 · A4✅骰子critBonus+伤害修正 · A5✅万能牌自盾/自疗/随机减益 · A6✅七彩光束光色加成 · A7✅糖衣炮弹穿甲buff · A8✅素描墨迹 · A9✅墨水炸弹墨迹 · A10✅灵魂打击当前HP伤害 · A11✅朗姆酒护甲buff去乱回血 · A12✅掠夺破泡泡盾
- B1✅强化多重(-30%HP+概率60) · B2✅命运之轮每回合抽花色 · B3✅速写(墨迹上限7+真伤flag) · B4✅水晶不朽(第10回合+5000HP/400ATK) · B5✅diamondEnhanced flag · B6✅rainbowEnhancedPrism flag · B7✅死亡怨灵诅咒全敌
### 🔴 余 2 项 (需更深改动, 待续):
- C1 ⬜ 财神龟 招财进宝 fortuneBuyEquip — 装备直接上身(应进装备席bench)+漏席满→全友AOE回10%maxHp. PoC:5613. **(涉装备席架构, 需确认是否有意分歧)**
- D1 ⬜ judgement(天使被动) 额外伤害按聚合算一次 vs PoC逐段取当时HP×11%. PoC passive-triggers.ts:489. **(需移进逐段命中管线, 数值微差非缺失)**
**注: 全28龟其余技能/被动经5agent核实=已正确实现(泡泡/闪电/凤凰/熔岩/赛博/星际/缩头/龟壳/无头其余/双头/钻石主体/幽灵主体 全对).**

---
## 🎬 动画/演出层系统审计 (2026-06-10, 4agent扫全28龟 choreography vs PoC) — 大体1:1, 6处具体偏差(5已修)
**结论: 上一轮 choreography 做得好, 绝大多数技能演出 1:1(VFX资产/蓄力/击飞/远近分类/弹幕时序/镜头 全对).** 仅 6 处可代码核对偏差:
- ✅ hunterBarrage 连珠箭: bolt错峰 280→120ms + 删多发的1支引导箭(11→10)
- ✅ rockShockwave 磐石之躯: 命中后横排敌补 knockup 小跳(原目标不动)
- ✅ crystalSpike/Burst 结晶引爆: 补 cam.shake(300,0.011)震屏 + 白闪(原引爆只跳数字无特效)
- ✅ ninjaBackstab 背刺: 3段戳刺停留期补 target 受击白闪×3(原无受击反馈)
- ⬜ **rainbowReflect 反射: 缺招牌"彩虹蛇"飞行VFX**(发光头+220px彩虹拖尾沿弹射路径 caster→敌→友→… 逐跳, PoC makeRainbowSnake). 复杂自定义VFX, 强依赖F5, 单列待做. PoC skill-handlers.ts:5145.
- 📝 过时注释清理(非bug): chest `_SELF_DRIVE_SKILLS`:4266 说thunder未移植实际已wired; pirate/candy/bubble `_RANGED_SKILLS` 注释说"80px melee"实际走25px attack-hop.
- 📝 范围外: crystalBall passive 回合末射魔法光线(castCrystalBeam)疑逻辑+VFX 双缺, 另查.

---
## 🔥 用户 F5 报告问题清单 (2026-06-10, 用户要"每个都改不漏") — 一个个修
逐条标: ⬜未修 / 🔧改中 / ✅已修(需F5确认) / ⚠我引入的回归. **每修一条对着 PoC 源码、parse+test、单独 commit。**
1. ⬜ **选龟画布(select-bg木板)高分辨率铺不满** — PoC fitSelectStage 按**真实像素** innerW/innerH 算 scale(全屏max/窗口min ×1.17), Godot _stage_scale 用 get_visible_rect(canvas_items=逻辑1280×720)→高分屏木板小一圈+绿边. 疑 CanvasLayer 不吃 content-scale. **PoC解法=真实像素缩放, 照它改.**
2. ⬜ **选龟区(pet-grid)排版崩/差远** — 网格区布局与 PoC 不符.
3. ⬜ **选龟区信息崩**.
4. ⚠ **图鉴 数值/等级系统崩** — 疑我加的"技能锁(默认Lv1锁idx≥3)"在有真实等级时锁错; 需查 Godot 是否有 pet level, 有则我那改是回归→修正/回退.
5. ⬜ **图鉴点击技能=弹窗(错)** — PoC 是**内联换页**(showPetDetail view={skillIdx}→renderSkillDetailSection, 顶部"← 返回列表" CodexScene.ts:532). 我做成 modal=自创. 改内联.
6. ⬜ **图鉴画布不动/不连主菜单** — PoC menu-bg-active 全局常驻漂移, 图鉴/菜单背景应连续(PersistentBg autoload 存在但各场景自建_bg). 查continuity.
7. ✅ **图鉴调试面板(🛠)** — 移植 MenuDebugOverlay (图鉴右上🛠, OS.is_debug_build gate=PoC DEV_VISIBLE): 全员Lv1/5/10·加币·重置·快速对战.
8. ✅(批1) **信息面板** — 2列布局(左属性1.2fr/右状态3fr)+被动/技能点击内联弹卡+头像52圆+羁绊tag60; **header其余(Lv前缀色/大稀有字28分离)未逐项核, 后续可继续**.
9. ✅ **龟盾** — 是技能漏护盾(A1已修), 非显示问题.
10. ✅核1:1 **竹叶特效** — 充能"🎋蓄力"=PoC原有(BattleScene.ts:3270), 非自创.
11. ⬜ **整个游戏字体** — 全局 theme 已设 m6x11+CJK(=PoC栈). 若仍不同=渲染细微差, 需用户指具体处.
12. ✅ **主菜单粒子** — 已删(连战斗命中火花一并删, 均自创/突兀).
13. ⬜ **野生→选龟 卡顿** — 场景同步加载纹理卡帧, PoC 有 preload. 需 threaded load/缓存(性能项).
**等级系统 ✅ 接通**: GameState.pet_levels持久存储+get/set + 战斗读存档等级(敌=玩家均值) + 图鉴等级加成/技能锁; fighter.gd 早有 get_level_mult/解锁/ai_pick. 正常play全Lv1=与PoC一致, 调试面板可设等级测试.
14. ✅ 自动战斗按钮删 · 选龟自创动画删 · 卡片直角 · 死亡措辞阵亡 · 菜单coming-soon toast/全屏提示 · 战斗日志开场/行动者 (本轮已修, 需F5).
15. ✅ 小龟"打击"=basicBarrage(10波随机全敌 3.1ATK物理), 数据已1:1(非bug, 已答).

---
## 🟢 新上下文从这里开始 (交接)

### 全场景代码级清点审计 完成 (2026-06-10, 7 agent 累计 + 我核+修)
**覆盖全部场景**: 战斗4面板(操作/信息/统计/商店) + 选龟 + 图鉴 + 闯关/奖励/Boss选 + 菜单/设置/成就/记录 + 事件/教程.
**总结论: 自创内容≈0 (唯选龟有, 已清); 其余分歧均为 (a)有意架构(bench/GameState/side-based) 或 (b)引擎差异(无渐变/backdrop-filter) 或 (c)有意 standalone(无返回外站链).** 真实缺口已逐个补:
- 信息面板: buff徽章系统(~30+17) + HP5子资源 + 4防御 + 护盾值 + 被动tile + 羁绊tag + 立绘辉光. **顶部回合进度线整条新建.**
- 图鉴: 可叠加badge + 双形态钮(E1) + 技能锁态.
- 操作面板: 冷却行 + emoji兜底.
- 闯关: 装备席chip + 动态阵亡数. 事件: 120ms按压延迟. 教程: box-shadow.
- 商店: 核实已1:1(picker是PoC死代码误报). 菜单4场景: 零自创~95%忠实.
**用户定调(2026-06-10): 严格1:1, 即使不合理也照PoC; 全部移植完才谈改进。** 已据此修: 死亡措辞倒下→阵亡+色#ff6b6b · 奖励/事件卡片圆角→直角.
**战斗日志结构 1:1 — ✅ 已做(本轮)**: 开场删自创(头/roster/装备)→"战斗开始!"+协同激活; 每行动者"▶ X 行动"(ts:2333); 超时加名; 死亡倒下→阵亡+色#ff6b6b; 结算统计块确认是 dead code(_log_battle_stats 无调用)未进日志=已符合PoC. **唯余: ~70 被动/装备触发日志逐 handler 补 emit(Godot 已有相当部分: 掠夺/储能/涅槃/亡灵/海螺/钩锁/竹编/变身等; 缺的零散需逐技能补, 量大低优).** 原计划留档↓:
- 日志机制: PoC BattleLog.ts (默认隐藏📜切换, 200行上限, colorize关键词上色). 死亡class色 #ff6b6b(已对); round-sep #ffd86b(已对).
- **删(Godot自创)**: 开场头"斗龟场v2·Godot Battle MVP·W4"(gd:8767) · 左右队roster(gd:8777-8778) · 装备列表🎒(gd:8789) · 结算伤害统计块(gd:8850-8864, PoC统计在弹窗非日志).
- **加(PoC有Godot缺)**: `战斗开始!`(ts:1642) · `协同激活: {tag} ×{tier}`(左)/`敌方协同: {tag} ×{tier}`(右)(ts:1643-44) · **`▶ {name} 行动` 每行动者**(ts:2333, 在 _run_side_turn 每actor起手处加) · `▶ {name}(木桩)跳过回合`(ts:2593) · ~70 被动/装备/技能触发日志(Godot已有相当部分: 掠夺/储能/涅槃/亡灵/海螺/钩锁等; 缺的需逐 skill_handler 补 emit, 量大).
- **改措辞**: 超时加名 `⏰ {name} 超时！自动出招`(ts:2086; Godot _auto_act_on_timeout 需取当前actor).
**其余 niche(全部移植完后再议)**: BossPick标题描边5→6 · 菜单 tutorial4步modal/coming-soon toast/全屏提示 · 教程渐变钮(引擎无渐变) · 装备锤×N badge · 闯关加成chip emoji(字体豆腐风险).
**全程 1021/1021 测过, 视觉项需 F5.**



### 全面板元素清点审计 (2026-06-09, 4 agent 并行 + 我核, 用户要 A 全清点)
**核心结论: 跨 4 面板自创内容≈0 (EXTRA 多是 Godot 技术产物 modal分层/headless skip, 非自创UI); 真问题=缺失(缩水)。** 选龟自创(被动描述/动画)已修。各面板待补:
- **操作面板 ActionPanel** (BattleScene.gd ~1784): EXTRA=0. 缺3: 简介下"冷却N回合"行(ActionPanel.ts:338) / 禁用卡 grayscale(只opacity) / 技能图标 emoji 兜底.
- **信息面板 DetailPanel** (BattleScene.gd ~7686): EXTRA=0. **缺~23项(大)**: 整个 buff/状态系统(30+徽章 DetailPanel.ts:1238-1412) / 5 HP子资源条(坚壁/泡沫/怒气/财宝/储能) / 4防御属性(治疗/护盾/减伤/闪避) / 羁绊tag图标 / 立绘辉光 / 大稀有badge / 护盾值 / 被动meter+详细toggle / 装备锤叠层badge. = ledger旧记"缩水(大)"坐实.
- **图鉴 CodexScene**: EXTRA: 技能/被动详情用 modal(PoC 内联换页, 结构差异非自创内容) + 调试状态栏文字. 缺: 装备"可叠加"badge / 装备数值预览 / **技能锁态(Lv.N解锁灰卡)** / **双形态切换钮(🏹/🌋, E1功能整缺)** / 调试工具栏.
- **商店 ShopOverlay** (BattleScene.gd ~1966): EXTRA≈0(技术性). 缺: **选装备的龟 picker 子弹窗**(ShopOverlay.ts:449, Godot 直接进席跳过) / 跳过钮内倒计时文字 / 按钮hover. 文案/颜色/格子已1:1.
**修复进度** (本轮 commit):
- ✅ 操作面板: 冷却N回合行 + emoji兜底 (grayscale 留小差异).
- ✅ 图鉴: 装备"可叠加"badge.
- ✅ 选龟: 技能 styled tooltip(SkillTipButton).
- ✅ **信息面板已补**(本轮): HP 5子资源条(坚壁/泡泡/怒气·火山/财宝/储能, _detail_meter) + 4防御属性(治疗/护盾/减伤/闪避, _buff_value+Rules.heal_mult/shield_mult) + HP行护盾值🛡/海葵盾🪼.
- ✅ **信息面板 已大幅补全**(本轮多 commit): buff/状态徽章系统(~30buff+~17非buff状态, _status_tag/_status_badge, 逐类型1:1非启发式) · HP 5子资源条 · 4防御属性 · HP行护盾值🛡/海葵🪼 · 技能区天生被动tile+强化"+"角标+CD格式(_detail_skill_tile) · 头部羁绊tag图标 · 立绘稀有色辉光环.
- ✅ **图鉴 已补**(本轮): 装备"可叠加"badge · 双形态切换钮(E1 ⚔️/🏹·🌋/🐢, _codex_form_view) · 技能锁态(默认Lv1 idx≥3灰卡+Lv.N解锁).
- ✅ **操作面板 已补**: 冷却N回合行 + emoji图标兜底.
- ✅ **商店 = 已 1:1 (无需改)**: agent 报"缺选龟picker"是**误报** — PoC ShopOverlay.ts:388-398 买装备 `if addToBench → addToBench 并 return`, showFighterPicker(449) 仅 addToBench 不存在的**死兜底**; Godot bench 流就是对的, 加 picker 反成自创.
- 🔴 **剩余(非阻塞)**:
  1. **图鉴装备数值预览 = 不适用/冗余(架构分歧)**: PoC regex 扫 `apply.toString` 提数值, 但 Godot equip 数据**只有 desc 文本无结构化数值字段**且 apply 是 GDScript 不可内省; 且 Godot desc 已含"提供 +20 攻击力"等数值. → 跳过(再做=重复 desc).
  2. **信息面板余 cosmetic**: 大稀有badge(rarity已在Lv行显, 加大badge恐重复, 看render定) / 被动meter+详细toggle / 装备锤×N叠层badge(niche, 需hammer stack字段).
  3. **顶部回合进度线**(5节点滑轨 整条缺失) — 大新建, 规格已备齐(下次直接建):
     · 数据模型 (PoC BattleScene.ts:546-558): nodes=[{round:0,type:equip}]; for t=1..turn+5: t∈{3,6,9,12}→push{t,event}, t∈{4,8,12}→push{t,shop}, 再 push{t,normal}; curIdx=t==turn 的 normal 节点. 渲染 curIdx±2 共5格(越界格 opacity0 占位保等宽).
     · 渲染 (BattleTopRow.ts:348-378 + CSS 95-155): dot 40px(当前52+脉冲+▼pin); 类型色: normal灰radial/event琥珀✦/shop蓝🛒/equip绿🎁; past opacity.4 scale.8 / future .72 .88 / current scale1.16. label: equip"初始装备"/event"事件"/shop"商店"/当前=side pill(🐢我方回合绿 / 👹敌方回合红)/其余"第N回合".
     · Godot 挂载: TopBar(title=$UI/TopBar/Title 锚定pill)下方加居中时间线容器(注意 ENVELOP 缩放定位); _update_turn_timeline() 在 _set_title(BattleScene.gd:796)后每回合调; **需先找 Godot 当前行动 side 变量**(无 active_side, side-based整队制 562be1bc, 查 turn 循环里的 side).
  4. **战斗日志架构**(PoC极简▶X行动 vs Godot逐攻击verbose) — 大改(改全局logging), 风险高, 新上下文做.
  4. **统计面板**: emoji+暴击统计早已修(2304b4a8); 其余1:1.
  方法: 每项先读 PoC render + Godot diff (见 [[feedback_full_inventory_audit]]), 单项一 commit, parse+test, 视觉需F5.



### 选龟界面 1:1 大整修 (2026-06-09, 用 Playwright 截 PoC 真图当基准, 非推导)
**方法转折**: 之前靠读源码/agent报告判"忠实"反复翻车 → 这轮 Playwright 跑 PoC(localhost) 提**实际渲染几何/computed style**当铁基准。验证: 我的 regionLayout→stage 换算**逐元素 1:1 准**(title 算出(431,82)=PoC实测; detailTop(1016,135)=实测)。区域定位没问题, 差的是内容/字体/交互/自创动画。
**本轮提交 (各一 commit, 全 1021 测过, 视觉需 F5)**:
1. **字体**: TeamSelect.tscn **没挂 theme** → Label 用 Godot 内置无衬线字 (字体不对根因); 挂 default_theme(m6x11+CJK). 注: PoC pixel-zh.ttf 不存在→中文也回退雅黑, 与 Godot 一致.
2. **入场动画去自创**: PoC index.html:659-662 入场规则选择器(.screen-title/.select-top/.pg-filter-bar)与**实际 DOM**(ts-title/pg-rarity-rail/无select-top)不匹配=死规则; 唯一命中 .pet-grid. → 删自创的标题掉落/三按钮左滑/导轨淡入, 只留 grid 淡入.
3. **CTA发光去自创**: #poc-btn-confirm(index.html:518) animation:none box-shadow:none 覆盖关掉脉冲 → 删自创发光 Panel.
4. **激活羁绊**: 文字长行→PoC 紧凑 chip(icon28+×tier, HFlow换行, hover tip; t3金/t2深底).
5. **技能图标**: 底色深蓝→PoC rgba(255,255,255,.04); 加角标(锁Lv4/Lv7·基础·✓ + 强化"+"); 双形态tooltip(近战/火山).
6. **随从特殊占位**: hiding→随从?/crystal+crystalBall→水晶球/candy+candyBomb→糖果炸弹, 占back→front空槽不计3龟; 战斗端运行时自动找槽一致.
7. **tap-swap 换位** + **拖拽排序**: 完整移植 onSlotClick(选中/互换/active空槽) + onDropPet(set_drag_forwarding).
8. **删战斗自创"自动战斗"按钮**: PoC _autoBattle 仅 F3/控制台调试钩子无按钮.
**余(需用户F5后定)**: 右栏分隔线/section-title小计数等像素细节; 卡片sprite 76 vs PoC 72 差4px(buildPetImgHTML逐sprite尺寸难盲对); 占位糖果炸弹 emoji 可能需 emoji 字体.



**工具/流程**:
- Godot: `/c/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe`
- 解析检查: `cd games/turtle-battle-godot && timeout 120 <godot> --headless --path . --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error"`
- 单测: `cd games/turtle-battle-godot && bash run-tests.sh` (期望 `ALL PASS (1021/1021)`)
- **坑(刚踩)**: 新增 `class_name X` 脚本, headless --import 测得过, 但用户 F5 会"X 未声明"崩 (全局类需重导/重启才注册). → **新脚本一律 `const X := preload("res://...")` 直引, 不用 class_name** (见 events.gd / fcb74caa).
- 一处一 commit, commit 带 PoC 出处. 可见/交互项做完只能标"需F5", 不喊"已验证".

**选龟界面去自创动画 — ✅ 本轮完成 (逐个 tween 核 PoC)**
- 核完 gd 全部 5 个动画点 vs PoC(.ts + index.html CSS):
  - ✅留(忠实): 入场编排(gd328-354↔index.html659-687 时长/delay/easing/transform全对上) · CTA脉冲(gd361-397↔pocSelectCtaPulse) · 立绘idle(↔.dp-portrait index.html:566 常驻).
  - 🔧修1 **卡片hover**: gd 自创 scale(1.03) → 改 PoC translateY(-2px)+柔光阴影(index.html:394-397).
  - 🔧修2 **卡片idle**: gd 之前所有卡常驻跳动(自创多余动画) → PoC 默认paused 仅hover/selected running(index.html:432/434); _apply_pet_idle_texture 加 autoplay 参.
  - 🔧修3 **toast计时**: _flash_status 2.0s+0.5s → PoC showToast fade-in.2s→1.8s→fade-out.2s.
- 提交本轮(需F5验手感). 1021/1021 测过.
- **下一个任务候选**: 选龟交互丰富度(非动画) — 见下方"选龟界面"条(拖拽排序/点击换位/召唤位标/技能角标/双形态tooltip/羁绊chip格式); 或中立Phase2 / 信息面板 / 时间线 / 140技能.
- ⚠️ 提醒: 入场掉落+CTA脉冲 PoC index.html:328/658-694 真有=忠实, 已核实别再动.

---
## ✅ 已完成 + 核实

### 飘字数字系统 — ✅ 全因素对齐 (逐行核 visual_dispatcher.ts)
- 颜色/字号/轨迹(pop/shrink/hold/flight/fade,重力200)/三色排行(红0蓝1白2紧凑×22窗220)/符号/屏中心640 = 逐项验1:1
- 修: **起跳位置 bug 在 4 个函数全贴脚底→龟身中心**(_spawn_float_text/_spawn_dot_text/_spawn_passive_text(+30脚下!)/_spawn_crit_label) · 非伤害堆叠(去自创base_row3/4,窗220→100,从row0) · autoOffset±16(label) · -15 label抬 · label scale1.0起跳 · 伤害忽略caller y_off(修审判true双偏移44→22) · 漏的 bubbleStore被动每回合青🫧回血+dmgPct溅射
- commit: b8b69f60 d6ea6c7b e3cf903e fb9b90fe e44b4325

### 影子 — ✓ 核实 1:1 (无需动)
- 全数值对上: silhouette/alpha0.55/scale1.1/flatten0.6/flipY/rot24°/offset22/lift9/σ4.48. 唯blur机制(Phaser addBlur vs Godot高斯shader)需F5终验radius.

### 站位 — 🔧 修1处, 余1
- ✅ bambooSmack knockToFront 击至前排 (288e2652)
- 🔴 SUSPECTED: 玩家选靶 _enter_targeting 没过滤 stealth (PoC/AI路径有). 需验隐身敌能否被手点.

### 点击穿透 — ✅ 修 (437e576c)
- modal浮层(商店/详情/装备弹窗 = 4个`var layer`)加 ui_modal组; 龟身 Area2D input_event 守卫: 有modal时return. PoC浮层本就挡点击.

---
## ✅ 本轮已修 (续)
- 统计面板 emoji(⚔🛡💚🔵📊) + 暴击统计(per-fighter crits→结算列) (2304b4a8)
- 施法面板 fortuneBuyEquip 禁用条件(币不足/席满满血) (8a33b540)
- **点击穿透**: modal浮层 ui_modal组+守卫挡背后龟点击 (437e576c)
- **图鉴返回键+ESC**(原死胡同出不去!) · 计时器黄阈≤20s · 商店重投文案/q_dodge补% (76ee60e3)

## ✓ 新核实 (基本1:1, 无需大改)
- **图鉴**: ✓ 无自创动画(每个tween映射PoC). 余: 返回键(已修)/form切换/技能等级锁/装备数值预览/debug — 待补
- **商店**: ✓ 经济/roll/reroll/AI/倒计时 全1:1, 无自创动画. (文案已修)

---
## 🔴 待做 (按价值/可验性)

### 中立生物事件 — 🔴 整个子系统缺失 (最大坑, 逻辑可单测)
- PoC `engine/events.ts`(163行) Godot **无 events.gd**. 缺: 6环境事件(volcano/tide/thunder/meteor/treasure-rain/fog, 回合3/6/9/12互斥各1次) + 3中立怪(treasure_golem hp300/atk30, giant_crab hp400/atk40, anemone_mother寄生) + spawnNeutralPair + 自动攻击 + handleNeutralKilled奖励(首杀big/后small) + anemone寄生结算(+15atk/+350盾/healReduce/5%群疗).
- PoC: BattleScene.ts:1771-1817 + 6727-6896. Godot 仅有死的 treasure_golem 攻击动画行(4785) + 孤立 _isNeutral 过滤(永不触发).

### 战斗日志 — 🔴 架构级偏差
- PoC: 每回合只 `▶ X 行动` + 特殊事件; 伤害走飘字不写日志. Godot: 每次攻击写 `name→skill→target -dmg` 行 + 自创开场roster/回合分隔/结算块.
- ~100条 PoC passive/装备/羁绊/中立日志行 Godot无. 措辞差(阵亡vs倒下, 💎vs💰收入, 🎒vs🔧装备). 颜色palette不同(伤害#ff8c8c vs PoC#ff4444; 治疗#3cd97a vs #06d6a0; 无逐词上色). PoC日志默认隐藏📜切换; Godot常驻.

### 施法面板 — 🔴 ~6项
- 被动技能卡 Godot跳过不显(PoC显⭐禁用卡 ActionPanel.ts:284); fortuneBuyEquip禁用条件没移(coins<cost/席满满血 没灰); emoji图标兜底缺(无PNG技能显示无图标); "冷却N回合"子行没渲; 选靶提示无"←返回选技能"可点按钮(只右键/Esc); 面板bg平涂vs渐变; 禁用卡无grayscale(只opacity). [自动战斗按钮=Godot自创, 可能有意].

### 选龟界面 — 🔧 自创动画已去(✅) / 交互丰富度待做(🔴)
- ✅ 自创动画已核完去掉: hover scale→translateY · idle 全卡常驻→hover/selected才播 · toast计时. 见顶部交接.
- 缺: 拖拽排序(ABSENT) · 点击换位(slot tap-swap) · 召唤位/水晶球/糖果占位标 · 技能图标角标(Lv4/Lv7/基础/✓/+) · 双形态tooltip · 羁绊chip格式(PoC紧凑icon+count+hover vs Godot展开文字行) · tier2色(#cdd vs #4cc9f0).
- 文档化差异(别改): Lv.1硬编码(无petState).

### 统计面板 — 🔧 2项 (可验)
- tab/header缺emoji(PoC '📊战斗统计'/'⚔造成'/'🛡承受'/'💚治疗'/'🔵护盾'); 暴击没统计(BattleStats无crits字段→结算暴击列恒0, BattleEndScene.gd:48).
- in-battle面板其余1:1(4tab/2列/排序/中立排除/死亡0.4/bar色). 刷新节奏: PoC实时60ms vs Godot每回合(有意).

### 场景切换卡顿 — 🔴 无预加载
- 全用 `get_tree().change_scene_to_file()` 同步加载, 场景_ready同步load纹理/sheet → 卡帧. PoC有Phaser preload阶段. 需: 加载屏+load_threaded 或 纹理cache autoload. 需F5验.

### 图鉴 — 🔴 待审 (自创动画?)
- 用户问"图鉴是不是也有[自创动画]". 待派agent审 CodexScene/图鉴 vs PoC.

### 信息面板 / 对局顶部进度线 / 商店 — 🔴 待审
- 信息面板: 每处一样+交互一样. 顶部进度线(turn timeline 5节点, 早审报缺). 商店: 1:1.

### 对局顶部进度线 — 🔴 回合轨道时间线【整条缺失】(大)
- PoC BattleTopRow.ts:95-155/348-378 = 5节点滑动轨道(当前±2, 渐变轨/彩色圆点 普通灰/事件琥珀✦/商店蓝🛒/装备绿🎁, 当前放大脉冲+▼). Godot **无**(只有"第N回合"pill). 需整体新建.
- 计时器条: 宽280 vs 180, ≤10s 脉冲动画缺(已修黄阈). [规则徽章 Godot 其实有 _add_rule_badge:6342, agent误报].

### 信息面板(龟详情) — 🔴 缩水移植 (大)
- _build_fighter_detail(7666+) 缺: **状态/buff区**(burn/poison/墨迹/电击/结晶/熔岩盾/泡盾… ~20状态徽章) · **被动区**(图标+meter条+长按大卡) · **HP资源子条**(坚壁/泡泡/怒气/财宝/储能) · **4防御属性**(治疗效果/护盾效果/伤害减免/闪避率) · 稀有度大徽章+羁绊标签图标 · 金属边框/920×540/pop动画 · 宝箱龟专属装备侧栏.
- ✓ 有且1:1: header/8基础属性/10装备格+点击弹窗/技能行/关闭行为.

### 140 技能 + 被动 — 🔴 待全审 (最大量)
- 需分批agent审每龟技能 choreography(施法位移/镜头/敌击飞/节奏/出伤/VFX) + 数值 vs PoC. 见 ../archive/CHOREO-FIX-QUEUE.md 已记部分.
