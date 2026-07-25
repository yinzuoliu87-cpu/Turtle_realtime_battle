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

func _run_once(attacker: String, full_energy: bool, frames: int) -> String:
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._edit_clear()   # ★清掉自动载入/上次遗留的摆位(调试场存盘到disk会跨run泄漏)→ 只留本run摆的2只·隔离
	# 近距: 左攻击龟 + 右可击杀假人(有限血·会掉血→指纹随战斗推进)
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 4000.0
	s._edit_full_energy = full_energy   # 满龟能: 主动技即就绪→放技(练更多技能RNG/DoT/时序路径)
	s._edit_place_unit(attacker, "left", Vector2(320, 300))
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
	# 场景A: 2 基础龟普攻(基线)
	OS.set_environment("TURTLE_SEED", "424242")
	var fp1: String = await _run_once("basic", false, 200)
	var fp2: String = await _run_once("basic", false, 200)
	OS.set_environment("TURTLE_SEED", "77")   # 不同种子
	var fp3: String = await _run_once("basic", false, 200)
	OS.set_environment("TURTLE_SEED", "")
	_ok("★A 同种子(424242)两遍普攻战 → 指纹逐字相同(确定性)", fp1 == fp2)
	if fp1 != fp2:
		print("  A.run1: ", fp1); print("  A.run2: ", fp2)
	_ok("★A 不同种子(77) → 指纹不同(结果真吃种子·非vacuous)", fp3 != fp1)

	# 场景B: 满龟能骰子龟放技(命运骰子=_battle_rng随机·练技能RNG/时序路径)
	OS.set_environment("TURTLE_SEED", "31337")
	var fpb1: String = await _run_once("dice", true, 260)
	var fpb2: String = await _run_once("dice", true, 260)
	OS.set_environment("TURTLE_SEED", "")
	_ok("★B 满龟能骰子龟放技 同种子两遍 → 指纹逐字相同(技能层也确定)", fpb1 == fpb2)
	if fpb1 != fpb2:
		print("  B.run1: ", fpb1); print("  B.run2: ", fpb2)

	_ok("分母: 指纹非空且含单位状态", fp1.length() > 10 and fp1.find("basic:") >= 0, fp1.substr(0, 70))
	print("ALL PASS — 战斗确定性成立(同种子同结果·Phase2b 固定步长生效)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
