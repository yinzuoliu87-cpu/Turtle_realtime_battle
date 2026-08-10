class_name SpiritEqVfx
extends RefCounted
## spirit_eq_vfx.gd — 灵物五件新装备(060~064)的演出层
## (方案书 docs/plans/20260805-装备逐件重做.md §0.5 · 实装契约 docs/plans/20260805-实装契约.md §6)
##
## ══════════════════════════════════════════════════════════════════════
##  ★为什么每一条都写成闭式解, 而不是"我调得像"
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-08-05:「要触手水准, 除非你用 pixel 的特效动画能做完美」「全部做好高质量特效」。
##
## ⚠ **诚实记录(第一条)**: 这五件**一张参考素材都没有**, 所以触手立的第 1 条判据
##   (逐帧量参考 → 相对包络表) **无从下手**。替代的是 shockwave_vfx.gd 那条路 ——
##   **给每件找一个真实的物理过程, 用它的闭式解当形态, 用它的守恒律当门禁**。
##   判据不是"像不像", 而是"它满不满足这几条可验证的定律"。手调缓动一条都过不了。
##
## ── ① 060 磷光水母伞: 伞面 = 张紧的膜 ⇒ 【二阶欠阻尼阶跃响应】────────────
##   x(t) = 1 − e^(−ζωₙt)·[cos(ω_d t) + (ζωₙ/ω_d)·sin(ω_d t)],  ω_d = ωₙ√(1−ζ²)
##   膜被释放后不会"缓缓张开", 它会**冲过头再回弹** —— 这就是伞骨的弹性储能。
##   ★可验证性质(闭式, 与 ζ 以外一切无关):
##     · 超调量 Mp = e^(−ζπ/√(1−ζ²))          ← 第一个峰的高度
##     · 峰值时刻 tp = π/ω_d                    ← 第一个峰在哪
##     · **对数减缩 δ = ln(xₖ/xₖ₊₁) = 2πζ/√(1−ζ²) 对【任意相邻两峰】恒定** ← 这条最狠,
##       任何手调曲线都做不到"每一对相邻峰的比值都相等"。
##
## ── ② 061 钻孔螺: 破损 20 层 = 【Paris 疲劳裂纹扩展律】────────────────────
##   da/dN = C·(ΔK)^m,  ΔK ∝ σ√(πa),  取金属/脆壳的典型 m = 4
##   ⇒ da/dN = C′a²  ⇒ 积分得 **a(N) = a₀ / (1 − N/N_f)** (N_f = 疲劳寿命)
##   即裂纹长度在接近寿命时**发散**: 前 12 层几乎看不出, 最后几层暴涨。
##   这正是"玩家要能看出快满了"要的那条曲线 —— 而且它不是我拧出来的, 是积分出来的。
##   ★可验证性质: **1/a(N) 对 N 严格线性**(斜率 = −â(20)/N_f)。手调曲线做不到严格线性。
##
## ── ③ 062 螳螂虾钳: 一击 = 【钳合(Hertz 接触) → 空泡 → Rayleigh 溃灭闪光】──
##   真实现象是两段的, 且第二段远亮于第一段。两段各有自己的闭式解:
##   · 段①【Hertz 弹性接触】: 接触半径 a = √(Rδ), 接触压强 p₀ ∝ √δ。
##     等速逼近 δ = v·t ⇒ **a² 对 t 严格线性**, 亮度 ∝ √t。
##   · 段②【Rayleigh 空穴溃灭】: R(t) = R₀(1 − t/t_c)^(2/5)  ← 与 Sedov 同为 2/5 自相似指数
##     溃灭速度 dR/dt ∝ (1−τ)^(−3/5) → **发散**, 所以第二段必然比第一段快且亮, 这是物理给的,
##     不是我设的。绝热压缩温度 θ = (R₀/R)^(3(γ−1)) = R̂^(−2) (单原子气体 γ=5/3)。
##   ★可验证性质: 段② 尺度不变 R̂(1−k·s)/R̂(1−s) ≡ k^0.4; θ·R̂² ≡ 1; 段②峰值/段①峰值 = 闭式比值。
##   ⚠ **诚实记录(第二条)**: 亮度的**显示映射**用的是对数(星等)基, 且段① 的"接触区压缩比 2.0"
##     是一个**显示取值, 不是实测量**。物理给的是【形状】与【段②必然更亮】, 那个 2.0 决定的只是
##     "段① 到底有多亮"。已在 STRIKE_COMPRESS 处标明。
##
## ── ④ 063 白鲸气环: 【浮力涡环】——────────────────────────────────────
##   白鲸吐的是**气**环, 所以体积守恒是真的(定深、不溶解):
##   · 环体积 V = 2π²R·a² = const  ⇒ **a = a₀√(R₀/R)**  ← 环径涨、环管必然变细
##   · 浮力给涡环冲量: I = ρΓπR², dI/dt = ρgV ⇒ **R² 对 t 严格线性**(Turner 1957)
##   · Kelvin–Lamb 平移速度 U = Γ/(4πR)·[ln(8R/a) − 1/4] ⇒ **越胀越慢**
##   ★可验证性质: R·a² ≡ const(体积守恒) · R² 对 t 线性 · U 随 R 单调降。
##
## ── ⑤ 064 溺者的浮囊: 【等压放气】+【Fick 扩散】────────────────────────
##   · 浮囊在定深下是**等压**的 ⇒ 气体量线性衰减 ⇒ 体积线性衰减 ⇒ **r ∝ f^(1/3)**
##     ★可验证: r³/r_max³ ≡ f 精确成立(f = 剩余余额比例)。
##     副产品: 皮面松弛度 s = 1 − f^(2/3), 与 (r/r_max)² 之和恒为 1 ⇒ 早期就看得见"在瘪"。
##   · 破裂后的诅咒云 = 被动标量扩散, 均方位移 = 2Dt ⇒ **r ∝ √t** ⇒ r² 对 t 线性。
##     (故意与 Sedov 的 2/5、Rayleigh 的 2/5 区分开: 三种扩散看起来就该不一样。)
##
## ── 技术路线 ────────────────────────────────────────────────────────
## 程序化 `ArrayMesh`(`SurfaceTool` 现算) + 顶点色, **零素材** —— 同 shockwave_vfx / tentacle_vfx。
## 用户铁律「新内容一律新素材, 不许拿别件顶替」: 程序化几何**不产出图**, 不吃这条约束,
## 也不存在"复用了谁的立绘"的问题。
##
## ⚠ 朝向坑 (memory [[fb-axis-y-plus-rotation-cancels]]): 本文件**不用 Sprite3D**,
##   直接建世界坐标顶点。贴地几何一律 y = GROUND_Y 的水平顶点, 门禁量 |面法线·上| ≈ 1.000。
##
## ⚠ 材质坑 (shockwave_vfx 已踩): 一律 `material_override`, **不用**
##   `set_surface_override_material` —— 后者在 --headless dummy renderer 下每设一次刷一条
##   `ERROR: Parameter "material" is null.`, 而那条**不在 run-tests.sh 的 FATAL 正则里**。


