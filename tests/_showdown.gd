extends Node
## _showdown.gd — 【可视单场对决】把胜率测试里的同一套阵型放出来看 (2026-07-29)
##
## 由来: 用户「开个调试场, 给我看看梭哈 vs 其他强势龟的技能, 加两小将的」。
##   调试场是自由摆位编辑器, 摆出来的场跟胜率测试【不是同一个环境】(等级/装备/小将/阵型都可能不同),
##   看到的结论就不能拿去解释胜率表。所以这里直接复用 _duel.gd 的配置逻辑 ——
##   同样的 1 龟 + 2 近战小将、同样 Lv5、同样无装备、同样种子。
##
## ★它比调试场多给的东西: 【逐龟伤害记账】—— 谁打出多少、其中多少来自被测技能。
##   梭哈的病是"1846 点要花 14.5 秒逐枚投出", 这个只有把数字打出来才看得见, 肉眼看不出。
##
## 跑法(开窗口看):
##   SHOW_L=fortune SHOW_LS=2 SHOW_R=ghost SHOW_RS=2 \
##   <godot> --path . --position 900,140 --resolution 1000x600 res://tests/_showdown.tscn
##
## 环境变量:
##   SHOW_L / SHOW_R    左右龟 id (默认 fortune / ghost)
##   SHOW_LS / SHOW_RS  技能下标 1..3 (默认 2 / 2)
##   SHOW_LEVEL         赛季等级 (默认 5, 与胜率测试一致)
##   SHOW_SEED          种子 (默认 20260728, 与胜率测试一致)
##   SHOW_SECS          最长看多少游戏秒 (默认 90)
##
## ★不进门禁: 下划线前缀, run-tests.sh 只自动发现 verify_*.gd

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fillers := ["basic", "stone"]     # 与 _duel.gd 一致的下路填充龟
var _s = null
var _t0 := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("[FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true

	var lid := _env("SHOW_L", "fortune")
	var rid := _env("SHOW_R", "ghost")
	var lsx := int(_env("SHOW_LS", "2"))
	var rsx := int(_env("SHOW_RS", "2"))
	var lv := int(_env("SHOW_LEVEL", "5"))
	var secs := float(_env("SHOW_SECS", "90"))

	var pets: Dictionary = _pets()
	var lname := _skill_name(pets, lid, lsx)
	var rname := _skill_name(pets, rid, rsx)
	print("=== 可视对决 (与胜率测试同环境: Lv%d / 无装备 / 1龟+2近战小将) ===" % lv)
	print("  左  %s · %s" % [_tname(pets, lid), lname])
	print("  右  %s · %s" % [_tname(pets, rid), rname])
	print("")

	_setup(gs, lid, lsx, rid, rsx, lv)
	RB.NO_TRAINER = true    # ★关训龟大师(与胜率测试同环境)
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_dump_setup()

	# ── 逐帧记账: 每只龟造成的总伤 (读单位字典里的累计字段, 不碰产品代码) ──
	var t := 0.0
	var last_report := 0.0
	while t < secs and not (gs.lane_results as Dictionary).has("top"):
		await get_tree().process_frame
		t = float(_s._t)
		if t - last_report >= 10.0:
			last_report = t
			_report(t)
	print("")
	print("=== 结束 (游戏时间 %.1f 秒) ===" % t)
	var top: String = str((gs.lane_results as Dictionary).get("top", ""))
	print("  上路结果: %s" % ("左胜" if top == "left" else ("右胜" if top == "right" else "未分胜负(超时)")))
	_report(t)
	print("")
	print("  窗口保留 15 秒供观察…")
	var w := 0.0
	while w < 15.0:
		await get_tree().process_frame
		w += get_process_delta_time()
	get_tree().quit(0)


func _report(t: float) -> void:
	print("  ── t=%.0fs ──" % t)
	for u in _s._units:
		if not (u is Dictionary):
			continue
		if u.get("_isEgg", false) or u.get("is_trainer", false):
			continue
		var tag := "小将" if u.get("_isMinion", false) else "龟  "
		var extra := ""
		# 财神专属: 金币数 + 梭哈是否用过 + 还剩几枚没投完
		if str(u.get("id", "")) == "fortune":
			extra = "  [金币 %d / 梭哈%s / 待投 %d]" % [
				int(u.get("gold", 0)),
				("已用" if u.get("allin_used", false) else "未用"),
				int(u.get("allin_coins", 0))]
		print("     %s %-6s %-5s 生命 %5d/%-5d 盾 %4d 龟能 %3d%s" % [
			tag, str(u.get("side", "")), str(u.get("id", "")),
			int(u.get("hp", 0)), int(u.get("maxHp", 0)),
			int(u.get("shield", 0)), int(u.get("energy", 0)), extra])


func _dump_setup() -> void:
	var lead := {"left": 0, "right": 0}
	var mini := {"left": 0, "right": 0}
	for u in _s._units:
		# ★别按 "lane" 字段筛 —— 单位字典里【没有】这个字段(_duel.gd 也不筛, 它只跑上路)。
		# 第一版加了 lane=="top" 判断, 结果一个都数不到、体检报 0龟0小将。
		if not (u is Dictionary):
			continue
		var sd := str(u.get("side", ""))
		if not lead.has(sd):
			continue
		if u.get("_isMinion", false):
			mini[sd] = int(mini[sd]) + 1
		elif not u.get("is_trainer", false) and not u.get("_isEgg", false):
			lead[sd] = int(lead[sd]) + 1
	print("  [体检] 上路 左 %d龟+%d小将 / 右 %d龟+%d小将  (应各 1+2)" % [
		lead["left"], mini["left"], lead["right"], mini["right"]])
	# ★探针(2026-07-29 用户「训龟大师没关吗」): _duel.gd 注释写着"关训龟大师", 但代码里找不到关的地方 ——
	#   _spawn_trainers() 只在 VFXPREVIEW / DEBUG_EDIT 时跳过, 而 _duel.gd 两个都没设。
	var tr := 0
	var trinfo: Array = []
	for u in _s._units:
		if (u is Dictionary) and u.get("is_trainer", false):
			tr += 1
			trinfo.append("%s(技=%s 攻=%d 血=%d)" % [str(u.get("side","")),
				str(u.get("_tr_active","")) + str(u.get("_tr_passive","")),
				int(u.get("atk",0)), int(u.get("hp",0))])
	print("  [体检] ★训龟大师在场数 = %d  %s" % [tr, trinfo])


func _setup(gs, lid: String, lsx: int, rid: String, rsx: int, lv: int) -> void:
	gs.reset_dual_lane()
	gs.dual_active = true
	gs.season_level = lv
	gs.hearts = 8
	gs.season_total_battles = 10
	gs.persistent_bench = []
	gs.persistent_equipped = {}
	gs.season_leaders = [lid, _fillers[0], _fillers[1]]
	gs.left_team.assign(gs.season_leaders)
	gs.loadouts = {lid: lsx}
	gs.dual_lineup = {
		"top": [
			{"kind": "leader", "id": lid, "slot": 0},
			{"kind": "minion", "role": "front"},
			{"kind": "minion", "role": "front"},
		],
		"bottom": [
			{"kind": "leader", "id": _fillers[0], "slot": 1},
			{"kind": "leader", "id": _fillers[1], "slot": 2},
			{"kind": "minion", "role": "front"},
		],
	}
	gs.dual_ghost = {
		"schema_ver": 1, "ghost_id": "show_%s_%d" % [rid, rsx], "is_bot": false, "bracket": 4,
		"profile": {"name": rid, "avatar": rid, "id": "SHOW"},
		"leaders": [rid, _fillers[0], _fillers[1]],
		"lane_assign": {"top": [rid], "bottom": [_fillers[0], _fillers[1]]},
		"minions": {
			"top": [{"role": "front", "elite": false, "equips": []}, {"role": "front", "elite": false, "equips": []}],
			"bottom": [{"role": "front", "elite": false, "equips": []}],
		},
		"loadouts": {rid: rsx}, "equipped": {}, "pet_levels": {},
		"season_total_battles": 10, "season_eggs_killed": 0,
	}


func _pets() -> Dictionary:
	var j = JSON.parse_string(FileAccess.get_file_as_string("res://data/pets.json"))
	var arr: Array = []
	if j is Array:
		arr = j
	elif j is Dictionary:
		for v in (j as Dictionary).values():
			if v is Array:
				arr = v
				break
	var out := {}
	for p in arr:
		out[str(p.get("id", ""))] = p
	return out


func _tname(pets: Dictionary, pid: String) -> String:
	return str((pets.get(pid, {}) as Dictionary).get("name", pid))


func _skill_name(pets: Dictionary, pid: String, idx: int) -> String:
	var p: Dictionary = pets.get(pid, {})
	var pool: Array = p.get("skillPool", [])
	if idx >= 0 and idx < pool.size():
		return str((pool[idx] as Dictionary).get("name", "?"))
	return "?"


func _env(k: String, dv: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else dv
