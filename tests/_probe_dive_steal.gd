extends Node
## 探针: 087 偷来的【大师技能】放在普通龟身上, 会不会留下卸不掉的状态。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Gadget := preload("res://scripts/systems/equip/eq_gadget_batch.gd")
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
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5

	## 对照组: 什么都不放, 打一场同样长
	_s._units.clear()
	var cu: Dictionary = _s._spawn._make_unit("basic", "left", c + Vector2(-120.0, 0.0))
	cu["maxHp"] = 1.0e6; cu["hp"] = 1.0e6
	var ce: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(-40.0, 0.0))
	ce["maxHp"] = 1.0e6; ce["hp"] = 1.0e6
	_s._units.append(cu); _s._units.append(ce)
	for _f in range(420):
		await get_tree().process_frame
	var ctrl := {}
	for k in cu.keys():
		ctrl[str(k)] = true
	print("[DS] 对照组字段 %d 个" % ctrl.size())

	for st in Gadget.DIVE_SKILLS:
		_s._units.clear()
		var u: Dictionary = _s._spawn._make_unit("basic", "left", c + Vector2(-120.0, 0.0))
		u["maxHp"] = 1.0e6; u["hp"] = 1.0e6
		var e: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(-40.0, 0.0))
		e["maxHp"] = 1.0e6; e["hp"] = 1.0e6
		var e2: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(40.0, 60.0))
		e2["maxHp"] = 1.0e6; e2["hp"] = 1.0e6
		_s._units.append(u); _s._units.append(e); _s._units.append(e2)
		## ★走真入口 dive_steal_once —— 它自己会摆 _tr_active / 瞄准 / 调 _cast_active
		var stt := {"stolen": []}
		for other in Gadget.DIVE_SKILLS:
			if str(other) != str(st):
				(stt["stolen"] as Array).append(str(other))
		var got: String = _s._equip_sys._gadget_sys.dive_steal_once(u, stt)
		var ok := (got != "")
		for _f in range(420):
			await get_tree().process_frame
		var live: Array = []
		for k in u.keys():
			var ks := str(k)
			if ctrl.has(ks) or ks.begins_with("_st_") or ks.ends_with("_t") \
					or ks.ends_with("_dur") or ks.ends_with("_amp") or ks.ends_with("_start"):
				continue
			var v = u[k]
			if v is bool and bool(v):
				live.append(ks)
			elif ks.ends_with("_until") and (v is float or v is int) and float(v) > _s._t:
				live.append("%s(+%.1fs)" % [ks, float(v) - _s._t])
		print("[DS] %-12s 放出来=%s  放完7秒后还活着: %s"
			% [st, str(ok), str(live) if not live.is_empty() else "无"])
	print("PROBE DONE")
	get_tree().quit(0)
