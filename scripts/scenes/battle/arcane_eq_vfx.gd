class_name ArcaneEqVfx
extends RefCounted
## arcane_eq_vfx.gd — 法器三件新装备的演出层
## 088 涨潮碑 · 089 蚀月符纸 · 090 镇海杵
##
## 效果本体在 `scripts/systems/equip/eq_arcane_batch.gd`(EqArcaneBatch), 由它 `new` 出本类。
## 契约 = `docs/plans/20260806-实装契约-批④.md` §7。
##
## ══════════════════════════════════════════════════════════════════════
##  ★三条自我约束(逐条对应踩过的坑)
## ══════════════════════════════════════════════════════════════════════
## ① **零素材**: 全部是程序化 `ArrayMesh`/`SurfaceTool` + Godot 内置图元, 不新建资源、
##    也**没有借用任何别件装备的立绘**(用户铁律「不复用素材除非点名」——程序化几何不产图,
##    不吃这条约束)。
## ② **不用 tween**: 无头 CI 下 `create_tween()` 推进不稳(CLAUDE.md §3.5,
##    `verify_pirate_hook` 为此连红三次), 且走 sim 的 delta 才跟时停/换路同步。
##    全部生命周期由本文件的 `tick(delta)` 推进 —— 门禁可以同步喂任意 delta。
## ③ **形态由闭式解给, 不手调系数**(memory [[fb-match-reference-by-measured-curve]]):
##    三条曲线各有物理模型, 全部抽成 `static func` 供门禁直接验, 不必建节点、不必等演出。
##
## ⚠ 朝向坑(memory [[fb-axis-y-plus-rotation-cancels]]): 本文件**不用 Sprite3D**,
##   直接建世界坐标顶点 —— 没有 `axis = AXIS_Y` 与 `rotation.x = -90` 互相抵消那层歧义。
##   贴地几何一律是 y = GROUND_Y 的水平顶点。
##
## ⚠ 材质一律走 `material_override`, 不用 `set_surface_override_material` ——
##   后者在 `--headless` dummy renderer 下每设一次刷一条 `Parameter "material" is null.`。


# ══════════════════════════════════════════════════════════════════
#  §物理常数 —— 每条都对应一个模型, 不是手调出来的
# ══════════════════════════════════════════════════════════════════

## ① 088 碑体上涌: 临界阻尼(ζ=1)阶跃响应 x̂(t) = 1 − (1+ωt)·e^(−ωt)。
##    性质: x̂(0)=0 · 单调增 · **恒 < 1(永不过冲)** —— 碑是"顶上来"不是"弹出来"。
##    ω 用「上涌到 98% 所需时间」定标: (1+ωt)e^(−ωt)=0.02 ⇒ ωt≈5.83。
const RISE_WT98 := 5.834681
## 碑从冒头到站定用的秒数
const RISE_SEC := 0.55
## 碑体尺寸(码): 宽 / 厚 / 高
const STELE_W_PX := 26.0
const STELE_D_PX := 14.0
const STELE_H_PX := 78.0

## ② 潮涌环(每秒一跳的那一圈): **匀速**外扩 —— 浅水重力波在固定水深下相速恒定,
##    所以 r(t) = R·(t/T) 是线性的, 不是爆轰那种减速的。
const PULSE_SEC := 0.55

## ③ 090 猛砸: **Sedov–Taylor 点爆轰** r ∝ t^(2/5) —— 强激波在均匀介质里的自相似解。
##    与潮涌环的线性外扩形成对比(一个是波、一个是爆), 肉眼分得出来。
const SEDOV_EXP := 0.4
## ★2026-08-08 0.85 → 0.55: 余波拖太久, 砸完半天不散(用户:「节奏也有问题」)
const SLAM_SEC := 0.55
## 硬前沿: 更快冲到边(比余波短) + 前 55% 满亮
const SLAM_EDGE_SEC := 0.34
const SLAM_EDGE_HOLD := 0.55

## ④ 089 符纸悬浮: 简谐上下 + 【面内】小幅摇摆。周期 1.6 秒, 幅度 4 码。
const BOB_OMEGA := 3.926990816987241
const BOB_AMP_PX := 4.0
## ★2026-08-07 拆掉的雷 ——【周期性整张消失】
##   旧实现: 符纸是一块 16×22×0.6 码的 BoxMesh, 绕 Y 轴**匀速自转** 1.35 rad/s。
##   薄片转过 π/1.35 = **2.33 秒就正好侧对镜头**, 那一刻投影宽度从 16 码掉到 0.6 码 ⇒ 整张消失。
##   干净台 22 倍实拍逐帧坐实(改前图 `_vfxlab_bf089_0/_2.png`: 一张是白方块、另一张只剩一根竖线)。
##   现在改成**恒定正对镜头 + 面内摇摆**(见 `face_basis` / `talisman_roll`):
##   投影面积恒定 ⇒ "转到侧面"这件事在**结构上**不可能再发生, 不是靠调参数躲开。
const TALISMAN_ROLL_MAX := 0.22
## 面内摇摆角频率: TAU/3 ⇒ 3 秒一个来回(有生气, 又慢到不抢眼)
const TALISMAN_ROLL_OMEGA := 2.0943951023931953
## 符纸尺寸(码)与悬停高度(米)
## ★2026-08-07 放大 ——【实战下只有 10.8×9.3 屏幕像素】
##   实战默认视角(1280×720·相机 (0,28,22) look_at (0,0.6,0)·fov 40)的标尺:
##     · 与视轴垂直的方向  28.148 px/米 = **0.6755 px/码**
##     · **世界竖直**方向还要乘 22/35.139 = 0.6261 ⇒ 只有 **0.4229 px/码**
##   旧版符纸是【世界竖直】的片 ⇒ 16 码宽 → 10.8 px、22 码高 → 9.3 px, 低于头顶徽章的 16 px。
##   改成正对镜头后两个方向都吃满 0.6755, 再把尺寸提到 30×44 码 ⇒ **20.3 × 29.7 屏幕像素**。
const TALISMAN_W_PX := 30.0
const TALISMAN_H_PX := 44.0
## 悬停高度(米)。★1.05 → 1.62: 放大到 30×44 码之后, 1.05 米正好把符纸压在目标龟的
##   脸和身体上(实拍 `_vfxlab_af089_0.png` 一看就知道) —— 治好了"看不见"却挡住了被贴的人。
##   抬到 1.62 让它浮在龟壳上沿, 既完整可见又不遮挡。
const TALISMAN_Y := 1.62
## 同一目标上叠了 N 张符纸时, 相邻两张的**横向错位**(场地像素)与**额外倾角**(弧度)。
## ★2026-08-09: 规格写的是"符纸可叠加", 但每张都画在同一点上 ⇒ 叠 3 张和叠 1 张
##   画面上一模一样, "可叠加"这条在演出层等于没做。实拍确认: 法器羁绊 3 档时
##   法力自回, 台上其实贴了好几张, 完全看不出来。
const TALISMAN_FAN_PX := 11.0
const TALISMAN_FAN_ROLL := 0.13
## 符纸程序化纹理的分辨率(与 30:44 同比 —— 不同比会把月牙拉扁)
const TALISMAN_TEX_W := 64
const TALISMAN_TEX_H := 94
## 月牙的几何(纹理像素): 外圆 / 被减掉的圆。两圆之差 = 月牙。
const MOON_C := Vector2(32.0, 30.0)
const MOON_R := 17.0
const MOON_CUT_C := Vector2(39.0, 28.0)
const MOON_CUT_R := 14.0
## 符纸的四种语义色(程序化纹理里只出现这四种 + 内框线, 门禁数色阶)
const TX_PAPER := Color(0.20, 0.10, 0.34, 0.82)   # 纸面(半透深紫)
const TX_EDGE := Color(0.80, 0.58, 1.00, 1.00)    # 外边框
const TX_INNER := Color(0.36, 0.20, 0.56, 0.94)   # 内框细线
const TX_MOON := Color(0.96, 0.92, 1.00, 1.00)    # 月牙
const TX_RUNE := Color(0.86, 0.66, 1.00, 1.00)    # 符文笔画

## ⑤ 090 浪潮每一跳的抛物线拱高 = 跨度的这个比例(4·h·s(1−s) 的 h)
const ARC_PEAK_FRAC := 0.18
## 浪潮折线的带宽(码)与存活秒数
## ★★2026-08-08 实拍(_vfxlab_p2eq_090_4.png): 18 码粗的方块串在 ADD 下**爆成一串白球** ——
## 而规格原文是「发射一片浪潮**如同闪电一样**」。球串既读不出"浪潮"也读不出"闪电"。
## ⇒ 收细到 5 码 + 分段 12→20 + 逐点横向抖动(见 WAVE_JITTER) ⇒ 一道有折角的电弧。
## ── 一簇水(用户 2026-08-08 纠正: 浪潮是水不是闪电)
## 水的两个色: 亮面与深处。★MIX 混合 ⇒ 颜色是它自己的, 不会被加成白
const COL_WATER := Color(0.60, 0.90, 1.00, 0.95)
const COL_WATER_DEEP := Color(0.20, 0.55, 0.82, 0.95)
## ── 水流带(用户 2026-08-08:「浪潮你自己想想到底怎么实现水流感」)
## ★★一簇离散水滴做不出"水流" —— 那是一袋颗粒在飞。水之所以读成水, 靠的是:
##   ① **连续形体**(带, 不是点)  ② **逐段滞后**(身体跟着头走但慢半拍, 过弯自然甩出弧线)
##   ③ **弧长大致恒定**(不能像弹簧忽长忽短)  ④ **头粗尾细**  ⑤ **行波**(高光沿身体往后跑)
##   这正是用户定触手水准时说的「形态要有物理模型(弧长恒定/曲率密度/行波/逐段滞后)」
##   —— memory [[fb-3d-quality-bar-tentacle]]。
const FLOW_SEGS := 14             ## 水流带分几节
const FLOW_REST_PX := 11.0        ## 相邻两节的静止间距(码) —— 弧长恒定就靠它
const FLOW_LAG := 0.34            ## 逐段滞后系数(每帧向前一节靠拢多少)
## ★2026-08-09 30→13: 30 码**半宽**意味着整条 60 码宽 —— 比龟还宽, 实拍是一片平板楔子,
##   没有"一簇水"的感觉。收到 13(整条 26 码 ≈ 半只龟宽)才像一股水。
const FLOW_HEAD_PX := 13.0        ## 头部半宽(码)
const FLOW_TAIL_PX := 2.0         ## 尾部半宽(码)
const FLOW_WAVE_SPD := 2.6        ## 行波沿身体往后跑的速度(节/秒)
const WATER_DROPS := 11           ## (溅水用)一簇里几颗水滴
const WATER_DROP_PX := 10.0       ## 单颗水滴的边长(码)
const WATER_SPREAD_PX := 20.0     ## 簇内水滴的横向散布(码)
const WATER_SPREAD_M := 0.22      ## 簇内水滴的高度散布(米)
const WATER_TAIL_SEC := 0.30      ## 最后一跳之后再留多久
const WATER_SPLASH_PX := 54.0     ## 落点溅起的环直径(码)
const WATER_SPLASH_SEC := 0.34
const WATER_SPLASH_DROPS := 6     ## 落点弹出几颗水滴
## ── 猛砸落地(水炸开)
const SLAM_BURST_DROPS := 46      ## 炸开多少颗水滴
const SLAM_BURST_PX := 420.0      ## 水滴最远抛到多少码(不是 1000 —— 那是伤害范围, 水泼不了那么远)
const SLAM_BURST_UP := 3.4        ## 抛射初速(高度项)
const SLAM_BURST_SEC := 0.75
const SLAM_BURST_LAG := 0.06      ## 逐颗错开起飞(整齐划一像喷泉, 错开才像炸开)
const SLAM_SPLASH_PX := 260.0     ## 落点贴地水花的直径(码)
const SLAM_SHAKE := 0.055         ## 震屏幅度 —— 7 米砸下来得有分量
const WAVE_W_PX := 5.0
## 浪潮折线的逐点横向抖动(码)。★走 `_juice_rng`(纯演出) 不走 `_battle_rng` ——
## 它不影响任何伤害判定, 用对局 rng 会白白动确定性(rng_discipline 盯着这条)。
const WAVE_JITTER := 14.0
const WAVE_SEC := 0.42
## 符纸转移那道光带的存活秒数
const TRANSFER_SEC := 0.30
## 起跳光柱的存活秒数(由调用方传入起跳时长时以它为准)
const PILLAR_H_M := 3.6

