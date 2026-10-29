extends Node
## verify_reserve_minion.gd —— 终极战场援军小将(2026-10-29, docs/plans/20261029-终极战场援军小将.md)
##
## 走真入口 RefereeRunner.run 跑整局双路, 在 sim_stepped 里强制团灭, 量终极战场开场那一刻两边上了谁:
##   S1 上路双方同一步全灭 → 下路右方全灭       ⇒ 右方没人 ⇒ 右方上援军小将(原来是一只完整小龟)
##   S2 上路双灭 + 下路右先灭左后灭             ⇒ 两边都没人 ⇒ 两边各一只援军小将
##   S3 对照: 上路灭左 / 下路灭右                ⇒ 两边都有幸存 ⇒ 不出援军小将
##   S4 右方上路只剩召唤物时左方团灭 → 下路右方全灭 ⇒ 右方名单为空 ⇒ 援军小将
##   S5 右方上路只剩普通小将赢下 → 下路右方全灭  ⇒ 终极战场里那几只普通小将不许被升成精英(用户 2026-10-29)
## 援军小将本身: 名字 / 不是精英 / 无装备 / 远程 400 / 龟能 135 / 技能四面合围 / 属性 = 底子 × (1 + 4% × 这一方本周已打场数)
## 技能: 四个出发点在目标前后左右 260 码(前 = 靠施法者那侧); 一道气波 = 100% 攻击力物理 + 该敌人 10% 最大生命值魔法;
##   出手一次排出 4 道; 技能两张表(_IMPL_SKILLS / _SKILL_CAST_RANGE)都登记了。

const Backend := preload("res://scripts/net/backend.gd")
const LEVEL := 6
const N_LEFT := 5          ## 左方本周已打场数
const N_RIGHT := 9         ## 右方(对手快照)本周已打场数 —— 故意与左方不同, 量「各按各的」

var host: Node
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	host = Node.new()
	add_child(host)
	_run.call_deferred()


func _snap_a(gs) -> Dictionary:
	gs.reset_dual_lane()
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	var shop: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			shop.append(str((e as Dictionary)["id"]))
	var pe := {}
	var k := 0
	for pid in gs.season_leaders:
		pe[pid] = [{"id": str(shop[k % shop.size()]), "star": 1}]
		k += 1
	gs.persistent_equipped = pe
	gs.dual_lineup = {
		"top": [
			{"kind": "leader", "slot": 0, "id": "basic"},
			{"kind": "minion", "role": "front", "equips": []},
			{"kind": "minion", "role": "back", "equips": []},
		],
		"bottom": [
			{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []},
		],
	}
	gs.loadouts = {"basic": 1, "stone": 2}
	gs.trainer_skill = "hook"
	gs.season_level = LEVEL
	gs.season_total_battles = N_LEFT
	return Backend.build_ghost_snapshot("g_rm_a", {"name": "蓝方", "avatar": "basic", "id": "g_rm_a"})


func _job(a: Dictionary, b: Dictionary, seed: int) -> Dictionary:
	var j := {"v": 1, "job_id": 1, "match_id": "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b", "mode": "gauntlet",
		"key": {"week": 1, "account": "t"}, "seed": seed, "client_version": ReplayRecorder.client_version(),
		"level": LEVEL, "a": a, "b": b}
	return JSON.parse_string(JSON.stringify(j))


func _kill_side(bt, side: String) -> void:
	for u in bt._units.duplicate():
		if not u.get("alive", false) or u.get("_isEgg", false) or u.get("is_trainer", false):
			continue
		if str(bt._eff_side(u)) != side:
			continue
		u["hp"] = 0.0
		bt._kill(u)


func _fielded(bt) -> Array:
	var out: Array = []
	for u in bt._units:
		if u.get("alive", false) and not u.get("_isEgg", false) and not u.get("is_trainer", false) and not u.get("is_summon", false):
			out.append(u)
	return out


