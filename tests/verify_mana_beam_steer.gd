extends Node
## verify_mana_beam_steer.gd — 068【可转向法力射线】(2026-08-11)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来: 用户 2026-08-11
##   「本来就应该是可以转向的射线，射线碰到谁就开始造成伤害，射线离开就停止造成伤害」
##   「必须做 3D，不要拿图片敷衍，也不要拿简单程序图形糊弄」
##   「命中特效不能是突然出现突然消失的」
## ══════════════════════════════════════════════════════════════════
## 方案书: docs/plans/20260811-068可转向法力射线.md
##
## ★★这份门禁守的头号风险是【漏人】:
##   BEAM_TICK=0.25s、转向 110°/s ⇒ **一个 tick 转 27.5°**。
##   在 500 码处那是 240 码弧长, 而射线全宽才 116 码
##   ⇒ 敌人会整个从两个 tick 的缝里漏过去, **而且不报任何错**。
##   (与「逐帧机制门禁必须逐帧喂」「合成单位被钳到同一点」同族: 粗粒度采样看不见缝隙。)
##
## ★判据全部落在【真实 eq_state 字段 / 真实掉血 / 真实节点】, 不量替身。
## ★全程不依赖任何 tween: 扫掠结算是闭式解, 同步喂 delta 即可判定(CLAUDE.md §3.5)。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_mana_beam_steer.tscn --quit-after 3000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Beam := preload("res://scripts/scenes/battle/mana_beam_vfx.gd")
const Vfx := preload("res://scripts/scenes/battle/potion_eq_vfx.gd")

