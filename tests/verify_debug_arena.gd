extends Node
## verify_debug_arena.gd — 调试场重做 (用户2026-07-24: 摆放流程/大师/精英/面板折叠/逐只配)
## 守: ①底部笔刷栏建出(含大师+精英) ②训龟大师能自由摆 ③精英小将能摆(修 elite:false 死bug)
##     ④逐只配 血量/无敌/满龟能 ⑤面板折叠 API + 跨重建持久(static)

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	RB.DEBUG_EDIT = true
	RB._edit_collapsed = false
	var scene = RB.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	# ① 底部笔刷栏
	_ok("★底部常驻笔刷栏建出来了(取代模态选龟)", scene._edit_brush_bar != null and is_instance_valid(scene._edit_brush_bar))
	_ok("★笔刷格 ≥ 28龟+浪板/火箭/精英/大师(分母)", scene._edit_brush_cells.size() >= 30, "%d 格" % scene._edit_brush_cells.size())
	var _keys: Array = []
	for p in scene._edit_brush_cells: _keys.append(str(p[1]))
	_ok("★笔刷含 精英小将", _keys.has("__minion__:elite"))
	_ok("★笔刷含 训龟大师", _keys.has(scene.TRAINER_ID))

	# ② 训龟大师能自由摆(修 _spawn_trainers 的 DEBUG_EDIT 跳过 → 调试场里能摆)
	scene._edit_set_brush(scene.TRAINER_ID)
	var tr = scene._edit_place_unit(scene.TRAINER_ID, "left", Vector2(120, 120))
	_ok("★训龟大师能摆(is_trainer)", tr is Dictionary and tr.get("is_trainer", false))
	_ok("★大师带装配的主动技", scene.TRAINER_SKILLS.has(str(tr.get("_tr_active", ""))))
	scene._edit_select_unit(tr)
	scene._edit_set_trainer_skill("glacier")
	_ok("★大师主动可逐只切(→冰川)", str(tr.get("_tr_active", "")) == "glacier")

	# ③ 精英小将能摆(★修 elite:false 死bug — 原来调试场根本摆不出精英)
	scene._edit_minion_role = "elite"
	var el = scene._edit_place_unit("__minion__", "right", Vector2(240, 120))
	_ok("★精英小将能摆(is_elite=true·修了elite:false)", el is Dictionary and el.get("is_elite", false))
	scene._edit_minion_role = "front"
	var mn = scene._edit_place_unit("__minion__", "right", Vector2(260, 120))
	_ok("★对照·普通小将 is_elite=false(证明断言非恒真)", not mn.get("is_elite", false))

	# ④ 逐只配 血量/无敌/满龟能(原来全局)
	var t = scene._edit_place_unit("basic", "left", Vector2(300, 120))
	scene._edit_select_unit(t)
	var hp0 := float(t.get("maxHp", 0.0))
	scene._edit_sel_adjust_hp(500.0)
	_ok("★逐只调血量(+500)", absf(float(t["maxHp"]) - (hp0 + 500.0)) < 1.0, "%.0f→%.0f" % [hp0, float(t["maxHp"])])
	_ok("★无敌默认关(摆下来会掉血)", not t.get("_review_dummy", false))
	scene._edit_sel_toggle_invincible()
	_ok("★逐只无敌可开", t.get("_review_dummy", false))
	scene._edit_sel_toggle_energy()
	_ok("★逐只满龟能可开", t.get("_edit_fe", false))

	# ⑤ 面板折叠 API + static 持久
	scene._edit_toggle_collapse()
	_ok("★面板可折叠(点一下 collapsed=true)", RB._edit_collapsed)
	scene._edit_toggle_collapse()
	_ok("★再点展开(collapsed=false)", not RB._edit_collapsed)

	# ⑥ 快照/重建 保住大师+精英(▶开始/⏸编辑/存盘 不丢)
	scene._edit_snapshot_setup()
	var kinds := {"trainer": false, "elite": false}
	for s in scene._edit_paused_setup:
		if bool(s.get("trainer", false)): kinds["trainer"] = true
		if str(s.get("role", "")) == "elite": kinds["elite"] = true
	_ok("★快照存了 大师", kinds["trainer"])
	_ok("★快照存了 精英(role=elite)", kinds["elite"])

	scene.queue_free()
	print("ALL PASS — 调试场重做(笔刷栏/大师/精英/逐只配/折叠)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
