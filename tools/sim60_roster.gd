extends SceneTree
## tools/sim60_roster.gd — 把 `scripts/systems/sim/sim_roster.gd` 的分配表打成 markdown(写台账用)。
## ★跑的就是模拟窗口自己用的那个函数, 不另写一份 Python 镜像(手抄的副本必然落后)。
## ★SIM_N=120 打 120 人表(默认 60); SIM_FROM=61 只统计/只打第 61 槽起那一段(覆盖统计按这一段算)。
## 跑法: QUIET=1 TURTLE_BACKEND=" " TURTLE_SUPABASE=" " <godot> --headless --audio-driver Dummy --path . -s tools/sim60_roster.gd

const R := preload("res://scripts/systems/sim/sim_roster.gd")


func _init() -> void:
	var raw := FileAccess.get_file_as_string("res://data/pets.json")
	var pets = JSON.parse_string(raw)
	if not (pets is Array):
		print("读不到 pets.json"); quit(1); return
	var by := {}
	for p in pets:
		by[str(p["id"])] = p
	var n_all: int = int(OS.get_environment("SIM_N")) if OS.get_environment("SIM_N") != "" else 60
	var from: int = int(OS.get_environment("SIM_FROM")) if OS.get_environment("SIM_FROM") != "" else 1
	var t_all: Array = R.table(pets, n_all)
	var t: Array = t_all.slice(from - 1)
	print("| 槽位 | 龟1 · 招 | 龟2 · 招 | 龟3 · 招 |")
	print("|---|---|---|---|")
	var cnt := {}
	var pair := {}
	for row in t:
		var cells: Array = []
		for a in range(3):
			var pid: String = row["pets"][a]
			var idx: int = int(row["skills"][a])
			var pet: Dictionary = by[pid]
			var sk: Dictionary = pet["skillPool"][idx]
			cells.append("%s(%s) · %d %s" % [pet.get("name", pid), pid, idx, sk.get("name", "?")])
			cnt[pid] = int(cnt.get(pid, 0)) + 1
			pair["%s#%d" % [pid, idx]] = int(pair.get("%s#%d" % [pid, idx], 0)) + 1
		print("| p%02d | %s |" % [int(row["slot"]), " | ".join(cells)])
	## 覆盖统计(分母打出来)
	var total_pairs := 0
	for p in pets:
		total_pairs += R.choices_for(p).size()
	var mn := 999
	var mx := 0
	for k in cnt:
		mn = mini(mn, int(cnt[k])); mx = maxi(mx, int(cnt[k]))
	var pmn := 999
	for k in pair:
		pmn = mini(pmn, int(pair[k]))
	print("")
	print("COVER turtles=%d/%d appear_min=%d appear_max=%d skill_pairs=%d/%d pair_min=%d"
		% [cnt.size(), pets.size(), mn, mx, pair.size(), total_pairs, pmn])
	## 槽内重复自检
	var bad := 0
	for row in t:
		var s := {}
		for pid in row["pets"]:
			if s.has(pid): bad += 1
			s[pid] = true
	print("DUP_IN_SLOT=%d" % bad)
	## 三连组重复: 本段内部 / 与本段之前的槽位
	var key_of := func(row) -> String:
		var k: Array = (row["pets"] as Array).duplicate(); k.sort()
		return ",".join(PackedStringArray(k))
	var before := {}
	for i in range(from - 1):
		before[key_of.call(t_all[i])] = true
	var inside := {}
	var dup_in := 0
	var dup_prev := 0
	for row in t:
		var kk: String = key_of.call(row)
		if inside.has(kk): dup_in += 1
		if before.has(kk): dup_prev += 1
		inside[kk] = true
	print("TRIPLE_DUP_IN_RANGE=%d TRIPLE_SAME_AS_EARLIER_SLOTS=%d (range %d..%d)" % [dup_in, dup_prev, from, n_all])
	quit(0)
