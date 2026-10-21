# 新手引导实机研究：全新账号首次启动 → 教程结束（2026-10-21）

起因：用户 10-21「首先第一眼玩家看到的是什么」「人家教程怎么做的你又去猜吗」。
本篇只记**录像里看得到的**；看不到的写「未看到 / 没拿到」。

## 方法

- 来源：YouTube 实机录像，yt-dlp 下载，imageio_ffmpeg 抽帧（先 5 秒一格通扫，关键段 2~3 秒一格精扫）。
- 首选 **MGFTUE** 频道（专录「新装→FTUE」的频道，竖/横屏原生 2340×1080，从启动开始、不剪辑）：TFT / 皇室战争 / Marvel Snap / 炉石 / 符文之地传说 都是 2024 年版本。
- MGFTUE 没录的游戏用 "Gameplay Walkthrough Part 1" 类录像，**有的不是从启动开始**，表里已注明。
- 时间码 = 视频内时间（mm:ss），截图文件名就是时间码。截图都是原分辨率（背包乱斗为横屏录像裁出中间竖屏区）。
- 抽帧踩坑：ffmpeg `fps=1/N` 通扫出来的格子比实际时间早 N/2 秒，截图已按实测偏移校正（以文件名时间为准）。

| 游戏 | 录像 | 年份 | 是否从启动开始 |
|---|---|---|---|
| 云顶之弈 TFT（手机） | https://www.youtube.com/watch?v=kOLqqDt-VQA （MGFTUE） | 2024-08 | 是 |
| 皇室战争 | https://www.youtube.com/watch?v=fqnkT8fXUUg （MGFTUE） | 2024-07 | 是 |
| Marvel Snap | https://www.youtube.com/watch?v=UgSOiu3nnw8 （MGFTUE） | 2024-08 | 是 |
| 炉石传说（本体，手机） | https://www.youtube.com/watch?v=h_OaSzSlMt8 （MGFTUE） | 2024-08 | 是 |
| 符文之地传说 LoR | https://www.youtube.com/watch?v=KIeyjh1RY4Q （MGFTUE） | 2024-09 | 是 |
| 背包乱斗 Backpack Brawl | https://www.youtube.com/watch?v=0YCRugxtyF8 （2026-02）；对照 https://www.youtube.com/watch?v=-6w-ViSkIio （2025-01）、https://www.youtube.com/watch?v=HqhtN6iAJ-Y （2024-10） | 2024~2026 | 2026 版：是（第一帧已在商店）；2024 版从起名开始 |
| 背包战争 Backpack Battles（手机） | https://www.youtube.com/watch?v=Y3xd8kh1rKQ | 2026-02 | **否**，第一帧已在商店，启动段没录 |
| Super Auto Pets（手机） | https://www.youtube.com/watch?v=i30bMyGNjDw | 2022-02 | 是（从登录页开始） |
| 刀塔霸业 Dota Underlords | https://www.youtube.com/watch?v=s6YCF1S2AZ8 | 2020-03 | **否**，第一帧已在教程棋盘 |
| 荒野乱斗 Brawl Stars（加的一款） | https://www.youtube.com/watch?v=16751Cn_Z_I | 2025-07 | 基本是（片头后第一帧已在操作） |

**没拿到的**：
- **炉石酒馆战棋**的首次教程：搜到的全是攻略/讲解视频，没有新号首次进入酒馆战棋的不剪辑录像。下面炉石一行是**炉石本体**新号流程（教程后才出现「酒馆指南」）。
- **Backpack Battles 启动段**、**Underlords 启动段**：录像不含，「几秒进第一战」只能从录像起点算，表里注明。
- **云顶手游国服/金铲铲**：只搜到攻略，没有新号录像。
- 所有录像都看不到「对手是否加成」的数值面板，必赢方式只按画面上能看到的（对手名字、血量、剧本台词）记。

---

## 逐款记录

### 1. 云顶之弈 TFT（手机，2024-08）`云顶之弈TFT/`

