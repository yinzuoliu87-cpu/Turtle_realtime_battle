extends Node
## verify_basic_slam.gd —— 小龟·过肩摔重做(方案书 docs/plans/20261024-过肩摔重做.md §6)。
##
## 用户 2026-10-24「当敌人进入范围，释放过肩刷，应该是小龟加速冲向目标，抱起目标，开一个跳高最后落地，
##   跳高的时候还应该稍微往小龟背后动一点吧，整个特效需要重做，上面的bug也必须修完」;「400吧」。
## 走真入口 `_basic_slam_sys._sk_basic_slam`(= `_do_skill` 的 "basicSlam"), 每个 sim 步量一次。
##
##   A 放技距离 400(主文件放技射程表 = 常量 = 400)
##   B 冲刺: 由慢到快(末速 ≥ 起速 2.5 倍), 真的冲到目标身边才抱
##   C 跳高: 小龟最高 ≈ SLAM_APEX_H; 目标越过头顶(更高)且倒过来; 上升步数 > 下砸步数(上升慢、下砸快)
##   D 整体往小龟背后移 SLAM_DRIFT_BACK; 目标落在小龟背后 SLAM_LAND_BACK; 全程无瞬移
##   E 伤害: 公式对; 两段都过护甲(体检 B1: 100 护甲 / 虚化的比值 = 护甲乘数 / 0.1)
##   F 溅射圆心 = 落点(B5): 主目标半空被打死, 离落点 340 码的挨打、尸体旁边但离落点 > 350 的不挨
##   G 抱不起来(B2): 免控 / 免击飞 / 龙蛋 ⇒ 不挪、不腾空、原地砸; 免击飞照晕, 免控与蛋不晕
##   H no_move 不被改(B3)
##   I 小龟半空阵亡(B4) ⇒ 不结算: 目标不掉血、旁人不掉血、目标复位、锁解开
##   J 双摔(B6): 第二只不抓、原地砸; 第一只落地前目标的锁不被第二只解开
##   K 追不上作废; 顿帧期间演出停住(B7)
##   L 落地: 贴地伤害圈(躺平 + 外径 = 350); 血条 / 影子跟着腾空的身体走(B7)
##   M 结束后不残留: 两边 `_slam` / 偏移 / 倒立都复位

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BC := preload("res://scripts/gamedata/basic_consts.gd")
const SYS := preload("res://scripts/systems/skills/basic_slam_system.gd")

var s
var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _mk(id: String, side: String, pos: Vector2, hp: float, atk: float = 100.0) -> Dictionary:
	var u: Dictionary = s._spawn._make_unit(id, side, pos)
	u["maxHp"] = hp; u["hp"] = hp; u["shield"] = 0.0; u["flat_dr"] = 0.0
	u["def"] = 0.0; u["mr"] = 0.0; u["base_def"] = 0.0; u["base_mr"] = 0.0
	u["dodge_bonus"] = 0.0; u["damage_reduction"] = 0.0; u["damage_amp"] = 0.0
	u["crit"] = 0.0; u["crit_dmg"] = 1.5; u["buffs"] = []; u["equips"] = []; u["eq_state"] = {}
	u["atk"] = atk; u["active_skills"] = []; u["no_basic"] = true
	s._units.append(u)
	return u


## 一步 sim(与 `_advance_sim_accum` 同样地取 frozen / 时停)。
func _step() -> void:
	s._sim_step(s.SIM_DT, s._hitstop > 0.0, not s._timestop._ts_active.is_empty())


## 放一次, 逐步记录, 直到小龟解锁(或 600 步)。hook(n) 每步前调。
func _cast(b: Dictionary, t: Dictionary, hook: Callable = Callable()) -> Dictionary:
	var rec := {"upos": [], "tpos": [], "uh": [], "th": [], "phase": [], "flip": false}
	s._basic_slam_sys._sk_basic_slam(b, t)
	var n := 0
	while n < 600 and bool(b.get("_slam", false)):
		if hook.is_valid():
			hook.call(n)
		_step()
		n += 1
		(rec["upos"] as Array).append(b["pos"])
		(rec["tpos"] as Array).append(t["pos"])
		(rec["uh"] as Array).append(float((b.get("_slam_voff", Vector3.ZERO) as Vector3).y))
		(rec["th"] as Array).append(float((t.get("_slam_voff", Vector3.ZERO) as Vector3).y))
		(rec["phase"] as Array).append(str(s._basic_slam_sys.last_phase))
		var sp = t.get("sprite", null)
		if is_instance_valid(sp) and (sp as Sprite3D).flip_v:
			rec["flip"] = true
	rec["steps"] = n
	return rec


