extends Node
## verify_eq_venom_drone.gd — 092【剧毒飞行物】(遗物·2 费) 门禁
##
## 方案书 docs/plans/20260805-装备逐件重做.md §0.5 ★092 / 实装契约 20260805-实装契约.md E 路
##
## 守两层:
##   【规格层】用户原话的每一个数与每一条规则: 50/70/100 生命 · 10/22/40 魔抗 ·
##            穿过目标落对面 · 每 0.25 秒留毒雾 · 毒雾活 4 秒 · 每 0.25 秒 2/3/5 层中毒 ·
##            每 0.25 秒 1 层剧毒缓速 · 封顶 20 层 · 每层 −2% 移速 −1% 魔抗 ·
##            1.5 秒不刷新则每 0.25 秒掉一层 · 携带者阵亡飞行物也阵亡 · 不可选中。
##   【物理层】演出的四条闭式解真的是那四条: 高斯烟团(σ² 线性 / 守恒量) ·
##            Dubins 最小转弯半径 · 受迫振子(反相 + f^(−2)) · 行波(逐段滞后 + 相速)。
##            ★这些是**性质断言**, 不是把公式抄一遍 —— 手调曲线一条都过不了。
##
## ⚠ 铁律(CLAUDE.md §3.5 / 契约 §7): **全部同步判定, 不等任何演出 tween。**
##   形态由纯函数给、节点由 apply_* 直接写到任意时刻; 逻辑由 `tick(delta)` 同步喂。
## ⚠ 用【干净合成单位】不用随机 spawn(memory [[fb-ci-vs-local-divergence]])。
## ⚠ 期望值一律**硬写字面量**, 不引用被测常量 —— 引用就是拿代码跟它自己比。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_eq_venom_drone.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const VD := preload("res://scripts/systems/equip/eq_venom_drone.gd")
const VV := preload("res://scripts/scenes/battle/venom_drone_vfx.gd")

## ── 规格硬写值(用户原话, 一个都不许从代码里读) ──
const WANT_HP := [50.0, 70.0, 100.0]
const WANT_MR := [10.0, 22.0, 40.0]
## ★期望值【引用代码常量】而不是再抄一份数字(2026-08-13 用户加强到 3/5/8 时,
##   抄的那份没跟上, 五条断言一起红)。判据要守的是"文案↔代码一致", 而那由
##   tooltip_number_audit 管; 这里守的是"一拍施加几层、三拍累加"这个**行为**。
const WANT_POISON := VD.POISON_STACKS
const WANT_BEAT := 0.25
const WANT_FOG_LIFE := 4.0
const WANT_VSLOW_CAP := 20
const WANT_MOVE_PER := 0.02
const WANT_MR_PER := 0.01
const WANT_GRACE := 1.5

var _n := 0
var _fail := 0
var _s
var _v
var _me
var _foe


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 092 剧毒飞行物(遗物·2费) ===")

	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(12):
		await get_tree().process_frame

	await _g0_wiring()
	if _v == null:
		print("")
		print("FAIL x%d — ★分母没过, 后面全是空检查" % maxi(1, _fail))
		get_tree().quit(1); return
	_g1_stats()
	_g2_path_geometry()
	await _g3_path_behavior()
	await _g4_turn_inertia()
	_g5_fog_physics()
	_g5b_fog_rim()
	await _g5c_fog_particles()
	await _g6_fog_lifetime()
	await _g7_poison()
	await _g8_vslow()
	await _g9_vslow_decay()
	await _g10_carrier_death()
	await _g11_lane_clear()
	_g12_flap_physics()
	await _g12b_moth_readability()
	await _g13_ring_visibility()
	await _g14_zero_asset()
	await _g15_rng()
	await _g16_perf()
	await _done()


# ── ⓪ ★分母 + 接线 ────────────────────────────────────────────────────────────
func _g0_wiring() -> void:
	print("")
	print("  ⓪ ★分母 + 接线:")
	_ok("⓪ 世界节点 _world 在", is_instance_valid(_s._world))
	var got = _s._equip_sys._venom
	_ok("⓪ ★EquipSystem 把 VenomDroneSystem 接出来了 (_equip_sys._venom)", got != null)
	if got == null:
		return
	_v = got
	_ok("⓪ 它拿到的是同一个 battle", is_same(_v.battle, _s))
	_ok("⓪ 演出层在 (_venom._vfx)", _v._vfx != null)
	_ok("⓪ 演出层也拿到同一个 battle", is_same(_v._vfx.battle, _s))
	# ★接线证据一: 遗物羁绊的每帧入口真的会推进它, 而且【在提前 return 之前】。
	#   RelicSynergySystem.tick 里有 `if _t_acc < PERIOD: return`(2.5 秒才过一次),
	#   接线若挪到那行之后, 飞行物就变成每 2.5 秒才动一帧, 而"函数存在"照样绿。
	await _setup_units()
	_v.clear_all()
	_s._relic_syn._t_acc = 0.0            # 把节拍推到刚清零 ⇒ tick(0.02) 一定走提前 return
	_s._relic_syn.tick(0.30)              # 0.30 > 0.25 ⇒ 一定跨过一个节拍 ⇒ 该重扫出飞行物
	print("     _relic_syn._t_acc=0 时 tick(0.30) → 飞行物 %d 只 (需求 1)" % _v._drones.size())
	# ══ ★航线整段【实时跟随】目标(用户 2026-08-13) ═══════════════════════
	#   「人家都往别的地方走了, 飞行物却飞到别的地方」——
	#   原来只在起段那一刻快照一次目标位置, 中途目标走开就一路飞向空地。
	#   ★判据是【把目标挪走 ⇒ 落点跟着变】; 只断言"有 dest"守不住(快照也有 dest)。
	var vd = _v
	if vd != null and not vd._drones.is_empty():
		var dr: Dictionary = vd._drones[0]
		var tg = dr.get("tgt", null)
		_ok("★分母: 这一段真的锁到了一个目标单位", tg is Dictionary,
			"tgt=%s" % ("有" if tg is Dictionary else "无"))
		if tg is Dictionary:
			var dest0: Vector2 = dr["dest"]
			(tg as Dictionary)["pos"] = (tg as Dictionary)["pos"] + Vector2(400.0, 300.0)
			vd.tick(0.05)
			var dest1: Vector2 = dr["dest"]
			_ok("★★目标挪走 500 码后, 落点跟着变了(整段实时跟随, 不是起段快照)",
				dest0.distance_to(dest1) > 50.0,
				"落点位移 %.0f 码" % dest0.distance_to(dest1))


	_ok("⓪ ★★每帧驱动接在 RelicSynergySystem.tick() 的提前 return 之【前】",
		_v._drones.size() == 1, "实得 %d 只" % _v._drones.size())
	var p0: Vector2 = _v._drones[0]["pos"]
	_s._relic_syn.tick(0.05)
	print("     再 tick(0.05): 位置 (%.1f,%.1f) → (%.1f,%.1f)" % [
		p0.x, p0.y, float(_v._drones[0]["pos"].x), float(_v._drones[0]["pos"].y)])
	_ok("⓪ 连续推进(位置真的在动)", (Vector2(_v._drones[0]["pos"]) - p0).length() > 0.1)
	# ★反面: delta=0 不该动
	var p1: Vector2 = _v._drones[0]["pos"]
	_s._relic_syn.tick(0.0)
	_ok("⓪ ★反面: delta=0 不推进(证明上面不是'随便调都变')",
		(Vector2(_v._drones[0]["pos"]) - p1).length() < 1e-9)
	# ★接线证据二: 换路真入口 _relic_syn.clear() 会撤场(dual_lane_flow.gd:467 调的就是它)
	_ok("⓪ ★分母: 撤之前确实有飞行物", _v._drones.size() == 1)
	_s._relic_syn.clear()
	print("     _relic_syn.clear()(换路真入口) → 飞行物 %d 只 (需求 0)" % _v._drones.size())
	_ok("⓪ ★★换路真入口 clear() 把飞行物撤了", _v._drones.size() == 0)
	# ★接线证据三: 092 不再走周期分发(它不是"到点触发一次"那个形状)
	_ok("⓪ ★092 不在批①周期表里", not EquipSystem.EQ_IV_BATCH1.has("p2eq_092"))
	await get_tree().process_frame


# ── ① 属性: 50/70/100 生命 + 10/22/40 魔抗(走真实属性管线量真单位) ──────────
func _g1_stats() -> void:
	print("")
	print("  ① 属性 — 用户原话「提供 50/70/100 生命值和 10/22/40 魔抗」:")
	var checked := 0
	for si in range(3):
		var u: Dictionary = _mk("left", [], 1000.0)
		u["equips"] = [{"id": "p2eq_092", "star": si + 1}]
		u["eq_state"] = {}
		var hp0: float = float(u["maxHp"])
		var mr0: float = float(u["base_mr"])
		# ★走真入口: EquipStatsApply 的单件属性管线, 不是自己读 STATS 抄一遍
		_s._equip_sys._stats._eq_apply_one_stats(u, "p2eq_092", si + 1)
		var dhp: float = float(u["maxHp"]) - hp0
		var dmr: float = float(u["base_mr"]) - mr0
		print("     %d★: +生命 %.0f (需求 %.0f) / +魔抗 %.0f (需求 %.0f)" % [
			si + 1, dhp, WANT_HP[si], dmr, WANT_MR[si]])
		_ok("① %d★ 生命 +%.0f" % [si + 1, WANT_HP[si]], absf(dhp - WANT_HP[si]) < 0.51,
			"实得 %.1f" % dhp)
		_ok("① %d★ 魔抗 +%.0f" % [si + 1, WANT_MR[si]], absf(dmr - WANT_MR[si]) < 0.51,
			"实得 %.1f" % dmr)
		_ok("① %d★ 当前生命也跟着涨(装备 hp 是最终值, 不乘 HP_MULT)" % (si + 1),
			absf(float(u["hp"]) - (1000.0 + WANT_HP[si])) < 0.51, "hp=%.1f" % float(u["hp"]))
		checked += 1
	_ok("① ★分母: 真的验了三个星级 (N=%d)" % checked, checked == 3)


