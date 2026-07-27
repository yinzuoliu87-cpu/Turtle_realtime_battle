extends Node
## _probe_trainer_ai.gd — 证明 AI_TRAINER_LEFT 真的改变行为(而不是加了个没用的开关)
##
## 起因(2026-07-27): trainer_system.gd:_tick_trainer_ai 里
##   `if side == "left" and not battle._stress: continue`
## → 无头仿真里【左侧大师全程不放主动技】, 右侧 AI 照放 = 系统性偏袒右侧, 机器人互打数据作废。
##
## 两个方向各验一次(缺一个这检查就是空的):
##   A. 不开开关 → 左侧施法次数必须 == 0, 右侧必须 > 0   (证明原来确实是瘸的)
##   B. 开开关   → 左侧施法次数必须 > 0                   (证明开关真的生效)
##
## 施法怎么数: 主动技共用 `_active_cd` 冷却字段, 放一次就被设成 CD 值。
## 逐帧采样, 只要 _active_cd 比上一帧【变大】就记一次施法 —— 不改任何产品代码。
##
## 跑法: SHIP=1 DL_AUTOFIGHT=1 TURTLE_SEED=20260727 \
##   <godot> --headless --audio-driver Dummy --path . res://tests/_probe_trainer_ai.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")

const FRAMES := 5000     # ≈83 游戏秒, 钩锁 CD 20 秒 → 够放好几次

var _fail := 0

func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


## 跑一场, 返回 {"left": 左侧施法次数, "right": 右侧施法次数, "frames": 实跑帧数}
func _run(gs, ai_left: bool) -> Dictionary:
	OS.set_environment("AI_TRAINER_LEFT", "1" if ai_left else "")
	gs.reset_dual_lane()
	gs.dual_active = true
	gs.trainer_skill = "hook"        # 必须是【主动】技; magic_stone 是被动, 永远不会进 _cast_active
	var seed_pool: Dictionary = Backend._load_seed()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var ghost = Backend.pool_find(seed_pool, 3, [], rng)
	if ghost == null:
		ghost = Backend.make_bot(3, rng)
	gs.dual_ghost = ghost

	var s = RB.new()
	add_child(s)
	var casts := {"left": 0, "right": 0}
	var prev := {"left": 0.0, "right": 0.0}
	var fr := 0
	while fr < FRAMES and str(s._dl_state) != "done":
		await get_tree().process_frame
		fr += 1
		for u in s._units:
			if not u.get("is_trainer", false):
				continue
			var side := str(u.get("side", ""))
			if not casts.has(side):
				continue
			var cd := float(u.get("_active_cd", 0.0))
			if cd > float(prev[side]) + 0.01:     # 冷却变大 = 刚放了一次
				casts[side] = int(casts[side]) + 1
			prev[side] = cd
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	casts["frames"] = fr
	return casts


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	var dr = get_node_or_null("/root/DataRegistry")
	if gs == null or dr == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	var ids: Array = []
	for p in dr.launch_pets:
		ids.append(str((p as Dictionary)["id"]))
	gs.season_leaders = ids.slice(0, 3)
	gs.left_team.assign(ids.slice(0, 3))
	gs.season_total_battles = 8
	gs.hearts = 8
	gs.season_level = 4
	gs.dual_lineup = {}
	gs.get_dual_lineup()

	print("=== A: 不开 AI_TRAINER_LEFT (现状) ===")
	var a: Dictionary = await _run(gs, false)
	print("  左侧施法 %d 次 / 右侧 %d 次 (跑了 %d 帧)" % [a["left"], a["right"], a["frames"]])
	_ok("★A 右侧大师【会】自动放技能(分母: 证明这个计数器不是恒0)", int(a["right"]) > 0,
		"右侧 %d 次" % int(a["right"]))
	_ok("★A 左侧大师【完全不放】—— 这就是原来的偏差", int(a["left"]) == 0,
		"左侧 %d 次" % int(a["left"]))

	print("=== B: 开 AI_TRAINER_LEFT ===")
	var b: Dictionary = await _run(gs, true)
	print("  左侧施法 %d 次 / 右侧 %d 次 (跑了 %d 帧)" % [b["left"], b["right"], b["frames"]])
	_ok("★B 开开关后左侧大师【真的会放了】(开关非摆设)", int(b["left"]) > 0,
		"左侧 %d 次" % int(b["left"]))
	_ok("★B 右侧仍在放(没把别人搞坏)", int(b["right"]) > 0, "右侧 %d 次" % int(b["right"]))

	OS.set_environment("AI_TRAINER_LEFT", "")
	print("ALL PASS — AI_TRAINER_LEFT 两个方向都成立" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
