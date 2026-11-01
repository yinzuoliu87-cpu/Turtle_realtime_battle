extends Node
## verify_tentacle_continuity.gd — 触手【状态切换处不跳】+ 动作量逐帧打印(2026-08-05 立 · 2026-10-31 随灵物触手重做改写)
##
## ★★★为什么必须有这条(原由来不变):
##   用户 2026-08-05：「这就是漏洞啊，为什么有漏洞？我让你做了这么多遍了还做不好吗」
##   —— 他发现前摇入口的卷曲量从预警末的 50° 跳回 262°（整条又卷回去再放开）。
##   根因是**没有机制**: 每改一个状态的姿态曲线, 都要手工去接它前后邻居的参数。
##
## ★2026-10-31 重做后(方案书 docs/plans/20261031d-灵物触手重做.md §4.3): 原来量 `_phase_at` 的 [根部角, 梢端角, 卷曲量],
##   那个函数连同整套链式模拟一起删了; 新做法是「姿态 = (状态, 状态计时) 的纯函数 + 进状态时记下当时的样子当起点」。
##   用户 10-31 的需求是「这东西在抽搐，而且一直闪光」⇒ 判据改量**着色器拿到的 24 个控制点**(GPU 弯曲用的那一份):
##   ① ★每一个状态切换处(出土→待机→预警→前摇→拍击→收回→待机、点刺、搬家、撤场)相邻两帧控制点位移
##      不超过它前后两帧位移的 2.5 倍(+2 厘米) —— 有断点 = 整条一帧跳过去
##   ④ ★自证: 判据分得出真断点(把一帧控制点换成另一个状态的, ① 那把尺子要报)
##   ②③ 只量不判(★未决 U11): 2026-10-31 用户否了第一版动作(「运动是有问题的啊」「甚至不如旧版」), 第一路改成
##      「以旧版中心线计算为起点原样恢复, 再用逐帧数据找抽搐来源只修那一处」⇒ 动作好不好的尺子(待机换向次数 /
##      待机 >3Hz 能量占比 / 各状态急动度峰值 / 同一时刻同一形状)等第一路交回「抽搐修复」的数值再定阈值;
##      这里先把这几个数逐帧量出来打印, 定阈值时直接拿来用。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_tentacle_continuity.tscn

const G := preload("res://tests/_tentacle_geo.gd")
const NAMES := ["出土", "待机", "前摇", "拍击", "收回", "撤场", "预警"]
const JUMP_K := 2.5
const JUMP_EPS := 0.02

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


## 一帧: [状态, 世界控制点, 露出比例]
func _frame(side: String, idx: int) -> Array:
	var mi := G.node_of(_v, side, idx)
	if mi == null:
		return [int(_v.state_of(side, idx)), PackedVector3Array(), 0.0]
	return [int(_v.state_of(side, idx)), G.world_pts(mi), G.vis_of(mi)]


## 每个状态切换处的跳变: 返回 [[说明, 跳变, 前后邻帧位移最大值]], 以及「两边都几乎看不见(露出 < 2%)」而跳过的个数。
## ★邻帧取「切换前那一步」与「切换后的再下一步」(k−2→k−1 / k+1→k+2), 不取紧跟着的 k→k+1:
##   只跳一帧又弹回去的那种(一帧闪一下)紧跟着的那一步也是一大跳, 拿它当邻帧就把自己抵消了(2026-10-31 改坏验证 T1 抓到)。
func _jumps(fr: Array) -> Array:
	var out: Array = []
	var skipped := 0
	for k in range(2, fr.size() - 2):
		if int(fr[k][0]) == int(fr[k - 1][0]):
			continue
		var a: PackedVector3Array = fr[k - 1][1]
		var b: PackedVector3Array = fr[k][1]
		if a.is_empty() or b.is_empty():
			continue
		if float(fr[k - 1][2]) < 0.02 and float(fr[k][2]) < 0.02:
			skipped += 1            # 整根还在地下(搬家时根部换位置): 什么都看不见, 不算跳
			continue
		var j := G.max_disp(a, b)
		var nb := maxf(G.max_disp(fr[k - 2][1], a), G.max_disp(fr[k + 1][1], fr[k + 2][1]))
		out.append(["%s→%s" % [NAMES[int(fr[k - 1][0])] if int(fr[k - 1][0]) >= 0 else "无", NAMES[int(fr[k][0])] if int(fr[k][0]) >= 0 else "无"], j, nb])
	return [out, skipped]


