class_name VenomDroneVfx
extends RefCounted
## venom_drone_vfx.gd — 092【剧毒飞行物】的演出层 (方案书 docs/plans/20260805-装备逐件重做.md §0.5 ★092)
##
## ══════════════════════════════════════════════════════════════════════
##  ★为什么不是"放个绿点飞 + 画几个绿圈"
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-08-05:「要触手水准」。触手立的第 2 条判据是 **「形态要有物理模型, 不是凑形状」**。
## 这件**一张参考素材都没有**, 所以触手那套的第 1 条(逐帧量参考做成包络表)无从下手 ——
## 走的是 `shockwave_vfx.gd` 那条路: **用可验证的物理规律当判据, 而不是"我调得像"**。
##
## 本文件四条形态全部是闭式解, 一个手调系数都没有。门禁验的是这几条**性质**
## (线性关系 / 守恒量 / 相位滞后 / 曲率上界), 手调出来的曲线一条都过不了。
##
## ── ① 毒雾: 二维高斯烟团 + 一阶衰减 (扩散方程的解析解) ────────────────
##   ∂C/∂t = D∇²C − C/τ    的点源解:
##       σ²(t) = σ₀² + 2Dt                       ← **半径 ∝ √t**(湍流扩散律)
##       C(r,t) = C₀·(σ₀²/σ²(t))·e^(−t/τ)·e^(−r²/2σ²)
##
##   两条可验证性质(门禁 ②):
##     · **σ² 对 t 严格线性**, 斜率恒为 2D —— 这就是 √t 律的等价陈述, 而且是**精确**的
##       (拿 `t^0.5` 硬凑的曲线过不了"σ²−σ₀² 与 t 成正比"这条)。
##     · **守恒量 `C_peak(t)·σ²(t)·e^(t/τ) ≡ C₀σ₀²`** —— 这是"总质量守恒 + 一阶衰减
##       可分离"的直接后果。峰值与半径被**焊死成一个量**, 谁被单独手调都会红。
##
##   ★★"生成 → 铺开 → 变淡" 这三段不是我分的段, 是解自己给的:
##     σ(t) 单调涨(铺开)、C_peak(t) 单调跌(变淡), 而**有效半径**
##       R(t) = σ(t)·√(2·ln(C_peak(t)/C_min))
##     是**先涨后跌**的 —— 因为烟团铺开的速度终究追不上浓度衰减的速度。
##     取 C_min = C_peak(4.0) ⇒ **R(4.0) 精确为 0**, 即"寿命 4 秒"不是拿计时器掐掉的,
##     是浓度自己跌到看不见的那一刻(规格写的 4 秒因此是解的边界条件, 不是外挂的截断)。
##
##   ★★★**尺子必须匹配被测概念**(用户判据 5·触手那次拿投影臂长量"拍了几次"):
##     伤害判定用的半径 **就是** R(t), 而渲染出来的 alpha 是
##       a(r,t) = C_peak(t)·e^(−r²/2σ²)
##     两者共用同一个 C(r,t) ⇒ **毒雾"看得见的边界"与"打得到的边界"是同一条等值线**
##     (a = C_min 处)。门禁 ⑤ 直接从真实网格顶点 + 真实材质反解这条等值线, 与 sim 用的
##     半径对比 —— 不是把公式在测试里抄第二遍。
##
## ── ② 飞行物转向: Dubins 载具 (最小转弯半径) ─────────────────────────
##   航向角速率有硬上限 ω_max ⇒ **最小转弯半径 R_min = V/ω_max**, 轨迹曲率 |κ| ≤ 1/R_min。
##   这就是"转向时应该有惯性"的物理表述: 瞬间改向 = 曲率无穷大 = R_min 为 0。
##   ★门禁 ③ 量的是**真实模拟出来的轨迹**的曲率上界, 不是读这个常量。
##
## ── ③ 扇翅与体态起伏: 受迫振子 ────────────────────────────────────────
##   翅膀行程角 φ(t) = A·sin(2πf·t); 升力的振荡部分 ∝ sin(2πf·t);
##   机体在竖直方向是被这个振荡力驱动的自由质点 ⇒ ÿ ∝ sin(2πf t) ⇒
##       y(t) = −(F/m)/(2πf)² · sin(2πf·t)
##   两条可验证性质(门禁 ④):
##     · **起伏与行程角恒定反相**(升力最大时机体在最低点 —— 二次积分带来的 π 相移)
##     · **起伏幅度 ∝ f^(−2)** —— 扇得越快, 机体反而抖得越轻。
##       这一条是"随手写个 sin 乘个系数"绝对给不出来的。
##
## ── ④ 尾部: 行波 + 逐段滞后 ──────────────────────────────────────────
##   被动柔性尾被根部驱动 ⇒ 挠度沿弧长传播:  y(s,t) = a(s)·sin(2πf·t − k·s)
##   · 尖端相对根部**恒定滞后 k 弧度** ⇒ 时间滞后 k/(2πf) 秒
##   · 零点沿弧长以相速 c = 2πf/k (归一弧长/秒) 行进
##   · 振幅 a(s) ∝ s^p 单调向尖端增大(根部僵硬)
##   ⇒ memory [[fb-3d-quality-bar-tentacle]] 说的"行波 / 逐段滞后"。
##
## ── ⑤ 剧毒缓速的累积可见性 ───────────────────────────────────────────
##   20 层要**数得出来**: 脚下的环上挂 n 个刻痕(n = 当前层数), 而不是"越来越绿"。
##   ★网格**只在层数变化时**重建(每单位最多 4 次/秒), 不是每帧 —— 见 `apply_ring`。
##
## ══════════════════════════════════════════════════════════════════════
##  ★2026-08-09 逐件重做 —— 实拍(VFXLAB p2eq_092, zoom 1.0 实战镜头)抓出三处
## ══════════════════════════════════════════════════════════════════════
## 上面那套物理**一条都没错**, 错在"物理正确"与"读得出来"是两回事。三处都是实拍+探针定的根因:
##
## ── 甲【"每 0.25 秒留一团"在画面上根本不成立】 ─────────────────────────
##   探针算的不是感觉, 是数: 飞行物 110 码/秒 × 0.25 秒 ⇒ 相邻两团**心距 27.5 码**,
##   而 σ(0)=26 → σ(4)=55.5 ⇒ **心距/σ = 1.06 一路掉到 0.50**。
##   两个等幅高斯要 **心距 > 2σ** 才会在中间出现凹陷 —— 这里连一半都不到。
##   ⇒ 把 16 团沿航线叠起来量 alpha 剖面: **局部极小值 0 个**。
##   也就是说旧演出**在数学上就不可能**读成"一团一团", 它必然是一条光滑的绿脊。
##   实拍完全对上: 屏幕上是一片模糊的绿油污, 数不出团数。
##
## ── 乙【淡出病: 4 秒的东西, 前 1 秒就丢掉 2/3 亮度】 ───────────────────
##   单团渲染 alpha = 0.45·C_peak(t): t=0 → 0.450 / t=1 → 0.151 / t=2 → 0.065。
##   而它 t=2 时的**伤害半径正是最大值 72.6 码**。⇒ 后 3 秒是"看不见但照样上毒"。
##
## ── 丙【"看得见的边界 == 打得到的边界"取在 alpha=0.016 这条等值线上】 ──
##   数学上成立, 但 1.6% 不透明度**在人眼阈值以下** ⇒ 这条自证性质是真的, 玩家却一点用都没有。
##
## ★★三处的**同一个解**: 给每一团补一圈【判定边界环 rim】, 半径**就是** `fog_radius(t)`。
##   · 甲: 每团一个可数的轮廓 ⇒ 沿航线的合成剖面从 0 个局部极小值变成十几个(门禁 ⑤f 量的就是这个)
##   · 乙: 环的 alpha 走 **holdfade**(前 62% 寿命恒定满亮, 之后才线性退场), 不再一出生就暴跌
##   · 丙: 那条等值线终于**画出来了**, 而且是全团最亮的一圈 ⇒ 玩家看得见"踩进这个圈就中毒"
##   ★haze(高斯烟团)一个数都没动 —— 上面那套闭式解与它的全部门禁原样留着。rim 是加法。
##
## ── 丁【飞行物读作"一颗绿橄榄 + 一片灰三角"】 ─────────────────────────
##   染色法实测(zoom 1.0 / 1280×720): 躯干 **32×15 px**、两只翅膀合计只占一个
##   **12×27 px 的竖条**、尾巴 23~35 px 却是全身最亮。三条结论:
##   · 两翅**同相且翅尖被 sin φ 抬到 +Y** ⇒ 从 52° 俯角看**完全重叠成一个三角**, 读作鲨鱼鳍
##   · 本体是个光滑椭球, 无头/无触角/无体节 ⇒ 没有方向感
##   · 加性发光的尾巴是全身最亮最尖的部分 ⇒ **被读成头**, 方向感是反的
##   · 毒绿本体 + FLY_H 1.55 米(龟身高 2.0) ⇒ 它压在绿壳龟的**背**上, 同色同位糊成一坨
##   ⇒ 重做成真的【毒蛾】: 头/胸/腹三段 + 触角 + 每侧前后两片蛾翅(翅尖**保持横向展开**,
##     sin φ 只负责上下扇), 体色改**深紫红**(与绿壳龟/绿毒雾都分得开), 尾巴压暗退到腹后,
##     飞高改 2.35 米(真的在头顶上方)。
##
## ── 技术路线 ────────────────────────────────────────────────────────
## 程序化 `ArrayMesh` / `ImmediateMesh` 现算, **零素材**(同 shockwave_vfx / tentacle_vfx)。
## 用户素材铁律「新内容一律新素材, 不许拿别件的立绘顶替」—— 程序化几何不产出图, 天然合规。
##
## ⚠ 朝向坑 (memory [[fb-axis-y-plus-rotation-cancels]]): 本文件**不用 Sprite3D**,
##   直接建世界坐标顶点, 没有 `axis=AXIS_Y` 与 `rotation.x=-90` 互相抵消那层歧义。
##   贴地的东西一律 y = GROUND_Y 的水平顶点, 门禁量 |三角面法线·上| ≈ 1.000。


