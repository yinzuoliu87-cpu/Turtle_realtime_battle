extends Node
## verify_equip_tally.gd — 每件装备的本局统计(用户 2026-10-04 ④)
##
## 用户原话:「四是现在每件装备（大部分）需要加上统计量，比如本局总治疗量，本局总伤害量，
##          到时候每个装备慢慢看要怎么显示统计吧」
## 数据结构与归因规则见 scripts/systems/equip/equip_tally.gd 文件头; 方案书 §8 ④。
##
## 判据都是【对账】, 不是数我插的标记:
##   · 合成段: 同一笔伤害/治疗/护盾, 装备账的增量 == 单位级 `_st_taken`/`_st_heal`/`_st_shield` 的增量
##   · 实战段: 携带者不普攻、敌人不还手 ⇒ 敌人受到的全部伤害只可能来自这件装备
##             ⇒ 装备账合计 == Σ敌人 `_st_taken`(分母: 必须 > 0)
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_equip_tally.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const DT := 1.0 / 60.0

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


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= maxf(2.0, absf(b) * 0.005)


func _eqv(u: Dictionary, iid: String, k: String) -> float:
	return float(((u.get("_st_eq", {}) as Dictionary).get(iid, {}) as Dictionary).get(k, 0.0))


func _eqdmg(u: Dictionary, iid: String) -> float:
	return _eqv(u, iid, "phy") + _eqv(u, iid, "mag") + _eqv(u, iid, "tru")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== ④ 每件装备的本局统计 ===")
	RB.DEBUG_EDIT = true
	s = RB.new()
	add_child(s)
	for _i in range(10):
		await get_tree().process_frame
	s._deterministic = true
	s.set_process(false)
	var tl = s._equip_sys.tally

	# ── A. 合成段: 两条伤害路 / 治疗 / 护盾 / 上下文外不记 / 护栏 ──
	var st: Array = await _stage("", false)
	var u: Dictionary = st[0]
	var al: Dictionary = st[1]
	var e: Dictionary = st[2][0]
	var t0: float = float(e.get("_st_taken", 0))
	var p0: Array = tl.push(u, "p2eq_901")
	s._damage._apply_damage_from(u, e, 300, Color.WHITE, 0.0, false, true)
	tl.pop(p0)
	var d1: float = float(e.get("_st_taken", 0)) - t0
	_ok("A1 ★伤害路①(_apply_damage_from): 装备账 == 目标承伤增量(分母 > 0)",
		d1 > 0.0 and _near(_eqdmg(u, "p2eq_901"), d1), "账 %.0f / 承伤 %.0f" % [_eqdmg(u, "p2eq_901"), d1])
	t0 = float(e.get("_st_taken", 0))
	p0 = tl.push(u, "p2eq_902")
	s._damage._apply_damage(e, 250, Color.WHITE, u, "tru")
	tl.pop(p0)
	var d2: float = float(e.get("_st_taken", 0)) - t0
	_ok("A2 ★伤害路②(_apply_damage): 装备账 == 目标承伤增量, 记在真实桶",
		d2 > 0.0 and _near(_eqv(u, "p2eq_902", "tru"), d2), "账 %.0f / 承伤 %.0f" % [_eqv(u, "p2eq_902", "tru"), d2])
	var h0: float = float(al.get("_st_heal", 0))
	var s0: float = float(al.get("_st_shield", 0))
	p0 = tl.push(u, "p2eq_903")
	s._damage._heal(al, 400.0)
	s._damage._grant_shield(al, 150.0)
	tl.pop(p0)
	_ok("A3 治疗给队友: 记在【携带者】的这件装备下 == 队友 _st_heal 增量",
		float(al.get("_st_heal", 0)) - h0 > 0.0 and _near(_eqv(u, "p2eq_903", "heal"), float(al.get("_st_heal", 0)) - h0),
		"账 %.0f" % _eqv(u, "p2eq_903", "heal"))
	_ok("A4 护盾给队友: == 队友 _st_shield 增量",
		float(al.get("_st_shield", 0)) - s0 > 0.0 and _near(_eqv(u, "p2eq_903", "shield"), float(al.get("_st_shield", 0)) - s0),
		"账 %.0f" % _eqv(u, "p2eq_903", "shield"))
	var before: String = str(u.get("_st_eq", {}))
	s._damage._apply_damage_from(u, e, 300, Color.WHITE)
	s._damage._heal(u, 100.0)
	_ok("A5 ★上下文外(普攻/技能本体)不记进装备账", str(u.get("_st_eq", {})) == before)
	p0 = tl.push(u, "p2eq_904")
	s._damage._heal(e, 300.0)
	s._damage._apply_damage_from(e, al, 200, Color.WHITE, 0.0, false, true)
	tl.pop(p0)
	_ok("A6 护栏: 上下文里给敌人回血 / 别人打的伤害都不记给这件", _eqv(u, "p2eq_904", "heal") == 0.0 and _eqdmg(u, "p2eq_904") == 0.0)

	# ── B. DoT 份额: 装备加 10 层流血 + 非装备再加 10 层 ⇒ 每跳一半记给装备 ──
	var e2: Dictionary = st[2][1]
	p0 = tl.push(u, "p2eq_905")
	s._damage._apply_dot_stacks(e2, "bleed", 10, u)
	tl.pop(p0)
	s._damage._apply_dot_stacks(e2, "bleed", 10, u)
	var tk0: float = float(e2.get("_st_taken", 0))
	s._tick_dot_stacks(e2)
	s._tick_dot_stacks(e2)
	var dd: float = float(e2.get("_st_taken", 0)) - tk0
	_ok("B1 ★层数 DoT 按份额分: 装备那 10 层 / 共 20 层 ⇒ 账 == 两跳 DoT 总伤的一半(分母 > 0)",
		dd > 0.0 and absf(_eqv(u, "p2eq_905", "phy") - dd * 0.5) <= 1.0, "账 %.1f / 总 %.0f" % [_eqv(u, "p2eq_905", "phy"), dd])

	# ── C. 延时队列 / 召唤物 —— 结算时上下文早没了, 靠入队/召唤那一刻盖的章 ──
	var e3: Dictionary = st[2][2]
	t0 = float(e3.get("_st_taken", 0))
	p0 = tl.push(u, "p2eq_906")
	s._pending_shots.append({"delay": 0.2, "src": u, "fn": func() -> void:
		s._damage._apply_damage_from(u, e3, 120, Color.WHITE, 0.0, false, true)})
	tl.pop(p0)
	for _k in range(30):
		s._sim_step(DT, false, false)
	var d3: float = float(e3.get("_st_taken", 0)) - t0
	_ok("C1 ★延时队列 _pending_shots: 落地时记回入队时的装备", d3 > 0.0 and _near(_eqdmg(u, "p2eq_906"), d3),
		"账 %.0f / 承伤 %.0f" % [_eqdmg(u, "p2eq_906"), d3])
	p0 = tl.push(u, "p2eq_907")
	var sm = s._spawn._spawn_summon(u, "verify_tally", 500.0, 50.0, {"label": "测试召唤", "no_move": true, "no_basic": true})
	tl.pop(p0)
	t0 = float(e3.get("_st_taken", 0))
	s._damage._apply_damage_from(sm, e3, 90, Color.WHITE)
	var d4: float = float(e3.get("_st_taken", 0)) - t0
	_ok("C2 ★召唤物: 装备上下文里召出来的, 它之后(上下文外)的伤害照样记给那件",
		d4 > 0.0 and _near(_eqdmg(u, "p2eq_907"), d4), "账 %.0f / 承伤 %.0f" % [_eqdmg(u, "p2eq_907"), d4])

	# ── D. 结算行: 摊平成纯标量键 + 合计页按路累加 = 本局 ──
	var row: Dictionary = s._st_row(u)
	_ok("D1 结算行带 `_st_eq|<id>|<键>` 且仍是纯标量",
		row.has("_st_eq|p2eq_901|phy") and not row.values().any(func(v): return v is Dictionary or v is Array), str(row.keys().size()))
	var r1: Dictionary = {"id": "basic", "name": "甲", "alive": true, "hp": 1.0, "maxHp": 2.0, "_st_eq|p2eq_001|phy": 100, "_st_eq|p2eq_012|shield": 40}
	var r2: Dictionary = {"id": "basic", "name": "甲", "alive": true, "hp": 1.0, "maxHp": 2.0, "_st_eq|p2eq_001|phy": 250}
	var merged: Array = s._hud._st_merge_all([{"lane": "top", "left": [r1], "right": []}, {"lane": "bottom", "left": [r2], "right": []}], "left")
	var nested: Dictionary = EquipTally.from_row(merged[0]) if merged.size() == 1 else {}
	_ok("D2 ★换路口径 = 本局: 同一只龟两路的装备账在合计页相加(100+250), 只在一路有的保留",
		merged.size() == 1 and int(nested.get("p2eq_001", {}).get("phy", 0)) == 350 and int(nested.get("p2eq_012", {}).get("shield", 0)) == 40,
		str(nested))

	# ── E. 实战段: 真装备走真入口, 携带者不普攻、敌人不还手 ⇒ 敌人承伤只来自这件装备 ──
	print("")
	## ★伤害按【桶】对账: 小龟本体还有不归装备的物理伤害(被动龟盾/普攻链), 拦不干净;
	##   所以挑魔法/真伤的装备 —— 敌人在这个桶里的承伤只可能来自这件装备。物理那一路由 A1/B1 的合成段守。
	for case in [["p2eq_004", "mag", "周期弹道(魔法)·fire_equip_effect"], ["p2eq_025", "tru", "延时雷队列·真伤"],
			["p2eq_058", "summon", "召唤物炮台(登场召唤)"], ["p2eq_012", "shield", "周期自护盾·装备 tick"],
			["p2eq_042", "heal", "群体治疗"], ["p2eq_044", "heal", "半血持续回复(多件摊付按份额拆)"],
			## 2026-10-04 第二轮: 由【全局表里的常驻物】驱动、没有单位上下文的几件(原来记 0)
			## ★080 只对魔法桶(炸弹那一段): 物理桶里混着小龟本体不归装备的物理(同上方注释);
			##   且只放一条 —— 直升机在全局表里, 不随 `_dl_clear_units` 撤, 第二条会撞上第一条那架接着炸
			["p2eq_080", "mag", "直升机(全局表·非单位)地毯轰炸(延时队列盖章)"],
			["p2eq_095", "shield", "圣光护盾(全局 3 秒节拍)"],
			["p2eq_071", "cream", "奶油盾(SpecialBalance 余额·不走 _grant_shield)"]]:
		await _real(str(case[0]), str(case[1]), str(case[2]))
	await _tick_owned()

	print("")
	print("断言 %d 条" % _n)
	if _fail == 0 and _n >= 28:
		print("ALL PASS — 装备账: 两条伤害路/治疗/护盾/DoT份额/延时队列/召唤物 都对得上; 换路按本局累加")
	else:
		print("FAIL x%d (断言 %d)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


func _real(iid: String, kind: String, label: String) -> void:
	var st: Array = await _stage(iid, true)
	var u: Dictionary = st[0]
	var al: Dictionary = st[1]
	var es: Array = st[2]
	var pre := 0.0
	for e in es:
		pre += float(e.get("_st_taken", 0))
	print("  DBG pre=", pre, " eq=", u.get("_st_eq", {}))
	al["_dbgmark"] = true
	var staged: Array = [u, al]
	staged.append_array(es)
	for k in range(900):
		## 携带者与其余 4 个本体都不放技能、不普攻(技能/普攻本体的伤害不归装备, 会污染「敌人承伤只来自装备」这个分母)
		for x in staged:
			x["atk_cd"] = 999.0   # 场上 5 个本体都不普攻(no_basic 只管召唤物); 装备召出来的东西照打
			x["energy"] = 0.0
			x["basic_enh_t"] = 0.0   # 小龟被动【龟盾】每 6 秒蓄一发强化普攻 —— 不归装备, 压住
		s._sim_step(DT, false, false)
		if k % 4 == 0:
			await get_tree().process_frame
	var taken := 0.0
	for e in es:
		taken += float(e.get("_st_taken", 0))
	var heal: float = float(u.get("_st_heal", 0)) + float(al.get("_st_heal", 0))
	var sh: float = float(u.get("_st_shield", 0)) + float(al.get("_st_shield", 0))
	var sm: Dictionary = {}
	for x in s._units:
		if x.get("is_summon", false) and is_same(x.get("summon_owner", null), u):
			sm = x
	match kind:
		"cream":
			var given := 0.0
			for x in [u, al]:
				given += float(x.get("_cream_given", 0.0))
			_ok("E %s %s: 装备账护盾 == 全队 Σ_cream_given(分母 > 0)" % [iid, label], given > 0.0 and _near(_eqv(u, iid, "shield"), given),
				"账 %.0f / 发放 %.0f" % [_eqv(u, iid, "shield"), given])
		"mag", "tru", "phy":
			var tb := 0.0
			for e in es:
				tb += float((e.get("_st_taken_by_type", {}) as Dictionary).get(kind, 0))
			_ok("E %s %s: 装备账[%s] == Σ敌人该桶承伤(分母 > 0)" % [iid, label, kind], tb > 0.0 and _near(_eqv(u, iid, kind), tb),
				"账 %.0f / 承伤 %.0f" % [_eqv(u, iid, kind), tb])
		"summon":
			var sd: float = float(sm.get("_st_dealt", 0)) if not sm.is_empty() else 0.0
			_ok("E %s %s: 装备账伤害 == 召唤物自己的 _st_dealt(分母 > 0)" % [iid, label], sd > 0.0 and _near(_eqdmg(u, iid), sd),
				"账 %.0f / 召唤物造成 %.0f" % [_eqdmg(u, iid), sd])
		"heal":
			_ok("E %s %s: 装备账治疗 == 我方 Σ_st_heal(分母 > 0)" % [iid, label], heal > 0.0 and _near(_eqv(u, iid, "heal"), heal),
				"账 %.0f / 回血 %.0f" % [_eqv(u, iid, "heal"), heal])
		"shield":
			_ok("E %s %s: 装备账护盾 == 我方 Σ_st_shield(分母 > 0)" % [iid, label], sh > 0.0 and _near(_eqv(u, iid, "shield"), sh),
				"账 %.0f / 获盾 %.0f" % [_eqv(u, iid, "shield"), sh])


## 干净小场: 携带者(3★) + 半血队友 + 3 个高血敌人。mute=true 时双方都不普攻(承伤只可能来自装备)。
func _stage(iid: String, mute: bool) -> Array:
	s._dl_sys._dl_clear_units()
	await get_tree().process_frame
	s._battle_rng.seed = 20261004
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-60, 0))
	u["maxHp"] = 6000.0; u["hp"] = 3000.0; u["atk"] = 120.0; u["no_move"] = true; u["no_basic"] = mute
	var al: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-120, 30))
	al["maxHp"] = 6000.0; al["hp"] = 3000.0; al["no_basic"] = true; al["no_move"] = true
	var es: Array = []
	for i in range(3):
		var e: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2((10.0 if not mute else 330.0) + 50.0 * float(i), -20.0 + 20.0 * float(i)))
		e["maxHp"] = 1.0e6; e["hp"] = 1.0e6; e["no_move"] = true; e["no_basic"] = true
		es.append(e)
	s._units.clear()
	s._units.append(u)
	s._units.append(al)
	s._units.append_array(es)
	s._edit_mode = false
	s._over = false
	u["equips"] = [] if iid == "" else [{"id": iid, "star": 3}]
	u["eq_state"] = {} if iid == "" else {iid: {}}
	s._equip_sys._stats._eq_apply_all_stats()
	return [u, al, es]


