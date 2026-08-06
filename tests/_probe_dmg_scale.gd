extends Node
## _probe_dmg_scale.gd — 探针(非门禁·不被 verify_* 自动发现)
## 目的: 量【一只龟一路能打出多少总伤害】, 用来核 093 香火石"每 4000 伤害刻一道痕·上限 300 道"够不够得着。
## 跑法: SHIP=1 godot --headless --path . res://tests/_probe_dmg_scale.tscn --quit-after 12000

const BATTLE := "res://scenes/RealtimeBattle3D.tscn"

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	var pack: PackedScene = load(BATTLE)
	var inst := pack.instantiate()
	add_child(inst)

	var sec := 0.0
	var last := -1.0
	while sec < 150.0:
		await get_tree().process_frame
		sec += get_process_delta_time()
		if sec - last >= 15.0:
			last = sec
			_dump(inst, sec)

	_dump(inst, sec)
	print("PROBE DONE")
	get_tree().quit(0)


func _dump(sc, sec: float) -> void:
	if not is_instance_valid(sc):
		print("[t=%.0f] 场景已销毁" % sec)
		return
	var units = sc.get("_units")
	if units == null:
		print("[t=%.0f] 无 _units" % sec)
		return
	var lane := "?"
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		lane = str(gs.current_lane)
	var rows: Array = []
	for u in units:
		var sd := str(u.get("side", ""))
		if sd != "left" and sd != "right":
			continue
		rows.append("%s/%s dealt=%d atk=%d" % [sd, str(u.get("name", "?")), int(u.get("_st_dealt", 0)), int(u.get("atk", 0))])
	print("[t=%.0f lane=%s _t=%.1f] %s" % [sec, lane, float(sc.get("_t")), " | ".join(rows)])
