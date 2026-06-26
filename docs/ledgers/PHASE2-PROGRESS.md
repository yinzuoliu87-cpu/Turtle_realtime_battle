# 二阶段实装 · 自主进度账本

> 用户 2026-06-11 设: 接下来~4h 每~20min 一轮自主推进二阶段, 提交 feat 分支(不push/不动main), 明早查看.
> 配套设计: `../design/深海龟战-总设计文档.md` / `../archive/IMPLEMENTATION GUIDE.md` / `深海龟战 装备系统 处理B.xlsx`.
> **装备系统已定 = 三合一升星(处理B), 不是进化石. 战斗 = 双路龟蛋(V3.2). 上线11龟已配齐龟能/怒气.**

## 自主轮原则 (沿用前几轮经验)
- 低风险优先: 先建**数据层 + 不破坏现有的新结构**; 重集成(替战斗模式/接效果)需用户拍板的, **只出计划+问题, 不盲改**.
- 每轮: 做一块 → parse(`--import`) + `bash run-tests.sh`(期望1021过) → 提交(引设计文档) → 更新本账本 → ScheduleWakeup ~20min.
- 新脚本用 `preload` 不用 `class_name`(F5会未声明崩). 数值占位先填能跑的.
- 不确定/需决策的 → 记到下面「⚠ 待用户拍板」, 不擅自定.

## 模块顺序 (实装指引 A→G; 先 A→B 验核心手感)
- **A 装备数据层**: 60 件(处理B xlsx) → 结构化数据表. 字段: id/名称/系列/大类/套装标签/稀有度/费用/基础属性(1星)/1星效果/3星效果/商店可刷/进池阶段.
- **B 三合一升星**: 3×1星→2星(×1.8), 9件→3星(质变). 无进化石. 商店买1星 + 备战席合成.
- **C 经济**: 单一深海币, 每局重置, 来源(回合+利息+阵亡), 花费(买装/刷新/合成?). 数值占位.
- **D 商店**: 小商店(每4大回合5格卖装+刷新递增) + 大商店(上下路间卖消耗品). 备战席容量10.
- **E 备战席**: =背包栏, 容量10, 出手前30s窗口拖到龟身(龟槽5).
- **F 双路战斗**: 分路暗选(分路即分死)→上路→下路(串行)→幸存者汇合终极战场; 小将补位; 龟蛋HP=1000+50×均等级; 攻蛋跨场累计; 每路结束回复30%已损.
- **G 终极战场+永恒buff**: 三情况判定; 败方蛋登场×5增伤+每回合自损25%maxHP; 无平局; 单场第30回合后存活统领每回合叠+50%增/受伤(仅统领).

## ✅ 已完成 (本会话, 上线版近期可玩层)
- 龟能(蓝量)系统: 9龟+龟壳 龟能, 熔岩龟怒气, 财神无龟能; CD全取消(火山形态volcanoSkills+梭哈cd999除外); 回复/消耗/AI退而求其次/HP下资源条/技能卡⚡🔥消耗角标.
- 上线11龟白名单(basic/stone/bamboo/angel/ice/fortune/rainbow/lightning/phoenix/shell/lava), 其余隐藏不删.
- 熔岩龟: 怒气消耗(地裂35/岩浆涌动35/熔岩喷射40) + 变身红条倒计时 + 变身AI(攒怒气冲变身).

## 🔄 二阶段进度
- **模块A 装备数据** ✅(数据已建, 未接入): `data/phase2-equipment.json` = 59件结构化(剑11/盾10/杖10/召唤9/潮汐7/枪11/独立1; 普14/精良3/稀有21/史诗14/传说7). 字段全(系列/大类/套装标签/名称/稀有度/费用/基础属性1星/1星效果/3星效果/商店可刷/进池阶段). **仅数据, 还没接 DataRegistry / 还没接战斗**(待模块B + 用户拍板复用vs新建).