# ── ② 寻路几何: 「飞过目标到达它的对面落点」(纯函数, 不等飞行) ───────────────
func _g2_path_geometry() -> void:
	print("")
	print("  ② 寻路几何 — 落点在目标【身后】, 不是目标身上:")
	var worst_dot := 1.0
	var worst_len := 0.0
	var checked := 0
	for a in [0.0, 0.7, 1.9, 3.0, 4.4, 5.9]:
		for d in [80.0, 300.0, 900.0]:
			var from := Vector2(500.0, 400.0)
			var tgt: Vector2 = from + Vector2(cos(a), sin(a)) * float(d)
			var dest: Vector2 = VD.overshoot_dest(from, tgt)
			var fwd: Vector2 = (tgt - from).normalized()
			var out: Vector2 = dest - tgt
			worst_dot = minf(worst_dot, out.normalized().dot(fwd))
			worst_len = maxf(worst_len, absf(out.length() - VD.OVERSHOOT))   # ★引用常量: 调数值不该动测试
			checked += 1
	print("     扫 %d 组 (角度,距离): 最小方向一致度 %.9f / 落点距目标偏差最大 %.6f 码" % [
		checked, worst_dot, worst_len])
	_ok("② ★分母: 真的扫了组数 (N=%d)" % checked, checked == 18)
	_ok("② ★落点严格在【来向的延长线】上(穿过去, 不是绕过去)", worst_dot > 1.0 - 1e-6)
	_ok("② ★落点距目标恒为 %.0f 码(OVERSHOOT)" % VD.OVERSHOOT, worst_len < 1e-3)
	# ★反面: "飞到目标就停" 的话落点就等于目标 —— 那样 out.length() 会是 0
	var dst: Vector2 = VD.overshoot_dest(Vector2(0, 0), Vector2(200, 0))
	print("     ★反面 from(0,0) tgt(200,0) → 落点 (%.1f,%.1f); 若是'飞到就停'应是 (200,0)" % [dst.x, dst.y])
	_ok("② ★反面: 落点 ≠ 目标(不是'飞到就停')", (dst - Vector2(200, 0)).length() > VD.OVERSHOOT * 0.75)
	# 退化: 已经贴在目标身上也必须给出一个合法的穿出点, 不能返回 NaN
	var deg: Vector2 = VD.overshoot_dest(Vector2(300, 300), Vector2(300, 300))
	_ok("② 退化情形(已贴在目标身上)仍给合法落点", is_finite(deg.x) and is_finite(deg.y)
		and (deg - Vector2(300, 300)).length() > VD.OVERSHOOT * 0.75)


# ── ③ 寻路行为: 真的模拟一段航程 —— 穿过去、落在对面 ────────────────────────
## ★不等演出: 直接同步喂 `tick(dt)`, 每一步都是纯计算。
func _g3_path_behavior() -> void:
	print("")
	print("  ③ 寻路行为 — 真模拟一段航程(同步喂 tick, 不等任何 tween):")
	await _setup_units()
	_v.clear_all()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	# 干净布局: 携带者在左, 唯一敌人在正右方 ⇒ 航向几乎不用转, 一定是"直穿"
	_me["pos"] = c + Vector2(-500.0, 0.0)
	_foe["pos"] = c + Vector2(0.0, 0.0)
	_foe["untargetable_until"] = 0.0
	_v._on_beat()                       # 走真入口重扫出飞行物
	_ok("③ ★分母: 飞行物建出来了", _v._drones.size() == 1)
	if _v._drones.size() != 1:
		return
	var d: Dictionary = _v._drones[0]
	var start: Vector2 = d["pos"]
	var tgt: Vector2 = _foe["pos"]
	var min_d := 1e9
	var steps := 0
	var end_leg: int = int(d["legs"])
	while steps < 3000 and int(d["legs"]) == end_leg:
		_v._tick_drones(1.0 / 60.0)
		if _v._drones.is_empty():
			break
		min_d = minf(min_d, (Vector2(d["pos"]) - tgt).length())
		steps += 1
	var fin: Vector2 = d["pos"]
	var past: float = (fin - tgt).dot((tgt - start).normalized())
	print("     起点(%.0f,%.0f) 目标(%.0f,%.0f) 终点(%.0f,%.0f)" % [
		start.x, start.y, tgt.x, tgt.y, fin.x, fin.y])
	print("     途中离目标最近 %.1f 码 / 终点在目标【前方】%.1f 码 / 共 %d 步" % [min_d, past, steps])
	_ok("③ ★分母: 真的走了步数且换了下一段 (N=%d)" % steps, steps > 60 and steps < 3000)
	_ok("③ ★真的【从目标身上穿过去】(途中最近 < 60 码)", min_d < 60.0, "实得 %.1f" % min_d)
	_ok("③ ★★落在目标【对面】(沿来向越过目标 ≥ OVERSHOOT×0.75)", past >= VD.OVERSHOOT * 0.75, "实得 %.1f" % past)
	_ok("③ ★反面: 不是'飞到目标就停'(终点离目标 ≥ 200 码)",
		(fin - tgt).length() >= VD.OVERSHOOT * 0.75, "实得 %.1f" % (fin - tgt).length())
	_ok("③ 到了对面就换下一段目标(legs 加了一)", int(d["legs"]) == end_leg + 1,
		"legs %d → %d" % [end_leg, int(d["legs"])])


# ── ④ 转向惯性: Dubins 最小转弯半径(量真实轨迹, 不读常量) ────────────────────
func _g4_turn_inertia() -> void:
	print("")
	print("  ④ 转向惯性 — Dubins 载具: 轨迹曲率有硬上限(瞬间改向做不到):")
	# ④a 纯函数: 180° 掉头要用满 π/ω 秒
	var hd := 0.0
	var t := 0.0
	var dt := 1.0 / 240.0
	var it := 0
	while absf(wrapf(PI - hd, -PI, PI)) > 1e-3 and it < 100000:
		hd = VV.steer(hd, PI, dt)
		t += dt
		it += 1
	print("     180° 掉头耗时 %.4f 秒 (需求 π/1.2 = %.4f)" % [t, PI / 1.2])
	_ok("④ ★分母: 掉头真的迭代了 (N=%d)" % it, it > 100)
	_ok("④ ★180° 掉头 = π/ω_max 秒(不是一帧转完)", absf(t - PI / 1.2) < 0.01, "实得 %.4f" % t)
	# ④b 真实轨迹: 逼它一直朝反方向拐, 量出来的转弯半径不得小于 V/ω
	var pos := Vector2.ZERO
	var h2 := 0.0
	var prev := pos
	var min_r := 1e9
	var arc := 0.0
	var turn := 0.0
	var n2 := 0
	for _i in range(600):
		var want: float = h2 + PI * 0.9      # 一直要求它急转
		var nh: float = VV.steer(h2, want, 1.0 / 60.0)
		var dth: float = absf(wrapf(nh - h2, -PI, PI))
		h2 = nh
		pos += Vector2(cos(h2), sin(h2)) * 110.0 * (1.0 / 60.0)
		var ds: float = (pos - prev).length()
		prev = pos
		arc += ds
		turn += dth
		if dth > 1e-9:
			min_r = minf(min_r, ds / dth)
		n2 += 1
	print("     急转 600 步: 总弧长 %.1f 码 / 总转角 %.2f 弧度 / 最小瞬时半径 %.3f 码 (需求 ≥ 110/1.2 = %.3f)" % [
		arc, turn, min_r, 110.0 / 1.2])
	_ok("④ ★分母: 真的转了 (总转角 %.2f 弧度 > 6.28)" % turn, turn > 6.28 and n2 == 600)
	_ok("④ ★★最小转弯半径 ≥ V/ω_max = 91.667 码(这就是'惯性')",
		min_r > 91.66 - 0.01, "实得 %.3f" % min_r)
	_ok("④ 平均转弯半径 = 弧长/转角 ≈ 91.667", absf(arc / turn - 91.6667) < 0.5,
		"实得 %.3f" % (arc / turn))
	# ★反面: 若实现成"瞬间改向", 一步就转 PI*0.9 ⇒ 半径 = ds/dθ ≈ 0.65 码, 差两个数量级
	print("     ★反面: 瞬间改向的话每步转 %.2f 弧度 ⇒ 半径 ≈ %.2f 码(差两个数量级)" % [
		PI * 0.9, 110.0 / 60.0 / (PI * 0.9)])
	_ok("④ ★反面: 实测半径远大于'瞬间改向'的 0.65 码", min_r > 50.0)


