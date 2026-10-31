extends Node
## _probe_tally_real.gd —— 装备统计逐笔对账: 真实对局版(只读探针, 不进门禁; 2026-10-31)
##
## 单件小场(_probe_tally_truth)量不到「多件 + 羁绊 + 龟被动」叠在一起的情形。这里摆 3v3 真龟、
## 每队按类型凑出羁绊, 走调试场真开打, 每一笔按调用栈判真值; 只查【多记】这一类
## (多件装备时「漏记」分不清该记哪件, 那一类由单件探针守)。
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/_probe_tally_real.tscn --quit-after 40000
##   ROUNDS=3 换 3 组阵容 · FRAMES=1500 每组帧数

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const EQS := preload("res://scripts/gamedata/equip_stats.gd")
const HOOK := preload("res://tests/_tally_truth_hook.gd")
## 真值判法认不出的「装备效果写在装备目录外」的函数(单件探针逐个核过: 都是那件装备自己的效果)
const EQ_ELSEWHERE := ["_dumbbell_hit", "_throw_dumbbell", "_fuel_bottle_hit", "_summon_walking_bear",
	"_crystal_sweep_hits", "shield_synergy_system.gd:tick"]

const TEAMS := [
	[["ghost", "stone", "basic"], ["lightning", "dice", "pirate"]],
	[["hunter", "phoenix", "ninja"], ["two_head", "fortune", "line"]],
	[["bubble", "cyber", "rainbow"], ["shell", "space", "lava"]],
]


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var by_type: Dictionary = {}
	var ids: Array = EQS.STATS.keys()
	ids.sort()
	var P2 = load("res://scripts/gamedata/phase2_types.gd")
	for k in ids:
		var t: String = str(P2.type_of(str(k)))
		var l: Array = by_type.get(t, [])
		l.append(str(k))
		by_type[t] = l
	var types: Array = by_type.keys()
	types.sort()
	print("[REAL] 类型: ", types)
	var rounds: int = int(OS.get_environment("ROUNDS")) if OS.get_environment("ROUNDS") != "" else 3
	var frames: int = int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 1500
	var total_bad := 0
	for r in range(rounds):
		var team: Array = TEAMS[r % TEAMS.size()]
		RB.DEBUG_EDIT = true
		var s = RB.new()
		add_child(s)
		await get_tree().process_frame
		await get_tree().process_frame
		var h = HOOK.new(s)
		s._equip_sys.tally = h
		s._debug._edit_clear()
		s._edit_dummy_killable = true
		s._edit_dummy_hp = 40000.0
		s._edit_full_energy = true
		var ti := r * 6
		var carried: Dictionary = {}    # 单位名 → 装备 id 列表
		for side_i in range(2):
			var side: String = "left" if side_i == 0 else "right"
			for j in range(3):
				var pid: String = str(team[side_i][j])
				var u: Dictionary = s._debug._edit_place_unit(pid, side,
					Vector2(320.0 if side == "left" else 760.0, 240.0 + 120.0 * float(j)))
				## 每只龟拿同一类型的 3 件(凑羁绊), 类型轮换
				var t: String = str(types[(ti + side_i * 3 + j) % types.size()])
				var pool: Array = by_type[t]
				var el: Array = []
				for q in range(mini(3, pool.size())):
					el.append({"id": str(pool[(q + r) % pool.size()]), "star": 3})
				u["_edit_equips"] = el
				carried["%s:%s" % [side, pid]] = el.map(func(x): return str(x["id"]))
		print("[REAL] 第 %d 组: %s" % [r + 1, str(carried)])
		s._debug._edit_start_battle()
		for _i in range(frames):
			await get_tree().process_frame
		total_bad += _report(h, s)
		s.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("[REAL] DONE 多记处数 %d" % total_bad)
	get_tree().quit(0)


func _known(e: Dictionary) -> bool:
	for k in EQ_ELSEWHERE:
		if str(e["stk"]).contains(str(k).get_basename()) or str(e["where"]).contains(str(k)):
			return true
	return false


func _report(h, s) -> int:
	var over: Dictionary = {}
	var samples: Dictionary = {}
	var n_ev := 0
	var cred_tot := 0.0
	for e in h.events:
		n_ev += 1
		var cred := 0.0
		for k in (e["credited"] as Dictionary).keys():
			cred += float(e["credited"][k])
		cred_tot += cred
		if cred <= 0.5:
			continue
		var tr: String = str(e["truth"])
		if tr in ["EQ", "SUMMON", "DEFER-EQ", "DOT"] or (tr.begins_with("DEFER-") and not (tr in ["DEFER-NONE", "DEFER-REACT", "DEFER-SYN"])):
			continue
		if _known(e):
			continue
		var wk: String = "%s %s %s @ %s → %s" % [tr, e["kind"], e["key"], e["where"], str((e["credited"] as Dictionary).keys())]
		over[wk] = float(over.get(wk, 0.0)) + cred
		if not samples.has(wk):
			samples[wk] = str(e["stk"])
	print("[REAL]   事件 %d · 装备账合计 %.0f · 多记 %d 处" % [n_ev, cred_tot, over.size()])
	for wk in over.keys():
		print("[REAL]   多记 %s = %.0f" % [wk, float(over[wk])])
		print("[REAL]       栈: %s" % str(samples[wk]))
	return over.size()
