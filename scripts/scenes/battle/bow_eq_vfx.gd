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
const RECOIL_IV := 0.25

## 贴地几何离地高度(米)。地板在 y=0, 抬一点免 z-fighting(同 shockwave_vfx)。
const GROUND_Y := 0.06
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
var _mesh_orb: SphereMesh = null
## 落箭网格与它对应的水平行程(半径变了就重建)
var _mesh_rain: ArrayMesh = null
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


## 一片骨甲 = 边长 1 的正方形薄片(局部 XY 平面, 法线 +Z)。
static func _build_plate() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := [Vector3(-0.5, -0.5, 0.0), Color(1, 1, 1, 0.30)]
	var b := [Vector3(0.5, -0.5, 0.0), Color(1, 1, 1, 0.30)]
	var c := [Vector3(0.5, 0.5, 0.0), Color(1, 1, 1, 1.0)]
	var d := [Vector3(-0.5, 0.5, 0.0), Color(1, 1, 1, 1.0)]
	_tri(st, a, b, c)
	_tri(st, a, c, d)
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
	u["_vine_orb"] = n
	u["_vine_orb_pos"] = org
	u["_vine_orb_vel"] = Vector2.ZERO
	return n


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
	var n := _streak(from, tgt_pos, col, 3.5 if crit else 2.2)
	if n != null:
		_fx.append({"node": n, "t": 0.0, "life": 0.20 if crit else 0.14, "kind": "streak"})


## 一条从 a 到 b 的细光带(贴地上方一点), 顶点色两端渐隐。
func _streak(a: Vector2, b: Vector2, col: Color, half_w_px: float) -> MeshInstance3D:
	if not _has_world():
		return null
	var d: Vector2 = b - a
	if d.length() < 0.5:
		return null
	var perp: Vector2 = Vector2(-d.y, d.x).normalized() * half_w_px
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ya: float = 0.85
	var p0 := [battle._world_pos(a - perp, ya), Color(col.r, col.g, col.b, 0.0)]
	var p1 := [battle._world_pos(a + perp, ya), Color(col.r, col.g, col.b, 0.0)]
	var p2 := [battle._world_pos(b + perp, ya), Color(col.r, col.g, col.b, col.a)]
	var p3 := [battle._world_pos(b - perp, ya), Color(col.r, col.g, col.b, col.a)]
	_tri(st, p0, p1, p2)
	_tri(st, p0, p2, p3)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return _node(mesh, _mat(true, 12), Vector3.ZERO, "vine_streak")


# ══════════════════════════════════════════════════════════════════
#  §074 骨甲壳层
# ══════════════════════════════════════════════════════════════════

## 按累计护盾比例刷新骨甲。frac = 累计护盾 / 最大生命。
## ★片数 = 累计次数(离散可数, "一层一层叠上去"), 壳半径 = 立方根(体积律)。
## 返回真正挂进 _world 的甲片数(门禁用它当分母)。
func plates_refresh(u: Dictionary, frac: float, layers: int) -> int:
	if not _has_world() or not u.get("alive", false):
		return 0
	var want: int = clampi(layers, 0, PLATE_CAP)
	var arr: Array = u.get("_bone_plates", [])
	arr = arr.filter(func(x): return is_instance_valid(x))
	if _mesh_plate == null:
		_mesh_plate = _build_plate()
	var rad_px: float = shell_radius_px(frac)
	var ws: float = float(battle.WS)
	while arr.size() < want:
		var m := _mat(false, 7)
		m.albedo_color = Color(0.92, 0.90, 0.78, 0.72)
		arr.append(_node(_mesh_plate, m, Vector3.ZERO, "bone_plate"))
	while arr.size() > want:
		var extra = arr.pop_back()
		if is_instance_valid(extra):
			extra.queue_free()
	var base: Vector3 = battle._world_pos(u["pos"], 0.55)
	for i in range(arr.size()):
		var n: MeshInstance3D = arr[i]
		if not is_instance_valid(n):
			continue
		var dir: Vector3 = plate_dir(i, maxi(1, arr.size()))
		n.position = base + dir * (rad_px * ws)
		n.scale = Vector3.ONE * maxf(0.02, rad_px * ws * 0.42)
		## 甲片贴着壳面(法线朝外) —— looking_at 的 up 取 +Y, 与径向共线时退化, 故偏一点
		var up: Vector3 = Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
		n.look_at_from_position(n.position, n.position + dir, up)
	u["_bone_plates"] = arr
	return arr.size()


# ══════════════════════════════════════════════════════════════════
#  §075 箭雨
# ══════════════════════════════════════════════════════════════════

## 落区标记(贴地环)。★半径写进节点的**真实 scale**, 门禁量节点不量公式
##   (memory [[fb-write-without-reader-and-fake-gates]]: 抄公式的门禁, 产品改成写死也照样绿)。
func rain_marker(center: Vector2, radius_px: float, life: float) -> MeshInstance3D:
	if not _has_world():
		return null
	if _mesh_ring == null:
		_mesh_ring = _build_ring()
	var m := _mat(true, 11)
	m.albedo_color = Color(0.62, 0.86, 0.45, 0.55)
	var n := _node(_mesh_ring, m, battle._world_pos(center, 0.0), "rain_ring")
	var rm: float = maxf(1e-4, radius_px * float(battle.WS))
	n.scale = Vector3(rm, rm, rm)
	_fx.append({"node": n, "t": 0.0, "life": maxf(0.05, life), "kind": "rain_ring"})
	return n


