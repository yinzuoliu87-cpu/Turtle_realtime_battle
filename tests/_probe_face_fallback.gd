extends Node
## _probe_face_fallback.gd — 量「sim 读 face_right 的两个兜底分支」在真实双路对局里走不走得到。
## 方案书 docs/plans/20261003-跨设备回放.md §9.6。不进门禁, 手跑:
##   PROBE_SEED=1 godot --headless --path . res://tests/_probe_face_fallback.tscn --quit-after 900000
## 计数靠产品代码里**临时**插的 `Engine.set_meta("fb_*")` 两行(量完逐字节还原, 不提交)。
## 不插计数时本探针仍可跑: 打印每局 face_right 被「渲染」改过几次(对照用)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const PAT := [0.016, 0.004, 0.04, 0.0167, 0.025, 0.05, 0.009, 0.0333]
const MAX_FRAMES := 40000
const POOL := ["basic", "stone", "bamboo", "angel", "ice", "ninja", "two_head", "ghost", "diamond", "fortune",
	"dice", "rainbow", "gambler", "hunter", "pirate", "candy", "bubble", "line", "lightning", "phoenix",
	"lava", "cyber", "crystal", "chest", "space", "hiding", "headless", "shell"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	## ★手跑也不许打真网络: project.godot 里填着真 Supabase 地址; 空白串 = 后端整层停用(与 run-tests.sh 同)
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	OS.set_environment("TURTLE_SEED", "")
	var base := int(OS.get_environment("PROBE_SEED")) if OS.has_environment("PROBE_SEED") else 1
	var n := int(OS.get_environment("PROBE_N")) if OS.has_environment("PROBE_N") else 3
	var tot := {}
	for k in range(n):
		var rng := RandomNumberGenerator.new()
		rng.seed = base * 1000 + k
		var L: Array = ["headless"]
		while L.size() < 3:
			var c: String = POOL[rng.randi() % POOL.size()]
			if not c in L: L.append(c)
		gs.reset_dual_lane()
		gs.test_mode = true
		gs.tutorial_active = false
		gs.week_phase = "ranked"
		gs.season_leaders = L
		gs.left_team.assign(L)
		gs.dual_lineup = {
			"top": [{"kind": "leader", "slot": 0, "id": L[0]}, {"kind": "minion", "role": "back", "equips": []}],
			"bottom": [{"kind": "leader", "slot": 1, "id": L[1], "equips": []},
				{"kind": "leader", "slot": 2, "id": L[2], "equips": []}, {"kind": "minion", "role": "back", "equips": []}],
		}
		gs.persistent_equipped = {}
		gs.loadouts = {"headless": 3}
		gs.season_level = 10
		gs.trainer_skill = ["hook", "whistle", "glacier", "magic_stone"][k % 4]
		gs.dual_ghost = Backend.make_bot(10 + rng.randi() % 30, rng)
		gs.dual_active = true
		for m in ["fb_rocket", "fb_scythe", "fb_rocket_call", "fb_scythe_call"]:
			Engine.set_meta(m, 0)
		var r: Dictionary = await _run()
		var line := "[probe] 局 %d %s 步=%d 渲染改朝向=%d" % [k, str(L), int(r["steps"]), int(r["render_flips"])]
		for m in ["fb_rocket_call", "fb_rocket", "fb_scythe_call", "fb_scythe"]:
			var v := int(Engine.get_meta(m, 0))
			line += " %s=%d" % [m, v]
			tot[m] = int(tot.get(m, 0)) + v
		print(line)
	print("[probe] 合计 ", tot)
	print("PROBE DONE")
	get_tree().quit(0)


func _run() -> Dictionary:
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	var st_frames := 0
	var last_state := ""
	var done_frames := 0
	var render_flips := 0
	var i := 0
	while i < MAX_FRAMES:
		var st: String = str(s._dl_state)
		if st != last_state:
			last_state = st
			st_frames = 0
		st_frames += 1
		if (st == "overview" or st == "lane_settle") and st_frames == 9:
			s._dl_sys._dl_present_click()
		elif st == "place" and st_frames == 6 and is_instance_valid(s._dl_go_btn):
			s._dl_go_btn.pressed.emit()
		var pre := {}
		s._advance_sim_accum(float(PAT[i % PAT.size()]))
		for u in s._units:
			pre[u.get("id", "") + str(u.get("side", ""))] = u.get("face_right", null)
		s._render._render_step(float(PAT[i % PAT.size()]), s._hitstop > 0.0, not s._timestop._ts_active.is_empty())
		for u in s._units:
			if pre.get(u.get("id", "") + str(u.get("side", "")), null) != u.get("face_right", null):
				render_flips += 1
		await get_tree().process_frame
		i += 1
		if str(s._dl_state) == "done":
			done_frames += 1
			if done_frames > 30:
				break
	var out := {"steps": int(s._sim_step_n), "render_flips": render_flips}
	for _g in range(10):
		await get_tree().process_frame
	s.queue_free()
	for _g in range(4):
		await get_tree().process_frame
	return out