# ══════════════════════════════════════════════════════════════════
#  §① 060 磷光水母伞 —— 二阶欠阻尼阶跃响应(膜张力)
# ══════════════════════════════════════════════════════════════════

## 阻尼比 ζ。★0 < ζ < 1 才有超调; 取 0.28 ⇒ 超调 40.4%, 两个可见的回弹峰。
## 别改成 ≥1: 那是过阻尼, 伞就变成"缓缓张开"= 又回到手调缓动了。
const PARASOL_ZETA := 0.28
## 无阻尼固有角频率 ωₙ (rad/s)。伞面越紧越大。12.0 ⇒ 第一个峰在 tp = π/ω_d ≈ 0.273 秒。
const PARASOL_WN := 12.0
## 收伞时长 = 1 个时间常数 1/(ζωₙ)。收伞是被伞骨拉回去的、不是自由振荡 ⇒ 不再过冲。
## ★"时间常数"是这个二阶系统自带的量, 不是我拍的秒数。
const PARASOL_CLOSE := 1.0 / (PARASOL_ZETA * PARASOL_WN)
## 伞的几何: 经向/纬向分段(伞面是半个椭球的下半)
const BELL_LON := 28
const BELL_LAT := 7
## 伞面扁率(高/半径)。水母伞是扁的。
const BELL_SQUASH := 0.55
## 触须条数与长度(相对伞半径)
const TENTACLE_N := 12
const TENTACLE_LEN := 1.35

## 阻尼固有频率 ω_d = ωₙ√(1−ζ²)
static func parasol_wd() -> float:
	return PARASOL_WN * sqrt(1.0 - PARASOL_ZETA * PARASOL_ZETA)


## 二阶欠阻尼系统的单位阶跃响应。x(0)=0, x(∞)=1, 途中过冲。
## ★这就是"伞被弹开"的位移曲线本身 —— 没有任何一处是插值出来的。
static func damped_step(t: float) -> float:
	if t <= 0.0:
		return 0.0
	var wd: float = parasol_wd()
	var zw: float = PARASOL_ZETA * PARASOL_WN
	return 1.0 - exp(-zw * t) * (cos(wd * t) + (zw / wd) * sin(wd * t))


## 超调量 Mp = e^(−ζπ/√(1−ζ²))。第一个峰的高度 = 1 + Mp。
static func parasol_overshoot() -> float:
	return exp(-PARASOL_ZETA * PI / sqrt(1.0 - PARASOL_ZETA * PARASOL_ZETA))


## 第一个峰的时刻 tp = π/ω_d
static func parasol_peak_time() -> float:
	return PI / parasol_wd()


## 对数减缩 δ = 2πζ/√(1−ζ²)。★相邻两峰的**偏差**之比恒为 e^δ, 与是第几对峰无关。
static func parasol_log_decrement() -> float:
	return 2.0 * PI * PARASOL_ZETA / sqrt(1.0 - PARASOL_ZETA * PARASOL_ZETA)


## 伞在【本次张开周期内】t 秒时的张开度(0=收拢, 1=完全张开, >1=过冲)。
## dur = 张开总时长(= 效果持续 2.5 秒), 末尾 PARASOL_CLOSE 秒收伞。
static func parasol_open_frac(t: float, dur: float) -> float:
	if t <= 0.0:
		return 0.0
	var t_close: float = maxf(0.0, dur - PARASOL_CLOSE)
	if t < t_close:
		return damped_step(t)
	## 收伞: 从收伞起点的值线性拉回 0(被伞骨拉回去, 不是自由振荡 ⇒ 不再过冲)
	var v0: float = damped_step(t_close)
	var k: float = clampf((t - t_close) / maxf(PARASOL_CLOSE, 0.001), 0.0, 1.0)
	return v0 * (1.0 - k)


# ══════════════════════════════════════════════════════════════════
#  §② 061 钻孔螺 —— Paris 疲劳裂纹扩展律
# ══════════════════════════════════════════════════════════════════

