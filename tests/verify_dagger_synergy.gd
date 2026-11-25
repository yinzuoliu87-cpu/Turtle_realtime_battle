extends Node
## verify_dagger_synergy.gd —— 匕首羁绊【刺杀】(2026-11-25 · 方案书 docs/plans/20261125-匕首羁绊.md §4.1)
##   A 门槛 3 / 6 / 10(不同匕首按 id 去重; 005 双生匕首算匕首、不再算剑)
##   B 一档: 开打那一刻全队挂强化; 第 10 秒不再挂。二档: 第 10 秒再挂一次。三档: 第 20 秒再挂一次。同一路不重复
##   C 强化击: 暴击率 0 也必暴击, 暴击伤害 = 原暴伤 + 额外(一档 25%), 额外吸血 20%; 普攻打出后清掉(真走 _basic_attack)
##   D 龟蛋 / 训龟大师不挂; 换路重新计时
##   E 「仪式」单档: 带 1 件仪式匕首就激活
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const DS := preload("res://scripts/systems/equip/dagger_synergy_system.gd")
const DAG := ["p2eq_005", "p2eq_108", "p2eq_109", "p2eq_110", "p2eq_111", "p2eq_112", "p2eq_113", "p2eq_114", "p2eq_115", "p2eq_116"]

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


func _mk(side: String, ids: Array, dx: float = 0.0, kind: String = "green") -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(kind, side, c + Vector2((-200.0 if side == "left" else 200.0) + dx, 0.0))
	for k in ["shield", "flat_dr", "def", "base_def", "mr", "base_mr", "crit", "dodge", "armor_pen", "armor_pen_pct", "damage_reduction", "damage_amp"]:
		u[k] = 0.0
	u["maxHp"] = 100000.0
	u["hp"] = 100000.0
	u["airborne"] = false
	var eq: Array = []
	for id in ids:
		eq.append({"id": id, "star": 1})
	u["equips"] = eq
	return u


func _run(units: Array) -> void:
	_s._units.clear()
	_s._units.append_array(units)
	_s._synergy._by_side = {"left": {}, "right": {}}
	_s._synergy.apply_all()
	_s._dagger_syn.reset_match()


