extends Node
## DEV 探针(11-22): 按裁判机的方式重放某个号本周的经济流水, 逐条打印指定统领身上的装备 / 背包, 找客户端与服务器分岔的那一步。
## 由来: 测试玩家 alex1997 账本第 327 条「equip shell」被服务器判 apply:equip:full(龟壳龟已装满), 手机上却装上了。
## 跑法: ECON_ROWS=res://.out/econ/alex_ops.json ECON_PID=shell ECON_FROM=300 ECON_TO=330 \
##       <godot> --headless --path . res://tests/probes/_probe_econ_replay_trace.tscn
## 流水文件 = tools/sb_ro.py 查出来的 [{seq, src, op}, …](按 seq 升序)。

const EL := preload("res://scripts/gamedata/econ_ledger.gd")


func _brief(a) -> String:
	var out: Array = []
	if a is Array:
		for e in a:
			if e is Dictionary:
				out.append("%s★%d" % [str(e.get("id", "")).replace("p2eq_", ""), int(e.get("star", 0))])
			else:
				out.append(str(e))
	return "[" + ", ".join(PackedStringArray(out)) + "]"


func _ready() -> void:
	var gs = get_node("/root/GameState")
	var path := OS.get_environment("ECON_ROWS")
	var pid := OS.get_environment("ECON_PID")
	var a := int(OS.get_environment("ECON_FROM"))
	var b := int(OS.get_environment("ECON_TO"))
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	var rows: Array = []
	for x in raw:
		var op: Dictionary = (x["op"] as Dictionary).duplicate(true)
		op["seq"] = int(x["seq"])
		rows.append(op)
	print("[trace] 流水 %d 条 · 看 %s · 第 %d~%d 条" % [rows.size(), pid, a, b])
	gs.test_mode = true
	gs.econ_quiet = int(gs.econ_quiet) + 1
	EconReplay.week_start(gs)
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		gs.season_total_battles = int(row.get("bt", 0))
		var before := _brief((gs.persistent_equipped as Dictionary).get(pid, []))
		var r: Dictionary = EL.apply(gs, row)
		if i >= a and i <= b:
			print("[trace] #%d %s → ok=%s %s · %s 身上 %s → %s · 背包 %d 件 %s · 统领 %s" % [i, JSON.stringify(row).left(110), str(r.get("ok")), str(r.get("reason", "")),
				pid, before, _brief((gs.persistent_equipped as Dictionary).get(pid, [])), (gs.persistent_bench as Array).size(),
				_brief(gs.persistent_bench).left(160), str(gs.season_leaders)])
		if not bool(r.get("ok", false)):
			print("[trace] ★第 %d 条不成交: %s" % [i, str(r)])
			break
	get_tree().quit(0)