| 时间 | 画面 |
|---|---|
| 00:02 | **第一眼**：TFT 标题 + 「SIGN IN TO CONTINUE」四个登录钮（Riot / Google / Xbox / Facebook）；之前一帧是系统「允许通知」 |
| 00:27 | 选服务器区（Where would you like to play?） |
| 00:35~00:55 | 补丁下载 2.2 GB（进度条） |
| 00:57 | 赛季活动弹窗 + **「Greetings, tactician! Are you new?」✗/✓** |
| **01:07** | **直接进教程对局棋盘**（1-1，「0/1」），不经过主菜单 |
| 01:12 | 企鹅 Pengu 文字框：「Hi, I'm Pengu! In Teamfight Tactics, you'll build a team of champions to battle for you against seven other players. If you're one of the last four standing, you win!」（约 40 词，全教程最长的一屏） |
| 01:20~01:55 | 「Placing Champions on the board makes them a part of your team」「Champions fight automatically」（一屏 3~10 词） |
| 02:02 | 商店：「Vayne has two traits… Let's build an Exemplar team. Buy Vayne!」；买错会说「Not THAT one!」（强制买指定英雄） |
| 03:42 | 海克斯三选一（教程里就教） |
| 04:10~ | 「Every player is a Tactician, like me!」；「You can't exceed the maximum team size… buy XP!」 |
| 10:00~10:30 | 装备合成 |
| 11:00 | 「You're really getting the hang of this! The timers are on now.」——**计时器到这时才开** |
| 12:00 | 「Experiment with formations! Champions with short range, like Guardians, are better in the front line.」 |
| **12:42** | **「YOU FINISHED 1ST PLACE」**，教程结束 |
| 12:52 | **主菜单第一次出现，全部入口同时开放**：Store / Treasure Realms / Team Planner / Pass / Play |
| 14:07 | 模式选择：Normal / Ranked（锁图标）/ Double Up / Hyper Roll / Tutorial |

- 启动→第一战：**67 秒**（其中约 20 秒是补丁下载，登录+选区约 30 秒）。
- 教程：一局完整的 8 人局（1-1 到 3-2），**约 11.5 分钟**；手段 = 角色（企鹅）文字框 + 高亮指示 + 指定购买；无跳过钮（开头的「Are you new?」✗ 就是跳过）。
- 必赢：结果是第 1 名，前半段不计时；对手实力画面上看不出。
- 解锁：教程结束后主菜单所有系统一次性开放，只有 Ranked 锁。

### 2. 皇室战争（2024-07）`皇室战争ClashRoyale/`

| 时间 | 画面 |
|---|---|
| 00:07 | **第一眼**：加载画面（Clash Royale 标题 + 角色插画 + 进度条） |
| 00:12 | 年龄滑条（What is your age?）+ 条款 |
| **00:22** | **已在战场**，国王：「Let's complete some training matches first!」 |
| 00:37 | 手指图标拖卡牌，河对面显示可放区域（红/橙色禁区） |
| 01:27 | 训练 1 胜利（对手「Royal Trainer」） |
| 01:37 | **大厅第一次出现**：「Training Progress 1/3」，只有 Battle 一个大钮 + 4 个宝箱槽；开宝箱得金币和新卡 |
| 01:57 | 手指强制点**升级骑士**（教「升级」系统） |
| 02:25 | 训练 2（国王：「Spells like Fireball deal direct damage!」） |
| 03:37 | **训练 3 之前才起名**：「After this final training you will battle real players around the world. Choose yourself a battle name…」 |
| 04:35 | 训练 3（「Mini P.E.K.K.A is a great card to counter Giant.」） |
| 05:37 | 训练营结束 → 奖杯之路 / 竞技场 1 |
| 06:32 | 游戏模式：Trophy Road 可玩；Goblin Queen's Journey「Unlocks at Arena 12」；Path of Legends「Unlocks at Arena 15」 |
| 06:57 | 商店（每日特惠） |

