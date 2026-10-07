extends Node
## verify_ui_consistency.gd — 全屏 UI 一致性【棘轮门禁】(2026-08-18)
##
## ═══ 为什么要有这个 ═══
## 用户 2026-08-18:「那到底还有哪些问题呢, **怎么这么多没想到的呢**, 你得在迭代里都解决」。
##
## 根因不是"我不够细", 是**我每条判据都只在当时那一块上建过, 从没铺到全屏**:
##   · 网页盒判据建在战斗信息面板 → 图鉴 45 个 / 选龟 43 个网页盒躺了一整晚没人查
##   · 死点击判据只认 `gui_input`, **完全覆盖不到 Button**(按钮走 pressed 信号)
##   · 探针实例化的是**空背包**, 33 格 6 卡根本没建 ⇒ 报"背包 0 网页盒"是假绿
##   · 换框之后内容区变小、文字压在金属边带上 —— 这一整类**我自己造的**毛病,
##     前十条判据一条都逮不到(实测 71 处)
##
## ⇒ 这张表是 13 条判据 × 7 个屏, 每格记基线, **只许降不许升**。
##   「忘了查另外几屏」从此不是"我要记得", 而是**结构上做不到**。
##
## ═══ 13 条判据(全部量真实矩形/真实像素, 不搜源码字符串) ═══
##   1 网页盒   StyleBoxFlat 四边有边框 + 底半透明 = CSS border+rgba 的长相(★主指标)
##   2 圆角盒   corner_radius > 0
##   3 默认皮   Button 非 flat 且没换过皮 —— 圆角纯色是"没游戏味"最直接的来源
##   4 死点击   BaseButton / 接了 gui_input, 却 MOUSE_FILTER_IGNORE
##   5 热区     短边 < 44pt 且长边 < 200px(真正难点的形状, 不含整行整列)
##   6 截断     clip_text 且真实字宽 > 真实矩形宽
##   7 挤没     有字但宽或高 < 6px
##   8 压扁     九宫格边距和 ≥ 实际尺寸 ⇒ 中段为负, 框根本画不出来
##   9 溢出     Label 要的行数 > 装得下的行数
##  10 压字     两段【不同】的文字矩形相交 > 25%
##  11 压边带   文字真实字块越出框的内容区
##  (12/13 = 分母: 每屏可见控件数、全局按钮/标签数)
##
## ═══ ★★2026-09-28 补两列: 每条判据**认得哪些节点类型** / 每屏量的是**全部还是第一个样本** ═══
## 不写这两列, 「这屏 0 违规」会被读成「这屏没问题」, 而实际可能是
## 「判据认不出那种节点」或「只量了列表第一条」。两个都栽过:
##
## | 判据 | 认得哪些节点类型 | 已知认不出的 |
## |---|---|---|
## | 1 网页盒 / 2 圆角盒 | 任意 Control 的 `panel/normal/background/fill` 四个 StyleBox 槽 | 别的槽名(`hover`/`pressed`/`focus`)；`_draw()` 自绘的框 |
## | 3 默认皮 | `Button` 且非 flat | 别的 `BaseButton` 子类(CheckBox/OptionButton 的皮没查) |
## | 4 死点击 / 5 热区 | `BaseButton` · `Range`(滑条) · `LineEdit` · `TextEdit` · 接了 `gui_input` 的任意控件 | **裸 `Control` 靠 `MOUSE_FILTER_STOP` 吃点击**——规模见下面 `mfstop` 分母 |
## | 6 截断 / 7 挤没 / 9 溢出 | `Label` | `RichTextLabel`(只进压字, 不进这三条)；`Button` 自己的 text |
## | 8 压扁 | `NinePatchRect` | `StyleBoxTexture` 铺出来的框 |
## | 10 压字 | `Label` + `RichTextLabel` | `Button` 的 text；Sprite/自绘文字 |
## | 11 压边带 | `NinePatchRect` · `StyleBoxTexture` 槽 · 拉伸成框的 `TextureRect` | `_draw()` 自绘的框 |
##
## | 屏 | 量到的是全部还是第一个样本 |
## |---|---|
## | MainMenu / Settings / Record / Leaderboard / BracketMap / TrainerConfig | **全部**(整棵树) |
## | Inventory / TeamSelect / Shop | **全部**(灌了 demo 数据/真池, 33 格 6 卡 / 28 张龟卡 / 10 张货架卡都在场) |
## | Codex | ★**只有第一条**——列表只渲染选中那一行的详情。实证: `detail_views.gd:571` 的形态切换钮 `_add_rect(196, 34, …)`, `34 < UISkin.MIN_FRAME_PX(40)` ⇒ `nine_if_big` **静默退回 StyleBoxFlat**(= 网页盒), 而它**只有双形态龟**(双头/熔岩)才画 ⇒ 量图鉴时永远碰不到。**这一格是已知欠账, 不是 0 违规。** |
## | 弹层(第二节) | **全部**(整棵树, 开弹层前后各量一次判增量) |
##
## ═══ 三个"判据本身会不会骗我"的堵口(每个都是今晚栽出来的) ═══
## ① **分母**: 每屏必须真的扫到控件, 否则 = 场景没建起来的假绿(今晚踩过 6 次)
## ② **边带宽度从贴图里量, 不读配置边距**: panel-frame 配置 20 → 真实边带 13;
##    slot-frame 配置 12 → 真实 6。拿配置值当尺子会高估碰撞、报一堆假的。
##    空心框(中间透明)要从外往内扫, 否则返回半个贴图宽(card-frame 72px 报过 36)。
## ③ **量真实字块, 不量控件矩形**: 列表行的 Label 占满 52px 行高但字是垂直居中的,
##    拿控件矩形量会把"稳稳在行中间"的字报成压边带 13px。**尺子要匹配被测概念。**
## ④ **配对要看节点树, 不能只看屏幕坐标**(2026-09-28): 屏幕坐标是**扁的** ——
##    弹框一盖上来, 「页面上的字」与「弹框里的框」在屏幕上就重叠了, 而它们根本不在同一层。
##    实测这一条造了 **5 条假违规里的 4 条**(设置屏 3 条 + 背包弹层 4 条, 两个方向都有)。
##    ⇒ 见 `_frame_owns`: 只认「框是字的祖先」与「同父兄弟」两种关系, 自检见 `_selftest_frame_pairing`。

## 墙那句话的唯一出处 —— 测试不许自己拼。
const _P2CX := preload("res://scripts/gamedata/phase2_config.gd")
## 池注入那个 static 字段的**唯一出处** —— 判据要量产品自己的账。
const _BE := preload("res://scripts/net/backend.gd")

const TOUCH_MIN := 81.0

## ★明细开关。**默认关**, 门禁行为一字不变(判据、基线、分母全不动);
## `UICONS_DUMP=1` 时额外打一份「命中的是谁」—— 整改前要的是清单, 不是个数。
##
## ★★为什么必须有这一步: 这张表只**数个数**(背包 10 个网页盒 / 选龟 61 个圆角盒)。
##   拿个数当整改清单, 一定会改到**已拍板要保留的**那批上 —— 本文件 :68 和
##   `InventoryScene.gd:467` 都写着那批 26px 迷你格 2026-08-18 实拍后故意退回过
##   (换金属槽框会让费用色从整块实心退化成一圈细边, 而那块实心色本身就是信息)。
var _DUMP: bool = OS.get_environment("UICONS_DUMP") != ""

## 每屏基线(上界)。**只许改小, 不许改大** —— 要放大必须在 CHANGELOG 里写清为什么。
## 商店库存是随机的(实测 0~2 网页盒 / 11~13 圆角盒), 所以它那两格取上沿。
## ★MainMenu 的 frame 1 = 木牌上的 36x36 图标越过边带 **2px**。边带是从贴图上量的近似值,
##   ±2px 在测量误差里, 实拍看就是好的 —— 卡 0 等于让判据去修一个不存在的问题。
##
## ★"tap" = 短边 < 81px(44pt) 的可点元素上限。剩下的 18 个各有理由, 不是漏做:
##   · TeamSelect 1 个 = **被动小签**(179×44)。点它是**手机上读被动描述的唯一途径**, 该达标 ——
##     但右列的竖向预算不够, 这是算过的: 立绘顶 144 → CTA 顶 715 = 571 设计单位可用;
##     立绘 156 + 名 26 + 属性 58 + 被动 104(=81px@PC 0.777) + 技能 259(2×2 的 81px 格) = 603。
##     **差 32 个单位, 唯一的slack是立绘**(要缩 21%)。⇒ 这是一个**要拿美术尺寸换**的取舍,
##     不是我漏做, 留给用户拍板。其余 4 个(返回/清空/上次阵容/开始冒险)已用 `_grow_to_touch()`
##     在**像素层绕中心**撑到 81 —— 底板烤在图上, 绕中心长文字就纹丝不动。
##   · Inventory 8 个迷你装备格: 版式极限(见下), 已另给 81px 的「卸下」主路径。
##   · Inventory 3 个前/后排小钮(56×44): 单位卡只有 244×116, 一个 81×81 的靶子摆在右上角会**盖住整卡的三分之一**
##     (卡里还有立绘/名字/三个装备格)。它切的是随从的前排/后排站位, 不是主路径。
##   · MainMenu 1 个调试入口: 不是玩家路径, 见下。
##
## ★两处**不是余量、是有理由的豁免**(别当成"还没改完"):
##   · MainMenu 的 1 个 = 右下角调试入口 120x46。它**不是玩家路径**, 刻意保持朴素,
##     和正式按钮长得不一样正是想要的效果。
##   · Inventory 的 10 个 = 单位卡上的 40x40 迷你装备格。2026-08-18 实拍对比后**退回过一次**:
##     换金属框会让**费用色从整块实心退化成一圈细边**, 而那块实心色本身就是信息
##     (一眼分得出 2/3/4/5 费)。⇒ 贴图框有它的最小可用尺寸, 小于它就该保持纯色块。
const BASE: Dictionary = {
	## ★2026-09-18 版式重做后按实测重定(基线只降不升, 见本表末尾 Record 那条的规矩):
	##   web 1→0 / round 3→0 / tap 1→0 —— 赛程条改成【不描边 + 直角】后, 主菜单
	##     一个网页盒、一个圆角盒都不剩了(圆角与"border+半透底"正是用户 2026-08-15 点名的 ai 味)。
	##   frame 1→2 —— **不是放宽标准, 是同一口径下元素变多**: 这条量的是"图标顶破框",
	##     而两个货币芯片各贡献 1 个【已知误报】(实拍放大确认图标四边都有余量、稳稳在框内,
	##     与本文件第 268 行记的"28 张龟卡头像全被报成压边带 3px"是同一类)。
	##     以前基线 1 容忍的就是龟币那一个; 现在多了深海币芯片(用户要求两种货币并排显示),
	##     所以是 2。★要真正解决得让判据量【图标 vs 框贴图的实际内容区】而不是控件矩形 —— 未做。
	"MainMenu": {"web": 0, "round": 0, "frame": 0, "tap": 0},   # frame 1→0(2026-10-06): 九宫格边越过切口改量切口条内描边后, 训龟大师铁箍木板那条量尺假象(横向端花 37px 当竖向边带)消失; 方键 4 字 4 图标实测 0
	"Inventory": {"web": 10, "round": 19, "frame": 0, "tap": 11},
	"Codex": {"web": 0, "round": 0, "frame": 0, "tap": 0},
	## ★★2026-09-27 61 → 32: 稀有度小签(S/A/B/C/SS/SSS)改**直角**, 一个函数掉 29 个
	##   (`_make_rarity_badge` —— 28 张龟卡各一枚 + 详情面板 1 枚)。
	## ⚠ 剩下的 32 里 **28 个是被动图标的正圆底**(`pet_grid.gd:154`, 26x26 半径 13)。
	##   正圆**不是**用户说的那味(他点名的是 border-radius 的圆角**矩形**), 刻意留着。
	##   ⇒ 判据一个字没放宽 —— 宁可让它数着, 也不为了数字好看去改判据。
	"TeamSelect": {"web": 0, "round": 32, "frame": 0, "tap": 1},
	# 商店货架随机 ⇒ 它这两格是**容差基线**(实测跨多次运行 0~3 网页盒 / 11~14 圆角盒)。
	# 卡到实测上沿会偶发红; 而真回归是数量级的(31 vs 0), 容差 +1 挡不住的场面不存在。
	## ★★2026-09-27 11 → 0: 门禁明细量出来 = **10 张货架卡的底板**(132x136)
	##   + 1 个详情面板底板(440x592)。两处都只是**底板** —— 看得见的边是
	##   `card-frame-t*.png` / `panel-frame.png` 那些不透明像素框画的, 圆角本来就
	##   被盖住 ⇒ 实拍确认**视觉零变化**(裁 2 倍看: 角铆钉照旧)。
	"Shop": {"web": 0, "round": 0, "frame": 0, "tap": 0},
	"Settings": {"web": 0, "round": 0, "frame": 0, "tap": 0},
	## ★★2026-08-21 重定基线 —— 旧的 0 是**空档占位屏**的数字(可见控件只有 10 个),
	##   钉死合成对局记录之后量到的是**真正的 Record 屏**(98 个控件): 圆角盒 18 个。
	##   ⇒ 这 18 个是**一直存在、却因为量错了屏而从没被这条门禁看见**的换皮欠债,
	##     不是新增的回归。按真实数字登记, 从此只降不升。
	## ★★2026-09-27 18 → 0: 门禁明细量出来这 18 个 = **12 个头像框**(36x36)
	##   + **6 行对局行**(760x52「胜」/「负」) —— 两个函数(`_avatar` / `_match_row`)。
	##   都改成直角; 对局行**左边那条 4px 的胜负色留着**(它是一眼分胜负的那一维)。
	"Record": {"web": 0, "round": 0, "frame": 0, "tap": 0},
	## ★★★【登录墙】= Settings + 强制「后端开着且邮箱为空」(`acct_override = 1`)。
	##   这一屏是**每个新玩家开游戏看到的第一屏**(关不掉、返回键都藏了), 而门禁
	##   **至今一次都没量过它** —— 门禁给每个测试 `TURTLE_BACKEND=" "`(有意关后端),
	##   于是墙与账号 UI 从不建出来(memory `fb-gate-subject-never-constructed`)。
	##   2026-09-27 拿真后端一跑, 当场 4 条: 默认皮按钮 ×4 / 热区不足 ×4 / 文字相撞 / 圆角盒 ×1。
	##   ⇒ 基线**先按实测如实登记**, 修完再往下拧(棘轮只许降)。
	## ★2026-09-28 round 1→0 / tap 2→0: 查触摸那轮把墙**第一次真正量到**之后的实测值。
	##   (在那之前这一屏在两个触摸门禁里都**不在场** —— 门禁给 `TURTLE_SUPABASE=" "`,
	##    `SB.enabled()` 恒假 ⇒ 墙根本没建起来, 扫到的是普通设置页。)
	##   ★基线停在比实测高的数 = 给那个 bug 留了回来的路。棘轮只许降。
	"登录墙": {"web": 0, "round": 0, "frame": 0, "tap": 0},
	## ★★★2026-09-27 补上剩下 4 个屏 —— 它们至今**一条判据都没量过**。
	##   `scenes/` 下 12 个场景, 这张表原来只有 7 个。缺的偏偏是:
	##   BracketMap(周日对阵图, 整天都在看) / Leaderboard / 
	##   **Matchmaking(每一局对局之间都过)** / TrainerConfig。
	##   ⇒ 「把 UI 做得更商业」在没人量的屏上做不完。
	## ★★2026-09-28 round 7 → 0(棘轮只许降): 上一轮把节点/页签/空态框全换成
	##   直角 + 九宫格之后, 实测就是 **0** —— 7 是登记时那一版的数字。
	##   ⚠ 只降不升这条规矩的**另一半**是"量到 0 就登 0", 否则棘轮空转 7 格,
	##     期间任何一个新圆角盒溜回来都不会红。
	"BracketMap": {"web": 0, "round": 0, "frame": 0, "tap": 0},
	## ★★★排行榜/撮合 —— 这两屏 2026-09-27 差点被登记成**占位屏的基线**:
	##   量出来 web/round/frame/tap 全 0, 看着干净, 而排行榜自带的分母打出来是
	##   `[LB] rows=1`(**榜上只有我自己一行**)。登记那个 0 等于让棘轮去守一块空屏
	##   —— 本仓 Record 2026-08-21 正是这样, 基线 0 守了一整个空档屏,
	##   真屏 18 个圆角盒从没被看见。⇒ **已知量错状态的基线, 一个都不登记。**
	##   现在走 `Backend.pool_override` 灌 14 条真人快照, 量的是**真榜**。
	"Leaderboard": {"web": 0, "round": 0, "frame": 0, "tap": 0},
	## ★★★**Matchmaking —— 2026-09-28 终于进表了**。它原来没进表不是漏登记:
	##   `_ready` 里两个计时器(2.2s + 2.6s)到点就 `change_scene_to_file` 进战斗
	##   ⇒ 门禁刚把这一屏建起来、还没量完, **它就把门禁自己拆了**
	##   (`get_tree()` 变 null, 后面断言连跑都没跑, 而且**没打 ALL PASS**、rc 还是 0 ——
	##    `verify_mainmenu_layout` 2026-09-26 因此一周有两天整份不算数)。
	##   ⇒ 这是「被测对象不在场」的第**四**种形状: **它在场过, 但撑不到被量。**
	##   ★缝 = `MatchmakingScene._may_leave_for_test`(static Callable, 无效 = 不生效),
	##     只管「什么时候走」。下面 `_mm_*` 那一节带三层分母。
	## ★★对手卡是 **2.2 秒后**才建的 ⇒ 早量到的那十几个控件是「正在找对手」
	##   那块**占位屏**。所以量之前要先等到对手名上屏(`_mm_wait_vs`),
	##   而不是拿 `_settle()` 的 MIN_WAIT 碰运气 —— 2.0s 的 MIN_WAIT 就在 2.2s 前面,
	##   雷达环恰好有六帧不动的话它当场量到占位屏(「靠运气绿」就是这个形状)。
	## ★★★基线 = **2026-09-28 首次量到就如实登记**的存量(棘轮只许降):
	##   web 0 / round 0 / tap 0 / frame 0。
	##   ★窗口控件只有 20 个而已(两张卡 x 5 + 标题/勾/VS + 背景 + 顶栏),
	##     这一屏本身就简 —— 但「简」不等于「不用量」, 上一个理由就是这么说的。
	"Matchmaking": {"web": 0, "round": 0, "frame": 0, "tap": 0},
	## ★2026-09-28 frame 7 → 0: 那个 7 是「卡太短 + 只调 inset」那一版的读数。
	##   真因查清后(内容最小高 102 > 内容区 94, 而 `offset_bottom` 被
	##   `get_combined_minimum_size()` 夹住根本没生效)把卡加高 14px, 实测已是 0。
	##   ★基线停在比实测高的数 = 给那个 bug 留了回来的路, 棘轮只许降。
	"TrainerConfig": {"web": 0, "round": 1, "frame": 0, "tap": 0},
}

