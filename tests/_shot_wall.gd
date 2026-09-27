extends Node
## 实拍【登录墙】那一屏。
##
## ★为什么要专门一份: `_shot_scene.gd` 是 `load(路径).instantiate()`, 拿不到实例
##   去设 `acct_override` —— 而墙的条件(后端开着 + 邮箱为空)在门禁环境下只能靠注入。
##   ⇒ 这里自己建实例、自己设注入, **不往产品代码里加实拍用的环境变量**。
const SET := preload("res://scripts/scenes/SettingsScene.gd")


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.account_email = ""
	await get_tree().process_frame
	var st = SET.new()
	st.acct_override = 1
	add_child(st)
	## 等够入场(墙里有 tween/Timer); 用帧数不用墙钟 —— 这里只是抓图不是判数值。
	for _i in range(220):
		await get_tree().process_frame
	## 探针: 把所有带贴图的节点连位置打出来 —— 实拍里有只龟压在标题上, 要先认出它是谁。
	if OS.has_environment("WALL_PROBE"):
		var stk: Array = [get_tree().root]
		while not stk.is_empty():
			var n = stk.pop_back()
			var tex = null
			if n is TextureRect:
				tex = (n as TextureRect).texture
			elif n is Sprite2D:
				tex = (n as Sprite2D).texture
			if tex != null:
				var pos := (n as CanvasItem).get_global_transform().origin
				print("[贴图] %-14s %-28s pos=%s  path=%s" % [n.get_class(), str(n.name).substr(0,28), str(pos), str(tex.resource_path)])
			for ch in n.get_children():
				stk.append(ch)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var out := OS.get_environment("SHOT_OUT")
	if out == "":
		out = "C:/tmp/wall.png"
	img.save_png(out)
	print("[SHOT] 登录墙 → %s (%dx%d)" % [out, img.get_width(), img.get_height()])
	get_tree().quit(0)
