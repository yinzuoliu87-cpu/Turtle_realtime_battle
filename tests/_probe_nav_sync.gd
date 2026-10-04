extends Node
## 探针: NavigationServer2D 新建 map 后, map_force_update 是不是同步生效? 不是的话要几个物理帧?

func _ready() -> void:
	var map := NavigationServer2D.map_create()
	NavigationServer2D.map_set_cell_size(map, 1.0)
	NavigationServer2D.map_set_active(map, true)
	if OS.get_environment("NAV_SYNC") == "1":
		NavigationServer2D.map_set_use_async_iterations(map, false)
	var ml := []
	for m in ClassDB.class_get_method_list("NavigationServer2D"):
		var n := str(m["name"])
		if n.contains("process") or n.contains("sync") or n.contains("force") or n.contains("iteration") or n.contains("async"):
			ml.append(n)
	print("NAVPROBE methods ", ml)
	var reg := NavigationServer2D.region_create()
	if OS.get_environment("NAV_SYNC") == "1":
		NavigationServer2D.region_set_use_async_iterations(reg, false)
	NavigationServer2D.region_set_map(reg, map)
	NavigationServer2D.region_set_enabled(reg, true)
	var poly := NavigationPolygon.new()
	poly.cell_size = 1.0
	var src := NavigationMeshSourceGeometryData2D.new()
	src.add_traversable_outline(PackedVector2Array([Vector2(0, 0), Vector2(1000, 0), Vector2(1000, 600), Vector2(0, 600)]))
	var hole := PackedVector2Array()
	for i in range(14):
		var a := TAU * float(i) / 14.0
		hole.append(Vector2(500, 300) + Vector2(cos(a) * 80.0, sin(a) * 120.0))
	src.add_obstruction_outline(hole)
	NavigationServer2D.bake_from_source_geometry_data(poly, src)
	NavigationServer2D.region_set_navigation_polygon(reg, poly)
	NavigationServer2D.map_force_update(map)
	var a0 := Vector2(100, 300)
	var b0 := Vector2(900, 300)
	print("NAVPROBE after force_update: iter=%d path=%d" % [NavigationServer2D.map_get_iteration_id(map), NavigationServer2D.map_get_path(map, a0, b0, true).size()])
	for f in range(6):
		await get_tree().process_frame
		print("NAVPROBE process_frame %d: iter=%d path=%d phys_frames=%d" % [f, NavigationServer2D.map_get_iteration_id(map), NavigationServer2D.map_get_path(map, a0, b0, true).size(), Engine.get_physics_frames()])
	print("NAVPROBE async_iter setting=", ProjectSettings.get_setting("navigation/world/map_use_async_iterations", "?"))
	NavigationServer2D.free_rid(reg)
	NavigationServer2D.free_rid(map)
	get_tree().quit(0)
