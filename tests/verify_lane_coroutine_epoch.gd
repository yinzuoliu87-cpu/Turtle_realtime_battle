extends Node
## verify_lane_coroutine_epoch.gd — 多段技协程不许活过换路(换路纪元 lane_epoch)
##
## ══════════════════════════════════════════════════════════════════════
##  由来(2026-10-04)
## ══════════════════════════════════════════════════════════════════════
## tween 捕获台账那一轮的探针: 上一路末尾放出的千刃风暴, 换路后在**下一路**接着打
## `_enemies_of(u)` —— 新路敌人吃了 136 伤害(不带千刃风暴 = 0)。原因: 协程只看 `u.alive`,
## 而换路时旧单位字典从不被标死。同形状的还有饮血连斩(每刀重新挑 `_pick_enemies_of`)、
## 大熊蓄力(蓄完往 `_units` 里召一只大熊 = 上一路的召唤物落进下一路)、大熊冲击波
## (波前挂在装备延时表里, 扫的也是 `_enemies_of(src)`)。
##
## 修法: `DualLaneFlow.lane_step()` —— 全部跨 sim 步的挂起点都经过它, 醒来发现纪元变了就停住;
## 外加 `EquipTickSystem.reset_for_lane()` 把装备延时表里上一路的在途项丢掉。
##
## ★判据量【结果】: 上一路那几个携带者换路之后**一点伤害都没再打出来**(`_st_dealt` 增量),
##   下一路的敌人**一滴血都没掉**, 下一路场上**没有**上一路召出的大熊。
## ★每一条都配分母: 换路那一刻这些协程/波**真的在途**(停在闸上的协程数 / 冲击波表 / 蓄力标记),
##   否则 0 伤害是空检查。
## ★下一路只摆一颗蛋给我方「占位」(蛋不出手) ⇒ 下一路敌人掉的每一滴血都只可能来自上一路。
## ★全程手推 sim(`_sim_step`), 与机器快慢无关。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0
var _s = null
var _gs = null


class ErrTap extends Logger:
	var err := 0
	var probe := 0
	var first := ""
	var mx := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		mx.lock()
		if code.contains("ERRTAP_PROBE_LANEEP") or rationale.contains("ERRTAP_PROBE_LANEEP"):
			probe += 1
		elif error_type != Logger.ERROR_TYPE_WARNING:
			err += 1
			if first == "":
				first = (code + " | " + rationale).substr(0, 160)
		mx.unlock()


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
	_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	_gs.test_mode = true
	print("=== 换路纪元: 上一路的多段技协程不许在下一路接着结算 ===")
	await _t_source()   # 本体里只有字符串提到 await, 审计器按字面判成协程; 加 await 无害
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s.set_process(false)
	await _t_switch()
	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 换路后上一路的协程一条都没再结算" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ──────────────────────────── 工具 ────────────────────────────

func _mk(id: String, side: String, off: Vector2, extra: Dictionary = {}) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + off, extra)
	u["maxHp"] = 1.0e8
	u["hp"] = 1.0e8
	_s._units.append(u)
	return u


func _steps(n: int) -> void:
	for _i in range(n):
		_s._sim_step(_s.SIM_DT, false, false)
		await get_tree().process_frame


func _sim_waiters() -> int:
	return _s.get_signal_connection_list("sim_stepped").size()


# ──────────────── ⓪ 源码: 跨 sim 步的挂起点全部经过闸 ────────────────
## 新写一条 `await battle.sim_stepped` 就绕过了纪元闸 ⇒ 当场红。唯一允许的是闸自己那一行。
func _t_source() -> void:
	print("--- ⓪ 源码: 直接 await sim_stepped 的只许是 lane_step 自己 ---")
	var re := RegEx.create_from_string("await[ ]+(battle[.])?sim_stepped")
	var hits: Array = []
	var files := 0
	var stack: Array = ["res://scripts"]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		for sub in da.get_directories():
			stack.append(d + "/" + sub)
		for f in da.get_files():
			if not f.ends_with(".gd"):
				continue
			files += 1
			var lines: PackedStringArray = FileAccess.get_file_as_string(d + "/" + f).split("\n")
			for i in range(lines.size()):
				var code: String = lines[i].split("#")[0]
				if re.search(code) != null:
					hits.append("%s:%d" % [f, i + 1])
	_ok("★分母: 扫到的脚本数 %d" % files, files >= 100)
	_ok("直接 await sim_stepped 的恰好 1 处且就在 dual_lane_flow.lane_step", hits.size() == 1 and str(hits[0]).begins_with("dual_lane_flow.gd:"),
		str(hits))
	var main_src := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var wi: int = main_src.find("func _wait_sim(")
	var wbody: String = main_src.substr(wi, 1400)
	_ok("_wait_sim 的挂起点走 lane_step(新协程写 _wait_sim 就自动受保护)", wi >= 0 and wbody.contains("await _dl_sys.lane_step()"))


