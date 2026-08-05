class_name ShockwaveVfx
extends RefCounted
## shockwave_vfx.gd — 盾羁绊【怒气冲击波】的爆轰演出 (方案书 docs/plans/20260804-羁绊特效批.md · 批 B · B2)
##
## ══════════════════════════════════════════════════════════════════════
##  ★为什么不是"放个环再淡出"
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-08-05:「之后我需要 3d 建模都是要触手的水准」。触手立的第 2 条判据是
## **「形态要有物理模型, 不是凑形状」** —— 触手是「弧长恒定 + 曲率密度 κ(u) + 行波偶极子」,
## 那才让它像一根真的鞭子而不是一条会变长的带子。
##
## 冲击波的对应物理是【点爆轰】, 而且它比触手更幸运: **有闭式解, 不用抽帧量**。
## 本文件三条曲线全部是解析式, 一个手调系数都没有 (对照 tentacle_vfx 的
## `SLAM_LEN_CURVE`/`SLAM_W_CURVE` —— 那两张表是逐帧量出来的, 因为参考是视频、没有闭式解)。
##
## ⚠ **诚实记录**: 用户没有给冲击波的视频参考, 所以本条**没有"逐帧量参考"这一步**。
##   代替它的是下面三条闭式解 —— 判据不是"我调得像", 而是"它满足这几条可验证的定律"。
##   门禁验的正是这几条**性质**(尺度不变性 / 过零点 / 极值位置 / 立方根定律),
##   手调出来的缓动曲线**一条都过不了**。
##
## ── ① 波前半径: Sedov–Taylor 强爆轰自相似解 ─────────────────────────
##   R(t) = ξ₀ · (E/ρ)^(1/5) · t^(2/5)      ⇒ 归一后 **R̂(u) = u^(2/5)**
##
##   这个 2/5 指数决定了观感: t=0 处导数**无穷大** —— 波前一瞬间就冲出去,
##   然后越来越慢。任何 `ease_out_cubic` 之类的缓动都是"起步有限速度",
##   做出来是【水波纹】不是【爆炸】。这一条是本演出与"随便放个扩散环"的分水岭。
##
##   ★可验证的性质(门禁 ②): **尺度不变性** R(4u)/R(u) ≡ 4^0.4 = 1.7411, 与 u 无关。
##     手调曲线不可能对所有 u 都满足。
##
## ── ② 亮度: Friedlander 超压波形 ───────────────────────────────────
##   Δp(τ)/Δp₀ = (1 − τ)·e^(−τ)            τ = t / t⁺ (t⁺ = 正压相时长)
##
##   · τ=0 峰值 1.0 (起爆瞬间最亮)
##   · **τ=1 精确过零** —— 正压相结束, 这是解析地标不是我拍的数
##   · τ>1 **负压相**(稀疏波): 极小值在 τ=2, 值 = −e^(−2) = −0.13534
##
##   ★负压相就是这条演出的"余振二次峰"(触手那条判据 3 说的"单调缓动做不出来的东西")。
##     单调淡出永远给不出"先推出去、再吸回来"。
##
## ── ③ 尘埃位移: ②的积分, 而且积得出闭式 ─────────────────────────────
##   尘埃微团的径向速度 ∝ Δp ⇒ 位移 d(τ) = ∫₀^τ (1−s)e^(−s) ds = **τ·e^(−τ)**
##
##   (验算: d/dτ[τe^(−τ)] = e^(−τ) − τe^(−τ) = (1−τ)e^(−τ) ✓ 正是 Friedlander)
##
##   归一化 d̂(τ) = τ·e^(1−τ), **极大值恰好 1.0 且恰好落在 τ=1** ——
##   即"尘埃环冲到最远"与"正压相结束"是**同一瞬间**, 之后被负压吸回来,
##   τ→∞ 时 d̂→0 (**完全回到原位**)。
##   ⇒ 尘埃环半径是【先涨后跌】的, 门禁 ④ 断言的就是这个"跌", 且峰值位置对上 τ=1。
##
## ── ④ 连发合并 (未决点 U2 → 用户拍板 B「同帧合并成一个更大的」) ───────
##   `shield_synergy_system._rage` 一次最多连发 5 次。5 个一样的环叠在同一帧同一点 = 糊成一团。
##   合并后半径按什么放大? —— **不是拍脑袋, 用 Hopkinson–Cranz 立方根定律**:
##       R ∝ W^(1/3),  t⁺ ∝ W^(1/3)     (W = 装药当量, 这里 = 连发次数)
##   ⇒ `energy_scale(n) = n^(1/3)`。5 连发 = **1.710 倍**半径 + 1.710 倍时长。
##   ★可验证性质(门禁 ⑤): `energy_scale(n)³ ≡ n` —— 体积/能量线性可加。
##   ⚠ 合并的只有**演出**; 伤害与护盾一次不少地照发 5 次 (见 shield_synergy_system._rage)。
##
## ── 技术路线 ────────────────────────────────────────────────────────
## 程序化 `ArrayMesh`(`SurfaceTool` 现算), 零素材 —— 同 tentacle_vfx / battle_world_builder。
## 用户铁律「不要复用素材除非我指明了」: 程序化几何不产出图, 不吃这条约束。
##
## ⚠ 朝向坑 (memory [[fb-axis-y-plus-rotation-cancels]]): 本文件**不用 Sprite3D**,
##   直接建世界坐标顶点, 没有 `axis` / `rotation.x=-90` 互相抵消那层歧义。
##   贴地面用 y = GROUND_Y 的水平顶点, 门禁量 |三角面法线·上| ≈ 1.000。


