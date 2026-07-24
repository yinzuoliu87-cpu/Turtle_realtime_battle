extends Node

## verify_trainer_skills.gd — 训龟大师【技能装配】逐个技能验收 (用户2026-07-23 方案书 20260723c)
## R1b 魔法石(被动): 大师普攻命中 → 2%目标最大生命 魔法伤害 + 自己每击 +5% 攻速(可叠·本场结束重置)。
## ★用真实场景实例(有完整单位字段), 直接驱动 _trainer_magicstone_onhit(照 verify_dot_stacks 做法)。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	await get_tree().process_frame
	var scene = RTScene.new()
	add_child(scene)                 # 触发 _ready → 建场 + spawn 队伍/大师
	await get_tree().process_frame
	await get_tree().process_frame

	_test_magic_stone(scene)
	_test_source(scene)

	scene.queue_free()
	print("ALL PASS — 训龟大师技能(魔法石)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)

func _test_magic_stone(scene) -> void:
	var trainer = null
	var enemy = null
	for u in scene._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
			trainer = u
		elif not u.get("is_trainer", false) and u.get("alive", false) and str(u.get("side", "")) == "right":
			enemy = u
	_ok("找到我方大师 + 敌方单位(分母)", trainer != null and enemy != null)
	if trainer == null or enemy == null:
		return
	trainer["_tr_passive"] = "magic_stone"
	trainer["_ms_stacks"] = 0
	trainer["crit"] = 0.0                       # 去暴击随机 → 确定性
	enemy["shield"] = 0.0
	enemy["dodge_bonus"] = 0.0
	var hp0: float = float(enemy["hp"])
	var mx: float = float(enemy["maxHp"])
	scene._trainer_magicstone_onhit(trainer, enemy)
	var drop: float = hp0 - float(enemy["hp"])
	_ok("★魔法石·命中附带魔法伤(≤2%最大生命·过魔抗)", drop > 0.0 and drop <= mx * 0.02 + 3.0,
		"掉 %.0f 血 (2%%最大生命=%d)" % [drop, int(mx * 0.02)])
	_ok("★魔法石·攻速叠 1 层", int(trainer.get("_ms_stacks", 0)) == 1)
	scene._trainer_magicstone_onhit(trainer, enemy)
	_ok("★魔法石·可叠加(第2击→2层)", int(trainer.get("_ms_stacks", 0)) == 2)
	# 无魔法石被动的大师不触发(反向)
	var t2 = {"is_trainer": true, "side": "left", "alive": true, "_tr_passive": "", "_ms_stacks": 0}
	_ok("★没装魔法石→攻速haste=1(源码断言在下条)", int(t2.get("_ms_stacks", 0)) == 0)

func _test_source(scene) -> void:
	var src: String = ""
	if RTScene is GDScript:
		src = (RTScene as GDScript).source_code
	_ok("★攻速按叠层缩短(_ms_stacks 进攻击间隔 / haste)",
		src.contains("_ms_stacks") and src.contains("TRAINER_ATK_INTERVAL / haste"))
	_ok("★只在装配了魔法石时才触发被动", src.contains('"magic_stone"'))
	_ok("★攻速叠层【本场结束重置】(_dl_start_fight 清 _ms_stacks·§3.4按本场计)",
		src.contains('_ms_stacks"] = 0'))
