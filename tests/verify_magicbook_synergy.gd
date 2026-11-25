extends Node
## verify_magicbook_synergy.gd —— 魔法书羁绊【飞弹】(2026-11-25 · 方案书 docs/plans/20261125b-魔法书羁绊.md §4.1)
##
## 用户 11-25:「每释放一次技能…我方所有单位…包括召唤物…召唤一定数量的魔法飞弹…数量等于消耗的龟能除以一个值…按档变化…
##   飞向随机敌人…固定加上目标百分比的魔法伤害」
##   A 门槛 3 / 6 / 10(不同魔法书按 id 去重)
##   B 枚数 = floor(龟能 ÷ 20/15/10), 至少 1 枚; 没耗龟能 / 没档位 ⇒ 0 枚(纯函数 + 实发两边都量)
##   C 每枚按速度飞, 出手那一刻不掉血; 落地每枚（60+目标 2.5% 最大生命值）魔法 ⇒ 10 枚总伤对账
##   D 召唤物放技能(on_cast)也出; 训龟大师不出; 敌方单位放技能用敌方档位(我方 3 档、敌方 0 档 ⇒ 敌方放不出)
##   E 挑目标走对局种子: 同种子两遍逐枚目标序列相同, 换种子不同; 4 个敌人 40 枚每个都挨到(不是只打一个)
##   F 属性: 每件魔法书给携带者增伤(羁绊逐档 3/6/10% × 件数 · 装备属性 dmgAmp 都写进 damage_amp)
##   G 携带者放技能 ⇒ after_cast 同一入口: 魔法书逐件生效 + 飞弹(118 护盾与飞弹同时出现)
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const MS := preload("res://scripts/systems/equip/magicbook_synergy_system.gd")
const MAG := ["p2eq_117", "p2eq_118", "p2eq_119", "p2eq_120", "p2eq_121", "p2eq_122", "p2eq_123", "p2eq_124", "p2eq_125", "p2eq_126"]

