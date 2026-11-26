extends Node
## verify_chip_items.gd —— 筹码 10 枚(消耗品)门禁(2026-11-26 · 方案书 docs/plans/20261126b-筹码.md)
##   A 不进三合一: 3 枚同色 1 星放背包 try_merge_all 后还是 3 枚
##   B 打完损坏: 积分赛(ranked_ref)/ 闯关 / 决赛那一笔进账把统领和小将身上的筹码全部拿掉、张数退回卡池, 别的装备不动;
##     其它来源(裁判补发金币 gauntlet_ref)不扣
##   C 效果: 黑 / 紫全队护盾(物理 / 魔法, 携带者最大生命 30%) · 黄控制免疫 · 棕倒地 2.5 秒回到 60% · 金第 8 秒全队护罩 3 秒免伤免持续伤害 + 全队 +25 攻 +25 双抗
##     · 灰攻击或挨打叠层 40 层封顶 · 绿每秒回 1%
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const CB := preload("res://scripts/systems/equip/eq_chip_batch.gd")
const EL := preload("res://scripts/gamedata/econ_ledger.gd")

var _n := 0
var _fail := 0
var _s
var _c


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _mk(side: String, ids: Array = [], dx: float = 0.0, dy: float = 0.0) -> Dictionary:
	var c: Vector2 = _s._arena_center
	var u: Dictionary = _s._spawn._make_unit("green", side, c + Vector2((-150.0 if side == "left" else 150.0) + dx, dy))
	for k in ["shield", "crit", "dodge_bonus", "damage_reduction", "damage_amp", "armor_pen", "armor_pen_pct", "phys_shield", "magic_shield"]:
		u[k] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["maxHp"] = 5000.0
	u["hp"] = 5000.0
	u["base_atk"] = 100.0
	u["buffs"] = []
	_s._recalc_stats(u)
	var eq: Array = []
	for id in ids:
		eq.append({"id": id, "star": 1})
	u["equips"] = eq
	return u


func _field(units: Array) -> void:
	_c.clear_all()
	_s._units.clear()
	_s._units.append_array(units)
	_s._synergy._by_side = {"left": {}, "right": {}}
	for u in units:
		if not (u.get("equips", []) as Array).is_empty():
			_s._equip_sys._stats.apply_unit(u)


func _adv(sec: float, units: Array = [], step: float = 0.05) -> void:
	var t := 0.0
	while t < sec - 1e-6:
		_s._t += step
		_c.tick(step)
		_s._equip_sys._mask_sys.tick(step)
		_s._damage.revive_tick()
		for u in units:
			_c.tick_unit(u, step)
		t += step


