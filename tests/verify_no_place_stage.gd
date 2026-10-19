extends Node
## verify_no_place_stage.gd —— 对局里不再有拖动站位环节(2026-10-19)
##
## 用户 10-19「我想在背包里实现站位修改，这样在对局内将不再有拖动站位环节」。
## 走真入口建一场双路对局(带开场演出: 三路总览 5 秒 → 对阵预览 5 秒), 每个 sim 步末尾采一次(`sim_stepped`):
##   ① 没有任何一步停在 `_dl_state == "place"`(建场与开打在同一步里)
##   ② 战场一建好(我方单位上场)那一步, 状态就已经是 fight
##   ③ 全程树里没有「开始战斗」钮(GoBtn), 也没有任何文字是「开始战斗」的按钮
##   ④ 开打之后 sim 真的在走(`_t` 涨)—— 没人按任何东西
## 两遍: 不带 / 带 `SIM_AUTOPILOT`(模拟号原来靠它按那颗钮; 现在两遍必须一样自己开打)。
## 旧门禁 verify_autopilot(「不带开关就停在摆位屏等人点」)的被测对象已经不存在, 由本条取代。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

const MAX_STEPS := 1500          # 开场演出 10 秒 = 600 步; 留足余量
const AFTER_FIGHT := 90          # 开打后再看 90 步

var _n := 0
var _fail := 0
var _s = null
## 每步采样的账
var _steps := 0
var _place_steps := 0
var _field_step := -1            # 我方单位第一次出现在场上的步
var _field_state := ""           # 那一步末尾的状态
var _fight_step := -1
var _go_seen := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	GameState.test_mode = true
	GameState.tutorial_active = false
	print("=== 对局里没有拖动站位环节 ===")
	var env0: String = OS.get_environment(SimAutopilot.ENV)
	for on in [false, true]:
		if on:
			OS.set_environment(SimAutopilot.ENV, "1")
		else:
			OS.set_environment(SimAutopilot.ENV, " ")
		await _run("带 SIM_AUTOPILOT" if on else "不带 SIM_AUTOPILOT", on)
	OS.set_environment(SimAutopilot.ENV, env0)
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


func _run(tag: String, on: bool) -> void:
	print("── %s ──" % tag)
	_ok("[%s] ★分母: 开关状态与本遍一致" % tag, SimAutopilot.enabled() == on)
	_steps = 0; _place_steps = 0; _field_step = -1; _field_state = ""; _fight_step = -1; _go_seen = 0
	DualLaneFlow.NO_PRESENT = false
	GameState.reset_dual_lane()
	GameState.dual_active = true
	GameState.season_leaders = ["basic", "stone", "bamboo"]
	GameState.dual_lineup = {}
	GameState.get_dual_lineup()
	GameState.dual_ghost = _fixed_ghost()
	_s = RB.new()
	_s._deterministic = true          # 每帧恰 1 步 ⇒ 帧数 = 步数, 与机器快慢无关
	_s.sim_stepped.connect(_on_step)
	add_child(_s)
	_ok("[%s] ★分母: 开场先走演出(不是快路径)" % tag, _s._dl_sys._dl_is_present(), "state=%s" % str(_s._dl_state))
	var w := 0
	while w < MAX_STEPS and (_fight_step < 0 or _steps < _fight_step + AFTER_FIGHT):
		await get_tree().process_frame
		w += 1
		if _s.find_child("GoBtn", true, false) != null or _has_go_text(_s):
			_go_seen += 1
	_ok("[%s] ★分母: 采了 %d 步(含 10 秒开场演出 ≥ 600 步)" % [tag, _steps], _steps >= 600)
	_ok("[%s] ★分母: 我方单位上场了(第 %d 步)" % [tag, _field_step], _field_step >= 0)
	_ok("[%s] ① ★没有任何一步停在摆位(place 步数 = %d)" % [tag, _place_steps], _place_steps == 0)
	_ok("[%s] ② ★上场那一步末尾就已开打(状态 %s)" % [tag, _field_state], _field_state == "fight")
	_ok("[%s] ② 开打步 = 上场步(%d / %d)" % [tag, _fight_step, _field_step], _fight_step == _field_step and _fight_step >= 0)
	_ok("[%s] ③ ★全程没有「开始战斗」钮(出现 %d 帧)" % [tag, _go_seen], _go_seen == 0)
	_ok("[%s] ④ 开打后 sim 在走(_t=%.2f)" % [tag, float(_s._t)], float(_s._t) > 0.5)
	_s.sim_stepped.disconnect(_on_step)
	for _g in range(10):
		await get_tree().process_frame
	_s.queue_free()
	for _i in range(4):
		await get_tree().process_frame
	GameState.dual_ghost = {}
	GameState.dual_active = false


func _on_step(_a = null, _b = null) -> void:
	_steps += 1
	var st := str(_s._dl_state)
	if st == "place":
		_place_steps += 1
	if _field_step < 0:
		for u in _s._units:
			if str(u.get("side", "")) == "left" and not u.get("_isEgg", false) and not u.get("is_trainer", false):
				_field_step = _steps
				_field_state = st
				break
	if _fight_step < 0 and st == "fight":
		_fight_step = _steps


func _has_go_text(n: Node) -> bool:
	if n is Button and str((n as Button).text).replace(" ", "").contains("开始战斗") and (n as Button).is_visible_in_tree():
		return true
	for c in n.get_children():
		if _has_go_text(c):
			return true
	return false


func _fixed_ghost() -> Dictionary:
	return {
		"schema_ver": 1,
		"ghost_id": "no_place_fixed_foe",
		"is_bot": true,
		"bracket": 0,
		"profile": {"name": "固定木桩", "avatar": "basic", "id": "NPS"},
		"leaders": ["basic", "stone"],
		"lane_assign": {"top": ["basic"], "bottom": ["stone"]},
		"minions": {"top": [], "bottom": []},
		"loadouts": {},
		"equipped": {},
		"pet_levels": {"basic": 1, "stone": 1},
		"season_total_battles": 0,
		"season_eggs_killed": 0,
	}
