class_name TentacleRig
extends RefCounted
## 灵物触手 · 唯一的动作控制器(2026-11-13 重写, 方案书 docs/plans/20261113b-灵物触手最后一版优化.md §7)
##
## 用户 11-13:「不应该加什么限制啊！…以前一些版加了很多七七八八的限制」→ 看完全部限制清单
##   (docs/plans/img-20261113-触手/触手全部限制清单.md)后「行」= 拆掉重写。
## 原来那套: 平面锁(只在「前 + 上」里动) + 已经关掉的物理(死代码) + 写死的逐节单调拍下公式 + 长度每帧硬拉回 +
##   地面硬钳 + 四层过渡混合, 几层互相拉扯 ⇒ 线动得不自然。
##
## 这里只有一个来源驱动整根线:
##   ① 每一节方向 = 俯仰角 + 侧偏角 ⇒ 整根能在立体空间里转身、扭、绕(不锁平面)。
##   ② 每个状态都是设计好的动作(阶段与节奏照用户 LoL 录屏量的; 姿势是我们自己摆的, 不是描帧数据)。
##   ③ 惯性只有一种: 每一节方向一个欠阻尼弹簧追目标(越往梢越软)⇒ 自然甩尾、过冲、回弹; 状态切换不再需要过渡补丁。
##      拍下那一段直接用设计好的动作(自带甩尾), 保证梢端贴地 = 伤害时刻 T_TOUCH。
##   ④ 长度由设计决定(待机短, 拍下甩长); 位置 = 方向 × 段长逐节累加, 不再每帧硬拉。不贴地钳: 落地姿势本身就是贴地躺平。
##   ⑤ 背侧(背鳍那一侧)从根部沿身体逐节平行传递 ⇒ 鳍始终在同一侧, 身体扭的时候跟着翻面。
## 伤害、状态机、各态时长仍归 TentacleVfx(这里只读 T_*)。

const SEG := 36
const U6 := [0.05, 0.25, 0.45, 0.65, 0.85, 1.0]

## ── 姿势(6 个控制点的俯仰角, 度; 0 = 朝目标水平, 90 = 竖直向上, 180 = 朝身后水平) ──
const P_UP := [90.0, 90.0, 90.0, 90.0, 90.0, 90.0]
const P_GROUND := [12.0, 2.0, 0.0, 0.0, 0.0, -1.0]

## 整套拍下的关键姿势, 按「离刀光(= 伤害时刻 T_TOUCH)还有几秒」τ 记。
## 2026-11-13 来源 = 用户手标中线: 用户「过滤算法也是有问题…我来对每个图片进行中线的标注…手抖…你来防止过拟合」⇒
##   桌面「触手中线标注」里 LoL 录屏 3 击(31.1 / 45.2 / 62.8 s, 两根以上不同的触手)每击 18 帧由用户手画中线;
##   tools/oneoff/read_annotation.py 读回(顺着笔画走, 圈也能读) → 平滑样条抹手抖 → 换算成沿身长 6 段角度;
##   tools/oneoff/annot_poses.py 每个控制点跨击取圆周平均(离其余两击 > 45° 的剔除) → 时间上 1:2:1 顺一遍。
## 动作: τ ≥ 0.86 仍在待机(预警带已经亮了) → 竖起、顶端卷成 C → 整根往后仰、C 越压越低 → 0.20 躺到身后(梢端翘起) →
##   0.15–0.10 外段往后、往下、往前一路卷 → 0.08–0.02 根部竖起、在根部旁边盘成一个圈 → 刀光出来时本体还盘着,
##   晚 2 帧(LAND_TAU)圈松开甩直贴地(用户的线: 45.2 / 62.8 两击到 0.000 帧还是圈)。
##   ★不是「贴地从侧面横扫」(我只看一击几帧目测的错误结论, 用户 11-13 指出)。
## 甩直那一下: 中段从头顶翻过去(角度往 0 走), 外段顺着原来盘的方向转到朝前(角度写成 360)—— 圈往外滚开(鞭子)。
## (11-13 第一版取 −0.033: 并排看刀光前一帧我们已经开始甩直, LoL 三击里两击还盘着 ⇒ 挪到刀光后 3 帧)
const LAND_TAU := -0.05
const STRIKE_T := [0.86, 0.800, 0.720, 0.600, 0.500, 0.400, 0.330, 0.260, 0.200, 0.150, 0.133, 0.117, 0.100, 0.083, 0.067, 0.050, 0.033, 0.017, LAND_TAU]
const STRIKE_P := [
	null,                                              # 待机
	[83.0, 94.9, 72.3, 50.6, -102.1, -117.0],          # 0.800
	[95.9, 121.4, 98.4, 71.0, -77.5, -124.5],          # 0.720
	[100.9, 145.3, 134.7, 90.1, -50.1, -101.1],        # 0.600 往后仰, C
	[102.3, 154.8, 165.0, 105.0, -8.8, -57.0],         # 0.500
	[105.6, 156.9, 179.0, 115.6, 40.2, -12.6],         # 0.400
	[109.1, 159.5, 184.7, 124.7, 75.1, 35.0],          # 0.330 C 松开
	[111.9, 156.4, 189.6, 144.3, 106.9, 95.5],         # 0.260
	[114.1, 148.1, 192.3, 184.4, 156.6, 153.6],        # 0.200 躺到身后
	[111.9, 141.8, 192.6, 225.6, 220.6, 209.5],        # 0.150 外段往后下卷
	[107.9, 137.7, 193.1, 244.4, 264.0, 261.1],        # 0.133
	[105.8, 132.8, 196.4, 250.4, 286.2, 300.1],        # 0.117
	[101.5, 126.5, 195.2, 256.4, 306.6, 337.4],        # 0.100
	[93.3, 120.5, 183.0, 259.8, 314.3, 357.4],         # 0.083 盘成圈
	[89.0, 114.8, 167.9, 260.9, 318.4, 357.2],         # 0.067
	[90.5, 106.2, 148.2, 263.4, 325.9, 355.9],         # 0.050
	[83.9, 95.3, 137.9, 262.7, 333.5, 372.5],          # 0.033
	[65.6, 86.0, 159.6, 252.3, 347.8, 415.1],          # 0.017 刀光前一帧, 还盘着
	[12.0, 2.0, 0.0, 360.0, 360.0, 360.0],             # LAND_TAU 甩直贴地
]
## 拉长: τ 从 LEN_T0 到 LEN_T1 由待机长度拉到全长(用户手标的线: 45.2 / 62.8 两击 0.6–0.5 就到全长, 31.1 晚一些)
const LEN_T0 := 0.80
const LEN_T1 := 0.45
## 拍下态里从这一刻起(离贴地 DIRECT_TAU 秒)完全照关键姿势走(不经弹簧) ⇒ 梢端贴地 = 伤害时刻 T_TOUCH
const DIRECT_TAU := 0.15
## 点刺(追击)的加速
const SLAM_EASE := 2.2
## 贴地后梢端回弹一下(度 / 衰减 / 角频率)
const BOUNCE_DEG := 8.0
const BOUNCE_DECAY := 12.0
const BOUNCE_W := 30.0
## 收回(11-13 用户手标 31.1 s 那一击刀光之后 8 帧): 贴地后一直趴到约 +0.6 s(整个收回态都趴着、全长不缩),
##   +0.6 s 起梢端才先翘起 ⇒ 抬起放在进待机后的头 REC_LIFT 秒: 梢端先抬(根部晚 RECOVER_ROOT_DELAY), 身长同时缩回待机长度。
##   (原来贴地 0.33 s 就开始抬, 是我早前目测的, 手标推翻了)
const REC_LIFT := 0.45
const RECOVER_ROOT_DELAY := 0.15
## 出土尖芽: 竖着时只露出这么长(录屏尖芽和卷好的待机差不多高), 张开卷钩时才长满; 鳍先半合着贴在身上
## 尖芽冒出来的高度(占长满时的比例) —— 11-13 用户手标两次出土光柱后 0–1.2 秒(第四批 + 第三批), 两次取平均:
##   光柱那一刻已经冒出 4 成多(前 0.1 秒里拱出来), 之后一直慢慢长, 约 1.2 秒才长满(原来 0.22 秒就冒到 7 成、再停住, 是我设计的)
## 光柱之前多少秒开始拱出来
const BUD_FIN := 0.3
## 预警 / 收回沿身长的滞后(秒 / 单位身长): 根部先动, 梢端跟上
## (0.08 时 C 形躺倒那一下梢端还卷着、全身已经拉长 ⇒ 拉成一个大圈; 录屏 τ 0.30 已经整根躺平)
const MOVE_LAG := 0.0   # 量出来的关键姿势本身已带梢端滞后(整根快照), 不再另加