# ══════════════════════════════════════════════════════════════════
#  §物理常数 —— 全部来自闭式解, 没有一个是调出来的
# ══════════════════════════════════════════════════════════════════

## Sedov–Taylor 指数 2/5。★别改成 0.5 之类的"看着顺眼"的数, 那就不是爆轰了。
const SEDOV_EXP := 0.4

## ★显示伽马 —— 把【超压】转成【看得见的亮度】。
##
##   这是**显示变换**, 不是把物理曲线揉圆: 物理量仍然是 Friedlander 原样,
##   只是亮度按感知(近似 sRGB 的 1/2.2 ≈ 0.45)去映射, 同 UI 里线性值转 sRGB 那一步。
##
## ⚠ 为什么必须有: 第一版 a = Δp 直接当 alpha, 结果是 ——
##   **波前在还看得见的时候只走到 51% 最大半径, 剩下一半是在全透明状态下长完的。**
##   于是门禁量出来的"最大直径 3.84 m"是一个**玩家永远看不到的数**。
##   这正是用户立的判据 5「尺子必须匹配被测概念」说的那类错误(拿投影臂长量"拍了几次")。
##   加伽马之后 τ=0.8 时亮度还有 0.34、半径已到 91% ⇒ 量的和看的是同一个东西。
##   门禁 ⑦ 有一条专门守它: 【还看得见时】必须已冲到 ≥85% 半径。
const DISPLAY_GAMMA := 0.45
## 立方根定律指数 (Hopkinson–Cranz)
const CUBE_ROOT := 1.0 / 3.0
## 动画跑到 Friedlander 的 τ = 6 收尾。
## 为什么是 6: τ=6 时残余超压 = −0.0124, 只有负压峰(−0.1353)的 **9.2%** ⇒ 切掉看不出跳变。
## 取 4 的话尾巴还有 41%, 会"啪"一下断掉。
const TAU_END := 6.0
## 正压相占整段动画的比例 = 1/TAU_END = 0.1667。
## ⇒ 0.55 秒的一发里, 亮的只有前 0.092 秒(约 5.5 帧@60fps)。爆炸就该是这个比例。
const POS_FRAC := 1.0 / TAU_END

## 尘埃环的起始半径(相对最大半径)。它从这里被推到 1.0 再被吸回来。
const DUST_SEED := 0.35

## 波前几何: 半球壳的经纬分段
const SHELL_LON := 24
const SHELL_LAT := 8
## 贴地环的经向分段(要更密, 否则大半径时看得见多边形折线)
const RING_LON := 48

## 半球壳的顶点亮度: 赤道(贴地)最亮 → 极点最暗。
## ★这不是美术偏好, 是【马赫反射】: 入射波与地面反射波在近地处汇合成马赫杆,
##   那里的超压是自由场的两倍多 ⇒ 真实爆轰的亮环就在地面附近。
const MACH_BASE_A := 1.00
const MACH_TOP_A := 0.12