## ⑥ 088 的【区域边界】(2026-08-07): 原来碑的那一圈与潮涌环用的是同一张软环网格 ——
##    内沿渐隐、外沿也只是 0.30 alpha 的软边, 于是"圈内 / 圈外"根本读不出来,
##    而 088 的攻速增益**只在圈内**, 边界就是这件的全部信息。
##    改法三条(都在 `_build_boundary_ring` 里, **不动潮涌/猛砸共用的 `_build_ring`**):
##      · 外沿做成**硬边**(BOUNDARY_RIM 那一窄圈 alpha 拉满) —— 一眼看得出线在哪
##      · 圈内铺一层**极淡的底色**(BOUNDARY_FILL) —— "里面"与"外面"不是同一块地
##      · 沿圈每 15° 一根**向内的刻度**(BOUNDARY_TICKS) —— 读作"这是一条界线"而不是"一圈光"
const BOUNDARY_RIM := 0.955          # 硬边从这个归一半径起到 1.0
const BOUNDARY_FILL := 0.085         # 圈内底色 alpha
const BOUNDARY_TICKS := 24           # 刻度根数(每 15°)
const BOUNDARY_TICK_IN := 0.86       # 刻度从这个归一半径伸到硬边

## ⑦ 090 起跳的三件读数(2026-08-07): 原来只有一根**不动的白光柱**, 起跳/滞空/砸落
##    在画面上完全一样 —— 节奏读不出来。现在:
##      · **水柱**高度 ≡ 携带者的真实滞空高度 `u["height"]`(不是自己另跑一条曲线)
##      · **地面影子**随高度收缩 —— 这是"它在多高"的经典读数
##      · **落点预告环**从 1.18× 收到 1.0×, 收满的那一刻就是砸落 ⇒ 读得出"要砸了"
const LEAP_SHADOW_PX := 96.0         # 贴地影子在【地面】时的直径(码)
const LEAP_SHADOW_MIN := 0.45        # 升到顶点时影子缩到这个比例
## ★收势环(wind-up)的终了半径(码)与起手倍数。
##   ⚠ **诚实记录**: 它不是"1000 码 AOE 的预告圈" —— 1000 码半径 = 2000 码直径,
##   在 1280 px 的屏幕上根本装不下(实拍确认整圈在画面外)。所以这里画的是
##   **收势**(起跳时张开、砸落瞬间收到最小), 表达的是"什么时候砸"而不是"砸多大";
##   "砸多大"由砸落那一圈 Sedov 激波(半径 = 真实的 SLAM_R_PX)自己说。
const LEAP_WINDUP_PX := 110.0
const LEAP_TELE_R0 := 2.6            # 收势环起手是终了半径的这个倍数
## ★下面两个是**结算侧数值的镜像**, 门禁焊死它们与 `EqArcaneBatch` 逐个相等:
##   `SLAM_R_PX ≡ EqArcaneBatch.PESTLE_RADIUS` · `LEAP_APEX_M ≡ EqArcaneBatch.PESTLE_APEX_M`。
##   为什么要镜像而不是直接引用: 本文件与 `EqArcaneBatch` 的引用是**单向**的
##   (见文件头 —— 效果本体引演出层的 COL_*), 反向再引一次 const 会形成循环依赖、Godot 解析期就炸。
##   ⇒ 拿"门禁焊死"换"不循环依赖", 与 `BladeEqVfx.WAVE_SPD` 是同一条老路。
## ★★半径 = **伤害判定的那一个常量**, 不另写一份(2026-08-13)。
##   用户问「伤害半径是500吗, 特效是1000吧」—— 查下来两边都是 500(碰巧相等), 但
##   **没有任何东西保证它们不漂**: 改了伤害忘了改演出, 预警区就会骗人, 而且不报错。
##   触手那边早有这条纪律(`WARN_HALF_W` 必须等于攻击长度), 定海针一直没有。
##   ⚠ 500 是**半径**; 横跨是直径 1000 —— "1000" 那个数是这么来的(它也曾是旧半径,
##     2026-08-09 用户拍板 1000→500, 因为拉不进一屏就"读不成一个圈")。
const SLAM_R_PX := EqArcaneBatch.PESTLE_RADIUS
## ★2026-08-08 用户「这个起跳不够高, 不够物理, 哪有这么快的跳」⇒ 与结算侧同步抬高。
const LEAP_APEX_M := 7.0
## ── 雷电预警圈(用户 2026-08-08:「我要做一个那种雷电圈预警的圈圈, 就是实际范围的」)
## ★★**不是一张贴图**。用户原话「不要拿图片敷衍我」—— 一张静态贴图铺地上是拿素材替代演出。
##   这里是**活的**: 圆周上的电弧每 WARN_REFRESH 秒整批重生, 各自带分形折角与分叉;
##   圈内还有游走的雷雾。做法沿用 078 电鳗那套(分形折线 + 双层 + 分叉), 已经验证过。
const WARN_ARCS := 22           ## 圆周上同时有几段电弧
const WARN_REFRESH := 0.07      ## 多久整批重生一次(秒) —— 这就是"噼啪"的节奏
const WARN_DEPTH := 3           ## 每段电弧的分形层数
const WARN_ROUGH := 0.30        ## 分形粗糙度(相对弦长)
const WARN_W_PX := 7.0          ## 电弧粗细(码)
const WARN_CORE_W_PX := 2.6     ## 白热芯粗细(码)
## ★★2026-08-09 雷雾改成【真粒子】(用户:「雷雾别拿个程序化的线条糊弄我啊, 3d 该有的粒子…」)。
##   旧实现 = WARN_MIST 条随机短线段躺在地上 —— 那是"线条", 不是雾。
##   现在 = GPUParticles3D, 发射体 = 整个圆盘(EMISSION_SHAPE_RING 内径 0), 开湍流,
##   每颗独立初速/旋转/尺寸曲线/颜色渐变 ⇒ 有体积、会翻涌、覆盖到边。
## ⚠ GPU 粒子在无头 CI 下不推进 ⇒ 门禁只能量【配置】(发射半径/数量/颜色/材质在位),
##   量不了"粒子真实位置"。判据落在能同步读到的东西上(同 CLAUDE.md §3.5 的原则)。
## ★覆盖率是这么算的: 圆盘面积 π·1000² ≈ 3.14M 码²。220 颗 × 26 码见方 = 0.15M ⇒ **只盖 5%**,
##   实拍就是"一地散点"而不是雾。改成 320 颗 × 90 码 = 2.6M ⇒ 约 **80%** 覆盖, 配低透明度才成雾。
##   (提覆盖率优先靠**放大单颗**而不是堆数量 —— 数量翻十倍会掉帧, 单颗放大不会。)
const MIST_PARTICLES := 320     ## 圆盘里同时存在多少颗雾
const MIST_LIFE := 1.15         ## 单颗寿命(秒)
const MIST_SZ_PX := 90.0        ## 单颗雾的边长(码)
const MIST_RISE := 0.9          ## 向上初速(米/秒) —— 慢慢往上翻
const MIST_TURB := 0.55         ## 湍流强度
const WARN_MIST := 14           ## (旧)圈内雷雾的条数 —— 已被粒子取代, 保留仅为历史对照
const WARN_MIST_LEN := 46.0     ## 单条雷雾的长度(码)
const WARN_MIST_A := 0.42       ## 雷雾透明度 —— 淡, 别盖住场上的单位
## 阵营色: 己方蓝 / 敌方红(与血条描边 `info_panel` 的 #3fa9ff / #ff5a5a 同源)
const WARN_Y := 0.06            ## 预警圈离地高度(米)
const WARN_ALLY := Color(0.247, 0.663, 1.0)
const WARN_FOE := Color(1.0, 0.353, 0.353)

## 贴地几何的离地高度(米) —— 高于地板顶面才不会被吞
const GROUND_Y := 0.06
## 环的经向分段
const RING_LON := 48
## 浪潮拱线的分段数
const ARC_SEG := 20

## 四件演出的语义色。★**颜色的单一事实源在演出层**(本文件), 效果本体
## `EqArcaneBatch` 反过来引用 `ArcaneEqVfx.COL_*` 当伤害飘字色 —— 引用是**单向**的,
## 免得两个 class_name 互相引用形成循环依赖(Godot 解析 const 时会炸)。
const COL_TIDE := Color("#5fd8ff")     # 088 潮汐(青)
const COL_STELE_BODY := Color(0.30, 0.52, 0.62, 0.96)   # 碑身: 湿石青(MIX, 不发亮)
const COL_STELE_BASE := Color(0.16, 0.28, 0.34, 0.96)   # 底座: 更暗一档
const STELE_BASE_K := 1.55                              # 底座相对碑身宽多少倍
const COL_STELE_RUNE := Color(0.62, 0.94, 1.0, 1.0)     # 顶端符带: 亮潮汐青(MIX, 提亮不靠加法)
const COL_MOON := Color("#b98cff")     # 089 蚀月(紫)
const COL_SLAM := Color("#7ec8ff")     # 090 猛砸(蓝白)
const COL_WAVE := Color("#8ff0ff")     # 090 浪潮(浅青)

## 节点身份标记(程序生成的网格 `resource_path` 是空串, 按路径数会全数成 0)
const META_KEY := "arcane_eq_vfx"
## `_owned` 上限, 同 SynergyVfx.OWNED_CAP 的口径(最后一道闸)
const OWNED_CAP := 256

var battle

## 本层建出来、还活着的节点(撤场用)。★存节点不存单位字典 —— CLAUDE.md §3.2。
var _owned: Array = []
## 正在播的特效 [{node, t, life, kind, …}] —— 每帧由 `tick()` 推进, **不用 tween**。
var _fx: Array = []
## 单位半径的贴地环网格(整局建一次; 材质**不能**共享, 会串色)
var _mesh_ring: ArrayMesh = null
## 088 的区域边界环(硬边 + 圈内底色 + 刻度) —— 与上面那张软环**分开**, 见 `_build_boundary_ring`
var _mesh_boundary: ArrayMesh = null
## 089 符纸的程序化纹理(整局画一次)。★存实例上不存 static —— static 的话进程退出时
##   Godot 会刷 `N resources still in use at exit`(relic_eq_vfx.gd:137 记的同款坑)。
var _tex_talisman: ImageTexture = null


func _init(b) -> void:
	battle = b


func _has_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调, 不建节点、不等演出(契约 §7: 全部同步判定)
# ══════════════════════════════════════════════════════════════════

## 碑体上涌的归一高度 x̂(t/T)。ζ=1 临界阻尼阶跃响应的解析解。
## ★性质(门禁逐条验): x̂(0)=0 · 严格单调增 · **恒 < 1** · x̂(T)≈0.98。
static func rise_frac(t: float, sec: float) -> float:
	if t <= 0.0 or sec <= 0.0:
		return 0.0
	var w: float = RISE_WT98 * (t / sec)
	return 1.0 - (1.0 + w) * exp(-w)


## 潮涌环半径: **匀速**外扩(浅水波相速恒定) r(t) = R·t/T。
static func pulse_radius(t: float, sec: float, r_max: float) -> float:
	if sec <= 0.0:
		return r_max
	return r_max * clampf(t / sec, 0.0, 1.0)


