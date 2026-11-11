extends Node
## verify_reserve_minion.gd —— 终极战场援军小将(2026-10-29, docs/plans/20261029-终极战场援军小将.md)
##
## 走真入口 RefereeRunner.run 跑整局双路, 在 sim_stepped 里强制团灭, 量终极战场开场那一刻两边上了谁:
##   S1 上路双方同一步全灭 → 下路右方全灭       ⇒ 右方没人 ⇒ 右方只有援军小将(原来是一只完整小龟); 左方 = 幸存 + 1 只援军
##   S2 上路双灭 + 下路右先灭左后灭             ⇒ 两边都没人 ⇒ 两边各只有一只援军小将
##   S3 两边都有幸存(上路灭左 / 下路灭右)       ⇒ ★两边仍各上一只援军小将(用户 2026-11-11「始终在终极战场登场」)
##   S4 右方上路只剩召唤物时左方团灭 → 下路右方全灭 ⇒ 右方名单为空 ⇒ 援军小将
##   S5 右方上路只剩普通小将赢下 → 下路右方全灭  ⇒ 终极战场里那几只普通小将不许被升成精英(用户 2026-10-29)
## 援军小将本身: 名字 / 不是精英 / 远程 400 / 龟能 135 / 技能四面合围 / 属性 = 底子 × (1 + 4% × 这一方本周已打场数)
## ★随身装备(2026-11-11, 方案书 docs/plans/20261111b-援军小将始终登场并带背包装备.md):
##   带且只带 1 件, = ReserveConsts.pick_equip(这一方 reserve_pool, 对局种子, 阵营); 左方 = A 快照的 reserve_pool(裁判任务),
##   右方 = 对手快照(dual_ghost)的 reserve_pool; 池子空 ⇒ 不带。P 段量纯函数(同种子同件 / 换种子能抽到不同件 / 空池)。
##   Q 段: 快照的 reserve_pool = 背包里的装备(无效 id 丢掉, 穿着的不算); R 段: 录制器刷新可抽清单的位置(源码顺序)。
## 技能: 四个出发点在目标前后左右 260 码(前 = 靠施法者那侧); 一道气波 = 100% 攻击力物理 + 该敌人 10% 最大生命值魔法;
##   出手一次排出 4 道; 技能两张表(_IMPL_SKILLS / _SKILL_CAST_RANGE)都登记了。

const Backend := preload("res://scripts/net/backend.gd")
const ES := preload("res://scripts/gamedata/equip_stats.gd")
const LEVEL := 6
const N_LEFT := 5          ## 左方本周已打场数
const N_RIGHT := 9         ## 右方(对手快照)本周已打场数 —— 故意与左方不同, 量「各按各的」
## 左方背包里没穿的装备(纯属性 / 受击类, 不在开场召唤东西, 不扰乱各场景的强制团灭)
const POOL_A := [{"id": "p2eq_047", "star": 2}, {"id": "p2eq_044", "star": 1}, {"id": "p2eq_014", "star": 3}]
## 右方(对手快照)的可抽清单: 故意与左方不同, 量「右方读对手自己的」
const POOL_B := [{"id": "p2eq_016", "star": 2}]

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
	## 背包(未穿戴): 三件不同星级 + 一个数据表里没有的 id(快照里必须丢掉)
	gs.persistent_bench = POOL_A.duplicate(true) + [{"id": "p2eq_999", "star": 1}]
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


