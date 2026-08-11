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
const HIT_IN := 0.09
const HIT_OUT := 0.18
## 命中爆点的星芒枝数与基础尺寸(码)
const HIT_SPIKES := 7
const HIT_R := 46.0
## 枪口星芒尺寸(码)
const MUZZLE_R := 62.0

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


static func _disc_mesh(seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mid := Color(1.0, 1.0, 1.0, 0.9)
	var rim := Color(1.0, 0.72, 0.30, 0.0)
	for i in range(seg):
		var a0: float = TAU * float(i) / float(seg)
		var a1: float = TAU * float(i + 1) / float(seg)
		st.set_color(mid); st.add_vertex(Vector3.ZERO)
		st.set_color(rim); st.add_vertex(Vector3(cos(a0), 0.0, sin(a0)))
		st.set_color(rim); st.add_vertex(Vector3(cos(a1), 0.0, sin(a1)))
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


# ══════════════════════════════════════════════════════════════════
#  §E 运行时
# ══════════════════════════════════════════════════════════════════

func _alive_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


func _node(mesh: ArrayMesh, mat: StandardMaterial3D, org: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = org
	if _alive_world():
		battle._world.add_child(mi)
	return mi


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
	var mz := _node(_star_mesh(9), _mat(36), battle._world_pos(origin, 0.0))
	mz.scale = Vector3(MUZZLE_R * ws, 1.0, MUZZLE_R * ws)
	var h: Dictionary = {
		"shells": shells, "muzzle": mz, "org": origin, "ang": ang,
		"len": length, "hw": half_w, "s": 0.0, "marks": [],
	}
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


## 每帧告知"现在照到了谁" —— 命中爆点按这个增删, 并且**淡入淡出**。
## ★用户 2026-08-11:「命中特效不能是突然出现突然消失的」。
func set_hits(h: Dictionary, lit: Array, delta: float) -> void:
	if h.is_empty() or not _alive_world():
		return
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
		_apply_mark(m)
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
		keep.append(_make_mark(u))
	h["marks"] = keep


func _make_mark(u: Dictionary) -> Dictionary:
	var ws: float = float(battle.WS)
	var star := _node(_star_mesh(HIT_SPIKES), _mat(38), battle._world_pos(u.get("pos", Vector2.ZERO), 0.0))
	var glow := _node(_disc_mesh(22), _mat(37), battle._world_pos(u.get("pos", Vector2.ZERO), 0.0))
	var m: Dictionary = {"u": u, "star": star, "glow": glow, "a": 0.0, "on": true, "spin": 0.0, "ws": ws}
	_apply_mark(m)
	return m


func _apply_mark(m: Dictionary) -> void:
	var u = m.get("u", null)
	if not (u is Dictionary):
		return
	var ws: float = float(m.get("ws", 1.0))
	var a: float = float(m.get("a", 0.0))
	# ★缓入缓出曲线(smoothstep), 线性 alpha 会读成"闪一下"
	var e: float = a * a * (3.0 - 2.0 * a)
	m["spin"] = float(m.get("spin", 0.0)) + 0.06
	var p: Vector3 = battle._world_pos(u.get("pos", Vector2.ZERO), 0.0)
	for key in ["star", "glow"]:
		var nd = m.get(key, null)
		if not is_instance_valid(nd):
			continue
		nd.position = p
		var r: float = HIT_R * ws * (0.55 + 0.45 * e) * (1.35 if key == "glow" else 1.0)
		nd.scale = Vector3(r, 1.0, r)
		nd.rotation.y = float(m["spin"]) * (1.0 if key == "star" else -0.6)
		(nd.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, e * (1.0 if key == "star" else 0.7))


func _free_mark(m: Dictionary) -> void:
	for key in ["star", "glow"]:
		var nd = m.get(key, null)
		if is_instance_valid(nd):
			nd.queue_free()
		m[key] = null


## 收工: 射线本体与所有命中爆点一起清掉。
## ★换路/战斗结束必须调 —— 068 的头顶充能条就是死在"建了没人清"上(v0.19.93 拆掉的那条)。
func stop(h: Dictionary) -> void:
	if h.is_empty():
		return
	for nd in h.get("shells", []):
		if is_instance_valid(nd):
			nd.queue_free()
	h["shells"] = []
	var mz = h.get("muzzle", null)
	if is_instance_valid(mz):
		mz.queue_free()
	h["muzzle"] = null
	for m in h.get("marks", []):
		_free_mark(m)
	h["marks"] = []
	var keep: Array = []
	for x in _live:
		if not is_same(x, h):
			keep.append(x)
	_live = keep


func clear_all() -> void:
	for h in _live.duplicate():
		stop(h)
	_live = []


func live_count() -> int:
	return _live.size()


## 场上所有(射线 + 枪口 + 命中爆点)的节点总数 —— 门禁数它验换路清干净。
func node_count() -> int:
	var n := 0
	for h in _live:
		for nd in h.get("shells", []):
			if is_instance_valid(nd):
				n += 1
		if is_instance_valid(h.get("muzzle", null)):
			n += 1
		for m in h.get("marks", []):
			for key in ["star", "glow"]:
				if is_instance_valid(m.get(key, null)):
					n += 1
	return n