## 弹簧: 根部角频率 OMEGA0(弧度 / 秒), 梢端软到 1 − OMEGA_TIP_SOFT; 阻尼比 ZETA(< 1 ⇒ 会过冲一点)
## 11-13 量 LoL 中间那根待机(每秒 60 帧, 只量规律): 梢端每次停下几乎不回弹(回摆比 0.07); 我们 ZETA 0.55 ⇒ 回摆比 0.47, 一直在晃
##   ⇒ 阻尼加大到几乎不过冲, 梢端更软(慢半拍跟上)
const OMEGA0 := 20.0
const OMEGA_TIP_SOFT := 0.55
const ZETA := 0.92
const SUB_H := 1.0 / 120.0
## 光柱之后的长出(待机头 GROW_T 秒, 照 LoL 录屏): 长到全高 → 竖着停 → 卷钩张鳍 → 放倒(放倒由弹簧自然完成)
## 11-13 两次出土(墙根 17.6 s / 中间 70 s)每秒 30 帧量, 以光柱那一刻为 0: 尖芽 0.2 秒就冒到全高 · 竖着站到 0.7–0.8 秒 ·
##   之后从梢端卷开、身子倾倒, 慢慢来, 约 1.9 秒卷成第一个待机姿势(原来冒得慢 0.55、卷得急 1.0→1.35, 正好反了)
const GROW_HOLD := 0.75
## 交给待机: LoL 1.88 秒卷成的圈一直保持到 75.0 秒(光柱后 2.65 秒)待机 A 段的第二个关键姿势(同一个圈), 那以后才是待机自己的动作。
##   11-13 夜: 原来 1.9–2.4 秒就混进待机 74→75 秒之间「拱形 → 圈」的过渡 ⇒ 圈先打开、头翻到左上成「?」再合上(用户「二十四之后还有啊」)
const GROW_UNFURL := 2.35
const GROW_T := 2.65
## 出土关键姿势的最后一项 = 待机 A 段 IDLE_JOIN 秒那个姿势(在光柱后 IDLE_FROM_BEAM + IDLE_JOIN 秒)
const IDLE_JOIN := 1.0
## 光柱后多少秒 = 待机 A 段的开头(LoL 中间那根: 光柱 72.35 s, 待机 A 段从 74.0 s 量起)
const IDLE_FROM_BEAM := 1.65
## 出土全程的关键姿势(11-13 用户手标中间那根出土光柱后 0–1.9 秒共 16 张, 顺时间连续反推 tools/oneoff/fit_spawn_keys2.py;
##   墙根那根作核对):
##   0.7–1.0 竖着、梢端往下勾成小圈 → 1.2–1.5 整根朝一侧拱成倒 U → 1.7–1.9 卷下去、梢端打圈 = 第一个待机姿势。
##   0.5 秒前竖直; 1.88 的圈保持到 IDLE_FROM_BEAM + IDLE_JOIN(2.65 秒), GROW_UNFURL → GROW_T 交给待机。
## 弹簧会让姿势慢约 0.1 秒 ⇒ 关键姿势提前取
## 出土后打开了跟随(弹簧): 每一节慢 2·ZETA / ω(u) 秒(根部约 0.09、梢端约 0.2 —— 梢端弹簧软) ⇒ 关键姿势每一节按自己的慢量提前取。
##   11-13 晚: 原来一律提前 0.09 ⇒ 梢端还慢 0.1 秒, 1.68 秒头该卷下来时还平着(和用户的线差 0.10)
## 对折 → 关键姿势: 露出的身长在这么多秒里长满
const GROW_HAND := 0.2
## 平面: 侧对镜头(和游戏里出土时触手的平面一致; 11-13 用户「出了土之后…头明明是向下微微动，我们怎么直接向左上角了」——
##   之前按斜对镜头的平面反推, 一条 2D 线对应的 3D 姿势选成了「上半截朝镜头折下来」, 放进侧对镜头的游戏里就成了往左上卷一大圈)。
## 0.38 秒那张梢端小钩正好转到对着镜头、画面上看成直的, 去掉(不然小钩一闪没了又出来)。
## 手标量出来(中间那根): 尖芽一直略往后仰(最高点在根部右边 11–16 像素), 0.28 秒起梢端朝后往下勾, 勾下来 40–60 像素(身高约 130)。
## 0–0.6 秒尖芽: 不用 3D 反推(一条 2D 线对应多种 3D 姿势, 反推挑成了「中段就折下来」⇒ 矮、往旁边横出去, 用户 11-13 指出「头明明是向下微微动」),
##   直接按手标线量出来的数摆: 尖芽几乎竖直(最高点只比根部偏 11–16 像素); 0.21 起梢端往后折、垂下来,
##   垂下的长度 0.28 秒约 40 像素、0.48–0.58 秒约 50–60 像素(身高约 130 像素, 镜头俯角下竖直方向要 ÷0.56 还原 ⇒ 折下来的约占身长 2–3 成)。
## 0.85 秒以后(头已经出来)的关键姿势: 用【我们游戏的镜头】(俯角 51.8°、正面朝画面右)从用户手标反推(tools/oneoff/fit_spawn_ourcam.py),
##   这样我们画面上的样子就是用户在 LoL 上标的样子; 不翻转(11-13 用户「我不知道你为什么要镜像」)
const GROW_KEYS := [
	## 0.85–1.18 由对折段给(见 HP_T); 对折播到 HP_END, 同一个形状连续变, 不在两套姿势之间切。
	## 1.18 / 1.35 / 1.51 三张是我设计的(1.18 那张在对折段 HP_T 末项; 先试过对折播到 1.10 就交给画面平面里的 1.18 ⇒ 头 0.08 秒里从身后翻到左边, 一帧挪 52 像素)(11-13 夜用户「二十、二十一、二十二针肯定是有问题的…它在墙里面，我们看不到…你得设计这三针，好接到这个二十三针」):
	##   LoL 1.01–1.51 秒上半截插进石墙看不见, 用户那几张线的顶是推的 ⇒ 原来照线反推成「1.18 往左勾 → 1.35 又整根竖直(高 5.3 米 = 待机 1.55 倍)
	##   → 1.51–1.68 0.15 秒里塌下去(头一帧掉 31 像素)」。改成一路走下去: 长到约待机 1.3 倍高 → 往左拱过去 → 头沿弧线匀速落下、卷进 1.68 的拱。
	##   能确定的都守住: 1.15 秒露在墙外那截已有待机 1.2 倍高; 1.60 秒头在左下朝下; 1.68 / 1.88 两张不动(看得见, 手标反推)。
	##   1.18(对折段末项)/ 1.35 / 1.51 三张由离线模拟器搜出来(tools/oneoff/spawn_sim.py 和游戏逐帧对过; design_spawn_opt.py):
	##   两头锚死第 19 / 23 帧; 要匀(1.10 以后一帧最大位移约 15 像素)、先长到待机 1.35 倍(1.25 秒)、头一路往左往下、身子弯得顺(没有折角、梢端不来回弯)。
	##   11-14 用户「中间部分有点不自然，像是硬给它扭的一样」: 量出根部来回摆(朝向 75 → 51 → 65 → 54 → 67°, 下半截最快 170°/秒、根比梢动得还快)
	##   ⇒ 加「根要稳、根部朝向不来回」重搜: 根部 81 → 73 → 67 → 65 → 67° 一路平稳, 下半截最快 70°/秒; 1.01 / 1.10 的根部倾斜与折向一起理顺
	##   11-14 用户「中间把这个头部往上抽的时候太猛了」: 量出 0.97–1.13 秒头 0.17 秒里从 76 升到 238 像素(一帧往上 24 像素)、到顶又停住
	##   ⇒ 1.01 / 1.10 / 1.18 / 1.35 / 1.51 五张一起重搜(tools/oneoff/design_spawn_opt2.py): 头不再一下伸到最顶, 保持卷着跟身子一起升起、往左拱,
	##   0.93–1.5 秒头每帧 12–13 像素匀速走、不停, 再慢慢收进 1.68 的拱; 整根一帧最快 14.5 像素(原 25), 最高待机 1.21 倍
	##   手调两次都不行: 钩在身后那个面里打开 ⇒ 头先指向身后(画面上最高)再回来; 折向改朝左 ⇒ 左边那条腿整段露出来一下甩上去
	[1.35, [74.8, 85.5, 108.7, 208.5, 231.7, 234.9], [0.0, 11.8, 29.5, 47.2, 59.0, 59.0]],   # 设计: 往左拱过去(上半截还偏向身后, 接对折段)
	[1.51, [69.3, 78.0, 115.5, 212.8, 253.8, 273.7], [0.0, 4.7, 11.8, 18.8, 23.5, 23.5]],   # 设计: 拱形, 头在左边往下
	[1.68, [64.7, 76.6, 106.3, 220.5, 278.8, 278.8]],   # 手标反推(我们的镜头) 残差 0.006
	[1.88, [64.0, 63.6, 107.3, 219.8, 274.7, 328.1]],   # 手标反推(我们的镜头); 11-14 根部固定 64 再拟合其余 5 点(原 38.4 ⇒ 根部 65 → 38 → 67 来回摆, 用户「像是硬给它扭的」), 形状差 0.016
]
## 露出比例突然变大(长出途中被叫去出手)时, 每秒最多长这么多
const EXPOSE_RATE := 5.0
## 鳍那一侧(背侧)绕身体转的最快速度(度 / 秒): 姿势表示法换了(拍下后收回)要翻面时, 0.2 秒内拧过去, 不一帧跳
const DORSAL_RATE := 240.0   # 11-13: 900 ⇒ 出手刚开始那一帧截面跳 15°; 240 ⇒ 分 4 帧转过去


