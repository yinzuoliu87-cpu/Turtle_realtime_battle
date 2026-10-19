extends Node
## verify_determinism_ulp.gd —— **跨芯片**浮点确定性: 在一台机器上模拟「另一块芯片」(2026-10-10)
##
## ══════════════════════════════════════════════════════════════════════
##  由来
## ══════════════════════════════════════════════════════════════════════
## 用户在 iPad(ARM64·IPA)上打的 8 场, 拿到 Windows(x86-64)上重放, 第 180~600 步就分叉;
## 屏幕比例 / 编辑器 vs 导出包 / 帧率 都已排除。`verify_determinism_cross` 只量得到 Windows↔Linux
## (两边都是 x86), 量不到 ARM —— CI 没有 ARM runner。
## 反汇编 ios.zip 里的 libgodot.a 实测: iOS 版引擎的 Vector2.length/distance_to/normalized/dot/…、
## lerpf/smoothstep、randf_range、randfn 全都编成了 FMA(融合乘加, 少一次舍入), x86 版不是;
## sin/cos/atan2/pow/exp/log 则各平台 libm 各算各的。⇒ 同一份输入, 末位不同, 几百步后分叉。
## 修法: sim 路径上这些全走 `scripts/util/det_math.gd`(只用 + - * / sqrt, 各平台逐位一致)。
##
## ══════════════════════════════════════════════════════════════════════
##  这把尺子怎么在一台 x86 上量「ARM 会不会分叉」
## ══════════════════════════════════════════════════════════════════════
## DetMath 有个门禁专用开关 `perturb = N`: 每 N 次**平台相关**的调用, 给结果加/减 1 ulp ——
## 正是另一块芯片会差的那一位。`raw = true` 让 DetMath 退回引擎原版(= 加固之前)。
##   U1 raw(加固前)+ 扰动 ⇒ **必须分叉** —— 证明扰动模型咬得住真实的那类 bug(尺子会咬人)。
##   U2 默认(加固后)+ 扰动 ⇒ 15 个场景的逐步指纹摘要 == `data/determinism_cross.json`(那份金标是
##      verify_determinism_cross 不带扰动跑出来、并在 CI Linux 上复核的) ⇒ 扰动一位都没改到结果。
##      (原来写成「同一进程跑两遍比」, 要多跑一整张表; 金标已经是那一遍的结果, 直接比它。对不上时才补跑一遍找首个分叉步)
##   U3 产品自己的回放校验在 `verify_determinism_ulp_replay.gd`(拆开是为了门禁并行: 两份各约 3~4 分钟)。
##   U4 DetMath 自身: 与引擎 libm 的误差在几个 ulp 内(数值没有改坏玩法), 且输出位模式 == 钉住的金标
##      (CI 的 Linux 每次 push 再算一遍 ⇒ 换编译器 / 换平台 DetMath 自己也必须逐位相同)。
## ★静态那一半(sim 路径上没有绕过 DetMath 的裸调用)在 `tools/det_math_lint.py`(run-tests 审计器)。
##   动态这一半只量得到「走 DetMath 的调用」—— 一处被改回裸调用的, 扰动打不到它, 只有 lint 看得见。
##
## 跑法: <godot> --headless --path . res://tests/verify_determinism_ulp.tscn --quit-after 60000
##   ULP_ONLY=u4 只跑 U4 · ULP_SCEN=⑬ 只跑这一个场景(变异验证用)

const SC := preload("res://scripts/referee/det_scenarios.gd")