## 分母下限: 这一屏至少该扫到这么多可见控件。少于它 = 场景没建起来, 下面的"0 问题"全是假的。
const MIN_CTRL: Dictionary = {
	## 登录墙: 设置页本体 + 墙(遮罩/框/标题/正文/昵称/两输入/两钮/状态) —— 少于这个数 = 墙没弹出来。
	## ★★登录墙立起来后**背后的设置页是藏掉的**(墙关不掉, 背后没有可用的东西),
	##   所以这一屏就只剩墙本身 ≈ 12 个控件。
	## ⚠ 而「控件下限」对这一屏**挡不住真正的回归**: 墙要是哪天不弹了,
	##   控件会变**多**(整个设置页 ~35 个)而不是变少, round/tap 又都是 ≤ 判据
	##   ⇒ 整行会一路绿, 量的却是另一块屏。⇒ 真分母是下面那条「墙那句话在不在」。
	"登录墙": 10,
	"BracketMap": 40, "TrainerConfig": 50,
	## ★排行榜: 面板 + 表头 + 11 行 ⇒ 灌了池就该有这么多。19 = 只有我自己那一行(占位屏)。
	"Leaderboard": 30,
	"MainMenu": 20, "Inventory": 120, "Codex": 120,
	## ★撑合屏: VS 态实测 **20** 个(两张卡 x 5 + 「已匹配到对手!」+ 勾 + VS
	##   + 底色/渐变/content_root + 顶栏 3)。而「正在找对手」那块占位屏只有 9~12 个
	##   ⇒ 18 这条线正好把两者分开。★但它**不是**这一屏的真分母——
	##   真分母是「对手名真的在屏幕上」(见 `_mm_wait_vs`), 同登录墙那一条的道理。
	"Matchmaking": 18,
	## ★Record 下限从 10 提到 80: 10 是占位屏也能过的数, 等于分母没起作用。
	"TeamSelect": 150, "Shop": 60, "Settings": 10, "Record": 80,
}

## 本屏用的池种子脚本(用完要 `clear()` —— `pool_override` 是 static)。
var _lb_seed = null
var _pass := 0
var _fail := 0
var _band_cache: Dictionary = {}


func _ok(nm: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [nm, detail])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [nm, detail])


## 量【贴图里真实画出来的边带有多厚】—— 不用九宫格配置的边距。
## 配置边距是"从哪切开去拉伸", 不是"画了多宽的边"; 实测两者差近一倍。
## 这张贴图"是不是一个框" —— 只看图, 不看文件名(名字是我起的, 拿它当判据等于"我说是就是")。
##
## 这条判据我连着写窄、写宽各一次, 把两次的结论都留下:
##   · 写"中心必须全透" ⇒ 漏掉 `menu/btn-frame.png`(中心是**实心木板** alpha 254),
##     设置屏三个按钮的框一个都没进过 framed, 「低画质模式: 关 (高画质)」压边压了很久没人报。
##   · 写"内部匀色 + 有边带" ⇒ **背景平铺图也算框**了, 一下多出 35 条假阳(选龟 26 / 主菜单 9)。
##   · 光加"不占大半个屏"还不够: 24x24 的小图标带个圈边也算框 ⇒ 还得要求**它大得装得下一行字**
##     (面积 ≥4000 且短边 ≥40)。
## 最后落在: `_band_of` 量得到边带(它本来就分空心/实心两支) + **边带占比像个"边"**(3%~30%)。
## 尺度约束(不占大半个屏)放在调用点 —— 那里才知道控件实际多大。
var _frame_cache: Dictionary = {}

func _is_frame_tex(tex: Texture2D) -> bool:
	var key := tex.resource_path
	if _frame_cache.has(key):
		return bool(_frame_cache[key])
	var img := tex.get_image()
	var ok := false
	if img != null and img.get_width() >= 16 and img.get_height() >= 16:
		var b := _band_of(tex)
		## 比例要和**扫描方向的那个维度**比 —— `_band_of` 是横着从中心往外扫的。
		## (拿高度比会把 893x212 的按钮板判成"边带占 48%"而排掉, 正是它一直没被查的原因之一。)
		ok = b >= 3.0 and b <= 0.35 * float(img.get_width())
	_frame_cache[key] = ok
	return ok

func _band_of(tex: Texture2D) -> float:
	var key := tex.resource_path
	if _band_cache.has(key):
		return float(_band_cache[key])
	var img := tex.get_image()
	if img == null:
		return 0.0
	var w := img.get_width()
	var h := img.get_height()
	var cx := w / 2
	var cy := h / 2
	var ctr := img.get_pixel(cx, cy)
	var bl := 0
	var bt := 0
	if ctr.a < 0.04:
		for x in range(0, cx):
			if img.get_pixel(x, cy).a < 0.04 and x > 0:
				bl = x
				break
		for y in range(0, cy):
			if img.get_pixel(cx, y).a < 0.04 and y > 0:
				bt = y
				break
	else:
		for x2 in range(cx, 0, -1):
			var c := img.get_pixel(x2, cy)
			if c.a < 0.04 or maxf(maxf(absf(c.r - ctr.r), absf(c.g - ctr.g)), absf(c.b - ctr.b)) > 0.12:
				bl = x2
				break
		for y2 in range(cy, 0, -1):
			var c2 := img.get_pixel(cx, y2)
			if c2.a < 0.04 or maxf(maxf(absf(c2.r - ctr.r), absf(c2.g - ctr.g)), absf(c2.b - ctr.b)) > 0.12:
				bt = y2
				break
	var band := float(maxi(bl, bt))
	_band_cache[key] = band
	return band


## 真正画出来的那块字的矩形(不是 Label 控件的矩形)。
## 是不是"浮在内容上的提示层"(toast) —— 这类重叠是设计如此, 不是 bug。
func _is_toast(c: Control) -> bool:
	var n := c
	var hop := 0
	while n != null and hop < 4:
		var nm := str(n.name).to_lower()
		if nm.findn("status") >= 0 or nm.findn("toast") >= 0 or nm.findn("flash") >= 0:
			return true
		n = n.get_parent() as Control
		hop += 1
	return false


func _ink_rect(l: Label) -> Rect2:
	var r := l.get_global_rect()
	var f: Font = l.get_theme_font("font")
	if f == null:
		return r
	var fs: int = l.get_theme_font_size("font_size")
	var ts: Vector2 = f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		ts.x = minf(ts.x, r.size.x)
		ts.y = float(maxi(l.get_visible_line_count(), 1)) * f.get_height(fs)
	var w: float = minf(ts.x, r.size.x)
	var h: float = minf(ts.y, r.size.y)
	var x := r.position.x
	match l.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			x = r.position.x + (r.size.x - w) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			x = r.position.x + (r.size.x - w)
	var y := r.position.y
	match l.vertical_alignment:
		VERTICAL_ALIGNMENT_CENTER:
			y = r.position.y + (r.size.y - h) * 0.5
		VERTICAL_ALIGNMENT_BOTTOM:
			y = r.position.y + (r.size.y - h)
	return Rect2(x, y, w, h)


## 等到【版面真的不动了】再量。
##
## ★由来(2026-08-18): 原来固定等 14 帧就量, 而好几个屏有**入场动画**(木牌从左边滑进来)。
##   实测主菜单的「排行榜」「图鉴」两个标签此时 global x = **−485**, 还在屏幕外,
##   而且两者**报同一个矩形** ⇒ 压字判据当场报"排行榜压图鉴", 可实拍两块木牌离得远远的。
##   **量了一个还在动的东西 = 量了个不存在的画面。**
## ⇒ 改成轮询: 每帧把所有可见控件的矩形加起来求和, 连续 6 帧不变才算稳住(上限 240 帧兜底)。
##
## ★★2026-08-22 第二次栽在同一处, 这次是【尺子】不是判据: 上限原本是 **240 帧**。
##   无头 CI 帧率极高、每帧只推进极少动画时间 ⇒ 240 帧根本等不到落位,
##   于是**又一次量了还在半空中的画面**, 报出「排行榜压图鉴」(CI 红、本地绿)。
##   这正是 CLAUDE.md §3.5 那条: **等游戏内效果一律用墙钟, 别用帧数**。
##   而且原来等不到也**不吭声**, 直接往下量 —— 静默截断比报错更坏, 因为它会
##   把"没等到"伪装成"真的压字了"。⇒ 改墙钟 + 返回是否真的稳住, 调用方必须断言。
## 【尺子】墙钟, 不是帧数。tween 走**真实时间**, 与帧率无关 ⇒
##   本地 240 帧 ≈ 4 秒(够), CI 无头帧率极高 240 帧 ≈ 0.2 秒(远远不够)。
## 【判据】**不能**要求"完全静止" —— 实测 7 个屏里有 4 个带常驻动效(永远在动),
##   原来的 240 帧上限只是把这件事盖住了。⇒ 分两段:
##   ① 先无条件等够 `MIN_WAIT` 墙钟秒(入场动画都 ≤1 秒, 2 秒足够它跑完);
##   ② 再尽量等"稳住"(给常驻动效的屏一个提前退出的机会), 上限 `MAX_WAIT`。
##   返回值 = 有没有真的稳住, 只作**信息**用 —— 它为 false 是正常的(常驻动效),
##   不该当失败。真正保证"量的不是半空中的画面"的是 ①。
const MIN_WAIT := 2.0
const MAX_WAIT := 8.0

func _settle(root: Node) -> bool:
	var last := -1.0
	var same := 0
	var _t0: float = float(Time.get_ticks_msec()) / 1000.0
	while float(Time.get_ticks_msec()) / 1000.0 - _t0 < MAX_WAIT:
		await get_tree().process_frame
		if float(Time.get_ticks_msec()) / 1000.0 - _t0 < MIN_WAIT:
			continue                      # ①入场期: 只等, 不判稳
		var acc := 0.0
		var st: Array = [root]
		while not st.is_empty():
			var n: Node = st.pop_back()
			if n is Control and (n as Control).is_visible_in_tree():
				var r := (n as Control).get_global_rect()
				acc += r.position.x + r.position.y * 3.0 + r.size.x * 7.0 + r.size.y * 11.0
			for ch in n.get_children():
				st.append(ch)
		if absf(acc - last) < 0.5:
			same += 1
			if same >= 6:
				return true
		else:
			same = 0
		last = acc
	return false


var _bbox_cache: Dictionary = {}


## 贴图里【真正有像素的那一块】在 0~1 归一坐标下的包围盒。
##
## ★由来: 龟/小将立绘四周都有大片透明留白(94x104 的框里, 实际画面可能只占中间 70%)。
##   只把控件矩形按 stretch 换算, 得到的还是"含留白的那块", 于是 28 张龟卡的头像、
##   6 张小将卡的立绘、28 个稀有度角标**全被报成压边带 3~7px** —— 而实拍它们稳稳在框里。
##   这是同一个错的第 9、10 次: **量真正画出来的东西, 不是量装它的盒子。**
func _opaque_bbox(tex: Texture2D) -> Rect2:
	var key := tex.resource_path
	if _bbox_cache.has(key):
		return _bbox_cache[key]
	var img := tex.get_image()
	var bb := Rect2(0, 0, 1, 1)
	if img != null and img.get_width() > 0:
		var w := img.get_width()
		var h := img.get_height()
		var x0 := w
		var y0 := h
		var x1 := -1
		var y1 := -1
		var step: int = maxi(1, int(maxf(float(w), float(h)) / 96.0))   # 大图抽样, 够用且不慢
		for y in range(0, h, step):
			for x in range(0, w, step):
				if img.get_pixel(x, y).a > 0.06:
					x0 = mini(x0, x)
					y0 = mini(y0, y)
					x1 = maxi(x1, x)
					y1 = maxi(y1, y)
		if x1 >= x0 and y1 >= y0:
			bb = Rect2(float(x0) / float(w), float(y0) / float(h),
				float(x1 - x0 + 1) / float(w), float(y1 - y0 + 1) / float(h))
	_bbox_cache[key] = bb
	return bb


