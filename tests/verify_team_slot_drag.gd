extends Node
## verify_team_slot_drag.gd — 选统领页: 编队槽之间拖动换位, 不会被「按下就算点一下」吃掉(2026-10-29 用户「拖不起来」)
##
## 病根: 编队槽 `gui_input` 【按下】就走 `_on_slot_click` —— 而同一个槽又是拖动源。
##   · 拖一次(0 → 2): 按下那一下被当成「首次点 = 选中 0 号」, 拖完选中还挂着
##   · 再按住 0 号想拖: 成了「二次点同一格 = 移除」→ 按下那一刻龟就被拿出阵容, 槽空了 → 拖不起来
##   · 选中别的槽时按住拖: 按下当场互换
## 改成松手且没怎么动才算点一下(与龟卡 / 背包卡同一口径); 落下后清掉残留选中。
## 走真入口(往视口推鼠标), 量 team 数组。
##   S1 0 号拖到 2 号 = 互换, 且没留下选中
##   S2 紧接着再拖 0 号到 1 号 = 互换(旧: 按下就把 0 号移除了)
##   S3 先点 0 号(选中)再拖 2 号到 1 号 = 只换 2↔1, 0 号不动
##   S4 点选流程照旧: 点 0 再点 2 = 互换; 同一格点两下 = 移除
##   S5 点选 0 号后把它拖去 2 号 = 选中作废; 再点 0 号只是选中(旧: 高亮挂到换过来的龟上, 再点 = 移除它)

const TS := preload("res://scenes/TeamSelect.tscn")

var _fail := 0
var _n := 0
var inst
var ids: Array = []


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _btn(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; e.position = p; e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(e, true)


func _drag(from: Vector2, to: Vector2) -> void:
	_btn(from, true)
	await get_tree().process_frame
	for k in range(1, 15):
		var m := InputEventMouseMotion.new()
		var p := from.lerp(to, float(k) / 14.0)
		m.position = p; m.global_position = p; m.relative = (to - from) / 14.0
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(m, true)
		await get_tree().process_frame
	_btn(to, false)
	for _i in range(3):
		await get_tree().process_frame


func _click(p: Vector2) -> void:
	_btn(p, true)
	await get_tree().process_frame
	_btn(p, false)
	for _i in range(3):
		await get_tree().process_frame


func _slot(i: int) -> Vector2:
	return (inst._slot_nodes[i] as Control).get_global_rect().get_center()


func _team() -> String:
	var out: Array = []
	for t in inst.team:
		out.append("-" if t == null else str(ids.find(t)))
	return ",".join(out)


func _put_team(t: Array) -> void:
	inst.team = t.duplicate()
	inst._selected_slot_idx = -1
	inst._active_slot_idx = -1
	inst._refresh_all()
	for _i in range(3):
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	GameState.test_mode = true
	GameState.season_leaders = []
	print("=== 选统领页·编队槽拖动 ===")
	## 三只普通龟(会自带随从占位的几只不要: 占位只能放空格, 会把换位规则搅进来)
	for p in DataRegistry.launch_pets:
		var pid := str(p["id"])
		if pid in ["hiding", "crystal", "candy"]:
			continue
		ids.append(pid)
		if ids.size() >= 3:
			break
	inst = TS.instantiate()
	add_child(inst)
	for _i in range(60):
		await get_tree().process_frame
	_ok("分母: 三只普通龟、三个槽、阵容没锁", ids.size() == 3 and (inst._slot_nodes as Array).size() == 3 and not inst._roster_locked,
		"%s · 槽 %d · 锁 %s" % [ids, (inst._slot_nodes as Array).size(), inst._roster_locked])
	if ids.size() < 3:
		_finish(); return
	await _put_team([ids[0], ids[1], ids[2]])

	# ── S1 ──
	await _drag(_slot(0), _slot(2))
	_ok("S1 ★0 号拖到 2 号 = 互换, 不留选中", _team() == "2,1,0" and int(inst._selected_slot_idx) == -1,
		"阵容 %s · 选中 %d" % [_team(), int(inst._selected_slot_idx)])

	# ── S2 ──
	await _drag(_slot(0), _slot(1))
	_ok("S2 ★紧接着再拖 0 号到 1 号 = 互换(不是按下就移除)", _team() == "1,2,0", "阵容 %s" % _team())

	# ── S3 ──
	await _put_team([ids[0], ids[1], ids[2]])
	await _click(_slot(0))
	var sel0 := int(inst._selected_slot_idx)
	await _drag(_slot(2), _slot(1))
	_ok("S3 ★先点选 0 号, 再拖 2 号到 1 号 = 只换 2↔1", sel0 == 0 and _team() == "0,2,1", "点后选中 %d · 阵容 %s" % [sel0, _team()])

	# ── S5 点选 0 号后又把 0 号拖去 2 号: 选中作废; 再点 0 号只是选中, 不是把换过来的那只移除 ──
	await _put_team([ids[0], ids[1], ids[2]])
	await _click(_slot(0))
	await _drag(_slot(0), _slot(2))
	var sel5 := int(inst._selected_slot_idx)
	await _click(_slot(0))
	_ok("S5 ★点选后拖走 = 选中作废; 再点那一格只是选中", sel5 == -1 and _team() == "2,1,0" and int(inst._selected_slot_idx) == 0,
		"拖后选中 %d · 阵容 %s · 再点后选中 %d" % [sel5, _team(), int(inst._selected_slot_idx)])

	# ── S4 点选流程照旧 ──
	await _put_team([ids[0], ids[1], ids[2]])
	await _click(_slot(0))
	await _click(_slot(2))
	_ok("S4 点 0 再点 2 = 互换", _team() == "2,1,0", "阵容 %s" % _team())
	await _put_team([ids[0], ids[1], ids[2]])
	await _click(_slot(1))
	await _click(_slot(1))
	_ok("S4b 同一格点两下 = 移除", _team() == "0,-,2", "阵容 %s" % _team())

	_finish()


func _finish() -> void:
	print("\n合计 %d 项 · 失败 %d · 用了 %d 帧" % [_n, _fail, Engine.get_process_frames()])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)
