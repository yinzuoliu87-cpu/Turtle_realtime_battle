extends Node
## _probe_fastsim.gd — 证明 FAST_SIM(跳每帧演出) ①真的提速 ②【完全不改战斗结果】
##
## 用户 2026-07-28:「每场不能以那种2.5倍速运行吗」
## 不能直接开 Engine.time_scale —— det 模式(TURTLE_SEED 设)每帧恰 1 个固定 SIM_DT 步,
## 根本不看 delta, 调 time_scale 无效。
## 也不走"每帧多跑 N 个 sim 步": 那会让 tween 相对慢 N 倍, 直接放大 CLAUDE.md §3.5 那个
## "伤害埋在 tween 链末尾、跑不完"的坑。
## 走的是【让每帧更便宜】: 跳过 battle_render._render_step(其文件头自陈"纯视觉不改战斗态")。
##
## 断言(缺一不可):
##   A. 关/开 FAST_SIM 跑同一场(同种子) → 战斗指纹【逐字相同】+ 胜负相同 + 帧数相同
##      ★这是一票否决项: 不同就说明它并非纯视觉, 提速无效, 必须回滚
##   B. 分母: 指纹非空(否则 A 恒真)
##   C. 真的更快(报速度比; 不快也不算错, 只是白折腾)
##
## 跑法: SHIP=1 DL_AUTOFIGHT=1 TURTLE_SEED=20260728 \
##   <godot> --headless --audio-driver Dummy --path . res://tests/_probe_fastsim.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")

const FRAME_CAP := 60000

var _fail := 0

func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _fingerprint(s) -> String:
	var parts: Array = []
	for u in s._units:
		parts.append("%s:%.2f:%.1f:%.1f:%s" % [
			str(u.get("id", "?")), float(u.get("hp", 0.0)),
			float((u.get("pos", Vector2()) as Vector2).x), float((u.get("pos", Vector2()) as Vector2).y),
			str(u.get("alive", false))])
	parts.sort()
	return "t=%.3f;" % float(s._t) + "|".join(parts)


func _run(gs, ghost: Dictionary, fast: bool) -> Dictionary:
	OS.set_environment("FAST_SIM", "1" if fast else "")
	gs.reset_dual_lane()
	gs.dual_active = true
	gs.dual_ghost = ghost
	var t0 := Time.get_ticks_msec()
	var s = RB.new()
	add_child(s)
	var fr := 0
	while fr < FRAME_CAP and str(s._dl_state) != "done":
		await get_tree().process_frame
		fr += 1
	var fp := _fingerprint(s)
	var res := {
		"fp": fp, "frames": fr, "ms": Time.get_ticks_msec() - t0,
		"winner": str(gs.dual_lane_winner()), "lanes": str(gs.lane_results), "t": float(s._t),
	}
	s.queue_free()
	for _f in range(10):
		await get_tree().process_frame
	return res


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
	gs.season_level = 5
	gs.hearts = 8
	gs.dual_lineup = {}
	gs.get_dual_lineup()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260728
	var ghost = Backend.pool_find(Backend._load_seed(), 4, [], rng)
	if ghost == null:
		ghost = Backend.make_bot(4, rng)

	print("=== A: FAST_SIM 关(现状) ===")
	var a: Dictionary = await _run(gs, ghost, false)
	print("  %d 帧 / %.1f 游戏秒 / 墙钟 %.1f 秒 | 胜方=%s %s" % [
		a["frames"], a["t"], float(a["ms"]) / 1000.0, a["winner"], a["lanes"]])

	print("=== B: FAST_SIM 开 ===")
	var b: Dictionary = await _run(gs, ghost, true)
	print("  %d 帧 / %.1f 游戏秒 / 墙钟 %.1f 秒 | 胜方=%s %s" % [
		b["frames"], b["t"], float(b["ms"]) / 1000.0, b["winner"], b["lanes"]])

	OS.set_environment("FAST_SIM", "")

	_ok("★B 分母: 指纹非空(否则 A 恒真)", str(a["fp"]).length() > 20, "长度 %d" % str(a["fp"]).length())
	_ok("★A 战斗指纹逐字相同(证明跳的确实是纯视觉)", str(a["fp"]) == str(b["fp"]),
		"" if str(a["fp"]) == str(b["fp"]) else "关: %s\n            开: %s" % [
			str(a["fp"]).substr(0, 90), str(b["fp"]).substr(0, 90)])
	_ok("★A 胜负相同", str(a["winner"]) == str(b["winner"]), "%s vs %s" % [a["winner"], b["winner"]])
	_ok("★A 帧数相同(同样的步序)", int(a["frames"]) == int(b["frames"]),
		"%d vs %d" % [int(a["frames"]), int(b["frames"])])

	var sp: float = float(a["ms"]) / maxf(1.0, float(b["ms"]))
	print("")
	print("  ★提速: %.2f 倍 (墙钟 %.1f 秒 → %.1f 秒)" % [sp, float(a["ms"]) / 1000.0, float(b["ms"]) / 1000.0])
	if sp < 1.15:
		print("  ⚠ 提速不明显 —— 说明每帧成本主要在 sim 而不在演出, 这条路收益有限")

	print("ALL PASS — FAST_SIM 是纯视觉且可用" if _fail == 0 else "FAILED: %d ★不可用, 必须回滚" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