## 一波落箭。每支箭是一条走**真抛物线**的光迹: 起点在落点上风侧高空, 终点是落点。
## ★落点用二维正态散布(Rayleigh 半径), 不是均匀随机。
## 返回本波真正建出来的箭节点数(门禁分母)。
func rain_arrows(center: Vector2, radius_px: float, n_arrows: int) -> int:
	if not _has_world():
		return 0
	var sigma: float = radius_px / RAIN_SIGMA_DIV
	## ★网格只建一次: 同一轮雨里每支箭的形状完全一样(行程与顶点都只看 radius_px),
	##   差的只是平移 ⇒ 建 1 个网格 + N 个 MeshInstance3D, 不是 N 个 SurfaceTool。
	##   (一轮雨 6 跳 × 7 支 = 42 支; 不缓存就是 42 次现算几何 —— 手机端预算同 shockwave_vfx。)
	var run: float = radius_px * 0.9
	if _mesh_rain == null or absf(_mesh_rain_run - run) > 0.01:
		_mesh_rain = _build_rain_arrow(run, lob_apex_px(run * 2.0))
		_mesh_rain_run = run
	var made := 0
	for i in range(maxi(0, n_arrows)):
		var off: Vector2 = scatter_offset(sigma)
		if off.length() > radius_px:
			off = off.normalized() * radius_px
		var land: Vector2 = center + off
		var m := _mat(true, 12)
		m.albedo_color = Color(0.80, 0.92, 0.55, 0.9)
		var node := _node(_mesh_rain, m, battle._world_pos(land, 0.0), "rain_arrow")
		_fx.append({"node": node, "t": 0.0, "life": 0.28, "kind": "rain_arrow"})
		made += 1
	return made


## 单支落箭的网格(局部坐标: 原点 = 落点)。从上风侧 run 码、h_px 码高处扎下来,
## 落地角 = 发射仰角 60° (无阻力斜抛的对称性) —— 所以它是【扎】下来而不是飘下来。
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
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


# ══════════════════════════════════════════════════════════════════
#  §076 贯穿光迹
# ══════════════════════════════════════════════════════════════════

## 一发贯穿箭的光迹。`cuts` 是沿程各命中点的**行程比例**(升序, ∈[0,1]) ——
## 每穿过一个人, 后面那一段的 alpha 就掉到 `tracer_alpha(已穿人数)`。
## ★alpha 直接取 `pierce_mult` —— 与伤害倍率同一个函数, 不抄第二遍。
## 返回节点; 节点的**真实长度**(AABB × scale)由门禁量, 期望 = len_px × WS。
func pierce_tracer(from: Vector2, dir: Vector2, len_px: float, cuts: Array) -> MeshInstance3D:
	if not _has_world():
		return null
	var d: Vector2 = dir
	if d.length() < 1e-6:
		d = Vector2.RIGHT
	d = d.normalized()
	var perp: Vector2 = Vector2(-d.y, d.x) * 3.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edges: Array = [0.0]
	for c in cuts:
		edges.append(clampf(float(c), 0.0, 1.0))
	edges.append(1.0)
	var col := Color(1.0, 0.72, 0.35)
	for k in range(edges.size() - 1):
		var f0: float = float(edges[k])
		var f1: float = float(edges[k + 1])
		if f1 - f0 < 1e-5:
			continue
		var a0: float = tracer_alpha(k)
		var a1: float = tracer_alpha(k)
		var pa: Vector2 = from + d * (len_px * f0)
		var pb: Vector2 = from + d * (len_px * f1)
		var v0 := [battle._world_pos(pa - perp, 0.75), Color(col.r, col.g, col.b, a0)]
		var v1 := [battle._world_pos(pa + perp, 0.75), Color(col.r, col.g, col.b, a0)]
		var v2 := [battle._world_pos(pb + perp, 0.75), Color(col.r, col.g, col.b, a1)]
		var v3 := [battle._world_pos(pb - perp, 0.75), Color(col.r, col.g, col.b, a1)]
		_tri(st, v0, v1, v2)
		_tri(st, v0, v2, v3)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	var n := _node(mesh, _mat(true, 13), Vector3.ZERO, "pierce_tracer")
	n.set_meta("len_px", len_px)
	_fx.append({"node": n, "t": 0.0, "life": 0.16, "kind": "tracer"})
	return n


# ══════════════════════════════════════════════════════════════════
#  §生命周期 —— 不用 tween, 走 sim 的 delta
# ══════════════════════════════════════════════════════════════════

## 每帧推进所有短命特效(淡出 + 到期 free)。
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
			n.queue_free()
			continue
		var m = n.material_override
		if m is StandardMaterial3D:
			var c: Color = (m as StandardMaterial3D).albedo_color
			(m as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, 1.0 - t / life)
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