## 跑一场, 在终极战场开场那一刻调 on_final(bt, units); 返回是否进了终极战场。
func _scenario(a: Dictionary, b: Dictionary, plan: Dictionary, on_final: Callable) -> bool:
	var st := {"steps": 0, "lane": "", "done": {}, "captured": false}
	await RefereeRunner.run(host, _job(a, b, 2000023), func(bt) -> void:
		bt.sim_stepped.connect(func() -> void:
			var lane := str(GameState.current_lane)
			if lane != st["lane"]:
				st["lane"] = lane
				st["steps"] = 0
			if str(bt._dl_state) != "fight" and str(bt._dl_state) != "eggwindow":
				return
			st["steps"] = int(st["steps"]) + 1
			if lane == "final" and not bool(st["captured"]):
				st["captured"] = true
				on_final.call(bt, _fielded(bt))
				return
			var acts: Array = plan.get(lane, [])
			for i in range(acts.size()):
				var act: Array = acts[i]
				var key := "%s#%d" % [lane, i]
				if st["done"].has(key) or int(st["steps"]) < int(act[0]):
					continue
				st["done"][key] = true
				if act.size() > 2 and str(act[2]) == "kill_right_leaders":
					for uu in bt._units.duplicate():
						if uu.get("alive", false) and str(uu.get("side")) == "right" and not uu.get("_isMinion", false) and not uu.get("_isEgg", false) and not uu.get("is_trainer", false) and not uu.get("is_summon", false):
							uu["hp"] = 0.0
							bt._kill(uu)
				if act.size() > 2 and str(act[2]) == "summon_right":
					var owner: Dictionary = {}
					for uu in bt._units:
						if uu.get("alive", false) and str(uu.get("side")) == "right" and not uu.get("_isEgg", false) and not uu.get("is_trainer", false) and not uu.get("is_summon", false):
							owner = uu
							break
					bt._spawn._spawn_summon(owner, "skeleton", 5000.0, 1.0, {"label": "亡灵骷髅", "spr_id": "skeleton", "col_size": 32.0, "hp_w": 22.0, "no_move": true, "no_basic": true})
					for uu in bt._units.duplicate():
						if uu.get("alive", false) and str(uu.get("side")) == "right" and not uu.get("_isEgg", false) and not uu.get("is_trainer", false) and not uu.get("is_summon", false):
							uu["hp"] = 0.0
							bt._kill(uu)
				for side in act[1]:
					_kill_side(bt, side)
		)
	)
	return bool(st["captured"])


func _side(units: Array, side: String) -> Array:
	return units.filter(func(u): return str(u.get("side")) == side)


func _is_reserve(u: Dictionary) -> bool:
	return u.get("_isMinion", false) and str(u.get("minion_role", "")) == "reserve"


## 援军小将本身的各项(n = 这一方本周已打场数)。
func _check_reserve(tag: String, u: Dictionary, n: int) -> void:
	var m := 1.0 + 0.04 * float(n)
	_ok(tag + " 名字「援军小将」", str(u.get("name")) == ReserveConsts.NAME, str(u.get("name")))
	_ok(tag + " 不是精英", not bool(u.get("is_elite", false)))
	_ok(tag + " ★属性 = 底子 ×(1 + 4% × %d 场)" % n,
		absf(float(u["maxHp"]) - 1000.0 * m) < 0.01 and absf(float(u["atk"]) - 50.0 * m) < 0.01
		and absf(float(u["def"]) - 15.0 * m) < 0.01 and absf(float(u["mr"]) - 15.0 * m) < 0.01,
		"hp %.1f atk %.2f def %.2f mr %.2f" % [float(u["maxHp"]), float(u["atk"]), float(u["def"]), float(u["mr"])])
	_ok(tag + " 远程普攻 400", not bool(u.get("melee", true)) and absf(float(u.get("atk_range", 0.0)) - 400.0) < 0.01,
		"melee=%s range=%s" % [str(u.get("melee")), str(u.get("atk_range"))])
	_ok(tag + " 技能四面合围 · 龟能 135", (u.get("active_skills", []) as Array) == [ReserveConsts.SKILL]
		and absf(float((u.get("energy_cost", {}) as Dictionary).get(ReserveConsts.SKILL, -1.0)) - 135.0) < 0.001,
		"%s %s" % [str(u.get("active_skills")), str(u.get("energy_cost"))])
	_ok(tag + " 没有装备", (u.get("equips", []) as Array).is_empty(), str(u.get("equips")))


