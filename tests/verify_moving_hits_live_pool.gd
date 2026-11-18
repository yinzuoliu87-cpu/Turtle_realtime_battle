extends Node
## verify_moving_hits_live_pool.gd — 会走 / 会扩散的攻击「谁能被打」每步现读(2026-11-18)
##
## 用户 11-18:「海浪滑行的时候，这个龟蛋罩子破了，它不会对龟蛋造成伤害吗？」→ 查实不会:
##   043 浪墙放出那一刻把敌人名单拍成快照(围栏没破的蛋不在里面), 浪走的约 5 秒里对面团灭、蛋罩破了也不加进去。
##   用户「那肯定要啊」⇒ 同类全仓扫: 拍快照的还有 096 炽天使斧回旋镖(出手时拍下身前名单)、
##   枪羁绊第二座炮台星浪(蓄力时拍下名单 + 按释放那一刻的距离排好到达时刻 + 名单本身含围栏没破的蛋 / 护盾分给自己的蛋)。
##   (034 大熊冲击波 / 024 喷火龙 / 029 冰道 / 石头龟岩脊 本来就每步现读 `_enemies_of`, 不在此列。)
##
## 每节都是 A/B: 同一个场面, 一次中途改状态(蛋罩破 / 走进身前 / 走远), 一次不改 —— 只差那一下。
## ★证明会红: 把三处任一处改回快照 ⇒ 对应那节红(提交前逐处变异过, 见提交说明)。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_moving_hits_live_pool.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const DT := 1.0 / 60.0

var _s
var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _center() -> Vector2:
	return _s.ARENA.position + _s.ARENA.size * 0.5


func _mk(side: String, off: Vector2, hp: float = 100000.0) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, _center() + off)
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["crit"] = 0.0
	u["def"] = 0.0
	u["base_def"] = 0.0
	u["mr"] = 0.0
	u["base_mr"] = 0.0
	u["flat_dr"] = 0.0
	u["damage_reduction"] = 0.0
	u["dodge_bonus"] = 0.0
	u["equips"] = []
	u["eq_state"] = {}
	_s._units.append(u)
	return u


## 合成的蛋: 只带选靶 / 名单看的两个记号(`_isEgg` 均分护盾排它, `_egg_fence` 围栏没破 = 谁都打不到)。
func _mk_egg(side: String, off: Vector2) -> Dictionary:
	var u := _mk(side, off)
	u["id"] = "__egg_probe__"
	u["_isEgg"] = true
	u["_egg_fence"] = true
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	print("=== 会走的攻击: 名单每步现读 ===")
	_t_tide(true)
	_t_tide(false)
	_t_boom(true)
	_t_boom(false)
	_t_turret_two()
	print("")
	if _fail == 0:
		print("ALL PASS — 会走的攻击名单每步现读 (%d 条)" % _n)
	else:
		print("FAILED: %d / %d" % [_fail, _n])
	get_tree().quit(0 if _fail == 0 else 1)


# ── ① 043 海浪护符: 浪走到一半蛋罩破了 ⇒ 浪前沿碰到蛋就算 ─────────────────────────
func _t_tide(drop_mid: bool) -> void:
	_s._units.clear()
	_s._equip_tick_sys.reset_for_lane()
	var c := _mk("left", Vector2(-700, 0))
	c["equips"] = [{"id": "p2eq_043", "star": 3}]
	var foe := _mk("right", Vector2(-200, 0))       # 定浪的朝向(朝右)
	var egg := _mk_egg("right", Vector2(600, 0))
	_s._equip_sys._eq_water_wave(c, 2)
	var th: Array = _s._equip_tick_sys._tide_hits
	_ok("★分母(%s): 登记了 1 道浪" % ("中途破罩" if drop_mid else "罩一直在"), th.size() == 1)
	if th.size() != 1:
		return
	var h: Dictionary = th[0]
	var fwd_egg: float = DetMath.dot((egg["pos"] as Vector2) - (h["start"] as Vector2), h["dir"] as Vector2)
	var h0: float = float(egg["hp"])
	var f0: float = float(foe["hp"])
	## 推到浪前沿离蛋还有 150 码(还没碰到)
	var steps := 0
	while steps < 4000:
		var t: float = float(h["t"])
		var trav: float = minf(1.0, (t - float(h["windup"])) / maxf(0.001, float(h["travel"]))) * float(h["dist"])
		if t >= float(h["windup"]) and trav >= fwd_egg - 150.0:
			break
		_s._equip_tick_sys._tick_tide_hits(DT)
		steps += 1
	_ok("★分母: 浪已经扫过前面的敌人(掉了 %.0f)、还没到蛋(蛋 %.0f → %.0f)" % [f0 - float(foe["hp"]), h0, float(egg["hp"])],
		float(foe["hp"]) < f0 and absf(float(egg["hp"]) - h0) < 0.5)
	if drop_mid:
		egg["_egg_fence"] = false                    # 浪走到一半: 对面团灭、蛋罩破了
	var n := 0
	while not _s._equip_tick_sys._tide_hits.is_empty() and n < 4000:
		_s._equip_tick_sys._tick_tide_hits(DT)
		n += 1
	if drop_mid:
		_ok("★★★① 浪走到一半蛋罩破了 ⇒ 浪前沿碰到蛋时照打(蛋 %.0f → %.0f)" % [h0, float(egg["hp"])], float(egg["hp"]) < h0)
	else:
		_ok("① 对照: 蛋罩一直在 ⇒ 浪扫过去也不伤蛋(蛋 %.0f → %.0f)" % [h0, float(egg["hp"])], absf(float(egg["hp"]) - h0) < 0.5)