## 贴地环: 外沿 = 波前(硬边), 内沿 = 拖尾。
## ★外沿【故意是硬的】—— 激波面在数学上就是一个间断面。软化外沿会让它变回"光晕"。
##   内侧的渐隐代表波后被压缩加热的高温区。
const RING_IN := 0.72
## Sedov 解里绝大部分被扫掠质量集中在厚度 R/(3κ) 的薄壳里 (κ=(γ+1)/(γ−1)=6, γ=1.4)
## ⇒ **R/18 = 0.0556R**。这个数只用来定"亮度最集中的那一圈"在哪, 见 _build_ring。
const SHELL_THICK_FRAC := 1.0 / 18.0

## 尘埃环的带宽(相对半径)。尘埃不是间断面, 两侧都软。
const DUST_BAND := 0.16

## 贴地几何的离地高度(米)。地板在 y=0, 抬一点免得 z-fighting。
const GROUND_Y := 0.06

## fired=1 时的最大半径(场地像素)。★这是**演出尺寸**不是效果半径 ——
##   怒气冲击波只打【一个】最近的敌人, 没有 AOE 半径可言。
##   所以这里绝不能拿"效果半径"当贴片尺寸(方案书 R9 / memory [[fb-verify-must-run-the-real-path]]),
##   反过来还要**压着做**: 太大会让玩家以为这是范围伤害。
##   80px × WS(0.024) = 1.92 m ≈ 龟身高(TARGET_BODY_H=2.0m) ⇒ 直径约两只龟宽, 读作"从这只龟身上炸开"。
const R_BASE_PX := 80.0

## fired=1 的整段时长(秒)。合并时 ×energy_scale (t⁺ ∝ W^(1/3), 与半径同律)。
const T_BASE := 0.55

## 震屏基础幅度。★5 连发也只到 0.045×1.710 = 0.077 < JUICE_SHAKE_HEAVY(0.10) ——
##   方案书 §2.3 要求这条"轻", 因为全队每攒 400 伤害就放一次, 频率不低。
const SHAKE_BASE := 0.045

var battle

## ★网格缓存: 两个网格都是【单位半径】的, 每一发只差 scale 与材质 ——
##   所以整局只需要各建一次。不缓存的话每发要现算 ~1150 个顶点(SurfaceTool),
##   而冲击波是"全队每攒 400 伤害放一次", 频率不低 (方案书 R12 手机端预算)。
##   ⚠ 网格可以共享, **材质不行** —— 材质上带着这一发自己的亮度, 共享会让多发互相串色。
## ★存在实例上而不是 `static var`: static 的话进程退出时还挂着 3 个 ArrayMesh,
##   Godot 会报 `ERROR: 3 resources still in use at exit`(实测)。挂实例上就跟着战斗场景一起走,
##   而 ShockwaveVfx 一场战斗只 new 一次 ⇒ 缓存命中率一模一样。
var _cache_shell: ArrayMesh = null
var _cache_ring: ArrayMesh = null
var _cache_dust: ArrayMesh = null


func _init(b) -> void:
	battle = b


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调, 不建节点、不等 tween (方案书 §7.1 / CLAUDE.md §3.5)
# ══════════════════════════════════════════════════════════════════

## Sedov–Taylor 归一波前半径。
##
## ★参数是【强激波相已走的比例】x ∈ [0,1], **不是整段动画的归一时间**。
##   两者的关系是 x = τ —— 因为强激波相**就是**正压相(τ∈[0,1]):
##   τ>1 之后波已经衰减成声波, Sedov 自相似解在那儿本来就不成立, 再往下套是错的。
##   ⇒ 波前在 τ=1 那一刻走到最大半径, 而那一刻它的亮度也恰好归零 —— 交接是严丝合缝的。
##
## ★性质: R(k·x) = k^0.4 · R(x) 对任意 k、任意 x 成立(尺度不变), 只要 k·x ≤ 1。
static func sedov_radius(x: float) -> float:
	return pow(clampf(x, 0.0, 1.0), SEDOV_EXP)


