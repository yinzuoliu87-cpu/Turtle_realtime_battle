extends Node
## _probe_tentacle_lol_metrics.gd — 「我们 vs LoL」动作对照表的「我们」那一列 + 三条手感(探针, 不进门禁)。
## 一根触手: 出土 → 长待机(6 秒, 量周期 / 幅度) → 正常拍击 → 回待机。逐帧(1/60)记中心线(根部相对坐标, 37 点)。
## 打: 待机梢端摆动主周期与幅度(占触手高) · 抬起用时与最高点 · 砸下(梢端从 90% 高度到贴地)帧数与逐帧下落量 ·
##     贴地后趴地时长 · 起身用时 · 三条手感(拍下 S 形 / 抬起梢端滞后 / 到顶与落地后梢端甩过头再回)。
## 跑法: bash godot-quiet.sh res://tests/probes/_probe_tentacle_lol_metrics.tscn --quit-after 20000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const TV := preload("res://scripts/systems/equip/tentacle_vfx.gd")

var _s


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
	var aim := r0 + Vector2(1.0, 0.0) * 320.0
	var C: Array = []
	var S: Array = []
	var dt := 1.0 / 60.0
	for f in range(1100):
		_s._t += dt
		if f == 600:
			tv.strike("left", 0, aim, 1.0)
		tv.tick(dt)
		var t: Dictionary = tv._tents["left|0"]
		var r3: Vector3 = t["root3"]
		var c := PackedVector3Array()
		for q in (t["center"] as PackedVector3Array):
			c.append(q - r3)
		C.append(c)
		S.append([int(t["state"]), float(t["ts"]), bool(t.get("hit", false))])
	## ── 待机(出土后 1~6 秒): 梢端高度的主周期 / 摆幅 ──
	var ys := PackedFloat32Array()
	var hmax := 0.0
	var tipx := PackedFloat32Array()
	for i in range(C.size()):
		if int(S[i][0]) == 1 and i > 180 and i < 600:
			var c: PackedVector3Array = C[i]
			ys.append(c[36].y)
			tipx.append(c[36].x)
			for p in c:
				hmax = maxf(hmax, p.y)
	var mean := 0.0
	for v in ys:
		mean += v
	mean /= maxf(1.0, float(ys.size()))
	var cross := 0
	var amp := 0.0
	for i in range(1, ys.size()):
		if (ys[i - 1] - mean) * (ys[i] - mean) < 0.0:
			cross += 1
		amp = maxf(amp, absf(ys[i] - mean))
	var ampx := 0.0
	var mx := 0.0
	for v in tipx:
		mx += v
	mx /= maxf(1.0, float(tipx.size()))
	for v in tipx:
		ampx = maxf(ampx, absf(v - mx))
	var secs: float = float(ys.size()) / 60.0
	print("[lol] 待机: 高 %.2f m · 梢端上下摆 ±%.2f m、前后摆 ±%.2f m(占高 %.0f%%) · 过均值 %d 次 / %.1f 秒 ⇒ 周期约 %.2f 秒" % [
		hmax, amp, ampx, 100.0 * maxf(amp, ampx) / maxf(hmax, 0.01), cross, secs, 2.0 * secs / maxf(1.0, float(cross))])
	## ── 抬起: 预警 + 前摇期间, 中心线最高点到达 95% 的时刻 ──
	var i_warn := -1
	var i_slam := -1
	var i_touch := -1
	var i_rec := -1
	var i_idle2 := -1
	for i in range(600, C.size()):
		var st: int = int(S[i][0])
		if i_warn < 0 and st == 6:
			i_warn = i
		if i_slam < 0 and st == 3:
			i_slam = i
		if i_touch < 0 and st == 3 and bool(S[i][2]):
			i_touch = i
		if i_rec < 0 and st == 4:
			i_rec = i
		if i_rec > 0 and i_idle2 < 0 and st == 1:
			i_idle2 = i
	var top := 0.0
	var i_top := i_warn
	for i in range(i_warn, i_slam):
		for p in (C[i] as PackedVector3Array):
			if p.y > top:
				top = p.y
				i_top = i
	var i_95 := i_top
	for i in range(i_warn, i_slam):
		var hh := 0.0
		for p in (C[i] as PackedVector3Array):
			hh = maxf(hh, p.y)
		if hh >= 0.95 * top:
			i_95 = i
			break
	print("[lol] 抬起: 预警起点 → 到最高点 95%% 用 %.2f 秒(%d 帧) · 最高点 %.2f m(待机高的 %.1f 倍) · 预警起点 → 贴地 %.2f 秒" % [
		float(i_95 - i_warn) / 60.0, i_95 - i_warn, top, top / maxf(hmax, 0.01), float(i_touch - i_warn) / 60.0])
	## ── 砸下: 梢端从拍击期最高点 → 贴地, 逐帧下落量 ──
	var tip_top := -1.0
	var i_tt := i_slam
	for i in range(i_slam - 8, i_touch + 1):
		var y: float = (C[i] as PackedVector3Array)[36].y
		if y > tip_top:
			tip_top = y
			i_tt = i
	var i_land := i_touch
	for i in range(i_tt, i_rec):
		if (C[i] as PackedVector3Array)[36].y <= 0.6:
			i_land = i
			break
	var drops := ""
	for i in range(i_tt + 1, mini(i_land + 1, i_tt + 30)):
		drops += "%.2f " % ((C[i - 1] as PackedVector3Array)[36].y - (C[i] as PackedVector3Array)[36].y)
	var i_90 := i_tt
	for i in range(i_tt, i_land + 1):
		if (C[i] as PackedVector3Array)[36].y <= tip_top * 0.9:
			i_90 = i - 1
			break
	print("[lol] 砸下: 梢端最高 %.2f m(拍击 ts=%.3f) → 贴地(≤0.6 m, ts=%.3f): %d 帧 · 从 90%% 高度起 %d 帧 · 命中(伤害)帧 = 第 %d 帧(ts=%.3f) · 逐帧下落 m: %s" % [
		tip_top, float(S[i_tt][1]), float(S[i_land][1]), i_land - i_tt, i_land - i_90, i_touch, float(S[i_touch][1]), drops])
	## ── 趴地与起身 ──
	var i_up := -1
	for i in range(i_land, C.size()):
		if (C[i] as PackedVector3Array)[36].y > 1.0:
			i_up = i
			break
	var i_back := -1
	for i in range(i_rec, C.size()):
		var d := 0.0
		var c1: PackedVector3Array = C[i]
		var c2: PackedVector3Array = C[mini(i + 1, C.size() - 1)]
		for k in range(c1.size()):
			d = maxf(d, c1[k].distance_to(c2[k]))
		if int(S[i][0]) == 1 and d < 0.02:
			i_back = i
			break
	print("[lol] 趴地: 贴地 → 梢端离地 >1 m 用 %.2f 秒 · 起身: 收回起点 → 回到待机且逐帧位移 <2 cm 用 %.2f 秒" % [
		float(i_up - i_land) / 60.0, float(i_back - i_rec) / 60.0])
	## ── 三条手感 ──
	## ① 拍下柔软(像鞭子): 下砸期中心线曲率变号次数(S 形 = 有行波) 的最大值
	var smax := 0
	for i in range(i_slam, i_touch + 1):
		var c3: PackedVector3Array = C[i]
		var last := 0.0
		var ch := 0
		for k in range(1, c3.size() - 1):
			var a: Vector3 = c3[k] - c3[k - 1]
			var b: Vector3 = c3[k + 1] - c3[k]
			var cr: float = a.cross(b).dot(Vector3(0, 0, 1))
			if absf(cr) < 0.0005:
				continue
			if last != 0.0 and signf(cr) != signf(last):
				ch += 1
			last = cr
		smax = maxi(smax, ch)
	## ② 抬起柔软(梢端滞后): 预警期梢端相对根段的「方向滞后」—— 根段(0→6)仰角先到, 梢段(30→36)晚到; 取两者到达各自 80% 的时间差
	var ang_root := PackedFloat32Array()
	var ang_tip := PackedFloat32Array()
	for i in range(i_warn, i_slam):
		var c4: PackedVector3Array = C[i]
		ang_root.append(rad_to_deg(atan2((c4[6] - c4[0]).y, (c4[6] - c4[0]).x)))
		ang_tip.append(rad_to_deg(atan2((c4[36] - c4[30]).y, (c4[36] - c4[30]).x)))
	var t_r := -1
	var t_t := -1
	for i in range(ang_root.size()):
		if t_r < 0 and ang_root[i] - ang_root[0] >= 0.8 * (ang_root[ang_root.size() - 1] - ang_root[0]):
			t_r = i
		if t_t < 0 and absf(ang_tip[i] - ang_tip[0]) >= 0.8 * absf(ang_tip[ang_tip.size() - 1] - ang_tip[0]):
			t_t = i
	## ③ 惯性甩尾: 落地后梢端在地上 / 空中「冲过最终位置再回来」的距离(拍击末与收回前 0.1 秒内梢端位移的反向段)
	var over := 0.0
	var i_end: int = mini(i_rec + 6, C.size() - 1)
	var fin: Vector3 = (C[i_end] as PackedVector3Array)[36]
	for i in range(i_touch, i_end):
		var pz: Vector3 = (C[i] as PackedVector3Array)[36]
		over = maxf(over, (pz - fin).dot(Vector3(1, 0, 0)))
	print("[lol] 手感①拍下柔软: 下砸期中心线曲率最多变号 %d 次(≥1 = S 形行波) · ②抬起柔软: 根段 80%% 到位第 %d 帧, 梢段第 %d 帧(梢晚 %d 帧) · ③甩尾: 落地后梢端冲过最终位置 %.2f m 再回来" % [
		smax, t_r, t_t, t_t - t_r, over])
	get_tree().quit(0)
