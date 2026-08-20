class_name BowEqVfx
extends RefCounted
## bow_eq_vfx.gd — 弓箭四件新装备(073/074/075/076)的演出层
## (方案书 docs/plans/20260805-装备逐件重做.md §0.5 · 实装契约 docs/plans/20260805-实装契约.md §6)
##
## ══════════════════════════════════════════════════════════════════════
##  ★判据: 可验证的物理规律, 不是"我调得像"
## ══════════════════════════════════════════════════════════════════════
## 触手立的第一条判据是「逐帧量参考做成包络表」—— **这四件一张参考图都没有**,
## 所以那条无从下手。替代路线照【怒气冲击波】(shockwave_vfx.gd): 每条形态都落在一个
## **有闭式解的物理模型**上, 门禁验的是那个模型的**性质**(恒等式/极值位置/尺度律/分布函数),
## 手调出来的缓动曲线一条都过不了。
##
## ⚠ **诚实记录**: 没有参考素材 ⇒ 本文件**没有"逐帧量参考"这一步**。
##   下面四条模型是这一步的替代品, 不是它的等价物。
##
## ── ① 073 藤蔓小球: 临界阻尼弹簧跟随 + 动量守恒反冲 ─────────────────
##   小球**不硬绑**在携带者身上, 而是一个二阶系统 ẍ = −ω²(x−T) − 2ω ẋ (ζ=1)。
##   ζ=1 是**临界阻尼**: 在"不过冲"的前提下收敛最快 —— ζ<1 会甩过头再荡回来(像挂在弹簧上的球),
##   ζ>1 会拖泥带水。选它是因为"跟班小球"该是**追得上但永远差一点**。
##
##   ★三条可验证性质(门禁 ①):
##     · 阶跃响应闭式解 **x̂(t) = 1 − (1+ωt)e^(−ωt)**, 且 `crit_damp_step` 的**离散积分器
##       在任意 dt 下与它逐点相等**(用的是精确离散化, 不是欧拉近似 ⇒ 帧率无关)
##     · **永不过冲**: x̂(t) < 1 对一切有限 t 成立(ζ<1 的欠阻尼会 >1)
##     · 匀速跟随的**稳态滞后 = 2v/ω**(精确)—— "有滞后跟随"这句话在这里是一个可量的数,
##       不是形容词。硬绑的滞后恒为 0, 一测就露。
##
##   反冲走**动量守恒**: 藤蔓箭带走动量 p, 小球得到 −p。门禁验 Δv 与射向**严格反平行**。
##
## ── ② 074 骨甲: 立方根壳层生长 + 叶序(黄金角)排布 ──────────────────
##   "护盾层层叠上去要看得见" 的正确编码不是"越叠越大到没边":
##   骨甲是**有厚度的实体**, 累积的是**体积**; 体积 ∝ r³ ⇒ **r ∝ V^(1/3)**。
##   ★可验证性质(门禁 ②): **radius(8·s) / radius(s) ≡ 2**, 与 s 无关(纯尺度律)。
##     线性半径(r ∝ V)会给出 8, 一测就分开。
##
##   甲片的方位角用**黄金角 137.5078°**(= π(3−√5))递增 —— 这是向日葵/松果的叶序排布,
##   它是唯一能让**任意 n 片都不排成辐条**的角度(无理数且是最难被有理数逼近的那个)。
##   ★可验证性质(门禁 ②): n=40 时, 黄金角排布的**最小两两间距**显著大于 90° 排布
##     (后者只有 4 条辐条, 片片重叠)。这是"层层叠上去看得清"这句话的可判定形式。
##
## ── ③ 075 箭雨: 真抛物线高抛 + 二维正态(Rayleigh)散布 ────────────────
##   高抛弹道是**无阻力斜抛**的闭式解。固定仰角 θ=60°(高抛), 射程 R 反解初速:
##       v = √(R·g / sin2θ)     T = 2v sinθ / g     z(x) = x·tanθ·(1 − x/R)
##   ★三条可验证性质(门禁 ③):
##     · **顶点高度 = R·tanθ/4** 精确(θ=60° ⇒ 0.4330·R), 且顶点恰在 **x = R/2**(对称)
##     · **飞行时间 ∝ √R**: T(4R)/T(R) ≡ 2。匀速直线飞行给 4, ease 曲线给别的数
##     · 落地角 = −θ(能量守恒, 无阻力) ⇒ 箭是**扎下来**的不是飘下来的
##
##   落点散布走**二维各向同性正态**, 不是均匀随机。它的半径服从 **Rayleigh 分布**:
##       P(r ≤ R) = 1 − exp(−R²/2σ²)
##   ★可验证性质(门禁 ③): 1σ 内只落 **39.35%**(不是一维正态的 68.27%, 也不是
##     均匀圆盘的 σ²/R²)。三者的 CDF 形状完全不同, 播种 RNG 抽 4000 个点就能分开。
##   ⚠ 这不是美术偏好: 真实齐射的落点误差是两个独立的正态分量(方位偏差 × 距离偏差),
##     合起来就是二维正态。均匀随机会让边缘密度偏高, 看着像"围成一圈"。
##
## ── ④ 076 贯穿光迹: Beer–Lambert 吸收律 ────────────────────────────
##   每穿一人伤害 ×0.75 —— 这**就是**离散吸收体的 Beer–Lambert 律:
##       I(n) = I₀ · 0.75ⁿ = I₀ · e^(−n·μ),  μ = −ln0.75 = 0.28768
##   ⇒ **光迹每段的亮度直接用伤害倍率**, 一个数两处用, 不抄第二遍。
##   ★可验证性质(门禁 ④): `tracer_alpha(n) ≡ pierce_mult(n)` 对每个 n 成立,
##     且 `pierce_mult(n) ≡ beer_lambert(n)`(在触底之前)。
##     "越穿越暗看得出来"于是变成一条恒等式, 而不是一句美术形容。
##
##   连射节奏走**阻尼谐振子的冲激响应** h(t) = e^(−ζωt)·sin(ω_d t) (ω_d = ω√(1−ζ²)):
##   ★可验证性质(门禁 ④): ① **LTI 叠加**: 两发的合成 ≡ 各自响应之和(线性系统);
##     ② 相邻两发间隔 0.25 秒时, 前一发的残余 < 峰值的 5% ⇒ **42 发读得出是 42 下**,
##     不是糊成一条连续的抖动。这条把"节奏感"变成了一个不等式。
##
## ── 技术路线 ────────────────────────────────────────────────────────
## 程序化 `ArrayMesh`/`SurfaceTool` 现算 + Godot 内置图元, **零素材**
## (同 shockwave_vfx / tentacle_vfx)。用户铁律「不复用素材除非点名」:
## 程序化几何不产出图, 不吃这条约束; 也**没有借用任何别件装备的立绘**。
##
## ⚠ 朝向坑 (memory [[fb-axis-y-plus-rotation-cancels]]): 本文件**不用 Sprite3D**,
##   直接建世界坐标顶点 —— 没有 `axis` 与 `rotation.x=-90` 互相抵消那层歧义。
##   贴地几何一律 y = GROUND_Y 的水平顶点。
##
## ⚠ 材质一律走 `material_override`, 不用 `set_surface_override_material` ——
##   后者在 `--headless` dummy renderer 下每设一次刷一条 `Parameter "material" is null.`
##   (shockwave_vfx.gd:_build_shell_mesh 那段血泪注释)。
##
## ⚠ **不用 tween**: 无头 CI 下 create_tween 推进不稳(CLAUDE.md §3.5), 且走 sim 的 delta
##   才跟时停/换路同步。全部生命周期由本文件的 `tick(delta)` 推进。


# ══════════════════════════════════════════════════════════════════
#  §物理常数 —— 全部来自闭式解
# ══════════════════════════════════════════════════════════════════

## ① 073 小球跟随的固有频率(rad/s)。ζ=1 固定(临界阻尼), 所以只有这一个自由参数。
##    ω=9 ⇒ 携带者以 100 码/秒平移时稳态滞后 2v/ω = 22.2 码 ≈ 小半个身位: 看得出在追, 不会掉队。
const ORB_OMEGA := 9.0
## 小球悬在携带者上方(码 → 后面按 WS 转米)与身侧的偏置
const ORB_OFFSET := Vector2(-26.0, -34.0)
## 小球半径(码)
const ORB_R_PX := 13.0
## 反冲冲量(码/秒)。小球质量归一 ⇒ Δv = −冲量 × 射向。
const ORB_RECOIL := 190.0

## ② 074 骨甲: 参考护盾比例 → 参考壳半径(码)。r = R0 · (frac/REF)^(1/3)
const PLATE_REF_FRAC := 0.30
const PLATE_R0_PX := 44.0
const PLATE_CUBE := 1.0 / 3.0
## 黄金角 = π(3−√5) rad = 137.50776…°。
## ★写成字面量而不是 `PI*(3.0-sqrt(5.0))` —— GDScript 的 const 表达式不接受内建函数调用
##   (memory [[project-god-file-decomposition]] 坑 15 同一类)。门禁 ② 有一条专门验它等于 π(3−√5)。
const GOLDEN_ANGLE := 2.399963229728653
## 一次最多画几片甲(再多也看不清, 且手机端预算)
const PLATE_CAP := 40

