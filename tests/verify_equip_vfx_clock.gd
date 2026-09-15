extends Node
## verify_equip_vfx_clock.gd — 装备演出时钟【帧率无关】(2026-09-15)
##
## 起因: 用户逐件验收 060 磷光水母伞, 我看 30fps 录屏时伞在屏上挂了约 4.6 秒, 而效果只有 2.5 秒。
## 探针(临时 tests/_probe_fps_vfx060, 已删): 每帧 1 步 sim → 效果 2.517s / 在屏 2.517s;
##   每帧 2 步 sim(= 30fps) → 效果 2.500s / 在屏 5.033s, 效果开了 1.017s 时伞的演出句柄 t 只有 0.500s。
## 根因: 灵物/药水/食物三层演出 + 068 激光尾巴挂在【每单位】的 tick 里, 按【引擎帧号】去重;
##   而 sim 是固定步长(SIM_DT = 1/60)的累加器 —— 30fps 一帧跑两步 sim, 帧号去重只放过第一步 ⇒ 演出慢一倍。
##   另外场上没有带装备的活单位时, 没人调那个 tick ⇒ 整层演出停摆(伞定格)。
##   同一类: EquipSystem._eq_on_hit 的「同一刻命中 ≥2 个目标 = 范围」也按帧号判(009 充能减半)。
##
## ★本门禁的规矩:
##   · 驱动照 verify_interactive_determinism: 关掉场景自己的 _process, 手动喂累加器;
##     但**每喂 spf 步就真的 await 一帧** —— 引擎帧号不走的话, 帧号去重根本不会被触发(= 假绿)。
##   · 尺子 = 【没被顿帧 / 时停冻住的 sim 步数】× SIM_DT。顿帧里效果和演出都该停, 拿总步数量会冤枉产品。
##   · 判据落在产品自己的账上: 效果侧的 pa_open / pa_t、演出句柄自己声明的 dur 与自己走的 t。
##   · 每组带分母断言。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	RB.DEBUG_EDIT = true
	print("=== 装备演出时钟: 帧率无关 ===")
	await _t_parasol_clock(1)
	await _t_parasol_clock(2)
	await _t_parasol_carrier_dies()
	await _t_parasol_hitstop()
	await _t_food_potion_beam()
	await _t_aoe_step_key()
	print("")
	## 分母: ①×2 各 5 + ② 3 + ③ 3 + ④ 4 + ⑤ 2 + ⑥ 4 = 26(第一版写成 30, 26 条全绿却没打 ALL PASS)
	if _fail == 0 and _n >= 26:
		print("ALL PASS (%d 条)" % _n)
		get_tree().quit(0)
	else:
		print("FAILED %d / %d" % [_fail, _n])
		get_tree().quit(1)


# ─────────────────────────────────────────────────────────────
#  台子
# ─────────────────────────────────────────────────────────────

## 调试场(假人不死、不还手), 关掉场景自己的 _process —— 只由本门禁喂累加器。
func _scene() -> Node:
	var s = RB.new()
	add_child(s)
	for _i in range(30):
		await get_tree().process_frame
	s.set_process(false)
	s._debug._edit_clear()
	s._edit_dummy_killable = false
	return s


func _start(s) -> void:
	s._debug._edit_start_battle()
	s._deterministic = false
	s._sim_accum = 0.0
	s._hitstop = 0.0
	s._sd_stacks = 0


## 挂装备 + 跑常驻字段管线(060/065~068/069~072 的每帧钩靠它开)
func _arm(s, u: Dictionary, ids: Array) -> void:
	u["equips"] = []
	u["eq_state"] = {}
	for iid in ids:
		(u["equips"] as Array).append({"id": iid, "star": 3})
		s._equip_sys._stats._eq_apply_flags(u, iid, 3)


## 一帧 = spf 步 sim, 然后真的等一帧(引擎帧号 +1)。返回本帧里【没被冻住】的步数。
func _frame(s, spf: int) -> int:
	var live := 0
	for _k in range(spf):
		if float(s._hitstop) <= 0.0 and s._timestop._ts_active.is_empty():
			live += 1
		s._advance_sim_accum(float(s.SIM_DT))
	await get_tree().process_frame
	return live


func _free(s) -> void:
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _find(arr: Array, kind: String) -> Dictionary:
	for h in arr:
		if h is Dictionary and str((h as Dictionary).get("kind", "")) == kind:
			return h
	return {}


func _has(arr: Array, h: Dictionary) -> bool:
	for x in arr:
		if is_same(x, h):
			return true
	return false