## Friedlander 超压波形。峰值 1.0 @ τ=0, 精确过零 @ τ=1, 极小 −e^(−2) @ τ=2。
static func friedlander(tau: float) -> float:
	if tau <= 0.0:
		return 1.0
	return (1.0 - tau) * exp(-tau)


## 尘埃微团的归一径向位移 = ∫₀^τ Friedlander，再除以它自己的极大值 e^(−1)。
## d̂(τ) = τ·e^(1−τ)。极大值恰为 1.0 恰在 τ=1；τ→∞ 时回到 0(被负压完全吸回)。
static func dust_disp(tau: float) -> float:
	if tau <= 0.0:
		return 0.0
	return tau * exp(1.0 - tau)


## Hopkinson–Cranz 立方根定律: 当量 n 倍 ⇒ 半径与正压相时长各 n^(1/3) 倍。
static func energy_scale(fired: int) -> float:
	return pow(float(maxi(1, fired)), CUBE_ROOT)


## 归一时间 u → Friedlander 的 τ
static func tau_of(u: float) -> float:
	return clampf(u, 0.0, 1.0) * TAU_END


## ★整个形态的单一事实源。门禁与演出**都只读这一个函数**,
##   不许在任何一边把公式抄第二遍 (memory [[fb-write-without-reader-and-fake-gates]]:
##   「门禁模拟公式 ≠ 量真实对象」—— 抄两遍的话把产品代码改坏门禁照样绿)。
##
## 返回(全部归一, 与绝对尺寸无关):
##   r_shock  波前半径 / 最大半径 ← 走 **τ** 不走 u: 强激波相=正压相, τ=1 时到顶(见 sedov_radius)
##   a_shock  波前亮度 = 正压部分再过 DISPLAY_GAMMA 显示变换; τ≥1 恒为 0
##   r_dust   尘埃环半径 / 最大半径  ← **非单调**: 涨到 1.0 再跌回 DUST_SEED
##   a_dust   尘埃环亮度
##   suction  负压强度 (0 = 还在正压相; >0 = 正在往回吸)
static func shape_at(u: float) -> Dictionary:
	var uu: float = clampf(u, 0.0, 1.0)
	var tau: float = tau_of(uu)
	var f: float = friedlander(tau)
	var d: float = dust_disp(tau)
	return {
		"u": uu,
		"tau": tau,
		"r_shock": sedov_radius(tau),
		"a_shock": pow(maxf(f, 0.0), DISPLAY_GAMMA),
		"r_dust": DUST_SEED + (1.0 - DUST_SEED) * d,
		"a_dust": d,
		"suction": maxf(-f, 0.0),
	}


## 这一发的最大半径(米)。fired 是本帧合并掉的连发次数。
func radius_m(fired: int) -> float:
	return R_BASE_PX * float(battle.WS) * energy_scale(fired)


## 这一发的总时长(秒)
static func duration_s(fired: int) -> float:
	return T_BASE * energy_scale(fired)


# ══════════════════════════════════════════════════════════════════
#  §几何 —— 程序化 ArrayMesh, 零素材
# ══════════════════════════════════════════════════════════════════

## 单位半径(=1)的半球壳。马赫杆亮度梯度: 贴地亮, 顶上暗。
##
## ★★为什么半球壳与贴地环是【两个节点】而不是一个网格的两个 surface:
##   它们要的材质不同 —— 贴地那圈必须 `no_depth_test`(地板/珊瑚高度盖不住, 同 _splash_ring_bold),
##   半球壳绝不能关(关了会盖住站在它前面的龟)。
##   而 `set_surface_override_material` 在 `--headless` 的 dummy renderer 下每设一次就刷一条
##   `ERROR: Parameter "material" is null.`(material_storage.cpp:265) ——
##   这条**不在 run-tests.sh 的 FATAL 正则里, 门禁不会红**, 但它是真的在刷错误。
##   实测: tentacle_vfx 用 `material_override` ⇒ 0 条; 本文件第一版用 surface override ⇒ 每发 2 条。
##   ⇒ 拆成一材质一节点, 全走 `material_override`。
static func _build_shell_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(SHELL_LAT):
		var p0: float = float(i) / float(SHELL_LAT) * (PI * 0.5)
		var p1: float = float(i + 1) / float(SHELL_LAT) * (PI * 0.5)
		for j in range(SHELL_LON):
			var t0: float = float(j) / float(SHELL_LON) * TAU
			var t1: float = float(j + 1) / float(SHELL_LON) * TAU
			var a := _shell_vert(p0, t0)
			var b := _shell_vert(p0, t1)
			var c := _shell_vert(p1, t1)
			var d := _shell_vert(p1, t0)
			_tri(st, a, b, c)
			_tri(st, a, c, d)
	st.commit(mesh)
	return mesh


