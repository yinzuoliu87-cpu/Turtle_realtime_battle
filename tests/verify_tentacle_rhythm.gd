extends Node
## verify_tentacle_rhythm.gd — 触手拍击的**节奏**（2026-08-04）
##
## ★为什么要单独一条：
##   用户 2026-08-04：「我回来验收要看到所有节奏和每个时间点的形状和视频里的一模一样」。
##   逐帧量官方 `wfull` 之后发现我当时的动画有三个**方向性**错误，而
##   `verify_tentacle_vfx` 全绿 —— 它守的是"状态机流转 / 长度上限 / 面数"，
##   **一个字都没守到节奏**。三个错误分别是：
##     ① 拍击 +2~+9 帧【完全定格】（覆盖恒定 9.06、臂长恒定 0.521），官方一帧都没停
##     ② 前摇在【缩小】（覆盖 1.52→1.17），官方在【长大】（1.55→2.73，+76%）
##     ③ 带宽【起点最粗一路细】，官方是【甩出去时细 → 鼓起来 → 再收细】
##
## ★判据全部落在**真实网格几何**上（沿曲线积弧长 / 量截面半径），
##   不是读 `SLAM_LEN_CURVE` 那张表 —— 读表就是恒真式（CLAUDE.md §2）。
##   四条各自都做过反向验证（见每条末尾的注释）。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_tentacle_rhythm.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const TV := preload("res://scripts/systems/equip/tentacle_vfx.gd")

var _n := 0
var _fail := 0
var _s
var _v


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 把触手摆到指定状态的指定 ts，重建网格，量【真实几何】
func _sample(st: int, ts: float) -> Dictionary:
	var t: Dictionary = _v._tents["left|0"]
	t["state"] = st
	t["ts"] = ts
	t["share"] = 1.0
	t["aim"] = _v.root_pos("left", 0) + Vector2(520.0, 60.0)
	t["acc"] = 99.0                       # 绕过待机降频
	_v.tick(0.0)
	var mi: MeshInstance3D = t["mi"]
	var m: ArrayMesh = mi.mesh
	if m.get_surface_count() == 0:
		return {"len": 0.0, "w": 0.0}
	var arr: Array = m.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	# ★★顶点布局：三角带是**非索引化**的 —— 每段 (RING-1) 个 quad × 6 个顶点，
	#   一个 quad 的 6 个顶点依次是 prev[k], prev[k+1], ring[k], prev[k+1], ring[k+1], ring[k]。
	#   （我第一版按 RING 步长切片当成"一个截面"，切出来根本不是截面，
	#     ①②③ 三条量到的全是垃圾数 —— 门禁自己把这个读法错误抓出来了。）
	var QPS: int = (TV.RING - 1) * 6          # 每段的顶点数
	var segs: int = vs.size() / QPS
	var mids: Array = []
	var widths: Array = []
	for j in range(segs):
		var base: int = j * QPS
		var c := Vector3.ZERO
		for k in range(QPS):
			c += vs[base + k]
		mids.append(c / float(QPS))
		# 带宽 = 同一截面【第 0 列】到【最后一列】的距离
		var last: int = base + (TV.RING - 2) * 6 + 1     # 最后一个 quad 的 prev[k+1]
		if last < vs.size():
			widths.append((vs[base] - vs[last]).length())
	var L := 0.0
	for j2 in range(1, mids.size()):
		L += (mids[j2] - mids[j2 - 1]).length()
	# ★★2026-08-05：本文件原来全部拿【弧长】当节奏的载体。
	#   用户："拍击应该以 idle 的模型来拍，像一个鞭子一样高高抬起然后打下去" ⇒
	#   弧长改成**恒定**（鞭子不会变长），投影长度靠卷曲量变。
	#   于是"弧长在变"这个判据整个失效（三条一起红）——
	#   **判据要换成【端点到根部的直线距离】**：那才是鞭子甩出去/收回来的量。
	var tip: float = 0.0
	if mids.size() >= 2:
		tip = (mids[mids.size() - 1] - mids[0]).length()
	# 取中段带宽（根/梢是锥形两端，不代表整体）
	var w := 0.0
	if widths.size() > 4:
		w = float(widths[int(widths.size() * 0.45)])
	return {"len": L, "w": w, "tip": tip}


