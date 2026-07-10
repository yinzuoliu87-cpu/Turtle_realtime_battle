extends Node
## verify_crystal_death_sync.gd — 守卫: 水晶龟阵亡 → 水晶球随从一同消失
## 用户〖2026-07-11〗:「要加死亡同步」(水晶球原本会在水晶龟死后继续战斗)

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

	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var crystal: Dictionary = scene._make_unit("crystal", "left", Vector2(500, 400))
	scene._units.append(crystal)
	# 手工造一颗水晶球随从(仿 spawn gate)
	var ball = scene._spawn_summon(crystal, "crystalball", 300.0, 40.0, {"label": "水晶球", "no_basic": true})
	_ok("水晶球召唤成功", ball != null and ball is Dictionary)
	if ball == null:
		_done(); return
	scene._units.append(ball)
	var killer: Dictionary = scene._make_unit("basic", "right", Vector2(600, 400))
	scene._units.append(killer)

	_ok("死前水晶球存活", ball.get("alive", false))

	# 杀死水晶龟
	scene._kill(crystal, killer)
	await get_tree().process_frame

	_ok("★水晶龟阵亡后水晶球也阵亡", not ball.get("alive", true),
		"ball.alive=%s" % [ball.get("alive")])

	# 对照: 缩头龟死了随从也死(既有行为, 顺带回归)
	var hiding: Dictionary = scene._make_unit("hiding", "left", Vector2(500, 400))
	scene._units.append(hiding)
	var minion = scene._spawn_summon(hiding, "minion", 300.0, 40.0, {"label": "随从"})
	if minion != null:
		scene._units.append(minion)
		scene._kill(hiding, killer)
		await get_tree().process_frame
		_ok("对照·缩头龟阵亡后随从也阵亡", not minion.get("alive", true))

	_done()


func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 水晶球随水晶龟阵亡同步消失")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)
