extends Node
## _probe_dupid.gd — 同一只龟 id 在【同一侧】出现两次会不会冲突?
##
## 由来: 驯服(训龟大师新技能)会让敌方单位归顺我方并跨入终极战场。若被驯服的是敌方【统领】
## (如敌方凤凰), 而我方本来也有凤凰 → 终极战场会出现"我方两只凤凰"。
## 终极战场阵容 = _dl_snapshot_survivors 拍的幸存 spec 累加, spec 里只有 {kind:leader, id:"phoenix"},
## 没有任何"这是第几只"的区分 —— 所以必须先确认同 id 同侧不会互相踩。
##
## 查四件事(打真数字, 不推理):
##   ① 两只都真的 spawn 出来了吗? (会不会被去重/覆盖)
##   ② 各自的血量/状态是独立的吗? (打一只掉血, 另一只不该掉)
##   ③ 技能选择 _chosen_skill_types(id, is_left) 按 id+side 取 —— 两只会不会共享/互相覆盖?
##   ④ 局内头像栏(team panels)会不会只建一个 / 或建重复导致报错?
##
## 跑法: SHIP=1 DL_AUTOFIGHT=1 <godot> --headless --audio-driver Dummy --path . res://tests/_probe_dupid.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 同 id 两只同侧 探针 ===")

	# ★直接走【终极战场那条路】: _spawn_lane_side(specs,...) 吃的就是幸存 spec 数组,
	#   绕开赛前布阵的 _dl_structure_ok("恰好3统领")校验 —— 第一版我用 dual_lineup 塞两只凤凰,
	#   结果 4 个统领被判非法、【静默重置成默认阵容】, 只 spawn 出 1 只, 白测一轮。
	_setup(gs)
	var s = RB.new()
	add_child(s)
	for _i in range(6):
		await get_tree().process_frame
	var specs: Array = [
		{"kind": "leader", "id": "phoenix"},
		{"kind": "leader", "id": "phoenix"},   # ★同 id 第二只(模拟被驯服的敌方凤凰)
		{"kind": "minion", "role": "front"},
	]
	s._spawn._spawn_lane_side(specs, "left", 5, Vector2(400.0, 400.0))
	for _i in range(4):
		await get_tree().process_frame
	print("  (直接按幸存 spec spawn 两只凤凰)")

	# ── ① 两只都在吗 ──
	var mine: Array = _phx(s)
	print("")
	print("  ① 我方凤凰数量 = %d (期望 2)" % mine.size())
	for i in range(mine.size()):
		print("     [%d] hp=%.0f/%.0f  pos=%s" % [i, float(mine[i]["hp"]), float(mine[i]["maxHp"]), str(mine[i]["pos"].round())])
	_chk("① 同 id 两只都 spawn 出来(没被去重)", mine.size() == 2)
	if mine.size() != 2:
		_done(s); return

	# ── ② 状态独立吗 ──
	var a: Dictionary = mine[0]
	var b: Dictionary = mine[1]
	var hp_b0: float = float(b["hp"])
	a["hp"] = float(a["hp"]) - 100.0
	await get_tree().process_frame
	print("")
	print("  ② 给[0]扣100血后: [0]=%.0f  [1]=%.0f (期望 [1] 不变 %.0f)" % [float(a["hp"]), float(b["hp"]), hp_b0])
	_chk("② 两只状态互相独立(不是同一个字典)", not is_same(a, b) and absf(float(b["hp"]) - hp_b0) < 0.01)

	# ── ③ 技能选择按 id+side 取 —— 两只共享同一份, 是否合理 ──
	var st_a: Array = s._chosen_skill_types("phoenix", true)
	print("")
	print("  ③ _chosen_skill_types(\"phoenix\", true) = %s" % str(st_a))
	print("     [0] active_skills=%s" % str(a.get("active_skills", [])))
	print("     [1] active_skills=%s" % str(b.get("active_skills", [])))
	_chk("③ 两只各自都有 active_skills(不是空)", not (a.get("active_skills", []) as Array).is_empty() and not (b.get("active_skills", []) as Array).is_empty())

	# ── ④ 头像栏 ──
	var panels := _count_panels(s)
	print("")
	print("  ④ 局内头像栏条目数 = %d" % panels)
	_chk("④ 头像栏没崩(条目数 > 0)", panels > 0)

	_done(s)


func _phx(s) -> Array:
	var out: Array = []
	for u in s._units:
		if str(u.get("id", "")) == "phoenix" and str(u.get("side", "")) == "left" and not u.get("is_summon", false):
			out.append(u)
	return out


func _count_panels(s) -> int:
	## 头像栏是 _hud._build_team_panels 建的; 这里只数它有没有产出节点
	var n := 0
	if s._ui_layer == null:
		return 0
	var stack: Array = [s._ui_layer]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		for c in nd.get_children():
			if c is TextureRect or c is Panel:
				n += 1
			stack.append(c)
	return n


func _chk(what: String, ok: bool) -> void:
	if not ok:
		_fail += 1
	print("     %s %s" % ["[PASS]" if ok else "[FAIL]", what])


func _done(s) -> void:
	s.queue_free()
	await get_tree().process_frame
	print("")
	print("  ALL PASS" if _fail == 0 else "  ★ %d 项 FAIL" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 我方上路放【两只凤凰】—— 模拟"驯服了敌方凤凰、我方本来也有凤凰"
func _setup(gs) -> void:
	gs.reset_dual_lane()
	gs.dual_active = true
	gs.season_level = 5
	gs.hearts = 8
	gs.season_total_battles = 10
	gs.persistent_bench = []
	gs.persistent_equipped = {}
	gs.season_leaders = ["basic", "stone", "bamboo"]   # ★布阵里不放凤凰: 否则场上会多出第3只, 分不清是不是去重问题
	gs.left_team.assign(gs.season_leaders)
	gs.loadouts = {"phoenix": 2}   # 凤凰只由 _spawn_lane_side 塞进来
	gs.dual_lineup = {
		"top": [
			{"kind": "leader", "id": "basic", "slot": 0},
			{"kind": "minion", "role": "front"},
			{"kind": "minion", "role": "front"},
		],
		"bottom": [
			{"kind": "leader", "id": "stone", "slot": 1},
			{"kind": "leader", "id": "bamboo", "slot": 2},
			{"kind": "minion", "role": "front"},
		],
	}
	gs.dual_ghost = {
		"schema_ver": 1, "ghost_id": "probe_dupid", "is_bot": false, "bracket": 4,
		"profile": {"name": "探针", "avatar": "basic", "id": "PROBE"},
		"leaders": ["basic", "stone", "bamboo"],
		"lane_assign": {"top": ["basic"], "bottom": ["stone", "bamboo"]},
		"minions": {"top": [{"role": "front", "elite": false, "equips": []}, {"role": "front", "elite": false, "equips": []}],
					"bottom": [{"role": "front", "elite": false, "equips": []}]},
		"loadouts": {}, "equipped": {}, "pet_levels": {},
		"season_total_battles": 10, "season_eggs_killed": 0,
	}
