extends Node
## verify_timestop_since_stamps.gd — 时停里【「上次发生时刻」戳】谁走谁停
##
## ══════════════════════════════════════════════════════════════════
##  由来(方案书 20260916c §8.8 尾巴·2026-10-04)
## ══════════════════════════════════════════════════════════════════
## 一类冷却写成「记下发生时刻 `x = _t`, 之后判 `_t - x >= CD`」(忍者被动冲刺 `_ninja_last_dash` 等)。
## 时停里 `_t` 冻住 ⇒ 对**携带者**来说 `_t - x` 永远停在时停开始那一刻:
##   携带者忍者在时停里冲一次就再也冲不了(间隔 0.4 秒永远凑不够)。
## 修法在 `TimestopSystem._ts_advance_unit_timers` 一处: 携带者 tick 前把这些戳往回挪 dt(TS_SINCE_UNIT_FIELDS / TS_SINCE_EQ_FIELDS)。
##
## ★判据(每条配分母):
##   ① 携带者忍者(真被动·真触发器): 时停里「上次冲刺 → 下一次被动冲刺」的步数 == 平时(对照组)
##   ② 被定格的忍者: 时停里 120 步不冲、`_ninja_last_dash` 逐位不变; 解除后按【剩下的】冷却冲(不是重新算、也不是早就冷却好了)
##   ③ 两张表里的每个字段: 携带者 1.5 秒后「已过去」== 1.5 秒; 被定格者 == 0
## ★时停用**真入口**触发(装 059 → `_ts_update_trigger` → 蓄力 1 秒 → `_ts_fire`), 不手写 `_ts_active`。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const TSS := preload("res://scripts/systems/equip/timestop_system.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if c:
		print("  [OK] %s  %s" % [t, ex])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [t, ex])


func _wait(nf: int) -> void:
	for _i in range(nf):
		await get_tree().process_frame


func _mk(id: String, side: String, at: Vector2) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit(id, side, at)
	u["no_move"] = true
	u["no_basic"] = true
	u["move_spd"] = 0.0
	u["maxHp"] = 99999.0
	u["hp"] = 99999.0
	u["active_skills"] = []   # 不放技: 时停瞬间给 +300 龟能, 放技会把别的协程混进来
	_s._units.append(u)
	return u


## 推 sim 直到 cond 成立或到上限, 返回走了几步。det 模式下一帧恰一步。
func _until(cond: Callable, cap: int) -> int:
	var n0: int = int(_s._sim_step_n)
	var k := 0
	while not cond.call() and k < cap:
		await get_tree().process_frame
		k += 1
	return int(_s._sim_step_n) - n0


