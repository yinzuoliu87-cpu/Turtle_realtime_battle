extends Node
## 探针: 地砖网格密度对帧率/绘制量的影响。窗口模式跑真对局, 采样 FPS 与渲染统计。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node("/root/GameState")
	gs.test_mode = true; gs.season_level = 5
	gs.dual_active = true; gs.current_lane = "top"
	var s = RB.new(); add_child(s)
	for _i in range(60): await get_tree().process_frame
	s._dl_sys._dl_clear_units(); s._dl_sys._dl_build_lane_field()
	await get_tree().process_frame
	s._dl_sys._dl_start_fight()
	for _i in range(90): await get_tree().process_frame      # 预热
	var fps: Array[float] = []
	for _i in range(360):
		await get_tree().process_frame
		fps.append(Engine.get_frames_per_second())
	fps.sort()
	var sum := 0.0
	for f in fps: sum += f
	var inst := 0
	var nodes := 0
	for n in s._tile_nodes:
		if is_instance_valid(n) and n is MultiMeshInstance3D:
			nodes += 1
			inst += (n as MultiMeshInstance3D).multimesh.instance_count
	print("FPSPROBE tile节点=%d  MultiMesh实例=%d  三角=%d" % [nodes, inst, inst * 12])
	print("FPSPROBE fps 均值=%.1f  中位=%.1f  1%%最低=%.1f  最低=%.1f (采样 %d 帧)" % [
		sum / fps.size(), fps[fps.size() / 2], fps[maxi(0, fps.size() / 100)], fps[0], fps.size()])
	print("FPSPROBE 绘制调用=%d  渲染图元=%d" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	get_tree().quit()
