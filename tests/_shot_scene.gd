extends Node
## DEV 工具: 给【非战斗场景】截图(战斗场有自己的 SELFSHOT, 其它页一直没有)。
##
##   SHOT_SCENE=res://scenes/TeamSelect.tscn SHOT_OUT=res://_shot_ts.png \
##     SHOT_WAIT=90 <godot> --path . res://tests/_shot_scene.tscn --position 5000,5000
##
## ★不能加 --headless —— 无头没有真实渲染, 截出来是空图**而且不报错**(同 VFXLAB 那条)。
## ★窗口挪到屏幕外不影响截图: 抓的是视口纹理, 不是屏幕。


func _ready() -> void:
	var path := OS.get_environment("SHOT_SCENE")
	if path == "":
		push_error("SHOT_SCENE 没给")
		get_tree().quit(1)
		return
	var out := OS.get_environment("SHOT_OUT")
	if out == "":
		out = "res://_shot.png"
	var wait := int(OS.get_environment("SHOT_WAIT")) if OS.has_environment("SHOT_WAIT") else 90
	## 可选: 先跑一段种子脚本(SHOT_SETUP=res://tests/_setup_syn_demo.gd), 让页面有数据可看。
	if OS.has_environment("SHOT_SETUP"):
		var setup_path := OS.get_environment("SHOT_SETUP")
		var scr: GDScript = load(setup_path)
		if scr != null:
			scr.run()
			print("[SHOT] setup: " + setup_path)
	var ps: PackedScene = load(path)
	if ps == null:
		push_error("场景加载不了: " + path)
		get_tree().quit(1)
		return
	add_child(ps.instantiate())
	for _i in range(maxi(1, wait)):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(out)
	print("[SHOT] %s → %s (%dx%d)" % [path, out, img.get_width(), img.get_height()])
	get_tree().quit(0)