## 把"画出来的矩形"再按贴图的不透明包围盒收一圈。
func _crop_alpha(drawn: Rect2, tex: Texture2D) -> Rect2:
	var bb := _opaque_bbox(tex)
	return Rect2(drawn.position + Vector2(bb.position.x * drawn.size.x, bb.position.y * drawn.size.y),
		Vector2(bb.size.x * drawn.size.x, bb.size.y * drawn.size.y))


## 真正画出来的那块图的矩形(不是 TextureRect 控件的矩形)。
func _art_rect(t: TextureRect) -> Rect2:
	var r := t.get_global_rect()
	var ts: Vector2 = t.texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return r
	match t.stretch_mode:
		TextureRect.STRETCH_KEEP:
			return _crop_alpha(Rect2(r.position,
				Vector2(minf(ts.x, r.size.x), minf(ts.y, r.size.y))), t.texture)
		TextureRect.STRETCH_KEEP_CENTERED:
			var kc: Vector2 = Vector2(minf(ts.x, r.size.x), minf(ts.y, r.size.y))
			return _crop_alpha(Rect2(r.position + (r.size - kc) * 0.5, kc), t.texture)
		TextureRect.STRETCH_KEEP_ASPECT, TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
			var k: float = minf(r.size.x / ts.x, r.size.y / ts.y)
			var sz: Vector2 = ts * k
			if t.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
				return _crop_alpha(Rect2(r.position + (r.size - sz) * 0.5, sz), t.texture)
			return _crop_alpha(Rect2(r.position, sz), t.texture)
		_:
			pass          # SCALE / COVERED: 铺满整个矩形, 直接进下面的留白裁剪
	return _crop_alpha(r, t.texture)


