extends Node
## _th_shots —— 变脸龟单技能审阅台自拍(dev 工具, 不是门禁; 文件名不以 verify_ 开头 ⇒ 不进自动发现)。
##
## 真入口: REVIEW=1 单技能审阅台(真对局循环、真技能分派、真渲染步), 只额外做四件事:
##   黑场(BLACKMAP) · 关 UI 层与光标 · 长焦锁住"变脸龟与第一个假人"的中点 · 每帧恰 1 步 sim(_deterministic)
##   ⇒ 第 N 张图 = 第 N×EVERY 步的游戏画面, 与机器快慢无关。
## 用法(必须开窗口渲染; 放右屏、静音):
##   TH_SKILL=1 TH_OUT=C:/x/dir TH_STEPS=600 TH_EVERY=3 TH_ZOOM=2.4 \
##     godot --audio-driver Dummy --path . --resolution 1280x720 --position 2000,80 res://tests/_th_shots.tscn
## 输出: <TH_OUT>/s<步号5位>_t<游戏秒>.png, 外加 log.txt(每张图那一刻的形态 / 当前动作 / 帧号)。

var _s = null


func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.has_environment(k) else d


func _ready() -> void:
	OS.set_environment("REVIEW", "1")
	OS.set_environment("REVIEW_TURTLE", "two_head")
	OS.set_environment("REVIEW_SKILL", _env("TH_SKILL", "0"))
	OS.set_environment("BLACKMAP", "1")
	OS.set_environment("QUIET", "1")
	var out := _env("TH_OUT", "user://th_shots")
	DirAccess.make_dir_recursive_absolute(out)
	var steps := int(_env("TH_STEPS", "600"))
	var every := maxi(1, int(_env("TH_EVERY", "3")))
	var zoom := float(_env("TH_ZOOM", "2.4"))
	_s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_s)
	for _i in range(4):
		await get_tree().process_frame
	_s._deterministic = true
	print("[th] scene up, cam=", _s._cam, " units=", _s._units.size())
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	var ct = get_node_or_null("/root/CursorTheme")
	if ct != null:
		for c in ct.get_children():
			if c is CanvasLayer:
				(c as CanvasLayer).visible = false
	var fov0: float = float(_s._cam.fov)
	var off: Vector3 = _s._cam_base - _s.CAM_TARGET
	var logf := FileAccess.open(out.path_join("log.txt"), FileAccess.WRITE)
	for n in range(steps):
		await get_tree().process_frame
		if _s._ui_layer != null:
			_s._ui_layer.visible = false
		var th = null
		var dm = null
		for u in _s._units:
			if str(u.get("id", "")) == "two_head" and th == null:
				th = u
			elif str(u.get("side", "")) == "right" and dm == null:
				dm = u
		if th != null:
			var f: Vector2 = th["pos"] if dm == null else (th["pos"] + dm["pos"]) * 0.5
			_s._cam_zoom_base = _s._world_pos(f, 1.0) + off
			_s._cam.position = _s._cam_zoom_base
			_s._cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(fov0 * 0.5)) / zoom))
		if n % every != 0:
			continue
		if n < 3: print("[th] shot ", n)
		if not OS.has_environment("TH_NOSHOT"):
			await RenderingServer.frame_post_draw
		var im: Image = get_viewport().get_texture().get_image()
		var t: float = float(_s._t)
		im.save_png(out.path_join("s%05d_t%06.2f.png" % [n, t]))
		if th != null and logf != null:
			var spr = th.get("sprite", null)
			var tx: String = str((spr.texture as Texture2D).resource_path.get_file()) if is_instance_valid(spr) and spr.texture != null else "-"
			logf.store_line("%d t=%.3f form=%s state=%s clip=%s tex=%s frame=%d hp=%.0f" % [n, t,
				str(th.get("two_form", "")), str(th.get("state", "")), str(th.get("_tha_clip", "")), tx,
				int(spr.frame) if is_instance_valid(spr) else -1, float(th.get("hp", 0.0))])
	if logf != null:
		logf.close()
	get_tree().quit()
