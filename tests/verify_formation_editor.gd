extends Node
## verify_formation_editor.gd —— 背包·站位编辑(2026-10-19)
##
## 用户 10-19「站位改为在背包里做好了」「我想在背包里实现站位修改，这样在对局内将不再有拖动站位环节」。
## 全程走真入口: 开背包场景 → 真点顶栏「站位」(FormationBtn) → 真拖(push_input 的鼠标事件) → 松手。
##   ① 版式(16:9 与 19.5:9 各一遍): 面板不压顶栏、不出屏; 顶栏「站位」签不与同排别的签重叠;
##      触控热区 ≥ 81(站位签 / 每只龟 / 两颗底键); 每路画出的龟数 = 阵容格子数
##   ② 拖动: 拖动中龟头像跟手(中心 = 指针 - 按下时的抓取偏移); 松手后 `dual_lineup[路][i].off`
##      = 按【独立算法】(场地像素 ÷ 0.6 → 世界 → 减队形中心 → 取整) 算出的那一格;
##      松手后龟头像停在【存下的那一格】; 拖过中线 ⇒ 被夹在我方半场(off.x = DX_MAX), 拖动中也不越线
##   ③ 开一局(真建场, 预览快路径): 我方单位就站在 `clamp_place_side(队形中心 + off)` ——
##      与背包里摆的是同一个点(不碰障碍时逐位相等)
##   ④ 「恢复默认」: 两路的 off 全清, 龟回到默认竖排
##   ⑤ 「完成」关掉面板

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const LP := preload("res://scripts/gamedata/lineup_pos.gd")
const FE := preload("res://scripts/scenes/inventory/formation_editor.gd")

const LEAD := ["basic", "stone", "bamboo"]
const SCALE := 0.6                     # 独立写一份: 场地显示比例(世界像素 → 屏幕像素)
const SHOT_DIR := "C:/tmp/play/fe"     # 版式几何(给离线出图用); 写不进就算了, 不影响判定

var _n := 0
var _fail := 0
var _gs = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_gs.test_mode = true
	_gs.tutorial_active = false
	_gs.onboarded = true
	print("=== 背包·站位编辑 ===")
	_setup_lineup()
	for r in [[1280, "16x9"], [1560, "19.5x9"]]:
		await _layout_pass(int(r[0]), str(r[1]))
	await _drag_pass()
	await _battle_pass()
	await _reset_pass()
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


func _setup_lineup() -> void:
	_gs.reset_dual_lane()
	_gs.dual_active = false
	_gs.season_leaders = LEAD.duplicate()
	_gs.dual_lineup = {
		"top": [
			{"kind": "leader", "slot": 0, "id": LEAD[0], "equips": []},
			{"kind": "minion", "role": "front", "equips": []},
		],
		"bottom": [
			{"kind": "leader", "slot": 1, "id": LEAD[1], "equips": []},
			{"kind": "leader", "slot": 2, "id": LEAD[2], "equips": []},
			{"kind": "minion", "role": "back", "equips": []},
		],
	}
	_gs.get_dual_lineup()


func _set_size(w: int) -> void:
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.size = Vector2i(w, 720)


func _open_inventory() -> Node:
	var sc = load("res://scenes/Inventory.tscn").instantiate()
	get_tree().root.add_child(sc)
	for _i in range(20):
		await get_tree().process_frame
	return sc


func _close_inventory(sc: Node) -> void:
	sc.queue_free()
	for _i in range(3):
		await get_tree().process_frame