- 启动→第一战：**约 20 秒**（只有年龄 + 条款两屏）。
- 教程：3 场训练战 + 战间大厅，**约 5.5 分钟**；手段 = 国王对话气泡（一句话，6~12 词）+ 白手指图标 + 出兵区高亮；不强制战斗内操作，但战间「升级」「开宝箱」是手指强制点。
- 必赢：对手是「Royal Trainer」训练 AI（名字明示），3 场都赢。
- 解锁顺序：战斗 → 宝箱/金币 → 卡牌升级（收藏）→ 起名 → 奖杯之路 → 模式（按竞技场锁）→ 商店。

### 3. Marvel Snap（2024-08）`MarvelSnap/`

| 时间 | 画面 |
|---|---|
| 00:02 | **第一眼**：Snap 标题插画 |
| 00:12 | 同意条款（一个 ACCEPT） |
| 00:27 | 「MATCH 1」Nick Fury VS（「Searching for Opponent…」，其实是剧本对手 Doctor Doom） |
| **约 00:35** | **进第一战**；第 1 回合只亮一个地点（New York） |
| 00:47 | 「Cards cost Energy.」「You can't play these cards yet.」（一屏 3~6 词） |
| 01:07 | 另两个地点出现：「Win 2 out of 3 Locations!」「Each card adds Power」「Highest Power wins!」「Most cards have special abilities!」 |
| 约 04:12 | 第一战 **VICTORY** |
| 04:22 | 「Here's a deck to get you started! Nice!」（送卡组） |
| 04:37 | **第一战之后才起名**（Recruit Missions / Enter a Name） |
| 04:44~08:50 | 第二战（对手名 SWOOSH，画面看不出是不是 AI） |
| 08:47 | 「Amazing job! Earn boosters every game! Visually upgrade cards! New card! Unlock new cards!」 |
| 09:37 | 「Edit your deck here!」（收藏/卡组） |
| 10:12 | 模式：Conquest 锁定「Unlocks when you finish the Recruit Season Pass」；Friendly Battle |

- 启动→第一战：**约 35 秒**。
- 教程：第一战剧本（逐步揭示地点和规则），第二战已半自由；主菜单约 **9.5 分钟**才出现。手段 = 短句浮框（3~6 词）+ 对手角色台词气泡。
- 必赢：第一战剧本对手（Doctor Doom 台词：「You'll do. As a warm-up to the real warm-up.」）。
- 解锁顺序：战斗 → 卡组 → 起名 → 升级卡牌 → 编辑卡组 → 模式（Conquest 在新兵季票后）。

### 4. 炉石传说（本体，手机，2024-08）`炉石传说Hearthstone/`

| 时间 | 画面 |
|---|---|
| 00:17 | **第一眼（可操作的）**：酒馆门 + 「Do you want to sign into an existing Battle.net account? Not Now / Sign In!」 |
| **01:12** | **第一战 VS**（Rexxar vs 吉安娜），中间是加载 |
| 01:32 | 「Drag this Minion to the board to play it!」+ 吉安娜自言自语气泡；**右上角一直有 Skip** |
| 02:07 | 「Attack Rexxar with your minion!」，END TURN 按钮发绿光 |
| 03:47 | 旅程地图「Your Journey Begins」（3 个关卡 + 宝箱）；教攻击/生命值图示 |
| 04:12 | 第二战（对手 20 血） |
| 08:07 | 第三战 巫妖王 |
| 13:02 | Victory，教程通关 |
| 13:07 | 「Create an Account? Nice work! Safeguard your progress…」 |
| 13:47 | 酒馆指南：「This guide will help you learn the ropes. Let's start off easy by playing a match!」 |
| 14:07 | 匹配真人（「You are being matched against a player of your skill」） |

- 启动→第一战：**约 70 秒**（含登录询问 + 加载）。
- 教程：3 场剧本战，**约 12 分钟**；手段 = 箭头/文字牌 + 双方英雄对话气泡 + 按钮发光；**全程有 Skip**。
- 必赢：剧本对手，第一战对手只有 10 血，第二战 20 血（我方 30）。
- 解锁：教程后才建号 → 酒馆指南（任务式）→ 真人匹配；其他模式没在 30 分钟内出现。

