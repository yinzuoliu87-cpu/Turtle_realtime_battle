extends Node
## 触手伤害的飘字颜色: 会不会继承上一次别的伤害的类型
func _ready() -> void:
	await get_tree().process_frame
	var scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn); await get_tree().process_frame
	for u in scn._units.duplicate():
		var sp = u.get("sprite", null)
		if sp != null and is_instance_valid(sp): sp.queue_free()
	scn._units.clear()
	var cx: float = scn.ARENA.position.x + scn.ARENA.size.x * 0.5
	var cy: float = scn.ARENA.position.y + scn.ARENA.size.y * 0.5
	var carrier: Dictionary = scn._spawn._make_unit("basic", "left", Vector2(cx - 320.0, cy))
	carrier["no_move"] = true; carrier["no_basic"] = true; carrier["move_spd"] = 0.0
	carrier["active_skills"] = []; carrier["deathfloor_until"] = 999999.0
	carrier["equips"] = [{"id": "p2eq_032", "star": 1}, {"id": "p2eq_025", "star": 1}]
	scn._units.append(carrier)
	var root: Vector2 = scn._tentacle_vfx.default_root("left", 0)
	var d: Dictionary = scn._spawn._make_unit("basic", "right", Vector2(root.x + 200.0, root.y))
	d["no_move"] = true; d["no_basic"] = true; d["move_spd"] = 0.0
	d["active_skills"] = []; d["base_def"] = 0.0; d["base_mr"] = 0.0
	scn._recalc_stats(d)
	d["maxHp"] = 100000.0; d["hp"] = 100000.0; d["deathfloor_until"] = 999999.0
	scn._units.append(d)
	scn._synergy.clear(); scn._synergy.apply_all()
	await get_tree().process_frame
	var ss = scn._spirit_syn
	print("  档位 = %d" % ss._side_tier("left"))
	# ① 有携带者
	scn._last_dmg_type = "magic"                       # 污染: 假装上一次是法术伤害
	ss._slap_resolve("left", root, Vector2.RIGHT, 400.0, 1.0)
	print("  ①有携带者   打完后 _last_dmg_type = %s   %s"
		% [scn._last_dmg_type, "✓物理" if scn._last_dmg_type == "physical" else "★错(飘字会是蓝/白)"])
	# ② 携带者已死(触手无敌, 会活过携带者)
	carrier["alive"] = false
	scn._last_dmg_type = "magic"
	ss._slap_resolve("left", root, Vector2.RIGHT, 400.0, 1.0)
	print("  ②携带者已死 打完后 _last_dmg_type = %s   %s"
		% [scn._last_dmg_type, "✓物理" if scn._last_dmg_type == "physical" else "★错(飘字会是蓝/白)"])
	print("  ★_any_carrier 在携带者死后返回: %s" % str(ss._any_carrier("left")))
	scn.queue_free(); get_tree().quit(0)
