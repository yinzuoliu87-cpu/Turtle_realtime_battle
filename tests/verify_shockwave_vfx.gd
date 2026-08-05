extends Node
## verify_shockwave_vfx.gd — 盾羁绊【怒气冲击波】演出门禁 (方案书 docs/plans/20260804-羁绊特效批.md · 批 B · B2)
##
## 守的东西分两层, 两层都要:
##   【物理层】三条闭式解真的是那三条闭式解 —— Sedov–Taylor 尺度不变 / Friedlander 精确过零 +
##            负压极值位置 / 尘埃位移是超压的积分 / Hopkinson–Cranz 立方根。
##            ★这些是**性质断言**, 不是把公式抄一遍: 手调出来的缓动曲线一条都过不了。
##   【接线层】走羁绊系统的**真入口**(`_shield_syn._rage` / `.tick`), 节点真的进 _world,
##            每帧驱动真的被调到, 撤场真的干净。
##
## ⚠ 铁律 (CLAUDE.md §3.5 / 方案书 §7.1): **一条测特效的用例不该等任何动画 tween 跑完。**
##   本文件全部同步: 形态由纯函数 `ShockwaveVfx.shape_at(u)` 给, 节点由 `apply_at(h,u)`
##   直接写到任意时刻 —— 想看 u=0.9 的样子就直接喂 0.9, 不用等。
##
## ⚠ 用干净合成单位, 不用随机 spawn (memory [[fb-ci-vs-local-divergence]])。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_shockwave_vfx.tscn
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SV := preload("res://scripts/scenes/battle/synergy_vfx.gd")
const SW := preload("res://scripts/scenes/battle/shockwave_vfx.gd")

## ★写字面值不引用被测常量 —— 引用就是拿代码跟它自己比 = 恒真式。
const E_CONST := 2.718281828459045
const WANT_SEDOV_EXP := 0.4                 # Sedov–Taylor: R ∝ t^(2/5)
const WANT_R_4X := 1.7411011265922482       # 4^0.4  (尺度不变性的比值)
const WANT_R_HALF := 0.7578582832551990     # 0.5^0.4
const WANT_NEG_PEAK := -0.1353352832366127  # −e^(−2), Friedlander 负压极小
const WANT_NEG_TAU := 2.0                   # 负压极小的位置
const WANT_CUBE5 := 1.7099759466766968      # 5^(1/3), Hopkinson–Cranz 五连发
const WANT_POS_FRAC := 1.0 / 6.0            # 正压相占比 (TAU_END=6)

var _n := 0
var _fail := 0
var _s
var _syn
var _sw
var _me
var _foe


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 盾【怒气冲击波】爆轰演出 (批 B·B2) ===")

	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(8):
		await get_tree().process_frame

	await _g0_wiring()
	if _syn == null or _sw == null:
		print("")
		print("FAIL x%d — ★分母没过, 后面全是空检查" % maxi(1, _fail))
		get_tree().quit(1); return
	_g1_sedov()
	_g2_friedlander()
	_g3_negative_phase()
	_g4_cube_root()
	await _g5_real_entry()
	await _g6_merge_u2()
	await _g7_size()
	await _g8_grounded()
	await _g9_teardown()
	await _g10_frame_driver()
	await _g11_zero_asset()
	await _g12_world_guard()
	await _done()


# ── ⓪ ★分母 + 接线 ───────────────────────────────────────────────────────────
func _g0_wiring() -> void:
	print("")
	print("  ⓪ ★分母 + 接线:")
	_ok("⓪ 世界节点 _world 在", is_instance_valid(_s._world))
	_ok("⓪ 场上有单位 (N=%d)" % _s._units.size(), _s._units.size() > 0)
	var got = _s._vfx._syn
	_ok("⓪ BattleVfx 把 SynergyVfx 接出来了", got != null and got is SynergyVfx)
	if got == null:
		return
	_syn = got
	_ok("⓪ ★SynergyVfx 把 ShockwaveVfx 接出来了 (_syn._shock)",
		_syn._shock != null and _syn._shock is ShockwaveVfx)
	if _syn._shock == null:
		return
	_sw = _syn._shock
	_ok("⓪ 它拿到的是同一个 battle", is_same(_sw.battle, _s))
	_ok("⓪ 盾羁绊系统在 (_shield_syn)", _s._shield_syn != null)
	await get_tree().process_frame


