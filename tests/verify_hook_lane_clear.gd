extends Node
## #21 换战场清掉在途钩子(用户 2026-11-07「上半场打完，到了下半场或到了终极战场之后，突然会射出两根钩锁」)。
## 走真入口: 大师放钩 → `_dl_next_lane` 换路(里面调 `_dl_clear_units`) → 在途数必须是 0;
##   新一路大师再放一次 ⇒ 在途恰好 1 根(原来是旧的 + 新的 = 2 根以上)。
## 由探针 tests/probes/_probe_hook_lane.gd 实测出根因后改成门禁。

var _fail := 0


func _chk(name: String, ok: bool, detail: String = "") -> void:
	print("  [%s] %s%s" % ["PASS" if ok else "FAIL", name, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fail += 1


func _left_trainer(s) -> Dictionary:
	for u in s._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left" and u.get("alive", false):
			return u
	return {}


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(s)
	for _i in range(5):
		await get_tree().process_frame
	print("=== #21 换战场清掉在途钩子 ===")
	var ts = s._trainer_sys
	var left = _left_trainer(s)
	if left.is_empty():
		s._spawn._spawn_trainers()
		left = _left_trainer(s)
	_chk("分母: 场上有我方训龟大师", not left.is_empty())
	if left.is_empty():
		_end(s)
		return
	left["_active_cd"] = 0.0
	var ok: bool = ts._cast_hook(left, Vector2.RIGHT)
	var before: int = ts._flights.size()
	print("  放钩 ok=%s 在途 %d 根" % [str(ok), before])
	_chk("分母: 换路前确实有钩子在飞", ok and before >= 1, "%d 根" % before)
	s._dl_sys._dl_next_lane("top")
	for _i in range(3):
		await get_tree().process_frame
	var after: int = ts._flights.size()
	print("  换路后在途 %d 根(需求 0)" % after)
	_chk("换路后在途钩子清空", after == 0, "%d 根" % after)
	_chk("换路后在途气波清空", ts._wave_flights.size() == 0, "%d 个" % ts._wave_flights.size())
	var left2 = _left_trainer(s)
	if left2.is_empty():
		s._spawn._spawn_trainers()   # 新一路的大师在开打时才生成, 这里照开头的做法补上
		left2 = _left_trainer(s)
	if not left2.is_empty():
		left2["_active_cd"] = 0.0
		ts._cast_hook(left2, Vector2.RIGHT)
		var n2: int = ts._flights.size()
		print("  新一路大师放钩后在途 %d 根(需求 1)" % n2)
		_chk("新一路大师放钩: 只有 1 根(不会「同时两根」)", n2 == 1, "%d 根" % n2)
	else:
		_chk("分母: 换路后有新一路的我方大师", false)
	_end(s)


func _end(s) -> void:
	s.queue_free()
	await get_tree().process_frame
	print("")
	print("ALL PASS — #21 换战场清掉在途钩子" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