## 破损层数上限(= 用户定稿的 20 层)
const BREACH_CAP := 20
## 疲劳寿命 N_f(层)。★取 24 而不是 20: N=N_f 时裂纹长度发散,
##   落在 24 上让第 20 层拿到 6a₀ 的有限值, 同时保住"最后几层暴涨"的观感
##   (第 20 层比第 19 层长 25%, 而第 10 层只比第 9 层长 4.3%)。
const PARIS_NF := 24.0
## 归一裂纹长度 â(N): â(BREACH_CAP) = 1。
## ★闭式: â(N) = (1 − CAP/N_f) / (1 − N/N_f)  ⇒ **1/â(N) 对 N 严格线性**。
static func crack_len(n: float) -> float:
	var nn: float = clampf(n, 0.0, float(BREACH_CAP))
	return (1.0 - float(BREACH_CAP) / PARIS_NF) / (1.0 - nn / PARIS_NF)


# ══════════════════════════════════════════════════════════════════
#  §③ 062 螳螂虾钳 —— Hertz 接触 + Rayleigh 空穴溃灭
# ══════════════════════════════════════════════════════════════════

## 段①(钳合/接触)时长(秒)。螳螂虾真实闭合约 2.7 ms, 游戏里放慢到可见。
const STRIKE_T := 0.10
## 段②(空泡生长 + 溃灭)时长(秒)
const CAVITY_T := 0.22
## 空泡生长占段② 的比例; 其余是 Rayleigh 溃灭。
const CAVITY_GROW_FRAC := 0.45
## 溃灭的最小半径比 R_min/R₀。★不能取 0: R→0 时绝热温度发散。
##   0.06 ⇒ 体积压缩 4630 倍, 温度比 (1/0.06)² = 277.8 —— 与实测声致发光的量级同档。
const R_MIN := 0.06
## 单原子气体绝热指数(氩)。θ = (R₀/R)^(3(γ−1)) = R̂^(−2)。
const GAMMA_MONO := 5.0 / 3.0
## ★★显示取值, 不是实测量(诚实记录): 段① 撞击接触区的名义压缩比。
##   它只决定"段① 有多亮"; 段② 必然更亮这件事是 Rayleigh 给的, 与它无关。
const STRIKE_COMPRESS := 2.0
## 亮度显示映射用【对数(星等)基】—— 段①/段② 的辐亮度差着 10^9 量级,
## 线性或 sRGB 伽马都会把段① 压成全黑。天文学量星等本来就用 log。

## Rayleigh 溃灭的归一空穴半径 R̂(τ) = (1−τ)^(2/5), τ∈[0,1]。
## ★2/5 指数使得 τ→1 时 dR/dτ → −∞: 溃灭是**加速**的, 这是"第二段更快更亮"的物理根源。
static func cavity_radius(tau: float) -> float:
	return pow(clampf(1.0 - tau, 0.0, 1.0), 0.4)


## 绝热压缩温度比 θ = R̂^(−3(γ−1)) = R̂^(−2)(γ=5/3), 半径钳在 R_MIN。
static func cavity_theta(tau: float) -> float:
	var r: float = maxf(cavity_radius(tau), R_MIN)
	return pow(r, -3.0 * (GAMMA_MONO - 1.0))


## 对数(星等)色调映射: θ=1 → 0, θ=θ_max → 1。
static func tone(theta: float) -> float:
	var tmax: float = pow(R_MIN, -3.0 * (GAMMA_MONO - 1.0))
	return clampf(log(maxf(theta, 1.0)) / log(tmax), 0.0, 1.0)


## 段① 的峰值亮度(= 接触区压缩比 STRIKE_COMPRESS 经同一条色调映射)
static func strike_peak_alpha() -> float:
	return tone(pow(STRIKE_COMPRESS, 3.0 * (GAMMA_MONO - 1.0)))


## 段② 的峰值亮度 = 1.0(θ 到达 θ_max)
static func collapse_peak_alpha() -> float:
	return tone(pow(R_MIN, -3.0 * (GAMMA_MONO - 1.0)))


## Hertz 接触: 归一接触半径 â(s) = √s (等速逼近 δ = v·t ⇒ a = √(Rδ) ∝ √t)。
## ★可验证: â² 对 s 严格线性。
static func hertz_contact(s: float) -> float:
	return sqrt(clampf(s, 0.0, 1.0))


## 整个两段式的形态。u = 归一到整段动画 [0,1]。
## 返回 stage(1/2) · r(归一半径) · a(亮度)
static func strike_shape(u: float) -> Dictionary:
	var total: float = STRIKE_T + CAVITY_T
	var t: float = clampf(u, 0.0, 1.0) * total
	if t < STRIKE_T:
		var s: float = t / STRIKE_T
		return {"stage": 1, "r": hertz_contact(s), "a": strike_peak_alpha() * hertz_contact(s), "tau": 0.0}
	var t2: float = (t - STRIKE_T) / maxf(CAVITY_T, 0.001)
	if t2 < CAVITY_GROW_FRAC:
		## 空泡生长: 由段① 的接触压强推开, 用同一条 Hertz 平方根律(镜像)
		var g: float = t2 / CAVITY_GROW_FRAC
		return {"stage": 2, "r": hertz_contact(g), "a": tone(cavity_theta(0.0)), "tau": 0.0}
	var tau: float = clampf((t2 - CAVITY_GROW_FRAC) / maxf(1.0 - CAVITY_GROW_FRAC, 0.001), 0.0, 1.0)
	return {"stage": 2, "r": cavity_radius(tau), "a": tone(cavity_theta(tau)), "tau": tau}


# ══════════════════════════════════════════════════════════════════
#  §④ 063 白鲸气环 —— 浮力涡环
# ══════════════════════════════════════════════════════════════════

## 初始环半径(相对最终环半径)
const RING_R0 := 0.42
## 初始环管半径 / 初始环半径
const RING_A0_FRAC := 0.30
## 一个环的存活时长(秒)
const RING_LIFE := 1.10
## 环的经向 / 管周向分段
const RING_LON := 40
const RING_TUBE := 8

