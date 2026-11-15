extends Node
## verify_eq_tally_coverage.gd —— 装备「本局」统计: 结果数 + 次数 / 层数 真的记上了(2026-11-15)。
##
## 用户 11-15:「压电陶瓷片…这装备统计现在啥都没有…应该是…已获得龟能这样子的东西啊」
##             「辣椒你是不可以写以施加流血层数是多少多少层，是不是就够了？」
## 盘点(tests/probes/_probe_eq_tally_sweep.gd, 95 件各 3★ 实打): 改前 10 件「暂无记录」, 其中 043 海浪护符是 11-14 改逐步碰撞时丢了记账上下文、
##   037 蛋糕蜡烛的持续回血一直没上下文。改法见 EquipTally 头注 11-15 那段。
## 做法: 与盘点探针同一个场景(调试场 携带者 basic 带这件 3★ + 队友 stone vs 三个会打会走的敌人, 我方血量 ×6, 第 60 步灌满法力, 打 60 秒),
##   读携带者 `_st_eq` 里这件那一行, 每件断言它该有的键 > 0; 再用产品的面板函数 `eq_stats_text` 看文字。
## 反向验证(11-15 实测): 删 `_eq_grant_energy` 里那行 on_energy ⇒ 085 / 065 / 059 龟能三条红; 删 `_tick_tide_hits` 的 push ⇒ 043 三条红。

const SIM_DT := 1.0 / 60.0
const STEPS := 3600
const _IP := preload("res://scripts/scenes/battle/info_panel.gd")
## [装备, 该有的键(都要 > 0), 面板里该出现的字]
const CASES := [
	["p2eq_085", ["energy"], "获得龟能"],
	["p2eq_065", ["energy"], "获得龟能"],
	["p2eq_002", ["dot_bleed", "phy"], "施加流血"],
	["p2eq_067", ["dot_poison"], "施加中毒"],
	["p2eq_037", ["heal", "dot_burn"], "治疗"],
	["p2eq_043", ["shield", "mag", "knock"], "击飞"],
	["p2eq_035", ["coins"], "获得深海币"],
	["p2eq_059", ["ts_sec", "energy"], "时停"],
	["p2eq_066", ["cc_block"], "免疫控制"],
	["p2eq_090", ["stun"], "眩晕"],
	["p2eq_029", ["stun"], "冰封"],
	["p2eq_020", ["knock"], "击飞"],
]

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, d])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	print("=== 装备「本局」统计: 结果数 + 次数 / 层数 ===")
	for cs in CASES:
		var eid: String = str(cs[0])
		var row: Dictionary = await _one(eid)
		var miss: Array = []
		for k in (cs[1] as Array):
			if float(row.get(str(k), 0.0)) <= 0.0:
				miss.append(k)
		_ok("%s 记上了 %s" % [eid, str(cs[1])], miss.is_empty(), "缺 %s · 整行 %s" % [str(miss), str(row)])
		var txt: String = _IP.eq_stats_text({"_st_eq": {eid: row}}, eid)
		_ok("%s 面板「本局」里有「%s」" % [eid, str(cs[2])], txt.contains(str(cs[2])), txt.replace("\n", " / "))
	## 面板文字的两个特例(不用实打): 017 的免控只免击飞 ⇒「免疫击飞」; 029 的眩晕是冰封 ⇒「冰封」不写「眩晕」
	var t17: String = _IP.eq_stats_text({"_st_eq": {"p2eq_017": {"cc_block": 2.0}}}, "p2eq_017")
	_ok("017 不沉之锚写「免疫击飞 2 次」", t17 == "免疫击飞 2 次", t17)
	var t29: String = _IP.eq_stats_text({"_st_eq": {"p2eq_029": {"stun": 3.0}}}, "p2eq_029")
	_ok("029 冰封水母写「冰封 3 次」不写眩晕", t29 == "冰封 3 次", t29)
	var t56: String = _IP.eq_stats_text({"_st_eq": {"p2eq_056": {"knock": 3.0, "stun": 3.0}}}, "p2eq_056")
	_ok("056 飞镖的击飞 = 击退 + 期间眩晕两步 ⇒ 只写「击飞 3 次」", t56 == "击飞 3 次", t56)
	var t0: String = _IP.eq_stats_text({"_st_eq": {"p2eq_085": {"energy": 0.4}}}, "p2eq_085")
	_ok("只列非零: 不足 1 的龟能不出现「获得龟能 0」", t0 == "", t0)
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


func _one(eid: String) -> Dictionary:
	OS.set_environment("TURTLE_SEED", "424242")
	var RB = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	RB.DEBUG_EDIT = true
	var s = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	s._debug._edit_clear()
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 9000.0
	s._edit_full_energy = false
	var car: Dictionary = s._debug._edit_place_unit("basic", "left", Vector2(420.0, 360.0))
	car["_edit_equips"] = [{"id": eid, "star": 3}]
	s._debug._edit_place_unit("stone", "left", Vector2(360.0, 460.0))
	for p in [["basic", Vector2(820.0, 330.0)], ["stone", Vector2(860.0, 430.0)], ["bamboo", Vector2(900.0, 260.0)]]:
		s._debug._edit_place_unit(str(p[0]), "right", p[1])
	s._debug._edit_start_battle()
	s.set_process(false)
	var k := 0
	var c = null
	for u in s._units:
		if not (u is Dictionary):
			continue
		if str(u.get("side", "")) == "right":
			u.erase("no_basic")      # 调试场的敌人默认是不动的假人: 放开, 会走会打
			u.erase("no_move")
			if k == 2:
				u["hp"] = 1200.0     # 一只残血: 击杀类有人可杀
			k += 1
		else:
			u["maxHp"] = float(u["maxHp"]) * 6.0   # 我方血量 ×6: 周期 / 受击类有时间生效(原血量十来秒就被打死)
			u["hp"] = u["maxHp"]
			if str(u.get("id", "")) == "basic":
				c = u
	for i in range(STEPS):
		if i == 60 and c is Dictionary and s.get("_staff_syn") != null:
			s._staff_syn.add_mana(c, 99999.0)   # 【法力】类装备(043 / 029 / 090)放得出来
		s._sim_step(SIM_DT, float(s._hitstop) > 0.0, not (s._timestop._ts_active as Array).is_empty())
		if i % 300 == 0:
			await get_tree().process_frame
	var out: Dictionary = {}
	if c is Dictionary:
		var t: Dictionary = c.get("_st_eq", {})
		for iid in t:
			if EquipCk.base_id(str(iid)) != eid:
				continue
			for kk in (t[iid] as Dictionary):
				out[kk] = float(out.get(kk, 0.0)) + float(t[iid][kk])
	OS.set_environment("TURTLE_SEED", "")
	s.queue_free()
	RB.DEBUG_EDIT = false
	await get_tree().process_frame
	await get_tree().process_frame
	return out
