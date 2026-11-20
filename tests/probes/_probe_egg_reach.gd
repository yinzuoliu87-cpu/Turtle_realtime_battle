extends Node
## 探针(11-20 用户「摄像头…左右上下移的位置还是太有限了…想看龟蛋血条，最左边都看不到」):
## 各缩放下把镜头推到最左, 龟蛋 / 蛋血条 / 训龟大师落在屏幕哪个 x(像素) —— 对照左侧队伍卡片的右沿。
## 站位照 dual_lane_flow(蛋 = ARENA.x + 70, 中线) 与 battle_spawn._spawn_trainers(大师 = ARENA.x + 40, 中线上 150)。
## 跑法: <godot> --audio-driver Dummy --path . --resolution 1560x720 --position 5000,5000 res://tests/probes/_probe_egg_reach.tscn
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")


func _wait(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	await get_tree().process_frame
	get_node("/root/GameState").test_mode = true
	var b = RB.new()
	add_child(b)
	await _wait(30)
	var vs: Vector2 = b.get_viewport().get_visible_rect().size
	var cy: float = b.ARENA.position.y + b.ARENA.size.y * 0.5
	var egg2d := Vector2(b.ARENA.position.x + 70.0, cy)
	var tr2d := Vector2(b.ARENA.position.x + 40.0, cy - 150.0)
	print("VIEW %dx%d  ARENA %s  PAN_LIMIT %.1f" % [int(vs.x), int(vs.y), str(b.ARENA), float(b.PAN_LIMIT)])
	for z in [1.0, 1.5, 2.0, float(b.CAM_ZOOM_MAX)]:
		b._cam_zoom = z
		b._cam_pan = Vector3(-99.0, 0.0, 0.0)
		b._apply_cam_zoom()
		await _wait(3)
		var cam: Camera3D = b._cam
		var e: Vector2 = cam.unproject_position(b._world_pos(egg2d, 0.6))
		var bar: Vector2 = cam.unproject_position(BattleRender.bar_anchor(b, {"pos": egg2d, "height": 0.0}))
		var t: Vector2 = cam.unproject_position(b._world_pos(tr2d, 1.0))
		print("REACH zoom=%.2f pan_x=%.2f  蛋 x=%d(%.0f%%)  蛋血条 x=%d y=%d  大师 x=%d y=%d" % [
			z, float(b._cam_pan.x), int(e.x), 100.0 * e.x / vs.x, int(bar.x), int(bar.y), int(t.x), int(t.y)])
	print("PROBE DONE")
	get_tree().quit()
