extends Node
## verify_headless_rage.gd — 守卫无头龟被动「亡灵怒」: 每损失1%生命 → 攻击力+1%, 最高+100%
##
## 起因(用户2026-07-19「补实装」): pets.json 与权威文档都写了这条被动, 但代码里【从来没实现过】——
## 只有 _update_headless_flame 的函数头注释提了一句"对应+1%攻/1%损血", 函数体却只改紫焰特效大小。
## 是 2026-07-19 全项目文案核对时发现的"文案有、代码没有"。
##
## 断言: 满血=基准 / 半血=1.5× / 濒死≈2× / 封顶不超过 2× / 回血后能降回来(不是单向累积)

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond: print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)

func _atk_at(scene, u: Dictionary, hp_frac: float) -> float:
	u["hp"] = float(u["maxHp"]) * hp_frac
	scene._tick_periodic_passive(u, 0.016)
	return float(u["atk"])

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame

	var u: Dictionary = scene._make_unit("headless", "left", Vector2(0, 0))
	scene._units.clear()
	scene._units.append(u)
	scene._apply_spawn_passives()
	var base: float = float(u.get("headless_base_atk", 0.0))
	_ok("登场记下基准攻击 headless_base_atk", base > 0.0, "基准=%.1f" % base)
	if base <= 0.0:
		_done(); return

	var full := _atk_at(scene, u, 1.0)
	var half := _atk_at(scene, u, 0.5)
	var low := _atk_at(scene, u, 0.02)

	_ok("满血 = 基准(无加成)", is_equal_approx(full, base), "%.1f vs 基准 %.1f" % [full, base])
	_ok("★半血 = 基准×1.5(损血50%→+50%攻)", absf(half - base * 1.5) < 0.6, "%.1f, 期望 %.1f" % [half, base * 1.5])
	_ok("★濒死(2%血) ≈ 基准×1.98", absf(low - base * 1.98) < 0.6, "%.1f, 期望 %.1f" % [low, base * 1.98])
	_ok("封顶不超过 +100%", low <= base * 2.0 + 0.01, "%.1f <= %.1f" % [low, base * 2.0])

	# 回血后要能降回来 —— 证明是"按当前损血重算"而不是单向累积
	var back := _atk_at(scene, u, 1.0)
	_ok("★回满血后攻击降回基准(非单向累积)", is_equal_approx(back, base), "%.1f vs %.1f" % [back, base])

	_done()

func _done() -> void:
	print("ALL PASS — 无头龟亡灵怒(损血加攻)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
