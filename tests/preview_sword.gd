extends Node
## 一次性预览: 建出 3D 紫剑, 渲进独立 SubViewport 再存图。
## ★不能直接抓根视口 —— 项目有 autoload 往上盖 UI(第一版抓到的是主菜单背景)。
func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1000, 620)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.05, 0.07)
	env.environment = e
	vp.add_child(env)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.05, 3.4)
	cam.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
	vp.add_child(cam)
	## 五个角度: 侧对 → 逐步转向镜头 —— 正是横斩扫过时会经历的
	for i in range(5):
		var s := Sword3D.build(1.0)
		s.position = Vector3(-1.5 + 0.75 * float(i), 0.0, 0.0)
		s.rotation.y = deg_to_rad(float(i) * 22.5)
		vp.add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("C:/tmp/sword3d_preview.png")
	print("[PREVIEW] saved  len=%.2f m" % Sword3D.total_len())
	get_tree().quit()
