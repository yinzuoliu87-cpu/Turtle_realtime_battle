extends RefCounted
class_name ManaBeamVfx
## mana_beam_vfx.gd — 068 深海气压罐【可转向法力射线】的演出层(2026-08-11)
##
## ══════════════════════════════════════════════════════════════════
##  这份文件的每个数字都是【逐帧量出来的】, 不是手调的
## ══════════════════════════════════════════════════════════════════
## 参考: LoL 圣光维克兹 R「生命形态解体射线」(SkinSpotlights, 60fps/1280x720)。
## 权威 wiki 只给引导时长/射程/宽度, **转向速率没有公开值** ⇒ 只能从视频量。
## 方案书: docs/plans/20260811-068可转向法力射线.md
##
## ★为什么不手调: memory [[fb-match-reference-by-measured-curve]] ——
##   手调缓动补不出真实曲线(余振二次峰这类细节只有表能给)。所以把参考 profile 成
##   **相对包络表**再驱动, 系数一个都不猜。
##
## ══════════════════════════════════════════════════════════════════
##  §A 时间包络 —— 我们旧版的形状是【反的】
## ══════════════════════════════════════════════════════════════════
## 实测(t=95.13~97.63s, 共 2.5 秒):
##   起手闪(2帧) → 蓄势 0.65s 低位 → 爬升 0.85s → 持续 0.9s
##   → **峰值出现在结束前最后一帧** → **一帧切断** → 余辉 0.5s
##
## 旧版 `beam_current = exp(-t/τ)` 是**开场即满、指数衰减** —— 完全反过来,
## 所以它读成"闪了一下", 而不是"越打越狠"。这比颜色和粗细都更致命。
##
## ⚠ 诚实标注: 原始测量数的是"金色像素总量", 里面**含命中爆点的贡献** ——
##   所以 0.76 处那个回落多半是那一发扫离了目标, 不是光束自身的性质。
##   下表取的是**趋势**, 回落压平了一些。
const ENV: Array = [
	# [归一时间, 相对强度]  —— 时间已按 2.5s → 3.0s 等比拉伸(归一后与拉伸无关)
	[0.000, 0.31], [0.020, 0.32], [0.040, 0.17], [0.080, 0.14],
	[0.140, 0.12], [0.200, 0.12], [0.260, 0.15], [0.320, 0.20],
	[0.380, 0.30], [0.440, 0.40], [0.500, 0.59], [0.560, 0.78],
	[0.600, 0.83], [0.680, 0.84], [0.760, 0.72], [0.840, 0.75],
	[0.900, 0.82], [0.940, 0.93], [0.960, 1.00], [0.980, 0.90],
	[1.000, 0.82],
]

## ══════════════════════════════════════════════════════════════════
##  §B 横截面 —— 芯晕分离(差分抠出光束后逐像素量的)
## ══════════════════════════════════════════════════════════════════
## 差分底已验证: 两张开火前的帧互差仅 46 个残差像素 ⇒ 相机静止, 底选对了。
## 从外到内是**平滑斜坡**: 外缘浓琥珀金(饱和度 0.50~0.65) → 纯白芯(饱和度 <0.10)。
## 旧版整条一个色 `Color(0.62,0.80,1.0)`、饱和度 0.38、alpha 硬分三带(0/1/0)
## ⇒ 没有芯晕分化 ⇒ 一坨均匀淡蓝, 读成雾。
##
## ★颜色推深 + 亮度靠 alpha 给, **不靠把颜色洗白** ——
##   v0.19.90「白球家族」那轮的结论(四件同一个病)。
## ★存的是【绝对目标色】(0~1 即 0~255), 直接来自差分实测的像素值 ——
##   不是"颜色 × 亮度"两栏, 那样会让"目标到底是多少"含糊。
##   括号里是实测原始像素。
const XSEC: Array = [
	# [归一半径,  r,    g,    b  ]
	[0.00, 1.00, 1.00, 1.00],   # 白芯   RGB(255,255,255)
	[0.20, 1.00, 1.00, 0.75],   #        RGB(255,255,191)
	[0.45, 1.00, 0.85, 0.46],   #        RGB(255,216,118)
	[0.75, 0.87, 0.70, 0.38],   #        RGB(222,178, 96)
	[1.00, 0.66, 0.55, 0.30],   # 外缘   RGB(169,141, 77)
]

## 五层壳的半径(外 → 内)。取在实测剖面的采样点上, 差分才不引入插值误差。
const SHELL_U: Array = [1.00, 0.75, 0.45, 0.20, 0.06]

## 每层壳的径向分段(绕轴一圈)
const RINGS := 14
## 沿程分段。实测**沿程峰值大致持平**(各站位都顶到 255) ⇒ 不做强衰减,
## 只在射程末端收束一点, 所以分段不用多。
const SEGS := 10

## 转向速率(度/秒)。实测: 屏幕角上限 72°/s(束身完整那一段),
## 过地面压缩 tan(θ屏)=k·tan(θ世界), k≈0.55 ⇒ 世界角 ≈110~120°/s。
## ★k 是估计值不是实测(方案书 §五 未决点 2) —— 但**角速度无量纲**, 不随场地尺度变,
##   所以这个数可以 1:1 搬过来, 不需要知道 LoL 的码与我们的码怎么换算。
const TURN_DPS := 110.0