var _n := 0
var _fail := 0
var _s


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _mk(side: String, ids: Array, x: float = 0.0, y: float = 0.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("green", side, c + Vector2(x, y))
	for k in ["shield", "flat_dr", "def", "base_def", "mr", "base_mr", "crit", "dodge", "armor_pen", "armor_pen_pct",
			"magic_pen", "magic_pen_pct", "damage_reduction", "damage_amp", "def_shred", "tenacity"]:
		u[k] = 0.0
	u["maxHp"] = 100000.0
	u["hp"] = 100000.0
	u["atk"] = 100.0
	u["airborne"] = false
	var eq: Array = []
	for id in ids:
		eq.append({"id": id, "star": 1})
	u["equips"] = eq
	u["eq_state"] = {}
	return u


func _run(units: Array) -> void:
	_s._equip_sys._magic_sys.clear_all()
	_s._ballistics.clear_flights()
	_s._units.clear()
	_s._units.append_array(units)
	_s._synergy._by_side = {"left": {}, "right": {}}
	_s._synergy.apply_all()
	for u in units:
		u["damage_amp"] = 0.0   # 只量飞弹本身(羁绊增伤属性 F 段单独量)


func _fly(sec: float) -> void:
	for i in range(int(round(sec / 0.05))):
		_s._t = float(_s._t) + 0.05
		_s._ballistics._step_flights(0.05)


func _lost(u: Dictionary) -> float:
	return float(u["maxHp"]) - float(u["hp"])


## 同一种子发 40 枚, 记逐枚挑到的目标下标
func _seq(seed: int) -> Array:
	var me := _mk("left", MAG, -300)
	var foes: Array = []
	for i in range(4):
		foes.append(_mk("right", [], 300, -150 + i * 100))
	_run([me] + foes)
	_s._battle_rng.seed = seed
	var out: Array = []
	var ms = _s._magic_syn
	var f0: int = int(ms.fired)
	ms.on_cast(me, 400.0)
	var fl: Array = _s._ballistics._flights
	for f in fl.slice(fl.size() - (int(ms.fired) - f0)):
		out.append(foes.find(f["tgt"]))
	_fly(2.0)
	var all_hit := true
	for f in foes:
		all_hit = all_hit and _lost(f) > 0.0
	out.append(all_hit)
	return out


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s.set_process(false)
	_s.set_physics_process(false)
	_s._t = 1000.0
	print("=== 魔法书羁绊【飞弹】 ===")
	var ms = _s._magic_syn

	## ── A 门槛 ──
	var got := {}
	for n in [2, 3, 5, 6, 9, 10]:
		_run([_mk("left", MAG.slice(0, n))])
		got[n] = ms.side_tier("left")
	_run([_mk("left", ["p2eq_117", "p2eq_117", "p2eq_117"])])
	var dup: int = ms.side_tier("left")
	_ok("A 门槛 3 / 6 / 10; 同一件带三本不算三种", got[2] == 0 and got[3] == 1 and got[5] == 1 and got[6] == 2 and got[9] == 2 and got[10] == 3 and dup == 0,
		"%s · 三本学徒笔记 %d 档" % [str(got), dup])

	## ── B 枚数 ──
	var pure := [MS.missiles_for(100.0, 1), MS.missiles_for(100.0, 2), MS.missiles_for(100.0, 3), MS.missiles_for(60.0, 1), MS.missiles_for(5.0, 3),
		MS.missiles_for(0.0, 3), MS.missiles_for(100.0, 0)]
	_ok("B 纯函数: 100 龟能 5/6/10 枚 · 60 龟能 1 档 3 枚 · 5 龟能至少 1 枚 · 0 龟能 / 0 档 0 枚", pure == [5, 6, 10, 3, 1, 0, 0], str(pure))
	var me := _mk("left", MAG, -300)
	var foe := _mk("right", [], 300)
	_run([me, foe])
	var f0: int = ms.fired
	ms.on_cast(me, 100.0)
	var fired3: int = ms.fired - f0
	var lost0 := _lost(foe)
	_fly(2.0)
	var each: float = float(MS.DMG_FLAT[2]) + float(MS.DMG_MAXHP[2]) * 100000.0
	_ok("B/C 3 档放 100 龟能技能 ⇒ 实发 10 枚; 出手时不掉血; 落地共 %.0f(每枚 %.0f)" % [each * 10.0, each],
		fired3 == 10 and lost0 == 0.0 and absf(_lost(foe) - each * 10.0) <= 10.0, "发 %d · 出手 %.0f · 落地 %.0f" % [fired3, lost0, _lost(foe)])

	## ── D 召唤物 / 训龟大师 / 敌方档位 ──
	me = _mk("left", MAG, -300)
	foe = _mk("right", [], 300)
	var summon := _mk("left", [], -200)
	summon["is_summon"] = true
	summon["id"] = "_summon_skel_mage"
	var trainer := _mk("left", [], -250)
	trainer["id"] = "__trainer__"
	trainer["is_trainer"] = true
	_run([me, foe, summon, trainer])
	f0 = ms.fired
	ms.on_cast(summon, 80.0)
	var by_summon: int = ms.fired - f0
	f0 = ms.fired
	ms.on_cast(trainer, 80.0)
	var by_trainer: int = ms.fired - f0
	f0 = ms.fired
	ms.on_cast(foe, 100.0)
	var by_foe: int = ms.fired - f0
	_ok("D 召唤物放 80 龟能技能 ⇒ 8 枚; 训龟大师 0; 敌方(0 档)放技能 0", by_summon == 8 and by_trainer == 0 and by_foe == 0,
		"召唤物 %d · 大师 %d · 敌方 %d" % [by_summon, by_trainer, by_foe])

	## ── E 对局种子 ──
	var a := _seq(12345)
	var b := _seq(12345)
	var c := _seq(777)
	var tgts: Array = a.slice(0, a.size() - 1)
	var distinct := {}
	for x in tgts:
		distinct[x] = true
	_ok("E 同种子逐枚目标相同、换种子不同; 40 枚分到 4 个敌人且每个都挨到", a == b and a != c and distinct.size() == 4 and bool(a[a.size() - 1]),
		"%d 枚 · 前 8 枚 %s / 换种子 %s" % [tgts.size(), str(tgts.slice(0, 8)), str(c.slice(0, 8))])

	## ── F 增伤属性 ──
	var amps := []
	for n in [3, 6, 10]:
		var u := _mk("left", MAG.slice(0, n))
		_s._units.clear()
		_s._units.append(u)
		_s._synergy._by_side = {"left": {}, "right": {}}
		u["damage_amp"] = 0.0
		_s._synergy.apply_all()
		amps.append(snappedf(float(u["damage_amp"]), 0.0001))
	var eu := _mk("left", [])
	eu["damage_amp"] = 0.0
	_s._equip_sys._stats.apply_stat_dict(eu, {"dmgAmp": 0.25}, "p2eq_125")
	_ok("F 羁绊每件增伤 3/6/10%(一只龟带 3/6/10 件 ⇒ 9/36/100%, 同炸弹护穿「每件」口径) · 装备属性 dmgAmp 写进 damage_amp", _near(amps[0], 0.09) and _near(amps[1], 0.36) and _near(amps[2], 1.0) and _near(float(eu["damage_amp"]), 0.25),
		"%s · 装备 %.2f" % [str(amps), float(eu["damage_amp"])])

	## ── G 同一入口 ──
	me = _mk("left", MAG.slice(0, 3), -300)   # 117 / 118 / 119 三种 ⇒ 1 档
	foe = _mk("right", [], 300)
	_run([me, foe])
	f0 = ms.fired
	var sk: String = str(me.get("active_skills", [""])[0]) if not me.get("active_skills", []).is_empty() else "basicBarrage"   # 合成单位没有主动技能 ⇒ 借一个技能类型名(按类型兜底消耗)
	ms.after_cast(me, foe, sk)
	_ok("G after_cast: 118 护盾与【飞弹】同时出(1 档, 按 _skill_cost 算枚数)",
		float(me["shield"]) > 0.0 and ms.fired - f0 == MS.missiles_for(float(_s._skill_cost(me, sk)), 1),
		"盾 %.0f · 飞弹 %d(龟能 %.0f)" % [float(me["shield"]), ms.fired - f0, float(_s._skill_cost(me, sk))])

	print("─────────────── %d 项, FAIL %d ───────────────" % [_n, _fail])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)


func _near(a: float, b: float, tol: float = 0.001) -> bool:
	return absf(a - b) <= tol