# ──────────────── ① 换路: 六条多段技在途时走真入口 _dl_clear_units ────────────────
func _t_switch() -> void:
	print("--- ① 换路(真入口 _dl_clear_units): 多段技在途时清场 ---")
	_s._units.clear()
	_s._pending_shots.clear()
	_s._over = false
	var sw: Dictionary = _mk("basic", "left", Vector2(-420, -160))     # 千刃风暴
	var bc: Dictionary = _mk("basic", "left", Vector2(-420, 160))      # 饮血连斩(★3: 8 刀 × 0.3 秒)
	var bb: Dictionary = _mk("basic", "left", Vector2(-420, 0))        # 大熊蓄力 → 召大熊
	var bw1: Dictionary = _mk("basic", "left", Vector2(-300, -60))     # 大熊冲击波(换路时波前在飞)
	var bw2: Dictionary = _mk("basic", "left", Vector2(-300, 60))      # 大熊冲击波(换路时还在举手)
	var nj: Dictionary = _mk("ninja", "left", Vector2(-200, 240))      # 忍者冲刺滑行
	var lv: Dictionary = _mk("lava", "left", Vector2(-200, -240))      # 火山跃升砸地(tween.finished 那一族)
	var carriers: Array = [sw, bc, bb, bw1, bw2, nj, lv]
	var names: Array = ["千刃风暴", "饮血连斩", "大熊蓄力", "冲击波·在飞", "冲击波·举手", "忍者滑行", "火山砸地"]
	var foe_a: Dictionary = _mk("basic", "right", Vector2(160, 0))
	var foe_b: Dictionary = _mk("basic", "right", Vector2(200, 120))
	for u in carriers:
		u["no_basic"] = true   # 只量协程打出的伤害, 不让携带者自己普攻
	for f in [foe_a, foe_b]:
		f["no_basic"] = true
		f["no_move"] = true
	var base_wait: int = _sim_waiters()
	var tap := ErrTap.new()
	OS.add_logger(tap)
	push_warning("ERRTAP_PROBE_LANEEP 门禁自检: 证明 Logger 接得到引擎输出(警告, 不是报错)")

	_s._equip_sys._eq_sword_storm(sw, 1)
	_s._equip_sys._blood_sys._eq_blood_combo(bc, 2)
	_s._big_bear_charge_and_spawn(bb, 0)
	_s._bear_shockwave(bw1, foe_a, 0)
	await _steps(20)
	_s._bear_shockwave(bw2, foe_b, 0)
	await _steps(10)
	_s._ninja_sys._ninja_glide(nj, nj["pos"], nj["pos"] + Vector2(300, 0), Vector2.RIGHT, foe_a,
		[{"o": foe_a, "proj": 250.0, "done": false}])
	_s._lava_sys._lava_volcano_slam(lv)
	await _steps(10)   # 换路这一刻: 风暴还没出剑阵 / 连斩砍到第 3 刀 / 大熊蓄力中 / 一条波在飞一条在举手 / 忍者起手 / 火山在空中

	## ── 分母: 换路那一刻它们真的都在途 ──
	var in_flight: int = _sim_waiters() - base_wait
	_ok("★分母: 换路那一刻有 %d 条协程挂在 sim 步上(风暴/连斩/斩痕/蓄力/举手/忍者)" % in_flight, in_flight >= 6)
	_ok("★分母: 连斩已经砍出去了(%d 伤害)、还没砍完(8 刀要 2.4 秒, 现在 0.67 秒)" % int(bc.get("_st_dealt", 0)),
		int(bc.get("_st_dealt", 0)) > 0)
	_ok("★分母: 有一条冲击波正在飞(装备延时表里 %d 条)" % _s._equip_tick_sys._bear_waves.size(),
		_s._equip_tick_sys._bear_waves.size() == 1)
	_ok("★分母: 忍者在滑行中、火山在空中(砸地还没落)", bool(nj.get("_ninja_gliding", false)) and bool(lv.get("_slam", false)))
	var bears0 := 0
	for u in _s._units:
		if u.get("is_big_bear", false):
			bears0 += 1
	_ok("★分母: 大熊还没召出来(蓄力 1.2 秒, 现在 0.67 秒)", bears0 == 0)

	var dealt0: Array = []
	for u in carriers:
		dealt0.append(int(u.get("_st_dealt", 0)))
	var ep0: int = _s._dl_sys.lane_epoch
	## 赛博机甲桥接: 上一路赛博在收官前一刻阵亡 ⇒ 此侧「仍算存活」到 _t+3。
	##   ★直接写字段而不调 `_cyber_assemble_mech`: 后者会排激光/机甲演出与延时项, 污染本测试「换路后一滴血没掉」那几条分母。
	##   写法与 cyber_system 那唯一一处写入同形(按阵营 = _t + 3.0)。
	_s._mech_incoming["left"] = float(_s._t) + 3.0
	var mech0: float = float(_s._mech_incoming.get("left", 0.0))
	_ok("★分母: 换路前赛博桥接时刻在未来(%.2f > _t %.2f)" % [mech0, float(_s._t)], mech0 > float(_s._t))

	## ── 换路(真入口) ──
	_s._dl_sys._dl_clear_units()
	_ok("赛博「机甲组装中仍算存活」的按阵营到期时刻换路清空(否则下一路开场最多 3 秒判不了团灭)",
		_s._mech_incoming.is_empty(), str(_s._mech_incoming))
	_ok("换路纪元 +1(%d → %d)" % [ep0, _s._dl_sys.lane_epoch], _s._dl_sys.lane_epoch == ep0 + 1)
	_ok("装备延时表清空(冲击波 %d 条 / 延时项 %d 条)" % [_s._equip_tick_sys._bear_waves.size(), _s._equip_tick_sys._bolt_q.size()],
		_s._equip_tick_sys._bear_waves.is_empty() and _s._equip_tick_sys._bolt_q.is_empty())

	## 下一路: 我方只摆一颗蛋(不出手), 敌方两只站桩、满血、不普攻
	_mk("__egg__", "left", Vector2(-600, 0), {"egg": true, "egg_side": "left", "hp": 1.0e8, "hp_max": 1.0e8})
	var nf1: Dictionary = _mk("basic", "right", Vector2(-120, 0))
	var nf2: Dictionary = _mk("basic", "right", Vector2(0, 140))
	var nf3: Dictionary = _mk("basic", "right", Vector2(-260, 200))
	for f in [nf1, nf2, nf3]:
		f["no_basic"] = true
		f["no_move"] = true
	_s._over = false
	var nj_pos0: Vector2 = nj["pos"]
	var lv_h0: float = float(lv.get("height", 0.0))

	await _steps(1)
	var parked: int = _s._dl_sys.parked_count()
	_ok("★分母: 换路后第一步, 停在闸上的协程 %d 条 == 换路时在途的 %d 条" % [parked, in_flight], parked == in_flight and parked >= 6)
	await _steps(int(6.0 / _s.SIM_DT))   # 6 秒: 足够让所有没停住的协程跑完全程

	## ── 判据 ──
	var leaked := 0
	for i in range(carriers.size()):
		var d: int = int(carriers[i].get("_st_dealt", 0)) - int(dealt0[i])
		leaked += d
		_ok("[%s] 换路后再没打出任何伤害" % names[i], d == 0, "多打了 %d" % d)
	var nf_lost: float = 0.0
	for f in [nf1, nf2, nf3]:
		nf_lost += 1.0e8 - float(f["hp"])
	_ok("下一路敌人一滴血没掉", nf_lost == 0.0, "掉了 %.0f" % nf_lost)
	var bears := 0
	for u in _s._units:
		if u.get("is_big_bear", false):
			bears += 1
	_ok("下一路场上没有上一路召出的大熊", bears == 0, "%d 只" % bears)
	_ok("忍者那条协程停住了(旧字典的位置不再被推: %s → %s)" % [str(nj_pos0), str(nj["pos"])], (nj["pos"] as Vector2).is_equal_approx(nj_pos0))
	_ok("火山那条协程作废了(tween 被 kill, 永不 finished: 高度 %.2f 不动, 砸地没落)" % lv_h0,
		is_equal_approx(float(lv.get("height", 0.0)), lv_h0) and bool(lv.get("_slam", false)))
	_ok("闸上的协程不随时间增长(6 秒后仍是 %d 条)" % _s._dl_sys.parked_count(), _s._dl_sys.parked_count() == parked)

	OS.remove_logger(tap)
	_ok("★分母: Logger 真的接得到引擎输出(自检 %d 条)" % tap.probe, tap.probe >= 1)
	_ok("★引擎 0 条报错(脚本报错等)", tap.err == 0, "%d 条 · 首条: %s" % [tap.err, tap.first])
