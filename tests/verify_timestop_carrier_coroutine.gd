extends Node
## verify_timestop_carrier_coroutine.gd — 时停里【多段技协程】谁走谁停
##
## ══════════════════════════════════════════════════════════════════
##  由来(方案书 20260916c §8.7 #8·2026-10-04 探针坐实)
## ══════════════════════════════════════════════════════════════════
## 时停的设计: 携带者「自由攻击/施法/移动、伤害即时结算」, 其余全场定格。
## 但 `_wait_sim(secs)` 量的是 `_t`, 而 `_t` 只在正常分支走 —— 时停分支只推 `_ts_remaining`。
## ⇒ **携带者自己**的多段技(忍者冲刺起手/落地、血刃连斩、剑线/激光/月刃、熔岩…)一碰 `_wait_sim`
##   就停在半路, 等时停结束才继续。探针: det 模式 `_wait_sim(0.1)` 平时 6 步醒, 时停里 1206 步。
## 反过来, 直接 `await sim_stepped` 推位移的那一族(忍者滑行段/双头炮弹/剑气/熊…)每步都醒 ⇒
##   **被定格的**单位在时停里照样在走。
##
## ★判据(每条配分母):
##   ① 携带者 `_wait_sim(0.1, 携带者)` 时停里醒的步数 == 平时(对照组)
##   ② 被定格单位 `_wait_sim(0.1, 它)` 时停里 120 步都不醒; 缺省 who 的(全局演出)也不醒 —— 旧行为保留
##   ③ 携带者【忍者冲刺】整段(起手→滑行→落地)时停里的步数 == 平时, 且真的走到了终点
##   ④ 被定格的忍者在时停开始时正滑到一半 ⇒ 时停里 120 步位置一动不动; 时停解除后照常走完
## ★时停用**真入口**触发(装 059 → `_ts_update_trigger` → 蓄力 1 秒 → `_ts_fire`), 不手写 `_ts_active`。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

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


## 启动一次 `_wait_sim(secs, who)`, 返回记账字典 {done, n0, n1}(步号)。
func _start_wait(secs: float, who) -> Dictionary:
	var st := {"done": false, "n0": int(_s._sim_step_n), "n1": -1}
	var f := func() -> void:
		if who == null: await _s._wait_sim(secs)
		else: await _s._wait_sim(secs, who)
		st["done"] = true
		st["n1"] = int(_s._sim_step_n)
	f.call()
	return st


## 启动一次忍者冲刺(真函数 `_ninja_glide`), 返回记账字典。hits 为空 ⇒ 不打人、不顿帧。
func _start_glide(u: Dictionary, dist: float) -> Dictionary:
	var st := {"n0": int(_s._sim_step_n), "start": u["pos"], "endp": u["pos"] + Vector2(dist, 0.0)}
	_s._ninja_sys._ninja_glide(u, u["pos"], st["endp"], Vector2(1, 0), u, [])
	return st