## ③ 075 箭雨: 高抛仰角 60° = π/3 rad(字面量, 理由同 GOLDEN_ANGLE)
const LOB_THETA := 1.0471975511965976
## tan60° 与 sin120°(= sin2θ), 同样写字面量
const LOB_TAN := 1.7320508075688772
const LOB_SIN2T := 0.8660254037844387
## 演出用重力(码/秒²)。只影响绝对时长, 不影响上面那三条**归一**性质。
## ── 075 银色箭袋·箭雨三段(2026-08-12 用户重设计:「先以中心展开一个圈, 圈里面你也得设计下,
##    然后是很多支箭射下来, 最后圈往中间关闭」; 旧版"完全看不到箭在动") ──
## 标定圈: 展开 / 收拢 各多少秒(总时长仍 = 6 跳 × 0.25 = 1.5 秒, 两头各吃一段)
const RAIN_OPEN_SEC := 0.28
const RAIN_CLOSE_SEC := 0.30
## 圈的刻度: 外圈短刻度数 / 长刻度每几格一根 / 内圈相对半径 / 刻度层自旋(rad/s)
const RAIN_TICKS := 36
const RAIN_TICK_MAJOR := 3
const RAIN_INNER_K := 0.55
const RAIN_FIELD_SPIN := 0.42
## 单支箭: 飞行时长(秒) / 出发高度(码) / 上风侧水平行程(码) / 箭长(码)
## ★2026-08-12 二轮(用户:「我是希望是上一版斜着射入, 但应该有箭的移动感, 从更高的地方开始生成」):
##   · 轨迹从"抛物线顶点起步"(出发几乎水平、越落越陡)改回**固定 60° 斜线**——
##     整段保持同一个入射角, 就是上一版那个"斜着扎下来"的读法, 但节点是真的在走。
##   · 出发高度 460 → 820 码(更高处生成), 水平行程 = H / tan60° 保证角度恰好 60°。
##   · 走线速度加速(s = u²) + 箭随速度拉长 ⇒ 越接近地面越快、拖影越长 = 移动感。
const RAIN_FLY_SEC := 0.42
const RAIN_FLY_H := 820.0
const RAIN_FLY_RUN := 473.4        # = 820 / tan(60°), 与 LOB_THETA 同一个入射角
const RAIN_ARROW_LEN := 58.0
## ★整波箭的【共同来向】(弧度) —— 一次齐射是从同一侧压过来的, 不是四面八方各射一支。
##   (2026-08-12 用户:「不是四面八方射过来的」; 旧版把来向写死成 −X 侧, 这里保持同一读法。)
const RAIN_VOLLEY_YAW := PI
## 拖尾最长(码)与落地后箭插在地上的时长(秒)
## ★2026-08-12 用户:「箭我要有拖尾, 而且不能凭空消失」——
##   轨迹是直线 ⇒ 拖尾就是【已走过的那一段路径本身】(不是另画一条装饰带);
##   落地不再原地淡掉, 而是把飞行体换成【插在地上的箭】+ 落尘, 再慢慢淡。
const RAIN_TRAIL_MAX := 210.0
const RAIN_STUCK_SEC := 0.62
## 银色三档(与"银色箭袋"同名同色): 亮银 / 银 / 暗银边
const SILVER_HI := Color(0.96, 0.98, 1.00)
const SILVER_MID := Color(0.78, 0.83, 0.90)
const SILVER_LO := Color(0.46, 0.52, 0.62)

const RAIN_G := 2600.0
## 落点散布的标准差 = 半径 / 3 ⇒ Rayleigh 下 1−e^(−4.5) = 98.89% 落在半径内。
const RAIN_SIGMA_DIV := 3.0

## ④ 076 贯穿: 每穿一人 ×0.75, 最低 25%
const PIERCE_DECAY := 0.75
const PIERCE_FLOOR := 0.25
## Beer–Lambert 吸收系数 μ = −ln(0.75)(字面量, 理由同上)
const BL_MU := 0.2876820724517809
## 连射反冲的阻尼谐振子: ω(rad/s) 与阻尼比 ζ
const RECOIL_W := 46.0
const RECOIL_Z := 0.35
## 阻尼频率 ω_d = ω√(1−ζ²) = 46 × 0.9367497 (字面量)
const RECOIL_WD := 43.090486
## 连射节拍(秒)。★与效果侧的发射间隔是**同一个数**, 由 EqBowBatch.VOLLEY_IV 焊住(门禁 ④ 验)。
const RECOIL_IV := 0.15
## ── 076 弩矢飞行(2026-08-12 用户:「这感觉像激光来的, 我需要箭和尾迹, 速度也太快了」)──
## 旧版是一条【瞬时】铺满 2000 码的匀亮细线 ⇒ 读成激光。改成一支真的在飞的弩矢:
##   · 速度 BOLT_SPEED(码/秒) —— 2000 码要飞 BOLT_LIFE 秒, 肉眼跟得上
##   · 尾迹 = 已飞过的那一段(封顶 BOLT_TRAIL_MAX), 与 075 落箭同一条做法
##   · 命中点的 X 爆点【等弩矢飞到那里才炸】(不再开场全亮 —— 那是激光才有的读法)
const BOLT_SPEED := 3000.0
const BOLT_TRAIL_MAX := 340.0
const BOLT_LEN := 62.0

## 贴地几何离地高度(米)。地板在 y=0, 抬一点免 z-fighting(同 shockwave_vfx)。
const GROUND_Y := 0.06
## 短命特效的【满亮保持比例】: 前 70% 寿命保持出生亮度, 只在最后 30% 线性收掉。
## ★2026-08-11 补验收: "一出生就线性淡出"是特效八病之首(memory [[fb-vfx-defect-families]]) ——
##   弓箭批实拍复核 9 张里 0 张抓到藤蔓箭, 短命亮片在任意采样时刻平均只有半亮。
const FADE_HOLD := 0.7
## 贴地环的经向分段
const RING_LON := 48
## 本层节点上打的 meta 键 —— 门禁按 meta 数, 不按节点名/贴图路径
## (程序生成贴图 resource_path 是空串, 按路径数会全数成 0)。
const META_KEY := "bow_eq_vfx"
## _owned 上限, 同 SynergyVfx.OWNED_CAP 的口径(最后一道闸)
const OWNED_CAP := 256

var battle

## 本层建出来、还活着的节点(撤场用)。存节点不存单位字典 —— CLAUDE.md §3.2。
var _owned: Array = []
## 正在播的短命特效 [{node, t, life, kind, …}] —— 每帧由 tick() 推进, **不用 tween**。
var _fx: Array = []
## 单位半径网格缓存(整局各建一次; 材质不能共享, 会串色 —— 同 shockwave_vfx)
var _mesh_ring: ArrayMesh = null
var _mesh_plate: ArrayMesh = null
var _mesh_orb_shield: SphereMesh = null
var _mesh_shard: ArrayMesh = null
var _mesh_orb: SphereMesh = null
## 落箭网格与它对应的水平行程(半径变了就重建)
var _mesh_rain: ArrayMesh = null
var _mesh_rain_field: ArrayMesh = null
var _mesh_shadow: ArrayMesh = null
var _mesh_trail: ArrayMesh = null
var _mesh_bolt: ArrayMesh = null
var _mesh_rain_run: float = -1.0


func _init(b) -> void:
	battle = b


func _has_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调, 不建节点、不等演出 (契约 §7: 全部同步判定)
# ══════════════════════════════════════════════════════════════════

# ── ① 073 临界阻尼跟随 ──────────────────────────────────────────

## 归一阶跃响应 x̂(t) = 1 − (1+ωt)·e^(−ωt)。
## ★ζ=1 的解析解。性质: x̂(0)=0 · 单调增 · **恒 < 1(永不过冲)** · x̂(1/ω)=1−2/e=0.264241。
static func step_response(omega: float, t: float) -> float:
	if t <= 0.0:
		return 0.0
	var w: float = omega * t
	return 1.0 - (1.0 + w) * exp(-w)


## 匀速目标下的**稳态滞后距离** = 2v/ω(精确)。
## ★"有滞后跟随, 不是硬绑"这句话的可量形式 —— 硬绑恒为 0。
static func lag_steady(speed: float, omega: float) -> float:
	if omega <= 0.0:
		return 0.0
	return 2.0 * speed / omega


## 临界阻尼弹簧的**精确离散化**一步(目标在本步内视为定点)。
## ★不是欧拉近似 —— 它对任意 dt 都严格等于连续解, 所以**帧率无关**
##   (大 dt 下欧拉会发散, 那正是"卡一下小球就飞出去"的来源)。
## 返回 [新位置, 新速度]。
static func crit_damp_step(pos: Vector2, vel: Vector2, target: Vector2, omega: float, dt: float) -> Array:
	if dt <= 0.0 or omega <= 0.0:
		return [pos, vel]
	var ex: float = exp(-omega * dt)
	var change: Vector2 = pos - target
	var temp: Vector2 = (vel + change * omega) * dt
	return [target + (change + temp) * ex, (vel - temp * omega) * ex]


## 反冲: 藤蔓箭沿 dir 带走动量 p ⇒ 小球得到 −p(动量守恒, 小球质量归一)。
## ★门禁验的是**严格反平行** dot(Δv, dir) = −|Δv|, 不是"看着往后弹了一下"。
static func recoil_dv(dir: Vector2, impulse: float) -> Vector2:
	var d: Vector2 = dir
	if d.length() < 1e-6:
		return Vector2.ZERO
	return -d.normalized() * impulse


# ── ② 074 立方根壳层 + 叶序排布 ─────────────────────────────────

## 累积护盾(占最大生命的比例) → 骨甲壳半径(码)。
## ★r ∝ V^(1/3): 甲片是有厚度的实体, 累积的是体积。
##   可验证: shell_radius_px(8s) / shell_radius_px(s) ≡ 2, 与 s 无关。
static func shell_radius_px(frac: float) -> float:
	if frac <= 0.0:
		return 0.0
	return PLATE_R0_PX * pow(frac / PLATE_REF_FRAC, PLATE_CUBE)


## 第 i 片甲(共 n 片)在半球穹顶上的单位方向。方位角按**黄金角**递增。
## ★y 用等面积映射(而不是等角), 否则甲片会挤在顶上 —— 与向日葵籽的排布同一套。
static func plate_dir(i: int, n: int) -> Vector3:
	var nn: int = maxi(1, n)
	var y: float = (float(i) + 0.5) / float(nn)          # 等面积: y 均匀 ⇒ 单位球带面积相等
	var r: float = sqrt(maxf(0.0, 1.0 - y * y))
	var th: float = float(i) * GOLDEN_ANGLE
	return Vector3(r * cos(th), y, r * sin(th))


## n 片甲两两之间的**最小距离**(单位球面上的弦长)。
## ★门禁拿它比"黄金角 vs 90° 辐条角": 前者显著大 = 不重叠, 后者会挤成 4 条辐条。
static func min_plate_gap(n: int, angle: float) -> float:
	var pts: Array = []
	var nn: int = maxi(2, n)
	for i in range(nn):
		var y: float = (float(i) + 0.5) / float(nn)
		var r: float = sqrt(maxf(0.0, 1.0 - y * y))
		var th: float = float(i) * angle
		pts.append(Vector3(r * cos(th), y, r * sin(th)))
	var best: float = INF
	for i in range(pts.size()):
		for j in range(i + 1, pts.size()):
			best = minf(best, (pts[i] as Vector3).distance_to(pts[j]))
	return best


# ── ③ 075 高抛弹道 + Rayleigh 散布 + 最密处 ─────────────────────

## 高抛顶点高度(码) = R·tanθ/4。★θ=60° ⇒ 0.4330·R。
static func lob_apex_px(range_px: float) -> float:
	return maxf(0.0, range_px) * LOB_TAN * 0.25