# ── ① 物理: Sedov–Taylor 强爆轰自相似解 ──────────────────────────────────────
## ★这一组不比"某一点的值", 比的是【尺度不变性】: R(k·u)/R(u) 与 u 无关, 恒等于 k^0.4。
##   任何手调缓动(ease_out / lerp / 分段曲线)都不可能对所有 (k,u) 都满足这一条。
func _g1_sedov() -> void:
	print("")
	print("  ① 物理 — Sedov–Taylor 波前 R ∝ t^(2/5):")
	var checked := 0
	var worst := 0.0
	for k in [2.0, 3.0, 4.0, 7.0]:
		for u in [0.01, 0.05, 0.1, 0.2, 0.24]:
			## ★k·u > 1 的组要跳过 —— sedov_radius 把 u 钳在 [0,1](动画到 u=1 就结束了),
			##   钳过之后比值当然不再是 k^0.4。这不是公式错, 是【采样跑出定义域】。
			##   第一版没跳, 20 组里有 2 组落在钳区 ⇒ 偏差 0.385, 门禁当场红。留着这条注释免得下次再踩。
			if float(u) * float(k) > 1.0:
				continue
			var a: float = SW.sedov_radius(float(u))
			var b: float = SW.sedov_radius(float(u) * float(k))
			if a <= 0.0:
				continue
			var got: float = b / a
			var want: float = pow(float(k), WANT_SEDOV_EXP)
			worst = maxf(worst, absf(got - want))
			checked += 1
	print("     扫了 %d 组 (k,u); 最大偏差 %.12f" % [checked, worst])
	_ok("① ★分母: 真的扫了组数 (N=%d, 20 组里 2 组 k·u>1 被跳过)" % checked, checked == 18)
	_ok("① ★尺度不变: R(k·u)/R(u) ≡ k^0.4 对所有 (k,u) 成立", worst < 1e-9,
		"最大偏差 %.12f" % worst)
	print("     R(4u)/R(u) = %.10f  (需求 4^0.4 = %.10f)" % [
		SW.sedov_radius(0.4) / SW.sedov_radius(0.1), WANT_R_4X])
	_ok("① R(1.0) = 1.0 (归一)", absf(SW.sedov_radius(1.0) - 1.0) < 1e-12)
	_ok("① R(0.0) = 0.0 (从一点炸开)", absf(SW.sedov_radius(0.0)) < 1e-12)
	print("     R(0.5) = %.10f" % SW.sedov_radius(0.5))
	_ok("① ★反面: R(0.5) ≠ 0.5 —— 不是线性扩散(水波纹)", absf(SW.sedov_radius(0.5) - 0.5) > 0.2)
	_ok("① R(0.5) = 0.5^0.4 = %.6f" % WANT_R_HALF,
		absf(SW.sedov_radius(0.5) - WANT_R_HALF) < 1e-9)
	## 起步速度: 前 1/60 秒(u=1/33 @0.55s) 就冲到 22% —— 这是"爆炸"与"涟漪"的分水岭
	print("     u=0.03 时已到 %.1f%% 半径 (线性的话只有 3.0%%)" % (SW.sedov_radius(0.03) * 100.0))
	_ok("① ★起步就冲出去 (u=0.03 时 ≥20% 半径)", SW.sedov_radius(0.03) > 0.20)


# ── ② 物理: Friedlander 超压波形 ─────────────────────────────────────────────
func _g2_friedlander() -> void:
	print("")
	print("  ② 物理 — Friedlander 超压 Δp(τ)=(1−τ)e^(−τ):")
	print("     f(0)=%.6f  f(1)=%.12f  f(2)=%.6f  f(6)=%.6f" % [
		SW.friedlander(0.0), SW.friedlander(1.0), SW.friedlander(2.0), SW.friedlander(6.0)])
	_ok("② 起爆瞬间峰值 = 1.0", absf(SW.friedlander(0.0) - 1.0) < 1e-12)
	_ok("② ★τ=1 精确过零(正压相结束 —— 解析地标, 不是拍的数)",
		absf(SW.friedlander(1.0)) < 1e-12)
	_ok("② τ>1 进负压相 (f(1.5) < 0)", SW.friedlander(1.5) < 0.0)
	# 扫出负压极小的位置 —— 不抄公式, 数值找 argmin
	var best_t := 0.0
	var best_v := 0.0
	var t := 1.0
	var steps := 0
	while t <= 6.0:
		var v: float = SW.friedlander(t)
		if v < best_v:
			best_v = v; best_t = t
		t += 0.0005
		steps += 1
	print("     数值扫 τ∈[1,6] (%d 步): 极小 %.9f @ τ=%.4f" % [steps, best_v, best_t])
	_ok("② ★分母: 真的扫了 (N=%d)" % steps, steps > 9000)
	_ok("② ★负压极小值 = −e^(−2) = %.9f" % WANT_NEG_PEAK, absf(best_v - WANT_NEG_PEAK) < 1e-6,
		"实得 %.9f" % best_v)
	_ok("② ★负压极小【位置】= τ=2.0 (解析地标)", absf(best_t - WANT_NEG_TAU) < 0.002,
		"实得 %.4f" % best_t)
	var tail: float = absf(SW.friedlander(6.0)) / absf(WANT_NEG_PEAK)
	print("     收尾残余 = 负压峰的 %.1f%% (TAU_END=6 就是为了让它 <10%%, 否则会'啪'一下断掉)" % (tail * 100.0))
	_ok("② 收尾残余 < 10% (TAU_END 选 6 的理由)", tail < 0.10)


