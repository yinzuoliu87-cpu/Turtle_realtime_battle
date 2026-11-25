extends Node
## verify_debug_summon_brush.gd —— 调试场「召唤物」笔刷 + 敌方「会动会打」(2026-11-24)
##
## 用户 11-24:「我们需要一个调试台…你能摆放一个友方单位，这单位可以是小龟，可以是任何召唤物。同样，我们有个敌方的靶子」。
## 判据(走调试场真入口: 笔刷摆放 `_edit_place_unit` → 「开始」`_edit_start_battle`):
##   A 召唤物笔刷每一件(SUMMON_EQ)摆下去开打后, 场上真的多出至少一个召唤物(is_summon), 召唤物的主人就是那个隐形携带者
##   B 隐形携带者: 藏起来(立绘不可见)、不可选中、不动、不打
##   C 敌方靶子默认站桩(no_move / no_basic); 开「会动会打」后两项都解除, 关掉又恢复
## 反向(2026-11-24 实测): 去掉 `_edit_ghostify()` 那一行 ⇒ B 红; `_edit_set_ai` 开的分支不清 no_move ⇒ C 红。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const DA := preload("res://scripts/scenes/battle/battle_debug_arena.gd")

var _n := 0
var _fail := 0


func _ok(nm: String, c: bool, d: String = "") -> void:
	_n += 1
	print(("  [PASS] " if c else "  [FAIL] ") + nm + ("  " + d if d != "" else ""))
	if not c:
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	GameState.test_mode = true
	print("=== 调试场召唤物笔刷 ===")
	RB.DEBUG_EDIT = true
	var c := Vector2(868, 474)
	var bad_a: Array = []
	var bad_b: Array = []
	for iid in DA.SUMMON_EQ:
		var s = RB.new()
		add_child(s)
		for _i in range(3):
			await get_tree().process_frame
		s._debug._edit_clear()
		s._debug.summon_eq = str(iid)
		s._edit_pick_star = 2
		var g: Dictionary = s._debug._edit_place_unit("__summon__", "left", c - Vector2(200, 0))
		s._debug._edit_place_unit("basic", "right", c + Vector2(150, 0))
		s._debug._edit_start_battle()
		## 轮询 + 上限(CLAUDE.md §4.5): 096 斧头等召唤物在开打后头几帧才生成(延到首帧 spawn), 只等一帧会漏判
		var summ := 0
		for _w in range(60):
			await get_tree().process_frame
			summ = 0
			for u in s._units:
				if bool(u.get("is_summon", false)) and str(u.get("side", "")) == "left":
					summ += 1
			if summ > 0 or (str(iid) == "p2eq_080" and not s._equip_sys._gun_sys._helis.is_empty()):
				break
		summ = 0
		for u in s._units:
			if bool(u.get("is_summon", false)) and is_same(u.get("summon_owner", null), g):
				summ += 1
		## 096 斧头 / 080 直升机等不一定登记 summon_owner 字段 ⇒ 退一步: 至少有个 is_summon 的左方单位
		if summ == 0:
			for u in s._units:
				if bool(u.get("is_summon", false)) and str(u.get("side", "")) == "left":
					summ += 1
		if summ == 0 and str(iid) != "p2eq_080":   # 080 直升机不是单位(演出节点), 单独看它的登记表
			bad_a.append(str(iid))
		if str(iid) == "p2eq_080" and s._equip_sys._gun_sys._helis.is_empty():
			bad_a.append(str(iid))
		var sp = g.get("sprite", null)
		var hidden: bool = not is_instance_valid(sp) or not (sp as Node3D).visible
		if not (hidden and s._is_untargetable(g) and bool(g.get("no_move", false)) and bool(g.get("no_basic", false))):
			bad_b.append(str(iid))
		s.queue_free()
		await get_tree().process_frame
	_ok("A ★%d 件召唤装备摆下去开打都召出了召唤物" % DA.SUMMON_EQ.size(), bad_a.is_empty(), str(bad_a))
	_ok("B 隐形携带者藏起来、不可选中、不动、不打", bad_b.is_empty(), str(bad_b))
	## C
	var s2 = RB.new()
	add_child(s2)
	for _i in range(3):
		await get_tree().process_frame
	s2._debug._edit_clear()
	var d: Dictionary = s2._debug._edit_place_unit("basic", "right", c + Vector2(150, 0))
	var st0: bool = bool(d.get("no_move", false)) and bool(d.get("no_basic", false))
	s2._debug._edit_set_ai(d, true)
	var st1: bool = not d.has("no_move") and not d.has("no_basic")
	s2._debug._edit_set_ai(d, false)
	var st2: bool = bool(d.get("no_move", false)) and bool(d.get("no_basic", false))
	_ok("C 敌方靶子默认站桩 → 开「会动会打」解除 → 关掉恢复", st0 and st1 and st2, "%s %s %s" % [str(st0), str(st1), str(st2)])
	RB.DEBUG_EDIT = false
	print("")
	print("ALL PASS — 调试场召唤物笔刷 (%d 条)" % _n if _fail == 0 and _n >= 3 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