# ── ② 096 炽天使斧回旋镖: 出手后才走进身前的敌人也挨打 ─────────────────────────────
func _t_boom(walk_in: bool) -> void:
	var fin = _s._equip_sys._axe._fin
	_s._units.clear()
	fin._booms.clear()
	var ax := _mk("left", Vector2(0, 0))
	ax["_eq_axe"] = true
	ax["_axe_pv"] = 4
	ax["_axe_final"] = "seraph"
	ax["id"] = "__axe_probe__"
	ax["atk"] = 100.0
	var far := _mk("right", Vector2(500, 0))          # 身前的敌人(定飞多远)
	var walker := _mk("right", Vector2(-300, 0))      # 出手时在身后
	var rec: Dictionary = fin.seraph_boomerang_launch(ax, Vector2.RIGHT)
	_ok("★分母(%s): 甩出了 1 把回旋镖" % ("出手后走进身前" if walk_in else "一直在身后"), not rec.is_empty())
	if rec.is_empty():
		return
	var w0: float = float(walker["hp"])
	if walk_in:
		walker["pos"] = (ax["pos"] as Vector2) + Vector2(250, 0)   # 出手后走到镖的路线上
	var n := 0
	while not fin._booms.is_empty() and n < 2000:
		fin.tick_boomerangs(DT)
		n += 1
	_ok("★分母: 身前那只照样挨打(掉 %.0f)" % (100000.0 - float(far["hp"])), float(far["hp"]) < 100000.0)
	if walk_in:
		_ok("★★★② 出手时在身后、之后走进路线 ⇒ 镖扫到就打(%.0f → %.0f)" % [w0, float(walker["hp"])], float(walker["hp"]) < w0)
	else:
		_ok("② 对照: 一直在出手点身后 ⇒ 不挨打(单向名单不变, %.0f → %.0f)" % [w0, float(walker["hp"])], absf(float(walker["hp"]) - w0) < 0.5)


# ── ③ 枪羁绊第二座炮台星浪: 蛋的两条名单规矩 + 环形扩散每步碰当前位置 ───────────────
func _guns(n: int) -> Array:
	var out: Array = []
	for e in DataRegistry.phase2_equipment:
		var id := str((e as Dictionary).get("id", ""))
		if _s.Phase2Types.type_of(id) == "枪":
			out.append({"id": id, "star": 1})
		if out.size() >= n:
			break
	return out


func _setup_guns(units: Array) -> void:
	_s._units.clear()
	_s._units.append_array(units)
	_s._synergy._by_side = {"left": {}, "right": {}}
	_s._synergy.apply_all()
	_s._gun_syn.apply_all()
	_s._gun_syn.clear()
	_s._equip_tick_sys.reset_for_lane()


func _step(sec: float) -> void:
	for _i in range(int(ceil(sec / 0.02))):
		_s._ballistics._step_pending_shots(0.02)
		_s._equip_tick_sys._tick_rings(0.02)


