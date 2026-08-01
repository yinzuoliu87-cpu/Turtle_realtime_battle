extends Node
## 界面多比例抓图器 —— UI 双端适配用(用户 2026-08-01:「有些画面都没有居中」)。
##
## 把指定界面在【一个视口尺寸】下抓一张图。外层脚本换 --resolution 反复调，
## 拼成"同一界面 × 多比例"的对照条 → 哪一屏在哪个比例下没居中, 是看出来的不是猜的。
##
## ★为什么不用一个进程里改视口: Godot 的 stretch 是启动时按窗口算的,
##   运行中改 window size 不等于换一个"启动在该分辨率上"的环境, 会测不准。
##   一个尺寸起一个进程最笨也最可信。
##
## 跑法: SHOT_SCENE=MainMenu SHOT_OUT=C:/tmp/x.png <godot> --path . \
##         res://tests/_shot_screens.tscn --resolution 960x720 --position 2200,300

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var scn := OS.get_environment("SHOT_SCENE")
	if scn == "":
		scn = "MainMenu"
	var out := OS.get_environment("SHOT_OUT")
	if out == "":
		out = "C:/tmp/screen.png"
	var path := "res://scenes/%s.tscn" % scn
	if not ResourceLoader.exists(path):
		print("[SHOT] 场景不存在: %s" % path)
		get_tree().quit(1); return
	var ps: PackedScene = load(path)
	var inst = ps.instantiate()
	add_child(inst)
	# 等界面自己布完(有的界面有入场 tween / 异步载数据)
	# ★等够入场动画: 左栏键从 x=-560 滑入, 延迟 0.5+0.08i 秒 + 0.42 秒行程(MainMenuScene._slide_in_left)。
	#   90 帧(=1.5s@60fps)会抓到滑到一半 —— 我第一版就是, 差点把"按钮被切在屏外"报成 bug。
	var _t0 := Time.get_ticks_msec()
	for _i in range(360):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(out)
	var vp: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	print("[SHOT] %s  视口 %dx%d  等待 %.1fs → %s" % [scn, int(vp.x), int(vp.y), float(Time.get_ticks_msec() - _t0) / 1000.0, out])
	get_tree().quit(0)
