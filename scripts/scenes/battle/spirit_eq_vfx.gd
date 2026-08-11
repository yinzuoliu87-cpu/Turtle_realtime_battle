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
const RING_R0 := 0.62   # 0.42→0.62(2026-08-11 用户「要环不要圆」: 起始环径太小+管肥=读成实心蛋)
## 初始环管半径 / 初始环半径
const RING_A0_FRAC := 0.12   # 0.30→0.12(细管才读成空心环; 守恒律 R·a²≡const 与 a₀ 取值无关)
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
var _m_plank: ArrayMesh = null
var _m_upf: ArrayMesh = null
## 大号光点版(小尺度节点用): pheal/pcover 节点只放 38~46 码, 光点不放大会缩成 1~2 像素隐形
var _m_upf_big: ArrayMesh = null
var _m_cracks: Array = []
var _m_chips: ArrayMesh = null
var _m_claw: ArrayMesh = null
var _m_torus_thin: ArrayMesh = null

## 060 的两个专用 shader(时间走 uniform, 不碰内建墙钟 —— mana_beam 同款纪律)
const SH_JELLY := preload("res://assets/shaders/jellyfish_bell.gdshader")
const SH_PLANK := preload("res://assets/shaders/phospho_plankton.gdshader")
## 磷光青(060 的身份色)
const PHOSPHO := Color(0.55, 0.95, 1.0)


