extends Node
## verify_stream_whitelist_alarm.gd — 逐帧直播 S1: 录流只逐步比「白名单」属性, 白名单外的属性一旦变了必须被报出来, 而且实测为 0。
## 方案书 docs/plans/20261019-服务器逐帧直播.md §2.1 白名单 / §2.2 / 验收清单。
##
## 录流器为了性能只逐步比 S0 量出来「真会变」的 30 种属性(+ 所有 Node3D 的变换 / 显隐), 其余属性只在建节点时发一次;
## 每个 keyframe 与每次删节点时把其余属性和基线全量核一遍, 变了就记一次报警(元数据 alarm / alarm_props)。
## 报警 ≠ 0 ⇒ 手机上那个属性永远停在建节点时的值(静默漏画) ⇒ 必须把它加进白名单(录流器 TRACKED + 取值路径)。
##
## 样本: DetScenarios 全部场景(14900 步, 覆盖召唤 / 弹道 / 羁绊 / 时停 …) + 真实快照局(S0 的最重那局, 三路打满)。
## ★分母: 节点层建过的节点数、做过全量核对的节点数都 > 0(否则「0 报警」只是没核)。
## ★正对照(证明这条判据会红): 在 sim 步里挂一个 Sprite3D 进 _world, 过几步改它的 billboard(白名单外)再删掉 ⇒
##   报警恰 1 次、键是 Sprite3D.billboard; 同样的流程改 modulate(白名单内) ⇒ 不报警, 而且流里录到了那次改动。

const J := preload("res://tests/_stream_jobs.gd")
const SC := preload("res://scripts/referee/det_scenarios.gd")
const SIM_DT := 1.0 / 60.0

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
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	gs.week_anchor_ts = int(SC.PIN_WEEK_ANCHOR)

	## ★真实快照局先跑: det 建场会把 RealtimeBattle3DScene.DEBUG_EDIT(静态)置 true, 之后再建的战斗场全是调试场、永远不开打。
	print("=== 真实快照局(最重, 三路打满) ===")
	var res: Dictionary = await RefereeRunner.run(self, J.heavy(), Callable(), {"keep": false})
	var mh: Dictionary = res.get("stream", {})
	print("  [量] 真实快照局: ok=%s 开打 %d 步 %d 节点 %d 核对 %d 报警 %d %s" % [str(res.get("ok")), int(res.get("fights", 0)),
		int(mh.get("steps", 0)), int(mh.get("nodes_new", 0)), int(mh.get("alarm_checked", 0)), int(mh.get("alarm", 0)), str(mh.get("alarm_props", {}))])
	_ok("分母 · 真实快照局算完、三路打满", bool(res.get("ok", false)) and int(res.get("fights", 0)) == 3)
	_ok("分母 · 真实快照局节点层建过 %d 个节点、全量核对过 %d 次" % [int(mh.get("nodes_new", 0)), int(mh.get("alarm_checked", 0))],
		int(mh.get("nodes_new", 0)) > 5000 and int(mh.get("alarm_checked", 0)) > 5000)
	_ok("★★真实快照局 白名单外变化 = 0", mh.has("alarm") and int(mh.get("alarm", -1)) == 0, str(mh.get("alarm_props", {})))

	print("=== 正对照: 白名单外的改动必须报出来 ===")
	var sc0: Dictionary = SC.all()[0]
	var c1: Dictionary = await _run_det(sc0, "billboard")
	_ok("★正对照 · 改 billboard(白名单外) ⇒ 报警恰 1 次、键 = Sprite3D.billboard", int(c1.get("alarm", -1)) == 1
		and int((c1.get("alarm_props", {}) as Dictionary).get("Sprite3D.billboard", 0)) == 1, str(c1.get("alarm_props")))
	var c2: Dictionary = await _run_det(sc0, "modulate")
	_ok("★正对照 · 改 modulate(白名单内) ⇒ 不报警, 且这一改被录成节点改动", int(c2.get("alarm", -1)) == 0
		and int(c2.get("node_sets", 0)) > int(c1.get("node_sets", 0)), "alarm=%s sets %d vs %d" % [str(c2.get("alarm")),
		int(c2.get("node_sets", 0)), int(c1.get("node_sets", 0))])

	print("=== DetScenarios 全部场景 ===")
	var tot := {"alarm": 0, "nodes_new": 0, "alarm_checked": 0, "steps": 0}
	var props := {}
	for sc in SC.all():
		var m: Dictionary = await _run_det(sc as Dictionary, "")
		for k in tot:
			tot[k] = int(tot[k]) + int(m.get(k, 0))
		for k in (m.get("alarm_props", {}) as Dictionary):
			props[k] = int(props.get(k, 0)) + int(m["alarm_props"][k])
		print("  [量] %s: 步 %d 节点 %d 核对 %d 报警 %d %s" % [str(sc["tag"]), int(m.get("steps", 0)), int(m.get("nodes_new", 0)),
			int(m.get("alarm_checked", 0)), int(m.get("alarm", 0)), str(m.get("alarm_first", {}))])
	_ok("分母 · det 全部 %d 个场景录了 %d 步(= 场景表帧数之和)" % [SC.all().size(), int(tot["steps"])], int(tot["steps"]) == _det_steps())
	_ok("分母 · det 节点层建过 %d 个节点、全量核对过 %d 次" % [int(tot["nodes_new"]), int(tot["alarm_checked"])],
		int(tot["nodes_new"]) > 1000 and int(tot["alarm_checked"]) > 1000)
	_ok("★★det 全部场景 白名单外变化 = 0", int(tot["alarm"]) == 0, str(props))
	(load("res://scripts/scenes/RealtimeBattle3DScene.gd")).DEBUG_EDIT = false

	_finish()


