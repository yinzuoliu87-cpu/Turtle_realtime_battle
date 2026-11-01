extends Node
## verify_tentacle_soft.gd — 触手拍下去: 不拍两次 / 不扎进地里 / 不戳出去 / 落地那一刻就是伤害那一刻
## (2026-08-20 立 · 2026-10-31 随灵物触手重做改写; 方案书 docs/plans/20261031d-灵物触手重做.md §4.3)
##
## ── 留下来的(新做法同样成立, 判据换成量着色器拿到的 24 个控制点, tests/_tentacle_geo.gd) ──
##   ① ★梢端【过了下落半程之后】再不许回抬 —— 用户 2026-08-05「明明我看到了两次拍击」(拍两次 = 落下去又抬起来)
##   ② ★没有任何一段扎进地面以下 —— 用户 2026-08-21「拍下去的时候鞭子有一部分直接在地下了」
##   ③ ★拍击全程弧长恒定 —— 用户 2026-08-05「戳出去」= 拍击中途变长。阈值沿用旧门禁的棘轮 36%(旧版链式模拟的收敛残差,
##      只降不升): 10-31 用户否了第一版成品, 第一路改成以旧版中心线为起点原样恢复 ⇒ 尺子回到旧版验收过的那一把, 修好了再往下收
##   ④ ★梢端真正落地的时刻 = 伤害结算时刻(`hit_delay`, 差 ≤ 0.05 秒) —— 用户 2026-08-21「肯定是落地伤害」
##   ⑤ ★点刺(闪避追击, share < 0.9)同样不回抬、不扎地
##
## ── 删掉的(★未决, 已登记方案书 §5 U5; 第一路恢复旧版中心线后按它交回的样子再定要不要找回来) ──
##   旧版这里还钉着三句用户原话, 量的是链式模拟 / 惯性弹簧的行为:
##     · 2026-08-20 句7「拍击时触手没有很柔软的弯曲…要像鞭子一样柔软拍下去」→ 行波前沿从根跑到梢
##     · 2026-08-21「抬起的时候你没有柔软感」→ 抬起期不定格(新版在 verify_tentacle_rhythm ① 量整条位移, 仍守)
##     · 2026-08-22「抬起到最高处时由于惯性触手的头部会向后弯…拍下来由于惯性头部会怎么样」→ 惯性滞后 / 甩尾过冲
##   10-31 重做按方案书 §7 去掉了链式模拟与惯性弹簧(它们是「抽搐」的嫌疑之一), 姿态改成 (状态, 计时) 的纯函数,
##   砸下压到 0.07 秒(1~4 帧, 参考共同规律 3)。这三条在新做法里没有对应的机制, 硬留判据只会是空判据或永远红。
##   ⇒ 不在这里假装还守着; 用户看成品时要专门问这三句还要不要(要的话是新一轮需求: 在姿态表里加滞后 / 过冲曲线)。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_tentacle_soft.tscn

const G := preload("res://tests/_tentacle_geo.gd")
const TV := preload("res://scripts/systems/equip/tentacle_vfx.gd")
## 拍击全程弧长允许的相对波动 —— 旧门禁的棘轮值(只降不升; 旧版实测 35.5%)
const ARC_TOL := 0.36
## 梢端落地口径: 走完全程落差的这个比例就算砸到了
const TOUCH_FRAC := 0.90
## 伤害结算与梢端真正落地之间允许的最大时差(秒)
const HIT_GAP_MAX := 0.05
## 判「回抬」的最小抬高(米): 着色器拿到的是姿态表算出来的点, 没有模拟噪声, 1 毫米就算
const RISE_EPS := 0.001

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


## 打一下(share), 从下令那一刻逐帧记 [状态, 梢端 y(相对根部), 最低点 y(相对根部), 弧长, 离下令的秒数], 直到回到待机
func _strike_rows(tv, mi: MeshInstance3D, share: float) -> Array:
	var rows: Array = []
	var root_y: float = mi.position.y
	tv.strike("left", 0, tv.root_pos("left", 0) + Vector2(380.0, 20.0), share)
	for i in range(400):
		G.step(tv)
		var pts := G.world_pts(mi)
		if pts.is_empty():
			continue
		var lo := 1.0e9
		for p in pts:
			lo = minf(lo, p.y)
		rows.append([int(tv.state_of("left", 0)), pts[pts.size() - 1].y - root_y, lo - root_y, G.arc(pts), float(i + 1) * G.SIM_DT])
		if int(tv.state_of("left", 0)) == 1 and i > 10:
			break
	return rows


## 拍击态(ST_SLAM)那一段里, 梢端过了下落半程之后的回抬次数与最大回抬
func _late_rise(rows: Array) -> Array:
	var ys: Array = []
	for r in rows:
		if int(r[0]) == 3:
			ys.append(float(r[1]))
	if ys.size() < 4:
		return [-1, 0.0, ys.size()]
	var hi: float = ys.max()
	var lo: float = ys.min()
	var half: float = hi - (hi - lo) * 0.5
	var cross := -1
	for k in range(ys.size()):
		if float(ys[k]) <= half and k > ys.find(hi):
			cross = k
			break
	var late := 0
	var worst := 0.0
	if cross >= 0:
		for k2 in range(cross + 1, ys.size()):
			var d: float = float(ys[k2]) - float(ys[k2 - 1])
			if d > RISE_EPS:
				late += 1
				worst = maxf(worst, d)
	return [late if cross >= 0 else -1, worst, ys.size()]


