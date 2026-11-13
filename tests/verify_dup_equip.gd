extends Node
## verify_dup_equip —— 同名装备带多件: 每件各自生效、统计分开(2026-11-13)
##
## 用户 11-13 原话:「两件肯定召唤两个炮台啊，三件召唤三个炮台…如果有出现两件相同装备，肯定是各自就是各自生效各自的
##   这个效果呀，也不能说共享啊…两个相同装备，它打的伤害，凭什么说你共享统计啊？那肯定是分开啊。」
## 方案书 docs/plans/20261113-同名装备多件各自生效.md(§6 验收 V1~V3)。
##
## 判据:
##   ① 份号: 第 1 件 = 原 id(单件逐字不变), 第 2 件起「id#2」; 上下文以外 key_of 恒为原 id。
##   ② 058 远古炮台 / 032 唤灵骨符: 两件 = 两个召唤物, 星级各按自己那件, 与装备栏顺序无关(修前: 只召一个, 星级取排后面那件)。
##   ③ 代表件(每类一件: on-hit / 周期 / 灵物每帧 / 奇械批④(084 远程只给属性、不记账 ⇒ 由 verify_eq_blade_batch ④ 验相加) / 遗物 / 低血触发 / 每帧 tick / 在途表 / 法器 / 召唤):
##      [3★, 1★] 两件各自都有「本局」账, 且 3★ 那件的账 > 1★ 那件(星级没被另一件覆盖)。
##   ④ 面板: 「本局」按份号取 ⇒ 第 2 件那一格读得到它自己的统计。
## 反向验证(11-13 做过): 把 EquipCk.ck_name 改成恒返回原 id ⇒ ①②③④ 变红; 逐字节还原。
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_dup_equip.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const _IPANEL := preload("res://scripts/scenes/battle/info_panel.gd")
const DT := 1.0 / 60.0
## 代表件: 每类一件。理由写在 ③ 的头注里; 都是 11-13 探针(tests/probes/_probe_dup_equip.gd)修前第二件账为 0 的件。
const CASES := ["p2eq_062", "p2eq_075", "p2eq_060", "p2eq_086", "p2eq_091", "p2eq_044", "p2eq_021", "p2eq_078", "p2eq_088", "p2eq_034"]

var s = null
var _n := 0
var _fail := 0


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
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	RB.DEBUG_EDIT = true
	print("=== verify_dup_equip: 同名装备多件各自生效 ===")
	_t_ck()
	await _t_summons()
	await _t_conch()
	await _t_cases()
	print("合计 %d 条" % _n)
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


# ① 份号
func _t_ck() -> void:
	print("── ① 份号 ──")
	var u: Dictionary = {"equips": [{"id": "p2eq_058", "star": 3}, {"id": "p2eq_001", "star": 1}, {"id": "p2eq_058", "star": 1}]}
	var es: Array = u["equips"]
	_ok("① 第 1 件 = 原 id(单件逐字不变)", EquipCk.ck_of(u, es[0]) == "p2eq_058")
	_ok("① 第 2 件同名 = 「p2eq_058#2」", EquipCk.ck_of(u, es[2]) == "p2eq_058#2", EquipCk.ck_of(u, es[2]))
	_ok("① 别的件不受影响", EquipCk.ck_of(u, es[1]) == "p2eq_001")
	_ok("① base_id 还原", EquipCk.base_id("p2eq_058#2") == "p2eq_058" and EquipCk.base_id("p2eq_058") == "p2eq_058")
	var cps: Array = EquipCk.copies(u, "p2eq_058")
	_ok("① copies: 两份、按装备栏顺序、各自星级", cps.size() == 2 and str(cps[0][0]) == "p2eq_058" and int(cps[0][1]) == 3
		and str(cps[1][0]) == "p2eq_058#2" and int(cps[1][1]) == 1, str(cps))


func _new_scene() -> void:
	if s != null:
		s.queue_free()
		await get_tree().process_frame
	s = RB.new()
	add_child(s)
	for _j in range(6):
		await get_tree().process_frame
	s._deterministic = true
	s.set_process(false)


