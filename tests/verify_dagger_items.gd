extends Node
## verify_dagger_items.gd —— 匕首 9 件逐件结算(2026-11-25 · 方案书 docs/plans/20261125-匕首羁绊.md §4.2)
##
## 只验结算(不依赖演出): 干净合成单位(护甲 / 魔抗 / 减伤 / 闪避 0, 出手方暴击 0), 时钟手动推进 `_t`,
##   直接调批系统的 tick_unit / tick / on_basic / on_hit / on_kill / on_spawn。数字一律从 EqDaggerBatch 常量算期望值。
##   108 折叠小刀: 第一次攻击附带 210 层流血; 第二次不再给
##   109 柳叶飞刀: 第 6 秒朝最远的敌人射, 命中途经的第一个(挡在中间的那个)挨（120+60% 攻击）魔法, 最远的不挨; 5.9 秒还没射
##   110 苦无: 第 5 秒掷 5 枚, 每枚（40+20% 攻击）魔法 + 自身回 30
##   111 毒牙: 暴击 ⇒ 中毒层数 = 80% 攻击力; 不暴击不给
##   112 三棱刺: 登场 ⇒ 百分比破甲 +45%
##   113 弯匕: 击杀 ⇒ 3 秒内攻速 ×2.5
##   114 仪式匕首: 目标 9% 血 ⇒ 斩杀; 11% 不斩; 击杀 ⇒ 血契 +1、携带者攻击 +2.5、护穿 +0.6; 同一下击杀两件只刻一次
##   115 暗影匕首: 召唤 8000 血 / 450 攻 / 90 双抗 / 50% 暴击、登场隐身; 影袭闪到最低血比例敌人身后、250% 必暴击;
##       首次 ≤50% ⇒ 分出影子(4000 血 / 225 攻, 20 秒后消散); 影子在场时影袭 ⇒ 两枚手里剑
##   116 黑曜石: 暴击插一把; 不够杀不拔; 够杀 ⇒ 全拔、目标死、携带者每把回 300
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const D := preload("res://scripts/systems/equip/eq_dagger_batch.gd")

var _n := 0
var _fail := 0
var _s
var _ds


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _mk(side: String, pos: Vector2, ids: Array = [], star: int = 3, hp: float = 100000.0, atk: float = 100.0) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("green", side, pos)
	u["maxHp"] = hp
	u["hp"] = hp
	u["atk"] = atk
	u["base_atk"] = atk
	for k in ["shield", "flat_dr", "def", "base_def", "mr", "base_mr", "crit", "dodge", "armor_pen", "armor_pen_pct",
			"magic_pen", "magic_pen_pct", "damage_reduction", "damage_amp", "def_shred", "tenacity"]:
		u[k] = 0.0
	u["airborne"] = false
	var eq: Array = []
	for id in ids:
		eq.append({"id": id, "star": star})
	u["equips"] = eq
	u["eq_state"] = {}
	return u


func _c() -> Vector2:
	return _s.ARENA.position + _s.ARENA.size * 0.5


func _place(units: Array) -> void:
	_ds.clear_all()
	_s._units.clear()
	_s._units.append_array(units)


func _adv(sec: float, carriers: Array = []) -> void:
	var steps := int(round(sec / 0.05))
	for i in range(steps):
		_s._t = float(_s._t) + 0.05
		for u in carriers:
			_ds.tick_unit(u, 0.05)
		_ds.tick(0.05)


func _lost(u: Dictionary) -> float:
	return float(u["maxHp"]) - float(u["hp"])


func _near(a: float, b: float, tol: float = 1.5) -> bool:
	return absf(a - b) <= tol


