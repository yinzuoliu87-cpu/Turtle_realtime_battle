extends Node
## verify_pirate_hook.gd — 自证: 海盗「掠夺」被动的死亡钩索 = 原版语义
## 跑法: godot --headless --path . res://tests/verify_pirate_hook.tscn --quit-after 300
##
## 回合制【原版】逐字（回合制 pets.json passive.desc）:
##   「海盗龟开局轰击随机敌人…；死亡时钩锁【击杀者】，同样造成 25%最大生命值 真实伤害。」
## 用户〖#15〗「掠夺我是说被动的【原版】海盗被动」
##
## 原实装 bug: 「任意敌人阵亡 → 存活的敌对海盗龟钩索【最近敌】」——触发条件与目标都不对。
##
## 本测试直接构造两只单位, 调 _kill(pirate, killer), 断言:
##   1. 击杀者掉了 25% 自身最大生命 (真实伤害, 穿双抗)
##   2. 击杀者被拉近到海盗尸位 90 码
##   3. 【非海盗】单位死亡时不触发钩索
##   4. 海盗被【召唤物】以外的单位杀死才算(is_summon 海盗不触发)

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  ✓ ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  ✗ ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	print("=== 1. 海盗阵亡 → 钩锁击杀者 ===")
	var pirate: Dictionary = _find(scene, "pirate")
	if pirate.is_empty():
		# 场上没有海盗 → 手工造一只
		pirate = scene._make_unit("pirate", "left", Vector2(500, 400))
		scene._units.append(pirate)
	var killer: Dictionary = _first_enemy(scene, pirate)
	if killer.is_empty():
		print("  – 找不到敌方单位, 跳过"); _done(); return

	# ★隔离: 场景仍在 tick, 其它单位会打 killer → 伤害被污染(实测 flaky: got=188 vs expect=125)
	#   只留 pirate + killer 存活, 并清掉 killer 身上的 DoT
	for o in scene._units:
		if o is Dictionary and o != pirate and o != killer:
			o["alive"] = false
	killer["stacks"] = {}
	killer["dots"] = []
	killer["_review_dummy"] = false   # ★评审假人"受击即回满", 会把伤害抹平 → 关掉才测得到真伤害
	killer["hp"] = killer["maxHp"]
	killer["pos"] = pirate["pos"] + Vector2(600, 0)     # 放远一点, 验证拉近
	var hp0: float = killer["hp"]
	var expect: int = int(float(killer["maxHp"]) * 0.25)

	scene._kill(pirate, killer)
	await get_tree().process_frame

	var lost: float = hp0 - float(killer["hp"])
	_ok("击杀者受到 ≈25% 自身最大生命的伤害", absf(lost - float(expect)) <= 2.0,
		"expect≈%d, got=%.0f" % [expect, lost])
	var dist: float = pirate["pos"].distance_to(killer["pos"])
	_ok("击杀者被拉近到海盗尸位 ~90 码", dist <= 95.0, "dist=%.1f" % dist)

	print("=== 2. 非海盗死亡 → 不触发钩索 ===")
	var other: Dictionary = _find_not(scene, "pirate")
	var k2: Dictionary = _first_enemy(scene, other)
	if other.is_empty() or k2.is_empty():
		print("  – 场上凑不出组合, 跳过")
	else:
		for o2 in scene._units:
			if o2 is Dictionary and o2 != other and o2 != k2:
				o2["alive"] = false
		k2["stacks"] = {}
		k2["dots"] = []
		k2["_review_dummy"] = false
		k2["hp"] = k2["maxHp"]
		var before: float = k2["hp"]
		scene._kill(other, k2)
		await get_tree().process_frame
		_ok("非海盗阵亡时击杀者不掉血(无钩索)", is_equal_approx(before, float(k2["hp"])),
			"before=%.0f after=%.0f" % [before, float(k2["hp"])])

	print("=== 3. 源码级: 不再是「任意敌死→钩最近敌」 ===")
	var src := _src("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("触发条件是 u.id == pirate", src.find("u.get(\"id\", \"\") == \"pirate\" and not u.get(\"is_summon\", false) and killer is Dictionary") >= 0)
	_ok("目标是 killer, 不是 _nearest_enemy", src.find("var _pt: Dictionary = killer") >= 0)

	_done()


func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 海盗死亡钩索 = 原版语义(自己死 → 钩击杀者)")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _find(scene, pid: String) -> Dictionary:
	for u in scene._units:
		if u is Dictionary and str(u.get("id", "")) == pid and u.get("alive", false):
			return u
	return {}


func _find_not(scene, pid: String) -> Dictionary:
	for u in scene._units:
		if u is Dictionary and str(u.get("id", "")) != pid and u.get("alive", false) and not u.get("is_summon", false):
			return u
	return {}


func _first_enemy(scene, u: Dictionary) -> Dictionary:
	if u.is_empty(): return {}
	for o in scene._units:
		if o is Dictionary and o.get("alive", false) and str(o.get("side", "")) != str(u.get("side", "")):
			return o
	return {}


func _src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return ""
	var s := f.get_as_text()
	f.close()
	return s