## 6 个控制点 → 身长位置 u 的值(Catmull-Rom, 端点外推)
static func _ctrl_interp(c: Array, u: float) -> float:
	var m: int = c.size()
	if u <= float(U6[0]):
		return float(c[0])
	var j: int = m - 2
	for k in range(m - 1):
		if u <= float(U6[k + 1]):
			j = k
			break
	var s: float = (u - float(U6[j])) / (float(U6[j + 1]) - float(U6[j]))
	var p0: float = float(c[maxi(j - 1, 0)])
	var p1: float = float(c[j])
	var p2: float = float(c[j + 1])
	var p3: float = float(c[mini(j + 2, m - 1)])
	return 0.5 * (2.0 * p1 + (p2 - p0) * s + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * s * s + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * s * s * s)


## ── 出土前段 = 对折的发卡(11-13 用户逐张讲解光柱后 0–0.68 秒) ──
## 「它第一张头是埋在地下面的…三分之一的身子露在那儿…其他部分是折着的，在地下」「这不是头啊，这只是半截身体啊，它是折着的」
## 「头是在底的这个后面」「顶上那根细尖是角或者鳞片, 实际的顶会低一点」
## 从底往上一条腿 → 顶上折过去 → 另一条腿往下、落在底的后面; 0.22 秒前头还扎在地里(地下那段不画)。
## 参数由 tools/oneoff/fit_hairpin.py 按我们游戏的镜头从用户手标(第 5、6 张用用户认可的重标)反推, 以往上那条腿长 = 1:
##   lp/lc 往上腿起始仰角与沿腿的弯 · r 折弯半径 · dy 往下腿的水平朝向(0 = 正面, 负 = 往后远离镜头) · dp 往下的角度 · D 往下腿长。
## Hn = 往上腿长(× HP_HMAX 个待机身长): 光柱前 0.1 秒从地里拱出来, 光柱那一刻已经 9 成高, 之后基本不长(手标顶高 77–98 像素)。
const HP_HMAX := 0.35   # 11-13 晚: 0.47 ⇒ 芽太大(0.85 秒顶高 = 待机的 1.0 倍; LoL 中间那根 106 / 待机约 144 = 0.74 倍),
##   1.18 交给后面的关键姿势时整根一下缩 25%(246 → 178 像素)。按 LoL 的比例缩到 0.745 倍 ⇒ 0.85 / 1.01 / 1.18 / 1.35 相对待机的高都和 LoL 一致
## 对折一直播到 1.18 秒(11-13 晚用户「第十六针往后应该是全错吧」): LoL 0.85–1.18 身子越长越高、头一直卷在顶上的折弯里
##   (用户的线: 顶在身长 0.58 → 0.71 → 1.0), 1.18 才伸直成 S。原来 0.86 秒对折一帧切到关键姿势 ⇒ 顶高一帧 96 → 134 像素、头从垂着翻成朝上。
##   0.85 / 1.01 / 1.18 三项由 tools/oneoff/fit_hairpin_roll.py 按我们游戏的镜头从用户手标反推(残差 0.004 / 0.007 / 0.001;
##   往下段长 D 与露出的身长直接按用户的线量, 画面上的长度比例也对齐用户的线 195 → 224 → 238 像素)。(11-13 夜改成播到 1.10 就交给设计的 1.18 那张; HP_T 里 1.18 那项只用来定 1.10 处的切线)
##   0.93 那项是我加的: LoL 0.85–0.95 头一直卷在右边成「P」, 0.98–1.01 才很快翻到左边(逐帧看 72.35 + 0.78…1.28 秒);
##   形状照 0.85, 身长按时间长一半(否则 0.85 → 1.01 匀速过渡, 0.93 秒已经变成平头直柱)。
##   11-13 夜用户「第十六针往后全部标注都是有问题」「它不是一瞬间到直的呀，它肯定就会有个变化过程吧？你自己得想想」:
##   LoL 1.01–1.51 秒触手上半截插进后面的石墙看不见(1.60 秒头才从墙左下钻出来朝下), 用户那几张线的顶部是推的;
##   我们这里没有墙、整根看得见 ⇒ 看不见那段自己设计: 1.01 / 1.10 两项改成「卷着的头匀速打开、折弯往上滚、身子往左后倾」,
##   0.93 → 1.18 用 0.25 秒展开(原来集中在 1.03–1.13 这 0.1 秒, 一下变直)
const HP_END := 1.18
const HP_T := [-0.17, -0.1, 0.0, 0.08, 0.15, 0.22, 0.34, 0.38, 0.48, 0.58, 0.68, 0.85, 0.93, 1.01, 1.1, 1.18]
## 露出身长 = (1 + D) × HP_HMAX × Hn(Hn 按 HP_HMAX = 0.47 时露出 0.837 / 0.92 / 0.98 定的; 之后整体缩 0.745 倍, 比例不变)
const HP_HN := [0.0, 0.55, 0.7, 0.8, 0.93, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.035, 1.164, 1.357, 1.440, 1.474]
const HP_LP := [96.0, 96.0, 96.0, 96.0, 96.5, 97.0, 98.0, 98.0, 99.0, 100.0, 100.0, 90.0, 90.0, 94.77, 94.31, 91.80]
## 0.22 秒前两条腿前后贴紧 ⇒ 从地里拱出来的是一根实心圆头柱子(LoL 实拍: 只看得见一根身子粗, 看不到第二条腿); 0.28 秒头出来后按反推的。
##   11-13 夜用户「第七针、第八针，你确定头在底的后面吗」: 原来折弯宽 0.12 ⇒ 两条腿中心只隔 0.33 米、身子半径合计约 0.5 米 ⇒ 两根管子互相穿插,
##   半透明下看成「张开的管子」; 且 0.15 / 0.21 两项折向已经开始往右转 ⇒ 第 8 帧那条腿甩到右前方。改: 折弯宽 0.20–0.32(刚好贴着不穿插), 0.21 前折向正对身后。
##   (头在不在身后 LoL 这两帧看不到 —— 头在地里; 按 0.28 秒头从往上那条腿的后背冒出来倒推)
##   LoL 0.267 秒还只是一根柱子 + 鳞尖, 0.28 秒头才从右侧探出来(原来 0.25 秒头已经甩出来了)。头不是从地里一下蹦出来:
##   0.15–0.22 秒先在往上那条腿正后方升到半腰(被挡住, 折向一直正对身后), 0.22–0.34 秒慢慢往右后方探出来
##   (11-13 夜试过「0.25 还在地里、0.28 就到半腰」⇒ 两帧走完, 一帧挪 60 像素, 瞬移; 又试 0.25 → 0.28 探出 ⇒ 两帧甩出去、0.30 秒急停,
##    用户「有个抽」; 现在每帧位移 15 → 3 慢慢收住)
## 11-13 晚用户「对折…不能直接扯折成两半吧？你身体是柔软的呀」: 折弯是圆的 —— 半径不小于往上腿的 0.18–0.22(原来 0.05 / 0.15 像折成两半);
##   第 5 张(0.28 秒)头在半腰、抵着往上那条腿的后背(用户原来的线就是对的, 不用我重标的)
const HP_R := [0.32, 0.3, 0.26, 0.22, 0.2, 0.2, 0.24, 0.24, 0.24, 0.24, 0.24, 0.367, 0.367, 0.44, 0.43, 0.33]
const HP_DP := [88.0, 88.0, 88.0, 88.0, 88.0, 88.0, 82.0, 82.0, 82.0, 82.0, 85.0, 66.3, 66.3, 58.89, 20.98, 33.19]
## 折弯往哪边翻过去(水平朝向, 度; 0 = 正面 / 画面右, 270 = 身后): 0.22 秒前原路折回贴在后面; 之后往右后方翻 ⇒ 头在画面右边、贴着往上那条腿的后背
##   (11-13: 原来取两条腿方向的平分线 —— 两条腿几乎反向时平分线不稳, 第 6–8 张头翻到了左边、第 10 张甩出一条腿)
const HP_MY := [270.0, 270.0, 270.0, 270.0, 270.0, 270.0, 300.0, 300.0, 300.0, 300.0, 290.0, 283.9, 283.9, 300.00, 285.88, 269.49]
const HP_D := [1.4, 1.4, 1.4, 1.4, 1.38, 0.7, 0.45, 0.52, 0.6, 0.68, 1.0, 0.72, 0.6, 0.44, 0.40, 0.42]
## 往下那段继续往回卷(梢端再转多少度): 0.85 秒用户的线是「P」—— 往下那段先往右鼓、再卷回到身子旁边; 1.18 伸直了只剩一点
const HP_CU := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 150.0, 150.0, 134.14, 112.99, 40.61]
## 整根在「正面 / 上」竖直面(= 画面平面)里的倾斜: 根部 HP_B0 + 沿往上那段渐变 HP_BL(度, 正 = 往后 / 画面左)。
##   折弯朝身后, 只在折向那个面里弯的话画面上看不出弯(拟合会让身子朝镜头倒来凑高度) ⇒ 画面上的 S 靠这一项
const HP_B0 := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -3.0, -7.0, -9.08, -13.57, -17.04]
const HP_BL := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 30.7, 30.7, 55.84, 57.39, 60.03]