## 抛物线高度: z(f·R) = R·f·tanθ·(1−f), f ∈ [0,1] 是水平行程比例。
## ★对称: z(f) ≡ z(1−f); 极大恰在 f=0.5 且等于 lob_apex_px。
static func lob_height_px(range_px: float, f: float) -> float:
	var ff: float = clampf(f, 0.0, 1.0)
	return maxf(0.0, range_px) * ff * LOB_TAN * (1.0 - ff)


## 飞行时间(秒): v = √(R g / sin2θ), T = 2v sinθ / g ⇒ **T ∝ √R**。
static func lob_time_s(range_px: float) -> float:
	var r: float = maxf(1.0, range_px)
	var v: float = sqrt(r * RAIN_G / LOB_SIN2T)
	return 2.0 * v * sin(LOB_THETA) / RAIN_G


## Rayleigh CDF: 二维各向同性正态的**半径**分布。P(r≤R) = 1 − exp(−R²/2σ²)。
## ★1σ 内 39.35%(不是一维的 68.27%), 2σ 内 86.47%。
static func rayleigh_cdf(r: float, sigma: float) -> float:
	if sigma <= 0.0:
		return 1.0 if r >= 0.0 else 0.0
	return 1.0 - exp(-(r * r) / (2.0 * sigma * sigma))


## 敌人**最密集处**: 先取"以某个敌人为心、半径 radius 的圆"里覆盖最多的那个,
## 再退到被覆盖集合的**质心**(凸组合, 落点更居中)。
## ★质心可能把某些点挤出圆外 —— 挤出去就退回圆心, 保证【覆盖数不下降】。
##   门禁 ③ 断言的正是"最终落点的覆盖数 ≥ 任一单敌为心的覆盖数"。
## ★纯几何、零 RNG ⇒ 确定性; 平手取下标最小的。
static func densest_point(pts: Array, radius: float) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var r2: float = radius * radius
	var best_i: int = 0
	var best_n: int = -1
	for i in range(pts.size()):
		var c: Vector2 = pts[i]
		var n: int = 0
		for p in pts:
			if (p as Vector2).distance_squared_to(c) <= r2:
				n += 1
		if n > best_n:
			best_n = n
			best_i = i
	var center: Vector2 = pts[best_i]
	var sum := Vector2.ZERO
	var cnt: int = 0
	for p in pts:
		if (p as Vector2).distance_squared_to(center) <= r2:
			sum += p
			cnt += 1
	if cnt <= 0:
		return center
	var cen: Vector2 = sum / float(cnt)
	var n2: int = 0
	for p in pts:
		if (p as Vector2).distance_squared_to(cen) <= r2:
			n2 += 1
	return cen if n2 >= best_n else center


## 落点散布(二维正态)。★走 `battle._battle_rng` —— 裸 randfn 会破坏确定性
##   (rng_discipline 审计器 + verify_battle_determinism 会抓)。
func scatter_offset(sigma: float) -> Vector2:
	if battle == null:
		return Vector2.ZERO
	return Vector2(battle._battle_rng.randfn(0.0, sigma), battle._battle_rng.randfn(0.0, sigma))


# ── ④ 076 贯穿衰减 + 连射节奏 ───────────────────────────────────

## 穿过 n 个敌人之后的伤害倍率。n=0 是第一个被穿的人(不衰减)。
## ★**这是伤害与光迹亮度的同一个事实源** —— 效果侧与演出侧都只读这一个函数。
static func pierce_mult(n: int) -> float:
	return maxf(PIERCE_FLOOR, pow(PIERCE_DECAY, float(maxi(0, n))))


## Beer–Lambert 形式: I = e^(−nμ)。触底之前应与 pierce_mult 逐点相等。
static func beer_lambert(n: int) -> float:
	return exp(-BL_MU * float(maxi(0, n)))


## 光迹第 n 段的亮度 —— **就是** pierce_mult(n)。抄第二遍的话产品改坏门禁照样绿。
static func tracer_alpha(n: int) -> float:
	return pierce_mult(n)


## 阻尼谐振子的冲激响应 h(t) = e^(−ζωt)·sin(ω_d t), t<0 为 0(因果)。
static func recoil_impulse(t: float) -> float:
	if t < 0.0:
		return 0.0
	return exp(-RECOIL_Z * RECOIL_W * t) * sin(RECOIL_WD * t)


## 多发叠加(LTI 线性系统 ⇒ 就是各自响应之和)。
static func recoil_sum(t: float, shot_times: Array) -> float:
	var s := 0.0
	for st in shot_times:
		s += recoil_impulse(t - float(st))
	return s


# ══════════════════════════════════════════════════════════════════
#  §几何 —— 程序化 ArrayMesh, 零素材
# ══════════════════════════════════════════════════════════════════

static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for v in [a, b, c]:
		st.set_color(v[1])
		st.add_vertex(v[0])


static func _flat(r: float, th: float, a: float) -> Array:
	return [Vector3(r * cos(th), GROUND_Y, r * sin(th)), Color(1, 1, 1, a)]


## 单位半径的贴地环(外沿硬 = 落区边界, 内沿渐隐)。
static func _build_ring() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(RING_LON):
		var t0: float = float(j) / float(RING_LON) * TAU
		var t1: float = float(j + 1) / float(RING_LON) * TAU
		for q in [[0.82, 0.0, 0.97, 0.9], [0.97, 0.9, 1.0, 0.35]]:
			var ri: float = float(q[0])
			var ai: float = float(q[1])
			var ro: float = float(q[2])
			var ao: float = float(q[3])
			_tri(st, _flat(ri, t0, ai), _flat(ro, t0, ao), _flat(ro, t1, ao))
			_tri(st, _flat(ri, t0, ai), _flat(ro, t1, ao), _flat(ri, t1, ai))
	st.commit(mesh)
	return mesh


## 一片鲸骨 = 竖长的肋骨条(局部 XY 平面, 长轴 Y, 法线 +Z): 中段平直、两端锥形收口。
## ★2026-08-11 重做: 旧版是正方形薄片 + 加色混合, 实拍读成"一撮白色纸屑"(白化 + 无形态,
##   验收口径「形状要像题面」—— 鲸骨胸甲的题面是骨头)。顶点色上亮象牙、下沉骨影,
##   长轴对着壳面经线(见 _plates_layout 的 up), 40 片叠起来是一圈圈肋排。
static func _build_plate() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ivory := Color(1.0, 0.98, 0.90, 0.96)
	var shade := Color(0.72, 0.66, 0.52, 0.92)
	## 骨条剪影: 8 点轮廓(宽 0.34 · 长 1.0 · 两端收窄), 圆心扇面三角化
	var pts := [Vector2(0.0, 0.5), Vector2(0.14, 0.34), Vector2(0.17, 0.0),
		Vector2(0.14, -0.34), Vector2(0.0, -0.5), Vector2(-0.14, -0.34),
		Vector2(-0.17, 0.0), Vector2(-0.14, 0.34)]
	for i in range(pts.size()):
		var a2: Vector2 = pts[i]
		var b2: Vector2 = pts[(i + 1) % pts.size()]
		_tri(st, [Vector3(0.0, 0.0, 0.0), Color(1.0, 0.99, 0.94, 0.98)],
			[Vector3(a2.x, a2.y, 0.0), shade if a2.y < 0.0 else ivory],
			[Vector3(b2.x, b2.y, 0.0), shade if b2.y < 0.0 else ivory])
	st.commit(mesh)
	return mesh