# ── ③ ★负压相 —— 单调缓动做不出来的那条 ─────────────────────────────────────
## 触手那条判据 3 说的"余振二次峰": 判据必须落在**单调曲线过不了**的性质上。
## 这里是: 尘埃环半径【先涨后跌】, 且峰值恰好落在正压相结束的那一刻。
func _g3_negative_phase() -> void:
	print("")
	print("  ③ ★负压相 — 尘埃先被推出去、再被吸回来:")
	var u := 0.0
	var top_u := 0.0
	var top_r := -1.0
	var last := -1.0
	var rises := 0
	var falls := 0
	var n := 0
	while u <= 1.0001:
		var r: float = float(SW.shape_at(u)["r_dust"])
		if r > top_r:
			top_r = r; top_u = u
		if last >= 0.0:
			if r > last + 1e-9: rises += 1
			elif r < last - 1e-9: falls += 1
		last = r
		u += 0.0005
		n += 1
	print("     扫 %d 个时刻: 上升 %d 段 / 下降 %d 段; 峰值 r=%.4f @ u=%.4f" % [
		n, rises, falls, top_r, top_u])
	_ok("③ ★分母: 真的扫了 (N=%d)" % n, n > 1900)
	_ok("③ ★★半径【先涨后跌】(单调缓动做不出来)", rises > 100 and falls > 100)
	_ok("③ ★峰值恰在正压相结束处 u = 1/TAU_END = %.4f" % WANT_POS_FRAC,
		absf(top_u - WANT_POS_FRAC) < 0.002, "实得 %.4f" % top_u)
	_ok("③ 峰值就是最大半径 1.0 (τ·e^(1−τ) 的极大恰为 1)", absf(top_r - 1.0) < 1e-3)
	var r_end: float = float(SW.shape_at(1.0)["r_dust"])
	print("     收尾半径 %.4f (起始 %.4f) —— 被负压吸回去了" % [r_end, float(SW.shape_at(0.0)["r_dust"])])
	_ok("③ 收尾比峰值小得多 (真的被吸回来了)", r_end < top_r * 0.7)

	# ★反面: 波前半径全程单调不减 —— 证明 ③ 不是"什么曲线都非单调"
	var mono := true
	var prev := -1.0
	var u2 := 0.0
	var n2 := 0
	while u2 <= 1.0001:
		var r2: float = float(SW.shape_at(u2)["r_shock"])
		if r2 < prev - 1e-9:
			mono = false
		prev = r2
		u2 += 0.001
		n2 += 1
	print("     波前半径扫 %d 个时刻: 单调不减 = %s" % [n2, str(mono)])
	_ok("③ ★反面: 波前半径全程单调不减(证明上一条不是恒真式)", mono and n2 > 900)

	# ★★积分关系: 尘埃位移是超压的积分 ⇒ 数值微分应当 ≡ e × Friedlander。
	#   这一条把两条曲线焊在一起 —— 谁被单独手调都会红。
	var worst := 0.0
	var m := 0
	for i in range(1, 60):
		var tau: float = float(i) * 0.1
		var h := 1e-4
		var num: float = (SW.dust_disp(tau + h) - SW.dust_disp(tau - h)) / (2.0 * h)
		var want: float = E_CONST * SW.friedlander(tau)
		worst = maxf(worst, absf(num - want))
		m += 1
	print("     d/dτ[尘埃位移] vs e×Δp: 扫 %d 点, 最大偏差 %.12f" % [m, worst])
	_ok("③ ★★尘埃位移【是】超压的积分 (数值微分对上 e×Friedlander)", worst < 1e-4 and m == 59,
		"最大偏差 %.12f / N=%d" % [worst, m])


# ── ④ 物理: Hopkinson–Cranz 立方根定律 (U2-B 的合并倍率) ─────────────────────
func _g4_cube_root() -> void:
	print("")
	print("  ④ 物理 — 连发合并走 Hopkinson–Cranz R ∝ W^(1/3) (未决点 U2 → 用户拍板 B):")
	var worst := 0.0
	for k in range(1, 6):
		var sc: float = SW.energy_scale(k)
		var cube: float = sc * sc * sc
		worst = maxf(worst, absf(cube - float(k)))
		print("     fired=%d → 半径 ×%.6f  (立方 = %.6f, 需求 %d)" % [k, sc, cube, k])
	_ok("④ ★能量线性可加: energy_scale(n)³ ≡ n", worst < 1e-9, "最大偏差 %.12f" % worst)
	_ok("④ fired=1 不放大", absf(SW.energy_scale(1) - 1.0) < 1e-12)
	_ok("④ fired=5 → ×%.6f" % WANT_CUBE5, absf(SW.energy_scale(5) - WANT_CUBE5) < 1e-9)
	_ok("④ ★反面: 不是线性放大(5 连发不是 5 倍大)", SW.energy_scale(5) < 2.0)
	_ok("④ ★反面: 也不是不放大(看得出比单发大)", SW.energy_scale(5) > 1.5)
	var d1: float = SW.duration_s(1)
	var d5: float = SW.duration_s(5)
	print("     时长 %.3f s → %.3f s (比值 %.6f, 需求同律 %.6f)" % [d1, d5, d5 / d1, WANT_CUBE5])
	_ok("④ ★时长与半径同律 (t⁺ ∝ W^(1/3))", absf(d5 / d1 - WANT_CUBE5) < 1e-6)
	var r1: float = _sw.radius_m(1)
	var r5: float = _sw.radius_m(5)
	print("     最大半径 %.3f m → %.3f m (比值 %.6f)" % [r1, r5, r5 / r1])
	_ok("④ 半径也同律", absf(r5 / r1 - WANT_CUBE5) < 1e-6)