static func _hp_at(arr: Array, tt: float) -> float:
	## 最后一项(HP_END)不停: 在那一刻交给关键姿势、接着动(11-13 夜: 末端切线为 0 ⇒ 1.18 秒减速到停一下又走)
	return _hermite(HP_T, arr, tt, true)


## 按时间的连贯插值(三次 Hermite, 切线 = 前后两个关键点连线的斜率): 经过关键点不减速。
## 11-13 用户「搁那疯狂抽动」: 原来每段各自慢起慢停(smoothstep) ⇒ 每到一个关键姿势速度掉到 0, 出土 2 秒里停走 15 次。
static func _hermite(ts_arr: Array, vals: Array, tt: float, end_moving := false) -> float:
	var n: int = ts_arr.size()
	if tt <= float(ts_arr[0]):
		return float(vals[0])
	if tt >= float(ts_arr[n - 1]):
		return float(vals[n - 1])
	var i := 0
	for k in range(n - 1):
		if tt >= float(ts_arr[k]):
			i = k
	var t0: float = float(ts_arr[i])
	var t1: float = float(ts_arr[i + 1])
	var h: float = t1 - t0
	var x: float = (tt - t0) / h
	var p0: float = float(vals[i])
	var p1: float = float(vals[i + 1])
	var m0: float = 0.0 if i == 0 else (p1 - float(vals[i - 1])) / (t1 - float(ts_arr[i - 1]))
	var m1: float = 0.0 if i + 1 == n - 1 else (float(vals[i + 2]) - p0) / (float(ts_arr[i + 2]) - t0)
	if i + 1 == n - 1 and end_moving:
		m1 = (p1 - p0) / h
	var x2: float = x * x
	var x3: float = x2 * x
	return (2.0 * x3 - 3.0 * x2 + 1.0) * p0 + (x3 - 2.0 * x2 + x) * h * m0 + (-2.0 * x3 + 3.0 * x2) * p1 + (x3 - x2) * h * m1


