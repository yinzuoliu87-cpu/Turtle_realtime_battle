extends Node
## verify_foe_season_level —— 双方各用各自的赛季等级(用户 2026-10-19「赛季等级」)。
##
## 改之前: 快照不带 `season_level`, 战斗里右方(对手快照)的单位等级 / 小将等级 / 蛋血一律吃**左方**(打的人)的等级
##   ⇒ 同一份阵容碰到高等级的人就跟着变强。现在快照带等级, 右方按快照自己的打; 旧快照(没这个键)退回老口径。
##
## 段落(全走真战斗场: 真 `_dl_build_lane_field` 建场, 量引擎里的单位字典):
##   ① 生产: `build_ghost_snapshot` 带 season_level = 我的等级; `make_bot` = `bot_level_for_battles(场次)`;
##      陪练 `seed_as_human` = 种子文件里那一支真实的等级(文件里有就照抄)
##   ② ★同一阵容, 右方快照 season_level = 1 与 = 10: 右方统领等级 / 生命 / 攻击、小将生命、右蛋血都不同,
##      而且正好是各自等级的公式值; 左方(等级 5)两次逐位相同
##   ③ ★旧快照(没 season_level): 右方 = 左方等级(老口径), 打 600 步后的全场指纹与「快照 season_level = 左方等级」逐步相同
##   ④ 越界值不信: season_level = 99 ⇒ 夹到 MAX_LEVEL
## ★分母: 每一遍都量到了右方统领 ≥ 2 只、右方小将 ≥ 1 只、两颗蛋; ③ 比过的步数 = 600。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BE := preload("res://scripts/net/backend.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const DLF := preload("res://scripts/scenes/battle/dual_lane_flow.gd")
const LEFT_LV := 5
const STEPS := 600

var _fail := 0
var _n := 0
var _gs


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


## 对手快照: 一个固定的机器人(三统领 + 小将), 再按需改它的 season_level。
func _foe(lv) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	var g: Dictionary = BE.make_bot(12, rng)
	## 装备摘掉: 装备的固定加值不随等级缩放, 留着就量不出「生命比 = 等级乘数比」。
	g["equipped"] = {}
	for lk in ["top", "bottom"]:
		for m in (g.get("minions", {}) as Dictionary).get(lk, []):
			(m as Dictionary).erase("equips")
	if lv == null:
		g.erase("season_level")
	else:
		g["season_level"] = lv
	return g


func _setup(foe: Dictionary) -> void:
	_gs.reset_dual_lane()
	_gs.test_mode = true
	_gs.tutorial_active = false
	_gs.debug_level = 0
	_gs.week_phase = "ranked"
	_gs.season_level = LEFT_LV
	_gs.candy_temp_levels = {}
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.persistent_equipped = {}
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	_gs.dual_ghost = foe.duplicate(true)
	_gs.dual_active = true