# ══════════════════════════════════════════════════════════════════
#  §物理常数 —— 全部进闭式解, 没有一个是"调得像"调出来的
# ══════════════════════════════════════════════════════════════════

## 毒雾寿命(秒)。★规格值。它同时是浓度阈值 C_min 的定义点 ⇒ R(FOG_LIFE) 精确为 0。
const FOG_LIFE := 4.0
## 释放时的高斯烟团标准差(码)
const FOG_SIG0 := 26.0
## 湍流扩散系数(码²/s)。σ²(t) = σ₀² + 2Dt
const FOG_D := 300.0
## 一阶衰减(沉降/分解)时间常数(秒)
const FOG_TAU := 2.2
## 网格画到 3σ。★必须 ≥ max R(t)/σ(t) = R(0)/σ(0) = 2.582, 否则"打得到的地方没画出来"
const FOG_RHO_MAX := 3.0
## 毒雾网格分段
const FOG_RINGS := 7
const FOG_SEGS := 32

## ── 判定边界环 rim (2026-08-09 重做·见文件头【甲乙丙】) ────────────────
## 环带的内缘占有效半径的比例。1.0 = 外缘 = **判定边界本身**。
## 0.88 ⇒ 环厚约 0.12·R ≈ 8 码 ≈ 实战镜头下 5 px: 再细就闪, 再粗就糊成盘。
const RIM_IN := 0.88
## 环的满亮 alpha
const RIM_A := 0.55
## **holdfade**: 前这么大比例的寿命里恒定满亮, 之后才线性退场。
## ★这一条是治"淡出病"的唯一开关 —— 0 就退化成"一出生就线性淡出"(门禁 ⑤g 的反向验证点)。
const RIM_HOLD := 0.62
## 环的网格分段(三圈顶点: 内缘 0 → 中缘 1 → 外缘 0 的三角窗)
const RIM_SEGS := 40

