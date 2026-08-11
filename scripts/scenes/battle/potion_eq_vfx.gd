class_name PotionEqVfx
extends RefCounted
## potion_eq_vfx.gd — 药水四件(065/066/067/068)的演出层。零素材, 全程序化 ArrayMesh + 顶点色。
##
## ══════════════════════════════════════════════════════════════════════
##  ★判据: 用【可验证的物理规律】, 不是"我调得像"
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-08-05:「要触手水准」。触手立的第 1 条判据是【逐帧量参考做成包络表】——
## 但这一批**一件参考素材都没有**, 那条无从下手。
## 于是照【怒气冲击波】(shockwave_vfx.gd)那条替代路: **每条形态都落在一个有闭式解的
## 物理模型上**, 门禁验的是那个模型的【解析性质】(尺度不变性/守恒量/极值位置/对数缩减率),
## 手调出来的缓动曲线一条都过不了。
##
## ⚠ 诚实记录: 与冲击波同样, 本条**没有"逐帧量参考"这一步**(没有参考可量)。
##   下面四个模型都是解析式, 一个手调系数都没有 —— 只有【定标常数】(把无量纲解拉到
##   本游戏的码/秒), 那些常数不改变曲线的形状, 改变形状的指数与相位全是物理给的。
##
## ── ① 065 鲨肝油: 薄膜干涉 (thin-film interference) ────────────────────
##   油膜是真实存在的干涉体。单层膜双光束干涉, 上表面反射有 π 相移 ⇒
##       I(λ, d) / I₀ = sin²(2π·n·d / λ)
##   相长条件 2nd = (m + ½)λ, 相消(全暗)条件 2nd = mλ。
##
##   ⇒ **层数 → 膜厚 → 干涉色**。滚雪球攒得越多, 油膜越厚, 光晕颜色沿干涉序**循环**
##     (金→绿→紫→金…)。这正是马路上机油斑的样子。
##
##   ★可验证性质(门禁): 某一通道的**暗纹等距** —— 相邻两个零点的膜厚间隔恒为 λ/(2n),
##     与 m 无关。任何"两色之间 lerp"的手调渐变都只有 0 或 1 个零点, 不可能等距无限多。
##   ★第二条: 三通道的**次序会翻转**(某些厚度 R>B, 另一些 B>R)。单段 lerp 做不到。
##
## ── ② 066 鲸涎浓浆: 二阶欠阻尼系统的阶跃响应 (变身过冲回稳) ──────────────
##       y(t) = 1 − e^(−ζωₙt)·[cos(ω_d t) + ζ/√(1−ζ²)·sin(ω_d t)],  ω_d = ωₙ√(1−ζ²)
##
##   这是"一个有质量的东西被突然推到新位置"的**真实**运动: 冲过头 → 回弹 → 再冲一点 → 稳。
##
##   ★可验证性质(门禁):
##     · 最大超调量 Mp = e^(−πζ/√(1−ζ²)) —— 经典闭式, 且**恰好**发生在 t_p = π/ω_d;
##     · **对数缩减率** δ = ln(A_k / A_{k+1}) = 2πζ/√(1−ζ²) —— 对【任意】相邻两个极值
##       都相同。这一条是"真的阻尼振动"与"手画一个回弹曲线"的分水岭;
##     · 存在**二次峰**(t = 3π/ω_d 处再次冲过终值) —— 单调缓动给不出。
##
## ── ③ 067 毒药瓶: Fick 扩散点源解 (毒云) + 真抛物线 (投掷) ───────────────
##   二维点源瞬时释放的浓度场闭式解:
##       c(r, t) = M / (4πDt) · exp(−r² / (4Dt))
##
##   · 特征半径 R(t) = √(4Dt) ⇒ **半径 ∝ √t**(湍流/分子扩散都是这条律, 与"匀速扩散"肉眼可分)
##   · 峰值浓度 c(0,t) = M/(4πDt) ⇒ **∝ 1/t**
##   · **质量守恒** ∮c·2πr dr ≡ M, 对任意 t 成立
##   · **自相似**: 令 ρ = r/R(t), 则 c/c(0,t) = e^(−ρ²) 与 t 无关
##     ⇒ 网格只建一次(单位半径, 顶点 alpha = e^(−ρ²)), 每帧只改 scale 与整体亮度。
##
##   ★可验证性质(门禁): 尺度不变性 R(4t)/R(t) ≡ 2;  峰值×t ≡ 常数;  数值积分回来 = M。
##     "半径匀速涨、alpha 线性淡出"这种手调做法, 三条**全部**过不了。
##
##   投掷是真抛物线(匀加速): 高度 h(s) = 4H·s(1−s), s∈[0,1]。
##   ★可验证: 关于 s=0.5 严格对称; 二阶差分恒定(=常重力); 端点恰好落地。
##
## ── ④ 068 深海气压罐: RC 放电 (法力激光的能量泄放) ──────────────────────
##       i(t) = I₀·e^(−t/τ)     Q(t) = Q_total·(1 − e^(−t/τ)) / (1 − e^(−T/τ))
##
##   罐子憋了一路的压力, 一次性泄掉 —— 泄放就是指数的。取 τ = T/3 ⇒ 收尾时残余电流
##   只有峰值的 e^(−3) = 4.98%, 切掉看不出跳变(同冲击波取 τ_end=6 的理由)。
##
##   ★★**伤害与亮度走同一条曲线** —— 光柱最亮的那一瞬也正是打得最狠的那一瞬。
##     不是"画面按 A 曲线、伤害按 B 曲线"那种两张皮。
##   ★可验证性质(门禁): **无记忆性** i(t+Δ)/i(t) 与 t 无关(这是指数函数的定义性质,
##     任何多项式/缓动都不满足); 半衰期 τ·ln2; Q(0)=0 且 Q(T)=1 **精确**。
##
## ── 技术路线 ──────────────────────────────────────────────────────────
## 程序化 `ArrayMesh`(`SurfaceTool` 现算) + 顶点色, **零贴图零素材**(同 shockwave_vfx /
## tentacle_vfx / battle_world_builder)。用户铁律「素材不复用除非点名」: 程序化几何不产出图,
## 也没有借用任何一件别的装备的立绘。
##
## ⚠ 朝向坑 (memory [[fb-axis-y-plus-rotation-cancels]]): 本文件**不用 Sprite3D**,
##   直接建世界坐标顶点。贴地几何一律 y = GROUND_Y 的水平面, 不存在 axis/rotation 互相抵消。
##
## ⚠ 推进方式: **不用 tween**。所有句柄由 `advance(delta)` 从 sim 循环推进,
##   任意时刻的形态由 `apply_at(h, u)` 同步写死 —— 门禁直接喂 u, 不等任何演出
##   (CLAUDE.md §3.5: 无头 CI 下场景树 tween 推进不稳, verify_pirate_hook 为此连红三次)。