## 一个控件里**第一段可见文字**(含 Button 自己的 text) —— 明细用它认是谁。
func _first_text(c: Node) -> String:
	if c is Button and str((c as Button).text).strip_edges() != "":
		return str((c as Button).text).substr(0, 12)
	var st: Array = [c]
	while not st.is_empty():
		var n = st.pop_front()
		if n is Label and str((n as Label).text).strip_edges() != "":
			return str((n as Label).text).replace("
", "/").substr(0, 12)
		if n is Button and str((n as Button).text).strip_edges() != "":
			return str((n as Button).text).substr(0, 12)
		for ch in n.get_children():
			st.append(ch)
	return "(无字)"


## 这个控件**玩家能不能操作它** —— 「死点击」「热区不足」两条判据的入口。
##
## ★★2026-09-28 补【判据只认某类节点】这条失明: 原来写的是
##   `c is BaseButton or c.gui_input.get_connections().size() > 0`。
##   有人把音量滑条把手设成 `MOUSE_FILTER_STOP`(**裸 `Control`**, 能吃点击)
##   做反向验证 —— **判据没红**。⇒ 滑条把手、拖拽区、自绘点击块全在盲区里。
## ★收哪几类是**按本仓真实用到的交互原语**列的, 不是我想象的:
##   `Range`(HSlider/VSlider/SpinBox —— 设置屏的音量/画质滑条是 `Range`, **不是** BaseButton)
##   `LineEdit` / `TextEdit`(登录墙的昵称与邮箱输入框)
##   接了 `gui_input` 的任意控件(羁绊小签、糖果罐格子都是这么做的)
## ★**没有**把"所有 MOUSE_FILTER_STOP 的控件"都收进来: Godot 里 Panel /
##   PanelContainer / ColorRect 默认就是 STOP, 收了会满屏噪音, 而噪音门禁等于没门禁。
##   剩下那一片有多大, 由 `d["mfstop"]` 这个**分母**如实报出来。
## ★★2026-09-28 `c is Range` 收窄成「能被拖动的那几种」。
##   `ProgressBar` 也是 `Range`, 而它是**只读读数** —— 给它 `MOUSE_FILTER_IGNORE` 是对的,
##   按原来的写法会被判成「死点击」⇒ 三条假违规(实测: 战斗面板的血条/能量条)。
##   查登录墙触摸那轮的 agent 第一版也写 `Range`, 当场撞到同一批, 已收窄。
func _interactive(c: Control) -> bool:
	return c is BaseButton or c is Slider or c is SpinBox or c is ScrollBar \
		or c is LineEdit or c is TextEdit \
		or _wired_from_outside(c)


## `gui_input` 上**外面**有人接吗(引擎自己接的那条不算)。
##
## ★★2026-09-28 由来(探针 `tests/_probe_wire2.gd` 实测): `RichTextLabel` 一进场景树,
##   它**内部的 `VScrollBar`** 就会把 `ScrollBar::_drag_node_input` 接到宿主的
##   `gui_input` 上 —— `scroll_active = false` 与 `mouse_filter = IGNORE` 都关不掉它。
##   ⇒ 照原来那句 `gui_input.get_connections().size() > 0`, **每一个** RichTextLabel
##   都被判成"接了 gui_input 的交互控件"。这条失明是**双向**的:
##     · 小尺寸的 RTL 文字(羁绊 chip 那类 97×16)被算成「热区不足」
##     · 而它们本来就设了 `MOUSE_FILTER_IGNORE` ⇒ 又被算成「死点击」
##   两边都是**假违规**, 而真正该抓的小按钮就埋在这些噪音里(噪音门禁等于没门禁)。
## ★判据平移到语义本身:「**外面**有人给它接了点击处理」——
##   回调对象是本控件自己、或本控件的内部子节点(RTL 的滚动条那类), 一律不算。
##   真接线(`chip.gui_input.connect(func(e): …)`)的回调对象是**脚本实例**, 不在这棵子树里。
func _wired_from_outside(c: Control) -> bool:
	for cn in c.gui_input.get_connections():
		var cb: Callable = cn.get("callable")
		var o = cb.get_object()
		if o == null:
			continue
		if o is Node and (o == c or c.is_ancestor_of(o as Node)):
			continue                      # 引擎自己的内部件
		return true
	return false


## 九宫格「切口条」里的边: 沿贴图中线, 在四条切口条(左/右/上/下)里各找**最暗**的那道线
##   (像素框的内描边; 同样暗时取最靠里的), 边 = 从外沿到那道线(含)。返回 (横向边, 竖向边) 各取两侧较大者。
## ★只给 `_band_of` 量越过切口的那种框兜底用(见调用点), 结果天然 ≤ 切口。
func _nine_outline_band(np: NinePatchRect) -> Vector2:
	var img := np.texture.get_image()
	if img == null:
		return Vector2.ZERO
	var w := img.get_width()
	var h := img.get_height()
	var cx := w / 2
	var cy := h / 2
	var res := Vector2.ZERO
	## [起点(切口线), 终点(外沿), 是否横向]
	var sides := [
		[mini(np.patch_margin_left, cx) - 1, 0, true],
		[w - mini(np.patch_margin_right, cx), w - 1, true],
		[mini(np.patch_margin_top, cy) - 1, 0, false],
		[h - mini(np.patch_margin_bottom, cy), h - 1, false],
	]
	for s in sides:
		var a: int = int(s[0])
		var b: int = int(s[1])
		var horiz: bool = bool(s[2])
		var step: int = -1 if b < a else 1
		var best_l := 9.0
		var best_i := -1
		var i := a
		while true:
			var px: Color = img.get_pixel(i, cy) if horiz else img.get_pixel(cx, i)
			if px.a >= 0.04:
				var lum: float = 0.299 * px.r + 0.587 * px.g + 0.114 * px.b
				if lum < best_l - 0.001:
					best_l = lum
					best_i = i
			if i == b:
				break
			i += step
		if best_i < 0:
			continue
		var band: float = float(best_i + 1) if step < 0 else float((w if horiz else h) - best_i)
		if horiz:
			res.x = maxf(res.x, band)
		else:
			res.y = maxf(res.y, band)
	return res


## 【这个框管得着这段字吗】—— 「压边带」第 11 条判据的**配对**规则。
##
## ★★由来(2026-09-28, 探针 `tests/_probe_settings_frame.gd` 实测): 原来的配对只有一句
##   「取**屏幕坐标**上包住字块中心的**最小**框」—— 而屏幕坐标是**扁的**, 它认不出
##   「这两个东西根本不在同一层」。设置屏一开弹框, 三条假违规当场全冒出来:
##
##   | 报的 | 真配到的框 | 实际关系 |
##   |---|---|---|
##   | `画质「高」+6`(页面上的按钮) | 弹框里的**「先不选」按钮**(520,452 240x48) | 弹框盖在它上面 |
##   | `80%+21`(页面上的音量百分比) | 弹框的**金属面板**(380,210 520x300) | 同上 |
##   | `两边的存档对不上+18`(弹框**标题**) | 页面上的**音量条槽**(450,207 380x26·内框只剩 10px 高) | 反过来: 框在弹框**背后** |
##
##   三条都不是产品 bug: 标题对**它自己那个框**量出来是 **−5**(框 560x340·边带 13·
##   标题在 box 内 y=18 > 13, 干净); `画质「高」` 对**它自己那块木牌**量出来是 **−9.5**。
##   ⇒ 判据把**一层的字**配给了**另一层的框**。两边都会中招, 所以不是"抬基线"能盖住的。
##
## ★这也解释了为什么它以前没红: 页面与弹框**同时在场**才可能跨层配对, 而弹层
##   2026-09-28 之前**从没被建出来过**(memory `fb-gate-subject-never-constructed`)。
##
## ★★判据只认两种关系, 其余一律不配对:
##   ① 框控件是字的**祖先** —— 字长在框里(对话框标题在 `Panel` 里、列表行的字在行框里)
##   ② 框控件与字是**同一个父节点下的兄弟** —— 设置屏 `_text_button` 那种:
##      一张 `btn-frame.png` 铺成 `TextureRect` 当框, 一个 `Label` 盖在它上面, 两个都是
##      `cont` 的孩子。这一支**必须留**, 否则整屏三个木牌按钮的压边带从此没人查。
## ★取不到宿主时(旧形状的数组)返回 true —— 宁可保持老行为, 不静默放过。
func _frame_owns(owner: Node, txt: Node) -> bool:
	if owner == null or txt == null:
		return true
	var n: Node = txt
	while n != null:
		if n == owner:
			return true                      # ① 框是字的祖先
		n = n.get_parent()
	return owner.get_parent() != null and owner.get_parent() == txt.get_parent()   # ② 同父兄弟


func _audit(root: Node) -> Dictionary:
	## ★★`hits` 与下面的计数走【同一次遍历、同一个 if】 —— 分两段扫必然漂。
	var d := {"hits": [], "web": 0, "round": 0, "ctrl": 0, "btn": 0, "lbl": 0,
		"stock": [], "dead": [], "small": [], "clip": [], "squash": [],
		"flat9": [], "spill": [], "overlap": [], "frame": [], "tap": [],
		## ★★2026-09-28 盲区分母: **非 BaseButton 却能吃鼠标事件**的控件有多少个。
		##   「死点击/热区」两条原来只认 `BaseButton` 和接了 `gui_input` 的控件 ⇒
		##   有人把音量滑条把手设成 `MOUSE_FILTER_STOP`(**裸 `Control`**)做反向验证,
		##   判据没红。这个数就是那条盲区的**规模**: 只打印、不判红
		##   (Godot 里 Panel/PanelContainer 默认就是 STOP, 拿它判红等于满屏噪音),
		##   但它涨到哪儿是看得见的, 而且它说明了下面 `_interactive()` 收的那几类
		##   之外还剩多大一片没人量。
		"mfstop": 0}
	var _vp_area: float = maxf(1.0, float(get_viewport().get_visible_rect().size.x)
		* float(get_viewport().get_visible_rect().size.y))
	var labels: Array = []
	var framed: Array = []
	var arts: Array = []
	var st: Array = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is Control and (n as Control).is_visible_in_tree():
			var c := n as Control
			d["ctrl"] = int(d["ctrl"]) + 1
			## 触控热区: 短边 < 81px(=44pt) 的可点元素。★TouchPad 本身不算(它是别人的热区),
			##   有效热区 = 控件矩形 与 它挂的 TouchPad 取大 —— 不这么算数字会反着涨(实测 43→51)。
			## 盲区分母(见 d["mfstop"] 那段注释)
			if not (c is BaseButton) and (c.mouse_filter == Control.MOUSE_FILTER_STOP
					or c.mouse_filter == Control.MOUSE_FILTER_PASS):
				d["mfstop"] = int(d["mfstop"]) + 1
			if str(c.name) != "TouchPad":
				var _hit: bool = _interactive(c)
				var _ew: float = c.size.x
				var _eh: float = c.size.y
				var _pad = c.get_node_or_null("TouchPad")
				if _pad != null and _pad is Control:
					_ew = maxf(_ew, (_pad as Control).size.x)
					_eh = maxf(_eh, (_pad as Control).size.y)
				if _hit and _ew > 1.0 and _eh > 1.0 and minf(_ew, _eh) < 81.0 and maxf(_ew, _eh) < 200.0:
					(d["tap"] as Array).append("%.0fx%.0f %s" % [_ew, _eh, c.get_class()])
			if n is TextureRect and (n as TextureRect).texture != null and c.size.x >= 12.0 and c.size.y >= 12.0:
				# 头像/图标顶破框也是"压边带"的一种(图鉴列表行的头像实拍把行框切开了)。
				# ★但要量【真正画出来的那块图】: TextureRect 用 KEEP_ASPECT_CENTERED 时
				#   图是**按比例缩到框内居中**的, 控件矩形比图大一圈 ——
				#   拿控件矩形量, 28 张龟卡的头像全被报成"压边带 3px", 而实拍头像稳稳在卡里。
				#   和文字那次一模一样的错(第 9 次): **尺子要匹配被测概念。**
				# ★角标要放过: 稀有度小签、被动小图标这类**本来就是设计成压在卡角上的**
				#   (选龟 28 张卡各一个, 实拍就该那样)。判据: 自己 ≤24px 且住在一个独立的小盒子里。
				#   不放过的话它们会一直红, 逼我去"修"一个根本不是问题的东西。
				var is_badge: bool = c.size.x <= 24.0 and c.size.y <= 24.0 \
					and (c.get_parent() is PanelContainer or c.get_parent() is Panel)
				## ★框本身不能再当"被测的图" —— 否则它自己越过自己的边带, 每个框都白报一条
				##   (实测设置屏 3 条、主菜单 3 条全是这么来的)。
				if not is_badge and not ((n as TextureRect).texture != null \
					and c.size.x * c.size.y >= 4000.0 and minf(c.size.x, c.size.y) >= 40.0 \
					and c.size.x * c.size.y < _vp_area * 0.20 \
					and _is_frame_tex((n as TextureRect).texture)):
					arts.append([_art_rect(n as TextureRect), "图<%s|%.0fx%.0f>" % [str(c.name), c.size.x, c.size.y], false, n])
			## ★2026-08-19 补的第三种框: **TextureRect 拉伸出来的框**。
			##   设置屏三个按钮就是这么做的(menu/btn-frame.png 铺满一个 TextureRect, 文字是它的兄弟 Label),
			##   而 framed 原来只收 NinePatchRect 和 StyleBoxTexture ⇒ **这类框一个都没查过**。
			##   实拍才发现「低画质模式: 关 (高画质)」两端顶在花纹上, 而门禁对 Settings 判 0。
			##   判据不认名字只认图: 中心 40% 全透 + 四边有实像素 = 框(见 _is_frame_tex)。
			##   边带要**按实际拉伸比例换算**: 贴图是原始像素, 控件被拉到别的尺寸了。
			## 面积超过视口 20% 的不算"框"(那是背景/满铺贴图) —— 不排除的话背景会把满屏文字都判成压边。
			if n is TextureRect and (n as TextureRect).texture != null \
				and c.size.x * c.size.y < _vp_area * 0.20 \
				and c.size.x * c.size.y >= 4000.0 and minf(c.size.x, c.size.y) >= 40.0 \
				and _is_frame_tex((n as TextureRect).texture):
				var _ft: Texture2D = (n as TextureRect).texture
				## ★只信**横向**端花, 竖向记 0。
				##   实测 `menu/btn-frame.png` 893x212: 横带 101(11%)、竖带 77(**36%**)。
				##   竖向那 36% 是**斜面倒角**不是硬边 —— 按 50px 高的按钮换算内框只剩 14px,
				##   于是连「全屏」两个字都被判成压边(实测三个按钮全红)。**量到的不等于挡得住的。**
				##   横向那 101 才是真挡人的东西(两端的花纹柱), 越过去字就骑在花上。
				var _sx: float = c.size.x / maxf(1.0, float(_ft.get_width()))
				framed.append([c.get_global_rect(), _band_of(_ft) * _sx, 0.0, n])
			if n is NinePatchRect and (n as NinePatchRect).texture != null:
				var np := n as NinePatchRect
				## ★★2026-10-06 九宫格的边**只可能**画在切口(patch margin)里 —— 切口以内是被拉伸/平铺的芯子。
				##   `_band_of` 从贴图正中往外扫, 遇到的第一道色变若已经**越过切口**, 那就是芯子里的花纹
				##   (主菜单方键 `sqbtn.png` 是三块木板拼的, 扫到第 49 行的板缝), 不是边。
				##   旧口径下这种框在 88px 方键上「内框 ≤0 ⇒ 跳过」= 一直没人量; 方键改 100px 后内框剩 2px
				##   ⇒ 4 个字 + 4 个图标全报 +31~34(实拍字和图标都稳稳在框里)。
				##   ⇒ 只在「量到的边越过切口」那一轴改量**切口条里最暗的那道描边**(像素框的内描边), 其余照旧。
				var _b9: float = _band_of(np.texture)
				var _bx9: float = _b9
				var _by9: float = _b9
				var _mx9: float = maxf(float(np.patch_margin_left), float(np.patch_margin_right))
				var _my9: float = maxf(float(np.patch_margin_top), float(np.patch_margin_bottom))
				if (_mx9 > 0.0 and _b9 > _mx9) or (_my9 > 0.0 and _b9 > _my9):
					var _ob: Vector2 = _nine_outline_band(np)
					if _mx9 > 0.0 and _b9 > _mx9:
						_bx9 = _ob.x
					if _my9 > 0.0 and _b9 > _my9:
						_by9 = _ob.y
				framed.append([c.get_global_rect(), _bx9, _by9, n])
				var mv: float = np.patch_margin_top + np.patch_margin_bottom
				var mh: float = np.patch_margin_left + np.patch_margin_right
				if np.size.y > 0.0 and (np.size.y <= mv or np.size.x <= mh):
					(d["flat9"] as Array).append("%.0fx%.0f" % [np.size.x, np.size.y])
			# ★两个覆盖缺口(2026-08-18 实拍图鉴才发现, 判据全绿而肉眼三处毛病):
			#   ① 技能卡正文是 **RichTextLabel**, 不是 Label ⇒ 「点开看全部」压在正文上,
			#      压字判据**根本没把正文收进来**, 报 0。
			#   ② 门槛写的 `length() >= 4` —— 而龟名是 2~3 个字(「财神龟」)、稀有度是 1 个字母(「C」)。
			#      底部统计行压在「财神龟」上、右边框切掉「C」, 两条都因为**字太短被过滤掉了**。
			#   ⇒ 文字类一律收进来(Label + RichTextLabel), 门槛降到 1。
			if n is RichTextLabel and str((n as RichTextLabel).get_parsed_text()).strip_edges() != "":
				var rl := n as RichTextLabel
				d["lbl"] = int(d["lbl"]) + 1
				var rr := rl.get_global_rect()
				var used := minf(rl.get_content_height(), rr.size.y) if rl.get_content_height() > 0.0 else rr.size.y
				labels.append([Rect2(rr.position, Vector2(rr.size.x, used)),
					str(rl.get_parsed_text()).strip_edges(), _is_toast(rl), n])
			if n is Label and str((n as Label).text).strip_edges().length() >= 1:
				var lb := n as Label
				d["lbl"] = int(d["lbl"]) + 1
				## 角标小签(选中 ✓ / 基础 / 稀有度)本来就是刻意压在格子角上的, 和图片角标同一类 ——
				## 之前只豁免了 TextureRect, 这里把 Label 版补上: 它住在一个 <40px 的独立小盒子里。
				var _par := lb.get_parent() as Control
				var _badge: bool = _par != null and (_par is PanelContainer or _par is Panel) \
						and _par.size.x < 40.0 and _par.size.y < 40.0
				labels.append([_ink_rect(lb), str(lb.text), _is_toast(lb) or _badge, n])
				var fs2: int = lb.get_theme_font_size("font_size")
				# ⚠ 判据太宽第 8 次: 报选龟稀有度栏杆的「A」「B」「C」被挤没 —— 实拍那几个
				#   字母**显示得好好的**。原因是这些 Label 是手工定位的, `size` 就是 (0,0),
				#   而 **Godot 的 Label 不裁剪**: 矩形再小照样把字画出来。
				#   只有 `clip_text` 打开时"矩形太小"才真会吃掉字。
				if (lb.size.x < 6.0 or lb.size.y < 6.0) and lb.clip_text:
					(d["squash"] as Array).append(str(lb.text).substr(0, 8))
				if lb.get_line_count() > lb.get_visible_line_count():
					(d["spill"] as Array).append(str(lb.text).substr(0, 8))
				if lb.clip_text and lb.autowrap_mode == TextServer.AUTOWRAP_OFF and lb.size.x > 1.0:
					var fnt: Font = lb.get_theme_font("font")
					if fnt != null and fnt.get_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x > lb.size.x + 0.5:
						(d["clip"] as Array).append(str(lb.text).substr(0, 8))
			for slot in ["panel", "normal", "background", "fill"]:
				if not c.has_theme_stylebox_override(slot):
					continue
				var sb = c.get_theme_stylebox(slot)
				if sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null:
					var _bb := _band_of((sb as StyleBoxTexture).texture)
					framed.append([c.get_global_rect(), _bb, _bb, n])
				elif sb is StyleBoxFlat:
					var f2 := sb as StyleBoxFlat
					var _r0: bool = f2.corner_radius_top_left > 0
					if _r0:
						d["round"] = int(d["round"]) + 1
					if f2.border_width_top > 0 and f2.border_width_bottom > 0 \
							and f2.border_width_left > 0 and f2.border_width_right > 0 \
							and f2.bg_color.a < 0.95:
						d["web"] = int(d["web"]) + 1
					## ★明细: 命中时把【是谁】记下来, 分堆之后再谈改哪些。
					if _DUMP and (_r0 or f2.bg_color.a < 0.95):
						var _rc: Rect2 = c.get_global_rect()
						var _wb: bool = f2.border_width_top > 0 and f2.border_width_bottom > 0 \
							and f2.border_width_left > 0 and f2.border_width_right > 0 \
							and f2.bg_color.a < 0.95
						if _r0 or _wb:
							## ★★名字是 `@PanelContainer@1103` 这种自动名, **认不出是什么控件**。
							##   加上它里头第一段文字 —— 那才是能对上源码的那一维。
							##   (2026-09-27: 选龟屏 61 个里 28 个是 `26x26 r=13` 的**正圆**,
							##    光看尺寸还以为是稀有度小签, 加了文字才认出是被动图标的圆底。)
							var _txt := _first_text(c)
							(d["hits"] as Array).append("%s%s %-16s %-14s %.0fx%.0f  r=%d b=%d a=%.2f  「%s」" % [
								"[web]" if _wb else "     ", "[round]" if _r0 else "       ",
								c.get_class(), str(c.name).substr(0, 14), _rc.size.x, _rc.size.y,
								f2.corner_radius_top_left, f2.border_width_top, f2.bg_color.a, _txt])
			var is_btn: bool = c is BaseButton
			var wired: bool = _interactive(c) and not (c is BaseButton)
			if c is Button and not (c as Button).flat:
				d["btn"] = int(d["btn"]) + 1
				if not c.has_theme_stylebox_override("normal"):
					(d["stock"] as Array).append(str((c as Button).text).substr(0, 8))
			if (is_btn or wired) and c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
				(d["dead"] as Array).append(c.name)
			if (is_btn or wired) and c.size.x > 1.0 and c.size.y > 1.0 \
					and minf(c.size.x, c.size.y) < TOUCH_MIN and maxf(c.size.x, c.size.y) < 200.0:
				(d["small"] as Array).append("%.0fx%.0f" % [c.size.x, c.size.y])
		for ch in n.get_children():
			st.append(ch)
	for i in range(labels.size()):
		for j in range(i + 1, labels.size()):
			if str(labels[i][1]) == str(labels[j][1]):
				continue
			# ★toast(StatusBar/飘字提示)本来就是【浮在内容上】的一层, 2 秒后淡出 ——
			#   把它算成"两段文字压在一起"是判据没分清"重叠"和"覆盖式提示"。
			#   只豁免这一类(名字里带 status/toast), 其它重叠仍然要红。
			if labels[i][2] or labels[j][2]:
				continue
			var ra: Rect2 = labels[i][0]
			var rb: Rect2 = labels[j][0]
			var inter: Rect2 = ra.intersection(rb)
			if inter.size.x <= 0.0 or inter.size.y <= 0.0:
				continue
			var amin: float = minf(ra.size.x * ra.size.y, rb.size.x * rb.size.y)
			if amin > 0.0 and (inter.size.x * inter.size.y) / amin > 0.25:
				(d["overlap"] as Array).append("%s|%s" % [
					str(labels[i][1]).substr(0, 5), str(labels[j][1]).substr(0, 5)])
	var boxed: Array = labels.duplicate()
	boxed.append_array(arts)
	for k in range(boxed.size()):
		var lr: Rect2 = boxed[k][0]
		var cc := lr.position + lr.size * 0.5
		var best := -1
		var best_a := 1.0e18
		for fi in range(framed.size()):
			var fr: Rect2 = framed[fi][0]
			if not fr.has_point(cc):
				continue
			## ★★★【框得管得着这段字】—— 只凭屏幕坐标配对会跨层乱配, 见 _frame_owns 的长注释。
			if not _frame_owns(framed[fi][3] if framed[fi].size() > 3 else null,
					boxed[k][3] if boxed[k].size() > 3 else null):
				if _DUMP:
					print("      [跨层·不配对] 「%s」 ⇢ 框<%s> (屏幕上重叠, 但不是它的框)" % [
						str(boxed[k][1]).substr(0, 24),
						str((framed[fi][3] as Node).name) if framed[fi].size() > 3 else "?"])
				continue
			var ar: float = fr.size.x * fr.size.y
			if ar < best_a:
				best_a = ar
				best = fi
		if best < 0:
			continue
		if boxed[k].size() > 2 and bool(boxed[k][2]):
			continue          # 角标/toast: 压在边上是设计如此
		var fr2: Rect2 = framed[best][0]
		var inter2: Rect2 = fr2.intersection(lr)
		var la: float = lr.size.x * lr.size.y
		if la <= 0.0 or inter2.size.x <= 0.0 or (inter2.size.x * inter2.size.y) / la < 0.60:
			continue
		var mx: float = float(framed[best][1])
		var my: float = float(framed[best][2])
		var inner := Rect2(fr2.position + Vector2(mx, my), fr2.size - Vector2(mx, my) * 2.0)
		if inner.size.x <= 0.0 or inner.size.y <= 0.0:
			continue
		var over := maxf(maxf(inner.position.y - lr.position.y,
			(lr.position.y + lr.size.y) - (inner.position.y + inner.size.y)),
			maxf(inner.position.x - lr.position.x,
			(lr.position.x + lr.size.x) - (inner.position.x + inner.size.x)))
		if over > 2.0:
			(d["frame"] as Array).append("%s+%.0f" % [str(boxed[k][1]).substr(0, 50), over])
	return d


## ══════════════════════════════════════════════════════════════════════
##  第二节【按了才建出来】—— 静止页一条判据都碰不到的那批界面 (2026-09-28)
## ══════════════════════════════════════════════════════════════════════
## ★由来: 上面那张 BASE 表扫的是**每个屏加载完静止下来的样子**。凡是"按一下才建"
##   的界面, 被测对象根本不在场 ⇒ 判据没错, 却永远绿
##   (memory `fb-gate-subject-never-constructed`)。实证四批:
##     · 主菜单教程确认弹窗: 12px 圆角 + 2px 描边 + 一个 Godot 默认皮按钮
##       —— **一次占三条判据, 而门禁一直绿**
##     · 背包的糖果罐操作栏 / 羁绊详情弹框 / 糖果罐领奖弹框
##       —— ★**全仓没有任何测试会建它们**
##     · 设置屏的存档冲突框与重置确认框
## ★★而且「改完了没有」不能拿上面那张棘轮表的数字看: 背包那三个真违规修掉之后,
##   `verify_ui_consistency` 的 Inventory 圆角盒**改前改后都是 18** —— 棘轮上的数
##   一格都没动。**判据的数字不动, 不等于什么都没发生。**
##
## ★量法: 同一个场景实例上 `_audit()` 两次(开弹层**前**/开弹层**后**), 判**增量**。
##   这样 13 条判据一条不改就全都罩到弹层上了, 而且**分母是天然的**:
##   「新增控件数 ≥ min_new」不成立 = 弹层没建起来 ⇒ 当场红, 而不是变成一条空检查
##   ("催了但没出来"就是它当初躲过门禁的那个形状)。
##
## ★同族的 `nine_if_big` 只量到第一个样本那一类, 见 BASE 表末尾新加的两列说明。
## ★★★基线全部是**2026-09-28 首次量到就如实登记**的存量, 棘轮**只许降**。
##   这一节是新开的扫描范围, 扩范围必然扫出存量 —— 而"放宽判据让它绿"和
##   "把存量当成没有"是同一件事。⇒ 照 `登录墙`(2026-09-27)那条的办法:
##   **先按实测如实登记, 修完再往下拧**, 并把每条是什么问题写在旁边交出去。
## `mode`: `"delta"`(默认) 判**增量** —— 弹层是叠在页面上的;
##         `"abs"` 判**绝对值** —— `jar_op_bar` 走 `_rebuild()` 会把整页重建
##         (实测控件数 196 → 178, **减少** 18), 增量在它身上根本不成立。
## `mark`: 开完之后屏幕上必须出现的一句话 —— `abs` 模式下没有"新增控件数"可用,
##         它就是那一条**分母**(催了但没出来 ⇒ 当场红, 不是静默变空检查)。
const POPUPS: Array = [
	## 2026-10-07 换成教程选择框(scripts/scenes/tutorial_choice.gd): 两颗按钮 168x81 ⇒ 热区存量 2 → 0(棘轮收紧)。
	{"scn": "MainMenu", "id": "tutorial_confirm", "label": "主菜单·教程确认弹窗",
		"min_new": 6, "web": 0, "round": 0, "tap": 0, "frame": 0, "stock": 0},
	## `abs`: 选中糖果罐会整页重建。数字与静止态的 Inventory 基线同一口径
	## (web 10 / round 18 = 那批**刻意保留**的迷你装备格与羁绊赠送徽章, 见 KEEP_OK)。
	## 存量: tap 13 = 静止态那 11 个 + 糖果罐那条栏带进来的 2 个 40x40 Panel。
	{"scn": "Inventory", "id": "jar_op_bar", "label": "背包·糖果罐操作栏",
		"mode": "abs", "mark": "打碎",
		"min_new": 0, "web": 10, "round": 18, "tap": 13, "frame": 0, "stock": 0},
	## ★★★2026-09-28 【frame 这一列整列重测过一遍】: 配对规则从「屏幕上最小的框」收紧成
	##   「祖先 / 同父兄弟」(见 `_frame_owns`)之后, 原来登记的 5 条存量里 **4 条是跨层假违规**
	##   —— 报的是**页面上的字**配**弹框里的框**(或反过来)。逐条实测(探针
	##   `tests/_probe_settings_frame.gd` / `UICONS_DUMP=1` 的「跨层·不配对」行):
	##     · 羁绊详情框 `月之刃+11`      ← 背包**页面上的装备名** vs 弹框的金属面板
	##     · 领奖框 `糖果罐碎了！…+20`   ← 弹框**标题** vs 背包页面的一个 Panel
	##       (对它**自己**那个框量出来是负的 = 干净)
	##     · 领奖框 `月之刃+9` / `图<…44x36>+11` ← 同上, 页面的装备名/图标 vs 弹框面板
	##     · 存档冲突框 `两边的存档对不上+18` ← 弹框**标题** vs 页面上的**音量条槽**
	##       (槽 380x26·内框只剩 10px 高; 标题对**自己**那个框是 **−5.0**)
	##   ★所以这四条不是"修好了", 是**从来就不该报**。棘轮按实测降到真值,
	##     并把"它到底是什么"写在这儿 —— 否则下一个人会去"修"一个不存在的 bug
	##     (`KEEP_OK` 那一节立在这儿就是为了这件事)。
	## 存量: tap +1(一个 40x40 Panel)。frame 从 1 降到 0(那 1 条是跨层假违规, 见上)。
	{"scn": "Inventory", "id": "synergy_popup", "label": "背包·羁绊详情弹框",
		"min_new": 5, "web": 0, "round": 0, "tap": 1, "frame": 0, "stock": 0},
	## 存量: tap +1 · frame +1 —— ★★**剩下这一条是真的**(关系=祖先, 字长在框里):
	##   「临时等级器 ×1 收进背包 · 点它再点一只龟或小将, 这一大轮就多一级」
	##   越出弹框内容区 **23px**。出处 `scripts/scenes/inventory/candy_jar.gd`
	##   `_show_jar_reward()`: 框 520x300·panel-frame 边带 13, 而这一行 `l.size = (440, 48)`
	##   放在 `x=40`, 18 号字按 `WORD_SMART` 断不开中文长句 ⇒ 字块比框的内容区宽。**交主会话。**
	##   (frame 从 4 降到 1: 另外 3 条是跨层假违规, 见上。)
	{"scn": "Inventory", "id": "jar_reward", "label": "背包·糖果罐领奖弹框",
		"min_new": 5, "web": 0, "round": 0, "tap": 1, "frame": 1, "stock": 0},
	## 干净(6 项全 0)。frame 从 1 降到 0 —— 原来那 1 条是跨层假违规(见上)。
	{"scn": "Settings", "id": "conflict_dialog", "label": "设置·存档冲突框",
		"min_new": 6, "web": 0, "round": 0, "tap": 0, "frame": 0, "stock": 0},
	## 干净(6 项全 0)。
	{"scn": "Settings", "id": "reset_confirm", "label": "设置·重置确认框",
		"min_new": 5, "web": 0, "round": 0, "tap": 0, "frame": 0, "stock": 0},
]


## ══════════════════════════════════════════════════════════════════════
##  【刻意保留·不许算违规】—— 带理由, 不是台账欠账
## ══════════════════════════════════════════════════════════════════════
## 这些是**复核过、退回过**的决定, 写在这里是为了下一个人(和下一个 agent)
## 不会把它们当成"还没改完"去改坏:
##   · `InventoryScene` 的 18 个 26px 迷你装备格 `r=3` 与 22px 羁绊赠送徽章 `r=3`
##     —— 2026-08-18 实拍对比后**退回过一次**: 套金属槽框会让**费用色从整块实心
##     退化成一圈细边**, 而那块实心色本身就是信息(一眼分得出 2/3/4/5 费)。
##     ⇒ 贴图框有它的最小可用尺寸, 小于它就该保持纯色块。
##     (它们正是 Inventory 基线里 `round 19` / `web 10` 那两个数的主体。)
##   · 选阵容的 28 个**正圆**头像/被动图标遮罩(`pet_grid.gd` 26x26 半径 13)
##     —— 用户点名的是 `border-radius` 的圆角**矩形**, 正圆不是那味, 刻意留着。
##     (TeamSelect 基线 `round 32` 里 28 个是它。)
## ⇒ 判据**一个字没放宽** —— 宁可让棘轮数着, 也不为了数字好看去改判据。
const KEEP_OK := {
	"Inventory/26px 迷你装备格 r=3": "换槽框会让费用色从整块实心退化成一圈细边, 而那块实心色就是信息(2026-08-18 实拍退回)",
	"Inventory/22px 羁绊赠送徽章 r=3": "同上(同一批实拍对比)",
	"TeamSelect/28 个正圆头像遮罩": "正圆不是 border-radius 那味(用户点名的是圆角矩形)",
}


## 走产品**自己的**那个入口把弹层催出来 —— 不在测试里另搭一套。
## ★返回 false = 这一条催不出来(接口改名/前置条件不成立), 调用方会**判红**,
##   不是静默跳过 —— 静默跳过正好复制了这些界面当初躲过门禁的那个形状。
func _open_popup(inst, id: String) -> bool:
	match id:
		"tutorial_confirm":
			if not inst.has_method("_on_tutorial"):
				return false
			inst._on_tutorial()
			return true
		"jar_op_bar":
			## 这条栏只在【选中糖果罐】之后才建(InventoryScene.gd `_build_op_bar` 的双胞胎)
			var gs2 = get_node_or_null("/root/GameState")
			if gs2 == null or not gs2.has_candy_jar():
				return false
			if not inst.has_method("_rebuild"):
				return false
			inst._sel_jar = true
			inst._rebuild()
			return true
		"synergy_popup":
			if inst.get("_inv_synergy") == null:
				return false
			## 「剑」是 `Phase2Types.TYPES` 里第一个键, 不是我编的类型名
			inst._inv_synergy._show_synergy_popup("剑", 1)
			return true
		"jar_reward":
			if inst.get("_inv_jar") == null:
				return false
			## 形状照 `GameState.break_candy_jar()` 的返回值(不走真打碎: 那会改存档)
			inst._inv_jar._show_jar_reward({"tier": 3, "coins": 40,
				"equip": "p2eq_001", "star": 2, "leveler": true})
			return true
		"conflict_dialog":
			if not inst.has_method("_open_conflict_dialog"):
				return false
			inst._open_conflict_dialog()
			return true
		"reset_confirm":
			if not inst.has_method("_ask_reset"):
				return false
			inst._ask_reset()
			return true
	return false


## 判据自检: `_interactive()` **真的认得**它声称认得的那几类节点。
##
## ★★为什么必须有这一节: 扩完 `_interactive()` 之后整份门禁照旧 ALL PASS ——
##   而那不是"没有违规", 是**那几类节点在这七八个屏上一个都没出现**
##   (设置屏可见控件只有 12 个, 滑条在折叠区里)。
##   「改了判据 → 门禁还是绿 → 就以为改对了」正是 memory
##   `fb-gate-subject-never-constructed` / `fb-gate-must-measure-requirement-not-my-hook`
##   那一族。⇒ 现造四个节点, 逐类证明它分得清。
func _selftest_interactive() -> void:
	print("  ── 判据自检: `_interactive()` 认得哪几类节点 ──")
	var sl := HSlider.new()          # 设置屏的音量/画质滑条是 Range, **不是** BaseButton
	var le := LineEdit.new()         # 登录墙的昵称/邮箱输入框
	var te := TextEdit.new()
	var bt := Button.new()
	var raw := Control.new()         # 裸 Control + MOUSE_FILTER_STOP: 能吃点击, 但不是交互原语
	raw.mouse_filter = Control.MOUSE_FILTER_STOP
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## ★★⑦⑧: `RichTextLabel` 进树就被引擎接上内部滚动条的 gui_input(见 `_wired_from_outside`)。
	##   ⑦ 证明那条**不算**交互; ⑧ 证明**外面真接的**照样算 —— 只有 ⑦ 的话, 把整类 RTL
	##   一刀排掉也能过, 那就把"谁真的给 RTL 接了点击"一起放走了。
	var rtl := RichTextLabel.new()
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rtl_w := RichTextLabel.new()
	rtl_w.gui_input.connect(func(_e): pass)
	for n in [sl, le, te, bt, raw, lbl, rtl, rtl_w]:
		add_child(n)
	await get_tree().process_frame     # ★必须等一帧: 内部滚动条是进树之后才接上的
	_ok("自检 ①`Range`(滑条)算交互控件", _interactive(sl), "改判据之前它不算 ⇒ 滑条的热区/死点击从没被量过")
	_ok("自检 ②`LineEdit` 算交互控件", _interactive(le))
	_ok("自检 ③`TextEdit` 算交互控件", _interactive(te))
	_ok("自检 ④`Button` 仍然算(没改坏老口径)", _interactive(bt))
	_ok("自检 ⑤裸 `Control`+MOUSE_FILTER_STOP **不**算交互控件",
		not _interactive(raw),
		"它确实能吃点击, 但 Panel/ColorRect 默认就是 STOP ⇒ 收了满屏噪音。规模走 mfstop 分母")
	_ok("自检 ⑥MOUSE_FILTER_IGNORE 的 `Label` 不算", not _interactive(lbl))
	## ★分母: 先证明那条引擎内部连接**真的在**(连接数 0 ⇒ ⑦ 恒真, 是空检查)。
	_ok("自检 ⑦分母: 裸 `RichTextLabel` 进树后 gui_input 上真有引擎接的那条(%d 条)"
		% rtl.gui_input.get_connections().size(), rtl.gui_input.get_connections().size() > 0,
		"0 条 ⇒ 下面那条是空检查")
	_ok("自检 ⑦裸 `RichTextLabel` **不**算交互控件(引擎内部滚动条接的那条不算)",
		not _interactive(rtl),
		"算了的话每个 RTL 文字都会被报「热区不足/死点击」—— 假违规压死真违规")
	_ok("自检 ⑧但**外面真接了** gui_input 的 `RichTextLabel` 仍然算(没把整类一刀排掉)",
		_interactive(rtl_w))
	for n2 in [sl, le, te, bt, raw, lbl, rtl, rtl_w]:
		n2.queue_free()
	await get_tree().process_frame


## 判据自检②: 「压边带」的**配对**认得哪种关系 —— `_frame_owns` 的分母。
##
## ★★为什么必须有这一节: 2026-09-28 把配对从「屏幕上最小的那个框」收紧成
##   「祖先 / 同父兄弟」之后, 整份门禁**从红变全绿**, 而且 4 条存量登记当场归零 ——
##   「收紧判据 → 门禁变绿」和「判据从此一条都逮不到」在输出上**长得一模一样**
##   (memory `fb-gate-subject-never-constructed` / `fb-gate-must-measure-requirement-not-my-hook`)。
##   ⇒ 现造三种关系, 逐个证明: 前两种**必须逮到**, 第三种(跨层)**必须放过**。
##   这三条是**反向验证的常驻版**: 把 `_frame_owns` 改回"永远 true", ③ 当场红;
##   改成"只认祖先", ② 当场红。
func _selftest_frame_pairing() -> void:
	print("  ── 判据自检②: 「压边带」配对认得哪种关系 ──")
	var _fb := StyleBoxFlat.new()
	var _box_sb: StyleBox = UISkin.nine("panel-frame.png", 20, _fb)
	_ok("自检⑦ 配对自检的素材在位(panel-frame/btn-frame 都能加载)",
		_box_sb is StyleBoxTexture and ResourceLoader.exists(_BTN_TEX),
		"贴图缺一张 ⇒ 下面三条全是空检查")

	## ① 框是字的【祖先】: 对话框标题长在 Panel 里, 标题贴着框顶 ⇒ 该逮到
	var r1 := Control.new()
	r1.size = Vector2(400, 200)
	add_child(r1)
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", _box_sb)
	box.position = Vector2.ZERO
	box.size = Vector2(300, 100)
	r1.add_child(box)
	var l1 := Label.new()
	l1.text = "压边带自检·祖先"
	l1.add_theme_font_size_override("font_size", 16)
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l1.position = Vector2.ZERO           # 顶到框的最上沿 ⇒ 越过 13px 边带
	l1.size = Vector2(300, 20)
	box.add_child(l1)
	await get_tree().process_frame
	_ok("自检⑦a 框是字的【祖先】时逮得到", (_audit(r1)["frame"] as Array).size() == 1,
		"实测 %s" % str(_audit(r1)["frame"]))

	## ② 框与字是【同父兄弟】: 设置屏 `_text_button` 的形状(TextureRect 当框 + Label 盖上去)
	var r2 := Control.new()
	r2.size = Vector2(400, 200)
	add_child(r2)
	r2.add_child(_mk_btn_shape(true))
	await get_tree().process_frame
	_ok("自检⑦b 框与字是【同父兄弟】时逮得到", (_audit(r2)["frame"] as Array).size() == 1,
		"实测 %s —— 红了 = 设置屏那三块木牌按钮的压边带从此没人查" % str(_audit(r2)["frame"]))

	## ③ 【跨层】: 同样的框、同样的字、同样的屏幕坐标, 但分别住在两个互不相干的分支里
	##    (= 弹框盖在页面上那个形状) ⇒ 必须放过
	var r3 := Control.new()
	r3.size = Vector2(400, 200)
	add_child(r3)
	var br_a := Control.new()          # 分支 A: 只放框
	var br_b := Control.new()          # 分支 B: 只放字(坐标与 A 完全重合)
	r3.add_child(br_a)
	r3.add_child(br_b)
	br_a.add_child(_mk_btn_shape(false, true))
	br_b.add_child(_mk_btn_shape(false, false))
	await get_tree().process_frame
	_ok("自检⑦c 【跨层】重叠时不配对(弹框盖在页面上那个形状)",
		(_audit(r3)["frame"] as Array).size() == 0,
		"实测 %s —— 绿不了 = 跨层假违规还在(设置屏那三条就是这么来的)" % str(_audit(r3)["frame"]))
	for n in [r1, r2, r3]:
		n.queue_free()
	await get_tree().process_frame


const _BTN_TEX := "res://assets/sprites/menu/btn-frame.png"

## 造一份「木牌按钮」形状。`together` = 框与字同父(②);
## 否则按 `frame_only` 只造框或只造字, 用来拼跨层那一组(③)。
func _mk_btn_shape(together: bool, frame_only: bool = false) -> Control:
	var cont := Control.new()
	cont.size = Vector2(260, 50)
	cont.position = Vector2.ZERO
	if together or frame_only:
		var fr := TextureRect.new()
		fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fr.stretch_mode = TextureRect.STRETCH_SCALE
		fr.size = Vector2(260, 50)
		fr.texture = load(_BTN_TEX)
		cont.add_child(fr)
	if together or not frame_only:
		var lb := Label.new()
		## ★14 个全角字 @18px = 252px > 内框 201.2px(边带 101 × 260/893 = 29.4, 两侧共 58.8)
		##   ⇒ 居中后左右各越出 25px。第一版只写了 11 个字(198px)**装得下**,
		##   ⓑ 当场红、而 ⓒ 是**空检查也绿** —— 字数不够两条都白写。
		lb.text = "压边带自检兄弟关系一二三四五"
		lb.add_theme_font_size_override("font_size", 18)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lb.size = Vector2(260, 50)
		lb.position = Vector2.ZERO
		cont.add_child(lb)
	return cont


func _audit_popups() -> void:
	print("  ── 第二节【按了才建出来】(静止页扫不到的界面) ──")
	var gs = get_node_or_null("/root/GameState")
	for spec in POPUPS:
		var scn: String = str(spec["scn"])
		var path := "res://scenes/%s.tscn" % scn
		if not ResourceLoader.exists(path):
			_ok("弹层 %s: 场景在位" % str(spec["label"]), false, "找不到 %s" % path)
			continue
		## 背包要 33 格 6 卡 + 糖果罐, 不灌就是空背包(那是另一块屏)
		if scn == "Inventory" and ResourceLoader.exists("res://tests/_setup_inv_demo.gd"):
			var sc = load("res://tests/_setup_inv_demo.gd")
			if sc != null and sc.has_method("run"):
				sc.run()
		if gs != null and int(gs.season_total_battles) <= 0:
			gs.season_total_battles = 3
		var inst = (load(path) as PackedScene).instantiate()
		add_child(inst)
		var _st1: bool = await _settle(inst)
		var kids0: Array = inst.get_children()
		var d0 := _audit(inst)
		## ★★先证明**基态自己是干净的** —— 不然"增量 0"可能是"本来就满是违规、
		##   弹层又加了一批", 两个数一减正好抵掉(memory `fb-gate-tautological...` 同族)。
		var opened: bool = _open_popup(inst, str(spec["id"]))
		_ok("★分母 弹层 %s: 产品自己的入口催得出来" % str(spec["label"]), opened,
			"催不出来 = 接口改名/前置不成立 ⇒ 这一条从此是空检查")
		if not opened:
			inst.queue_free()
			await get_tree().process_frame
			continue
		## ★等【落位】用的是同一套墙钟 `_settle`(弹层有入场 tween)。
		##   ⚠ 不靠"撞到最坏那一帧": `_settle` 先无条件等够 MIN_WAIT 墙钟秒,
		##     入场动画都 ≤1 秒 ⇒ 量的不是半空中的画面。
		var _st2: bool = await _settle(inst)
		## ★★★【探子】先塞一个**假违规**进弹层, 确认判据量得到, 再摘掉量真的。
		##   不做这一步的话, 「催出来了**但判据没作用在它身上**」依然是恒绿 ——
		##   而那正是这批界面当初躲过门禁的同一个形状(判据没错, 碰不到面)。
		##   探子做成 12px 圆角 + 4 边描边 + 半透底 = 一次同时踩「网页盒」与「圆角盒」,
		##   所以一条断言能证明两条判据都活着。
		var host: Node = inst
		for k2 in inst.get_children():
			if not (k2 in kids0) and k2 is Control:
				host = k2                    # 弹层自己那一层(证明扫的是它, 不只是静止页)
				break
		var spy := PanelContainer.new()
		spy.name = "UICONS_SPY"
		spy.position = Vector2(4, 4)
		spy.custom_minimum_size = Vector2(60, 30)
		var ssb := StyleBoxFlat.new()
		ssb.bg_color = Color(0.1, 0.1, 0.1, 0.5)     # a < 0.95 ⇒ 网页盒那一条
		ssb.set_border_width_all(2)                   # 四边有边框 ⇒ 同上
		ssb.set_corner_radius_all(12)                 # ⇒ 圆角盒那一条
		spy.add_theme_stylebox_override("panel", ssb)
		host.add_child(spy)
		await get_tree().process_frame
		var dspy := _audit(inst)
		spy.queue_free()
		await get_tree().process_frame
		var d1 := _audit(inst)
		_ok("★★★探子 弹层 %s: 往它里头塞一个假网页盒, 判据逮得到"
			% str(spec["label"]),
			int(dspy["web"]) - int(d1["web"]) == 1 and int(dspy["round"]) - int(d1["round"]) == 1,
			"塞进去 web %d→%d / round %d→%d (挂在 %s 上) —— 逮不到 = 判据没作用在这一层, 下面全是恒绿"
			% [int(d1["web"]), int(dspy["web"]), int(d1["round"]), int(dspy["round"]),
				str(host.name)])
		var absmode: bool = str(spec.get("mode", "delta")) == "abs"
		## ★★这一条就是"催了但没出来"的堵口: 它不成立, 下面所有增量都是 0-0=0 的空检查。
		if absmode:
			## `abs` 模式没有"新增控件数"可用(整页重建, 控件数会**变少**)
			## ⇒ 分母改成【那一句话真的上了屏】—— 字取产品自己那一处, 不在测试里另编。
			var mk: String = str(spec.get("mark", ""))
			var seen := false
			var stk: Array = [inst]
			while not stk.is_empty():
				var n2 = stk.pop_back()
				if n2 is Button and str((n2 as Button).text).find(mk) >= 0:
					seen = true
				elif n2 is Label and str((n2 as Label).text).find(mk) >= 0:
					seen = true
				for c2 in n2.get_children():
					stk.append(c2)
			_ok("★★分母 弹层 %s: 真的建起来了(屏上找得到「%s」)" % [str(spec["label"]), mk],
				seen, "找不到 = 它没被建出来, 而下面几条会变成永远绿的空检查")
			_ok("★分母 弹层 %s: 整页真的重建过(控件数变了)" % str(spec["label"]),
				int(d1["ctrl"]) != int(d0["ctrl"]),
				"开之前 %d → 开之后 %d" % [int(d0["ctrl"]), int(d1["ctrl"])])
		else:
			var dn: int = int(d1["ctrl"]) - int(d0["ctrl"])
			_ok("★★分母 弹层 %s: 真的建起来了(新增可见控件 ≥ %d)"
				% [str(spec["label"]), int(spec["min_new"])], dn >= int(spec["min_new"]),
				"新增 %d 个(开之前 %d → 开之后 %d)" % [dn, int(d0["ctrl"]), int(d1["ctrl"])])
		for k in ["web", "round"]:
			var inc: int = int(d1[k]) if absmode else int(d1[k]) - int(d0[k])
			_ok("弹层 %s %s ≤ %d" % [str(spec["label"]),
				"网页盒" if k == "web" else "圆角盒", int(spec[k])],
				inc <= int(spec[k]),
				"%s %d (页面基态 %d)" % ["实测" if absmode else "增量", inc, int(d0[k])])
		for k2 in ["tap", "frame", "stock"]:
			var a0: Array = d0[k2] as Array
			var a1: Array = d1[k2] as Array
			var inc2: int = a1.size() if absmode else a1.size() - a0.size()
			var nm2: String = {"tap": "热区不足(短边<44pt)", "frame": "文字压边带",
				"stock": "Godot 默认皮按钮"}[k2]
			_ok("弹层 %s %s ≤ %d" % [str(spec["label"]), nm2, int(spec[k2])],
				inc2 <= int(spec[k2]),
				"%s %d %s" % ["实测" if absmode else "增量", inc2,
					str((a1 if absmode else a1.slice(maxi(0, a0.size()), a1.size())).slice(0, 4))])
		inst.queue_free()
		await get_tree().process_frame
	print("    [刻意保留·带理由] %d 条(不是欠账, 别去「修」它们):" % KEEP_OK.size())
	for kk in KEEP_OK:
		print("       %s —— %s" % [str(kk), str(KEEP_OK[kk])])


## ═══════════════════════════════════════════════════════════════════
##  【撑合屏】—— 它在场过, 但撑不到被量 (2026-09-28)
## ═══════════════════════════════════════════════════════════════════
## 缝开在**产品那边**: `MatchmakingScene._may_leave_for_test`(static Callable,
## 无效 = 不生效), 样式抄仓库里现成的三个 —— `Backend.pool_override` /
## `Supabase._transport_for_test` / `phase2_config.now_override_ts`。
## 它**只答「现在该不该离开这一屏」**, 去哪不由它说。
##
## ★三层分母(缺一层那两种假绿就回来了):
##   ① 这一屏真的建起来了       —— 可见控件 ≥ `MIN_CTRL`, 且**对手名在屏幕上**
##   ② 缝真的生效了             —— **两边都断**: 路真的走到了最后一步(回调被调) +
##                                      调完之后真的没跳场(实例还在树里)
##   ③ 判据真的作用在它身上   —— **探子**: 塞一个假违规进去, 判据要逐得到
const _MM := preload("res://scripts/scenes/MatchmakingScene.gd")
## 门禁**自己**写的那条期望路径 —— 故意**不**读 `_MM.BATTLE_SCENE`。
## ★读它就成了「拿同一个常量比它自己」: 目标被改成别的场景时两边一起变,
##   判据恒真(memory `fb-completeness-needs-external-yardstick`: 尺子得在被测物之外)。
const _MM_DEST := "res://scenes/RealtimeBattle3D.tscn"
var _mm_leave_calls := 0
var _mm_leave_path := ""


## 缝的回调: 只答「不走」, 并把被告知的目标记下来。
func _mm_may_leave(dest: String) -> bool:
	_mm_leave_calls += 1
	_mm_leave_path = dest
	return false


func _mm_opp_name() -> String:
	if GameState.dual_opponent is Dictionary:
		return str((GameState.dual_opponent as Dictionary).get("name", ""))
	return ""


func _mm_find_label(root: Node, txt: String) -> bool:
	var st: Array = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is Label and (n as Label).is_visible_in_tree() \
				and str((n as Label).text).find(txt) >= 0:
			return true
		for ch in n.get_children():
			st.append(ch)
	return false


## 等到【对手卡真的建出来】—— 不等它量的就是「正在找对手」那块占位屏。
## 【尺子】墙钟(CLAUDE.md §3.5): 帧数在无头下与真实时间完全脱钩。
## 【判据】屏幕上出现一个写着**对手名**的 Label。名字取 `GameState.dual_opponent`
##   —— 那是**撑合逻辑自己算出来**的那一份, 不是测试里拄的一句屏幕词
##   (拄屏幕词的话改文案会让这条分母静默失明; 而 bot 昵称表是范本不许动)。
func _mm_wait_vs(root: Node) -> bool:
	var t0: float = float(Time.get_ticks_msec()) / 1000.0
	while float(Time.get_ticks_msec()) / 1000.0 - t0 < 8.0:
		await get_tree().process_frame
		var nm := _mm_opp_name()
		if nm != "" and _mm_find_label(root, nm):
			return true
	return false


## ★★★【探子】—— 往这一屏塞一个**假违规**, 断言判据逮得到, 再摸掉量真的。
##
## ★它堵的是: **屏建出来了, 但判据没作用在它身上**。
##   没有这一步的话, 「这屏恰好没违规所以绿」与「判据瞎了/量的是另一棵树」
##   **长得一模一样** —— 而本门禁 2026-09-27/28 已经栓过两次同族
##   (登录墙从没被建出来 / 弹层从没被建出来)。
## ★★**四列棘轮每一列都要有一个假违规被逮到** —— 只验两条的话,
##   剩下两列的 0 依旧分不清「干净」与「瞎了」。四个探子各占一块**空地**,
##   互不覆盖(否则一个探子会把另一个的数带偏):
##     web/round —— 12px 圆角 + 2px 四边描边 + 半透底 `StyleBoxFlat`(两条签名各一)
##     tap       —— 40x40 的 `Button`(短边 < 81px = 44pt)。`flat = true` 是故意的:
##                  不带皮的非 flat 按钮会同时进【Godot 默认皮】那条全局名单,
##                  而我要量的是 tap 这一列, 不是造一条别的噪声。
##     frame     —— 一个用**产品自己的** `UISkin.nine("panel-frame.png")` 铺的框,
##                  里头塞一条顶到距边 2px 的字(真实边带 13px ⇒ 越界 11px > 2px 阀值)。
##                  ★框不自己拄贴图路径: 用同一个原语就不会抄一份永远落后的副本。
## ★摸掉之后**再量一次并要求逐个相等** —— 变异必须还原,
##   不还原就把本屏的基线污染了(memory `fb-restore-mutations-after-reverse-verify`)。
func _mm_probe(root: Node, d0: Dictionary) -> Dictionary:
	## ① web + round
	var bad := Panel.new()
	bad.name = "UICONS_PROBE_BOX"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.20, 0.30, 0.50)     # a < 0.95 ⇒ 网页盒那一条要的半透底
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	bad.add_theme_stylebox_override("panel", sb)
	bad.size = Vector2(150, 90)
	bad.position = Vector2(60, 600)
	## 不碰「死点击」那一条(它不是交互位)。
	bad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bad)
	## ② tap
	var badb := Button.new()
	badb.name = "UICONS_PROBE_TAP"
	badb.text = ""
	badb.flat = true
	badb.size = Vector2(40, 40)
	badb.custom_minimum_size = Vector2(40, 40)
	badb.position = Vector2(1150, 610)
	root.add_child(badb)
	## ③ frame
	var badf := Panel.new()
	badf.name = "UICONS_PROBE_FRAME"
	badf.add_theme_stylebox_override("panel",
		UISkin.nine("panel-frame.png", 20, StyleBoxEmpty.new()))
	badf.size = Vector2(300, 120)
	badf.position = Vector2(490, 590)
	badf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(badf)
	var badl := Label.new()
	badl.name = "UICONS_PROBE_SPILL"
	badl.text = "探子压边带"
	badl.size = Vector2(200, 30)
	badl.position = Vector2(2, 2)
	badl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badf.add_child(badl)
	await get_tree().process_frame
	var d1 := _audit(root)
	_ok("★★★探子 Matchmaking: 四列各塞一个假违规, 判据四条都逮得到",
		int(d1["web"]) == int(d0["web"]) + 1 and int(d1["round"]) == int(d0["round"]) + 1
			and (d1["tap"] as Array).size() == (d0["tap"] as Array).size() + 1
			and (d1["frame"] as Array).size() == (d0["frame"] as Array).size() + 1,
		"web %d→%d  round %d→%d  tap %d→%d  frame %d→%d (各应 +1) %s" % [
			int(d0["web"]), int(d1["web"]), int(d0["round"]), int(d1["round"]),
			(d0["tap"] as Array).size(), (d1["tap"] as Array).size(),
			(d0["frame"] as Array).size(), (d1["frame"] as Array).size(),
			str((d1["frame"] as Array).slice(0, 2))])
	badl.free()
	badf.free()
	badb.free()
	bad.free()
	await get_tree().process_frame
	var d2 := _audit(root)
	_ok("★★★探子 Matchmaking: 摸掉之后逐个复原(不复原就把本屏基线污染了)",
		int(d2["web"]) == int(d0["web"]) and int(d2["round"]) == int(d0["round"])
			and int(d2["ctrl"]) == int(d0["ctrl"])
			and (d2["tap"] as Array).size() == (d0["tap"] as Array).size()
			and (d2["frame"] as Array).size() == (d0["frame"] as Array).size(),
		"web %d/%d round %d/%d ctrl %d/%d tap %d/%d frame %d/%d" % [
			int(d2["web"]), int(d0["web"]), int(d2["round"]), int(d0["round"]),
			int(d2["ctrl"]), int(d0["ctrl"]),
			(d2["tap"] as Array).size(), (d0["tap"] as Array).size(),
			(d2["frame"] as Array).size(), (d0["frame"] as Array).size()])
	return d2