## 发卡在 tt 时刻: 返回 [每节方向(局部: x 正面 / y 上 / z 侧向朝镜头), 整根长(× 待机身长)]
static func _hairpin(tt: float) -> Array:
	## 11-13 用户「你这挤在一起，你这硬…自然的把这个头放在这个底的背后折过去就行了」:
	##   原来是「两段直腿 + 一小段圆弧」, 还把两条腿压到相碰 ⇒ 像硬纸板对折。
	##   现在整根是一条连续的弧: 往上那段微微往后仰 → 弯曲在顶上一段较长的身子里慢慢完成(像一根软管搭过去) →
	##   往下那段顺着落到底的后面。弯得多快由 HP_R(软硬, 越大越圆)定, 往哪边折由 HP_MY 定(身后偏右)。
	var hn: float = _hp_at(HP_HN, tt)
	var a0: float = _hp_at(HP_LP, tt)
	var w: float = maxf(_hp_at(HP_R, tt), 0.04)
	var myr: float = deg_to_rad(_hp_at(HP_MY, tt))
	var dp: float = _hp_at(HP_DP, tt)
	var dl: float = maxf(_hp_at(HP_D, tt), 0.0)
	var cu: float = _hp_at(HP_CU, tt)
	var b0: float = _hp_at(HP_B0, tt)
	var bl: float = _hp_at(HP_BL, tt)
	var hdir := Vector3(cos(myr), 0.0, sin(myr))
	var up := Vector3.UP
	var total: float = 1.0 + dl
	## 弯曲中心在往上那段的末尾稍前一点(顶是圆的, 不在一个点上折)
	var sc: float = 1.0 - 0.5 * w
	var dirs := PackedVector3Array()
	dirs.resize(SEG)
	for i in range(SEG):
		var sx: float = (float(i) + 0.5) / float(SEG) * total
		var f: float = 0.5 * (1.0 + tanh((sx - sc) / w))
		## 仰角(在「往上 / 往折的那一侧」这个竖直面里): a0(稍往后仰) → −dp(朝折过去那一侧往下), 往下那段再往回卷 cu
		var ang: float = deg_to_rad(lerpf(a0, -dp, f) - cu * maxf(0.0, sx - sc) / maxf(total - sc, 0.001))
		var dv: Vector3 = hdir * cos(ang) + up * sin(ang)
		## 整根在画面平面里倾斜(根部 b0, 沿往上那段渐变到 b0 + bl)
		var bt: float = deg_to_rad(b0 + bl * minf(sx / sc, 1.0))
		dirs[i] = Vector3(dv.x * cos(bt) - dv.y * sin(bt), dv.x * sin(bt) + dv.y * cos(bt), dv.z).normalized()
	return [dirs, total * HP_HMAX * hn]


## 出土 0.85 秒以后: 身长 u 处的方向(局部向量)。两个关键姿势之间按方向插值:
##   某一节在两个姿势里朝前 / 朝后正好相反(例: 0.85「P」→ 1.01「9」, 头那一圈从右边换到左边)时, 绕竖直轴从身后转过去,
##   不在平面里甩一大圈(11-13 实拍: 按角度插值 ⇒ 头往右横甩出去再翻回来, 每节 3700°/秒; LoL 那一下在画面上只是小圈换了边)
static var _gv_cache := {}


## 关键姿势在身长 u 处拆成「仰角 e」与「水平朝向 az」两条随时间的轨道(az: 0 = 正面, ±180 = 朝后; 前后换边时从身后 −90 转过去),
## 再按时间连贯插值(_hermite) ⇒ 经过关键姿势不停顿, 换边也不在平面里甩圈
static func _grow_vec(tg: float, u: float) -> Vector3:
	var key: int = int(round(u * 1000.0))
	if not _gv_cache.has(key):
		## 每个关键时刻的方向(发卡段 + 后面的关键姿势)
		var tsa: Array = []
		var vs: Array = []
		var si: int = clampi(int(u * float(SEG)), 0, SEG - 1)
		for th in HP_T:
			if float(th) > HP_END + 0.001:
				continue
			tsa.append(float(th))
			vs.append((_hairpin(float(th))[0] as PackedVector3Array)[si])
		## 对折播到 HP_END, 在那一刻正好是对折的形状 ⇒ 关键姿势只取它之后的
		for kk in range(GROW_KEYS.size()):
			if float(GROW_KEYS[kk][0]) <= HP_END + 0.001:
				continue
			tsa.append(float(GROW_KEYS[kk][0]))
			## 可选第三项 = 6 个控制点的侧偏(度, 按 _py_vec: 往后仰过竖直的那几节取正 = 偏向身后; 设计的 1.35 / 1.51 用到, 接对折段里朝身后的上半截)
			var gk: Array = GROW_KEYS[kk]
			vs.append(_py_vec(_ctrl_interp(gk[1], u), _ctrl_interp(gk[2], u) if gk.size() > 2 else 0.0))
		## 最后接到待机 A 段 IDLE_JOIN 秒的姿势(1.88 的圈保持住、交给待机时两边同一个姿势)
		tsa.append(IDLE_FROM_BEAM + IDLE_JOIN)
		vs.append(_py_vec(TentacleIdleKeys.angle_at(IDLE_JOIN, u), TentacleIdleKeys.yaw_at(IDLE_JOIN, u)))
		## 拆成仰角 e / 水平朝向 az 两条轨道。同一个方向有两种写法: (e, az) 和 (180 − e, az + 180)。
		## 每一步挑「总转动最小」的写法(朝向转动按 0.3 折算): 只差一点的前后摆就原地摆过去(根部越过竖直);
		##   真的整个换边(头那一圈从左换到右)才绕身后转过去。
		##   11-13: 一律绕身后转 ⇒ 根部那几节也被拉着绕半圈, 截面 / 鳍跟着拧(411°/秒)
		var ea: Array = []
		var aa: Array = []
		for k2 in range(vs.size()):
			var v3: Vector3 = (vs[k2] as Vector3).normalized()
			var e0: float = rad_to_deg(asin(clampf(v3.y, -1.0, 1.0)))
			var az0: float = rad_to_deg(atan2(v3.z, v3.x))
			if k2 == 0:
				ea.append(e0)
				aa.append(az0)
				continue
			var pe: float = float(ea[k2 - 1])
			var pa: float = float(aa[k2 - 1])
			var best_e := e0
			var best_a := az0
			var best_c := 1e9
			for fl in range(2):
				var ec: float = (180.0 - e0) if fl == 1 else e0
				var ac: float = (az0 + 180.0) if fl == 1 else az0
				ec = pe + wrapf(ec - pe, -180.0, 180.0)
				ac = pa + wrapf(ac - pa, -180.0, 180.0)
				var cst: float = absf(ec - pe) + 0.3 * absf(ac - pa)
				if cst < best_c:
					best_c = cst
					best_e = ec
					best_a = ac
			ea.append(best_e)
			aa.append(best_a)
		_gv_cache[key] = [tsa, ea, aa]
	var c: Array = _gv_cache[key]
	var ee: float = deg_to_rad(_hermite(c[0], c[1], tg))
	var az2: float = deg_to_rad(_hermite(c[0], c[2], tg))
	return Vector3(cos(ee) * cos(az2), sin(ee), cos(ee) * sin(az2)).normalized()