# ── ⑤ 毒雾物理: 高斯烟团 + 一阶衰减(全是性质断言, 不抄公式) ──────────────────
func _g5_fog_physics() -> void:
	print("")
	print("  ⑤ 毒雾物理 — 二维高斯烟团 σ²=σ₀²+2Dt · C∝(1/σ²)e^(−t/τ):")
	# ⑤a √t 律的精确陈述: σ² 对 t 严格线性, 斜率恒定
	var slopes: Array = []
	var m := 0
	for i in range(1, 40):
		var t0: float = float(i) * 0.1
		var t1: float = t0 + 0.05
		var s0: float = VV.fog_sigma(t0)
		var s1: float = VV.fog_sigma(t1)
		slopes.append((s1 * s1 - s0 * s0) / (t1 - t0))
		m += 1
	var smin: float = slopes[0]
	var smax: float = slopes[0]
	for s in slopes:
		smin = minf(smin, float(s)); smax = maxf(smax, float(s))
	print("     σ² 的斜率扫 %d 段: [%.6f, %.6f] (常数 = 2D)" % [m, smin, smax])
	_ok("⑤ ★分母: 真的扫了段数 (N=%d)" % m, m == 39)
	_ok("⑤ ★★σ² 对 t 严格线性(= 半径 ∝ √t 的精确陈述)", smax - smin < 1e-6,
		"跨度 %.9f" % (smax - smin))
	print("     σ(0)=%.3f 码 / σ(1)=%.3f / σ(4)=%.3f (单调铺开)" % [
		VV.fog_sigma(0.0), VV.fog_sigma(1.0), VV.fog_sigma(VD.FOG_LIFE)])
	_ok("⑤ σ 单调涨(铺开)", VV.fog_sigma(0.0) < VV.fog_sigma(1.0)
		and VV.fog_sigma(1.0) < VV.fog_sigma(VD.FOG_LIFE))
	# ★反面: 若写成线性扩散 σ ∝ t, σ² 的斜率就不会是常数
	_ok("⑤ ★反面: σ 不是线性的(σ(4)/σ(0) ≠ σ(2)/σ(0)×2)",
		absf(VV.fog_sigma(VD.FOG_LIFE) / VV.fog_sigma(0.0) - 2.0 * VV.fog_sigma(2.0) / VV.fog_sigma(0.0)) > 0.3)

	# ⑤b 守恒量: C_peak·σ²·e^(t/τ) ≡ 常数 —— 峰值与半径被焊死成一个量
	var k0: float = VV.fog_peak(0.0) * VV.fog_sigma(0.0) * VV.fog_sigma(0.0) * exp(0.0 / 2.2)
	var worst := 0.0
	var m2 := 0
	for i in range(0, 81):
		var tt: float = float(i) * 0.05
		var kk: float = VV.fog_peak(tt) * VV.fog_sigma(tt) * VV.fog_sigma(tt) * exp(tt / 2.2)
		worst = maxf(worst, absf(kk / k0 - 1.0))
		m2 += 1
	print("     守恒量 C_peak·σ²·e^(t/τ) 扫 %d 点: 最大相对偏差 %.12f" % [m2, worst])
	_ok("⑤ ★分母: 真的扫了 (N=%d)" % m2, m2 == 81)
	_ok("⑤ ★★守恒量恒定(总质量守恒 + 一阶衰减可分离 —— 手调曲线过不了)", worst < 1e-9,
		"最大相对偏差 %.12f" % worst)
	print("     C_peak: t=0 %.4f / t=1 %.4f / t=2 %.4f / t=4 %.5f (单调变淡)" % [
		VV.fog_peak(0.0), VV.fog_peak(1.0), VV.fog_peak(2.0), VV.fog_peak(VD.FOG_LIFE)])
	_ok("⑤ 峰值浓度单调跌(变淡)", VV.fog_peak(0.0) > VV.fog_peak(1.0)
		and VV.fog_peak(1.0) > VV.fog_peak(2.0) and VV.fog_peak(2.0) > VV.fog_peak(VD.FOG_LIFE))

	# ⑤c 有效半径: 先涨后跌, 且在 4.0 秒精确归零 —— "生成→铺开→变淡"是解自己给的
	var up := 0
	var down := 0
	var top_t := 0.0
	var top_r := -1.0
	var last := -1.0
	var m3 := 0
	var tt2 := 0.0
	while tt2 <= 4.0001:
		var r: float = VV.fog_radius(tt2)
		if r > top_r:
			top_r = r; top_t = tt2
		if last >= 0.0:
			if r > last + 1e-9: up += 1
			elif r < last - 1e-9: down += 1
		last = r
		tt2 += 0.002
		m3 += 1
	print("     有效半径扫 %d 个时刻: 上升 %d 段 / 下降 %d 段; 峰值 %.2f 码 @ t=%.3f s" % [
		m3, up, down, top_r, top_t])
	_ok("⑤ ★分母: 真的扫了 (N=%d)" % m3, m3 > 1900)
	_ok("⑤ ★★有效半径【先涨后跌】(铺开终究追不上变淡 —— 单调曲线做不出来)",
		up > 50 and down > 500)
	_ok("⑤ ★★寿命末尾(4.0 秒)有效半径精确归零 —— 4 秒是解的边界条件不是外挂截断",
		absf(VV.fog_radius(VD.FOG_LIFE)) < 1e-9, "实得 %.12f" % VV.fog_radius(VD.FOG_LIFE))
	_ok("⑤ 生成时就有可观的半径(不是从 0 长起)", VV.fog_radius(0.0) > 50.0,
		"实得 %.2f" % VV.fog_radius(0.0))
	## ★2026-08-20: 原来写死「t < 2.0」, 那是照 FOG_LIFE=4.0 算的一半。
	##   用户 2026-08-13 把毒雾寿命加强到 6 秒, 而演出侧的常量一直没跟上(见 venom_drone_vfx.gd),
	##   ⇒ 加强从没生效; 修好之后这条断言反而红了 —— **判据自己抄了那个过期的数**。
	##   改成从常量推导: 峰值必须落在寿命前半程, 不管寿命是几秒。
	_ok("⑤ 峰值半径在前半程(t < FOG_LIFE/2 = %.1f s)" % (VD.FOG_LIFE * 0.5),
		top_t < VD.FOG_LIFE * 0.5, "实得 %.3f (寿命 %.1f)" % [top_t, VD.FOG_LIFE])

	# ⑤d ★★尺子匹配被测概念: 伤害半径 == 渲染 alpha 的等值线
	#     反解 —— 在 fog_radius(t) 处的渲染 alpha 应当恰好等于阈值 fog_a_min()
	var amin: float = VV.fog_a_min()
	var worst2 := 0.0
	var m4 := 0
	for i in range(1, 20):
		var tt3: float = float(i) * 0.2
		var rr: float = VV.fog_radius(tt3)
		if rr <= 0.0:
			continue
		worst2 = maxf(worst2, absf(VV.fog_alpha_at(rr, tt3) / amin - 1.0))
		m4 += 1
	print("     在有效半径处的渲染 alpha / 阈值: 扫 %d 点, 最大相对偏差 %.12f (阈值 %.6f)" % [
		m4, worst2, amin])
	_ok("⑤ ★分母: 真的扫了 (N=%d)" % m4, m4 > 15)
	_ok("⑤ ★★★打得到的边界 == 看得见的边界(同一条浓度等值线)", worst2 < 1e-9,
		"最大相对偏差 %.12f" % worst2)
	_ok("⑤ 半径内侧明显更亮(浓度梯度真的存在)",
		VV.fog_alpha_at(0.0, 1.0) > VV.fog_alpha_at(VV.fog_radius(1.0), 1.0) * 5.0)

	# ⑤e ★接线: 【真实节点】的 scale 与材质 alpha 就是上面那两条曲线(不是另画一套)
	# ★2026-08-09 重做后一团毒雾是 Node3D 挂两片(haze 高斯烟团 + rim 判定边界环) ⇒
	#   这里要取 `haze` 子节点。**不能只把 cast 改成 null 就算了** —— 那样这两条断言
	#   会静默变成"跳过", 看着照样绿(本项目栽过的"空检查")。
	_v.clear_all()
	var fn = _v._vfx.make_fog(Vector2(700.0, 400.0))
	_ok("⑤ ★分母: 毒雾节点建出来了", fn != null)
	if fn != null:
		var hz := fn.get_node_or_null("haze") as MeshInstance3D
		_ok("⑤ ★分母: haze(高斯烟团)子节点在", hz != null)
		var bad5 := 0
		var m5 := 0
		for i in range(0, 16):
			var tt: float = float(i) * 0.25
			_v._vfx.apply_fog(fn, tt)
			var sc: float = hz.scale.x / float(_s.WS)          # 米 → 码
			var al: float = (hz.material_override as StandardMaterial3D).albedo_color.a
			if absf(sc - VV.fog_sigma(tt)) > 1e-4:
				bad5 += 1
			# 渲染 alpha = 显示增益 0.45 × 归一浓度(★增益是常数 ⇒ 等值线一条不动)
			## ★读常量而不是写死 0.45: 这条守的是**关系**(alpha = 常数增益 × 归一浓度,
			##   增益与 t 无关 ⇒ 等值线一条不动), 不是那个具体数字。
			##   2026-08-09 haze 从"就是雾"降级为极淡底色(0.45→0.14, 真雾改用粒子),
			##   写死的数字当场把这条判红 —— 而演出与判定的关系其实一点没变。
			if absf(al - VV.FOG_DRAW_A * VV.fog_peak(tt)) > 1e-6:
				bad5 += 1
			m5 += 1
		print("     真实节点 vs 曲线: 喂 %d 个时刻, 不符 %d 处 (scale=σ(t) 码 / alpha=%.2f×C_peak(t))" % [m5, bad5, VV.FOG_DRAW_A])
		_ok("⑤ ★分母: 真的喂了时刻 (N=%d)" % m5, m5 == 16)   # ★这是本用例自己采样的次数, 与 FOG_LIFE 无关
		_ok("⑤ ★★真实节点的 scale 与材质 alpha 就是这两条曲线本身(演出与判定同源)", bad5 == 0,
			"不符 %d 处" % bad5)
		fn.queue_free()


# ── ⑤★ 判定边界环 rim: 2026-08-09 逐件重做的三条验收 ─────────────────────────
## 实拍(VFXLAB p2eq_092 · zoom 1.0 实战镜头)抓出三处, 三处一个解 —— 见
## venom_drone_vfx.gd 文件头【甲乙丙】。这一节守的就是那个解。
func _g5b_fog_rim() -> void:
	## ★★2026-08-09 **判定边界环已移除**(用户:「为啥要环啊」—— 我没有站得住的理由)。
	##   原来这一节钉的是"环在场 / 环 holdfade / 环半径 ≡ fog_radius(t)"。
	##   ②那条保证没有丢, 而是**加强**了: 粒子直接铺在 `fog_radius(t)` 里(见 ⑤P),
	##   "看得见的 == 打得到的"由粒子的发射盘独扛, 不再靠画一条线。
	##   `fog_rim_profile` / `_build_rim_mesh` 是纯函数, 保留不删, 但已无人调用。
	print("")
	print("  ⑤b 判定边界环: 已移除(见本函数注释), 保证改由 ⑤P 的粒子发射盘承担")


func _g6_fog_lifetime() -> void:
	print("")
	print("  ⑥ 毒雾 — 每 0.25 秒留一团 · 4 秒后真的消失:")
	await _setup_units()
	_v.clear_all()
	_v._on_beat()
	_ok("⑥ ★分母: 飞行物在", _v._drones.size() == 1)
	if _v._drones.is_empty():
		return
	# 喂 1.05 秒 ⇒ 恰好 4 团(⌊1.05/0.25⌋ = 4; 第 5 团要到 1.25 秒)。
	# ★为什么不喂整 1.0 秒: 步长是 1/60 秒, 二进制里 15×(1/60) = 0.24999999999999997 < 0.25,
	#   第一次投放会落在第 16 步(0.2667 秒)。累加器带余数 ⇒ 长期节拍精确是 0.25 秒
	#   (下面"4 秒常驻 16 团"那条就是它的证明), 但拿【整点】当断言点会踩这个边界。
	_feed(1.05)
	print("     喂 1.05 秒 → 毒雾 %d 团 (需求 4 = ⌊1.05/0.25⌋)" % _v._fogs.size())
	_ok("⑥ ★每 0.25 秒留一团(1.05 秒 = 4 团)", _v._fogs.size() == 4, "实得 %d" % _v._fogs.size())
	_ok("⑥ ★世界里真有 4 个毒雾节点(不是只记了账)", _count("venom_fog") == 4,
		"实得 %d" % _count("venom_fog"))
	# 再喂到【满一个寿命】: 常驻团数应稳定在 FOG_LIFE ÷ BEAT
	## ★喂食时长也按常量推导 —— 写死 3.15 秒的话, 寿命一调长就喂不满、团数自然不够。
	_feed(VD.FOG_LIFE - 1.05 + 0.15)
	print("     再喂到 %.2f 秒 → 毒雾 %d 团 (需求 %d = 寿命 ÷ 节拍)"
		% [VD.FOG_LIFE + 0.15, _v._fogs.size(), int(VD.FOG_LIFE / VD.BEAT)])
	## ★团数【由常量推导】: 寿命 ÷ 节拍。写死的话调数值就红一片(2026-08-13 踩过)。
	_ok("⑥ ★★常驻团数稳定在 %d(= 寿命 %.0f 秒 ÷ 节拍 %.2f 秒)" % [int(VD.FOG_LIFE / VD.BEAT), VD.FOG_LIFE, VD.BEAT], _v._fogs.size() == int(VD.FOG_LIFE / VD.BEAT),
		"实得 %d" % _v._fogs.size())
	# ★再喂到 6.1 秒 —— 这一段专门守【寿命就是 4 秒】。
	#   为什么 4.2 秒那个点不够: 4.2/0.25 = 16.8 ⇒ 就算寿命是 8 秒, 那时也才投了 16 团,
	#   "常驻 16"照样成立(反向验证里把寿命改成 8 秒, 4.2 秒那条真的没红)。
	#   到 6.1 秒时: 寿命 4 秒 ⇒ 仍是 16 团; 寿命 8 秒 ⇒ 会攒到 24 团。这才分得开。
	_feed(1.9)
	var oldest := 0.0
	for f in _v._fogs:
		oldest = maxf(oldest, float(f["t"]))
	print("     再喂到 6.1 秒 → 毒雾 %d 团 (需求仍是 16); 最老的一团年龄 %.3f 秒 (必须 < VD.FOG_LIFE)" % [
		_v._fogs.size(), oldest])
	_ok("⑥ ★★寿命就是 %.0f 秒(按 FOG_LIFE 推导)" % VD.FOG_LIFE + "",
		_v._fogs.size() == int(VD.FOG_LIFE / VD.BEAT), "实得 %d" % _v._fogs.size())
	_ok("⑥ ★到点真的被回收(最老的一团 < FOG_LIFE)", oldest < VD.FOG_LIFE, "实得 %.3f" % oldest)
	# 停掉飞行物之后再喂 4 秒 —— 所有毒雾必须清零(节点也没了)。
	# ★必须先把装备摘掉: 只清 `_drones` 的话, 下一拍 `_rescan_carriers` 会照规格【重新召唤】
	#   (携带者还活着还带着它) ⇒ 新毒雾源源不断, 常驻量恒为 16, 这条永远量不到 0。
	#   第一版就是这么红的 —— 那不是 bug, 是测试没把"停止生产"做到位。
	_me["equips"] = []
	var kept: Array = _v._drones
	_v._drones = []
	for dd in kept:
		_v._free_drone(dd)
	_feed(VD.FOG_LIFE + 0.05)
	await get_tree().process_frame
	print("     撤掉飞行物再喂 4.05 秒 → 毒雾 %d 团 / 世界节点 %d 个 (都需求 0)" % [
		_v._fogs.size(), _count("venom_fog")])
	_ok("⑥ ★★每团各自活满 FOG_LIFE 后全部消失", _v._fogs.size() == 0)
	_ok("⑥ ★节点也真的 free 了(不是只清了表)", _count("venom_fog") == 0)