## 飞行速度(码/秒)。★"缓慢的飞行": 龟的移速档位是 60~120(turtle_stats.ROLE_SPEC),
##   110 落在中上 —— 比慢龟快、比快龟慢, 读起来是"晃悠着飘", 不是导弹。
const DRONE_SPEED := 110.0
## 航向角速率上限(弧度/秒) ⇒ 最小转弯半径 = SPEED/TURN_RATE = 91.67 码
const DRONE_TURN_RATE := 1.2
## 巡航高度(米)。★2026-08-09 从 1.55 抬到 2.35: 龟身高 TARGET_BODY_H = 2.0 米,
## 1.55 米等于**趴在龟背上** —— 实拍里毒绿本体和绿壳龟糊成一坨, 分不出是两个东西。
const FLY_H := 2.35

## 扇翅频率(Hz)
const FLAP_HZ := 6.0
## 翅膀行程角幅值(弧度) —— 上下各 ~40°
const FLAP_AMP := 0.70
## 受迫振子的驱动强度(米·弧度⁻²·秒⁻²)。机体起伏幅度 = BOB_DRIVE/(2πf)²
## ⇒ f=6Hz 时 0.0422 m。★这一条的价值不在数值, 在于它**除以 (2πf)²** —— 见门禁 ④。
const BOB_DRIVE := 60.0

## 尾部: 分段数 / 尖端相对根部的相位滞后(弧度) / 振幅沿弧长的幂次 / 振幅(米)
const TAIL_SEG := 7
const TAIL_LAG := 2.4
const TAIL_P := 1.6
const TAIL_AMP := 0.22
## 尾根/尾尖在本体局部坐标里的 x(米)。局部 +X = 前进方向 ⇒ 尾巴挂在 −X 侧。
## ★2026-08-09 尾根从 −0.34 退到腹部末端之后(−0.62): 旧值让尾巴从**胸**的位置就长出来,
##   加上它是全身最亮的加性发光条 ⇒ 实拍里被读成"头"(方向感整个反了)。
const TAIL_X0 := -0.62
const TAIL_X1 := -1.24

## ── 蛾体三段(米)。局部 +X = 前进方向 ⇒ 头在 +X 侧、腹在 −X 侧 ──
## ★为什么要分三段: 一颗光滑椭球在 32×15 px 下没有任何方向信息(实拍读作"绿橄榄")。
##   头/胸/腹 + 触角 才让"哪边是前"一眼可读。
const HEAD_X := 0.30
const HEAD_R := Vector3(0.155, 0.145, 0.150)
const THORAX_X := 0.045
const THORAX_R := Vector3(0.260, 0.150, 0.170)
const ABDOMEN_X := -0.335
const ABDOMEN_R := Vector3(0.320, 0.108, 0.118)
## 触角: 根(相对头心)/尖(局部坐标)/半宽
const ANT_ROOT := Vector3(0.42, 0.055, 0.045)
const ANT_TIP := Vector3(0.74, 0.265, 0.175)
const ANT_W := 0.022

## 翅展(米·单侧)与弦长。★1.44 米总跨 ≈ 蛾的正常比例(体长 0.9 米)
const WING_SPAN := 0.72
const WING_CHORD := 0.34
## ★★翅尖的【横向展开】保底比例 —— 这一条是本次重做的关键。
##   旧写法 tip = (0, sin φ·SPAN, ±cos φ·SPAN): φ 一大, 翅尖就整个抬到 +Y,
##   两只翅在 52° 俯角下**完全重叠**成一个三角(染色法实测: 两翅合计只有 12×27 px 的竖条)。
##   现在横向分量恒在 [WING_KEEP, 1] 之间, sin φ 只管上下扇 ⇒ 两翅始终分居本体两侧。
const WING_KEEP := 0.80
## ★上下扇动的行程占翅展的比例(sin φ 的系数)。**0.30 不是"调小一点"**:
##   本作是 52° 俯视 ⇒ 一只【横着飞】的蛾, 它的翅展方向正好落在**屏幕竖直**(被压缩)那一轴上。
##   行程一大, 两只翅就一起被顶到本体正上方、在投影里重叠 —— 这正是旧版"鲨鱼鳍"的成因,
##   只把翅面改成四边形治不了。俯视视角下的正确读法是**从上往下看的蛾**: 双翅摊平在两侧,
##   扇动表现为小幅【上反角摆动】而不是大幅拍打。
const WING_LIFT := 0.30
## 后翅相对前翅的尺寸/位置
const HIND_K := 0.62
const HIND_X := -0.30

## ★毒雾的**显示增益**(不是把物理揉圆): 渲染 alpha = FOG_DRAW_A × C(r,t)/C₀。
##   一个【常数】增益同时缩放浓度与阈值 ⇒ 等值线一条不动, "看得见的边界 == 打得到的边界"
##   仍然精确成立(门禁 ⑤d 验的正是这条)。加它的理由是实拍出来的:
##   16 团加性叠在一起会把尾迹烧成一片白, 反而看不出"一团一团铺开"的层次。
const FOG_DRAW_A := 0.45