## 给忍者 nj 摆一个「刚好可冲」的靶子(射程内·不在 10 秒冷却里·落地), 返回靶子。
func _arm_target(nj: Dictionary, dummy: Dictionary, dx: float) -> void:
	dummy["pos"] = (nj["pos"] as Vector2) + Vector2(dx, 0.0)
	dummy.erase("_ninja_dash_until")
	dummy["airborne"] = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 时停里「上次发生时刻」戳: 携带者照走 / 被定格者停 ===")
	_s = RB.new()
	add_child(_s)
	_s._deterministic = true   # 每帧恰一步 sim ⇒ 步数与机器快慢无关
	await _wait(40)
	_s._units.clear()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var nc: Dictionary = _mk("ninja", "left", c + Vector2(-600, -200))    # 将来的携带者
	var dr: Dictionary = _mk("basic", "right", c + Vector2(-400, -200))   # 携带者的靶子
	var nf: Dictionary = _mk("ninja", "right", c + Vector2(600, 260))     # 将来被定格的忍者
	var dl: Dictionary = _mk("basic", "left", c + Vector2(400, 260))      # 它的靶子
	nc["_ninja_last_dash"] = 1.0e9   # 先都按住(`_t - 1e9` < 0): 只在要量的时候放开
	nf["_ninja_last_dash"] = 1.0e9
	await _wait(10)
	var ts = _s._timestop

	# ── 对照组(时停之前): 刚冲完 → 下一次被动冲刺要几步 ──
	_arm_target(nc, dr, 200.0)
	nc["_ninja_last_dash"] = float(_s._t)
	var t_c0: float = float(_s._t)
	var n_c_raw: int = await _until(func() -> bool: return bool(nc.get("_ninja_gliding", false)), 300)
	## ★平时量的是【游戏时间走了几步】而不是 sim 步数: 开场有几步 `_t` 不走(实测 29 步里 `_t` 只走了 25 步),
	##   而时停里携带者每步都 tick ⇒ 两边要比的是「携带者自己过了几步」。
	var n_c: int = int(round((float(_s._t) - t_c0) / _s.SIM_DT))
	_ok("★分母·对照: 平时「上次冲刺 → 下一次被动冲刺」游戏时间 %d 步(sim %d 步)(DASH_SELF_CD=%.2f 秒 ≈ %d 步)" % [n_c, n_c_raw, NinjaSystem.DASH_SELF_CD, int(round(NinjaSystem.DASH_SELF_CD / _s.SIM_DT))],
		bool(nc.get("_ninja_gliding", false)) and absi(n_c - int(round(NinjaSystem.DASH_SELF_CD / _s.SIM_DT))) <= 1)
	await _until(func() -> bool: return not bool(nc.get("_ninja_gliding", false)) and float(_s._hitstop) == 0.0, 600)
	await _wait(80)   # 靶子击飞 0.8 秒落地
	nc["_ninja_last_dash"] = 1.0e9
	_ok("★分母: 对照组跑完时停还没开始(_ts_fired=%s)" % str(ts._ts_fired),
		not bool(ts._ts_fired) and (ts._ts_active as Array).is_empty())

	# ── 真入口触发时停(3★ = 20 秒) ──
	nc["equips"] = [{"id": "p2eq_059", "star": 3}]
	_s._t = 999.0
	ts._ts_update_trigger(0.016)
	var n_fire: int = await _until(func() -> bool: return not (ts._ts_active as Array).is_empty(), 400)
	_ok("★分母: 真入口放出了时停(%d 步后 · 携带者在名单里 · 剩 %.2f 秒)" % [n_fire, float(ts._ts_remaining)],
		_s._arr_has_unit(ts._ts_active, nc) and not _s._arr_has_unit(ts._ts_active, nf)
		and float(ts._ts_remaining) > 15.0)

	# ── ① 携带者: 时停里刚冲完 → 下一次被动冲刺, 步数 == 平时 ──
	var t_frozen0: float = float(_s._t)
	_arm_target(nc, dr, 200.0)
	nc["_ninja_last_dash"] = float(_s._t)
	## ② 同时: 被定格的忍者冷却走了一半(0.2 秒), 靶子就在射程里
	_arm_target(nf, dl, -200.0)
	nf["_ninja_last_dash"] = float(_s._t) - 0.2
	var nf_last0: float = float(nf["_ninja_last_dash"])
	var n_t: int = await _until(func() -> bool: return bool(nc.get("_ninja_gliding", false)), 300)
	_ok("★① 携带者忍者时停里「上次冲刺 → 下一次被动冲刺」%d 步 == 平时 %d 步(容 1 步: 两边浮点累加次序不同)" % [n_t, n_c],
		bool(nc.get("_ninja_gliding", false)) and absi(n_t - n_c) <= 1, "修前: `_t - _ninja_last_dash` 恒 0 ⇒ 300 步都不冲")
	_ok("★分母①: 这段时间 `_t` 真的冻着(%.3f → %.3f) —— 否则①是在正常时间里量的" % [t_frozen0, float(_s._t)],
		float(_s._t) == t_frozen0 and not (ts._ts_active as Array).is_empty())
	await _wait(maxi(0, 120 - n_t))
	_ok("★② 被定格的忍者时停里 120 步没冲(滑行中=%s), `_ninja_last_dash` 逐位不变(%.6f → %.6f)" % [str(nf.get("_ninja_gliding", false)), nf_last0, float(nf["_ninja_last_dash"])],
		not bool(nf.get("_ninja_gliding", false)) and float(nf["_ninja_last_dash"]) == nf_last0,
		"被定格者的冷却也在走 ⇒ 时停没冻住它")
	_ok("★分母②: 它的靶子一直在射程里且可冲(距 %.1f 码 ≤ %.0f)" % [(nf["pos"] as Vector2).distance_to(dl["pos"]), NinjaSystem.DASH_SENSE],
		(nf["pos"] as Vector2).distance_to(dl["pos"]) <= NinjaSystem.DASH_SENSE and not dl.has("_ninja_dash_until"))

	# ── ③ 两张表逐字段: 携带者「已过去」照走, 被定格者不动 ──
	await _until(func() -> bool: return not bool(nc.get("_ninja_gliding", false)) and float(_s._hitstop) == 0.0, 600)
	nc["_ninja_last_dash"] = 1.0e9   # 下面这段不让它再冲(冲刺会重写这个字段)
	var tnow: float = float(_s._t)
	var ufs: Array = TSS.TS_SINCE_UNIT_FIELDS.filter(func(f): return f != "_ninja_last_dash")
	var efs: Array = TSS.TS_SINCE_EQ_FIELDS
	for who in [nc, nf]:
		for f in ufs: who[f] = tnow
		if not (who.get("eq_state", null) is Dictionary): who["eq_state"] = {}
		var est: Dictionary = {}
		for f in efs: est[f] = tnow
		(who["eq_state"] as Dictionary)["_probe"] = est
	await _wait(90)   # 1.5 秒
	var c_el: Array = []
	var f_el: Array = []
	for who in [nc, nf]:
		var arr: Array = c_el if is_same(who, nc) else f_el   # 单位字典不许 ==(递归哈希, CLAUDE.md §3.2)
		for f in ufs: arr.append(snappedf(float(_s._t) - float(who[f]), 0.001))
		for f in efs: arr.append(snappedf(float(_s._t) - float(((who["eq_state"] as Dictionary)["_probe"] as Dictionary)[f]), 0.001))
	_ok("★分母③: 两张表共 %d 个字段(单位 %d + 装备子状态 %d)" % [ufs.size() + efs.size(), ufs.size(), efs.size()],
		ufs.size() >= 8 and efs.size() >= 3)
	_ok("★③ 携带者每个字段 1.5 秒后「已过去」都 == 1.5(%s)" % str(c_el),
		c_el.all(func(x): return absf(float(x) - 1.5) < 0.002), "修前: `_t` 不走 ⇒ 全是 0")
	_ok("★③ 被定格者每个字段「已过去」都 == 0(%s)" % str(f_el),
		f_el.all(func(x): return float(x) == 0.0) and float(_s._t) == tnow)
	_ok("★分母③: 量的时候时停一直开着(剩 %.2f 秒)" % float(ts._ts_remaining),
		not (ts._ts_active as Array).is_empty() and float(ts._ts_remaining) > 10.0)

	# ── 解除后: 被定格的忍者按【剩下的】0.2 秒冲(≈12 步), 不是立刻、也不是从头 0.4 秒 ──
	_arm_target(nf, dl, -200.0)
	ts._end_timestop()
	var n_after: int = await _until(func() -> bool: return bool(nf.get("_ninja_gliding", false)), 300)
	var want: int = int(round((NinjaSystem.DASH_SELF_CD - 0.2) / _s.SIM_DT))
	_ok("★② 解除后被定格的忍者 %d 步后冲(剩 0.2 秒 ≈ %d 步)" % [n_after, want],
		bool(nf.get("_ninja_gliding", false)) and absi(n_after - want) <= 1)

	print("")
	if _fail == 0: print("ALL PASS — 时停「上次发生时刻」戳 %d 条" % _n)
	else: print("FAILED: %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