func _minion(gs) -> Dictionary:
	for u in gs.get_dual_lineup()["top"]:
		if u is Dictionary and str(u.get("kind", "")) == "minion" and (u as Dictionary).get("equips") is Array and not ((u as Dictionary)["equips"] as Array).is_empty():
			return u
	return {"equips": []}


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	## ── A 不进三合一 ──
	var bench0: Array = (gs.persistent_bench as Array).duplicate(true)
	var eq0: Dictionary = (gs.persistent_equipped as Dictionary).duplicate(true)
	var dl0: Dictionary = (gs.dual_lineup as Dictionary).duplicate(true)
	gs.persistent_bench = [gs.mk_eq("p2eq_147", 1), gs.mk_eq("p2eq_147", 1), gs.mk_eq("p2eq_147", 1)]
	gs.try_merge_all("left")
	var n147 := 0
	for it in gs.persistent_bench:
		if str(it.get("id", "")) == "p2eq_147":
			n147 += 1
	_ok("A 3 枚白色筹码放背包不合成(仍是 3 枚 1 星)", n147 == 3, str(gs.persistent_bench))

	## ── B 打完损坏 ──
	gs.persistent_bench = []
	gs.persistent_equipped = {"green": [gs.mk_eq("p2eq_151", 1), gs.mk_eq("p2eq_001", 2)]}
	var dl: Dictionary = gs.default_dual_lineup().duplicate(true)
	(dl["top"] as Array).append({"kind": "minion", "role": "front", "equips": [gs.mk_eq("p2eq_156", 1), gs.mk_eq("p2eq_003", 1)]})
	gs.dual_lineup = dl
	var left151: int = gs.pool_left("p2eq_151") if gs.has_method("pool_left") else -1
	var r0: Dictionary = EL.apply(gs, {"op": "income", "src": "gauntlet_ref", "coins": 3})
	var still: int = (gs.persistent_equipped["green"] as Array).size() + (_minion(gs)["equips"] as Array).size()
	var r1: Dictionary = EL.apply(gs, {"op": "income", "src": "ranked_ref", "coins": 4, "xp": 2, "axe": true, "candy": 1})
	var leader_ids: Array = []
	for it in gs.persistent_equipped["green"]:
		leader_ids.append(str(it["id"]))
	var minion_ids: Array = []
	for it in _minion(gs)["equips"]:
		minion_ids.append(str(it["id"]))
	var left151b: int = gs.pool_left("p2eq_151") if gs.has_method("pool_left") else -1
	_ok("B 裁判补发金币(gauntlet_ref)不扣 · 积分赛那一笔扣掉统领和小将身上的筹码(别的装备留着), 张数退回卡池",
		still == 4 and int(r1.get("burned", 0)) == 2 and leader_ids == ["p2eq_001"] and minion_ids == ["p2eq_003"] and (left151 < 0 or left151b == left151 + 1),
		"不扣时 %d 件 · 烧 %d · 统领 %s · 小将 %s · 卡池 %d→%d" % [still, int(r1.get("burned", 0)), str(leader_ids), str(minion_ids), left151, left151b])
	gs.persistent_bench = bench0
	gs.persistent_equipped = eq0
	gs.dual_lineup = dl0

	## ── C 效果 ──
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s.set_process(false)
	_s.set_physics_process(false)
	_s._t = 4000.0
	_s._sd_t0 = _s._t
	_c = _s._equip_sys._chip_sys
	print("=== 筹码 10 枚 ===")

	var me := _mk("left", ["p2eq_151", "p2eq_152"])
	var ally := _mk("left", [], 0.0, 150.0)
	_field([me, ally, _mk("right")])
	var want: float = float(me["maxHp"]) * CB.SHIELD_PCT
	_ok("C 黑 + 紫: 全队各得物理护盾和魔法护盾 = 携带者最大生命 30%%(%.0f)" % want,
		absf(float(ally["phys_shield"]) - want) < 1.0 and absf(float(ally["magic_shield"]) - want) < 1.0 and absf(float(me["phys_shield"]) - want) < 1.0,
		"队友 物 %.0f 魔 %.0f" % [float(ally["phys_shield"]), float(ally["magic_shield"])])

	me = _mk("left", ["p2eq_153"])
	var foe := _mk("right")
	_field([me, foe])
	_s._damage._stun(me, 2.0, "test")
	_ok("C 黄: 整个战场控制免疫(眩晕打不上)", float(me.get("stun_until", 0.0)) <= _s._t, str(me.get("stun_until", 0.0)))
	## 11-27 自查补: 挡掉的控制记进这一枚的装备统计「免疫控制 N 次」(原来面板只写「整场免控」, 看不出它真挡了)
	var cc153 := 0.0
	var st_eq: Dictionary = me.get("_st_eq", {})
	for k in st_eq:
		if str(k).begins_with("p2eq_153"):
			cc153 += float((st_eq[k] as Dictionary).get("cc_block", 0.0))
	_ok("C 黄: 挡掉一次眩晕 ⇒ 装备统计「免疫控制」记 1 次", is_equal_approx(cc153, 1.0), str(st_eq))

	me = _mk("left", ["p2eq_154"])
	foe = _mk("right")
	_field([me, foe])
	me["hp"] = 100.0
	_s._damage._apply_damage_from(foe, me, 999, Color.WHITE, 0.0, true)
	var alive_after: bool = bool(me.get("alive", false))
	_adv(2.6)
	_ok("C 棕: 致命一击倒地不死, 2.5 秒后回到 60%% 最大生命", alive_after and absf(float(me["hp"]) - 0.6 * float(me["maxHp"])) < 2.0, "活 %s · 生命 %.0f / %.0f" % [str(alive_after), float(me["hp"]), float(me["maxHp"])])

	me = _mk("left", ["p2eq_155"])
	ally = _mk("left", [], 0.0, 150.0)
	foe = _mk("right")
	_field([me, ally, foe])
	_s._sd_t0 = _s._t
	var atk0 := float(ally["base_atk"])
	_adv(7.9)
	var before: bool = float(ally.get("_gold_guard_until", 0.0)) > _s._t
	_adv(0.15)
	var hp0 := float(ally["hp"])
	_s._damage._apply_damage_from(foe, ally, 500, Color.WHITE, 0.0, true)
	_s._damage._apply_dot_stacks(ally, "burn", 30, foe)
	var took := hp0 - float(ally["hp"])
	var dots := int((ally.get("dot_stacks", {}) as Dictionary).get("burn", 0))
	_adv(3.1)
	hp0 = float(ally["hp"])
	_s._damage._apply_damage_from(foe, ally, 500, Color.WHITE, 0.0, true)
	_ok("C 金: 第 8 秒(7.9 秒还没有)全队护罩 3 秒: 真伤 500 吃 0、灼烧不上层; 3 秒后照常挨打; 全队 +25 攻击",
		not before and took == 0.0 and dots == 0 and hp0 - float(ally["hp"]) > 0.0 and absf(float(ally["base_atk"]) - atk0 - 25.0) < 1e-3,
		"罩内 %.0f · 灼烧 %d 层 · 罩后 %.0f · 攻 +%.0f" % [took, dots, hp0 - float(ally["hp"]), float(ally["base_atk"]) - atk0])

	me = _mk("left", ["p2eq_156"])
	foe = _mk("right")
	_field([me, foe])
	var hpmax0 := float(me["maxHp"])
	for _i in range(25):
		_s._basic_attack(me, foe)
	for _i in range(25):
		_s._damage._apply_damage_from(foe, me, 1, Color.WHITE)
	_ok("C 灰: 攻击 25 次 + 挨打 25 次 ⇒ 封顶 40 层: +80 攻 +80 双抗 +800 最大生命, 满层 +10%% 增伤减伤",
		int(me["_grey_stk"]) == 40 and absf(float(me["maxHp"]) - hpmax0 - 800.0) < 1e-3 and absf(float(me["damage_amp"]) - 0.10) < 1e-6
		and absf(float(me["damage_reduction"]) - 0.10) < 1e-6, "层 %d · 生命 +%.0f · 增伤 %.2f" % [int(me["_grey_stk"]), float(me["maxHp"]) - hpmax0, float(me["damage_amp"])])

	me = _mk("left", ["p2eq_150"])
	_field([me, _mk("right")])
	me["hp"] = 2000.0
	_adv(2.0, [me])
	_ok("C 绿: 2 秒回 2%% 最大生命(约 %.0f)" % (0.02 * float(me["maxHp"])), absf(float(me["hp"]) - 2000.0 - 0.02 * float(me["maxHp"])) < 5.0, "%.0f" % (float(me["hp"]) - 2000.0))

	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 筹码 10 枚 (%d 条)" % _n)
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