## 缝的**两边**各一条断言 —— 只断一边都会漏。
func _mm_after(root: Node, me_scene: Node) -> void:
	var t0: float = float(Time.get_ticks_msec()) / 1000.0
	while _mm_leave_calls == 0 and float(Time.get_ticks_msec()) / 1000.0 - t0 < 10.0:
		await get_tree().process_frame
	## ① 【不注入时它会自己跳场】那一半。
	##   ★为什么不能真让它跳一次给你看: 跳了门禁自己就没了 —— **那正是这条缝
	##     要解决的问题本身**。所以这一半量的是**同一条路真的走到了最后一步**:
	##     回调就在 `change_scene_to_file` 的**前一行**, 它被调到 ⇒ 不注入的话
	##     此刻执行的就是跳场。
	##   ★这一条挡的是「缝变成死代码」: 哪天计时器或跳场那段被删/被挑,
	##     回调不再被调 ⇒ **当场红**, 而不是静默退化成一条永远成立的空检查
	##     (memory `fb-gate-tautological-when-it-spans-a-frame` 同族)。
	_ok("★★分母 Matchmaking: 缝真的被走到了(= 不注入的话此刻正在 change_scene_to_file)",
		_mm_leave_calls == 1, "回调 %d 次" % _mm_leave_calls)
	_ok("★★分母 Matchmaking: 缝没改「跳去哪」(目标仍是战斗场景)",
		_mm_leave_path == _MM_DEST, "目标 %s" % _mm_leave_path)
	## ② 【注入后它不会跳场】那一半。两边加起来才叫「缝真的生效了」。
	_ok("★★分母 Matchmaking: 缝真的拦住了(实例还在树里 + current_scene 还是门禁自己)",
		is_instance_valid(root) and root.is_inside_tree() and get_tree().current_scene == me_scene,
		"in_tree=%s current_scene=%s" % [str(root.is_inside_tree()),
			str(get_tree().current_scene == me_scene)])
	## ★用完立刻还原 —— static, 活过场景切换。下一屏开头有一条断言盯着它。
	_MM._may_leave_for_test = Callable()


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await get_tree().process_frame
	## 门禁自己这棵树 —— 撑合屏那条「真的没跳场」拿它做参照。
	var _me_scene: Node = get_tree().current_scene
	print("=== 全屏 UI 一致性棘轮 ===")
	var tot_ctrl := 0
	var tot_btn := 0
	var tot_lbl := 0
	var tot_mf := 0
	var all_stock: Array = []
	var all_dead: Array = []
	var all_clip: Array = []
	var all_squash: Array = []
	var all_flat9: Array = []
	var all_spill: Array = []
	var all_overlap: Array = []
	for scn in BASE.keys():
		## ★★★每一屏开头先验「上一屏没把池注入留下来」。
		##   `Backend.pool_override` 是 **static**, 活过场景切换 —— 漏清一次,
		##   后面每一屏量的都是那份假池, 而**没有任何判据会发现**。
		##   2026-09-27 反向验证当场证实: 把 `clear()` 换成 `pass` ⇒ 整份 **ALL PASS**。
		##   ⇒ 这一条就是补那个洞的(同族: 状态活过它该活的范围)。
		_ok("★分母 %s: 进这一屏时池注入是干净的(上一屏漏清 = 后面全在量假池)" % str(scn),
			(_BE.pool_override as Dictionary).is_empty(),
			"残留 %d 桶" % (_BE.pool_override as Dictionary).size())
		## ★同族的第二份 static: 撑合屏那条缝。漏还原一次, 后面每一个
		##   跑到撑合屏的用例都会被它拦在原地, 而**没有任何判据会发现**。
		_ok("★分母 %s: 进这一屏时撑合缝是还原的(static, 漏还原会波及后面每一屏)" % str(scn),
			not _MM._may_leave_for_test.is_valid(),
			"注入还在 = 撑合屏从此永不跳场")
		## ★屏名不一定等于场景名: 「登录墙」量的是 Settings 的**另一个状态**。
		var scene_name: String = "Settings" if str(scn) == "登录墙" else str(scn)
		var path := "res://scenes/%s.tscn" % scene_name
		if not ResourceLoader.exists(path):
			_ok("场景在位: %s" % str(scn), false, "找不到 %s" % path)
			continue
		## ★★排行榜/撮合要**真人行**才是真屏。不灌的话排行榜自带的分母打出来是
		##   `[LB] rows=1`(榜上只有我自己) —— 那是占位屏, 与 Record 2026-08-21 同族。
		## ★不是 bug 是产品行为: v0.19.446 修掉「种子池 396 条占名次」之后,
		##   全新档的榜本来就只有自己 ⇒ 要量真榜就得自己灌。
		## ★走 `Backend.pool_override` 而不是写盘 —— `save_pool()` 在 test_mode 下
		##   直接 return(保护真存档), 写盘那条路根本不通(查了才知道)。
		if str(scn) == "Leaderboard" and ResourceLoader.exists("res://tests/_setup_lb_rows.gd"):
			_lb_seed = load("res://tests/_setup_lb_rows.gd")
			## ★★★不许静默跳过: 这个种子脚本第一版有 Parse Error(漏了 `Backend` 的 preload),
			##   `has_method("run")` 直接为 false ⇒ 一声不响地不执行, 而屏幕照样建得起来
			##   ⇒ 量占位屏、门禁报全绿。⇒ 跑不起来**当场判红**。
			_ok("★分母 %s: 种子脚本 `_setup_lb_rows` 跑得起来(跑不起来 = 量占位屏)" % str(scn),
				_lb_seed != null and _lb_seed.has_method("run") and _lb_seed.has_method("clear"))
			if _lb_seed != null and _lb_seed.has_method("run"):
				_lb_seed.run()
		if str(scn) == "Inventory" and ResourceLoader.exists("res://tests/_setup_inv_demo.gd"):
			var sc = load("res://tests/_setup_inv_demo.gd")
			if sc != null and sc.has_method("run"):
				sc.run()
		## ★★商店有"本大轮没打过第一场就锁店"的分支(`_build_locked()` 直接 return)。
		##   开没开店取决于**本机存档** ⇒ 我这台机器量的是真商店, CI 上是全新档量的是占位屏 ——
		##   **两边根本不是同一块屏**, 棘轮数字自然对不上。(2026-08-19 在 _probe_webbox 上先撞到:
		##   它报"商店只有 1 个 stylebox", 那是占位屏。) ⇒ 在这里显式推进有内容的那一支。
		if int(gs.season_total_battles) <= 0:
			gs.season_total_battles = 3
		## ★★2026-08-21 与上面商店同一类坑, Record 漏了:
		##   Record 屏画的是 `GameState.match_history`(`RecordScene.gd:73`) ⇒ **依赖本机存档**。
		##   我这台打过几局就有卡片, CI 全新档是空的 ⇒ 两边不是同一块屏,
		##   而基线 0 正好是**空档占位屏**的数字 = 棘轮在守占位屏, 真正的 Record 从没被量过。
		##   (实测: 我跑了一次带窗口的 demo 写进 1 条对局记录, 这条门禁当场红 ——
		##    窗口模式 `test_mode=false` 会写真存档, headless 才不写。)
		## ⇒ 在内存里**钉死**一份合成记录(不写盘: test_mode 已开), 两边量同一块屏。
		if str(scn) == "Record":
			var synth: Array = []
			for mi in range(6):
				synth.append({"result": "win" if mi % 2 == 0 else "lose",
					"lineup": ["basic", "fire"], "mode": "实时", "turn": 30 + mi})
			## ★回放 S3(2026-10-04): 第一行挂一个本机有录像的回放 id ⇒ 战绩页上的「回放」入口
			##   (整行热区 + 行尾签牌)也被这四条判据量到 —— 不挂的话量的是一块没有入口的屏。
			##   录像文件只要「在」就出入口(判据 `ReplayFetcher.has_replay`), 内容不读。
			var rp_id := "00000000-0000-4000-8000-0000000000a1"
			DirAccess.make_dir_recursive_absolute("user://replays/")
			var rpf := FileAccess.open("user://replays/%s.rpl" % rp_id, FileAccess.WRITE)
			if rpf != null:
				rpf.store_buffer(PackedByteArray([0x78, 0x9c]))
				rpf.close()
			synth[0]["replay_id"] = rp_id
			gs.match_history = synth
		# ★商店货架已在 ShopScene 里钉死(test_mode ⇒ _rng.seed 固定, 不 randomize)。
		#   之前试 `seed(20260818)` 没用是因为**那是全局 RNG, 而商店有自己的 RandomNumberGenerator** ——
		#   钉错了对象, 不是"钉不住"。现三次连跑都是 0/11。
		var inst = (load(path) as PackedScene).instantiate()
		## ★★必须在 `add_child` **之前**注入 —— `_ready` 是 add_child 那一刻跑的,
		##   之后再设就晚了(墙已经按真实配置决定过建不建)。
		if str(scn) == "登录墙":
			inst.acct_override = 1
		## ★★BracketMap 不喂数据就只画一句空态(见 `_empty_text()`)
		##   ⇒ 那是**量占位屏**(本仓 Record 2026-08-21 正是这样, 基线 0 守了一整个空档屏)。
		##   ⇒ 走它自己的真入口 `set_data()` 喂一个 8 人桶。
		if str(scn) == "BracketMap" and inst.has_method("set_data"):
			## 形状照 `verify_bracket_map.gd:385` 的真实用法, 不是我编的。
			inst.set_data({"size": 8, "round": 2, "me": 2,
				"names": ["甲龟", "乙龟", "丙龟", "丁龟", "戊龟", "己龟", "庚龟", "辛龟"],
				"done": {"1:0": 0, "1:1": 1, "1:2": 0, "1:3": 1}}, {}, 1789862400 + 10 * 3600)
		## ★★★撑合屏要一条【冻住时序的缝】才量得到 —— 详见上面 `_mm_*` 那一节
		##   与 `MatchmakingScene._may_leave_for_test` 的长注释。
		##   ★注入必须在 `add_child` **之前**: `_ready` 是 add_child 那一刻起跑的。
		if str(scn) == "Matchmaking":
			_mm_leave_calls = 0
			_mm_leave_path = ""
			_MM._may_leave_for_test = _mm_may_leave
		add_child(inst)
		## ★用完立刻清掉池注入 —— `Backend.pool_override` 是 static, 活过场景切换,
		##   留着会把后面每一屏都喂上这份假池。
		if _lb_seed != null:
			_lb_seed.clear()
			_lb_seed = null
		## ★等够 MIN_WAIT 墙钟秒再量(见 _settle 的长注释)。返回值只打印不当判据 ——
		##   带常驻动效的屏永远"稳不住", 拿它当失败就是判据不匹配被测对象。
		## ★★撑合屏: **先等到对手卡建出来**再让 `_settle` 去判稳。
		##   不这么做的话它就是靠运气: `_settle` 的 MIN_WAIT(2.0s) 就在对手卡
		##   那个 2.2s 计时器**前面**, 雷达环恰好有六帧不动 ⇒ 当场量到占位屏。
		if str(scn) == "Matchmaking":
			var _vs_ok: bool = await _mm_wait_vs(inst)
			_ok("★★分母 Matchmaking: 对手卡真的建出来了(不等它 = 在量「正在找对手」那块占位屏)",
				_vs_ok, "对手名「%s」" % _mm_opp_name())
		var _stable: bool = await _settle(inst)
		print("    [落位] %s: %s" % [str(scn), "已静止" if _stable else "仍有常驻动效(入场已过, 照量)"])
		var d := _audit(inst)
		## ★★★第三层分母: **判据真的作用在这一屏身上吗**。见 `_mm_probe`。
		if str(scn) == "Matchmaking":
			d = await _mm_probe(inst, d)
		var b: Dictionary = BASE[scn]
		tot_ctrl += int(d["ctrl"])
		tot_btn += int(d["btn"])
		tot_lbl += int(d["lbl"])
		tot_mf += int(d["mfstop"])
		_ok("★分母 %s: 真的建起来了" % str(scn), int(d["ctrl"]) >= int(MIN_CTRL.get(scn, 10)),
			"可见控件 %d (下限 %d)" % [int(d["ctrl"]), int(MIN_CTRL.get(scn, 10))])
		if _DUMP:
			var _h: Array = d.get("hits", []) as Array
			print("  ── %s 明细 %d 条(web/round 命中) ──" % [str(scn), _h.size()])
			for _line in _h:
				print("     %s" % str(_line))
		## ★★★登录墙的**真分母**: 墙自己那句话必须在屏幕上。
		##   控件下限挡不住这一屏(见 MIN_CTRL 那段注释) —— 墙不弹了控件反而更多。
		##   字取 `login_wall_head()`(产品自己那一处), 不在测试里拼。
		if str(scn) == "登录墙":
			var _head: String = _P2CX.login_wall_head()
			var _found: bool = false
			var _stk: Array = [inst]
			while not _stk.is_empty():
				var _n = _stk.pop_back()
				if _n is Label and str((_n as Label).text).find(_head) >= 0:
					_found = true
				for _c in _n.get_children():
					_stk.append(_c)
			_ok("★★分母 登录墙: 墙那句话「%s」真的在屏幕上" % _head, _found,
				"找不到 = 量的是另一块屏(控件数挡不住这一类)")
		## ★回放 S3 的分母: 战绩页上「回放」入口真的建出来了(不然下面四条量的是没有入口的屏)。
		if str(scn) == "Record":
			var _rpb: Array = inst.find_children("ReplayBtn", "Button", true, false)
			_ok("★分母 Record: 「回放」入口真的在屏幕上(%d 个)" % _rpb.size(), _rpb.size() == 1)
		_ok("%s 网页盒 ≤ %d" % [str(scn), int(b["web"])], int(d["web"]) <= int(b["web"]),
			"实测 %d" % int(d["web"]))
		_ok("%s 圆角盒 ≤ %d" % [str(scn), int(b["round"])], int(d["round"]) <= int(b["round"]),
			"实测 %d" % int(d["round"]))
		_ok("%s 热区不足(短边<44pt) ≤ %d" % [str(scn), int(b["tap"])],
			(d["tap"] as Array).size() <= int(b["tap"]),
			"实测 %d %s" % [(d["tap"] as Array).size(), str((d["tap"] as Array).slice(0, 4))])
		_ok("%s 文字压边带 ≤ %d" % [str(scn), int(b["frame"])],
			(d["frame"] as Array).size() <= int(b["frame"]),
			"实测 %d %s" % [(d["frame"] as Array).size(), str((d["frame"] as Array).slice(0, 4))])
		for v1 in (d["stock"] as Array):
			all_stock.append("%s:%s" % [str(scn), str(v1)])
		for v2 in (d["dead"] as Array):
			all_dead.append("%s:%s" % [str(scn), str(v2)])
		for v3 in (d["clip"] as Array):
			all_clip.append("%s:%s" % [str(scn), str(v3)])
		for v4 in (d["squash"] as Array):
			all_squash.append("%s:%s" % [str(scn), str(v4)])
		for v5 in (d["flat9"] as Array):
			all_flat9.append("%s:%s" % [str(scn), str(v5)])
		for v6 in (d["spill"] as Array):
			all_spill.append("%s:%s" % [str(scn), str(v6)])
		for v7 in (d["overlap"] as Array):
			all_overlap.append("%s:%s" % [str(scn), str(v7)])
		## ★★撑合屏收尾: 缝的两边各一条断言 + 还原 static。
		if str(scn) == "Matchmaking":
			await _mm_after(inst, _me_scene)
		inst.queue_free()
		await get_tree().process_frame
	await _selftest_interactive()
	await _selftest_frame_pairing()
	await _audit_popups()
	await _test_cursor_scale()
	print("  ── 全屏合计 ──")
	print("    [盲区分母] 非 BaseButton 却能吃鼠标事件(MOUSE_FILTER_STOP/PASS)的控件: %d 个" % tot_mf)
	print("      —— 这个数是「判据只认某类节点」那条失明的**规模**。`_interactive()` 现在收了")
	print("         Range/LineEdit/TextEdit/接了 gui_input 的, 剩下这 %d 个里绝大多数是" % tot_mf)
	print("         Panel/ColorRect 这类**默认就 STOP** 的容器(不是交互点), 所以只打印不判红。")
	_ok("★分母: 盲区分母本身要量得到(>0 说明这条统计真的在跑)", tot_mf > 0, "%d 个" % tot_mf)
	_ok("★分母: 扫到的可见控件 ≥ 500", tot_ctrl >= 500, "%d 个" % tot_ctrl)
	_ok("★分母: 扫到的按钮 ≥ 25", tot_btn >= 25, "%d 个" % tot_btn)
	_ok("★分母: 扫到的带字标签 ≥ 120", tot_lbl >= 120, "%d 个" % tot_lbl)
	_ok("没有【还用 Godot 默认皮】的按钮", all_stock.is_empty(), str(all_stock.slice(0, 5)))
	_ok("没有【收不到点击】的交互控件", all_dead.is_empty(), str(all_dead.slice(0, 5)))
	_ok("没有【被 clip_text 截断】的文字", all_clip.is_empty(), str(all_clip.slice(0, 5)))
	_ok("没有【被挤成 <6px】的文字", all_squash.is_empty(), str(all_squash.slice(0, 5)))
	_ok("没有【边距和 ≥ 尺寸】的退化九宫格", all_flat9.is_empty(), str(all_flat9.slice(0, 5)))
	_ok("没有【行数装不下】的文字", all_spill.is_empty(), str(all_spill.slice(0, 5)))
	_ok("没有【两段文字压在一起】", all_overlap.is_empty(), str(all_overlap.slice(0, 5)))
	print("  %d passed, %d failed" % [_pass, _fail])
	if _fail == 0:
		print("ALL PASS — 全屏 UI 一致性")
	get_tree().quit(1 if _fail > 0 else 0)