## 援军小将本身的各项(n = 这一方本周已打场数; pool / seed / side = 期望的随身装备从哪来)。
func _check_reserve(tag: String, u: Dictionary, n: int, pool: Array, seed: int, side: String) -> void:
	var m := 1.0 + 0.04 * float(n)
	_ok(tag + " 名字「援军小将」", str(u.get("name")) == ReserveConsts.NAME, str(u.get("name")))
	_ok(tag + " 不是精英", not bool(u.get("is_elite", false)))
	## 期望 = 底子 × 成长 + 所带那件装备的基础属性(终极战场第一步还没挨打 ⇒ 014 硬化 0 层); 047 重击锤再加 maxHp × 比例
	var es: Dictionary = {}
	var ueq: Array = u.get("equips", [])
	if ueq.size() == 1:
		var rows = ES.STATS.get(str(ueq[0].get("id")), [])
		var st: int = clampi(int(ueq[0].get("star", 1)), 1, 3)
		if rows is Array and (rows as Array).size() >= st:
			es = rows[st - 1]
	var hp_x: float = 1000.0 * m + float(es.get("hp", 0.0))
	var atk_x: float = 50.0 * m + float(es.get("atk", 0.0)) + hp_x * float(u.get("hammer_pct", 0.0))
	var def_x: float = 15.0 * m + float(es.get("def", 0.0))
	var mr_x: float = 15.0 * m + float(es.get("mr", 0.0))
	_ok(tag + " ★属性 = 底子 ×(1 + 4%% × %d 场) + 所带装备 %s" % [n, str(ueq)],
		absf(float(u["maxHp"]) - hp_x) < 0.01 and absf(float(u["atk"]) - atk_x) < 0.01
		and absf(float(u["def"]) - def_x) < 0.01 and absf(float(u["mr"]) - mr_x) < 0.01,
		"hp %.1f/%.1f atk %.2f/%.2f def %.2f/%.2f mr %.2f/%.2f" % [float(u["maxHp"]), hp_x, float(u["atk"]), atk_x, float(u["def"]), def_x, float(u["mr"]), mr_x])
	_ok(tag + " 远程普攻 400", not bool(u.get("melee", true)) and absf(float(u.get("atk_range", 0.0)) - 400.0) < 0.01,
		"melee=%s range=%s" % [str(u.get("melee")), str(u.get("atk_range"))])
	_ok(tag + " 技能四面合围 · 龟能 135", (u.get("active_skills", []) as Array) == [ReserveConsts.SKILL]
		and absf(float((u.get("energy_cost", {}) as Dictionary).get(ReserveConsts.SKILL, -1.0)) - 135.0) < 0.001,
		"%s %s" % [str(u.get("active_skills")), str(u.get("energy_cost"))])
	var want: Array = ReserveConsts.pick_equip(pool, seed, side)
	var eqs: Array = u.get("equips", [])
	_ok(tag + " ★随身装备带且只带 1 件, 来自这一方的可抽清单(星级照背包)",
		eqs.size() == 1 and want.size() == 1 and str(eqs[0].get("id")) == str(want[0]["id"]) and int(eqs[0].get("star", 0)) == int(want[0]["star"])
		and pool.any(func(it): return str(it["id"]) == str(eqs[0].get("id")) and int(it["star"]) == int(eqs[0].get("star", 0))),
		"带 %s / 应 %s" % [str(eqs), str(want)])


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
	b["reserve_pool"] = POOL_B.duplicate(true)

	## S1
	var got := {}
	var ok1 := await _scenario(a, b, {"top": [[30, ["left", "right"]]], "bottom": [[30, ["right"]]]}, func(bt, units: Array) -> void:
		var r := _side(units, "right")
		got["r"] = r
		got["l"] = _side(units, "left")
		got["seed"] = int(bt._battle_rng.seed)
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
				## 追踪: 从目标右边 150 码发一道, 目标每步横着跑 4 码(直飞必然打空: 停 10 步 + 飞 14 步 = 横移 96 码 > 半宽 55)。
				##   量援军小将造成的魔法伤害(只有气波会打魔法段)有没有涨 —— 只认这一道。
				var dbt: Dictionary = rv.get("_st_dealt_by_type", {})
				var mag0: int = int(dbt.get("mag", 0))
				bt._reserve_sys.fly_wave(rv, tgt, (tgt["pos"] as Vector2) + Vector2(150.0, 0.0))
				for _k in range(60 + roundi(ReserveConsts.WAVE_HOLD / bt._ballistics.SKILLSHOT_STEP)):
					tgt["pos"] = (tgt["pos"] as Vector2) + Vector2(0.0, 4.0)
					bt._ballistics._step_pending_shots(bt._ballistics.SKILLSHOT_STEP)
				got["homing"] = int((rv.get("_st_dealt_by_type", {}) as Dictionary).get("mag", 0)) > mag0
				## 原地停: 目标就贴在出发点上(10 码), 停的那几步不许打中; 停满才出发、第一步就打中
				var hold_n: int = roundi(ReserveConsts.WAVE_HOLD / bt._ballistics.SKILLSHOT_STEP)
				var mag1: int = int((rv.get("_st_dealt_by_type", {}) as Dictionary).get("mag", 0))
				bt._reserve_sys.fly_wave(rv, tgt, (tgt["pos"] as Vector2) + Vector2(10.0, 0.0))
				var hit_step := -1
				for _k in range(hold_n + 6):
					bt._ballistics._step_pending_shots(0.0 if _k == 0 else bt._ballistics.SKILLSHOT_STEP)
					if hit_step < 0 and int((rv.get("_st_dealt_by_type", {}) as Dictionary).get("mag", 0)) > mag1:
						hit_step = _k
				got["hold"] = [hit_step, hold_n]
				## 补查: 敌人在气波这一步起点后面 5 码(迎面走来、从两步之间跨过去的那种) —— 不开补查打不到, 开了打得到
				var p0: Vector2 = (tgt["pos"] as Vector2) + Vector2(5.0, 0.0)
				got["catch_off"] = bt._ballistics._first_on_segment(rv, p0, Vector2.RIGHT, 19.0, ReserveConsts.WAVE_HALF_W, 0.0)
				got["catch_on"] = bt._ballistics._first_on_segment(rv, p0, Vector2.RIGHT, 19.0, ReserveConsts.WAVE_HALF_W, ReserveConsts.WAVE_CATCHUP)
				got["catch_tgt"] = tgt
				var before: int = bt._pending_shots.size()
				bt._reserve_sys.cast(rv, tgt)
				got["queued"] = bt._pending_shots.size() - before
			var cm: Dictionary = bt.get_script().get_script_constant_map()
			got["tables"] = (cm.get("_IMPL_SKILLS", {}) as Dictionary).has(ReserveConsts.SKILL) and (cm.get("_SKILL_CAST_RANGE", {}) as Dictionary).has(ReserveConsts.SKILL)
	)
	_ok("S1 进了终极战场", ok1)
	var r1: Array = got.get("r", [])
	var sd1: int = int(got.get("seed", 0))
	_ok("S1 分母: 对局种子拿到了", sd1 != 0, str(sd1))
	_ok("S1 ★右方没人 ⇒ 只有援军小将(不是小龟)", r1.size() == 1 and _is_reserve(r1[0]), str(r1.map(func(u): return str(u.get("name")))))
	if r1.size() == 1 and _is_reserve(r1[0]):
		_check_reserve("S1 右方", r1[0], N_RIGHT, POOL_B, sd1, "right")
	var l1: Array = got.get("l", [])
	var l1_res: Array = l1.filter(func(u): return _is_reserve(u))
	_ok("S1 ★左方有幸存 ⇒ 幸存照上, 另加一只援军小将(用户 11-11「始终登场」)",
		l1_res.size() == 1 and l1.size() >= 2, "左方 %d 个, 援军 %d 只" % [l1.size(), l1_res.size()])
	if l1_res.size() == 1:
		_check_reserve("S1 左方", l1_res[0], N_LEFT, POOL_A, sd1, "left")
	_ok("S1 场上没有兜底小龟", not (got.get("r", []) as Array).any(func(u): return str(u.get("id")) == "basic"))
	_ok("技能 ★四个出发点, 都在目标 %.0f 码外" % ReserveConsts.WAVE_RADIUS, int(got.get("pts_n", 0)) == 4 and bool(got.get("pts_r_ok", false)))
	_ok("技能 「前」那道在靠施法者一侧, 「后」那道在背后", bool(got.get("front_ok", false)))
	var dm: Array = got.get("dmg", [0, -1, 0])
	_ok("技能 ★一道 = 100% 攻击力物理 + 该敌人 10% 最大生命值魔法", absf(float(dm[0]) - float(dm[1])) <= 1.0, "实掉 %.0f 期望 %.0f (目标最大生命 %.0f)" % [float(dm[0]), float(dm[1]), float(dm[2])])
	_ok("技能 出手一次排出 4 道气波(+1 解除定身)", int(got.get("queued", 0)) == ReserveConsts.WAVES + 1, str(got.get("queued")))
	_ok("技能 两张表(_IMPL_SKILLS / _SKILL_CAST_RANGE)都登记了", bool(got.get("tables", false)))
	_ok("技能 ★气波追踪: 目标横着跑开也追得上(直飞会打空)", bool(got.get("homing", false)))
	var hd: Array = got.get("hold", [-1, -1])
	_ok("技能 ★气波出现后原地停 %.1f 秒(停的时候贴脸也不打), 停满第一步就打中" % ReserveConsts.WAVE_HOLD,
		int(hd[1]) > 0 and int(hd[0]) == int(hd[1]), "第 %d 步打中 / 应停 %d 步" % [int(hd[0]), int(hd[1])])
	_ok("技能 ★迎面走来的敌人不会从两步之间穿过去(补查)", got.get("catch_off") == null and got.get("catch_on") != null and is_same(got.get("catch_on"), got.get("catch_tgt")),
		"不补查=%s 补查=%s" % [str(got.get("catch_off") != null), str(got.get("catch_on") != null)])

	## S2
	got = {}
	var ok2 := await _scenario(a, b, {"top": [[30, ["left", "right"]]], "bottom": [[30, ["right"]], [90, ["left"]]]}, func(_bt, units: Array) -> void:
		got["r"] = _side(units, "right")
		got["l"] = _side(units, "left")
		got["seed"] = int(_bt._battle_rng.seed))
	_ok("S2 进了终极战场", ok2)
	var l2: Array = got.get("l", [])
	var r2: Array = got.get("r", [])
	_ok("S2 ★两边都没人 ⇒ 两边各一只援军小将", l2.size() == 1 and r2.size() == 1 and _is_reserve(l2[0]) and _is_reserve(r2[0]))
	if l2.size() == 1 and _is_reserve(l2[0]):
		_check_reserve("S2 左方", l2[0], N_LEFT, POOL_A, int(got.get("seed", 0)), "left")
	if r2.size() == 1 and _is_reserve(r2[0]):
		_ok("S2 右方按对手自己的场数(%d)" % N_RIGHT, absf(float(r2[0]["maxHp"]) - 1000.0 * (1.0 + 0.04 * N_RIGHT)) < 0.01, "%.1f" % float(r2[0]["maxHp"]))
	_ok("S2 左方援军小将不带统领的持久装备(原来兜底小龟会带), 只带背包里抽的那一件",
		l2.size() == 1 and (l2[0].get("equips", []) as Array).size() == 1
		and not (gs.persistent_equipped as Dictionary).values().any(func(arr): return (arr as Array).any(func(it): return str(it.get("id")) == str((l2[0]["equips"] as Array)[0].get("id")))))

	## S3 对照
	got = {}
	var ok3 := await _scenario(a, b, {"top": [[30, ["left"]]], "bottom": [[30, ["right"]]]}, func(_bt, units: Array) -> void:
		got["all"] = units)
	_ok("S3 进了终极战场", ok3)
	var all3: Array = got.get("all", [])
	var l3: Array = _side(all3, "left")
	var r3: Array = _side(all3, "right")
	_ok("S3 分母: 两边都有幸存", l3.any(func(u): return not _is_reserve(u)) and r3.any(func(u): return not _is_reserve(u)),
		"左 %d 右 %d" % [l3.size(), r3.size()])
	_ok("S3 ★两边都有幸存 ⇒ 仍各上一只援军小将(用户 11-11「始终在终极战场登场」)",
		l3.filter(func(u): return _is_reserve(u)).size() == 1 and r3.filter(func(u): return _is_reserve(u)).size() == 1)

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
	var r5n: Array = r5.filter(func(u): return not _is_reserve(u))
	_ok("S5 分母: 右方带着普通小将进终极战场(援军以外)", r5n.size() >= 1 and r5n.all(func(u): return u.get("_isMinion", false)), str(r5n.size()))
	_ok("S5 ★只剩普通小将那一方不被升成精英", not r5.is_empty() and not r5.any(func(u): return bool(u.get("is_elite", false))),
		str(r5.map(func(u): return "%s elite=%s hp=%.0f" % [str(u.get("minion_role")), str(u.get("is_elite")), float(u["maxHp"])])))

	_pure_checks(a, b)

	print("=== 共 %d 条, 失败 %d ===" % [_n, _fail])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)


