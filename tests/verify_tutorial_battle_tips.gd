extends Node

## verify_tutorial_battle_tips.gd — 教程战斗里的 6 句不阻塞提示(v5 C1~C6, 分镜 docs/plans/20261021-教程分镜v5.md §C)
##
## 分镜原则: 「战斗中讲道理」「不暂停」; C 的 6 条都挂在事件上, 某场没触发(如 C6 没到 1 : 1)就不出, 不卡流程(风险 3)。
## 量:
##   ① 桩测: 导演 `_trigger_hit` 对 5 种事件各一正一反(事件发生 ⇒ 真; 没发生 ⇒ 假); 锚点在单位死了时解析为空
##   ② 桩测: 一句挂上后锚点永远解析不出(那只龟死了)⇒ TIP_STALE_SEC 后丢掉, 下一句照常上(不卡队)
##   ③ 真战斗(真入口: 导演 enter → 选龟屏写的同三项 → next_scene_after → 真战斗场景当前场景, 打到结算):
##      · 测试自己从战斗状态独立记下每个事件第一次发生的时刻(不读导演的判据)
##      · 发生了的事件 ⇒ 对应那一句真显示过(文字 == 步骤表, {pet} 填成了真放技能那只龟的名字)
##      · 没发生的事件 ⇒ 那一句一帧都没出(教程战斗必赢 2 : 0 ⇒ C6 应当不出)
##      · 演出期间一帧提示都不出; 任何时刻提示都不挡点击; 战斗照常打到结算(提示没卡住流程)
##   分母: 真打到了结算 / 两路都开打过 / 至少 4 种事件真发生过(否则「发生 ⇒ 出现」是空检查)

const BATTLE := "res://scenes/RealtimeBattle3D.tscn"
const TG := preload("res://scripts/scenes/TutorialGuide.gd")
const FRAME_CAP := 15000

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


class StubDL extends RefCounted:
	var present_fading = null