## 加性发光材质(顶点色当亮度), 零素材。
static func _mat(no_depth: bool, prio: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.no_depth_test = no_depth
	## ⚠ render_priority 在【材质】上, MeshInstance3D 没有这个属性
	m.render_priority = prio
	m.albedo_color = Color(1, 1, 1, 1)
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


# ══════════════════════════════════════════════════════════════════
#  §073 藤蔓小球
# ══════════════════════════════════════════════════════════════════

## 给携带者挂一颗藤蔓小球(已经在 _world 里)。已有就直接返回。
## ★状态(位置/速度)存在**单位字典的常驻字段**上, 不是节点上 —— 换路重建单位时天然清掉。
func ensure_orb(u: Dictionary) -> Node3D:
	if not _has_world() or not u.get("alive", false):
		return null
	var cur = u.get("_vine_orb", null)
	if is_instance_valid(cur):
		return cur
	if _mesh_orb == null:
		_mesh_orb = SphereMesh.new()
		_mesh_orb.radius = ORB_R_PX * float(battle.WS)
		_mesh_orb.height = ORB_R_PX * 2.0 * float(battle.WS)
		_mesh_orb.radial_segments = 12
		_mesh_orb.rings = 6
	var m := _mat(false, 8)
	m.albedo_color = Color(0.45, 0.95, 0.42, 0.9)
	## ★★实心球 + 加色混合 + CULL_DISABLED ⇒ 正面背面各加一层 ⇒ **球心被加爆成白**。
	##   实拍 A/B 实测(2026-08-11): 073 自己画的 14000 个像素里, 62% 明确偏绿、
	##   **15% 低饱和(白芯)** —— 实战小尺寸下白芯占视觉主导, 读成"一个白球"。
	##   ⇒ 球体只画正面(反正背面也看不到), 加色只叠一层, 颜色就留得住。
	##   (同族: 095 罩子那一轮的"颜色乘数必须 ≤ 1.0, 否则金子被钳成白"。)
	##   ⚠ 只改小球自己这一份材质 —— `_mat()` 是共用的, 环/带子需要 CULL_DISABLED。
	m.cull_mode = BaseMaterial3D.CULL_BACK
	var org: Vector2 = (u["pos"] as Vector2) + ORB_OFFSET
	var n := _node(_mesh_orb, m, battle._world_pos(org, 0.85), "vine_orb")
	_orb_wrap(n)
	u["_vine_orb"] = n
	u["_vine_orb_pos"] = org
	u["_vine_orb_vel"] = Vector2.ZERO
	return n


## 小球上的【藤蔓缠绕】(2026-08-11 补验收): 两条斜缠的深绿藤环 + 三片小叶。
## ★验收口径「禁圆/球敷衍」—— 球本身是用户点名的形态("藤蔓小球"), 但"藤蔓"得看得出来:
##   素球在实拍里就是一颗浅绿弹珠。藤环取两条互相斜交的大圆(倾角 0.5 / −0.9 rad),
##   叶片从环上径向伸出。挂成小球节点的【子节点】⇒ 跟随/撤场零额外接线。
## ★材质走 MIX 不走加色: 深绿是【比球暗】的颜色, 加色只会把它加没(乘没/加爆同族坑)。
func _orb_wrap(orb: Node3D) -> void:
	var r: float = ORB_R_PX * float(battle.WS) * 1.08
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vine := Color(0.13, 0.42, 0.12, 0.95)
	var leaf := Color(0.30, 0.80, 0.22, 0.95)
	var seg := 18
	var bw: float = r * 0.14                     # 藤条带半宽
	for tilt in [0.5, -0.9]:                     # 两条藤, 各绕一条斜大圆
		var q := Basis(Vector3(1.0, 0.0, 0.0), float(tilt))
		for j in range(seg):
			var t0: float = float(j) / float(seg) * TAU
			var t1: float = float(j + 1) / float(seg) * TAU
			var d0 := Vector3(cos(t0), 0.0, sin(t0))
			var d1 := Vector3(cos(t1), 0.0, sin(t1))
			_tri(st, [q * (d0 * (r - bw)), vine], [q * (d0 * (r + bw)), vine], [q * (d1 * (r + bw)), vine])
			_tri(st, [q * (d0 * (r - bw)), vine], [q * (d1 * (r + bw)), vine], [q * (d1 * (r - bw)), vine])
		## 每条藤上错开长几片叶: 根在环上, 尖沿径向伸出
		for lt in ([0.7, 2.8] if float(tilt) > 0.0 else [4.4]):
			var dl := Vector3(cos(float(lt)), 0.0, sin(float(lt)))
			var tang := Vector3(-sin(float(lt)), 0.0, cos(float(lt)))
			_tri(st, [q * ((dl - tang * 0.18) * r), leaf],
				[q * ((dl + tang * 0.18) * r), leaf],
				[q * (dl * (r * 1.65)), Color(leaf.r, leaf.g, leaf.b, 0.0)])
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m2 := _mat(false, 9)
	m2.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mi.material_override = m2
	mi.set_meta(META_KEY, "vine_orb_wrap")
	orb.add_child(mi)                            # 子节点: 跟着球走, 球 free 它也 free


## 每帧推进小球(临界阻尼跟随)。★纯同步, 门禁可以喂任意 delta。
func orb_tick(u: Dictionary, delta: float) -> void:
	var tgt: Vector2 = (u["pos"] as Vector2) + ORB_OFFSET
	var p: Vector2 = u.get("_vine_orb_pos", tgt)
	var v: Vector2 = u.get("_vine_orb_vel", Vector2.ZERO)
	var r: Array = crit_damp_step(p, v, tgt, ORB_OMEGA, delta)
	u["_vine_orb_pos"] = r[0]
	u["_vine_orb_vel"] = r[1]
	var n = u.get("_vine_orb", null)
	if is_instance_valid(n):
		n.position = battle._world_pos(r[0], 0.85)


## 射出藤蔓箭: ①给小球反冲(动量守恒) ②画一道藤蔓光迹。
func orb_fire(u: Dictionary, tgt_pos: Vector2, crit: bool) -> void:
	var from: Vector2 = u.get("_vine_orb_pos", (u["pos"] as Vector2) + ORB_OFFSET)
	var dir: Vector2 = tgt_pos - from
	if dir.length() < 1.0:
		dir = Vector2.RIGHT
	u["_vine_orb_vel"] = Vector2(u.get("_vine_orb_vel", Vector2.ZERO)) + recoil_dv(dir, ORB_RECOIL)
	if not _has_world():
		return
	var col: Color = Color(1.0, 0.94, 0.45, 0.95) if crit else Color(0.50, 0.93, 0.45, 0.85)
	## ★寿命 0.26/0.34(旧 0.14/0.20): 实拍复核(2026-08-11)按普攻节拍铺 9 张一支都没抓到 ——
	##   0.14 秒 + 出生即淡出, 玩家肉眼同样读不到"每次普攻多射一箭"这条核心机制。
	var n := _streak(from, tgt_pos, col, 4.2 if crit else 3.0)
	if n != null:
		_fx.append({"node": n, "t": 0.0, "life": 0.34 if crit else 0.26, "kind": "streak"})


## 一支从 a 到 b 的【藤蔓箭】(贴地上方一点): 箭杆尾端渐隐 + 命中端三角箭头 + 杆上两对倒刺。
## ★2026-08-11 重做: 旧版是一条裸光带, 验收口径「箭就是箭」—— 没有头就读不出射向,
##   没有刺就读不出"藤蔓"。倒刺朝【后】斜(荆棘的生长方向), 头在 b(命中端)。
func _streak(a: Vector2, b: Vector2, col: Color, half_w_px: float) -> MeshInstance3D:
	if not _has_world():
		return null
	var d: Vector2 = b - a
	if d.length() < 0.5:
		return null
	var dirn: Vector2 = d.normalized()
	var perp: Vector2 = Vector2(-dirn.y, dirn.x)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ya: float = 0.85
	var head_len: float = minf(16.0, d.length() * 0.25)   # 箭头长(码); 贴脸短箭不越过目标
	var neck: Vector2 = b - dirn * head_len               # 箭头根部(杆到这里为止)
	var w: Vector2 = perp * half_w_px
	var p0 := [battle._world_pos(a - w, ya), Color(col.r, col.g, col.b, 0.0)]
	var p1 := [battle._world_pos(a + w, ya), Color(col.r, col.g, col.b, 0.0)]
	var p2 := [battle._world_pos(neck + w, ya), Color(col.r, col.g, col.b, col.a)]
	var p3 := [battle._world_pos(neck - w, ya), Color(col.r, col.g, col.b, col.a)]
	_tri(st, p0, p1, p2)
	_tri(st, p0, p2, p3)
	## 箭头: 底边 = 3 倍杆宽、尖恰在 b —— 加色混合下三角重叠处自然比杆亮一档
	var hw: Vector2 = perp * (half_w_px * 3.0)
	_tri(st, [battle._world_pos(neck - hw, ya), Color(col.r, col.g, col.b, col.a)],
		[battle._world_pos(neck + hw, ya), Color(col.r, col.g, col.b, col.a)],
		[battle._world_pos(b, ya), Color(col.r, col.g, col.b, col.a)])
	## 两对倒刺(藤蔓的荆棘): 杆长 45%/70% 处, 斜向后伸、尖端渐隐
	for f in [0.45, 0.70]:
		var root: Vector2 = a + d * float(f)
		for s in [1.0, -1.0]:
			var tip: Vector2 = root - dirn * (half_w_px * 4.0) + perp * (half_w_px * 3.2 * float(s))
			_tri(st, [battle._world_pos(root - dirn * half_w_px, ya), Color(col.r, col.g, col.b, col.a * 0.8)],
				[battle._world_pos(root + dirn * half_w_px, ya), Color(col.r, col.g, col.b, col.a * 0.8)],
				[battle._world_pos(tip, ya), Color(col.r, col.g, col.b, 0.0)])
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return _node(mesh, _mat(true, 12), Vector3.ZERO, "vine_streak")


# ══════════════════════════════════════════════════════════════════
#  §074 鲸骨护盾罩(2026-08-12 二轮 · 用户: 「不需要这种叠一次给个特效的,
#       我要的是护盾罩子: 获得护盾 / 持续护盾 / 护盾破裂」)
#
#  三态一件事: **罩子在 = 还有盾**。
#    · 获得: 罩子弹出(过冲回弹), 之后每次叠盾走一次涟漪脉冲(亮一下, 不新增节点)
#    · 持续: 常驻跟人, 缓慢呼吸; **尺寸恒定** —— 不随剩余盾量缩小
#            (用户 2026-08-11 对 071 的原话「不要做那种被打缩小的」, 同族约束)
#    · 破裂: 盾归零 ⇒ 罩子炸成骨片四散(向外+下落), 膜闪一下收掉
# ══════════════════════════════════════════════════════════════════

## 罩子半径(码) / 肋条数 / 破裂骨片数与飞行时长
## 护盾球专用 shader(卡尔马 E 参考: 菲涅耳壳 + 双向螺旋能量带 + 细纹流丝)
const ORB_SHADER := "res://assets/shaders/shield_orb.gdshader"
const DOME_R_PX := 92.0
const DOME_RIBS := 8
const DOME_SHARDS := 14
const DOME_BREAK_SEC := 0.55
## 弹出过冲(秒)与呼吸幅度
const DOME_POP_SEC := 0.26
const DOME_BREATH := 0.035


static func dome_pop(x: float) -> float:
	if x >= 1.0:
		return 1.0
	var xx: float = clampf(x, 0.0, 1.0)
	return 1.0 - exp(-5.2 * xx) * cos(6.4 * xx)


## 建/取护盾球(幂等: 已有就直接返回)。获得护盾那一刻由 EqBowBatch 调。
##
## ★2026-08-12 二轮 · 用户:「参考 lol 卡尔马的 e 技能, 护盾应该是个球, 是流动的」——
##   半球罩改成【整球】+ 专用 shader(assets/shaders/shield_orb.gdshader):
##   菲涅耳边沿(球壳感) + 双向反转螺旋能量带(真流动, 不是整体旋转) + 细纹流丝。
##   配色是从卡尔马参考帧【逐像素量】出来的三档(芯/带/外缘), 不是照文字调的。
func dome_ensure(u: Dictionary) -> Dictionary:
	if not _has_world() or not u.get("alive", false):
		return {}
	var h = u.get("_bone_dome", null)
	if h is Dictionary and is_instance_valid((h as Dictionary).get("shell", null)):
		return h
	if _mesh_orb_shield == null:
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 48
		sm.rings = 24
		_mesh_orb_shield = sm
	var mat := ShaderMaterial.new()
	mat.shader = load(ORB_SHADER)
	mat.set_shader_parameter("u_t", 0.0)
	mat.set_shader_parameter("u_gain", 1.0)
	mat.set_shader_parameter("u_spin", 1.0)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_orb_shield
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_adopt(mi, "bone_dome")
	var nh := {"shell": mi, "mat": mat, "t": 0.0, "flash": 0.0}
	u["_bone_dome"] = nh
	dome_follow(u, 0.0)
	return nh


## 每次叠盾: 涟漪脉冲(亮一下), **不新增节点** —— 用户不要"叠一次给个特效"。
func dome_pulse(u: Dictionary) -> void:
	var h = u.get("_bone_dome", null)
	if h is Dictionary:
		(h as Dictionary)["flash"] = 1.0


## 每帧: 跟人 + 弹出过冲 + 呼吸 + 脉冲衰减 + **喂 shader 时间**(流动靠它, 不用 TIME)。
## 尺寸【不随剩余盾量变】(用户 2026-08-11 对 071 定的同族约束)。
func dome_follow(u: Dictionary, delta: float) -> void:
	var h = u.get("_bone_dome", null)
	if not (h is Dictionary):
		return
	var hh: Dictionary = h
	hh["t"] = float(hh.get("t", 0.0)) + maxf(0.0, delta)
	hh["flash"] = maxf(0.0, float(hh.get("flash", 0.0)) - maxf(0.0, delta) * 3.4)
	var t: float = float(hh["t"])
	var pop: float = dome_pop(t / DOME_POP_SEC)
	var r: float = DOME_R_PX * float(battle.WS) * pop * (1.0 + DOME_BREATH * sin(t * 2.1))
	## 球心抬到身体中段(球要把龟裹住, 不是扣在脚下)
	var base: Vector3 = battle._world_pos(u["pos"], 0.62)
	var fl: float = float(hh["flash"])
	var n = hh.get("shell", null)
	if is_instance_valid(n):
		n.position = base
		n.scale = Vector3(r, r, r)
	var m = hh.get("mat", null)
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter("u_t", t)          # ← 流动的事实源
		(m as ShaderMaterial).set_shader_parameter("u_gain", 1.0 + 1.1 * fl)


## 护盾破裂: 罩子炸成骨片(向外飞 + 重力下落), 膜闪一下随即收掉。
## 返回生成的骨片数(门禁拿它当分母)。
func dome_break(u: Dictionary) -> int:
	var h = u.get("_bone_dome", null)
	if not (h is Dictionary):
		return 0
	var made := 0
	if _has_world():
		if _mesh_shard == null:
			_mesh_shard = _build_plate()          # 骨片复用甲片网格(同一件的同一块骨)
		var base: Vector3 = battle._world_pos(u["pos"], 0.05)
		for i in range(DOME_SHARDS):
			var th: float = float(i) * TAU / float(DOME_SHARDS) + 0.11
			var ph: float = [0.18, 0.52, 0.86, 0.34][i % 4]      # 确定性仰角(无 randf)
			var m := _mat(false, 8)
			m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			m.albedo_color = Color(0.95, 0.93, 0.82, 0.95)
			var n := _node(_mesh_shard, m, base, "bone_shard")
			n.scale = Vector3.ONE * (DOME_R_PX * float(battle.WS) * 0.16)
			_fx.append({"node": n, "t": 0.0, "life": DOME_BREAK_SEC, "kind": "shard",
				"c": base, "dir": Vector3(cos(th) * cos(ph), sin(ph), sin(th) * cos(ph))})
			made += 1
	var n2 = (h as Dictionary).get("shell", null)
	if is_instance_valid(n2):
		n2.queue_free()
	u.erase("_bone_dome")
	return made


# ══════════════════════════════════════════════════════════════════
#  §074 骨甲壳层(旧: 叠一层加一片 —— 已被上面的护盾罩取代)
# ══════════════════════════════════════════════════════════════════

## 按累计护盾比例刷新骨甲。frac = 累计护盾 / 最大生命。
## ★片数 = 累计次数(离散可数, "一层一层叠上去"), 壳半径 = 立方根(体积律)。
## ⚠★★**本函数现在零调用者** —— 产品侧没人调, 门禁也没人调
##   (全仓 `plates_refresh` 只出现在下面这一行 def 里)。上面那句"保留供门禁的几何律用"
##   与下面那句"门禁用它当分母"**都是空头支票**, 已删。要么给它接一条真门禁, 要么删掉整节。
##   memory [[fb-verify-must-run-the-real-path]]:「断言函数存在」守不住「还有没有人调」。
func plates_refresh(u: Dictionary, frac: float, layers: int) -> int:
	if not _has_world() or not u.get("alive", false):
		return 0
	var want: int = clampi(layers, 0, PLATE_CAP)
	var arr: Array = u.get("_bone_plates", [])
	arr = arr.filter(func(x): return is_instance_valid(x))
	if _mesh_plate == null:
		_mesh_plate = _build_plate()
	while arr.size() < want:
		## ★MIX 不走加色(2026-08-11): 骨头是实体不是光, 加色在暗底上把象牙白直接白化
		##   (实拍读成白纸屑; 同族: 073 小球加爆成白那条注释)。
		var m := _mat(false, 7)
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		m.albedo_color = Color(0.93, 0.90, 0.78, 0.92)
		arr.append(_node(_mesh_plate, m, Vector3.ZERO, "bone_plate"))
	while arr.size() > want:
		var extra = arr.pop_back()
		if is_instance_valid(extra):
			extra.queue_free()
	u["_bone_plates"] = arr
	u["_bone_frac"] = frac                       # 存给每帧跟随用(plates_follow 只认它)
	_plates_layout(u, shell_radius_px(frac))
	return arr.size()


## 甲片【每帧跟随】(2026-08-11 补验收): 旧版只在普攻刷新时归位, 携带者一走位
## 甲片就吊在身后(实拍: 走到贴脸后甲片还挂在出发点方向)。由 EqBowBatch._tick_orbs 每帧调。
func plates_follow(u: Dictionary) -> void:
	if not u.has("_bone_plates"):
		return
	_plates_layout(u, shell_radius_px(float(u.get("_bone_frac", 0.0))))


## 把现有甲片按叶序摆上壳面(半径 rad_px, 圆心 = 携带者当前位)。refresh 与 follow 共用 ——
## 抄两份摆位就是 memory [[fb-hand-rolled-copies-drift]] 那条坑。
func _plates_layout(u: Dictionary, rad_px: float) -> void:
	var arr: Array = u.get("_bone_plates", [])
	var ws: float = float(battle.WS)
	var base: Vector3 = battle._world_pos(u["pos"], 0.55)
	for i in range(arr.size()):
		var n: MeshInstance3D = arr[i]
		if not is_instance_valid(n):
			continue
		var dir: Vector3 = plate_dir(i, maxi(1, arr.size()))
		n.position = base + dir * (rad_px * ws)
		n.scale = Vector3.ONE * maxf(0.02, rad_px * ws * 0.42)
		## 甲片贴着壳面(法线朝外) —— looking_at 的 up 取 +Y, 与径向共线时退化, 故偏一点;
		## up 投影到壳面后就是经线方向 ⇒ 骨条的长轴(局部 Y)沿经线竖排, 像一圈圈肋骨
		var up: Vector3 = Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
		n.look_at_from_position(n.position, n.position + dir, up)


# ══════════════════════════════════════════════════════════════════
#  §075 箭雨
# ══════════════════════════════════════════════════════════════════

## 落区【银色标定圈】的贴地网格(单位半径): 外圈 + 刻度 + 内圈 + 十字准星 + 四角箭标。
## ★用户 2026-08-12:「先以中心展开一个圈…这个圈里面你也得设计下」——
##   空心圈是"无含义圆环"族; 这里圈内有东西: 它是箭袋主人给这片地划的射击标定。
static func _build_rain_field() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hi := Color(1, 1, 1, 1.0)
	var mid := Color(1, 1, 1, 0.62)
	var dim := Color(1, 1, 1, 0.30)

	# ① 外圈实线(0.965~1.0) + ② 内圈细线(RAIN_INNER_K)
	for band in [[0.965, 1.0, hi], [RAIN_INNER_K - 0.012, RAIN_INNER_K + 0.012, mid]]:
		var ri: float = float(band[0])
		var ro: float = float(band[1])
		var cc: Color = band[2]
		for j in range(96):
			var t0: float = float(j) / 96.0 * TAU
			var t1: float = float(j + 1) / 96.0 * TAU
			_flat_quad(st, ri, ro, t0, t1, cc, cc)

	# ③ 外圈刻度: 每格一根短刻, 每 RAIN_TICK_MAJOR 格一根长刻(读得出"这是标定过的距离")
	for k in range(RAIN_TICKS):
		var th: float = float(k) * TAU / float(RAIN_TICKS)
		var major: bool = (k % RAIN_TICK_MAJOR) == 0
		var inner: float = 0.88 if major else 0.925
		var w: float = 0.010 if major else 0.006
		_flat_quad(st, inner, 0.962, th - w, th + w, (hi if major else mid), (hi if major else mid))

	# ④ 中心十字准星 + 小菱形(圈心是"瞄准点", 不是空的)
	for ang in [0.0, PI * 0.5]:
		_flat_quad(st, -0.16, 0.16, ang - 0.008, ang + 0.008, mid, mid)
		_flat_quad(st, -0.16, 0.16, ang + PI - 0.008, ang + PI + 0.008, mid, mid)
	for j2 in range(4):
		var a0: float = float(j2) * TAU / 4.0
		var a1: float = float(j2 + 1) * TAU / 4.0
		_tri(st, [Vector3(0, GROUND_Y, 0), hi],
			[Vector3(0.06 * cos(a0), GROUND_Y, 0.06 * sin(a0)), dim],
			[Vector3(0.06 * cos(a1), GROUND_Y, 0.06 * sin(a1)), dim])

	# ⑤ 四个方位的箭标(指向圆心 —— "箭往这里落")
	for q in range(4):
		var th2: float = float(q) * TAU / 4.0 + PI * 0.25
		var tipr: float = RAIN_INNER_K + 0.10
		var basr: float = RAIN_INNER_K + 0.24
		var tip := Vector3(tipr * cos(th2), GROUND_Y, tipr * sin(th2))
		var l := Vector3(basr * cos(th2 - 0.06), GROUND_Y, basr * sin(th2 - 0.06))
		var r := Vector3(basr * cos(th2 + 0.06), GROUND_Y, basr * sin(th2 + 0.06))
		_tri(st, [tip, hi], [l, dim], [r, dim])

	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


## 贴地扇环块(r0..r1 × th0..th1)。r 允许为负 ⇒ 穿过圆心画整条(十字准星用)。
static func _flat_quad(st: SurfaceTool, r0: float, r1: float, th0: float, th1: float,
		c0: Color, c1: Color) -> void:
	var a := Vector3(r0 * cos(th0), GROUND_Y, r0 * sin(th0))
	var b := Vector3(r1 * cos(th0), GROUND_Y, r1 * sin(th0))
	var c := Vector3(r1 * cos(th1), GROUND_Y, r1 * sin(th1))
	var d := Vector3(r0 * cos(th1), GROUND_Y, r0 * sin(th1))
	_tri(st, [a, c0], [b, c1], [c, c1])
	_tri(st, [a, c0], [c, c1], [d, c0])


## 落区标定圈: **展开 → 常驻 → 往中间关闭** 三段(用户 2026-08-12 点名的顺序)。
## ★半径写进节点的**真实 scale**, 门禁量节点不量公式
##   (memory [[fb-write-without-reader-and-fake-gates]]: 抄公式的门禁, 产品改成写死也照样绿)。
func rain_marker(center: Vector2, radius_px: float, life: float) -> MeshInstance3D:
	if not _has_world():
		return null
	if _mesh_rain_field == null:
		_mesh_rain_field = _build_rain_field()
	var m := _mat(true, 11)
	m.albedo_color = Color(SILVER_MID.r, SILVER_MID.g, SILVER_MID.b, 0.85)
	var n := _node(_mesh_rain_field, m, battle._world_pos(center, 0.0), "rain_ring")
	n.scale = Vector3(1e-4, 1e-4, 1e-4)          # 从中心展开 ⇒ 出生半径为 0
	_fx.append({"node": n, "t": 0.0, "life": maxf(0.05, life), "kind": "rain_ring",
		"r_full": maxf(1e-4, radius_px * float(battle.WS))})
	return n


## 标定圈的归一半径包络: 0→1 展开, 中段常驻 1, 末段收回 0。
## ★纯函数, 门禁直接采样(演出与判据同源)。life 是整轮时长。
static func rain_ring_scale(t: float, life: float) -> float:
	var L: float = maxf(life, 0.01)
	if t <= RAIN_OPEN_SEC:
		# 展开带一点过冲(1.06 → 1.0), 看着是"甩开"而不是"吹气球"
		var u: float = clampf(t / RAIN_OPEN_SEC, 0.0, 1.0)
		return sin(u * PI * 0.5) * (1.0 + 0.06 * (1.0 - u))
	if t >= L - RAIN_CLOSE_SEC:
		var v: float = clampf((L - t) / RAIN_CLOSE_SEC, 0.0, 1.0)
		return v * v                              # 收拢是加速的(末段"啪"地闭合)
	return 1.0


## 一波落箭 —— **每支箭是一个会飞的实体**(2026-08-12 重做; 旧版是一条静止的光迹,
## 用户实拍判语「完全看不到箭在动」)。
##   · 位置走自由落体抛物线: 水平匀速, 竖直 y = h(1 − u²) ⇒ 越接近地面掉得越快
##   · 箭身【朝速度方向】: 出发时斜, 落地时几乎垂直 —— 所以是"扎"下来
##   · 地面有影子, 随高度收小变深 ⇒ 观众在箭还没到时就知道它要落在哪
## ★落点用二维正态散布(Rayleigh 半径), 不是均匀随机。
## 返回本波真正建出来的箭节点数(门禁分母)。
func rain_arrows(center: Vector2, radius_px: float, n_arrows: int) -> int:
	if not _has_world():
		return 0
	var sigma: float = radius_px / RAIN_SIGMA_DIV
	## ★网格只建一次(同一轮雨里每支箭形状一样, 差的只是变换) —— 一轮 6 跳 × 7 支 = 42 支,
	##   不缓存就是 42 次现算几何(手机端预算同 shockwave_vfx)。
	if _mesh_rain == null:
		_mesh_rain = _build_flying_arrow()
	if _mesh_shadow == null:
		_mesh_shadow = _build_shadow_disc()
	if _mesh_trail == null:
		_mesh_trail = _build_trail()
	var made := 0
	for i in range(maxi(0, n_arrows)):
		var off: Vector2 = scatter_offset(sigma)
		if off.length() > radius_px:
			off = off.normalized() * radius_px
		var land: Vector2 = center + off
		## 来向: **整波同一个方向**(齐射), 只留极小的确定性抖动免得像复制粘贴的一排。
		## ★不是每支一个方向 —— 那会变成"四面八方射过来", 用户已明确否掉。
		var yaw: float = RAIN_VOLLEY_YAW + float(i % 3) * 0.02 - 0.02
		var m := _mat(true, 12)
		m.albedo_color = Color(SILVER_HI.r, SILVER_HI.g, SILVER_HI.b, 1.0)
		var node := _node(_mesh_rain, m, battle._world_pos(land, 0.0), "rain_arrow")
		var ms := _mat(true, 10)
		ms.albedo_color = Color(SILVER_LO.r, SILVER_LO.g, SILVER_LO.b, 0.5)
		var sh := _node(_mesh_shadow, ms, battle._world_pos(land, 0.0), "rain_shadow")
		var mt := _mat(true, 11)
		mt.albedo_color = Color(SILVER_MID.r, SILVER_MID.g, SILVER_MID.b, 0.9)
		var tr := _node(_mesh_trail, mt, battle._world_pos(land, 0.0), "rain_trail")
		## ★寿命只到落地那一刻: 落地时换成【插在地上的箭】(见 tick), 不是原地淡没
		_fx.append({"node": node, "shadow": sh, "trail": tr, "t": 0.0, "life": RAIN_FLY_SEC,
			"kind": "rain_fly", "land": land, "yaw": yaw})
		made += 1
	return made


## 单支箭的归一飞行(u ∈ 0..1): 返回 [水平回退比例, 高度比例]。
## **固定斜角直线** + 加速走线: 两个分量同为 1 − u² ⇒ 轨迹是直的(入射角恒 60°),
## 而速度随 u 线性增大(位移 ∝ u²) ⇒ 越接近地面越快, 这就是"扎"的手感。
## ★纯函数: 演出与门禁同源(门禁量真实节点位置, 对照这个函数)。
static func rain_fly_at(u: float) -> Vector2:
	var uu: float = clampf(u, 0.0, 1.0)
	var s: float = uu * uu                      # 走线进度(加速)
	return Vector2(1.0 - s, 1.0 - s)


## 会飞的箭(局部坐标: 原点 = 箭尖, 箭沿 +Y 向上延伸 ⇒ 摆放时把 +Y 转到"来向")。
## 头 + 杆 + 两片尾羽, 十字双面 —— 从任何角度看都是一支箭而不是一条线。
static func _build_flying_arrow() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L: float = 1.0                      # 单位长, 摆放时按 RAIN_ARROW_LEN 缩放
	var hi := Color(1, 1, 1, 1.0)
	var mid := Color(1, 1, 1, 0.75)
	var tail := Color(1, 1, 1, 0.35)
	for axis in [Vector3(0.055, 0, 0), Vector3(0, 0, 0.055)]:
		# 杆: 尖(0) → 尾(L)
		var a := [Vector3.ZERO + axis * 0.35, hi]
		var b := [Vector3(0, L, 0) + axis * 0.35, tail]
		var c := [Vector3(0, L, 0) - axis * 0.35, tail]
		var d := [Vector3.ZERO - axis * 0.35, hi]
		_tri(st, a, b, c)
		_tri(st, a, c, d)
		# 箭头: 尖在原点的三角
		_tri(st, [Vector3.ZERO, hi], [Vector3(0, 0.22, 0) + axis * 1.9, mid],
			[Vector3(0, 0.22, 0) - axis * 1.9, mid])
		# 尾羽: 杆尾两片
		_tri(st, [Vector3(0, L, 0), mid], [Vector3(0, L * 0.74, 0) + axis * 1.7, tail],
			[Vector3(0, L * 0.80, 0), tail])
		_tri(st, [Vector3(0, L, 0), mid], [Vector3(0, L * 0.74, 0) - axis * 1.7, tail],
			[Vector3(0, L * 0.80, 0), tail])
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


## 拖尾网格(局部: 原点 = 箭尖端, 沿 +Y 拉长一个单位; 头亮尾透, 十字双面)。
## 摆放时 scale.y = 已飞过的距离 ⇒ 它画的就是真实路径, 不是凭感觉加的一条带子。
static func _build_trail() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var head := Color(1, 1, 1, 0.85)
	var mid := Color(1, 1, 1, 0.28)
	var tail := Color(1, 1, 1, 0.0)
	for axis in [Vector3(0.055, 0, 0), Vector3(0, 0, 0.055)]:
		# 分两段: 近端粗而亮, 远端收细并透明 —— 拖尾是"越远越淡", 不是等宽亮带
		for seg in [[0.0, 0.45, head, mid, 1.0, 0.62], [0.45, 1.0, mid, tail, 0.62, 0.10]]:
			var y0: float = float(seg[0])
			var y1: float = float(seg[1])
			var c0: Color = seg[2]
			var c1: Color = seg[3]
			var w0: float = float(seg[4])
			var w1: float = float(seg[5])
			var a := [Vector3(0, y0, 0) + axis * w0, c0]
			var b := [Vector3(0, y1, 0) + axis * w1, c1]
			var c := [Vector3(0, y1, 0) - axis * w1, c1]
			var d := [Vector3(0, y0, 0) - axis * w0, c0]
			_tri(st, a, b, c)
			_tri(st, a, c, d)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


## 落地: 把箭插在地上(保持入射角) + 一圈落尘。**插着的那支**由 holdfade 淡出,
## 所以观众看到的是"扎进地里 → 慢慢消散", 而不是飞到一半凭空没了。
## 返回插好的箭节点(门禁拿它验"落地后现场还有东西")。
func _plant_arrow(land: Vector2, yaw: float, fly_basis: Basis) -> MeshInstance3D:
	if not _has_world():
		return null
	var m := _mat(true, 12)
	m.albedo_color = Color(SILVER_MID.r, SILVER_MID.g, SILVER_MID.b, 0.95)
	var n := _node(_mesh_rain, m, battle._world_pos(land, 0.0), "rain_stuck")
	## 姿态沿用飞行末帧的朝向(同一入射角), 只把速度拉伸去掉 ⇒ 看着就是刚扎进去那一支
	n.transform.basis = fly_basis.orthonormalized().scaled(
		Vector3.ONE * (RAIN_ARROW_LEN * float(battle.WS)))
	_fx.append({"node": n, "t": 0.0, "life": RAIN_STUCK_SEC, "kind": "rain_stuck"})
	## 落尘: 贴地小环, 半径比影子稍大, 快速散掉
	if _mesh_shadow != null:
		var md := _mat(true, 10)
		md.albedo_color = Color(SILVER_HI.r, SILVER_HI.g, SILVER_HI.b, 0.55)
		var d := _node(_mesh_shadow, md, battle._world_pos(land, 0.0), "rain_dust")
		var dr: float = 22.0 * float(battle.WS)
		d.scale = Vector3(dr, dr, dr)
		_fx.append({"node": d, "t": 0.0, "life": 0.26, "kind": "rain_dust"})
	return n


## 地面影子(单位半径的贴地圆盘, 中心深外沿淡)
static func _build_shadow_disc() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(24):
		var t0: float = float(j) / 24.0 * TAU
		var t1: float = float(j + 1) / 24.0 * TAU
		_tri(st, [Vector3(0, GROUND_Y, 0), Color(1, 1, 1, 0.9)],
			[Vector3(cos(t0), GROUND_Y, sin(t0)), Color(1, 1, 1, 0.0)],
			[Vector3(cos(t1), GROUND_Y, sin(t1)), Color(1, 1, 1, 0.0)])
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


## 单支落箭的网格(局部坐标: 原点 = 落点)。从上风侧 run 码、h_px 码高处扎下来,
## 落地角 = 发射仰角 60° (无阻力斜抛的对称性) —— 所以它是【扎】下来而不是飘下来。
## ★2026-08-11 补验收: 加了箭头(尖恰在落点)与尾羽(杆长 65% 处两对) —— 旧版是无头裸线,
##   实拍读成"一把划痕"不是"一场箭雨"(验收口径「箭就是箭」)。
## ⚠ 新几何全部收在旧 AABB 之内: 门禁量的是"起点高 = 抛物线顶点 + 光带半宽", 头/羽都比它低。
func _build_rain_arrow(run: float, h_px: float) -> ArrayMesh:
	var ws: float = float(battle.WS)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(1, 1, 1, 1)
	var half: float = 2.4 * ws
	var a := Vector3(-run * ws, h_px * ws, 0.0)
	var b := Vector3(0.0, GROUND_Y, 0.0)
	for axis in [Vector3(0.0, 0.0, half), Vector3(0.0, half, 0.0)]:
		var p0 := [a - axis, Color(col.r, col.g, col.b, 0.0)]
		var p1 := [a + axis, Color(col.r, col.g, col.b, 0.0)]
		var p2 := [b + axis, col]
		var p3 := [b - axis, col]
		_tri(st, p0, p1, p2)
		_tri(st, p0, p2, p3)
	## 箭头: 沿杆向的双面三角尖(两个正交平面各一片), 尖恰在落点 b
	var dirv: Vector3 = (b - a).normalized()
	var side := Vector3(0.0, 0.0, 1.0)
	var up2: Vector3 = dirv.cross(side).normalized()
	var neck: Vector3 = b - dirv * (14.0 * ws)
	for hx in [side * (half * 2.6), up2 * (half * 2.6)]:
		_tri(st, [neck - hx, col], [neck + hx, col], [b, col])
	## 尾羽: 杆长 65% 处(alpha 梯度到这已有 ~0.65)两对小斜羽, 斜向后、尖端渐隐
	var tail: Vector3 = a + (b - a) * 0.65
	var fcol := Color(col.r, col.g, col.b, 0.65)
	for fx in [side, up2]:
		for sgn in [1.0, -1.0]:
			var tip2: Vector3 = tail - dirv * (10.0 * ws) + fx * (float(sgn) * 7.0 * ws)
			_tri(st, [tail - dirv * (2.5 * ws), fcol], [tail + dirv * (2.5 * ws), fcol],
				[tip2, Color(col.r, col.g, col.b, 0.0)])
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


# ══════════════════════════════════════════════════════════════════
#  §076 贯穿光迹
# ══════════════════════════════════════════════════════════════════

## 一发贯穿箭的光迹。`cuts` 是沿程各命中点的**行程比例**(升序, ∈[0,1]) ——
## 每穿过一个人, 后面那一段的 alpha 就掉到 `tracer_alpha(已穿人数)`。
## ★alpha 直接取 `pierce_mult` —— 与伤害倍率同一个函数, 不抄第二遍。
## 一发贯穿弩矢 —— **飞出去**, 不是一条瞬时铺满的线(2026-08-12 用户: 「像激光…我需要箭和尾迹」)。
## 每帧推进: 弩矢本体 + 身后尾迹(已飞过的那段, 封顶) + 飞到哪个命中点才炸哪个 X。
## ★命中点的 alpha 仍取 tracer_alpha(同一个事实源: 打到第 k 人的那份伤害), 只是【时机】跟着弩矢走。
## 返回弩矢节点(门禁量它的真实位移)。
func pierce_tracer(from: Vector2, dir: Vector2, len_px: float, cuts: Array) -> MeshInstance3D:
	if not _has_world():
		return null
	var d: Vector2 = dir
	if d.length() < 1e-6:
		d = Vector2.RIGHT
	d = d.normalized()
	if _mesh_bolt == null:
		_mesh_bolt = _build_flying_arrow()
	if _mesh_trail == null:
		_mesh_trail = _build_trail()
	var col := Color(1.0, 0.72, 0.35)
	var m := _mat(true, 12)
	m.albedo_color = Color(col.r, col.g, col.b, 1.0)
	var n := _node(_mesh_bolt, m, battle._world_pos(from, 0.75), "bolt")
	var mt := _mat(true, 11)
	mt.albedo_color = Color(col.r, col.g, col.b, 0.85)
	var tr := _node(_mesh_trail, mt, battle._world_pos(from, 0.75), "bolt_trail")
	## 弩矢朝向: +Y 指向【来处】(与 075 的箭同一套朝向约定) ⇒ 尖端朝飞行方向
	var fwd := Vector3(d.x, 0.0, d.y)
	var up_dir: Vector3 = -fwd
	var side: Vector3 = up_dir.cross(Vector3.UP).normalized()
	var fwd2: Vector3 = side.cross(up_dir).normalized()
	var basis := Basis(side, up_dir, fwd2)
	n.transform.basis = basis.scaled(Vector3.ONE * (BOLT_LEN * float(battle.WS)))
	tr.transform.basis = basis
	_fx.append({"node": n, "trail": tr, "t": 0.0, "life": maxf(0.05, len_px / BOLT_SPEED),
		"kind": "bolt", "from": from, "dir": d, "len": len_px, "cuts": (cuts as Array).duplicate(),
		"fired": 0})
	return n

## 弩矢经过某个命中点时的记号: 一枚 X 形爆点(alpha = 打到第 k 人的那份伤害 —— 同一事实源)。
## ★与旧版的差别只在【时机】: 旧版一发射出就把所有 X 全画上(激光式), 现在是箭到才炸。
func _bolt_hit_mark(at: Vector2, dirn: Vector2, k: int) -> MeshInstance3D:
	if not _has_world():
		return null
	var d: Vector2 = dirn.normalized()
	var perp: Vector2 = Vector2(-d.y, d.x)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a: float = tracer_alpha(k)
	var col := Color(1.0, 0.86, 0.55, a)
	var ya: float = 0.75
	var arm: float = 26.0
	var w: float = 4.0
	for axis in [[d, perp], [perp, d]]:
		var ax: Vector2 = axis[0]
		var px: Vector2 = axis[1]
		var p0 := [battle._world_pos(at - ax * arm - px * w, ya), col]
		var p1 := [battle._world_pos(at - ax * arm + px * w, ya), col]
		var p2 := [battle._world_pos(at + ax * arm + px * w, ya), col]
		var p3 := [battle._world_pos(at + ax * arm - px * w, ya), col]
		_tri(st, p0, p1, p2)
		_tri(st, p0, p2, p3)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	var m := _mat(true, 13)
	m.albedo_color = Color(1, 1, 1, 1)
	var n := _node(mesh, m, Vector3.ZERO, "bolt_hit")
	_fx.append({"node": n, "t": 0.0, "life": 0.30, "kind": "bolt_hit"})
	return n


## 贯穿的【读数强化】(2026-08-11 补验收, 与光迹同寿命):
## · 每个命中点一枚 X 形爆点 —— "这一发穿过了几个人"从亮度台阶变成数得出的记号
## · 线末端一枚弩矢镖(菱形头 + 双尾翼) —— 光迹是弩箭飞过的路, 镖是那支箭本身
##   (旧版整条匀亮细线, 实拍读成"激光"不是"弩机连发"; 验收口径「弩就是弩」)。
## ★alpha 仍取 tracer_alpha(同一个事实源): 爆点 k 用 tracer_alpha(k)(打到第 k 人的那份伤害),
##   镖用 tracer_alpha(cuts.size())(穿完所有人之后剩下的那份)。
func _pierce_hits(from: Vector2, dirn: Vector2, len_px: float, cuts: Array) -> MeshInstance3D:
	if not _has_world():
		return null
	var d: Vector2 = dirn.normalized()
	var perp: Vector2 = Vector2(-d.y, d.x)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ya: float = 0.75
	var col := Color(1.0, 0.84, 0.45)
	for k in range(cuts.size()):
		var c0: Vector2 = from + d * (len_px * clampf(float(cuts[k]), 0.0, 1.0))
		var a: float = tracer_alpha(k)
		for ang in [0.7853981633974483, 2.356194490192345]:   # ±45°: X 形的两根斜杆(π/4 与 3π/4)
			var ax: Vector2 = (d * cos(float(ang)) + perp * sin(float(ang))) * 13.0
			var aw: Vector2 = Vector2(-ax.y, ax.x).normalized() * 2.6
			_tri(st, [battle._world_pos(c0 - ax - aw, ya), Color(col.r, col.g, col.b, a)],
				[battle._world_pos(c0 - ax + aw, ya), Color(col.r, col.g, col.b, a)],
				[battle._world_pos(c0 + ax + aw, ya), Color(col.r, col.g, col.b, a)])
			_tri(st, [battle._world_pos(c0 - ax - aw, ya), Color(col.r, col.g, col.b, a)],
				[battle._world_pos(c0 + ax + aw, ya), Color(col.r, col.g, col.b, a)],
				[battle._world_pos(c0 + ax - aw, ya), Color(col.r, col.g, col.b, a)])
	## 弩矢镖: 菱形头(尖在线末端) + 两片斜尾翼
	var tip: Vector2 = from + d * len_px
	var mid: Vector2 = tip - d * 26.0
	var back: Vector2 = tip - d * 40.0
	var da: float = tracer_alpha(cuts.size())
	var wv: Vector2 = perp * 6.0
	_tri(st, [battle._world_pos(mid - wv, ya), Color(col.r, col.g, col.b, da)],
		[battle._world_pos(mid + wv, ya), Color(col.r, col.g, col.b, da)],
		[battle._world_pos(tip, ya), Color(col.r, col.g, col.b, da)])
	for s in [1.0, -1.0]:
		_tri(st, [battle._world_pos(mid, ya), Color(col.r, col.g, col.b, da)],
			[battle._world_pos(back + perp * (11.0 * float(s)), ya), Color(col.r, col.g, col.b, da * 0.6)],
			[battle._world_pos(back, ya), Color(col.r, col.g, col.b, da * 0.8)])
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	var n := _node(mesh, _mat(true, 14), Vector3.ZERO, "pierce_hits")
	n.set_meta("cuts_n", cuts.size())
	_fx.append({"node": n, "t": 0.0, "life": 0.22, "kind": "pierce_hits"})
	return n


# ══════════════════════════════════════════════════════════════════
#  §生命周期 —— 不用 tween, 走 sim 的 delta
# ══════════════════════════════════════════════════════════════════

## 每帧推进所有短命特效(holdfade + 到期 free)。
## ★2026-08-11 两处修正(实拍复核后):
##   ① 淡出改【holdfade】—— 前 FADE_HOLD(70%) 寿命满亮, 只在最后 30% 线性收掉。
##      旧版从出生就 1−t/life, 采样到的永远是半亮(藤蔓箭 9 张实拍 0 张可见的主因之一)。
##   ② 乘的是【出生时那份 alpha】(a0), 不是 1.0 —— 旧版第一帧就把作者调好的基础透明度
##      顶掉(落区环 albedo 0.55 一进 tick 变 ~1.0, "调的数字根本没上过屏")。
func tick(delta: float) -> void:
	if _fx.is_empty():
		return
	var keep: Array = []
	for h in _fx:
		var n = h["node"]
		if not is_instance_valid(n):
			continue
		var t: float = float(h["t"]) + maxf(0.0, delta)
		h["t"] = t
		var life: float = maxf(0.01, float(h["life"]))
		if t >= life:
			var sh0 = h.get("shadow", null)
			if is_instance_valid(sh0):
				sh0.queue_free()
			var tr0 = h.get("trail", null)
			if is_instance_valid(tr0):
				tr0.queue_free()
			## ★飞行结束 = 落地那一刻 ⇒ 把箭【插在地上】+ 掀起落尘, 再由 holdfade 慢慢淡。
			##   (2026-08-12 用户:「不能凭空消失」—— 旧版飞完原地淡掉, 读起来就是凭空没了。)
			if str(h.get("kind", "")) == "rain_fly":
				_plant_arrow(h.get("land", Vector2.ZERO), float(h.get("yaw", 0.0)), n.transform.basis)
			## ★弩矢出列时把【还没炸的命中点】补齐 —— 一帧跨过整段行程(卡顿/低帧率)时
			##   否则会静默吞掉记号: 玩家看到"穿了 3 个人却只有 1 个爆点"。判据不能依赖帧率。
			if str(h.get("kind", "")) == "bolt":
				var cuts_e: Array = h.get("cuts", [])
				var fired_e: int = int(h.get("fired", 0))
				var from_e: Vector2 = h.get("from", Vector2.ZERO)
				var dir_e: Vector2 = h.get("dir", Vector2.RIGHT)
				var len_e: float = float(h.get("len", 0.0))
				while fired_e < cuts_e.size():
					_bolt_hit_mark(from_e + dir_e * (len_e * float(cuts_e[fired_e])), dir_e, fired_e)
					fired_e += 1
				h["fired"] = fired_e
			n.queue_free()
			continue
		## 075 标定圈: 展开 → 常驻 → 往中间关闭(用户 2026-08-12 点名的三段)
		if str(h.get("kind", "")) == "rain_ring":
			var rf: float = float(h.get("r_full", 1.0))
			var k2: float = rain_ring_scale(t, life)
			var rr: float = maxf(1e-4, rf * k2)
			n.scale = Vector3(rr, rr, rr)
			n.rotation.y = t * RAIN_FIELD_SPIN          # 刻度层缓旋: 标定盘在"读数"
		## 075 落箭: 真的在飞 —— 位置走抛物线、箭身朝速度方向、地上有影子
		if str(h.get("kind", "")) == "rain_fly":
			var u2: float = clampf(t / RAIN_FLY_SEC, 0.0, 1.0)
			var f: Vector2 = rain_fly_at(u2)
			var yaw: float = float(h.get("yaw", 0.0))
			var land2: Vector2 = h.get("land", Vector2.ZERO)
			var back: Vector2 = Vector2(cos(yaw), sin(yaw)) * (RAIN_FLY_RUN * f.x)
			var hgt: float = RAIN_FLY_H * f.y * float(battle.WS)
			n.position = battle._world_pos(land2 + back, 0.0) + Vector3.UP * hgt
			## 朝向 = 那条固定斜线的反向(箭尖朝落点)。整段同一个角 ⇒ "斜着射入"。
			## ★箭身按当前速度拉长(v ∝ u): 越快越长 —— 静止的箭是看不出速度的。
			var dirw := Vector3(cos(yaw) * RAIN_FLY_RUN, RAIN_FLY_H, sin(yaw) * RAIN_FLY_RUN)
			if dirw.length() > 1e-6:
				var up_dir: Vector3 = dirw.normalized()          # 箭的 +Y = 从尾指向来处
				var axis_ref: Vector3 = Vector3.RIGHT if absf(up_dir.y) > 0.98 else Vector3.UP
				var side2: Vector3 = up_dir.cross(axis_ref).normalized()
				var fwd2: Vector3 = side2.cross(up_dir).normalized()
				var stretch: float = 1.0 + 1.15 * u2
				n.transform.basis = Basis(side2, up_dir, fwd2).scaled(
					Vector3(1.0, stretch, 1.0) * (RAIN_ARROW_LEN * float(battle.WS)))
			## 拖尾: 与箭同向, 长度 = 【已经飞过的距离】(封顶), 所以它画的就是走过的那段路径
			var tr2 = h.get("trail", null)
			if is_instance_valid(tr2):
				tr2.position = n.position
				tr2.transform.basis = n.transform.basis.orthonormalized()
				var flown: float = (RAIN_FLY_H / sin(deg_to_rad(60.0))) * (1.0 - f.y)
				var tl: float = minf(flown, RAIN_TRAIL_MAX) * float(battle.WS)
				tr2.scale = Vector3(1.0, maxf(tl, 1e-4), 1.0)
			var sh2 = h.get("shadow", null)
			if is_instance_valid(sh2):
				# 影子: 箭越低越小越深(观众提前看得出落点)
				var sr: float = (10.0 + 26.0 * f.y) * float(battle.WS)
				sh2.scale = Vector3(sr, sr, sr)
				var sm2 = sh2.material_override
				if sm2 is StandardMaterial3D:
					(sm2 as StandardMaterial3D).albedo_color = Color(SILVER_LO.r, SILVER_LO.g,
						SILVER_LO.b, 0.18 + 0.42 * (1.0 - f.y))
				if u2 >= 1.0:
					sh2.queue_free()
					h["shadow"] = null
		## 076 弩矢: 沿直线匀速飞 + 身后尾迹 + 飞到哪个命中点才炸哪个 X
		if str(h.get("kind", "")) == "bolt":
			var u3: float = clampf(t / life, 0.0, 1.0)
			var from3: Vector2 = h.get("from", Vector2.ZERO)
			var d3: Vector2 = h.get("dir", Vector2.RIGHT)
			var travelled: float = float(h.get("len", 0.0)) * u3
			var pos3: Vector2 = from3 + d3 * travelled
			n.position = battle._world_pos(pos3, 0.75)
			var tr3 = h.get("trail", null)
			if is_instance_valid(tr3):
				tr3.position = n.position
				var tl3: float = minf(travelled, BOLT_TRAIL_MAX) * float(battle.WS)
				tr3.scale = Vector3(1.0, maxf(tl3, 1e-4), 1.0)
			## 命中点: 弩矢经过谁, 谁那一刻炸 X(不是开场全亮 —— 那是激光的读法)
			var cuts3: Array = h.get("cuts", [])
			var fired: int = int(h.get("fired", 0))
			while fired < cuts3.size() and u3 >= float(cuts3[fired]):
				var hp3: Vector2 = from3 + d3 * (float(h.get("len", 0.0)) * float(cuts3[fired]))
				_bolt_hit_mark(hp3, d3, fired)
				fired += 1
			h["fired"] = fired
		## 074 护盾破裂的骨片: 向外飞(带阻力) + 重力下落 + 翻滚。位移在这里推,
		## 淡出仍走下面那段公用逻辑(前 FADE_HOLD 满亮)。
		if str(h.get("kind", "")) == "shard":
			var dirn: Vector3 = h.get("dir", Vector3.UP)
			var c0: Vector3 = h.get("c", Vector3.ZERO)
			var sp: float = DOME_R_PX * float(battle.WS) * 2.6
			var rr: float = sp * 0.22 * (1.0 - exp(-t / 0.18))     # 带阻力的外飞
			var drop: float = 2.2 * t * t                          # 重力下落(归一世界单位)
			n.position = c0 + dirn * rr + Vector3.DOWN * drop * float(battle.WS) * 34.0
			n.rotation = Vector3(t * 5.1, t * 3.7, t * 2.3)
		var m = n.material_override
		if m is StandardMaterial3D:
			var c: Color = (m as StandardMaterial3D).albedo_color
			if not h.has("a0"):
				h["a0"] = c.a          # 首帧记下出生 alpha, 之后所有淡出都以它为基准
			var x: float = t / life
			var k: float = 1.0 if x < FADE_HOLD else (1.0 - x) / (1.0 - FADE_HOLD)
			(m as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, float(h["a0"]) * maxf(0.0, k))
		keep.append(h)
	_fx = keep


## 撤掉某个单位身上的**常驻件**(藤蔓小球 + 骨甲片), 返回 free 掉几个。
##
## ★为什么需要它: 换路时 `_dl_clear_units()` 只 free 单位自己的 sprite/bar,
##   **不会动挂在 `_world` 上的节点**(SynergyVfx.clear 的注释记的就是这个)。
##   而给 `dual_lane_flow.gd` 加一行 clear 要动 `scripts/scenes/battle/*` 的既有文件(本批不许碰)
##   ⇒ 改成 `EqBowBatch` 每 0.5 秒自扫: 主人已经不在 `battle._units` 里就撤掉。
func detach(u: Dictionary) -> int:
	var freed := 0
	var n = u.get("_vine_orb", null)
	if is_instance_valid(n):
		n.queue_free()
		freed += 1
	u.erase("_vine_orb")
	u.erase("_vine_orb_pos")
	u.erase("_vine_orb_vel")
	for p in u.get("_bone_plates", []):
		if is_instance_valid(p):
			p.queue_free()
			freed += 1
	u.erase("_bone_plates")
	## 074 护盾罩(2026-08-12): 换路自扫也要把罩子收掉, 否则"人走了罩子还在"
	var dh = u.get("_bone_dome", null)
	if dh is Dictionary:
		var dn = (dh as Dictionary).get("shell", null)
		if is_instance_valid(dn):
			dn.queue_free()
			freed += 1
		u.erase("_bone_dome")
	return freed


## 撤场: free 掉本层还活着的所有节点, 返回真的 free 了几个。
func clear() -> int:
	var freed := 0
	for n in _owned:
		if is_instance_valid(n):
			n.queue_free()
			freed += 1
	_owned.clear()
	_fx.clear()
	return freed
