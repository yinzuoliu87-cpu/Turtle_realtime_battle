extends Node
## _probe_stele.gd — 探针(非门禁·`_` 开头不被自动发现)
## 问题: 截图评审在【真实对局】里让 094 的携带者死了, 阵亡点没有出现任何碑,
##       而 verify_eq_relic_batch 里直调 `_eq_on_death` 是能立起来的(157 条 ALL PASS)。
## 这个探针把中间那一段逐步打出来: 走【真的 `_kill`】而不是直调 on_death, 看哪一步断的。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var s = RB.new()
	add_child(s)
	for _i in range(30):
		await get_tree().process_frame

	var sys = s._equip_sys._relic_sys
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	s._units.clear()

	var car: Dictionary = s._spawn._make_unit("fortune", "left", c + Vector2(-200.0, 0.0))
	car["equips"] = [{"id": "p2eq_094", "star": 3}]
	car["eq_state"] = {"p2eq_094": {}}
	car["maxHp"] = 1000.0; car["hp"] = 1000.0
	car["shield"] = 0.0; car["def"] = 0.0; car["mr"] = 0.0
	car["base_def"] = 0.0; car["base_mr"] = 0.0; car["dodge_bonus"] = 0.0
	s._units.append(car)

	var foe: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(200.0, 0.0))
	foe["maxHp"] = 100000.0; foe["hp"] = 100000.0
	s._units.append(foe)

	print("[probe] 起手 stele_count=%d  carrier.alive=%s" % [sys.stele_count(), str(car.get("alive"))])

	# ★走【真的伤害路径】把携带者打死 —— 不直调 _kill, 更不直调 on_death
	s._damage._apply_damage_from(foe, car, 99999, Color("#ffffff"))
	print("[probe] 打死之后 alive=%s hp=%.1f  stele_count=%d"
		% [str(car.get("alive")), float(car.get("hp", -1)), sys.stele_count()])
	print("[probe] carrier 还在 _units 里吗: %s   _units.size=%d"
		% [str(s._arr_has_unit(s._units, car)), s._units.size()])

	# 再喂几帧全局 tick, 看碑会不会被自扫掉
	for i in range(5):
		s._equip_sys.tick_global(0.2)
		print("[probe] tick_global 第 %d 次(累计 %.1f 秒) stele_count=%d" % [i + 1, (i + 1) * 0.2, sys.stele_count()])

	# ★碑立起来了 ⇒ 问题在【看不见】。把演出节点的世界坐标逐帧打出来:
	#   relic_eq_vfx.apply_stele 里 `root.position.y = base.y - STELE_H*(1-rise_profile(tau))`
	#   ⇒ tau=0 时整根埋在地下 STELE_H, tau=1 才完全升起。
	var st0: Dictionary = sys._steles[0] if sys.stele_count() > 0 else {}
	var h = st0.get("h", null)
	print("[probe] 演出句柄有没有: %s" % str(h != null))
	if h is Dictionary and h.has("root") and is_instance_valid(h["root"]):
		var r = h["root"]
		print("[probe] 碑节点: 在场景树里=%s  visible=%s  y=%.3f"
			% [str(r.is_inside_tree()), str(r.visible), r.position.y])
		for i in range(6):
			sys.tick(0.5)
			print("[probe]   +%.1f 秒 age=%.2f  y=%.3f  visible=%s"
				% [(i + 1) * 0.5, float(sys._steles[0]["age"]) if sys.stele_count() > 0 else -1.0,
				   r.position.y if is_instance_valid(r) else -999.0,
				   str(r.visible) if is_instance_valid(r) else "已释放"])
	else:
		print("[probe] ★★演出句柄不可用 —— 碑在结算层存在, 但【根本没建演出节点】")

	# 对照: 直调 on_death(门禁走的就是这条) —— 若这条能立而上面不能, 说明断在 _kill→on_death 之间
	s._units.clear()
	var car2: Dictionary = s._spawn._make_unit("fortune", "left", c + Vector2(-100.0, 100.0))
	car2["equips"] = [{"id": "p2eq_094", "star": 3}]
	car2["eq_state"] = {"p2eq_094": {}}
	s._units.append(car2)
	sys.clear_all()
	s._equip_sys._eq_on_death(car2, null)
	print("[probe] 对照·直调 _eq_on_death → stele_count=%d" % sys.stele_count())

	print("PROBE DONE")
	get_tree().quit(0)