## 画布坐标 → 推给视口的坐标(窗口坐标)。
func _scr(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = _scr(p)
	e.global_position = _scr(p)
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	get_viewport().push_input(e)


func _motion(p: Vector2, rel: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = _scr(p)
	m.global_position = _scr(p)
	m.relative = rel
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(m)


func _click(c: Control) -> void:
	var p: Vector2 = c.get_global_rect().get_center()
	_motion(p, Vector2.ZERO)
	_mouse(p, true)
	_mouse(p, false)
	for _i in range(3):
		await get_tree().process_frame


func _editor(sc: Node) -> Control:
	return sc.find_child("FormationEditor", true, false) as Control


func _open_editor(sc: Node) -> Control:
	var fb := sc.find_child("FormationBtn", true, false) as Button
	if fb == null:
		return null
	await _click(fb)
	return _editor(sc)


# ══════════════════════════════════════════════════════════════
#  ① 版式
# ══════════════════════════════════════════════════════════════
func _layout_pass(w: int, tag: String) -> void:
	print("── ① 版式 %s (%d×720) ──" % [tag, w])
	_set_size(w)
	for _i in range(3):
		await get_tree().process_frame
	var sc = await _open_inventory()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var fb := sc.find_child("FormationBtn", true, false) as Button
	_ok("[%s] ★分母: 顶栏有「站位」签且可见" % tag, fb != null and fb.is_visible_in_tree())
	if fb == null:
		await _close_inventory(sc)
		return
	var fr: Rect2 = fb.get_global_rect()
	_ok("[%s] 「站位」签热区 ≥ 81" % tag, fr.size.y >= 81.0 and fr.size.x >= 81.0, str(fr.size))
	_ok("[%s] 「站位」签在屏内" % tag, fr.position.x >= 0.0 and fr.end.x <= vp.x + 0.5, str(fr))
	var overl: Array = []
	for b in fb.get_parent().get_children():
		if b != fb and b is Button and (b as Button).is_visible_in_tree() and (b as Button).get_global_rect().intersects(fr):
			overl.append(str((b as Button).text))
	_ok("[%s] 「站位」签不与同排别的签重叠" % tag, overl.is_empty(), str(overl))
	var ed := await _open_editor(sc)
	_ok("[%s] ★点「站位」⇒ 站位面板打开" % tag, ed != null and ed.is_visible_in_tree())
	if ed == null:
		await _close_inventory(sc)
		return
	var er: Rect2 = ed.get_global_rect()
	_ok("[%s] 面板不压顶栏(上沿 = 顶栏下沿 %.0f)" % [tag, TopBar.BAR_H], absf(er.position.y - TopBar.BAR_H) < 0.5, str(er))
	_ok("[%s] 面板铺满宽度" % tag, er.position.x <= 0.5 and er.end.x >= vp.x - 0.5, str(er))
	## 面板里每一个可见控件都在 [0, vw] × [BAR_H, 720] 里
	var outs: Array = []
	var geo: Array = []
	var cs: Array = []
	_collect(ed, cs)
	for c in cs:
		var r: Rect2 = (c as Control).get_global_rect()
		geo.append({"name": str((c as Control).name), "cls": (c as Control).get_class(), "r": [r.position.x, r.position.y, r.size.x, r.size.y],
			"text": str(c.get("text")) if c.get("text") != null else ""})
		if c == ed:
			continue
		if r.position.x < -0.5 or r.end.x > vp.x + 0.5 or r.position.y < TopBar.BAR_H - 0.5 or r.end.y > vp.y + 0.5:
			outs.append("%s %s" % [str((c as Control).name), str(r)])
	_ok("[%s] ★分母: 面板里有 %d 个可见控件" % [tag, cs.size()], cs.size() >= 12)
	_ok("[%s] ★没有控件出屏 / 压进顶栏" % tag, outs.is_empty(), str(outs))
	## 龟头像: 数量 = 阵容格子数; 热区 ≥ 81
	var lu: Dictionary = _gs.get_dual_lineup()
	for lane in ["top", "bottom"]:
		var n: int = (lu[lane] as Array).size()
		var small: Array = []
		var got := 0
		for i in range(n):
			var t := ed.find_child("Token_%s_%d" % [lane, i], true, false) as Control
			if t != null:
				got += 1
				if t.size.x < 81.0 or t.size.y < 81.0:
					small.append(i)
		_ok("[%s] %s: 画出 %d / %d 只" % [tag, lane, got, n], got == n)
		_ok("[%s] %s: 龟头像热区 ≥ 81" % [tag, lane], small.is_empty(), str(small))
	for nm in ["FormationReset", "FormationDone"]:
		var b := ed.find_child(nm, true, false) as Button
		_ok("[%s] %s 热区 ≥ 81 高" % [tag, nm], b != null and b.size.y >= 81.0, str(b.size) if b != null else "无")
	## 两块场地不重叠、在屏内居中
	var ft := ed.find_child("Field_top", true, false) as Control
	var fbm := ed.find_child("Field_bottom", true, false) as Control
	if ft != null and fbm != null:
		var a: Rect2 = ft.get_global_rect()
		var b2: Rect2 = fbm.get_global_rect()
		_ok("[%s] 两块场地不重叠" % tag, not a.intersects(b2), "%s / %s" % [a, b2])
		var mid: float = (a.position.x + b2.end.x) * 0.5
		_ok("[%s] 两块场地水平居中" % tag, absf(mid - vp.x * 0.5) < 2.0, "中点 %.1f / 屏宽一半 %.1f" % [mid, vp.x * 0.5])
	_dump_geo(tag, vp, sc, geo)
	var done := ed.find_child("FormationDone", true, false) as Button
	await _click(done)
	_ok("[%s] ⑤「完成」⇒ 面板关掉" % tag, _editor(sc) == null or not is_instance_valid(_editor(sc)) or _editor(sc).is_queued_for_deletion())
	await _close_inventory(sc)


func _collect(n: Node, out: Array) -> void:
	if n is Control and (n as Control).is_visible_in_tree():
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


func _dump_geo(tag: String, vp: Vector2, sc: Node, geo: Array) -> void:
	var top: Array = []
	var fb := sc.find_child("FormationBtn", true, false) as Button
	if fb != null:
		for b in fb.get_parent().get_children():
			if b is Control and (b as Control).is_visible_in_tree():
				var r: Rect2 = (b as Control).get_global_rect()
				top.append({"name": str(b.name), "text": str(b.get("text")) if b.get("text") != null else "", "r": [r.position.x, r.position.y, r.size.x, r.size.y]})
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var f := FileAccess.open(SHOT_DIR + "/geo_%s.json" % tag, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"vp": [vp.x, vp.y], "bar_h": TopBar.BAR_H, "topbar": top, "editor": geo}))
		f.close()