# ─────────────────────────────────────────────────────────────
# ① 060 伞: 在屏时长 == 效果时长; 效果开了 X 秒时演出句柄的 t 也是 X
# ─────────────────────────────────────────────────────────────
func _t_parasol_clock(spf: int) -> void:
	print("── ① 060 伞 · 每帧 %d 步 sim(%s) ──" % [spf, "≈60fps" if spf == 1 else "= 30fps"])
	var s = await _scene()
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._debug._edit_place_unit("fortune", "left", c + Vector2(-200.0, 0.0))
	s._debug._edit_place_unit("basic", "right", c + Vector2(600.0, 0.0))
	_start(s)
	_arm(s, u, ["p2eq_060"])
	var vfx = s._equip_sys._spirit_sys._vfx
	var dt: float = float(s.SIM_DT)
	var tol: float = 2.0 * float(spf) * dt + 1e-6
	var clock := 0.0
	var was_open := false
	var t_open := -1.0
	var t_close := -1.0
	var v_on := -1.0
	var v_off := -1.0
	var pair_pa := -1.0
	var pair_ht := -1.0
	var frames := 0
	var fr0: int = Engine.get_process_frames()
	while frames < 1500 and v_off < 0.0:
		clock += float(await _frame(s, spf)) * dt
		frames += 1
		var st: Dictionary = u["eq_state"].get("p2eq_060", {})
		var op: bool = bool(st.get("pa_open", false))
		var h: Dictionary = _find(vfx._live, "parasol")
		if op and not was_open and t_open < 0.0:
			t_open = clock
		if was_open and not op and t_close < 0.0:
			t_close = clock
		if v_on < 0.0 and not h.is_empty():
			v_on = clock
		if v_on >= 0.0 and v_off < 0.0 and h.is_empty():
			v_off = clock
		if op and not h.is_empty() and pair_pa < 0.0 and float(st.get("pa_t", 0.0)) >= 1.0:
			pair_pa = float(st.get("pa_t", 0.0))
			pair_ht = float(h.get("t", -1.0))
		was_open = op
	var fr_used: int = Engine.get_process_frames() - fr0
	_ok("① spf=%d ★分母: 引擎帧号真的逐帧在走(喂 %d 帧 / 帧号走了 %d) —— 不走的话帧号去重根本不会被触发" % [spf, frames, fr_used],
		fr_used == frames)
	_ok("① spf=%d ★分母: 伞开过也收过, 演出句柄出现过也消失过" % spf,
		t_open >= 0.0 and t_close >= 0.0 and v_on >= 0.0 and v_off >= 0.0,
		"开 %.3f 收 %.3f / 出现 %.3f 消失 %.3f" % [t_open, t_close, v_on, v_off])
	_ok("① spf=%d 效果持续 2.5 秒(需求原文「持续 2.5 秒」)" % spf,
		absf((t_close - t_open) - 2.5) <= tol, "实测 %.3f" % (t_close - t_open))
	_ok("① spf=%d ★★伞在屏时长 == 效果时长(修前 30fps 实测: 在屏 5.033 / 效果 2.500)" % spf,
		absf((v_off - v_on) - (t_close - t_open)) <= tol,
		"在屏 %.3f / 效果 %.3f / 容差 %.3f" % [v_off - v_on, t_close - t_open, tol])
	_ok("① spf=%d ★★效果开了 %.3f 秒时, 演出句柄自己的 t 也是这么多(修前 30fps: 1.017 时只有 0.500)" % [spf, pair_pa],
		pair_pa >= 0.0 and absf(pair_ht - pair_pa) <= tol, "句柄 t=%.3f" % pair_ht)
	await _free(s)