## ★本体【不用加性】—— 实拍教训: 本体 + 双翅 + 尾巴四层加性叠在一处直接饱和成白团,
##   翅和尾完全看不出来(比"没做动画"还糟)。改成:
##     · 躯干 = 不透明 MIX 的深紫红 ⇒ 有【剪影】, 能看出是个虫子
##     · 翅膀 = 半透明 MIX 的毒绿 ⇒ 昆虫翅本来就是透的, 扇动时能看见开合
##     · 尾巴 = 加性发光 ⇒ 它是毒雾的出口, 该亮 —— **但不能是全身最亮的**(见下)
##
## ★★2026-08-09 体色从毒绿改**深紫红**: 这是一件叫【毒蛾茧】的装备, 它的画面里同时有
##   ①绿壳龟 ②满地毒绿雾 ③黄绿脚环。本体再用毒绿, 三样全糊在一个色相里, 实拍中
##   飞行物压在龟背上根本分不出是两个东西。紫红是毒绿的补色 ⇒ 一眼分得开, 也仍然"读作毒"。
## ★头用【热品红】而不是和胸同深浅: 尾巴是加性发光的毒绿, 而 Rec.709 里绿的权重是红的 3.4 倍
##   ⇒ 深紫红的头在感知亮度上**打不过**一条绿尾巴, 视觉重心还是会跑到尾上(门禁 ⑫e 量的就是这个)。
const COL_HEAD := Color(0.98, 0.26, 0.68, 1.0)
const COL_THORAX := Color(0.44, 0.09, 0.34, 1.0)
const COL_ABDOMEN := Color(0.28, 0.06, 0.24, 1.0)
## 触角/复眼高光: 亮青 —— 全身唯一的冷色高光, 钉住"哪边是头"
const COL_ANTENNA := Color(0.55, 1.00, 0.86, 1.0)
const COL_WING := Color(0.62, 0.96, 0.40, 0.62)
## ★尾巴亮度压到 0.55: 旧的 (0.45,1.00,0.32,1.0) 加性发光是全身最亮最尖的部分,
##   实拍里被读成头。现在它退到腹后、暗于头部 ⇒ 视觉重心回到头。
const COL_TAIL := Color(0.34, 0.86, 0.30, 0.42)

## 剧毒缓速脚环: 半径(码) / 刻痕角宽(弧度) / 满层(20)时的环亮度
const RING_R := 46.0
const RING_MARK_W := 0.13
const RING_A_FULL := 0.85
## ★与 VenomDroneSystem.VSLOW_CAP 同值。此处**故意写死字面量**而不 import ——
##   门禁要能验"20 层封顶"这件事在两侧是一致的; 引用同一个常量 = 拿代码跟它自己比。
const RING_MARK_MAX := 20

## 贴地几何的离地高度(米)。地板在 y=0, 抬一点免 z-fighting
const GROUND_Y := 0.07

## 节点记账用的 meta 键(同 SynergyVfx.META_KEY 的做法: 程序生成的网格没有 resource_path,
## 按名字数不可靠, 一律打 meta)
const META_KEY := "venom_drone_vfx"

## 配色: 毒绿 / 尾焰青绿 / 脚环黄绿
const COL_FOG := Color(0.42, 0.92, 0.30, 1.0)
const COL_RING := Color(0.72, 0.98, 0.25, 1.0)
## 判定边界环: 比雾体更亮更黄, 才在一片绿雾里读得出"这是一圈边"
const COL_RIM := Color(0.68, 1.00, 0.34, 1.0)


var battle

## 缓存网格: 毒雾盘与本体都是【单位尺度】的, 每一团只差 scale 与材质 ⇒ 整局各建一次。
## ★存实例上不用 `static var`: static 的话进程退出时还挂着 ArrayMesh,
##   Godot 会报 `ERROR: N resources still in use at exit`(shockwave_vfx 实测过)。
var _cache_fog: ArrayMesh = null
var _cache_rim: ArrayMesh = null
var _cache_body: ArrayMesh = null


func _init(b) -> void:
	battle = b


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调, 不建节点、不等 tween (CLAUDE.md §3.5)
# ══════════════════════════════════════════════════════════════════

## 高斯烟团的标准差(码)。σ²(t) = σ₀² + 2Dt ⇒ σ ∝ √t (t 大时)
static func fog_sigma(t: float) -> float:
	return sqrt(FOG_SIG0 * FOG_SIG0 + 2.0 * FOG_D * maxf(t, 0.0))


## 中心浓度(归一到 t=0 时为 1)。质量守恒的 1/σ² 稀释 × 一阶衰减 e^(−t/τ)
static func fog_peak(t: float) -> float:
	var s2: float = fog_sigma(t) * fog_sigma(t)
	return (FOG_SIG0 * FOG_SIG0 / s2) * exp(-maxf(t, 0.0) / FOG_TAU)


## 浓度阈值 = 寿命末尾的中心浓度。★由它定义"看不见了" ⇒ R(FOG_LIFE) 精确为 0。
static func fog_a_min() -> float:
	return fog_peak(FOG_LIFE)


## 有效半径(码): 浓度等值线 C(r,t) = C_min 的位置。
## **先涨后跌**, 且在 t=FOG_LIFE 处精确归零。伤害判定与渲染边界共用这一条。
static func fog_radius(t: float) -> float:
	if t <= 0.0:
		t = 0.0
	if t >= FOG_LIFE:
		return 0.0
	var q: float = fog_peak(t) / fog_a_min()
	if q <= 1.0:
		return 0.0
	return fog_sigma(t) * sqrt(2.0 * log(q))


## 渲染 alpha(归一): a(r,t) = C_peak(t)·e^(−r²/2σ²)。
## ★门禁 ⑤ 用它反解等值线, 与 fog_radius 对账 —— 两者必须是同一个 C(r,t)。
static func fog_alpha_at(r: float, t: float) -> float:
	var s: float = fog_sigma(t)
	return fog_peak(t) * exp(-(r * r) / (2.0 * s * s))


# ── 判定边界环 rim (2026-08-09 重做) ──────────────────────────────────────
#  ★这三个函数是"看得见 == 打得到"从【数学等值线】变成【肉眼可见的一圈】的全部实现。
#    环的世界半径直接就是 `fog_radius(t)`(sim 判定用的那一条), 不是另算一份。

## 环带的径向剖面。ρ = r / R(t) ∈ [0,1]: 内缘 RIM_IN 处 0 → 中缘 1 → 外缘(判定边界)0。
## ★三角窗而不是硬边: 硬边在 5 px 宽的带子上会闪, 而且门禁没法从顶点色反解出剖面。
static func fog_rim_profile(rho: float) -> float:
	if rho <= RIM_IN or rho >= 1.0:
		return 0.0
	var m: float = (RIM_IN + 1.0) * 0.5
	if rho <= m:
		return (rho - RIM_IN) / (m - RIM_IN)
	return (1.0 - rho) / (1.0 - m)


