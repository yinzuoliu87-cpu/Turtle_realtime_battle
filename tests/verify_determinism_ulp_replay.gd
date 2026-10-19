extends Node
## verify_determinism_ulp_replay.gd —— 跨芯片浮点确定性 · **产品回放**那一半(2026-10-10)
##
## 由来与扰动模型见 `verify_determinism_ulp.gd` 头注(DetMath.perturb = 每 N 次平台相关调用 ±1 ulp,
## 在一台 x86 上模拟 iPad 的 ARM 芯片)。这一份走**产品自己的回放校验**(ReplayRecorder 每 60 步一个校验点):
##   U3 交互模式(帧长乱跳、人点幕布/按开打)录双路真对局 → **带扰动**重放:
##      · 加固后(默认): 3 局都必须校验点全对、放完(diverged_at = -1)
##      · 加固前(DetMath.raw): 第 1 局必须停在某个校验点 —— 证明扰动在产品路径上咬得住。
##        实测停在第 360~480 步; 真机 iPad 录像在 PC 上的分叉是第 180~600 步, 同一个量级。
## 拆成单独一份是为了门禁并行(与 verify_determinism_ulp 各约 3~4 分钟)。
##
## 跑法: <godot> --headless --path . res://tests/verify_determinism_ulp_replay.tscn --quit-after 60000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")

const STRIDE := 7
const PAT_REC := [0.016, 0.004, 0.04, 0.0167, 0.025, 0.05, 0.009, 0.0333]
const PAT_PLAY := [0.05, 0.0167, 0.004, 0.03, 0.012, 0.0167, 0.045, 0.02]
const MAX_FRAMES := 30000
## 几局: 统领 × 对手机器人种子 —— 挑用角度/弹道/环绕/位移/寻路的龟。raw 对照只跑第 1 局(省帧)。
const MATCHES := [
	{"leaders": ["star", "phoenix", "rocket"], "bot": 11, "trainer": "hook", "raw": true},
	{"leaders": ["crystal", "lava", "headless"], "bot": 22, "trainer": "hook", "raw": false},
	{"leaders": ["pirate", "cyber", "hiding"], "bot": 33, "trainer": "hook", "raw": false},
]

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	_ok("分母 · 正式版默认: DetMath.raw=false、perturb=0", not DetMath.raw and DetMath.perturb == 0)
	for m in MATCHES:
		await _u3(m)
	print("")
	print("  [量] 本门禁共走了 %d 帧(run-tests.sh frames_for 预算要比它大)" % Engine.get_process_frames())
	if _fail == 0:
		print("ALL PASS — 跨芯片浮点确定性·产品回放 (%d/%d)" % [_n, _n])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _n - _fail])
	DetMath.raw = false
	DetMath.reset_perturb(0)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────── U3 产品回放 ───────────────────────────────

func _setup_gs(gs, m: Dictionary) -> void:
	gs.reset_dual_lane()
	gs.test_mode = true
	gs.tutorial_active = false
	gs.week_phase = "gauntlet"
	var ld: Array = m["leaders"]
	gs.season_leaders = ld.duplicate()
	gs.left_team.assign(gs.season_leaders)
	gs.dual_lineup = {
		"top": [
			{"kind": "leader", "slot": 0, "id": ld[0]},
			{"kind": "minion", "role": "front", "equips": []},
		],
		"bottom": [
			{"kind": "leader", "slot": 1, "id": ld[1], "equips": []},
			{"kind": "leader", "slot": 2, "id": ld[2], "equips": []},
			{"kind": "minion", "role": "back", "equips": []},
		],
	}
	## 统领带上几件用角度/弹道/环绕的装备(③ 那一套里挑)
	gs.persistent_equipped = {str(ld[0]): [{"id": "p2eq_032", "star": 3}, {"id": "p2eq_058", "star": 3}, {"id": "p2eq_073", "star": 3}]}
	gs.season_level = 4
	gs.trainer_skill = str(m["trainer"])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(m["bot"])
	gs.dual_ghost = Backend.make_bot(3, rng)
	gs.dual_active = true