func _run() -> void:
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		_ok("GameState 在", false)
		get_tree().quit(1)
		return
	gs.test_mode = true
	gs.tutorial_active = false
	print("=== 终极战场援军小将 ===")
	var a := _snap_a(gs)
	var b: Dictionary = a.duplicate(true)
	b["profile"] = {"name": "紫方", "avatar": "stone", "id": "g_rm_b"}
	b["ghost_id"] = "g_rm_b"
	b["season_total_battles"] = N_RIGHT

	## S1
	var got := {}
	var ok1 := await _scenario(a, b, {"top": [[30, ["left", "right"]]], "bottom": [[30, ["right"]]]}, func(bt, units: Array) -> void:
		var r := _side(units, "right")
		got["r"] = r
		got["l"] = _side(units, "left")
		## 技能(在真对局里现场量)
		if r.size() == 1 and _is_reserve(r[0]):
			var rv: Dictionary = r[0]
			var tgt: Dictionary = {}
			for u in got["l"]:
				if u.get("_isMinion", false):
					tgt = u
					break
			if tgt.is_empty() and not (got["l"] as Array).is_empty():
				tgt = got["l"][0]
			if not tgt.is_empty():
				var pts: Array = bt._reserve_sys.spawn_points(rv, tgt)
				var tp: Vector2 = tgt["pos"]
				var dists: Array = pts.map(func(p): return snappedf(DetMath.vlen((p as Vector2) - tp), 0.01))
				got["pts_n"] = pts.size()
				got["pts_r_ok"] = dists.all(func(d): return absf(float(d) - ReserveConsts.WAVE_RADIUS) < 0.05)
				var dc: float = DetMath.vlen((rv["pos"] as Vector2) - tp)
				got["front_ok"] = DetMath.vlen((rv["pos"] as Vector2) - (pts[0] as Vector2)) < dc and DetMath.vlen((rv["pos"] as Vector2) - (pts[1] as Vector2)) > dc
				## 一道气波的伤害: 期望值按同一套公式算(暴击 0 ⇒ 无随机)
				var hp0: float = float(tgt["hp"]) + float(tgt.get("shield", 0.0))
				var phys_exp: float = float(rv["atk"]) * DamageMath.resist_multiplier(DamageMath.effective_resist(float(tgt["def"]), 0.0, 0.0)) * DamageMath.dr_mult(float(tgt.get("damage_reduction", 0.0)))
				var mag_exp: float = float(tgt["maxHp"]) * 0.10 * DamageMath.resist_multiplier(DamageMath.effective_resist(float(tgt["mr"]), 0.0, 0.0)) * DamageMath.dr_mult(float(tgt.get("damage_reduction", 0.0)))
				bt._reserve_sys.wave_hit(rv, tgt)
				var drop: float = hp0 - (float(tgt["hp"]) + float(tgt.get("shield", 0.0)))
				got["dmg"] = [drop, round(phys_exp) + round(mag_exp), float(tgt["maxHp"])]
				var before: int = bt._pending_shots.size()
				bt._reserve_sys.cast(rv, tgt)
				got["queued"] = bt._pending_shots.size() - before
			var cm: Dictionary = bt.get_script().get_script_constant_map()
			got["tables"] = (cm.get("_IMPL_SKILLS", {}) as Dictionary).has(ReserveConsts.SKILL) and (cm.get("_SKILL_CAST_RANGE", {}) as Dictionary).has(ReserveConsts.SKILL)
	)
	_ok("S1 进了终极战场", ok1)
	var r1: Array = got.get("r", [])
	_ok("S1 ★右方没人 ⇒ 上的是援军小将(不是小龟)", r1.size() == 1 and _is_reserve(r1[0]), str(r1.map(func(u): return str(u.get("name")))))
	if r1.size() == 1 and _is_reserve(r1[0]):
		_check_reserve("S1 右方", r1[0], N_RIGHT)
	_ok("S1 左方有幸存 ⇒ 不出援军小将", not (got.get("l", []) as Array).any(func(u): return _is_reserve(u)))
	_ok("S1 场上没有兜底小龟", not (got.get("r", []) as Array).any(func(u): return str(u.get("id")) == "basic"))
	_ok("技能 ★四个出发点, 都在目标 260 码外", int(got.get("pts_n", 0)) == 4 and bool(got.get("pts_r_ok", false)))
	_ok("技能 「前」那道在靠施法者一侧, 「后」那道在背后", bool(got.get("front_ok", false)))
	var dm: Array = got.get("dmg", [0, -1, 0])
	_ok("技能 ★一道 = 100% 攻击力物理 + 该敌人 10% 最大生命值魔法", absf(float(dm[0]) - float(dm[1])) <= 1.0, "实掉 %.0f 期望 %.0f (目标最大生命 %.0f)" % [float(dm[0]), float(dm[1]), float(dm[2])])
	_ok("技能 出手一次排出 4 道气波(+1 解除定身)", int(got.get("queued", 0)) == ReserveConsts.WAVES + 1, str(got.get("queued")))
	_ok("技能 两张表(_IMPL_SKILLS / _SKILL_CAST_RANGE)都登记了", bool(got.get("tables", false)))

	## S2
	got = {}
	var ok2 := await _scenario(a, b, {"top": [[30, ["left", "right"]]], "bottom": [[30, ["right"]], [90, ["left"]]]}, func(_bt, units: Array) -> void:
		got["r"] = _side(units, "right")
		got["l"] = _side(units, "left"))
	_ok("S2 进了终极战场", ok2)
	var l2: Array = got.get("l", [])
	var r2: Array = got.get("r", [])
	_ok("S2 ★两边都没人 ⇒ 两边各一只援军小将", l2.size() == 1 and r2.size() == 1 and _is_reserve(l2[0]) and _is_reserve(r2[0]))
	if l2.size() == 1 and _is_reserve(l2[0]):
		_check_reserve("S2 左方", l2[0], N_LEFT)
	if r2.size() == 1 and _is_reserve(r2[0]):
		_ok("S2 右方按对手自己的场数(%d)" % N_RIGHT, absf(float(r2[0]["maxHp"]) - 1000.0 * (1.0 + 0.04 * N_RIGHT)) < 0.01, "%.1f" % float(r2[0]["maxHp"]))
	_ok("S2 左方援军小将不带背包装备(原来兜底小龟会带)", l2.size() == 1 and (l2[0].get("equips", []) as Array).is_empty())

	## S3 对照
	got = {}
	var ok3 := await _scenario(a, b, {"top": [[30, ["left"]]], "bottom": [[30, ["right"]]]}, func(_bt, units: Array) -> void:
		got["all"] = units)
	_ok("S3 进了终极战场", ok3)
	_ok("S3 ★分母: 两边都有幸存 ⇒ 不出援军小将", not (got.get("all", []) as Array).is_empty() and not (got.get("all", []) as Array).any(func(u): return _is_reserve(u)))

	## S4
	got = {}
	var ok4 := await _scenario(a, b, {"top": [[30, ["left"], "summon_right"]], "bottom": [[30, ["right"]]]}, func(_bt, units: Array) -> void:
		got["r"] = _side(units, "right"))
	_ok("S4 进了终极战场", ok4)
	var r4: Array = got.get("r", [])
	_ok("S4 只剩召唤物赢下一路 ⇒ 右方上援军小将", r4.size() == 1 and _is_reserve(r4[0]))

	## S5
	got = {}
	var ok5 := await _scenario(a, b, {"top": [[20, [], "kill_right_leaders"], [30, ["left"]]], "bottom": [[30, ["right"]]]}, func(_bt, units: Array) -> void:
		got["r"] = _side(units, "right"))
	_ok("S5 进了终极战场", ok5)
	var r5: Array = got.get("r", [])
	_ok("S5 分母: 右方带着普通小将进终极战场", r5.size() >= 1 and r5.all(func(u): return u.get("_isMinion", false)), str(r5.size()))
	_ok("S5 ★只剩普通小将那一方不被升成精英", not r5.is_empty() and not r5.any(func(u): return bool(u.get("is_elite", false))),
		str(r5.map(func(u): return "%s elite=%s hp=%.0f" % [str(u.get("minion_role")), str(u.get("is_elite")), float(u["maxHp"])])))

	print("=== 共 %d 条, 失败 %d ===" % [_n, _fail])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)
