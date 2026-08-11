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
	_t_mana_bar()
	await _t_burst_tables()

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


## ⑨ 法力护盾进血条第四段(用户 2026-08-11:「为啥飘字, 应该是给一个特殊颜色护盾条, 这是特殊护盾」)
##   与圣盾白黄(_holyShieldVal)/壳青绿(_hidingShellVal)/海胆紫(urchin_sh_left)同一套机制。
##   链条: SpecialBalance 余额 → _tick_pressure_can 每帧镜像 _manaShieldVal → HpBar 读字段画段。
##   判据落在【真实单位字段 + 真实 HpBar 对象】, 镜像走真实的每帧入口, 不由门禁手写。
func _t_mana_bar() -> void:
	_s._units.clear()
	_s._spec.clear_all()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var carrier: Dictionary = _s._spawn._make_unit("fortune", "left", c + Vector2(-520.0, 0.0))
	carrier["alive"] = true
	carrier["pos"] = c + Vector2(-520.0, 0.0)
	carrier["hp"] = 3000.0; carrier["maxHp"] = 3000.0
	carrier["shield"] = 0.0
	carrier["equips"] = [{"id": "p2eq_068", "star": 3}]
	carrier["eq_state"] = {"p2eq_068": {"can_t0": 0.0, "can_charge": 3000.0, "can_fired": 0}}
	_s._units.append(carrier)
	_mk("right", carrier["pos"] + Vector2(900.0, 0.0))
	_ps._eq_pressure_release(carrier, 2, carrier["eq_state"]["p2eq_068"])
	var granted: float = _s._spec.val(carrier, _ps.CAN_MANA_KEY)
	_ok("⑨ ★分母: 释放后 SpecialBalance 里真有法力护盾", granted > 0.0, "val=%.0f" % granted)
	_ps._tick_pressure_can(carrier, 2, 0.05)
	_ok("⑨ ★★每帧镜像已写进单位字段(血条只认 f 的字段, 拿不到 battle._spec)",
		absf(float(carrier.get("_manaShieldVal", 0.0)) - granted) < 1.0,
		"_manaShieldVal=%.0f 应≈%.0f" % [float(carrier.get("_manaShieldVal", 0.0)), granted])
	var hb = carrier.get("hp_bar", null)
	_ok("⑨ ★分母: 单位真有 HpBar 组件", hb != null and is_instance_valid(hb))
	if hb != null and is_instance_valid(hb):
		hb.update_state(carrier)
		_ok("⑨ ★★HpBar 把法力盾读成了段值(真实对象字段, 不量替身)",
			absf(float(hb._mana) - granted) < 1.0, "hb._mana=%.0f 应≈%.0f" % [float(hb._mana), granted])
		_ok("⑨ ★★法力盾计入条总量 _bm(不计入 ⇒ 段宽恒为 0 = 画不出来)",
			float(hb._bm) >= 3000.0 + granted - 1.0,
			"_bm=%.0f 应≥ maxHp+盾=%.0f" % [float(hb._bm), 3000.0 + granted])
		_ok("⑨ 段色是蓝主导的特殊色(区别圣盾黄/壳绿/海胆紫/普通灰白)",
			hb._MANA_L.b8 > hb._MANA_L.r8 and hb._MANA_L.b8 > hb._MANA_L.g8,
			"_MANA_L=#%02x%02x%02x" % [hb._MANA_L.r8, hb._MANA_L.g8, hb._MANA_L.b8])
	# 8 秒线性衰减要在条上肉眼可见: 衰减走真实 SpecialBalance.tick, 镜像必须跟着缩
	_s._spec.tick(4.0)
	_ps._tick_pressure_can(carrier, 2, 0.05)
	var half: float = float(carrier.get("_manaShieldVal", 0.0))
	_ok("⑨ 衰减跟得上(4/8 秒后镜像 ≈ 一半)", half > granted * 0.3 and half < granted * 0.7,
		"衰减 4 秒后 %.0f(初始 %.0f)" % [half, granted])
	_s._spec.tick(9.0)
	_ps._tick_pressure_can(carrier, 2, 0.05)
	_ok("⑨ 耗尽后镜像归零(条停在旧值 = 骗人)",
		float(carrier.get("_manaShieldVal", -1.0)) < 0.5,
		"_manaShieldVal=%.2f" % float(carrier.get("_manaShieldVal", -1.0)))
	# 飘字必须删干净 —— 有现成血条段机制却另起一行飘字, 是「充能条没人看得见」同款错误
	var src: String = FileAccess.get_file_as_string("res://scripts/systems/equip/eq_potion_batch.gd")
	_ok("⑨ ★分母: 源文件读得到(空串 = 空检查)", src.length() > 1000, "len=%d" % src.length())
	var bad := false
	for ln in src.split("\n"):
		if ("_float_text" in ln) and ("法力护盾" in ln):
			bad = true
	_ok("⑨ ★飘字已删(源码不再有「法力护盾」_float_text 行)", not bad)
	_ps.clear_all()          # ⑨ 自己放的束自己清 —— 漏了会污染 ⑩ 的节点计数(踩过)