### 5. 符文之地传说 LoR（2024-09）`符文之地传说LoR/`

| 时间 | 画面 |
|---|---|
| 00:07 | **第一眼**：标题插画 + 「SIGN IN TO BEGIN PLAYING」四个登录钮 |
| 01:07 | 「FIRST BATTLE」（How to win / Attacking / Champions，PLAY NOW） |
| 01:32 | 「Play Garen.」黄色箭头指手牌 |
| 01:57 | 「Taking Actions」说明框（约 20 词，Tap to continue） |
| 03:42 | 第一战 VICTORY |
| 03:47 | 「WELCOME TO RUNETERRA」4 关教程地图（First Battle / The Best Defense / Back and Forth / Light and Shadow BOSS） |
| 18:37 | 「GAME MODE UNLOCK: The Path of Champions unlocked!」 |
| 18:47 | 「NEW MODES AVAILABLE」PvP / PvE 二选一 |
| 18:57 | PvP Introduction 任务链 |
| 19:52 | 主界面（Home / Play / Collection / Rewards / Store） |

- 启动→第一战：**约 85 秒**（登录 + 加载）。
- 教程：4 场剧本战，**约 17.5 分钟**；手段 = 箭头 + 单句指令 + 偶尔整框规则说明（需点继续）。
- 必赢：剧本对手（第一战敌方 Draven）。
- 解锁：4 关打完才解锁两大模式；主界面在近 20 分钟时才出现。

### 6. 背包乱斗 Backpack Brawl（2026-02 版）`背包乱斗BackpackBrawl/`

| 时间 | 画面 |
|---|---|
| 00:04 | **第一眼：已在商店**，白手指 + 「Drag from shop to buy」 |
| 00:16 | 右上「Fight!」 |
| 00:19 | **打完第一轮商店才起名**（My name is…） |
| **00:21** | **第一战 VS「Sir Timothy」（木头训练假人）** |
| 00:24 | 「Fights are automatic. Your items VS their items」 |
| 00:36 | Victory（1 个奖杯 / 2 条命） |
| 01:15 | 「Full recipes combine after the fight!」 |
| 之后每轮 | 每次只讲一件：「Place next to other sword to make a recipe」「Buffs are positive effects」「Armor absorbs damage」「Weapons use stamina to attack」「Change game speed here」「Drag rock to shop to sell」（一屏 4~10 词） |
| 05:33 | 第一次失败（对手逐轮变强） |
| 08:15 | 整局结束（被淘汰） |
| 08:33 | **主菜单第一次出现**；开奖励箱（金币 ×250、物品 ×15） |
| 09:15 | 物品升级（XP） |
| 09:36~ | 英雄列表、图鉴 |

- 启动→第一战：**约 20 秒**（录像起点就是商店）。
- 教程：**就是第一整局**（约 8 分钟），不另设教程模式；第一战必赢（木头假人），之后对手变强会输。
- **版本对比（同一游戏的改动方向）**：2024-10 版（HqhtN6iAJ-Y）是 起名 → 主菜单 → 选英雄 → 商店，第一战在 01:10；2025-01 版（-6w-ViSkIio）第一帧已在商店、01:05 第一战、打完才起名、才见主菜单；2026-02 版 21 秒第一战。⇒ **这款同类游戏两年里把主菜单和起名都挪到了第一战之后**。

### 7. 背包战争 Backpack Battles（手机，2026-02）`背包战争BackpackBattles/`

- **第一帧已在商店**（启动段没录，没拿到）。店主狐狸气泡：「Buy items from the shop by dragging them into your inventory」→「You can rotate an item you have grabbed…」→「Give them a big whap from me!」。
- 01:17 找对手，**01:22 第一战**（离录像起点）；03:12「Round won!」胜场 10 杯 / 5 命；03:17 选技能。
- 教程同样是第一整局里逐轮弹提示 + 物品说明卡（点开有完整数值）；第一战输赢录像里没看清，**未确认**。

