extends Node
## 「减伤」属性 damage_reduction 的两件事(用户 2026-10-15):
##   ① 对流血/灼烧/中毒也生效 —— 原来一概不吃(「不影响持续伤害（如流血、灼烧）？」), 探针实测 50% 与 0% 掉血一样
##   ② 石头龟嘲讽的减伤并入这个属性(「肯定是并入啊」) —— 原来是另乘一道: 面板显示 0%、不受 90% 总上限约束
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _mk(kind: String, side: String, off: Vector2, dr: float) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(kind, side, c + off)
	for k in ["shield", "flat_dr", "def", "mr", "base_def", "base_mr", "dodge_bonus", "damage_amp", "crit",
			"armor_pen", "magic_pen", "armor_pen_pct", "magic_pen_pct"]:
		u[k] = 0.0
	u["damage_reduction"] = dr
	u["maxHp"] = 100000.0
	u["hp"] = 100000.0
	u["dots"] = []
	u["no_basic"] = true
	u["no_move"] = true
	u["eq_state"] = {}
	return u


## 一跳 40 层 DoT 掉多少血
func _dot_loss(kind: String, dr: float) -> float:
	var u := _mk("green", "left", Vector2(-200, 0), dr)
	var foe := _mk("green", "right", Vector2(200, 0), 0.0)
	_s._units.clear()
	_s._units.append_array([u, foe])
	u["dot_stacks"] = {kind: 40}
	u["dot_src"] = {kind: foe}
	var h0: float = u["hp"]
	_s._tick_dot_stacks(u)
	return h0 - float(u["hp"])


