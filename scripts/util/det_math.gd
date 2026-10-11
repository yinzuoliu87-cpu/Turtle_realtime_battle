class_name DetMath
extends RefCounted
## DetMath —— sim 路径上**跨平台逐位一致**的数学(2026-10-10·方案书 `docs/plans/20261010-跨平台浮点确定性.md`)。
##
## ══════════════════════════════════════════════════════════════════════
##  为什么要有它
## ══════════════════════════════════════════════════════════════════════
## 8 场 iPad(ARM64·IPA)真人录像拿到 Windows(x86-64)上重放, 第 180~600 步就分叉。两类根因:
##   ① **引擎 C++ 里的 FMA 融合**: iOS 用 clang 编 Godot, 默认 `-ffp-contract=on` ⇒ `x*x + y*y` 被编成
##      一条 `fmadd`(只舍入一次); x86-64 基线没有 FMA, 是两次舍入。反汇编 ios.zip 里的 libgodot.a 实测:
##      Vector2.length / length_squared / distance_to / distance_squared_to / normalized / dot / cross /
##      angle_to / rotated / limit_length / move_toward / lerp, 全局 lerpf / smoothstep / lerp_angle /
##      move_toward / wrapf / remap, RandomPCG::random(randf_range)、randfn —— **全都带 fmadd**。
##   ② **libm 超越函数**: sin/cos/tan/atan/atan2/asin/acos/pow/exp/log 是各家 libm 自己的近似,
##      IEEE-754 不要求逐位一致(Apple libm ≠ MSVC/UCRT ≠ glibc)。
##
## ★GDScript 层的 `+ - * /` 与 `sqrt` 是**安全的**: VM 每条运算单独执行、单独舍入(同一份反汇编里
##   gdscript_vm / variant_op 的标量浮点运算**零** fmadd), 而 IEEE-754 要求这五种运算正确舍入 ⇒
##   用它们写出来的东西在任何平台上逐位相同。本文件里的实现**只用这五种运算 + floor/比较**。
##   fmod / fposmod / floor / ceil / round / absf / minf / maxf / clampf 也是精确运算, 可以直接用。
##
## ══════════════════════════════════════════════════════════════════════
##  门禁 / 测试开关(只有门禁会动, 正式版永远是默认值)
## ══════════════════════════════════════════════════════════════════════
##   raw     = true  ⇒ 每个函数退回**引擎原版**(= 加固之前的代码, 数值逐位相同)。
##   perturb = N > 0 ⇒ 每 N 次「平台相关」调用给结果加/减 1 ulp —— 在一台机器上**模拟另一块芯片**。
##             ★只作用于 raw 分支: 那正是会随芯片变的那一步; 确定性实现里没有平台相关的步骤可扰动。
##   ⇒ `tests/verify_determinism_ulp.gd`: raw+扰动 必须分叉(尺子会咬人), 默认+扰动 必须逐步一致,
##     加上 `tools/det_math_lint.py` 静态守着「sim 路径上没有绕过本文件的裸调用」。

## ★常量为什么写成「整数 / 2 的幂」: Godot 解析浮点字面量走自己的 `built_in_strtod`, 16 位以上有效数字
##   **不是正确舍入**(实测 π/2 的 33 位前段解析偏了 1 ulp ⇒ sin(98765) 误差 1.4e-11)。各平台是同一份算法,
##   (它里面那条 `1e9*frac1 + frac2` 在 ARM 上也被融合了, 但 1e9×(≤9 位整数)必为精确值 ⇒ 融合不改结果, 反汇编核过)
##   所以不是跨平台问题, 是精度问题。整数字面量与 ≤11 位的 2 的幂解析精确、除以 2 的幂精确 ⇒ 常量逐位等于 fdlibm 原值。

static var raw := false
static var perturb := 0
static var perturb_hits := 0      # 扰动真的生效了几次(门禁分母: 0 = 扰动根本没打到)
static var _pc := 0

