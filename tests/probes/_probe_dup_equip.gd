extends Node
## _probe_dup_equip.gd —— 同一件装备带两件, 第二件有没有各自生效(只读探针, 不进门禁; 2026-11-13)
##
## 用户 11-13:「两件肯定召唤两个炮台啊，三件召唤三个炮台…两件相同装备，肯定是各自生效各自的效果，
##              也不能说共享啊」。
## 每件装备在同一个干净小场(同 _probe_tally_truth)里跑五种配置, 量「世界里实际发生的量」:
##   Z 不带  ·  A [3★]  ·  B [3★, 3★]  ·  C [3★, 1★]  ·  D [1★, 3★]
## 判据(粗筛, 结果再逐件人工看代码):
##   第二件收益 g2 = B − A  对比  第一件收益 g1 = A − Z ; g2 明显小于 g1 ⇒ 第二件没各自生效
##   召唤物个数 B < 2×A ⇒ 召唤只出一份
##   C ≠ D ⇒ 结果跟装备栏顺序有关(典型: 后一件的星级覆盖前一件)
## 产出量 = 敌方承伤 + 我方实际回血 + 我方实际获盾。
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/probes/_probe_dup_equip.tscn --quit-after 40000000
##   EQ_ONLY=p2eq_058,p2eq_032 只跑这几件 · STEPS=1500 战斗步数

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const EQS := preload("res://scripts/gamedata/equip_stats.gd")
const DT := 1.0 / 60.0

var s = null
var names: Dictionary = {}
var steps := 1500


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	RB.DEBUG_EDIT = true
	var f := FileAccess.open("res://data/phase2-equipment.json", FileAccess.READ)
	for e in JSON.parse_string(f.get_as_text()):
		names[str(e["id"])] = str(e.get("name", ""))
	var ids: Array = EQS.STATS.keys()
	ids.sort()
	var only: String = OS.get_environment("EQ_ONLY")
	if only != "":
		ids = Array(only.split(","))
	if OS.get_environment("STEPS") != "":
		steps = int(OS.get_environment("STEPS"))
	print("[DUP] 件数 %d  步数 %d" % [ids.size(), steps])
	var z: Dictionary = await _run("", [])
	print("[DUP] Z 不带: 产出 %d" % int(z["out"]))
	var flagged := 0
	for iid in ids:
		var a: Dictionary = await _run(str(iid), [3])
		var b: Dictionary = await _run(str(iid), [3, 3])
		var c: Dictionary = await _run(str(iid), [3, 1])
		var d: Dictionary = await _run(str(iid), [1, 3])
		var g1: float = float(a["out"]) - float(z["out"])
		var g2: float = float(b["out"]) - float(a["out"])
		var flags: Array = []
		## v2(份号上线后): 每件各自的账 —— B 的第二件要有自己的产出; 3★ 那件的账不随它排第几变
		var k2: String = str(iid) + "#2"
		var bt1: float = float(b["by_ck"].get(str(iid), 0.0)); var bt2: float = float(b["by_ck"].get(k2, 0.0))
		var c3: float = float(c["by_ck"].get(str(iid), 0.0)); var c1: float = float(c["by_ck"].get(k2, 0.0))
		var d1: float = float(d["by_ck"].get(str(iid), 0.0)); var d3: float = float(d["by_ck"].get(k2, 0.0))
		if bt1 > 50.0 and bt2 < 0.5 * bt1:
			flags.append("第二件账少(%d vs %d)" % [int(bt2), int(bt1)])
		if maxf(c3, d3) > 50.0 and absf(c3 - d3) / maxf(c3, d3) > 0.3:
			flags.append("3★那件随位置变(%d vs %d)" % [int(c3), int(d3)])
		if maxf(c1, d1) > 50.0 and absf(c1 - d1) / maxf(c1, d1) > 0.3:
			flags.append("1★那件随位置变(%d vs %d)" % [int(c1), int(d1)])
		if float(a["tally"]) <= 1.0 and float(b["tally"]) <= 1.0:
			flags.append("无账(另验)")
		if g1 > 80.0 and g2 < 0.5 * g1:
			flags.append("第二件收益低(%.0f%%)" % (100.0 * g2 / g1))
		if int(a["summons"]) > 0 and int(b["summons"]) < 2 * int(a["summons"]):
			flags.append("召唤物 %d→%d" % [int(a["summons"]), int(b["summons"])])
		var cd_den: float = maxf(1.0, maxf(absf(float(c["out"])), absf(float(d["out"]))))
		if absf(float(c["out"]) - float(d["out"])) / cd_den > 0.03 or int(c["summons"]) != int(d["summons"]):
			flags.append("顺序相关(C%d≠D%d)" % [int(c["out"]), int(d["out"])])
		var strict: bool = OS.get_environment("V1") != ""
		if strict and float(a["tally"]) > 80.0 and float(b["tally"]) < 1.6 * float(a["tally"]):
			flags.append("装备账 %d→%d" % [int(a["tally"]), int(b["tally"])])
		if not strict:
			flags = flags.filter(func(x): return not str(x).begins_with("顺序相关") and not str(x).begins_with("第二件收益低"))
		if not flags.is_empty():
			flagged += 1
		print("[DUP] %s %s %s | g1 %d g2 %d | 召唤 A%d B%d C%d D%d | 账 A%d B[%d,%d] C[3★%d,1★%d] D[1★%d,3★%d] | C%d D%d %s" % [
			"✗" if not flags.is_empty() else "✓", iid, names.get(iid, "?"),
			int(g1), int(g2), int(a["summons"]), int(b["summons"]), int(c["summons"]), int(d["summons"]),
			int(a["tally"]), int(bt1), int(bt2), int(c3), int(c1), int(d1), int(d3), int(c["out"]), int(d["out"]), " ".join(flags)])
	print("[DUP] DONE 标记 %d / %d" % [flagged, ids.size()])
	get_tree().quit(0)