func _ready() -> void:
	await get_tree().process_frame
	print("=== 灵物触手: 不跳 / 不抽 / 表驱动 ===")
	var RB = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_v = _s._tentacle_vfx
	_v.clear()
	_v.preview_lock = false

	# ══ ① 走一整套: 出土 → 待机 → 拍击 → 点刺 → 搬家 → 撤场, 逐帧记控制点 ══════════
	var fr: Array = []
	_v.ensure("left", 1)
	var aim: Vector2 = _v.root_pos("left", 0) + Vector2(320.0, 50.0)
	var plan := {150: "strike", 330: "jab", 420: "reloc", 600: "strike2", 800: "retract"}
	var seen := {}
	for i in range(900):
		if plan.has(i):
			match str(plan[i]):
				"strike", "strike2":
					_v.strike("left", 0, aim, 1.0)
				"jab":
					_v.strike("left", 0, aim + Vector2(0.0, -90.0), 0.25)
				"reloc":
					_v.relocate("left", 0, _v.root_pos("left", 0) + Vector2(90.0, -70.0))
				"retract":
					_v.ensure("left", 0)
		G.step(_v)
		var f := _frame("left", 0)
		seen[int(f[0])] = true
		fr.append(f)
		if int(f[0]) < 0:
			break
	var js: Array = _jumps(fr)
	var lst: Array = js[0]
	var bad: Array = []
	for e in lst:
		if float(e[1]) > JUMP_K * float(e[2]) + JUMP_EPS:
			bad.append("%s 跳 %.3f 米(邻帧 %.3f)" % [str(e[0]), float(e[1]), float(e[2])])
	var shown := PackedStringArray()
	for e in lst:
		shown.append("%s %.3f/%.3f" % [str(e[0]), float(e[1]), float(e[2])])
	print("     状态切换处 跳变/邻帧: %s · 整根在地下跳过 %d 处" % [", ".join(shown), int(js[1])])
	_ok("① ★分母: 走到过出土 / 待机 / 预警 / 前摇 / 拍击 / 收回 / 撤场 七个状态、比过 %d 个切换处" % lst.size(),
		seen.has(0) and seen.has(1) and seen.has(6) and seen.has(2) and seen.has(3) and seen.has(4) and seen.has(5) and lst.size() >= 10,
		str(seen.keys()))
	_ok("① ★★每个状态切换处控制点都不跳(≤ 邻帧位移 × %.1f + %.2f 米)" % [JUMP_K, JUMP_EPS], bad.is_empty(), str(bad))

	# ══ ④ 自证: 把一帧换成另一个状态的样子, 尺子要报 ══════════════════════
	var fake: Array = fr.duplicate(true)
	var kk := -1
	for k in range(3, fake.size() - 2):
		if int(fake[k][0]) != int(fake[k - 1][0]) and int(fake[k][0]) == 6:
			kk = k
			break
	if kk > 0:
		for k2 in range(kk, mini(kk + 3, fake.size())):
			fake[k2][1] = fr[clampi(kk + 75, 0, fr.size() - 1)][1]      # 预警一开始就跳到 1.25 秒后的样子
	var js2: Array = _jumps(fake)
	var caught := false
	for e in (js2[0] as Array):
		if float(e[1]) > JUMP_K * float(e[2]) + JUMP_EPS:
			caught = true
	_ok("④ ★自证: 人为造一个断点(预警第 0 帧直接换成 1.25 秒后的形状), ① 的尺子报出来了", kk > 0 and caught, "kk=%d" % kk)

	# ══ ② 待机 / 各状态的动作量(只量不判, U11) ═══════════════════════
	## 各状态急动度峰值(控制点三阶差 / dt³, 取整条最大)—— 抽搐 = 急动度尖峰
	var jerk := {}
	for k4 in range(3, fr.size()):
		var a0: PackedVector3Array = fr[k4 - 3][1]
		var a1: PackedVector3Array = fr[k4 - 2][1]
		var a2: PackedVector3Array = fr[k4 - 1][1]
		var a3: PackedVector3Array = fr[k4][1]
		if int(fr[k4][0]) != int(fr[k4 - 3][0]) or a0.size() != a3.size() or a0.is_empty() or a1.size() != a0.size() or a2.size() != a0.size():
			continue
		var jm := 0.0
		for j4 in range(a0.size()):
			jm = maxf(jm, (a3[j4] - 3.0 * a2[j4] + 3.0 * a1[j4] - a0[j4]).length())
		var stn: String = NAMES[int(fr[k4][0])]
		jerk[stn] = maxf(float(jerk.get(stn, 0.0)), jm / pow(G.SIM_DT, 3.0))
	var jshow := PackedStringArray()
	for kn in jerk:
		jshow.append("%s %.0f" % [str(kn), float(jerk[kn])])
	print("     [量] 各状态急动度峰值(米/秒³): %s" % ", ".join(jshow))
	_v.clear()
	_v.ensure("left", 1)
	G.until_state(_v, "left", 0, 1)
	G.step(_v, 40)                              # 出土混进待机
	var mi := G.node_of(_v, "left", 0)
	var tips: Array = []
	for _i in range(int(5.2 / G.SIM_DT)):        # 5.2 秒
		G.step(_v)
		var lp := G.local_pts(mi)
		if not lp.is_empty():
			tips.append(lp[lp.size() - 1])
	var rev := [0, 0, 0]
	var amp := [0.0, 0.0, 0.0]
	var lo := [1.0e9, 1.0e9, 1.0e9]
	var hi := [-1.0e9, -1.0e9, -1.0e9]
	for k3 in range(tips.size()):
		for ax in range(3):
			lo[ax] = minf(float(lo[ax]), float((tips[k3] as Vector3)[ax]))
			hi[ax] = maxf(float(hi[ax]), float((tips[k3] as Vector3)[ax]))
		if k3 >= 2:
			for ax2 in range(3):
				var v0: float = (tips[k3 - 1] as Vector3)[ax2] - (tips[k3 - 2] as Vector3)[ax2]
				var v1: float = (tips[k3] as Vector3)[ax2] - (tips[k3 - 1] as Vector3)[ax2]
				if absf(v0) > 1.0e-6 and absf(v1) > 1.0e-6 and signf(v0) != signf(v1):
					rev[ax2] = int(rev[ax2]) + 1
	for ax3 in range(3):
		amp[ax3] = float(hi[ax3]) - float(lo[ax3])
	var secs: float = maxf(0.01, float(tips.size()) * G.SIM_DT)
	## 待机梢端位移的频谱: >3Hz 的能量占比(去均值后逐轴离散傅里叶, 0.19 Hz 一格)
	var hf := 0.0
	var tot := 0.0
	var nt: int = tips.size()
	for ax4 in range(3):
		var mean := 0.0
		for t4 in tips:
			mean += (t4 as Vector3)[ax4]
		mean /= maxf(1.0, float(nt))
		for kf in range(1, nt / 2):
			var re := 0.0
			var im := 0.0
			for n4 in range(nt):
				var x: float = (tips[n4] as Vector3)[ax4] - mean
				re += x * cos(TAU * float(kf * n4) / float(nt))
				im -= x * sin(TAU * float(kf * n4) / float(nt))
			var e: float = re * re + im * im
			tot += e
			if float(kf) / secs > 3.0:
				hf += e
	print("     [量] 待机 %.1f 秒: 梢端摆幅 %.3f / %.3f / %.3f 米 · 速度换向 每秒 %.2f / %.2f / %.2f 次 · >3Hz 能量占比 %.4f" % [secs,
		float(amp[0]), float(amp[1]), float(amp[2]), float(rev[0]) / secs, float(rev[1]) / secs, float(rev[2]) / secs, hf / maxf(tot, 1.0e-12)])
	_ok("② 分母: 待机真的在动(梢端最大摆幅 %.3f 米 > 0.03)、采到 %d 帧" % [maxf(float(amp[0]), maxf(float(amp[1]), float(amp[2]))), tips.size()],
		tips.size() > 200 and maxf(float(amp[0]), maxf(float(amp[1]), float(amp[2]))) > 0.03)

	# ══ ③ 同一时刻同一个形状?(只量不判, U11) ═══════════════════════
	_v.clear()
	_v.ensure("left", 1)
	_v.ensure("right", 1)                       # 两根都是 0 号 ⇒ 相位相同
	G.until_state(_v, "left", 0, 1)
	G.until_state(_v, "right", 0, 1)
	_v.strike("left", 0, _v.root_pos("left", 0) + Vector2(300.0, 0.0), 1.0)
	G.until_state(_v, "left", 0, 1, 400)        # 左边打完一整套回到待机, 右边一直待机
	G.step(_v, 60)                               # 待机混完(0.45 秒)
	var ml := G.node_of(_v, "left", 0)
	var mr := G.node_of(_v, "right", 0)
	var pl := G.local_pts(ml)
	var pr := G.local_pts(mr)
	var dmax := G.max_disp(pl, pr)
	print("     [量] 同一时刻两根待机触手(左边刚打完一套)控制点最大差 %.7f 米(0 = 表驱动、没有历史状态; U11 定要不要判)" % dmax)
	_ok("③ 分母: 两根待机触手的控制点都量到了(%d / %d 个)" % [pl.size(), pr.size()], pl.size() > 0 and pl.size() == pr.size())

	_v.clear()
	_s._units.clear()
	_s.set_process(false)
	await get_tree().process_frame
	_s.queue_free()
	RB.DEBUG_EDIT = false
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 触手状态切换处不跳(动作量已打印, 阈值待定 U11)" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
