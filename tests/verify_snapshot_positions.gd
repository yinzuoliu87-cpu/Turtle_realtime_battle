extends Node
## verify_snapshot_positions.gd —— 站位在背包里摆好、随阵容进快照(2026-10-19 · 方案书 20261019-服务器裁判 §2)
##
## 用户 10-19「站位改为在背包里做好了」。10-18 周日实战: 对局里摆的站位只在本机、不进快照 ⇒「本地站位赢、服务器判输」。
## ① 快照带站位: 统领按龟 id(`leader_off`), 小将在各自那条里(`off`); 没摆过的不写
## ② 开打: 我方按 `off` 站(再按岛形 + 障碍夹), 对手按快照里的 `off` 镜像站
## ③ 没摆过的那一路 = 原来的固定队形(逐位不变 ⇒ 旧存档 / 旧快照 / 机器人 / 跨平台金标都不受影响)
## ④ 整数往返: pack 出来是整数, 越界被钳进可摆范围

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const LP := preload("res://scripts/gamedata/lineup_pos.gd")
const BE := preload("res://scripts/net/backend.gd")

var _n := 0
var _fail := 0
var _s = null
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
	if _gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	_gs.test_mode = true
	print("=== 站位进快照 ===")

	## ④ 整数往返 / 钳范围
	_ok("④ pack 是整数数组", LP.pack(Vector2i(12, -34)) == [12, -34])
	_ok("④ 越界钳进可摆范围", LP.pack(Vector2i(9999, -9999)) == [LP.DX_MAX, LP.DY_MIN])

	var lead: Array = ["stone", "basic", "diamond"]
	_gs.season_leaders = lead.duplicate()
	var OFF_L := [-100, 200]
	var OFF_M := [150, -250]
	_gs.dual_lineup = {
		"top": [
			{"kind": "leader", "id": lead[0], "slot": 0, "off": OFF_L.duplicate()},
			{"kind": "minion", "role": "front", "off": OFF_M.duplicate()},
			{"kind": "minion", "role": "back"},
		],
		"bottom": [
			{"kind": "leader", "id": lead[1], "slot": 1},
			{"kind": "leader", "id": lead[2], "slot": 2},
			{"kind": "minion", "role": "front"},
		],
	}

	## ① 快照
	var snap: Dictionary = BE.build_ghost_snapshot("g_pos_test", {"name": "站位测试"})
	var loff: Dictionary = snap.get("leader_off", {})
	var mt: Array = (snap.get("minions", {}) as Dictionary).get("top", [])
	var mb: Array = (snap.get("minions", {}) as Dictionary).get("bottom", [])
	_ok("① ★快照带统领站位", loff.get(lead[0]) == OFF_L, str(loff))
	_ok("① 没摆过的统领不写", not loff.has(lead[1]) and not loff.has(lead[2]), str(loff.keys()))
	_ok("① ★分母: 上路 2 个小将", mt.size() == 2, str(mt.size()))
	if mt.size() == 2:
		_ok("① ★快照带小将站位", (mt[0] as Dictionary).get("off") == OFF_M, str(mt[0]))
		_ok("① 没摆过的小将不写", not (mt[1] as Dictionary).has("off"))
	_ok("① 下路小将没有站位", mb.size() == 1 and not (mb[0] as Dictionary).has("off"))
	## 往返: 快照经 JSON(上传 / 拉取就是这么走的)后仍是同一组整数
	var rt = JSON.parse_string(JSON.stringify(snap))
	_ok("① JSON 往返后统领站位仍是 [-100, 200]", rt is Dictionary and LP.off_of({"off": (rt["leader_off"] as Dictionary)[lead[0]]}, 0, 1) == Vector2i(-100, 200))

	## ② ③ 开打
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_gs.season_leaders = lead.duplicate()
	_gs.dual_lineup = _gs.dual_lineup     # 场景 _ready 可能重置过阵容, 再写一遍
	_gs.dual_ghost = rt
	var cx: float = _s.ARENA.position.x + _s.ARENA.size.x * 0.5
	var cy: float = _s.ARENA.position.y + _s.ARENA.size.y * 0.5
	var base_l := Vector2(cx - 420.0, cy)
	var base_r := Vector2(cx + 420.0, cy)

	_gs.current_lane = "top"
	_s._units.clear()
	_s._dl_sys._dl_build_lane_field()
	var mine := _side_units("left")
	var foes := _side_units("right")
	_ok("② ★分母: 上路我方 3 个 / 对手 3 个", mine.size() == 3 and foes.size() == 3, "%d / %d" % [mine.size(), foes.size()])
	if mine.size() == 3 and foes.size() == 3:
		var want_l: Vector2 = _s._dl_sys.clamp_place_side(LP.to_field(base_l, Vector2i(-100, 200), "left"), "left")
		var want_m: Vector2 = _s._dl_sys.clamp_place_side(LP.to_field(base_l, Vector2i(150, -250), "left"), "left")
		_ok("② ★我方统领按背包站位站", (mine[0]["pos"] as Vector2).is_equal_approx(want_l), "%s vs %s" % [mine[0]["pos"], want_l])
		_ok("② ★我方小将按背包站位站", (mine[1]["pos"] as Vector2).is_equal_approx(want_m), "%s vs %s" % [mine[1]["pos"], want_m])
		var dflt2: Vector2 = base_l + Vector2(0.0, (2.0 - 1.0) * 154.0)
		_ok("③ 我方没摆过的那个照旧固定队形", (mine[2]["pos"] as Vector2).is_equal_approx(dflt2), "%s vs %s" % [mine[2]["pos"], dflt2])
		var fl = _find(foes, lead[0])
		var want_fl: Vector2 = _s._dl_sys.clamp_place_side(LP.to_field(base_r, Vector2i(-100, 200), "right"), "right")
		_ok("② ★对手统领按快照站位镜像站", fl != null and (fl["pos"] as Vector2).is_equal_approx(want_fl), "%s vs %s" % [fl["pos"] if fl != null else "-", want_fl])
		_ok("② 对手站在右半场", fl != null and float((fl["pos"] as Vector2).x) > cx)
		_ok("② ★对照: 摆过的站位不等于固定队形(证明真读了 off)", not (mine[0]["pos"] as Vector2).is_equal_approx(base_l + Vector2(0.0, -154.0)))

	_gs.current_lane = "bottom"
	_s._units.clear()
	_s._dl_sys._dl_build_lane_field()
	## 生成后立刻量(不等帧): 上一路留下的开打状态会让单位在下一帧走动
	var mine_b := _side_units("left")
	_ok("③ ★分母: 下路我方 3 个", mine_b.size() == 3, str(mine_b.size()))
	if mine_b.size() == 3:
		var same := true
		for i in range(3):
			var d: Vector2 = base_l + Vector2(0.0, (float(i) - 1.0) * 154.0)
			if not (mine_b[i]["pos"] as Vector2).is_equal_approx(d):
				same = false
		_ok("③ ★下路没摆过 ⇒ 三个都在固定队形(与改前逐位相同)", same,
			str(mine_b.map(func(u): return "%s@%s" % [u.get("id"), u.get("pos")])))

	_gs.dual_ghost = {}
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


func _side_units(side: String) -> Array:
	var out: Array = []
	for u in _s._units:
		if u is Dictionary and str(u.get("side", "")) == side and not u.get("_isEgg", false) and str(u.get("id", "")) != "__trainer__" and not u.get("_summoned", false):
			out.append(u)
	return out


func _find(arr: Array, id: String):
	for u in arr:
		if str(u.get("id", "")) == id:
			return u
	return null