## 命中爆点的淡入/淡出(秒)。★用户 2026-08-11:「命中特效不能是突然出现突然消失的」。
## ★淡入比淡出短: 被照到要"立刻有反应", 离开可以留一点余韵。
## 实测(束切断后爆点 4 帧内塌掉)比旧值快得多 ⇒ 收紧到 0.06/0.10, 仍保 out>in。
const HIT_IN := 0.06
const HIT_OUT := 0.10
## 枪口星芒尺寸(码)
const MUZZLE_R := 62.0

## ══════════════════════════════════════════════════════════════════
##  §B2 爆点结构表 —— 2026-08-11 逐帧量出(r_full 持续段 222~240 + 爆发段 271~276)
## ══════════════════════════════════════════════════════════════════
## 换算锚: 参考束全宽 104px = 我们 BEAM_HALF_W×2 = 116码 ⇒ 1px ≈ 1.115码。
## ★三个反直觉的实测结论(不许"顺手改回直觉"):
##   ① 持续期【没有白芯】: 黄像素 RGB(207,144,65)→(173,111,84), 白占比 <4%。
##      白色只在【末端爆发】出现(实心核 ~10px + 白刺带 44~72px)。
##   ② 刺的角宽是【双峰】: 细针 4~12° 与宽瓣 35~55° 并存(p25=6° p50=22° p75=47°)。
##   ③ 刺形每 ~2 帧重掷一次(相邻帧 33ms 相关只剩 0.37) —— 不是一个定形星芒在转。
const HIT_SPIKE_N := 15                                    # 整圈外推中位(逐帧 9~20)
const HIT_LEN_Q: Array = [27.0, 40.0, 64.0, 77.0, 90.0]   # 刺长分位表(码) q=0/.25/.5/.75/1
const HIT_NEEDLE_FRAC := 0.6                               # 细针占比; 其余为宽瓣
const HIT_NEEDLE_DEG := 8.0                                # 细针全角宽(°)
const HIT_LOBE_DEG := 42.0                                 # 宽瓣全角宽(°)
const HIT_GLOW_R0 := 33.0        # 光晕亮度平台半径(码) — mean dL 在 r≤30px 持平
const HIT_GLOW_SCALE := 14.5     # 平台外指数衰减尺度(码) (≈13px)
const HIT_GLOW_RMAX := 90.0      # 光晕见底半径(码) (≈80px)
const HIT_RESHUFFLE := 0.04      # 刺形重掷周期(秒)
const HIT_PATTERNS := 3          # 预建几套刺形轮换(建网格不进热路径)
const HIT_COL_IN := Color(0.81, 0.56, 0.25)    # 根部 RGB(207,144,65) sat 0.69
const HIT_COL_OUT := Color(0.68, 0.44, 0.33)   # 端部 RGB(173,111,84) sat 0.51
## 末端爆发(束结束的最后一瞬, 实测 0.1s / 6 帧):
const BURST_SEC := 0.10
const BURST_LEN_MULT := 2.2      # 刺长倍率(204px / 90px)
const BURST_CORE_R := 12.0       # 实心白核半径(码) (≈10px)
const BURST_RING_R0 := 49.0      # 白刺带内半径(码) (44px)
const BURST_RING_R1 := 80.0      # 白刺带外半径(码) (72px)
const BURST_OUT := 0.07          # 爆发后的塌收(实测 4 帧)

## ══════════════════════════════════════════════════════════════════
##  §B3 束身细丝 —— 横截面亮脊实测 p50 = 4 条(2~5 波动), 位置逐帧重排
## ══════════════════════════════════════════════════════════════════
## ★离束火花实测为【零】(perp>65px 无独立亮斑) —— 亮点全在束辉光内部,
##   所以不做飞散粒子, 只做束内细丝。
const FIL_N := 4                 # 每束细丝股数
const FIL_R := 0.085             # 细丝半径(单位半径 = 束半宽的倍数)
const FIL_SWAP := 0.08           # 细丝排布轮换周期(秒)
const FIL_COL := Color(1.0, 0.92, 0.70)   # 近白琥珀(比外晕亮一挡)

var battle = null
var _live: Array = []


func _init(b) -> void:
	battle = b


# ══════════════════════════════════════════════════════════════════
#  §C 包络求值
# ══════════════════════════════════════════════════════════════════

## 瞬时强度 i(s), s∈[0,1] 为归一进度。线性插值实测表。
static func env(s: float) -> float:
	var t: float = clampf(s, 0.0, 1.0)
	for i in range(ENV.size() - 1):
		var a: Array = ENV[i]
		var b: Array = ENV[i + 1]
		if t <= float(b[0]):
			var span: float = maxf(float(b[0]) - float(a[0]), 1e-6)
			var k: float = (t - float(a[0])) / span
			return lerpf(float(a[1]), float(b[1]), clampf(k, 0.0, 1.0))
	return float((ENV[ENV.size() - 1] as Array)[1])