## 单位半径的贴地环(波前的地面痕迹)。外沿硬 = 激波间断面; 内沿渐隐 = 波后高温区。
static func _build_ring_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	## 亮度最集中的一圈落在 1 − SHELL_THICK_FRAC 处(Sedov 薄壳中心), 那里给满亮度;
	## 从它往内侧一路渐隐到 RING_IN, 往外侧到 1.0 只掉一点点(外沿仍然是亮的硬边)。
	var r_hot: float = 1.0 - SHELL_THICK_FRAC
	for j in range(RING_LON):
		var t0: float = float(j) / float(RING_LON) * TAU
		var t1: float = float(j + 1) / float(RING_LON) * TAU
		var quads := [[RING_IN, 0.0, r_hot, 1.0], [r_hot, 1.0, 1.0, 0.85]]
		for q in quads:
			var ri: float = float(q[0])
			var ai: float = float(q[1])
			var ro: float = float(q[2])
			var ao: float = float(q[3])
			var a := _flat_vert(ri, t0, ai)
			var b := _flat_vert(ro, t0, ao)
			var c := _flat_vert(ro, t1, ao)
			var d := _flat_vert(ri, t1, ai)
			_tri(st2, a, b, c)
			_tri(st2, a, c, d)
	st2.commit(mesh)
	return mesh


## 单位半径的尘埃环 —— 一条两侧都软的贴地带(尘埃不是间断面)。
static func _build_dust_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r_in: float = 1.0 - DUST_BAND
	var r_mid: float = 1.0 - DUST_BAND * 0.5
	for j in range(RING_LON):
		var t0: float = float(j) / float(RING_LON) * TAU
		var t1: float = float(j + 1) / float(RING_LON) * TAU
		for q in [[r_in, 0.0, r_mid, 1.0], [r_mid, 1.0, 1.0, 0.0]]:
			var ri: float = float(q[0])
			var ai: float = float(q[1])
			var ro: float = float(q[2])
			var ao: float = float(q[3])
			var a := _flat_vert(ri, t0, ai)
			var b := _flat_vert(ro, t0, ao)
			var c := _flat_vert(ro, t1, ao)
			var d := _flat_vert(ri, t1, ai)
			_tri(st, a, b, c)
			_tri(st, a, c, d)
	st.commit(mesh)
	return mesh


## 半球壳上的一个顶点。返回 [位置, 顶点色]。
static func _shell_vert(phi: float, th: float) -> Array:
	var p := Vector3(cos(phi) * cos(th), sin(phi), cos(phi) * sin(th))
	var a: float = lerpf(MACH_BASE_A, MACH_TOP_A, sin(phi))
	return [p, Color(1, 1, 1, a)]


## 贴地面上的一个顶点(y = GROUND_Y, 平的)
static func _flat_vert(r: float, th: float, a: float) -> Array:
	return [Vector3(r * cos(th), GROUND_Y, r * sin(th)), Color(1, 1, 1, a)]


static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for v in [a, b, c]:
		st.set_color(v[1])
		st.add_vertex(v[0])


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
	##   (hookbomb_system.gd:740-742 那段血泪注释说的就是这个)
	m.render_priority = prio
	m.albedo_color = Color(1, 1, 1, 0)
	return m


# ══════════════════════════════════════════════════════════════════
#  §演出
# ══════════════════════════════════════════════════════════════════

