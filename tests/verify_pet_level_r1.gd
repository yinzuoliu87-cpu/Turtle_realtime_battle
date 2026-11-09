extends Node
## verify_pet_level_r1.gd —— 按龟等级（R1）+ 裁判把关「拥有 ∪ 限免」+ 等级表的来路。
## 方案书 20261105c §4.2（快照加 lv 表；_unit_level 三个调用点按龟取；龟蛋血量按三只平均；赛季等级只留装备格数 / 小将；
##   没有 lv 表的旧快照退回整队等级）、20261107b §4、20261107 §4.9；接口契约 §4。
##
## 段落（战斗全走真战斗场 `_dl_build_lane_field` 建场，量引擎里的单位字典）：
##   ① 生产：build_ghost_snapshot 本机有等级表 ⇒ 带 lv（三只统领各自的）、没有 ⇒ 不带；make_bot 30 个 ⇒ 统领都在
##      它自己那一组限免里、lv 全 1；陪练 seed_as_human lv 全 1
##   ② ★同一局两侧不同等级：左 {basic 1, stone 2, bamboo 9}（赛季 5）、右 {三只 2 / 7 / 10}（赛季 3）：
##      每只统领的等级 = 表里它自己的、生命 = 同一只在整队等级那一遍的生命 ÷ 整队乘数 × 它的乘数；小将等级不动（5 / 3）；
##      龟蛋满血 = 三只平均（左 4、右 6，不是 5 / 3）；_unit_level / _lvl_mult_for（统领、召唤物按主人、小将走整队）
##   ③ ★旧快照（两侧都没有 lv 表）⇒ 统领 / 小将 / 蛋全按整队等级（左 5 右 3），逐位同改之前的公式
##   ④ ★裁判：validate 三只统领都在「拥有 ∪ 限免」才收；不在 ⇒ a_bad_snapshot / b_bad_snapshot；拥有补进来就收；没账号（机器人池）不查；
##      ★本周已上场过（key.a_kept / b_kept，迁移 20261109e）⇒ 卖掉了也收（统领一周锁死，周中失去不该整周被拒）；只放过 kept 里的那只；
##      state_for 左方等级表 = A 快照的 lv（没有 ⇒ 空）
##   ⑤ 显示：GameState.battle_level_for 统领按龟等级 + 临时等级器、小将("")按赛季等级、调试强制等级压过一切
##   ⑥ 录像：STATE_KEYS 有 pet_lv；没有 pet_lv 的旧录像 ⇒ 清空看的人的表
##   ⑦ 曲线：TurtleLevel 与迁移 20261109b 同一条（70 / 160 / 1350、阈值两侧）
##   ⑧ 客户端：PetLevelsNet 回包 ⇒ 28 只全表（拥有的按服务器等级、其余 1）；没登录不过滤；陪练号选龟补到 3 只都能上场

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BE := preload("res://scripts/net/backend.gd")
const DLF := preload("res://scripts/scenes/battle/dual_lane_flow.gd")
const LEFT_LV := 5
const RIGHT_LV := 3
const LTAB := {"basic": 1, "stone": 2, "bamboo": 9}      # 平均 4
const RLVS := [2, 7, 10]                                   # 平均 19/3 ⇒ 6
const WEEK := 1762732800
const ACCT_A := "11111111-2222-4333-8444-555555555555"
const ACCT_B := "99999999-8888-4777-8666-555555555555"

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


