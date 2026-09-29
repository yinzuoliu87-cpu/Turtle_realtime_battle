extends Node
## verify_autopilot.gd — `SIM_AUTOPILOT` 的门禁。自动驾驶只干一件事:
## **进了摆位屏就替玩家按「▶ 开 打」**。这里量两条相反的判据 + 一条源码级的。
##
## ══════════════════════════════════════════════════════════════════════
##  ① 默认必须彻底关掉
## ══════════════════════════════════════════════════════════════════════
## 判据**不是**「变量是 false」, 而是**真走一遍摆位屏**:
##   · 分母: 钩子真的被调过(`hook_calls >= 1`)、摆位屏真的建起来了(「开打」钮在场且可见)
##   · 我的计数器: `drive_calls == 0`
##   · ★**产品自己的账**: 等够 `DWELL_PLACE × 2 + 60` 帧之后 `_dl_state` **仍然是 `"place"`**
##     —— 摆位阶段没结束, 它还在等人点。只数自己插的计数器等于插一行数一行必绿
##     (memory `fb-gate-must-measure-requirement-not-my-hook`)。
##
## ② 开开关: 同一个分母、同一段等待, `_dl_state` 走到 `"fight"`、「开打」钮被隐藏
##    (`_dl_start_fight()` 自己干的 —— 这是**产品的账**, 不是我的标记)。
##
## ③ 源码级: `autopilot.gd` 的代码行里一次都不许提经济字段 / `_units` / `_battle_rng` /
##    `change_scene_to_file`。配正控(同一套判法必须找得到 `press_go`), 否则它是个恒真式。
##
## ══════════════════════════════════════════════════════════════════════
##  「不改变战斗结果」那条判据在 `tests/_probe_autopilot_nochange.gd`
## ══════════════════════════════════════════════════════════════════════
## 它要跑**三场**对局(≈2000 帧), 而 `run-tests.sh` 的默认帧预算是 **500 帧**,
## 而那张登记表(`frames_for()`)本轮不由我改。要收进门禁: 改名
## `verify_autopilot_nochange.gd/.tscn` + 加一行 `verify_autopilot_nochange) echo 6000 ;;`。
## ⚠ 只改名不登记 = 半路被 `--quit-after` 掐断 = 没打 ALL PASS(CLAUDE.md §2 那个坑)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AP_SRC := "res://scripts/systems/sim/autopilot.gd"