func _t_turret_two() -> void:
	var G := _guns(6)
	_ok("★分母: 找到 6 件枪(第二座炮台要 6 件)", G.size() == 6, str(G.size()))
	if G.size() < 6:
		return
	_s._units.clear()
	var c1 := _mk("left", Vector2(-300, -100))
	c1["equips"] = G.slice(0, 3)
	var c2 := _mk("left", Vector2(-300, 100))
	c2["equips"] = G.slice(3, 6)
	var ally := _mk("left", Vector2(-250, 0))
	var my_egg := _mk_egg("left", Vector2(-500, 0))
	var foe := _mk("right", Vector2(300, 0))
	var foe_egg := _mk_egg("right", Vector2(600, 0))
	var units: Array = [c1, c2, ally, my_egg, foe, foe_egg]
	_setup_guns(units)
	var org: Vector2 = _s._gun_syn._turret_pos("left", 1)
	## ③a 转护盾: 均摊名单不含自己的蛋
	_s._gun_syn._t2_shield_phase["left"] = true
	_s._gun_syn._t2_acc = 0.0
	_s._gun_syn.tick(5.1)
	var n_share: int = int((_s._gun_syn._t2_last.get("left", {}) as Dictionary).get("n", -1))
	_step(SynergyVfx.CHARGE_SEC + 3000.0 / SynergyVfx.WAVE_SPEED)
	_ok("★★③a 转护盾: 均摊的人头 = 3(两个带枪的 + 友军, 不含自己的蛋; 用户 08-01「分摊不应该包括龟蛋」)", n_share == 3, "n=%d" % n_share)
	_ok("③a 友军拿到盾 %.0f、自己的蛋 %.0f" % [float(ally["shield"]), float(my_egg["shield"])],
		float(ally["shield"]) > 0.0 and absf(float(my_egg["shield"])) < 0.01)
	## ③b 化弹幕: 围栏没破的蛋不挨(「单体 + AoE 都不锁」)
	_setup_guns(units)
	_s._gun_syn._t2_shield_phase["left"] = false
	_s._gun_syn._t2_acc = 0.0
	var f0: float = float(foe["hp"])
	var e0: float = float(foe_egg["hp"])
	_s._gun_syn.tick(5.1)
	_step(SynergyVfx.CHARGE_SEC + 3000.0 / SynergyVfx.WAVE_SPEED)
	_ok("★★③b 化弹幕: 敌人掉 %.0f、围栏没破的蛋不掉(%.0f → %.0f)" % [f0 - float(foe["hp"]), e0, float(foe_egg["hp"])],
		float(foe["hp"]) < f0 and absf(float(foe_egg["hp"]) - e0) < 0.5)
	## ③c 星浪走到一半蛋罩破了 ⇒ 波扫到就打
	_setup_guns(units)
	foe_egg["pos"] = org + Vector2(1500, 0)
	_s._gun_syn._t2_shield_phase["left"] = false
	_s._gun_syn._t2_acc = 0.0
	var e1: float = float(foe_egg["hp"])
	_s._gun_syn.tick(5.1)
	_step(SynergyVfx.CHARGE_SEC + 800.0 / SynergyVfx.WAVE_SPEED)   # 环走到 ~800 码, 离蛋还远
	_ok("★分母: 环还没到蛋那儿(%.0f → %.0f)" % [e1, float(foe_egg["hp"])], absf(float(foe_egg["hp"]) - e1) < 0.5)
	foe_egg["_egg_fence"] = false
	_step(1200.0 / SynergyVfx.WAVE_SPEED)
	_ok("★★★③c 星浪走到一半蛋罩破了 ⇒ 环扫到蛋就打(%.0f → %.0f)" % [e1, float(foe_egg["hp"])], float(foe_egg["hp"]) < e1)
	## ③d 释放后走远的: 环扫到它【现在】的位置才挨(原来按释放那一刻的距离排时刻 ⇒ 走开了照样挨)
	foe_egg["_egg_fence"] = true
	_setup_guns(units)
	foe["pos"] = org + Vector2(100, 0)
	_s._gun_syn._t2_shield_phase["left"] = false
	_s._gun_syn._t2_acc = 0.0
	_s._gun_syn.tick(5.1)
	_step(SynergyVfx.CHARGE_SEC)                    # 刚释放
	var rings: Array = _s._equip_tick_sys._rings
	_ok("★分母: 释放后登记了 1 道星浪环", rings.size() == 1, str(rings.size()))
	if rings.size() != 1:
		return
	var ring: Dictionary = rings[0]
	foe["pos"] = org + Vector2(1500, 0)             # 立刻走远
	## ★量「这道环打没打到它」(环的 hit 名单), 不量血: 同一拍第一座炮台的激光也会打它, 血量分不出是谁打的
	_step(500.0 / SynergyVfx.WAVE_SPEED)            # 环到 ~500 码: 释放那一刻它在 100 码处, 旧写法这时早挨了
	var hit_mid: bool = _s._arr_has_unit(ring["hit"], foe)
	_step(1200.0 / SynergyVfx.WAVE_SPEED)
	var hit_end: bool = _s._arr_has_unit(ring["hit"], foe)
	_ok("★★★③d 释放后走到 1500 码: 环走到 500 码时还没碰到它(%s), 环到它那儿才碰到(%s)" % [str(hit_mid), str(hit_end)],
		not hit_mid and hit_end)
