extends Node
## verify_holy_spear.gd —— 146 圣枪重做(11-26 晚用户设计 · 方案书 docs/plans/20261126c-圣枪重做.md §6)
##   ① 每路首次低于 50% ⇒ 圣枪护盾(星级 × 最大生命) + 双抗; 再跌破不再给
##   ② 普通 / 魔法 / 物理护盾都存进储能, 封顶 100% 最大生命
##   ③ 每 12 秒引导, 每 0.25 秒耗一份储能出一个光球, 不够一个就结束
##   ④ 友方光球: 临时等级 +1(+5% 基础) + 回血; 敌方光球: 魔法伤害 + 携带者护盾(回存储能)
##   ⑤ 候选: 友方只有统领 / 小将(含自己), 不含召唤物 / 龟蛋; 敌方含召唤物
##   ⑥ 温泉蛋 + 圣枪临时等级: 攻速按总等级算, 基础属性线性叠加
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SB := preload("res://scripts/systems/equip/eq_spear_batch.gd")

var _n := 0
var _fail := 0
var _s
var _b


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _mk(side: String, ids: Array = [], dx: float = 0.0, star: int = 1) -> Dictionary:
	var c: Vector2 = _s._arena_center
	var u: Dictionary = _s._spawn._make_unit("green", side, c + Vector2((-150.0 if side == "left" else 150.0) + dx, 0.0))
	for k in ["shield", "crit", "dodge_bonus", "damage_reduction", "damage_amp", "armor_pen", "armor_pen_pct", "magic_pen", "magic_pen_pct"]:
		u[k] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["maxHp"] = 5000.0
	u["hp"] = 5000.0
	u["base_atk"] = 100.0
	u["buffs"] = []
	u["airborne"] = false
	_s._recalc_stats(u)
	var eq: Array = []
	for id in ids:
		eq.append({"id": id, "star": star})
	u["equips"] = eq
	return u


func _field(units: Array) -> void:
	_b.clear_all()
	_s._units.clear()
	_s._units.append_array(units)
	_s._synergy._by_side = {"left": {}, "right": {}}
	for u in units:
		if not (u.get("equips", []) as Array).is_empty():
			_s._equip_sys._stats.apply_unit(u)
		u["_holy_store"] = {}


func _adv(sec: float, units: Array = [], step: float = 0.05) -> void:
	var t := 0.0
	while t < sec - 1e-6:
		_s._t += step
		_b.tick(step)
		for u in units:
			_b.tick_unit(u, step)
		_s._ballistics._step_flights(step)
		t += step


func _store(u: Dictionary) -> float:
	return SB.holy_stored(u, "p2eq_146")


