extends Node

## verify_interaction_matrix.gd — 交互矩阵: 【阶段 × 手势】逐格验 (2026-07-22)
##
## 建这个的原因很直接: 2026-07-22 一天之内, 用户报的每一个交互问题
## 都发生在【门禁 100% 绿】的时候, 而且全部落在"某个阶段 × 某个手势"的交叉点上:
##   · 暂停 × 拖动     → 拖不动(process_mode)
##   · 暂停 × 移动鼠标 → 光标不动(autoload process_mode)
##   · 放置 × 拖单位   → 龟停在半路、镜头跑了(相机块 return true 吞掉事件)
##     (2026-10-19 起对局里没有放置阶段, 这一行只是由来)
##
## 我原来的 verify_cam_pan 写了 14 条事件序列断言, 【一条都没覆盖放置阶段】——
## 因为我只测"我想到的路径"。矩阵的意义就是逼着把每一格都列出来, 空着的格子一眼可见。
##
## ★一律【直接调 _unhandled_input / _cam_handle_input】而不是 push_input:
##   push_input 会按内容缩放换算坐标(实测 300px 进去变成 6000), 命中判定全落空,
##   会得到"放置逻辑没收到按下"这种假结论(2026-07-22 我差点据此报错误的根因)。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
var _rows: Array = []


func _ok(cell: String, expect: String, cond: bool, got: String = "") -> void:
	_rows.append([cell, expect, cond, got])
	if not cond:
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	var s = RTScene.new()
	get_tree().root.add_child(s)
	for i in 20:
		await get_tree().process_frame
	s._dl_sys._dl_build_lane_field()
	for i in 8:
		await get_tree().process_frame

	var u = _own_unit(s)
	if u == null:
		print("  [FAIL] 场上没有我方可拖单位 —— 空检查不是通过")
		get_tree().quit(1)
		return
	print("  [分母] 场上单位 %d 个" % s._units.size())

	_cell_fight_drag(s)
	_cell_paused_drag(s)
	_cell_wheel_zoom(s)
	_cell_pinch_not_pan(s)
	_cell_no_button_no_pan(s)

	_report()
	s.queue_free()
	get_tree().quit(0 if _fail == 0 else 1)


func _own_unit(s):
	for o in s._units:
		if str(o.get("side", "")) == "left" and not o.get("_isEgg", false) \
		   and not o.get("is_summon", false) and not o.get("is_trainer", false):
			return o
	return null


## 连发 4 次左键拖动, 返回镜头位移
func _drag(s, use_cam_only: bool = false) -> float:
	s._cam_pan_reset()
	var p0 = s._cam_pan
	s._pan_active = true
	s._pan_moved = true
	s._touch_seen = false
	for i in 4:
		var m := InputEventMouseMotion.new()
		m.position = Vector2(400 + 40 * i, 300)
		m.relative = Vector2(40, 0)
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		if use_cam_only:
			s._cam_handle_input(m)
		else:
			s._unhandled_input(m)
	return p0.distance_to(s._cam_pan)


## (原 ① ② 「放置阶段 × 拖单位 / 拖空地」两格: 2026-10-19 对局里没有放置阶段了(站位在背包里摆),
##   相机块里那道「拖龟时镜头让路」的闸随之删除 ⇒ 这两格没有被测对象, 一并删掉。)


## ③ 战斗中 × 拖动 → 镜头能动, 且【手里的残留引用不该影响它】
func _cell_fight_drag(s) -> void:
	s._dl_state = "fight"
	s._edit_drag_unit = _own_unit(s)   # 故意留个残留值
	var d := _drag(s, true)
	_ok("战斗 × 拖动(带残留引用)", "镜头能动", d > 0.001, "平移 %.4f 米" % d)
	s._edit_drag_unit = null