func _det_steps() -> int:
	var s := 0
	for sc in SC.all():
		s += int((sc as Dictionary)["frames"])
	return s


## DetScenarios 同一套建场(det_scenarios.gd `run()`), 但关掉战斗场自己的 _process, 由这里逐步推 sim 并接录流器
##   (与裁判机同一个挂点形状: pre_step → _sim_step → post_step)。
## control = "" 正常跑 / "billboard" | "modulate": 第 10 步在 sim 步里挂一个 Sprite3D 进 _world, 第 20 步改那个属性, 第 30 步删掉。
func _run_det(sc: Dictionary, control: String) -> Dictionary:
	OS.set_environment("TURTLE_SEED", str(sc["seed"]))
	var RB = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s.set_process(false)
	s._debug._edit_clear()
	var lo: Dictionary = sc.get("loadouts", {})
	if not lo.is_empty():
		var gs2 = get_node_or_null("/root/GameState")
		for k in lo:
			gs2.loadouts[str(k)] = int(lo[k])
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 40000.0
	s._edit_full_energy = true
	for p in (sc["pairs"] as Array):
		var pid: String = str(p[0])
		if pid.begins_with("__minion__"):
			var bits: PackedStringArray = pid.split(":")
			s._edit_minion_role = str(bits[1]) if bits.size() > 1 else "front"
			pid = "__minion__"
		var u: Dictionary = s._debug._edit_place_unit(pid, str(p[1]), Vector2(float(p[2]), float(p[3])))
		if (p[4] as Array).size() > 0:
			var el: Array = []
			for e in (p[4] as Array):
				el.append({"id": str(e), "star": 3})
			u["_edit_equips"] = el
		if (p as Array).size() > 5 and bool(p[5]):
			u["active_skills"] = s._resolve_active_skills(pid, false)
			u["skill_idx"] = 0
	s._debug._edit_start_battle()
	s.set_process(false)
	var rec := StreamRecorder.new(s, {})
	rec.start()
	var probe: Sprite3D = null
	for i in range(int(sc["frames"])):
		if i % 60 == 0:
			await get_tree().process_frame
		rec.pre_step()
		if control != "":
			if i == 10:
				probe = Sprite3D.new()
				s._world.add_child(probe)
			elif i == 20 and is_instance_valid(probe):
				if control == "billboard":
					probe.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
				else:
					probe.modulate = Color(0.2, 0.4, 0.6, 0.5)
			elif i == 30 and is_instance_valid(probe):
				probe.queue_free()
		s._sim_step(SIM_DT, float(s._hitstop) > 0.0, not (s._timestop._ts_active as Array).is_empty())
		rec.post_step()
	var m: Dictionary = rec.finish()
	OS.set_environment("TURTLE_SEED", "")
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func _finish() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 白名单外变化为 0 且报警判据会红 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