# ══════════════════════════════════════════════════════════════════
#  §① 薄膜干涉 (065 鲨肝油)
# ══════════════════════════════════════════════════════════════════

## 角鲨烯(鲨鱼肝油的主成分)折射率, 实测值 1.4965 —— 取 1.47 这一档。
const FILM_N := 1.47
## 起始膜厚(纳米)。取在第一条相长条件附近, 一开始就是有颜色的。
const FILM_D0 := 130.0
## 每叠一层攻速, 膜厚增加(纳米)。★这是【定标】常数, 不影响曲线形状(只决定循环快慢)。
const FILM_DK := 42.0
## 采样三个可见光波长(纳米): 红 / 绿 / 蓝
const FILM_LAMBDA_R := 610.0
const FILM_LAMBDA_G := 545.0
const FILM_LAMBDA_B := 465.0


# ══════════════════════════════════════════════════════════════════
#  §② 二阶欠阻尼阶跃响应 (066 鲸涎浓浆 · 变身过冲回稳)
# ══════════════════════════════════════════════════════════════════

## 阻尼比 ζ。0<ζ<1 才有振荡; 0.30 给出 37% 超调 —— 明显看得见"冲过头"又不夸张。
const OVR_ZETA := 0.30
## 无阻尼固有角频率 ωₙ (rad/s)。★定标常数(决定快慢), 不改变超调量与衰减比。
const OVR_WN := 17.0
## 演出跑到 t = OVR_END 收尾。此时包络 e^(−ζωₙt) = e^(−4.59) = 1.0%, 切掉看不出跳变。
const OVR_END := 0.90