# ── ⑤ 形态A: 走【羁绊真入口】把节点建进 _world ──────────────────────────────
## §7.3 明令: 不许直接点演出函数。这里走 `_shield_syn._rage(...)`,
## 与 verify_shield_synergy 用的是同一个入口。
func _g5_real_entry() -> void:
	print("")
	print("  ⑤ 形态A — 走羁绊真入口 _shield_syn._rage() 建节点:")
	await _setup_units()
	await _reset()
	_ok("⑤ ★分母: 复位后本层节点 0 个", _count() == 0)
	_ok("⑤ ★分母: 顶档盾 (tier=%d)" % int(_s._synergy.tier_for(_me, "盾")),
		int(_s._synergy.tier_for(_me, "盾")) == 3)

	_me["_shield_rage"] = 0.0
	_s._shield_syn._rage(_me, 3, 400.0)
	print("     _rage(400) → 波前 %d 个 / 尘埃 %d 个 (各需求 1)" % [
		_count("shockwave"), _count("shockwave_dust")])
	_ok("⑤ 半球壳节点建出来了", _count("shockwave") == 1)
	_ok("⑤ 贴地环节点建出来了", _count("shockwave_ring") == 1)
	_ok("⑤ 尘埃节点建出来了", _count("shockwave_dust") == 1)
	_ok("⑤ 波前是 MeshInstance3D(程序化网格, 不是贴片)", _pick("shockwave") is MeshInstance3D)
	_ok("⑤ 句柄进了 _shocks 表(否则没人每帧推它)", _syn._shocks.size() == 1)

	# ★反面①: 攒不满阈值 → 一个节点都不该建
	await _reset()
	_me["_shield_rage"] = 0.0
	_s._shield_syn._rage(_me, 3, 399.0)
	print("     ★反面 _rage(399) → %d 个 (需求 0)" % _count("shockwave"))
	_ok("⑤ ★反面: 攒到 399 不放(阈值 400)", _count("shockwave") == 0)

	# ★反面②: 场上没有活敌人 → _shockwave 空转, 不该"没打出去却炸了一下"
	await _reset()
	_foe["alive"] = false
	_me["_shield_rage"] = 0.0
	_s._shield_syn._rage(_me, 3, 400.0)
	print("     ★反面 敌人全死时 _rage(400) → %d 个 (需求 0)" % _count("shockwave"))
	_ok("⑤ ★反面: 没打出去就不放演出", _count("shockwave") == 0)
	_foe["alive"] = true

	# 完整路径 on_damaged 也走得通
	await _reset()
	_me["_shield_rage"] = 0.0
	_s._shield_syn.on_damaged(_me, _foe, 400)
	print("     on_damaged(400) → %d 个 (需求 1)" % _count("shockwave"))
	_ok("⑤ ★完整承伤路径 on_damaged 也放得出来", _count("shockwave") == 1)


# ── ⑥ ★U2-B 验收: 连发合并成一个更大的, 而【数值一条没变】────────────────────
func _g6_merge_u2() -> void:
	print("")
	print("  ⑥ ★U2-B — 5 连发合并成【一个】更大的, 伤害照发 5 次:")
	await _setup_units()

	# 单发基准
	await _reset()
	_foe["hp"] = 900000.0
	_me["_shield_rage"] = 0.0; _me["shield"] = 0.0
	_s._shield_syn._rage(_me, 3, 400.0)
	var d1: float = 900000.0 - float(_foe["hp"])
	var n1: int = _count("shockwave")
	var h1: Dictionary = _syn._shocks[0] if _syn._shocks.size() > 0 else {}
	var r1: float = float(h1.get("r_m", 0.0))

	# 五连发
	await _reset()
	_foe["hp"] = 900000.0
	_me["_shield_rage"] = 0.0; _me["shield"] = 0.0
	_s._shield_syn._rage(_me, 3, 2000.0)
	var d5: float = 900000.0 - float(_foe["hp"])
	var n5: int = _count("shockwave")
	var h5: Dictionary = _syn._shocks[0] if _syn._shocks.size() > 0 else {}
	var r5: float = float(h5.get("r_m", 0.0))

	print("     单发: 节点 %d 个 / 敌掉 %.0f / 最大半径 %.3f m" % [n1, d1, r1])
	print("     五连: 节点 %d 个 / 敌掉 %.0f / 最大半径 %.3f m" % [n5, d5, r5])
	_ok("⑥ ★分母: 单发确实建了 1 个且打出了伤害", n1 == 1 and d1 > 0.0)
	_ok("⑥ ★★5 连发只建【一个】节点(不是 5 个叠在同一点)", n5 == 1, "实得 %d" % n5)
	_ok("⑥ ★★★数值一条没变: 5 连发伤害 = 单发 × 5 (合并的只有演出)",
		absf(d5 - d1 * 5.0) < 3.0, "实得 %.0f, 需求 %.0f" % [d5, d1 * 5.0])
	_ok("⑥ 句柄记着 fired=5", int(h5.get("fired", 0)) == 5, "实得 %d" % int(h5.get("fired", 0)))
	_ok("⑥ 句柄记着 fired=1", int(h1.get("fired", 0)) == 1)
	print("     半径比 %.6f (需求 5^(1/3) = %.6f)" % [r5 / maxf(r1, 1e-9), WANT_CUBE5])
	_ok("⑥ ★合并后的半径按立方根定律放大", absf(r5 / maxf(r1, 1e-9) - WANT_CUBE5) < 1e-5)
	_ok("⑥ ★反面: 不是 5 倍半径(那会糊满半个战场)", r5 < r1 * 2.0)


