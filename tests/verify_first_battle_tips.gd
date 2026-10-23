extends Node

## verify_first_battle_tips.gd — 跳过教程的玩家第一场正式对战: 两路 / 龟蛋 / 终极战场各一句首次提示
##   (我的提议, 用户未明确要过 —— 原来写成「用户 2026-10-21」, 2026-10-23 订正; 只对跳过 / 中途离开教程的玩家;
##    走完教程的玩家三句全记成看过, 见 FirstTips.keys_seen_on_tutorial_end 与 verify_tutorial_battle_tips ④)
##
## 量:
##   ① 句子就是教程战斗那三句: FirstTips.battle_tip_steps == data/tutorial-steps.json battle C2 / C5 / C6(本测试自己读 json 比, 不读产品的读法)
##   ② 桩战斗(当前场景, 本局在录 = 自己的正式对局), 走导演真 `_process`: 三个事件依次发生 ⇒ 三句各显示一次, 文字逐字 == 教程原句;
##      显示那一刻记成看过(三个键); 任何一帧都不挡点击
##   ③ 第二场: 三句都看过 ⇒ 一句都不挂
##   ④ 不该出的地方: 回放(mode=play) / 没 onboarded / 教程沙盒里(tutorial_active)⇒ 一句都不挂(各配一条「同条件换成正式对局就挂」的对照)
##   ⑤ 真战斗(真入口: 真战斗场景当前场景, 积分赛日, 本局在录, 不在沙盒): 开打 ⇒ C2 那句真显示过、记成看过