# ══════════════════════════════════════════════════════════════
#  ② 拖动
# ══════════════════════════════════════════════════════════════
## 场地局部坐标 → 世界 → 偏移(独立写一份, 不调 InvFormation)。
func _expect_off(field: Control, center_global: Vector2) -> Vector2i:
	var local: Vector2 = field.get_global_transform().affine_inverse() * center_global
	var world: Vector2 = RB.ARENA.position + local / SCALE
	var base: Vector2 = RB.ARENA.position + RB.ARENA.size * 0.5 - Vector2(float(LP.FORMATION_DX), 0.0)
	return Vector2i(int(round(world.x - base.x)), int(round(world.y - base.y)))


func _token_world(t: Control) -> Vector2:
	var field := t.get_parent() as Control
	var local: Vector2 = field.get_global_transform().affine_inverse() * t.get_global_rect().get_center()
	return RB.ARENA.position + local / SCALE


func _drag(t: Control, grab: Vector2, delta: Vector2, steps: int) -> Dictionary:
	var c0: Vector2 = t.get_global_rect().get_center()
	var p0: Vector2 = c0 + grab
	_motion(p0, Vector2.ZERO)
	_mouse(p0, true)
	await get_tree().process_frame
	var worst := 0.0
	var max_x := -1e9
	for i in range(1, steps + 1):
		var p: Vector2 = p0 + delta * (float(i) / float(steps))
		_motion(p, delta / float(steps))
		await get_tree().process_frame
		var cc: Vector2 = t.get_global_rect().get_center()
		worst = maxf(worst, cc.distance_to(p - grab))
		max_x = maxf(max_x, _token_world(t).x)
	var pe: Vector2 = p0 + delta
	_mouse(pe, false)
	for _i in range(2):
		await get_tree().process_frame
	return {"worst": worst, "release": pe - grab, "max_x": max_x}


