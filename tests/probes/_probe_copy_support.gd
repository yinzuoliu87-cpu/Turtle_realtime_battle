extends Node
## _probe_copy_support.gd —— 龟壳「复制」整类核查之二(2026-11-09): 对敌无伤害的可抄技能(护盾 / 治疗 / 增益 / 控制),
##   复制规则「60% 效果 = 伤害 + 护盾 / 治疗 / DoT」里护盾与治疗这两样: 复制放 vs 直接放, 龟壳拿到的护盾峰值 / 回血总量之比应 = 0.6。
##   增益数值 / 控制时长不在这条规则里(不量)。_probe_copy_ratio 量的是对敌伤害那 57 个。
## 每个用例一个全新战斗场、同一随机种子、每帧恰一步 sim、固定窗口; 龟壳开局掉一半血(治疗才有地方加)。
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/probes/_probe_copy_support.tscn   只跑某几个: PROBE_SKILLS=a,b

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ShellSystem := preload("res://scripts/systems/skills/shell_system.gd")
const CopyRules := preload("res://scripts/gamedata/copy_rules.gd")
const WINDOW := 300
const SEED := 20261109


func _case(skill: String, copy: bool) -> Dictionary:
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
	## 血量上限放大: 第一版 412 血掉一半 ⇒ 朗姆酒两边都回满 206、比值被上限卡成 1(假象)
	sh["maxHp"] = 100000.0
	sh["hp"] = 50000.0
	var foe: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(140, 0))
	foe["active_skills"] = [skill]
	foe["maxHp"] = 1.0e6
	foe["hp"] = 1.0e6
	foe["no_basic"] = true
	foe["no_move"] = true
	foe["energy"] = 0.0
	s._units.clear()
	s._units.append(sh)
	s._units.append(foe)
	s._over = false
	var hp0: float = float(sh["hp"])
	if copy:
		s._shell_sys._sk_shell_copy(sh, foe)
	else:
		s._do_skill(sh, foe, skill)
	var shield_max := float(sh.get("shield", 0.0))
	var heal := 0.0
	var last_hp := hp0
	for _i in range(WINDOW):
		await get_tree().process_frame
		shield_max = maxf(shield_max, float(sh.get("shield", 0.0)))
		var h := float(sh["hp"])
		if h > last_hp:
			heal += h - last_hp
		last_hp = h
	var foe_dmg: float = 1.0e6 - float(foe["hp"])
	s.queue_free()
	await get_tree().process_frame
	return {"shield": shield_max, "heal": heal, "foe_dmg": foe_dmg}


func _ratio(a: float, b: float) -> float:
	return (a / b) if b > 0.5 else -1.0


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
	print("=== 探针: 复制整类之二(护盾 / 治疗) · COPY_EFFECT = %s · 候选 %d 个 ===" % [ShellSystem.COPY_EFFECT, skills.size()])
	var bad: Array = []
	var none: Array = []
	var n_meas := 0
	for sk in skills:
		var b: Dictionary = await _case(sk, false)
		if float(b["foe_dmg"]) > 0.0 and only == "":
			continue   # 对敌有伤害: 那一类归 _probe_copy_ratio
		var a: Dictionary = await _case(sk, true)
		var rs := _ratio(float(a["shield"]), float(b["shield"]))
		var rh := _ratio(float(a["heal"]), float(b["heal"]))
		var tags: Array = []
		if rs >= 0.0:
			tags.append("盾 %.3f" % rs)
			if absf(rs - ShellSystem.COPY_EFFECT) > 0.05:
				bad.append("%s 盾(%.2f)" % [sk, rs])
		if rh >= 0.0:
			tags.append("疗 %.3f" % rh)
			if absf(rh - ShellSystem.COPY_EFFECT) > 0.05:
				bad.append("%s 疗(%.2f)" % [sk, rh])
		if rs < 0.0 and rh < 0.0:
			none.append(sk)
		else:
			n_meas += 1
		print("PROBE %-24s 复制 盾%8.0f 疗%8.0f | 直接 盾%8.0f 疗%8.0f | %s" % [sk, float(a["shield"]), float(a["heal"]),
			float(b["shield"]), float(b["heal"]), " ".join(tags) if not tags.is_empty() else "不给盾也不回血(增益 / 控制类, 不在规则里)"])
	print("PROBE SUMMARY 量到盾或治疗的 %d 个; 不按 %s 的 %d 处: %s" % [n_meas, ShellSystem.COPY_EFFECT, bad.size(), str(bad)])
	print("PROBE SUMMARY 不给盾也不回血 %d 个: %s" % [none.size(), str(none)])
	print("PROBE DONE")
	get_tree().quit(0)
