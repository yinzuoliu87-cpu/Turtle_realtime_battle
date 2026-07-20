extends Node
## verify_crystal_death_sync.gd — 守卫: 水晶龟阵亡后【水晶球继续战斗】, 而缩头龟随从随主人消失
##
## ⚠ 本文件断言的是【反转后】的行为, 别照文件名想当然:
##   用户〖2026-07-11〗:「要加死亡同步」→ 水晶球随主人死
##   用户〖2026-07-16〗反转:「水晶球不随主人阵亡, 继续战斗」→ 代码删掉了死亡同步
##     (见 RealtimeBattle3DScene.gd「删死亡同步·用户2026-07-16反转07-11拍板」那行)
##   当时只改了代码, 这个测试没跟着改 → 它守着一个已被推翻的决定红了很久(2026-07-19 修正)。
## 缩头龟随从【仍然】随主人消失, 两者行为不同是有意的, 所以两条都断言, 防以后又被顺手"统一"掉。

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

	_ok("★水晶龟阵亡后水晶球【继续战斗】(用户2026-07-16反转)", ball.get("alive", false),
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
		print("ALL PASS — 水晶球不随主人阵亡(继续战斗) / 缩头龟随从随主人消失")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)