## 对手: 固定机器人(装备摘掉: 装备固定加值不随等级缩放, 留着量不出「生命比 = 乘数比」)。lv_tab = null ⇒ 不带 lv 表。
func _foe(lv_tab, all_top: bool = false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261109
	var g: Dictionary = BE.make_bot(12, rng)
	g["equipped"] = {}
	for lk in ["top", "bottom"]:
		for m in (g.get("minions", {}) as Dictionary).get(lk, []):
			(m as Dictionary).erase("equips")
	g["season_level"] = RIGHT_LV
	if all_top:     # 三只统领都在上路(第一路开打那一步就量得到三只)
		g["lane_assign"] = {"top": (g["leaders"] as Array).duplicate(), "bottom": []}
		g["minions"] = {"top": [], "bottom": [{"role": "front", "elite": true}, {"role": "back", "elite": false}, {"role": "back", "elite": false}]}
		g.erase("leader_off")
	g.erase("lv")
	if lv_tab != null:
		g["lv"] = lv_tab
	return g


func _setup(foe: Dictionary, ltab: Dictionary, all_top: bool = false) -> void:
	_gs.reset_dual_lane()
	_gs.test_mode = true
	_gs.tutorial_active = false
	_gs.debug_level = 0
	_gs.week_phase = "ranked"
	_gs.season_level = LEFT_LV
	_gs.candy_temp_levels = {}
	_gs.pet_lv = ltab.duplicate()
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
	if all_top:
		_gs.dual_lineup = {
			"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
				{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
				{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []}],
			"bottom": [{"kind": "minion", "role": "front", "equips": []}, {"kind": "minion", "role": "back", "equips": []},
				{"kind": "minion", "role": "back", "equips": []}],
		}
	_gs.dual_ghost = foe.duplicate(true)
	_gs.dual_active = true


## 建场 → 第一路开打那一步量单位(另把 _unit_level / _lvl_mult_for 的读数一起带回)。
func _run(foe: Dictionary, ltab: Dictionary, all_top: bool = false) -> Dictionary:
	_setup(foe, ltab, all_top)
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
	var out := {"state": str(s._dl_state), "L": {}, "R": {}, "Lm": [], "Rm": [], "egg": {}, "egg_hp": {}, "ul": {}, "mult": {}}
	var stone_u = null
	var a_minion = {"_isMinion": true, "side": "left", "id": "__minion__"}   # 三只都在上路时上路没有小将: 用一个小将形状的单位量整队乘数
	for u in s._units:
		var side := str(u.get("side", ""))
		if bool(u.get("_isEgg", false)):
			out["egg"][side] = float(u.get("maxHp", 0.0))
			continue
		if bool(u.get("is_trainer", false)) or bool(u.get("is_summon", false)):
			continue
		var row := [int(u.get("level", 0)), float(u.get("maxHp", 0.0)), float(u.get("atk", 0.0))]
		if bool(u.get("_isMinion", false)):
			(out["Lm" if side == "left" else "Rm"] as Array).append(row)
			if side == "left":
				a_minion = u
		else:
			(out["L" if side == "left" else "R"] as Dictionary)[str(u.get("id", ""))] = row
			if side == "left" and str(u.get("id", "")) == "stone":
				stone_u = u
	out["egg_hp"] = (_gs.egg_hp as Dictionary).duplicate()
	var rl: Array = foe.get("leaders", [])
	out["ul"] = {"L_stone": int(s._unit_level("left", "stone")), "L_team": int(s._unit_level("left")),
		"R_last": int(s._unit_level("right", str(rl[2]))) if rl.size() >= 3 else -1, "R_team": int(s._unit_level("right"))}
	if stone_u != null and a_minion != null:
		var summon := {"is_summon": true, "summon_owner": stone_u, "side": "left", "id": "_summon_minion"}
		out["mult"] = {"stone": float(s._lvl_mult_for(stone_u)), "summon": float(s._lvl_mult_for(summon)),
			"minion": float(s._lvl_mult_for(a_minion))}
	## 驯服过来进终极战场的龟(幸存名单带 lv_side = 原主人那一方): 按原主人那张表; 不带 = 按自己站的这一方
	##   走真的那条路: 幸存名单 spec → _spawn_lane_side(终极战场建场用的同一个)
	if rl.size() >= 3:
		var n0: int = (s._units as Array).size()
		s._spawn._spawn_lane_side([{"kind": "leader", "id": str(rl[2]), "hp_frac": 1.0, "tamed_side": "left", "lv_side": "right"},
			{"kind": "leader", "id": str(rl[2]), "hp_frac": 1.0}], "left", LEFT_LV, Vector2(400.0, 300.0))
		var tm: Dictionary = s._units[n0]
		var pl: Dictionary = s._units[n0 + 1]
		out["tamed"] = [int(tm.get("level", 0)), int(pl.get("level", 0)), float(s._lvl_mult_for(tm))]
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
	OS.set_environment("TURTLE_SEED", "4242")
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	var acct0 := str(_gs.account_id)
	var wk0 := int(_gs.week_anchor_ts)

	# ── ① 生产 ──
	print("=== ① 快照里的 lv 表 ===")
	_setup(_foe(null), {})
	var s0: Dictionary = BE.build_ghost_snapshot("g_r1", {"name": "x", "avatar": "basic", "id": "g_r1"})
	_ok("① 本机没有等级表 ⇒ 快照不带 lv(旧口径, 对面也按整队等级)", not s0.has("lv"), str(s0.keys()))
	_gs.pet_lv = TurtleLevel.full_table(["stone"], {"stone": 6, "basic": 9})
	var s1: Dictionary = BE.build_ghost_snapshot("g_r1", {"name": "x", "avatar": "basic", "id": "g_r1"})
	_ok("★① 本机有等级表 ⇒ lv = 三只统领各自的(stone 拥有 6、basic 没拥有 1、bamboo 1)",
		s1.get("lv", {}) == {"basic": 1, "stone": 6, "bamboo": 1}, str(s1.get("lv", "缺")))
	var bad_bot: Array = []
	for k in range(30):
		var r := RandomNumberGenerator.new()
		r.seed = 7000 + k
		var st0: int = r.state
		var b: Dictionary = BE.make_bot(k % 25, r)
		var fr := WeeklyFree.free_ids("bot:%d" % st0, 0, [])
		var ld: Array = b.get("leaders", [])
		var lvt: Dictionary = TurtleLevel.table_of(b.get("lv", null))
		var ok := ld.size() == 3 and lvt.size() == 3
		for p in ld:
			if not fr.has(str(p)) or int(lvt.get(str(p), 0)) != 1:
				ok = false
		if not ok:
			bad_bot.append("%d: %s / %s" % [k, str(ld), str(fr)])
	_ok("★① make_bot 30 个: 三只统领都在它自己那组限免 7 只里、lv 全 1", bad_bot.is_empty(), str(bad_bot.slice(0, 2)))
	var raw := {"ghost_id": "seed_x_b10", "leaders": ["basic", "stone", "bamboo"], "season_total_battles": 10, "season_level": 7,
		"lane_assign": {"top": ["basic"], "bottom": ["stone", "bamboo"]}, "minions": {"top": [{"role": "front"}, {"role": "back"}], "bottom": [{"role": "back"}]}}
	_ok("① 陪练 seed_as_human: lv 全 1", TurtleLevel.table_of(BE.seed_as_human(raw, 1).get("lv")) == {"basic": 1, "stone": 1, "bamboo": 1})

	# ── ② / ③ ──
	print("=== ② 两侧按龟等级 / ③ 旧快照整队等级 ===")
	var rl0: Array = _foe(null).get("leaders", [])
	var rtab := {}
	for i in range(mini(3, rl0.size())):
		rtab[str(rl0[i])] = RLVS[i]
	## 统领与蛋: 三只都摆上路(第一路开打那一步三只都在场); 小将: 原阵型(上路 1 统领 + 小将)
	var ref: Dictionary = await _run(_foe(null, true), {}, true)
	var per: Dictionary = await _run(_foe(rtab, true), LTAB, true)
	var refm: Dictionary = await _run(_foe(null), {})
	var perm: Dictionary = await _run(_foe(rtab), LTAB)
	for pair in [["整队", ref], ["按龟", per]]:
		var o: Dictionary = pair[1]
		_ok("分母(%s): 开打了、左统领 %d 只 = 3、右统领 %d 只 = 3、两颗蛋" % [str(pair[0]), (o["L"] as Dictionary).size(), (o["R"] as Dictionary).size()],
			str(o["state"]) == "fight" and (o["L"] as Dictionary).size() == 3 and (o["R"] as Dictionary).size() == 3
			and (o["egg"] as Dictionary).has("left") and (o["egg"] as Dictionary).has("right"), str(o["state"]))
	for pair in [["整队", refm], ["按龟", perm]]:
		var o2: Dictionary = pair[1]
		_ok("分母(%s · 原阵型): 开打了、两侧上路都有小将" % str(pair[0]), str(o2["state"]) == "fight"
			and not (o2["Lm"] as Array).is_empty() and not (o2["Rm"] as Array).is_empty(), "%d / %d" % [(o2["Lm"] as Array).size(), (o2["Rm"] as Array).size()])
	## ③ 旧快照
	var lv3 := true
	for id in ref["L"]:
		lv3 = lv3 and int(ref["L"][id][0]) == LEFT_LV
	for id in ref["R"]:
		lv3 = lv3 and int(ref["R"][id][0]) == RIGHT_LV
	_ok("★③ 没有 lv 表: 统领全按整队等级(左 %d / 右 %d)" % [LEFT_LV, RIGHT_LV], lv3, "%s / %s" % [str(ref["L"]), str(ref["R"])])
	_ok("★③ 没有 lv 表: 小将与蛋也按整队等级(蛋 = egg_max_for(5) / (3))",
		int(refm["Lm"][0][0]) == LEFT_LV and int(refm["Rm"][0][0]) == RIGHT_LV
		and is_equal_approx(float(ref["egg"]["left"]), DLF.egg_max_for(LEFT_LV)) and is_equal_approx(float(ref["egg"]["right"]), DLF.egg_max_for(RIGHT_LV)))
	## ② 按龟
	var bad2: Array = []
	var ml := UnitScaling.level_multiplier(LEFT_LV)
	var mr := UnitScaling.level_multiplier(RIGHT_LV)
	for id in per["L"]:
		var want: int = int(LTAB.get(id, -1))
		var hp_want: float = float(ref["L"][id][1]) / ml * UnitScaling.level_multiplier(want)
		if int(per["L"][id][0]) != want or absf(float(per["L"][id][1]) - hp_want) > 1e-3 * hp_want:
			bad2.append("左 %s Lv%d 血 %.1f(应 Lv%d %.1f)" % [id, int(per["L"][id][0]), float(per["L"][id][1]), want, hp_want])
	for id in per["R"]:
		var want_r: int = int(rtab.get(id, -1))
		var hpr: float = float(ref["R"][id][1]) / mr * UnitScaling.level_multiplier(want_r)
		if int(per["R"][id][0]) != want_r or absf(float(per["R"][id][1]) - hpr) > 1e-3 * hpr:
			bad2.append("右 %s Lv%d 血 %.1f(应 Lv%d %.1f)" % [id, int(per["R"][id][0]), float(per["R"][id][1]), want_r, hpr])
	_ok("★★② 每只统领按自己的等级: 等级 = 表里的、生命 = 整队那遍 ÷ 整队乘数 × 自己的乘数(左 3 只 + 右 %d 只)" % (per["R"] as Dictionary).size(),
		bad2.is_empty() and (per["L"] as Dictionary).size() == 3, "; ".join(bad2))
	_ok("★② 同一局两侧三只等级各不相同(不是整队一个数)", int(per["L"]["basic"][0]) != int(per["L"]["bamboo"][0])
		and _distinct_levels(per["R"]) >= 2, "%s / %s" % [str(per["L"]), str(per["R"])])
	_ok("★② 小将等级不动(左 %d / 右 %d = 赛季等级)、生命与整队那遍逐位相同" % [LEFT_LV, RIGHT_LV],
		int(perm["Lm"][0][0]) == LEFT_LV and int(perm["Rm"][0][0]) == RIGHT_LV
		and var_to_bytes(perm["Lm"]) == var_to_bytes(refm["Lm"]) and var_to_bytes(perm["Rm"]) == var_to_bytes(refm["Rm"]))
	## 用户 2026-11-08「尾端血量按赛季等级」⇒ 龟蛋按这一方的赛季等级, 不是三只统领龟等级的平均(那样会是 4 / 6)
	_ok("★★② 龟蛋满血按赛季等级: 左 %d、右 %d(不是三只平均 4 / 6)" % [LEFT_LV, RIGHT_LV],
		is_equal_approx(float(per["egg"]["left"]), DLF.egg_max_for(LEFT_LV)) and is_equal_approx(float(per["egg"]["right"]), DLF.egg_max_for(RIGHT_LV))
		and is_equal_approx(float(per["egg_hp"]["left"]), DLF.egg_max_for(LEFT_LV)) and is_equal_approx(float(per["egg_hp"]["right"]), DLF.egg_max_for(RIGHT_LV)),
		"%.0f / %.0f" % [float(per["egg"]["left"]), float(per["egg"]["right"])])
	_ok("★② _unit_level: 左 stone = 2、左整队 = %d、右第三只 = 10、右整队 = %d" % [LEFT_LV, RIGHT_LV],
		per["ul"] == {"L_stone": 2, "L_team": LEFT_LV, "R_last": 10, "R_team": RIGHT_LV}, str(per["ul"]))
	_ok("★② 驯服过来进终极战场的龟按原主人那张表(右第三只 10 级; 不带 lv_side ⇒ 左表里没有 = 1); 没有表 ⇒ 老口径(左整队 %d)" % LEFT_LV,
		per.get("tamed", []) == [10, 1, UnitScaling.level_multiplier(10)] and int((ref.get("tamed", [0]) as Array)[0]) == LEFT_LV,
		"%s / %s" % [str(per.get("tamed", [])), str(ref.get("tamed", []))])
	var mm: Dictionary = per["mult"]
	_ok("★② _lvl_mult_for: 统领 stone = 2 级乘数、它的召唤物 = 主人的、小将 = 整队乘数",
		not mm.is_empty() and is_equal_approx(float(mm["stone"]), UnitScaling.level_multiplier(2))
		and is_equal_approx(float(mm["summon"]), UnitScaling.level_multiplier(2)) and is_equal_approx(float(mm["minion"]), ml), str(mm))

	# ── ④ 裁判 ──
	print("=== ④ 裁判把关 / 等级表 ===")
	var fa := WeeklyFree.free_ids(ACCT_A, WEEK, ["stone"])
	var fb := WeeklyFree.free_ids(ACCT_B, WEEK, [])
	var outside_a := ""
	for p in WeeklyFree.ALL:
		if not fa.has(p) and p != "stone":
			outside_a = p
			break
	var ja := _job([fa[0], fa[1], "stone"], [fb[0], fb[1], fb[2]])
	_ok("④ 分母: A 拥有 stone + 两只限免、B 三只限免 ⇒ 收", RefereeJob.validate(ja) == "", RefereeJob.validate(ja))
	var jb := _job([fa[0], fa[1], outside_a], [fb[0], fb[1], fb[2]])
	_ok("★★④ A 有一只既没拥有也不是限免 ⇒ a_bad_snapshot", RefereeJob.validate(jb) == "a_bad_snapshot", RefereeJob.validate(jb))
	jb["key"]["a_owned"] = ["stone", outside_a]
	_ok("★④ 那只补进拥有 ⇒ 收(拥有读任务单 key.a_owned = 领活时服务器盖的)", RefereeJob.validate(jb) == "", RefereeJob.validate(jb))
	var jf := _job([fa[0], fa[1], outside_a], [fb[0], fb[1], fb[2]])
	(jf["a"] as Dictionary)["owned"] = ["stone", outside_a]
	(jf["a"] as Dictionary)["account_id"] = ACCT_A
	_ok("★④ 周赛局快照里自报的 owned 不认(只认 key 里服务器盖的)", RefereeJob.validate(jf) == "a_bad_snapshot", RefereeJob.validate(jf))
	var outside_b := ""
	for p in WeeklyFree.ALL:
		if not fb.has(p):
			outside_b = p
			break
	var jc := _job([fa[0], fa[1], "stone"], [fb[0], fb[1], outside_b])
	_ok("★★④ B 有一只不在 ⇒ b_bad_snapshot", RefereeJob.validate(jc) == "b_bad_snapshot", RefereeJob.validate(jc))
	jc["key"]["b_account"] = null
	_ok("★④ B 没有账号(服务器机器人池, key.b_account = null) ⇒ 不查", RefereeJob.validate(jc) == "", RefereeJob.validate(jc))
	var jd := _job([fa[0], fa[1], "stone"], [fb[0], fb[1], fb[2]])
	jd["key"]["week"] = WEEK + 604800
	_ok("★④ 周锚点读 key.week: 换成下一周 ⇒ 这组限免对不上 ⇒ 拒", RefereeJob.validate(jd) != "", RefereeJob.validate(jd))
	var je := _job([fa[0], fa[1], "stone"], [fb[0], fb[1], fb[2]])
	je["key"]["a_owned"] = []
	_ok("④ 盖章时没拥有(key.a_owned = [], 没绑定) ⇒ stone 不认", RefereeJob.validate(je) == "a_bad_snapshot", RefereeJob.validate(je))
	## 周中卖掉 stone: 现在不拥有了, 但本周已经上场打过(服务器盖 key.a_kept)⇒ 照收; kept 只放过它自己
	je["key"]["a_kept"] = ["stone"]
	_ok("★★④ 周中卖掉 stone、本周上场过(key.a_kept) ⇒ 收", RefereeJob.validate(je) == "", RefereeJob.validate(je))
	var jk := _job([fa[0], outside_a, "stone"], [fb[0], fb[1], fb[2]])
	jk["key"]["a_owned"] = []
	jk["key"]["a_kept"] = ["stone"]
	_ok("★④ kept 只放过上场过的那只: 另一只既没拥有也不是限免也没上场过 ⇒ 仍拒", RefereeJob.validate(jk) == "a_bad_snapshot", RefereeJob.validate(jk))
	var jkb := _job([fa[0], fa[1], "stone"], [fb[0], fb[1], outside_b])
	jkb["key"]["b_kept"] = [outside_b]
	_ok("★④ B 方同一条(key.b_kept)", RefereeJob.validate(jkb) == "", RefereeJob.validate(jkb))
	jkb["key"].erase("b_kept")
	(jkb["b"] as Dictionary)["kept"] = [outside_b]
	_ok("★④ 快照里自报的 kept 不认(只认 key)", RefereeJob.validate(jkb) == "b_bad_snapshot", RefereeJob.validate(jkb))
	## 偷袭局: 服务端没走领活盖章(key 里没有账号)时, 用 raid_create 盖在快照里的 account_id / owned(20261109c)
	var jr := _job([fa[0], fa[1], "stone"], [fb[0], fb[1], fb[2]])
	jr["mode"] = "raid"
	jr["key"] = {"week": WEEK, "b_account": ACCT_B}   # 偷袭建任务时 meta 里本来就有一个只放账号的 b_account(20261109c) —— 不能当成盖过章
	(jr["a"] as Dictionary)["account_id"] = ACCT_A
	(jr["a"] as Dictionary)["owned"] = ["stone"]
	(jr["b"] as Dictionary)["account_id"] = ACCT_B
	(jr["b"] as Dictionary)["owned"] = []
	_ok("★④ 偷袭局 key 里没有账号 ⇒ 读快照里 raid_create 盖的 account_id / owned: 合格 ⇒ 收", RefereeJob.validate(jr) == "", RefereeJob.validate(jr))
	(jr["a"] as Dictionary)["owned"] = []
	_ok("★④ 偷袭局快照里 A 没拥有 stone ⇒ a_bad_snapshot", RefereeJob.validate(jr) == "a_bad_snapshot", RefereeJob.validate(jr))
	var jo := _job([fa[0], fa[1], outside_a], [fb[0], fb[1], fb[2]])
	jo["key"] = {"week": WEEK}
	_ok("④ 旧任务(key 里没有账号、不是偷袭) ⇒ 不查(与改之前相同)", RefereeJob.validate(jo) == "", RefereeJob.validate(jo))
	(jo["a"] as Dictionary)["account_id"] = ACCT_A
	(jo["a"] as Dictionary)["owned"] = []
	_ok("★④ 周赛局快照里自报的 account_id / owned 一概不读(没盖章 = 不查; 不拿客户端给的身份去算限免)",
		RefereeJob.validate(jo) == "", RefereeJob.validate(jo))
	var nrm := func(specs: Array) -> Array: return specs
	(ja["a"] as Dictionary)["lv"] = {"stone": 4, fa[0]: 1, fa[1]: 1}
	var st: Dictionary = RefereeJob.state_for(ja, nrm)
	_ok("★④ state_for: 旧任务(key 里没有 a_lv) ⇒ 左方等级表 = A 快照的 lv", st.get("pet_lv", null) == {"stone": 4, fa[0]: 1, fa[1]: 1}, str(st.get("pet_lv", "缺")))
	ja["key"]["a_lv"] = {"stone": 7, fa[0]: 1, fa[1]: 2}
	ja["key"]["b_lv"] = {fb[0]: 5}
	(ja["b"] as Dictionary)["lv"] = {fb[0]: 10}
	var st2: Dictionary = RefereeJob.state_for(ja, nrm)
	_ok("★④ state_for: 领活盖的 key.a_lv 压过 A 快照自报的; key.b_lv 写进对手快照(压过 B 自报的 10)",
		st2.get("pet_lv", null) == {"stone": 7, fa[0]: 1, fa[1]: 2} and ((st2["dual_ghost"] as Dictionary).get("lv", {}) as Dictionary) == {fb[0]: 5},
		"%s / %s" % [str(st2.get("pet_lv")), str((st2["dual_ghost"] as Dictionary).get("lv"))])
	(ja["key"] as Dictionary).erase("a_lv")
	(ja["key"] as Dictionary).erase("b_lv")
	(ja["a"] as Dictionary).erase("lv")
	_ok("★④ state_for: key 和 A 快照都没有 lv ⇒ 空(整队等级); 对手快照原样", (RefereeJob.state_for(ja, nrm).get("pet_lv", null) as Dictionary).is_empty()
		and (RefereeJob.state_for(ja, nrm)["dual_ghost"] as Dictionary).get("lv", {}) == {fb[0]: 10})

	# ── ⑤ 显示 ──
	print("=== ⑤ 显示等级 ===")
	_gs.debug_level = 0
	_gs.season_level = LEFT_LV
	_gs.pet_lv = {"stone": 2, "basic": 1}
	_gs.candy_temp_levels = {"stone": 1}
	_ok("★⑤ battle_level_for: stone = 2 + 临时 1 = 3; 小将(\"\") = 赛季 5; 表里没有的 = 1",
		_gs.battle_level_for("stone") == 3 and _gs.battle_level_for("") == LEFT_LV and _gs.battle_level_for("lava") == 1,
		"%d / %d / %d" % [_gs.battle_level_for("stone"), _gs.battle_level_for(""), _gs.battle_level_for("lava")])
	_gs.pet_lv = {}
	_ok("⑤ 没有等级表 ⇒ 赛季等级(老口径)", _gs.battle_level_for("stone") == LEFT_LV + 1)
	_gs.debug_level = 8
	_gs.pet_lv = {"stone": 2}
	_ok("⑤ 调试强制等级压过龟等级", _gs.battle_level_for("stone") == 9)
	_gs.debug_level = 0
	_gs.candy_temp_levels = {}

	# ── ⑥ 录像 ──
	_ok("⑥ 录像 STATE_KEYS 有 pet_lv", ReplayRecorder.STATE_KEYS.has("pet_lv"))
	_gs.pet_lv = {"stone": 7}
	ReplayRecorder.apply_state({"season_level": 4})
	_ok("★⑥ 旧录像(没有 pet_lv) ⇒ 清空看的人自己的表", (_gs.pet_lv as Dictionary).is_empty(), str(_gs.pet_lv))
	ReplayRecorder.apply_state({"pet_lv": {"stone": 3}})
	_ok("⑥ 新录像 ⇒ 用录像里的表", _gs.pet_lv == {"stone": 3})

	# ── ⑦ 曲线 ──
	_ok("★⑦ 曲线: 70 / 160 / 1350; 69→1 70→2 1349→9 1350→10 9999→10",
		TurtleLevel.xp_to_reach(2) == 70 and TurtleLevel.xp_to_reach(3) == 160 and TurtleLevel.xp_cap() == 1350
		and TurtleLevel.level_for_xp(69) == 1 and TurtleLevel.level_for_xp(70) == 2 and TurtleLevel.level_for_xp(1349) == 9
		and TurtleLevel.level_for_xp(1350) == 10 and TurtleLevel.level_for_xp(9999) == 10 and TurtleLevel.WIN_XP == 8 and TurtleLevel.LOSE_XP == 6)
	var sql := FileAccess.get_file_as_string("res://server/supabase/migrations/20261109b_pet_levels.sql")
	_ok("⑦ 迁移里同一条曲线(50 + 10 × 等级)、赢 8 输 6、封顶 1350",
		sql.contains("* (50 + 10 * least(") and sql.contains("case when p_won then 8 else 6 end") and sql.contains("check (xp between 0 and 1350)"))

	# ── ⑧ 客户端缓存 ──
	print("=== ⑧ 客户端 ===")
	_gs.account_id = ACCT_A           # 缓存按号记: 先换到这个号, 再采用它的回包
	_gs.week_anchor_ts = WEEK
	var res := {"ok": true, "data": {"ok": true, "linked": true, "owned": ["stone", "lava", "nope"],
		"levels": {"stone": {"lv": 4, "xp": 300}, "basic": {"lv": 9, "xp": 1200}}}}
	var p := PetLevelsNet.parse(res)
	PetLevelsNet.adopt(p)
	var tbl: Dictionary = _gs.pet_lv
	_ok("★⑧ 回包 ⇒ 28 只全表: 拥有的 stone 4、拥有没记录的 lava 1、没拥有的 basic 1(服务器有记录也不认)",
		tbl.size() == 28 and int(tbl["stone"]) == 4 and int(tbl["lava"]) == 1 and int(tbl["basic"]) == 1
		and PetLevelsNet.owned == ["stone", "lava"], "%d 只 %s" % [tbl.size(), str(PetLevelsNet.owned)])
	_ok("⑧ 回包不像(ok 假 / 没有 owned) ⇒ 不采用", PetLevelsNet.parse({"ok": false, "data": {}}).is_empty()
		and PetLevelsNet.parse({"ok": true, "data": {"levels": {}}}).is_empty())
	var al := PetLevelsNet.allowed_now()
	_ok("★⑧ 登录了 ⇒ 能上场的 = WeeklyFree.allowed_ids(我的账号, 本周, 拥有)",
		PetLevelsNet.filter_on() and al == WeeklyFree.allowed_ids(ACCT_A, WEEK, ["stone", "lava"]), str(al))
	var not_al := ""
	for x in WeeklyFree.ALL:
		if not al.has(x):
			not_al = x
			break
	var y: String = WeeklyFree.free_ids(ACCT_A, WEEK, ["stone", "lava"])[0]
	var pick := PetLevelsNet.fill_allowed([not_al, "lava", y])
	var pick_ok := pick.size() == 3 and not pick.has(not_al)
	for x in pick:
		pick_ok = pick_ok and al.has(x)
	_ok("★⑧ 陪练号选龟: 槽位表里本周能上的留下(lava、%s)、不能上的(%s)换成能上的, 恰 3 只" % [y, not_al],
		pick_ok and pick[0] == "lava" and pick[1] == y, str(pick))
	PetLevelsNet.adopt_owned(["stone", "lava"])
	_gs.account_id = "22222222-3333-4444-8555-666666666666"
	_ok("★⑧ 换号 ⇒ 上一个号的拥有作废(这个号没有缓存 ⇒ 空, 只剩它自己的限免)",
		PetLevelsNet.allowed_now() == WeeklyFree.allowed_ids("22222222-3333-4444-8555-666666666666", WEEK, [])
		and PetLevelsNet.owned.is_empty(), str(PetLevelsNet.owned))
	_gs.account_id = ""
	_ok("⑧ 没登录后端 ⇒ 不过滤(门禁 / 本机开发)", not PetLevelsNet.filter_on()
		and PetLevelsNet.fill_allowed(["ice", "ghost", "lava"]) == ["ice", "ghost", "lava"])
	_gs.account_id = acct0
	_gs.week_anchor_ts = wk0
	_gs.pet_lv = {}
	PetLevelsNet.owned = []
	_finish()


func _job(la: Array, lb: Array) -> Dictionary:
	return {"v": 1, "mode": "ranked", "seed": 77,
		"key": {"week": WEEK, "a_account": ACCT_A, "b_account": ACCT_B, "a_owned": ["stone"], "b_owned": []},
		"a": {"leaders": la, "lane_assign": {"top": [la[0], la[1]], "bottom": [la[2]]}},
		"b": {"leaders": lb, "lane_assign": {"top": [lb[0]], "bottom": [lb[1], lb[2]]}}}


func _distinct_levels(side: Dictionary) -> int:
	var s := {}
	for id in side:
		s[int(side[id][0])] = true
	return s.size()


func _finish() -> void:
	print("  (共 %d 条断言)" % _n)
	if _fail == 0 and _n > 0:
		print("ALL PASS — 按龟等级")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
