extends "res://tests/verify_determinism_b.gd"
## 探针(不进门禁): 每只龟 × 指定技能下标, 同种子跑两遍, 报逐步指纹分叉。
## env: PROBE_IDX=1|2|3   PROBE_IDS=a,b,c (可省=全部)   PROBE_FRAMES=900

func _trace(pairs: Array, frames: int, loadouts: Dictionary = {}, cast_probe: bool = false) -> Array:
	if OS.get_environment("PROBE_RESET_WHEEL") != "":
		GameState.gambler_wheel_stacks = {}
	return await super._trace(pairs, frames, loadouts, cast_probe)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.week_anchor_ts = int(SC.PIN_WEEK_ANCHOR)
	var idx: int = int(OS.get_environment("PROBE_IDX")) if OS.get_environment("PROBE_IDX") != "" else 2
	var frames: int = int(OS.get_environment("PROBE_FRAMES")) if OS.get_environment("PROBE_FRAMES") != "" else 900
	var ids: Array = []
	if OS.get_environment("PROBE_IDS") != "":
		for x in OS.get_environment("PROBE_IDS").split(","): ids.append(str(x))
	else:
		var pf := FileAccess.open("res://data/pets.json", FileAccess.READ)
		var pj = JSON.parse_string(pf.get_as_text())
		var plist: Array = pj if pj is Array else (pj as Dictionary).get("pets", [])
		for pe in plist: ids.append(str(pe["id"]))
	for id in ids:
		var pairs: Array = [
			[id, "left", 320.0, 300.0, []],
			["basic", "right", 620.0, 260.0, []],
			["basic", "right", 680.0, 360.0, []],
			["basic", "right", 900.0, 300.0, []]]
		var r: Array = await _two_runs(pairs, frames, "424242", {id: idx}, true)
		var ca: Dictionary = r[13]
		var cb: Dictionary = r[14]
		var d := ""
		if int(r[2]) >= 0:
			var sa: PackedStringArray = str((r[3] as Array)[int(r[2])]).split("|")
			var sb: PackedStringArray = str((r[8] as Array)[int(r[2])]).split("|")
			for k in range(mini(sa.size(), sb.size())):
				if sa[k] != sb[k]: d += " [%s != %s]" % [sa[k], sb[k]]
		print("PROBE id=%s idx=%d bad=%d/%d first=%d castsA=%s castsB=%s %s" % [id, idx, int(r[0]), int(r[1]), int(r[2]), str(ca), str(cb), d.substr(0, 300)])
	print("PROBE DONE")
	get_tree().quit(0)