# ── ⑦ 形态D: 尺寸不离谱 —— 量【真实节点】的 scale, 不抄公式 ─────────────────
## ★怒气冲击波【没有 AOE】: 它只打一个最近的敌人。所以视觉直径不能大到让玩家
##   以为这是范围伤害 (方案书 R9 / memory [[fb-verify-must-run-the-real-path]])。
func _g7_size() -> void:
	print("")
	print("  ⑦ 形态D — 尺寸(战场 %.1f×%.1f m · 龟身高 %.2f m):" % [
		_s.ARENA.size.x * _s.WS, _s.ARENA.size.y * _s.WS, _s.TARGET_BODY_H])
	await _setup_units()
	await _reset()
	_me["_shield_rage"] = 0.0
	_s._shield_syn._rage(_me, 3, 400.0)
	var mi := _pick("shockwave") as MeshInstance3D
	_ok("⑦ ★分母: 拿到真实节点", mi != null)
	if mi == null:
		return
	var h: Dictionary = _syn._shocks[0]
	# ★把节点推到 u=1.0(最大) —— 同步, 不等 tween
	_sw.apply_at(h, 1.0)
	var dia_max: float = mi.scale.x * 2.0
	_sw.apply_at(h, 0.0)
	var dia_0: float = mi.scale.x * 2.0
	_sw.apply_at(h, 0.03)
	var dia_early: float = mi.scale.x * 2.0
	print("     单发直径: u=0 → %.4f m / u=0.03 → %.3f m / u=1 → %.3f m" % [dia_0, dia_early, dia_max])
	_ok("⑦ 最大直径在 [2.0, 5.0] m (量真实节点 scale, 约两只龟宽)",
		dia_max >= 2.0 and dia_max <= 5.0, "实得 %.3f" % dia_max)
	_ok("⑦ ★不能读成 AOE: 直径 < 战场宽的 20%%", dia_max < _s.ARENA.size.x * _s.WS * 0.20)
	_ok("⑦ u=0 时几乎是一点(从一点炸开)", dia_0 < 0.01)
	_ok("⑦ ★起手就冲出去(u=0.03 已过最大的 20%)", dia_early > dia_max * 0.20)

	## ★★★这条守的是【尺子有没有量到玩家真看得见的东西】(用户判据 5)。
	##   第一版 alpha 直接用超压 ⇒ 波前还看得见时只走到 51% 半径, 剩下一半在全透明下长完 ——
	##   门禁量的"最大直径 3.84 m"是玩家永远看不到的数, 而它照样绿。
	##   ⇒ 改成: 扫全程, 在【亮度 ≥ 可见阈值】的那些时刻里取最大半径, 拿它跟绝对最大比。
	var vis_r := 0.0
	var vis_n := 0
	var uu := 0.0
	while uu <= 1.0001:
		var sh: Dictionary = SW.shape_at(uu)
		if float(sh["a_shock"]) >= 0.15:
			vis_r = maxf(vis_r, float(sh["r_shock"]))
			vis_n += 1
		uu += 0.001
	print("     波前【还看得见时】(a≥0.15, 共 %d 个时刻)最远走到 %.1f%% 最大半径" % [
		vis_n, vis_r * 100.0])
	_ok("⑦ ★分母: 真有看得见的时刻 (N=%d)" % vis_n, vis_n > 20)
	_ok("⑦ ★★最大半径是【看得见的时候】达到的(不是全透明状态下长完的)", vis_r >= 0.85,
		"实得 %.3f" % vis_r)
	## 亮度的两个解析地标: 起爆满亮 / 正压相结束精确归零
	print("     亮度 a(τ=0)=%.4f  a(τ=1)=%.6f" % [
		float(SW.shape_at(0.0)["a_shock"]), float(SW.shape_at(WANT_POS_FRAC)["a_shock"])])
	_ok("⑦ 起爆瞬间满亮", absf(float(SW.shape_at(0.0)["a_shock"]) - 1.0) < 1e-9)
	_ok("⑦ ★正压相结束时亮度精确归零(与半径到顶是同一瞬间)",
		float(SW.shape_at(WANT_POS_FRAC)["a_shock"]) < 1e-6)

	await _reset()
	_me["_shield_rage"] = 0.0
	_s._shield_syn._rage(_me, 3, 2000.0)
	var mi5 := _pick("shockwave") as MeshInstance3D
	if mi5 != null:
		_sw.apply_at(_syn._shocks[0], 1.0)
		var d5: float = mi5.scale.x * 2.0
		print("     五连直径: %.3f m" % d5)
		_ok("⑦ 五连最大直径仍 < 8 m (合并了也不糊屏)", d5 < 8.0, "实得 %.3f" % d5)
		_ok("⑦ 五连比单发大得看得出来", d5 > dia_max * 1.5)