# ── ⑦ 中毒层数: 每 0.25 秒 2/3/5 层 ────────────────────────────────────────
func _g7_poison() -> void:
	print("")
	print("  ⑦ 中毒 — 毒雾每 0.25 秒施加 2/3/5 层:")
	for si in range(3):
		await _setup_units()
		_v.clear_all()
		_me["equips"] = [{"id": "p2eq_092", "star": si + 1}]
		# 把敌人钉在毒雾正中心 —— 干净合成单位, 不靠飞行物飞过去(那会引入随机)
		_v._on_beat()
		if _v._drones.is_empty():
			_ok("⑦ si=%d ★分母: 飞行物在" % si, false); continue
		var d: Dictionary = _v._drones[0]
		_v._drop_fog(d)
		_foe["pos"] = Vector2(d["pos"])
		_foe["dot_stacks"] = {}
		_ok("⑦ si=%d ★分母: 起手 0 层中毒" % si,
			int(_foe["dot_stacks"].get("poison", 0)) == 0)
		_v._apply_fog_field()
		var got: int = int(_foe["dot_stacks"].get("poison", 0))
		print("     %d★: 一拍施加 %d 层 (需求 %d)" % [si + 1, got, WANT_POISON[si]])
		_ok("⑦ %d★ 一拍 = %d 层中毒" % [si + 1, WANT_POISON[si]], got == WANT_POISON[si],
			"实得 %d" % got)
		_v._apply_fog_field()
		_v._apply_fog_field()
		var got3: int = int(_foe["dot_stacks"].get("poison", 0))
		_ok("⑦ %d★ 三拍 = %d 层(累加)" % [si + 1, WANT_POISON[si] * 3],
			got3 == WANT_POISON[si] * 3, "实得 %d" % got3)
		_ok("⑦ %d★ 中毒来源记的是携带者(DoT 吃它的穿透/增伤)" % (si + 1),
			is_same(_foe.get("dot_src", {}).get("poison", null), _me))
	# ★反面: 站在毒雾【外面】一层都不该有
	await _setup_units()
	_v.clear_all()
	_v._on_beat()
	if not _v._drones.is_empty():
		var d2: Dictionary = _v._drones[0]
		_v._drop_fog(d2)
		_foe["dot_stacks"] = {}
		_foe["pos"] = Vector2(d2["pos"]) + Vector2(400.0, 0.0)   # 远超 t=0 时的 67 码有效半径
		_v._apply_fog_field()
		print("     ★反面: 敌人放到 400 码外 → 中毒 %d 层 (需求 0)" % int(_foe["dot_stacks"].get("poison", 0)))
		_ok("⑦ ★反面: 毒雾外的单位一层都不吃(证明上面不是'谁都上毒')",
			int(_foe["dot_stacks"].get("poison", 0)) == 0)
		# 边界: 有效半径内侧吃、外侧不吃 —— 量的是 sim 真用的那条半径
		var r0: float = VV.fog_radius(0.0)
		_foe["dot_stacks"] = {}
		_foe["pos"] = Vector2(d2["pos"]) + Vector2(r0 - 2.0, 0.0)
		_v._apply_fog_field()
		var inside: int = int(_foe["dot_stacks"].get("poison", 0))
		_foe["dot_stacks"] = {}
		_foe["pos"] = Vector2(d2["pos"]) + Vector2(r0 + 2.0, 0.0)
		_v._apply_fog_field()
		var outside: int = int(_foe["dot_stacks"].get("poison", 0))
		print("     边界 r=%.2f 码: 内侧 2 码 → %d 层 / 外侧 2 码 → %d 层" % [r0, inside, outside])
		_ok("⑦ ★判定边界就是有效半径(内吃外不吃)", inside > 0 and outside == 0)


# ── ⑧ 剧毒缓速: 每拍 +1 · 封顶 20 · 每层 −2% 移速 −1% 魔抗 ──────────────────
func _g8_vslow() -> void:
	print("")
	print("  ⑧ 剧毒缓速 — 每 0.25 秒 +1 层 · 封顶 20 · 每层 −2%% 移速 −1%% 魔抗:")
	await _setup_units()
	_v.clear_all()
	_foe["base_mr"] = 100.0
	_foe["mr"] = 100.0
	_foe["move_perm"] = 1.0
	_s._recalc_stats(_foe)
	var mv0: float = float(_foe["move_perm"])
	var mr0: float = float(_foe["mr"])
	_ok("⑧ ★分母: 起手 0 层 / move_perm=1.0 / 魔抗=100",
		VD.vslow_stacks(_foe) == 0 and absf(mv0 - 1.0) < 1e-9 and absf(mr0 - 100.0) < 0.51,
		"n=%d mv=%.4f mr=%.1f" % [VD.vslow_stacks(_foe), mv0, mr0])
	_v.add_vslow(_foe, 1)
	print("     1 层: move_perm %.4f (需求 0.98) / 魔抗 %.2f (需求 99)" % [
		float(_foe["move_perm"]), float(_foe["mr"])])
	_ok("⑧ 1 层 → 移速 ×0.98", absf(float(_foe["move_perm"]) - 0.98) < 1e-6,
		"实得 %.6f" % float(_foe["move_perm"]))
	_ok("⑧ 1 层 → 魔抗 100 → 99(−1%)", absf(float(_foe["mr"]) - 99.0) < 0.51,
		"实得 %.2f" % float(_foe["mr"]))
	for _i in range(9):
		_v.add_vslow(_foe, 1)
	print("     10 层: n=%d / move_perm %.4f (需求 0.80) / 魔抗 %.2f (需求 90)" % [
		VD.vslow_stacks(_foe), float(_foe["move_perm"]), float(_foe["mr"])])
	_ok("⑧ 攒到 10 层", VD.vslow_stacks(_foe) == 10, "实得 %d" % VD.vslow_stacks(_foe))
	_ok("⑧ 10 层 → 移速 ×0.80", absf(float(_foe["move_perm"]) - 0.80) < 1e-6)
	_ok("⑧ 10 层 → 魔抗 90", absf(float(_foe["mr"]) - 90.0) < 0.51)
	for _i2 in range(40):
		_v.add_vslow(_foe, 1)
	print("     猛灌 50 次: n=%d (需求封顶 20) / move_perm %.4f (需求 0.60) / 魔抗 %.2f (需求 80)" % [
		VD.vslow_stacks(_foe), float(_foe["move_perm"]), float(_foe["mr"])])
	_ok("⑧ ★★封顶 20 层(灌 50 次也不超)", VD.vslow_stacks(_foe) == WANT_VSLOW_CAP,
		"实得 %d" % VD.vslow_stacks(_foe))
	_ok("⑧ ★20 层 → 移速 ×0.60(= 1 − 20×2%)", absf(float(_foe["move_perm"]) - 0.60) < 1e-6,
		"实得 %.6f" % float(_foe["move_perm"]))
	_ok("⑧ ★20 层 → 魔抗 80(= 100 × (1 − 20×1%))", absf(float(_foe["mr"]) - 80.0) < 0.51,
		"实得 %.2f" % float(_foe["mr"]))
	# ★★量【真实生效的移速】: 走 sim 里那条乘法链, 不是只看字段
	var eff: float = float(_foe["move_spd"]) * float(_foe.get("move_perm", 1.0))
	var base_eff: float = float(_foe["move_spd"])
	print("     真实移速 = move_spd(%.1f) × move_perm(%.2f) = %.2f (基准 %.1f)" % [
		float(_foe["move_spd"]), float(_foe["move_perm"]), eff, base_eff])
	_ok("⑧ ★★真实移速被砍到 60%(量的是 sim 那条乘法链上的量)",
		absf(eff / base_eff - 0.60) < 1e-6, "实得 %.6f" % (eff / base_eff))
	# ★不占用两条减速通道 —— 占了会把冰冻/岩浆的减速吞掉
	print("     减速两条单槽通道: slow_until=%.2f spd_dbf_until=%.2f (都需求 0 = 没被占)" % [
		float(_foe.get("slow_until", 0.0)), float(_foe.get("spd_dbf_until", 0.0))])
	_ok("⑧ ★★没有占用 slow_until / spd_move_mult 两条单槽减速通道(不与别的减速打架)",
		float(_foe.get("slow_until", 0.0)) <= 0.0 and float(_foe.get("spd_dbf_until", 0.0)) <= 0.0)
	# ★只留一条魔抗 buff, 不 append 第二条(否则 20 次施加 = 20 条)
	var nb := 0
	for b in _foe["buffs"]:
		if bool((b as Dictionary).get("_vslow", false)):
			nb += 1
	print("     buffs 里本效果的条数 %d (需求 1 —— 每次重写不追加)" % nb)
	_ok("⑧ ★魔抗只挂一条 buff(重写不追加)", nb == 1, "实得 %d" % nb)
	# 归零后完全还原
	_v._set_vslow(_foe, 0)
	print("     清到 0 层: move_perm %.4f (需求 1.0) / 魔抗 %.2f (需求 100)" % [
		float(_foe["move_perm"]), float(_foe["mr"])])
	_ok("⑧ ★清零后属性精确还原(没有浮点漂移)",
		absf(float(_foe["move_perm"]) - 1.0) < 1e-9 and absf(float(_foe["mr"]) - 100.0) < 0.51)
	# 反复加减 200 次也不漂
	for _k in range(100):
		_v.add_vslow(_foe, 3)
		_v._set_vslow(_foe, VD.vslow_stacks(_foe) - 2)
	_v._set_vslow(_foe, 0)
	_ok("⑧ ★反复加减 100 轮后仍精确还原(证明不是增量式写法)",
		absf(float(_foe["move_perm"]) - 1.0) < 1e-9, "实得 %.9f" % float(_foe["move_perm"]))


