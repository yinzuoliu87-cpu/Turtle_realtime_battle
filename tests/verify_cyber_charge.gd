extends Node
## verify_cyber_charge.gd — 自证: 赛博龟「智能AI」登场即 3 层充能
## 跑法: godot --headless --path . res://tests/verify_cyber_charge.tscn --quit-after 300
##
## 用户〖2026-07-07 逐字〗:
##   「普攻得改，一段伤害1ATK物理，但会穿透目标并无限飞行，射程为450码，技能3为智能AI，
##     【赛博龟登场时拥有3层充能】，主动为40龟能，释放技能时获得一层充能，
##     而赛博龟会进行走位或冲刺来躲避技能了，以及登场时赛博龟获得20%移动速度」
##
## 2026-07-10 轮F 发现: 代码只做了 +20% 移速与「释放+1充能」, 【登场3层充能漏做】(从0起算)。
## ⚠ 充能的【消耗方式与收益】用户从未定义 → 只作计数, 不自造。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.loadouts["cyber"] = 3          # skillPool[3] = 智能AI (cyberSmartAI)

	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	print("=== 1. 选中智能AI → 登场即 3 层充能 ===")
	var cy: Dictionary = scene._make_unit("cyber", "left", Vector2(500, 400))
	scene._units.append(cy)
	var types: Array = scene._chosen_skill_types("cyber", true)
	_ok("loadout 解析到 cyberSmartAI", "cyberSmartAI" in types, "types=%s" % [types])

	var spd0: float = float(cy["move_spd"])
	scene._apply_spawn_passives()
	_ok("登场充能 = 3", int(cy.get("cyber_ai_charge", -1)) == 3,
		"got=%d" % int(cy.get("cyber_ai_charge", -1)))
	_ok("登场 +20% 移速", absf(float(cy["move_spd"]) - spd0 * 1.2) < 0.01,
		"%.1f -> %.1f" % [spd0, float(cy["move_spd"])])

	print("=== 2. 每次释放 +1 充能 ===")
	scene._sk_cyber_smart(cy)
	_ok("释放一次 → 4 层", int(cy.get("cyber_ai_charge", -1)) == 4,
		"got=%d" % int(cy.get("cyber_ai_charge", -1)))

	print("=== 3. 没选智能AI → 不给充能/不给移速 ===")
	if gs != null:
		gs.loadouts["cyber"] = 1          # 换成 能量大炮
	var cy2: Dictionary = scene._make_unit("cyber", "left", Vector2(600, 400))
	scene._units.append(cy2)
	var spd2: float = float(cy2["move_spd"])
	scene._apply_spawn_passives()
	_ok("未选智能AI → 无充能键", not cy2.has("cyber_ai_charge"))
	_ok("未选智能AI → 移速不变", absf(float(cy2["move_spd"]) - spd2) < 0.01)

	print("")
	if _fail == 0:
		print("ALL PASS — 赛博智能AI: 登场3层充能 + 释放+1 + 未选不生效")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)