# ── ⑧ 形态C: 贴地的真的贴地 (方案书 R10) ────────────────────────────────────
## 本条量的是【真实三角面法线】, 不是 Sprite3D 的 axis ——
## 本层是 ArrayMesh, 压根没有 "axis=AXIS_Y 再叠 rotation.x=-90 会抵消" 那个歧义,
## 但"我以为贴地了其实立着"这个失败模式一样存在, 所以照量。
func _g8_grounded() -> void:
	print("")
	print("  ⑧ 形态C — 贴地面真的平铺 (|面法线·上| 该 ≈1.000):")
	await _setup_units()
	await _reset()
	_me["_shield_rage"] = 0.0
	_s._shield_syn._rage(_me, 3, 400.0)
	var mi := _pick("shockwave") as MeshInstance3D
	var du := _pick("shockwave_dust") as MeshInstance3D
	var rg := _pick("shockwave_ring") as MeshInstance3D
	_ok("⑧ ★分母: 三个节点都在", mi != null and du != null and rg != null)
	if mi == null or du == null or rg == null:
		return

	var ring := _updots(rg, 0)
	print("     贴地环: %d 面, |n·上| 最小 %.4f 平均 %.4f" % [
		int(ring[0]), float(ring[1]), float(ring[2])])
	_ok("⑧ ★分母: 贴地环真的有面 (N=%d)" % int(ring[0]), int(ring[0]) > 50)
	_ok("⑧ ★★贴地环真的平铺", float(ring[1]) > 0.99)

	var dust := _updots(du, 0)
	print("     尘埃环: %d 面, |n·上| 最小 %.4f 平均 %.4f" % [
		int(dust[0]), float(dust[1]), float(dust[2])])
	_ok("⑧ ★分母: 尘埃环真的有面 (N=%d)" % int(dust[0]), int(dust[0]) > 50)
	_ok("⑧ ★★尘埃环真的平铺", float(dust[1]) > 0.99)

	# ★反面: 半球壳【不】该平铺 —— 否则 ⑧ 是"随便什么都 >0.99"的恒真式
	var shell := _updots(mi, 0)
	print("     ★反面 半球壳: %d 面, |n·上| 最小 %.4f 平均 %.4f (它是立体的)" % [
		int(shell[0]), float(shell[1]), float(shell[2])])
	_ok("⑧ ★分母: 半球壳真的有面 (N=%d)" % int(shell[0]), int(shell[0]) > 100)
	_ok("⑧ ★反面: 半球壳【不】平铺(证明 ⑧ 不是恒真式)", float(shell[2]) < 0.8)
	# 半球壳的最高点该在正上方 ≈ 半径处(它是个半球, 不是一张平饼)
	var top: float = _mesh_top(mi, 0)
	print("     半球壳顶点最高 y = %.4f (单位半径, 需求 ≈1.0)" % top)
	_ok("⑧ 半球壳真的拱起来了(顶 ≈ 1 个半径高)", top > 0.95 and top < 1.05)
	## ★贴地环【就是】这个半球与地面的交线, 不是另画的一个环 ⇒ 两者半径必须永远相等。
	##   拆成两个节点之后这条最容易断(两处各自 scale), 所以喂几个时刻各验一遍。
	var same := true
	for uu in [0.0, 0.05, 0.3, 0.77, 1.0]:
		_sw.apply_at(_syn._shocks[0], float(uu))
		if absf(mi.scale.x - rg.scale.x) > 1e-9:
			same = false
	print("     半球壳 vs 贴地环 半径(喂 5 个时刻): 恒等 = %s" % str(same))
	_ok("⑧ ★贴地环与半球壳半径恒等(它是同一个半球的地面交线)", same)
	## ★反面: 尘埃环【不】跟着走 —— 否则上一条可能是"所有节点 scale 都一样"的恒真式
	_sw.apply_at(_syn._shocks[0], 1.0)
	print("     ★反面 u=1 时 尘埃环 %.4f vs 波前 %.4f (需求不等)" % [du.scale.x, mi.scale.x])
	_ok("⑧ ★反面: 尘埃环走自己的律(证明上一条不是恒真式)", absf(du.scale.x - mi.scale.x) > 0.1)


# ── ⑨ 形态F: 撤场干净 (方案书 R7) ───────────────────────────────────────────
func _g9_teardown() -> void:
	print("")
	print("  ⑨ 形态F — 撤场干净:")
	await _setup_units()
	await _reset()
	_me["_shield_rage"] = 0.0
	_s._shield_syn._rage(_me, 3, 400.0)
	var before: int = _count("shockwave") + _count("shockwave_ring") + _count("shockwave_dust")
	_ok("⑨ ★分母: 撤之前确实有节点 (%d 个)" % before, before == 3)

	# ⑨a 自然收尾: 喂满一整段时长 → 自己 free, 不用等任何 tween
	var dur: float = SW.duration_s(1)
	_s._shield_syn.tick(dur * 0.5)
	await get_tree().process_frame
	print("     喂 %.3f s (半程) → 还剩 %d 个 (需求 3)" % [dur * 0.5, _count("shockwave") + _count("shockwave_ring") + _count("shockwave_dust")])
	_ok("⑨ ★半程时还在(证明下一条不是'一喂就没')",
		_count("shockwave") + _count("shockwave_ring") + _count("shockwave_dust") == 3)
	_s._shield_syn.tick(dur * 0.6)
	await get_tree().process_frame
	print("     再喂 %.3f s (超过总时长 %.3f s) → %d 个 (需求 0)" % [
		dur * 0.6, dur, _count("shockwave") + _count("shockwave_ring") + _count("shockwave_dust")])
	_ok("⑨ ★放完自己收干净", _count("shockwave") + _count("shockwave_ring") + _count("shockwave_dust") == 0)
	_ok("⑨ 句柄表也空了", _syn._shocks.size() == 0)

	# ⑨b 换路撤场: clear() 一次性拔掉
	_me["_shield_rage"] = 0.0
	_s._shield_syn._rage(_me, 3, 400.0)
	_ok("⑨ ★分母: 又建出来了", _count("shockwave") == 1)
	_s._shield_syn.clear()             # ← dual_lane_flow.gd:458 换路时调的就是它
	await get_tree().process_frame
	print("     _shield_syn.clear() (换路真入口) → %d 个 (需求 0)" % _count())
	_ok("⑨ ★★换路真入口 clear() 把演出节点也撤了", _count() == 0)
	_ok("⑨ 句柄表也清了(不清的话下一帧 tick 会拿着已 free 的句柄)", _syn._shocks.size() == 0)
	_me["_shield_rage"] = 0.0
	_s._shield_syn._rage(_me, 3, 400.0)
	_ok("⑨ ★★装回来又建得出来(证明上一条不是'永久坏了')", _count("shockwave") == 1)