## ⚠ 待用户拍板 (自主期间不擅自定, 攒着明早问)
1. **装备复用 vs 新建**: 处理B 60件里很多名字 = 现有 equipment.json 的件(锈蚀短剑/海藻短刃/治愈海葵…). 是**新数据表替掉旧的**, 还是新旧并存映射? 旧装备 apply 逻辑能否复用到新件?
2. **双路战斗是大重做**: 现在是单场3v3. 双路龟蛋要重搭战斗流程(分路/串行2场/龟蛋基地/小将/终极). 是在现有 BattleScene 上扩, 还是新场景? 龟能/怒气/技能层可复用.
3. **2星中间档数值**: 设计说 ×1.8 自动生成(不在表内). 确认算法(基础属性×1.8? 特效怎么强化?).
4. **套装加成数值**: 系列≥3 / 子流派≥2 的具体加成 — 全待定(设计说先做系列维度).
5. **经济/商店全部数值**: 每回合产出/利息/阵亡奖励/各花费/刷新涨价曲线 — 设计明确标占位待实测.
   (商店【费用概率】曲线已按用户定的"10档随整局升、高费越来越大"建好 SHOP_COST_ODDS, 数值占位可整表替.)
6. **消耗品清单**: 8件药水/炸弹的具体效果数值未设计.

## 📜 轮日志
- **R1** (起): 熔岩龟变身红条倒计时+变身AI(提交); 建本账本; 模块A 装备数据提取(59件结构化).
- **R2** (用户在线给方向: 装备只名字+emoji效果空/双路在现有BattleScene扩/2星套装经济商店做壳):
  - 装备补 emoji + 效果占位(effectImpl=false).
  - **模块B壳** phase2_equip.gd: 属性解析+升星×1.8+三合一+套装检测.
  - **C/D/E/G 数值壳** phase2_config.gd: 经济/商店/备战席/双路龟蛋/终极战场 全占位常量一处.
  - **模块F骨架** phase2_duallane.gd + GameState: 分路/路序/胜负判定 + BattleScene按路开打钩子(guarded).
  - DataRegistry 加载装备; 1058测过. (设计文档+xlsx 入库)
  - **双路路序串接** _show_result: 中间路打完串下一路, 末路落结算用整局胜负; final暂用上路阵容代演.
  - **商店费用概率10档**(用户加需求): SHOP_COST_ODDS 随整局(上+下+终极)推进, 高费概率越来越大; roll_cost_tier+stage_for_shop_visit. 1076测过.
  - **商店费用概率反复调**(用户逐档给锚点, 最后参考云顶之弈Set17曲线定): 见 SHOP_COST_ODDS 注释. 概率已锁定.
- **R3** (龟蛋逻辑层, 读设计文档V3.2 §3-6 吃准规则后做):
  - GameState.damage_egg(攻蛋跨上/下/终极累计, 归零摧毁)+egg_alive+egg_frac(满级蛋1500).
  - Phase2Config: egg_final_hit(×5)/egg_self_loss(25%maxHP)/standby_recover(已损30%)/eternal_mult(永恒N层×(1+0.5N)).
  - phase2_minion.gd: 小将Lv1=750/45/7/7(基数250/30×补丁系数×3/×1.5, 用户2026-06-25补丁)每级×1.05, 前砍1.4/后射1.5; fill_lane补到3名+空路首个升精英.
  - 纯逻辑可测, 1098测过.
- **R4** (双路大地图场景): DualLaneMap.tscn/Scene — 左右龟蛋🥚+血条 + 三条路(上/终极/下)色条+战场节点+当前路高亮+胜负标. 战斗枢纽: 进图→进各路→打完回图推进→决出显结果. 入口=主菜单本地模式"双路龟蛋(测试)". _show_result(duallane)改为回大地图. 视觉需F5.
- **R5** (PvP 架构 — 用户提"这会用在pvp想想怎么搞"):
  - **../design/PHASE2-PVP-DESIGN.md**: 定权威模型=服务器/房主权威+事件驱动(非lockstep; 回合制带宽小+防作弊+免determinism). 单机=PvP退化(left local/right ai) → 关键决策: **后续接战斗按"权威算state+产出事件, 客户端渲染"的形状搭, 别写PvP要推翻的单机专用逻辑**.
  - phase2_pvp.gd: 分路暗选commit-reveal(防偷看) + 回合ACTION构造/校验 + 控制方判定. GameState: side_controllers/battle_seed/对局快照(同步·重连). 1114测过.
