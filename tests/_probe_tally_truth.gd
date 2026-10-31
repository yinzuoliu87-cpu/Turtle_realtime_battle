extends Node
## _probe_tally_truth.gd —— 装备统计逐笔对账(只读探针, 不进门禁; 2026-10-31)
##
## 用户 10-31:「有些装备它明明没有治疗效果，为什么它有治疗呢？…二费的那个箭袋，装备伤害统计肯定是有问题的」。
## 每件装备一个干净小场(同 _probe_eq_tally_coverage), 携带者额外带 30% 生命偷取(吸血是最常见的「反应治疗」),
## 每一笔伤害/治疗/护盾按调用栈判真值(见 _tally_truth_hook.gd), 与 EquipTally 实记逐笔对账。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/_probe_tally_truth.tscn --quit-after 4000000
##   EQ_ONLY=p2eq_075,p2eq_001 只跑这几件 · LS=0 不加吸血 · VERBOSE=1 打每件的明细

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const EQS := preload("res://scripts/gamedata/equip_stats.gd")
const HOOK := preload("res://tests/_tally_truth_hook.gd")
const DT := 1.0 / 60.0

var s = null
var names: Dictionary = {}


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
	var ls: float = 0.3 if OS.get_environment("LS") != "0" else 0.0
	print("[TRUTH] 件数 %d  携带者吸血 %.2f" % [ids.size(), ls])
	var bad_n := 0
	for iid in ids:
		if s != null:
			s.queue_free()
			await get_tree().process_frame
		s = RB.new()
		add_child(s)
		for _j in range(6):
			await get_tree().process_frame
		s._deterministic = true
		s.set_process(false)
		var h = HOOK.new(s)
		s._equip_sys.tally = h
		await _run(str(iid), ls)
		if _report(str(iid), h):
			bad_n += 1
	print("[TRUTH] DONE 有问题的件数 %d / %d" % [bad_n, ids.size()])
	get_tree().quit(0)


func _mk(id: String, side: String, pos: Vector2) -> Dictionary:
	return s._spawn._make_unit(id, side, pos)


func _run(iid: String, ls: float) -> void:
	s._battle_rng.seed = 20261031
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
	## 远处一个敌人: 给 075 这类「按距离增伤 / 打最密集处」的装备一个远目标
	var far: Dictionary = _mk("basic", "right", c + Vector2(420, 0))
	far["maxHp"] = 1.0e6; far["hp"] = 1.0e6; far["atk"] = 1.0; far["no_move"] = true
	s._units.clear()
	for x in [u, al, fod, far]:
		s._units.append(x)
	s._units.append_array(es)
	s._edit_mode = false
	s._over = false
	u["equips"] = [{"id": iid, "star": 3}]
	u["eq_state"] = {iid: {}}
	s._equip_sys._stats._eq_apply_all_stats()
	u["range_add"] = float(u.get("range_add", 0.0)) + 400.0
	u["lifesteal"] = float(u.get("lifesteal", 0.0)) + ls
	if iid == "p2eq_062":
		(u["buffs"] as Array).append({"stat": "dodge", "amount": 0.4, "pct": false, "until": 1.0e9, "src_eq": "probe"})
		s._recalc_stats(u)
	for k in range(1500):
		s._sim_step(DT, false, false)
		if k % 8 == 0:
			await get_tree().process_frame
	if u.get("alive", false):
		u["hp"] = 1.0
		s._kill(u, es[0])
	for k in range(360):
		s._sim_step(DT, false, false)
		if k % 8 == 0:
			await get_tree().process_frame
	s._over = true