func _zero_stats() -> void:
	for k in _b.stat:
		_b.stat[k] = 0


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s.set_process(false)
	_s.set_physics_process(false)
	_s._t = 3000.0
	_b = _s._equip_sys._spear_sys
	print("=== 146 圣枪 ===")

	## ① 首次半血
	var me := _mk("left", ["p2eq_146"])
	_field([me])
	_zero_stats()
	var mx := float(me["maxHp"])
	var def0 := float(me["def"])
	var mr0 := float(me["mr"])
	me["hp"] = mx * 0.49
	_adv(0.05, [me])
	var want_sh: float = mx * float(SB.HOLY_GUARD_PCT[0])
	var part: float = want_sh / float(SB.HOLY_GUARD_SEC)
	_ok("① 首次低于 50%: 当场给第 1 份圣枪护盾(合计 40% 最大生命 ÷ 4) + 护甲 / 魔抗各 +30",
		int(_b.stat["holy_guard"]) == 1 and int(_b.stat["holy_guard_part"]) == 1 and absf(float(me["shield"]) - part) < 1.0
		and absf(float(me["def"]) - def0 - 30.0) < 0.01 and absf(float(me["mr"]) - mr0 - 30.0) < 0.01,
		"盾 %.0f(应 %.0f) · 护甲 +%.1f · 魔抗 +%.1f" % [float(me["shield"]), part, float(me["def"]) - def0, float(me["mr"]) - mr0])
	_ok("① 圣枪护盾记在独立标记上(血条画金色段)", absf(float(me.get("_spearShieldVal", 0.0)) - part) < 1.0, "标记 %.0f" % float(me.get("_spearShieldVal", 0.0)))
	_adv(0.9, [me])
	var at1 := int(_b.stat["holy_guard_part"])
	_adv(0.2, [me])
	var at2 := int(_b.stat["holy_guard_part"])
	_adv(2.5, [me])
	_ok("① 之后每秒一份: 0.95 秒时还是 1 份、1.15 秒时 2 份、给满 4 份停住, 合计 = 40% 最大生命",
		at1 == 1 and at2 == 2 and int(_b.stat["holy_guard_part"]) == SB.HOLY_GUARD_SEC and absf(float(me["shield"]) - want_sh) < 1.0
		and absf(float(me.get("_spearShieldVal", 0.0)) - want_sh) < 1.0,
		"%d → %d → %d 份 · 盾 %.0f(应 %.0f)" % [at1, at2, int(_b.stat["holy_guard_part"]), float(me["shield"]), want_sh])
	_ok("① 圣枪护盾本身也存进储能", absf(_store(me) - want_sh) < 1.0, "储能 %.0f" % _store(me))
	_s._damage._apply_damage(me, int(want_sh * 0.5), Color.WHITE)
	ShieldSynergySystem.converge_marks([me])
	_ok("① 护盾被打掉一半: 标记跟着收敛, 不超过剩下的护盾", float(me.get("_spearShieldVal", 0.0)) <= float(me["shield"]) + 0.01 and float(me["shield"]) < want_sh,
		"标记 %.0f · 护盾 %.0f" % [float(me.get("_spearShieldVal", 0.0)), float(me["shield"])])
	me["hp"] = mx * 0.8
	_adv(0.05, [me])
	me["hp"] = mx * 0.2
	_adv(0.05, [me])
	_ok("① 同一路再跌破 50% 不再给", int(_b.stat["holy_guard"]) == 1 and int(_b.stat["holy_guard_part"]) == SB.HOLY_GUARD_SEC, "触发 %d 次" % int(_b.stat["holy_guard"]))

	## ② 三种护盾都存, 封顶最大生命
	me = _mk("left", ["p2eq_146"])
	_field([me])
	_s._damage._grant_shield(me, 100.0)
	var s1 := _store(me)
	var ms: float = MagicShield.seaweed_on_spawn(_s, me, 0)
	var s2 := _store(me)
	var ps0 := float(me.get("phys_shield", 0.0))
	_s._equip_sys._mask_sys.on_spawn(me, "p2eq_127", 0)
	var pgot := float(me.get("phys_shield", 0.0)) - ps0
	var s3 := _store(me)
	_ok("② 普通护盾存进储能", absf(s1 - 100.0) < 0.01, "%.1f" % s1)
	_ok("② 魔法护盾存进储能", ms > 0.0 and absf(s2 - s1 - ms) < 0.01, "+%.1f(魔法盾 %.1f)" % [s2 - s1, ms])
	_ok("② 物理护盾存进储能", pgot > 0.0 and absf(s3 - s2 - pgot) < 0.01, "+%.1f(物理盾 %.1f)" % [s3 - s2, pgot])
	_s._damage._grant_shield(me, 99999.0)
	_ok("② 储能封顶 100% 最大生命", absf(_store(me) - float(me["maxHp"])) < 0.01, "%.0f / %.0f" % [_store(me), float(me["maxHp"])])

	## ③ 引导节奏: 1100 储能 / 一星 500 一个 ⇒ 两个光球, 剩 100 结束
	me = _mk("left", ["p2eq_146"])
	_field([me])
	_zero_stats()
	me["_holy_store"] = {"p2eq_146": 1100.0}
	_adv(11.9, [me])
	_ok("③ 12 秒前不引导", int(_b.stat["holy_orb"]) == 0, "光球 %d" % int(_b.stat["holy_orb"]))
	_adv(0.15, [me])
	var first := int(_b.stat["holy_orb"])
	_adv(0.25, [me])
	var second := int(_b.stat["holy_orb"])
	_adv(1.0, [me])
	_ok("③ 第 12 秒开始引导: 先出 1 个, 0.25 秒后第 2 个, 不够 500 就停",
		first == 1 and second == 2 and int(_b.stat["holy_orb"]) == 2 and absf(_store(me) - 100.0) < 0.01 and int(_b.stat["holy_channel"]) == 1,
		"%d → %d → %d · 剩 %.0f" % [first, second, int(_b.stat["holy_orb"]), _store(me)])

	## ④a 友方光球(场上只有自己 ⇒ 必砸自己): 临时等级 +1, +5% 基础, 回 150
	me = _mk("left", ["p2eq_146"])
	_field([me])
	_zero_stats()
	var mx0 := float(me["maxHp"])
	var atk0 := float(me["base_atk"])
	me["hp"] = mx0 * 0.6
	var hp0 := float(me["hp"])
	me["_holy_store"] = {"p2eq_146": 500.0}
	_adv(12.0, [me])
	_adv(1.0, [me])
	var gain: float = mx0 * 0.05
	_ok("④ 友方光球: 临时等级 +1(基础攻击 / 最大生命 +5%) 并回复 150",
		int(_b.stat["holy_ally"]) == 1 and int(me.get("_holy_lv", 0)) == 1 and absf(float(me["base_atk"]) - atk0 * 1.05) < 0.01
		and absf(float(me["maxHp"]) - mx0 - gain) < 0.01 and absf(float(me["hp"]) - hp0 - gain - 150.0) < 0.01,
		"等级 %d · 攻 %.1f · 血 +%.1f(应 +%.1f)" % [int(me.get("_holy_lv", 0)), float(me["base_atk"]), float(me["hp"]) - hp0, gain + 150.0])
	_ok("④ 等级框显示等级算上圣枪临时等级", int(_s._effective_level(me)) == int(me.get("level", 1)) + 1,
		"显示 %d · 基础 %d" % [int(_s._effective_level(me)), int(me.get("level", 1))])

	## ④b 敌我都有: 魔法伤害 + 护盾回存(三星 300 一个, 储能给满 ⇒ 一次引导十几个)
	me = _mk("left", ["p2eq_146"], 0.0, 3)
	var foe := _mk("right")
	_field([me, foe])
	foe["maxHp"] = 500000.0
	foe["hp"] = 500000.0   # 别让它中途被打死(死了后面的光球就砸不到敌方)
	_zero_stats()
	_s._battle_rng.seed = 4321
	me["_holy_store"] = {"p2eq_146": float(me["maxHp"])}
	var store0 := float(me["maxHp"])
	var foe_hp0 := float(foe["hp"])
	var sh_got0 := float(me.get("_st_shield", 0.0))
	_adv(12.0, [me, foe])
	_adv(11.0, [me, foe])   # 满储能 + 回存能连放三十多个(约 9 秒); 停在下一次引导(第 24 秒)之前
	var ne := int(_b.stat["holy_enemy"])
	var na := int(_b.stat["holy_ally"])
	var dmg_each: float = float(SB.HOLY_ORB_DMG[2])
	_ok("④ 敌方光球: 每个造成 500 魔法伤害(对方魔抗 0)", ne > 0 and absf(foe_hp0 - float(foe["hp"]) - dmg_each * float(ne)) < 1.0 + float(ne),
		"命中敌方 %d 个 · 掉血 %.0f(应 %.0f)" % [ne, foe_hp0 - float(foe["hp"]), dmg_each * float(ne)])
	_ok("④ 敌方光球给携带者护盾 200 / 个", absf(float(me.get("_st_shield", 0.0)) - sh_got0 - float(SB.HOLY_ORB_SHIELD[2]) * float(ne)) < 1.0,
		"获盾 %.0f(应 %.0f)" % [float(me.get("_st_shield", 0.0)) - sh_got0, float(SB.HOLY_ORB_SHIELD[2]) * float(ne)])
	_ok("④ 光球都落了地: 友方 + 敌方 = 发出的个数, 且两种都出现过",
		ne + na == int(_b.stat["holy_orb"]) and na > 0 and ne > 0, "发 %d · 友 %d · 敌 %d" % [int(_b.stat["holy_orb"]), na, ne])
	var spent: float = float(int(_b.stat["holy_orb"])) * float(SB.HOLY_ORB_COST[2])
	var back: float = float(SB.HOLY_ORB_SHIELD[2]) * float(ne)
	_ok("④ 敌方给的护盾回存储能: 剩余 = 初始 − 消耗 + 回存, 且引导结束时不够一个光球",
		absf(_store(me) - (store0 - spent + back)) < 1.0 and _store(me) < float(SB.HOLY_ORB_COST[2]) and spent > store0,
		"初始 %.0f · 消耗 %.0f · 回存 %.0f · 剩 %.0f" % [store0, spent, back, _store(me)])

	## ⑤ 候选
	me = _mk("left", ["p2eq_146"])
	var minion := _mk("left", [], -60.0)
	minion["minion_kind"] = "front"
	var summon := _mk("left", [], -90.0)
	summon["is_summon"] = true
	var egg := _mk("left", [], -120.0)
	egg["_isEgg"] = true
	var foe_s := _mk("right")
	foe_s["is_summon"] = true
	_field([me, minion, summon, egg, foe_s])
	var pool: Array = _b.holy_pool(me)
	var has := func(x) -> bool:
		for o in pool:
			if is_same(o, x):
				return true
		return false
	_ok("⑤ 候选含自己 / 友方小将 / 敌方召唤物, 不含友方召唤物 / 龟蛋",
		has.call(me) and has.call(minion) and has.call(foe_s) and not has.call(summon) and not has.call(egg) and pool.size() == 3,
		"候选 %d 个" % pool.size())

	## ⑥ 温泉蛋 + 圣枪: 攻速按总等级, 基础属性线性
	var u := _mk("left", ["p2eq_146"])
	_field([u])
	var iv0 := float(u["atk_interval"])
	var a0 := float(u["base_atk"])
	_s._equip_tick_sys.holy_level_up(u)
	_s._equip_tick_sys.holy_level_up(u)
	_s._equip_tick_sys._egg_replay_levels(u, 1)
	_ok("⑥ 圣枪 2 级 + 温泉蛋 1 级: 攻击间隔 = 基准 / (1 + 2% × 3), 基础攻击 = 基准 × (1 + 5% × 3)",
		absf(float(u["atk_interval"]) - iv0 / 1.06) < 1e-4 and absf(float(u["base_atk"]) - a0 * 1.15) < 0.01,
		"间隔 %.4f(应 %.4f) · 攻 %.2f(应 %.2f)" % [float(u["atk_interval"]), iv0 / 1.06, float(u["base_atk"]), a0 * 1.15])

	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 146 圣枪 (%d 条)" % _n)
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