## 浮力涡环: **R² 对 t 线性**(dI/dt = 浮力, I = ρΓπR²)。归一到 R(RING_LIFE) = 1。
static func ring_radius(t: float) -> float:
	var k: float = clampf(t / RING_LIFE, 0.0, 1.0)
	var r0sq: float = RING_R0 * RING_R0
	return sqrt(r0sq + (1.0 - r0sq) * k)


## 体积守恒 V = 2π²R·a² = const ⇒ a(R) = a₀·√(R₀/R)。返回**绝对**管半径(同一尺度)。
static func ring_tube(t: float) -> float:
	var r: float = ring_radius(t)
	return RING_A0_FRAC * RING_R0 * sqrt(RING_R0 / maxf(r, 1e-6))


## Kelvin–Lamb 平移速度(归一, 取 Γ/4π = 1): U = [ln(8R/a) − 1/4] / R。随 R 增大单调降。
static func ring_speed(t: float) -> float:
	var r: float = ring_radius(t)
	var a: float = ring_tube(t)
	return (log(8.0 * r / maxf(a, 1e-6)) - 0.25) / maxf(r, 1e-6)


## 引爆需要的环数(用户定稿)
const RING_TRIGGER := 3


# ══════════════════════════════════════════════════════════════════
#  §⑤ 064 溺者的浮囊 —— 等压放气 + Fick 扩散
# ══════════════════════════════════════════════════════════════════

## 浮囊几何分段
const BLADDER_LON := 20
const BLADDER_LAT := 12
## 浮囊满余额时的半径(场地码)。★这是**演出尺寸**, 不是效果半径。
const BLADDER_R_PX := 46.0
## 诅咒云扩散到 300 码用多久(秒)
const BURST_T := 0.75

## 等压放气: 体积 ∝ 剩余气体量 ⇒ r = r_max·f^(1/3)。
## ★可验证: (r/r_max)³ ≡ f 精确成立。
static func bladder_radius_frac(f: float) -> float:
	return pow(clampf(f, 0.0, 1.0), 1.0 / 3.0)


## 皮面松弛度 s = 1 − f^(2/3)。★与 (r/r_max)² 之和恒为 1 —— 这条让"在瘪"早期就看得见:
##   f=0.5 时半径只小 21%, 但松弛度已到 0.37。
static func bladder_slack(f: float) -> float:
	return 1.0 - pow(clampf(f, 0.0, 1.0), 2.0 / 3.0)


## Fick 扩散: 均方位移 = 2Dt ⇒ r ∝ √t。归一到 r(1)=1。
## ★可验证: r² 对归一时间严格线性。
static func diffusion_radius(u: float) -> float:
	return sqrt(clampf(u, 0.0, 1.0))


# ══════════════════════════════════════════════════════════════════
#  §几何工具 —— 程序化 ArrayMesh, 零素材
# ══════════════════════════════════════════════════════════════════

## 贴地几何的离地高度(米)。地板在 y=0, 抬一点免得 z-fighting。
const GROUND_Y := 0.06

var battle

## 本层建出来、还活着的句柄。撤场用(同 SynergyVfx._owned 的立场)。
var _live: Array = []
## 上限 —— 最后一道闸(手机端预算), 同 SynergyVfx.OWNED_CAP。
const LIVE_CAP := 96

## 网格缓存: 全是【单位尺寸】的, 每一发只差 scale 与材质 ⇒ 整局各建一次。
## ★材质不能共享(每一发带着自己的亮度), 网格可以。
## ★挂实例上不用 static: static 会让进程退出时报 "resources still in use at exit"。
var _m_bell: ArrayMesh = null
var _m_ring: ArrayMesh = null
var _m_disc: ArrayMesh = null
var _m_torus: ArrayMesh = null
var _m_sphere: ArrayMesh = null


func _init(b) -> void:
	battle = b


func _has_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for v in [a, b, c]:
		st.set_color(v[1])
		st.add_vertex(v[0])


## 贴地面上的一个顶点(y = GROUND_Y, 平的)
static func _flat(r: float, th: float, a: float) -> Array:
	return [Vector3(r * cos(th), GROUND_Y, r * sin(th)), Color(1, 1, 1, a)]


## 加性发光材质(零素材, 顶点色当亮度)
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
	m.albedo_color = Color(1, 1, 1, 0)
	return m