func _u3(m: Dictionary) -> void:
	## ★静态的 DEBUG_EDIT 若被别处(场景表 `_det_scenarios.run`)置了真, 双路对局会以调试场方式建场,
	##   第一路打完就卡在 _dl_state="" 永远打不完(实测: 跑满 30000 帧、727 个校验点、state 空)。拆文件后照样防一手。
	RB.DEBUG_EDIT = false
	var gs = get_node_or_null("/root/GameState")
	var tag := "%s / 机器人 %d" % [str(m["leaders"]), int(m["bot"])]
	for raw in ([false, true] if bool(m.get("raw", false)) else [false]):
		DetMath.raw = raw
		DetMath.reset_perturb(0)
		OS.set_environment("TURTLE_SEED", "")
		_setup_gs(gs, m)
		var rec_run: Dictionary = await _run(PAT_REC, true)
		var rec: Dictionary = rec_run.get("rec", {})
		_ok("  分母 · %s%s · 录到一局(打完 %s · 校验点 %d 个)" % [tag, " [raw]" if raw else "", str(rec_run["state"]),
			(rec.get("cps", []) as Array).size()], not rec.is_empty() and str(rec_run["state"]) == "done"
			and (rec.get("cps", []) as Array).size() > 5)
		if rec.is_empty():
			continue
		DetMath.reset_perturb(STRIDE)
		ReplayRecorder.begin_play(rec)
		var pl: Dictionary = await _run(PAT_PLAY, false)
		var hits: int = DetMath.perturb_hits
		DetMath.reset_perturb(0)
		if not raw:
			_ok("★★U3 %s · 加固后 · 带扰动重放 ⇒ 校验点 %d 个全对、放完(diverged_at=%d %s)" % [tag, int(pl["cps"]),
				int(pl["div"]), str(pl["why"])], int(pl["div"]) < 0 and bool(pl["finished"]) and int(pl["cps"]) > 5)
		else:
			_ok("★★U3 %s · 加固前(raw) · 带扰动重放 ⇒ 必须停下(第 %d 步 %s · 扰动打中 %d 次)" % [tag, int(pl["div"]),
				str(pl["why"]), hits], int(pl["div"]) >= 0 and hits > 0)
	DetMath.raw = false


## 跑一局(与 verify_replay_roundtrip._run 同一个驱动形状: 帧长由我喂、扮演玩家点幕布/按开打)。
func _run(pat: Array, as_player: bool) -> Dictionary:
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	var st_frames := 0
	var last_state := ""
	var done_frames := 0
	var i := 0
	while i < MAX_FRAMES:
		var st: String = str(s._dl_state)
		if st != last_state:
			if OS.get_environment("ULP_TRACE") != "":
				print("    [态] 帧 %d 步 %d: %s → %s" % [i, int(s._sim_step_n), last_state, st])
			last_state = st
			st_frames = 0
		st_frames += 1
		if as_player:
			if (st == "overview" or st == "lane_settle") and st_frames == 9:
				s._dl_sys._dl_present_click()
		s._process(float(pat[i % pat.size()]))
		await get_tree().process_frame
		i += 1
		if s._replay.diverged_at >= 0:
			break
		if str(s._dl_state) == "done":
			done_frames += 1
			if done_frames > 30:
				break
	var out := {"state": str(s._dl_state), "div": int(s._replay.diverged_at), "why": str(s._replay.diverge_why),
		"cps": int(s._replay.cp_checked), "finished": bool(s._replay.finished),
		"rec": (s._replay.rec as Dictionary).duplicate(true) if s._replay.mode == "rec" else {}}
	for _g in range(10):
		await get_tree().process_frame
	s.queue_free()
	for _g in range(4):
		await get_tree().process_frame
	return out