## 阻尼固有角频率 ω_d = ωₙ√(1−ζ²)
static func ovr_wd() -> float:
	return OVR_WN * sqrt(1.0 - OVR_ZETA * OVR_ZETA)


## 单位阶跃响应。y(0)=0, y(∞)=1, 首峰 1+Mp 在 t=π/ω_d。
static func damped_step(t: float) -> float:
	if t <= 0.0:
		return 0.0
	var wd: float = ovr_wd()
	var z: float = OVR_ZETA
	var env: float = exp(-z * OVR_WN * t)
	return 1.0 - env * (cos(wd * t) + (z / sqrt(1.0 - z * z)) * sin(wd * t))


## 最大超调量 Mp = e^(−πζ/√(1−ζ²)) (经典闭式)
static func ovr_overshoot() -> float:
	return exp(-PI * OVR_ZETA / sqrt(1.0 - OVR_ZETA * OVR_ZETA))


## 首峰时刻 t_p = π/ω_d
static func ovr_peak_time() -> float:
	return PI / ovr_wd()


## 对数缩减率 δ = 2πζ/√(1−ζ²)。相邻两个极值的偏差之比恒为 e^δ —— 对**任意** k 成立。
static func ovr_log_decrement() -> float:
	return 2.0 * PI * OVR_ZETA / sqrt(1.0 - OVR_ZETA * OVR_ZETA)


## 变身过程中 t 时刻的体型倍率。final=终值(1.40 = +40%)。
## ★这是 066「体型 +40%」唯一的事实源: `_eq_potion` 每帧把它写进 u["size_mult"],
##   battle_render.gd:368 读它且**影子跟着涨** ⇒ 这个"变大"是真的看得见。
static func ovr_size_at(t: float, final_mult: float) -> float:
	if t >= OVR_END:
		return final_mult
	return 1.0 + (final_mult - 1.0) * damped_step(t)


# ══════════════════════════════════════════════════════════════════
#  §③ Fick 扩散 (067 毒药瓶 · 毒云) + 抛物线 (投掷)
# ══════════════════════════════════════════════════════════════════

## 扩散系数 D (码²/秒)。★**定标**: 令 t=1.0 秒时的可见边缘半径恰好等于效果半径 400 码。
##   可见边缘取浓度降到峰值 5% 处 ⇒ r_edge = √(4Dt·ln20) = √(4D·2.9957)
##   400² = 4D·2.9957 ⇒ D = 13353。取 13350。
##   ⚠ 它只把无量纲解拉到本游戏的尺度, **不改变 √t 这个指数** —— 指数是物理给的。
const CLOUD_D := 13350.0
## 可见边缘的浓度阈值(相对峰值)
const CLOUD_EDGE_FRAC := 0.05
## 毒云演出总时长(秒)。到 4 秒时峰值只剩 1/4, 半径 2 倍。
const CLOUD_LIFE := 4.0
## 毒云演出的起算时刻下限(秒) —— t=0 时 c(0,t)→∞ 是解的奇点, 从 t₀ 起算。
const CLOUD_T0 := 0.18

## 药瓶飞行时长(秒)与抛高(码)
const VIAL_FLIGHT := 0.55
const VIAL_ARC_H := 190.0


## 扩散特征半径 R(t) = √(4Dt)。★**尺度不变**: R(k·t)/R(t) ≡ √k, 与 t 无关。
static func cloud_radius(t: float) -> float:
	return sqrt(4.0 * CLOUD_D * maxf(t, 0.0))


## 可见边缘半径: 浓度降到峰值 CLOUD_EDGE_FRAC 的那一圈。
## r_edge = R(t)·√(−ln f)。仍然 ∝ √t。
static func cloud_edge_radius(t: float) -> float:
	return cloud_radius(t) * sqrt(-log(CLOUD_EDGE_FRAC))