## 累计比例 Q(s) = ∫i / ∫总。★与 `env` 是【导数关系】——
## 画面最亮那一瞬也正是打得最狠那一瞬, 不是"画面按 A 曲线、伤害按 B 曲线"两张皮。
## Q(0)=0 与 Q(1)=1 都是精确的 ⇒ "3 秒里一共打出去的正好是设计总量"。
static func env_frac(s: float) -> float:
	var t: float = clampf(s, 0.0, 1.0)
	var acc: float = 0.0
	var tot: float = 0.0
	var hit: float = 0.0
	for i in range(ENV.size() - 1):
		var a: Array = ENV[i]
		var b: Array = ENV[i + 1]
		var t0: float = float(a[0])
		var t1: float = float(b[0])
		var seg: float = (float(a[1]) + float(b[1])) * 0.5 * (t1 - t0)   # 梯形
		tot += seg
		if t >= t1:
			acc += seg
		elif t > t0:
			var k: float = (t - t0) / maxf(t1 - t0, 1e-6)
			var mid: float = lerpf(float(a[1]), float(b[1]), k)
			acc += (float(a[1]) + mid) * 0.5 * (t - t0)
			hit = 1.0
	if tot <= 0.0:
		return 0.0
	return clampf(acc / tot, 0.0, 1.0)


## 横截面在归一半径 u 处的【目标颜色】。返回 [r, g, b, 亮度],
## 亮度取三分量均值(单调, 给门禁判"从外到内越来越亮"用)。
static func xsec_at(u: float) -> Array:
	var t: float = clampf(u, 0.0, 1.0)
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var done := false
	for i in range(XSEC.size() - 1):
		var p: Array = XSEC[i]
		var q: Array = XSEC[i + 1]
		if not done and t <= float(q[0]):
			var span: float = maxf(float(q[0]) - float(p[0]), 1e-6)
			var k: float = clampf((t - float(p[0])) / span, 0.0, 1.0)
			r = lerpf(float(p[1]), float(q[1]), k)
			g = lerpf(float(p[2]), float(q[2]), k)
			b = lerpf(float(p[3]), float(q[3]), k)
			done = true
	if not done:
		var z: Array = XSEC[XSEC.size() - 1]
		r = float(z[1]); g = float(z[2]); b = float(z[3])
	return [r, g, b, (r + g + b) / 3.0]


## 第 k 层壳应当【叠加】的增量 = T(u_k) − T(u_{k−1})。
##
## ★★这是这份文件最关键的一段。加色混合下, 屏幕上的颜色是**各层之和**,
##   所以要让【和】等于实测剖面 —— 而不是让每一层都等于它。
##   第一版每层都带完整目标色 ⇒ 高分量先饱和、低分量继续累加 ⇒ R 与 G 被拉平
##   ⇒ 实拍量到 R/G=1.02(黄白), 而参考是 1.25(琥珀金)。
##   与「白球家族」同族: 加色叠加会洗掉身份色, 那次表现为爆白, 这次表现为褪色。
static func shell_add(k: int) -> Array:
	var t: Array = xsec_at(float(SHELL_U[k]))
	var p: Array = [0.0, 0.0, 0.0] if k == 0 else xsec_at(float(SHELL_U[k - 1]))
	return [maxf(float(t[0]) - float(p[0]), 0.0),
		maxf(float(t[1]) - float(p[1]), 0.0),
		maxf(float(t[2]) - float(p[2]), 0.0)]


## 白芯占整束宽度的比例 —— 定义为"饱和度 < 0.20 的那一段"。
## 门禁拿它对实测区间, 免得以后有人把芯改宽到看不出芯晕分化。
static func core_frac() -> float:
	var last: float = 0.0
	var u: float = 0.0
	while u <= 1.0001:
		var c: Array = xsec_at(u)
		var mx: float = maxf(maxf(float(c[0]), float(c[1])), float(c[2]))
		var mn: float = minf(minf(float(c[0]), float(c[1])), float(c[2]))
		var sat: float = 0.0 if mx <= 0.0 else (mx - mn) / mx
		if sat < 0.20:
			last = u
		u += 0.005
	return last


# ══════════════════════════════════════════════════════════════════
#  §D 几何 —— 真 3D 同轴套壳(不是贴图, 不是贴地四边形)
# ══════════════════════════════════════════════════════════════════

