extends Node
## _probe_mvp_merge.gd — 探针: 量 MVP 角标条数 与 合计页行数(不下结论, 只打数)
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null

func _count_text(n: Node, needle: String) -> int:
	var c := 0
	if n is Label and str((n as Label).text) == needle:
		c += 1
	for ch in n.get_children():
		c += _count_text(ch, needle)
	return c

func _all_text(n: Node) -> String:
	var s := ""
	if n is Label:
		s += str((n as Label).text) + "|"
	for ch in n.get_children():
		s += _all_text(ch)
	return s

func _mk(nm: String, id: String, dealt: int, minion: bool = false) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", "left", Vector2(400, 400))
	u["name"] = nm
	u["id"] = id
	u["_st_dealt"] = dealt
	u["_st_taken"] = 10
	u["_st_heal"] = 0
	u["_st_crit"] = 0
	u["_st_kills"] = 1
	u["alive"] = true
	if minion:
		u["_isMinion"] = true
	return u

func _ready() -> void:
	await get_tree().process_frame
	GameState.test_mode = true
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false

	print("── A. MVP 角标: 同名两只(同 dealt) ──")
	var a := _mk("小将", "minion", 500)
	var b := _mk("小将", "minion", 500)
	var c := _mk("石龟", "stone", 100)
	var col = _s._hud._stats_column("我方", [a, b, c], Color.WHITE)
	print("   MVP 标签条数 = %d  (期望 1)" % _count_text(col, "MVP"))
	print("   文本: ", _all_text(col).substr(0, 200))

	print("── A2. 同名但 dealt 不同 ──")
	var a2 := _mk("小将", "minion", 500)
	var b2 := _mk("小将", "minion", 300)
	var col2 = _s._hud._stats_column("我方", [a2, b2], Color.WHITE)
	print("   MVP 标签条数 = %d  (期望 1)" % _count_text(col2, "MVP"))

	print("── B. 合计: 同名同 id 的【小将】, 两路各一只 ──")
	var p1 := {"lane": "top", "left": [_s._st_row(_mk("小将", "minion", 100, true))], "right": []}
	var p2 := {"lane": "bottom", "left": [_s._st_row(_mk("小将", "minion", 200, true))], "right": []}
	var m1: Array = _s._hud._st_merge_all([p1, p2], "left")
	print("   行数 = %d (两只不同实体, 期望 2)" % m1.size())
	for r in m1:
		print("     行: name=%s dealt=%d" % [str(r["name"]), int(r["_st_dealt"])])

	print("── C. 合计: 同名不同 id, 两路各一只 ──")
	var p3 := {"lane": "top", "left": [_s._st_row(_mk("小将", "minionA", 100))], "right": []}
	var p4 := {"lane": "bottom", "left": [_s._st_row(_mk("小将", "minionB", 200))], "right": []}
	var m2: Array = _s._hud._st_merge_all([p3, p4], "left")
	print("   行数 = %d (期望 2)" % m2.size())
	for r in m2:
		print("     行: name=%s dealt=%d" % [str(r["name"]), int(r["_st_dealt"])])

	print("── D. 合计: 同一路内 3 只同名小将 ──")
	var p5 := {"lane": "top", "left": [_s._st_row(_mk("小将", "minion", 10, true)),
		_s._st_row(_mk("小将", "minion", 20, true)), _s._st_row(_mk("小将", "minion", 30, true))], "right": []}
	var m3: Array = _s._hud._st_merge_all([p5], "left")
	print("   行数 = %d (期望 3)" % m3.size())

	print("── E. _st_mvp_index(按单位) ──")
	var r1: Dictionary = _s._st_row(_mk("小将", "minion", 500))
	var r2: Dictionary = _s._st_row(_mk("小将", "minion", 300))
	var r3: Dictionary = _s._st_row(_mk("石龟", "stone", 100))
	print("   mvp_index = %d  (期望 0)" % _s._hud._st_mvp_index([r1, r2, r3]))
	print("   mvp_index(并列 500/500) = %d  (期望 0, 只给一个)"
		% _s._hud._st_mvp_index([_s._st_row(_mk("小将", "minion", 500)), _s._st_row(_mk("小将", "minion", 500))]))
	print("   mvp_index(全 0 伤害) = %d  (期望 -1)"
		% _s._hud._st_mvp_index([_s._st_row(_mk("小将", "minion", 0))]))

	print("── F. 合计: 真龟打完上路又打决胜(应仍合成一行) ──")
	var q1 := {"lane": "top", "left": [_s._st_row(_mk("石龟", "stone", 100))], "right": []}
	var q2 := {"lane": "final", "left": [_s._st_row(_mk("石龟", "stone", 200))], "right": []}
	var mf: Array = _s._hud._st_merge_all([q1, q2], "left")
	print("   行数 = %d (期望 1), dealt = %d (期望 300)" % [mf.size(), int(mf[0]["_st_dealt"]) if mf.size() > 0 else -1])

	print("PROBE DONE")
	get_tree().quit(0)