## 环的亮度包络 —— **holdfade**: 前 RIM_HOLD 比例的寿命恒定满亮, 之后线性退到 0。
## ★为什么不跟着浓度走: 浓度 C_peak(t) 在 t=1 秒就只剩 1/3(见文件头【乙】),
##   而这团**照样在上毒**。判定边界的可见性必须跟着【寿命】走, 不能跟着浓度走。
static func fog_rim_alpha(t: float) -> float:
	if t <= 0.0:
		return RIM_A
	if t >= FOG_LIFE:
		return 0.0
	var k: float = t / FOG_LIFE
	if k <= RIM_HOLD:
		return RIM_A
	return RIM_A * (1.0 - (k - RIM_HOLD) / (1.0 - RIM_HOLD))


## 一团毒雾在半径 r 处的【合成显示亮度】= 高斯烟团(haze) + 判定边界环(rim)。
## ★门禁 ⑤f 拿它沿航线叠 16 团量"局部极小值有几个" —— 那就是"一团一团数不数得出来"。
##   旧演出(只有 haze)在这条尺子下是 **0 个**, 而且是数学上必然的(心距/σ ≤ 1.06 < 2)。
static func fog_draw_at(r: float, t: float) -> float:
	var v: float = FOG_DRAW_A * fog_alpha_at(r, t)
	var rr: float = fog_radius(t)
	if rr > 0.0:
		v += fog_rim_alpha(t) * fog_rim_profile(absf(r) / rr)
	return v


## Dubins 转向: 航向以不超过 ω_max 的角速率转向目标航向。返回新航向。
## ★这就是"惯性": 瞬间改向 = 曲率无穷大, 本函数把它钳在 1/R_min。
static func steer(hd: float, want: float, dt: float) -> float:
	var d: float = wrapf(want - hd, -PI, PI)
	var m: float = DRONE_TURN_RATE * maxf(dt, 0.0)
	return hd + clampf(d, -m, m)


## 最小转弯半径(码) = V/ω_max
static func min_turn_radius() -> float:
	return DRONE_SPEED / DRONE_TURN_RATE


## 翅膀行程角(弧度)。φ(t) = A·sin(2πf·t)
static func stroke(t: float, f: float = FLAP_HZ) -> float:
	return FLAP_AMP * sin(TAU * f * t)


## 受迫振子响应幅度(米) = 驱动/(2πf)²。★门禁 ④ 验 amp(f)·f² 与 f 无关。
static func bob_amp(f: float = FLAP_HZ) -> float:
	var w: float = TAU * maxf(f, 1e-6)
	return BOB_DRIVE / (w * w)


## 机体竖直起伏(米)。**与行程角恒定反相**(二次积分带来的 π 相移)。
static func bob(t: float, f: float = FLAP_HZ) -> float:
	return -bob_amp(f) * sin(TAU * f * t)


## 尾部挠度(米)。s ∈ [0,1] 是归一弧长(0=根 1=尖)。行波 + 逐段滞后。
static func tail_offset(s: float, t: float, f: float = FLAP_HZ) -> float:
	var ss: float = clampf(s, 0.0, 1.0)
	return TAIL_AMP * pow(ss, TAIL_P) * sin(TAU * f * t - TAIL_LAG * ss)


## 行波的相速(归一弧长/秒) = 2πf/k。零点沿尾巴以这个速度往尖端跑。
static func tail_phase_speed(f: float = FLAP_HZ) -> float:
	return TAU * f / TAIL_LAG


# ══════════════════════════════════════════════════════════════════
#  §几何 —— 程序化, 零素材
# ══════════════════════════════════════════════════════════════════

## 单位 σ 的贴地高斯盘(顶点 alpha = e^(−ρ²/2), ρ 画到 FOG_RHO_MAX)。
## ★网格是【σ 口径】的: 节点 scale = σ(t) ⇒ 世界半径 r 处的顶点 alpha 恒为 e^(−r²/2σ²),
##   再乘材质的 C_peak(t) 就精确等于 fog_alpha_at(r,t)。这是"看得见=打得到"的实现依据。
static func _build_fog_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(FOG_RINGS):
		var r0: float = float(i) / float(FOG_RINGS) * FOG_RHO_MAX
		var r1: float = float(i + 1) / float(FOG_RINGS) * FOG_RHO_MAX
		var a0: float = exp(-(r0 * r0) * 0.5)
		var a1: float = exp(-(r1 * r1) * 0.5)
		for j in range(FOG_SEGS):
			var t0: float = float(j) / float(FOG_SEGS) * TAU
			var t1: float = float(j + 1) / float(FOG_SEGS) * TAU
			var a := _flat_vert(r0, t0, a0)
			var b := _flat_vert(r1, t0, a1)
			var c := _flat_vert(r1, t1, a1)
			var d := _flat_vert(r0, t1, a0)
			_tri(st, a, b, c)
			_tri(st, a, c, d)
	st.commit(mesh)
	return mesh


## 单位半径的贴地环带(顶点 alpha = fog_rim_profile(ρ), ρ ∈ [RIM_IN, 1])。
## ★节点 scale = R(t) ⇒ 外缘恰好落在**判定边界**上。门禁 ⑤h 从真实顶点反解这条剖面。
static func _build_rim_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mid: float = (RIM_IN + 1.0) * 0.5
	# 三圈顶点: 内缘 RIM_IN(0) → 中缘 mid(1) → 外缘 1.0(0)。★与 fog_rim_profile 同一条剖面
	var rads: Array = [RIM_IN, mid, 1.0]
	var alps: Array = [0.0, 1.0, 0.0]
	for i in range(rads.size() - 1):
		var r0: float = float(rads[i])
		var r1: float = float(rads[i + 1])
		var a0: float = float(alps[i])
		var a1: float = float(alps[i + 1])
		for j in range(RIM_SEGS):
			var t0: float = float(j) / float(RIM_SEGS) * TAU
			var t1: float = float(j + 1) / float(RIM_SEGS) * TAU
			var a := _flat_vert(r0, t0, a0)
			var b := _flat_vert(r1, t0, a1)
			var c := _flat_vert(r1, t1, a1)
			var d := _flat_vert(r0, t1, a0)
			_tri(st, a, b, c)
			_tri(st, a, c, d)
	st.commit(mesh)
	return mesh