## 推 sim 直到 cond 成立或到上限, 返回走了几步。det 模式下一帧恰一步。
func _until(cond: Callable, cap: int) -> int:
	var n0: int = int(_s._sim_step_n)
	var k := 0
	while not cond.call() and k < cap:
		await get_tree().process_frame
		k += 1
	return int(_s._sim_step_n) - n0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 时停里多段技协程: 携带者照走 / 被定格者停 ===")
	_s = RB.new()
	add_child(_s)
	_s._deterministic = true   # 每帧恰一步 sim ⇒ 步数与机器快慢无关
	await _wait(40)
	_s._units.clear()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	## ★两只都用【普通龟】跑忍者冲刺的真函数: 摆真忍者的话它的被动自动冲刺(主场景 `_ninja_last_dash`)
	##   会冲向对面那只并打出顿帧, 和我量的那一段搅在一起(第一版实测: 对照组 38 步 / 只走 260 码)。
	var carrier: Dictionary = _mk("basic", "left", c + Vector2(-500, -120))
	var frozen: Dictionary = _mk("basic", "right", c + Vector2(-500, 160))
	await _wait(10)
	var ts = _s._timestop

	# ── 对照组(时停之前): 同样的等待 / 同样的冲刺各要几步 ──
	var w0: Dictionary = _start_wait(0.1, carrier)   # nowait: 故意并发启动, 结果靠记账字典轮询
	var n_w0: int = await _until(func() -> bool: return bool(w0["done"]), 200)
	var g0: Dictionary = _start_glide(carrier, 300.0)
	var n_g0: int = await _until(func() -> bool: return not bool(carrier.get("_ninja_gliding", false)), 600)
	var d_g0: float = (carrier["pos"] as Vector2).distance_to(g0["start"])
	_ok("★分母·对照: 平时 `_wait_sim(0.1)` %d 步醒(应 6)、冲刺 300 码 %d 步走完、走了 %.1f 码" % [n_w0, n_g0, d_g0],
		n_w0 == 6 and n_g0 > 20 and n_g0 < 200 and absf(d_g0 - 300.0) < 0.5 and float(_s._hitstop) == 0.0)
	_ok("★分母: 对照组跑完时停还没开始(_ts_fired=%s)" % str(ts._ts_fired),
		not bool(ts._ts_fired) and (ts._ts_active as Array).is_empty())

	# ── 真入口触发时停(3★ = 20 秒) ──
	carrier["equips"] = [{"id": "p2eq_059", "star": 3}]
	_s._t = 999.0
	ts._ts_update_trigger(0.016)
	## 被定格那只在蓄力段(世界还在走)开始冲刺: 起手 0.18 秒 + 900 码 ⇒ 时停释放时正滑到一半
	var g_fz: Dictionary = _start_glide(frozen, 900.0)
	var n_fire: int = await _until(func() -> bool: return not (ts._ts_active as Array).is_empty(), 400)
	_ok("★分母: 真入口放出了时停(%d 步后 · 携带者在名单里 · 剩 %.2f 秒)" % [n_fire, float(ts._ts_remaining)],
		_s._arr_has_unit(ts._ts_active, carrier) and not _s._arr_has_unit(ts._ts_active, frozen)
		and float(ts._ts_remaining) > 15.0)
	var fz_mid: float = (frozen["pos"] as Vector2).distance_to(g_fz["start"])
	_ok("★分母④: 时停开始时被定格的忍者正滑到一半(已走 %.1f / 900 码 · 滑行中=%s)" % [fz_mid, str(frozen.get("_ninja_gliding", false))],
		fz_mid > 30.0 and fz_mid < 870.0 and bool(frozen.get("_ninja_gliding", false)))

	# ── ① 携带者的等待: 步数与平时相同 ──
	var t_frozen0: float = float(_s._t)
	var w1: Dictionary = _start_wait(0.1, carrier)   # nowait: 故意并发启动, 结果靠记账字典轮询
	var n_w1: int = await _until(func() -> bool: return bool(w1["done"]), 200)
	_ok("★① 携带者 `_wait_sim(0.1, 携带者)` 时停里 %d 步醒 == 平时 %d 步" % [n_w1, n_w0],
		bool(w1["done"]) and n_w1 == n_w0, "修前: 等到时停结束(~1200 步)才醒")
	_ok("★分母①: 这段时间 `_t` 真的冻着(%.3f → %.3f) —— 否则①是在正常时间里量的" % [t_frozen0, float(_s._t)],
		float(_s._t) == t_frozen0 and not (ts._ts_active as Array).is_empty())

	# ── ② 被定格者 / 全局演出的等待: 时停里不醒 ──
	var w2: Dictionary = _start_wait(0.1, frozen)   # nowait: 故意并发启动, 结果靠记账字典轮询
	var w3: Dictionary = _start_wait(0.1, null)   # nowait: 故意并发启动, 结果靠记账字典轮询
	var fz_pos0: Vector2 = frozen["pos"]
	var g1: Dictionary = _start_glide(carrier, 300.0)
	var n_g1: int = await _until(func() -> bool: return not bool(carrier.get("_ninja_gliding", false)), 600)
	var d_g1: float = (carrier["pos"] as Vector2).distance_to(g1["start"])
	await _wait(maxi(0, 120 - n_g1))
	_ok("★② 被定格者 `_wait_sim(0.1, 它)` 时停里 120 步不醒(done=%s); 缺省 who 的也不醒(done=%s)" % [str(w2["done"]), str(w3["done"])],
		not bool(w2["done"]) and not bool(w3["done"]))
	# ── ③ 携带者的冲刺整段: 步数与平时相同, 且真的走到了终点 ──
	_ok("★③ 携带者忍者冲刺(起手→滑行→落地)时停里 %d 步走完 == 平时 %d 步 · 走了 %.1f 码" % [n_g1, n_g0, d_g1],
		n_g1 == n_g0 and absf(d_g1 - 300.0) < 0.5, "修前: 起手第一格就停住, 等时停结束")
	# ── ④ 被定格的忍者: 时停里一动不动 ──
	var fz_move: float = (frozen["pos"] as Vector2).distance_to(fz_pos0)
	_ok("★④ 被定格的忍者滑到一半, 时停里 120 步位移 %.2f 码(必须 0)" % fz_move, fz_move < 0.001,
		"修前: `await sim_stepped` 每步都醒 ⇒ 被定格的人照样在滑")
	_ok("★分母②③④: 量的时候时停一直开着(剩 %.2f 秒)" % float(ts._ts_remaining),
		not (ts._ts_active as Array).is_empty() and float(ts._ts_remaining) > 10.0)

	# ── ⑤ 到期时刻(§8.7 #9 补进来的那几个): 携带者的时停里照常倒计时, 被定格者的不动 ──
	## 顶层字段走主场景 `_TS_TIMER_FIELDS`, 装备子状态走 `TimestopSystem.TS_EQ_TIMER_FIELDS` —— 两张表各抽一个代表。
	var tnow: float = float(_s._t)
	var keys := ["move_buff_until", "stiff_until", "eq:p2eq_081:up_until", "eq:p2eq_062:emp_cd_until"]
	for who in [carrier, frozen]:
		who["move_buff_until"] = tnow + 1.0
		who["stiff_until"] = tnow + 1.0
		if not (who.get("eq_state", null) is Dictionary): who["eq_state"] = {}
		(who["eq_state"] as Dictionary)["p2eq_081"] = {"up_until": tnow + 1.0}
		(who["eq_state"] as Dictionary)["p2eq_062"] = {"emp_cd_until": tnow + 1.0}
	await _wait(90)   # 1.5 秒 > 1 秒
	var rd := func(who: Dictionary, k: String) -> float:
		if k.begins_with("eq:"):
			var bits: PackedStringArray = k.split(":")
			return float(((who["eq_state"] as Dictionary)[bits[1]] as Dictionary)[bits[2]])
		return float(who[k])
	var c_left: Array = []
	var f_left: Array = []
	for k in keys:
		c_left.append(snappedf(float(rd.call(carrier, k)) - float(_s._t), 0.001))
		f_left.append(snappedf(float(rd.call(frozen, k)) - float(_s._t), 0.001))
	_ok("★⑤ 携带者的 4 个到期时刻时停里 1.5 秒后都到期了(剩 %s 秒, 都须 ≤ 0)" % str(c_left),
		c_left.all(func(x): return float(x) <= 0.0), "修前: `_t` 不走 ⇒ 永远剩 1 秒")
	_ok("★⑤ 被定格者的同 4 个到期时刻一动不动(剩 %s 秒, 都须 = 1)" % str(f_left),
		f_left.all(func(x): return absf(float(x) - 1.0) < 0.001) and float(_s._t) == tnow,
		"被定格者的计时也在走 ⇒ 时停没冻住它")

	# ── 解除后: 被冻住的照常走完(冻死了也是 bug) ──
	ts._end_timestop()
	var n_w2: int = await _until(func() -> bool: return bool(w2["done"]) and bool(w3["done"]), 200)
	var n_fz: int = await _until(func() -> bool: return not bool(frozen.get("_ninja_gliding", false)), 600)
	var fz_end: float = (frozen["pos"] as Vector2).distance_to(g_fz["start"])
	_ok("★解除后: 被定格者的等待 %d 步内醒(应 ≤6)、冲刺走完 900 码(实 %.1f · 再 %d 步)" % [n_w2, fz_end, n_fz],
		bool(w2["done"]) and bool(w3["done"]) and n_w2 <= 6 and absf(fz_end - 900.0) < 0.5)

	print("")
	if _fail == 0: print("ALL PASS — 时停多段技协程 %d 条" % _n)
	else: print("FAILED: %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