const TEAM := ["basic", "stone", "bamboo"]
const WAIT_PLACE := 400        # 等摆位屏出现的帧上限
## 等"够久"的帧数: 比 DWELL_PLACE 多出一大截 —— 不开开关时这段等待之后
## 摆位阶段必须**还在**; 开开关时这段等待之内必须**已经结束**。
const OVERWAIT := SimAutopilot.DWELL_PLACE * 2 + 60

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
	await get_tree().process_frame
	GameState.test_mode = true      # 绝不写玩家存档(与 tests/_autoplay.gd 同一条双保险)
	## 开场演出(3 路总览 + 对阵预览 = 每路 10 秒)对本判据零信息量, 跳掉省一半帧。
	## `NO_PRESENT` 是项目自己给离线统计留的开关(dual_lane_flow.gd:19)。
	var was_np: bool = bool(DualLaneFlow.NO_PRESENT)
	DualLaneFlow.NO_PRESENT = true

	await _phase("off")
	await _phase("on")
	_phase_src()

	DualLaneFlow.NO_PRESENT = was_np
	OS.unset_environment(SimAutopilot.ENV)
	if _fail == 0:
		print("ALL PASS (%d/%d)" % [_n, _n])
	else:
		print("FAILED %d/%d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


## mode = "off" / "on"
func _phase(mode: String) -> void:
	var on: bool = mode == "on"
	print("── %s SIM_AUTOPILOT: 摆位屏 %s ──" % [
		("开" if on else "不带"), ("应该自己开打" if on else "应该一直等着人点")])
	if on:
		OS.set_environment(SimAutopilot.ENV, "1")
	else:
		OS.unset_environment(SimAutopilot.ENV)
	_ok("★分母: 开关状态和这一段要测的一致(enabled=%s)" % str(SimAutopilot.enabled()),
		SimAutopilot.enabled() == on)
	SimAutopilot.reset_ledger_for_test()

	## ── 走真入口: 建一场真的双路对局, 让它自己走到摆位屏 ──
	GameState.reset_dual_lane()
	GameState.dual_active = true
	GameState.season_leaders = TEAM.duplicate()
	GameState.dual_ghost = _fixed_ghost()
	GameState.get_dual_lineup()
	var s = RB.new()
	add_child(s)
	var w := 0
	while w < WAIT_PLACE and str(s._dl_state) != "place":
		await get_tree().process_frame
		w += 1
	## ★分母: 摆位屏真的建起来了 —— 没建起来的话下面两条什么也没量到
	##   (memory `fb-gate-subject-never-constructed`)。
	var btn = s.get("_dl_go_btn")
	_ok("★分母: 走到了摆位屏(%d 帧), 「开打」钮在场且可见" % w,
		str(s._dl_state) == "place" and btn is Button and is_instance_valid(btn)
			and (btn as Button).visible,
		"state=%s btn=%s" % [str(s._dl_state), str(btn)])
	_ok("★分母: 钩子真的接在摆位屏上(hook_calls=%d)" % SimAutopilot.hook_calls,
		SimAutopilot.hook_calls >= 1, "hook_calls=%d" % SimAutopilot.hook_calls)

	## ── 等够久 ──
	for _i in range(OVERWAIT):
		await get_tree().process_frame
	var state_after := str(s._dl_state)
	var btn_vis: bool = btn is Button and is_instance_valid(btn) and (btn as Button).visible

	if on:
		_ok("② 真的开车了 (drive_calls ≥ 1)", SimAutopilot.drive_calls >= 1,
			"drive_calls=%d" % SimAutopilot.drive_calls)
		_ok("② 按了恰好 1 次「开打」(不是 0 次也不是连点)", SimAutopilot.press_go == 1,
			"press_go=%d" % SimAutopilot.press_go)
		## ★★产品自己的账: 摆位阶段真的结束了 + 钮被 `_dl_start_fight()` 自己藏了
		_ok("② ★★产品的账: 摆位阶段真的结束了(_dl_state: place → %s)" % state_after,
			state_after == "fight" or state_after == "eggwindow" or state_after == "done",
			"state=%s" % state_after)
		_ok("② ★产品的账: 「开打」钮被隐藏了(_dl_start_fight 自己干的)", not btn_vis,
			"visible=%s" % str(btn_vis))
		_ok("② ★分母: sim 真的开始推进了(_t=%.3f > 0)" % float(s._t), float(s._t) > 0.0)
	else:
		_ok("① 自动驾驶一次都没开车 (drive_calls == 0)", SimAutopilot.drive_calls == 0,
			"drive_calls=%d press_go=%d" % [SimAutopilot.drive_calls, SimAutopilot.press_go])
		_ok("① 一次都没按过「开打」 (press_go == 0)", SimAutopilot.press_go == 0,
			"press_go=%d" % SimAutopilot.press_go)
		## ★★产品自己的账: 等了 %d 帧(= DWELL_PLACE 的两倍多)之后**还在摆位**
		_ok("① ★★产品的账: 等了 %d 帧仍停在摆位屏(还在等人点)" % OVERWAIT,
			state_after == "place", "state=%s" % state_after)
		_ok("① ★产品的账: 「开打」钮还挂着、还可见", btn_vis, "visible=%s" % str(btn_vis))
		_ok("① ★分母: sim 一步都没推进(_t=%.3f == 0 —— 摆位阶段 _fight_on 恒假)" % float(s._t),
			is_equal_approx(float(s._t), 0.0))

	## ★判完先宽限几帧再释放 —— 在飞的演出会在 await 之后撞上已释放的 battle
	##   (与 tests/_autoplay.gd 同一条经验)。
	for _g in range(20):
		await get_tree().process_frame
	s.queue_free()
	for _i in range(4):
		await get_tree().process_frame


# ══════════════════════════════════════════════════════════════
#  ③ 源码级: 不许碰经济/战斗内部/切场景
# ══════════════════════════════════════════════════════════════
func _phase_src() -> void:
	print("── ③ 源码级: 自动驾驶不许提经济 / 战斗内部 / 切场景 ──")
	var f := FileAccess.open(AP_SRC, FileAccess.READ)
	_ok("★分母: 读到了 autopilot.gd", f != null)
	if f == null:
		return
	var code: Array = []
	for line in f.get_as_text().split("\n"):
		var t := str(line).strip_edges()
		if t == "" or t.begins_with("#"):
			continue          # 注释里提到的名字不算(它们正是在解释为什么不碰)
		code.append(str(line).split("#")[0])
	f.close()
	_ok("★分母: 代码行(去注释)有 %d 行" % code.size(), code.size() >= 40,
		"%d 行" % code.size())
	var body := "\n".join(PackedStringArray(code))
	## ★正控: 同一套判法必须找得到一个**确实存在**的名字, 否则它是个坏判据(恒真)。
	_ok("★正控: 这套判法找得到确实在的 `press_go`", body.contains("press_go"))
	var banned := [
		"onboarded", "tutorial_active", "tutorial_stage",
		"meta_deepsea_coins", "hearts", "season_level", "season_xp", "season_wins",
		"season_total_battles", "persistent_bench", "persistent_equipped", "loadouts",
		"_units", "_battle_rng", "_apply_damage", "_dl_start_fight", "buy_season_xp",
		"DL_AUTOFIGHT", "change_scene_to_file",
	]
	var hits: Array = []
	for w in banned:
		if body.contains(str(w)):
			hits.append(str(w))
	_ok("③ 一个都没提: %s" % str(banned), hits.is_empty(), "提到了 %s" % str(hits))


## 固定对手快照(照 TutorialDirector.make_weak_ghost 的形状)—— 不走 Backend, 零随机。
func _fixed_ghost() -> Dictionary:
	return {
		"schema_ver": 1,
		"ghost_id": "autopilot_fixed_foe",
		"is_bot": true,
		"bracket": 0,
		"profile": {"name": "固定木桩", "avatar": "basic", "id": "APT"},
		"leaders": ["basic", "stone"],
		"lane_assign": {"top": ["basic"], "bottom": ["stone"]},
		"minions": {"top": [], "bottom": []},
		"loadouts": {},
		"equipped": {},
		"pet_levels": {"basic": 1, "stone": 1},
		"season_total_battles": 0,
		"season_eggs_killed": 0,
	}