## 单位半径的椭球本体(靠节点 scale 压成扁虫身)
static func _build_body_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lat := 8
	var lon := 14
	for i in range(lat):
		var p0: float = float(i) / float(lat) * PI - PI * 0.5
		var p1: float = float(i + 1) / float(lat) * PI - PI * 0.5
		for j in range(lon):
			var t0: float = float(j) / float(lon) * TAU
			var t1: float = float(j + 1) / float(lon) * TAU
			var a := _sph_vert(p0, t0)
			var b := _sph_vert(p1, t0)
			var c := _sph_vert(p1, t1)
			var d := _sph_vert(p0, t1)
			_tri(st, a, b, c)
			_tri(st, a, c, d)
	st.commit(mesh)
	return mesh


static func _sph_vert(phi: float, th: float) -> Array:
	var p := Vector3(cos(phi) * cos(th), sin(phi), cos(phi) * sin(th))
	## 腹面亮一点(毒液囊) —— 纯视觉梯度, 不参与任何判定
	var a: float = lerpf(1.0, 0.45, clampf(sin(phi) * 0.5 + 0.5, 0.0, 1.0))
	return [p, Color(1, 1, 1, a)]


static func _flat_vert(r: float, th: float, a: float) -> Array:
	return [Vector3(r * cos(th), GROUND_Y, r * sin(th)), Color(1, 1, 1, a)]


static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for v in [a, b, c]:
		st.set_color(v[1])
		st.add_vertex(v[0])