## 返回 true = 这件有对不上的账
const SHOULD := ["EQ", "SUMMON", "DEFER-EQ", "DEFER-SUMMON"]
func _report(iid: String, h) -> bool:
	## per[kk] = {should, cred_should, over, unk, unk_cred}; kk = dmg:phy / heal:heal / shield:shield
	var per: Dictionary = {}
	var by: Dictionary = {}          # 展示用: by[truth][kk] = [实, 记]
	var wrong_dir := 0.0
	var wheres: Dictionary = {}
	var samples: Dictionary = {}
	var other_iid: Dictionary = {}
	for e in h.events:
		var cred := 0.0
		for k in (e["credited"] as Dictionary).keys():
			cred += float(e["credited"][k])
			if not str(k).begins_with(iid + "|"):
				other_iid[k] = float(other_iid.get(k, 0.0)) + float(e["credited"][k])
		var toward_ok: bool = (str(e["tgt_side"]) == "right") == (str(e["kind"]) == "dmg")
		if not toward_ok:
			wrong_dir += cred
			continue
		var tr: String = str(e["truth"])
		var kk: String = str(e["kind"]) + ":" + str(e["key"])
		var b: Dictionary = by.get(tr, {})
		var bb: Array = b.get(kk, [0.0, 0.0])
		b[kk] = [float(bb[0]) + float(e["amt"]), float(bb[1]) + cred]
		by[tr] = b
		if tr == "DOT":
			continue
		var r: Dictionary = per.get(kk, {"should": 0.0, "cred_should": 0.0, "over": 0.0, "unk": 0.0, "unk_cred": 0.0})
		if tr in SHOULD:
			r["should"] = float(r["should"]) + float(e["amt"])
			r["cred_should"] = float(r["cred_should"]) + cred
			if float(e["amt"]) - cred > 0.5:
				var wk: String = "漏记 %s %s @ %s" % [tr, kk, str(e["where"])]
				wheres[wk] = float(wheres.get(wk, 0.0)) + float(e["amt"]) - cred
				if not samples.has(wk): samples[wk] = str(e["stk"])
		elif tr.begins_with("DEFER-") and not (tr in ["DEFER-NONE", "DEFER-REACT", "DEFER-SYN"]):
			r["unk"] = float(r["unk"]) + float(e["amt"])
			r["unk_cred"] = float(r["unk_cred"]) + cred
		else:
			r["over"] = float(r["over"]) + cred
			if cred > 0.5:
				var wk2: String = "多记 %s %s @ %s" % [tr, kk, str(e["where"])]
				wheres[wk2] = float(wheres.get(wk2, 0.0)) + cred
				if not samples.has(wk2): samples[wk2] = str(e["stk"])
		per[kk] = r
	var direct_by: Dictionary = {}
	for d in h.direct:
		var dk: String = ("dmg:" + str(d["key"])) if str(d["key"]) in ["phy", "mag", "tru"] else (str(d["key"]) + ":" + str(d["key"]))
		direct_by[dk] = float(direct_by.get(dk, 0.0)) + float(d["amt"])
	var bad := false
	var line: String = "%s %s" % [iid, names.get(iid, "?")]
	for tr in by.keys():
		for kk in (by[tr] as Dictionary).keys():
			line += " | %s %s 实%d 记%d" % [tr, kk, int(by[tr][kk][0]), int(by[tr][kk][1])]
	for kk in per.keys():
		var r: Dictionary = per[kk]
		var under: float = float(r["should"]) - float(r["cred_should"]) - float(direct_by.get(kk, 0.0))
		if under > 1.0 or float(r["over"]) > 1.0:
			bad = true
		if float(r["unk"]) > 0.5:
			line += " | ?未定 %s 实%d 记%d" % [kk, int(r["unk"]), int(r["unk_cred"])]
	## DoT: 层全是装备加的 ⇒ 该全记; 全不是装备加的 ⇒ 一点都不该记
	var dot_types: Dictionary = {}
	for a in h.dot_adds:
		var dt: Dictionary = dot_types.get(str(a["type"]), {"eq": 0, "other": 0, "where": {}})
		if str(a["truth"]) in SHOULD:
			dt["eq"] = int(dt["eq"]) + int(a["stacks"])
		else:
			dt["other"] = int(dt["other"]) + int(a["stacks"])
		(dt["where"] as Dictionary)[str(a["truth"]) + "@" + str(a["where"])] = 1
		dot_types[str(a["type"])] = dt
	if by.has("DOT"):
		var all_eq := true
		var none_eq := true
		for t2 in dot_types.keys():
			if int(dot_types[t2]["other"]) > 0: all_eq = false
			if int(dot_types[t2]["eq"]) > 0: none_eq = false
		for kk in (by["DOT"] as Dictionary).keys():
			var a2: float = float(by["DOT"][kk][0]); var c2: float = float(by["DOT"][kk][1])
			if all_eq and not dot_types.is_empty() and a2 - c2 > 1.0:
				bad = true
				wheres["漏记 DOT %s (层全是装备加的)" % kk] = a2 - c2
			if none_eq and c2 > 1.0:
				bad = true
				wheres["多记 DOT %s (层没有一层是装备加的)" % kk] = c2
	if wrong_dir > 0.5:
		bad = true
		line += " | ⚠记到反方向 %d" % int(wrong_dir)
	if not other_iid.is_empty():
		bad = true
		line += " | ⚠记到别的件 %s" % str(other_iid)
	if not direct_by.is_empty():
		line += " | 直记 %s" % str(direct_by)
	if not dot_types.is_empty():
		line += " | 加层 %s" % str(dot_types)
	print(("[TRUTH] ✗ " if bad else "[TRUTH] ✓ ") + line)
	if bad or OS.get_environment("VERBOSE") != "":
		for wk in wheres.keys():
			print("[TRUTH]      %s = %d" % [wk, int(wheres[wk])])
			if OS.get_environment("VERBOSE") == "2" and samples.has(wk):
				print("[TRUTH]          栈: %s" % str(samples[wk]))
	return bad