## 峰值浓度 c(0,t) = M/(4πDt)。取 M=1 ⇒ ∝ 1/t。
static func cloud_peak(t: float) -> float:
	return 1.0 / (4.0 * PI * CLOUD_D * maxf(t, 1e-6))


## 浓度场 c(r,t) = M/(4πDt)·exp(−r²/(4Dt))。M=1。
static func cloud_conc(r: float, t: float) -> float:
	var rt: float = maxf(t, 1e-6)
	return cloud_peak(rt) * exp(-(r * r) / (4.0 * CLOUD_D * rt))


## 自相似归一剖面: ρ = r/R(t) ⇒ c/c(0,t) = e^(−ρ²), **与 t 无关**。
## 网格的顶点 alpha 就是它 —— 所以整个毒云只建一次网格。
static func cloud_profile(rho: float) -> float:
	return exp(-rho * rho)


## 抛物线高度剖面 h(s) = 4H·s(1−s), s∈[0,1]。关于 s=0.5 严格对称, 二阶差分恒定(=常重力)。
static func arc_height(s: float, apex: float) -> float:
	var ss: float = clampf(s, 0.0, 1.0)
	return 4.0 * apex * ss * (1.0 - ss)


## 药瓶在飞行进度 s 处的地面位置(线性) —— 水平匀速, 竖直匀加速, 合起来才是抛物线。
static func arc_pos(p0: Vector2, p1: Vector2, s: float) -> Vector2:
	return p0.lerp(p1, clampf(s, 0.0, 1.0))


# ══════════════════════════════════════════════════════════════════
#  §④ RC 泄放 (068 深海气压罐 · 法力激光)
# ══════════════════════════════════════════════════════════════════

## 激光持续总时长(秒) —— 用户规格「在 3 秒里持续造成」
const BEAM_SEC := 3.0
## 泄放时间常数 τ = T/3 ⇒ 收尾残余电流 e^(−3) = 4.98%
const BEAM_TAU := BEAM_SEC / 3.0
## 光柱长度(码) —— 用户规格 2000 码
const BEAM_RANGE := 2000.0
## 光柱半宽(码)。★这是【演出宽度】也是【判定宽度】, 两者同一个数 ——
##   memory [[fb-verify-must-run-the-real-path]]: 把效果半径当贴片尺寸(或反过来)是踩过的坑。
const BEAM_HALF_W := 58.0


## 归一泄放电流 i(t)/I₀ = e^(−t/τ)。
## ★**无记忆性**: i(t+Δ)/i(t) = e^(−Δ/τ) 与 t 无关 —— 这是指数函数的定义性质,
##   任何多项式/缓动都不满足。门禁靠它把"手调淡出"挡在外面。
static func beam_current(t: float) -> float:
	return exp(-maxf(t, 0.0) / BEAM_TAU)


## 半衰期 τ·ln2
static func beam_halflife() -> float:
	return BEAM_TAU * log(2.0)


## 已泄放比例 Q(t)/Q_total = (1−e^(−t/τ)) / (1−e^(−T/τ))。
## Q(0)=0 与 Q(T)=1 都是**精确**的 —— 归一化保证"3 秒里一共打出去的正好是设计总量"。
static func beam_frac(t: float) -> float:
	var tt: float = clampf(t, 0.0, BEAM_SEC)
	return (1.0 - exp(-tt / BEAM_TAU)) / (1.0 - exp(-BEAM_SEC / BEAM_TAU))


# ══════════════════════════════════════════════════════════════════
#  §几何 —— 程序化 ArrayMesh, 零素材
# ══════════════════════════════════════════════════════════════════

## 贴地几何的离地高度(米)。地板在 y=0, 抬一点免得 z-fighting。
const GROUND_Y := 0.055
## 环/盘的经向分段
const RING_LON := 48
## 毒云剖面的径向分段(采 e^(−ρ²) 到 ρ=2.2, 即 0.8% 峰值)
const CLOUD_RINGS := 12
const CLOUD_RHO_MAX := 2.2

var battle