func _at(t0: float, el: float) -> void:
	_s._sd_t0 = t0
	_s._t = t0 + el
	_s._dagger_syn.tick(0.0)


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s.set_process(false)
	_s.set_physics_process(false)
	print("=== 匕首羁绊【刺杀】 ===")

	## ── A 门槛 ──
	var got := {}
	for n in [2, 3, 5, 6, 9, 10]:
		_run([_mk("left", DAG.slice(0, n))])
		got[n] = _s._dagger_syn.side_tier("left")
	_ok("A ★门槛 3 / 6 / 10(含 005 双生匕首)", got[2] == 0 and got[3] == 1 and got[5] == 1 and got[6] == 2 and got[9] == 2 and got[10] == 3, str(got))
	_run([_mk("left", ["p2eq_001", "p2eq_003", "p2eq_005"])])
	_ok("A 005 不再算剑(剑 2 件 ⇒ 剑羁绊 0 档)", int(_s._synergy.tier_for(_s._units[0], "剑")) == 0, str(_s._synergy.tier_for(_s._units[0], "剑")))

	## ── B 触发时刻 ──
	var me := _mk("left", DAG.slice(0, 3))
	var ally := _mk("left", [], 60.0)
	var foe := _mk("right", [])
	_run([me, ally, foe])
	_at(5000.0, 0.0)
	var r0 := float(me.get("_assassin_ready", 0.0))
	var ra := float(ally.get("_assassin_ready", 0.0))
	var rf := float(foe.get("_assassin_ready", 0.0))
	me.erase("_assassin_ready"); ally.erase("_assassin_ready")
	_at(5000.0, 10.5)
	_ok("B 一档: 开打即全队挂强化(额外暴伤 %.0f%%), 敌方不挂; 第 10 秒不再挂" % (DS.EXTRA_CRIT_DMG[0] * 100.0),
		absf(r0 - DS.EXTRA_CRIT_DMG[0]) < 1e-6 and absf(ra - DS.EXTRA_CRIT_DMG[0]) < 1e-6 and rf == 0.0 and not me.has("_assassin_ready"),
		"%.2f / %.2f / 敌 %.2f / 10 秒 %s" % [r0, ra, rf, str(me.get("_assassin_ready"))])
	me = _mk("left", DAG.slice(0, 6))
	_run([me])
	_at(6000.0, 0.0)
	me.erase("_assassin_ready")
	_at(6000.0, 9.9)
	var pre10 := me.has("_assassin_ready")
	_at(6000.0, 10.0)
	var r10 := float(me.get("_assassin_ready", 0.0))
	me.erase("_assassin_ready")
	_at(6000.0, 25.0)
	_ok("B 二档: 第 10 秒再挂一次(9.9 秒还没有), 额外暴伤 %.0f%%; 不会第三次" % (DS.EXTRA_CRIT_DMG[1] * 100.0),
		not pre10 and absf(r10 - DS.EXTRA_CRIT_DMG[1]) < 1e-6 and not me.has("_assassin_ready"), "%s / %.2f / %s" % [str(pre10), r10, str(me.has("_assassin_ready"))])
	me = _mk("left", DAG)
	_run([me])
	_at(7000.0, 0.0); me.erase("_assassin_ready")
	_at(7000.0, 10.0); me.erase("_assassin_ready")
	_at(7000.0, 20.0)
	var r20 := float(me.get("_assassin_ready", 0.0))
	_ok("B 三档: 第 20 秒第三次, 额外暴伤 %.0f%%" % (DS.EXTRA_CRIT_DMG[2] * 100.0), absf(r20 - DS.EXTRA_CRIT_DMG[2]) < 1e-6, "%.2f" % r20)

	## ── C 强化击 ──
	me = _mk("left", DAG.slice(0, 3))
	foe = _mk("right", [])
	_run([me, foe])
	me["crit"] = 0.0
	me["crit_dmg"] = 1.5
	me["atk"] = 100.0
	_at(8000.0, 0.0)
	DS.begin_basic(me)
	var dmg_c: int = _s._resolve_dmg(me, 100.0, foe, false)
	var crit_c: bool = bool(_s._last_atk_crit)
	var ls_c: float = DS.extra_ls(me)
	_s._dagger_syn.end_basic(me, foe)
	var dmg_n: int = _s._resolve_dmg(me, 100.0, foe, false)
	_ok("C 暴击率 0 也必暴击: 100 ⇒ %.0f(1.5 + 0.25 暴伤), 吸血 +%.0f%%; 打完清掉、下一下回到 100" % [100.0 * (1.5 + DS.EXTRA_CRIT_DMG[0]), DS.LIFESTEAL * 100.0],
		crit_c and dmg_c == int(round(100.0 * (1.5 + DS.EXTRA_CRIT_DMG[0]))) and absf(ls_c - DS.LIFESTEAL) < 1e-6 and dmg_n == 100 and not me.has("_assassin_now"),
		"%d · 暴击 %s · 吸血 %.2f · 之后 %d" % [dmg_c, str(crit_c), ls_c, dmg_n])
	## 真走一遍主场景普攻: 强化被消费
	me["_assassin_ready"] = DS.EXTRA_CRIT_DMG[0]
	var st0: int = _s._dagger_syn.struck
	_s._basic_attack(me, foe)
	_ok("C 主场景 _basic_attack 消费强化(ready 清掉、打出次数 +1、now 不残留)",
		not me.has("_assassin_ready") and not me.has("_assassin_now") and _s._dagger_syn.struck == st0 + 1, "struck %d → %d" % [st0, _s._dagger_syn.struck])

	## ── D 龟蛋 / 训龟大师 / 换路 ──
	me = _mk("left", DAG.slice(0, 3))
	var egg := _mk("left", [], 120.0)
	egg["_isEgg"] = true
	_run([me, egg])
	_at(9000.0, 0.0)
	var egg_r := egg.has("_assassin_ready")
	me.erase("_assassin_ready")
	_at(9500.0, 0.0)
	_ok("D 龟蛋不挂; 换路(开打时刻变了)重新计时 ⇒ 新一路开打再挂", not egg_r and me.has("_assassin_ready"), "蛋 %s · 新路 %s" % [str(egg_r), str(me.has("_assassin_ready"))])

	## ── E 仪式 ──
	_run([_mk("left", ["p2eq_114"])])
	_ok("E 带 1 件仪式匕首 ⇒「仪式」激活(单档)", int(_s._synergy.tier_for(_s._units[0], "仪式")) == 1, str(_s._synergy.tier_for(_s._units[0], "仪式")))

	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 匕首羁绊【刺杀】 (%d 条)" % _n)
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
