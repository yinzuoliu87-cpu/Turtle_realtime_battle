extends Node
## verify_fortune_goldshield.gd — 财神「梭哈后技能变金盾」(用户2026-07-12)
##   梭哈(一场限一次)用过后, 该技能槽变「金盾」: 80龟能·护盾=当前金币数(不消耗金币)·持盾期锁龟能(盾破/4s到期解锁)
const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _fail := 0
func _ok(n, c, d=""):
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	var sc = RTScene.new(); add_child(sc)
	await get_tree().process_frame
	await get_tree().process_frame
	sc.set_process(false); sc.set_physics_process(false)
	sc._t = 10.0

	# ── ① 梭哈用过 → 龟能消耗改80 + allin_used ──
	var f: Dictionary = sc._make_unit("fortune", "left", Vector2(400, 400))
	var e: Dictionary = sc._make_unit("basic", "right", Vector2(460, 400))
	e["maxHp"] = 1e9; e["hp"] = 1e9
	sc._units.append(f); sc._units.append(e)
	f["gold"] = 25.0
	sc._sk_fortune_allin(f, e)
	_ok("梭哈: allin_used=true", f.get("allin_used", false) == true)
	_ok("梭哈: 该技龟能消耗改80(变金盾)", is_equal_approx(float(f["energy_cost"].get("fortuneAllIn", 0.0)), 80.0), "cost=%d" % int(f["energy_cost"].get("fortuneAllIn", 0)))

	# ── ② 分派: 梭哈用过后 _do_skill("fortuneAllIn") 路由到金盾(而非再放梭哈) ──
	f["gold"] = 15.0; f["shield"] = 0.0
	sc._do_skill(f, e, "fortuneAllIn")
	_ok("梭哈用过→_do_skill 路由到金盾(护盾=金币15)", is_equal_approx(float(f.get("shield", 0.0)), 15.0), "shield=%d" % int(f.get("shield", 0)))

	# ── ③ 金盾: 护盾=金币数 · 不消耗金币 · 锁龟能标记 ──
	f["gold"] = 20.0
	f["shield"] = 0.0
	sc._sk_fortune_goldshield(f)
	_ok("金盾: 护盾量=当前金币数(20)", is_equal_approx(float(f.get("shield", 0.0)), 20.0), "shield=%d" % int(f.get("shield", 0)))
	_ok("金盾: 金币不消耗(仍20)", int(f["gold"]) == 20, "gold=%d" % int(f["gold"]))
	_ok("金盾: gold_shield_until 设了(>当前t=10)", float(f.get("gold_shield_until", 0.0)) > sc._t)

	# ── ④ 持金盾期间锁龟能: _tick_skill_cd 不减冷却(龟能=冷却进度) ──
	f["skill_cd"] = {"fortuneAllIn": 5.0}
	f["active_skills"] = ["fortuneAllIn"]
	f["shield"] = 20.0; f["gold_shield_until"] = sc._t + 4.0
	sc._tick_skill_cd(f, 0.5)
	_ok("金盾: 持盾期锁龟能(冷却不减, 仍5.0)", is_equal_approx(float(f["skill_cd"]["fortuneAllIn"]), 5.0), "cd=%.2f" % float(f["skill_cd"]["fortuneAllIn"]))
	f["shield"] = 0.0   # 盾破 → 解锁
	sc._tick_skill_cd(f, 0.5)
	_ok("金盾: 盾破后解锁(冷却恢复减少)", float(f["skill_cd"]["fortuneAllIn"]) < 5.0, "cd=%.2f" % float(f["skill_cd"]["fortuneAllIn"]))

	# ── ⑤ 金盾无金币时不放(护盾不为0乱给) ──
	var f2: Dictionary = sc._make_unit("fortune", "left", Vector2(300, 300))
	f2["gold"] = 0.0; f2["shield"] = 0.0
	sc._sk_fortune_goldshield(f2)
	_ok("金盾: 0金币→不给护盾(不空放)", is_equal_approx(float(f2.get("shield", 0.0)), 0.0))

	print("")
	print(("ALL PASS — 财神梭哈后变金盾(护盾=金币数/不消耗/锁龟能/80龟能)" if _fail == 0 else "FAIL x%d" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)