## 猛砸激波半径: Sedov–Taylor 自相似解 r(t) = R·(t/T)^(2/5)。
## ★与 `pulse_radius` 的**线性**形成对比: 同样走到一半时间, 爆轰已经跑了 R·0.5^0.4 = 0.758R,
##   而潮涌环才 0.5R —— 前段快后段慢, 这是"爆"该有的样子。
static func blast_radius(t: float, sec: float, r_max: float) -> float:
	if sec <= 0.0:
		return r_max
	return r_max * pow(clampf(t / sec, 0.0, 1.0), SEDOV_EXP)


## 符纸悬浮的竖直偏移(码)。简谐: A·sin(ωt)。
static func bob_offset(t: float) -> float:
	return BOB_AMP_PX * sin(BOB_OMEGA * t)


## 符纸的【面内】摇摆角(弧度)。有界简谐 —— 幅度恒 ≤ TALISMAN_ROLL_MAX。
## ★这是"自转"的替代品: 旧的匀速自转会走遍 [0, 2π) 从而必然经过侧对镜头的相位;
##   有界摇摆连"侧对"那个角度都到不了, 而且它是**绕视轴**转的, 根本不改变投影面积。
static func talisman_roll(t: float) -> float:
	return TALISMAN_ROLL_MAX * sin(TALISMAN_ROLL_OMEGA * t)


## 让一块【局部平面在 XY、法线 +Z】的片正对镜头, 并绕视轴滚 `roll` 弧度。
##
## ★可验证性质(门禁逐条验, 与 roll 无关):
##     返回 basis 的 **+Z 轴 ≡ −cam_fwd**  ⇒ 片永远正对镜头, 投影面积恒定
##     三根轴两两正交且长度 ≡ 1            ⇒ 不会顺手把片拉伸/镜像
##   任何"绕世界 Y 轴转"的实现都过不了第一条 —— 这正是旧版消失的根因。
static func face_basis(cam_fwd: Vector3, roll: float) -> Basis:
	var n: Vector3 = -cam_fwd.normalized()
	var ref: Vector3 = Vector3.UP
	if absf(n.dot(ref)) > 0.999:
		ref = Vector3.FORWARD
	var right: Vector3 = ref.cross(n).normalized()
	var up: Vector3 = n.cross(right).normalized()
	var c: float = cos(roll)
	var s: float = sin(roll)
	return Basis(right * c + up * s, up * c - right * s, n)


## 镜头前向(单位向量)。
## ★拿不到相机时退回**默认战斗机位的视轴**(0,28,22) → (0,0.6,0) —— 本项目相机方向恒定
##   (缩放只改 fov、平移只挪机位, 见 `RB._cam_zoom_base` 的算法), 所以这个退路是真值不是凑数。
## ★静态版: 别的演出文件(如 084 的十字斩)也要"正对镜头 + 面内 roll", 走同一份实现,
##   免得手抄一份从此各自漂(memory [[fb-hand-rolled-copies-drift]])。
static func cam_forward_of(b) -> Vector3:
	if b != null and is_instance_valid(b._cam):
		return -((b._cam as Camera3D).global_transform.basis.z).normalized()
	return Vector3(0.0, -27.4, -22.0).normalized()


func _cam_forward() -> Vector3:
	return cam_forward_of(battle)


# ══════════════════════════════════════════════════════════════════
#  §089 符纸的程序化纹理 —— 零素材(代码现画一张 Image, 不落任何资源文件)
# ══════════════════════════════════════════════════════════════════

## 一张符纸的图: 外边框 + 内框细线 + 月牙 + 符文笔画。
##
## ★为什么非画不可: 改前干净台 22 倍拉近占大半屏, 符纸是**一张纯白空白四边形** ——
##   没有符文、没有月、没有边框。装备叫"蚀月符纸", 画面上却没有任何一个字对得上。
## ★门禁量的是**这张 Image 的真实像素**(色阶数 / 边框比纸面亮 / 月牙面积占外圆的比例
##   落在"是月牙不是满月也不是空"的区间 / 符文区亮像素数), 不是"我看着像"。
static func talisman_tex_image() -> Image:
	var img := Image.create(TALISMAN_TEX_W, TALISMAN_TEX_H, false, Image.FORMAT_RGBA8)
	img.fill(TX_PAPER)
	var w: int = TALISMAN_TEX_W
	var h: int = TALISMAN_TEX_H
	# ① 外边框(3 px)
	for y in range(h):
		for x in range(w):
			if x < 3 or x >= w - 3 or y < 3 or y >= h - 3:
				img.set_pixel(x, y, TX_EDGE)
	# ② 内框细线(inset 5, 1 px)
	for x in range(5, w - 5):
		img.set_pixel(x, 5, TX_INNER)
		img.set_pixel(x, h - 6, TX_INNER)
	for y in range(5, h - 5):
		img.set_pixel(5, y, TX_INNER)
		img.set_pixel(w - 6, y, TX_INNER)
	# ③ 月牙 = 外圆减去偏置的内圆(这是"蚀月"四个字的字面几何)
	for y in range(h):
		for x in range(w):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			if p.distance_to(MOON_C) <= MOON_R and p.distance_to(MOON_CUT_C) > MOON_CUT_R:
				img.set_pixel(x, y, TX_MOON)
	# ④ 符文笔画: 一根中竖 + 三道横 + 两笔斜挑(下半张)
	_stroke(img, 30, 52, 34, 88)
	_stroke(img, 19, 56, 45, 59)
	_stroke(img, 23, 67, 41, 70)
	_stroke(img, 17, 78, 47, 81)
	## 两笔斜挑。★上界收在 y = 89 —— 再往下就压到 91 起的下边框上, 会把边框啃出缺口
	##   (纹理是自己画的, 越界不报错、只是画面上少一段边, 属于"改完不看图就发现不了"那类)。
	for k in range(6):
		_stroke(img, 22 - k, 82 + k, 25 - k, 84 + k)
		_stroke(img, 39 + k, 82 + k, 42 + k, 84 + k)
	return img