const _INV_PIO2 := (5734161139222659 / 4294967296.0 / 2097152.0)
const _PIO2_1 := (1686629713 / 1073741824.0)     # π/2 的前 33 位
const _PIO2_2 := (2242054355 / 4294967296.0 / 4294967296.0 / 2.0)
const _PIO2_3 := (160220439 / 4294967296.0 / 4294967296.0 / 4294967296.0)
const _S1 := -(6004799503160649 / 4294967296.0 / 8388608.0)
const _S2 := (2401919801261139 / 4294967296.0 / 67108864.0)
const _S3 := -(7320136532976085 / 4294967296.0 / 4294967296.0 / 2.0)
const _S4 := (6506786730409597 / 4294967296.0 / 4294967296.0 / 128.0)
const _S5 := -(7571127717829867 / 4294967296.0 / 4294967296.0 / 16384.0)
const _S6 := (1537454791456095 / 4294967296.0 / 4294967296.0 / 524288.0)
const _C1 := (1501199875790163 / 4294967296.0 / 8388608.0)
const _C2 := -(6405119470031223 / 4294967296.0 / 1073741824.0)
const _C3 := (457508533350745 / 4294967296.0 / 4294967296.0)
const _C4 := -(5205429506036397 / 4294967296.0 / 4294967296.0 / 1024.0)
const _C5 := (1261860039765105 / 4294967296.0 / 4294967296.0 / 32768.0)
const _C6 := -(1757820317994549 / 4294967296.0 / 4294967296.0 / 8388608.0)
const _ATANHI := [(8352332796509007 / 4294967296.0 / 4194304.0), (884279719003555 / 4294967296.0 / 262144.0), (8852218891597467 / 4294967296.0 / 2097152.0), (884279719003555 / 4294967296.0 / 131072.0)]
const _ATANLO := [(3683087214424817 / 4294967296.0 / 4294967296.0 / 4294967296.0 / 2048.0), (4967757600021511 / 4294967296.0 / 4294967296.0 / 4294967296.0 / 2048.0), (4511882386918333 / 4294967296.0 / 4294967296.0 / 4294967296.0 / 4096.0), (4967757600021511 / 4294967296.0 / 4294967296.0 / 4294967296.0 / 1024.0)]
const _AT := [(6004799503160589 / 4294967296.0 / 4194304.0), -(1801439850937073 / 4294967296.0 / 2097152.0), (5146970997949439 / 4294967296.0 / 8388608.0),
	-(8006398829074033 / 4294967296.0 / 16777216.0), (3275337272528951 / 4294967296.0 / 8388608.0), -(5542580929731181 / 4294967296.0 / 16777216.0),
	(4799809039908177 / 4294967296.0 / 16777216.0), -(4203530284924621 / 4294967296.0 / 16777216.0), (7172437082246635 / 4294967296.0 / 33554432.0),
	-(5264754476739631 / 4294967296.0 / 33554432.0), (4694068057790993 / 4294967296.0 / 67108864.0)]
const _PI_LO := (4967757600021511 / 4294967296.0 / 4294967296.0 / 4294967296.0 / 512.0)
const _LN2_HI := (2977044471 / 4294967296.0)
const _LN2_LO := (3691024475790907 / 4294967296.0 / 4294967296.0 / 1048576.0)
const _INV_LN2 := (3248660424278399 / 4294967296.0 / 524288.0)
const _P1 := (3002399751580319 / 4294967296.0 / 4194304.0)
const _P2 := -(6405119469862291 / 4294967296.0 / 536870912.0)
const _P3 := (1220022702274443 / 4294967296.0 / 4294967296.0)
const _P4 := -(7807914560613361 / 4294967296.0 / 4294967296.0 / 256.0)
const _P5 := (390835970239053 / 4294967296.0 / 4294967296.0 / 512.0)
const _LG1 := (6004799503160723 / 4294967296.0 / 2097152.0)
const _LG2 := (1801439850921601 / 4294967296.0 / 1048576.0)
const _LG3 := (5146971033736025 / 4294967296.0 / 4194304.0)
const _LG4 := (8006390766270639 / 4294967296.0 / 8388608.0)
const _LG5 := (3275661152453103 / 4294967296.0 / 4194304.0)
const _LG6 := (5517391500461727 / 4294967296.0 / 8388608.0)
const _LG7 := (1332903234475153 / 4294967296.0 / 2097152.0)
const _SQRT2 := (6369051672525773 / 4294967296.0 / 1048576.0)
const _CMP_EPS := 0.00001