# ══════════════════════════════════════════════════════════════════════════
#  ★★CURSOR_SCALE —— 自绘光标相对 UI 的大小不许随窗口变
# ══════════════════════════════════════════════════════════════════════════
## 由来 (2026-09-29 台账 ④, 用户原话「不合理的地方比如这个光标为什么这么大？」):
##   `autoload/CursorTheme.gd` 原来写 `_cur.scale = base_scl / clampf(cf, 0.5, 4.0)`,
##   把爪子钉死在**屏幕物理 ~24px**、故意不随内容缩放。实测(tests/_probe_cursor_size.gd)
##   换算成设计像素时它**随窗口变四倍**: 2560 宽 12px / 1280 宽 24px / 640 宽 48px,
##   而本文件自己的触控下限 `TOUCH_MIN = 81`(44pt) ⇒ 小窗口下一只爪子有触控区的 59%。
##   附带: `clampf` 的下界 0.5 在 480 宽(cf=0.375)**真的被夹住** ⇒ 那句"固定 24px"本来就是假的。
##
## ★这是**手机触屏游戏**: `CursorTheme._ready` 在 Android/iOS 直接早退, 手机上一只爪子都没有
##   ⇒ 这只爪子只存在于桌面/开发期, 「和屏上别的东西同一套比例」比「1:1 照抄网页 PoC 的
##   position:fixed div」重要。所以改成**只吃状态缩放**(0.8/0.9/1.0/1.12), 恒 24 设计px。
##
## ★判据形状(memory「判据要刚好卡住那个形状」): 那个形状是**「相对 UI 的大小随窗口变」**,
##   所以主判据是**跨窗口尺寸的一致性**(旧写法 4 倍差 ⇒ 红), 幅度上限只是第二道。
## ★分母(memory「凡『X 不许超上限』必须配一条『X 真的到过上限附近』"): 必须先证明这一轮
##   **真的量到了一个跨度很大的 cf 区间** —— 窗口没真变过的话"到处都一样大"是恒真的空检查。
## ★跑的是产品自己那份建树 + 每帧代码(`_build_cursor()` / `_process()`), 只绕过平台早退那两行;
##   量的是真节点的全局变换 × 真 `get_screen_transform()`, 不是我这里重算一遍公式。
const _CURSOR_DESIGN := Vector2(1280.0, 720.0)   # project.godot window/size/viewport_*
## 爪子在【设计像素】里的高度上限 = 触控下限的 40%。
## 24(现状) 过, 48(旧写法在 640 宽时) 红; 悬停态 1.12× = 26.9 也还在里面。
const _CURSOR_MAX_OF_TOUCH := 0.40