- **R6** (攻蛋进战斗 — 用户描述"一方全灭→蛋出现前排中间→挨打几回合→战场结束"):
  - BattleScene._show_result(duallane): _wiped_side检测 → _egg_attack_phase: 蛋🥚登场败方前排中间(front-1),
    胜方存活龟攻3回合(或碎), 伤害扣GameState.egg_hp[loser]跨场累计, 演出=蛋震+飘字+血条排空+"摧毁!"banner.
  - 蛋视图独立简版(不进fighters/slot_nodes并行数组)→不碰目标/刷新/_make_slot_view, 低风险.
  - GameState.dual_match_over(蛋碎即时判对方胜); 大地图改用它. 1115测过. **战斗演出需F5**(进双路打输一路看蛋).
- **R7** (小将补位进战斗 + 修正每方3统领):
  - **设计纠正**: 每方【3统领】分上/下路(我之前误用6), 故每路必<3统领→小将补位是核心非可选.
  - _build_teams: duallane按该路统领0-3建队 + _fill_lane_minions补深海小将到3名(空一路首个精英); 小将带基础攻击技(physical, 前1.4/后1.5)能出手; _make_slot_view emoji回退(🐠/🦐占位).
  - DUALLANE_SMOKE=1 无头冒烟入口; 双路+小将冒烟45s零脚本错误; 1118测过. **小将站位/攻击演出需F5**.
  - **下一步**: ①待命回复30%(需跨路HP继承) ②终极3情况路由(需幸存者带HP汇合) ③永恒buff每场第30回合 ④战斗内蛋血HUD/当前路名. 另: 分路暗选UI(3龟分2路) / 装备stat上身(复用vs新建) / 真美术替🥚🐠 / 网络P3.
  - ⚠新增待拍板: 跨路HP继承(待命回复+终极汇合都依赖它)=每路用独立fighter, 需打完snapshot存活龟HP, 终极重建带入. 大改, 接前确认.
- **R8** (分路暗选UI + 局内等级系统):
  - **分路暗选UI**: 大地图新增分路阶段, 3龟chip各[↑上][↓下]分配, 敌方暗选显❓, 全配后开战; 为PvP commit-reveal铺垫.
  - **局内等级(TFT风, 用户规划+拍板3项)**: ../design/PHASE2-LEVEL-DESIGN.md; 1-10级每局重置, 绑①龟蛋HP②商店概率档③小将等级.
    - 用户定: 升级强化蛋(max+50&current+50累计伤害保留) / 被动+买经验 / 小将随等级.
    - Phase2Config: MAX_LEVEL/XP阈值[2..96]/被动XP2/买经验4币4XP/局内币5(占位). GameState: dual_level/xp/coins + add_xp(连升+强化蛋)+buy_xp+grant_dual_round; setup按start_level定蛋HP; 快照含.
    - 绑定: 小将lv=dual_level; 战斗每回合grant_dual_round; 大地图局内等级HUD(Lv/XP条/🪙/买经验按钮). 1135测过. **UI需F5**.
- **R9** (跨路HP继承 + 终极战场 — 用户确认流程"没问题"后打通主线):
  - **胜负改蛋制**: dual_match_over只看蛋碎(赢路只给攻蛋回合, 蛋多撑过1×→几乎必进终极).
  - GameState: dual_survivors + snapshot_lane_survivors(存活统领+待命回复30%, 跳小将/阵亡) + dual_lanes_done.
  - _build_teams "final": 从dual_survivors重建(带血不补小将) + _apply_survivor_hp. _egg_attack_phase(terminal): 败蛋×5+自损25%+凿穿.
  - _show_result(duallane)重构: 攻蛋→快照幸存→回图; 终极done. 地图蛋制判胜+终极入口. DUALLANE_SMOKE_FINAL冒烟+地图自动推进. 1143测.
- **R10** (永恒buff — 自主推进轮, 用户"自己推进一轮"):
  - damage乘子+_eternalStack(造成&受到各+50%/层线性); duallane第30回合后存活统领每回合叠层(仅统领). 1146测.
  - **下一步**: 双路商店(用上 概率档=等级 + dual_coins买装/升星) / 战斗内等级+路+蛋HUD / 装备stat上身(复用vs新建待定) / 真美术 / 网络P3.
  - ⚠ 整局主线已通(分路→上路→下路→终极→蛋碎判胜); **战斗演出/终极/永恒/小将 全需F5眼验**(headless跑不出画面).