## ⑩ 爆点/细丝照实测表(2026-08-11 逐帧量的, 用户标准: 像素级 1:1 视频参考)
##   实测三个反直觉结论都要焊死: 持续期无白芯 / 刺形每~2帧重掷 / 白色只在末端爆发。
##   判据落在【真实网格顶点 / 真实节点 / 真实 mesh 引用】, 不是"我调用过"。
func _t_burst_tables() -> void:
	# ── 表本身 ──
	_ok("⑩ 刺长分位表照实测(p50=64码, max=90码; 1px=1.115码)",
		absf(Beam.spike_len(0.5) - 64.0) < 0.5 and absf(Beam.spike_len(1.0) - 90.0) < 0.5,
		"p50=%.1f max=%.1f" % [Beam.spike_len(0.5), Beam.spike_len(1.0)])
	_ok("⑩ 刺角宽双峰保住(细针<15° 宽瓣>30°, 实测 4~12° 与 35~55°)",
		Beam.HIT_NEEDLE_DEG < 15.0 and Beam.HIT_LOBE_DEG > 30.0,
		"needle=%.0f° lobe=%.0f°" % [Beam.HIT_NEEDLE_DEG, Beam.HIT_LOBE_DEG])
	var ci: Color = Beam.HIT_COL_IN
	var sat: float = (ci.r - minf(minf(ci.r, ci.g), ci.b) / ci.r) if ci.r > 0 else 0.0
	sat = (maxf(maxf(ci.r, ci.g), ci.b) - minf(minf(ci.r, ci.g), ci.b)) / maxf(maxf(maxf(ci.r, ci.g), ci.b), 0.001)
	_ok("⑩ ★持续期爆点是琥珀不是白(实测白占比<4%%, sat 0.69) —— 白色只属于末端爆发",
		sat >= 0.4, "根部色 sat=%.2f" % sat)
	_ok("⑩ 光晕剖面: 平台到 33码 + 指数衰减 + 90码见底",
		absf(Beam.glow_at(0.0) - 1.0) < 1e-6 and absf(Beam.glow_at(33.0) - 1.0) < 1e-6
		and Beam.glow_at(60.0) > 0.05 and Beam.glow_at(60.0) < 0.4
		and Beam.glow_at(90.0) < 1e-6,
		"g(33)=%.2f g(60)=%.2f g(90)=%.2f" % [Beam.glow_at(33.0), Beam.glow_at(60.0), Beam.glow_at(90.0)])
	# ── 刺束网格是真 3D(旧版贴地星芒 y≡0 就是被这条打死的) ──
	var bm: ArrayMesh = Beam._burst_mesh(1)
	var vts: PackedVector3Array = bm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var maxy := 0.0
	for v in vts:
		maxy = maxf(maxy, absf(v.y))
	_ok("⑩ ★★刺束是 3D(方向撒满球面含朝镜头), 不是贴地星芒", maxy > 0.3,
		"max|y|=%.2f —— 0 = 全趴在地上" % maxy)
	_ok("⑩ ★分母: 刺数照表(顶点数 = N×2片×3)", vts.size() == Beam.HIT_SPIKE_N * 6,
		"%d 顶点, 期望 %d" % [vts.size(), Beam.HIT_SPIKE_N * 6])
	# ── 运行时: 走真入口(release → _eq_beam_step), 断言真实节点 ──
	_s._units.clear()
	_s._spec.clear_all()
	_ps.clear_all()          # 从干净的 _live 起量, 别人漏的束不算到我头上
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
	var st: Dictionary = carrier["eq_state"]["p2eq_068"]
	var h: Dictionary = st.get("beam_h", {})
	_ok("⑩ ★分母: 束身里有细丝节点(实测每截面 3~5 条亮脊)",
		is_instance_valid(h.get("fil_node", null)) and Beam.FIL_N >= 2 and Beam.FIL_N <= 5,
		"FIL_N=%d" % Beam.FIL_N)
	for _i in range(10):
		_ps._eq_beam_step(carrier, 0.25)      # 2.50s: 持续段
	var marks: Array = h.get("marks", [])
	_ok("⑩ ★分母: 持续段有爆点 mark", marks.size() > 0)
	if marks.size() > 0:
		var m0: Dictionary = marks[0]
		_ok("⑩ ★持续段【没有】白核节点(白色只属于末端爆发)", m0.get("core", null) == null)
		_ok("⑩ 爆点带球状光晕壳(三层)", (m0.get("glows", []) as Array).size() == 3)
		var fil_a = h["fil_node"].mesh if is_instance_valid(h.get("fil_node", null)) else null
		_ps._eq_beam_step(carrier, 0.28)      # t_acc 2.50→2.78 跨 0.27 档 ⇒ 细丝换排布
		var fil_b = h["fil_node"].mesh if is_instance_valid(h.get("fil_node", null)) else null
		_ok("⑩ 细丝排布在轮换(周期=实测闪变去相关 270ms)", fil_a != null and fil_b != null and fil_a != fil_b)
		var mesh_a = m0["star"].mesh if is_instance_valid(m0.get("star", null)) else null
		_ps._eq_beam_step(carrier, 0.05)      # resh ≥ 0.04 ⇒ 重掷
		var mesh_b = m0["star"].mesh if is_instance_valid(m0.get("star", null)) else null
		_ok("⑩ ★★刺形真的在重掷(实测 33ms 相关只剩 0.37): 换的是真 mesh 引用",
			mesh_a != null and mesh_b != null and mesh_a != mesh_b)
	# ── ⑪ 束身 shader + 枪口飘带(二轮量测, 方案书 §九) ──
	_ok("⑪ 实测常量钉死: 调制±10.5%% / 呼吸±6%%·67ms / 闪变 270ms",
		absf(Beam.BEAM_MOD_AMP - 0.105) < 1e-6 and absf(Beam.BEAM_BREATH_AMP - 0.06) < 1e-6
		and absf(Beam.BEAM_BREATH_SEC - 0.067) < 1e-6 and absf(Beam.BEAM_EVOLVE_SEC - 0.27) < 1e-6)
	var sh0 = (h["shells"] as Array)[0]
	var smat = sh0.material_override if is_instance_valid(sh0) else null
	_ok("⑪ ★束身材质是 ShaderMaterial 且挂的是 mana_beam shader(真对象)",
		smat is ShaderMaterial and (smat as ShaderMaterial).shader == Beam.BEAM_SHADER)
	if smat is ShaderMaterial:
		# ★null 安全: 参数根本没被设过时 get 返回 null, float(null) 是运行时错误 ——
		#   会把测试函数【静默中止】(剩余断言不跑但照样 ALL PASS)。null → -999 = 必红。
		var utv = (smat as ShaderMaterial).get_shader_parameter("u_t")
		var uev = (smat as ShaderMaterial).get_shader_parameter("u_env")
		var ut: float = float(utv) if utv != null else -999.0
		var ue: float = float(uev) if uev != null else -999.0
		_ok("⑪ ★★u_t 每帧在喂(shader 时间不是 TIME 是 t_acc) —— 回读真参数",
			absf(ut - float(h.get("t_acc", -1.0))) < 0.3, "u_t=%.2f t_acc=%.2f" % [ut, float(h.get("t_acc", 0.0))])
		_ok("⑪ u_env 跟着包络(此刻 s≈0.94 应 >0.5)", ue > 0.5, "u_env=%.2f" % ue)
	var src2: String = FileAccess.get_file_as_string("res://assets/shaders/mana_beam.gdshader")
	_ok("⑪ ★分母: shader 源文件在", src2.length() > 300, "len=%d" % src2.length())
	_ok("⑪ ★shader 不用 TIME(暂停一致/确定性 —— 时间只能走 u_t)",
		not ("TIME" in src2))
	_ok("⑪ ★shader 不做 UV 滚动(实测束身【不流动】: 55/55 帧对位移=0)",
		not ("u_flow" in src2) and not ("scroll" in src2))
	var rbs: Array = h.get("ribbons", [])
	_ok("⑪ ★分母: 枪口飘带 %d 条都在(真节点)" % Beam.RIBBON_N,
		rbs.size() == Beam.RIBBON_N and is_instance_valid(rbs[0]) if rbs.size() > 0 else false)
	if rbs.size() > 0 and is_instance_valid(rbs[0]):
		var rot_a: float = float((rbs[0] as Node3D).rotation.y)
		_ps._eq_beam_step(carrier, 0.05)
		var rot_b: float = float((rbs[0] as Node3D).rotation.y)
		var moved: float = absf(angle_difference(rot_a, rot_b))
		_ok("⑪ ★★飘带真的在公转(150°/s × 0.05s ≈ 7.5°)",
			moved > deg_to_rad(5.0) and moved < deg_to_rad(12.0),
			"实转 %.1f°" % rad_to_deg(moved))
	# ── 末端爆发: 束结束 → 白核+白刺带出现, 然后自清 ──
	_ps._eq_beam_step(carrier, 0.30)          # 2.88+0.30 > 3.0 ⇒ ended ⇒ finale
	_ok("⑩ ★分母: 束体已撤(finale 只留爆点)", not is_instance_valid(h.get("muzzle", null)))
	_ok("⑪ 飘带随 finale 一起撤(留着就绕一个空位转)", (h.get("ribbons", []) as Array).is_empty())
	var fmarks: Array = h.get("marks", [])
	var has_core := false
	for m in fmarks:
		if is_instance_valid(m.get("core", null)) and float(m.get("burst", -1.0)) >= 0.0:
			has_core = true
	_ok("⑩ ★★末端爆发: 白核节点真的建出来了(实测最后 0.1s 实心白核+白刺带)", has_core,
		"marks=%d" % fmarks.size())
	# 自清: 走真实驱动源 advance(帧去重 ⇒ 每次 await 一帧)。
	# ★先把 carrier 撤出 sim —— 真实 _process 也会对它调 advance(真实 delta≈0.016),
	#   帧去重会把门禁手动喂的 0.05 吃掉 ⇒ 0.16s < 0.17s 塌收永远走不完(踩过)。
	_s._units.clear()
	for _i in range(10):
		_ps._beam_vfx.advance(0.05)
		await get_tree().process_frame
	_ok("⑩ ★★爆发后自清(0.10s 爆发 + 0.07s 塌收, 之后节点必须归零)",
		_ps._beam_vfx.node_count() == 0 and _ps._beam_vfx.live_count() == 0,
		"还剩 %d 节点 / %d 句柄" % [_ps._beam_vfx.node_count(), _ps._beam_vfx.live_count()])