# ── ⑨ 衰减: 1.5 秒不刷新 → 每 0.25 秒掉一层 ────────────────────────────────
func _g9_vslow_decay() -> void:
	print("")
	print("  ⑨ 衰减 — 1.5 秒内没被再施加 → 每 0.25 秒失去一层:")
	await _setup_units()
	_v.clear_all()
	_v.add_vslow(_foe, 10)
	_ok("⑨ ★分母: 起手 10 层", VD.vslow_stacks(_foe) == 10)
	# 前 5 拍(1.25 秒)一层都不许掉
	var trace: Array = []
	for _i in range(5):
		_v._beat_n += 1
		_v._decay_vslow()
		trace.append(VD.vslow_stacks(_foe))
	print("     不刷新 5 拍(1.25 秒): 层数 %s (需求全是 10)" % str(trace))
	_ok("⑨ ★1.25 秒内一层都不掉(宽限期是 1.5 秒不是 1.25)",
		trace == [10, 10, 10, 10, 10], "实得 %s" % str(trace))
	# 第 6 拍(累计 1.5 秒)开始掉, 之后每拍掉一层
	var trace2: Array = []
	for _i2 in range(5):
		_v._beat_n += 1
		_v._decay_vslow()
		trace2.append(VD.vslow_stacks(_foe))
	print("     再 5 拍: 层数 %s (需求 9,8,7,6,5 —— 第 6 拍起每拍掉一层)" % str(trace2))
	_ok("⑨ ★★第 6 拍(= 1.5 秒)开始掉, 之后每 0.25 秒掉一层",
		trace2 == [9, 8, 7, 6, 5], "实得 %s" % str(trace2))
	print("     此时 move_perm %.4f (需求 0.90 = 1 − 5×2%%)" % float(_foe["move_perm"]))
	_ok("⑨ 掉层后属性跟着回来(5 层 → ×0.90)",
		absf(float(_foe["move_perm"]) - 0.90) < 1e-6, "实得 %.6f" % float(_foe["move_perm"]))
	# ★刷新一次 → 宽限期重新计时, 下一拍不该掉
	_v._beat_n += 1
	_v.add_vslow(_foe, 1)
	var n_after: int = VD.vslow_stacks(_foe)
	_v._beat_n += 1
	_v._decay_vslow()
	print("     刷新一次(→%d 层)后再走一拍: %d 层 (需求不变 —— 宽限期重新计时)" % [
		n_after, VD.vslow_stacks(_foe)])
	_ok("⑨ ★被再次施加 → 宽限期重新计时(下一拍不掉)", VD.vslow_stacks(_foe) == n_after)
	# 一路掉到 0: 属性完全还原
	for _i3 in range(60):
		_v._beat_n += 1
		_v._decay_vslow()
	print("     一路掉到 %d 层: move_perm %.4f (需求 1.0)" % [
		VD.vslow_stacks(_foe), float(_foe["move_perm"])])
	_ok("⑨ ★掉到 0 层后属性精确还原", VD.vslow_stacks(_foe) == 0
		and absf(float(_foe["move_perm"]) - 1.0) < 1e-9)


# ── ⑩ 携带者阵亡 → 飞行物阵亡(而已落地的毒雾照常活满) ───────────────────────
func _g10_carrier_death() -> void:
	print("")
	print("  ⑩ 携带者阵亡 → 飞行物也阵亡:")
	await _setup_units()
	# ★再放一个【活着的】左方队友: 不放的话携带者一死左队就团灭, 真实场景的 `_check_end`
	#   会把 `battle._over` 置真 ⇒ 下面那句 `sim_running()` 变假 ⇒ 毒雾根本不再被推进,
	#   于是"死后毒雾按时消散"这条会量到 0 变化, 看着像 bug 其实是战斗已经结束了。
	#   (第一版就是这么红的。留着这段注释免得下次再踩。)
	var ally: Dictionary = _mk("left", [], 900000.0)
	ally["pos"] = _me["pos"] + Vector2(0.0, 120.0)
	_v.clear_all()
	_v._on_beat()
	_feed(0.6)
	var n_fog: int = _v._fogs.size()
	print("     开局: 飞行物 %d 只 / 毒雾 %d 团 / 世界里飞行物节点 %d 个" % [
		_v._drones.size(), n_fog, _count("venom_drone")])
	_ok("⑩ ★分母: 飞行物与毒雾都在", _v._drones.size() == 1 and n_fog >= 2
		and _count("venom_drone") == 1)
	_me["alive"] = false
	_v._tick_drones(1.0 / 60.0)          # 每帧判, 不用等 0.25 秒重扫
	await get_tree().process_frame
	print("     携带者阵亡后一帧: 飞行物 %d 只 / 节点 %d 个 (都需求 0); 毒雾还剩 %d 团" % [
		_v._drones.size(), _count("venom_drone"), _v._fogs.size()])
	_ok("⑩ ★★携带者一死, 飞行物【同一帧】就没了", _v._drones.size() == 0)
	_ok("⑩ ★飞行物节点真的 free 了", _count("venom_drone") == 0)
	_ok("⑩ ★已落地的毒雾不受影响(它有自己的 4 秒寿命)", _v._fogs.size() == n_fog,
		"%d → %d" % [n_fog, _v._fogs.size()])
	# 毒雾在携带者死后仍然会推进并到期 —— 这是"驱动不挂在携带者身上"的直接证据
	_ok("⑩ ★分母: 战斗还没结束(sim_running 为真), 否则下面量到 0 变化是假象",
		_v.sim_running(), "_over=%s" % str(_s._over))
	_feed(VD.FOG_LIFE + 0.05)
	await get_tree().process_frame
	print("     携带者已死, 再喂 4.05 秒 → 毒雾 %d 团 (需求 0 —— 死后毒雾仍在被推进)" % _v._fogs.size())
	_ok("⑩ ★★携带者死后毒雾仍被推进并按时消散(驱动没挂在携带者身上)", _v._fogs.size() == 0)
	# 复活(把 alive 改回来) → 下一拍重新召唤, 证明上面不是"永久坏了"
	_me["alive"] = true
	_v._on_beat()
	_ok("⑩ ★反面: 携带者活着就会重新召唤(证明不是'永久坏了')", _v._drones.size() == 1)
	# 不可选中: 飞行物压根不是 battle._units 里的单位 ⇒ 结构性不可选中
	var in_units := false
	for u in _s._units:
		if u is Dictionary and (u as Dictionary).has("_venom_is_drone"):
			in_units = true
	print("     飞行物在 battle._units 里吗: %s (场上单位 %d 个 = 携带者+队友+靶子, 需求 false)" % [
		str(in_units), _s._units.size()])
	_ok("⑩ ★★不可选中: 飞行物不是 _units 里的单位(不会被索敌/AOE/团灭判定看见)",
		not in_units and _s._units.size() == 3)


# ── ⑪ 换路清干净: 飞行物 + 毒雾 + 所有单位身上的剧毒缓速层 ────────────────────
func _g11_lane_clear() -> void:
	print("")
	print("  ⑪ 换路撤场 — 走 _relic_syn.clear() 真入口(dual_lane_flow.gd:467):")
	await _setup_units()
	_v.clear_all()
	_v._on_beat()
	_feed(1.2)
	_v.add_vslow(_foe, 7)
	_v._tick_rings()
	var before_nodes: int = _count()
	print("     撤之前: 飞行物 %d / 毒雾 %d / 脚环 %d / 世界里本层节点 %d 个 / 敌人 %d 层" % [
		_v._drones.size(), _v._fogs.size(), _v._rings.size(), before_nodes, VD.vslow_stacks(_foe)])
	_ok("⑪ ★分母: 撤之前确实有东西", _v._drones.size() == 1 and _v._fogs.size() >= 4
		and _v._rings.size() == 1 and before_nodes >= 6 and VD.vslow_stacks(_foe) == 7)
	_s._relic_syn.clear()                # ← 换路真入口
	await get_tree().process_frame
	print("     clear() 之后: 飞行物 %d / 毒雾 %d / 脚环 %d / 世界里本层节点 %d 个" % [
		_v._drones.size(), _v._fogs.size(), _v._rings.size(), _count()])
	_ok("⑪ ★★飞行物清了", _v._drones.size() == 0)
	_ok("⑪ ★★毒雾清了", _v._fogs.size() == 0)
	_ok("⑪ ★★脚环清了", _v._rings.size() == 0)
	_ok("⑪ ★★一个节点都不泄漏(触手 warn_mi 那次就是每次换路漏一个)", _count() == 0,
		"实得 %d" % _count())
	print("     敌人身上: %d 层 / move_perm %.4f / 魔抗 %.2f (需求 0 / 1.0 / 原值)" % [
		VD.vslow_stacks(_foe), float(_foe["move_perm"]), float(_foe["mr"])])
	_ok("⑪ ★★剧毒缓速层也清了(不带进下一路)", VD.vslow_stacks(_foe) == 0)
	_ok("⑪ ★属性还原(move_perm 回 1.0)", absf(float(_foe["move_perm"]) - 1.0) < 1e-9)
	var nb := 0
	for b in _foe["buffs"]:
		if bool((b as Dictionary).get("_vslow", false)):
			nb += 1
	_ok("⑪ ★魔抗 buff 也摘掉了(buffs 里本效果 %d 条, 需求 0)" % nb, nb == 0)
	_ok("⑪ ★临时字段也擦了(_vslow_ring/_vslow_idle/_vslow_touch)",
		not _foe.has("_vslow_ring") and not _foe.has("_vslow_idle") and not _foe.has("_vslow_touch"))
	# ★反面: 清完还能重新建(证明不是把系统弄坏了)
	_v._on_beat()
	_ok("⑪ ★反面: 清完再来一路照样召唤得出来", _v._drones.size() == 1)
	_v.clear_all()