### 8. Super Auto Pets（手机，2022-02）`超级自走宠物SAP/`

| 时间 | 画面 |
|---|---|
| 00:05 | **第一眼**：登录页（Email / Register / Play as Guest） |
| 00:07 | 主菜单：一个巨大的「Arena Mode」+ Versus Mode + 几个小按钮 |
| 00:22 | 商店，第一条提示「Buy a pet for 3 gold.」（白箭头 + 可关的小黑框） |
| 00:37 | 「Buy food for your pets.」 |
| 01:07 | 「Time to test your team by having a friendly battle with another team.」 |
| 01:32 | 起队名（形容词 + 名词选按钮） |
| **01:47** | **第一战 VS** |
| 02:12 | **第一战失败**（Defeat，心少一颗） |
| 04:02 | 「You reached turn 3! Tier 2 animals unlocked! You now lose 2 lives per loss!」 |
| 07:50 | Victory |

- 启动→第一战：**约 1 分 47 秒**（其中商店第一轮约 1 分 20 秒）。
- 教程：没有单独教程，就是第一局里的小提示框（每条可点 ✗ 关），一屏 4~15 词；新内容按回合解锁（第 3 回合 2 阶动物、失败扣命加倍）。
- 必赢：**不保证**，录像第一战就输了（对手是别的玩家的异步队伍）。

### 9. 刀塔霸业 Dota Underlords（2020-03）`刀塔霸业Underlords/`

- 录像第一帧已在教程棋盘（启动段**没拿到**）。乌鸦讲解员文字框：「Dota Underlords is a game of strategy where you'll battle against seven other players. Last player standing wins.」，后面「The only way to win is by building the best crew. Let's hire our first hero. Open the SHOP…」——**一屏 20~40 词，是这批里字最多的**。
- 02:50 选霸主；**03:10「Nice job, you finished the tutorial!」**（教程约 3 分钟，一场缩短的引导局）；03:30 送称号「Teacher's Pet」。
- 04:10 模式页：Knockout / Standard / Duos / Training；**Ranked「Play 3 casual games to unlock」**；还有 Bot Match。
- 14:50 第一场正式局第 3 名。

### 10. 荒野乱斗 Brawl Stars（2025-07，加的一款）`荒野乱斗BrawlStars/`

- **第一眼就是操作**：Shelly 头像气泡「Hi, I'm Shelly! Let's collect all these POWER CUBES!」+ 虚拟摇杆上的手指。
- 00:27「Tap the RED CONTROL to shoot the closest enemy. Destroy them all!」
- 00:42「It's showdown time!」第一场 10 人乱斗；**01:52「You are #1!」+10 奖杯**。
- **02:02 打完第一场才起名**（What's your nickname?），之后才进城/主菜单动画。

---

## 总表