## 建一发冲击波的节点(**还没挂进树**, 由 SynergyVfx._adopt 负责挂 + 记账)。
## 返回句柄 Dictionary; 后续每帧由 `advance()` 推进, 门禁则直接 `apply_at()` 到任意时刻。
##
## ⚠ 节点与参数在本函数返回时就是【u=0 的最终值】—— 门禁下一行就能判, 不等任何 tween。
func make_blast(pos2d: Vector2, col: Color, fired: int) -> Dictionary:
	if battle == null or not is_instance_valid(battle._world):
		return {}
	var rm: float = radius_m(fired)
	var dur: float = duration_s(fired)

	if _cache_shell == null:
		_cache_shell = _build_shell_mesh()
	if _cache_ring == null:
		_cache_ring = _build_ring_mesh()
	if _cache_dust == null:
		_cache_dust = _build_dust_mesh()

	var org: Vector3 = battle._world_pos(pos2d, 0.0)
	var shock := _node(_cache_shell, _mat(false, 9), org)
	var ring := _node(_cache_ring, _mat(true, 11), org)
	var dust := _node(_cache_dust, _mat(true, 10), org)

	var h := {
		"shock": shock, "ring": ring, "dust": dust,
		"col": col, "r_m": rm, "dur": dur, "fired": maxi(1, fired), "t": 0.0,
	}
	apply_at(h, 0.0)
	return h


## 本层节点的三个键 —— 建/推/收三处共用同一份名单, 免得加了第四个节点漏改一处。
const NODE_KEYS := ["shock", "ring", "dust"]


static func _node(mesh: ArrayMesh, mat: StandardMaterial3D, org: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	## ★用 material_override 不用 set_surface_override_material, 理由见 _build_shell_mesh 的注释
	mi.material_override = mat
	mi.position = org
	return mi


## ★把 u 时刻的形态写到真实节点上 —— **纯同步**, 门禁直接喂任意 u。
##   演出侧每帧调它、门禁侧也调它, 只有这一份实现 (判据 6: 数值断言不依赖 tween)。
func apply_at(h: Dictionary, u: float) -> void:
	if h.is_empty():
		return
	var s: Dictionary = shape_at(u)
	var col: Color = h["col"]
	var rm: float = float(h["r_m"])

	## 下限 1e-4: 半径 0 会让 Basis 退化, Godot 会刷 "scale is zero" 警告
	var rs: float = maxf(float(s["r_shock"]) * rm, 1e-4)
	var a: float = float(s["a_shock"])
	var shock = h["shock"]
	if is_instance_valid(shock):
		shock.scale = Vector3(rs, rs, rs)
		(shock.material_override as StandardMaterial3D).albedo_color = Color(
			col.r, col.g, col.b, col.a * a)
	var ring = h["ring"]
	if is_instance_valid(ring):
		## 贴地环与半球壳【同一个半径】—— 它就是这个半球与地面的交线, 不是另一个环。
		ring.scale = Vector3(rs, rs, rs)
		## 比空中壳亮 —— 马赫杆(见 MACH_BASE_A 那段)
		(ring.material_override as StandardMaterial3D).albedo_color = Color(
			col.r, col.g, col.b, minf(1.0, col.a * a * 1.35))

	var dust = h["dust"]
	if is_instance_valid(dust):
		var rd: float = maxf(float(s["r_dust"]) * rm, 1e-4)
		dust.scale = Vector3(rd, rd, rd)
		## ★负压相里把颜色往"冷掉的余烬"推 —— 高温气体被吸回来时是在降温。
		##   suction ∈ [0, 0.1353], 归一到 [0,1] 再当插值量。
		var k: float = clampf(float(s["suction"]) / 0.135335, 0.0, 1.0)
		var ember := Color(col.r * 0.55, col.g * 0.30, col.b * 0.18, col.a)
		var c2: Color = col.lerp(ember, k)
		(dust.material_override as StandardMaterial3D).albedo_color = Color(
			c2.r, c2.g, c2.b, c2.a * float(s["a_dust"]) * 0.85)


## 推进一帧。返回 false = 这一发放完了(调用方该 free 节点)。
func advance(h: Dictionary, delta: float) -> bool:
	if h.is_empty():
		return false
	var t: float = float(h["t"]) + maxf(delta, 0.0)
	h["t"] = t
	var dur: float = maxf(float(h["dur"]), 0.001)
	apply_at(h, t / dur)
	return t < dur