# ─────────────────────────────────────────────────────────────
# ② 伞开着时携带者阵亡, 场上再没有带装备的活单位: 伞照样按时收起, 不定格
#    修前: 这层演出只在【带装备的活单位】的 tick 里推进 ⇒ 一死整层停摆
# ─────────────────────────────────────────────────────────────
func _t_parasol_carrier_dies() -> void:
	print("── ② 060 伞开着时携带者阵亡 · 30fps ──")
	var s = await _scene()
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._debug._edit_place_unit("fortune", "left", c + Vector2(-200.0, 0.0))
	## 不带装备的队友: 让战斗别因为左边死光而结束
	var mate: Dictionary = s._debug._edit_place_unit("fortune", "left", c + Vector2(-260.0, 160.0))
	s._debug._edit_place_unit("basic", "right", c + Vector2(600.0, 0.0))
	_start(s)
	_arm(s, u, ["p2eq_060"])
	mate["equips"] = []
	var vfx = s._equip_sys._spirit_sys._vfx
	var dt: float = float(s.SIM_DT)
	var tol: float = 4.0 * dt + 1e-6
	var clock := 0.0
	var v_on := -1.0
	var v_off := -1.0
	var killed := false
	var h_at_kill := false
	var armed_alive := -1
	var frames := 0
	while frames < 900 and v_off < 0.0:
		clock += float(await _frame(s, 2)) * dt
		frames += 1
		var h: Dictionary = _find(vfx._live, "parasol")
		if v_on < 0.0 and not h.is_empty():
			v_on = clock
		if v_on >= 0.0 and v_off < 0.0 and h.is_empty():
			v_off = clock
		if v_on >= 0.0 and not killed and v_off < 0.0 and clock - v_on >= 0.5:
			h_at_kill = not h.is_empty()
			s._kill(u, null)
			killed = true
			armed_alive = 0
			for o in s._units:
				if o is Dictionary and bool((o as Dictionary).get("alive", false)) \
						and not ((o as Dictionary).get("equips", []) as Array).is_empty():
					armed_alive += 1
	_ok("② ★分母: 伞开到 0.5 秒时杀掉了携带者, 当时伞还在, 携带者确实死了, 战斗没结束",
		killed and h_at_kill and not bool(u.get("alive", true)) and not bool(s._over),
		"killed=%s 伞在=%s alive=%s over=%s" % [str(killed), str(h_at_kill), str(u.get("alive", true)), str(s._over)])
	_ok("② ★分母: 杀掉之后场上【带装备的活单位】= 0(修前正是这种情形整层停摆)", armed_alive == 0,
		"实为 %d" % armed_alive)
	_ok("② ★★伞仍然在开伞后 2.5 秒收起, 不定格(修前: 永远不消失)",
		v_off >= 0.0 and absf((v_off - v_on) - 2.5) <= tol,
		"出现 %.3f 消失 %.3f → 在屏 %.3f" % [v_on, v_off, v_off - v_on])
	await _free(s)


# ─────────────────────────────────────────────────────────────
# ③ 顿帧期间: 效果计时(_tick_parasol)不走, 演出也不许走 —— 两者之差在顿帧前后不变
# ─────────────────────────────────────────────────────────────
func _t_parasol_hitstop() -> void:
	print("── ③ 060 伞 · 顿帧期间演出与效果一起停 ──")
	var s = await _scene()
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._debug._edit_place_unit("fortune", "left", c + Vector2(-200.0, 0.0))
	s._debug._edit_place_unit("basic", "right", c + Vector2(600.0, 0.0))
	_start(s)
	_arm(s, u, ["p2eq_060"])
	var vfx = s._equip_sys._spirit_sys._vfx
	var dt: float = float(s.SIM_DT)
	var frames := 0
	var h: Dictionary = {}
	var st: Dictionary = {}
	while frames < 900:
		await _frame(s, 2)
		frames += 1
		st = u["eq_state"].get("p2eq_060", {})
		h = _find(vfx._live, "parasol")
		if bool(st.get("pa_open", false)) and not h.is_empty() and float(st.get("pa_t", 0.0)) >= 0.5:
			break
	var ok0: bool = not h.is_empty() and bool(st.get("pa_open", false))
	_ok("③ ★分母: 伞开着且演出句柄在", ok0)
	if not ok0:
		await _free(s)
		return
	var pa0: float = float(st.get("pa_t", 0.0))
	var ht0: float = float(h.get("t", 0.0))
	s._hitstop = 0.30
	var frozen := 0
	var guard := 0
	while float(s._hitstop) > 0.0 and guard < 60:
		frozen += 2 - int(await _frame(s, 2))
		guard += 1
	st = u["eq_state"].get("p2eq_060", {})
	var pa1: float = float(st.get("pa_t", 0.0))
	var ht1: float = float(h.get("t", 0.0))
	_ok("③ ★分母: 顿帧 0.30 秒真的冻住了 ≥16 步 sim, 效果计时在此期间最多走 2 步",
		frozen >= 16 and absf(pa1 - pa0) <= 2.0 * dt + 1e-6,
		"冻住 %d 步 · 效果计时 %.3f → %.3f" % [frozen, pa0, pa1])
	_ok("③ ★★顿帧前后「演出 t − 效果 t」不变(去掉演出层的顿帧闸, 演出会多走 0.30 秒)",
		absf((ht1 - pa1) - (ht0 - pa0)) <= 2.0 * dt + 1e-6,
		"前 %.3f / 后 %.3f" % [ht0 - pa0, ht1 - pa1])
	await _free(s)