| 游戏 | 第一眼 | 启动→第一战 | 第一战之前经过 | 教程形式 | 第一战必赢？怎么赢 | 主菜单何时出现 / 解锁节奏 | 教程总长 | 每屏字数 |
|---|---|---|---|---|---|---|---|---|
| TFT | 登录钮 | 67 s | 登录、选区、下载、「Are you new?」 | 一整局引导局 | 第 1 名（不计时到中盘） | 教程结束后**一次全开**，只锁 Ranked | ~11.5 min | 3~40 词 |
| 皇室战争 | 加载画面 | **20 s** | 年龄、条款 | 3 场训练战 | 是，对手明写「Royal Trainer」 | 第 1 战后出现**极简大厅**（只有 Battle），之后逐个开：宝箱→升级→起名→奖杯之路→模式（按竞技场锁）→商店 | ~5.5 min | 6~12 词 |
| Marvel Snap | 标题插画 | 35 s | 条款 | 剧本战 + 半自由战 | 是，剧本对手 | 第 1 战后送卡组、起名；约 9.5 min 才见主菜单；Conquest 锁到新兵季票 | ~9.5 min | 3~6 词 |
| 炉石（本体） | 是否登录 | 70 s | 登录询问、加载 | 3 场剧本战，全程 Skip | 是，对手 10/20 血 | 教程后建号 → 酒馆指南 → 真人匹配 | ~12 min | 3~8 词 |
| LoR | 登录钮 | 85 s | 登录、加载 | 4 场剧本战 | 是，剧本对手 | 4 关后才解锁两大模式；~19.5 min 见主界面 | ~17.5 min | 2~20 词 |
| 背包乱斗（2026） | **商店（拖一件买）** | **21 s** | 买一件 → 起名 | 第一整局逐轮提示 | 是，对手木头假人；之后会输 | **整局打完（8 min）才见主菜单** | ~8 min | 4~10 词 |
| 背包战争 | 商店（录像起点） | 未拿到（起点后 82 s） | 未拿到 | 第一整局逐轮提示 | 未确认 | 未拿到 | — | 5~15 词 |
| SAP | 登录页 | 107 s | 登录、主菜单、商店一轮、起队名 | 第一局小提示，可关 | **否**（录像第一战就输） | 无主菜单解锁，按回合解锁动物阶 | 提示散在前 ~6 min | 4~15 词 |
| Underlords | 未拿到 | 未拿到 | 未拿到 | 3 分钟引导局 | 未确认 | 教程后模式全开，Ranked 要先打 3 场 | ~3 min | **20~40 词** |
| 荒野乱斗 | **直接操作** | **0 s**（实战 42 s） | 无 | 操作教学 + 1 场乱斗 | 是，第 1 名 | 打完才起名、才进主菜单 | ~2 min | 5~15 词 |

## 共性（只数上表 10 款里看得到的）

1. **第一眼不是主菜单。** 有画面的 9 款里，没有一款在第一战前让玩家看到完整主菜单：
   要么登录/标题（TFT、LoR、炉石、Snap、皇室战争、SAP），要么直接是对局/商店（背包乱斗 2026、荒野乱斗、背包战争）。
   唯一在第一战前出现主菜单的是 SAP，而它的主菜单只有一个巨大的「Arena Mode」按钮。
2. **问不问「要不要教程」：** 只有 TFT 问了一句「Are you new? ✗/✓」（叠在活动弹窗上）；炉石是战斗中右上角常驻 Skip。其余 7 款**不问**，直接开打。
3. **起名推迟到第一战之后**：Snap、背包乱斗（2025/2026）、荒野乱斗、皇室战争（第 3 场前）都是先打再起名。背包乱斗 2024→2026 的改版正是把起名和主菜单都挪到第一战后面。
4. **启动→第一战**：中位数约 35~70 秒，而且其中大半是登录/下载；**扣掉登录和下载，进第一战都在 10~20 秒内**。同类（背包类、皇室战争、荒野乱斗）都 ≤ 21 秒。
5. **第一战必赢**：8 款能判断的里 7 款必赢（剧本对手 / 训练假人 / 名字明写训练 AI），只有 SAP 不保证。必赢的手段都是**对手弱**（假人、剧本、低血量），**没有一款在画面上给玩家方加成并明示**。
6. **字少、一次只讲一件**：大多数一屏 3~12 词、一句指令（「Drag from shop to buy」「Cards cost Energy」「Play Garen」）；长说明只有 TFT 开场一屏和 Underlords（一屏 20~40 词）。规则在**用到那一刻**才出现（Snap 第 1 回合只开一个地点；背包乱斗每轮讲一件新东西）。
7. **系统解锁两派**：
   - **逐个开（手游派）**：皇室战争（战间大厅只有 Battle 钮，宝箱→升级→起名→奖杯路→模式→商店）、Snap（卡组→起名→升级→编辑卡组→模式锁）、LoR（4 关后才开模式）。
   - **一次全开 + 锁排位（PC 移植派）**：TFT、Underlords——教程一结束主菜单全开，只锁 Ranked。
   - 背包乱斗介于两者之间：整局打完才见主菜单，见到时全部可用。