## 跑一遍: 建场 → 第一路开打那一步量单位; 再往后打 `steps` 步, 每步记指纹。
func _run(foe: Dictionary, steps: int) -> Dictionary:
	_setup(foe)
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	var guard := 0
	while str(s._dl_state) != "fight" and guard < 3000:
		s._process(s.SIM_DT)
		guard += 1
		if guard % 20 == 0:
			await get_tree().process_frame
	var out := {"state": str(s._dl_state), "L": {}, "R": {}, "Lm": [], "Rm": [], "egg": {}, "egg_hp": {}, "fps": []}
	for u in s._units:
		var side := str(u.get("side", ""))
		if bool(u.get("_isEgg", false)):
			out["egg"][side] = float(u.get("maxHp", 0.0))
			continue
		if bool(u.get("is_trainer", false)) or bool(u.get("_isSummon", false)):
			continue
		var row := [int(u.get("level", 0)), float(u.get("maxHp", 0.0)), float(u.get("atk", 0.0)), float(u.get("def", 0.0))]
		if bool(u.get("_isMinion", false)):
			(out["Lm" if side == "left" else "Rm"] as Array).append(row)
		else:
			(out["L" if side == "left" else "R"] as Dictionary)[str(u.get("id", ""))] = row
	out["egg_hp"] = (_gs.egg_hp as Dictionary).duplicate()
	out["unit_lv_r"] = int(s._unit_level("right"))
	for _k in range(steps):
		s._process(s.SIM_DT)
		(out["fps"] as Array).append(ReplayRecorder.fingerprint(s))
		if _k % 20 == 0:
			await get_tree().process_frame
	s.queue_free()
	await get_tree().process_frame
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_ok("分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	OS.set_environment("TURTLE_SEED", "4242")      # det 模式: 每次 _process 恰 1 步, 同种子可逐步比
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")

	# ── ① 生产 ──
	print("=== ① 快照带赛季等级 ===")
	_setup(_foe(null))
	_gs.season_level = 7
	var snap: Dictionary = BE.build_ghost_snapshot("g_lv_test", {"name": "x", "avatar": "basic", "id": "g_lv_test"})
	_ok("★① 真人快照带 season_level = 我的等级(7)", int(snap.get("season_level", -1)) == 7, str(snap.get("season_level", "缺")))
	var bad_bot := []
	for n in [0, 1, 3, 9, 12, 20, 30]:
		var r := RandomNumberGenerator.new()
		r.seed = 100 + n
		var b: Dictionary = BE.make_bot(n, r)
		if int(b.get("season_level", -1)) != P2.bot_level_for_battles(n):
			bad_bot.append("%d→%s" % [n, str(b.get("season_level", "缺"))])
	_ok("★① 机器人快照 season_level = bot_level_for_battles(场次)(7 个场次)", bad_bot.is_empty(), str(bad_bot))
	var raw := {"ghost_id": "seed_x_b10", "leaders": ["basic", "stone", "bamboo"], "season_total_battles": 10, "season_level": 7,
		"lane_assign": {"top": ["basic"], "bottom": ["stone", "bamboo"]}, "minions": {"top": [{"role": "front"}, {"role": "back"}], "bottom": [{"role": "back"}]}}
	var raw0 := raw.duplicate(true)
	raw0.erase("season_level")
	_ok("★① 陪练入池: 文件里的等级照抄(7); 缺 ⇒ 按场次(%d)" % P2.bot_level_for_battles(10),
		int(BE.seed_as_human(raw, 1).get("season_level", -1)) == 7
		and int(BE.seed_as_human(raw0, 1).get("season_level", -1)) == P2.bot_level_for_battles(10))
	_ok("④ 越界不信: 99 ⇒ %d / 0 ⇒ 缺 / 字符串 ⇒ 缺" % P2.MAX_LEVEL, BE.ghost_level({"season_level": 99}) == P2.MAX_LEVEL
		and BE.ghost_level({"season_level": 0}) == -1 and BE.ghost_level({"season_level": "9"}) == -1)

	# ── ② 右方 1 级 vs 10 级 ──
	print("=== ② 同一阵容, 右方快照等级 1 vs 10(左方 %d) ===" % LEFT_LV)
	var a1: Dictionary = await _run(_foe(1), 1)
	var a10: Dictionary = await _run(_foe(10), 1)
	for pair in [["1", a1], ["10", a10]]:
		var o: Dictionary = pair[1]
		_ok("分母(右方 %s 级): 开打了、右方统领 %d 只 ≥ 2、右方小将 %d 只 ≥ 1、两颗蛋" % [str(pair[0]), (o["R"] as Dictionary).size(), (o["Rm"] as Array).size()],
			str(o["state"]) == "fight" and (o["R"] as Dictionary).size() >= 2 and (o["Rm"] as Array).size() >= 1
			and (o["egg"] as Dictionary).has("left") and (o["egg"] as Dictionary).has("right"), str(o["state"]))
	var lv_ok := true
	var hp_ratio_ok := true
	var detail := []
	var m1: float = UnitScaling.level_multiplier(1)
	var m10: float = UnitScaling.level_multiplier(10)
	for id in (a1["R"] as Dictionary):
		var r1: Array = a1["R"][id]
		var r10: Array = (a10["R"] as Dictionary).get(id, [])
		if r10.is_empty() or int(r1[0]) != 1 or int(r10[0]) != 10:
			lv_ok = false
		elif absf(float(r10[1]) / float(r1[1]) - m10 / m1) > 1e-6 or float(r10[2]) <= float(r1[2]):
			hp_ratio_ok = false
		detail.append("%s Lv%s/%s 血 %.0f/%.0f" % [id, str(r1[0]), str(r10[0]) if not r10.is_empty() else "?", float(r1[1]), float(r10[1]) if not r10.is_empty() else 0.0])
	_ok("★★② 右方统领等级 = 快照里的等级(1 / 10), 不是左方的 %d" % LEFT_LV, lv_ok, "; ".join(detail))
	_ok("★★② 右方统领生命比 = 等级乘数比(%.3f)、攻击更高" % (m10 / m1), hp_ratio_ok)
	var rm1: Array = a1["Rm"][0]
	var rm10: Array = a10["Rm"][0]
	_ok("★② 右方小将等级 / 生命跟着快照走(Lv%d %.0f → Lv%d %.0f)" % [int(rm1[0]), float(rm1[1]), int(rm10[0]), float(rm10[1])],
		int(rm1[0]) == 1 and int(rm10[0]) == 10 and float(rm10[1]) > float(rm1[1]))
	_ok("★② 右蛋满血按右方等级(%.0f / %.0f)、开局蛋血同值" % [float(a1["egg"]["right"]), float(a10["egg"]["right"])],
		is_equal_approx(float(a1["egg"]["right"]), DLF.egg_max_for(1)) and is_equal_approx(float(a10["egg"]["right"]), DLF.egg_max_for(10))
		and is_equal_approx(float(a1["egg_hp"]["right"]), DLF.egg_max_for(1)) and is_equal_approx(float(a10["egg_hp"]["right"]), DLF.egg_max_for(10)))
	_ok("★② 左方(等级 %d)两遍逐位相同: 统领 / 小将 / 左蛋" % LEFT_LV,
		var_to_bytes(a1["L"]) == var_to_bytes(a10["L"]) and var_to_bytes(a1["Lm"]) == var_to_bytes(a10["Lm"])
		and float(a1["egg"]["left"]) == float(a10["egg"]["left"]) and is_equal_approx(float(a1["egg"]["left"]), DLF.egg_max_for(LEFT_LV)))
	_ok("② 左方统领等级 = %d(读 GameState)" % LEFT_LV, int((a1["L"] as Dictionary).values()[0][0]) == LEFT_LV)

	# ── ③ 旧快照 ──
	print("=== ③ 旧快照(没 season_level) ≡ 右方与左方同级(老口径) ===")
	var old: Dictionary = await _run(_foe(null), STEPS)
	var same: Dictionary = await _run(_foe(LEFT_LV), STEPS)
	_ok("★③ 旧快照: 右方等级退回左方的 %d(_unit_level / 统领 / 小将 / 蛋)" % LEFT_LV,
		int(old["unit_lv_r"]) == LEFT_LV and int((old["R"] as Dictionary).values()[0][0]) == LEFT_LV
		and int(old["Rm"][0][0]) == LEFT_LV and is_equal_approx(float(old["egg"]["right"]), DLF.egg_max_for(LEFT_LV)),
		"unit_lv_r=%d" % int(old["unit_lv_r"]))
	var f0: Array = old["fps"]
	var f1: Array = same["fps"]
	var first_diff := -1
	for k in range(mini(f0.size(), f1.size())):
		if str(f0[k]) != str(f1[k]):
			first_diff = k
			break
	_ok("分母 ③: 两遍各比了 %d 步" % f0.size(), f0.size() == STEPS and f1.size() == STEPS)
	_ok("★★③ 旧快照与「快照等级 = 左方等级」逐步指纹相同(%d 步)" % STEPS, first_diff < 0 and f0.size() == f1.size(), "第一处不同: %d" % first_diff)
	_finish()


func _finish() -> void:
	print("  (共 %d 条断言)" % _n)
	if _fail == 0 and _n > 0:
		print("ALL PASS — 双方各用各自的赛季等级")
	get_tree().quit(1 if _fail > 0 else 0)