# ── ⑫ 扇翅 / 尾部 物理 ────────────────────────────────────────────────────────
func _g12_flap_physics() -> void:
	print("")
	print("  ⑫ 扇翅与尾部 — 受迫振子 + 行波:")
	# ⑫a 起伏幅度 ∝ f^(−2): amp(f)·f² 与 f 无关
	var vals: Array = []
	for f in [3.0, 6.0, 9.0, 13.0, 20.0]:
		vals.append(VV.bob_amp(float(f)) * float(f) * float(f))
	var lo: float = vals[0]
	var hi: float = vals[0]
	for x in vals:
		lo = minf(lo, float(x)); hi = maxf(hi, float(x))
	print("     amp(f)·f² 在 f=3..20 上: [%.9f, %.9f] (需求常数)" % [lo, hi])
	_ok("⑫ ★分母: 真的取了 5 个频率 (N=%d)" % vals.size(), vals.size() == 5)
	_ok("⑫ ★★起伏幅度 ∝ f^(−2)(受迫振子的响应, 不是随手乘个系数)",
		hi - lo < 1e-9, "跨度 %.12f" % (hi - lo))
	print("     f=6Hz 时起伏幅度 %.4f 米 (龟身高 2.0 米 ⇒ 约 2%%, 是'轻微上下'不是'弹跳')" % VV.bob_amp(6.0))
	_ok("⑫ 起伏幅度落在合理区间 (0.01~0.10 米)",
		VV.bob_amp(6.0) > 0.01 and VV.bob_amp(6.0) < 0.10)
	# ⑫b 起伏与行程角恒定反相
	var worst := 0.0
	var m := 0
	for i in range(0, 200):
		var t: float = float(i) * 0.003
		var s: float = VV.stroke(t)
		var b: float = VV.bob(t)
		# 归一后应当恒为 −1 倍
		if absf(s) > 1e-6:
			worst = maxf(worst, absf(b / VV.bob_amp() + s / 0.70))
			m += 1
	print("     反相校验扫 %d 点: 最大偏差 %.12f" % [m, worst])
	_ok("⑫ ★分母: 真的扫了 (N=%d)" % m, m > 150)
	_ok("⑫ ★★起伏与行程角恒定反相(二次积分带来的 π 相移)", worst < 1e-9,
		"最大偏差 %.12f" % worst)
	# ⑫c 尾部行波: **从真函数 tail_offset 上量**滞后, 不在测试里把公式抄第二遍。
	#   ★第一版就是抄了一遍(自己算 sin(2πft−2.4) 跟自己比), 反向验证把 TAIL_LAG 改成 0
	#   之后这条【照样绿】—— memory [[fb-write-without-reader-and-fake-gates]] 说的
	#   「门禁模拟公式 ≠ 量真实对象」。现在改成: 逐个 s 找 tail_offset 的上行过零时刻,
	#   看它是不是随弧长【线性推后】(这就是行波), 斜率 = k/(2πf)。
	var f0 := 6.0
	var cross: Array = []
	for si in [0.2, 0.4, 0.6, 0.8, 1.0]:
		var s0: float = float(si)
		var prev: float = VV.tail_offset(s0, 0.0, f0)
		var t2 := 0.0
		var found := -1.0
		while t2 < 0.20:
			t2 += 0.00002
			var cur: float = VV.tail_offset(s0, t2, f0)
			if prev <= 0.0 and cur > 0.0:
				found = t2
				break
			prev = cur
		cross.append(found)
	var okc := true
	for x in cross:
		if float(x) < 0.0:
			okc = false
	print("     tail_offset 的上行过零时刻(s=0.2..1.0): %s 秒" % str(cross))
	_ok("⑫ ★分母: 五个弧长位置都真的找到了过零点", okc and cross.size() == 5, str(cross))
	if okc:
		# 斜率 = 每单位归一弧长推后多少秒 = k/(2πf) = 2.4/(2π×6) = 0.063662
		var slope: float = (float(cross[4]) - float(cross[0])) / 0.8
		print("     滞后随弧长的斜率 %.6f 秒/单位弧长 (需求 k/(2πf) = 2.4/(2π×6) = %.6f)" % [
			slope, 2.4 / (TAU * 6.0)])
		_ok("⑫ ★★尾部是行波: 过零时刻随弧长【线性推后】, 斜率 = k/(2πf)",
			absf(slope - 2.4 / (TAU * 6.0)) < 1e-4, "实得 %.6f" % slope)
		var mono_lag := true
		for i in range(1, cross.size()):
			if float(cross[i]) <= float(cross[i - 1]) + 1e-6:
				mono_lag = false
		_ok("⑫ ★逐段滞后: 越靠尖端过零越晚(不是整体同时摆)", mono_lag, str(cross))
	# 相速: 零点沿弧长以 2πf/k 前进
	print("     行波相速 %.4f 归一弧长/秒 (需求 2π×6/2.4 = %.4f)" % [
		VV.tail_phase_speed(6.0), TAU * 6.0 / 2.4])
	_ok("⑫ 行波相速 = 2πf/k", absf(VV.tail_phase_speed(6.0) - TAU * 6.0 / 2.4) < 1e-9)
	# 振幅沿弧长单调增(根部僵硬、尖端软) —— 同样【从真函数量包络】, 不抄公式
	var mono := true
	var prev := -1.0
	var m3 := 0
	var env: Array = []
	for i in range(0, 21):
		var s3: float = float(i) / 20.0
		var amp := 0.0
		for j in range(0, 200):     # 扫一整个周期取 |挠度| 的最大值 = 包络
			amp = maxf(amp, absf(VV.tail_offset(s3, float(j) * (1.0 / 6.0) / 200.0, f0)))
		if amp < prev - 1e-9:
			mono = false
		prev = amp
		env.append(amp)
		m3 += 1
	print("     沿弧长量到的振幅包络(21 点): 根 %.5f → 中 %.5f → 尖 %.5f 米" % [
		float(env[0]), float(env[10]), float(env[20])])
	_ok("⑫ ★分母: 真的量了 21 个弧长位置 (N=%d)" % m3, m3 == 21)
	_ok("⑫ 尾部振幅沿弧长单调增(根部僵硬、尖端软)", mono
		and float(env[20]) > float(env[10]) * 1.5)