## 一个干净小场(同 tests/probes/_probe_dup_equip.gd): 携带者 + 一个友军 + 三个高血敌人 + 一个脆皮 + 一个远处敌人。
func _arena(iid: String, stars: Array) -> Dictionary:
	s._battle_rng.seed = 20261113
	s._dl_sys._dl_clear_units()
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-60, 0))
	u["maxHp"] = 6000.0; u["hp"] = 3000.0; u["atk"] = 120.0; u["no_move"] = true
	u["energy"] = 100.0
	var al: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-120, 30))
	al["maxHp"] = 6000.0; al["hp"] = 3000.0; al["no_basic"] = true; al["no_move"] = true
	var es: Array = []
	for i in range(3):
		var e: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(10.0 + 50.0 * float(i), -20.0 + 20.0 * float(i)))
		e["maxHp"] = 1.0e6; e["hp"] = 1.0e6; e["atk"] = 25.0; e["no_move"] = true
		es.append(e)
	var fod: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(30, 40))
	fod["maxHp"] = 400.0; fod["hp"] = 400.0; fod["atk"] = 1.0; fod["no_move"] = true
	var far: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(420, 0))
	far["maxHp"] = 1.0e6; far["hp"] = 1.0e6; far["atk"] = 1.0; far["no_move"] = true
	s._units.clear()
	for x in [u, al, fod, far]:
		s._units.append(x)
	s._units.append_array(es)
	s._edit_mode = false
	s._over = false
	var eqs: Array = []
	for st in stars:
		eqs.append({"id": iid, "star": int(st)})
	u["equips"] = eqs
	u["eq_state"] = {iid: {}}
	s._equip_sys._stats._eq_apply_all_stats()
	u["range_add"] = float(u.get("range_add", 0.0)) + 400.0
	return u


func _summons_of(owner: Dictionary, kind: String) -> Array:
	var out: Array = []
	for x in s._units:
		if (x as Dictionary).get("is_summon", false) and str((x as Dictionary).get("summon_kind", "")) == kind \
				and is_same((x as Dictionary).get("summon_owner", null), owner):
			out.append(x)
	return out


# ② 058 / 032: 两件 = 两个召唤物, 各自星级, 与顺序无关
func _t_summons() -> void:
	print("── ② 召唤类 ──")
	for spec in [["p2eq_058", "turret", "_turret_si"], ["p2eq_032", "skeleton", ""]]:
		var iid: String = spec[0]
		for order in [[3, 1], [1, 3]]:
			await _new_scene()
			var u: Dictionary = _arena(iid, order)
			for k in range(6):
				s._sim_step(DT, false, false)
			var sm: Array = _summons_of(u, str(spec[1]))
			var hps: Array = []
			for x in sm:
				hps.append(int(float((x as Dictionary)["maxHp"])))
			_ok("② %s %s: 两件召出两个" % [iid, str(order)], sm.size() == 2, "n=%d" % sm.size())
			if str(spec[2]) != "" and sm.size() == 2:
				var sis: Array = [int(sm[0][spec[2]]), int(sm[1][spec[2]])]
				_ok("② %s %s: 星级各按自己那件(装备栏顺序)" % [iid, str(order)], sis == [order[0] - 1, order[1] - 1], str(sis))
			elif sm.size() == 2:
				_ok("② %s %s: 两只血量不同(星级各按自己那件)" % [iid, str(order)], hps[0] != hps[1], str(hps))
			if iid == "p2eq_058" and sm.size() == 2:
				var src: Array = [str(sm[0].get("_eq_src", "")), str(sm[1].get("_eq_src", ""))]
				_ok("② 058 %s: 两座炮台的账各记各的那一件" % str(order), src == ["p2eq_058", "p2eq_058#2"], str(src))


## 033 复活海螺: 某一件(携带者 + 份号)的虫现存几只。
func _worms_of(owner: Dictionary, ck: String) -> int:
	var n := 0
	for x in s._units:
		var xd: Dictionary = x
		if xd.get("alive", false) and str(xd.get("summon_kind", "")) == "worm" and str(xd.get("_eq_src", "")) == ck \
				and is_same(xd.get("_eq_owner", null), owner):
			n += 1
	return n


