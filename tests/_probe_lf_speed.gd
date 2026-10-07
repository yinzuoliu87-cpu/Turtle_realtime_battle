extends Node
## 探针(不进门禁): 同一份录像按 1/4/8 步每帧播, 看哪一档分叉、分叉在第几步、那一刻在什么阶段。
const Backend := preload("res://scripts/net/backend.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _gs
var _fp_rec: Dictionary = {}
var _fp_bad := ""
var _cur = null
var _mode := "rec"
var _hp_rec: Dictionary = {}
var _hp_play: Dictionary = {}
var _first_bad := -1


func _on_step() -> void:
	var n := int(_cur._sim_step_n)
	var f: String = ReplayRecorder.fingerprint(_cur)
	var hs: Array = []
	for u in _cur._units:
		hs.append("%s:%.4f/%.3f" % [str(u.get("id", "")), float(u.get("hp", 0.0)), float(u.get("shield", 0.0))])
	if _mode == "rec":
		_hp_rec[n] = hs
	else:
		_hp_play[n] = hs
	if _mode == "rec":
		_fp_rec[n] = f
	elif _first_bad < 0 and _fp_rec.has(n) and str(_fp_rec[n]) != f:
		_first_bad = n
	elif _fp_bad == "" and _fp_rec.has(n) and str(_fp_rec[n]) != f:
		var a: PackedStringArray = str(_fp_rec[n]).split("|")
		var b: PackedStringArray = f.split("|")
		var diffs: Array = []
		for i in range(maxi(a.size(), b.size())):
			var x := a[i] if i < a.size() else "<none>"
			var y := b[i] if i < b.size() else "<none>"
			if x != y:
				diffs.append("REC " + x + "\n      PLAY " + y)
		_fp_bad = "step %d state=%s diffs=%d\n   %s" % [n, str(_cur._dl_state), diffs.size(), "\n   ".join(PackedStringArray(diffs.slice(0, 4)))]


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	OS.set_environment("TURTLE_SEED", "")
	_gs.test_mode = true
	_gs.reset_dual_lane()
	_gs.tutorial_active = false
	_gs.onboarded = true
	_gs.week_phase = "ranked"
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []}, {"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []}, {"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}]}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(OS.get_environment("PSEED")) if OS.has_environment("PSEED") else 20261008
	_gs.dual_ghost = Backend.make_bot(3, rng)
	_gs.dual_active = true
	_gs.account_id = "11111111-2222-4333-8444-555555555555"
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	_cur = s
	s.sim_stepped.connect(_on_step)
	await get_tree().process_frame
	var last := ""
	var stf := 0
	var fights := 0
	var i := 0
	var trans: Array = []
	while i < 6000 and not s._replay.finished:
		var st: String = str(s._dl_state)
		if st != last:
			trans.append("%d:%s" % [int(s._sim_step_n), st])
			last = st
			stf = 0
		stf += 1
		if (st == "overview" or st == "lane_settle") and stf == 9:
			s._dl_sys._dl_present_click()
		elif st == "place" and stf == 20 and is_instance_valid(s._dl_go_btn):
			s._dl_go_btn.pressed.emit()
			fights += 1
		elif st == "fight" and fights >= 2 and stf == 200:
			s._do_surrender()
		s._process(0.05)
		if i % 4 == 0:
			await get_tree().process_frame
		i += 1
	var rec: Dictionary = s._replay.rec.duplicate(true)
	print("PROBE rec steps=%d trans=%s" % [int((rec.get("end", {}) as Dictionary).get("s", -1)), str(trans)])
	s.queue_free()
	await _frames(4)
	for k in [1, 4, 8]:
		for mode in ["perframe", "await_each"]:
			ReplayRecorder.begin_play(rec)
			var b = RB.new()
			add_child(b)
			b.set_process(false)
			_cur = b
			_mode = "play"
			_fp_bad = ""
			b.sim_stepped.connect(_on_step)
			await get_tree().process_frame
			var g := 0
			while g < 20000 and not b._replay.finished and b._replay.diverged_at < 0:
				b._sim_accum = 0.0
				b._advance_sim_accum((float(k) + 0.5) * b.SIM_DT)
				g += 1
				if mode == "await_each" or g % 8 == 0:
					await get_tree().process_frame
			print("PROBE k=%d mode=%s finished=%s div=%d why=%s state=%s" % [k, mode, str(b._replay.finished), int(b._replay.diverged_at),
				str(b._replay.diverge_why), str(b._dl_state)])
			print("PROBE first fp diff: ", _fp_bad)
			if _first_bad > 0:
				for q in range(_first_bad - 40, _first_bad + 3):
					var a: Array = _hp_rec.get(q, [])
					var c: Array = _hp_play.get(q, [])
					var la: Array = []
					for z in range(mini(a.size(), c.size())):
						if str(a[z]).begins_with("space") or a[z] != c[z]:
							la.append("R=%s P=%s" % [a[z], c[z]])
					print("PROBE  s=%d %s" % [q, str(la)])
			_first_bad = -1
			_hp_play = {}
			b.queue_free()
			ReplayRecorder.end_play()
			await _frames(4)
	get_tree().quit(0)