## 与我们现状的差异（00_选择框 / 01_选择3只龟上阵 / 全程时间轴）

我们现在（`docs/plans/img-20261020-教程/`，教程 v3 全程录屏 145 秒）：

| 项 | 我们 | 参考 |
|---|---|---|
| 第一眼 | **完整主菜单**（背包 / 商店「首战后解锁」/ 图鉴 / 排行榜 / 训龟大师 / 积分赛 / 0/11 晋级闯关赛 / 距截止 3 天 8 小时 / 本周对战 0/16 / 两种货币）压暗 + 中间弹框「欢迎来到斗龟场 / 新手教程 / 开始教程 · 跳过」 | 10 款里没有一款第一眼是完整主菜单；只有 TFT 问「Are you new?」 |
| 第一战前 | 选择框 → **选龟屏**（品级页签 全部/SSS/SS/S/A/B/C、羁绊羊皮纸、技能面板、3 个空位）→ 点出战；约 12 秒 | 同类第一战前最多「买一件东西」（背包乱斗）或什么都不做（荒野乱斗、皇室战争直接给卡组） |
| 启动→第一战 | 教程内约 12 秒；加上第一眼主菜单+选择框 | 同类扣掉登录 10~20 秒 |
| 必赢 | 我方增伤 50% / 减伤 30%（「教程加成」点开可见） | 参考里都是**对手弱**（假人、剧本、训练 AI 名字明写），没看到给玩家加成的 |
| 教程长度 | 约 2.5 分钟、1 场战斗 + 13 次点按 | 1~3 场战斗，3~12 分钟；同类（背包乱斗）= 第一整局 |
| 主菜单出现时机 | 第 0 秒 | 第一战之后（皇室战争 1.5 min、背包乱斗 8.5 min、TFT 13 min） |
| 起名 | （新号默认像真人名，未在教程里起） | 多数推迟到第一战之后，不在第一战前 |

## 结论

1. **第一眼**：参考里没有「先给完整主菜单再弹框问要不要教程」的做法。同类的第一眼是**对局本身**（荒野乱斗）或**商店里一件可以拖的东西**（背包乱斗 2026 / 背包战争），手游大作是登录/标题后**直接进战斗**。⇒ 我们的第一眼应换成对局或「选龟/商店的第一步」，主菜单留到第一战之后。是否保留「开始教程/跳过」：参考里只有 TFT 问（且是一句「Are you new?」），炉石是战斗中常驻 Skip——两种都有出处。
2. **多久进第一战**：同类扣掉登录都在 **10~20 秒**内进第一战，期间只做一个动作（买一件 / 拖一张卡）。我们的「选 3 只龟」一屏带品级页签、羁绊、技能面板，信息量远大于参考任何一款的第一屏；参考的共同做法是**先替玩家配好**（皇室战争给卡组、Snap 剧本手牌、背包乱斗给初始物品）。
3. **系统解锁节奏**：同构的手游（皇室战争、Snap）是**第一战后出现极简大厅，再一个一个开**（皇室战争战间大厅只有 Battle 钮）；同类背包游戏是**第一整局打完才见主菜单**。我们现在第一眼就露出背包/商店/图鉴/排行榜/训龟大师/积分赛/闯关赛全部入口。
4. **必赢方式**：参考都用「对手弱」（训练假人 Sir Timothy、Royal Trainer、剧本 Boss 10 血），**没有看到明示给玩家加成的先例**。我们的「增伤 50% / 减伤 30%」是用户 10-20 定的，参考里找不到同款，这一条照用户决定，不据此推翻。
5. **字数**：参考一屏多为 3~12 词的一句指令，规则在用到时才讲；我们现有「赢两个战场获胜，1:1 进入终极战场」「击碎敌方的蛋直接获胜」这类一句话提示与参考一致。

截图目录：本目录下各游戏子文件夹（文件名 = 视频时间码 + 内容），共 93 张。