class StubBattle extends Node:
	var _units: Array = []
	var _over := false
	var _dl_state := "fight"
	var _dl_present_root = null
	var _dl_sys = StubDL.new()
	var _t := 10.0
	var _sd_t0 := 0.0
	var _dl_hud = null
	var _hud = null
	var _cam = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 60     # 提示按真实时间淡入淡出; 钉帧率 ⇒ 游戏秒 ≈ 真实秒, 「事件发生 ⇒ 来得及显示」可预期
	await get_tree().process_frame
	GameState.test_mode = true
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	var dummy := Node.new()
	dummy.scene_file_path = "res://scenes/MainMenu.tscn"
	root.add_child(dummy)
	get_tree().current_scene = dummy
	var td = get_node("/root/TutorialDirector")
	_stub_triggers(td)
	await _stub_stale(td)
	await _real_battle(td, dummy)
	print("  (共 %d 条断言 · 跑了 %d 帧)" % [_n, Engine.get_process_frames()])
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少 %d) —— 有协程被半路掐断" % [_n, MIN_ASSERTS])
	print("ALL PASS — 教程战斗提示: 挂在事件上 / 没发生就不出 / 不挡点击 / 不卡流程" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _step(td: Node, trig: String) -> Dictionary:
	for st in TG.steps_for("battle"):
		if str((st as Dictionary).get("trigger", "")) == trig:
			return st
	return {}


## ① 每种事件一正一反(桩: 只有导演读的那几个字段)
func _stub_triggers(td: Node) -> void:
	print("  ── ① 事件判据桩测 ──")
	var bt := StubBattle.new()
	add_child(bt)
	var ally := {"side": "left", "id": "basic", "alive": true, "skill_gcd_until": 0.0}
	var tr := {"side": "left", "is_trainer": true, "alive": true, "_active_cd": 0.0}
	var foe_tr := {"side": "right", "is_trainer": true, "alive": true, "_active_cd": 15.0}
	var egg := {"side": "right", "_isEgg": true, "alive": true, "hp": 500.0, "maxHp": 500.0}
	var minion := {"side": "left", "_isMinion": true, "alive": true, "skill_gcd_until": 3.0}
	bt._units = [ally, tr, egg, minion, foe_tr]
	var s_fight := _step(td, "fight")
	var s_ally := _step(td, "ally_skill")
	var s_tr := _step(td, "trainer_skill")
	var s_egg := _step(td, "foe_egg_hit")
	var s_fin := _step(td, "final_lane")
	_ok("分母: 5 种事件在步骤表里各有一句", not s_fight.is_empty() and not s_ally.is_empty() and not s_tr.is_empty() and not s_egg.is_empty() and not s_fin.is_empty())
	_ok("★ally_skill 反: 我方龟没放过技能(小将放过不算) ⇒ 假", not td._trigger_hit(bt, s_ally))
	ally["skill_gcd_until"] = 12.5
	_ok("★★ally_skill 正: 我方龟放过技能 ⇒ 真, 且记下是哪只", td._trigger_hit(bt, s_ally) and is_same(td._btips_ctx.get("ally_skill"), ally))
	_ok("★trainer_skill 反: 我方训龟大师主动冷却 0(敌方大师出过钩不算) ⇒ 假", not td._trigger_hit(bt, s_tr))
	tr["_active_cd"] = 9.0
	_ok("★★trainer_skill 正: 训龟大师放过技能(冷却中) ⇒ 真", td._trigger_hit(bt, s_tr))
	_ok("★foe_egg_hit 反: 敌方蛋满血 ⇒ 假", not td._trigger_hit(bt, s_egg))
	egg["hp"] = 480.0
	_ok("★★foe_egg_hit 正: 敌方蛋掉过血 ⇒ 真", td._trigger_hit(bt, s_egg))
	var lane0 := str(GameState.current_lane)
	GameState.current_lane = "bottom"
	_ok("★final_lane 反: 还在下路战场 ⇒ 假", not td._trigger_hit(bt, s_fin))
	GameState.current_lane = "final"
	_ok("★★final_lane 正: 进了终极战场且开打 ⇒ 真", td._trigger_hit(bt, s_fin))
	bt._dl_state = "overview"
	_ok("★final_lane: 终极战场还在演出 ⇒ 假(演出卡上不压提示)", not td._trigger_hit(bt, s_fin))
	GameState.current_lane = lane0
	bt._dl_state = "fight"
	bt._t = 0.5
	_ok("★fight 反: 开打 0.5 秒(不到开场「开 战」放完) ⇒ 假", not td._trigger_hit(bt, s_fight))
	bt._t = 10.0
	_ok("★★fight 正: 开打 10 秒 ⇒ 真", td._trigger_hit(bt, s_fight))
	var s_lanes: Dictionary = TG.steps_for("battle")[1]
	bt._t = 1.8
	_ok("★C2 带 delay=%.1f: 开打 1.8 秒时 C1 已到点而 C2 还没到(比 C1 晚)" % float(s_lanes.get("delay", 0.0)), float(s_lanes.get("delay", 0.0)) >= 2.0
		and not td._trigger_hit(bt, s_lanes) and td._trigger_hit(bt, s_fight))
	## 锚点: 单位死了 ⇒ 空(不会把环套在一具尸体的位置上)
	td._btips_cur_ctx = {"alive": false}
	_ok("★锚点 cast_unit: 那只龟死了 ⇒ 空矩形", td._battle_anchor("cast_unit", bt) == Rect2())
	_ok("★锚点 trainer: 大师死了 ⇒ 空矩形", td._battle_anchor("trainer", bt) == Rect2())
	## {pet} 填真名
	var pd: Dictionary = DataRegistry.pet_by_id.get("basic", {})
	var filled: String = td._fill_battle_text(str(s_ally.get("text", "")), ally)
	_ok("★★C3 的 {pet} 填成放技能那只龟的名字「%s」" % str(pd.get("name", "")), str(pd.get("name", "")) != ""
		and filled.contains("【%s】" % str(pd.get("name", ""))) and not filled.contains("{"), filled)
	td._btips_ctx = {}
	td._btips_cur_ctx = {}
	bt.queue_free()


## ② 一句挂上后永远没机会显示 ⇒ 过期丢掉, 下一句照常上
func _stub_stale(td: Node) -> void:
	print("  ── ② 过期丢弃 ──")
	var bt := StubBattle.new()
	add_child(bt)
	td._stop_battle_tips()
	td._btips_bt = bt
	td._btips_steps = []
	var dead := {"text": "甲", "highlight": "cast_unit", "advanceOn": "tip_a", "hand": "none", "auto": 0.5, "_id": "X1", "_ctx": {"alive": false}}
	var ok_step := {"text": "乙", "highlight": "buff_badge", "advanceOn": "tip_b", "hand": "none", "auto": 0.5, "_id": "X2", "_ctx": {}}
	td._btips_queue = [dead, ok_step]
	## 不在沙盒里 ⇒ 导演 _process 不推它; 这里按真实帧时长亲手推(与 _process 同一个函数)
	for _i in range(2):
		await get_tree().process_frame
		td._tick_battle_tips(get_process_delta_time())
	_ok("分母: 第一句挂上了", td._battle_tips != null and td.battle_tips_log() == ["X1"], str(td.battle_tips_log()))
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int((td.TIP_STALE_SEC + 2.0) * 1000.0) and td.battle_tips_log().size() < 2:
		await get_tree().process_frame
		td._tick_battle_tips(get_process_delta_time())
	var waited: float = float(Time.get_ticks_msec() - t0) / 1000.0
	_ok("★★锚点永远解析不出的那句 %.0f 秒后丢掉, 下一句照常挂上(不卡队)" % td.TIP_STALE_SEC,
		td.battle_tips_log() == ["X1", "X2"] and waited >= td.TIP_STALE_SEC - 0.5, "%s 等了 %.1f 秒" % [str(td.battle_tips_log()), waited])
	td._stop_battle_tips()
	bt.queue_free()
	await get_tree().process_frame


func _overlays() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("tut_overlay"):
		if is_instance_valid(n) and n.has_method("is_showing") and not n.is_queued_for_deletion():
			out.append(n)
	return out


## ③ 真战斗
func _real_battle(td: Node, dummy: Node) -> void:
	print("  ── ③ 真战斗(教程第一把, 打到结算) ──")
	GameState.first_tips_seen = {}     # 账号侧: 教程结束时把教程里真显示过的 C2 / C5 / C6 记成看过(④)
	td.enter(null)
	td.preset_team()          # = 选龟屏「出战」那一下写的三项(选龟屏本身由 verify_tutorial_flow_v3 真点)
	GameState.reset_dual_lane()
	var nxt: String = td.next_scene_after("team_select")
	_ok("分母: 导演把教学战斗武装好了", nxt == td.BATTLE and td.steps_key_for("battle") == "battle")
	OS.set_environment("TURTLE_SEED", "20261021")
	var bt: Node = (load(BATTLE) as PackedScene).instantiate()
	get_tree().root.add_child(bt)
	get_tree().current_scene = bt
	var steps: Array = TG.steps_for("battle")
	var by_trig := {}
	for st in steps:
		by_trig[str((st as Dictionary).get("trigger", "")) + ":" + str((st as Dictionary).get("_id", ""))] = st
	var ev_frame := {}          # 事件 → 第一次发生的帧(测试自己记)
	var casters: Array = []     # 放过技能的我方龟名
	var shown := {}             # 显示过的文字 → 第一次的帧
	var shown_in_present := 0
	var blocking := 0
	var lanes := {}
	var fr := 0
	var c3 := {}               # C3 第一次显示那一刻: 点名的龟 / 圈 / 圈住的是谁
	var c3_tmpl := ""
	for st6 in steps:
		if str((st6 as Dictionary).get("_id", "")) == "C3":
			c3_tmpl = str((st6 as Dictionary).get("text", ""))
	while fr < FRAME_CAP and is_instance_valid(bt) and str(bt._dl_state) != "done":
		await get_tree().process_frame
		fr += 1
		var st := str(bt._dl_state)
		var lane := str(GameState.current_lane)
		var presenting: bool = st == "overview" or st == "preview" or is_instance_valid(bt._dl_present_root) \
			or is_instance_valid(bt._dl_sys.present_fading)
		if st == "fight":
			lanes[lane] = true
			if not ev_frame.has("fight"):
				ev_frame["fight"] = fr
		if lane == "final" and st == "fight" and not ev_frame.has("final_lane"):
			ev_frame["final_lane"] = fr
		for u in bt._units:
			if str(u.get("side", "")) == "left" and not bool(u.get("is_trainer", false)) and not bool(u.get("is_summon", false)) \
					and not bool(u.get("_isMinion", false)) and not bool(u.get("_isEgg", false)) and float(u.get("skill_gcd_until", 0.0)) > 0.0:
				if not ev_frame.has("ally_skill"):
					ev_frame["ally_skill"] = fr
				var nm := str((DataRegistry.pet_by_id.get(str(u.get("id", "")), {}) as Dictionary).get("name", ""))
				if nm != "" and not (nm in casters):
					casters.append(nm)
			if bool(u.get("is_trainer", false)) and str(u.get("side", "")) == "left" and float(u.get("_active_cd", 0.0)) > 0.0 and not ev_frame.has("trainer_skill"):
				ev_frame["trainer_skill"] = fr
			if bool(u.get("_isEgg", false)) and str(u.get("side", "")) == "right" and float(u.get("hp", 0.0)) < float(u.get("maxHp", 0.0)) - 0.01 \
					and not ev_frame.has("foe_egg_hit"):
				ev_frame["foe_egg_hit"] = fr
		for g in _overlays():
			if not g.is_showing():
				continue
			var t: String = g.current_text()
			if not shown.has(t):
				shown[t] = fr
				print("    [帧 %d] 提示「%s」" % [fr, t])
			if c3.is_empty() and c3_tmpl != "" and int(g.get("_idx")) == 0 and _c3_name(c3_tmpl, t) != "" and g._ring.visible:
				c3 = _c3_probe(bt, td, g, _c3_name(c3_tmpl, t))
			if presenting and g.is_tip():
				shown_in_present += 1
			if g.is_tip() and g.is_blocking():
				blocking += 1
	print("    事件第一次发生(帧): %s · 放过技能的龟 %s · 两路 %s" % [str(ev_frame), str(casters), str(lanes.keys())])
	print("    导演挂过的提示: %s · 共 %d 帧" % [str(td.battle_tips_log()), fr])
	var order: Array = []
	for t4 in shown.keys():
		for st4 in steps:
			if _matches(str((st4 as Dictionary).get("text", "")), str(t4), casters):
				order.append(str((st4 as Dictionary).get("_id", "")))
	_ok("★★开场先讲 C1 再讲 C2(别的事件即使更早发生也排在后面)", order.size() >= 2 and order[0] == "C1" and order[1] == "C2", str(order))
	_ok("★★分母: 真打到了结算(提示没卡住流程)", is_instance_valid(bt) and str(bt._dl_state) == "done", "%d 帧" % fr)
	_ok("分母: 上下两路都开打过", lanes.has("top") and lanes.has("bottom"), str(lanes.keys()))
	var happened := 0
	for k in ["fight", "ally_skill", "trainer_skill", "foe_egg_hit", "final_lane"]:
		if ev_frame.has(k):
			happened += 1
	_ok("★分母: 至少 4 种事件真发生过(否则「发生 ⇒ 出现」是空检查)", happened >= 4, "%d 种" % happened)
	for st2 in steps:
		var s: Dictionary = st2
		var trig := str(s.get("trigger", ""))
		var id := str(s.get("_id", ""))
		var tmpl := str(s.get("text", ""))
		var hit := ""
		for t2 in shown.keys():
			if _matches(tmpl, str(t2), casters):
				hit = str(t2)
		if ev_frame.has(trig):
			_ok("★★%s 事件「%s」发生了(帧 %d) ⇒ 那一句真显示过" % [id, trig, int(ev_frame[trig])], hit != "", "显示过: %s" % str(shown.keys()))
			if hit != "":
				_ok("★%s 显示在事件之后(不抢跑)" % id, int(shown[hit]) >= int(ev_frame[trig]), "事件帧 %d / 显示帧 %d" % [int(ev_frame[trig]), int(shown[hit])])
		else:
			_ok("★★%s 事件「%s」没发生 ⇒ 那一句一帧都没出(不卡流程)" % [id, trig], hit == "", hit)
	for t3 in shown.keys():
		_ok("★显示的「%s」占位都填了" % str(t3).left(14), not str(t3).contains("{"))
	## ★C3 圈的就是点名的那只(10-21 录屏: 文案点名【石头龟】, 圈却像套在旁边小将的血条上)
	_ok("分母: C3 显示过并量到了", not c3.is_empty(), str(c3))
	if not c3.is_empty():
		_ok("★★C3 点名的龟 == 导演圈的那只(同一个单位)", bool(c3.get("same_ctx", false)), str(c3))
		_ok("★★C3 圈住点名那只的血条 + 龟能槽(整组条)", bool(c3.get("bar_in", false)), str(c3))
		_ok("★★C3 圈住点名那只的身体(脚底投影点在圈里)", bool(c3.get("feet_in", false)), str(c3))
		_ok("★C3 圈的中心离点名那只最近(不是别的单位)", str(c3.get("nearest", "")) == "named", str(c3))
		_ok("★★C3 圈里没有别的单位叠着(看见的就是点名那只)", (c3.get("others_in_ring", ["?"]) as Array).is_empty(), str(c3.get("others_in_ring", [])))
	_ok("★★演出期间一帧提示都没出", shown_in_present == 0, "%d 帧" % shown_in_present)
	_ok("★★提示在屏的任何一帧都不挡点击", blocking == 0, "%d 帧" % blocking)
	_ok("★C6: 教程战斗必赢 2 : 0 ⇒ 没进终极战场(C6 不出是对的)", not lanes.has("final"))
	get_tree().current_scene = dummy
	bt.queue_free()
	for _i in range(5):
		await get_tree().process_frame
	td.end_tutorial("abandoned")
	## ④ 教程里真显示过的两路 / 龟蛋那两句 ⇒ 账号侧记成看过(跳过教程的玩家才会在首场正式对战再看到); 没显示过的终极战场那句不记
	var FT = load("res://scripts/systems/onboarding/first_tips.gd")
	var seen: Dictionary = GameState.first_tips_seen
	var t2 := ""
	var t5 := ""
	for st5 in steps:
		if str((st5 as Dictionary).get("_id", "")) == "C2":
			t2 = str((st5 as Dictionary).get("text", ""))
		if str((st5 as Dictionary).get("_id", "")) == "C5":
			t5 = str((st5 as Dictionary).get("text", ""))
	_ok("分母: 教程里 C2 / C5 真显示过", shown.has(t2) and shown.has(t5))
	_ok("★★教程结束 ⇒ 真显示过的 C2 / C5 记成账号看过(首场正式对战不再出)", bool(seen.get(FT.FIRST_LANES, false)) and bool(seen.get(FT.FIRST_EGG, false)), str(seen))
	_ok("★★中途离开教程: 教程里没出的 C6 不记 ⇒ 第一次真进终极战场时还会讲(同跳过教程的玩家)", not bool(seen.get(FT.FIRST_FINAL, false)), str(seen))
	## ★★2026-10-23 走完教程 ⇒ 三句全记(正式对战一条不出)。用户「我问你打完了教程，玩家每周第一把内为什么有提示」
	var all3: Array = FT.keys_seen_on_tutorial_end("completed", {})
	_ok("★★走完教程(教程里一句都没显示过也一样) ⇒ 两路 / 龟蛋 / 终极战场三句全记成看过",
		all3.size() == 3 and all3.has(FT.FIRST_LANES) and all3.has(FT.FIRST_EGG) and all3.has(FT.FIRST_FINAL), str(all3))
	var part: Array = FT.keys_seen_on_tutorial_end("abandoned", {"C2": true})
	_ok("★中途离开 ⇒ 只记教程里真显示过的(C2 ⇒ 只有两路)", part == [FT.FIRST_LANES], str(part))
	var dsrc := FileAccess.get_file_as_string("res://autoload/tutorial_director.gd")
	_ok("★★教程结束真的走这一个判据(end_tutorial 调 keys_seen_on_tutorial_end(reason, …))",
		dsrc.find("FT.keys_seen_on_tutorial_end(reason, _btips_tut_shown)") >= 0)
	OS.set_environment("TURTLE_SEED", "")


## 显示出来的字是不是这一句(带 {pet} 的: 填的是放过技能的某只龟)
func _matches(tmpl: String, got: String, casters: Array) -> bool:
	if not tmpl.contains("{pet}"):
		return got == tmpl
	for nm in casters:
		if got == tmpl.replace("{pet}", str(nm)):
			return true
	return false


## C3 文案里点名的龟名(模板 {pet} 那一段)。不是 C3 ⇒ ""。
func _c3_name(tmpl: String, got: String) -> String:
	var i := tmpl.find("{pet}")
	if i < 0:
		return ""
	var pre := tmpl.substr(0, i)
	var post := tmpl.substr(i + 5)
	if not got.begins_with(pre) or not got.ends_with(post) or got.length() <= pre.length() + post.length():
		return ""
	return got.substr(pre.length(), got.length() - pre.length() - post.length())


## C3 显示那一刻: 点名那只(按名字在我方龟里找, 测试自己找)的条 / 脚底是否在圈里, 圈中心离谁最近。
func _c3_probe(bt: Node, td: Node, g: Node, nm: String) -> Dictionary:
	var ring := Rect2(g._ring.position, g._ring.size)
	var named = null
	for u in bt._units:
		if str(u.get("side", "")) == "left" and not bool(u.get("_isMinion", false)) and not bool(u.get("is_trainer", false)) 				and bool(u.get("alive", false)) and str((DataRegistry.pet_by_id.get(str(u.get("id", "")), {}) as Dictionary).get("name", "")) == nm:
			named = u
	var out := {"name": nm, "ring": ring}
	if named == null:
		return out
	var cam: Camera3D = bt._cam
	var feet: Vector2 = cam.unproject_position(bt._world_pos(named["pos"], 0.0))
	var bar := (named["bar_root"] as Control).get_global_rect()
	out["same_ctx"] = is_same(td._btips_cur_ctx, named)
	out["bar_in"] = ring.grow(1.0).encloses(bar)
	out["feet_in"] = ring.has_point(feet)
	out["feet"] = feet
	out["bar"] = bar
	## 圈中心到各单位(头顶条中心)的距离: 最近的是不是点名那只
	var best := 1e9
	var who := ""
	for u in bt._units:
		var br = u.get("bar_root", null)
		if br == null or not is_instance_valid(br) or not bool(u.get("alive", false)) or not (br as Control).is_visible_in_tree():
			continue
		var c: Vector2 = cam.unproject_position(bt._world_pos(u["pos"], float(u.get("height", 0.0)) * 0.5))
		var d := c.distance_to(ring.get_center())
		if d < best:
			best = d
			who = "named" if is_same(u, named) else str(u.get("id", ""))
	out["nearest"] = who
	## 圈里有没有别的单位的头顶条(别的单位叠在点名那只身上 ⇒ 圈里看见的是别人)
	var others: Array = []
	for u in bt._units:
		var br2 = u.get("bar_root", null)
		if is_same(u, named) or br2 == null or not is_instance_valid(br2) or not bool(u.get("alive", false)) or not (br2 as Control).is_visible_in_tree():
			continue
		if ring.intersects((br2 as Control).get_global_rect()):
			others.append(str(u.get("id", "")))
	out["others_in_ring"] = others
	return out