func _drag_pass() -> void:
	print("── ② 拖动 ──")
	_set_size(1280)
	for _i in range(3):
		await get_tree().process_frame
	var sc = await _open_inventory()
	var ed := await _open_editor(sc)
	_ok("★分母: 面板打开", ed != null)
	if ed == null:
		await _close_inventory(sc)
		return
	## 拖上路统领: 一段不碰任何边界的位移 ⇒ 全程跟手, 存下的 = 独立算的
	var t := ed.find_child("Token_top_0", true, false) as Control
	var field := ed.find_child("Field_top", true, false) as Control
	_ok("★分母: 找到上路统领头像", t != null and field != null)
	if t == null or field == null:
		await _close_inventory(sc)
		return
	var before = (_gs.get_dual_lineup()["top"][0] as Dictionary).get("off")
	_ok("★分母: 拖之前上路统领没有 off", before == null, str(before))
	var r: Dictionary = await _drag(t, Vector2(9, -7), Vector2(60, 40), 10)
	_ok("② ★拖动中头像跟手(中心 = 指针 - 抓取偏移, 最大偏差 %.2f px)" % float(r["worst"]), float(r["worst"]) <= 1.0)
	var want: Vector2i = _expect_off(field, r["release"])
	var got = (_gs.get_dual_lineup()["top"][0] as Dictionary).get("off")
	_ok("② ★松手 ⇒ dual_lineup.top[0].off = 独立算出的 %s" % str(want), got is Array and got == [want.x, want.y], str(got))
	var ww: Vector2 = RB.ARENA.position + RB.ARENA.size * 0.5 - Vector2(float(LP.FORMATION_DX), 0.0) + Vector2(want)
	_ok("② ★分母: 这一格不碰任何边界(可摆范围 / 岛形 / 中线), 本段位移不该被夹", want == LP.clamp_off(want)
		and ArenaShape.inside(ww, RB.ARENA, ArenaShape.N, 60.0) and ww.x <= RB.ARENA.position.x + RB.ARENA.size.x * 0.5 - 120.0, str(want))
	var tw: Vector2 = _token_world(t)
	_ok("② ★松手后头像停在存下的那一格", got is Array and tw.distance_to(FE.world_from_off(Vector2i(int(got[0]), int(got[1])))) <= 1.0 / SCALE,
		"头像 %s / 存的 %s" % [tw, FE.world_from_off(Vector2i(int(got[0]), int(got[1]))) if got is Array else "-"])

	## 拖下路第二只统领越过中线 ⇒ 被夹在我方半场
	var t2 := ed.find_child("Token_bottom_1", true, false) as Control
	_ok("★分母: 找到下路第二只统领", t2 != null)
	if t2 != null:
		var r2: Dictionary = await _drag(t2, Vector2.ZERO, Vector2(700, -20), 14)
		var got2 = (_gs.get_dual_lineup()["bottom"][1] as Dictionary).get("off")
		var mid_x: float = RB.ARENA.position.x + RB.ARENA.size.x * 0.5
		_ok("② ★拖过中线 ⇒ off.x 被夹到 DX_MAX = %d" % LP.DX_MAX, got2 is Array and int(got2[0]) == LP.DX_MAX, str(got2))
		_ok("② ★拖动全程不越线(最右世界 x %.1f ≤ 中线 - 120 = %.1f)" % [float(r2["max_x"]), mid_x - 120.0],
			float(r2["max_x"]) <= mid_x - 120.0 + 1.0 / SCALE)
		var tw2: Vector2 = _token_world(t2)
		_ok("② 松手后头像停在存下的那一格(越线那只)", got2 is Array and tw2.distance_to(FE.world_from_off(Vector2i(int(got2[0]), int(got2[1])))) <= 1.0 / SCALE,
			"头像 %s" % tw2)
	## 别的格子没被动
	var lu: Dictionary = _gs.get_dual_lineup()
	_ok("② 没拖过的格子不写 off", not (lu["top"][1] as Dictionary).has("off") and not (lu["bottom"][0] as Dictionary).has("off")
		and not (lu["bottom"][2] as Dictionary).has("off"))
	await _click(ed.find_child("FormationDone", true, false) as Button)
	await _close_inventory(sc)


