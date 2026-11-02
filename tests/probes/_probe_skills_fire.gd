extends Node
## 批量台: 每个技能【由它自己的龟】放一次, 量有没有产生可观测效果。
## 判据同 §⑫ 口径: 伤害 / 治疗 / 护盾 / 新建演出节点, 四者全无 = 空转。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _s = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_node_or_null("/root/GameState").test_mode = true
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0

	## 技能 → 它的主人
	var owner_of := {}
	var pets: Array = DataRegistry.all_pets
	for p in pets:
		for sk in (p.get("skillPool", []) if p is Dictionary else []):
			var t = str((sk as Dictionary).get("type", ""))
			if t != "" and _s._IMPL_SKILLS.has(t):
				owner_of[t] = str(p.get("id", ""))
	var keys: Array = owner_of.keys()
	keys.sort()
	print("=== 逐个技能由自己的龟放一次: %d 个 ===" % keys.size())

	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var dead: Array = []
	for st in keys:
		var pid: String = str(owner_of[st])
		_s._units.clear()
		var u: Dictionary = _s._spawn._make_unit(pid, "left", c + Vector2(-160.0, 0.0))
		u["maxHp"] = 1.0e6
		u["hp"] = 1.0e6
		u["shield"] = 0.0
		var foes: Array = []
		for k in range(3):
			var e: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(-40.0 + 80.0 * k, -40.0 + 40.0 * k))
			e["maxHp"] = 1.0e6
			e["hp"] = 1.0e6
			e["shield"] = 0.0
			foes.append(e)
			_s._units.append(e)
		_s._units.append(u)
		var hp0 := 0.0
		for e in foes:
			hp0 += float(e["hp"])
		var sh0: float = float(u.get("shield", 0.0))
		var hs0: float = float(u.get("hp", 0.0))
		var born := {"n": 0}
		var cb := func(_nd: Node) -> void: born["n"] += 1
		if _s._world != null:
			_s._world.child_entered_tree.connect(cb)
		_s._do_skill(u, foes[0], str(st))
		for _f in range(150):
			await get_tree().process_frame
		if _s._world != null and _s._world.child_entered_tree.is_connected(cb):
			_s._world.child_entered_tree.disconnect(cb)
		var hp1 := 0.0
		for e in foes:
			hp1 += float(e["hp"])
		var dmg: float = hp0 - hp1
		var gain: float = maxf(0.0, float(u.get("shield", 0.0)) - sh0) \
			+ maxf(0.0, float(u.get("hp", 0.0)) - hs0)
		var nb: int = int(born["n"])
		var flag := ""
		if dmg <= 0.0 and gain <= 0.0 and nb <= 0:
			flag = "❌空转(不掉血·不给盾治疗·没建任何演出节点)"
			dead.append("%s (%s)" % [st, pid])
		print("  %-24s %-10s 伤害 %9.1f · 盾/治疗 %8.1f · 新建节点 %3d %s"
			% [st, pid, dmg, gain, nb, flag])
	print("")
	print("=== 空转的 %d / %d ===" % [dead.size(), keys.size()])
	for x in dead:
		print("   " + x)
	print("PROBE DONE")
	get_tree().quit(0)