# ── ⑩ ★★每帧驱动真的被调到 —— 「写了没人读」的反面 ─────────────────────────
## memory [[fb-write-without-reader-and-fake-gates]]: 生产侧写了、消费侧没读, 两边单看都对。
## 这里的具体风险是: 接线那行被挪到 `_t_holy < HOLY_PERIOD` 的提前 return 之【后】——
## 那样冲击波每 3 秒才动一帧, 而"函数存在""节点建出来"两条断言全都照绿。
func _g10_frame_driver() -> void:
	print("")
	print("  ⑩ ★★每帧驱动 — 走 _shield_syn.tick() 真入口:")
	await _setup_units()
	await _reset()
	_me["_shield_rage"] = 0.0
	_s._shield_syn._rage(_me, 3, 400.0)
	var mi := _pick("shockwave") as MeshInstance3D
	_ok("⑩ ★分母: 节点在", mi != null)
	if mi == null:
		return
	var s0: float = mi.scale.x
	## ★把圣光的节拍推到【刚清零】—— 这样 tick(0.02) 一定走那条提前 return 分支。
	_s._shield_syn._t_holy = 0.0
	_s._shield_syn.tick(0.02)
	var s1: float = mi.scale.x
	print("     _t_holy=0 时 tick(0.02): scale %.6f → %.6f" % [s0, s1])
	_ok("⑩ ★★接线在提前 return 之【前】(圣光没到点也照样推进冲击波)", s1 > s0 + 1e-6,
		"scale 没变 = 接线被挡在 `_t_holy < HOLY_PERIOD` 后面了")
	_s._shield_syn.tick(0.05)
	var s2: float = mi.scale.x
	print("     再 tick(0.05): scale → %.6f" % s2)
	_ok("⑩ 连续推进(scale 继续涨)", s2 > s1 + 1e-6)
	# ★反面: delta=0 不该动 —— 证明上面不是"随便调都变"
	var s3: float = mi.scale.x
	_s._shield_syn.tick(0.0)
	print("     ★反面 tick(0.0): scale %.6f → %.6f (需求不变)" % [s3, mi.scale.x])
	_ok("⑩ ★反面: delta=0 不推进(证明上面不是'随便调都变')", absf(mi.scale.x - s3) < 1e-9)
	# 亮度也在被驱动: 正压相很短, 推过它之后波前应当暗下来
	var m0: Color = (mi.material_override as StandardMaterial3D).albedo_color
	_s._shield_syn.tick(SW.duration_s(1) * 0.5)
	var m1: Color = (mi.material_override as StandardMaterial3D).albedo_color
	print("     波前亮度 a: %.4f → %.4f (正压相只占 %.1f%%, 早就过了)" % [
		m0.a, m1.a, SW.POS_FRAC * 100.0])
	_ok("⑩ 亮度也被每帧驱动(过了正压相就暗)", m1.a < m0.a)


# ── ⑪ 零素材 ────────────────────────────────────────────────────────────────
## 用户铁律「不要复用素材除非我指明了」。本条演出**一张图都没用**: 纯几何 + 顶点色。
func _g11_zero_asset() -> void:
	print("")
	print("  ⑪ 零素材 — 纯程序化几何, 一张图都没 load:")
	await _setup_units()
	await _reset()
	_me["_shield_rage"] = 0.0
	_s._shield_syn._rage(_me, 3, 400.0)
	var checked := 0
	var bad := 0
	for kind in ["shockwave", "shockwave_ring", "shockwave_dust"]:
		var mi := _pick(kind) as MeshInstance3D
		if mi == null:
			_ok("⑪ %s ★分母: 节点在" % kind, false); continue
		var am := mi.mesh as ArrayMesh
		var m := mi.material_override as StandardMaterial3D
		print("     %s: mesh.resource_path=\"%s\", %d surface, %d 面" % [
			kind, str(am.resource_path), am.get_surface_count(),
			int(am.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3)])
		_ok("⑪ %s 网格是现算的(resource_path 空)" % kind, str(am.resource_path) == "")
		checked += 1
		if m == null or m.albedo_texture != null:
			bad += 1
		if m != null:
			_ok("⑪ %s 顶点色当亮度(没贴图)" % kind,
				m.albedo_texture == null and m.vertex_color_use_as_albedo)
			_ok("⑪ %s 加性发光" % kind, m.blend_mode == BaseMaterial3D.BLEND_MODE_ADD)
	print("     共查 %d 个材质, 带贴图的 %d 个 (需求 0)" % [checked, bad])
	_ok("⑪ ★分母: 真的查了材质 (N=%d)" % checked, checked == 3)
	_ok("⑪ ★一张素材都没用", bad == 0)