## 局部方向 → [俯仰, 侧偏](度), 与 _dir 互逆
static func _vec_py(v: Vector3) -> Vector2:
	var vv: Vector3 = v.normalized()
	return Vector2(rad_to_deg(asin(clampf(vv.y, -1.0, 1.0))), rad_to_deg(atan2(vv.z, vv.x)))


static func _py_vec(p_deg: float, y_deg: float) -> Vector3:
	var p: float = deg_to_rad(p_deg)
	var y: float = deg_to_rad(y_deg)
	return Vector3(cos(y) * cos(p), sin(p), sin(y) * cos(p))


## 待机姿势(每节俯仰角): 根部取离 ref_root 最近的那一圈, 往梢逐节取离上一节最近的 ⇒ 沿身长连续,
## 和设计姿势插值时每一节转的方向一致(不会相邻两节一个往前转、一个往后转打结)。
## (各根不同步靠触手自己的相位 t["phase"] 进 tl; 原来另传一个由相位算的种子, 早已不用, 11-14 删)
static func _idle_chain(tl: float, ref_root: float) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	o.resize(SEG)
	var prev: float = ref_root
	for i in range(SEG):
		var u: float = (float(i) + 0.5) / float(SEG)
		var a: float = TentacleIdleKeys.angle_at(tl, u)
		a = prev + wrapf(a - prev, -180.0, 180.0)
		o[i] = a
		prev = a
	return o


## 整套拍下(甩之前): 身长 u 处、离贴地还有 tt 秒时的 [俯仰, 侧偏]。tt ≥ STRIKE_T[0] 仍是待机。
static func _strike_pose(idle_p: float, idle_y: float, u: float, tt: float) -> Vector2:
	var n: int = STRIKE_T.size()
	if tt >= float(STRIKE_T[0]):
		return Vector2(idle_p, idle_y)
	if tt >= float(STRIKE_T[1]):
		## 待机 → 竖起
		var k: float = smoothstep(0.0, 1.0, (float(STRIKE_T[0]) - tt) / (float(STRIKE_T[0]) - float(STRIKE_T[1])))
		return Vector2(lerpf(idle_p, _ctrl_interp(STRIKE_P[1], u), k), idle_y * (1.0 - k))
	if tt <= float(STRIKE_T[n - 1]):
		return Vector2(_ctrl_interp(STRIKE_P[n - 1], u), 0.0)
	## 关键姿势之间按时间走 Catmull-Rom(过关键姿势不停顿)
	for i in range(1, n - 1):
		var ta: float = float(STRIKE_T[i])
		var tb: float = float(STRIKE_T[i + 1])
		if tt >= tb:
			var x: float = (ta - tt) / (ta - tb)
			var p0: float = _ctrl_interp(STRIKE_P[maxi(i - 1, 1)], u)
			var p1: float = _ctrl_interp(STRIKE_P[i], u)
			var p2: float = _ctrl_interp(STRIKE_P[i + 1], u)
			var p3: float = _ctrl_interp(STRIKE_P[mini(i + 2, n - 1)], u)
			return Vector2(0.5 * (2.0 * p1 + (p2 - p0) * x + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * x * x + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * x * x * x), 0.0)
	return Vector2(_ctrl_interp(STRIKE_P[n - 1], u), 0.0)


