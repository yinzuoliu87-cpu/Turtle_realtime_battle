extends Node
## _probe_copy_ratio.gd —— 龟壳「复制」整类核查（2026-11-09）：每个能被复制的技能，复制放 vs 直接放，敌人掉血之比应 = COPY_EFFECT。
##   _probe_copy_60 已实测冰封 / 墨水炸弹比值 1.000（弹道命中 / 补间回调里结算 ⇒ 结算时龟壳 dmg_out_mult 已复位）。
##   这里把整类扫一遍，找出所有不按 60% 结算的。
## 每个用例一个全新的战斗场（上一用例的场地效果、召唤物、弹道不串过来），同一随机种子，每帧恰一步 sim，固定窗口 WINDOW 帧。
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/probes/_probe_copy_ratio.tscn
## 只跑某几个: PROBE_SKILLS=iceFreeze,lineInkBomb

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ShellSystem := preload("res://scripts/systems/skills/shell_system.gd")
const CopyRules := preload("res://scripts/gamedata/copy_rules.gd")
const WINDOW := 300
const HP := 1.0e6
const SEED := 20261109


func _case(skill: String, copy: bool) -> float:
	var s = RB.new()
	add_child(s)
	for _i in range(30):
		await get_tree().process_frame
	s._deterministic = true
	s._battle_rng.seed = SEED
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var sh: Dictionary = s._spawn._make_unit("shell", "left", c + Vector2(-140, 0))
	sh["no_basic"] = true
	sh["no_move"] = true
	sh["energy"] = 0.0
	sh["crit"] = 0.0
	var foe: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(140, 0))
	foe["active_skills"] = [skill]
	foe["maxHp"] = HP
	foe["hp"] = HP
	foe["no_basic"] = true
	foe["no_move"] = true
	foe["energy"] = 0.0
	s._units.clear()
	s._units.append(sh)
	s._units.append(foe)
	s._over = false
	if copy:
		s._shell_sys._sk_shell_copy(sh, foe)
	else:
		s._do_skill(sh, foe, skill)
	for _i in range(WINDOW):
		await get_tree().process_frame
	var dmg: float = HP - float(foe["hp"])
	s.queue_free()
	await get_tree().process_frame
	return dmg


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var only := OS.get_environment("PROBE_SKILLS")
	var skills: Array = []
	for k in RB._IMPL_SKILLS.keys():
		if CopyRules.can_copy(str(k), RB._IMPL_SKILLS) and (only == "" or only.split(",").has(str(k))):
			skills.append(str(k))
	skills.sort()
	print("=== 探针: 复制整类 · COPY_EFFECT = %s · %d 个可复制技能 · 窗口 %d 帧 ===" % [ShellSystem.COPY_EFFECT, skills.size(), WINDOW])
	var bad: Array = []
	var nodmg: Array = []
	for sk in skills:
		var a: float = await _case(sk, true)
		var b: float = await _case(sk, false)
		var r: float = (a / b) if b > 0.0 else -1.0
		var tag := "ok"
		if b <= 0.0:
			tag = "无伤害"
			nodmg.append(sk)
		elif absf(r - ShellSystem.COPY_EFFECT) > 0.05:
			tag = "★不对"
			bad.append("%s(%.2f)" % [sk, r])
		print("PROBE %-24s 复制=%9.0f  直接=%9.0f  比值=%6.3f  %s" % [sk, a, b, r, tag])
	print("PROBE SUMMARY 不按 %s 结算 %d 个: %s" % [ShellSystem.COPY_EFFECT, bad.size(), str(bad)])
	print("PROBE SUMMARY 对敌无伤害(另查) %d 个: %s" % [nodmg.size(), str(nodmg)])
	print("PROBE DONE")
	get_tree().quit(0)
