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

## 飞行速度(码/秒)。★"缓慢的飞行": 龟的移速档位是 60~120(turtle_stats.ROLE_SPEC),
##   110 落在中上 —— 比慢龟快、比快龟慢, 读起来是"晃悠着飘", 不是导弹。
const DRONE_SPEED := 110.0
## 航向角速率上限(弧度/秒) ⇒ 最小转弯半径 = SPEED/TURN_RATE = 91.67 码
const DRONE_TURN_RATE := 1.2
## 巡航高度(米)
const FLY_H := 1.55

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
## 尾根/尾尖在本体局部坐标里的 x(米)。局部 +X = 前进方向 ⇒ 尾巴挂在 −X 侧
const TAIL_X0 := -0.34
const TAIL_X1 := -1.12

## 本体尺寸(米)。龟身高 TARGET_BODY_H = 2.0 ⇒ 这东西约龟的三分之一, 读作"小飞虫"
const BODY_L := 0.55
const BODY_H := 0.27
const BODY_W := 0.27
## 翅展(米·单侧)
const WING_SPAN := 0.72
const WING_CHORD := 0.34

## ★毒雾的**显示增益**(不是把物理揉圆): 渲染 alpha = FOG_DRAW_A × C(r,t)/C₀。
##   一个【常数】增益同时缩放浓度与阈值 ⇒ 等值线一条不动, "看得见的边界 == 打得到的边界"
##   仍然精确成立(门禁 ⑤d 验的正是这条)。加它的理由是实拍出来的:
##   16 团加性叠在一起会把尾迹烧成一片白, 反而看不出"一团一团铺开"的层次。
const FOG_DRAW_A := 0.45

## ★本体【不用加性】—— 实拍教训: 本体 + 双翅 + 尾巴四层加性叠在一处直接饱和成白团,
##   翅和尾完全看不出来(比"没做动画"还糟)。改成:
##     · 躯干 = 不透明 MIX 的深毒绿 ⇒ 有【剪影】, 能看出是个虫子
##     · 翅膀 = 半透明 MIX 的浅绿 ⇒ 昆虫翅本来就是透的, 扇动时能看见开合
##     · 尾巴 = 加性发光 ⇒ 它是毒雾的出口, 该亮
const COL_BODY_SOLID := Color(0.20, 0.52, 0.16, 1.0)
const COL_WING := Color(0.72, 1.00, 0.62, 0.42)
const COL_TAIL := Color(0.45, 1.00, 0.32, 1.0)

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


var battle

## 缓存网格: 毒雾盘与本体都是【单位尺度】的, 每一团只差 scale 与材质 ⇒ 整局各建一次。
## ★存实例上不用 `static var`: static 的话进程退出时还挂着 ArrayMesh,
##   Godot 会报 `ERROR: N resources still in use at exit`(shockwave_vfx 实测过)。
var _cache_fog: ArrayMesh = null
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
func make_fog(pos2d: Vector2):
	if battle == null or not is_instance_valid(battle._world):
		return null
	if _cache_fog == null:
		_cache_fog = _build_fog_mesh()
	var mi := MeshInstance3D.new()
	mi.mesh = _cache_fog
	mi.material_override = _mat(true, 8)
	mi.position = battle._world_pos(pos2d, 0.0)
	mi.set_meta(META_KEY, "venom_fog")
	battle._world.add_child(mi)
	apply_fog(mi, 0.0)
	return mi


## 把 t 时刻的形态写到真实节点上 —— **纯同步**, 门禁直接喂任意 t。
## 演出侧每帧调它、门禁侧也调它, 只有这一份实现。
func apply_fog(mi, t: float) -> void:
	if not is_instance_valid(mi):
		return
	## 世界尺度: 码 → 米
	var s: float = maxf(fog_sigma(t) * float(battle.WS), 1e-4)
	mi.scale = Vector3(s, 1.0, s)
	## ★渲染 alpha = 显示增益 × 归一浓度。常数增益不动等值线(见 FOG_DRAW_A 那段)。
	var a: float = FOG_DRAW_A * fog_peak(t)
	(mi.material_override as StandardMaterial3D).albedo_color = Color(
		COL_FOG.r, COL_FOG.g, COL_FOG.b, a)


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
	## 躯干: 不透明剪影(MIX) —— 加性会和翅/尾叠成白团, 见 COL_BODY_SOLID 那段
	var body := MeshInstance3D.new()
	body.mesh = _cache_body
	body.material_override = _mat(false, 6, false)
	(body.material_override as StandardMaterial3D).albedo_color = COL_BODY_SOLID
	body.scale = Vector3(BODY_L, BODY_H, BODY_W)
	body.name = "body"
	root.add_child(body)
	## 翅膀: 半透明(MIX) —— 昆虫翅是透的, 扇动时能看见开合
	var wing := MeshInstance3D.new()
	wing.mesh = ImmediateMesh.new()
	wing.material_override = _mat(false, 7, false)
	(wing.material_override as StandardMaterial3D).albedo_color = COL_WING
	wing.name = "wing"
	root.add_child(wing)
	## 尾巴: 加性发光 —— 它是毒雾的出口
	var flap := MeshInstance3D.new()
	flap.mesh = ImmediateMesh.new()
	flap.material_override = _mat(false, 8)
	(flap.material_override as StandardMaterial3D).albedo_color = COL_TAIL
	flap.name = "flap"
	root.add_child(flap)
	battle._world.add_child(root)
	apply_drone(root, Vector2.ZERO, 0.0, 0.0)
	return root


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


## 两只翅膀: 绕本体纵轴(+X)以行程角 φ(t) 摆动。左右**同相**(昆虫双翅同步)。
static func _emit_wings(im: ImmediateMesh, t: float) -> void:
	var phi: float = stroke(t)
	var cy: float = sin(phi) * WING_SPAN
	var cz: float = cos(phi) * WING_SPAN
	for sgn in [1.0, -1.0]:
		var root_f := Vector3(WING_CHORD * 0.5, 0.06, 0.05 * sgn)
		var root_b := Vector3(-WING_CHORD * 0.5, 0.06, 0.05 * sgn)
		var tip := Vector3(0.0, 0.06 + cy, sgn * cz)
		_emit_tri(im, root_f, root_b, tip, 0.95, 0.95, 0.20)


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
