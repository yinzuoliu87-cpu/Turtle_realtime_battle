extends Node
## DEV 探针(11-24): 按裁判机的方式重放某个号一周的经济流水, 每一步看全队 / 单只装备数是否超过上限。
## 由来: 上周 alex + 4 个陪练号都在「买入触发三合一 → 紧接着穿装备」时被服务器判 apply:equip:full。
##   疑点: GameState 读档时跑 migrate_equip_caps() —— 超上限就把最弱的**直接删掉、不记流水**; 服务器重放不读档、不删。
##   若流水中途某一步超了上限, 手机下次读档就比服务器少几件 ⇒ 之后穿装备两边对不上。
## 跑法: ECON_ROWS=res://.out/econ/<文件>.json <godot> --headless --path . res://tests/probes/_probe_econ_cap_overflow.tscn
## 输出: 每个「超上限」的第一步 + 那一刻全队数 / 上限 / 超的那只; 最后一行 [cap] 汇总。

const EL := preload("res://scripts/gamedata/econ_ledger.gd")


func _brief(a) -> String:
	var out: Array = []
	if a is Array:
		for e in a:
			if e is Dictionary:
				out.append("%s★%d" % [str(e.get("id", "")).replace("p2eq_", ""), int(e.get("star", 0))])
	return "[" + ", ".join(PackedStringArray(out)) + "]"


func _over_units(gs) -> Array:
	var out: Array = []
	for pid in (gs.season_leaders if gs.season_leaders is Array else []):
		var arr: Array = (gs.persistent_equipped as Dictionary).get(str(pid), [])
		if gs._cap_count(arr) > gs._P2.UNIT_EQUIP_CAP:
			out.append("%s%s" % [str(pid), _brief(arr)])
	var dl: Dictionary = gs.dual_lineup if gs.dual_lineup is Dictionary else {}
	for lane in ["top", "bottom"]:
		for u in (dl.get(lane, []) as Array):
			if u is Dictionary and str(u.get("kind", "")) == "minion" and u.get("equips") is Array:
				if gs._cap_count(u["equips"]) > gs._P2.UNIT_EQUIP_CAP:
					out.append("小将%s%s" % [lane, _brief(u["equips"])])
	return out


func _ready() -> void:
	var gs = get_node("/root/GameState")
	var path := OS.get_environment("ECON_ROWS")
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	var rows: Array = []
	for x in raw:
		var op: Dictionary = (x["op"] as Dictionary).duplicate(true)
		op["seq"] = int(x["seq"])
		rows.append(op)
	gs.test_mode = true
	gs.econ_quiet = int(gs.econ_quiet) + 1
	EconReplay.week_start(gs)
	var over_steps := 0
	var first := -1
	var was_over := false
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		gs.season_total_battles = int(row.get("bt", 0))
		## ECON_SORT_KEYS=1: 每条之前模拟一次存档读写(JSON.stringify 默认按键名排序 ⇒ 读回来的字典键序 = 字母序, 同手机)
		if OS.get_environment("ECON_SORT_KEYS") == "1":
			gs.persistent_equipped = JSON.parse_string(JSON.stringify(gs.persistent_equipped))
		var r: Dictionary = EL.apply(gs, row)
		if i >= int(OS.get_environment("ECON_DUMP_FROM") if OS.has_environment("ECON_DUMP_FROM") else "99999") and i <= int(OS.get_environment("ECON_DUMP_TO") if OS.has_environment("ECON_DUMP_TO") else "-1"):
			var eqs: Array = []
			for pid in gs.season_leaders:
				eqs.append("%s%s" % [str(pid), _brief((gs.persistent_equipped as Dictionary).get(str(pid), []))])
			var ms: Array = []
			var dl: Dictionary = gs.dual_lineup if gs.dual_lineup is Dictionary else {}
			for lane in ["top", "bottom"]:
				for u in (dl.get(lane, []) as Array):
					if u is Dictionary and str(u.get("kind", "")) == "minion":
						ms.append("%s:%s%s" % [lane, str(u.get("role", "")), _brief(u.get("equips", []))])
			print("[dump] #%d %s ok=%s · 背包%s · %s · 小将 %s" % [i, JSON.stringify(row).left(90), str(r.get("ok")), _brief(gs.persistent_bench), " ".join(PackedStringArray(eqs)), " ".join(PackedStringArray(ms))])
		if not bool(r.get("ok", false)):
			print("[cap] #%d 不成交 %s · %s" % [i, str(r), JSON.stringify(row).left(100)])
			break
		var team: int = int(gs.team_equipped_count())
		var cap: int = int(gs.team_equip_cap())
		var units := _over_units(gs)
		var over := team > cap or not units.is_empty()
		if over:
			over_steps += 1
			if first < 0:
				first = i
			if not was_over:
				print("[cap] #%d 起超上限: 全队 %d / 上限 %d(等级 %d) · 单只超 %s · 这一条 %s" % [i, team, cap, int(gs.season_level),
					str(units), JSON.stringify(row).left(110)])
		elif was_over:
			print("[cap] #%d 回到上限内: 全队 %d / 上限 %d" % [i, team, cap])
		was_over = over
	print("[cap] %s · 流水 %d 条 · 超上限的步数 %d · 第一次 #%d" % [path.get_file(), rows.size(), over_steps, first])
	get_tree().quit(0)
