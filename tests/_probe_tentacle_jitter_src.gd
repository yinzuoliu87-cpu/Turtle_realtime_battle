extends Node
## _probe_tentacle_jitter_src.gd — 触手抽搐来源定位(探针, 不进门禁)。
## 同一根触手、同一帧, 并排算两条中心线:
##   A = 实际画出来的(链式模拟 `_sim_chain` 的输出)
##   B = 它追的目标姿势(姿态表 `_seg_angle` 给的每段方向, 从根部直接积分; 即「没有模拟时」的形状)
## 按状态统计梢端 / 中段的逐帧速度与急动度(三阶差分)。B 平滑而 A 抖 ⇒ 抖是模拟自己长出来的。
## 跑法: bash godot-quiet.sh res://tests/_probe_tentacle_jitter_src.tscn --quit-after 20000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const NAMES := ["EMERGE", "IDLE", "REAR", "SLAM", "RECOVER", "RETRACT", "WARN"]

var _s


func _target(tv, t: Dictionary) -> PackedVector3Array:
	## 与 `_sim_chain` 开头那段「指定姿势」同一份计算, 只是不做模拟、直接积分
	var side: String = str(t["side"])
	var from2: Vector2 = tv.root_pos(side, int(t["idx"]))
	var to2: Vector2 = t["aim"]
	if to2 == Vector2.ZERO:
		to2 = from2 + Vector2(1.0 if side == "left" else -1.0, 0.0) * 400.0
	var bas: Array = tv._basis_of(from2, to2)
	var root3: Vector3 = bas[0]
	var fwd: Vector3 = bas[1]
	var lat: Vector3 = bas[2]
	var up: Vector3 = bas[3]
	var ph: Array = tv._phase(t)
	var stt: int = int(t["state"])
	var ds: float = tv._arc_for(t, stt) * float(ph[0]) / float(tv.SEG)
	var swayt: float = _s._t * tv.SWAY_SPEED + float(t["phase"])
	var kacc := 0.0
	var p: Vector3 = root3
	var out := PackedVector3Array()
	for i in range(tv.SEG + 1):
		out.append(p - root3)
		var u: float = float(i) / float(tv.SEG)
		var seg: Array = tv._seg_angle(t, stt, u, float(t["ts"]), swayt, kacc)
		kacc = float(seg[3])
		var ar: float = deg_to_rad(float(seg[0]))
		var yw: float = float(seg[1])
		p += (fwd * cos(ar) * cos(yw) + lat * sin(yw) * cos(ar) + up * sin(ar)).normalized() * ds
	return out


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	var tv = _s._tentacle_vfx
	tv.clear()
	tv.preview_lock = true
	tv.ensure_forced("left", 1)
	var r0: Vector2 = tv.root_pos("left", 0)
	var aim := r0 + Vector2(1.0, -0.3).normalized() * 300.0
	var A: Array = []
	var B: Array = []
	var S: Array = []
	var dt := 1.0 / 60.0
	for f in range(1100):
		_s._t += dt
		if f == 300 or f == 700:
			tv.strike("left", 0, aim, 1.0)
		tv.tick(dt)
		var t: Dictionary = tv._tents["left|0"]
		var r3: Vector3 = t["root3"]
		var ca := PackedVector3Array()
		for q in (t["center"] as PackedVector3Array):
			ca.append(q - r3)
		A.append(ca)
		B.append(_target(tv, t))
		S.append([int(t["state"]), float(t["ts"])])
	for which in [["A 实际(模拟输出)", A], ["B 目标姿势(无模拟)", B]]:
		var P: Array = which[1]
		var stat := {}
		for i in range(3, P.size()):
			var sname: String = NAMES[int(S[i][0])]
			if i >= 1 and int(S[i][0]) != int(S[i - 1][0]):
				sname = "切换"
			for pi in [18, 36]:
				var v: float = ((P[i][pi] as Vector3) - (P[i - 1][pi] as Vector3)).length() * 1000.0
				var j: float = ((P[i][pi] as Vector3) - 3.0 * (P[i - 1][pi] as Vector3) + 3.0 * (P[i - 2][pi] as Vector3) - (P[i - 3][pi] as Vector3)).length() * 1000.0
				var k: String = "%s|%d" % [sname, pi]
				var e: Array = stat.get(k, [0.0, 0.0, 0])
				stat[k] = [maxf(e[0], v), maxf(e[1], j), int(e[2]) + 1]
		var line := ""
		for k in stat:
			line += "\n    %-12s 速度max %6.0f mm/帧  急动度max %6.0f mm/帧³  (%d 帧)" % [k, stat[k][0], stat[k][1], stat[k][2]]
		print("[jsrc] ", which[0], line)
	## 待机里模拟输出的梢端速度随「进入待机后经过的秒数」怎么变(余震衰减 还是 一直停不下来)
	var buckets := [[0.0, 0.5], [0.5, 1.0], [1.0, 2.0], [2.0, 3.0], [3.0, 5.0], [5.0, 99.0]]
	var line2 := ""
	for bk in buckets:
		var mx := 0.0
		var sm := 0.0
		var nn := 0
		for i in range(1, A.size()):
			if int(S[i][0]) == 1 and int(S[i - 1][0]) == 1 and float(S[i][1]) >= float(bk[0]) and float(S[i][1]) < float(bk[1]):
				var v: float = ((A[i][36] as Vector3) - (A[i - 1][36] as Vector3)).length() * 1000.0
				mx = maxf(mx, v)
				sm += v
				nn += 1
		if nn > 0:
			line2 += "\n    待机第 %.1f~%.1f 秒: 梢端速度 均值 %.0f / 最大 %.0f mm/帧 (%d 帧)" % [bk[0], bk[1], sm / nn, mx, nn]
	print("[jsrc] 待机余震:", line2)
	## 第一段待机(出土后)第 1~3 秒: 梢端 A / B 的 y 与水平位置, 每 6 帧一个
	var tl := ""
	for i in range(1, A.size()):
		if int(S[i][0]) == 1 and float(S[i][1]) >= 1.0 and float(S[i][1]) < 3.0 and i < 300 and i % 6 == 0:
			var a3: Vector3 = A[i][36]
			var b3: Vector3 = B[i][36]
			tl += "\n    ts %.2f  A(%.2f, %.2f, %.2f)  B(%.2f, %.2f, %.2f)  |A-B| %.2f m" % [float(S[i][1]), a3.x, a3.y, a3.z, b3.x, b3.y, b3.z, (a3 - b3).length()]
	print("[jsrc] 待机梢端轨迹:", tl)
	## 各状态: 模拟输出偏离目标姿势多少(梢端 / 中点, 米), 以及梢端最低高度
	var dev := {}
	for i in range(A.size()):
		var nm2: String = NAMES[int(S[i][0])]
		var e2: Array = dev.get(nm2, [0.0, 0.0, 0.0, 0.0, 99.0, 0])
		var d36: float = ((A[i][36] as Vector3) - (B[i][36] as Vector3)).length()
		var d18: float = ((A[i][18] as Vector3) - (B[i][18] as Vector3)).length()
		dev[nm2] = [e2[0] + d36, maxf(e2[1], d36), e2[2] + d18, maxf(e2[3], d18), minf(e2[4], (A[i][36] as Vector3).y), int(e2[5]) + 1]
	var dl := ""
	for k2 in dev:
		var e3: Array = dev[k2]
		dl += "\n    %-8s 梢端偏离 均值 %.2f / 最大 %.2f m · 中点偏离 均值 %.2f / 最大 %.2f m · 梢端最低 y %.2f m (%d 帧)" % [k2, e3[0] / e3[5], e3[1], e3[2] / e3[5], e3[3], e3[4], e3[5]]
	print("[jsrc] 模拟 vs 目标姿势:", dl)
	## 状态切换那一帧: 目标姿势(B)各参数的跳变 —— 用姿态表本身(_phase_at)在切换前后两帧的值
	for i in range(1, S.size()):
		if int(S[i][0]) != int(S[i - 1][0]):
			var jb: float = ((B[i][36] as Vector3) - (B[i - 1][36] as Vector3)).length() * 1000.0
			var ja: float = ((A[i][36] as Vector3) - (A[i - 1][36] as Vector3)).length() * 1000.0
			print("[jsrc] 切换 帧 %d %s→%s: 目标姿势梢端一帧跳 %.0f mm, 模拟输出梢端 %.0f mm" % [i, NAMES[int(S[i - 1][0])], NAMES[int(S[i][0])], jb, ja])
	## 抬到最高点(前摇最后一帧 = 拍下前一帧)时各段在哪: 沿拍击方向(前 +/后 −)、离地高度, 米
	var bs: Array = tv._basis_of(r0, aim)
	var fw: Vector3 = bs[1]
	for i in range(1, S.size() - 1):
		if int(S[i][0]) == 2 and int(S[i + 1][0]) == 3:
			var ln := ""
			for pi3 in [0, 6, 12, 18, 24, 30, 36]:
				var q3: Vector3 = A[i][pi3]
				ln += "  段%02d(前%+.2f, 高%.2f)" % [pi3, q3.dot(fw), q3.y]
			print("[peak] 帧 %d 抬到最高点:%s" % [i, ln])
	for i in range(1, S.size()):
		if int(S[i][0]) == 6 or int(S[i][0]) == 2:
			if i % 10 == 0 or (int(S[i][0]) == 2 and int(S[i - 1][0]) == 6):
				var q4: Vector3 = A[i][36]
				var q5: Vector3 = A[i][18]
				print("[rise] 帧 %d %s ts %.2f  中点(前%+.2f, 高%.2f)  梢端(前%+.2f, 高%.2f)" % [i, NAMES[int(S[i][0])], float(S[i][1]), q5.dot(fw), q5.y, q4.dot(fw), q4.y])
	## 拍下时各段第一次贴地(离地 < 0.35 米)的时刻: 自然 = 从根到梢依次变晚(用户 11-01「途中为什么这个尖会比他身子更快到」)
	for i in range(1, S.size()):
		if int(S[i][0]) == 3 and int(S[i - 1][0]) != 3:
			var ln2 := ""
			for pi4 in [6, 12, 18, 24, 30, 36]:
				## 「落到位」= 降了 90%(相对本段拍下起点与 40 帧内最低点); 趴着时各段离地高度不同, 不能用绝对高度
				var h0: float = (A[i][pi4] as Vector3).y
				var hmin: float = h0
				for j in range(i, mini(i + 40, S.size())):
					hmin = minf(hmin, (A[j][pi4] as Vector3).y)
				var hit := -1
				for j in range(i, mini(i + 40, S.size())):
					if (A[j][pi4] as Vector3).y <= hmin + 0.1 * (h0 - hmin):
						hit = j - i
						break
				ln2 += "  段%02d 第%d帧(%.1f→%.1f米)" % [pi4, hit, h0, hmin]
			print("[land] 拍下起帧 %d 各段首次贴地:%s" % [i, ln2])
			if i < 500:
				for j2 in range(i - 4, mini(i + 34, S.size()), 2):
					var ln3 := ""
					for pi5 in [6, 12, 18, 24, 30, 36]:
						ln3 += " %5.2f" % (A[j2][pi5] as Vector3).y
					print("[hgt] 拍下第%3d帧 高(段06..36):%s  前(梢) %+.2f" % [j2 - i, ln3, (A[j2][36] as Vector3).dot(fw)])
	## 整个出手的速度曲线(用户 11-01「速度没有加速度吗？没有个运动过程吗？」): 中段 / 梢端每帧位移, 每 2 帧一行, 条长 = 梢端速度
	for i in range(300, mini(470, S.size()), 2):
		var vm: float = ((A[i][18] as Vector3) - (A[i - 1][18] as Vector3)).length() * 1000.0
		var vt: float = ((A[i][36] as Vector3) - (A[i - 1][36] as Vector3)).length() * 1000.0
		print("[spd] 帧%4d %-7s ts %.2f  中段 %5.0f  梢端 %5.0f mm/帧 %s" % [i, NAMES[int(S[i][0])], float(S[i][1]), vm, vt, "#".repeat(int(vt / 25.0))])
	## 抽搐 = 速度方向来回翻: 相邻两帧速度点积 < 0(两帧都 > 3 mm/帧才算), 按状态数每秒几次; A 与 B 并排
	for which2 in [["A", A], ["B", B]]:
		var P2: Array = which2[1]
		var rv := {}
		for i in range(2, P2.size()):
			var nm3: String = NAMES[int(S[i][0])]
			for pi2 in [12, 24, 36]:
				var v1: Vector3 = (P2[i][pi2] as Vector3) - (P2[i - 1][pi2] as Vector3)
				var v0: Vector3 = (P2[i - 1][pi2] as Vector3) - (P2[i - 2][pi2] as Vector3)
				var k3: String = "%s|%d" % [nm3, pi2]
				var e4: Array = rv.get(k3, [0, 0])
				var fl: int = 1 if (v1.dot(v0) < 0.0 and v1.length() > 0.003 and v0.length() > 0.003) else 0
				rv[k3] = [int(e4[0]) + fl, int(e4[1]) + 1]
		var l3 := ""
		for k4 in rv:
			l3 += "\n    %-11s 反转 %3d 次 / %4d 帧 = %5.1f 次/秒" % [k4, rv[k4][0], rv[k4][1], float(rv[k4][0]) * 60.0 / float(rv[k4][1])]
		print("[jflip] ", which2[0], l3)
	get_tree().quit(0)