# ══════════════════════════════════════════════════════════════
#  ③ 开一局: 单位就站在背包里摆的那一格
# ══════════════════════════════════════════════════════════════
func _battle_pass() -> void:
	print("── ③ 开一局 ──")
	var lu: Dictionary = _gs.get_dual_lineup().duplicate(true)
	var o = (lu["top"][0] as Dictionary).get("off")
	_ok("★分母: 上路统领带着背包里摆的 off 进场", o is Array, str(o))
	if not (o is Array):
		return
	var was_np: bool = bool(DualLaneFlow.NO_PRESENT)
	DualLaneFlow.NO_PRESENT = true
	_gs.dual_active = true
	_gs.current_lane = "top"
	_gs.dual_ghost = _fixed_ghost()
	var s = RB.new()
	add_child(s)
	## NO_PRESENT: 建场与开打都在 _ready 里同步发生 ⇒ 不等帧, 单位还在开打那一刻的位置上
	var me = null
	for u in s._units:
		if str(u.get("side", "")) == "left" and str(u.get("id", "")) == LEAD[0] and not u.get("_isEgg", false):
			me = u
	_ok("★分母: 场上找到上路我方统领 %s" % LEAD[0], me != null, "lane=%s units=%d" % [str(_gs.current_lane), s._units.size()])
	if me != null:
		var off := Vector2i(int(o[0]), int(o[1]))
		var cx: float = s.ARENA.position.x + s.ARENA.size.x * 0.5
		var cy: float = s.ARENA.position.y + s.ARENA.size.y * 0.5
		var want: Vector2 = s._dl_sys.clamp_place_side(Vector2(cx - 420.0 + float(off.x), cy + float(off.y)), "left")
		_ok("③ ★单位站在 clamp_place_side(队形中心 + off)", (me["pos"] as Vector2).is_equal_approx(want), "%s vs %s" % [me["pos"], want])
		var fe_w: Vector2 = FE.world_from_off(off)
		print("    [信息] 背包里那一格 %s / 场上 %s (差 %.1f: 只有碰到这张图的障碍才不为 0)" % [fe_w, me["pos"], fe_w.distance_to(me["pos"])])
		_ok("③ 背包与战场同一套队形中心(背包那一格经战场夹取 = 场上)", s._dl_sys.clamp_place_side(fe_w, "left").is_equal_approx(me["pos"]))
	for _g in range(10):
		await get_tree().process_frame
	s.queue_free()
	for _i in range(4):
		await get_tree().process_frame
	DualLaneFlow.NO_PRESENT = was_np
	_gs.dual_ghost = {}
	_gs.dual_active = false
	_gs.current_lane = "top"
	_gs.dual_lineup = lu          # 场景可能动过阵容, 还原成拖完的那一份给 ④ 用


# ══════════════════════════════════════════════════════════════
#  ④ 恢复默认
# ══════════════════════════════════════════════════════════════
func _reset_pass() -> void:
	print("── ④ 恢复默认 ──")
	_set_size(1280)
	for _i in range(3):
		await get_tree().process_frame
	var cnt0 := _count_off()
	_ok("★分母: 恢复之前有 %d 格带 off" % cnt0, cnt0 >= 2)
	var sc = await _open_inventory()
	var ed := await _open_editor(sc)
	var rb := ed.find_child("FormationReset", true, false) as Button if ed != null else null
	_ok("★分母: 找到「恢复默认」", rb != null)
	if rb != null:
		await _click(rb)
		_ok("④ ★「恢复默认」⇒ 两路 off 全清", _count_off() == 0, "剩 %d" % _count_off())
		var ed2 := _editor(sc)
		_ok("④ 面板还开着(重画)", ed2 != null and not ed2.is_queued_for_deletion())
		if ed2 != null:
			var t := ed2.find_child("Token_top_0", true, false) as Control
			var n: int = (_gs.get_dual_lineup()["top"] as Array).size()
			var d: Vector2 = FE.world_from_off(LP.default_off(0, n))
			_ok("④ 上路统领头像回到默认竖排那一格", t != null and _token_world(t).distance_to(d) <= 1.0 / SCALE,
				"%s vs %s" % [_token_world(t) if t != null else Vector2.ZERO, d])
			await _click(ed2.find_child("FormationDone", true, false) as Button)
	await _close_inventory(sc)


func _count_off() -> int:
	var k := 0
	var lu: Dictionary = _gs.get_dual_lineup()
	for lane in ["top", "bottom"]:
		for u in lu[lane]:
			if u is Dictionary and (u as Dictionary).has("off"):
				k += 1
	return k


func _fixed_ghost() -> Dictionary:
	return {
		"schema_ver": 1,
		"ghost_id": "formation_fixed_foe",
		"is_bot": true,
		"bracket": 0,
		"profile": {"name": "固定木桩", "avatar": "basic", "id": "FMT"},
		"leaders": ["basic", "stone"],
		"lane_assign": {"top": ["basic"], "bottom": ["stone"]},
		"minions": {"top": [], "bottom": []},
		"loadouts": {},
		"equipped": {},
		"pet_levels": {"basic": 1, "stone": 1},
		"season_total_battles": 0,
		"season_eggs_killed": 0,
	}