func _ready() -> void:
	await get_tree().process_frame
	var scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn)
	await get_tree().process_frame
	print("=== 触手拍下去: 不拍两次 / 不扎地 / 不戳出去 / 落地即伤害 ===")
	var tv = scn._tentacle_vfx
	_ok("★分母: tentacle_vfx 在场", tv != null)
	if tv == null:
		_done(scn)
		return
	tv.clear()
	tv.ensure_forced("left", 1)
	G.until_state(tv, "left", 0, 1, 2000)
	G.step(tv, 40)
	var mi := G.node_of(tv, "left", 0)
	_ok("★分母: 触手已出土并待机、节点在", int(tv.state_of("left", 0)) == 1 and mi != null, "state=%d" % int(tv.state_of("left", 0)))
	if mi == null:
		_done(scn)
		return

	## ── 正常拍击 ──
	var rows := _strike_rows(tv, mi, 1.0)
	var slam_n := 0
	var arc_lo := 1.0e9
	var arc_hi := 0.0
	var under := 0
	var under_deep := 0.0
	var y_hi := -1.0e9
	var y_lo := 1.0e9
	for r in rows:
		if int(r[0]) == 3:
			slam_n += 1
			arc_lo = minf(arc_lo, float(r[3]))
			arc_hi = maxf(arc_hi, float(r[3]))
			y_hi = maxf(y_hi, float(r[1]))
			y_lo = minf(y_lo, float(r[1]))
		if int(r[0]) == 3 or int(r[0]) == 4:
			if float(r[2]) < -0.02:
				under += 1
				under_deep = maxf(under_deep, -float(r[2]))
	_ok("★分母: 采到拍击态 %d 帧(= 0.5 秒)" % slam_n, slam_n >= 28)

	var lr: Array = _late_rise(rows)
	print("     梢端 %.2f → %.2f 米 · 过半程之后回抬 %d 次(最大 %.4f 米)" % [y_hi, y_lo, int(lr[0]), float(lr[1])])
	_ok("★分母: 梢端真的过了下落半程", int(lr[0]) >= 0)
	_ok("★★★① 梢端过了下落半程之后再不许回抬(= 不许拍两次)", int(lr[0]) == 0, "回抬 %d 次, 最大 %.4f" % [int(lr[0]), float(lr[1])])

	print("     拍击 / 收回期 有 %d 帧有点在地面以下, 最深 %.3f 米" % [under, under_deep])
	_ok("★★② 没有任何一段扎进地面以下(拍击 + 收回全程)", under == 0, "%d 帧, 最深 %.3f" % [under, under_deep])

	print("     拍击期弧长 %.2f ~ %.2f 米(攻击长度 %.1f, 差 %.1f%%)" % [arc_lo, arc_hi, TV.ATTACK_LEN, (arc_hi - arc_lo) / maxf(arc_lo, 0.01) * 100.0])
	_ok("★★③ 拍击全程弧长恒定(波动 ≤ %.0f%%) —— 不许「戳出去」, 也不许缩回去" % (ARC_TOL * 100.0),
		arc_hi > 1.0 and arc_hi - arc_lo <= arc_lo * ARC_TOL, "%.2f ~ %.2f" % [arc_lo, arc_hi])

	## ④ 真落地时刻(梢端走完 90% 落差) vs 伤害时刻
	## ★落地时刻在两帧之间线性插出来(旧门禁按 1/120 秒采样; 这里按真实 sim 步 1/60 秒走, 不插的话会多算最多一帧)
	var t_geo := -1.0
	var passed_hi := false
	var thr: float = y_hi - (y_hi - y_lo) * TOUCH_FRAC
	var prev_r: Array = []
	for r2 in rows:
		if int(r2[0]) != 3:
			continue
		if float(r2[1]) >= y_hi - 1.0e-6:
			passed_hi = true
		if passed_hi and float(r2[1]) <= thr:
			t_geo = float(r2[4])
			if not prev_r.is_empty() and float(prev_r[1]) > thr:
				var y0: float = float(prev_r[1])
				var y1: float = float(r2[1])
				t_geo = float(prev_r[4]) + (y0 - thr) / maxf(y0 - y1, 1.0e-6) * G.SIM_DT
			break
		prev_r = r2
	var t_hit: float = float(TV.hit_delay(1.0))
	print("     梢端真正落地 %.3f 秒 / 伤害结算 %.3f 秒(差 %.3f)" % [t_geo, t_hit, absf(t_geo - t_hit)])
	_ok("★★④ 落地那一刻就是伤害那一刻(差 ≤ %.2f 秒)" % HIT_GAP_MAX, t_geo > 0.0 and absf(t_geo - t_hit) <= HIT_GAP_MAX)

	## ── ⑤ 点刺 ──
	G.until_state(tv, "left", 0, 1, 300)
	var rj := _strike_rows(tv, mi, 0.25)
	var lj: Array = _late_rise(rj)
	var under_j := 0
	for r3 in rj:
		if (int(r3[0]) == 3 or int(r3[0]) == 4) and float(r3[2]) < -0.02:
			under_j += 1
	print("     点刺: 拍击态 %d 帧 · 过半程之后回抬 %d 次 · 地下 %d 帧" % [int(lj[2]), int(lj[0]), under_j])
	## 点刺(贴地扫出去)不一定有「落下过半程」这一段(-1 = 没有) —— 那就只守不扎地
	_ok("★⑤ 点刺也不回抬、不扎地", int(lj[2]) >= 10 and int(lj[0]) <= 0 and under_j == 0, "回抬 %d(-1 = 没有下落段) / 地下 %d" % [int(lj[0]), under_j])
	_done(scn)


func _done(scn) -> void:
	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 触手拍下去不拍两次 / 不扎地 / 不戳出去 / 落地即伤害" if _fail == 0 else "FAIL")
	if scn != null:
		scn.queue_free()
	get_tree().quit(0 if _fail == 0 else 1)