# ─────────────────────────────────────────────────────────────
# ④ 食物层(070 砖块命中 → 溅冠 crown + 冲击环 bwave) / 药水层(067 每 6 秒毒瓶 → 飞行 vial + 溅 vsplash + 毒雾 cloud):
#    每个演出句柄的在屏时长(未冻住的 sim 秒) == 它自己声明的 dur。修前 30fps 下 = 2 × dur。
# ⑤ 068 激光收尾: 枪口 + 飘带 0.2 秒渐隐(实测值 MUZZLE_FADE)在 30fps 下也是 0.2 秒。
# ─────────────────────────────────────────────────────────────
func _t_food_potion_beam() -> void:
	print("── ④⑤ 食物层 / 药水层 / 068 激光尾巴 · 30fps ──")
	var s = await _scene()
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._debug._edit_place_unit("fortune", "left", c + Vector2(-150.0, 0.0))
	var dm: Dictionary = s._debug._edit_place_unit("basic", "right", c + Vector2(150.0, 0.0))
	_start(s)
	_arm(s, u, ["p2eq_070", "p2eq_067", "p2eq_068"])
	var dt: float = float(s.SIM_DT)
	var tol: float = 4.0 * dt + 1e-6
	var layers := {"食物": s._equip_sys._food_sys._vfx, "药水": s._equip_sys._potion_sys._vfx}
	var watch: Array = []
	var done: Array = []
	var clock := 0.0
	var frames := 0
	var hb: Dictionary = {}
	var fin_at := -1.0
	var fin_marks := -1
	var fade_end := -1.0
	var charged := -1.0
	while frames < 800 and clock < 16.5:
		clock += float(await _frame(s, 2)) * dt
		frames += 1
		## 068 的充能只来自【受到的伤害】(储量为 0 时第 12 秒直接不放激光), 而假人不还手
		##   ⇒ 第 2 秒走真受伤入口挨一下(第一版没挨打, ⑤ 的分母当场红: 句柄一次都没出现)。
		if charged < 0.0 and clock >= 2.0:
			s._damage._apply_damage_from(dm, u, 200, Color(1, 1, 1))
			charged = float((u["eq_state"].get("p2eq_068", {}) as Dictionary).get("can_charge", 0.0))
		for name in layers:
			for h in layers[name]._live:
				if not (h is Dictionary):
					continue
				var d: float = float((h as Dictionary).get("dur", -1.0))
				if d <= 0.0 or d > 30.0:
					continue
				var known := false
				for r in watch:
					if is_same(r["h"], h):
						known = true
						break
				if not known:
					watch.append({"h": h, "layer": name, "on": clock})
		var keep: Array = []
		for r in watch:
			if _has(layers[r["layer"]]._live, r["h"]):
				keep.append(r)
			else:
				done.append({"layer": r["layer"], "kind": str((r["h"] as Dictionary).get("kind", "")),
					"dur": float((r["h"] as Dictionary)["dur"]), "scr": clock - float(r["on"])})
		watch = keep
		var s68: Dictionary = u["eq_state"].get("p2eq_068", {})
		var bh = s68.get("beam_h", {})
		if hb.is_empty() and bh is Dictionary and not (bh as Dictionary).is_empty():
			hb = bh
		if not hb.is_empty() and fin_at < 0.0 and hb.has("fade_t"):
			fin_at = clock
			fin_marks = (hb.get("marks", []) as Array).size()
		if fin_at >= 0.0 and fade_end < 0.0 and (hb.get("fade_nodes", []) as Array).is_empty():
			fade_end = clock
	var want_kinds := {"食物": ["crown", "bwave"], "药水": ["vial", "vsplash", "cloud"]}
	for name in want_kinds:
		var worst := 0.0
		var worst_s := ""
		var nk := {}
		for r in done:
			if str(r["layer"]) != name or not (want_kinds[name] as Array).has(str(r["kind"])):
				continue
			nk[str(r["kind"])] = int(nk.get(str(r["kind"]), 0)) + 1
			var e: float = absf(float(r["scr"]) - float(r["dur"]))
			if e >= worst:
				worst = e
				worst_s = "%s dur=%.3f 在屏=%.3f" % [str(r["kind"]), float(r["dur"]), float(r["scr"])]
		var all_in := true
		for k in want_kinds[name]:
			if int(nk.get(k, 0)) < 1:
				all_in = false
		_ok("④ %s层 ★分母: %s 每种都至少完整播完一次" % [name, str(want_kinds[name])], all_in, "各 %s" % str(nk))
		_ok("④ %s层 ★★每个句柄在屏时长 == 自己的 dur(修前 30fps 下是 2 倍)" % name,
			all_in and worst <= tol, "最差 %s · 容差 %.3f" % [worst_s, tol])
	_ok("⑤ ★分母: 挨打攒到了充能, 068 在第 12 秒放出了激光, 3 秒后收尾(finale), 收尾时有正在照的爆点(否则尾巴不归 advance 管)",
		charged > 0.0 and not hb.is_empty() and fin_at >= 0.0 and fin_marks > 0,
		"充能 %.1f · 句柄=%s 收尾 %.3f 爆点 %d" % [charged, str(not hb.is_empty()), fin_at, fin_marks])
	_ok("⑤ ★★枪口 + 飘带渐隐 0.2 秒(修前 30fps 下 0.4 秒)",
		fade_end >= 0.0 and absf((fade_end - fin_at) - 0.2) <= tol,
		"收尾 %.3f → 渐隐完 %.3f = %.3f 秒" % [fin_at, fade_end, fade_end - fin_at])
	await _free(s)


