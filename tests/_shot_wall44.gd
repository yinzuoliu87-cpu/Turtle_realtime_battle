extends Node
## 实拍【登录墙】—— 两种视口 × 键盘收起/弹出 × 两步, 一个进程里全拍完。
##
## ★为什么一个进程里拍完: 改前/改后要对照, 而"改前"得把产品文件临时换回旧版
##   ⇒ 那个窗口越短越好(同一个工作区里还有别的 agent 在跑门禁)。
## ★为什么不用 `_shot_scene.gd`: 它是 `load(路径).instantiate()`, 拿不到实例去设
##   `acct_override` —— 而墙的条件(后端开着 + 邮箱为空)在这种环境下只能靠注入。
## ★键盘那一档用产品自己的注入缝 `SET.vkb_override_vp`(视口单位), 不假装按键盘。
##
## 跑法(**不要 --headless**, 无头没有渲染; 窗口静音 + 放屏幕左下角 + 拍完自退):
##   SHOT_TAG=after SHOT_DIR=C:/tmp/wall44/shots \
##   <godot> --audio-driver Dummy --path . res://tests/_shot_wall44.tscn \
##     --resolution 1280x720 --position 0,340
const SET := preload("res://scripts/scenes/SettingsScene.gd")

## 视口 × 键盘档 —— 与 `verify_login_wall` / `_probe_wall_vprofile` 同一口径。
const VPS := [Vector2i(1280, 720), Vector2i(1560, 720)]
const KB_FRAC := 0.415        ## iPhone 14/15 横屏 ASCII 键盘 162pt / 屏高 390pt

var _st = null


func _w(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _shoot(name: String) -> void:
	## ★420 帧才干净 —— 140 帧不够(本仓实拍成规: 要等落位)。
	await _w(420)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = "C:/tmp/wall44/shots"
	var tag := OS.get_environment("SHOT_TAG")
	if tag == "":
		tag = "x"
	var p := "%s/%s_%s.png" % [dir, tag, name]
	img.save_png(p)
	print("[SHOT] %s  (%dx%d)" % [p, img.get_width(), img.get_height()])


func _ready() -> void:
	await _w(2)
	OS.set_environment("TURTLE_SUPABASE", "http://127.0.0.1:9")
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		## ★★`test_mode` 必须开: 带窗口跑的时候 GameState 会写**真存档**
		##   (memory `fb-debug-stage-writes-real-save`)。
		gs.test_mode = true
		gs.account_email = ""
		gs.account_id = "uid-shot"
	var sb = load("res://scripts/net/supabase.gd")
	if sb != null and sb.has_method("_reset_auth_for_test"):
		sb._reset_auth_for_test()
	await _w(2)
	for vp in VPS:
		get_tree().root.size = vp
		await _w(6)
		_st = (load("res://scenes/Settings.tscn") as PackedScene).instantiate()
		_st.acct_override = 1     ## ★必须在 add_child 之前 —— `_ready` 那一刻就决定建不建墙
		add_child(_st)
		await _w(12)
		var built: bool = _st._email_layer != null and is_instance_valid(_st._email_layer)
		print("[分母] %dx%d 墙在场 = %s" % [vp.x, vp.y, str(built)])
		SET.vkb_override_vp = -1.0
		await _shoot("%dx%d_kb0" % [vp.x, vp.y])
		SET.vkb_override_vp = float(vp.y) * KB_FRAC
		await _shoot("%dx%d_kb42" % [vp.x, vp.y])
		SET.vkb_override_vp = -1.0
		## 第二步只有候选 A 有(旧版没有 `_email_set_step`) ⇒ 有就拍, 没有就跳过。
		if _st.has_method("_email_set_step"):
			_st._email_set_step(2)
			await _w(6)
			await _shoot("%dx%d_step2_kb0" % [vp.x, vp.y])
			SET.vkb_override_vp = float(vp.y) * KB_FRAC
			await _shoot("%dx%d_step2_kb42" % [vp.x, vp.y])
			SET.vkb_override_vp = -1.0
		_st.queue_free()
		_st = null
		await _w(6)
	print("SHOT DONE")
	get_tree().quit(0)