# ─────────────────────────────── 扰动(门禁专用) ───────────────────────────────

## 门禁开扰动前清零(换一局重来时图样从头开始, 录与播才可比)。
static func reset_perturb(every: int) -> void:
	perturb = every
	_pc = 0
	perturb_hits = 0


static func _tick() -> int:
	_pc += 1
	if _pc % perturb != 0:
		return 0
	perturb_hits += 1
	return 1 if (_pc / perturb) % 2 == 0 else -1


## double 结果 ±1 ulp(超越函数: 各家 libm 差的就是这一位)。
static func _pf(x: float) -> float:
	if perturb <= 0 or x == 0.0 or is_nan(x) or is_inf(x):
		return x
	var d := _tick()
	if d == 0:
		return x
	var b := PackedFloat64Array([x]).to_byte_array()
	b.encode_s64(0, b.decode_s64(0) + d)
	return b.decode_double(0)


## float32 结果 ±1 ulp(Vector2 是 float32; FMA 差的是 float32 的末位)。
static func _p32(x: float) -> float:
	if perturb <= 0 or x == 0.0 or is_nan(x) or is_inf(x):
		return x
	var d := _tick()
	if d == 0:
		return x
	var b := PackedFloat32Array([x]).to_byte_array()
	b.encode_s32(0, b.decode_s32(0) + d)
	return b.decode_float(0)


static func _pv(v: Vector2) -> Vector2:
	if perturb <= 0:
		return v
	return Vector2(_p32(v.x), _p32(v.y))


# ─────────────────────────────── Vector2 ───────────────────────────────
## 全部按 double 算(分量从 float32 读进来是精确的), 返回时 Vector2 再舍入回 float32 —— 两步都是确定的。

static func vlen(v: Vector2) -> float:
	if raw:
		return _p32(v.length())
	return sqrt(v.x * v.x + v.y * v.y)


static func len2(v: Vector2) -> float:
	if raw:
		return _p32(v.length_squared())
	return v.x * v.x + v.y * v.y


static func dist(a: Vector2, b: Vector2) -> float:
	if raw:
		return _p32(a.distance_to(b))
	var dx: float = a.x - b.x
	var dy: float = a.y - b.y
	return sqrt(dx * dx + dy * dy)


static func dist2(a: Vector2, b: Vector2) -> float:
	if raw:
		return _p32(a.distance_squared_to(b))
	var dx: float = a.x - b.x
	var dy: float = a.y - b.y
	return dx * dx + dy * dy


static func norm(v: Vector2) -> Vector2:
	if raw:
		return _pv(v.normalized())
	var l2: float = v.x * v.x + v.y * v.y
	if l2 == 0.0:
		return Vector2()
	var l: float = sqrt(l2)
	return Vector2(v.x / l, v.y / l)


static func dot(a: Vector2, b: Vector2) -> float:
	if raw:
		return _p32(a.dot(b))
	return a.x * b.x + a.y * b.y


static func cross(a: Vector2, b: Vector2) -> float:
	if raw:
		return _p32(a.cross(b))
	return a.x * b.y - a.y * b.x


static func angle(v: Vector2) -> float:
	if raw:
		return _pf(v.angle())
	return datan2(v.y, v.x)


static func angle_to(a: Vector2, b: Vector2) -> float:
	if raw:
		return _pf(a.angle_to(b))
	return datan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)