## 一发 1 倍攻击力(100)物理直接伤害掉多少血
func _hit_loss(u: Dictionary) -> float:
	var foe := _mk("green", "right", Vector2(200, 0), 0.0)
	foe["atk"] = 100.0
	_s._units.clear()
	_s._units.append_array([u, foe])
	var h0: float = u["hp"]
	_s._damage._apply_damage_from(foe, u, _s._atk_dmg(foe, 1.0, u, false), Color.WHITE)
	return h0 - float(u["hp"])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 减伤: 持续伤害 + 嘲讽并入 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s._edit_mode = false
	_s._over = false

	print("--- ① 减伤对持续伤害生效 ---")
	for kind in ["burn", "poison", "bleed"]:
		var l0 := _dot_loss(kind, 0.0)
		var l5 := _dot_loss(kind, 0.5)
		_ok("①%s ★分母: 0%% 减伤时这一跳真掉了血" % kind, l0 > 10.0, "掉 %.1f" % l0)
		_ok("①%s 50%% 减伤 ⇒ 掉一半" % kind, absf(l5 - l0 * 0.5) <= 1.0, "%.1f → %.1f" % [l0, l5])
	var h0 := _hit_loss(_mk("green", "left", Vector2(-200, 0), 0.0))
	var h5 := _hit_loss(_mk("green", "left", Vector2(-200, 0), 0.5))
	_ok("①直接伤害 对照: 50% 减伤也是掉一半(没被重复扣成 1/4)", h0 > 10.0 and absf(h5 - h0 * 0.5) <= 1.0, "%.1f → %.1f" % [h0, h5])

	print("--- ② 嘲讽减伤并入减伤属性 ---")
	var st := _mk("stone", "left", Vector2(-200, 0), 0.0)
	st["def"] = 18.0
	st["base_def"] = 18.0
	st["atk"] = 36.0
	var foe := _mk("green", "right", Vector2(200, 0), 0.0)
	_s._units.clear()
	_s._units.append_array([st, foe])
	_s._pending_shots.clear()
	_s._stone_sys._sk_stone_taunt(st)
	var want: float = StoneSystem.TAUNT_DR_PER_DEF * 18.0 * 0.01
	_ok("②a 施放后减伤属性 = 0.5% × 18 护甲 = 9%", absf(float(st["damage_reduction"]) - want) < 0.0001,
		"%.4f(应 %.4f)" % [float(st["damage_reduction"]), want])
	_ok("②b 嘲讽护盾是通用护盾(有到期时刻, 不是永久)", float(st.get("shield_until", 0.0)) > _s._t,
		"shield_until=%.2f t=%.2f" % [float(st.get("shield_until", 0.0)), _s._t])
	var steps := 0
	while steps < 400 and float(st.get("_taunt_dr", 0.0)) > 0.0:
		_s._ballistics._step_pending_shots(0.02)
		steps += 1
	_ok("②c ★%.1f 秒后减伤扣回 0(只扣自己给的那份)" % StoneSystem.TAUNT_SEC,
		absf(float(st["damage_reduction"])) < 0.0001 and steps >= int(StoneSystem.TAUNT_SEC / 0.02) - 2,
		"减伤 %.4f · 走了 %d 步" % [float(st["damage_reduction"]), steps])

	var st2 := _mk("stone", "left", Vector2(-200, 0), 0.30)
	st2["def"] = 18.0
	_s._units.clear()
	_s._units.append_array([st2, foe])
	_s._stone_sys._sk_stone_taunt(st2)
	_ok("②d 与别的减伤加算(30% + 9% = 39%)", absf(float(st2["damage_reduction"]) - 0.39) < 0.0001,
		"%.4f" % float(st2["damage_reduction"]))
	while float(st2.get("_taunt_dr", 0.0)) > 0.0:
		_s._ballistics._step_pending_shots(0.5)
	_ok("②e 到期只扣嘲讽那 9%, 别的 30% 还在", absf(float(st2["damage_reduction"]) - 0.30) < 0.0001,
		"%.4f" % float(st2["damage_reduction"]))

	var st3 := _mk("stone", "left", Vector2(-200, 0), 0.90)
	st3["def"] = 18.0
	var hit_before := _hit_loss(st3)
	_s._units.append(st3)
	_s._stone_sys._sk_stone_taunt(st3)
	st3["shield"] = 0.0            # 嘲讽护盾会把这一发吃掉, 量的是减伤不是护盾
	var hit_after := _hit_loss(st3)
	_ok("②f ★总减伤封顶 90%: 已有 90% 再嘲讽, 挨打不再变少(原来另乘一道会降到 5%)",
		hit_before > 5.0 and absf(hit_after - hit_before) <= 0.5, "%.1f → %.1f" % [hit_before, hit_after])

	print("--- ③ 钻石结构 / 岩层 也并入减伤属性(同嘲讽) ---")
	var dm := _mk("diamond", "left", Vector2(-200, 0), 0.0)
	_s._units.clear()
	_s._units.append_array([dm, foe])
	_s._spawn._apply_spawn_passive_one(dm)
	_ok("③a 钻石龟登场后减伤属性 = 结构 %d%%" % int(DiamondSystem.STRUCT_FLAT_DR * 100.0),
		absf(float(dm["damage_reduction"]) - DiamondSystem.STRUCT_FLAT_DR) < 0.0001, "%.4f" % float(dm["damage_reduction"]))
	var rk := _mk("stone", "left", Vector2(-200, 0), 0.0)
	rk["stone_rockbody"] = true
	rk["rock_layers"] = 0
	var foe2 := _mk("green", "right", Vector2(200, 0), 0.0)
	foe2["atk"] = 100.0
	_s._units.clear()
	_s._units.append_array([rk, foe2])
	for _i in range(5):
		_s._damage._apply_damage_from(foe2, rk, 10, Color.WHITE)
	_ok("③b ★分母: 挨 5 下真长了 5 层岩层", int(rk.get("rock_layers", 0)) == 5, "层 %d" % int(rk.get("rock_layers", 0)))
	_ok("③c 5 层岩层 ⇒ 减伤属性 5%", absf(float(rk["damage_reduction"]) - 5.0 * StoneSystem.ROCK_DR_PER_LAYER) < 0.0001,
		"%.4f" % float(rk["damage_reduction"]))

	print("=== %d 项, FAIL %d ===" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)