# ─────────────────────────────────────────────────────────────
# ⑥ 009「同一刻命中 ≥2 个不同目标 = 范围(充能减半)」按 sim 步判, 不按引擎帧号。
#    30fps 下一帧两步 sim: 相邻两步各打一个目标, 修前被判成范围。
# ─────────────────────────────────────────────────────────────
func _t_aoe_step_key() -> void:
	print("── ⑥ 009 范围判定按 sim 步号 ──")
	var s = await _scene()
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	s._units.clear()
	var a: Dictionary = s._spawn._make_unit("fortune", "left", c + Vector2(-100.0, 0.0))
	var b1: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(100.0, -60.0))
	var b2: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(100.0, 60.0))
	for x in [a, b1, b2]:
		s._units.append(x)
	a["equips"] = [{"id": "p2eq_009", "star": 1}]
	## 对照组: 同一步里连打两个不同目标 → 第二下算范围 ⇒ 20 + 20×0.5 = 30(证明判定没被整个关掉)
	a["eq_state"] = {"p2eq_009": {}}
	a["_onhit_fr"] = -999
	s._equip_sys._eq_on_hit(a, b1, 10, true, false)
	var e1: float = float(a["eq_state"]["p2eq_009"].get("blade_energy", 0.0))
	s._equip_sys._eq_on_hit(a, b2, 10, true, false)
	var e_same: float = float(a["eq_state"]["p2eq_009"].get("blade_energy", 0.0))
	## 相邻两步各打一个目标, 中间【不】等引擎帧 —— 正是 30fps 一帧跑两步 sim 的情形
	a["eq_state"] = {"p2eq_009": {}}
	a["_onhit_fr"] = -999
	s._equip_sys._eq_on_hit(a, b1, 10, true, false)
	var n0: int = int(s._sim_step_n)
	var f0: int = Engine.get_process_frames()
	s._sim_step(float(s.SIM_DT), false, false)
	var n1: int = int(s._sim_step_n)
	var f1: int = Engine.get_process_frames()
	s._equip_sys._eq_on_hit(a, b2, 10, true, false)
	var e_two: float = float(a["eq_state"]["p2eq_009"].get("blade_energy", 0.0))
	_ok("⑥ ★分母: 第一下单体命中充能 20(1 星)", absf(e1 - 20.0) < 0.001, "实测 %.2f" % e1)
	_ok("⑥ ★分母: 两次命中之间 sim 步号 +1、引擎帧号没动", n1 - n0 == 1 and f1 == f0,
		"步号 %d→%d · 帧号 %d→%d" % [n0, n1, f0, f1])
	_ok("⑥ 对照: 同一步里两个目标 → 第二下按范围减半 ⇒ 30", absf(e_same - 30.0) < 0.001, "实测 %.2f" % e_same)
	_ok("⑥ ★★相邻两步各一个目标 → 两下都是单体 ⇒ 40(修前按帧号判成范围: 30)",
		absf(e_two - 40.0) < 0.001, "实测 %.2f" % e_two)
	await _free(s)