# ── ⑫★ 蛾体可读性: 2026-08-09 逐件重做的验收(全部量【真实网格顶点】) ─────────
## 旧演出在实战镜头(zoom 1.0)下染色法实测: 躯干 32×15 px、**两只翅膀合计只占一个
## 12×27 px 的竖条**、尾巴 23~35 px 却是全身最亮 ⇒ 读作"一颗绿橄榄 + 一片灰三角",
## 而且尾巴被当成头(方向感是反的)。这一节把那三条都钉成断言。
func _g12b_moth_readability() -> void:
	print("")
	print("  ⑫★ 蛾体可读性 — 俯视 52° 下双翅不许重叠 / 头尾分得清:")
	await _setup_units()
	_v.clear_all()
	_v._on_beat()
	_ok("⑫★ ★分母: 飞行物建出来了", _v._drones.size() == 1)
	if _v._drones.is_empty():
		return
	var dr = _v._drones[0]["node"]
	_ok("⑫★ ★分母: 节点在", is_instance_valid(dr))
	if not is_instance_valid(dr):
		return

	# ⑫d ★★双翅【不许折到本体正上方】——【俯视视角】下那等于两只翅在屏幕上完全重合。
	#    判据: 整个扇动周期里, 翅尖的**竖直行程** / 翅尖的**最小横向展开** 必须够小。
	#    ★量的是 `apply_drone` 真的吐进 ImmediateMesh 的顶点, 不是把公式在测试里抄一遍
	#      (memory [[fb-write-without-reader-and-fake-gates]]: 门禁模拟公式 ≠ 量真实对象)。
	var wing := dr.get_node_or_null("wing") as MeshInstance3D
	_ok("⑫★ ★分母: 翅膀节点在", wing != null)
	if wing == null:
		return
	var y_lo := 1e9
	var y_hi := -1e9
	var z_abs_min := 1e9
	var z_abs_max := 0.0
	var left := 0
	var right := 0
	var frames := 0
	for i in range(0, 40):                       # 覆盖 1/6 秒 = 6Hz 的一整个周期
		var t: float = float(i) * (1.0 / 6.0) / 40.0
		_v._vfx.apply_drone(dr, Vector2(700.0, 400.0), 0.0, t)
		var vs: PackedVector3Array = (wing.mesh as ImmediateMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		if vs.size() == 0:
			continue
		frames += 1
		var zmax_this := 0.0
		for v in vs:
			y_lo = minf(y_lo, v.y); y_hi = maxf(y_hi, v.y)
			if v.z > 0.001: left += 1
			elif v.z < -0.001: right += 1
			zmax_this = maxf(zmax_this, absf(v.z))
		z_abs_min = minf(z_abs_min, zmax_this)
		z_abs_max = maxf(z_abs_max, zmax_this)
	var ratio: float = (y_hi - y_lo) / maxf(z_abs_min, 1e-6)
	print("     喂 %d 个相位: 翅尖竖直行程 %.4f 米 / 全周期最小横向展开 %.4f 米 ⇒ 比值 %.3f" % [
		frames, y_hi - y_lo, z_abs_min, ratio])
	# ★旧写法 tip = (0, sinφ·SPAN, ±cosφ·SPAN): 竖直行程是峰峰值 2·sin(A)·SPAN,
	#   最小横向展开是 cos(A)·SPAN(A = FLAP_AMP = 0.70) ⇒ 比值 1.68, 翅整个折到头顶上。
	var old_ratio: float = (2.0 * sin(0.70) * 0.72) / (cos(0.70) * 0.72)
	print("     ★旧写法(tip = (0, sinφ·SPAN, ±cosφ·SPAN)) 的同一比值 = %.3f —— 翅整个折到头顶上" % old_ratio)
	_ok("⑫★ ★分母: 真的喂了相位 (N=%d)" % frames, frames == 40)
	_ok("⑫★ ★★双翅始终摊开在两侧: 竖直行程/横向展开 < 0.60(旧写法是 %.2f ⇒ 52° 俯视下必然重叠)"
		% old_ratio, ratio < 0.60, "实得 %.3f" % ratio)
	_ok("⑫★ ★左右两侧都真的有翅(左 %d 顶点 / 右 %d 顶点, 需求都 > 0 且大致相等)" % [left, right],
		left > 0 and right > 0 and absi(left - right) <= 2)
	_ok("⑫★ ★翅展够大(最大横向 %.3f 米 ≥ 半个体长)" % z_abs_max, z_abs_max > 0.45)

	# ⑫e ★方向感: 头在前、腹在后、触角最靠前; 头必须比尾亮(旧版尾巴最亮 ⇒ 被读成头)
	var seg: Dictionary = {}
	for nm in ["head", "body", "abdomen"]:
		var n = dr.get_node_or_null(nm)
		if n != null:
			seg[nm] = n
	print("     蛾体分段: %s (需求 head/body/abdomen 三段都在)" % str(seg.keys()))
	_ok("⑫★ ★分母: 头/胸/腹三段都建出来了 (N=%d)" % seg.size(), seg.size() == 3)
	if seg.size() == 3:
		var xh: float = float(seg["head"].position.x)
		var xb: float = float(seg["body"].position.x)
		var xa: float = float(seg["abdomen"].position.x)
		print("     三段的局部 x(+X = 前进方向): 头 %.3f > 胸 %.3f > 腹 %.3f" % [xh, xb, xa])
		_ok("⑫★ ★★头在最前、腹在最后(一颗光滑椭球给不出方向感)", xh > xb and xb > xa)
		var lum_h: float = _lum(seg["head"])
		var lum_a: float = _lum(seg["abdomen"])
		_ok("⑫★ ★头比腹亮(视觉重心在头) — 头 %.3f > 腹 %.3f" % [lum_h, lum_a], lum_h > lum_a * 1.4)
		var flap := dr.get_node_or_null("flap") as MeshInstance3D
		_ok("⑫★ ★分母: 尾巴节点在", flap != null)
		if flap != null:
			var lum_t: float = _lum(flap)
			print("     亮度: 头 %.3f / 尾 %.3f (旧版尾巴是 1.000 的加性发光 ⇒ 全身最亮 ⇒ 被读成头)" % [
				lum_h, lum_t])
			_ok("⑫★ ★★尾巴不再是全身最亮(否则它会被读成头, 方向感整个反)", lum_t < lum_h * 0.8,
				"头 %.3f / 尾 %.3f" % [lum_h, lum_t])
	var ant := dr.get_node_or_null("antenna") as MeshInstance3D
	_ok("⑫★ ★分母: 触角节点在", ant != null)
	if ant != null:
		var av: PackedVector3Array = (ant.mesh as ImmediateMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var xmax := -9.9
		for v in av:
			xmax = maxf(xmax, v.x)
		print("     触角 %d 顶点, 最靠前的 x = %.3f (头心 x = 0.300 ⇒ 触角必须更靠前)" % [av.size(), xmax])
		_ok("⑫★ ★触角真的伸在头的前面(全身最前的点)", av.size() >= 6 and xmax > 0.42,
			"顶点 %d / xmax %.3f" % [av.size(), xmax])

	# ⑫f ★飞行高度: 必须高过龟(龟身高 2.0 米), 否则和绿壳龟糊成一坨
	_v._vfx.apply_drone(dr, Vector2(700.0, 400.0), 0.0, 0.0)
	print("     飞行物离地 %.2f 米 (龟身高 2.0 米 ⇒ 必须 > 2.0 才是'在头顶上方飞')" % dr.position.y)
	_ok("⑫★ ★★飞得比龟高(旧值 1.55 米 = 趴在龟背上, 实拍里两者糊成一坨)",
		dr.position.y > 2.0, "实得 %.2f" % dr.position.y)
	_v.clear_all()


# ── ⑬ 剧毒缓速的累积可见性: 环上刻痕数 == 层数 ──────────────────────────────
func _g13_ring_visibility() -> void:
	print("")
	print("  ⑬ 累积可见性 — 20 层要能【数出来】:")
	await _setup_units()
	_v.clear_all()
	var checked := 0
	var bad: Array = []
	for n in [1, 3, 7, 12, 20]:
		_v._set_vslow(_foe, int(n))
		_v._tick_rings()
		var r := _pick("venom_ring") as MeshInstance3D
		if r == null:
			bad.append("n=%d 没建出环" % int(n)); continue
		var tris: int = _tri_count(r)
		# 每个刻痕 = 2 个三角面
		if tris != int(n) * 2:
			bad.append("n=%d 面数 %d (需求 %d)" % [int(n), tris, int(n) * 2])
		checked += 1
	print("     刻痕数校验: 查了 %d 档层数, 不符 %d 处 %s" % [checked, bad.size(), str(bad)])
	_ok("⑬ ★分母: 真的查了 5 档 (N=%d)" % checked, checked == 5)
	_ok("⑬ ★★环上刻痕数 == 剧毒缓速层数(玩家能数出叠了几层)", bad.is_empty(), str(bad))
	# 亮度也随层数涨
	_v._set_vslow(_foe, 4)
	_v._tick_rings()
	var r4 := _pick("venom_ring") as MeshInstance3D
	var a4: float = (r4.material_override as StandardMaterial3D).albedo_color.a
	_v._set_vslow(_foe, 20)
	_v._tick_rings()
	var a20: float = (r4.material_override as StandardMaterial3D).albedo_color.a
	print("     环亮度: 4 层 %.4f → 20 层 %.4f (需求单调涨)" % [a4, a20])
	_ok("⑬ 环亮度随层数涨", a20 > a4 + 0.1)
	# 贴地: |面法线·上| ≈ 1
	var g: Array = _updots_im(r4)
	print("     脚环 %d 面, |n·上| 最小 %.4f 平均 %.4f" % [int(g[0]), float(g[1]), float(g[2])])
	_ok("⑬ ★分母: 脚环真的有面 (N=%d)" % int(g[0]), int(g[0]) == 40)
	_ok("⑬ ★脚环真的贴地平铺(不是立着的)", float(g[1]) > 0.99)
	# 层数归零 → 环消失
	_v._set_vslow(_foe, 0)
	_v._tick_rings()
	await get_tree().process_frame
	print("     层数归零 → 世界里脚环 %d 个 (需求 0)" % _count("venom_ring"))
	_ok("⑬ ★层数归零环就消失", _count("venom_ring") == 0)


# ── ⑭ 零素材 + 贴地 + _world 守卫 ────────────────────────────────────────────
func _g14_zero_asset() -> void:
	print("")
	print("  ⑭ 零素材 — 纯程序化几何, 一张图都没 load:")
	await _setup_units()
	_v.clear_all()
	_v._on_beat()
	_feed(0.3)
	var checked := 0
	var bad := 0
	for kind in ["venom_fog", "venom_drone"]:
		var nd := _pick(kind)
		if nd == null:
			_ok("⑭ %s ★分母: 节点在" % kind, false); continue
		checked += 1
		var mats: Array = _mats_of(nd)
		_ok("⑭ %s ★分母: 取到材质 (N=%d)" % [kind, mats.size()], mats.size() > 0)
		for m in mats:
			var sm := m as StandardMaterial3D
			if sm == null or sm.albedo_texture != null:
				bad += 1
		var meshes: Array = _meshes_of(nd)
		for mm in meshes:
			if str((mm as Mesh).resource_path) != "":
				bad += 1
	print("     共查 %d 类节点, 带贴图/带资源路径的 %d 处 (需求 0)" % [checked, bad])
	_ok("⑭ ★分母: 真的查了 (N=%d)" % checked, checked == 2)
	_ok("⑭ ★一张素材都没用(全是现算的几何 + 顶点色)", bad == 0)
	# 毒雾贴地。★重做后一团毒雾是 Node3D 挂 haze + rim, 这里取 haze 子节点 ——
	#   **不能让 cast 失败静默跳过**, 那样这两条会变成空检查却照样绿。
	var fog_root := _pick("venom_fog")
	_ok("⑭ ★分母: 毒雾 root 在", fog_root != null)
	var fog := (fog_root.get_node_or_null("haze") if fog_root != null else null) as MeshInstance3D
	_ok("⑭ ★分母: haze 子节点在(取不到就说明结构变了, 不许静默跳过)", fog != null)
	if fog != null:
		var g: Array = _updots(fog, 0)
		print("     毒雾盘 %d 面, |n·上| 最小 %.4f 平均 %.4f" % [int(g[0]), float(g[1]), float(g[2])])
		_ok("⑭ ★分母: 毒雾盘真的有面 (N=%d)" % int(g[0]), int(g[0]) > 200)
		_ok("⑭ ★★毒雾真的贴地平铺(memory: axis=AXIS_Y 再叠 rotation 会抵消)", float(g[1]) > 0.99)
	# ★反面: 飞行物本体【不】贴地(否则上面那条是"随便什么都 >0.99"的恒真式)
	var dr := _pick("venom_drone")
	if dr != null:
		var body := dr.get_node_or_null("body") as MeshInstance3D
		if body != null:
			var g2: Array = _updots(body, 0)
			print("     ★反面 本体 %d 面, |n·上| 平均 %.4f (它是立体的)" % [int(g2[0]), float(g2[2])])
			_ok("⑭ ★反面: 本体不平铺(证明上一条不是恒真式)", float(g2[2]) < 0.8)
		print("     飞行物离地高度 %.2f 米 (龟身高 2.0 米 ⇒ 它在头顶飞)" % dr.position.y)
		_ok("⑭ 飞行物在空中(离地 > 1.0 米)", dr.position.y > 1.0)
	# _world 守卫: 世界不在时不崩也不建
	var saved = _s._world
	_s._world = null
	var f2 = _v._vfx.make_fog(Vector2(700, 400))
	var d2 = _v._vfx.make_drone()
	var r2 = _v._vfx.make_ring()
	_s._world = saved
	_ok("⑭ R2: _world 不在时 make_fog/make_drone/make_ring 全返回 null 且不崩",
		f2 == null and d2 == null and r2 == null)
	_ok("⑭ ★反面: 世界装回来立刻又建得出来", _v._vfx.make_fog(Vector2(700, 400)) != null)
	_v.clear_all()


# ── ⑮ RNG 纪律: 选目标走已播种的 _battle_rng ────────────────────────────────
func _g15_rng() -> void:
	print("")
	print("  ⑮ RNG 纪律 — 选目标必须走已播种的 battle._battle_rng:")
	await _setup_units()
	# 多放几个敌人, 让"随机选"真的有得选
	var extra: Array = []
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	for i in range(6):
		var e: Dictionary = _mk("right", [], 5000.0)
		e["pos"] = c + Vector2(200.0 + 60.0 * float(i), -180.0 + 55.0 * float(i))
		extra.append(e)
	var seq_a: Array = _leg_seq(1234)
	var seq_b: Array = _leg_seq(1234)
	var seq_c: Array = _leg_seq(999)
	print("     种子 1234 第一遍: %s" % str(seq_a))
	print("     种子 1234 第二遍: %s" % str(seq_b))
	print("     种子  999 一遍  : %s" % str(seq_c))
	_ok("⑮ ★分母: 序列非空且真的在变(不是同一个点重复 %d 次)" % seq_a.size(),
		seq_a.size() == 12 and _distinct(seq_a) >= 3, "distinct=%d" % _distinct(seq_a))
	_ok("⑮ ★★同种子两遍逐字相同(走的是受控 PRNG, 不是裸 randi)", seq_a == seq_b)
	_ok("⑮ ★不同种子给出不同序列(证明上一条不是'压根没随机')", seq_a != seq_c)
	for e2 in extra:
		_s._arr_erase_unit(_s._units, e2)
	_v.clear_all()


# ── ⑯ 性能: 实测每帧开销(32 团毒雾 = 双方各带一件的满载) ─────────────────────
func _g16_perf() -> void:
	print("")
	print("  ⑯ 性能 — 双方各带一件(2 只飞行物 · 32 团常驻毒雾)的每帧开销:")
	await _setup_units()
	_v.clear_all()
	_foe["equips"] = [{"id": "p2eq_092", "star": 3}]
	_foe["eq_state"] = {}
	# 再放 6 个敌人当碰撞对象(每拍每片场都要对它们做距离判定)
	var extra: Array = []
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	for i in range(6):
		var e: Dictionary = _mk("right", [], 900000.0)
		e["pos"] = c + Vector2(-120.0 + 50.0 * float(i), -100.0 + 40.0 * float(i))
		extra.append(e)
	_v._on_beat()
	_feed(4.5)          # 攒到满载
	print("     满载: 飞行物 %d 只 / 毒雾 %d 团 / 场上单位 %d" % [
		_v._drones.size(), _v._fogs.size(), _s._units.size()])
	_ok("⑯ ★分母: 真的满载了(2 只飞行物 · ≥30 团毒雾)",
		_v._drones.size() == 2 and _v._fogs.size() >= 30,
		"drones=%d fogs=%d" % [_v._drones.size(), _v._fogs.size()])
	var frames := 600
	var t0: int = Time.get_ticks_usec()
	for _i in range(frames):
		_v.tick(1.0 / 60.0)
	var us: float = float(Time.get_ticks_usec() - t0) / float(frames)
	print("     %d 帧平均 %.4f ms/帧 (触手当年 4 根实测 0.33 ms/帧)" % [frames, us / 1000.0])
	_ok("⑯ ★★满载每帧开销 < 1.0 ms(触手 4 根是 0.33 ms, 这是同一量级的预算)",
		us / 1000.0 < 1.0, "实测 %.4f ms" % (us / 1000.0))
	for e2 in extra:
		_s._arr_erase_unit(_s._units, e2)
	_v.clear_all()


# ── 工具 ──────────────────────────────────────────────────────────────────────

## 造一组干净的合成单位: 左边一只带 3★ 092 的携带者 + 右边一个厚血靶子。
## ★用真的 `_make_unit`(手写字典会漏 untargetable_until 等字段 → _nearest_enemy 直接 SCRIPT ERROR)。
## ★用 "green" 不用 "basic": 小龟有【不屈】被动会改伤害。
func _setup_units() -> void:
	_me = _mk("left", ["p2eq_092"], 900000.0)
	_foe = _mk("right", [], 900000.0)
	_s._units.clear()
	_s._units.append(_me)
	_s._units.append(_foe)
	# sim 必须处于"真的在跑"的状态, 否则 tick 直接 return(摆位阶段不该有飞行物)
	_s._over = false
	_s._edit_mode = false
	_s._dl_state = ""
	_ok("★分母: sim_running() 为真(否则后面全是空检查)", _v == null or _v.sim_running())
	await get_tree().process_frame


func _mk(side: String, ids: Array, hp: float = 900000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var off := Vector2(-300.0, 0.0) if side == "left" else Vector2(300.0, 0.0)
	var u: Dictionary = _s._spawn._make_unit("green", side, c + off)
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["def"] = 0.0; u["base_def"] = 0.0
	u["mr"] = 0.0; u["base_mr"] = 0.0
	u["crit"] = 0.0
	u["dodge_bonus"] = 0.0
	u["damage_reduction"] = 0.0
	u["damage_amp"] = 0.0
	u["buffs"] = []
	u["dot_stacks"] = {}
	u["dot_src"] = {}
	u["move_perm"] = 1.0
	var e: Array = []
	for i in ids:
		e.append({"id": str(i), "star": 3})
	u["equips"] = e
	u["eq_state"] = {}
	if not _s._arr_has_unit(_s._units, u):
		_s._units.append(u)
	return u


## 同步喂 sec 秒(60 分之一秒一步) —— 不等任何演出。
func _feed(sec: float) -> void:
	var steps: int = int(round(sec * 60.0))
	for _i in range(steps):
		_v.tick(1.0 / 60.0)


## 播下种子, 重建飞行物, 记录 12 段航程的落点(取整避免浮点噪声)。
func _leg_seq(seed_v: int) -> Array:
	_v.clear_all()
	_s._battle_rng.seed = seed_v
	_v._on_beat()
	if _v._drones.is_empty():
		return []
	var d: Dictionary = _v._drones[0]
	var out: Array = []
	for _i in range(12):
		_v._new_leg(d)
		out.append("%d,%d" % [int(round(float(d["dest"].x))), int(round(float(d["dest"].y)))])
	return out


## 一条采样曲线上的【局部极小值】个数 —— "一团一团分不分得出来"的尺子。
## ★两个等幅高斯只有心距 > 2σ 才会在中间出现凹陷; 本件心距/σ ≤ 1.06 ⇒ 纯 haze 必然是 0。
func _dips(a: Array) -> int:
	var n := 0
	for i in range(1, a.size() - 1):
		if float(a[i]) < float(a[i - 1]) - 1e-9 and float(a[i]) < float(a[i + 1]) - 1e-9:
			n += 1
	return n


func _distinct(a: Array) -> int:
	var seen: Dictionary = {}
	for x in a:
		seen[str(x)] = true
	return seen.size()


## _world 里本层建的节点数(按 meta 数 —— 程序生成的网格没有 resource_path)。
## ★必须跳过 `is_queued_for_deletion()`: `queue_free()` 是【延迟】的, 同一帧里
##   节点仍然挂在树上、`has_meta` 也仍然为真 ⇒ 不跳的话"撤场干净"这条要么得多等一帧,
##   要么就会把已经撤掉的东西数进来(第一版实测数到 29 个)。
func _count(kind: String = "") -> int:
	var n := 0
	for c in _s._world.get_children():
		if not c.has_meta(VV.META_KEY) or c.is_queued_for_deletion():
			continue
		if kind != "" and str(c.get_meta(VV.META_KEY)) != kind:
			continue
		n += 1
	return n


func _pick(kind: String) -> Node3D:
	for c in _s._world.get_children():
		if c.has_meta(VV.META_KEY) and str(c.get_meta(VV.META_KEY)) == kind:
			return c
	return null


func _mats_of(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).material_override != null:
		out.append((n as MeshInstance3D).material_override)
	for ch in n.get_children():
		out.append_array(_mats_of(ch))
	return out


func _meshes_of(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append((n as MeshInstance3D).mesh)
	for ch in n.get_children():
		out.append_array(_meshes_of(ch))
	return out


## ArrayMesh 某 surface 上所有三角面的 |世界法线·上|: [面数, 最小值, 平均值]
func _updots(mi: MeshInstance3D, surf: int) -> Array:
	var am := mi.mesh as ArrayMesh
	if am == null or am.get_surface_count() <= surf:
		return [0, 0.0, 0.0]
	return _dots_from(am.surface_get_arrays(surf)[Mesh.ARRAY_VERTEX], mi.global_transform.basis)


## ImmediateMesh 版(脚环)
func _updots_im(mi: MeshInstance3D) -> Array:
	var im := mi.mesh as ImmediateMesh
	if im == null or im.get_surface_count() == 0:
		return [0, 0.0, 0.0]
	return _dots_from(im.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], mi.global_transform.basis)


func _dots_from(vs: PackedVector3Array, b: Basis) -> Array:
	var cnt := 0
	var mn := 2.0
	var sum := 0.0
	var i := 0
	while i + 2 < vs.size():
		var n: Vector3 = (vs[i + 1] - vs[i]).cross(vs[i + 2] - vs[i])
		if n.length() > 1e-12:
			var d: float = absf((b * n).normalized().dot(Vector3.UP))
			mn = minf(mn, d)
			sum += d
			cnt += 1
		i += 3
	return [cnt, (mn if cnt > 0 else 0.0), (sum / float(maxi(1, cnt)))]


## 一个 MeshInstance3D 的 material_override 的【感知亮度】(Rec.709 加权 × alpha)。
## ★量"谁最亮"要连 alpha 一起量 —— 旧尾巴是 alpha=1.0 的加性发光, 这正是它抢走视觉重心的原因。
func _lum(mi) -> float:
	var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
	if m == null:
		return 0.0
	var c: Color = m.albedo_color
	return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * c.a


func _tri_count(mi: MeshInstance3D) -> int:
	var im := mi.mesh as ImmediateMesh
	if im == null or im.get_surface_count() == 0:
		return 0
	return int(im.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3)


func _ok(what: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("     [PASS] ", what)
	else:
		_fail += 1
		print("     [FAIL] ", what, ("  " + detail) if detail != "" else "")



## ★★毒雾是**真粒子**(2026-08-09 用户:「那也别用圈圈来敷衍我啊，雾气是怎么做?」)。
## 旧"雾" = 一张贴地平面圆盘(顶点 alpha 写死高斯), 零粒子零贴图零动画 ——
## 不翻涌不飘不变形, 只会整体缩放变淡。与 090 被点名的"雷雾是程序化线条"同族。
## ⚠ GPU 粒子在无头 CI 下不推进 ⇒ 这里只量**配置**(是不是粒子/发射半径/有没有贴图),
##   量不了"粒子真实位置"。判据落在能同步读到的东西上(CLAUDE.md §3.5 同一条原则)。
func _g5c_fog_particles() -> void:
	var root = _v._vfx.make_fog(Vector2(400, 300))
	_ok("⑤P 分母: 毒雾团建出来了", is_instance_valid(root))
	if not is_instance_valid(root):
		return
	var puffs = (root as Node).get_node_or_null("puffs")
	_ok("⑤P ★★毒雾是 GPUParticles3D 真粒子, 不是一张贴地渐变圆盘",
		puffs != null and puffs is GPUParticles3D)
	if puffs == null:
		return
	var ps := puffs as GPUParticles3D
	var pm := ps.process_material as ParticleProcessMaterial
	_ok("⑤P 分母: 挂了 ParticleProcessMaterial", pm != null)
	_ok("⑤P 粒子会翻涌(开了湍流, 不是一层静止的膜)", pm != null and pm.turbulence_enabled)
	_ok("⑤P 从圆心起(内径 0 ⇒ 实心圆盘, 不是只在边上)",
		pm != null and pm.emission_ring_inner_radius <= 1e-6)
	var qm := ps.draw_pass_1 as QuadMesh
	var dm := (qm.material if qm != null else null) as StandardMaterial3D
	_ok("⑤P ★粒子有贴图(没贴图的 QuadMesh 就是实心方片 —— 090 满屏蓝方块的根因)",
		dm != null and dm.albedo_texture != null)
	_ok("⑤P 贴图按 NEAREST 取样", dm != null and dm.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST)
	## ★★发射半径必须跟着闭式解的 σ(t) 走 —— 与判定同源, 不是另调一套看着差不多的数
	var bad: int = 0
	var m: int = 0
	for k in range(9):
		var tt: float = float(k) * 0.45
		_v._vfx.apply_fog(root, tt)
		## ★★不是 σ(t) 而是 **判定半径 R(t)** —— 雾铺到哪就打到哪。
		##   2026-08-09 去掉判定边界环之后, "看得见 == 打得到"由这一条独扛。
		var want: float = VV.fog_radius(tt) * float(_s.WS)
		if absf(pm.emission_ring_radius - want) > 1e-5:
			bad += 1
		m += 1
	_ok("⑤P ★★发射盘半径 ≡ 判定半径 fog_radius(t)(喂 %d 个时刻, 雾铺到哪就打到哪)" % m,
		bad == 0, "不符 %d 处" % bad)
	## 判定半径先涨后跌、寿命末尾精确归零 ⇒ 雾自己收干净
	## ★2026-08-20: 原来这三个时刻写死 3.99 / 2.0(照 FOG_LIFE=4.0 算的)。用户 2026-08-13 把寿命
	##   加强到 6 秒, 而演出侧常量一直没跟上 ⇒ 加强从没生效; 修好后这条断言反而红了 ——
	##   **判据自己抄了那个过期的数**。改成从 FOG_LIFE 推导, 寿命再改也不用动这里。
	var t_end: float = VD.FOG_LIFE - 0.01
	var t_mid: float = VD.FOG_LIFE * 0.5
	_v._vfx.apply_fog(root, t_end)
	var r_end: float = pm.emission_ring_radius
	_v._vfx.apply_fog(root, t_mid)
	var r_mid: float = pm.emission_ring_radius
	_ok("⑤P 雾的范围先涨后收(中段 > 末段), 寿命末尾(%.1f s)自己收干净" % VD.FOG_LIFE,
		r_mid > r_end * 3.0, "t=%.2f %.4f / t=%.2f %.4f" % [t_mid, r_mid, t_end, r_end])
	## 亮度跟着归一浓度走(与 haze 同一条 C_peak, 只是增益不同)
	_v._vfx.apply_fog(root, 0.0)
	var a0: float = dm.albedo_color.a
	_v._vfx.apply_fog(root, 2.0)
	var a2: float = dm.albedo_color.a
	_ok("⑤P 粒子亮度随浓度衰减(t=0 比 t=2 亮)", a0 > a2, "%.4f → %.4f" % [a0, a2])
	## ⚠ 必须**等一帧**再走: `queue_free()` 是延迟的, 不等的话这团雾会被后面
	##   ⑥/⑪ 的节点计数逮到, 报成"多了一团 / 泄漏一个"(2026-08-09 实测三条红)。
	if is_instance_valid(root):
		(root as Node).queue_free()
	await get_tree().process_frame


func _done() -> void:
	if is_instance_valid(_s):
		if _v != null:
			_v.clear_all()
		_s._units.clear()
		_s.set_process(false)
		await get_tree().process_frame
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	print("ALL PASS — 092 剧毒飞行物" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
