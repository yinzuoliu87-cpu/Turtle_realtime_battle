extends Node
## verify_bomb_mines.gd —— 102 地雷「在站位图中摆放」整条链(2026-11-24 · 方案书 docs/plans/20261124f-炸弹羁绊.md §4.2)
##
## 用户 11-24：「你装备了，就你有多少个地雷可放，你上半场比如说是四个，那你下半场也是四个，中间上也是四个，而且四个的位置都应该一致」。
## 链：背包站位图拖雷(InvFormation.commit_mine) → 存在那件地雷的装备条目 `mines` → 开打注入装备(EqBombBatch.eq_entry 不丢 `mines`)
##     → 每个战场开打按【全队】埋(EqBombBatch.place_team_mines)，坐标相对队形中心(LineupPos)。
## 判据：
##   A 拖全队第 1 件地雷的第 2 颗 ⇒ 这件条目写下整组 N 颗，第 2 颗 = 拖到的偏移，其余 = 默认
##   B 注入装备后条目还带着 `mines`
##   C 上路(只有 3★ 那只在这一路)：埋 5 + 3 = 8 颗(下路那只 1★ 的也算)，逐颗 = LineupPos.to_field(队形中心, 偏移)
##   D 下路：同样 8 颗、位置与上路逐颗相同
##   E 对方(快照里同样的条目)按镜像落在右半场
## 反向(2026-11-24 实测)：eq_entry 不带 mines ⇒ B/C/D 红；埋雷改回「只埋携带者那一路」⇒ C/D 红。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const FE := preload("res://scripts/scenes/inventory/formation_editor.gd")
const B := preload("res://scripts/systems/equip/eq_bomb_batch.gd")

var _n := 0
var _fail := 0
var _s = null
var _gs = null


func _ok(nm: String, c: bool, d: String = "") -> void:
	_n += 1
	print(("  [PASS] " if c else "  [FAIL] ") + nm + ("  " + d if d != "" else ""))
	if not c:
		_fail += 1


func _side_mines(side: String) -> Array:
	var out: Array = []
	for m in _s._equip_sys._bomb_sys._mines:
		if str(m["side"]) == side:
			out.append(Vector2(m["pos"]))
	return out


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for p in a:
		var hit := false
		for q in b:
			if (p as Vector2).distance_to(q) < 0.5:
				hit = true
				break
		if not hit:
			return false
	return true


func _build(lane: String) -> void:
	_s._dl_sys._dl_clear_units()
	_s._equip_sys._bomb_sys.clear_all()
	_gs.current_lane = lane
	_s._dl_sys._dl_build_lane_field()
	await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_gs.test_mode = true
	print("=== 102 地雷站位图摆放(全队·三个战场同位) ===")
	_gs.season_leaders = ["stone", "basic", "diamond"]
	_gs.persistent_equipped = {"stone": [{"id": "p2eq_102", "star": 3}], "basic": [], "diamond": [{"id": "p2eq_102", "star": 1}]}
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "id": "stone", "slot": 0, "off": [0, -100]}, {"kind": "leader", "id": "basic", "slot": 1}, {"kind": "minion", "role": "front"}],
		"bottom": [{"kind": "leader", "id": "diamond", "slot": 2}, {"kind": "minion", "role": "front"}, {"kind": "minion", "role": "back"}],
	}
	_gs.dual_active = true
	## A
	var fe = FE.new(null)
	var refs: Array = FE.mine_refs()
	_ok("★分母: 全队 2 件地雷(3★ 石头龟 / 1★ 钻石龟)", refs.size() == 2, str(refs))
	fe.commit_mine(0, 1, Vector2i(150, 60))
	var e: Dictionary = _gs.persistent_equipped["stone"][0]
	var mines: Array = e.get("mines", [])
	var n3: int = int(B.MINE_COUNT[2])
	var n1: int = int(B.MINE_COUNT[0])
	var d0: Vector2i = B.default_mine_off(0, 0, n3)
	_ok("A 拖第 2 颗 ⇒ 整组 %d 颗写进这件条目；第 2 颗 = (150,60)，第 1 颗 = 默认 %s" % [n3, str(d0)],
		mines.size() == n3 and int(mines[1][0]) == 150 and int(mines[1][1]) == 60 and int(mines[0][0]) == d0.x and int(mines[0][1]) == d0.y, str(mines))
	## B
	var inj: Dictionary = B.eq_entry(e, 0)
	_ok("B 注入装备后还带着摆位", inj.get("mines") is Array and (inj["mines"] as Array).size() == n3, str(inj))
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	var base: Vector2 = _s._arena_center - Vector2(float(LineupPos.FORMATION_DX), 0.0)
	var want: Array = []
	for k in range(n3):
		want.append(ArenaShape.clamp_in(LineupPos.to_field(base, Vector2i(int(mines[k][0]), int(mines[k][1])), "left"), _s.ARENA, 60.0))
	for k in range(n1):
		want.append(ArenaShape.clamp_in(LineupPos.to_field(base, B.default_mine_off(1, k, n1), "left"), _s.ARENA, 60.0))
	## C
	await _build("top")
	var top: Array = _side_mines("left")
	_ok("C 上路埋 %d 颗(3★ 的 %d 颗 + 下路那只 1★ 的 %d 颗)，逐颗在站位图的位置" % [top.size(), n3, n1], _same(top, want), str(top))
	## D
	await _build("bottom")
	var bot: Array = _side_mines("left")
	_ok("D 下路同样 %d 颗、与上路逐颗同位" % bot.size(), top.size() == n3 + n1 and _same(bot, top), str(bot))
	## E 对方：快照里同一条目 ⇒ 右半场镜像
	_gs.dual_ghost = {"top": [{"kind": "leader", "id": "stone", "equips": [inj.duplicate(true)]}],
		"bottom": [{"kind": "leader", "id": "basic"}]}
	await _build("top")
	var rm: Array = _side_mines("right")
	var base_r: Vector2 = _s._arena_center + Vector2(float(LineupPos.FORMATION_DX), 0.0)
	var want_r: Vector2 = ArenaShape.clamp_in(LineupPos.to_field(base_r, Vector2i(150, 60), "right"), _s.ARENA, 60.0)
	var hit_r := false
	for p in rm:
		if (p as Vector2).distance_to(want_r) < 0.5:
			hit_r = true
	_ok("E 对方 %d 颗，按镜像落在右半场(%s)" % [rm.size(), str(want_r)], rm.size() == n3 and hit_r and want_r.x > _s._arena_center.x, str(rm))
	_gs.dual_active = false
	print("")
	print("ALL PASS — 102 地雷站位图摆放 (%d 条)" % _n if _fail == 0 and _n >= 6 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