## ④ 暂停 × 拖动 → 仍要能看战场(2026-07-22 测试人员报的那条)
func _cell_paused_drag(s) -> void:
	s._dl_state = "fight"
	var was := get_tree().paused
	get_tree().paused = true
	var d := _drag(s, true)
	get_tree().paused = was
	_ok("暂停 × 拖动", "镜头能动", d > 0.001, "平移 %.4f 米" % d)


## ⑤ 滚轮缩放 —— 各阶段都该生效
func _cell_wheel_zoom(s) -> void:
	for st in ["fight"]:
		s._dl_state = st
		var z0: float = s._cam_zoom
		var w := InputEventMouseButton.new()
		w.button_index = MOUSE_BUTTON_WHEEL_UP
		w.pressed = true
		s._cam_handle_input(w)
		_ok("战斗 × 滚轮", "缩放变化",
			absf(s._cam_zoom - z0) > 0.0001, "zoom %.3f → %.3f" % [z0, s._cam_zoom])
		s._cam_zoom = z0
		s._apply_cam_zoom()


## ⑥ 双指捏合 → 只缩放, 不平移(两指时平移必须让路)
func _cell_pinch_not_pan(s) -> void:
	s._dl_state = "fight"
	s._touch_pts.clear()
	s._cam_pan_reset()
	var p0 = s._cam_pan
	for idx in 2:
		var t := InputEventScreenTouch.new()
		t.index = idx
		t.pressed = true
		t.position = Vector2(300 + 200 * idx, 300)
		s._cam_handle_input(t)
	var z0: float = s._cam_zoom
	for idx in 2:
		var dg := InputEventScreenDrag.new()
		dg.index = idx
		dg.position = Vector2(250 + 300 * idx, 300)
		dg.relative = Vector2(-50 + 100 * idx, 0)
		s._cam_handle_input(dg)
	_ok("战斗 × 双指捏合", "只缩放不平移",
		p0.distance_to(s._cam_pan) < 0.001, "却平移了 %.4f 米" % p0.distance_to(s._cam_pan))
	_ok("战斗 × 双指捏合", "缩放确实变了", absf(s._cam_zoom - z0) > 0.0001,
		"zoom %.3f → %.3f" % [z0, s._cam_zoom])
	s._touch_pts.clear()
	s._cam_zoom = z0
	s._apply_cam_zoom()


## ⑦ 没按键 × 移动鼠标 → 不许平移(release 被 GUI 吃掉时 _pan_active 会永久卡 true)
func _cell_no_button_no_pan(s) -> void:
	s._dl_state = "fight"
	s._edit_drag_unit = null
	s._cam_pan_reset()
	var p0 = s._cam_pan
	s._pan_active = true
	s._pan_moved = false
	s._pan_from = Vector2(400, 300)
	s._touch_seen = false
	for i in 4:
		var m := InputEventMouseMotion.new()
		m.position = Vector2(400 + 40 * i, 300)
		m.relative = Vector2(40, 0)
		m.button_mask = 0
		s._cam_handle_input(m)
	var d: float = p0.distance_to(s._cam_pan)
	_ok("任意 × 空手移鼠标", "镜头不动", d < 0.001, "平移 %.4f 米" % d)


func _report() -> void:
	print("")
	print("  ┌─ 交互矩阵 ─────────────────────────────────────────────")
	for r in _rows:
		var mark: String = "OK  " if r[2] else "FAIL"
		print("  │ [%s] %-22s 期望: %-14s %s" % [mark, str(r[0]), str(r[1]), str(r[3])])
	print("  └────────────────────────────────────────────────────────")
	print("  [分母] 矩阵共 %d 格" % _rows.size())
	## 2026-10-19 删掉放置阶段三格(拖单位 / 拖空地 / 放置×滚轮) ⇒ 9 → 6 格。
	if _rows.size() < 6:
		_fail += 1
		print("  [FAIL] 矩阵只有 %d 格 —— 格子少了就是漏测(空检查不是通过)" % _rows.size())
	print("ALL PASS — 交互矩阵(阶段 × 手势)" if _fail == 0 else "FAILED: %d 格不通过" % _fail)