## P / Q / R: 抽取的纯函数、快照里的可抽清单、录制器刷新的位置
func _pure_checks(a: Dictionary, b: Dictionary) -> void:
	print("--- P 抽一件(纯函数) ---")
	var pool5 := [{"id": "e1", "star": 1}, {"id": "e2", "star": 2}, {"id": "e3", "star": 3}, {"id": "e4", "star": 1}, {"id": "e5", "star": 2}]
	_ok("P 空池 ⇒ 不带", ReserveConsts.pick_equip([], 12345, "left").is_empty())
	var same := true
	var seen := {}
	var lr_diff := 0
	for sd in range(1, 61):
		var p1: Array = ReserveConsts.pick_equip(pool5, sd * 7919, "left")
		var p2: Array = ReserveConsts.pick_equip(pool5, sd * 7919, "left")
		if p1 != p2 or p1.size() != 1:
			same = false
		if p1.size() == 1:
			seen[str(p1[0]["id"])] = true
		if ReserveConsts.pick_equip(pool5, sd * 7919, "right") != p1:
			lr_diff += 1
	_ok("P ★同种子同阵营 ⇒ 同一件, 每次恰 1 件(60 个种子)", same)
	_ok("P ★60 个种子抽到 ≥ 3 种不同的件(不是恒取第一件)", seen.size() >= 3, str(seen.keys()))
	_ok("P 左右两方各抽各的(同种子下有不同的时候)", lr_diff > 0, "不同 %d / 60" % lr_diff)
	var big: Array = []
	for i in range(ReserveConsts.POOL_CAP + 15):
		big.append({"id": "x%d" % i, "star": 9})
	var cp: Array = ReserveConsts.clean_pool(big + ["bad", {"star": 2}])
	_ok("P 清洗: 上限 %d 件 / 星级夹到 1~3 / 丢掉没有 id 的" % ReserveConsts.POOL_CAP,
		cp.size() == ReserveConsts.POOL_CAP and cp.all(func(it): return int(it["star"]) == 3 and str(it["id"]) != ""), str(cp.size()))

	print("--- Q 快照里的可抽清单 ---")
	var qa: Array = a.get("reserve_pool", [])
	_ok("Q ★快照 reserve_pool = 背包里的装备(数据表里没有的 p2eq_999 丢掉)", qa == POOL_A, str(qa))
	var worn: Array = []
	for arr in (GameState.persistent_equipped as Dictionary).values():
		for it in (arr as Array):
			worn.append(str(it.get("id")))
	_ok("Q 分母: 统领身上穿着 %d 件" % worn.size(), worn.size() >= 1)
	_ok("Q 穿在身上的不进可抽清单", not qa.any(func(it): return worn.has(str(it["id"])) and not POOL_A.any(func(pa): return str(pa["id"]) == str(it["id"]))))
	_ok("Q 对手快照用对手自己那份(本测试的右方)", (b.get("reserve_pool", []) as Array) == POOL_B)
	var bot: Dictionary = Backend.make_bot(9, _rng_of(4242))
	_ok("Q 机器人快照也带 reserve_pool(不带 = 一眼认得出), 1~2 件", (bot.get("reserve_pool", []) as Array).size() in [1, 2], str(bot.get("reserve_pool")))
	var dv: Array = Backend.derived_reserve_pool("g_seed_x")
	_ok("Q ★快照缺 reserve_pool 键(陪练种子 / 机器人) ⇒ 按 ghost_id 派生 1~2 件, 与陪练转换同一个函数",
		dv.size() in [1, 2] and Backend.reserve_pool_of({"ghost_id": "g_seed_x"}) == dv, str(dv))
	_ok("Q 有键但是空数组(真人背包里没有没穿的) ⇒ 空, 不派生", Backend.reserve_pool_of({"ghost_id": "g_seed_x", "reserve_pool": []}).is_empty())
	var bot_pool: Array = ReserveConsts.clean_pool(bot.get("reserve_pool", []))   # JSON 往返后星级是 float, 清洗成 int 再比
	_ok("Q 机器人 = 按自己的 ghost_id 派生", bot_pool == Backend.derived_reserve_pool(str(bot.get("ghost_id", ""))),
		"%s / %s" % [str(bot_pool), str(Backend.derived_reserve_pool(str(bot.get("ghost_id", ""))))])

	print("--- R 录制器: 实打开局从背包刷新, 回放 / 观赛 / 裁判 / 补打不刷新 ---")
	var src := FileAccess.get_file_as_string("res://scripts/systems/replay/replay_recorder.gd").replace("\r\n", "\n")   # 行尾 CRLF / LF 都按 LF 比
	var i_ref := src.find("_start_referee()\n\t\treturn")
	var i_res := src.find("_start_resume()\n\t\treturn")
	var i_set := src.find("GameState.reserve_pool = GameState.reserve_candidates()")
	var i_rec := src.find("\tif should_record():")
	_ok("R 分母: 四处都找到了", i_ref > 0 and i_res > 0 and i_set > 0 and i_rec > 0, "%d %d %d %d" % [i_ref, i_res, i_set, i_rec])
	_ok("R ★刷新在裁判 / 补打 return 之后、开始录制之前(录像里就是这一份)", i_ref < i_set and i_res < i_set and i_set < i_rec)
	_ok("R STATE_KEYS 有 reserve_pool、没有 persistent_bench", ReplayRecorder.STATE_KEYS.has("reserve_pool") and not ReplayRecorder.STATE_KEYS.has("persistent_bench"))


func _rng_of(sd: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = sd
	return r