const BATTLE := "res://scenes/RealtimeBattle3D.tscn"
const FT := preload("res://scripts/systems/onboarding/first_tips.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

var _fail := 0
var _n := 0
const MIN_ASSERTS := 30


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


class StubReplay extends RefCounted:
	var mode := "rec"
	var live = null

	func is_live() -> bool:
		return false


class StubDL extends RefCounted:
	var present_fading = null


class StubHud extends RefCounted:
	var _pk_egg_r: Control = null
	var _pk_egg_icons: Array = []


class StubBattle extends Node:
	var _units: Array = []
	var _over := false
	var _dl_state := "overview"
	var _dl_present_root = null
	var _dl_sys = StubDL.new()
	var _t := 0.0
	var _sd_t0 := 0.0
	var _dl_hud: Control = null
	var _hud = StubHud.new()
	var _cam = null
	var _replay = StubReplay.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 60
	await get_tree().process_frame
	GameState.test_mode = true
	OS.set_environment("ONBOARD", "0")
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	var dummy := Node.new()
	dummy.scene_file_path = "res://scenes/MainMenu.tscn"
	root.add_child(dummy)
	get_tree().current_scene = dummy
	var td = get_node("/root/TutorialDirector")
	var lane0 := str(GameState.current_lane)
	_same_sentences()
	await _stub_first(td, dummy)
	await _stub_second(td, dummy)
	await _not_here(td, dummy)
	await _real_battle(td, dummy)
	GameState.current_lane = lane0
	print("  (共 %d 条断言 · 跑了 %d 帧)" % [_n, Engine.get_process_frames()])
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少 %d) —— 有协程被半路掐断" % [_n, MIN_ASSERTS])
	print("ALL PASS — 首场正式对战三句: 教程原句 / 挂在同一事件 / 各一次 / 回放·教程·没入门不出" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _account(onboarded: bool) -> void:
	GameState.onboarded = onboarded
	GameState.tutorial_active = false
	GameState.first_tips_seen = {}


## 教程步骤表 battle 段(测试自己读 json)
func _json_steps() -> Dictionary:
	var out := {}
	var js = JSON.parse_string(FileAccess.get_file_as_string("res://data/tutorial-steps.json"))
	for st in (js as Dictionary).get("battle", []):
		out[str((st as Dictionary).get("_id", ""))] = st
	return out


# ① 句子 = 教程原句
func _same_sentences() -> void:
	print("  ── ① 三句 = 教程战斗 C2 / C5 / C6 ──")
	_account(true)
	var js := _json_steps()
	var got: Array = FT.battle_tip_steps(false)
	_ok("★分母: 三句", got.size() == 3, "%d" % got.size())
	var ids: Array = []
	for st in got:
		ids.append(str((st as Dictionary).get("_id", "")))
	_ok("★★正是 C2 / C5 / C6(两路 / 龟蛋 / 终极战场)", ids == ["C2", "C5", "C6"], str(ids))
	var keys := {"C2": FT.FIRST_LANES, "C5": FT.FIRST_EGG, "C6": FT.FIRST_FINAL}
	for st in got:
		var s: Dictionary = st
		var id := str(s.get("_id", ""))
		var j: Dictionary = js.get(id, {})
		_ok("★★%s 文字逐字 == 步骤表「%s」" % [id, str(j.get("text", ""))], str(s.get("text", "")) == str(j.get("text", "")) and str(j.get("text", "")) != "")
		_ok("%s 挂在同一个事件(%s)/ 同一个锚点" % [id, str(j.get("trigger", ""))], str(s.get("trigger", "")) == str(j.get("trigger", ""))
			and str(s.get("highlight", "")) == str(j.get("highlight", "")))
		_ok("%s 键 = %s" % [id, str(keys.get(id, ""))], str(s.get("_ft_key", "")) == str(keys.get(id, "")))


func _mk_stub(mode: String) -> StubBattle:
	var bt := StubBattle.new()
	bt.scene_file_path = BATTLE
	bt._replay.mode = mode
	var plate := Control.new()
	plate.position = Vector2(540, 20)
	plate.size = Vector2(200, 40)
	bt.add_child(plate)
	bt._dl_hud = plate
	var eggr := Control.new()
	eggr.position = Vector2(800, 70)
	eggr.size = Vector2(160, 14)
	bt.add_child(eggr)
	bt._hud._pk_egg_r = eggr
	bt._units = [{"side": "right", "_isEgg": true, "alive": true, "hp": 500.0, "maxHp": 500.0}]
	return bt


func _mount(bt: Node, dummy: Node) -> void:
	get_tree().root.add_child(bt)
	get_tree().current_scene = bt
	await get_tree().process_frame
	await get_tree().process_frame


func _unmount(bt: Node, dummy: Node) -> void:
	get_tree().current_scene = dummy
	bt.queue_free()
	for _i in range(4):
		await get_tree().process_frame


func _overlays() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("tut_overlay"):
		if is_instance_valid(n) and n.has_method("is_showing") and not n.is_queued_for_deletion():
			out.append(n)
	return out


## 推桩战斗的钟, 直到某句显示出来(或超时)。返回显示过的文字表(文字 → 次数, 按出现)。
func _run(bt: StubBattle, until_text: String, shown: Dictionary, max_sec: float, stats: Dictionary) -> bool:
	var t0 := Time.get_ticks_msec()
	var cur := str(stats.get("cur", ""))     # 跨调用记住此刻在屏的那句(同一句连着显示不重复数)
	var left := -1                           # 等到了之后再走几帧(导演下一帧才记「看过」)
	while Time.get_ticks_msec() - t0 < int(max_sec * 1000.0):
		await get_tree().process_frame
		bt._t += get_process_delta_time()
		var now := ""
		for g in _overlays():
			if g.is_showing():
				now = g.current_text()
				if g.is_blocking():
					stats["blocking"] = int(stats.get("blocking", 0)) + 1
		if now != "" and now != cur:
			shown[now] = int(shown.get(now, 0)) + 1
		cur = now
		stats["cur"] = cur
		if left > 0:
			left -= 1
			if left == 0:
				return true
		elif until_text != "" and shown.has(until_text):
			left = 3
	return left >= 0


# ② 第一场
func _stub_first(td: Node, dummy: Node) -> void:
	print("  ── ② 第一场正式对战(桩, 走导演真 _process) ──")
	_account(true)
	var js := _json_steps()
	var t2 := str(js["C2"]["text"])
	var t5 := str(js["C5"]["text"])
	var t6 := str(js["C6"]["text"])
	GameState.current_lane = "top"
	var bt := _mk_stub("rec")
	await _mount(bt, dummy)
	_ok("★分母: 导演把三句挂到这一场(首场模式)", td._btips_first and is_same(td._btips_bt, bt) and td._btips_steps.size() == 3)
	var shown := {}
	var stats := {}
	## 演出中: 一句都不出
	await _run(bt, "", shown, 1.0, stats)
	_ok("★演出中(overview)一句都不出", shown.is_empty(), str(shown))
	bt._dl_state = "fight"
	bt._sd_t0 = bt._t
	var ok2 := await _run(bt, t2, shown, 10.0, stats)
	_ok("★★开打 ⇒ C2「%s」显示" % t2, ok2, str(shown))
	_ok("★★C2 显示 ⇒ first_lanes 记成看过", bool(GameState.first_tips_seen.get(FT.FIRST_LANES, false)))
	_ok("★龟蛋没被打 ⇒ C5 还没出、没记", not shown.has(t5) and not bool(GameState.first_tips_seen.get(FT.FIRST_EGG, false)))
	bt._units[0]["hp"] = 450.0
	var ok5 := await _run(bt, t5, shown, 12.0, stats)
	_ok("★★敌方龟蛋掉血 ⇒ C5「%s」显示" % t5, ok5, str(shown))
	_ok("★★C5 显示 ⇒ first_egg 记成看过", bool(GameState.first_tips_seen.get(FT.FIRST_EGG, false)))
	_ok("★没进终极战场 ⇒ C6 没出、没记", not shown.has(t6) and not bool(GameState.first_tips_seen.get(FT.FIRST_FINAL, false)))
	GameState.current_lane = "final"
	var ok6 := await _run(bt, t6, shown, 12.0, stats)
	_ok("★★进终极战场 ⇒ C6「%s」显示" % t6, ok6, str(shown))
	_ok("★★C6 显示 ⇒ first_final 记成看过", bool(GameState.first_tips_seen.get(FT.FIRST_FINAL, false)))
	await _run(bt, "", shown, 5.0, stats)
	_ok("★★三句各只出一次", int(shown.get(t2, 0)) == 1 and int(shown.get(t5, 0)) == 1 and int(shown.get(t6, 0)) == 1, str(shown))
	_ok("★只出了这三句(没把 C1 教程加成 / C3 / C4 带出来)", shown.size() == 3, str(shown.keys()))
	_ok("★★任何一帧都不挡点击", int(stats.get("blocking", 0)) == 0, "%d 帧" % int(stats.get("blocking", 0)))
	await _unmount(bt, dummy)
	GameState.current_lane = "top"


# ③ 第二场
func _stub_second(td: Node, dummy: Node) -> void:
	print("  ── ③ 第二场: 都看过 ⇒ 不挂 ──")
	_ok("分母: 三个键都看过", bool(GameState.first_tips_seen.get(FT.FIRST_LANES, false)) and bool(GameState.first_tips_seen.get(FT.FIRST_EGG, false))
		and bool(GameState.first_tips_seen.get(FT.FIRST_FINAL, false)))
	var bt := _mk_stub("rec")
	await _mount(bt, dummy)
	bt._dl_state = "fight"
	var shown := {}
	await _run(bt, "", shown, 5.0, {})
	_ok("★★第二场一句都不挂、不出", not td._btips_first and shown.is_empty(), str(shown))
	await _unmount(bt, dummy)


# ④ 不该出的地方(各配对照)
func _not_here(td: Node, dummy: Node) -> void:
	print("  ── ④ 回放 / 没入门 / 教程沙盒 ⇒ 不出 ──")
	for c in [["回放(mode=play)", "play", true, false], ["没 onboarded", "rec", false, false], ["教程沙盒里(tutorial_active)", "rec", true, true]]:
		_account(bool(c[2]))
		GameState.tutorial_active = bool(c[3])
		var bt := _mk_stub(str(c[1]))
		bt._dl_state = "fight"
		await _mount(bt, dummy)
		var shown := {}
		await _run(bt, "", shown, 5.5, {})
		_ok("★★%s ⇒ 首场三句不挂、不出" % c[0], not td._btips_first and shown.is_empty(), str(shown))
		_ok("%s ⇒ 一个键都没记" % c[0], GameState.first_tips_seen.is_empty())
		await _unmount(bt, dummy)
	GameState.tutorial_active = false
	## 对照: 同一套桩、正式对局、入门过 ⇒ 挂(证明上面三条不出不是因为桩坏了)
	_account(true)
	var bt2 := _mk_stub("rec")
	bt2._dl_state = "fight"
	await _mount(bt2, dummy)
	var shown2 := {}
	await _run(bt2, str(_json_steps()["C2"]["text"]), shown2, 10.0, {})
	_ok("★对照: 正式对局 + 入门过 ⇒ C2 出", shown2.has(str(_json_steps()["C2"]["text"])), str(shown2))
	await _unmount(bt2, dummy)


# ⑤ 真战斗
func _real_battle(td: Node, dummy: Node) -> void:
	print("  ── ⑤ 真战斗(跳过教程的号, 积分赛日第一场) ──")
	var ovr0: int = P2C.now_override_ts
	var now := int(Time.get_unix_time_from_system())
	P2C.now_override_ts = P2C.week_anchor_utc(now) + 86400 + 12 * 3600   # 周二 12:00 UTC
	_account(true)
	td.preset_team()
	GameState.reset_dual_lane()
	GameState.week_phase = P2C.PHASE_RANKED
	GameState.dual_active = true
	GameState.dual_ghost = td.make_weak_ghost()
	OS.set_environment("TURTLE_SEED", "20261021")
	var bt: Node = (load(BATTLE) as PackedScene).instantiate()
	get_tree().root.add_child(bt)
	get_tree().current_scene = bt
	var t2 := str(_json_steps()["C2"]["text"])
	var shown := {}
	var fr := 0
	while fr < 9000 and is_instance_valid(bt) and str(bt._dl_state) != "done" and not shown.has(t2):
		await get_tree().process_frame
		fr += 1
		for g in _overlays():
			if g.is_showing() and not shown.has(g.current_text()):
				shown[g.current_text()] = fr
	for _k in range(4):          # 导演下一帧才记「看过」
		await get_tree().process_frame
	_ok("分母: 这一场在录(玩家自己的正式对局)", is_instance_valid(bt) and str(bt._replay.mode) == "rec", str(bt._replay.mode) if is_instance_valid(bt) else "?")
	_ok("分母: 不在教程沙盒里", not td.in_sandbox() and not GameState.tutorial_active)
	_ok("★★真战斗开打 ⇒ C2「%s」真显示" % t2, shown.has(t2), "%s · %d 帧" % [str(shown), fr])
	_ok("★★真战斗里显示 ⇒ first_lanes 记成看过", bool(GameState.first_tips_seen.get(FT.FIRST_LANES, false)))
	get_tree().current_scene = dummy
	if is_instance_valid(bt):
		bt.queue_free()
	for _i in range(5):
		await get_tree().process_frame
	OS.set_environment("TURTLE_SEED", "")
	P2C.now_override_ts = ovr0
	GameState.dual_active = false