## 画一个实心矩形笔画(纹理像素坐标, 含边界), 越界自动裁掉。
static func _stroke(img: Image, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(maxi(0, mini(y0, y1)), mini(img.get_height() - 1, maxi(y0, y1)) + 1):
		for x in range(maxi(0, mini(x0, x1)), mini(img.get_width() - 1, maxi(x0, x1)) + 1):
			img.set_pixel(x, y, TX_RUNE)


## ★优先用**真立绘**(PixelLab 出的黄纸朱砂符, 2026-08-07)。
##   `talisman_tex_image()` 那张程序化的留着当兜底 —— 它是"几个矩形拼的符文",
##   v0.19.37 之前它甚至是一张**纯白空板**(10.8×9.3 屏幕像素, 无符文/无月/无边框)。
##   ⚠ 返回类型放宽到 Texture2D: 立绘是 CompressedTexture2D, 不是 ImageTexture。
##     写死 ImageTexture 会在这里静默走不进去(只有实拍能发现)。
const TALISMAN_TEX_PATH := "res://assets/sprites/vfx/eq-talisman.png"
var _tex_talisman_file: Texture2D = null
var _tex_talisman_tried := false

func _talisman_tex() -> Texture2D:
	if not _tex_talisman_tried:
		_tex_talisman_tried = true
		if ResourceLoader.exists(TALISMAN_TEX_PATH):
			_tex_talisman_file = load(TALISMAN_TEX_PATH)
	if _tex_talisman_file != null:
		return _tex_talisman_file
	if _tex_talisman == null:
		_tex_talisman = ImageTexture.create_from_image(talisman_tex_image())
	return _tex_talisman


## ⑦ 起跳影子的收缩比例。性质(门禁逐条验): f(0) ≡ 1 · f(apex) ≡ LEAP_SHADOW_MIN · 严格单调减。
## ★"影子随高度收缩"是全行业通用的高度读数, 不是我编的曲线 —— 所以它可以是线性的。
static func leap_shadow_scale(h_m: float, apex_m: float) -> float:
	return lerpf(1.0, LEAP_SHADOW_MIN, clampf(h_m / maxf(0.001, apex_m), 0.0, 1.0))


## ⑦ 收势环的半径。性质: r(0) = LEAP_TELE_R0·R · **r(1) ≡ R(精确)** · 严格单调减。
## ★r(1) 精确落在终了半径上 —— 收不到位就读不出“砸落就是现在”。
static func telegraph_radius(q: float, r_max: float) -> float:
	return r_max * lerpf(LEAP_TELE_R0, 1.0, clampf(q, 0.0, 1.0))


## 浪潮一跳的拱高(米制无关的比例形): 4·h·s(1−s), s∈[0,1]。
## ★s=0 与 s=1 处为 0(两端贴着单位), 峰在 s=0.5 处 = h。
static func arc_height(s: float, peak: float) -> float:
	var x: float = clampf(s, 0.0, 1.0)
	return 4.0 * peak * x * (1.0 - x)


## 折线总长(码) —— 浪潮跳了多远的可量形式。
static func path_length(pts: Array) -> float:
	var sum: float = 0.0
	for i in range(1, pts.size()):
		sum += (pts[i] as Vector2).distance_to(pts[i - 1] as Vector2)
	return sum


# ══════════════════════════════════════════════════════════════════
#  §几何 —— 程序化 ArrayMesh, 零素材
# ══════════════════════════════════════════════════════════════════

static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for v in [a, b, c]:
		st.set_color(v[1])
		st.add_vertex(v[0])


static func _flat(r: float, th: float, a: float) -> Array:
	return [Vector3(r * cos(th), GROUND_Y, r * sin(th)), Color(1, 1, 1, a)]


## 单位半径的贴地环(外沿硬 = 区域边界, 内沿渐隐)。
static func _build_ring() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(RING_LON):
		var t0: float = float(j) / float(RING_LON) * TAU
		var t1: float = float(j + 1) / float(RING_LON) * TAU
		for q in [[0.80, 0.0, 0.96, 0.85], [0.96, 0.85, 1.0, 0.30]]:
			var r0: float = q[0]
			var a0: float = q[1]
			var r1: float = q[2]
			var a1: float = q[3]
			_tri(st, _flat(r0, t0, a0), _flat(r1, t0, a1), _flat(r1, t1, a1))
			_tri(st, _flat(r0, t0, a0), _flat(r1, t1, a1), _flat(r0, t1, a0))
	st.commit(mesh)
	return mesh


func _ring_mesh() -> ArrayMesh:
	if _mesh_ring == null:
		_mesh_ring = _build_ring()
	return _mesh_ring


## 088 专用的【区域边界】环(单位半径)。★与 `_build_ring` 分开是**有意的**:
##   那张软环是给"潮涌 / 猛砸"这类**扩散波**用的, 波本来就该软; 而 088 要的是一条**界线**。
##   共用一张 = 又要软又要硬, 只能两边都不像。三层结构:
##     ① 圈内底色(0 → BOUNDARY_TICK_IN, alpha = BOUNDARY_FILL) —— "里面"是一块地
##     ② 硬边(BOUNDARY_RIM → 1.0, alpha = 1.0, 内外都不渐隐) —— 线在哪一眼看得出
##     ③ 每 15° 一根向内的刻度 —— 读作界线而不是"一圈光"
static func _build_boundary_ring() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(RING_LON):
		var t0: float = float(j) / float(RING_LON) * TAU
		var t1: float = float(j + 1) / float(RING_LON) * TAU
		# ① 圈内底色: 从圆心铺到刻度起点(用扇形三角, 内半径 0)
		_tri(st, _flat(0.0, t0, BOUNDARY_FILL), _flat(BOUNDARY_TICK_IN, t0, BOUNDARY_FILL),
			_flat(BOUNDARY_TICK_IN, t1, BOUNDARY_FILL))
		# ② 硬边: 内外沿都不渐隐 ⇒ 边界是"线"不是"雾"
		_tri(st, _flat(BOUNDARY_RIM, t0, 1.0), _flat(1.0, t0, 1.0), _flat(1.0, t1, 1.0))
		_tri(st, _flat(BOUNDARY_RIM, t0, 1.0), _flat(1.0, t1, 1.0), _flat(BOUNDARY_RIM, t1, 1.0))
	# ③ 向内的刻度(每 TAU/BOUNDARY_TICKS 一根)
	var half: float = TAU / float(BOUNDARY_TICKS) * 0.16
	for k in range(BOUNDARY_TICKS):
		var th: float = float(k) / float(BOUNDARY_TICKS) * TAU
		_tri(st, _flat(BOUNDARY_TICK_IN, th - half, 0.0), _flat(BOUNDARY_RIM, th - half, 0.95),
			_flat(BOUNDARY_RIM, th + half, 0.95))
		_tri(st, _flat(BOUNDARY_TICK_IN, th - half, 0.0), _flat(BOUNDARY_RIM, th + half, 0.95),
			_flat(BOUNDARY_TICK_IN, th + half, 0.0))
	st.commit(mesh)
	return mesh


func _boundary_mesh() -> ArrayMesh:
	if _mesh_boundary == null:
		_mesh_boundary = _build_boundary_ring()
	return _mesh_boundary


## 边界环的材质: **MIX 而不是 ADD**。ADD 会把硬边和刻度一起加成一片白, 边界反而更糊
##   —— 与 089 符纸那条同源(`_mat_paper` 的注释)。
static func _mat_boundary(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.render_priority = 9
	m.albedo_color = col
	return m


static func _mat(col: Color, prio: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	## ⚠ render_priority 在【材质】上, MeshInstance3D 没有这个属性
	m.render_priority = prio
	m.albedo_color = col
	return m


## 贴图片材质(符纸用)。★与 `_mat` 的两处关键差别:
##   · **MIX 而不是 ADD** —— ADD 会把纸面/边框/符文一起加成一片白, 正是旧版"纯白空白"的一半原因
##   · `no_depth_test` —— 符纸贴在敌人身上, 不穿透就会被立绘挡掉半张
## **实体**材质(碑体用)。★与 `_mat` 的关键差别是 **MIX 而不是 ADD**:
## ADD 下一个实心盒子的正反两面(CULL_DISABLED)会互相叠加 ⇒ 青色 #5fd8ff **爆成纯白**,
## 实拍里 088 的碑就是一块**纯白长方块**(白球/白块家族)。实体物要 MIX + 只画正面。
static func _mat_solid(col: Color, prio: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.render_priority = prio
	m.albedo_color = col
	return m


static func _mat_paper(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.no_depth_test = true
	m.render_priority = 11
	m.albedo_color = Color(1, 1, 1, 1)
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 像素画风, 别插值糊掉笔画
	return m


func _adopt(n: Node3D, kind: String) -> void:
	n.set_meta(META_KEY, kind)
	battle._world.add_child(n)
	if _owned.size() >= OWNED_CAP:
		_owned = _owned.filter(func(x): return is_instance_valid(x))
	_owned.append(n)


func _node(mesh: Mesh, mat: StandardMaterial3D, org: Vector3, kind: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = org
	_adopt(mi, kind)
	return mi


## 一条 A→B 的光带(细长盒体, 沿 +X 拉伸后绕 Y 对齐)。
func _band(a2d: Vector2, b2d: Vector2, col: Color, width_px: float, y_m: float) -> MeshInstance3D:
	var wf: Vector3 = battle._world_pos(a2d, y_m)
	var wt: Vector3 = battle._world_pos(b2d, y_m)
	var seg: Vector3 = wt - wf
	var l: float = seg.length()
	if l < 0.001:
		return null
	var bm := BoxMesh.new()
	bm.size = Vector3(l, width_px * float(battle.WS), width_px * float(battle.WS))
	var mi := _node(bm, _mat(col, 12), wf + seg * 0.5, "band")
	mi.rotation.y = -atan2(seg.z, seg.x)
	return mi


# ══════════════════════════════════════════════════════════════════
#  §088 涨潮碑
# ══════════════════════════════════════════════════════════════════

## 立碑: 一圈贴地边界(半径 = 效果半径) + 一块从地里顶上来的碑体。
## ★环的半径**就是** 250 码的效果半径 —— 不是"贴片尺寸"
##   (memory [[fb-verify-must-run-the-real-path]] 那次把效果半径当贴片尺寸, 公式全对但长 19.2 米)。
func stele_raise(pos2d: Vector2, radius_px: float, sec: float) -> Node3D:
	if not _has_world():
		return null
	var root := Node3D.new()
	root.position = battle._world_pos(pos2d, 0.0)
	_adopt(root, "stele")
	# ★2026-08-07 换成【区域边界环】: 硬外沿 + 圈内底色 + 每 15° 一根刻度。
	#   旧的是与潮涌/猛砸共用的软环 ⇒ 圈内与圈外读不出差别, 而 088 的攻速增益
	#   **只在圈内**, 那条边界就是这件的全部信息。共用软环也照旧留着(潮涌还在用)。
	var ring := MeshInstance3D.new()
	ring.mesh = _boundary_mesh()
	ring.material_override = _mat_boundary(COL_TIDE)
	ring.scale = Vector3(radius_px * float(battle.WS), 1.0, radius_px * float(battle.WS))
	root.add_child(ring)
	# ★★2026-08-08 实拍(_vfxlab_p2eq_088)后重做碑体。旧版是**一块纯白长方块** ——
	#   根因不是颜色而是 `_mat` 走 **ADD**: 实心盒子的正反两面叠加把 #5fd8ff 爆成白。
	#   ⇒ 走 `_mat_solid`(MIX + 只画正面), 并拆成三段做出**碑的剪影**:
	#     底座(宽而矮·暗) / 碑身(窄而高·石青) / 顶端符带(亮青, 这块是"它在生效"的信号)
	var ws: float = float(battle.WS)
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(STELE_W_PX * ws, STELE_H_PX * ws, STELE_D_PX * ws)
	slab.mesh = bm
	slab.material_override = _mat_solid(COL_STELE_BODY, 10)
	root.add_child(slab)
	var base := MeshInstance3D.new()
	var bbm := BoxMesh.new()
	bbm.size = Vector3(STELE_W_PX * STELE_BASE_K * ws, STELE_H_PX * 0.16 * ws,
		STELE_D_PX * STELE_BASE_K * ws)
	base.mesh = bbm
	base.material_override = _mat_solid(COL_STELE_BASE, 9)
	base.position = Vector3(0.0, -STELE_H_PX * 0.42 * ws, 0.0)
	slab.add_child(base)
	var rune := MeshInstance3D.new()
	var rbm := BoxMesh.new()
	rbm.size = Vector3(STELE_W_PX * 1.08 * ws, STELE_H_PX * 0.055 * ws, STELE_D_PX * 1.08 * ws)
	rune.mesh = rbm
	# ⚠ 这里**也不能用 ADD**: 实心盒正反面叠加照样把青爆成白(第一版符带就是一条白带,
	#   跟碑体是同一个根因, 只是换了个小零件)。要"发亮"靠**提亮颜色**, 不靠加法混合。
	rune.material_override = _mat_solid(COL_STELE_RUNE, 11)
	rune.position = Vector3(0.0, STELE_H_PX * 0.24 * ws, 0.0)
	slab.add_child(rune)
	## ★把【效果半径】记在节点自己身上, 门禁量真实对象而不是在测试里把公式抄一遍
	##   (memory [[fb-write-without-reader-and-fake-gates]]:「门禁模拟公式 ≠ 量真实对象」)。
	root.set_meta("radius_px", radius_px)
	_fx.append({"node": root, "slab": slab, "t": 0.0, "life": maxf(0.05, sec), "kind": "stele"})
	return root


## 每秒一跳的潮涌环(匀速外扩)。
func stele_pulse(pos2d: Vector2, radius_px: float) -> Node3D:
	return _ring_fx(pos2d, radius_px, COL_TIDE, PULSE_SEC, "pulse")


# ══════════════════════════════════════════════════════════════════
#  §089 蚀月符纸
# ══════════════════════════════════════════════════════════════════

## 给目标贴一张悬浮符纸(跟着它走, 上下轻浮 + 慢自转)。
## ★状态里存的是**单位字典本身**(放在 `_fx` 条目的 value 位) —— 允许;
##   禁止的是拿它当 Dictionary 的**键**(CLAUDE.md §3.2)。
func talisman_stick(u, sec: float) -> Node3D:
	if not _has_world() or not (u is Dictionary):
		return null
	## ★QuadMesh 而不是 BoxMesh: 片就是片, 没有"厚度"这一维就没有"侧对镜头"这件事可发生。
	var qm := QuadMesh.new()
	qm.size = Vector2(TALISMAN_W_PX * float(battle.WS), TALISMAN_H_PX * float(battle.WS))
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	mi.material_override = _mat_paper(_talisman_tex())
	mi.position = battle._world_pos((u as Dictionary)["pos"] as Vector2, TALISMAN_Y)
	mi.basis = face_basis(_cam_forward(), 0.0)
	_adopt(mi, "talisman")
	## 这只单位身上已经有几张 ⇒ 新的一张排在下一格(扇形错开, 见 TALISMAN_FAN_PX)
	_fx.append({"node": mi, "unit": u, "t": 0.0, "life": maxf(0.05, sec),
		"kind": "talisman", "slot": talisman_count_on(u)})
	_reflow_talismans(u)
	return mi


## 这只单位身上**现存**几张符纸(不含刚要加的那张)。门禁直接调, 纯同步。
func talisman_count_on(u) -> int:
	var n: int = 0
	for f in _fx:
		if str(f.get("kind", "")) != "talisman":
			continue
		if is_same(f.get("unit", null), u):
			n += 1
	return n


## 把这只单位身上的符纸重新编号(0..n-1) —— 中间掉一张时后面的要补位,
## 否则扇形会留个洞、且 slot 越用越大把符纸甩到体外。
func _reflow_talismans(u) -> void:
	var idx: int = 0
	for f in _fx:
		if str(f.get("kind", "")) != "talisman":
			continue
		if not is_same(f.get("unit", null), u):
			continue
		f["slot"] = idx
		f["slots"] = 0
		idx += 1
	for f in _fx:
		if str(f.get("kind", "")) == "talisman" and is_same(f.get("unit", null), u):
			f["slots"] = idx


## 第 i 张(共 n 张)相对单位中心的横向偏移(场地像素) —— 整组以中心对称。
static func talisman_fan_dx(i: int, n: int) -> float:
	if n <= 1:
		return 0.0
	return (float(i) - float(n - 1) * 0.5) * TALISMAN_FAN_PX


## 符纸从尸体飞向新目标的那道紫光。
func talisman_transfer(from2d: Vector2, to2d: Vector2) -> Node3D:
	if not _has_world():
		return null
	var mi := _band(from2d, to2d, COL_MOON, 10.0, TALISMAN_Y)
	if mi == null:
		return null
	_fx.append({"node": mi, "t": 0.0, "life": TRANSFER_SEC, "kind": "transfer"})
	return mi


# ══════════════════════════════════════════════════════════════════
#  §090 镇海杵
# ══════════════════════════════════════════════════════════════════

## 起跳 → 滞空 → 砸落的**节奏读数**(存活 = 起跳到砸落的时长)。
##
## ★2026-08-07 重做。原来是一根**从头到尾不动**的白光柱: 起跳、滞空、下落三段在画面上
##   完全一样, 玩家只看到"地上多了一根白条", 节奏一点都读不出来(用户原话
##   「跳起来那一段读不出」)。现在三样各管一件事, **全部跟着携带者的真实滞空高度走**:
##     · **水柱**: 高度 ≡ `u["height"]`(主循环 airborne 积分出来的那个数, 不是另跑一条曲线)
##       ⇒ 柱子长 = 它跳了多高, 上升/悬停/下落一眼分得出
##     · **地面影子**: 按 `leap_shadow_scale` 收缩 —— "东西在多高"的经典读数
##     · **落点预告环**: 半径从 1.18× 收到 1.0×(`telegraph_radius`), **收满即砸落**
##       ⇒ 提前告诉玩家"这一下要砸多大、什么时候砸"; 用的是 088 那张**硬边**网格,
##         因为它要表达的确实是一条边界。
## 雷电预警圈的**一批**电弧(圆周分 WARN_ARCS 段, 每段一道分形电弧 + 白热芯 + 偶尔一根内指分叉)。
## ★半径就是**真实砸落半径**, 不缩不涨 —— 用户:「预警环我不想要缩的, 要实际范围的」。
##   旧版收拢到 `LEAP_WINDUP_PX = 110` 码, 而真正挨砸的是 1000 码, **差九倍**。
func _warn_batch(root: Node3D, center: Vector2, radius_px: float, col: Color) -> void:
	var rng: RandomNumberGenerator = battle._juice_rng
	var sheet: Texture2D = _arc_sheet()
	for i in range(WARN_ARCS):
		var a0: float = TAU * float(i) / float(WARN_ARCS)
		var a1: float = TAU * float(i + 1) / float(WARN_ARCS)
		## ★★把电弧摆在【真实生效边界】= 伤害圆 ∩ 战场, 而不是数学上的圆周。
		##   为什么: 1000 码半径 ⇒ 直径 2000 码, 而战场只有 1596×728 码 —— **圈比战场还大**。
		##   画在数学圆周上, 电弧全部落在场外: 能看清龟的取景里圈在画面外, 能看到圈的取景里
		##   龟只剩几个像素(2026-08-09 实拍确认)。而"画一个玩家永远看不全的圈"本身就是假消息,
		##   与旧版"元数据写 1000、实际画 110"是同一种谎, 只是方向相反。
		##   ⇒ 沿射线取"圆周点"与"战场边界点"里**更近的那个**: 范围没被缩小,
		##     只是把边界画在它真正起作用的地方。
		var p0: Vector2 = _warn_edge(center, a0, radius_px)
		var p1: Vector2 = _warn_edge(center, a1, radius_px)
		if sheet != null:
			## ★★精灵表电弧: 每段**各自随机起始帧** —— 整批同相位会读成"一圈在齐步闪",
			##   那是旧版随机折线换汤不换药。相位错开才像一圈各自噼啪的电。
			_arc_sprite(root, (p0 + p1) * 0.5, center, col, sheet, rng.randi() % ARC_SHEET_FRAMES)
		else:
			_arc_seg(root, p0, p1, col, WARN_W_PX, WARN_CORE_W_PX, rng)   # 素材缺失时的兜底
	## 圈内雷雾 —— 见 MIST_* 的头注: 这里**不再**画线段, 由 `_mist_particles` 出真粒子。
	## (电弧只沿圆周排一圈; 圈内的"有电感"完全交给粒子。)


## ══ 生成素材(PixelLab · 2026-08-09 · 用户「要像素风格就好, 不要对齐」) ══
## ★为什么用精灵表而不是继续拼几何: 电弧的精髓是**逐帧变形**(锯齿重排 + 爆闪出现/消失),
##   几何近似做不出来 —— 旧实现是"每 0.07 秒整批重生一批随机折线", 那是噪声不是动画。
const ARC_SHEET_PATH := "res://assets/sprites/vfx/eq090-warn-arc.png"
const ARC_SHEET_FRAMES := 9
const ARC_SHEET_FPS := 14.0
## 单段电弧的世界尺寸(Sprite3D.pixel_size)与离地高度(米)。
## 64 px 的图 × 0.032 ≈ 2.0 米 ≈ 一只龟高。★旧值 0.075 会做出 4.8 米的电弧(比龟高一倍多)。
const ARC_PX_SIZE := 0.032
const ARC_H_M := 1.05
## 落点水花: 原地翻搅的水盘(逐帧泡沫重排)。
## ⚠ 诚实记录: 同一批还生成过一版"扩散的环", 但**实测它没在扩**
##   (逐帧量平均半径 36.6→34.3, 反而略缩) ⇒ 没拿它当波前, 改当水花。
const SPLASH_SHEET_PATH := "res://assets/sprites/vfx/eq090-splash.png"
const SPLASH_SHEET_FRAMES := 9
## 冲击波前沿: 一圈**朝外站立**的碎浪(9 帧, 泡沫逐帧重排)。
## ★这才是"不是一个环在被拉大": 环的**成分**是会碎的浪, 半径只负责把它推出去。
const CREST_SHEET_PATH := "res://assets/sprites/vfx/eq090-crest.png"
const CREST_SHEET_FRAMES := 9
const CREST_N := 20             ## 一圈几段浪冠
const CREST_H_M := 2.6          ## 单段浪冠的高度(米)
const CREST_FPS := 20.0

var _tex_arc_sheet: Texture2D = null
var _tex_arc_tried := false
func _arc_sheet() -> Texture2D:
	if not _tex_arc_tried:
		_tex_arc_tried = true
		if ResourceLoader.exists(ARC_SHEET_PATH):
			_tex_arc_sheet = load(ARC_SHEET_PATH)
	return _tex_arc_sheet


var _tex_crest_sheet: Texture2D = null
var _tex_crest_tried := false
func _crest_sheet() -> Texture2D:
	if not _tex_crest_tried:
		_tex_crest_tried = true
		if ResourceLoader.exists(CREST_SHEET_PATH):
			_tex_crest_sheet = load(CREST_SHEET_PATH)
	return _tex_crest_sheet


var _tex_splash_sheet: Texture2D = null
var _tex_splash_tried := false
func _splash_sheet() -> Texture2D:
	if not _tex_splash_tried:
		_tex_splash_tried = true
		if ResourceLoader.exists(SPLASH_SHEET_PATH):
			_tex_splash_sheet = load(SPLASH_SHEET_PATH)
	return _tex_splash_sheet


## 单颗雾的贴图。★没有它, `QuadMesh` 就是一个**实心方片** —— 2026-08-09 实拍
##   满屏蓝方块就是这么来的(我照抄 `_impact_particles` 时漏了"它那颗只有 0.16 米所以看不出是方的")。
## 做法: 16×16 径向衰减 + **量化成 5 档**(像素风要的是台阶不是高斯糊) + NEAREST。
var _tex_mist: ImageTexture = null
func _mist_tex() -> ImageTexture:
	if _tex_mist != null:
		return _tex_mist
	var n: int = 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c: float = float(n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var d: float = Vector2(float(x) - c, float(y) - c).length() / (c + 0.5)
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			## 量化: 连续渐变 → 5 档台阶(像素风)
			a = floor(a * 5.0) / 5.0
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_tex_mist = ImageTexture.create_from_image(img)
	return _tex_mist


## 预警范围内的**雷雾粒子**。整个圆盘都在冒, 不是一圈边。
## ★半径直接吃传进来的 `radius_px` —— 与伤害半径同一个数, 不另设参数(旧版差九倍就是这么来的)。
func _mist_particles(center: Vector2, radius_px: float, col: Color) -> GPUParticles3D:
	var ps := GPUParticles3D.new()
	ps.amount = MIST_PARTICLES
	ps.lifetime = MIST_LIFE
	ps.one_shot = false
	ps.explosiveness = 0.0
	ps.randomness = 1.0
	ps.local_coords = false
	ps.fixed_fps = 30
	var pm := ParticleProcessMaterial.new()
	## 发射体 = **实心圆盘**(RING 内径 0) ⇒ 雾铺满整个预警范围, 不是只在边上
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.emission_ring_radius = radius_px * float(battle.WS)
	pm.emission_ring_inner_radius = 0.0
	pm.emission_ring_height = 0.25
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 22.0
	pm.initial_velocity_min = MIST_RISE * 0.4
	pm.initial_velocity_max = MIST_RISE
	pm.gravity = Vector3(0, -0.35, 0)          # 轻微回落 ⇒ 翻涌而不是升天
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = MIST_TURB
	pm.turbulence_noise_scale = 2.2
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -40.0
	pm.angular_velocity_max = 40.0
	pm.scale_min = 0.55
	pm.scale_max = 1.35
	## 尺寸曲线: 生出来小 → 涨到满 → 收掉(避免"凭空出现又凭空消失")
	var cv := Curve.new()
	cv.add_point(Vector2(0.0, 0.15))
	cv.add_point(Vector2(0.35, 1.0))
	cv.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = cv
	pm.scale_curve = ct
	## 颜色渐变: 暗 → 亮 → 透(按阵营色)
	var gr := Gradient.new()
	gr.set_color(0, Color(col.r * 0.35, col.g * 0.35, col.b * 0.35, 0.0))
	gr.set_color(1, Color(col.r, col.g, col.b, 0.0))
	gr.add_point(0.25, Color(col.r, col.g, col.b, 0.20))
	gr.add_point(0.70, Color(col.r, col.g, col.b, 0.13))
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	pm.color_ramp = gt
	ps.process_material = pm
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.vertex_color_use_as_albedo = true
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.albedo_color = col
	dm.albedo_texture = _mist_tex()
	dm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var qm := QuadMesh.new()
	qm.size = Vector2(MIST_SZ_PX * float(battle.WS), MIST_SZ_PX * float(battle.WS))
	qm.material = dm
	ps.draw_pass_1 = qm
	ps.position = battle._world_pos(center, 0.10)
	ps.emitting = true
	return ps


## 从 `center` 沿 `ang` 出发, 取"伤害半径"与"战场边界"里先到的那个交点。
## ★纯几何, 门禁直接调(不建节点)。半径 ≤ 战场时结果就是圆周本身 —— 不改变小范围的行为。
static func warn_edge_dist(center: Vector2, ang: float, radius_px: float, arena: Rect2) -> float:
	var d := Vector2(cos(ang), sin(ang))
	var lim: float = radius_px
	if absf(d.x) > 1e-6:
		var tx: float = ((arena.end.x if d.x > 0.0 else arena.position.x) - center.x) / d.x
		if tx > 0.0:
			lim = minf(lim, tx)
	if absf(d.y) > 1e-6:
		var ty: float = ((arena.end.y if d.y > 0.0 else arena.position.y) - center.y) / d.y
		if ty > 0.0:
			lim = minf(lim, ty)
	return maxf(lim, 1.0)


func _warn_edge(center: Vector2, ang: float, radius_px: float) -> Vector2:
	var r: float = warn_edge_dist(center, ang, radius_px, battle.ARENA)
	return center + Vector2(cos(ang), sin(ang)) * r


## 一段【精灵表】电弧: 竖立在圈上、正对镜头, 逐帧播放。
## ⚠ 站立而不是躺平 —— `axis = AXIS_Y` **本身就是平铺**, 再 rotation.x=-90 会抵消
##   (memory [[fb-axis-y-plus-rotation-cancels]]: 两圈"贴地印记"因此一直立着)。
##   这里要的就是立着, 所以直接用 Sprite3D 的默认 billboard, 不碰 axis。
func _arc_sprite(root: Node3D, at: Vector2, center: Vector2, col: Color, sheet: Texture2D, frame0: int) -> void:
	var sp := Sprite3D.new()
	sp.texture = sheet
	sp.hframes = ARC_SHEET_FRAMES
	sp.frame = frame0 % ARC_SHEET_FRAMES
	sp.set_meta("f0", frame0 % ARC_SHEET_FRAMES)
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.shaded = false
	sp.transparent = true
	## ⚠ 不能用 ALPHA_CUT_DISCARD: 它按 0.5 阈值丢像素, 而下面 tick 里把整段
	##   `modulate.a` 压到 0.45(刚起跳时) ⇒ **整条电弧被丢光**, 实拍完全看不见。
	##   (2026-08-09 踩到; 表现是"精灵表接好了、编译也过了, 就是没有画面"。)
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sp.modulate = Color(col.r, col.g, col.b, 1.0)
	sp.pixel_size = ARC_PX_SIZE
	sp.render_priority = 6
	## ⚠ 相对量要按**圆心**算, 不能按 `root.position` —— 传进来的 root 是 `warn` 节点,
	##   它的 `.position` 是局部的 0, 而它挂在已经位移到单位处的 leap root 下
	##   ⇒ 用 root.position 会把偏移加两次, 电弧被甩到世界角落(2026-08-09 实拍全黑就是它)。
	sp.position = battle._world_pos(at, ARC_H_M) - battle._world_pos(center, 0.0)
	root.add_child(sp)


## 一段分形电弧(身 + 白热芯), 挂到 root 下。★与 078 电鳗同一条做法。
func _arc_seg(root: Node3D, a: Vector2, b: Vector2, col: Color,
		w_px: float, core_px: float, rng: RandomNumberGenerator) -> void:
	var pts: Array = [a, b]
	var span: float = (b - a).length()
	var dir: Vector2 = (b - a).normalized() if span > 0.001 else Vector2.RIGHT
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	for lv in range(WARN_DEPTH):
		var sig: float = span * WARN_ROUGH * pow(2.0, -0.5 * float(lv + 1))
		var out: Array = [pts[0]]
		for k in range(pts.size() - 1):
			var mid: Vector2 = (Vector2(pts[k]) + Vector2(pts[k + 1])) * 0.5
			out.append(mid + perp * sig * (rng.randf() * 2.0 - 1.0))
			out.append(Vector2(pts[k + 1]))
		pts = out
	for k2 in range(pts.size() - 1):
		_warn_band(root, pts[k2], pts[k2 + 1], w_px, Color(col.r, col.g, col.b, col.a * 0.85))
		_warn_band(root, pts[k2], pts[k2 + 1], core_px, Color(1.0, 1.0, 1.0, col.a))


## 一条贴地的细带(世界坐标顶点直接建 ⇒ 朝向由几何决定, 不靠 billboard)。
func _warn_band(root: Node3D, a: Vector2, b: Vector2, half_w_px: float, col: Color) -> void:
	var d: Vector2 = b - a
	if d.length() < 0.001:
		return
	var p: Vector2 = Vector2(-d.y, d.x).normalized() * half_w_px * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v: Array = [battle._world_pos(a + p, WARN_Y), battle._world_pos(b + p, WARN_Y),
		battle._world_pos(b - p, WARN_Y), battle._world_pos(a - p, WARN_Y)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(v[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(col, 11)
	root.add_child(mi)


## `dest`: 这一跳的**落点**。预警圈钉在它上面(用户 2026-08-13:「需要正确的显示预警区,
## 即落点的多少范围而不是起跳的」); 影子仍跟着龟走 —— 那两样本来就该分开。
func pestle_leap(u, sec: float, dest = null) -> Node3D:
	if not _has_world() or not (u is Dictionary):
		return null
	var pos2: Vector2 = (u as Dictionary)["pos"]
	var root := Node3D.new()
	root.position = battle._world_pos(pos2, 0.0)
	_adopt(root, "leap")
	# ★★2026-08-08 **删掉水柱**。用户:「我从始至终说的高高跃起, 加什么水柱啊」——
	#   他说得对: 规格里从来没有水柱, 那是我接手前就在那儿、我又没质疑就留着了。
	#   "高高跃起"该看到的是**龟真的飞得很高 + 地面影子缩小**, 不是脚下长出一根柱子。
	# 地面影子
	var sh := MeshInstance3D.new()
	sh.mesh = _ring_mesh()
	sh.material_override = _mat(COL_WAVE, 8)
	sh.scale = Vector3(LEAP_SHADOW_PX * 0.5 * float(battle.WS), 1.0, LEAP_SHADOW_PX * 0.5 * float(battle.WS))
	root.add_child(sh)
	# ★★雷电预警圈(2026-08-08 重做)。旧版是一圈**收拢的硬边环**, 而且收拢到
	#   `LEAP_WINDUP_PX = 110` 码 —— 真正挨砸的是 `SLAM_R_PX = 1000` 码, **差九倍**:
	#   玩家读到"圈收到这么小 = 只有这一小圈挨砸", 站 300 码外照样吃 3ATK+5000 魔法+8 秒眩晕。
	#   (节点上还 `set_meta("radius_px", SLAM_R_PX)` 写着 1000 ⇒ **元数据说 1000、画出来 110**,
	#    门禁只验 meta 就抓不到 —— memory [[fb-write-without-reader-and-fake-gates]] 那一族。)
	#   ⇒ 现在: **固定在真实半径、不缩**, 且是**活的电弧**(每 WARN_REFRESH 秒整批重生)。
	var warn := Node3D.new()
	warn.position = Vector3.ZERO
	root.add_child(warn)
	var side_col: Color = WARN_ALLY if str(battle._eff_side(u)) == "left" else WARN_FOE
	_warn_batch(warn, pos2, SLAM_R_PX, side_col)
	## ★雷雾: 真粒子, 铺满整个预警圆盘(见 `_mist_particles`)。
	## ⚠ 必须挂在 **root** 下, 不能挂 `warn` —— tick 里电弧每 WARN_REFRESH(0.07 秒)
	##   把 `warn` 的子节点**整批 queue_free 重生**, 挂那儿的粒子会被反复清掉(等于没有)。
	##   挂 root 则跟着 `drop_leap`/寿命一起收, 生命周期正好。
	var mist := _mist_particles(pos2, SLAM_R_PX, side_col)
	mist.position = battle._world_pos(pos2, 0.10) - root.position
	root.add_child(mist)
	root.set_meta("radius_px", SLAM_R_PX)
	_fx.append({"node": root, "unit": u, "shadow": sh, "warn": warn,
		"dest": (dest if dest is Vector2 else pos2),
		"warn_col": side_col, "warn_t": 0.0,
		## ★★`life` 只用来算进度 q(电弧越接近落地越快越亮), **不再用它退场**。
		##   2026-08-09 用户:「还没落地怎么雷雾和预警消失了」—— 就是它:
		##   演出 tick 走 `tick_global`(顿帧期间照跑), 而跳跃被 `if frozen` 冻住
		##   ⇒ 演出比人先"到点", 圈和雾在半空就没了。这与砸落提前是**同一个 bug 的两半**,
		##   我上一轮只修了结算侧。⇒ 退场只认 `drop_leap`(真实落地事件), `watchdog` 兜底防孤儿。
		"t": 0.0, "life": maxf(0.05, sec), "kind": "leap",
		"watchdog": maxf(0.05, sec) * 3.0 + 2.0})
	return root


## 砸落。★★2026-08-08 重做 —— 旧版**就一句 `_ring_fx`**: 一圈柔和扩张环, 别的什么都没有。
## 从 7 米砸下来只出一个环, 跟"镇海杵猛砸整个战场"完全不匹配(用户:「砸击特效到底怎么做」)。
## 现在四样, 全是水(这件是镇海杵):
##   ① **水炸开** —— 一大蓬水滴从落点向外抛射(各自走抛物线, 落回地面)
##   ② **冲击波环** —— 半径就是真实的 1000 码, 从 0 扩到满
##   ③ **落点水花** —— 一圈贴地的溅水
##   ④ **震屏** —— 7 米砸下来得有分量
## 收掉某只龟的起跳演出(预警圈 + 影子)。★由**真实落地事件**调, 不靠自己数秒 ——
## 演出的寿命和物理的落地是两条时钟, 一旦分叉就会出现"人落地了圈还亮着"。
## (2026-08-09: 砸落改成落地事件触发后, 门禁当场量到 结算那一帧 预警圈=1。)
## 携带者在【半空阵亡】: 起跳演出改成【按自己的自然寿命走完】再消失。
##
## ★为什么需要这个: 退场本来只认两条路 —— `drop_leap()`(真实落地事件) 或 watchdog 兜底。
##   人死在半空就永远不会有落地事件 ⇒ 预警圈要一直亮到 watchdog(= jump_sec×3+2 ≈ **7.0 秒**),
##   而这一跳本来只有 1.67 秒 ⇒ 圈在尸体上多亮 5 秒多。
## ★用户 2026-08-13 定的语义:「携带者阵亡, 预警特效还是持续到正常消失, 只是没有拍地和
##   击飞特效了」= **演出善终、效果作废**。效果侧本来就对(`_tick_slams` 每帧验 alive 就丢记录),
##   这里补的是演出侧。
func orphan_leap(u) -> void:
	for f in _fx:
		if str(f.get("kind", "")) != "leap":
			continue
		if not is_same(f.get("unit", null), u):
			continue
		f["orphan"] = true      # ⇒ tick 的 "leap" 分支改按 life 退场


func drop_leap(u) -> void:
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		if str(f.get("kind", "")) != "leap":
			continue
		if not is_same(f.get("unit", null), u):
			continue
		_free_fx(i)


func pestle_slam(pos2d: Vector2, radius_px: float) -> Node3D:
	# ★★2026-08-08 冲击波重做(用户:「你这冲击波环做的不好, 节奏也有问题」):
	#   旧版是**一圈软环 + 从出生就线性淡出** ⇒ 扩到最满的那一刻 alpha 恰好 0,
	#   看得见的只有中间那段半亮的慢爬, 而且拖 0.85 秒不散(节奏拖沓)。
	#   ⇒ 拆两层, 各管一件事:
	#     · **硬前沿**: `_boundary_mesh`(硬边, 与预警圈同族) 快速冲出去, **前 55% 满亮**才收
	#     · **余波**: 软环跟在后面、更淡更慢 —— 只负责"刚才这里炸过"
	#   两层都走 Sedov(r ∝ t^0.4), 但**寿命不同** ⇒ 前沿先到边、余波慢慢散, 这就是节奏。
	## ★★波前 = 一圈**朝外站立的碎浪**(生成素材, 9 帧), 半径按 Sedov 往外推。
	##   旧版是 `_boundary_mesh` 被 scale 撑大 —— 那是"一个环在变大", 环本身是死的。
	var crest: Texture2D = _crest_sheet()
	if crest != null:
		var ring_root := Node3D.new()
		ring_root.position = battle._world_pos(pos2d, 0.0)
		_adopt(ring_root, "slam")
		for k in range(CREST_N):
			var ang: float = TAU * float(k) / float(CREST_N)
			var cs := Sprite3D.new()
			cs.texture = crest
			cs.hframes = CREST_SHEET_FRAMES
			cs.frame = k % CREST_SHEET_FRAMES         # 起始帧错开: 一圈不齐步
			cs.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			cs.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			cs.shaded = false
			cs.transparent = true
			cs.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
			cs.render_priority = 12
			cs.pixel_size = CREST_H_M / 64.0
			## 朝外站: 绕 Y 轴转到背对圆心 ⇒ 玩家看到的是一堵朝自己压过来的水墙
			cs.rotation = Vector3(0.0, -ang + PI * 0.5, 0.0)
			cs.set_meta("ang", ang)
			ring_root.add_child(cs)
		_fx.append({"node": ring_root, "t": 0.0, "life": SLAM_EDGE_SEC,
			"kind": "crestring", "r": radius_px, "c": pos2d})
	else:
		var edge := _node(_boundary_mesh(), _mat_boundary(COL_SLAM),
			battle._world_pos(pos2d, 0.05), "slam")
		edge.scale = Vector3(0.001, 1.0, 0.001)
		_fx.append({"node": edge, "t": 0.0, "life": SLAM_EDGE_SEC, "kind": "slamedge", "r": radius_px})
	var ring := _ring_fx(pos2d, radius_px, COL_SLAM, SLAM_SEC, "slam")
	if not _has_world():
		return ring
	var rng: RandomNumberGenerator = battle._juice_rng
	# ① 水炸开: **GPU 粒子**一次性喷发(旧版是 46 个 BoxMesh 各自算抛物线 ⇒ 实拍就是一堆蓝方块,
	#   正是用户说的"方块不像水")。粒子: 半球初速 + 重力回落 + 尺寸曲线 + 深浅两色。
	var burst := GPUParticles3D.new()
	burst.amount = SLAM_BURST_DROPS * 3
	burst.lifetime = SLAM_BURST_SEC
	burst.one_shot = true
	burst.explosiveness = 0.92
	burst.randomness = 1.0
	burst.local_coords = false
	var bpm := ParticleProcessMaterial.new()
	bpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	bpm.emission_sphere_radius = SLAM_SPLASH_PX * 0.25 * float(battle.WS)
	bpm.direction = Vector3(0, 1, 0)
	bpm.spread = 72.0
	bpm.initial_velocity_min = SLAM_BURST_UP * 0.55
	bpm.initial_velocity_max = SLAM_BURST_UP * 1.35
	bpm.gravity = Vector3(0, -18.0, 0)
	bpm.damping_min = 0.4
	bpm.damping_max = 1.6
	bpm.scale_min = 0.5
	bpm.scale_max = 1.5
	var bcv := Curve.new()
	bcv.add_point(Vector2(0.0, 1.0))
	bcv.add_point(Vector2(0.75, 0.85))
	bcv.add_point(Vector2(1.0, 0.0))
	var bct := CurveTexture.new()
	bct.curve = bcv
	bpm.scale_curve = bct
	var bgr := Gradient.new()
	bgr.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	bgr.set_color(1, Color(COL_WATER_DEEP.r, COL_WATER_DEEP.g, COL_WATER_DEEP.b, 0.0))
	bgr.add_point(0.30, COL_WATER)
	var bgt := GradientTexture1D.new()
	bgt.gradient = bgr
	bpm.color_ramp = bgt
	burst.process_material = bpm
	var bdm := StandardMaterial3D.new()
	bdm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bdm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bdm.vertex_color_use_as_albedo = true
	bdm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bdm.albedo_texture = _mist_tex()
	bdm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var bqm := QuadMesh.new()
	bqm.size = Vector2(WATER_DROP_PX * 2.2 * float(battle.WS), WATER_DROP_PX * 2.2 * float(battle.WS))
	bqm.material = bdm
	burst.draw_pass_1 = bqm
	burst.position = battle._world_pos(pos2d, 0.35)
	_adopt(burst, "slam_drop")
	burst.emitting = true
	_fx.append({"node": burst, "t": 0.0, "life": SLAM_BURST_SEC + 0.3, "kind": "keepalive"})
	# ③ 落点水花: **生成的 9 帧水盘**(逐帧泡沫重排), 贴地平铺、边播边扩。
	#   ★不是"一个环被 scale 撑大" —— 表面每帧都在翻搅, 扩散只负责把它铺开。
	#   ⚠ 诚实记录: 同一批还生成过"扩散的环", 实测它**没在扩**(逐帧量平均半径 36.6→34.3),
	#     所以扩散仍由代码给, 素材给的是**表面运动**。两者分工写在这, 别再当它是纯帧驱动。
	var sp_sheet: Texture2D = _splash_sheet()
	if sp_sheet != null:
		var spr := Sprite3D.new()
		spr.texture = sp_sheet
		spr.hframes = SPLASH_SHEET_FRAMES
		spr.frame = 0
		spr.axis = Vector3.AXIS_Y            # ★AXIS_Y 本身就是平铺, 别再 rotation.x=-90(会抵消)
		spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		spr.shaded = false
		spr.transparent = true
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		spr.render_priority = 11
		spr.pixel_size = SLAM_SPLASH_PX * float(battle.WS) / 128.0
		spr.position = battle._world_pos(pos2d, 0.07)
		_adopt(spr, "splash")
		_fx.append({"node": spr, "t": 0.0, "life": SLAM_SEC * 0.9, "kind": "splashsheet",
			"px0": spr.pixel_size})
	else:
		_ring_fx(pos2d, SLAM_SPLASH_PX, COL_WATER, SLAM_SEC * 0.7, "splash")   # 素材缺失兜底
	# ④ 震屏
	battle._shake(SLAM_SHAKE)
	return ring


## 浪潮折线: 每一跳画一段拱形(4·h·s(1−s)), 拱高 = 跨度的 ARC_PEAK_FRAC。
## ★同步建完就返回 —— 伤害早在 `EqArcaneBatch.wave_chain` 里结算过了, 这里纯画。
## 浪潮: **一簇水**沿抛物线从一个目标跳到下一个, 每落一处溅一下。
##
## ★★2026-08-08 用户:「浪潮弹射是**一簇水**在目标之间跳来跳去, **有高度变化**,
##   **并不是闪电连锁**, 你理解有问题」—— 他是对的, 而且这是我读错了规格:
##   原话「发射一片浪潮**如同闪电一样**」说的是"**快**得像闪电", 我读成了"**形状**像闪电",
##   于是做成折线电弧还加了抖动。这件是**镇海杵**, 整件都该是水。
## ⇒ 现在: 一簇水滴(WATER_DROPS 颗, 各带随机小偏移)整体沿**真抛物线**飞,
##   峰高 = 跨度 × ARC_PEAK_FRAC; 每跳到一个目标就 `_water_splash` 溅一圈, 再飞下一跳。
##   飞行节拍与结算侧共用 `EqArcaneBatch.wave_hop_delay(i)`(不各算一份)。
func wave_path(pts: Array) -> Node3D:
	if not _has_world() or pts.size() < 2:
		return null
	var root := Node3D.new()
	root.position = Vector3.ZERO
	_adopt(root, "wave")
	# 带的每一节先全部堆在起点, 之后由 tick 逐段追头(见 "water" 分支)
	var chain: Array = []
	var start: Vector2 = pts[0]
	for k in range(FLOW_SEGS):
		chain.append({"p": start, "h": 0.45})
	# 每两节之间一块四边形(每帧重建 —— 形体在变, 顶点也得跟着变)
	var quads: Array = []
	for k2 in range(FLOW_SEGS - 1):
		var mi := MeshInstance3D.new()
		var wm := _mat_solid(COL_WATER, 12)
		## ⚠ 带子必须**双面可见**: `_mat_solid` 默认 CULL_BACK, 而这些四边形是每帧按
		##   `perp` 现算顶点的 —— 头尾方向一变绕向就翻, 整条带子会被剔掉。
		##   (2026-08-09 实拍: 画面上只剩两个灰块, 那其实是每跳的落点水花, 带子一节都没显示。)
		wm.cull_mode = BaseMaterial3D.CULL_DISABLED
		## 头亮尾淡靠**顶点色**(写了得有人读 ⇒ 必须开 vertex_color_use_as_albedo)
		wm.vertex_color_use_as_albedo = true
		mi.material_override = wm
		root.add_child(mi)
		quads.append(mi)
	root.set_meta("path_len", path_length(pts))
	_fx.append({"node": root, "t": 0.0,
		"life": EqArcaneBatch.wave_hop_delay(pts.size() - 2) + WATER_TAIL_SEC,
		"kind": "water", "pts": pts, "chain": chain, "quads": quads, "splashed": 0})
	return root


## 落点溅水: 一圈贴地小环 + 几颗向外弹的水滴。
func _water_splash(at: Vector2) -> void:
	if not _has_world():
		return
	var rng: RandomNumberGenerator = battle._juice_rng
	_ring_fx(at, WATER_SPLASH_PX, COL_WAVE, WATER_SPLASH_SEC, "splash")
	for _k in range(WATER_SPLASH_DROPS):
		var bm := BoxMesh.new()
		var sz: float = WATER_DROP_PX * 0.8 * float(battle.WS)
		bm.size = Vector3(sz, sz, sz)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = _mat_solid(COL_WATER, 12)
		var ang: float = rng.randf() * TAU
		mi.position = battle._world_pos(at, 0.35)
		_adopt(mi, "splash")
		_fx.append({"node": mi, "t": 0.0, "life": WATER_SPLASH_SEC, "kind": "drop",
			"p0": at, "dir": Vector2(cos(ang), sin(ang)),
			"vx": WATER_SPLASH_PX * (0.5 + rng.randf()), "vy": 1.6 + rng.randf()})


# ══════════════════════════════════════════════════════════════════
#  §驱动与撤场
# ══════════════════════════════════════════════════════════════════

func _ring_fx(pos2d: Vector2, radius_px: float, col: Color, sec: float, kind: String) -> Node3D:
	if not _has_world():
		return null
	var mi := _node(_ring_mesh(), _mat(col, 9), battle._world_pos(pos2d, 0.0), kind)
	mi.scale = Vector3(0.001, 1.0, 0.001)
	mi.set_meta("radius_px", radius_px)
	_fx.append({"node": mi, "t": 0.0, "life": sec, "kind": kind, "r": radius_px})
	return mi


## 每帧推进。★纯同步, 门禁可以喂任意 delta; 不依赖 tween。
func tick(delta: float) -> void:
	if delta <= 0.0 or _fx.is_empty():
		return
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		var n = f.get("node", null)
		if not is_instance_valid(n):
			_fx.remove_at(i)
			continue
		f["t"] = float(f["t"]) + delta
		var t: float = float(f["t"])
		var life: float = maxf(0.001, float(f["life"]))
		var k: String = str(f["kind"])
		match k:
			"stele":
				var slab = f.get("slab", null)
				if is_instance_valid(slab):
					var h: float = STELE_H_PX * float(battle.WS)
					var fr: float = rise_frac(t, RISE_SEC)
					## 碑从地下顶上来: 站定时中心在 h/2, 冒头时中心在 −h/2
					(slab as Node3D).position.y = h * (fr - 0.5)
				if t >= life:
					_free_fx(i)
			"slamedge":
				# 硬前沿: 半径走 Sedov, **前 SLAM_EDGE_HOLD 满亮**, 之后才收 ——
				# 线性淡出会让"冲到最远"的那一刻正好看不见(本轮第 N 次同一个病)。
				var er: float = blast_radius(t, life, float(f.get("r", 100.0))) * float(battle.WS)
				(n as Node3D).scale = Vector3(maxf(0.001, er), 1.0, maxf(0.001, er))
				var eq: float = clampf(t / life, 0.0, 1.0)
				_set_alpha(n, 1.0 if eq <= SLAM_EDGE_HOLD 					else clampf((1.0 - eq) / maxf(0.001, 1.0 - SLAM_EDGE_HOLD), 0.0, 1.0))
				if t >= life:
					_free_fx(i)
			"pulse", "slam":
				var rp: float = float(f.get("r", 100.0))
				var r: float = (blast_radius(t, life, rp) if k == "slam" else pulse_radius(t, life, rp))
				var s: float = maxf(0.001, r * float(battle.WS))
				(n as Node3D).scale = Vector3(s, 1.0, s)
				_set_alpha(n, 1.0 - clampf(t / life, 0.0, 1.0))
				if t >= life:
					_free_fx(i)
			"keepalive":
				## 粒子节点自己管颜色/寿命, 这里只负责到点回收 —— 千万别写 alpha,
				## 统一的 `_set_alpha` 会把 GPUParticles3D 的 draw_pass 材质改坏。
				if t >= life:
					_free_fx(i)
			"crestring":
				## 半径按 Sedov(r ∝ t^0.4)往外推, 每段浪冠自己播帧 ⇒ **环在扩 + 浪在碎**
				var cu: float = clampf(t / life, 0.0, 1.0)
				var cr: float = blast_radius(t, life, float(f.get("r", 100.0)))
				var ca: float = 1.0 if cu < 0.55 else (1.0 - (cu - 0.55) / 0.45)
				for ch in (n as Node3D).get_children():
					if not (ch is Sprite3D):
						continue
					var cspr := ch as Sprite3D
					var cang: float = float(cspr.get_meta("ang", 0.0))
					var cpt: Vector2 = Vector2(cos(cang), sin(cang)) * cr
					cspr.position = battle._world_pos(
						Vector2(f["c"]) + cpt, CREST_H_M * 0.5) - (n as Node3D).position
					cspr.frame = (int(t * CREST_FPS) + int(cang * 3.0)) % CREST_SHEET_FRAMES
					cspr.modulate.a = ca
				if t >= life:
					_free_fx(i)
			"splashsheet":
				## 逐帧播 + 同时铺开(素材给表面运动, 代码给扩散 —— 见建它那段的注释)
				var su: float = clampf(t / life, 0.0, 1.0)
				var sspr := n as Sprite3D
				sspr.frame = mini(SPLASH_SHEET_FRAMES - 1, int(su * float(SPLASH_SHEET_FRAMES)))
				sspr.pixel_size = float(f.get("px0", 0.01)) * (0.45 + 0.85 * su)
				## holdfade: 前 60% 满亮再收(短命特效从出生就淡是本轮的老毛病)
				sspr.modulate.a = 1.0 if su < 0.6 else (1.0 - (su - 0.6) / 0.4)
				if t >= life:
					_free_fx(i)
			"talisman":
				var u = f.get("unit", null)
				if u is Dictionary and (u as Dictionary).get("alive", false):
					var p: Vector2 = (u as Dictionary)["pos"]
					var slot: int = int(f.get("slot", 0))
					var slots: int = maxi(1, int(f.get("slots", 1)))
					p.x += talisman_fan_dx(slot, slots)
					(n as Node3D).position = battle._world_pos(p, TALISMAN_Y + bob_offset(t) * float(battle.WS))
					## ★每帧重新对准镜头 —— 相机会跟着战况平移/缩放, 只在建的时候对一次,
					##   镜头一动就又斜了(而"斜"到极限就是旧版那种整张消失)。
					var extra_roll: float = (float(int(f.get("slot", 0))) - float(maxi(1, int(f.get("slots", 1))) - 1) * 0.5) * TALISMAN_FAN_ROLL
					(n as Node3D).basis = face_basis(_cam_forward(), talisman_roll(t) + extra_roll)
				if t >= life or not (u is Dictionary) or not (u as Dictionary).get("alive", false):
					_free_fx(i)
					## 掉一张之后剩下的要补位, 否则扇形留洞
					_reflow_talismans(u)
			"water":
				# ★★水流带: 头走抛物线, 身体**逐段滞后**追头, 并把节距拉回静止值(弧长恒定)。
				#   这四条(连续形体/逐段滞后/弧长恒定/头粗尾细+行波)才是"水流感"的来源,
				#   一簇离散颗粒做不出来 —— 那是一袋点在飞。
				var wpts: Array = f.get("pts", [])
				var nseg: int = maxi(1, wpts.size() - 1)
				var seg_i: int = 0
				var seg_q: float = 0.0
				var prev_t: float = 0.0
				for si2 in range(nseg):
					var end_t: float = EqArcaneBatch.wave_hop_delay(si2)
					if t < end_t or si2 == nseg - 1:
						seg_i = si2
						seg_q = clampf((t - prev_t) / maxf(0.001, end_t - prev_t), 0.0, 1.0)
						break
					prev_t = end_t
				var done: int = int(f.get("splashed", 0))
				while done < nseg and t >= EqArcaneBatch.wave_hop_delay(done):
					_water_splash(wpts[done + 1])
					done += 1
				f["splashed"] = done
				# ① 头: 走这一跳的抛物线(真高度变化)
				var a2: Vector2 = wpts[seg_i]
				var b2: Vector2 = wpts[seg_i + 1]
				var head_p: Vector2 = a2.lerp(b2, seg_q)
				var peak_m: float = a2.distance_to(b2) * ARC_PEAK_FRAC * float(battle.WS)
				var head_h: float = 0.45 + arc_height(seg_q, peak_m)
				var chain: Array = f.get("chain", [])
				if chain.is_empty():
					continue
				(chain[0] as Dictionary)["p"] = head_p
				(chain[0] as Dictionary)["h"] = head_h
				# ② 身体: 逐段滞后追前一节, 再把节距拉回 FLOW_REST_PX(弧长恒定)
				for wk in range(1, chain.size()):
					var me: Dictionary = chain[wk]
					var ahead: Dictionary = chain[wk - 1]
					var mp: Vector2 = me["p"]
					var ap: Vector2 = ahead["p"]
					mp = mp.lerp(ap, FLOW_LAG)
					var d: Vector2 = mp - ap
					var dl: float = d.length()
					if dl > 0.001:
						mp = ap + d / dl * FLOW_REST_PX      # ← 弧长恒定
					else:
						mp = ap + Vector2(FLOW_REST_PX, 0.0)
					me["p"] = mp
					me["h"] = lerpf(float(me["h"]), float(ahead["h"]), FLOW_LAG)
				# ③ 画: 相邻两节之间一块四边形, 头粗尾细; 行波沿身体往后跑
				var quads: Array = f.get("quads", [])
				for k2 in range(quads.size()):
					var qn = quads[k2]
					if not is_instance_valid(qn):
						continue
					var c0: Dictionary = chain[k2]
					var c1: Dictionary = chain[k2 + 1]
					var p0: Vector2 = c0["p"]
					var p1: Vector2 = c1["p"]
					var dir2: Vector2 = p1 - p0
					if dir2.length() < 0.001:
						dir2 = Vector2.RIGHT
					var perp: Vector2 = Vector2(-dir2.y, dir2.x).normalized()
					var f0: float = float(k2) / float(maxi(1, quads.size()))
					var f1: float = float(k2 + 1) / float(maxi(1, quads.size()))
					var w0: float = lerpf(FLOW_HEAD_PX, FLOW_TAIL_PX, f0)
					var w1: float = lerpf(FLOW_HEAD_PX, FLOW_TAIL_PX, f1)
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					var v: Array = [
						battle._world_pos(p0 + perp * w0, float(c0["h"])),
						battle._world_pos(p1 + perp * w1, float(c1["h"])),
						battle._world_pos(p1 - perp * w1, float(c1["h"])),
						battle._world_pos(p0 - perp * w0, float(c0["h"]))]
					## 沿身体的不透明度: 头 1.0 → 尾 0.15(一股水的头是实的, 尾巴散开)
					var a0v: float = lerpf(1.0, 0.15, f0)
					var a1v: float = lerpf(1.0, 0.15, f1)
					var vc: Array = [
						Color(1, 1, 1, a0v), Color(1, 1, 1, a1v),
						Color(1, 1, 1, a1v), Color(1, 1, 1, a0v)]
					for idx in [0, 1, 2, 0, 2, 3]:
						st.set_color(vc[idx])
						st.add_vertex(v[idx])
					(qn as MeshInstance3D).mesh = st.commit()
					# 行波: 高光沿身体往后跑 ⇒ 水面在"流"而不是整条一个色
					var ph: float = fposmod(f0 + t * FLOW_WAVE_SPD, 1.0)
					var lit: float = pow(1.0 - ph, 3.0)
					var m2 = (qn as MeshInstance3D).material_override
					if m2 is StandardMaterial3D:
						(m2 as StandardMaterial3D).albedo_color = 							COL_WATER_DEEP.lerp(COL_WATER, 0.35 + 0.65 * lit)
				if t >= life:
					_free_fx(i)
			"drop":
				# 溅出的水滴: 自己走一条小抛物线落回地面
				# ⚠ **负的 t = 还没轮到它起飞**, 必须显式判 —— `clampf(t/life,0,1)` 会把它钳成 0,
				#   于是这颗水滴会**满亮地堆在落点**等着, 错开等于没做。
				#   (082 贝壳串、085 龟能微粒踩过同一个坑, 这是第三次。)
				if t < 0.0:
					_set_alpha(n, 0.0)
					continue
				var dq: float = clampf(t / life, 0.0, 1.0)
				var dp: Vector2 = (f["p0"] as Vector2) + (f["dir"] as Vector2) * float(f["vx"]) * dq
				var dh: float = maxf(0.05, float(f["vy"]) * dq - 4.2 * dq * dq)
				(n as Node3D).position = battle._world_pos(dp, dh)
				_set_alpha(n, 1.0 - dq * dq)
				if t >= life:
					_free_fx(i)
			"leap":
				# ★三样各管一件事, 全部跟着**真实滞空高度** `u["height"]` 走
				#   (那是主循环 airborne 积分出来的数 —— 不另跑一条曲线, 演出与物理天然同步)
				var lu = f.get("unit", null)
				var hm: float = float((lu as Dictionary).get("height", 0.0)) if lu is Dictionary else 0.0
				var q: float = clampf(t / life, 0.0, 1.0)
				if lu is Dictionary:
					(n as Node3D).position = battle._world_pos((lu as Dictionary)["pos"] as Vector2, 0.0)
				## ★预警圈钉在【落点】: root 跟着龟走(影子要跟), 所以这里给 warn 一个反向偏移,
				##   让它在世界里停在 dest 上。用户点名"预警区是落点的范围, 不是起跳的"。
				var lwarn = f.get("warn", null)
				if is_instance_valid(lwarn) and f.has("dest"):
					(lwarn as Node3D).position = battle._world_pos(f["dest"] as Vector2, 0.0) \
						- (n as Node3D).position
				var lsh = f.get("shadow", null)
				if is_instance_valid(lsh):
					var ss: float = LEAP_SHADOW_PX * 0.5 * leap_shadow_scale(hm, LEAP_APEX_M) * float(battle.WS)
					(lsh as Node3D).scale = Vector3(ss, 1.0, ss)
				var lw = f.get("warn", null)
				if is_instance_valid(lw):
					# ★半径**不变**(就是真实砸落范围); "要来了"靠**电弧越来越密越来越亮**表达,
					#   不靠缩圈 —— 缩圈会被读成"范围在变小", 那是假消息。
					## ★★2026-08-09: 电弧改成**逐帧播精灵表**, 不再"每 0.07 秒整批 queue_free 重生"。
					##   旧做法是拿"随机重排折线"冒充动画 —— 那是噪声, 不是变形。
					##   现在每段各自推进自己的帧号(起始帧已随机), 越接近落地播得越快、越亮。
					f["warn_t"] = float(f.get("warn_t", 0.0)) + delta
					var spd: float = ARC_SHEET_FPS * (1.0 + 1.6 * q)     # 临近落地: 噼啪加快
					var bright: float = 0.45 + 0.55 * q
					for ch in (lw as Node3D).get_children():
						if ch is Sprite3D:
							var sp3 := ch as Sprite3D
							sp3.frame = int(floor(float(f["warn_t"]) * spd + float(sp3.get_meta("f0", 0)))) % ARC_SHEET_FRAMES
							sp3.modulate.a = bright
						elif ch is Node3D:
							_set_alpha(ch, bright)
				## ★正常情况不看 life —— 见建它那段的注释: 只有真实落地(`drop_leap`)或兜底才收。
				##   **例外**: 携带者半空阵亡(`orphan`)⇒ 永远等不到落地事件, 改按自然寿命走完就收
				##   (用户 2026-08-13:「预警特效还是持续到正常消失, 只是没有拍地和击飞」)。
				if bool(f.get("orphan", false)) and t >= life:
					_free_fx(i)
				elif t >= float(f.get("watchdog", life * 3.0 + 2.0)):
					_free_fx(i)
			_:
				_set_alpha(n, 1.0 - clampf(t / life, 0.0, 1.0))
				if t >= life:
					_free_fx(i)


func _set_alpha(n, a: float) -> void:
	if n is MeshInstance3D:
		var m = (n as MeshInstance3D).material_override
		if m is StandardMaterial3D:
			var c: Color = (m as StandardMaterial3D).albedo_color
			(m as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0))
	elif n is Node3D:
		for ch in (n as Node3D).get_children():
			_set_alpha(ch, a)


func _free_fx(i: int) -> void:
	var f: Dictionary = _fx[i]
	var n = f.get("node", null)
	if is_instance_valid(n):
		(n as Node).queue_free()
	_fx.remove_at(i)


## 撤场: 全部释放。返回释放了几个(门禁数它)。
func clear() -> int:
	var n: int = 0
	for x in _owned:
		if is_instance_valid(x):
			(x as Node).queue_free()
			n += 1
	_owned.clear()
	_fx.clear()
	## ★缓存一并放掉: 不放的话进程退出时 Godot 刷
	##   `RID allocations of type DummyMesh/DummyTexture were leaked at exit`
	##   (relic_eq_vfx.gd:717 记的同款坑)。下次要用会 lazy 重建, 不影响功能。
	_mesh_ring = null
	_tex_talisman = null
	return n


## 还活着的本层节点数(可按 kind 过滤) —— 门禁量真实对象用。
func alive_count(kind: String = "") -> int:
	var n: int = 0
	for x in _owned:
		if not is_instance_valid(x):
			continue
		if kind != "" and str((x as Node).get_meta(META_KEY, "")) != kind:
			continue
		n += 1
	return n
