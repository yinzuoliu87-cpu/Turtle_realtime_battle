extends Node
## _probe_copy_60.gd —— 龟壳「复制」抄来的技能到底按多少结算（2026-11-09 · 交接 11-08 L 报的结算 bug：
##   「冰封 / 墨水炸弹没按 60% 结算；实测复制效果 60%→65% 掉血不变；机制是推断」）。
##
## 做法：同一只龟壳、同一个新造的敌人（血极厚、不动、不普攻、暴击 0），两种放法各量一遍敌人掉的血：
##   A = 走真入口 `_sk_shell_copy`（敌人身上只挂这一个技能 ⇒ 候选池确定）
##   B = 龟壳直接 `_do_skill` 放同一个技能（不在复制期）
##   比值 A / B 应 = ShellSystem.COPY_EFFECT（0.6）。每帧恰一步 sim（_deterministic），等到两边都不再掉血。
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/probes/_probe_copy_60.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ShellSystem := preload("res://scripts/systems/skills/shell_system.gd")
const SKILLS := ["iceFreeze", "lineInkBomb"]
const WAIT_FRAMES := 900

var _s


func _fresh(skill: String) -> Array:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var sh: Dictionary = _s._spawn._make_unit("shell", "left", c + Vector2(-140, 0))
	sh["no_basic"] = true
	sh["no_move"] = true
	sh["energy"] = 0.0
	sh["crit"] = 0.0
	var foe: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(140, 0))
	foe["active_skills"] = [skill]
	foe["maxHp"] = 1.0e6
	foe["hp"] = 1.0e6
	foe["no_basic"] = true
	foe["no_move"] = true
	foe["energy"] = 0.0
	_s._units.clear()
	_s._pending_shots.clear()
	_s._units.append(sh)
	_s._units.append(foe)
	_s._over = false
	return [sh, foe]


func _settle(foe: Dictionary) -> Array:
	## 掉血不再变化 120 帧(或到上限)就算完; 返回 [掉血, 用了几帧]
	var last := float(foe["hp"])
	var still := 0
	var n := 0
	var t0: float = float(_s._t)
	var changes: Array = []
	print("  调用后同步掉血 = %.0f" % (1.0e6 - last))
	while n < WAIT_FRAMES and still < 120:
		await get_tree().process_frame
		n += 1
		var h := float(foe["hp"])
		if h == last:
			still += 1
		else:
			changes.append("f%d:-%.0f" % [n, last - h])
			still = 0
			last = h
	print("  sim 时钟走了 %.2f 秒 · 掉血帧 %s" % [float(_s._t) - t0, str(changes)])
	return [1.0e6 - float(foe["hp"]), n]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._deterministic = true
	print("=== 探针: 龟壳复制结算倍率 · COPY_EFFECT = %s ===" % ShellSystem.COPY_EFFECT)
	for sk in SKILLS:
		var p: Array = _fresh(sk)
		_s._shell_sys._sk_shell_copy(p[0], p[1])
		var a: Array = await _settle(p[1])
		p = _fresh(sk)
		_s._do_skill(p[0], p[1], sk)
		var b: Array = await _settle(p[1])
		var ratio: float = (a[0] / b[0]) if b[0] > 0.0 else -1.0
		print("PROBE %s  复制=%.0f(%d 帧)  直接=%.0f(%d 帧)  比值=%.3f" % [sk, a[0], a[1], b[0], b[1], ratio])
	print("PROBE DONE")
	get_tree().quit(0)