func _stk(u: Dictionary, k: String) -> int:
	return int((u.get("dot_stacks", {}) as Dictionary).get(k, 0)) if u.get("dot_stacks") is Dictionary else 0


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s.set_process(false)
	_s.set_physics_process(false)
	_ds = _s._equip_sys._dagger_sys
	_s._t = 1000.0
	print("=== 匕首 9 件逐件结算 ===")
	var c := _c()

	## ── 108 折叠小刀 ──
	var me := _mk("left", c + Vector2(-60, 0), ["p2eq_108"])
	var t1 := _mk("right", c + Vector2(60, 0))
	_place([me, t1])
	_ds.on_basic(me, t1, "p2eq_108", 2)
	var b1 := _stk(t1, "bleed")
	_ds.on_basic(me, t1, "p2eq_108", 2)
	var b2 := _stk(t1, "bleed")
	_ok("108 第一次攻击附带 %d 层流血, 第二次不再给" % int(D.FOLD_BLEED[2]), b1 == int(D.FOLD_BLEED[2]) and b2 == b1, "%d → %d" % [b1, b2])

	## ── 109 柳叶飞刀 ──
	me = _mk("left", c + Vector2(-300, 0), ["p2eq_109"])
	var mid := _mk("right", c + Vector2(0, 0))
	var far := _mk("right", c + Vector2(400, 0))
	_place([me, mid, far])
	_adv(5.9, [me])
	var early: int = int(_ds.stat["knife"])
	_adv(2.0, [me])
	var w109: float = float(D.KNIFE_FLAT[2]) + D.KNIFE_ATK * 100.0
	_ok("109 第 6 秒射(5.9 秒没射); 挡在中间的挨 %.0f 魔法, 最远的不挨" % w109,
		early == 0 and int(_ds.stat["knife"]) == 1 and _near(_lost(mid), w109) and _lost(far) == 0.0,
		"早 %d · 射 %d · 中 %.0f · 远 %.0f" % [early, int(_ds.stat["knife"]), _lost(mid), _lost(far)])

	## ── 110 苦无 ──
	me = _mk("left", c + Vector2(-200, 0), ["p2eq_110"])
	me["hp"] = 50000.0
	t1 = _mk("right", c + Vector2(200, 0))
	_place([me, t1])
	_adv(6.0, [me])
	var n110 := int(D.KUNAI_N[2])
	var w110: float = float(n110) * (float(D.KUNAI_FLAT[2]) + D.KUNAI_ATK * 100.0)
	_ok("110 第 5 秒掷 %d 枚, 目标共挨 %.0f, 自身回 %.0f" % [n110, w110, float(n110) * float(D.KUNAI_HEAL[2])],
		int(_ds.stat["kunai"]) == n110 and _near(_lost(t1), w110, 3.0) and _near(float(me["hp"]) - 50000.0, float(n110) * float(D.KUNAI_HEAL[2]), 2.0),
		"枚 %d · 挨 %.0f · 回 %.0f" % [int(_ds.stat["kunai"]), _lost(t1), float(me["hp"]) - 50000.0])

	## ── 111 毒牙匕首 ──
	me = _mk("left", c + Vector2(-60, 0), ["p2eq_111"])
	t1 = _mk("right", c + Vector2(60, 0))
	_place([me, t1])
	me["_b4_crit"] = false
	_ds.on_hit(me, t1, 10.0, "p2eq_111", 2)
	var p0 := _stk(t1, "poison")
	me["_b4_crit"] = true
	_ds.on_hit(me, t1, 10.0, "p2eq_111", 2)
	var w111 := int(floor(100.0 * float(D.FANG_POISON_ATK[2])))
	_ok("111 不暴击不给; 暴击给 %d 层中毒(80%% 攻击力)" % w111, p0 == 0 and _stk(t1, "poison") == w111, "%d / %d" % [p0, _stk(t1, "poison")])

	## ── 112 三棱刺 ──
	me = _mk("left", c, ["p2eq_112"])
	_place([me])
	_ds.on_spawn(me, "p2eq_112", 2)
	_ok("112 登场 ⇒ 百分比破甲 +%.0f%%" % (float(D.PIERCE_PCT[2]) * 100.0), _near(float(me["armor_pen_pct"]), float(D.PIERCE_PCT[2]), 1e-6), str(me["armor_pen_pct"]))

	## ── 113 弯匕 ──
	me = _mk("left", c, ["p2eq_113"])
	t1 = _mk("right", c + Vector2(60, 0))
	_place([me, t1])
	_ds.on_kill(me, t1, "p2eq_113", 2)
	var hm := float(me.get("haste_mult", 1.0))
	var hu := float(me.get("haste_until", 0.0)) - float(_s._t)
	_ok("113 击杀 ⇒ %.0f 秒内攻速 ×%.1f" % [D.KRIS_SEC, 1.0 + float(D.KRIS_ASPD[2])], _near(hm, 1.0 + float(D.KRIS_ASPD[2]), 1e-6) and _near(hu, D.KRIS_SEC, 1e-6),
		"×%.2f · %.2f 秒" % [hm, hu])

	## ── 114 仪式匕首 ──
	me = _mk("left", c + Vector2(-60, 0), ["p2eq_114"])
	t1 = _mk("right", c + Vector2(60, 0), [], 3, 10000.0)
	var t2 := _mk("right", c + Vector2(60, 60), [], 3, 10000.0)
	_place([me, t1, t2])
	t1["hp"] = 900.0
	t2["hp"] = 1100.0
	var m0: int = _ds.marks_of("left")
	var a0 := float(me["base_atk"])
	_ds.on_hit(me, t1, 10.0, "p2eq_114", 2)
	_ds.on_hit(me, t2, 10.0, "p2eq_114", 2)
	_ok("114 9%% 血被斩杀; 11%% 不斩", not bool(t1["alive"]) and bool(t2["alive"]), "%s / %s" % [str(t1["alive"]), str(t2["alive"])])
	## 斩杀那一下经 _kill → 击杀钩已刻下第 1 道; 同一刻再来一次(同一只身上第二件的钩子)不重复刻; 换个时刻再击杀 +1
	var m1: int = _ds.marks_of("left")
	_ds.on_kill(me, t1, "p2eq_114", 2)
	var m1b: int = _ds.marks_of("left")
	_s._t = float(_s._t) + 1.0
	_ds.on_kill(me, t2, "p2eq_114", 2)
	_ok("114 斩杀即刻 1 道血契(同一刻不重复)、再击杀 +1; 每道携带者攻击 +%.1f、护穿 +%.2f" % [float(D.RITUAL_ATK[2]), float(D.RITUAL_PEN[2])],
		m1 == m0 + 1 and m1b == m1 and _ds.marks_of("left") == m0 + 2 and _near(float(me["base_atk"]) - a0, 2.0 * float(D.RITUAL_ATK[2]), 1e-6)
		and _near(float(me["armor_pen"]), 2.0 * float(D.RITUAL_PEN[2]), 1e-6),
		"血契 %d → %d / %d → %d · 攻 +%.2f · 护穿 %.2f" % [m0, m1, m1b, _ds.marks_of("left"), float(me["base_atk"]) - a0, float(me["armor_pen"])])

	## ── 115 暗影匕首 ──
	me = _mk("left", c + Vector2(-300, 0), ["p2eq_115"])
	t1 = _mk("right", c + Vector2(200, 0), [], 3, 100000.0)
	t2 = _mk("right", c + Vector2(260, 80), [], 3, 100000.0)
	t2["hp"] = 30000.0
	_place([me, t1, t2])
	_ds.on_spawn(me, "p2eq_115", 2)
	var ns: Dictionary = _ds.ninja_state(0)
	var nin: Dictionary = ns.get("u", {})
	_ok("115 召唤暗影忍者 %.0f 血 / %.0f 攻 / %.0f 双抗 / %.0f%% 暴击、登场隐身" % [float(D.NINJA_HP[2]), float(D.NINJA_ATK[2]), float(D.NINJA_RES[2]), float(D.NINJA_CRIT[2]) * 100.0],
		not nin.is_empty() and _near(float(nin["maxHp"]), float(D.NINJA_HP[2])) and _near(float(nin["atk"]), float(D.NINJA_ATK[2]))
		and _near(float(nin["def"]), float(D.NINJA_RES[2])) and _near(float(nin["mr"]), float(D.NINJA_RES[2])) and _near(float(nin["crit"]), float(D.NINJA_CRIT[2]), 1e-6)
		and float(nin.get("untargetable_until", 0.0)) > float(_s._t) + 100.0,
		"%s" % ("空" if nin.is_empty() else "%.0f / %.0f / %.0f / %.2f" % [float(nin["maxHp"]), float(nin["atk"]), float(nin["def"]), float(nin["crit"])]))
	ns["en"] = D.NINJA_EN_MAX
	var l2 := _lost(t2)
	_adv(0.5)
	var w115: float = D.NINJA_STRIKE_MULT * float(D.NINJA_ATK[2]) * 1.5
	_ok("115 影袭: 闪到最低血比例的敌人身后, 挨 %.0f(250%% 必暴击)" % w115,
		int(_ds.stat["ninja_strike"]) == 1 and _near(_lost(t2) - l2, w115, 3.0) and _lost(t1) == 0.0
		and DetMath.dist(Vector2(nin["pos"]), Vector2(t2["pos"])) < 80.0,
		"影袭 %d · 挨 %.0f · 别人 %.0f · 距 %.0f" % [int(_ds.stat["ninja_strike"]), _lost(t2) - l2, _lost(t1), DetMath.dist(Vector2(nin["pos"]), Vector2(t2["pos"]))])
	nin["hp"] = float(nin["maxHp"]) * 0.45
	_adv(0.05)
	var cs: Dictionary = _ds.ninja_state(1)
	var cl: Dictionary = cs.get("u", {})
	_ok("115 首次 ≤50%% ⇒ 分出影子(%.0f 血 / %.0f 攻)" % [float(D.NINJA_HP[2]) * D.NINJA_CLONE_STAT, float(D.NINJA_ATK[2]) * D.NINJA_CLONE_STAT],
		not cl.is_empty() and _near(float(cl["maxHp"]), float(D.NINJA_HP[2]) * D.NINJA_CLONE_STAT) and _near(float(cl["atk"]), float(D.NINJA_ATK[2]) * D.NINJA_CLONE_STAT),
		"%s" % ("空" if cl.is_empty() else "%.0f / %.0f" % [float(cl["maxHp"]), float(cl["atk"])]))
	ns["en"] = D.NINJA_EN_MAX
	_adv(0.5)
	_ok("115 影子在场时影袭 ⇒ 两枚手里剑", int(_ds.stat["shuriken"]) == 2, str(_ds.stat["shuriken"]))
	_adv(D.NINJA_CLONE_SEC)
	_ok("115 影子 %.0f 秒后消散" % D.NINJA_CLONE_SEC, not cl.is_empty() and not bool(cl["alive"]), str(cl.get("alive")))

	## ── 116 黑曜石匕首 ──
	me = _mk("left", c + Vector2(-60, 0), ["p2eq_116"])
	me["hp"] = 50000.0
	t1 = _mk("right", c + Vector2(60, 0), [], 3, 100000.0)
	_place([me, t1])
	me["_b4_crit"] = true
	_ds.on_hit(me, t1, 10.0, "p2eq_116", 2)
	_ds.on_hit(me, t1, 10.0, "p2eq_116", 2)
	var one: float = float(D.OBS_FLAT[2]) + D.OBS_ATK * 100.0 + float(D.OBS_MAXHP[2]) * 100000.0
	var stuck := (t1.get("_obs", []) as Array).size()
	_ok("116 暴击插两把, 不够杀不拔(每把 %.0f, 目标 10 万血)" % one, stuck == 2 and bool(t1["alive"]) and _lost(t1) == 0.0, "插 %d · 挨 %.0f" % [stuck, _lost(t1)])
	t1["hp"] = one * 2.0 - 5.0
	_adv(0.05)
	_ok("116 目标血 ≤ 两把伤害 ⇒ 立即全拔、目标死、携带者回 %.0f" % (2.0 * float(D.OBS_HEAL[2])),
		not bool(t1["alive"]) and int(_ds.stat["obs_pull"]) == 1 and _near(float(me["hp"]) - 50000.0, 2.0 * float(D.OBS_HEAL[2]), 2.0),
		"活 %s · 拔 %d · 回 %.0f" % [str(t1["alive"]), int(_ds.stat["obs_pull"]), float(me["hp"]) - 50000.0])

	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 匕首 9 件 (%d 条)" % _n)
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