static func _node(mesh: ArrayMesh, mat: StandardMaterial3D, org: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	## ★material_override 不用 set_surface_override_material(理由见文件头)
	mi.material_override = mat
	mi.position = org
	return mi


## 单位半径的【水母伞】: 下半椭球壳。伞缘亮、伞顶暗(磷光集中在伞缘)。
static func _build_bell() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(BELL_LAT):
		var p0: float = float(i) / float(BELL_LAT) * (PI * 0.5)
		var p1: float = float(i + 1) / float(BELL_LAT) * (PI * 0.5)
		for j in range(BELL_LON):
			var t0: float = float(j) / float(BELL_LON) * TAU
			var t1: float = float(j + 1) / float(BELL_LON) * TAU
			var a := _bell_vert(p0, t0)
			var b := _bell_vert(p0, t1)
			var c := _bell_vert(p1, t1)
			var d := _bell_vert(p1, t0)
			_tri(st, a, b, c)
			_tri(st, a, c, d)
	## 触须: 从伞缘垂下的细条(两三角一条)
	for k in range(TENTACLE_N):
		var th: float = float(k) / float(TENTACLE_N) * TAU
		var w: float = 0.035
		var x0 := Vector3(cos(th), 0.0, sin(th))
		var side := Vector3(-sin(th) * w, 0.0, cos(th) * w)
		var tip := Vector3(cos(th) * 0.92, -TENTACLE_LEN * BELL_SQUASH, sin(th) * 0.92)
		var va := [x0 - side, Color(1, 1, 1, 0.55)]
		var vb := [x0 + side, Color(1, 1, 1, 0.55)]
		var vc := [tip + side * 0.35, Color(1, 1, 1, 0.0)]
		var vd := [tip - side * 0.35, Color(1, 1, 1, 0.0)]
		_tri(st, va, vb, vc)
		_tri(st, va, vc, vd)
	st.commit(mesh)
	return mesh


## 伞面顶点。phi=0 在伞缘(赤道), phi=π/2 在伞顶。
static func _bell_vert(phi: float, th: float) -> Array:
	var p := Vector3(cos(phi) * cos(th), sin(phi) * BELL_SQUASH, cos(phi) * sin(th))
	## 磷光: 伞缘最亮 → 伞顶半亮(生物发光集中在伞缘的光器上)
	var a: float = lerpf(1.0, 0.22, sin(phi))
	return [p, Color(1, 1, 1, a)]


## 单位半径的贴地细环(用作 200 码庇护圈 / 引爆环 / 诅咒云外沿)
static func _build_ring() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 64
	for j in range(n):
		var t0: float = float(j) / float(n) * TAU
		var t1: float = float(j + 1) / float(n) * TAU
		for q in [[0.90, 0.0, 0.975, 1.0], [0.975, 1.0, 1.0, 0.25]]:
			var ri: float = float(q[0])
			var ai: float = float(q[1])
			var ro: float = float(q[2])
			var ao: float = float(q[3])
			_tri(st, _flat(ri, t0, ai), _flat(ro, t0, ao), _flat(ro, t1, ao))
			_tri(st, _flat(ri, t0, ai), _flat(ro, t1, ao), _flat(ri, t1, ai))
	st.commit(mesh)
	return mesh


## 单位半径的贴地实心盘(诅咒云 / 接触区)
static func _build_disc() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 48
	var ctr := [Vector3(0.0, GROUND_Y, 0.0), Color(1, 1, 1, 0.85)]
	for j in range(n):
		var t0: float = float(j) / float(n) * TAU
		var t1: float = float(j + 1) / float(n) * TAU
		_tri(st, ctr, _flat(1.0, t0, 0.0), _flat(1.0, t1, 0.0))
	st.commit(mesh)
	return mesh


## 单位圆环面(环半径 1 / 管半径 1)。顶点 = 径向单位向量 + 管截面偏移。
static func _build_torus() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(RING_LON):
		var t0: float = float(j) / float(RING_LON) * TAU
		var t1: float = float(j + 1) / float(RING_LON) * TAU
		for k in range(RING_TUBE):
			var p0: float = float(k) / float(RING_TUBE) * TAU
			var p1: float = float(k + 1) / float(RING_TUBE) * TAU
			_tri(st, _torus_vert(t0, p0), _torus_vert(t1, p0), _torus_vert(t1, p1))
			_tri(st, _torus_vert(t0, p0), _torus_vert(t1, p1), _torus_vert(t0, p1))
	st.commit(mesh)
	return mesh


## 圆环面顶点。★把"环向"与"管向"分量分别放进 (x,z) 与 (y + 径向偏移),
##   使得 apply 时能各自缩放 —— 见 _apply_ring。这里先建 R=1 / a=1 的形状,
##   管向分量写进【顶点色的 rg 通道】当权重, 供 apply 时按真实 a 重算位置。
##   ⚠ Godot 的 MeshInstance3D 不能逐顶点改, 所以真做法是: 建**管向权重为 0 的骨架环**,
##     再用一个各向异性 scale 把管径压出来。为了保住体积守恒, 环管用【独立节点】画。
static func _torus_vert(th: float, ph: float) -> Array:
	var dir := Vector3(cos(th), 0.0, sin(th))
	var p := dir + Vector3(dir.x * cos(ph), sin(ph), dir.z * cos(ph))
	## 管的下半暗(背光), 上半亮
	var a: float = lerpf(0.35, 1.0, 0.5 + 0.5 * sin(ph))
	return [p, Color(1, 1, 1, a)]


## 单位半径球(浮囊)
static func _build_sphere() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(BLADDER_LAT):
		var p0: float = -PI * 0.5 + float(i) / float(BLADDER_LAT) * PI
		var p1: float = -PI * 0.5 + float(i + 1) / float(BLADDER_LAT) * PI
		for j in range(BLADDER_LON):
			var t0: float = float(j) / float(BLADDER_LON) * TAU
			var t1: float = float(j + 1) / float(BLADDER_LON) * TAU
			_tri(st, _sph_vert(p0, t0), _sph_vert(p0, t1), _sph_vert(p1, t1))
			_tri(st, _sph_vert(p0, t0), _sph_vert(p1, t1), _sph_vert(p1, t0))
	st.commit(mesh)
	return mesh


static func _sph_vert(phi: float, th: float) -> Array:
	var p := Vector3(cos(phi) * cos(th), sin(phi), cos(phi) * sin(th))
	## 上半亮(水面来的光), 下半暗
	var a: float = lerpf(0.30, 1.0, 0.5 + 0.5 * sin(phi))
	return [p, Color(1, 1, 1, a)]


func _ensure_meshes() -> void:
	if _m_bell == null: _m_bell = _build_bell()
	if _m_ring == null: _m_ring = _build_ring()
	if _m_disc == null: _m_disc = _build_disc()
	if _m_torus == null: _m_torus = _build_torus()
	if _m_sphere == null: _m_sphere = _build_sphere()


## 节点上打的自定义 meta 键 —— 门禁按 meta 数点数, **不按名字/贴图路径**:
## 程序生成的网格 resource_path 是空串, 按路径数会全部数成 0(SynergyVfx 已记过这个坑)。
const META_KEY := "spirit_eq_vfx"


## 建节点并挂进 _world + 打 meta。返回节点(挂不上时返回 null)。
func _spawn_node(mesh: ArrayMesh, mat: StandardMaterial3D, org: Vector3, kind: String) -> MeshInstance3D:
	if not _has_world():
		return null
	var mi := _node(mesh, mat, org)
	mi.set_meta(META_KEY, kind)
	battle._world.add_child(mi)
	return mi


# ══════════════════════════════════════════════════════════════════
#  §演出入口 —— 每个都返回句柄; 形态由 apply_at() 同步写死, 门禁直接喂任意 u
# ══════════════════════════════════════════════════════════════════

## 060: 打开伞。radius_px = 庇护半径(码, 用户定稿 200), dur = 持续(2.5 秒)。
## ⚠ 庇护圈的半径必须**量真实节点**: ring 节点的 scale = radius_px × WS。
func parasol_open(pos2d: Vector2, col: Color, radius_px: float, dur: float) -> Dictionary:
	if not _has_world():
		return {}
	_ensure_meshes()
	_ensure_room()
	var org: Vector3 = battle._world_pos(pos2d, 0.0)
	## 伞本体挂在龟头顶上方一点(伞是撑开在头顶的)
	var bell := _spawn_node(_m_bell, _mat(false, 8), org + Vector3(0.0, 1.30, 0.0), "bell")
	var ring := _spawn_node(_m_ring, _mat(true, 9), org, "parasol_ring")
	if bell == null or ring == null:
		return {}
	var h := {
		"kind": "parasol", "bell": bell, "ring": ring, "col": col,
		"bell_r": 78.0 * float(battle.WS), "ring_r": radius_px * float(battle.WS),
		"dur": maxf(dur, 0.01), "t": 0.0,
	}
	_live.append(h)
	apply_at(h, 0.0)
	return h


## 061: 在目标身上刷一次破损裂纹。n = 施加之后的层数。
func breach_marks(pos2d: Vector2, col: Color, n: int) -> Dictionary:
	if not _has_world():
		return {}
	_ensure_meshes()
	_ensure_room()
	var org: Vector3 = battle._world_pos(pos2d, 0.0)
	var ring := _spawn_node(_m_ring, _mat(true, 10), org, "breach")
	if ring == null:
		return {}
	var h := {
		"kind": "breach", "ring": ring, "col": col, "n": clampi(n, 0, BREACH_CAP),
		"base_r": 34.0 * float(battle.WS), "dur": 0.42, "t": 0.0,
	}
	_live.append(h)
	apply_at(h, 0.0)
	return h


## 062: 强化普攻的两段式(钳合 → 空泡 → 溃灭闪光)。
func cavitation_strike(pos2d: Vector2, col: Color) -> Dictionary:
	if not _has_world():
		return {}
	_ensure_meshes()
	_ensure_room()
	var org: Vector3 = battle._world_pos(pos2d, 0.0)
	var disc := _spawn_node(_m_disc, _mat(true, 11), org, "contact")
	var flash := _spawn_node(_m_sphere, _mat(false, 12), org + Vector3(0.0, 0.55, 0.0), "cavity")
	if disc == null or flash == null:
		return {}
	var h := {
		"kind": "strike", "disc": disc, "flash": flash, "col": col,
		"r_m": 62.0 * float(battle.WS), "dur": STRIKE_T + CAVITY_T, "t": 0.0,
	}
	_live.append(h)
	apply_at(h, 0.0)
	return h


## 063: 在目标身上放一个涡环。idx = 这是它身上的第几个(0/1/2), 用来错开高度。
func bubble_ring(pos2d: Vector2, col: Color, idx: int) -> Dictionary:
	if not _has_world():
		return {}
	_ensure_meshes()
	_ensure_room()
	var org: Vector3 = battle._world_pos(pos2d, 0.0)
	## ★★环面也是封闭曲面(管子的正面+背面) ⇒ 加色混合下同样会叠出白。
	##   A/B 实测(2026-08-11): 颜色推深后白占比 76%→43%, 再只画正面才掍得下去。
	var _rm := _mat(false, 9)
	_rm.cull_mode = BaseMaterial3D.CULL_BACK
	var tor := _spawn_node(_m_torus, _rm, org + Vector3(0.0, 0.30 + 0.22 * float(idx), 0.0), "ring")
	if tor == null:
		return {}
	var h := {
		"kind": "ring", "torus": tor, "col": col, "idx": maxi(0, idx),
		"r_m": 46.0 * float(battle.WS), "rise": 0.95, "dur": RING_LIFE, "t": 0.0,
		"y0": 0.30 + 0.22 * float(idx),
	}
	_live.append(h)
	apply_at(h, 0.0)
	return h


## 064: 浮囊。frac 由 `apply_at` 从外部余额喂进来(见 set_bladder_frac)。
func float_bladder(pos2d: Vector2, col: Color) -> Dictionary:
	if not _has_world():
		return {}
	_ensure_meshes()
	_ensure_room()
	var org: Vector3 = battle._world_pos(pos2d, 0.0)
	var _bm := _mat(false, 7)
	## ★★实心球 + 加色混合 + CULL_DISABLED ⇒ 正面背面各加一层 ⇒ **球心被加爆成白**。
	##   同族实测见 073 藤蕎小球(2026-08-11 A/B): 白芯占比 15% → 只画正面后 3%。
	##   浮囊本身就是个"气囊", 背面看不见, 只画正面不掉任何信息。
	##   ⚠ 只改浮囊自己这份 —— `_mat()` 是共用的, 环/带子需要 CULL_DISABLED。
	_bm.cull_mode = BaseMaterial3D.CULL_BACK
	var sph := _spawn_node(_m_sphere, _bm, org + Vector3(0.0, 1.55, 0.0), "bladder")
	if sph == null:
		return {}
	var h := {
		"kind": "bladder", "sphere": sph, "col": col,
		"r_m": BLADDER_R_PX * float(battle.WS), "frac": 1.0, "dur": -1.0, "t": 0.0,
	}
	_live.append(h)
	apply_at(h, 0.0)
	return h


## 064: 浮囊破裂 → 诅咒云扩散到 radius_px 码。
func bladder_burst(pos2d: Vector2, col: Color, radius_px: float) -> Dictionary:
	if not _has_world():
		return {}
	_ensure_meshes()
	_ensure_room()
	var org: Vector3 = battle._world_pos(pos2d, 0.0)
	var cloud := _spawn_node(_m_disc, _mat(true, 10), org, "curse_cloud")
	var edge := _spawn_node(_m_ring, _mat(true, 11), org, "curse_edge")
	if cloud == null or edge == null:
		return {}
	var h := {
		"kind": "burst", "cloud": cloud, "edge": edge, "col": col,
		"r_m": radius_px * float(battle.WS), "dur": BURST_T, "t": 0.0,
	}
	_live.append(h)
	apply_at(h, 0.0)
	return h


## 浮囊的剩余余额比例(0~1)。★由效果侧每帧喂真值 —— 演出**不自己算衰减**,
##   否则会出现"看起来还有一半、实际已经空了"的两套真相。
func set_bladder_frac(h: Dictionary, f: float) -> void:
	if h.is_empty() or str(h.get("kind", "")) != "bladder":
		return
	h["frac"] = clampf(f, 0.0, 1.0)
	apply_at(h, 0.0)


# ══════════════════════════════════════════════════════════════════
#  §形态写入 —— 纯同步。演出侧每帧调它、门禁侧也调它, 只有这一份实现。
# ══════════════════════════════════════════════════════════════════

func apply_at(h: Dictionary, u: float) -> void:
	if h.is_empty():
		return
	match str(h.get("kind", "")):
		"parasol": _apply_parasol(h, u)
		"breach": _apply_breach(h, u)
		"strike": _apply_strike(h, u)
		"ring": _apply_ring(h, u)
		"bladder": _apply_bladder(h)
		"burst": _apply_burst(h, u)


static func _set_col(n, c: Color) -> void:
	if is_instance_valid(n):
		(n.material_override as StandardMaterial3D).albedo_color = c


## 半径下限 1e-4: 0 会让 Basis 退化, Godot 刷 "scale is zero" 警告。
static func _set_scale(n, s: Vector3) -> void:
	if is_instance_valid(n):
		n.scale = Vector3(maxf(s.x, 1e-4), maxf(s.y, 1e-4), maxf(s.z, 1e-4))


func _apply_parasol(h: Dictionary, u: float) -> void:
	var dur: float = float(h["dur"])
	var t: float = clampf(u, 0.0, 1.0) * dur
	var f: float = parasol_open_frac(t, dur)
	var col: Color = h["col"]
	var br: float = float(h["bell_r"]) * f
	_set_scale(h["bell"], Vector3(br, br, br))
	## 磷光强度随张开度走(伞张得越开, 发光面越大)
	_set_col(h["bell"], Color(col.r, col.g, col.b, col.a * clampf(f, 0.0, 1.0)))
	## ★庇护圈是【效果半径的真实写照】: 半径恒等于 200 码, 不随伞的振荡缩放 ——
	##   它表示的是"谁在范围里", 拿它当演出去过冲就是在骗玩家。只有亮度跟着张开度走。
	var rr: float = float(h["ring_r"])
	_set_scale(h["ring"], Vector3(rr, rr, rr))
	_set_col(h["ring"], Color(col.r, col.g, col.b, col.a * 0.55 * clampf(f, 0.0, 1.0)))


func _apply_breach(h: Dictionary, u: float) -> void:
	var col: Color = h["col"]
	var n: int = int(h["n"])
	## 裂纹长度走 Paris 律 —— 这是"快满了"的读数
	var g: float = crack_len(float(n))
	var r: float = float(h["base_r"]) * (1.0 + g * 0.9)
	_set_scale(h["ring"], Vector3(r, r, r))
	## 一闪即逝: 亮度按 (1−u)² 落下
	var k: float = clampf(1.0 - u, 0.0, 1.0)
	## 满层时转成刺目的白(= 下一击变真伤的预告)
	var full: float = 1.0 if n >= BREACH_CAP else 0.0
	var c2: Color = col.lerp(Color(1.0, 1.0, 1.0, col.a), full * 0.75)
	_set_col(h["ring"], Color(c2.r, c2.g, c2.b, c2.a * k * k * (0.55 + 0.45 * g)))


func _apply_strike(h: Dictionary, u: float) -> void:
	var s: Dictionary = strike_shape(u)
	var col: Color = h["col"]
	var rm: float = float(h["r_m"])
	## 段① 接触盘: 贴地, 半径走 Hertz √t
	var st: int = int(s["stage"])
	var r_disc: float = rm * (float(s["r"]) if st == 1 else 1.0)
	_set_scale(h["disc"], Vector3(r_disc, r_disc, r_disc))
	_set_col(h["disc"], Color(col.r, col.g, col.b, col.a * (float(s["a"]) if st == 1 else 0.0)))
	## 段② 空泡: 球, 半径走 Rayleigh, 亮度走绝热温度的对数色调映射
	var r_f: float = rm * 0.42 * float(s["r"]) if st == 2 else 1e-4
	_set_scale(h["flash"], Vector3(r_f, r_f, r_f))
	## 溃灭时颜色被推向白热(温度上去了, 黑体往蓝白跑)
	var hot: float = clampf(float(s["a"]), 0.0, 1.0)
	var c2: Color = col.lerp(Color(1.0, 1.0, 1.0, col.a), hot * hot)
	_set_col(h["flash"], Color(c2.r, c2.g, c2.b, c2.a * (float(s["a"]) if st == 2 else 0.0)))


func _apply_ring(h: Dictionary, u: float) -> void:
	var t: float = clampf(u, 0.0, 1.0) * RING_LIFE
	var col: Color = h["col"]
	var rm: float = float(h["r_m"])
	var R: float = ring_radius(t)
	var a: float = ring_tube(t)
	## ★环径与管径**各自**缩放: 直接 Vector3(R,R,R) 会把管径一起放大 = 体积不守恒,
	##   那就不是气环了(体积守恒正是本条的判据 ①)。
	##   Godot 没有逐顶点缩放 ⇒ 用各向异性 scale: x/z 乘 (R+a)/2、y 乘 a。
	##   ⚠ 诚实记录: 这是**近似**, 只在 a≪R 时准 —— 而气环恰好一直 a≪R
	##     (a₀/R₀ = 0.30, 随 R 增大还在变小)。守恒律本身由纯函数 ring_radius/ring_tube 给,
	##     门禁逐点验的是那两个函数; 这里只负责把它画出来。
	var sx: float = rm * (R + a) * 0.5
	var sy: float = rm * a
	_set_scale(h["torus"], Vector3(sx, sy, sx))
	## Kelvin–Lamb: 越胀越慢 ⇒ 上升高度是速度的积分, 用归一速度加权
	var rise: float = float(h["rise"]) * (R - RING_R0) / maxf(1.0 - RING_R0, 1e-6)
	if is_instance_valid(h["torus"]):
		var n = h["torus"]
		n.position.y = float(h["y0"]) + rise
	## 尾段淡出
	var k: float = clampf((1.0 - u) * 3.0, 0.0, 1.0)
	_set_col(h["torus"], Color(col.r, col.g, col.b, col.a * k))


func _apply_bladder(h: Dictionary) -> void:
	var f: float = float(h["frac"])
	var col: Color = h["col"]
	var r: float = float(h["r_m"]) * bladder_radius_frac(f)
	## 松弛的皮沿重力垂下来 ⇒ 越瘪越扁(y 比 x/z 再多缩一点松弛度)
	var slack: float = bladder_slack(f)
	_set_scale(h["sphere"], Vector3(r, r * (1.0 - 0.45 * slack), r))
	_set_col(h["sphere"], Color(col.r, col.g, col.b, col.a * (0.35 + 0.5 * f)))


func _apply_burst(h: Dictionary, u: float) -> void:
	var col: Color = h["col"]
	var rm: float = float(h["r_m"])
	var r: float = rm * diffusion_radius(u)
	_set_scale(h["cloud"], Vector3(r, r, r))
	_set_scale(h["edge"], Vector3(r, r, r))
	var fade: float = clampf(1.0 - u * u, 0.0, 1.0)
	_set_col(h["cloud"], Color(col.r, col.g, col.b, col.a * 0.30 * fade))
	_set_col(h["edge"], Color(col.r, col.g, col.b, col.a * fade))


# ══════════════════════════════════════════════════════════════════
#  §推进与撤场
# ══════════════════════════════════════════════════════════════════

const NODE_KEYS := ["bell", "ring", "disc", "flash", "torus", "sphere", "cloud", "edge"]


func _free_handle(h: Dictionary) -> void:
	for k in NODE_KEYS:
		var n = h.get(k, null)
		if n != null and is_instance_valid(n):
			n.queue_free()


## 到上限了先收掉最老的(最后一道闸)
func _ensure_room() -> void:
	while _live.size() >= LIVE_CAP:
		_free_handle(_live[0])
		_live.remove_at(0)


## 每帧推进。★不用 tween: 无头 CI 下 create_tween 推进不稳(CLAUDE.md §3.5),
##   而且走 sim 的 delta 才跟时停/换路同步。
func tick(delta: float) -> void:
	if not _has_world():
		clear_all()
		return
	var i := 0
	while i < _live.size():
		var h: Dictionary = _live[i]
		var dur: float = float(h.get("dur", -1.0))
		if dur <= 0.0:
			i += 1
			continue          # 常驻类(浮囊): 由效果侧决定何时收
		var t: float = float(h["t"]) + maxf(delta, 0.0)
		h["t"] = t
		apply_at(h, t / dur)
		if t >= dur:
			_free_handle(h)
			_live.remove_at(i)
		else:
			i += 1


## 手动收掉一个句柄(浮囊这类常驻的)
func drop(h: Dictionary) -> void:
	if h.is_empty():
		return
	for i in range(_live.size()):
		if _live[i] == h:
			_live.remove_at(i)
			break
	_free_handle(h)


## 撤场: 收掉所有在播的句柄, **并放掉网格缓存**。
## ★为什么连缓存一起放: 不放的话进程退出时 Godot 会报
##   `RID allocations of type DummyMesh were leaked at exit`(实测 5 条 —— 正好是这里的 5 个网格)。
##   那条不在 run-tests.sh 的 FATAL 正则里, 不会红门禁, 但它是真的在漏。
##   缓存是懒建的(`_ensure_meshes`), 换路后第一次用会重建 —— 5 个网格, 可忽略。
func clear_all() -> void:
	for h in _live:
		_free_handle(h)
	_live.clear()
	_m_bell = null
	_m_ring = null
	_m_disc = null
	_m_torus = null
	_m_sphere = null


## 门禁用: 当前活着的句柄数
func live_count() -> int:
	return _live.size()