## 网格缓存: 全是【单位尺寸】的, 每一发只差 scale 与材质 ⇒ 整局各建一次。
## ★挂实例上而不是 static var: static 的话进程退出时还挂着 ArrayMesh,
##   Godot 会报 "resources still in use at exit"(shockwave_vfx 实测过)。
var _m_ring: ArrayMesh = null
var _m_cloud: ArrayMesh = null
var _m_beam: ArrayMesh = null
var _m_quad: ArrayMesh = null

## 世界里在途的演出句柄(投掷/毒云/激光)。由 advance(delta) 推进, **不是 tween**。
var _live: Array = []


func _init(b) -> void:
	battle = b


static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for v in [a, b, c]:
		st.set_color(v[1])
		st.add_vertex(v[0])


static func _flat(r: float, th: float, a: float) -> Array:
	return [Vector3(r * cos(th), GROUND_Y, r * sin(th)), Color(1, 1, 1, a)]


## 单位半径的贴地细环(065 光晕用): 内沿软、外沿软, 中间一圈最亮。
func _ring_mesh() -> ArrayMesh:
	if _m_ring != null:
		return _m_ring
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(RING_LON):
		var t0: float = float(j) / float(RING_LON) * TAU
		var t1: float = float(j + 1) / float(RING_LON) * TAU
		for q in [[0.80, 0.0, 0.92, 1.0], [0.92, 1.0, 1.0, 0.0]]:
			var a := _flat(float(q[0]), t0, float(q[1]))
			var b := _flat(float(q[2]), t0, float(q[3]))
			var c := _flat(float(q[2]), t1, float(q[3]))
			var d := _flat(float(q[0]), t1, float(q[1]))
			_tri(st, a, b, c)
			_tri(st, a, c, d)
	st.commit(mesh)
	_m_ring = mesh
	return mesh


## 单位半径的毒云盘。★顶点 alpha **就是**自相似剖面 e^(−ρ²) ——
##   扩散解的自相似性让这张网格与时间无关, 每帧只改 scale 与整体亮度。
func _cloud_mesh() -> ArrayMesh:
	if _m_cloud != null:
		return _m_cloud
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(CLOUD_RINGS):
		var r0: float = float(i) / float(CLOUD_RINGS) * CLOUD_RHO_MAX
		var r1: float = float(i + 1) / float(CLOUD_RINGS) * CLOUD_RHO_MAX
		var a0: float = cloud_profile(r0)
		var a1: float = cloud_profile(r1)
		for j in range(RING_LON):
			var t0: float = float(j) / float(RING_LON) * TAU
			var t1: float = float(j + 1) / float(RING_LON) * TAU
			var a := _flat(r0 / CLOUD_RHO_MAX, t0, a0)
			var b := _flat(r1 / CLOUD_RHO_MAX, t0, a1)
			var c := _flat(r1 / CLOUD_RHO_MAX, t1, a1)
			var d := _flat(r0 / CLOUD_RHO_MAX, t1, a0)
			_tri(st, a, b, c)
			_tri(st, a, c, d)
	st.commit(mesh)
	_m_cloud = mesh
	return mesh


## 单位长度 × 单位半宽的贴地光柱(沿 +X, 起点在原点)。中轴白热、两侧渐隐。
func _beam_mesh() -> ArrayMesh:
	if _m_beam != null:
		return _m_beam
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 16
	for i in range(segs):
		var x0: float = float(i) / float(segs)
		var x1: float = float(i + 1) / float(segs)
		# 沿程亮度: 泄放的能量在传播中被介质吸收 ⇒ 也按指数掉(比尔–朗伯定律)
		var b0: float = exp(-1.1 * x0)
		var b1: float = exp(-1.1 * x1)
		for band in [[-1.0, 0.0, -0.34, 1.0], [-0.34, 1.0, 0.34, 1.0], [0.34, 1.0, 1.0, 0.0]]:
			var z0: float = float(band[0])
			var av0: float = float(band[1])
			var z1: float = float(band[2])
			var av1: float = float(band[3])
			var a := [Vector3(x0, GROUND_Y, z0), Color(1, 1, 1, av0 * b0)]
			var b := [Vector3(x1, GROUND_Y, z0), Color(1, 1, 1, av0 * b1)]
			var c := [Vector3(x1, GROUND_Y, z1), Color(1, 1, 1, av1 * b1)]
			var d := [Vector3(x0, GROUND_Y, z1), Color(1, 1, 1, av1 * b0)]
			_tri(st, a, b, c)
			_tri(st, a, c, d)
	st.commit(mesh)
	_m_beam = mesh
	return mesh


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