## 加性发光材质(零素材, 顶点色当亮度)。
## ⚠ render_priority 在【材质】上, MeshInstance3D 没有这个属性。
## ⚠ 一律用 `material_override` 而不是 `set_surface_override_material` ——
##   后者在 --headless 的 dummy renderer 下每设一次刷一条
##   `ERROR: Parameter "material" is null.`(shockwave_vfx 实测), 而那条不在 FATAL 正则里。
static func _mat(no_depth: bool, prio: int, additive: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.no_depth_test = no_depth
	m.render_priority = prio
	m.albedo_color = Color(1, 1, 1, 0)
	return m


# ══════════════════════════════════════════════════════════════════
#  §毒雾节点
# ══════════════════════════════════════════════════════════════════

## 建一团毒雾的节点(**已挂进 _world**)。返回 null = 世界不在(R2 守卫)。
##
## ★2026-08-09 从"一个 MeshInstance3D"改成"一个 Node3D 挂两片"(见文件头【甲乙丙】):
##   · `haze` = 原来那张高斯烟团盘, **一个数都没改**(scale=σ(t)、alpha=0.45·C_peak(t))
##   · `rim`  = 新增的【判定边界环】, scale = fog_radius(t) = sim 真正用来判命中的半径
##   打 meta 的仍然只有 root ⇒ `_count("venom_fog")` 这类按 meta 数的记账口径不变。
func make_fog(pos2d: Vector2):
	if battle == null or not is_instance_valid(battle._world):
		return null
	if _cache_fog == null:
		_cache_fog = _build_fog_mesh()
	if _cache_rim == null:
		_cache_rim = _build_rim_mesh()
	var root := Node3D.new()
	root.set_meta(META_KEY, "venom_fog")
	root.position = battle._world_pos(pos2d, 0.0)
	var haze := MeshInstance3D.new()
	haze.mesh = _cache_fog
	haze.material_override = _mat(true, 8)
	haze.name = "haze"
	root.add_child(haze)
	var rim := MeshInstance3D.new()
	rim.mesh = _cache_rim
	rim.material_override = _mat(true, 9)
	rim.name = "rim"
	root.add_child(rim)
	battle._world.add_child(root)
	apply_fog(root, 0.0)
	return root


## 把 t 时刻的形态写到真实节点上 —— **纯同步**, 门禁直接喂任意 t。
## 演出侧每帧调它、门禁侧也调它, 只有这一份实现。
func apply_fog(root, t: float) -> void:
	if not is_instance_valid(root):
		return
	var haze = root.get_node_or_null("haze")
	if is_instance_valid(haze):
		## 世界尺度: 码 → 米
		var s: float = maxf(fog_sigma(t) * float(battle.WS), 1e-4)
		haze.scale = Vector3(s, 1.0, s)
		## ★渲染 alpha = 显示增益 × 归一浓度。常数增益不动等值线(见 FOG_DRAW_A 那段)。
		var a: float = FOG_DRAW_A * fog_peak(t)
		(haze.material_override as StandardMaterial3D).albedo_color = Color(
			COL_FOG.r, COL_FOG.g, COL_FOG.b, a)
	var rim = root.get_node_or_null("rim")
	if not is_instance_valid(rim):
		return
	## ★★环的世界半径 **就是** sim 判定用的 `fog_radius(t)` —— 不是另算一份"看着差不多"的。
	##   门禁 ⑤e-rim 量的是这个真实节点的 scale, 不是重抄一遍公式。
	var rr: float = fog_radius(t)
	rim.visible = rr > 0.0
	if rr <= 0.0:
		return
	var rs: float = rr * float(battle.WS)
	rim.scale = Vector3(rs, 1.0, rs)
	(rim.material_override as StandardMaterial3D).albedo_color = Color(
		COL_RIM.r, COL_RIM.g, COL_RIM.b, fog_rim_alpha(t))


# ══════════════════════════════════════════════════════════════════
#  §飞行物本体
# ══════════════════════════════════════════════════════════════════

## 建一只飞行物(**已挂进 _world**)。返回 null = 世界不在。
func make_drone():
	if battle == null or not is_instance_valid(battle._world):
		return null
	if _cache_body == null:
		_cache_body = _build_body_mesh()
	var root := Node3D.new()
	root.set_meta(META_KEY, "venom_drone")
	## ── 蛾体三段 ── 全用同一个单位球网格, 只差 scale/position/颜色 ⇒ 零额外网格。
	## ★节点名 `body` 保留给【胸】: 门禁 ⑭ 的反面断言(本体不平铺)按名字取它。
	_add_seg(root, "abdomen", ABDOMEN_X, ABDOMEN_R, COL_ABDOMEN, 5)
	_add_seg(root, "body", THORAX_X, THORAX_R, COL_THORAX, 6)
	_add_seg(root, "head", HEAD_X, HEAD_R, COL_HEAD, 7)
	## 触角: 全身唯一的冷色高光, 静态几何(不随扇翅变) ⇒ 建一次就够
	var ant := MeshInstance3D.new()
	ant.mesh = ImmediateMesh.new()
	ant.material_override = _mat(false, 8)
	(ant.material_override as StandardMaterial3D).albedo_color = COL_ANTENNA
	ant.name = "antenna"
	root.add_child(ant)
	var ia := ant.mesh as ImmediateMesh
	ia.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_antennae(ia)
	ia.surface_end()
	## 翅膀: 半透明(MIX) —— 昆虫翅是透的, 扇动时能看见开合
	var wing := MeshInstance3D.new()
	wing.mesh = ImmediateMesh.new()
	wing.material_override = _mat(false, 4, false)
	(wing.material_override as StandardMaterial3D).albedo_color = COL_WING
	wing.name = "wing"
	root.add_child(wing)
	## 尾巴: 加性发光 —— 它是毒雾的出口。★亮度已压到头部之下(见 COL_TAIL 那段)
	var flap := MeshInstance3D.new()
	flap.mesh = ImmediateMesh.new()
	flap.material_override = _mat(false, 3)
	(flap.material_override as StandardMaterial3D).albedo_color = COL_TAIL
	flap.name = "flap"
	root.add_child(flap)
	battle._world.add_child(root)
	apply_drone(root, Vector2.ZERO, 0.0, 0.0)
	return root


## 挂一段躯干(头/胸/腹): 同一个单位球网格 + 各自的 scale/位置/颜色。
func _add_seg(root: Node3D, nm: String, x: float, r: Vector3, col: Color, prio: int) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _cache_body
	mi.material_override = _mat(false, prio, false)
	(mi.material_override as StandardMaterial3D).albedo_color = col
	mi.scale = r
	mi.position = Vector3(x, 0.0, 0.0)
	mi.name = nm
	root.add_child(mi)


## 把 (位置, 航向, 时刻) 写到真实节点上 —— **纯同步**。
## 局部 +X = 前进方向; 绕 Y 转 −hd 把 +X 映到像素平面的 (cos hd, sin hd)。
func apply_drone(root, pos2d: Vector2, hd: float, t: float) -> void:
	if not is_instance_valid(root):
		return
	root.position = battle._world_pos(pos2d, FLY_H + bob(t))
	root.basis = Basis(Vector3.UP, -hd)
	var wing = root.get_node_or_null("wing")
	if wing != null:
		var iw := (wing as MeshInstance3D).mesh as ImmediateMesh
		if iw != null:
			iw.clear_surfaces()
			iw.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			_emit_wings(iw, t)
			iw.surface_end()
	var flap = root.get_node_or_null("flap")
	if flap == null:
		return
	var im := (flap as MeshInstance3D).mesh as ImmediateMesh
	if im == null:
		return
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_tail(im, t)
	im.surface_end()


## 一对触角: 从头前斜向前上方伸出。**静态**几何(不参与扇翅), 只负责钉住"哪边是头"。
static func _emit_antennae(im: ImmediateMesh) -> void:
	for sgn in [1.0, -1.0]:
		var a := Vector3(ANT_ROOT.x, ANT_ROOT.y, ANT_ROOT.z * sgn)
		var b := Vector3(ANT_TIP.x, ANT_TIP.y, ANT_TIP.z * sgn)
		var n: Vector3 = (b - a).cross(Vector3.UP)
		if n.length() < 1e-6:
			n = Vector3(0, 0, 1)
		n = n.normalized() * ANT_W
		_emit_tri(im, a + n, a - n, b, 1.00, 1.00, 0.15)


## 两只蛾翅(每侧【前翅 + 后翅】两片, 共四片): 以行程角 φ(t) 上下扇。左右**同相**(昆虫双翅同步)。
##
## ★★2026-08-09 重写翅尖的位置公式 —— 这是本次重做里最关键的一处几何修正。
##   旧: `tip = (0, sin φ·SPAN, ±cos φ·SPAN)` ⇒ φ 一大, **横向分量 cos φ 掉下来、
##       竖直分量 sin φ 顶上去**, 两只翅一起飞到本体正上方; 而本作是 52° 俯视 ⇒
##       两个三角在屏幕上完全重合成一片(染色法实测: 两翅合计只有 12×27 px 的竖条, 读作鲨鱼鳍)。
##   新: 横向分量恒为 `WING_KEEP + (1−WING_KEEP)·cos φ` ∈ [0.62, 1.0] ⇒ **永远横向展开**,
##       sin φ 只驱动上下(WING_LIFT 系数)。⇒ 两只翅始终分居本体两侧, 扇动仍然看得见。
##   ★翅面用【四边形】而不是三角形: 三角形只有一个尖, 读不出翅形; 四边形能做出
##     "前缘长、后缘短" 的蛾翅轮廓。
static func _emit_wings(im: ImmediateMesh, t: float) -> void:
	var phi: float = stroke(t)
	var span_k: float = WING_KEEP + (1.0 - WING_KEEP) * cos(phi)
	var lift: float = sin(phi) * WING_SPAN * WING_LIFT
	for sgn in [1.0, -1.0]:
		# 前翅: 弦长 WING_CHORD, 翅根贴在胸侧
		_emit_wing_quad(im, sgn, 0.0, 1.0, span_k, lift, 0.78, 0.30)
		# 后翅: 小一号并靠后 ⇒ 蛾的双翅轮廓
		_emit_wing_quad(im, sgn, HIND_X, HIND_K, span_k, lift, 0.60, 0.18)


## 一片翅: 沿翅展取三档剖面(根 / 中 / 尖), 每档给出前缘与后缘两点。
## ★★为什么不是一个四边形: 旧写法的**尖弦几乎等于根弦**(1.20c vs 1.17c) ⇒ 画出来是个
##   直上直下的**矩形**, 实拍读作"背上顶了两个纸箱"。真正的翅形要靠【弦长沿翅展收窄 +
##   后掠】: 这里尖弦收到根弦的 0.40、翅心沿 −X 后掠 0.34c ⇒ 轮廓是收尖后掠的蛾翅。
const _WING_TAPER := [1.0, 0.88, 0.40]

static func _emit_wing_quad(im: ImmediateMesh, sgn: float, x0: float, k: float,
		span_k: float, lift: float, a_root: float, a_tip: float) -> void:
	var c: float = WING_CHORD * k
	var fr: Array = []
	var bk: Array = []
	var al: Array = []
	for i in range(_WING_TAPER.size()):
		var s: float = float(i) / float(_WING_TAPER.size() - 1)
		var w: float = float(_WING_TAPER[i])
		var z: float = lerpf(0.055, WING_SPAN * k * span_k, s) * sgn
		var y: float = 0.05 + lift * k * s
		var xc: float = x0 - c * 0.34 * s
		fr.append(Vector3(xc + c * 0.62 * w, y, z))
		bk.append(Vector3(xc - c * 0.55 * w, y, z))
		al.append(lerpf(a_root, a_tip, s))
	for i in range(_WING_TAPER.size() - 1):
		_emit_tri(im, fr[i], bk[i], bk[i + 1], float(al[i]), float(al[i]), float(al[i + 1]))
		_emit_tri(im, fr[i], bk[i + 1], fr[i + 1], float(al[i]), float(al[i + 1]), float(al[i + 1]))


## 尾部: 沿 −X 展开的行波带, 逐段滞后, 尖端振幅最大。
static func _emit_tail(im: ImmediateMesh, t: float) -> void:
	var prev_c := Vector3.ZERO
	var prev_w := 0.0
	for i in range(TAIL_SEG + 1):
		var s: float = float(i) / float(TAIL_SEG)
		var x: float = lerpf(TAIL_X0, TAIL_X1, s)
		var z: float = tail_offset(s, t)
		var c := Vector3(x, 0.02, z)
		var w: float = lerpf(0.09, 0.015, s)
		if i > 0:
			var a0 := prev_c + Vector3(0, 0, prev_w)
			var b0 := prev_c - Vector3(0, 0, prev_w)
			var a1 := c + Vector3(0, 0, w)
			var b1 := c - Vector3(0, 0, w)
			var f0: float = 1.0 - (float(i - 1) / float(TAIL_SEG)) * 0.75
			var f1: float = 1.0 - (float(i) / float(TAIL_SEG)) * 0.75
			_emit_tri(im, a0, b0, b1, f0, f0, f1)
			_emit_tri(im, a0, b1, a1, f0, f1, f1)
		prev_c = c
		prev_w = w


static func _emit_tri(im: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3,
		aa: float, ab: float, ac: float) -> void:
	im.surface_set_color(Color(1, 1, 1, aa)); im.surface_add_vertex(a)
	im.surface_set_color(Color(1, 1, 1, ab)); im.surface_add_vertex(b)
	im.surface_set_color(Color(1, 1, 1, ac)); im.surface_add_vertex(c)


# ══════════════════════════════════════════════════════════════════
#  §剧毒缓速的累积可见性(脚环)
# ══════════════════════════════════════════════════════════════════

## 建一个空的脚环节点(**已挂进 _world**)。刻痕由 apply_ring 按层数生成。
func make_ring():
	if battle == null or not is_instance_valid(battle._world):
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.material_override = _mat(true, 9)
	mi.set_meta(META_KEY, "venom_ring")
	mi.set_meta("marks", -1)
	battle._world.add_child(mi)
	return mi


## 把"这只身上 n 层剧毒缓速"画出来: 环上 **n 个刻痕**, 玩家能数。
## ★网格【只在 n 变化时】重建 —— 每单位最多 4 次/秒(施加节拍就是 0.25 秒), 不是每帧。
##   位置每帧更新(跟着单位走), 那个是常数开销。
func apply_ring(mi, pos2d: Vector2, n: int) -> void:
	if not is_instance_valid(mi):
		return
	mi.position = battle._world_pos(pos2d, 0.0)
	var nn: int = clampi(n, 0, RING_MARK_MAX)
	var a: float = RING_A_FULL * float(nn) / float(RING_MARK_MAX)
	(mi.material_override as StandardMaterial3D).albedo_color = Color(
		COL_RING.r, COL_RING.g, COL_RING.b, a)
	if int(mi.get_meta("marks", -1)) == nn:
		return
	mi.set_meta("marks", nn)
	var im := (mi as MeshInstance3D).mesh as ImmediateMesh
	im.clear_surfaces()
	if nn <= 0:
		return
	var rin: float = RING_R * float(battle.WS) * 0.74
	var rout: float = RING_R * float(battle.WS)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(nn):
		var th: float = float(k) / float(RING_MARK_MAX) * TAU
		var t0: float = th - RING_MARK_W * 0.5
		var t1: float = th + RING_MARK_W * 0.5
		var p0 := Vector3(rin * cos(t0), GROUND_Y, rin * sin(t0))
		var p1 := Vector3(rout * cos(t0), GROUND_Y, rout * sin(t0))
		var p2 := Vector3(rout * cos(t1), GROUND_Y, rout * sin(t1))
		var p3 := Vector3(rin * cos(t1), GROUND_Y, rin * sin(t1))
		_emit_tri(im, p0, p1, p2, 0.55, 1.0, 1.0)
		_emit_tri(im, p0, p2, p3, 0.55, 1.0, 0.55)
	im.surface_end()