- **R11** (移除老商店+老羁绊 → 换新商店 — 用户"老商店和羁绊移除, 换新商店, 羁绊只在装备间"):
  - 双路移除: 老乌龟羁绊(Synergies.apply_team/运气/元素burn) + 老战中商店(turn%4) + PoC回合经济; 全guard by mode≠duallane, 老模式不破坏.
  - **新商店**: phase2_equip.roll_shop(按局内等级费用概率档掷5格) + GameState dual_shop_offer/buy(进备战席扣局内币)/refresh; 大地图"🛒深海商店"浮层(5卡+买+刷新+备战席). 1157测.
- **R12** (装备闭环 + 模式精简 — 用户连续多条):
  - **三合一升星**: try_merge_bench 自动合成(3件同款同星→高1星, 买入即触发); 备战席显星★②③.
  - **装备上身(拖动)**: equip_to_turtle/unequip; 大地图"🐢统领装备"浮层 _DragItem拖→_DropZone(龟)装上, 点装备卸回; 战斗龟脚下展示装备emoji.
  - **星级辨识**: 1★银/2★金/3★青 + ★mark (浮层/备战席/战斗).
  - **槽位随等级**: equip_slots_for_level=clamp(ceil(lv/2),1,5) — 1-2级1/3-4级2/.../9-10级5; 满槽禁用.
  - **移除老商店/老乌龟羁绊/老经济**(双路); 羁绊改只在装备间(套装). **移除深海闯关/指定Boss菜单**(上线只推塔).
  - **野生对局接真选龟**: 菜单→TeamSelect选3统领→DualLaneMap(真阵容+随机野生敌). 1176测.
  - **下一步**: 套装加成数值/装备特效(用户后续一一加) / 战斗内蛋血·路名HUD / 真美术替emoji / 网络PvP(P3) / 老dungeon&boss代码可清.

## 装备效果自主实装 (用户"自己列计划+几小时自主,每部分都完成不留待拍板")
- **R1** (盾系018-021): 守护贝壳(回合开始自回base+pct×maxHp经healAmp)/治愈海葵(奶自己+最低血友军+海葵层每层加治疗护盾强度)/哑铃(锻炼层+maxHp + 新on_side_end钩子扔哑铃)/守护贝母(连最高ATK友军给龟能盾净化+_p2GuardLink伤害转移, damage.gd apply_raw_damage分流). 新helper _heal/_highest_atk_ally/_cleanse_debuffs. 1268测.
  - 解读记录: 海葵"任何来源治疗"暂只计本装治疗 / 021"伤害最高"用ATK近似.
  - **计划**: R2=杖系/元素022-024+029(余烬真火/火珊瑚灼烧/龙蛋吐息/冰封水母冻结, 后3复用phase1 e_fire/e_dragon_egg/e_jelly); R3-4=龟蛋改真单位(../design/EGG-AS-UNIT-PLAN.md); R5+=余backlog+effectImpl+ledger.