## ⑤ 033: 用户 11-13「不应该出两个吗？」—— 3★ 分裂上限 WORM_CAP 按【件】算。
##   一只龟两件 3★ ⇒ 两条分裂链各到 4 只(共 8); 两只龟各带一件同理。原来按「我方场上全部海螺虫」算, 两件合计也只到 4。
func _t_conch() -> void:
	print("── ⑤ 033 复活海螺: 分裂上限按件 ──")
	var cap: int = EquipSystem.WORM_CAP
	for mode in ["一只龟两件", "两只龟各一件"]:
		await _new_scene()
		var u: Dictionary = _arena("p2eq_033", [3, 3] if mode == "一只龟两件" else [3])
		var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
		var keep: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-260, 80))   # 撑住单路判定(单路模式召唤物不计存活)
		keep["maxHp"] = 1.0e7; keep["hp"] = 1.0e7; keep["no_basic"] = true; keep["no_move"] = true
		s._units.append(keep)
		var owners: Array = [[u, "p2eq_033"], [u, "p2eq_033#2"]]
		var al: Dictionary = {}
		for x in s._units:
			if not is_same(x, u) and not is_same(x, keep) and str((x as Dictionary).get("side", "")) == "left":
				al = x
		if mode == "两只龟各一件":
			al["equips"] = [{"id": "p2eq_033", "star": 3}]
			al["eq_state"] = {"p2eq_033": {}}
			owners = [[u, "p2eq_033"], [al, "p2eq_033"]]
		for k in range(30):
			s._sim_step(DT, false, false)
		u["hp"] = 1.0
		s._kill(u, null)
		if mode == "两只龟各一件":
			al["hp"] = 1.0
			s._kill(al, null)
		var mx: Array = [0, 0]
		var mx_all := 0
		for k in range(int(EquipSystem.WORM_SPLIT_IV * 60.0 * 5.0)):
			s._sim_step(DT, false, false)
			for i in range(2):
				mx[i] = maxi(int(mx[i]), _worms_of(owners[i][0], str(owners[i][1])))
			mx_all = maxi(mx_all, _worms_of(owners[0][0], str(owners[0][1])) + _worms_of(owners[1][0], str(owners[1][1])))
			if k % 30 == 0:
				await get_tree().process_frame
		_ok("⑤ %s: 分母 —— 对局没提前判完(%s)" % [mode, str(s._over)], not s._over)
		_ok("⑤ %s: 两条分裂链各到上限 %d 只(实测 %s)" % [mode, cap, str(mx)], int(mx[0]) == cap and int(mx[1]) == cap)
		_ok("⑤ %s: 合计 %d 只(实测最多同时 %d 只)" % [mode, 2 * cap, mx_all], mx_all == 2 * cap,
			"原来按我方场上全部海螺虫算上限 ⇒ 合计只有 %d" % cap)


func _eq_total(u: Dictionary, ck: String) -> float:
	var r: Dictionary = (u.get("_st_eq", {}) as Dictionary).get(ck, {})
	var t := 0.0
	for k in r.keys():
		t += float(r[k])
	return t


# ③ 代表件: [3★, 1★] 两件各自都有账, 3★ > 1★; ④ 面板按份号读得到第 2 件
func _t_cases() -> void:
	print("── ③ 代表件各自生效 ──")
	var panel_done := false
	for iid in CASES:
		await _new_scene()
		var u: Dictionary = _arena(str(iid), [3, 1])
		for k in range(1500):
			s._sim_step(DT, false, false)
			if k % 8 == 0:
				await get_tree().process_frame
		s._over = true
		var a3: float = _eq_total(u, str(iid))
		var a1: float = _eq_total(u, str(iid) + "#2")
		_ok("③ %s: 第 2 件(1★)有自己的账" % iid, a1 > 0.0, "3★ %.0f · 1★ %.0f" % [a3, a1])
		_ok("③ %s: 3★ 那件的账 > 1★ 那件(星级没被覆盖)" % iid, a3 > a1, "3★ %.0f · 1★ %.0f" % [a3, a1])
		if not panel_done and a1 > 0.0:
			panel_done = true
			var t2: String = _IPANEL.eq_stats_text(u, str(iid) + "#2")
			var t1: String = _IPANEL.eq_stats_text(u, str(iid))
			_ok("④ 面板「本局」按份号: 第 2 件那一格读到自己的统计(与第 1 件不同)", t2 != "" and t2 != t1, "#2「%s」 vs 「%s」" % [t2.replace("\n", " / "), t1.replace("\n", " / ")])
	_ok("④ 分母: 面板那条真的跑了", panel_done)