static func _shader_mat(sh: Shader, prio: int, mode: int = 0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = prio
	m.set_shader_parameter("u_col", Vector3(PHOSPHO.r, PHOSPHO.g, PHOSPHO.b))
	if sh == SH_PLANK:
		m.set_shader_parameter("u_mode", mode)
	return m


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


static func _node(mesh: ArrayMesh, mat: Material, org: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	## ★material_override 不用 set_surface_override_material(理由见文件头)
	mi.material_override = mat
	mi.position = org
	return mi


## 单位半径的【水母伞】: 下半椭球壳。伞缘亮、伞顶暗(磷光集中在伞缘)。
## ★UV 是给 jellyfish_bell.gdshader 的数据通道(约定焊死):
##   UV.x = 方位角/TAU; UV.y ≥ 0 伞面(0=伞缘 1=伞顶), UV.y < 0 触须(-w, 根→梢)。
## ★触须是十字双鳍(单面片背对相机会被剔/看不见 —— 飘带那次踩过), 分 5 段(行波要弯得动)。
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
			_tri_uv(st, a, b, c)
			_tri_uv(st, a, c, d)
	## 触须: 分段十字鳍, 每段顶点带 UV.y=-w 给 shader 做行波
	var segs := 5
	for k in range(TENTACLE_N):
		var th: float = float(k) / float(TENTACLE_N) * TAU
		var ux: float = (float(k) + 0.5) / float(TENTACLE_N)
		var wd := 0.035
		for s in range(segs):
			var w0: float = float(s) / float(segs)
			var w1: float = float(s + 1) / float(segs)
			var r0: float = lerpf(1.0, 0.92, w0)
			var r1: float = lerpf(1.0, 0.92, w1)
			var y0: float = -TENTACLE_LEN * BELL_SQUASH * w0
			var y1: float = -TENTACLE_LEN * BELL_SQUASH * w1
			var p0v := Vector3(cos(th) * r0, y0, sin(th) * r0)
			var p1v := Vector3(cos(th) * r1, y1, sin(th) * r1)
			var a0: float = 0.55 * (1.0 - w0)
			var a1: float = 0.55 * (1.0 - w1)
			var wk0: float = wd * (1.0 - 0.6 * w0)
			var wk1: float = wd * (1.0 - 0.6 * w1)
			for side in [Vector3(-sin(th), 0.0, cos(th)), Vector3(cos(th) * 0.3, 1.0, sin(th) * 0.3).normalized()]:
				var s0: Vector3 = side * wk0
				var s1: Vector3 = side * wk1
				var va := [p0v - s0, Color(1, 1, 1, a0), Vector2(ux, -w0)]
				var vb := [p0v + s0, Color(1, 1, 1, a0), Vector2(ux, -w0)]
				var vc := [p1v + s1, Color(1, 1, 1, a1), Vector2(ux, -w1)]
				var vd2 := [p1v - s1, Color(1, 1, 1, a1), Vector2(ux, -w1)]
				_tri_uv(st, va, vb, vc)
				_tri_uv(st, va, vc, vd2)
	st.generate_normals()
	st.commit(mesh)
	return mesh


## 带 UV 通道的顶点写入(v = [pos, color, uv]; 旧 _tri 的三元组没有 uv)
static func _tri_uv(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for v in [a, b, c]:
		st.set_color(v[1])
		st.set_uv(v[2] if v.size() > 2 else Vector2.ZERO)
		st.add_vertex(v[0])


## 伞面顶点。phi=0 在伞缘(赤道), phi=π/2 在伞顶。UV=(方位/TAU, sinφ) 给 shader。
static func _bell_vert(phi: float, th: float) -> Array:
	var p := Vector3(cos(phi) * cos(th), sin(phi) * BELL_SQUASH, cos(phi) * sin(th))
	## 磷光: 伞缘最亮 → 伞顶半亮(生物发光集中在伞缘的光器上)
	var a: float = lerpf(1.0, 0.22, sin(phi))
	return [p, Color(1, 1, 1, a), Vector2(th / TAU, sin(phi))]


## 磷光浮游生物场(060): 散布在单位圆盘里的小菱形光点 + 圈带加密。
## ★这是「庇护圈」的替身 —— 用户 2026-08-11:「别用这种程序生成的圆敷衍」。
##   圈不再是几何线, 是 r∈[0.88,1.0] 圈带处加密的浮游光点(各自闪烁)。
##   UV.x = 归一半径(=1 处就是 200 码 —— 半径语义还在, 只是长相变成了生物),
##   UV.y = 光点 id, COLOR.a = 菱形形状(中心亮尖端 0)。
const PLANK_FIELD_N := 64
const PLANK_BAND_N := 30
static func _build_plank() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(PLANK_FIELD_N + PLANK_BAND_N):
		var b: int = i * 13 + 5
		var band: bool = i >= PLANK_FIELD_N
		var rr: float = (0.88 + 0.12 * _hh(b)) if band else (0.12 + 0.86 * sqrt(_hh(b)))
		var th: float = TAU * _hh(b + 1)
		var sz: float = (0.014 + 0.016 * _hh(b + 2)) * (1.25 if band else 1.0)
		var y: float = GROUND_Y + 0.02 + 0.10 * _hh(b + 3)
		var c := Vector3(rr * cos(th), y, rr * sin(th))
		var mid: float = float(i) / float(PLANK_FIELD_N + PLANK_BAND_N)
		_mote(st, c, sz, Vector2(rr, mid))
	st.commit(mesh)
	return mesh


## 伞下上浮微粒(060): 伞半径内的小光点, shader mode1 让它们各自循环上浮。
const UPF_N := 14
static func _build_upf(size_mult: float = 1.0) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(UPF_N):
		var b: int = i * 29 + 3
		var rr: float = 0.15 + 0.75 * sqrt(_hh(b))
		var th: float = TAU * _hh(b + 1)
		var c := Vector3(rr * cos(th), 0.05, rr * sin(th))
		_mote(st, c, (0.035 + 0.03 * _hh(b + 2)) * size_mult, Vector2(rr, float(i) / float(UPF_N)))
	st.commit(mesh)
	return mesh


## 一颗光点 = 两片十字菱形(任意视角有截面; 平面双面不翻倍)
static func _mote(st: SurfaceTool, c: Vector3, sz: float, uv: Vector2) -> void:
	var bright := Color(1, 1, 1, 0.9)
	var dim := Color(1, 1, 1, 0.0)
	for pr in [[Vector3(sz, 0, 0), Vector3(0, sz, 0)], [Vector3(0, 0, sz), Vector3(0, sz, 0)]]:
		var u_: Vector3 = pr[0]
		var v_: Vector3 = pr[1]
		_tri_uv(st, [c - u_, dim, uv], [c + v_, bright, uv], [c + u_, dim, uv])
		_tri_uv(st, [c - u_, dim, uv], [c + u_, dim, uv], [c - v_, bright, uv])


## 确定性哈希(mesh 生成期用, 不碰全局随机流)
static func _hh(i: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + 78.233) * 43758.5453, 1.0)


## 061 裂纹覆盖层: 锯齿折线裂缝(十字条带), 档位=层段(1-5/6-12/13-19/20 → 裂缝 2/4/6/8 条)。
## ★不是圆环: 用户 2026-08-11「别用程序生成的圆敷衍」—— 破损就该长得像【裂开】。
## 单位半径 1 = 满层裂纹半径; 运行时 scale × crack_len(n)(Paris 律, 快满暴涨)。
static func _build_cracks(band: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_cr: int = [2, 4, 6, 8][clampi(band, 0, 3)]
	var white: bool = band >= 3
	for i in range(n_cr):
		var b: int = band * 71 + i * 19
		var ang: float = TAU * (float(i) + 0.5 * _hh(b)) / float(n_cr)
		var segs := 4
		var pos := Vector3.ZERO
		var dir := Vector3(cos(ang), 0.35 * (_hh(b + 1) - 0.5), sin(ang)).normalized()
		var w0: float = 0.10 * (0.8 + 0.5 * _hh(b + 2))
		for sg in range(segs):
			var t0: float = float(sg) / float(segs)
			var ln: float = (1.0 / float(segs)) * (0.75 + 0.5 * _hh(b + 3 + sg))
			# 锯齿: 每段折一个随机小角
			var kink := Vector3(-dir.z, 0.0, dir.x) * (_hh(b + 9 + sg) - 0.5) * 0.55
			var nd: Vector3 = (dir + kink).normalized()
			var p1: Vector3 = pos + nd * ln
			var wa: float = w0 * (1.0 - t0)
			var wb: float = w0 * (1.0 - float(sg + 1) / float(segs))
			var ca := Color(1, 1, 1, 0.9 * (1.0 - 0.5 * t0)) if white else Color(0.62, 0.9, 1.0, 0.85 * (1.0 - 0.5 * t0))
			var cb := Color(ca.r, ca.g, ca.b, ca.a * 0.6)
			var side := Vector3(-nd.z, 0.0, nd.x)
			for sv in [side, Vector3(0, 1, 0)]:
				var s0: Vector3 = sv * wa
				var s1: Vector3 = sv * wb
				_tri_uv(st, [pos - s0, ca, Vector2.ZERO], [p1 - s1, cb, Vector2.ZERO], [p1 + s1, cb, Vector2.ZERO])
				_tri_uv(st, [pos - s0, ca, Vector2.ZERO], [p1 + s1, cb, Vector2.ZERO], [pos + s0, ca, Vector2.ZERO])
			pos = p1
			dir = nd
	st.commit(mesh)
	return mesh


## 062 钳形光弧: 左右两片月牙钳(弧 130°, 根粗尖细, 十字条带)。待发指示与钳合闪共用。
static func _build_claw() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 10
	for side in [-1.0, 1.0]:
		for sg in range(segs):
			var t0: float = float(sg) / float(segs)
			var t1: float = float(sg + 1) / float(segs)
			var a0: float = deg_to_rad(-65.0 + 130.0 * t0) + PI * (0.5 - 0.5 * side)
			var a1: float = deg_to_rad(-65.0 + 130.0 * t1) + PI * (0.5 - 0.5 * side)
			var p0 := Vector3(cos(a0) * 1.0 + 0.18 * side, 0.10 * sin(a0 * 2.0), sin(a0) * 0.85)
			var p1 := Vector3(cos(a1) * 1.0 + 0.18 * side, 0.10 * sin(a1 * 2.0), sin(a1) * 0.85)
			var w0: float = 0.16 * (1.0 - t0 * 0.9)
			var w1: float = 0.16 * (1.0 - t1 * 0.9)
			var c0 := Color(1.0, 0.82, 0.45, 0.85 * (1.0 - t0 * 0.5))
			var c1 := Color(1.0, 0.82, 0.45, 0.85 * (1.0 - t1 * 0.5))
			var nd: Vector3 = (p1 - p0).normalized()
			var sv := Vector3(-nd.z, 0.0, nd.x)
			for ax in [sv, Vector3(0, 1, 0)]:
				var s0: Vector3 = ax * w0
				var s1: Vector3 = ax * w1
				_tri_uv(st, [p0 - s0, c0, Vector2.ZERO], [p1 - s1, c1, Vector2.ZERO], [p1 + s1, c1, Vector2.ZERO])
				_tri_uv(st, [p0 - s0, c0, Vector2.ZERO], [p1 + s1, c1, Vector2.ZERO], [p0 + s0, c0, Vector2.ZERO])
	st.commit(mesh)
	return mesh


## 061 壳屑: 一圈小碎片(菱形光点复用), 节点 scale 弹开读成迸出
static func _build_chips() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(6):
		var b: int = i * 23 + 7
		var ang: float = TAU * _hh(b)
		var r: float = 0.45 + 0.5 * _hh(b + 1)
		var c := Vector3(cos(ang) * r, 0.15 + 0.5 * _hh(b + 2), sin(ang) * r)
		_mote(st, c, 0.09 + 0.06 * _hh(b + 3), Vector2(r, float(i) / 6.0))
	st.commit(mesh)
	return mesh


## 单位半径的贴地细环(用作引爆环 / 诅咒云外沿; 060 的庇护圈已换浮游光点带)
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


## 真·细管圆环(063 持久叠环/引爆用): R=1, a=0.14 的标准圆环面 —— 有真实的洞。
## ★_build_torus 那个是 R=a 的角环(内半径 0 没有洞, 环感靠明暗假装), 顶视角=实心盘;
##   飞行环(斜视+暗部)骗得过去, 套身持久环骗不过去(2026-08-11 实拍连翻三轮才定位)。
static func _build_torus_thin() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var A := 0.14
	for j in range(RING_LON):
		var t0: float = float(j) / float(RING_LON) * TAU
		var t1: float = float(j + 1) / float(RING_LON) * TAU
		for k in range(RING_TUBE):
			var p0: float = float(k) / float(RING_TUBE) * TAU
			var p1: float = float(k + 1) / float(RING_TUBE) * TAU
			_tri(st, _tor2_vert(t0, p0, A), _tor2_vert(t1, p0, A), _tor2_vert(t1, p1, A))
			_tri(st, _tor2_vert(t0, p0, A), _tor2_vert(t1, p1, A), _tor2_vert(t0, p1, A))
	st.commit(mesh)
	return mesh


static func _tor2_vert(th: float, ph: float, a: float) -> Array:
	var dir := Vector3(cos(th), 0.0, sin(th))
	var p: Vector3 = dir * (1.0 + a * cos(ph)) + Vector3(0.0, a * sin(ph), 0.0)
	var al: float = lerpf(0.5, 1.0, 0.5 + 0.5 * sin(ph))
	return [p, Color(1, 1, 1, al)]


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
	if _m_plank == null: _m_plank = _build_plank()
	if _m_upf == null: _m_upf = _build_upf()
	if _m_upf_big == null: _m_upf_big = _build_upf(3.0)
	if _m_cracks.is_empty():
		for b in range(4): _m_cracks.append(_build_cracks(b))
	if _m_chips == null: _m_chips = _build_chips()
	if _m_claw == null: _m_claw = _build_claw()
	if _m_torus_thin == null: _m_torus_thin = _build_torus_thin()


## 节点上打的自定义 meta 键 —— 门禁按 meta 数点数, **不按名字/贴图路径**:
## 程序生成的网格 resource_path 是空串, 按路径数会全部数成 0(SynergyVfx 已记过这个坑)。
const META_KEY := "spirit_eq_vfx"


## 建节点并挂进 _world + 打 meta。返回节点(挂不上时返回 null)。
func _spawn_node(mesh: ArrayMesh, mat: Material, org: Vector3, kind: String) -> MeshInstance3D:
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
## covered = 本次被罩住的队友(单位字典数组) —— 每人头顶起一簇环绕磷光点(谁被罩着一眼可读)。
## ⚠ 庇护范围的半径必须**量真实节点**: plank 场节点的 scale = radius_px × WS
##   (浮游光点带的 r=1 就是 200 码 —— 长相换成生物了, 半径语义没变)。
func parasol_open(pos2d: Vector2, col: Color, radius_px: float, dur: float, covered: Array = []) -> Dictionary:
	if not _has_world():
		return {}
	_ensure_meshes()
	_ensure_room()
	var org: Vector3 = battle._world_pos(pos2d, 0.0)
	## 伞本体挂在龟头顶上方一点(伞是撑开在头顶的)
	var bell := _spawn_node(_m_bell, _shader_mat(SH_JELLY, 8), org + Vector3(0.0, 1.30, 0.0), "bell")
	## 磷光浮游场: 静布光点 + 开伞光波扫过点亮 + 圈带常亮(替掉几何圆环)
	var plank := _spawn_node(_m_plank, _shader_mat(SH_PLANK, 9, 0), org, "plank")
	var upf := _spawn_node(_m_upf, _shader_mat(SH_PLANK, 10, 1), org, "upf")
	if bell == null or plank == null or upf == null:
		return {}
	var h := {
		"kind": "parasol", "bell": bell, "plank": plank, "upf": upf, "col": col,
		"bell_r": 78.0 * float(battle.WS), "ring_r": radius_px * float(battle.WS),
		"dur": maxf(dur, 0.01), "t": 0.0,
	}
	_live.append(h)
	apply_at(h, 0.0)
	## 丙: 被罩队友的环绕磷光点(独立句柄, 各自跟随单位)
	for cu in covered:
		if cu is Dictionary:
			parasol_cover(cu, dur)
	return h


## 060·丙: 被罩队友头顶撑起一把【迷你水母伞】(同款钟体, 与主伞同步开合搏动) +
## 环绕磷光微粒。「伞下的人头顶有小伞」—— 用户 2026-08-11:「给友军的罩子特效不明显」。
func parasol_cover(u: Dictionary, dur: float) -> Dictionary:
	if not _has_world():
		return {}
	_ensure_meshes()
	_ensure_room()
	var org: Vector3 = battle._world_pos(u.get("pos", Vector2.ZERO), 2.15)
	var bell := _spawn_node(_m_bell, _shader_mat(SH_JELLY, 11), org, "bell")
	var nd := _spawn_node(_m_upf_big, _shader_mat(SH_PLANK, 12, 1), battle._world_pos(u.get("pos", Vector2.ZERO), 1.7), "mote")
	if nd != null and nd.material_override is ShaderMaterial:
		(nd.material_override as ShaderMaterial).set_shader_parameter("u_boost", 1.6)
	if bell == null or nd == null:
		return {}
	var h := {"kind": "pcover", "bell": bell, "mote": nd, "u": u,
		"bell_r": 44.0 * float(battle.WS), "r": 38.0 * float(battle.WS),
		"dur": maxf(dur, 0.01), "t": 0.0}
	_live.append(h)
	apply_at(h, 0.0)
	return h


## 060·丙: 闪避触发的迷你伞残影 —— 「伞替你挡了一下」。0.3 秒快速开合。
func parasol_dodge_flash(u: Dictionary) -> Dictionary:
	if not _has_world():
		return {}
	_ensure_meshes()
	_ensure_room()
	var nd := _spawn_node(_m_bell, _shader_mat(SH_JELLY, 12), battle._world_pos(u.get("pos", Vector2.ZERO), 2.0), "bell")
	if nd == null:
		return {}
	var h := {"kind": "pflash", "bell": nd, "u": u, "r": 34.0 * float(battle.WS),
		"dur": 0.30, "t": 0.0}
	_live.append(h)
	apply_at(h, 0.0)
	return h


## 收血绿(治疗的通用语义色 —— 形态仍是有机光点, 不是圆圈)
const HEAL_GREEN := Color(0.45, 1.0, 0.55)


## 060·丙: 收伞回血, 两拍(用户 2026-08-11 拍板「回血的时候加个绿色回复的特效」):
##   ① 0~0.4s 伞的磷光收束成光流回到身体(青) —— 回血的因;
##   ② 0.3~0.95s 身体涌出【绿色恢复光点】上浮消散 —— 回血的果, 数字随后落。
func parasol_heal(u: Dictionary) -> Dictionary:
	if not _has_world():
		return {}
	_ensure_meshes()
	_ensure_room()
	var nd := _spawn_node(_m_upf_big, _shader_mat(SH_PLANK, 11, 1), battle._world_pos(u.get("pos", Vector2.ZERO), 1.4), "mote")
	var gm := _spawn_node(_m_upf_big, _shader_mat(SH_PLANK, 12, 1), battle._world_pos(u.get("pos", Vector2.ZERO), 1.1), "gmote")
	if nd == null or gm == null:
		return {}
	if gm.material_override is ShaderMaterial:
		(gm.material_override as ShaderMaterial).set_shader_parameter(
			"u_col", Vector3(HEAL_GREEN.r, HEAL_GREEN.g, HEAL_GREEN.b))
		(gm.material_override as ShaderMaterial).set_shader_parameter("u_boost", 2.6)
	var h := {"kind": "pheal", "mote": nd, "gmote": gm, "u": u, "r0": 64.0 * float(battle.WS),
		"dur": 0.95, "t": 0.0}
	_live.append(h)
	apply_at(h, 0.0)
	return h


## 061: 持久裂纹覆盖层(跟随目标, 层数=档位+尺寸, 满 20 白热搏动)。create-or-update。
## 句柄存在 tgt["_breach_h"](单位自己的字段, 不拿单位当键 §3.2)。
func breach_overlay(tgt: Dictionary, n: int) -> void:
	if not _has_world():
		return
	_ensure_meshes()
	var h = tgt.get("_breach_h", null)
	var band: int = 3 if n >= BREACH_CAP else (2 if n >= 13 else (1 if n >= 6 else 0))
	if h is Dictionary and is_instance_valid((h as Dictionary).get("cracks", null)):
		(h as Dictionary)["n"] = n
		if int((h as Dictionary).get("band", -1)) != band:
			(h as Dictionary)["band"] = band
			(h as Dictionary)["cracks"].mesh = _m_cracks[band]
		return
	_ensure_room()
	var nd := _spawn_node(_m_cracks[band], _mat(false, 13), battle._world_pos(tgt.get("pos", Vector2.ZERO), 1.2), "cracks")
	if nd == null:
		return
	var hh := {"kind": "breach_ov", "cracks": nd, "u": tgt, "n": n, "band": band,
		"base_r": 64.0 * float(battle.WS), "dur": 1.0e9, "t": 0.0}
	tgt["_breach_h"] = hh
	_live.append(hh)
	apply_at(hh, 0.0)


## 061: 钻入闪(裂纹小星速闪) + 壳屑迸出。每次普攻命中一次。
func drill_flash(pos2d: Vector2) -> void:
	if not _has_world():
		return
	_ensure_meshes()
	_ensure_room()
	var fl := _spawn_node(_m_cracks[1], _mat(false, 14), battle._world_pos(pos2d, 1.4), "flash")
	var ch := _spawn_node(_m_chips, _mat(false, 14), battle._world_pos(pos2d, 1.0), "chips")
	if fl == null or ch == null:
		return
	var h := {"kind": "pdrill", "flash": fl, "chips": ch,
		"r": 40.0 * float(battle.WS), "dur": 0.28, "t": 0.0}
	_live.append(h)
	apply_at(h, 0.0)


## (旧)一次性裂纹环 —— 已被 breach_overlay/drill_flash 取代, 留给门禁形态用例。
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


## 062: 【蓄好待发】指示 —— 携带者身前一对钳形光弧微微开合, 命中消费即收。
func mantis_ready(u: Dictionary) -> void:
	if not _has_world():
		return
	_ensure_meshes()
	var h = u.get("_mready_h", null)
	if h is Dictionary and is_instance_valid((h as Dictionary).get("claw", null)):
		return
	_ensure_room()
	var nd := _spawn_node(_m_claw, _mat(false, 13), battle._world_pos(u.get("pos", Vector2.ZERO), 1.5), "claw")
	if nd == null:
		return
	var hh := {"kind": "mready", "claw": nd, "u": u, "r": 30.0 * float(battle.WS), "dur": 1.0e9, "t": 0.0}
	u["_mready_h"] = hh
	_live.append(hh)
	apply_at(hh, 0.0)


func mantis_consume(u: Dictionary) -> void:
	var h = u.get("_mready_h", null)
	if h is Dictionary:
		_free_handle(h)
		drop(h)
	u["_mready_h"] = null


## 062: 强化命中三拍(照真实空化时序, 全有机形态): ①钳形 V 双弧快斩 ②小气泡簇向心聚缩
## ③星形溃灭闪 + 壳屑(Rayleigh「第二段必然更亮」保住, 亮的是尖锐星芒不是白球)。
func mantis_hit(pos2d: Vector2) -> void:
	if not _has_world():
		return
	_ensure_meshes()
	_ensure_room()
	var claw := _spawn_node(_m_claw, _mat(false, 14), battle._world_pos(pos2d, 1.4), "claw")
	var bub := _spawn_node(_m_upf_big, _mat(false, 13), battle._world_pos(pos2d, 1.2), "bub")
	var fl := _spawn_node(_m_cracks[1], _mat(false, 14), battle._world_pos(pos2d, 1.3), "flash")
	var ch := _spawn_node(_m_chips, _mat(false, 14), battle._world_pos(pos2d, 1.0), "chips")
	if claw == null or bub == null or fl == null or ch == null:
		return
	var h := {"kind": "mhit", "claw": claw, "bub": bub, "flash": fl, "chips": ch,
		"r": 44.0 * float(battle.WS), "dur": 0.50, "t": 0.0}
	_live.append(h)
	apply_at(h, 0.0)


## (旧)两段式圆盘+白球 —— 已被 mantis_hit 取代, 留给门禁形态用例(strike_shape 闭式解仍被钉)。
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
	var tor := _spawn_node(_m_torus_thin, _rm, org + Vector3(0.0, 0.30 + 0.22 * float(idx), 0.0), "ring")
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


## 063: 加环演出 —— 大环贴地从外收拢、落到本层叠环的半径上(用户 2026-08-11 三改:
## 「添加环做大环缩小到环的特效」, 上升涡环废弃)。n = 落成后的层数(决定落点半径)。
func whale_ring_apply(tgt: Dictionary, n: int) -> void:
	if not _has_world():
		return
	_ensure_meshes()
	_ensure_room()
	var _rma := _mat(false, 14)
	_rma.cull_mode = BaseMaterial3D.CULL_BACK
	var tor := _spawn_node(_m_torus_thin, _rma, battle._world_pos(tgt.get("pos", Vector2.ZERO), 0.10), "ring")
	if tor == null:
		return
	var r_end: float = 30.0 * float(battle.WS) * (1.0 + 0.45 * float(maxi(n - 1, 0)))
	var h := {"kind": "wapply", "ring": tor, "u": tgt, "r0": r_end * 2.4, "r1": r_end,
		"dur": 0.30, "t": 0.0}
	_live.append(h)
	apply_at(h, 0.0)


## 063: 持久叠环覆盖层 —— 1~2 个亮气环悬在目标头顶慢转微浮, 层数即读数(引爆前一直在)。
## 旧状态: 环的视觉只活 1.1s(飞行演出)而层数持续到 3 ⇒ 叠环状态大部分时间零显示。
func whale_stack(tgt: Dictionary, n: int) -> void:
	if not _has_world():
		return
	_ensure_meshes()
	var h = tgt.get("_wring_h", null)
	if h is Dictionary and is_instance_valid((h as Dictionary).get("torus", null)):
		(h as Dictionary)["n"] = n
		return
	_ensure_room()
	var _rm1 := _mat(false, 13)
	_rm1.cull_mode = BaseMaterial3D.CULL_BACK   # ★只画正面: 内侧面露出来会读成"碗/实心圆"(用户点名要空心环)
	var _rm2 := _mat(false, 13)
	_rm2.cull_mode = BaseMaterial3D.CULL_BACK
	var t1 := _spawn_node(_m_torus_thin, _rm1, battle._world_pos(tgt.get("pos", Vector2.ZERO), 0.10), "torus")
	var t2 := _spawn_node(_m_torus_thin, _rm2, battle._world_pos(tgt.get("pos", Vector2.ZERO), 0.10), "torus2")
	if t1 == null or t2 == null:
		return
	var hh := {"kind": "wring_ov", "torus": t1, "torus2": t2, "u": tgt, "n": n,
		"r": 30.0 * float(battle.WS), "dur": 1.0e9, "t": 0.0}
	tgt["_wring_h"] = hh
	_live.append(hh)
	apply_at(hh, 0.0)


## 063: 引爆 —— 叠环归心收缩 + 星形爆闪 + 碎屑(真伤白字由效果侧跳)。
func whale_detonate(tgt: Dictionary) -> void:
	var h = tgt.get("_wring_h", null)
	if h is Dictionary:
		_free_handle(h)
		drop(h)
	tgt["_wring_h"] = null
	if not _has_world():
		return
	_ensure_meshes()
	_ensure_room()
	var _rmd := _mat(false, 14)
	_rmd.cull_mode = BaseMaterial3D.CULL_BACK
	var tor := _spawn_node(_m_torus_thin, _rmd, battle._world_pos(tgt.get("pos", Vector2.ZERO), 0.10), "torus")
	var fl := _spawn_node(_m_cracks[2], _mat(false, 14), battle._world_pos(tgt.get("pos", Vector2.ZERO), 1.4), "flash")
	var ch := _spawn_node(_m_chips, _mat(false, 14), battle._world_pos(tgt.get("pos", Vector2.ZERO), 1.0), "chips")
	if tor == null or fl == null or ch == null:
		return
	var hh := {"kind": "wdet", "torus": tor, "flash": fl, "chips": ch,
		"r": 40.0 * float(battle.WS), "dur": 0.42, "t": 0.0}
	_live.append(hh)
	apply_at(hh, 0.0)


## 063: 攻速期升泡流 —— 白鲸吐泡加速的语义, buff 持续多久泡流就冒多久。
func whale_haste(u: Dictionary, sec: float) -> void:
	if not _has_world() or sec <= 0.05:
		return
	_ensure_meshes()
	_ensure_room()
	var gm := _spawn_node(_m_upf_big, _shader_mat(SH_PLANK, 12, 1), battle._world_pos(u.get("pos", Vector2.ZERO), 1.6), "mote")
	if gm == null:
		return
	if gm.material_override is ShaderMaterial:
		(gm.material_override as ShaderMaterial).set_shader_parameter("u_boost", 1.6)
	var hh := {"kind": "whaste", "mote": gm, "u": u, "r": 34.0 * float(battle.WS),
		"dur": sec, "t": 0.0}
	_live.append(hh)
	apply_at(hh, 0.0)


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
		"breach_ov": _apply_breach_ov(h)
		"pdrill": _apply_pdrill(h, u)
		"mready": _apply_mready(h)
		"mhit": _apply_mhit(h, u)
		"wring_ov": _apply_wring(h)
		"wapply": _apply_wapply(h, u)
		"wdet": _apply_wdet(h, u)
		"whaste": _apply_whaste(h, u)
		"pcover": _apply_pcover(h, u)
		"pflash": _apply_pflash(h, u)
		"pheal": _apply_pheal(h, u)
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
	## 钟体 shader: 张开度/时间喂 uniform(搏动·菲涅尔·脉络·触须行波全在 shader 里)
	var bm = h["bell"].material_override if is_instance_valid(h["bell"]) else null
	if bm is ShaderMaterial:
		bm.set_shader_parameter("u_t", t)
		bm.set_shader_parameter("u_open", f)
		bm.set_shader_parameter("u_alpha", col.a)
	## ★庇护范围是【效果半径的真实写照】: plank 场半径恒等于 200 码, 不随伞的振荡缩放 ——
	##   它表示的是"谁在范围里", 拿它当演出去过冲就是在骗玩家。亮相由 shader 里的
	##   光波(开伞后 0.55s 扫满)与圈带常亮承担 —— 长相是浮游生物, 不是几何线圈。
	var rr: float = float(h["ring_r"])
	_set_scale(h["plank"], Vector3(rr, rr, rr))
	var pm = h["plank"].material_override if is_instance_valid(h["plank"]) else null
	if pm is ShaderMaterial:
		pm.set_shader_parameter("u_t", t)
		pm.set_shader_parameter("u_open", clampf(f, 0.0, 1.0))
		pm.set_shader_parameter("u_wave_t", t if t < 0.8 else -1.0)
		pm.set_shader_parameter("u_alpha", col.a)
	## 伞下上浮微粒(伞半径尺度)
	var ur: float = float(h["bell_r"]) * 1.15
	_set_scale(h["upf"], Vector3(ur, ur, ur))
	var um = h["upf"].material_override if is_instance_valid(h["upf"]) else null
	if um is ShaderMaterial:
		um.set_shader_parameter("u_t", t)
		um.set_shader_parameter("u_open", clampf(f, 0.0, 1.0))
		um.set_shader_parameter("u_alpha", col.a * 0.8)


## 被罩队友: 迷你伞(与主伞同一条开合曲线 ⇒ 同步呼吸) + 环绕磷光点, 都跟随单位。
func _apply_pcover(h: Dictionary, u: float) -> void:
	var uu = h.get("u", null)
	if not (uu is Dictionary):
		return
	var t: float = clampf(u, 0.0, 1.0) * float(h["dur"])
	var f: float = parasol_open_frac(t, float(h["dur"]))
	var bell = h.get("bell", null)
	if is_instance_valid(bell):
		bell.position = battle._world_pos((uu as Dictionary).get("pos", Vector2.ZERO), 2.15)
		var br: float = float(h["bell_r"]) * maxf(f, 0.001)
		bell.scale = Vector3(br, br, br)
		var bm = bell.material_override
		if bm is ShaderMaterial:
			bm.set_shader_parameter("u_t", t)
			bm.set_shader_parameter("u_open", f)
			bm.set_shader_parameter("u_alpha", 0.62)
	var nd = h.get("mote", null)
	if not is_instance_valid(nd):
		return
	nd.position = battle._world_pos((uu as Dictionary).get("pos", Vector2.ZERO), 1.7)
	var r: float = float(h["r"])
	nd.scale = Vector3(r, r, r)
	var m = nd.material_override
	if m is ShaderMaterial:
		m.set_shader_parameter("u_t", t)
		m.set_shader_parameter("u_open", clampf(f, 0.0, 1.0))
		m.set_shader_parameter("u_alpha", 0.95)


## 闪避残影: 迷你伞 0.3 秒快速开合(开合曲线复用同一套阻尼阶跃)。
func _apply_pflash(h: Dictionary, u: float) -> void:
	var uu = h.get("u", null)
	var nd = h.get("bell", null)
	if not is_instance_valid(nd):
		return
	if uu is Dictionary:
		nd.position = battle._world_pos((uu as Dictionary).get("pos", Vector2.ZERO), 2.0)
	var t: float = clampf(u, 0.0, 1.0) * float(h["dur"])
	var f: float = parasol_open_frac(t, float(h["dur"]))
	var r: float = float(h["r"]) * maxf(f, 0.001)
	nd.scale = Vector3(r, r, r)
	var m = nd.material_override
	if m is ShaderMaterial:
		m.set_shader_parameter("u_t", t)
		m.set_shader_parameter("u_open", f)
		m.set_shader_parameter("u_alpha", 0.9)


## 收伞回血两拍: ①磷光收束进身体(青, 0~0.4s) ②绿色恢复光点从身体涌出上浮(0.3~0.95s)。
func _apply_pheal(h: Dictionary, u: float) -> void:
	var uu = h.get("u", null)
	var t: float = clampf(u, 0.0, 1.0) * float(h["dur"])
	## ① 收束(青)
	var nd = h.get("mote", null)
	if is_instance_valid(nd):
		if uu is Dictionary:
			nd.position = battle._world_pos((uu as Dictionary).get("pos", Vector2.ZERO), 1.4)
		var k1: float = clampf(t / 0.4, 0.0, 1.0)
		var r: float = float(h["r0"]) * lerpf(1.0, 0.12, k1 * k1)
		nd.scale = Vector3(r, r, r)
		var m = nd.material_override
		if m is ShaderMaterial:
			m.set_shader_parameter("u_t", k1 * 0.4)
			m.set_shader_parameter("u_open", 1.0)
			m.set_shader_parameter("u_alpha", 0.9 * (1.0 - k1 * k1))
	## ② 绿色恢复(治疗语义色): 上浮光点, 亮度走 sin 包(起于收束将尽时)
	var gm = h.get("gmote", null)
	if is_instance_valid(gm):
		if uu is Dictionary:
			gm.position = battle._world_pos((uu as Dictionary).get("pos", Vector2.ZERO), 1.1)
		var k2: float = clampf((t - 0.30) / 0.65, 0.0, 1.0)
		var gr: float = 54.0 * float(battle.WS)
		gm.scale = Vector3(gr, gr, gr)
		var m2 = gm.material_override
		if m2 is ShaderMaterial:
			m2.set_shader_parameter("u_t", k2 * 4.0)          # 驱动上浮循环(拉快: 一次浮到顶)
			m2.set_shader_parameter("u_open", sin(k2 * PI))
			m2.set_shader_parameter("u_alpha", 1.0)


## 持久裂纹: 跟随单位; 尺寸 = crack_len(n)(Paris 律 —— 快满暴涨是积分出来的不是拍的);
## 满层白热搏动(读数=「下一击真伤」)。单位死亡自清。
func _apply_breach_ov(h: Dictionary) -> void:
	var uu = h.get("u", null)
	var nd = h.get("cracks", null)
	if not is_instance_valid(nd):
		return
	if not (uu is Dictionary) or not (uu as Dictionary).get("alive", false):
		_free_handle(h)
		if uu is Dictionary:
			(uu as Dictionary)["_breach_h"] = null
		drop(h)
		return
	nd.position = battle._world_pos((uu as Dictionary).get("pos", Vector2.ZERO), 1.2)
	var n: int = int(h.get("n", 0))
	var g: float = crack_len(float(n))
	var r: float = float(h["base_r"]) * (0.35 + 0.65 * g)
	nd.scale = Vector3(r, r, r)
	var a: float = 0.7 + 0.3 * g
	if n >= BREACH_CAP:
		a = 0.75 + 0.25 * sin(float(h.get("t", 0.0)) * 9.0)   # 白热搏动
	_set_col(nd, Color(1, 1, 1, a))


## 待发钳弧: 跟随单位, 微微开合搏动(scale 呼吸); 单位死亡自清。
func _apply_mready(h: Dictionary) -> void:
	var uu = h.get("u", null)
	var nd = h.get("claw", null)
	if not is_instance_valid(nd):
		return
	if not (uu is Dictionary) or not (uu as Dictionary).get("alive", false):
		_free_handle(h)
		if uu is Dictionary:
			(uu as Dictionary)["_mready_h"] = null
		drop(h)
		return
	nd.position = battle._world_pos((uu as Dictionary).get("pos", Vector2.ZERO), 1.5)
	var t: float = float(h.get("t", 0.0))
	var r: float = float(h["r"]) * (1.0 + 0.08 * sin(t * 5.0))
	nd.scale = Vector3(r, r, r)
	nd.rotation.y = 0.25 * sin(t * 2.1)
	_set_col(nd, Color(1, 1, 1, 0.6 + 0.2 * sin(t * 5.0)))


## 强化命中三拍: 钳斩(0~0.12 过冲) → 气泡簇聚缩(0.1~0.32) → 星形溃灭闪+壳屑(0.28~0.5)
func _apply_mhit(h: Dictionary, u: float) -> void:
	var t: float = clampf(u, 0.0, 1.0) * float(h["dur"])
	var r: float = float(h["r"])
	var claw = h.get("claw", null)
	if is_instance_valid(claw):
		var k1: float = clampf(t / 0.12, 0.0, 1.0)
		var cr: float = r * (0.5 + 1.0 * k1)
		claw.scale = Vector3(cr, cr, cr)
		_set_col(claw, Color(1, 1, 1, 0.95 * (1.0 - k1)))
	var bub = h.get("bub", null)
	if is_instance_valid(bub):
		var k2: float = clampf((t - 0.10) / 0.22, 0.0, 1.0)
		var br: float = r * lerpf(1.1, 0.3, k2)          # 向心聚缩(空泡被压向溃灭点)
		bub.scale = Vector3(br, br, br)
		_set_col(bub, Color(1, 1, 1, (0.7 * k2 + 0.2) * (1.0 if t < 0.32 else 0.0)))
	var fl = h.get("flash", null)
	if is_instance_valid(fl):
		var k3: float = clampf((t - 0.28) / 0.22, 0.0, 1.0)
		var fr: float = r * (0.4 + 1.2 * sin(k3 * PI))
		fl.scale = Vector3(fr, fr, fr)
		_set_col(fl, Color(1, 1, 1, 0.95 * sin(k3 * PI)))
	var ch = h.get("chips", null)
	if is_instance_valid(ch):
		var k4: float = clampf((t - 0.28) / 0.22, 0.0, 1.0)
		var r2: float = r * (0.4 + 1.2 * k4)
		ch.scale = Vector3(r2, r2, r2)
		_set_col(ch, Color(1, 1, 1, 0.9 * (1.0 - k4 * k4) * (1.0 if t >= 0.28 else 0.0)))


## 叠环覆盖: 跟随目标, 慢转微浮; n 决定第二环显不显; 死亡自清。亮青(A/B 推深过的那支)。
func _apply_wring(h: Dictionary) -> void:
	var uu = h.get("u", null)
	var t1 = h.get("torus", null)
	if not is_instance_valid(t1):
		return
	if not (uu is Dictionary) or not (uu as Dictionary).get("alive", false):
		_free_handle(h)
		if uu is Dictionary:
			(uu as Dictionary)["_wring_h"] = null
		drop(h)
		return
	var t: float = float(h.get("t", 0.0))
	var n: int = int(h.get("n", 1))
	var r: float = float(h["r"])
	var i := 0
	for key in ["torus", "torus2"]:
		var nd = h.get(key, null)
		if not is_instance_valid(nd):
			i += 1
			continue
		# ★环【平铺地面·同心外扩】(用户 2026-08-11 二改: 环放地下, 第二个比第一个大)
		nd.position = battle._world_pos((uu as Dictionary).get("pos", Vector2.ZERO), 0.10)
		var ri: float = r * (1.0 + 0.45 * float(i))   # 第二环半径 ×1.45
		nd.scale = Vector3(ri, ri * 0.5, ri)          # y 压扁一点: 贴地环不需要立管
		nd.rotation.y = t * (0.9 + 0.4 * float(i))
		var vis: float = 0.8 if n > i else 0.0
		_set_col(nd, Color(0.28, 0.72, 1.0, vis))
		i += 1


## 加环: 大环贴地收拢落位(跟随目标), 落定时最亮
func _apply_wapply(h: Dictionary, u: float) -> void:
	var uu = h.get("u", null)
	var nd = h.get("ring", null)
	if not is_instance_valid(nd):
		return
	if uu is Dictionary:
		nd.position = battle._world_pos((uu as Dictionary).get("pos", Vector2.ZERO), 0.10)
	var k: float = clampf(u, 0.0, 1.0)
	var r: float = lerpf(float(h["r0"]), float(h["r1"]), 1.0 - (1.0 - k) * (1.0 - k))
	nd.scale = Vector3(r, r * 0.5, r)
	_set_col(nd, Color(0.28, 0.72, 1.0, 0.35 + 0.55 * k))


## 引爆: 环归心收缩 + 星形爆闪 + 碎屑弹开
func _apply_wdet(h: Dictionary, u: float) -> void:
	var k: float = clampf(u, 0.0, 1.0)
	var r: float = float(h["r"])
	var tor = h.get("torus", null)
	if is_instance_valid(tor):
		# ★引爆【向外炸开】(用户: 要爆开不是缩小): 环从叠环半径向外冲到 2.6 倍并淡出
		var tr: float = r * lerpf(0.6, 2.6, 1.0 - (1.0 - k) * (1.0 - k))
		tor.scale = Vector3(tr, tr * 0.5, tr)
		_set_col(tor, Color(0.28, 0.72, 1.0, 0.9 * (1.0 - k)))
	var fl = h.get("flash", null)
	if is_instance_valid(fl):
		var fr: float = r * (0.4 + 1.3 * sin(k * PI))
		fl.scale = Vector3(fr, fr, fr)
		_set_col(fl, Color(1, 1, 1, 0.95 * sin(k * PI)))
	var ch = h.get("chips", null)
	if is_instance_valid(ch):
		var r2: float = r * (0.4 + 1.3 * k)
		ch.scale = Vector3(r2, r2, r2)
		_set_col(ch, Color(0.6, 0.9, 1.0, 0.9 * (1.0 - k * k)))


## 攻速泡流: 跟随携带者, 首尾 0.2s 淡入淡出
func _apply_whaste(h: Dictionary, u: float) -> void:
	var uu = h.get("u", null)
	var nd = h.get("mote", null)
	if not is_instance_valid(nd):
		return
	if uu is Dictionary:
		nd.position = battle._world_pos((uu as Dictionary).get("pos", Vector2.ZERO), 1.6)
	var t: float = clampf(u, 0.0, 1.0) * float(h["dur"])
	var k: float = minf(minf(t / 0.2, (float(h["dur"]) - t) / 0.2), 1.0)
	var r: float = float(h["r"])
	nd.scale = Vector3(r, r, r)
	var m = nd.material_override
	if m is ShaderMaterial:
		m.set_shader_parameter("u_t", t)
		m.set_shader_parameter("u_open", clampf(k, 0.0, 1.0))
		m.set_shader_parameter("u_alpha", 0.85)


## 060·丙沿用: 只要绿色恢复涌(mote 不建 ⇒ 收束段自动跳过) —— 062 的 40% 吸血也用这支绿。
func green_heal(u: Dictionary) -> void:
	if not _has_world():
		return
	_ensure_meshes()
	_ensure_room()
	var gm := _spawn_node(_m_upf_big, _shader_mat(SH_PLANK, 12, 1), battle._world_pos(u.get("pos", Vector2.ZERO), 1.1), "gmote")
	if gm == null:
		return
	if gm.material_override is ShaderMaterial:
		(gm.material_override as ShaderMaterial).set_shader_parameter(
			"u_col", Vector3(HEAL_GREEN.r, HEAL_GREEN.g, HEAL_GREEN.b))
		(gm.material_override as ShaderMaterial).set_shader_parameter("u_boost", 2.6)
	var h := {"kind": "pheal", "gmote": gm, "u": u, "r0": 0.0, "dur": 0.95, "t": 0.28}
	_live.append(h)
	apply_at(h, 0.28 / 0.95)


## 钻入闪: 裂纹星速闪(过冲缩回) + 壳屑弹开淡出
func _apply_pdrill(h: Dictionary, u: float) -> void:
	var k: float = clampf(u, 0.0, 1.0)
	var fl = h.get("flash", null)
	if is_instance_valid(fl):
		var r: float = float(h["r"]) * (0.5 + 0.9 * sin(k * PI))
		fl.scale = Vector3(r, r, r)
		_set_col(fl, Color(1, 1, 1, 0.95 * (1.0 - k)))
	var ch = h.get("chips", null)
	if is_instance_valid(ch):
		var r2: float = float(h["r"]) * (0.4 + 1.1 * k)
		ch.scale = Vector3(r2, r2, r2)
		_set_col(ch, Color(1, 1, 1, 0.9 * (1.0 - k * k)))


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
	# 真环网格(R=1/a=0.14): 主径直接 R, 管径纵向按 a/0.14 跟守恒变细。
	# (管的水平向厚度随 R 等比 —— 显示近似; 守恒律本体仍由 ring_radius/ring_tube 纯函数钉)
	var sx: float = rm * R
	var sy: float = rm * (a / 0.14)
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

const NODE_KEYS := ["bell", "ring", "disc", "flash", "torus", "sphere", "cloud", "edge", "plank", "upf", "mote", "gmote", "cracks", "chips", "claw", "bub", "torus2"]


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