# ── ⑫ 守 _world == null (方案书 R2) ─────────────────────────────────────────
## ★同帧内改回来, 中间不 await, 免得 _process 拿着 null 跑一帧。
func _g12_world_guard() -> void:
	print("")
	print("  ⑫ R2 — _world 不在时不崩也不建:")
	await _setup_units()
	await _reset()
	var saved = _s._world
	var n0: int = _syn.alive_count()
	_s._world = null
	var h = _syn.rage_shockwave(Vector2(700, 400), Vector2(900, 400), 1)
	var h2 = _sw.make_blast(Vector2(700, 400), Color(1, 1, 1, 1), 1)
	_s._world = saved
	print("     _world=null: rage_shockwave → %s / make_blast → %s (都需求空)" % [
		str(h), str(h2)])
	_ok("⑫ rage_shockwave 守空", h is Dictionary and (h as Dictionary).is_empty())
	_ok("⑫ make_blast 守空", h2 is Dictionary and (h2 as Dictionary).is_empty())
	_ok("⑫ 一个节点都没记账", _syn.alive_count() == n0)
	var h3 = _syn.rage_shockwave(Vector2(700, 400), Vector2(900, 400), 1)
	_ok("⑫ ★反面: 世界装回来立刻又能建", h3 is Dictionary and not (h3 as Dictionary).is_empty())


# ── 工具 ──────────────────────────────────────────────────────────────────────

## 造一组干净的合成单位: 9 件盾的顶档携带者 + 一个厚血靶子。
## ★照抄 verify_shield_synergy 的 _mk —— 用真的 _make_unit, 别手写字典
##   (手写会漏 untargetable_until 等字段 ⇒ _nearest_enemy 直接 SCRIPT ERROR)。
## ★用 "green" 不用 "basic": 小龟有【不屈】被动会改伤害。
func _setup_units() -> void:
	var SH := ["p2eq_018", "p2eq_081", "p2eq_082", "p2eq_016", "p2eq_021", "p2eq_045",
		"p2eq_014", "p2eq_015", "p2eq_017"]
	_me = _mk("left", SH.slice(0, 3), 2000.0)
	_foe = _mk("right", [], 900000.0)
	var us := [_me, _mk("left", SH.slice(3, 6)), _mk("left", SH.slice(6, 9)), _foe]
	_s._units.clear()
	_s._units.append_array(us)
	_s._synergy._by_side = {"left": {}, "right": {}}
	_s._synergy.apply_all()
	await get_tree().process_frame


func _mk(side: String, ids: Array, hp: float = 2000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var off := Vector2(-200.0, 0.0) if side == "left" else Vector2(200.0, 0.0)
	var u: Dictionary = _s._spawn._make_unit("green", side, c + off)
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["def"] = 0.0; u["base_def"] = 0.0
	u["mr"] = 0.0; u["base_mr"] = 0.0
	u["crit"] = 0.0
	u["dodge_bonus"] = 0.0
	var e: Array = []
	for i in ids:
		e.append({"id": str(i), "star": 1})
	u["equips"] = e
	u["eq_state"] = {}
	return u


## _world 里本层建的节点数 (按自定义 meta 数, 不按名字 —— 程序生成的网格没有 resource_path)
func _count(kind: String = "") -> int:
	var n := 0
	for c in _s._world.get_children():
		if not c.has_meta(SV.META_KEY):
			continue
		if kind != "" and str(c.get_meta(SV.META_KEY)) != kind:
			continue
		n += 1
	return n


func _pick(kind: String) -> Node3D:
	for c in _s._world.get_children():
		if c.has_meta(SV.META_KEY) and str(c.get_meta(SV.META_KEY)) == kind:
			return c
	return null


## 某个 surface 上所有三角面的 |世界法线·上|: 返回 [面数, 最小值, 平均值]
func _updots(mi: MeshInstance3D, surf: int) -> Array:
	var arr: Array = (mi.mesh as ArrayMesh).surface_get_arrays(surf)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var b: Basis = mi.global_transform.basis
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


## 某 surface 顶点里最高的 y (单位半径口径 —— 读局部顶点, 与 scale 无关)
func _mesh_top(mi: MeshInstance3D, surf: int) -> float:
	var arr: Array = (mi.mesh as ArrayMesh).surface_get_arrays(surf)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var top := -1e9
	for v in vs:
		top = maxf(top, v.y)
	return top


func _reset() -> void:
	_syn.clear()
	await get_tree().process_frame


func _ok(what: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("     [PASS] ", what)
	else:
		_fail += 1
		print("     [FAIL] ", what, ("  " + detail) if detail != "" else "")


func _done() -> void:
	if is_instance_valid(_s):
		_s._units.clear()
		_s.set_process(false)
		await get_tree().process_frame
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	print("ALL PASS — 盾怒气冲击波爆轰演出(批 B·B2)" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