func _first(rec: Dictionary, ph: String) -> int:
	return (rec["phase"] as Array).find(ph)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	RB.DEBUG_EDIT = true
	s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s.set_process(false)
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	print("=== 小龟 · 过肩摔(重做) ===")

	# ── A ──
	_ok("A 放技距离 400 = 主文件放技射程表 = 常量", is_equal_approx(BC.SLAM_CAST_RANGE, 400.0)
		and is_equal_approx(float(s._SKILL_CAST_RANGE.get("basicSlam", -1.0)), BC.SLAM_CAST_RANGE),
		"表 %s / 常量 %s" % [str(s._SKILL_CAST_RANGE.get("basicSlam")), str(BC.SLAM_CAST_RANGE)])

	# ── B/C/D/E 基本一摔(目标在 330 码, 两个旁人在它附近) ──
	s._units.clear()
	var b := _mk("basic", "left", c - Vector2(165, 0), 99999.0)
	var t := _mk("stone", "right", c + Vector2(165, 0), 5000.0)
	var r := _cast(b, t)
	var ig: int = _first(r, "grab")
	var ij: int = _first(r, "jump")
	var il: int = _first(r, "land")
	_ok("分母 · 走完了冲刺 → 抱起 → 跳高 → 落地(%d 步)" % int(r["steps"]), ig > 2 and ij > ig and il > ij, "grab@%d jump@%d land@%d" % [ig, ij, il])
	var up: Array = r["upos"]
	if ig > 3:
		var v_first: float = (up[1] as Vector2).distance_to(up[0]) / s.SIM_DT
		var v_last: float = (up[ig - 1] as Vector2).distance_to(up[ig - 2]) / s.SIM_DT
		_ok("★B 冲刺由慢到快(末速 ≥ 起速 2.5 倍)", v_last >= v_first * 2.5, "起 %.0f → 末 %.0f 码/秒" % [v_first, v_last])
		_ok("★B 真的冲到目标身边才抱(抱住那一刻距离 ≤ %.0f)" % BC.SLAM_GRAB_DIST,
			(up[ig - 1] as Vector2).distance_to(c + Vector2(165, 0)) <= BC.SLAM_GRAB_DIST + 1.0,
			"%.1f 码" % (up[ig - 1] as Vector2).distance_to(c + Vector2(165, 0)))
	var uh: Array = r["uh"]
	var th: Array = r["th"]
	var umax: float = 0.0
	var imax := 0
	for i in range(uh.size()):
		if float(uh[i]) > umax:
			umax = float(uh[i]); imax = i
	var tmaxh: float = 0.0
	for x in th:
		tmaxh = maxf(tmaxh, float(x))
	_ok("★C 小龟跳到 ≈ %.1f 米" % BC.SLAM_APEX_H, absf(umax - BC.SLAM_APEX_H) <= 0.12, "%.2f" % umax)
	_ok("★C 目标越过小龟头顶(比小龟高 ≥ 0.8 米)且倒过来", tmaxh >= umax + 0.8 and bool(r["flip"]), "目标 %.2f / 小龟 %.2f / 倒立 %s" % [tmaxh, umax, str(r["flip"])])
	_ok("★C 上升慢、下砸快(上升步数 > 下砸步数)", ij >= 0 and (imax - ij) > (il - imax), "上升 %d 步 / 下砸 %d 步" % [imax - ij, il - imax])
	var gpos: Vector2 = up[maxi(0, ig - 1)]
	var dir: Vector2 = ((c + Vector2(165, 0)) - gpos).normalized()
	var u_end: Vector2 = b["pos"]
	var t_end: Vector2 = t["pos"]
	_ok("★D 跳高整体往小龟背后移 %.0f 码" % BC.SLAM_DRIFT_BACK, absf((gpos - u_end).dot(dir) - BC.SLAM_DRIFT_BACK) <= 4.0,
		"%.1f 码" % (gpos - u_end).dot(dir))
	_ok("★D 目标落在小龟背后 %.0f 码" % BC.SLAM_LAND_BACK, absf((u_end - t_end).dot(dir) - BC.SLAM_LAND_BACK) <= 4.0,
		"%.1f 码" % (u_end - t_end).dot(dir))
	var jump_u := 0.0
	var jump_t := 0.0
	for i in range(maxi(1, ig), mini(up.size(), il + 1)):
		jump_u = maxf(jump_u, (up[i] as Vector2).distance_to(up[i - 1]))
		jump_t = maxf(jump_t, ((r["tpos"] as Array)[i] as Vector2).distance_to((r["tpos"] as Array)[i - 1]))
	_ok("★D 抱起之后全程无瞬移(小龟每步 ≤ 8 码、目标每步 ≤ 16 码)", jump_u <= 8.0 and jump_t <= 16.0, "小龟 %.1f / 目标 %.1f" % [jump_u, jump_t])
	_ok("D 落地眩晕 %.1f 秒" % BC.SLAM_STUN_SEC, absf(float(t.get("stun_until", 0.0)) - s._t - BC.SLAM_STUN_SEC) <= 0.12,
		"剩 %.2f" % (float(t.get("stun_until", 0.0)) - s._t))
	_ok("★M 结束后两边都解锁、偏移归零、不倒立", not b.get("_slam", false) and not t.get("_slam", false)
		and (b.get("_slam_voff", Vector3.ZERO) as Vector3) == Vector3.ZERO and (t.get("_slam_voff", Vector3.ZERO) as Vector3) == Vector3.ZERO
		and not (t["sprite"] as Sprite3D).flip_v)
	# L 落地特效: 贴地伤害圈外径 = 350
	var land: Vector2 = s._basic_slam_sys.last_land
	var ring_r := -1.0
	var flat := false
	for nd in s._world.get_children():
		if nd is Sprite3D and (nd as Sprite3D).has_meta("ring_target_ps"):
			var sp3: Sprite3D = nd
			var rr: float = float(sp3.get_meta("ring_target_ps")) * s.RING_CELL_PX * (s.RING_LAST_R_PX / (s.RING_CELL_PX * 0.5)) / (2.0 * s.WS)
			var at: Vector3 = s._world_pos(land, 0.05)
			if absf(rr - BC.SLAM_SPLASH_RADIUS) < 1.0 and Vector2(sp3.position.x - at.x, sp3.position.z - at.z).length() < 0.05:
				ring_r = rr
				flat = sp3.billboard == BaseMaterial3D.BILLBOARD_DISABLED and sp3.axis == Vector3.AXIS_Y
	_ok("★L 落点有一圈贴地(躺平)的伤害圈, 外径 = %.0f 码" % BC.SLAM_SPLASH_RADIUS, ring_r > 0.0 and flat, "外径 %.1f 躺平 %s" % [ring_r, str(flat)])

	# ── E 护甲 / 虚化(B1) ──
	var dmg := {}
	for case in [["def0", 0.0, false], ["def100", 100.0, false], ["phase", 0.0, true]]:
		s._units.clear()
		var b2 := _mk("basic", "left", c - Vector2(40, 0), 99999.0)
		var t2 := _mk("stone", "right", c + Vector2(40, 0), 5000.0)
		t2["def"] = float(case[1])
		if bool(case[2]):
			t2["phase_until"] = s._t + 100.0
		_cast(b2, t2)
		dmg[str(case[0])] = 5000.0 - float(t2["hp"])
	var mult: float = DamageMath.resist_multiplier(DamageMath.effective_resist(100.0, 0.0, 0.0))
	var r100: float = float(dmg["def100"]) / maxf(1.0, float(dmg["def0"]))
	var rph: float = float(dmg["phase"]) / maxf(1.0, float(dmg["def0"]))
	_ok("分母 · 0 护甲主目标掉血 = 公式(1.0A + 0.2%×ATK×5000, 含小龟被动增伤)", float(dmg["def0"]) >= 100.0 + 1000.0 - 1.0, "%.0f" % float(dmg["def0"]))
	_ok("★E 100 护甲: 整笔伤害按护甲乘数缩(两段都过护甲)", absf(r100 - mult) <= 0.03, "比值 %.3f / 护甲乘数 %.3f" % [r100, mult])
	_ok("★E 虚化: 整笔伤害 × 0.1", absf(rph - GhostSystem.PHASE_MULT) <= 0.02, "比值 %.3f" % rph)

	# ── F 溅射圆心 = 落点(主目标半空被打死) ──
	s._units.clear()
	var b3 := _mk("basic", "left", c - Vector2(40, 0), 99999.0)
	var t3 := _mk("stone", "right", c + Vector2(40, 0), 5000.0)
	## 预测落点: 抱住时小龟在 c-40(离目标 80 > 60 ⇒ 先冲一点) —— 跑一遍记下来再造旁人太绕; 直接在 hook 里等落点定下来
	var spl: Array = []          # [near, far] —— ★闭包里改不了外面的局部变量, 用数组装(第一版就是这么静默跳过的)
	var killed := [false]
	var r3 := _cast(b3, t3, func(n: int) -> void:
		if str(s._basic_slam_sys.last_phase) == "jump" and not killed[0]:
			killed[0] = true
			s._damage._apply_damage(t3, 99999, Color.RED)
			## 跳高刚开始: 落点 = 抱住点往后 DRIFT + LAND_BACK
			var g: Vector2 = b3["pos"]
			var d3: Vector2 = (t3["pos"] - g).normalized() if (t3["pos"] - g).length() > 1.0 else Vector2.RIGHT
			var land3: Vector2 = g - d3 * (BC.SLAM_DRIFT_BACK + BC.SLAM_LAND_BACK)
			spl.append(_mk("stone", "right", land3 + Vector2(0, 340), 5000.0))
			spl.append(_mk("stone", "right", (t3["pos"] as Vector2) + (t3["pos"] - land3).normalized() * 260.0, 5000.0)))
	_ok("分母 · 主目标半空被打死了、小龟照常落地", killed[0] and not t3.get("alive", true) and str(s._basic_slam_sys.last_phase) == "land")
	_ok("★F 结算圆心 = 落点", s._basic_slam_sys.last_center.distance_to(s._basic_slam_sys.last_land) < 1.0,
		"圆心 %s 落点 %s" % [str(s._basic_slam_sys.last_center), str(s._basic_slam_sys.last_land)])
	_ok("分母 · 两个旁人造出来了", spl.size() == 2)
	if spl.size() == 2:
		var near: Dictionary = spl[0]
		var far: Dictionary = spl[1]
		var far_d: float = (far["pos"] as Vector2).distance_to(s._basic_slam_sys.last_land)
		var far_c: float = (far["pos"] as Vector2).distance_to(t3["pos"])
		_ok("分母 · 尸体旁那个: 离尸体 ≤ 350(按尸体算会挨打)、离落点 > 350", far_c <= 350.0 and far_d > 350.0, "离尸体 %.0f 离落点 %.0f" % [far_c, far_d])
		_ok("★F 离落点 340 码的挨打、尸体旁但离落点 > 350 码的不挨",
			float(near["hp"]) < 5000.0 and float(far["hp"]) >= 5000.0,
			"near %.0f far %.0f" % [float(near["hp"]), float(far["hp"])])

	# ── G 抱不起来 ──
	for case in [["免控", "cc"], ["免击飞(017)", "knock"], ["龙蛋", "egg"]]:
		s._units.clear()
		var b4 := _mk("basic", "left", c - Vector2(40, 0), 99999.0)
		var t4 := _mk("stone", "right", c + Vector2(40, 0), 5000.0)
		match str(case[1]):
			"cc":
				t4["cc_immune_until"] = s._t + 100.0
			"knock":
				t4["_knock_immune"] = true
			"egg":
				t4["_eggImmune"] = true
		var p0: Vector2 = t4["pos"]
		var r4 := _cast(b4, t4)
		var tmh: float = 0.0
		for x in (r4["th"] as Array):
			tmh = maxf(tmh, float(x))
		var stunned: bool = float(t4.get("stun_until", 0.0)) > s._t
		var want_stun: bool = str(case[1]) == "knock"
		_ok("★G %s: 不挪、不腾空、原地砸(掉血), 眩晕 = %s" % [str(case[0]), "晕" if want_stun else "不晕"],
			(t4["pos"] as Vector2).distance_to(p0) < 1.0 and tmh == 0.0 and float(t4["hp"]) < 5000.0
				and stunned == want_stun and str(s._basic_slam_sys.last_phase) == "hop_land",
			"挪 %.1f 腾空 %.2f 掉 %.0f 晕 %s 段 %s" % [(t4["pos"] as Vector2).distance_to(p0), tmh, 5000.0 - float(t4["hp"]), str(stunned), str(s._basic_slam_sys.last_phase)])

	# ── G2 正被击飞在半空的目标: 照样抱(用户要「抱起目标」), 落地后击飞状态干净 ──
	s._units.clear()
	var bq := _mk("basic", "left", c - Vector2(40, 0), 99999.0)
	var tq := _mk("stone", "right", c + Vector2(40, 0), 5000.0)
	tq["airborne"] = true
	tq["height"] = 1.5
	tq["vy"] = 2.0
	var rq := _cast(bq, tq)
	var qh: float = 0.0
	for x in (rq["th"] as Array):
		qh = maxf(qh, float(x))
	_ok("★G2 半空中的目标照样被抱起摔下(不是原地砸)", (rq["phase"] as Array).has("jump") and qh >= BC.SLAM_APEX_H,
		"最高 %.2f 段 %s" % [qh, str(s._basic_slam_sys.last_phase)])
	_ok("★G2 落地后不再是击飞态、高度归零、掉血 + 眩晕", not tq.get("airborne", false) and float(tq.get("height", 0.0)) == 0.0
		and float(tq["hp"]) < 5000.0 and float(tq.get("stun_until", 0.0)) > s._t)

	# ── H no_move ──
	s._units.clear()
	var b5 := _mk("basic", "left", c - Vector2(40, 0), 99999.0)
	var t5 := _mk("stone", "right", c + Vector2(40, 0), 5000.0)
	t5["no_move"] = true
	_cast(b5, t5)
	_ok("★H 目标原本 no_move ⇒ 摔完还是 no_move", bool(t5.get("no_move", false)))

	# ── I 小龟半空阵亡 ──
	s._units.clear()
	var b6 := _mk("basic", "left", c - Vector2(40, 0), 99999.0)
	var t6 := _mk("stone", "right", c + Vector2(40, 0), 5000.0)
	var o6 := _mk("stone", "right", c + Vector2(-80, 120), 5000.0)
	var dead := [false]
	_cast(b6, t6, func(n: int) -> void:
		if str(s._basic_slam_sys.last_phase) == "jump" and not dead[0]:
			dead[0] = true
			s._damage._apply_damage(b6, 999999, Color.RED))
	for _i in range(30):
		_step()
	_ok("分母 · 小龟在跳高途中被打死", dead[0] and not b6.get("alive", true))
	_ok("★I 不结算: 目标与旁人都不掉血、目标不晕", float(t6["hp"]) >= 5000.0 and float(o6["hp"]) >= 5000.0
		and float(t6.get("stun_until", 0.0)) <= s._t, "目标 %.0f 旁人 %.0f" % [float(t6["hp"]), float(o6["hp"])])
	_ok("★I 目标复位: 偏移归零、不倒立、锁解开", (t6.get("_slam_voff", Vector3.ZERO) as Vector3) == Vector3.ZERO
		and not (t6["sprite"] as Sprite3D).flip_v and not t6.get("_slam", false))

	# ── J 双摔 ──
	s._units.clear()
	var b7 := _mk("basic", "left", c - Vector2(40, 0), 99999.0)
	var b8 := _mk("basic", "left", c - Vector2(40, 60), 99999.0)
	var t7 := _mk("stone", "right", c + Vector2(40, 0), 50000.0)
	var second := [false]
	var lock_broken := [false]
	var hopped := [false]
	var watch := func() -> void:
		## 对称判据: 只要目标还被抱在半空(偏移 > 0)且还有小龟在演出里, 它的锁就必须还在 —— 不管先结束的是哪一只
		var busy: bool = b7.get("_slam", false) or b8.get("_slam", false)
		if busy and float((t7.get("_slam_voff", Vector3.ZERO) as Vector3).y) > 0.0 and not t7.get("_slam", false):
			lock_broken[0] = true
		if str(s._basic_slam_sys.last_phase).begins_with("hop"):
			hopped[0] = true
	_cast(b7, t7, func(n: int) -> void:
		if str(s._basic_slam_sys.last_phase) == "jump" and not second[0]:
			second[0] = true
			s._basic_slam_sys._sk_basic_slam(b8, t7)
		watch.call())
	for _i in range(60):
		_step()
		watch.call()
	_ok("分母 · 第一只跳高时第二只也放了", second[0])
	_ok("★J 第二只不抓已在别的演出里的目标(走原地砸)", hopped[0])
	_ok("★J 目标被抱在半空时锁一直在(不被先结束的那只解开)", not lock_broken[0])
	_ok("★J 都结束后锁全解开", not b7.get("_slam", false) and not b8.get("_slam", false) and not t7.get("_slam", false))

	# ── K 追不上作废 / 顿帧停住 ──
	s._units.clear()
	var b9 := _mk("basic", "left", s.ARENA.position + Vector2(60, s.ARENA.size.y * 0.5), 99999.0)
	var t9 := _mk("stone", "right", s.ARENA.end - Vector2(60, s.ARENA.size.y * 0.5), 5000.0)
	_cast(b9, t9)
	_ok("★K 1400+ 码外追不上 ⇒ 作废(不伤害、不晕、解锁)", str(s._basic_slam_sys.last_phase) == "dash_timeout"
		and float(t9["hp"]) >= 5000.0 and not b9.get("_slam", false), str(s._basic_slam_sys.last_phase))
	s._units.clear()
	var ba := _mk("basic", "left", c - Vector2(40, 0), 99999.0)
	var ta := _mk("stone", "right", c + Vector2(40, 0), 5000.0)
	var frozen_moved := [-1.0]
	var hs := [false]
	var held := [Vector2.ZERO, 0]
	_cast(ba, ta, func(n: int) -> void:
		if str(s._basic_slam_sys.last_phase) == "jump" and not hs[0]:
			hs[0] = true
			s._hitstop = 0.2
			held[0] = ta["pos"]
			held[1] = 0
		elif hs[0] and s._hitstop > 0.0:
			held[1] = int(held[1]) + 1
			frozen_moved[0] = maxf(frozen_moved[0], (ta["pos"] as Vector2).distance_to(held[0])))
	_ok("★K 顿帧期间演出停住(目标一码都不动)", hs[0] and int(held[1]) >= 5 and frozen_moved[0] < 0.01,
		"顿帧 %d 步, 期间挪了 %.2f" % [int(held[1]), frozen_moved[0]])

	# ── L 血条 / 影子跟着身体 ──
	s._units.clear()
	var bb := _mk("basic", "left", c, 99999.0)
	s._render._update_world_transforms()
	var sh0: float = (bb["shadow"] as Sprite3D).scale.x
	bb["_slam_voff"] = Vector3(0, 3.0, 0)
	s._render._update_world_transforms()
	var sh1: float = (bb["shadow"] as Sprite3D).scale.x
	_ok("★L 腾空 3 米影子缩小(≤ 一半)", sh1 <= sh0 * 0.5 + 1e-4, "%.3f → %.3f" % [sh0, sh1])
	var root = bb.get("bar_root", null)
	if is_instance_valid(root):
		bb["_slam_voff"] = Vector3.ZERO
		s._render._update_overlay()
		var y0: float = (root as Control).position.y
		bb["_slam_voff"] = Vector3(0, 3.0, 0)
		s._render._update_overlay()
		var y1: float = (root as Control).position.y
		_ok("★L 腾空 3 米血条跟着往上走", y1 < y0 - 10.0, "屏幕 y %.0f → %.0f" % [y0, y1])
	else:
		_ok("★L 分母 · 单位有血条节点", false)
	bb["_slam_voff"] = Vector3.ZERO

	RB.DEBUG_EDIT = false
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 小龟过肩摔重做" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit()