## 扰动步长: 每 7 次平台相关调用扰动一次(稀疏 —— 比真实的 FMA 差异还稀, 照样必须咬得住)。
const STRIDE := 7
## raw 证据跑这几个场景(角度/弹道/环绕/抛物线/位移最多的): ③ 满装备 ⑧ 受控 PRNG 落点 ⑬ 凤凰/熔岩/宝箱/星际/无头
const RAW_TAGS := ["③", "⑧", "⑬"]
const GOLDEN_PATH := DeviceSelfcheck.GOLDEN_PATH   # ★与设备自检同一份金标(data/, 进导出包)
## U4 金标: DetMath 在固定输入集上全部输出的位模式摘要(见 `_math_digest`)。
const GOLDEN_MATH := "a1bfb101c1670aed0921de344a53d272115857f805a54b6e181d7fcd676d6ebb"

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.week_anchor_ts = int(SC.PIN_WEEK_ANCHOR)
	_ok("分母 · 正式版默认: DetMath.raw=false、perturb=0", not DetMath.raw and DetMath.perturb == 0)

	var only := OS.get_environment("ULP_ONLY")
	if only == "" or only == "u4":
		print("=== U4 DetMath 自身: 精度与金标 ===")
		_u4()
	if only == "u4":
		_finish()
		return

	print("=== U1 / U2 场景表(%d 个) ===" % SC.all().size())
	var golden = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_PATH))
	var gn: int = (golden as Dictionary).size() if golden is Dictionary else -1
	_ok("分母 · 金标读到 %d 条(= 场景表 %d 个)" % [gn, SC.all().size()], gn == SC.all().size())
	if not (golden is Dictionary):
		golden = {}
	var raw_div := 0
	var raw_n := 0
	## ULP_SCEN=③ 只跑这一个场景(变异验证用; 门禁里不设 ⇒ 全表)
	var scen := OS.get_environment("ULP_SCEN")
	for sc in SC.all():
		var tag: String = str((sc as Dictionary)["tag"])
		if scen != "" and not tag.begins_with(scen):
			continue
		var is_raw_case := false
		for rt in RAW_TAGS:
			if tag.begins_with(rt):
				is_raw_case = true
		## U2: 加固后 + 扰动 ⇒ 摘要 == 不带扰动的金标
		var b: Array = await _scenario(sc, false, STRIDE)
		var want: String = str((golden as Dictionary).get(tag, ""))
		var det := ""
		if str(b[0]) != want:
			var a: Array = await _scenario(sc, false, 0)
			var cmp: Array = _cmp(a[1], b[1])
			det = "不带扰动重跑: %s(%s 金标) · 与带扰动的那遍 %d 步不同, 首个第 %d 步" % [str(a[0]).left(16),
				"==" if str(a[0]) == want else "≠", int(cmp[0]), int(cmp[2])]
		_ok("★★U2 %s · 加固后 + 扰动(每 %d 次) ⇒ 摘要 == 金标" % [tag, STRIDE], want != "" and str(b[0]) == want,
			("%s / 金标 %s  %s" % [str(b[0]).left(16), want.left(16), det]) if str(b[0]) != want else str(b[0]).left(16))
		_ok("  分母 · %s · 这一局在推进(不同指纹 %d > 1)" % [tag, int(b[2])], int(b[2]) > 1)
		_ok("  ★U2 %s · 加固后平台相关调用 0 次(扰动无处可打: %d 次)" % [tag, int(b[3])], int(b[3]) == 0)
		if is_raw_case:
			## U1: 加固前 + 扰动 ⇒ 必须分叉
			var ra: Array = await _scenario(sc, true, 0)
			var rb: Array = await _scenario(sc, true, STRIDE)
			var rc: Array = _cmp(ra[1], rb[1])
			raw_n += 1
			if int(rc[0]) > 0:
				raw_div += 1
			_ok("★★U1 %s · 加固前(raw) + 扰动 ⇒ 必须分叉(首个第 %d 步, %d/%d 步不同, 扰动打中 %d 次)"
				% [tag, int(rc[2]), int(rc[0]), int(rc[1]), int(rb[3])], int(rc[0]) > 0 and int(rb[3]) > 0)
			if raw_n == 1:
				## 只对第一个 raw 场景复核一次(省帧): raw 不扰动跑两遍自身逐位一致 ⇒ 分叉只能来自扰动
				_ok("  分母 · %s · raw 不扰动两遍自身逐位一致(分叉只能来自扰动)" % tag,
					_cmp(ra[1], (await _scenario(sc, true, 0))[1])[0] == 0)
	_ok("分母 · U1 跑了 %d 个场景、%d 个分叉" % [raw_n, raw_div],
		(raw_n == RAW_TAGS.size() or scen != "") and raw_div == raw_n)
	_finish()


