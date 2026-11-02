extends Node
## _probe_salvo_flaky.gd —— 一次性探针(不进门禁): verify_determinism_b ⑯ 在 CI 上偶发红(0.19.566 那次 A/B 两个敌人承伤互换)。
## 照抄 ⑯ 的 _salvo_run, 同一进程连跑 N 遍(全局种子 11/97 交替), 打印每遍的承伤串 + 每门炮锁定的目标位置。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")


func _ready() -> void:
	await get_tree().process_frame
	var seen := {}
	for k in range(6):
		var r: Array = await _salvo_run(11 if k % 2 == 0 else 97)
		print("[SALVO] #%d g=%d dmg=%s" % [k, 11 if k % 2 == 0 else 97, r[0]])
		seen[r[0]] = true
	print("[SALVO] 不同结果 %d 种" % seen.size())
	get_tree().quit(0)


func _salvo_run(gseed: int) -> Array:
	RB.DEBUG_EDIT = false
	var s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	s._deterministic = true
	add_child(s)
	for _i in range(40):
		await get_tree().process_frame
	s._units.clear()
	var ar: Rect2 = s.ARENA
	var ctr: Vector2 = ar.position + ar.size * 0.5
	var cyber: Dictionary = _salvo_unit(s, "left", ctr)
	cyber["drone_n"] = 6
	cyber["_drones"] = []
	for _k in range(6):
		var sp := Sprite3D.new()
		s._world.add_child(sp)
		cyber["_drones"].append({"spr": sp})
	s._units.append(cyber)
	var foes: Array = []
	for k in range(8):
		var fx: float = ar.position.x + ar.size.x * (0.15 + 0.1 * float(k))
		var fy: float = ar.position.y + ar.size.y * (0.2 + 0.6 * float(k % 3) / 2.0)
		var f: Dictionary = _salvo_unit(s, "right", Vector2(fx, fy))
		foes.append(f)
		s._units.append(f)
	s._dbg_salvo_picks.clear()
	seed(gseed)
	s._battle_rng.seed = 20261010
	s.set_process(false)
	s._cyber_sys._cyber_assemble_mech(cyber)
	var rng_at := []
	for w in range(150):
		s._process(s.SIM_DT)
		if w == 80 or w == 110:
			rng_at.append("%d:%d/%s" % [w, s._battle_rng.state, str(s._t).left(6)])
		if w % 10 == 0:
			await get_tree().process_frame
	var parts: Array = []
	for f in foes:
		parts.append("%.0f" % (float(f["maxHp"]) - float(f["hp"])))
	var pos := []
	for f in foes:
		pos.append("(%.0f,%.0f)" % [f["pos"].x, f["pos"].y])
	print("[SALVO]   rng=%s pos=%s" % [str(rng_at), " ".join(pos)])
	var out := [",".join(parts)]
	s.queue_free()
	for _i in range(4):
		await get_tree().process_frame
	return out


func _salvo_unit(s, side: String, pos: Vector2) -> Dictionary:
	var u: Dictionary = s._spawn._make_unit("green", side, pos)
	u["maxHp"] = 30000.0; u["hp"] = 30000.0
	u["shield"] = 0.0; u["flat_dr"] = 0.0
	u["_home_pos"] = pos
	return u