func _test_cursor_scale() -> void:
	print("  ── ★★CURSOR_SCALE: 光标相对 UI 的大小 ──")
	var src := FileAccess.get_file_as_string("res://autoload/CursorTheme.gd")
	_ok("★分母 CURSOR_SCALE: 读得到 CursorTheme.gd", src != "")
	var ct = load("res://autoload/CursorTheme.gd").new()
	add_child(ct)
	await get_tree().process_frame
	## ★先证明【平台早退真的把建树挡住了】: 无头下 _ready 一个节点都不该建。
	##   这条同时是"手机上没有这只爪子"那半句的行为证据(同一道早退)。
	_ok("★★CURSOR_SCALE: 无头下 `_ready` 没建爪子(平台早退真的挡住了建树)",
		ct._cur == null and not bool(ct._enabled),
		"_cur=%s _enabled=%s" % [str(ct._cur), str(ct._enabled)])
	_ok("★★CURSOR_SCALE: 手机(Android/iOS)不建自绘光标 ⇒ 这只爪子只存在于桌面",
		src.contains("OS.get_name() in [\"Android\", \"iOS\"]"),
		"早退没了 = 手机上会残留一只绿龟爪(用户 2026-07-18)")
	var mm0 := Input.mouse_mode
	ct._build_cursor()      # 产品自己那份建树代码(只绕过早退)
	_ok("★分母 CURSOR_SCALE: 手动建树之后爪子在场(不在场 ⇒ 下面全是空检查)",
		ct._cur != null and ct._g != null and bool(ct._enabled),
		"_cur=%s _g=%s" % [str(ct._cur), str(ct._g)])
	if ct._cur == null or ct._g == null:
		ct.queue_free()
		Input.mouse_mode = mm0
		return

	## ★★控件框必须真的等于 `ART` —— `_g.size = ART` 那行要是又被写到 `expand_mode` 前面,
	##   默认 EXPAND_KEEP_SIZE 会把它上调到贴图尺寸(48 = ART 的两倍), 而且**不报任何错**。
	##   这条量的是真节点的 `size`, 不是源码里那行赋值。
	_ok("★★CURSOR_SCALE: 爪子控件框 = ART(%d) —— 不是被上调到贴图尺寸的 %d" % [ct.ART, ct.ART * 2],
		is_equal_approx((ct._g as Control).size.y, float(ct.ART))
			and is_equal_approx((ct._glow as Control).size.y, float(ct.ART)),
		"_g.size=%s _glow.size=%s 贴图=%s" % [str((ct._g as Control).size),
			str((ct._glow as Control).size), str((ct._g as TextureRect).texture.get_size())])
	## ★热点: `HOT`/`ORIGIN` 是 24 坐标系的, 控件框一胀大爪尖就不落在鼠标点上了。
	##   量法: 美术坐标 (11,1)(爪尖) 画在哪 vs 代码认为鼠标点在哪, 两者之差应为 0。
	var _S: Vector2 = (ct._g as Control).size
	var _drawn: Vector2 = (ct._g as Control).get_global_transform() 		* Vector2(11.0 * _S.x / ct.ART, 1.0 * _S.y / ct.ART)
	var _assumed: Vector2 = (ct._cur as Control).get_global_transform() * ct.HOT
	_ok("★★CURSOR_SCALE: 爪尖真的落在鼠标点上(热点偏移 = 0)",
		(_drawn - _assumed).length() <= 0.01,
		"偏移 %s (控件框胀大时实测 (11,1))" % str(_drawn - _assumed))

	var vp := get_viewport()
	var root_win := get_tree().root
	var size0: Vector2i = root_win.size
	var rows: Array = []          # [窗口, cf_真实, 设计px, 物理px]
	var design_min := 1e9
	var design_max := -1.0
	var cf_min := 1e9
	var cf_max := -1.0
	for win in [Vector2i(2560, 1440), Vector2i(1920, 1080), Vector2i(1280, 720),
			Vector2i(800, 600), Vector2i(640, 360), Vector2i(624, 351)]:
		root_win.size = win
		await get_tree().process_frame
		await get_tree().process_frame
		ct._process(0.0)          # 产品自己的每帧代码(它才是决定 scale 的那一行)
		var cf: float = vp.get_screen_transform().get_scale().y
		var design_px: float = (ct._g as Control).get_global_transform().get_scale().y \
			* (ct._g as Control).size.y
		var phys_px: float = design_px * cf
		rows.append([win, cf, design_px, phys_px])
		design_min = minf(design_min, design_px)
		design_max = maxf(design_max, design_px)
		cf_min = minf(cf_min, cf)
		cf_max = maxf(cf_max, cf)
		print("    [实测] 窗口 %dx%d  cf=%.4f  设计px=%.1f (占触控下限 %.0f%%)  物理px=%.1f"
			% [win.x, win.y, cf, design_px, design_px / TOUCH_MIN * 100.0, phys_px])
	root_win.size = size0
	await get_tree().process_frame

	## ① 分母: 这一轮真的量到了一个跨度很大的 cf 区间 —— 否则"到处一样大"是恒真的
	print("    [分母] 量了 %d 个窗口尺寸, cf 区间 %.4f ~ %.4f" % [rows.size(), cf_min, cf_max])
	_ok("★★分母 CURSOR_SCALE: cf 真的跨了大区间(≤0.55 到 ≥1.5), 否则下面那条恒真",
		rows.size() >= 4 and cf_min <= 0.55 and cf_max >= 1.5,
		"n=%d cf %.4f~%.4f" % [rows.size(), cf_min, cf_max])
	## ② 主判据: 换窗口大小时, 爪子在【设计像素】里的大小不许变(旧写法这里是 4 倍差)
	var ratio: float = (design_max / design_min) if design_min > 0.0 else 999.0
	_ok("★★★CURSOR_SCALE: 爪子相对 UI 的大小不随窗口变(设计px 最大/最小 ≤ 1.02)",
		ratio <= 1.02, "设计px %.1f ~ %.1f ⇒ %.2f 倍(两个 bug 都在时实测 24~96 = 4.00 倍)"
			% [design_min, design_max, ratio])
	## ③ 幅度: 相对本仓自己的触控下限不许太大
	_ok("★★CURSOR_SCALE: 爪子高度 ≤ 触控下限的 %.0f%%(=%.1f 设计px)"
			% [_CURSOR_MAX_OF_TOUCH * 100.0, TOUCH_MIN * _CURSOR_MAX_OF_TOUCH],
		design_max <= TOUCH_MIN * _CURSOR_MAX_OF_TOUCH,
		"实测最大 %.1f 设计px = 触控下限的 %.0f%%" % [design_max, design_max / TOUCH_MIN * 100.0])
	## ④ 反过来: 物理像素【应该】跟着窗口走(= 它真的和别的像素同比例缩)。
	##   这条和 ② 是一对: 只有 ② 会让"干脆写死一个常数"也过, 加上 ④ 才钉住"跟着 UI 缩"。
	var phys_min := 1e9
	var phys_max := -1.0
	for r in rows:
		phys_min = minf(phys_min, float(r[3]))
		phys_max = maxf(phys_max, float(r[3]))
	_ok("★★CURSOR_SCALE: 物理像素跟着窗口走(≥3 倍跨度) ⇒ 它和场上别的像素同比例",
		phys_min > 0.0 and phys_max / phys_min >= 3.0,
		"物理px %.1f ~ %.1f ⇒ %.2f 倍" % [phys_min, phys_max, (phys_max / phys_min) if phys_min > 0.0 else 0.0])
	## ⑤ 那条 clamp 的谎话没了: 缩放不再读内容缩放因子, 也就没有"被夹住"这回事
	var proc := _cursor_strip_comments(_cursor_func_body(src, "_process"))
	_ok("★CURSOR_SCALE: `_process` 不再用内容缩放因子给爪子定尺寸(没有 clamp 下界可撒谎)",
		not proc.contains("get_screen_transform"),
		"_process 里还在读 get_screen_transform ⇒ 又把爪子钉回物理像素了")

	ct.queue_free()
	Input.mouse_mode = mm0
	await get_tree().process_frame


