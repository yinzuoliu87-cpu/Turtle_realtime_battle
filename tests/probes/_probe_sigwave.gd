extends Node
## _probe_sigwave.gd — 探针: `battle_vfx.gd:909 _sw_prev_stt` 到底收到什么 / 它有没有用
##
## 问题(write_orphan_audit 容器网 2026-09-28 报): `_sw_prev_stt` 读 1 处 · 全仓零写入
##   ⇒ 传进 `_sigwave._fire(..., _sw_prev_stt)` 的永远是空字典?
## 本探针打真值, 不推理。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	gs.season_level = 5
	var s = RB.new()
	add_child(s)
	for _i in range(8):
		await get_tree().process_frame

	var vfx = s._vfx
	var sw = s._equip_sys._sigwave
	print("=== 探针A: 走真入口 _vfx_preview_sigwave, 每次打状态容器真值 ===")
	print("  调用前 _sw_prev_src = %s" % str(vfx._sw_prev_src))
	var degs: Array = []
	for k in range(6):
		var n0: int = sw._waves.size()
		vfx._vfx_preview_sigwave(s._arena_center, Vector2.RIGHT, 2)
		var d := -1.0
		if sw._waves.size() > n0:
			d = float(sw._waves[sw._waves.size() - 1].get("deg", -1.0))
		degs.append(d)
		var st_now = {} if vfx._sw_prev_src == null else (vfx._sw_prev_src as Dictionary)["eq_state"].get("p2eq_038", {})
		print("  第%d次: 单位 eq_state[p2eq_038] = %s   新波 deg = %.1f  (_waves=%d)"
			% [k + 1, str(st_now), d, sw._waves.size()])
	print("  ⇒ 六次的张角序列 = %s" % str(degs))

	print("")
	print("=== 探针B: 对照 —— 每次传一个全新 {} (= 「参数恒空」那种世界) ===")
	var src2: Dictionary = s._spawn._make_unit("basic", "left", Vector2(-9000, -9000), {})
	src2["equips"] = []; src2["eq_state"] = {}
	var foe2: Dictionary = s._spawn._make_unit("basic", "right", Vector2(-8600, -9000), {})
	foe2["maxHp"] = 99999.0; foe2["hp"] = 99999.0
	s._units.append(src2); s._units.append(foe2)
	var degs_b: Array = []
	for k in range(6):
		var n0b: int = sw._waves.size()
		sw._fire(src2, foe2, 2, {})
		var db := -1.0
		if sw._waves.size() > n0b:
			db = float(sw._waves[sw._waves.size() - 1].get("deg", -1.0))
		degs_b.append(db)
	print("  ⇒ 六次的张角序列 = %s" % str(degs_b))

	print("")
	print("=== 探针C: 真战斗路径用的 stt 是什么(equip_system.gd:1568 那条) ===")
	var src3: Dictionary = s._spawn._make_unit("basic", "left", Vector2(-9400, -9000), {})
	src3["equips"] = [{"id": "p2eq_038", "star": 3}]; src3["eq_state"] = {}
	var foe3: Dictionary = s._spawn._make_unit("basic", "right", Vector2(-9000, -9000), {})
	foe3["maxHp"] = 99999.0; foe3["hp"] = 99999.0
	s._units.append(src3); s._units.append(foe3)
	var stt3: Dictionary = {}
	src3["eq_state"]["p2eq_038"] = stt3
	for k in range(22):
		sw.on_hit(src3, foe3, 2, stt3)
	print("  打 22 下普攻后 stt3 = %s" % str(stt3))
	print("  src3._sig_fired_n = %d" % int(src3.get("_sig_fired_n", 0)))

	print("")
	print("=== 探针D: 演出层 —— 张角改不改画面? 量 ImmediateMesh 的真几何 ===")
	sw._waves.clear()
	var prev_v := -1
	for deg in [90.0, 180.0, 270.0, 360.0]:
		var w: Dictionary = {"src": src2, "from": s._arena_center, "dir": Vector2.RIGHT,
			"half": deg_to_rad(deg * 0.5), "deg": deg, "dmg": 500.0, "t": 0.0,
			"hit": [], "nodes": []}
		sw._place_nodes(w, 300.0)
		var im = w.get("mesh", null)
		if not is_instance_valid(im):
			print("  deg=%.0f° → 没建出 mesh (battle._world=%s)" % [deg, str(s._world)])
			continue
		var imesh: ImmediateMesh = (im as MeshInstance3D).mesh
		var tot := 0
		var per: Array = []
		for si2 in range(imesh.get_surface_count()):
			var arr: Array = imesh.surface_get_arrays(si2)
			var n: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			per.append(n)
			tot += n
		## 角向覆盖: 取所有顶点相对波心的角度, 量张开了多少度
		var mn := 9e9
		var mx := -9e9
		var c3: Vector3 = s._world_pos(s._arena_center, 0.0)
		for si3 in range(imesh.get_surface_count()):
			for v in (imesh.surface_get_arrays(si3)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var a := atan2(v.z - c3.z, v.x - c3.x)
				mn = minf(mn, a); mx = maxf(mx, a)
		print("  deg=%.0f° → surface %d 个 · 顶点 %s (共 %d) · 角向跨度 %.1f°"
			% [deg, imesh.get_surface_count(), str(per), tot, rad_to_deg(mx - mn)])
		prev_v = tot
		sw._free_nodes(w)
	print("PROBE DONE")
	get_tree().quit(0)