- **R2** (杖系/元素 023/024/025/028/029): 火珊瑚(on_hit每段灼烧)/龙蛋(on_turn_begin吐息满3喷火龙沿随机有敌列同列F+B友回血+敌魔法+灼烧, 装备3层)/雷鸣贝壳(on_side_end N道雷各1×ATK真伤)/寒霜法杖(on_cast魔法+冰寒chilled)/冰封水母(on_hit概率魔法+冻结眩晕+成功冻结给盾). 14条新测. **待: 022余烬真火(需dot.gd burn→true钩子) + 026/027/030/031(充能/层数/水晶引爆) + 召唤系**.
- **R2.5** (010横扫卡元数据补brief/hits/icon — 疑skill panel"技能遮住"因素之一; 用户报需F5确认/截图).
- **计划更新(用户R2.6)**: 优先【信息面板1:1审计】= 逐行读 PoC DetailPanel源 vs Godot _show_fighter_detail(8849), 列PoC该面板全子元素(header/属性/装备格/技能tile/状态徽章/cd灰)做diff(多删少补错改), 引PoC行号. **做2遍**(第2遍catch第1遍漏的). 用户报"信息面板完全错误"+"施法面板技能全被遮住但cd灰显示". 然后再继续 022真火/026充能/027电击/030-031水晶/召唤系/龟蛋改真单位.
- **澄清(用户)**: "混乱"是【新状态/debuff】不是bug! 效果=持有者技能被遮住/显示灰(不能放技能, 类弱化版眩晕). 要新建 confused/混乱 buff type + 动作面板该单位全技能置灰 + 状态徽章 + 某些装备/技能施加它.
- **用户总令**: "全部都做完吧, 有图片的都配上" = 实装【所有】剩余装备(022/026/027/030/031 + 034-059, 规格全在 PHASE2-EQUIP-WAND/SHIELD/SUMMON-TIDE-GUN-SPEC.md) + 混乱状态 + 信息面板1:1审计(2遍) + 龟蛋改真单位 + **给有icon图的装备配真图标**(★phase1同款用其icon PNG路径, 见equipment.ts; 新件用emoji). 不停, 全做完.
- **R-混乱** (新状态confused实装): Buffs type "confused" → _skill_ready(actor)全置灰不可选 + 回合循环 Buffs.has(confused)→_do_confused_action(强制skill0基础攻击随机敌"胡乱攻击") + 状态徽章(😵混乱). 1276测/双路冒烟零错. **施加方待接**(某装备/技能挂confused, 用户后续指定; 机制已通).
- **用户令(进程)**: "每装备做场景描述+怎么实现, 自己看自己实现" → 实装每件时在spec文档补【场景+实现要点】(钩子/数值/边界); "自己做, 轮次搞快点不等这么久" → ScheduleWakeup缩短到~90-120s.
- **R3** (022余烬法杖+真火机制): on_cast施灼烧+挂trueFire状态; dot.gd burn tick查trueFire→灼烧转真伤(无视魔抗). 杖系仅余026/027/030/031. 3条新测/1279.
- **R4** (批6: 潮汐041退潮(纯属)/042涟漪(on_turn_begin全队回已损%)/044深海护符(on_hit_as_target首次<50%回血一次)/047重击锤(apply_stats atk+=maxHp%) + 枪械055靶向器(on_hit markedDmg标记)/058穿甲弹(on_hit溅射身后%). +shieldHealPct属性. 7测/1286.
- **R5** (批7: 召唤037蜡烛(on_side_end三阶段循环熄灭/微弱回血+邻格半效/燃烧敌横排魔法+灼烧)/038信号放大器(on_turn_begin本回合临时增伤区间随机, 复用damage.gd _dmgBonusThisTurnPct)/040FPGA板(on_turn_begin抽N个2-bit状态星1/2/4个: 00回血+永久护甲魔抗·01永久攻+生命偷取·10本回合增伤·11本回合减伤) + 潮汐045生命珍珠(on_hit_as_target首次<50%回血%+N火球%目标maxHp魔法+灼烧, 触发一次). 12测/1298.
- **R6** (批8: 枪械on_cast连射 048黄铜手铳(N发命中最前敌X×ATK物理)/050加特林贝壳(N发随机分布敌X×ATK物理+永久减护甲)/051激光手枪(同列F+B首敌X×ATK物理+流血, 身后50%)/057狙击长管(对最低血%敌X×ATK物理, 击杀→递归再开枪上限12)). +_lowest_hp_enemy helper. 9测/1307.
- **R7** (批9: 枪械049连发弩(on_cast向后排敌每人连射N发, 伤害按目标已损血0.8~1.3×ATK)/053霰弹贝(on_cast N发弹珠随机分布敌各0.22×ATK, 被≥8发命中→眩晕)/054瞄准镜(纯属性atk/crit/critDmg + _cannotBeDodged不被闪避flag) + 独立059沙漏(纯属性龟能+生命). +critDmg属性(→_extraCritDmgPerm). 9测/1316.
- **R8** (批10, 镜phase1机制: 杖026雷电法杖(on_hit充能+25/AOE+12.5满100→链式闪电跳N不重复敌各X魔法)/027电棍(on_cast电击最前敌X魔法+施法计数满阈值3/3/2→眩晕)/030水晶球A(on_cast沿一列same_row N段各X魔法+水晶层满3引爆%maxHp)/031水晶球B(on_cast全敌X魔法+水晶层满3引爆, 3★引爆邻格+50%) + 潮汐043海浪(on_side_end+1巨浪层满3/2/2→随机横排same_column扫敌我: 友+盾+永久护甲魔抗/敌魔法+永久减). +_p2_lightning_chain/_p2_crystal_beam helper. 21测/1334.
- **R9** (批11: 召唤039竹叶(on_cast持生长充能时→强化攻随机敌base+20%携带者maxHp魔法+回20%maxHp+永久maxHp, 3★可触发3次, 镜e_bamboo_leaf)/枪械052左轮(on_side_end装6发每回合射1发random敌base+coef×ATK物理, 0弹停火, 镜e_revolver; 敌死+1装弹待死亡钩子)). 8测/1342. **剩7件需额外管线: 034玩偶熊(召唤新单位)/035齿轮·052敌死装弹(死亡钩子)/036孵化器(临时等级)/046幽灵墨鱼(闪避钩子)/056飞镖(击飞追踪)** — 留作专项轮(同龟蛋改真单位一起).
- **R10** (批12 死亡钩子子系统): phase2 on_death(dead,all) 新增 + BattleScene死亡口(7282 _incubator_on_death旁)接通. 035黄铜齿轮(on_turn_begin+N齿轮层, 携带者死亡→每齿轮+2深海币落GameState.dual_coins+战报) 全实装; 052左轮(敌死→对面所有左轮持有者+1子弹cap6)死亡装弹补全. 6测/1348. **剩4件=各一子系统: 034玩偶熊(召唤新fighter)/036孵化器(临时等级,phase1 _incubator可复用但需把p2eq_036接进多个progress点)/046+054(需先实装dodge掷骰命中判定, Godot只有dodge buff显示)/056飞镖(击飞_knockedUpThisTurn事件追踪).**
- **R11** (批13: 036孵化器): 复用phase1孵化进度系统(_incubatorProgress/_incubatorTempLevel, 死亡口_incubator_on_death已自动给036+10/+15). phase2钩子接进度源: on_turn_begin+5/on_hit造伤×0.1/on_hit_as_target承伤×0.1 → 满100升临时Lv(cap3每级+5%基础) + **新增满级→全队均摊护盾(300/400/600一次)**. 内联进度数学(不preload EquipmentRuntime防成环, 与死亡口同字段同逻辑). 简化: cap3/阈值100全星统一(3★的cap5/-30%阈值未做, 记录). 8测/1356. **剩3件: 034玩偶熊(召唤新fighter)/046+054(dodge掷骰未实装)/056飞镖(击飞追踪) — 与龟蛋改真单位同专项轮.**
- **R12** (批14: 046幽灵墨鱼+054瞄准镜, 复用既有dodge掷骰): **发现_roll_dodge已在skill_handlers.gd实装(405/748/2672调用)+含e_ghost盾/dodgeCounter反击, 之前误判'Godot没dodge'**. 扩展_roll_dodge: 顶部加054攻击者_cannotBeDodged→必中bypass; 命中成功块加046 _p2GhostShield永久护盾. 046 apply_stats=加dodge buff(15/25/50%, 999)+_p2GhostShield(30/50/120). 6测/1362. **装备效果~58/59! 仅剩034玩偶熊(召唤新fighter)=与龟蛋改真单位同管线.**
- **R13** (批15: 056飞镖, 复用B的_knockedUpThisTurn): on_side_end向所有被击飞敌(_knockedUpThisTurn)各射1镖(base+coef×ATK物理+流血), 命中移除靶子. B统一_mark_knockup后此flag可靠→056解锁. +补标001/010/034 effectImpl(早实装漏标). 4测/1397. **剩仅032/033唤灵·复活海螺(死亡变虫复活, 需复用on_death+_spawn_combatant). 装备 57/59!**
- **R14** (批16 收官: 032唤灵海螺+033复活海螺): 032=入口纯属性件(+50/60/70hp). 033=复用phase1 e_conch死亡变虫: apply_stats设_equipConch=true(BattleScene死亡口3463已读→变形小虫复活)+逐星小虫属性(_conchWormHp/Atk 150/20→300/40, 我把e_conch变形的硬编码150/20改成读这俩flag, phase1默认不变). 11测. **简化记录: 033 3★'每回合分裂'未做(新机制, TODO).** + 修stale哨兵测(item[0]=001已实装) + 加'装备效果≥57实装'正向断言. **🎉 装备效果 59/59 全实装! 1409测过.**
