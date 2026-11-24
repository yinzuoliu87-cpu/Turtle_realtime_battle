extends Node
## verify_bomb_mines.gd —— 102 地雷「在站位图中摆放」整条链(2026-11-24 · 方案书 docs/plans/20261124f-炸弹羁绊.md §4.2)
##
## 用户 11-24：地雷在站位图里摆，开打就埋在那里；不摆就埋在己方前排正前方。
## 链：背包站位图拖雷(InvFormation.commit_mine) → 存在那件地雷的装备条目 `mines` →
##     开打注入装备(EqBombBatch.eq_entry, 不丢 `mines`) → 登场埋雷(EqBombBatch._place_mines) 按 LineupPos 坐标落到场上。
## 判据：
##   A 拖第 2 颗 ⇒ 这件地雷条目写下整组 N 颗(N = 星级颗数)，第 2 颗 = 拖到的偏移，其余 = 默认位置
##   B 注入装备后条目还带着 `mines`(原来只留 id/star/chg)
##   C 真走换路管线 `_dl_build_lane_field` 开一路：场上的雷 = LineupPos.to_field(队形中心, 偏移, left)，逐颗对上
##   D 没摆过 ⇒ 默认：携带者正前方 MINE_FWD 码一排
##   E 右方(对手快照同一条目)按镜像落在右半场
## 反向(2026-11-24 实测)：eq_entry 里不带 mines ⇒ B、C 红；_place_mines 不镜像 ⇒ E 红。
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_gs.test_mode = true
	print("=== 102 地雷站位图摆放 ===")
	_gs.season_leaders = ["stone", "basic", "diamond"]
	_gs.persistent_equipped = {"stone": [{"id": "p2eq_102", "star": 3}], "basic": [], "diamond": [{"id": "p2eq_102", "star": 1}]}
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "id": "stone", "slot": 0, "off": [0, -100]}, {"kind": "leader", "id": "basic", "slot": 1}, {"kind": "minion", "role": "front"}],
		"bottom": [{"kind": "leader", "id": "diamond", "slot": 2}, {"kind": "minion", "role": "front"}, {"kind": "minion", "role": "back"}],
	}
	## A
	var fe = FE.new(null)
	fe.commit_mine("top", 0, 0, 1, Vector2i(150, 60))
	var e: Dictionary = _gs.persistent_equipped["stone"][0]
	var mines: Array = e.get("mines", [])
	var n3: int = int(B.MINE_COUNT[2])
	var d0: Vector2i = B.default_mine_off(Vector2i(0, -100), 0, n3)
	_ok("A 拖第 2 颗 ⇒ 整组 %d 颗写进这件地雷条目；第 2 颗 = (150,60)，第 1 颗 = 默认 %s" % [n3, str(d0)],
		mines.size() == n3 and int(mines[1][0]) == 150 and int(mines[1][1]) == 60 and int(mines[0][0]) == d0.x and int(mines[0][1]) == d0.y,
		str(mines))
	## B
	var inj: Dictionary = B.eq_entry(e, 0)
	_ok("B 注入装备后还带着摆位", inj.get("mines") is Array and (inj["mines"] as Array).size() == n3, str(inj))
	## C / D：真开一路
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._dl_sys._dl_clear_units()
	_s._equip_sys._bomb_sys.clear_all()
	_gs.current_lane = "top"
	_s._dl_sys._dl_build_lane_field()
	await get_tree().process_frame
	var bs = _s._equip_sys._bomb_sys
	var base: Vector2 = _s._arena_center - Vector2(float(LineupPos.FORMATION_DX), 0.0)
	var left_mines: Array = []
	for m in bs._mines:
		if str(m["side"]) == "left":
			left_mines.append(Vector2(m["pos"]))
	var hit := 0
	for k in range(n3):
		var want: Vector2 = LineupPos.to_field(base, Vector2i(int(mines[k][0]), int(mines[k][1])), "left")
		for p in left_mines:
			if (p as Vector2).distance_to(want) < 0.5:
				hit += 1
				break
	_ok("C 开打：上路 3★ 地雷埋了 %d 颗，逐颗落在站位图摆的位置(%d/%d 对上)" % [left_mines.size(), hit, n3],
		left_mines.size() == n3 and hit == n3, str(left_mines))
	## D：下路那只没摆过
	_s._dl_sys._dl_clear_units()
	bs.clear_all()
	_gs.current_lane = "bottom"
	_s._dl_sys._dl_build_lane_field()
	await get_tree().process_frame
	var carrier = null
	for u in _s._units:
		if str(u.get("id", "")) == "diamond" and str(u.get("side", "")) == "left":
			carrier = u
	var n1: int = int(B.MINE_COUNT[0])
	var okd: bool = carrier != null and bs._mines.size() >= n1
	if okd:
		for k in range(n1):
			var want2: Vector2 = Vector2(carrier["pos"]) + Vector2(B.MINE_FWD, (float(k) - float(n1 - 1) * 0.5) * B.MINE_GAP)
			var found := false
			for m in bs._mines:
				if Vector2(m["pos"]).distance_to(want2) < 8.0:   # 携带者登场后会被队形分离推开 1~2 码(雷按登场那一刻的位置埋)
					found = true
			okd = okd and found
	_ok("D 没摆过 ⇒ 1★ %d 颗默认埋在携带者正前方 %.0f 码一排" % [n1, B.MINE_FWD], okd, "雷 %d 颗" % bs._mines.size())
	## E：右方镜像 —— 合成一个右方携带者，带同一条摆位
	bs.clear_all()
	var r: Dictionary = _s._spawn._make_unit("stone", "right", _s._arena_center + Vector2(400, 0))
	r["equips"] = [inj.duplicate(true)]
	_s._units.append(r)
	bs.on_spawn(r, "p2eq_102", 2)
	var base_r: Vector2 = _s._arena_center + Vector2(float(LineupPos.FORMATION_DX), 0.0)
	var want_r: Vector2 = LineupPos.to_field(base_r, Vector2i(150, 60), "right")
	var hit_r := false
	for m in bs._mines:
		if Vector2(m["pos"]).distance_to(want_r) < 0.5:
			hit_r = true
	_ok("E 右方按镜像落在右半场(%s)" % str(want_r), hit_r and want_r.x > _s._arena_center.x)
	print("")
	print("ALL PASS — 102 地雷站位图摆放 (%d 条)" % _n if _fail == 0 and _n >= 5 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