## 剥掉 `#` 注释 —— 上面那条判据搜的是【代码】里还有没有 get_screen_transform。
## ★不剥会栽: 修好那一行时我在旁边留了一句「(旧写法: base_scl / clampf(vp.get_screen_transform()…))」,
##   门禁当场把它当成代码判红了 —— 判据搜源码字符串就必须先剥注释。
func _cursor_strip_comments(block: String) -> String:
	var out := ""
	for line in block.split("
"):
		var s := str(line)
		var in_q := false
		var q := ""
		var cut := -1
		for i in s.length():
			var ch := s[i]
			if in_q:
				if ch == q and (i == 0 or s[i - 1] != "\\"):
					in_q = false
			elif ch == "\"" or ch == "'":
				in_q = true
				q = ch
			elif ch == "#":
				cut = i
				break
		out += (s.substr(0, cut) if cut >= 0 else s) + "
"
	return out


## 取某个函数的函数体源码(到下一个顶层 func 为止)。
func _cursor_func_body(src: String, fname: String) -> String:
	var head := "\nfunc %s(" % fname
	var i := src.find(head)
	if i < 0:
		return ""
	var start := i + 1
	var j := src.find("\nfunc ", start)
	if j < 0:
		j = src.length()
	return src.substr(start, j - start)