static func rotated(v: Vector2, ang: float) -> Vector2:
	if raw:
		return _pv(v.rotated(ang))
	var s: float = dsin(ang)
	var c: float = dcos(ang)
	return Vector2(v.x * c - v.y * s, v.x * s + v.y * c)


static func vlerp(a: Vector2, b: Vector2, t: float) -> Vector2:
	if raw:
		return _pv(a.lerp(b, t))
	return Vector2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)


static func limit_len(v: Vector2, l: float) -> Vector2:
	if raw:
		return _pv(v.limit_length(l))
	var n: float = sqrt(v.x * v.x + v.y * v.y)
	if n > 0.0 and l < n:
		return Vector2(v.x / n * l, v.y / n * l)
	return v


static func vmove_toward(a: Vector2, to: Vector2, delta: float) -> Vector2:
	if raw:
		return _pv(a.move_toward(to, delta))
	var dx: float = to.x - a.x
	var dy: float = to.y - a.y
	var n: float = sqrt(dx * dx + dy * dy)
	if n <= delta or n < _CMP_EPS:
		return to
	return Vector2(a.x + dx / n * delta, a.y + dy / n * delta)


## Geometry2D.get_closest_point_to_segment 的确定性版(引擎版里 dot / length_squared / `a + n*d` 在 ARM 上融合)。
static func seg_closest(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	if raw:
		return _pv(Geometry2D.get_closest_point_to_segment(p, a, b))
	var nx: float = b.x - a.x
	var ny: float = b.y - a.y
	var l2: float = nx * nx + ny * ny
	if l2 < 1e-20:
		return a
	var d: float = ((p.x - a.x) * nx + (p.y - a.y) * ny) / l2
	if d <= 0.0:
		return a
	if d >= 1.0:
		return b
	return Vector2(a.x + nx * d, a.y + ny * d)


# ─────────────────────────────── 随机(RandomNumberGenerator) ───────────────────────────────
## 引擎的 randf_range = `randf() * (to - from) + from`(float32, ARM 上融合)。这里同样只取**一个** randf()
##   ⇒ 消耗的随机数个数与原版相同(序列不错位), 只是乘加分两步、按 double 算。

static func rrange(rng: RandomNumberGenerator, a: float, b: float) -> float:
	if raw:
		return _p32(rng.randf_range(a, b))
	return a + rng.randf() * (b - a)


## randfn(Box-Muller): 引擎版 = `temp = randf(); if temp < ε: temp += ε; mean + dev * cos(τ·randf()) * sqrt(-2·log(temp))`。
##   取数顺序与个数照抄(先 temp 后角度, 共两个), 超越函数换成本文件的。
static func rnorm(rng: RandomNumberGenerator, mean: float, dev: float) -> float:
	if raw:
		return _pf(rng.randfn(mean, dev))
	var t: float = rng.randf()
	if t < _CMP_EPS:
		t += _CMP_EPS
	var u: float = rng.randf()
	return mean + dev * (dcos(TAU * u) * sqrt(-2.0 * dlog(t)))


# ─────────────────────────────── 标量 ───────────────────────────────

static func flerp(a: float, b: float, t: float) -> float:
	if raw:
		return _pf(lerpf(a, b, t))
	return a + (b - a) * t


static func smooth(from: float, to: float, x: float) -> float:
	if raw:
		return _pf(smoothstep(from, to, x))
	if is_equal_approx(from, to):
		if from <= to:
			return 0.0 if x <= from else 1.0
		return 1.0 if x <= to else 0.0
	var s: float = clampf((x - from) / (to - from), 0.0, 1.0)
	return s * s * (3.0 - 2.0 * s)


## 补间缓动(写 sim 状态的补间专用): 补间本身一律「float 0→1、线性」(Linear::in = c*t/d+b, 先除后加, 不会融合),
##   缓动在回调里用它算。引擎的 Quad/Sine/Cubic 方程在 iOS 版里是融合的(反汇编 tween.o 实测), Vector2 补间走的
##   Animation::interpolate_variant 也是 ⇒ 不许让它们的输出进 sim。方程照抄 Godot easing_equations.h(b=0, c=1, d=1)。
static func tween_ease(q: float, trans: int, ease_type: int) -> float:
	if raw:
		return _p32(Tween.interpolate_value(0.0, 1.0, q, 1.0, trans, ease_type))
	if trans == Tween.TRANS_LINEAR:
		return q
	match ease_type:
		Tween.EASE_IN:
			return _ease_in(q, trans)
		Tween.EASE_OUT:
			return 1.0 - _ease_in(1.0 - q, trans)
		Tween.EASE_IN_OUT:
			if q < 0.5:
				return 0.5 * _ease_in(2.0 * q, trans)
			return 0.5 + 0.5 * (1.0 - _ease_in(2.0 - 2.0 * q, trans))
	## EASE_OUT_IN
	if q < 0.5:
		return 0.5 * (1.0 - _ease_in(1.0 - 2.0 * q, trans))
	return 0.5 + 0.5 * _ease_in(2.0 * q - 1.0, trans)


## 各缓动的 in 形(out / in_out 由对称得出, 与 Godot 的分段式在数学上相同)。
static func _ease_in(x: float, trans: int) -> float:
	match trans:
		Tween.TRANS_QUAD:
			return x * x
		Tween.TRANS_CUBIC:
			return x * x * x
		Tween.TRANS_QUART:
			return x * x * x * x
		Tween.TRANS_SINE:
			return 1.0 - dcos(x * (PI * 0.5))
	push_error("DetMath.tween_ease: 不支持的 trans %d(sim 补间只许 LINEAR/QUAD/CUBIC/QUART/SINE)" % trans)
	return x


static func lerp_ang(from: float, to: float, w: float) -> float:
	if raw:
		return _pf(lerp_angle(from, to, w))
	var diff: float = fmod(to - from, TAU)
	var dd: float = fmod(2.0 * diff, TAU) - diff
	return from + dd * w


# ─────────────────────────────── 超越函数(fdlibm 移植, 只用 + - * / sqrt floor) ───────────────────────────────

## 归约 x = k·π/2 + r(|r| ≤ π/4, 写在 dsin/dcos 里): 三段 π/2(各 33 位), k < 2^20 时 k·段 精确,
##   |x| ≲ 1.6e6 内误差 ≈ 1 ulp。超出这个范围照样确定(只是精度降), sim 里的角度远到不了。
static func _ksin(x: float) -> float:
	var z: float = x * x
	var v: float = z * x
	var r: float = _S2 + z * (_S3 + z * (_S4 + z * (_S5 + z * _S6)))
	return x + v * (_S1 + z * r)


static func _kcos(x: float) -> float:
	var z: float = x * x
	var r: float = z * (_C1 + z * (_C2 + z * (_C3 + z * (_C4 + z * (_C5 + z * _C6)))))
	var hz: float = 0.5 * z
	var w: float = 1.0 - hz
	return w + (((1.0 - w) - hz) + z * r)


static func dsin(x: float) -> float:
	if raw:
		return _pf(sin(x))
	if is_nan(x) or is_inf(x):
		return NAN
	if absf(x) <= (884279719003555 / 4294967296.0 / 262144.0):
		return _ksin(x)
	var k: float = floor(x * _INV_PIO2 + 0.5)
	var r: float = ((x - k * _PIO2_1) - k * _PIO2_2) - k * _PIO2_3
	match posmod(int(k), 4):
		0: return _ksin(r)
		1: return _kcos(r)
		2: return -_ksin(r)
	return -_kcos(r)


static func dcos(x: float) -> float:
	if raw:
		return _pf(cos(x))
	if is_nan(x) or is_inf(x):
		return NAN
	if absf(x) <= (884279719003555 / 4294967296.0 / 262144.0):
		return _kcos(x)
	var k: float = floor(x * _INV_PIO2 + 0.5)
	var r: float = ((x - k * _PIO2_1) - k * _PIO2_2) - k * _PIO2_3
	match posmod(int(k), 4):
		0: return _kcos(r)
		1: return -_ksin(r)
		2: return -_kcos(r)
	return _ksin(r)


static func dtan(x: float) -> float:
	if raw:
		return _pf(tan(x))
	return dsin(x) / dcos(x)


static func _atan_pos(ax: float) -> float:
	## ax ≥ 0 的 atan(fdlibm s_atan.c)
	if ax >= (1 * 4294967296.0 * 4294967296.0 * 4.0):       # 2^66
		return _ATANHI[3] + _ATANLO[3]
	var id := -1
	var x: float = ax
	if ax < 0.4375:
		if ax < 3.7252902984e-09:            # 2^-28
			return ax
	elif ax < 1.1875:
		if ax < 0.6875:
			id = 0
			x = (2.0 * ax - 1.0) / (2.0 + ax)
		else:
			id = 1
			x = (ax - 1.0) / (ax + 1.0)
	elif ax < 2.4375:
		id = 2
		x = (ax - 1.5) / (1.0 + 1.5 * ax)
	else:
		id = 3
		x = -1.0 / ax
	var z: float = x * x
	var w: float = z * z
	var s1: float = z * (_AT[0] + w * (_AT[2] + w * (_AT[4] + w * (_AT[6] + w * (_AT[8] + w * _AT[10])))))
	var s2: float = w * (_AT[1] + w * (_AT[3] + w * (_AT[5] + w * (_AT[7] + w * _AT[9]))))
	if id < 0:
		return x - x * (s1 + s2)
	return _ATANHI[id] - ((x * (s1 + s2) - _ATANLO[id]) - x)


# zero-caller-ok: DetMath 是 sim 路径上 atan 的唯一合法入口(det_math_lint 禁裸 atan), 现在 sim 里没人用 atan, 留着给下一个要用的人
static func datan(x: float) -> float:
	if raw:
		return _pf(atan(x))
	if is_nan(x):
		return NAN
	if x < 0.0:
		return -_atan_pos(-x)
	return _atan_pos(x)


static func datan2(y: float, x: float) -> float:
	if raw:
		return _pf(atan2(y, x))
	if is_nan(x) or is_nan(y):
		return NAN
	var yneg: bool = y < 0.0 or (y == 0.0 and 1.0 / y < 0.0)
	var xneg: bool = x < 0.0 or (x == 0.0 and 1.0 / x < 0.0)
	if y == 0.0:
		if not xneg:
			return y                           # ±0
		return -PI if yneg else PI
	if x == 0.0:
		return -PI * 0.5 if yneg else PI * 0.5
	if is_inf(x):
		if is_inf(y):
			var q: float = PI * 0.25 if not xneg else PI * 0.75
			return -q if yneg else q
		if not xneg:
			return -0.0 if yneg else 0.0
		return -PI if yneg else PI
	if is_inf(y):
		return -PI * 0.5 if yneg else PI * 0.5
	var z: float = _atan_pos(absf(y / x))
	if xneg:
		z = PI - (z - _PI_LO)
	return -z if yneg else z


static func dasin(x: float) -> float:
	if raw:
		return _pf(asin(x))
	if is_nan(x) or absf(x) > 1.0:
		return NAN
	return datan2(x, sqrt((1.0 - x) * (1.0 + x)))


# zero-caller-ok: 同 datan —— det_math_lint 禁裸 acos, 这是唯一合法入口
static func dacos(x: float) -> float:
	if raw:
		return _pf(acos(x))
	if is_nan(x) or absf(x) > 1.0:
		return NAN
	return datan2(sqrt((1.0 - x) * (1.0 + x)), x)


## 2^k(k 整数): 逐位平方, 每一步都是 2 的幂相乘 = 精确。
static func _pow2i(k: int) -> float:
	var base: float = 2.0 if k >= 0 else 0.5
	var n: int = absi(k)
	var r: float = 1.0
	while n > 0:
		if n & 1:
			r *= base
		base *= base
		n >>= 1
	return r


static func dexp(x: float) -> float:
	if raw:
		return _pf(exp(x))
	if is_nan(x):
		return NAN
	if x > (6243314768165359 / 4294967296.0 / 2048.0):
		return INF
	if x < -(6554261109157969 / 4294967296.0 / 2048.0):
		return 0.0
	var k := 0
	var hi: float = x
	var lo := 0.0
	var ax: float = absf(x)
	if ax > (6243314768165359 / 4294967296.0 / 4194304.0):              # 0.5·ln2
		k = int(floor(x * _INV_LN2 + 0.5))
		hi = x - float(k) * _LN2_HI
		lo = float(k) * _LN2_LO
		x = hi - lo
	elif ax < 3.7252902984e-09:
		return 1.0 + x
	var t: float = x * x
	var c: float = x - t * (_P1 + t * (_P2 + t * (_P3 + t * (_P4 + t * _P5))))
	if k == 0:
		return 1.0 - ((x * c) / (c - 2.0) - x)
	var y: float = 1.0 - ((lo - (x * c) / (2.0 - c)) - hi)
	## 分两步乘, 避免 2^k 本身上溢/下溢(k 在 ±1075 内)
	var k1: int = k / 2
	return y * _pow2i(k1) * _pow2i(k - k1)


static func dlog(x: float) -> float:
	if raw:
		return _pf(log(x))
	if is_nan(x) or x < 0.0:
		return NAN
	if x == 0.0:
		return -INF
	if is_inf(x):
		return INF
	## x = m·2^k, m ∈ [√2/2, √2)。按 2 的幂缩放 = 精确。
	var k := 0
	var m: float = x
	while m >= (1 * 4294967296.0 * 4294967296.0):        # 2^64
		m *= (1 / 4294967296.0 / 4294967296.0)            # 2^-64
		k += 64
	while m < (1 / 4294967296.0 / 4294967296.0):
		m *= (1 * 4294967296.0 * 4294967296.0)
		k -= 64
	while m >= _SQRT2:
		m *= 0.5
		k += 1
	while m < _SQRT2 * 0.5:
		m *= 2.0
		k -= 1
	var f: float = m - 1.0
	var s: float = f / (2.0 + f)
	var z: float = s * s
	var w: float = z * z
	var t1: float = w * (_LG2 + w * (_LG4 + w * _LG6))
	var t2: float = z * (_LG1 + w * (_LG3 + w * (_LG5 + w * _LG7)))
	var r: float = t2 + t1
	var hfsq: float = 0.5 * f * f
	var dk: float = float(k)
	return dk * _LN2_HI - ((hfsq - (s * (hfsq + r) + dk * _LN2_LO)) - f)


## pow: 常见形状走精确/确定的捷径, 其余 exp(y·log x)。
##   y 是 |y| ≤ 64 的整数 ⇒ 逐位平方(只有乘除); y = ±0.5 ⇒ sqrt。
static func dpow(x: float, y: float) -> float:
	if raw:
		return _pf(pow(x, y))
	if y == 0.0:
		return 1.0
	if is_nan(x) or is_nan(y):
		return NAN
	if y == 1.0:
		return x
	if y == 2.0:
		return x * x
	if y == 0.5 and x >= 0.0:
		return sqrt(x)
	if y == -0.5 and x > 0.0:
		return 1.0 / sqrt(x)
	if y == floor(y) and absf(y) <= 64.0:
		var n: int = int(absf(y))
		var b: float = x
		var r: float = 1.0
		while n > 0:
			if n & 1:
				r *= b
			b *= b
			n >>= 1
		return 1.0 / r if y < 0.0 else r
	if x == 0.0:
		return INF if y < 0.0 else 0.0
	if x < 0.0:
		return NAN
	return dexp(y * dlog(x))