var _s
var _ps
var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _mk(side: String, p: Vector2, hp: float = 500000.0) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, p)
	u["alive"] = true
	u["pos"] = p
	u["hp"] = hp
	u["maxHp"] = hp
	u["shield"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["flat_dr"] = 0.0
	u["damage_reduction"] = 0.0
	u["equips"] = []
	u["eq_state"] = {}
	_s._units.append(u)
	return u


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 068 可转向法力射线 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0
	_ps = _s._equip_sys._potion_sys
	_ok("★分母: 拿到药水系统与射线演出层", _ps != null and _ps._beam_vfx != null)
	if _ps == null or _ps._beam_vfx == null:
		print("FAIL x1"); get_tree().quit(1); return

	_t_sweep_math()
	_t_no_skip()
	_t_turn_clamp()
	_t_retarget()
	_t_envelope()
	_t_xsec()
	_t_hit_fade()
	_t_lane_clear()

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 068 可转向射线" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## ① 扫掠求交的闭式解本身对不对(纯函数, 但它是整条链的地基)
func _t_sweep_math() -> void:
	# 不转向 ⇒ 退化成"在不在带内", f 只能是 0 或 1 —— 这是【回归保护】:
	# 改动前的行为就是这个, 新旧必须逐字一致。
	_ok("① 不转向 + 在带内 ⇒ f=1(与改动前逐字一致)",
		absf(_ps._sweep_frac(0.0, 0.0, 0.05, 0.2) - 1.0) < 1e-6)
	_ok("① 不转向 + 在带外 ⇒ f=0",
		absf(_ps._sweep_frac(0.0, 0.0, 0.5, 0.2)) < 1e-6)
	# 转 1.0 弧度, 敌人角半宽 0.1 且正好在中途 ⇒ 被照到的比例 = 0.2/1.0
	_ok("① 扫掠比例 = 交集 ÷ 扫掠角(闭式解, 不是采样)",
		absf(_ps._sweep_frac(0.0, 1.0, 0.5, 0.1) - 0.2) < 1e-6,
		"实得 %.4f 期望 0.2" % _ps._sweep_frac(0.0, 1.0, 0.5, 0.1))
	# 敌人角宽比整个扫掠还大 ⇒ 全程被照 ⇒ f 封顶 1
	_ok("① f 封顶 1(敌人角宽 > 扫掠角时全程被照)",
		absf(_ps._sweep_frac(0.0, 0.2, 0.1, 5.0) - 1.0) < 1e-6)
	_ok("① 反向扫掠同样成立(角度差是有符号的)",
		absf(_ps._sweep_frac(1.0, 0.0, 0.5, 0.1) - 0.2) < 1e-6)
	# 角半宽必须与旧版"垂距 ≤ 58 码"严格等价 ⇒ 用 asin 不是 atan
	var d := 500.0
	_ok("① ★角半宽与旧版垂距判定【严格等价】(asin 不是 atan)",
		absf(sin(_ps._half_angle(d)) * d - Vfx.BEAM_HALF_W) < 0.01,
		"d·sin(α)=%.3f 应等于 BEAM_HALF_W=%.1f" % [sin(_ps._half_angle(d)) * d, Vfx.BEAM_HALF_W])


## ②★★不漏人: 转向时跨过的敌人必须被结算
func _t_no_skip() -> void:
	_s._units.clear()
	_s._spec.clear_all()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var carrier: Dictionary = _s._spawn._make_unit("fortune", "left", c + Vector2(-520.0, 0.0))
	carrier["alive"] = true
	carrier["pos"] = c + Vector2(-520.0, 0.0)
	carrier["hp"] = 3000.0; carrier["maxHp"] = 3000.0
	carrier["equips"] = [{"id": "p2eq_068", "star": 3}]
	carrier["eq_state"] = {"p2eq_068": {"can_t0": 0.0, "can_charge": 3000.0, "can_fired": 0}}
	_s._units.append(carrier)
	var org: Vector2 = carrier["pos"]
	# 初始最远敌: 正右方远处; 途中敌: 与初始方向成 ~18°, 距离 600
	var far: Dictionary = _mk("right", org + Vector2(1400.0, 0.0))
	var mid: Dictionary = _mk("right", org + Vector2(600.0 * cos(deg_to_rad(18.0)), 600.0 * sin(deg_to_rad(18.0))))
	# 更远且更偏的新目标 —— far 死后射线会朝它扫, 途中必然扫过 mid
	var nxt: Dictionary = _mk("right", org + Vector2(1400.0 * cos(deg_to_rad(40.0)), 1400.0 * sin(deg_to_rad(40.0))))
	_ps._eq_pressure_release(carrier, 2, carrier["eq_state"]["p2eq_068"])
	var st: Dictionary = carrier["eq_state"]["p2eq_068"]
	_ok("② ★分母: 开火时锁的是最远敌(far)", is_same(st.get("beam_tgt", null), far))
	_ok("② ★分母: mid 一开始【不在】射线上(否则这条测不到「扫过」)",
		absf(angle_difference(float(st.get("beam_ang", 0.0)),
			(mid["pos"] - org).angle())) > _ps._half_angle((mid["pos"] - org).length()),
		"mid 角偏 %.3f rad, 角半宽 %.3f rad" % [
			absf(angle_difference(float(st.get("beam_ang", 0.0)), (mid["pos"] - org).angle())),
			_ps._half_angle((mid["pos"] - org).length())])
	var mid_hp0: float = float(mid["hp"])
	# far 立刻死掉 ⇒ 射线改指 nxt, 一路扫过 mid
	far["alive"] = false
	far["hp"] = 0.0
	# ★只喂到转向完成为止(40° ÷ 110°/s ≈ 0.36s), 不喂满 3 秒 ——
	#   喂满的话光束已经结束、`beam_tgt` 被清成 null, 换靶断言就测不到了。
	for _i in range(4):
		_ps._eq_beam_step(carrier, 0.25)
	_ok("② ★★被扫过的敌人真的掉血了(漏人的话这里恒为 0)",
		float(mid["hp"]) < mid_hp0 - 0.5,
		"mid 掉血 %.1f —— 若为 0 = 敌人从两个 tick 的缝里漏过去了" % (mid_hp0 - float(mid["hp"])))
	_ok("② ★分母: 同步触发证据 _mana_beam_n > 0(不等演出)",
		int(mid.get("_mana_beam_n", 0)) > 0, "_mana_beam_n=%d" % int(mid.get("_mana_beam_n", 0)))
	_ok("② 换靶后确实指向了新目标", is_same(st.get("beam_tgt", null), nxt))


## ③ 角速率受钳制 —— 不许瞬移
func _t_turn_clamp() -> void:
	_s._units.clear()
	_s._spec.clear_all()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var carrier: Dictionary = _s._spawn._make_unit("fortune", "left", c + Vector2(-520.0, 0.0))
	carrier["alive"] = true
	carrier["pos"] = c + Vector2(-520.0, 0.0)
	carrier["hp"] = 3000.0; carrier["maxHp"] = 3000.0
	carrier["equips"] = [{"id": "p2eq_068", "star": 3}]
	carrier["eq_state"] = {"p2eq_068": {"can_t0": 0.0, "can_charge": 3000.0, "can_fired": 0}}
	_s._units.append(carrier)
	var org: Vector2 = carrier["pos"]
	var a: Dictionary = _mk("right", org + Vector2(900.0, 0.0))
	_ps._eq_pressure_release(carrier, 2, carrier["eq_state"]["p2eq_068"])
	var st: Dictionary = carrier["eq_state"]["p2eq_068"]
	# 目标瞬移到正后方 ⇒ 期望方向差 180°, 但一帧只能转 TURN_DPS·delta
	a["pos"] = org + Vector2(-900.0, 0.0)
	var before: float = float(st.get("beam_ang", 0.0))
	var dt := 0.1
	_ps._eq_beam_step(carrier, dt)
	var moved: float = absf(angle_difference(before, float(st.get("beam_ang", 0.0))))
	var cap: float = deg_to_rad(Beam.TURN_DPS) * dt
	_ok("③ ★★一帧的转角 ≤ 角速率上限(不瞬移)", moved <= cap + 1e-5,
		"实转 %.4f rad, 上限 %.4f rad(%.0f°/s × %.2fs)" % [moved, cap, Beam.TURN_DPS, dt])
	_ok("③ ★分母: 它确实在转(不是纹丝不动 ⇒ 上一条会变成空检查)",
		moved > cap * 0.9, "实转 %.4f rad" % moved)
	# 180° 掉头要多久 —— 把实测换算值钉住(改了 TURN_DPS 这条会红)
	var need: float = PI / deg_to_rad(Beam.TURN_DPS)
	_ok("③ 180° 掉头耗时 %.2fs(实测换算 110°/s)" % need, need > 1.3 and need < 1.9,
		"%.2fs —— 太快=转向没代价, 太慢=换靶等于放弃" % need)


## ④ 目标死亡 ⇒ 换靶(读真实字段, 不是"我调用过换靶函数")
func _t_retarget() -> void:
	_s._units.clear()
	_s._spec.clear_all()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var carrier: Dictionary = _s._spawn._make_unit("fortune", "left", c + Vector2(-520.0, 0.0))
	carrier["alive"] = true
	carrier["pos"] = c + Vector2(-520.0, 0.0)
	carrier["hp"] = 3000.0; carrier["maxHp"] = 3000.0
	carrier["equips"] = [{"id": "p2eq_068", "star": 3}]
	carrier["eq_state"] = {"p2eq_068": {"can_t0": 0.0, "can_charge": 3000.0, "can_fired": 0}}
	_s._units.append(carrier)
	var org: Vector2 = carrier["pos"]
	var a: Dictionary = _mk("right", org + Vector2(1200.0, 0.0))
	var b: Dictionary = _mk("right", org + Vector2(700.0, 300.0))
	_ps._eq_pressure_release(carrier, 2, carrier["eq_state"]["p2eq_068"])
	var st: Dictionary = carrier["eq_state"]["p2eq_068"]
	_ok("④ ★分母: 先锁最远的 a", is_same(st.get("beam_tgt", null), a))
	a["alive"] = false
	_ps._eq_beam_step(carrier, 0.05)
	_ok("④ ★★目标死亡后换成活着的 b(读真实 beam_tgt 字段)",
		is_same(st.get("beam_tgt", null), b),
		"beam_tgt 仍是死的那个 ⇒ 射线会一直指着尸体")


## ⑤ 时间包络: 末端最亮 + frac 是 env 的归一化积分
func _t_envelope() -> void:
	_ok("⑤ ★★末端最亮(参考实测: 峰值在结束前那一帧)",
		Beam.env(0.96) > Beam.env(0.10) * 2.0,
		"env(0.96)=%.3f env(0.10)=%.3f —— 换回指数衰减这条就红" % [Beam.env(0.96), Beam.env(0.10)])
	_ok("⑤ 累计比例两端精确: Q(0)=0, Q(1)=1",
		absf(Beam.env_frac(0.0)) < 1e-6 and absf(Beam.env_frac(1.0) - 1.0) < 1e-6,
		"Q(0)=%.6f Q(1)=%.6f" % [Beam.env_frac(0.0), Beam.env_frac(1.0)])
	_ok("⑤ 累计比例单调不减(伤害不能倒扣)",
		Beam.env_frac(0.3) <= Beam.env_frac(0.6) and Beam.env_frac(0.6) <= Beam.env_frac(0.9))
	# ★★同源: frac 必须是 env 的归一化积分 —— 门禁自己数值积分一遍再比,
	#   不是调 env_frac 跟自己比(那是代数恒等 = 假门禁)
	var acc := 0.0
	var tot := 0.0
	var steps := 2000
	for i in range(steps):
		tot += Beam.env(float(i) / float(steps))
	for i in range(int(steps * 0.5)):
		acc += Beam.env(float(i) / float(steps))
	_ok("⑤ ★★亮度与伤害同源: Q(0.5) = ∫env 到 0.5 ÷ ∫env 全程",
		absf(Beam.env_frac(0.5) - acc / maxf(tot, 1e-9)) < 0.01,
		"Q(0.5)=%.4f 门禁自己积分得 %.4f" % [Beam.env_frac(0.5), acc / maxf(tot, 1e-9)])


## ⑥ 横截面: 芯晕必须分化(白芯窄、外缘浓琥珀)
func _t_xsec() -> void:
	var cf: float = Beam.core_frac()
	_ok("⑥ ★★白芯占比在实测区间内(差分实测: 饱和度<0.20 的那一段约占 13%%)",
		cf >= 0.08 and cf <= 0.22,
		"实为 %.3f —— 芯和晕一样宽就没有芯晕分化了, 会读成一坨均匀色" % cf)
	var rim: Array = Beam.xsec_at(1.0)
	var mx: float = maxf(maxf(float(rim[0]), float(rim[1])), float(rim[2]))
	var mn: float = minf(minf(float(rim[0]), float(rim[1])), float(rim[2]))
	var sat: float = 0.0 if mx <= 0.0 else (mx - mn) / mx
	_ok("⑥ 外缘是【浓】琥珀金(实测饱和度 0.50~0.65)", sat >= 0.45,
		"实为 %.3f —— 低饱和 + 加色混合对黑底就是白, 这是白球家族的病" % sat)
	var core: Array = Beam.xsec_at(0.0)
	_ok("⑥ 芯是白的", float(core[0]) > 0.95 and float(core[1]) > 0.95 and float(core[2]) > 0.95)
	_ok("⑥ 亮度从外到内单调上升(平滑斜坡, 不是硬分带)",
		float(Beam.xsec_at(0.0)[3]) > float(Beam.xsec_at(0.5)[3])
		and float(Beam.xsec_at(0.5)[3]) > float(Beam.xsec_at(1.0)[3]))


## ⑦ 命中特效: 不能突现突消(用户 2026-08-11 点名)
func _t_hit_fade() -> void:
	_ok("⑦ ★★命中爆点有淡入淡出(不是突现突消)",
		Beam.HIT_IN > 0.0 and Beam.HIT_OUT > 0.0,
		"HIT_IN=%.3f HIT_OUT=%.3f" % [Beam.HIT_IN, Beam.HIT_OUT])
	_ok("⑦ 淡出比淡入长(被照到要立刻有反应, 离开留一点余韵)",
		Beam.HIT_OUT > Beam.HIT_IN,
		"in=%.3f out=%.3f" % [Beam.HIT_IN, Beam.HIT_OUT])


## ⑧ 换路撤场: 节点必须归零
func _t_lane_clear() -> void:
	_s._units.clear()
	_s._spec.clear_all()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var carrier: Dictionary = _s._spawn._make_unit("fortune", "left", c + Vector2(-520.0, 0.0))
	carrier["alive"] = true
	carrier["pos"] = c + Vector2(-520.0, 0.0)
	carrier["hp"] = 3000.0; carrier["maxHp"] = 3000.0
	carrier["equips"] = [{"id": "p2eq_068", "star": 3}]
	carrier["eq_state"] = {"p2eq_068": {"can_t0": 0.0, "can_charge": 3000.0, "can_fired": 0}}
	_s._units.append(carrier)
	_mk("right", carrier["pos"] + Vector2(900.0, 0.0))
	_ps._eq_pressure_release(carrier, 2, carrier["eq_state"]["p2eq_068"])
	_ps._eq_beam_step(carrier, 0.1)
	var n0: int = _ps._beam_vfx.node_count()
	_ok("⑧ ★分母: 射线真的建出了 3D 节点(数真实节点, 不是「我调用过」)",
		n0 > 0, "节点数 %d" % n0)
	# ★走真入口: dual_lane_flow 换路时就是这么调的(has_method 保护)
	_ok("⑧ ★分母: _potion_sys 有 clear_all —— 没有的话换路清理会【静默跳过】它",
		_ps.has_method("clear_all"))
	_ps.clear_all()
	_ok("⑧ ★★换路撤场后节点归零(漏清 = 上一路的射线钉在下一路)",
		_ps._beam_vfx.node_count() == 0,
		"还剩 %d 个" % _ps._beam_vfx.node_count())