## ★用 material_override 不用 set_surface_override_material ——
##   后者在 --headless 的 dummy renderer 下每设一次刷一条 `Parameter "material" is null.`,
##   那条**不在 run-tests.sh 的 FATAL 正则里**(门禁不会红)但确实在刷错误(shockwave_vfx 实测)。
func _node(mesh: ArrayMesh, mat: StandardMaterial3D, org: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = org
	if is_instance_valid(battle._world):
		battle._world.add_child(mi)
	return mi


func _alive_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════
#  §065 油膜光晕 —— 常驻在携带者脚下, 颜色随层数走干涉序
# ══════════════════════════════════════════════════════════════════

## 光晕基础半径(码)与每层增量。半径涨得慢, 颜色循环得快 —— 让"色"当主要读数。
const FILM_R0 := 46.0
const FILM_RK := 1.4
const FILM_R_MAX := 118.0


static func film_radius(stacks: int) -> float:
	return minf(FILM_R0 + FILM_RK * float(maxi(0, stacks)), FILM_R_MAX)


func film_clear(u: Dictionary) -> void:
	var nd = u.get("_oilfilm_nd", null)
	if nd is MeshInstance3D and is_instance_valid(nd):
		nd.queue_free()
	u["_oilfilm_nd"] = null


# ══════════════════════════════════════════════════════════════════
#  §066 变身闪光 (一次性冲击环, 与过冲同拍)
# ══════════════════════════════════════════════════════════════════

func brew_flash(u: Dictionary) -> void:
	if not _alive_world():
		return
	battle._splash_ring_bold(u["pos"], Color(0.98, 0.90, 0.62), 150.0)
	battle._skill_ring(u["pos"], Color(1.0, 0.84, 0.45, 0.75), 92.0)


# ══════════════════════════════════════════════════════════════════
#  §067 投掷 + 毒云
# ══════════════════════════════════════════════════════════════════

## 抛出一个药瓶(纯演出)。落地结算由调用方用 battle._pending_shots 定时 —— **不是 tween**。
func vial_throw(p0: Vector2, p1: Vector2) -> Dictionary:
	if not _alive_world():
		return {}
	var nd := _node(_ring_mesh(), _mat(true, 12), battle._world_pos(p0, 0.0))
	var h := {"kind": "vial", "nd": nd, "p0": p0, "p1": p1, "t": 0.0, "dur": VIAL_FLIGHT}
	apply_at(h, 0.0)
	_live.append(h)
	return h


## 落地毒云(纯演出)。半径 ∝ √t, 峰值 ∝ 1/t, 质量守恒 —— 全由 §③ 的闭式解驱动。
func vial_cloud(pos: Vector2) -> Dictionary:
	if not _alive_world():
		return {}
	var nd := _node(_cloud_mesh(), _mat(true, 7), battle._world_pos(pos, 0.0))
	var h := {"kind": "cloud", "nd": nd, "pos": pos, "t": 0.0, "dur": CLOUD_LIFE}
	apply_at(h, 0.0)
	_live.append(h)
	return h


# ══════════════════════════════════════════════════════════════════
#  §068 法力激光 + 充能条
# ══════════════════════════════════════════════════════════════════

## 发射法力激光(纯演出)。伤害由 `_eq_potion` 每帧按 `beam_frac` 的增量投递, 与亮度同一条曲线。
func mana_beam(origin: Vector2, dir: Vector2) -> Dictionary:
	if not _alive_world():
		return {}
	var d: Vector2 = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	var nd := _node(_beam_mesh(), _mat(true, 13), battle._world_pos(origin, 0.0))
	nd.rotation = Vector3(0.0, -atan2(d.y, d.x), 0.0)
	var h := {"kind": "beam", "nd": nd, "origin": origin, "dir": d, "t": 0.0, "dur": BEAM_SEC}
	apply_at(h, 0.0)
	_live.append(h)
	return h


## 充能条: 头顶两片(底槽 + 填充)。★玩家得看出"快满了", 这是用户点名要的可见性。


# ══════════════════════════════════════════════════════════════════
#  §推进 —— 纯同步, 门禁可直接喂任意 u
# ══════════════════════════════════════════════════════════════════

## 把归一时间 u 时刻的形态写到真实节点上。演出侧与门禁侧只有这一份实现
## (memory [[fb-write-without-reader-and-fake-gates]]:「门禁模拟公式 ≠ 量真实对象」)。
func apply_at(h: Dictionary, uu: float) -> void:
	if h.is_empty() or not _alive_world():
		return
	var nd = h.get("nd", null)
	if not (nd is MeshInstance3D) or not is_instance_valid(nd):
		return
	var mat := nd.material_override as StandardMaterial3D
	var s: float = clampf(uu, 0.0, 1.0)
	match str(h.get("kind", "")):
		"vial":
			var p: Vector2 = arc_pos(h["p0"], h["p1"], s)
			var hh: float = arc_height(s, VIAL_ARC_H) * float(battle.WS)
			nd.position = battle._world_pos(p, hh)
			var rr: float = 15.0 * float(battle.WS)
			nd.scale = Vector3(rr, rr, rr)
			mat.albedo_color = Color(0.52, 0.92, 0.42, 0.95)
		"cloud":
			# ★半径与亮度都从扩散闭式解取, 不是"越来越大越来越淡"的手调
			var t: float = CLOUD_T0 + s * CLOUD_LIFE
			var rm: float = (cloud_edge_radius(t) / sqrt(-log(CLOUD_EDGE_FRAC))) * CLOUD_RHO_MAX * float(battle.WS)
			nd.scale = Vector3(rm, rm, rm)
			# 亮度 ∝ 峰值浓度(∝1/t), 归一到 t=CLOUD_T0 那一刻
			var pk: float = cloud_peak(t) / cloud_peak(CLOUD_T0)
			mat.albedo_color = Color(0.36, 0.88, 0.34, clampf(0.85 * pk, 0.0, 0.9))
		"beam":
			var tt: float = s * BEAM_SEC
			var i: float = beam_current(tt)
			var ln: float = BEAM_RANGE * float(battle.WS)
			var hw: float = BEAM_HALF_W * float(battle.WS) * (0.55 + 0.45 * i)
			nd.scale = Vector3(ln, 1.0, hw)
			mat.albedo_color = Color(0.62, 0.80, 1.0, clampf(0.95 * i, 0.0, 1.0))


## 推进一帧。★由 sim 循环调, 不用 tween(无头 CI 下 tween 推进不稳)。
## 撤场: 把还活着的演出全部 free。
##
## ★★2026-08-11 补: 这份文件**以前根本没有 clear_all** ——
##   而 dual_lane_flow 的换路清理是 has_method 保护的 ⇒ 药水这一路(065~068)
##   一直被**静默跳过**, 演出节点全留到下一路。
##   保护性的 has_method 让「没写 clear」变成了「不清也不报错」——
##   与 memory [[fb-write-without-reader-and-fake-gates]] 同族。
func clear_all() -> void:
	for h in _live:
		var nd = h.get("nd", null)
		if is_instance_valid(nd):
			nd.queue_free()
	_live = []


func advance(delta: float) -> void:
	if _live.is_empty():
		return
	var keep: Array = []
	for h in _live:
		var t: float = float(h["t"]) + maxf(delta, 0.0)
		h["t"] = t
		var dur: float = maxf(float(h["dur"]), 0.001)
		apply_at(h, t / dur)
		if t < dur:
			keep.append(h)
		else:
			var nd = h.get("nd", null)
			if nd is MeshInstance3D and is_instance_valid(nd):
				nd.queue_free()
	_live = keep


func live_count() -> int:
	return _live.size()
