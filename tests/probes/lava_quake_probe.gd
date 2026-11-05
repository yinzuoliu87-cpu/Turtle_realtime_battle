extends Node
## 探针(2026-11-05 用户「熔岩龟特效几乎看不见，你怎么看不见？」): 审阅台放「地裂」, 打印岩浆池的
## 逻辑中心 / 3D 位置 / 投到屏幕的像素 / 可见性 / 透明度 / 尺寸, 以及敌人的屏幕位置, 看池子到底画在哪。
## 用法: REVIEW=1 REVIEW_TURTLE=lava REVIEW_SKILL=1 godot --path . res://tests/probes/lava_quake_probe.tscn
var sc: Node = null
var f := 0
var seen := 0
func _ready() -> void:
	sc = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(sc)
func _process(_d: float) -> void:
	f += 1
	if sc == null or not ("_lava_sys" in sc):
		return
	var zs: Array = sc._lava_sys._lava_zones
	if zs.is_empty():
		if f > 1500:
			print("[LAVA] 1500 帧内没生成岩浆池"); get_tree().quit()
		return
	seen += 1
	if seen in [1, 3, 8, 15, 30, 60]:
		var z: Dictionary = zs[0]
		var d: Sprite3D = z["disc"]
		var cam: Camera3D = sc._cam
		var sp: Vector2 = cam.unproject_position(d.global_position)
		print("[LAVA] +%d 帧 center=%s r=%.0f disc.gpos=%s 屏幕=%s visible=%s a=%.2f pixel_size=%.4f tex=%s 在相机后=%s" % [
			seen, str(z["center"]), float(z["radius"]), str(d.global_position), str(sp), str(d.is_visible_in_tree()),
			d.modulate.a, d.pixel_size, str(d.texture.get_size() if d.texture else null), str(cam.is_position_behind(d.global_position))])
		for u in sc._units:
			if u.get("alive", false):
				var n = u.get("node", null)
				var up: Vector2 = cam.unproject_position(sc._world_pos(u["pos"], 0.0))
				print("    单位 %s/%s pos=%s 屏幕=%s" % [str(u.get("id")), str(u.get("side")), str(u["pos"]), str(up)])
	if seen in [3, 15, 45] and DisplayServer.get_name() != "headless":
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://.out/review/probe/lava_shot_%d.png" % seen))
	if seen > 60:
		get_tree().quit()