static func _mat(prio: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# ★只画正面。实心闭合曲面 + 加色 + 双面 ⇒ 正反各叠一层 ⇒ 中心必然加爆成白,
	#   这就是 v0.19.90「白球家族」四件的共同根因。
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.no_depth_test = true
	m.render_priority = prio
	m.albedo_color = Color(1, 1, 1, 0)
	return m


## 一层壳: 沿 +X 从 0 到 1 的圆管, 半径 = u(归一半径)。
## 顶点色 = 该半径处的实测颜色 × 亮度; alpha 额外乘一个"边缘更透"的权重,
## 这样 5 层叠起来才是**平滑的径向渐变**而不是 5 个同心圆环。
static func _shell_mesh_k(k: int) -> ArrayMesh:
	var u: float = float(SHELL_U[k])
	var d: Array = shell_add(k)
	# 颜色 = 增量方向, alpha = 增量幅值 ⇒ 叠加之和精确等于实测剖面。
	# ★亮度靠 alpha 给, 颜色只管色相 —— 不把颜色洗白(白球家族那轮的结论)。
	# ★★色相校准(2026-08-11, 实拍闭环量出来的, 不是手调):
	#   第一版渲染出来外缘 R/G=1.08, 而实测参考是 1.20 —— 绿分量偏高 ⇒ 读成黄而不是琥珀。
	#   原因在渲染管线(顶点色 sRGB→线性、乘 alpha、加色累加、再编回 sRGB)会把通道比压平,
	#   光在 XSEC 里写对目标色不够。
	#   ⇒ 按实拍缺口对 G/B 做一次校准: 需要 G×0.90、B×0.77 才能让【屏幕上量到的】
	#     通道比回到实测参考。目标仍是实测剖面, 改的只是编码。
	var g_cal := 0.90
	var b_cal := 0.77
	d[1] = float(d[1]) * g_cal
	d[2] = float(d[2]) * b_cal
	var mx: float = maxf(maxf(float(d[0]), float(d[1])), float(d[2]))
	if mx <= 1e-6:
		mx = 1e-6
	var col := Color(float(d[0]) / mx, float(d[1]) / mx, float(d[2]) / mx)
	var a: float = clampf(mx, 0.0, 1.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in range(SEGS):
		var x0: float = float(s) / float(SEGS)
		var x1: float = float(s + 1) / float(SEGS)
		# 射程末端轻微收束(实测沿程大致持平, 只在最后一小段收) + 起点也收一点
		var k0: float = _taper(x0)
		var k1: float = _taper(x1)
		for r in range(RINGS):
			var a0: float = TAU * float(r) / float(RINGS)
			var a1: float = TAU * float(r + 1) / float(RINGS)
			var p00 := Vector3(x0, sin(a0) * u * k0, cos(a0) * u * k0)
			var p10 := Vector3(x1, sin(a0) * u * k1, cos(a0) * u * k1)
			var p11 := Vector3(x1, sin(a1) * u * k1, cos(a1) * u * k1)
			var p01 := Vector3(x0, sin(a1) * u * k0, cos(a1) * u * k0)
			var c00 := Color(col.r, col.g, col.b, a * k0)
			var c10 := Color(col.r, col.g, col.b, a * k1)
			_quad(st, p00, p10, p11, p01, c00, c10, c10, c00)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


static func _taper(x: float) -> float:
	# 起点 0.55 → 0.12 处满 → 0.88 起收 → 末端 0.35
	if x < 0.12:
		return lerpf(0.55, 1.0, x / 0.12)
	if x > 0.88:
		return lerpf(1.0, 0.35, (x - 0.88) / 0.12)
	return 1.0


static func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		c0: Color, c1: Color, c2: Color, c3: Color) -> void:
	st.set_color(c0); st.add_vertex(p0)
	st.set_color(c1); st.add_vertex(p1)
	st.set_color(c2); st.add_vertex(p2)
	st.set_color(c0); st.add_vertex(p0)
	st.set_color(c2); st.add_vertex(p2)
	st.set_color(c3); st.add_vertex(p3)


## 星芒(枪口与命中共用): 贴地放射, n 枝, 长短交替。
static func _star_mesh(n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var core := Color(1.0, 1.0, 1.0, 0.95)
	var tip := Color(1.0, 0.80, 0.38, 0.0)
	for i in range(n):
		var a: float = TAU * float(i) / float(n)
		var ln: float = 1.0 if (i % 2 == 0) else 0.58
		var w: float = 0.13
		var d := Vector3(cos(a), 0.0, sin(a))
		var s := Vector3(-sin(a), 0.0, cos(a)) * w
		st.set_color(core); st.add_vertex(-s)
		st.set_color(tip);  st.add_vertex(d * ln)
		st.set_color(core); st.add_vertex(s)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


## 确定性伪随机(哈希, 无 RNG 状态) —— 刺形/细丝排布要"看着随机"但不许碰全局随机流
## (rng_discipline 门禁: 裸随机冻结)。同一 seed 永远同一套形, 重掷靠换 seed。
static func _hash(i: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + 78.233) * 43758.5453, 1.0)


## 刺长: 按实测分位表采样(q∈[0,1] → 码)。表是 [min,p25,p50,p75,max], 线性内插。
static func spike_len(q: float) -> float:
	var t: float = clampf(q, 0.0, 1.0) * 4.0
	var i: int = clampi(int(t), 0, 3)
	return lerpf(float(HIT_LEN_Q[i]), float(HIT_LEN_Q[i + 1]), t - float(i))


## 光晕亮度剖面(归一): r≤R0 平台 1.0, 之后 exp(-(r-R0)/SCALE), RMAX 处清零。
static func glow_at(r: float) -> float:
	if r <= HIT_GLOW_R0:
		return 1.0
	if r >= HIT_GLOW_RMAX:
		return 0.0
	return exp(-(r - HIT_GLOW_R0) / HIT_GLOW_SCALE)


## ★爆点刺束 —— 真 3D: 方向撒满整个球面(含朝镜头), 每根刺是一对十字鳍。
## 参考: 几十根长短粗细各异的尖刺炸开成球状、立起来与角色相当 —— 不是贴地星芒。
## seed 换一套刺形(数量/方向/长短/宽窄全部由哈希驱动, 同 seed 恒定)。
## 单位: 网格半径 1.0 = HIT_LEN_Q 的最大值(码), 运行时按码缩放。
static func _burst_mesh(seed: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lmax: float = float(HIT_LEN_Q[4])
	for i in range(HIT_SPIKE_N):
		var b: int = seed * 97 + i * 13
		# 球面均匀方向: y = 2h-1, 方位角 2πh'
		var cy: float = 2.0 * _hash(b) - 1.0
		var az: float = TAU * _hash(b + 1)
		var rr: float = sqrt(maxf(1.0 - cy * cy, 0.0))
		var dir := Vector3(rr * cos(az), cy, rr * sin(az))
		var ln: float = spike_len(_hash(b + 2)) / lmax
		var needle: bool = _hash(b + 3) < HIT_NEEDLE_FRAC
		var deg: float = HIT_NEEDLE_DEG if needle else HIT_LOBE_DEG
		# 半高角宽 → 半长处的半宽
		var hw: float = ln * 0.5 * tan(deg_to_rad(deg * 0.5))
		var side := dir.cross(Vector3.UP)
		if side.length() < 0.1:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized() * hw
		var side2 := dir.cross(side).normalized() * hw
		var c0 := Color(HIT_COL_IN.r, HIT_COL_IN.g, HIT_COL_IN.b, 0.95)
		var c1 := Color(HIT_COL_OUT.r, HIT_COL_OUT.g, HIT_COL_OUT.b, 0.0)
		for s in [side, side2]:      # 十字鳍: 两片互垂, 任何视角都有截面
			st.set_color(c0); st.add_vertex(-s)
			st.set_color(c1); st.add_vertex(dir * ln)
			st.set_color(c0); st.add_vertex(s)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


## 末端爆发的白刺带: 白色碎片刺, 根部悬在 RING_R0、尖到 RING_R1(实测白色在 44~72px 成带)。
static func _burst_ring_mesh(seed: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = HIT_SPIKE_N
	for i in range(n):
		var b: int = seed * 131 + i * 17
		var cy: float = 2.0 * _hash(b) - 1.0
		var az: float = TAU * _hash(b + 1)
		var rr: float = sqrt(maxf(1.0 - cy * cy, 0.0))
		var dir := Vector3(rr * cos(az), cy, rr * sin(az))
		var r0: float = BURST_RING_R0 / BURST_RING_R1
		var hw: float = 0.055 + 0.05 * _hash(b + 2)
		var side := dir.cross(Vector3.UP)
		if side.length() < 0.1:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized() * hw
		var c0 := Color(1.0, 1.0, 1.0, 0.9)
		var c1 := Color(1.0, 0.97, 0.88, 0.0)
		for s in [side, dir.cross(side).normalized() * hw]:
			st.set_color(c0); st.add_vertex(dir * r0 - s)
			st.set_color(c1); st.add_vertex(dir)
			st.set_color(c0); st.add_vertex(dir * r0 + s)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


# ══════════════════════════════════════════════════════════════════
#  §E 运行时
# ══════════════════════════════════════════════════════════════════

func _alive_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


func _node(mesh: Mesh, mat: StandardMaterial3D, org: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = org
	if _alive_world():
		battle._world.add_child(mi)
	return mi


## 束身细丝: FIL_N 股, 各有垂向偏移与微角差(两端偏移不同 ⇒ 与轴不严格平行),
## 每股一对十字鳍薄带。seed 换一套排布(实测: 脊的位置沿束变化、逐帧重排)。
## 单位空间与壳一致: x∈[0,1], 半径 1 = 束半宽。
static func _fil_mesh(seed: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(FIL_N):
		var b: int = seed * 61 + i * 29
		var a0: float = TAU * _hash(b)
		var r0: float = 0.15 + 0.45 * _hash(b + 1)
		var y0: float = sin(a0) * r0
		var z0: float = cos(a0) * r0
		var y1: float = clampf(y0 + 0.55 * (_hash(b + 2) - 0.5), -0.6, 0.6)
		var z1: float = clampf(z0 + 0.55 * (_hash(b + 3) - 0.5), -0.6, 0.6)
		var p0 := Vector3(0.04, y0, z0)
		var p1 := Vector3(0.97, y1, z1)
		var c0 := Color(FIL_COL.r, FIL_COL.g, FIL_COL.b, 0.0)
		var cm := Color(FIL_COL.r, FIL_COL.g, FIL_COL.b, 0.42 + 0.2 * _hash(b + 4))
		var mid: Vector3 = (p0 + p1) * 0.5
		for s in [Vector3(0.0, FIL_R, 0.0), Vector3(0.0, 0.0, FIL_R)]:
			st.set_color(c0); st.add_vertex(p0 - s)
			st.set_color(cm); st.add_vertex(mid + s)
			st.set_color(c0); st.add_vertex(p1 - s)
			st.set_color(c0); st.add_vertex(p0 + s)
			st.set_color(cm); st.add_vertex(mid - s)
			st.set_color(c0); st.add_vertex(p1 + s)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


## 开火。返回句柄(存进 eq_state)。`ang` 是世界平面上的朝向弧度。
func fire(origin: Vector2, ang: float, length: float, half_w: float) -> Dictionary:
	if not _alive_world():
		return {}
	var ws: float = float(battle.WS)
	var shells: Array = []
	for i in range(SHELL_U.size()):
		# 从外到内建, render_priority 递增 ⇒ 芯画在最上面
		var nd := _node(_shell_mesh_k(i), _mat(30 + i), battle._world_pos(origin, 0.0))
		nd.scale = Vector3(length * ws, half_w * ws, half_w * ws)
		shells.append(nd)
	# 细丝: 两套排布轮换(换 mesh 不换节点 ⇒ 热路径零分配)。节点放进 shells,
	# aim/set_progress/stop/node_count 就全部顺带管到了。
	var fil_meshes: Array = [_fil_mesh(1), _fil_mesh(2)]
	var fil := _node(fil_meshes[0], _mat(35), battle._world_pos(origin, 0.0))
	fil.scale = Vector3(length * ws, half_w * ws, half_w * ws)
	shells.append(fil)
	var mz := _node(_star_mesh(9), _mat(36), battle._world_pos(origin, 0.0))
	mz.scale = Vector3(MUZZLE_R * ws, 1.0, MUZZLE_R * ws)
	var h: Dictionary = {
		"shells": shells, "muzzle": mz, "org": origin, "ang": ang,
		"len": length, "hw": half_w, "s": 0.0, "marks": [],
		"fil_meshes": fil_meshes, "fil_node": fil, "t_acc": 0.0,
		# 爆点刺形: 预建 HIT_PATTERNS 套轮换(重掷=换 mesh, 不是每 40ms 建网格)
		"hit_meshes": [], "ring_mesh": null,
	}
	for i in range(HIT_PATTERNS):
		(h["hit_meshes"] as Array).append(_burst_mesh(i + 1))
	h["ring_mesh"] = _burst_ring_mesh(7)
	aim(h, ang)
	set_progress(h, 0.0)
	_live.append(h)
	return h


## 转向: 只转节点, **不重建网格** ⇒ 热路径零分配。
func aim(h: Dictionary, ang: float) -> void:
	if h.is_empty():
		return
	h["ang"] = ang
	for nd in h.get("shells", []):
		if is_instance_valid(nd):
			nd.rotation = Vector3(0.0, -ang, 0.0)


## 按归一进度更新亮度/粗细。
func set_progress(h: Dictionary, s: float) -> void:
	if h.is_empty():
		return
	h["s"] = s
	var i: float = env(s)
	var ws: float = float(battle.WS) if battle != null else 1.0
	# 粗细也跟着涨(实测: 爬升期光束在变粗), 但幅度小于亮度
	var w: float = float(h.get("hw", 58.0)) * ws * (0.62 + 0.38 * i)
	for k in range(h.get("shells", []).size()):
		var nd = h["shells"][k]
		if not is_instance_valid(nd):
			continue
		nd.scale = Vector3(float(h.get("len", 2000.0)) * ws, w, w)
		(nd.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, i)
	var mz = h.get("muzzle", null)
	if is_instance_valid(mz):
		mz.scale = Vector3(MUZZLE_R * ws * (0.7 + 0.5 * i), 1.0, MUZZLE_R * ws * (0.7 + 0.5 * i))
		(mz.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, i)
		mz.rotation.y = float(h.get("ang", 0.0)) * 0.35     # 缓慢反向自转, 免得像贴纸
	# 细丝排布轮换(换 mesh 不建节点): 实测脊位逐帧重排, 周期 FIL_SWAP
	var fn = h.get("fil_node", null)
	if is_instance_valid(fn):
		var fm: Array = h.get("fil_meshes", [])
		if fm.size() >= 2:
			var idx: int = int(float(h.get("t_acc", 0.0)) / FIL_SWAP) % fm.size()
			if fn.mesh != fm[idx]:
				fn.mesh = fm[idx]


## 每帧告知"现在照到了谁" —— 命中爆点按这个增删, 并且**淡入淡出**。
## ★用户 2026-08-11:「命中特效不能是突然出现突然消失的」。
## ★爆点亮度乘束包络(实测: 爆点能量跟束包络同曲线起伏) —— 一条曲线, 不是两张皮。
func set_hits(h: Dictionary, lit: Array, delta: float) -> void:
	if h.is_empty() or not _alive_world():
		return
	h["t_acc"] = float(h.get("t_acc", 0.0)) + maxf(delta, 0.0)
	var envk: float = 0.35 + 0.65 * env(float(h.get("s", 0.0)))
	var marks: Array = h.get("marks", [])
	# ① 已有的: 还在照 → 淡入; 不照了 → 淡出
	var keep: Array = []
	for m in marks:
		var still := false
		for u in lit:
			if is_same(m.get("u", null), u):       # ★单位字典比较必须 is_same(§3.2)
				still = true
				break
		m["on"] = still
		m["a"] = clampf(float(m.get("a", 0.0)) + (delta / HIT_IN if still else -delta / HIT_OUT), 0.0, 1.0)
		if float(m["a"]) <= 0.0 and not still:
			_free_mark(m)
			continue
		_apply_mark(m, h, envk, delta)
		keep.append(m)
	# ② 新照到的: 建一个(alpha 从 0 起, 所以是淡入不是突现)
	for u in lit:
		var found := false
		for m in keep:
			if is_same(m.get("u", null), u):
				found = true
				break
		if found:
			continue
		keep.append(_make_mark(u, h, envk))
	h["marks"] = keep


## 爆点中心在【身体中段】(高度 1.1) —— 参考爆点包住角色, 不是贴地(立起来与角色相当)。
const HIT_H := 1.1
## 光晕三层壳: 半径与基础 alpha 按实测剖面配(平台 33码 → 指数落到 90码见底)。
## 加色叠加下三层从内到外的透视叠加近似平台+衰减 —— 近似, 没做实拍闭环(诚实标注)。
const GLOW_SHELLS: Array = [[33.0, 0.14], [58.0, 0.06], [90.0, 0.028]]


func _make_mark(u: Dictionary, h: Dictionary, envk: float) -> Dictionary:
	var ws: float = float(battle.WS)
	var p: Vector3 = battle._world_pos(u.get("pos", Vector2.ZERO), HIT_H)
	var meshes: Array = h.get("hit_meshes", [])
	var star := _node(meshes[0] if meshes.size() > 0 else _burst_mesh(1), _mat(38), p)
	var glows: Array = []
	for g in GLOW_SHELLS:
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 18
		sm.rings = 9
		var mt := _mat(37)
		mt.albedo_color = Color(HIT_COL_IN.r, HIT_COL_IN.g, HIT_COL_IN.b, 0.0)
		var nd := _node(sm, mt, p)
		nd.scale = Vector3.ONE * float((g as Array)[0]) * ws
		glows.append(nd)
	var m: Dictionary = {"u": u, "star": star, "glows": glows, "core": null, "ring": null,
		"a": 0.0, "on": true, "spin": 0.0, "ws": ws, "resh": 0.0, "pi": 0, "burst": -1.0}
	_apply_mark(m, h, envk, 0.0)
	return m


func _apply_mark(m: Dictionary, h: Dictionary, envk: float, delta: float) -> void:
	var u = m.get("u", null)
	if not (u is Dictionary):
		return
	var ws: float = float(m.get("ws", 1.0))
	var a: float = float(m.get("a", 0.0))
	# ★缓入缓出曲线(smoothstep), 线性 alpha 会读成"闪一下"
	var e: float = a * a * (3.0 - 2.0 * a)
	m["spin"] = float(m.get("spin", 0.0)) + 0.9 * delta
	var p: Vector3 = battle._world_pos(u.get("pos", Vector2.ZERO), HIT_H)
	# 刺形重掷: 每 HIT_RESHUFFLE 秒换一套预建刺形 + 换一个哈希朝向(不重建网格)
	m["resh"] = float(m.get("resh", 0.0)) + delta
	if float(m["resh"]) >= HIT_RESHUFFLE:
		m["resh"] = 0.0
		m["pi"] = (int(m.get("pi", 0)) + 1) % HIT_PATTERNS
		var meshes: Array = h.get("hit_meshes", [])
		var star0 = m.get("star", null)
		if is_instance_valid(star0) and meshes.size() > int(m["pi"]):
			star0.mesh = meshes[int(m["pi"])]
	# 末端爆发的时间推进(burst>=0 才生效)
	var bt: float = float(m.get("burst", -1.0))
	var blen := 1.0
	var bfade := 1.0
	if bt >= 0.0:
		bt += delta
		m["burst"] = bt
		blen = lerpf(1.0, BURST_LEN_MULT, clampf(bt / BURST_SEC, 0.0, 1.0))
		if bt > BURST_SEC:
			bfade = clampf(1.0 - (bt - BURST_SEC) / BURST_OUT, 0.0, 1.0)
	var lmax: float = float(HIT_LEN_Q[4])
	var star = m.get("star", null)
	if is_instance_valid(star):
		star.position = p
		star.scale = Vector3.ONE * lmax * ws * blen * (0.7 + 0.3 * e)
		star.rotation.y = float(m["spin"]) + float(m.get("pi", 0)) * 2.4
		(star.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, e * envk * bfade)
	var gi := 0
	for nd in m.get("glows", []):
		if is_instance_valid(nd):
			nd.position = p
			var ga: float = float((GLOW_SHELLS[gi] as Array)[1])
			(nd.material_override as StandardMaterial3D).albedo_color = Color(
				HIT_COL_IN.r, HIT_COL_IN.g, HIT_COL_IN.b, ga * e * envk * bfade * blen)
		gi += 1
	# 爆发期的白核与白刺带(只在 finale 里建)
	var bin_a: float = clampf(bt / (BURST_SEC * 0.5), 0.0, 1.0) if bt >= 0.0 else 0.0
	var core = m.get("core", null)
	if is_instance_valid(core):
		core.position = p
		(core.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, 0.9 * bin_a * bfade)
	var ring = m.get("ring", null)
	if is_instance_valid(ring):
		ring.position = p
		# ★白刺带【不乘 blen】: 实测白色固定在 49~80 码成带, 只有琥珀刺才拉长 ×2.2
		ring.scale = Vector3.ONE * BURST_RING_R1 * ws
		ring.rotation.y = float(m["spin"]) * 0.5
		(ring.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, bin_a * bfade)


func _free_mark(m: Dictionary) -> void:
	for key in ["star", "core", "ring"]:
		var nd = m.get(key, null)
		if is_instance_valid(nd):
			nd.queue_free()
		m[key] = null
	for nd in m.get("glows", []):
		if is_instance_valid(nd):
			nd.queue_free()
	m["glows"] = []


## ★束自然结束: 束体立即撤(包络已把"一帧切断"演完), 但**正在照着的爆点转入末端爆发**
## (实测: 最后 0.1s 刺长 ×2.2 + 实心白核 + 白刺带, 然后 4 帧塌收) —— 之后由 advance 自清。
func finale(h: Dictionary) -> void:
	if h.is_empty():
		return
	for nd in h.get("shells", []):
		if is_instance_valid(nd):
			nd.queue_free()
	h["shells"] = []
	h["fil_node"] = null
	var mz = h.get("muzzle", null)
	if is_instance_valid(mz):
		mz.queue_free()
	h["muzzle"] = null
	var ring_mesh = h.get("ring_mesh", null)
	var keep: Array = []
	for m in h.get("marks", []):
		if not bool(m.get("on", false)) or float(m.get("a", 0.0)) <= 0.0:
			_free_mark(m)          # 没在照的余韵 mark 直接收掉, 不给它爆发
			continue
		m["burst"] = 0.0
		var u = m.get("u", null)
		if u is Dictionary and _alive_world():
			var ws: float = float(m.get("ws", 1.0))
			var p: Vector3 = battle._world_pos((u as Dictionary).get("pos", Vector2.ZERO), HIT_H)
			var sm := SphereMesh.new()
			sm.radius = 1.0
			sm.height = 2.0
			sm.radial_segments = 16
			sm.rings = 8
			var cn := _node(sm, _mat(39), p)
			cn.scale = Vector3.ONE * BURST_CORE_R * ws
			m["core"] = cn
			if ring_mesh != null:
				m["ring"] = _node(ring_mesh, _mat(39), p)
		keep.append(m)
	h["marks"] = keep
	if keep.is_empty():
		_drop(h)


## 每帧推进(束结束后的爆发/塌收没有别的驱动源)。多携带者会各调一次 ⇒ 帧去重。
var _adv_fr: int = -1
func advance(delta: float) -> void:
	var fr: int = Engine.get_process_frames()
	if fr == _adv_fr:
		return
	_adv_fr = fr
	for h in _live.duplicate():
		if not (h.get("shells", []) as Array).is_empty():
			continue                      # 束还活着, 由 set_hits 驱动
		var keep: Array = []
		for m in h.get("marks", []):
			var bt: float = float(m.get("burst", -1.0))
			if bt >= 0.0 and bt > BURST_SEC + BURST_OUT:
				_free_mark(m)
				continue
			_apply_mark(m, h, 1.0, delta)
			keep.append(m)
		h["marks"] = keep
		if keep.is_empty():
			_drop(h)


func _drop(h: Dictionary) -> void:
	var keep: Array = []
	for x in _live:
		if not is_same(x, h):
			keep.append(x)
	_live = keep


## 收工: 射线本体与所有命中爆点一起清掉。
## ★换路/战斗结束必须调 —— 068 的头顶充能条就是死在"建了没人清"上(v0.19.93 拆掉的那条)。
func stop(h: Dictionary) -> void:
	if h.is_empty():
		return
	for nd in h.get("shells", []):
		if is_instance_valid(nd):
			nd.queue_free()
	h["shells"] = []
	h["fil_node"] = null
	var mz = h.get("muzzle", null)
	if is_instance_valid(mz):
		mz.queue_free()
	h["muzzle"] = null
	for m in h.get("marks", []):
		_free_mark(m)
	h["marks"] = []
	_drop(h)


func clear_all() -> void:
	for h in _live.duplicate():
		stop(h)
	_live = []


func live_count() -> int:
	return _live.size()


## 场上所有(射线 + 细丝 + 枪口 + 命中爆点/白核/白刺带)的节点总数 —— 门禁数它验换路清干净。
func node_count() -> int:
	var n := 0
	for h in _live:
		for nd in h.get("shells", []):
			if is_instance_valid(nd):
				n += 1
		if is_instance_valid(h.get("muzzle", null)):
			n += 1
		for m in h.get("marks", []):
			for key in ["star", "core", "ring"]:
				if is_instance_valid(m.get(key, null)):
					n += 1
			for nd in m.get("glows", []):
				if is_instance_valid(nd):
					n += 1
	return n
