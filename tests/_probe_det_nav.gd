extends Node
## _probe_det_nav —— DetNav(确定性寻路)与引擎 NavigationServer2D.map_get_path 的几何偏差(探针, 不进门禁)。
## 跑法: <godot> --headless --path . res://tests/_probe_det_nav.tscn --quit-after 20000
## 输出: 随机 N 对起止点, 两边路径长度相对差 / 路点数 / 首个转向点的距离差 的分布, 以及每次查询耗时。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.reset_dual_lane()
	gs.tutorial_active = false
	gs.week_phase = "gauntlet"
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	gs.dual_lineup = {"top": [{"kind": "leader", "slot": 0, "id": "basic"}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []}, {"kind": "leader", "slot": 2, "id": "bamboo", "equips": []}]}
	var r0 := RandomNumberGenerator.new()
	r0.seed = 5
	gs.dual_ghost = Backend.make_bot(3, r0)
	gs.dual_active = true
	var s = RB.new()
	add_child(s)
	for _i in range(30):
		await get_tree().process_frame
	if s._obstacles.is_empty():
		s._world_builder._build_map_props()
	if not s._nav_ready:
		## 建场时寻路图还没建: 强制建一次
		s._world_builder._build_navmesh()
	print("[NAV] nav_ready=%s 障碍 %d 个 · DetNav 顶点 %d" % [str(s._nav_ready), s._obstacles.size(),
		s._world_builder.det_nav._nodes.size() if s._world_builder.det_nav != null else -1])
	var dn: DetNav = s._world_builder.det_nav
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var lo: Vector2 = s.ARENA.position + Vector2(30, 30)
	var hi: Vector2 = s.ARENA.end - Vector2(30, 30)
	var N := 2000
	var blocked := 0
	var len_diff_max := 0.0
	var len_diff_sum := 0.0
	var turn_diff_max := 0.0
	var big := 0
	var longer := 0
	var us_det := 0
	var us_eng := 0
	for k in range(N):
		var a := Vector2(DetMath.rrange(rng, lo.x, hi.x), DetMath.rrange(rng, lo.y, hi.y))
		var b := Vector2(DetMath.rrange(rng, lo.x, hi.x), DetMath.rrange(rng, lo.y, hi.y))
		var t0 := Time.get_ticks_usec()
		var pe: PackedVector2Array = NavigationServer2D.map_get_path(s._nav_map, a, b, true)
		us_eng += Time.get_ticks_usec() - t0
		t0 = Time.get_ticks_usec()
		var pd: PackedVector2Array = dn.path(a, b)
		us_det += Time.get_ticks_usec() - t0
		if pd.size() > 2:
			blocked += 1
		var le := _plen(pe)
		var ld := _plen(pd)
		var rel: float = absf(le - ld) / maxf(1.0, le)
		len_diff_max = maxf(len_diff_max, rel)
		len_diff_sum += rel
		if ld > le * 1.01 + 1.0:
			longer += 1
			if longer <= 6:
				print("[NAV] Det 比引擎长 #%d a=%s b=%s 引擎 %s(长 %.1f) / Det %s(长 %.1f)" % [k, str(a), str(b), str(pe), le, str(pd), ld])
		if rel > 0.02:
			big += 1
			if big <= 0:
				print("[NAV] 大偏差 #%d a=%s b=%s 引擎 %s(长 %.1f) / Det %s(长 %.1f)" % [k, str(a), str(b), str(pe), le, str(pd), ld])
		if pe.size() >= 2 and pd.size() >= 2:
			turn_diff_max = maxf(turn_diff_max, pe[1].distance_to(pd[1]) if pe.size() > 2 and pd.size() > 2 else 0.0)
	print("[NAV] %d 对 · 需要绕障 %d 对 · 路径长度相对差 平均 %.4f%% 最大 %.3f%% · >2%% 的 %d 对 · 首个拐点最大距离差 %.2f px" % [
		N, blocked, len_diff_sum / N * 100.0, len_diff_max * 100.0, big, turn_diff_max])
	print("[NAV] Det 比引擎长(>1%%) 的 %d 对" % longer)
	print("[NAV] 每次查询: 引擎 %.1f us · DetNav %.1f us" % [float(us_eng) / N, float(us_det) / N])
	s.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)


func _plen(p: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(p.size() - 1):
		l += p[i].distance_to(p[i + 1])
	return l
