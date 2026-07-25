extends Node
## verify_battle_determinism.gd — Phase2b 北极星: 同 TURTLE_SEED + 固定步长 → 同战斗结果(可复现)
## 用调试场摆 2 只近距对打(避免匹配/GameState队伍依赖·轻·两场【顺序】跑防同时开→省内存防BSOD)。
## 跑两遍同种子, 比对指纹(各单位 id+hp+pos + _t)。逐字相同 = 确定性成立。
## ⚠这是真·探针: 若不同, 说明还有非确定源(残留 tween 驱动 sim / 未收束随机 / 消费顺序)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _fingerprint(scene) -> String:
	var parts: Array = []
	for u in scene._units:
		parts.append("%s:%.2f:%.1f:%.1f" % [str(u.get("id", "?")), float(u.get("hp", 0.0)), float((u.get("pos", Vector2()) as Vector2).x), float((u.get("pos", Vector2()) as Vector2).y)])
	parts.sort()
	return "t=%.3f;" % float(scene._t) + "|".join(parts)

func _run_once(frames: int) -> String:
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._edit_clear()   # ★清掉自动载入/上次遗留的摆位(调试场存盘到disk会跨run泄漏)→ 只留本run摆的2只·隔离
	# 近距: 左攻击龟 + 右可击杀假人(有限血·会掉血→指纹随战斗推进)
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 4000.0
	s._edit_place_unit("basic", "left", Vector2(320, 300))
	s._edit_place_unit("basic", "right", Vector2(400, 300))
	s._edit_start_battle()
	for _i in range(frames):
		await get_tree().process_frame
	var fp := _fingerprint(s)
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return fp

func _ready() -> void:
	OS.set_environment("TURTLE_SEED", "424242")
	var fp1: String = await _run_once(200)
	var fp2: String = await _run_once(200)
	OS.set_environment("TURTLE_SEED", "77")   # 不同种子
	var fp3: String = await _run_once(200)
	OS.set_environment("TURTLE_SEED", "")
	var same := fp1 == fp2
	_ok("★同种子(424242)两遍 headless 战斗 → 指纹逐字相同(确定性成立)", same)
	if not same:
		print("  run1: ", fp1)
		print("  run2: ", fp2)
	# 非 vacuous: 不同种子应给不同结果(否则说明战斗没吃随机=指纹对种子不敏感=白测)
	_ok("★不同种子(77) → 指纹不同(证明结果真吃种子·同种子match非恒真)", fp3 != fp1, "seed77 vs 424242")
	_ok("分母: 指纹非空且含单位状态", fp1.length() > 10 and fp1.find("basic:") >= 0, fp1.substr(0, 90))
	print("ALL PASS — 战斗确定性成立(同种子同结果·Phase2b 固定步长生效)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