func _finish() -> void:
	print("")
	print("  [量] 本门禁共走了 %d 帧(run-tests.sh frames_for 预算要比它大)" % Engine.get_process_frames())
	if _fail == 0:
		print("ALL PASS — 跨芯片浮点确定性 (%d/%d)" % [_n, _n])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _n - _fail])
	DetMath.raw = false
	DetMath.reset_perturb(0)
	get_tree().quit(1 if _fail > 0 else 0)


## 跑一个场景。返回 [摘要, 逐步指纹, 不同指纹数, 扰动打中次数]。
func _scenario(sc: Dictionary, raw: bool, stride: int) -> Array:
	DetMath.raw = raw
	DetMath.reset_perturb(stride)
	OS.set_environment("TURTLE_SEED", str(sc["seed"]))
	var r: Array = await SC.run(self, sc)
	OS.set_environment("TURTLE_SEED", "")
	var hits: int = DetMath.perturb_hits
	DetMath.raw = false
	DetMath.reset_perturb(0)
	return [r[0], r[1], r[2], hits]


## [不同的步数, 比了几步, 首个不同步(-1 = 无)]
func _cmp(a: Array, b: Array) -> Array:
	var bad := 0
	var first := -1
	var n: int = mini(a.size(), b.size())
	for i in range(n):
		if str(a[i]) != str(b[i]):
			bad += 1
			if first < 0:
				first = i
	if a.size() != b.size():
		bad += absi(a.size() - b.size())
	return [bad, n, first]


# ─────────────────────────────── U4 DetMath 自身 ───────────────────────────────

## 固定输入集(覆盖象限边界、大角度、小量、典型 sim 量级)。
func _inputs() -> Array:
	## ★输入只用短字面量 / 引擎常量 / DetMath.rrange: 引擎的 randf_range 在 ARM 上是融合的, 拿它造输入,
	##   ARM 上的输入就和这里不一样, 金标会假红。
	var xs: Array = [0.0, 1e-9, 0.1, 0.5, PI / 4.0, 1.0, PI / 2.0, 2.0, 3.0,
		PI, 4.0, 5.5, TAU, 10.0, 100.0, 1234.5678, 98765.4321, -0.3, -2.5, -7.0]
	var out: Array = []
	for x in xs:
		out.append(float(x))
	var r := RandomNumberGenerator.new()
	r.seed = 20261010
	for _k in range(300):
		out.append(DetMath.rrange(r, -50.0, 50.0))
	return out


func _bits(v: float) -> String:
	return ReplayRecorder.exact(v)


## Vector2 不许走 str()(底下是各平台 printf, .5 舍入方向不同 —— 见 ReplayRecorder.exact 头注)
func _v2bits(v: Vector2) -> String:
	return _bits(v.x) + "/" + _bits(v.y)


func _ulps(a: float, b: float) -> float:
	if a == b:
		return 0.0
	var m: float = maxf(absf(a), absf(b))
	return absf(a - b) / maxf(m * 2.220446049250313e-16, 4.9e-324)