## 这一帧每一节的目标: [俯仰(度), 侧偏(度)] 两个数组(长 SEG), 以及弧长倍数(× ARC_LEN)与露出比例。
static func _targets(v, t: Dictionary, stt: int, ts: float) -> Dictionary:
	var pitch := PackedFloat32Array()
	var yaw := PackedFloat32Array()
	pitch.resize(SEG)
	yaw.resize(SEG)
	## 待机 = 按标注量出来的关键姿势(TentacleIdleKeys)。11-13 试过「按统计规律随机生成」(TentacleIdleGen),
	##   用户「不行，比上次按标注走的差多了」⇒ 退回; 规律只用来改进标注版, 不取代标注
	var tl: float = v.battle._t + float(t["phase"]) / TAU * TentacleIdleKeys.period()
	var idle_k: float = TentacleVfx.IDLE_ARC_K
	var len_k: float = idle_k
	var expose := 1.0
	var share: float = float(t.get("share", 1.0))
	var from: Array = t.get("rig_from", P_UP)
	var full: bool = share >= 0.9
	## 整套拍下: 离贴地还有几秒(预警 / 前摇 / 拍下三个状态接成一条时间线)
	var tau := -1.0
	if full:
		match stt:
			TentacleVfx.ST_WARN:
				tau = (TentacleVfx.T_WARN - ts) + TentacleVfx.T_REAR + TentacleVfx.T_TOUCH
			TentacleVfx.ST_REAR:
				tau = (TentacleVfx.T_REAR - ts) + TentacleVfx.T_TOUCH
			TentacleVfx.ST_SLAM:
				tau = TentacleVfx.T_TOUCH - ts
	var idle_c := PackedFloat32Array()
	if stt == TentacleVfx.ST_RECOVER:
		idle_c = _idle_chain(tl, float(P_GROUND[0]))
	elif stt != TentacleVfx.ST_EMERGE:
		idle_c = _idle_chain(tl, 90.0)
	## 根部那一节的姿势(决定鳍朝哪边): 俯仰 / 侧偏 / 表示法(横扫用「仰角 + 水平朝向」= -1)
	var root_p := 90.0
	var root_y := 0.0
	var root_s := 1.0
	## 出土: 发卡 / 关键姿势 / 待机 三者按方向向量混合(侧偏可能隔着 ±180°, 不能按角度插)
	var hp_d := PackedVector3Array()
	var hp_len := 0.0
	var grow_on: bool = stt == TentacleVfx.ST_IDLE and bool(t.get("rig_grow", false))
	var tg: float = ts if grow_on else ts - TentacleVfx.T_EMERGE
	if stt == TentacleVfx.ST_EMERGE or (grow_on and tg < HP_END):
		var hp: Array = _hairpin(minf(tg, HP_END))
		hp_d = hp[0]
		hp_len = float(hp[1])
	for i in range(SEG):
		var u: float = (float(i) + 0.5) / float(SEG)
		var p := 90.0
		var y := 0.0
		var rep := 1.0
		match stt:
			TentacleVfx.ST_EMERGE:
				## 前 1.9 秒身子不露(只有漩涡 / 黑影); 光柱前 0.1 秒发卡从地里拱出来
				var hv: Vector2 = _vec_py(hp_d[i])
				p = hv.x
				y = hv.y
			TentacleVfx.ST_IDLE:
				var uf2: float = 1.0
				var p_from := 90.0
				if grow_on:
					## 0–1.18 对折(头卷在顶上、往上滚开) → 1.18–1.88 关键姿势 → 圈保持到 2.65 = 待机 75.0 秒那个姿势(2.35–2.65 交给待机)
					## 对折段直接用对折的形状(参数随时间连贯变化) —— 11-13 原来按「身长第几节」把方向插值,
					##   对折段总长一直在变, 同一节前后几帧落在不同的腿上 ⇒ 头一会儿钻地一会儿悬空。HP_END 以后接关键姿势:
					##   那一刻关键姿势轨道正好等于对折的形状; 跟随(弹簧)慢的那几分之一秒在交给待机、打开跟随时一起慢慢加上(原来一帧跳 0.09 秒)
					var lead: float = 2.0 * ZETA / (OMEGA0 * (1.0 - OMEGA_TIP_SOFT * u))
					var gv: Vector3 = hp_d[i] if tg < HP_END else _grow_vec(tg + lead * smoothstep(GROW_UNFURL, GROW_T, tg), u)
					var ub: float = smoothstep(GROW_UNFURL, GROW_T, ts)
					var iv: Vector3 = _py_vec(idle_c[i], TentacleIdleKeys.yaw_at(tl, u))
					var gp: Vector2 = _vec_py(gv.lerp(iv, ub).normalized())
					p = gp.x
					y = gp.y
					pitch[i] = p
					yaw[i] = y
					if i == 0:
						root_p = p
						root_y = y
					continue
				elif bool(t.get("rig_rec", false)):
					## 拍下后从贴地抬回待机: 梢端先抬
					uf2 = smoothstep(0.0, REC_LIFT - RECOVER_ROOT_DELAY, ts - RECOVER_ROOT_DELAY * (1.0 - u))
					p_from = _ctrl_interp(P_GROUND, u)
				p = lerpf(p_from, idle_c[i], uf2)
				y = TentacleIdleKeys.yaw_at(tl, u) * uf2
			TentacleVfx.ST_WARN, TentacleVfx.ST_REAR, TentacleVfx.ST_SLAM:
				if full:
					## 梢端慢半拍: 同一时刻梢端看到的 τ 更大(还在上一个阶段)
					var tt: float = tau + MOVE_LAG * u
					var iy: float = TentacleIdleKeys.yaw_at(tl, u)
					if tau > LAND_TAU:
						var sp: Vector2 = _strike_pose(idle_c[i], iy, u, tt)
						p = sp.x
						y = sp.y
					else:
						## 贴地后: 躺平 + 梢端回弹一下
						var ta: float = tau - LAND_TAU
						p = _ctrl_interp(P_GROUND, u) + BOUNCE_DEG * u * u * exp(BOUNCE_DECAY * ta) * sin(-BOUNCE_W * ta)
				elif stt == TentacleVfx.ST_SLAM:
					## 点刺(追击): 从下令那一刻的姿势直接刺下去
					var x2: float = clampf(ts / 0.10, 0.0, 1.0)
					p = lerpf(_ctrl_interp(from, u), _ctrl_interp(P_GROUND, u), pow(x2, SLAM_EASE))
			TentacleVfx.ST_RECOVER:
				p = _ctrl_interp(P_GROUND, u)       # 整个收回态都贴地趴着(手标)
			TentacleVfx.ST_RETRACT:
				p = TentacleIdleKeys.angle_at(tl, u)
				y = TentacleIdleKeys.yaw_at(tl, u)
		pitch[i] = p
		yaw[i] = y
		if i == 0:
			root_p = p
			root_y = y
			root_s = rep
	var fin := 1.0
	match stt:
		TentacleVfx.ST_EMERGE:
			## 光柱前 0.1 秒发卡从地里拱出来(整根长按发卡算; 地下那段不画)
			expose = hp_len if ts > TentacleVfx.T_EMERGE - 0.17 else 0.0
			fin = 0.0
		TentacleVfx.ST_IDLE:
			if grow_on:
				var l70: float = float(_hairpin(HP_END)[1])
				expose = hp_len if tg < HP_END else lerpf(l70, 1.0, smoothstep(HP_END, HP_END + GROW_HAND, tg))
				fin = lerpf(BUD_FIN, 1.0, smoothstep(GROW_HOLD, GROW_UNFURL - 0.1, ts))
			elif bool(t.get("rig_rec", false)):
				len_k = lerpf(1.0, idle_k, smoothstep(0.0, REC_LIFT, ts))
		TentacleVfx.ST_WARN, TentacleVfx.ST_REAR, TentacleVfx.ST_SLAM:
			if full:
				len_k = lerpf(idle_k, 1.0, 1.0 - smoothstep(LEN_T1, LEN_T0, tau))
			elif stt == TentacleVfx.ST_SLAM:
				## 点刺: 身长在刺下去那 0.1 秒里从下令那一刻的长度渐变到全长(和姿势同一条时间线)。
				##   11-13 夜 verify_tentacle_continuity 抓到: 原来直接 1.0 ⇒ 待机(0.6)→ 点刺一帧之内整根从 5.8 米变 9.6 米, 梢端一下跳 2 米多
				len_k = lerpf(float(t.get("rig_len_from", idle_k)), 1.0, pow(clampf(ts / 0.10, 0.0, 1.0), SLAM_EASE))
		TentacleVfx.ST_RECOVER:
			len_k = 1.0
		TentacleVfx.ST_RETRACT:
			expose = 1.0 - clampf(ts / TentacleVfx.T_RETRACT, 0.0, 1.0)
	return {"pitch": pitch, "yaw": yaw, "len_k": len_k, "expose": expose, "fin": fin,
		"root_p": root_p, "root_y": root_y, "root_s": root_s}


static func _dir(fwd: Vector3, lat: Vector3, up: Vector3, p_deg: float, y_deg: float) -> Vector3:
	var p: float = deg_to_rad(p_deg)
	var y: float = deg_to_rad(y_deg)
	return ((fwd * cos(y) + lat * sin(y)) * cos(p) + up * sin(p)).normalized()


## 进预警 / 点刺那一刻: 记下当前看得见的姿势(由弹簧状态反算 6 个控制点的俯仰 / 侧偏), 预警从这里起抬, 不跳。
static func capture_from(t: Dictionary, fwd: Vector3, lat: Vector3, up: Vector3) -> void:
	var d: PackedVector3Array = t.get("rig_d", PackedVector3Array())
	if d.size() != SEG:
		t["rig_from"] = P_UP
		t["rig_from_y"] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		return
	var fp: Array = []
	var fy: Array = []
	var prev := 90.0
	for uu in U6:
		var i: int = clampi(int(float(uu) * float(SEG)) - 1, 0, SEG - 1)
		var v: Vector3 = d[i]
		var h: float = Vector2(v.dot(fwd), v.dot(lat)).length()
		var pa: float = rad_to_deg(atan2(v.dot(up), v.dot(fwd)))
		## 沿身长展开(相邻控制点不绕整圈)
		while pa - prev > 180.0:
			pa -= 360.0
		while prev - pa > 180.0:
			pa += 360.0
		prev = pa
		fp.append(pa)
		fy.append(rad_to_deg(atan2(v.dot(lat), maxf(h, 0.0001))) if absf(v.dot(fwd)) > 0.2 else 0.0)
	t["rig_from"] = fp
	t["rig_from_y"] = fy
	## 下令那一刻的身长系数(点刺从这个长度渐变到全长)
	t["rig_len_from"] = float(t.get("rig_len", TentacleVfx.IDLE_ARC_K))


