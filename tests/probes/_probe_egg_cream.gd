extends Node
## 探针(11-08 晚): 用户「炼乳罐提供的奶油护盾…获得这个护盾的龟蛋变成无敌了呀？是 bug 还是什么？」
## 0.22.9 的 071 会给龟蛋发奶油盾(main 已在 _cream_grant_all 跳过龟蛋)。这里量「龟蛋身上有奶油盾时挨打 / 盾破之后」血量怎么走,
## 对照没盾的龟蛋。不是门禁。跑法: <godot> --headless --audio-driver Dummy --path . res://tests/probes/_probe_egg_cream.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _s = null


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	OS.set_environment("TURTLE_SEED", "424242")
	_s = RB.new()
	add_child(_s)
	_s._deterministic = true
	for _i in range(30):
		await get_tree().process_frame
	OS.set_environment("TURTLE_SEED", "")
	for with_cream in [false, true]:
		await _run(with_cream)
	get_tree().quit(0)


func _run(with_cream: bool) -> void:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var egg: Dictionary = _s._spawn._make_unit("__egg__", "left", c + Vector2(-300, 0), {"egg": true, "egg_side": "left", "hp": 2000.0, "hp_max": 2000.0})
	var foe: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(200, 0))
	foe["no_basic"] = true
	foe["no_move"] = true
	foe["energy"] = 0.0
	foe["maxHp"] = 99999.0
	foe["hp"] = 99999.0
	var mate: Dictionary = _s._spawn._make_unit("basic", "left", c + Vector2(-200, 200))
	mate["no_basic"] = true
	mate["no_move"] = true
	_s._units.clear()
	_s._units.append_array([egg, foe, mate])
	_s._over = false
	print("=== %s 奶油盾 ===  蛋 maxHp %.0f hp %.0f 双抗 %.0f/%.0f 围栏 %s" % ["有" if with_cream else "没有",
		float(egg["maxHp"]), float(egg["hp"]), float(egg["def"]), float(egg["mr"]), str(egg.get("_egg_fence", false))])
	if with_cream:
		_s._spec.grant(egg, "p2eq_071_cream", float(egg["maxHp"]) * 0.25, {
			"on_break": func(uu, _k, reason): _s._equip_sys._food_sys._cream_on_break(uu, 2, str(reason), mate)})
	for k in range(12):
		for u in _s._units:
			u["energy"] = 0.0
		var hp0 := float(egg["hp"])
		_s._damage._apply_damage_from(foe, egg, 400, Color.RED)
		var hp1 := float(egg["hp"])
		_s._damage._apply_damage(egg, 150, Color.RED, foe)
		var hp2 := float(egg["hp"])
		for _i in range(6):
			await get_tree().process_frame
		var bal := 0.0
		var uid := str(egg.get("_spec_uid", ""))
		if uid != "" and _s._spec._bal.has(uid):
			for kk in (_s._spec._bal[uid] as Dictionary):
				bal += float(_s._spec._bal[uid][kk]["val"])
		print("  第 %2d 下: 普攻路 %.0f→%.0f  真伤路 →%.0f  奶油余额 %.0f  双抗 %.0f/%.0f  存活 %s  破盾次数 %d" % [k, hp0, hp1, hp2, bal,
			float(egg["def"]), float(egg["mr"]), str(egg.get("alive", false)), int(egg.get("_cream_broke_n", 0))])
		if not egg.get("alive", false):
			break