func _taken_all(es: Array) -> float:
	var t := 0.0
	for x in es:
		t += float((x as Dictionary).get("_st_taken", 0))
	return t


## ── F. 全局表/常驻物驱动的件(2026-10-04 第二轮接上): 结算函数走真入口直调, 进去之前先把上下文清成「无」——
##   ⇒ 记到的账只可能来自结算函数自己切的上下文(原来这些件就是因为「全局 tick 没有携带者上下文」才记 0)。
##   每条都是对账: 装备账增量 == 目标单位级 `_st_taken` 增量, 且分母 > 0。
func _tick_owned() -> void:
	print("")
	var st: Array = await _stage("", true)
	var u: Dictionary = st[0]
	var al: Dictionary = st[1]
	var e: Dictionary = st[2][0]
	u["eq_state"] = {}
	al["pos"] = e["pos"]   # 碑的友军护盾要在圈里
	var tl = s._equip_sys.tally
	var cases: Array = [
		["p2eq_088", "mag", "潮汐碑一跳(碑在全局表)", func() -> void:
			s._equip_sys._arcane_sys._stele_settle({"src": u, "si": 2, "pos": e["pos"], "dmg": 40.0, "shd": 55.0})],
		["p2eq_089", "mag", "符纸一跳(符纸在全局表)", func() -> void:
			s._equip_sys._arcane_sys._talisman_settle({"src": u, "tgt": e, "si": 2, "per": 66.0})],
		["p2eq_094", "mag", "祖龟碑石雷落地(携带者已阵亡)", func() -> void:
			s._equip_sys._relic_sys.stele_bolt_land({"carrier": u, "tgt": e, "si": 2})],
		["p2eq_055", "phy", "钩索炸弹每秒一跳(挂在敌人身上)", func() -> void:
			e["hookbomb_pct"] = 0.0001
			e["hookbomb_src"] = u
			e["hookbomb_t"] = 0.0
			s._hookbomb_sys._hb_tick(e, 1.0)
			e["hookbomb_pct"] = 0.0
			e["hookbomb_src"] = null],
		["p2eq_038", "mag", "电磁波命中(波在全局在途表)", func() -> void:
			s._equip_sys._sigwave._apply(u, e, 120.0)],
		["p2eq_084", "phy", "十字斩横斩(本系统分段时刻表)", func() -> void:
			u["pos"] = (e["pos"] as Vector2) - Vector2(80, 0)
			s._equip_sys._blade_sys.cross_slash_hit(u, Vector2.RIGHT, 2, 1)],
	]
	for c in cases:
		var iid: String = str(c[0])
		var key: String = str(c[1])
		var t0: float = _taken_all(st[2])
		var a0: float = _eqv(u, iid, key)
		tl.use(null)
		(c[3] as Callable).call()
		var d: float = _taken_all(st[2]) - t0   # AOE(碑/十字斩)会扫到不止一个敌人 ⇒ 对 Σ敌人
		var got: float = _eqv(u, iid, key) - a0
		_ok("F %s %s: 上下文清空后直调结算, 装备账[%s] == 目标承伤增量(分母 > 0)" % [iid, str(c[2]), key], d > 0.0 and _near(got, d),
			"账 %.0f / 承伤 %.0f" % [got, d])
	_ok("F p2eq_088 碑内友军护盾也记给立碑者(分母 > 0)", _eqv(u, "p2eq_088", "shield") > 0.0, "%.0f" % _eqv(u, "p2eq_088", "shield"))
	var sh0: float = _eqv(u, "p2eq_064", "shield")
	u["_bladder_si"] = 1
	tl.use(null)
	s._equip_sys._spirit_sys._ghost_grant(u, 1)
	_ok("F p2eq_064 幽灵护盾(SpecialBalance 余额): 装备账 == 发放量 maxHp×80%(分母 > 0)",
		float(u["maxHp"]) > 0.0 and _near(_eqv(u, "p2eq_064", "shield") - sh0, float(u["maxHp"]) * 0.80),
		"账 %.0f / maxHp %.0f" % [_eqv(u, "p2eq_064", "shield") - sh0, float(u["maxHp"])])