## 求这一帧的中心线(世界坐标, SEG+1 个点)与背侧方向(每个点一个)。
static func solve(v, t: Dictionary, root3: Vector3, fwd: Vector3, lat: Vector3, up: Vector3, stt: int, ts: float) -> Array:
	## 出土 → 待机那一刻起播「长出」; 离开待机或播完就停
	var prev_st: int = int(t.get("rig_st", -1))
	if stt == TentacleVfx.ST_IDLE and prev_st == TentacleVfx.ST_EMERGE:
		t["rig_grow"] = true
		## 待机从「LoL 中间那根出土后接着的那一刻」开始播: 出土的关键姿势和待机 A 段量的是同一根触手(72.35 s 光柱 → 74.0 s 待机 A 段开头),
		##   光柱后 ts 秒对应待机 A 段的 ts − 1.65 秒 ⇒ 出土收尾交给待机时两边是同一个姿势, 不会甩一下(11-13 实测原来交接处每帧挪 1.5 米)
		t["phase"] = TAU * fposmod(-IDLE_FROM_BEAM - float(v.battle._t), TentacleIdleKeys.period()) / TentacleIdleKeys.period()
	if stt != TentacleVfx.ST_IDLE or ts > GROW_T:
		t["rig_grow"] = false
	## 收回态 → 待机那一刻起播「从贴地抬回」
	if stt == TentacleVfx.ST_IDLE and prev_st == TentacleVfx.ST_RECOVER:
		t["rig_rec"] = true
	if stt != TentacleVfx.ST_IDLE or ts > REC_LIFT:
		t["rig_rec"] = false
	t["rig_st"] = stt
	var tg: Dictionary = _targets(v, t, stt, ts)
	t["rig_fin"] = float(tg["fin"])
	t["rig_len"] = float(tg["len_k"])
	var pitch: PackedFloat32Array = tg["pitch"]
	var yaw: PackedFloat32Array = tg["yaw"]
	var target := PackedVector3Array()
	target.resize(SEG)
	for i in range(SEG):
		target[i] = _dir(fwd, lat, up, pitch[i], yaw[i])
	var d: PackedVector3Array = t.get("rig_d", PackedVector3Array())
	var vel: PackedVector3Array = t.get("rig_v", PackedVector3Array())
	var dt: float = float(t.get("dt", 0.0))
	t["dt"] = 0.0
	if d.size() != SEG:
		d = target.duplicate()
		vel = PackedVector3Array()
		vel.resize(SEG)
	## 拍下(整套): 弹簧照跑, 再按 m 往设计动作上收 —— 甩之前收满(m = 1), 甩 / 贴地 / 回弹完全照设计 ⇒ 梢端贴地 = T_TOUCH
	var m := 0.0
	## 出土: 刚从地里拱出来那一下(光柱前后)直接按姿势走, 之后打开跟随(弹簧) —— 11-13 原来出土全程直接按姿势硬摆, 没有一点惯性和跟随
	if stt == TentacleVfx.ST_EMERGE:
		m = 1.0
	## 出土全程(对折 + 关键姿势, 到 GROW_UNFURL)直接按姿势走, 交给待机时(GROW_UNFURL → GROW_T)才慢慢打开跟随:
	##   弹簧的跟随会慢 0.1–0.2 秒(梢端软) ⇒ 头该在半腰时还在地下(11-13 实测); 1.51 → 1.68 秒梢端 0.17 秒转 90°,
	##   跟随根本跟不上, 提前量按 1.51 对 1.68 就错、按 1.68 对 1.51 就错(11-13 夜实测和用户的线差 0.10)。关键姿势之间本来就是连贯插值
	elif stt == TentacleVfx.ST_IDLE and bool(t.get("rig_grow", false)):
		m = 1.0 - smoothstep(GROW_UNFURL, GROW_T, ts)
	if stt == TentacleVfx.ST_SLAM and float(t.get("share", 1.0)) >= 0.9:
		m = smoothstep(0.0, TentacleVfx.T_TOUCH - DIRECT_TAU, ts)
	var d0: PackedVector3Array = d.duplicate()
	var steps: int = clampi(int(ceil(dt / SUB_H)), 0, 12)
	var h: float = dt / float(steps) if steps > 0 else 0.0
	for _s in range(steps):
		for i in range(SEG):
			var u: float = (float(i) + 0.5) / float(SEG)
			var w: float = OMEGA0 * (1.0 - OMEGA_TIP_SOFT * u)
			var a: Vector3 = (target[i] - d[i]) * (w * w) - vel[i] * (2.0 * ZETA * w)
			vel[i] += a * h
			d[i] = (d[i] + vel[i] * h).normalized()
	if m > 0.0:
		for i in range(SEG):
			d[i] = d[i].lerp(target[i], m).normalized()
			## 速度按这一帧实际的变化记下, 收回时弹簧接得上
			if dt > 0.0:
				vel[i] = (d[i] - d0[i]) / dt
	t["rig_d"] = d
	t["rig_v"] = vel
	## 露出比例: 往小随时跟上; 往大最多每秒 EXPOSE_RATE(长出途中被叫去出手不会一帧长满)
	var ex_t: float = float(tg["expose"])
	var ex: float = float(t.get("rig_exp", ex_t))
	ex = ex_t if ex_t <= ex else minf(ex_t, ex + EXPOSE_RATE * maxf(dt, 0.0))
	if bool(t.get("rig_grow", false)) or stt == TentacleVfx.ST_EMERGE:
		ex = ex_t
	t["rig_exp"] = ex
	var ds: float = TentacleVfx.ARC_LEN * float(tg["len_k"]) * ex / float(SEG)
	var pts := PackedVector3Array()
	pts.resize(SEG + 1)
	pts[0] = root3
	for i in range(SEG):
		pts[i + 1] = pts[i] + d[i] * ds
	## 背侧(鳍那一侧): 根部 = 根部那一节「竖着时朝前、往后躺倒时朝上、横扫时一直朝上」(录屏逐帧: 往后仰的 C 鳍在内侧、
	##   躺在身后鳍朝上); 换表示法要翻面时按 DORSAL_RATE 拧过去。再沿身体逐节平行传递。
	## 11-13 用户「搁这疯狂抽动」: 原来由根部那一节的(俯仰, 侧偏)算 —— 根部一越过竖直, 侧偏就从 0 跳到 180,
	##   算出来的背侧整个反过来 180°, 再按 DORSAL_RATE 拧过去 ⇒ 出土 0.68–1.08 秒截面和鳍绕身子拧, 最快 939°/秒。
	##   改成直接由根部那一节的方向算(方向 × 侧向): 竖着 ⇒ 朝前, 往后躺 ⇒ 朝上, 和原来一样, 但方向连续变它就连续变, 不会突然反过来。
	var tan0: Vector3 = d[0]
	var dn_t: Vector3 = tan0.cross(lat)
	dn_t = dn_t - tan0 * dn_t.dot(tan0)
	dn_t = dn_t.normalized() if dn_t.length() > 0.001 else fwd
	var dn: Vector3 = t.get("rig_dn", dn_t)
	dn = dn - tan0 * dn.dot(tan0)
	if dn.length() < 0.001 or dt <= 0.0:
		dn = dn_t
	else:
		dn = dn.normalized()
		var ang: float = atan2(tan0.dot(dn.cross(dn_t)), dn.dot(dn_t))
		var stp: float = clampf(ang, -deg_to_rad(DORSAL_RATE) * dt, deg_to_rad(DORSAL_RATE) * dt)
		dn = (dn * cos(stp) + tan0.cross(dn) * sin(stp)).normalized()
	t["rig_dn"] = dn
	var dors := PackedVector3Array()
	dors.resize(SEG + 1)
	var b: Vector3 = dn
	for i in range(SEG + 1):
		var tan: Vector3 = d[mini(i, SEG - 1)]
		b = b - tan * b.dot(tan)
		if b.length() < 0.001:
			b = lat.cross(tan)
		b = b.normalized()
		dors[i] = b
	return [pts, dors]