func _ready() -> void:
	await get_tree().process_frame
	print("=== 灵物触手: 拍击节奏(逐帧对齐官方) ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_v = _s._tentacle_vfx
	_v.clear()
	_v.ensure("left", 1)
	_v.tick(2.1)                                   # 走完出土

	# ── ① 拍击期间【不许定格】────────────────────────────────
	#   官方 +2~+9 每帧都在变（覆盖 8.53→4.11）。我当时恒定 8 帧。
	#   判据：把 0~T_SLAM 均匀采 12 点，相邻弧长【任意连续 3 点完全相等】即判定格。
	#   ★反向验证：把 `arc` 改成常数 `reach_arc` 后本条立刻 FAIL（实测）。
	var lens: Array = []
	for i in range(12):
		lens.append(float(_sample(3, TV.T_SLAM * float(i) / 11.0)["tip"]))
	var frozen := 0
	var run := 1
	for i in range(1, lens.size()):
		if absf(float(lens[i]) - float(lens[i - 1])) < 0.01:
			run += 1
			frozen = maxi(frozen, run)
		else:
			run = 1
	_ok("① ★拍击期间【端点一帧都不许定格】(官方每帧都在变; 我曾恒定 8 帧)",
		frozen < 3, "最长连续 %d 个采样点端点距离不变: %s" % [frozen, str(lens.slice(0, 6))])

	# ── ② 长度包络有【二次峰】(鞭子余振) ────────────────────
	#   官方 +0 0.435 → +1 0.354 → +2 **0.417**(回弹)。任何单调缓动都做不出来。
	#   判据：0~0.12s 内存在 a>b<c 的谷（先降后升）。
	#   ★反向验证：把 SLAM_LEN_CURVE 换成单调递减序列后本条 FAIL。
	var e0: float = float(_sample(3, 0.005)["tip"])
	var e1: float = float(_sample(3, 0.040)["tip"])
	var e2: float = float(_sample(3, 0.075)["tip"])
	_ok("② ★甩出去有【余振二次峰】(先回缩再涨回来, 像鞭子; 官方 0.435→0.354→0.417)",
		e1 < e0 * 0.995 and e2 > e1 * 1.02,
		"%.2f → %.2f → %.2f" % [e0, e1, e2])

	# ── ③ 前摇是【长大】不是缩小 ────────────────────────────
	#   官方前摇 5 帧覆盖 +76%、投影臂长 0.097→0.167。我曾是 1.52→1.17（反的）。
	#   ★反向验证：把 REAR 的 arc 改回 ARC_LEN 常数后本条 FAIL。
	var r0: float = float(_sample(2, 0.005)["tip"])
	var r1: float = float(_sample(2, TV.T_REAR * 0.95)["tip"])
	_ok("③ ★前摇【抬起来】(端点抬高/拉远; 官方 5 帧涨 76%)",
		r1 > r0 * 1.18, "前摇端点 %.2f → %.2f (×%.2f)" % [r0, r1, r1 / maxf(r0, 0.01)])

	# ── ④ 带宽：甩出去时【细】→ 鼓起来 → 再收细 ──────────────
	#   官方 +0 0.0396 → +2 **0.0508(峰)** → +6 0.0296。我曾是起点最粗一路细。
	#   ★反向验证：把 SLAM_W_CURVE[0] 改成 1.2 后本条 FAIL。
	var w0: float = float(_sample(3, 0.005)["w"])
	var wp: float = float(_sample(3, 0.070)["w"])
	var w6: float = float(_sample(3, 0.210)["w"])
	_ok("④ ★带宽先细后鼓再收(官方 .0396→.0508→.0296; 我曾是起点最粗一路细)",
		w0 < wp * 0.92 and w6 < wp * 0.80,
		"甩出 %.3f → 峰 %.3f → 收 %.3f" % [w0, wp, w6])

	# ── ④b ★弧长【恒定】—— 鞭子不会变长 ─────────────────────
	#   ★反向验证：把 `_arc_for` 的 ST_SLAM 改回 `reach*_env(...)` 后本条 FAIL。
	var al: Array = []
	for i3 in range(6):
		al.append(float(_sample(3, TV.T_SLAM * float(i3) / 5.0)["len"]))
	var amin: float = al[0]
	var amax: float = al[0]
	for v in al:
		amin = minf(amin, float(v)); amax = maxf(amax, float(v))
	_ok("④b ★弧长在整个拍击里【恒定】—— 鞭子不会变长(投影变化靠卷曲)",
		amax - amin < amin * 0.06, "弧长 %.2f ~ %.2f" % [amin, amax])

	# ── ⑤ 分母自证：上面四条量到的是【真实几何】不是 0 ─────────
	_ok("⑤ ★分母: 量到的弧长/带宽都是真数(不是空网格)",
		e0 > 1.0 and wp > 0.05 and lens.size() == 12,
		"e0=%.2f wp=%.3f n=%d" % [e0, wp, lens.size()])

	# ── ⑥ 包络表本身没被改坏（表是官方逐帧量出来的事实源）────
	_ok("⑥ 包络表长度一致且首帧带宽 < 峰值(官方: 甩出去那帧是细的)",
		TV.SLAM_LEN_CURVE.size() == TV.SLAM_W_CURVE.size()
			and float(TV.SLAM_W_CURVE[0]) < 0.9,
		"len=%d w[0]=%.3f" % [TV.SLAM_LEN_CURVE.size(), float(TV.SLAM_W_CURVE[0])])

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 触手拍击节奏" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