func _u4() -> void:
	var xs: Array = _inputs()
	var worst := {"sin": 0.0, "cos": 0.0, "atan2": 0.0, "exp": 0.0, "log": 0.0, "pow": 0.0, "asin": 0.0, "tan": 0.0}
	var parts: Array = []
	for x in xs:
		var xf: float = x
		var s1: float = DetMath.dsin(xf)
		var c1: float = DetMath.dcos(xf)
		var at: float = DetMath.datan2(xf, 1.7 - xf * 0.3)
		var ex: float = DetMath.dexp(clampf(xf, -40.0, 40.0))
		var lg: float = DetMath.dlog(absf(xf) + 0.01)
		var pw: float = DetMath.dpow(absf(xf) + 0.5, 1.37)
		var asn: float = DetMath.dasin(clampf(xf / 60.0, -1.0, 1.0))
		var tn: float = DetMath.dtan(xf * 0.37)
		worst["sin"] = maxf(worst["sin"], absf(s1 - sin(xf)))
		worst["cos"] = maxf(worst["cos"], absf(c1 - cos(xf)))
		worst["atan2"] = maxf(worst["atan2"], _ulps(at, atan2(xf, 1.7 - xf * 0.3)))
		worst["exp"] = maxf(worst["exp"], _ulps(ex, exp(clampf(xf, -40.0, 40.0))))
		worst["log"] = maxf(worst["log"], absf(lg - log(absf(xf) + 0.01)))
		worst["pow"] = maxf(worst["pow"], _ulps(pw, pow(absf(xf) + 0.5, 1.37)))
		worst["asin"] = maxf(worst["asin"], absf(asn - asin(clampf(xf / 60.0, -1.0, 1.0))))
		## tan 在极点附近值本身巨大, 按「误差 / (1 + |tan|²)」量(= 对角度的误差, 与 sin/cos 同一量级)
		worst["tan"] = maxf(worst["tan"], absf(tn - tan(xf * 0.37)) / (1.0 + tn * tn) / 2.220446049250313e-16)
		var v := Vector2(xf, 0.37 * xf - 3.0)
		var w := Vector2(-0.5 * xf + 7.0, xf * 0.11)
		parts.append("%s,%s,%s,%s,%s,%s,%s,%s" % [_bits(s1), _bits(c1), _bits(at), _bits(ex), _bits(lg), _bits(pw),
			_bits(asn), _bits(tn)])
		parts.append("%s,%s,%s,%s,%s,%s" % [_bits(DetMath.vlen(v)), _bits(DetMath.dist(v, w)), _bits(DetMath.dot(v, w)),
			_v2bits(DetMath.norm(v)), _v2bits(DetMath.rotated(v, xf)), _bits(DetMath.angle_to(v, w))])
	## 绝对误差判据(sin/cos/log/asin 结果可能接近 0, 用绝对量): 1e-15 级 ⇒ 玩法上与 libm 不可分辨
	_ok("U4 精度 · sin/cos 与 libm 最大绝对误差 %s / %s(< 1e-14)" % [String.num_scientific(worst["sin"]), String.num_scientific(worst["cos"])],
		worst["sin"] < 1e-14 and worst["cos"] < 1e-14)
	_ok("U4 精度 · atan2 / exp / pow / tan 相对误差 %.1f / %.1f / %.1f / %.1f ulp(< 8)" % [worst["atan2"], worst["exp"],
		worst["pow"], worst["tan"]], worst["atan2"] < 8.0 and worst["exp"] < 8.0 and worst["pow"] < 64.0 and worst["tan"] < 8.0)
	_ok("U4 精度 · log / asin 最大绝对误差 %s / %s(< 1e-14)" % [String.num_scientific(worst["log"]), String.num_scientific(worst["asin"])],
		worst["log"] < 1e-14 and worst["asin"] < 1e-14)
	_ok("分母 · U4 输入 %d 个" % xs.size(), xs.size() >= 300)
	## datan / dacos 现在 sim 里没人用(zero-caller-ok), 但它们是唯一合法入口 ⇒ 精度也要守着(不进金标摘要)
	var w_at := 0.0
	var w_ac := 0.0
	for x in xs:
		var xf: float = x
		w_at = maxf(w_at, absf(DetMath.datan(xf) - atan(xf)))
		w_ac = maxf(w_ac, absf(DetMath.dacos(clampf(xf / 60.0, -1.0, 1.0)) - acos(clampf(xf / 60.0, -1.0, 1.0))))
	_ok("U4 精度 · atan / acos 最大绝对误差 %s / %s(< 1e-14)" % [String.num_scientific(w_at), String.num_scientific(w_ac)],
		w_at < 1e-14 and w_ac < 1e-14)
	var dig: String = "|".join(parts).sha256_text()
	print("  [量] DetMath 输出摘要 = %s" % dig)
	_ok("★★U4 DetMath 输出位模式 == 金标(换平台/换编译器也必须逐位相同; CI Linux 每次重算)",
		GOLDEN_MATH != "" and dig == GOLDEN_MATH, "实得 %s / 金标 %s" % [dig, GOLDEN_MATH])
	## raw 分支真的是引擎原版(否则 U1 的「加固前」不是真的加固前)
	DetMath.raw = true
	var same_raw: bool = DetMath.dsin(1.234) == sin(1.234) and DetMath.vlen(Vector2(3.1, 4.7)) == Vector2(3.1, 4.7).length()
	DetMath.raw = false
	_ok("U4 · raw=true 时 DetMath 与引擎原版逐位相同(U1 才量的是真正的加固前)", same_raw)