func _mk(id: String, side: String, pos: Vector2) -> Dictionary:
	return s._spawn._make_unit(id, side, pos)


func _run(iid: String, stars: Array) -> Dictionary:
	if s != null:
		s.queue_free()
		await get_tree().process_frame
	s = RB.new()
	add_child(s)
	for _j in range(6):
		await get_tree().process_frame
	s._deterministic = true
	s.set_process(false)
	s._battle_rng.seed = 20261113
	s._dl_sys._dl_clear_units()
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = _mk("basic", "left", c + Vector2(-60, 0))
	u["maxHp"] = 6000.0; u["hp"] = 3000.0; u["atk"] = 120.0; u["no_move"] = true
	u["energy"] = 100.0
	var al: Dictionary = _mk("basic", "left", c + Vector2(-120, 30))
	al["maxHp"] = 6000.0; al["hp"] = 3000.0; al["no_basic"] = true; al["no_move"] = true
	var es: Array = []
	for i in range(3):
		var e: Dictionary = _mk("basic", "right", c + Vector2(10.0 + 50.0 * float(i), -20.0 + 20.0 * float(i)))
		e["maxHp"] = 1.0e6; e["hp"] = 1.0e6; e["atk"] = 25.0; e["no_move"] = true
		es.append(e)
	var fod: Dictionary = _mk("basic", "right", c + Vector2(30, 40))
	fod["maxHp"] = 400.0; fod["hp"] = 400.0; fod["atk"] = 1.0; fod["no_move"] = true
	var far: Dictionary = _mk("basic", "right", c + Vector2(420, 0))
	far["maxHp"] = 1.0e6; far["hp"] = 1.0e6; far["atk"] = 1.0; far["no_move"] = true
	s._units.clear()
	for x in [u, al, fod, far]:
		s._units.append(x)
	s._units.append_array(es)
	s._edit_mode = false
	s._over = false
	var eqs: Array = []
	for st in stars:
		eqs.append({"id": iid, "star": int(st)})
	u["equips"] = eqs
	u["eq_state"] = {} if iid == "" else {iid: {}}
	s._equip_sys._stats._eq_apply_all_stats()
	u["range_add"] = float(u.get("range_add", 0.0)) + 400.0
	if iid == "p2eq_062":
		(u["buffs"] as Array).append({"stat": "dodge", "amount": 0.4, "pct": false, "until": 1.0e9, "src_eq": "probe"})
		s._recalc_stats(u)
	var seen: Array = []
	for k in range(steps):
		s._sim_step(DT, false, false)
		if k % 4 == 0:
			_scan_summons(seen)
		if k % 8 == 0:
			await get_tree().process_frame
	if u.get("alive", false):
		u["hp"] = 1.0
		s._kill(u, es[0])
	for k in range(360):
		s._sim_step(DT, false, false)
		if k % 4 == 0:
			_scan_summons(seen)
		if k % 8 == 0:
			await get_tree().process_frame
	s._over = true
	var out := 0.0
	var tally := 0.0
	var by_ck: Dictionary = {}
	for x in s._units:
		var xd: Dictionary = x
		if str(xd.get("side", "")) == "right":
			out += float(xd.get("_st_taken", 0))
		else:
			out += float(xd.get("_st_heal", 0)) + float(xd.get("_st_shield", 0))
		var allr: Dictionary = xd.get("_st_eq", {})
		for ck in allr.keys():
			if EquipCk.base_id(str(ck)) != iid or iid == "":
				continue
			var row: Dictionary = allr[ck]
			for kk in row.keys():
				tally += float(row[kk])
				by_ck[str(ck)] = float(by_ck.get(str(ck), 0.0)) + float(row[kk])
	return {"out": out, "summons": seen.size(), "tally": tally, "by_ck": by_ck}


func _scan_summons(seen: Array) -> void:
	for x in s._units:
		var xd: Dictionary = x
		if not xd.get("is_summon", false) or str(xd.get("side", "")) != "left":
			continue
		var dup := false
		for y in seen:
			if is_same(y, xd):
				dup = true
				break
		if not dup:
			seen.append(xd)
