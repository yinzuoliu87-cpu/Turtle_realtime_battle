extends Node
## DEV 工具(不是门禁): 过肩摔体检(2026-10-24) —— 审阅台真场景, 按 sim 步号逐阶段拍。
## 跑法(窗口只开右屏·静音):
##   SHOT_DIR=<目录> SHOT_TAG=<前缀> REVIEW=1 REVIEW_TURTLE=basic REVIEW_SKILL=3 APPDATA=<单独目录> \
##   WINDOW=1 bash godot-quiet.sh --position 2000,80 --resolution 1560x720 res://tests/_shot_slam.tscn
## ★不能 --headless: 无头拿不到视口纹理。
## ★找到小龟放过肩摔的那一步起切 `_deterministic`(一帧恰一步 sim) ⇒ 下面的步号就是游戏内 1/60 秒。

## 步号(从检测到 _slam 那一帧起算) → 阶段名
const SHOTS := {2: "1-grab", 9: "2-grab-end", 18: "3-rise", 27: "4-flip-apex", 38: "5-fall", 50: "6-near-land", 60: "7-land-dust", 66: "8-rings", 76: "9-after"}


func _ready() -> void:
	await get_tree().process_frame
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	var scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn)
	var dir := OS.get_environment("SHOT_DIR")
	var tag := OS.get_environment("SHOT_TAG")
	var caster = null
	var w := 0
	while w < 6000:
		await get_tree().process_frame
		w += 1
		for u in scn._units:
			if str(u.get("id", "")) == "basic" and str(u.get("side", "")) == "left" and bool(u.get("_slam", false)):
				caster = u
		if caster != null:
			break
	if caster == null:
		print("[SHOT] 没等到过肩摔")
		get_tree().quit(1)
		return
	scn._deterministic = true
	print("[SHOT] 过肩摔开始于第 %d 帧 _t=%.2f" % [w, scn._t])
	var tgt = null
	for u in scn._units:
		if str(u.get("side", "")) == "right" and bool(u.get("_slam", false)):
			tgt = u
	var n := 0
	while n < 90:
		await get_tree().process_frame
		n += 1
		if SHOTS.has(n):
			await RenderingServer.frame_post_draw
			var p := "%s/%s-%s.png" % [dir, tag, SHOTS[n]]
			get_viewport().get_texture().get_image().save_png(p)
			var tv: Vector3 = tgt.get("_slam_voff", Vector3.ZERO) if tgt != null else Vector3.ZERO
			var cv: Vector3 = caster.get("_slam_voff", Vector3.ZERO)
			var fv := false
			if tgt != null and is_instance_valid(tgt.get("sprite")): fv = (tgt["sprite"] as Sprite3D).flip_v
			var bar_y := -1.0
			if tgt != null and is_instance_valid(tgt.get("bar_root")): bar_y = (tgt["bar_root"] as Control).position.y
			var spr_y := -1.0
			if tgt != null and is_instance_valid(tgt.get("sprite")): spr_y = scn._cam.unproject_position((tgt["sprite"] as Sprite3D).global_position).y
			print("[SHOT] step=%d %s 敌voff=%.2f 龟voff=%.2f flip_v=%s 敌血条屏幕y=%.0f 敌立绘屏幕y=%.0f" % [n, p, tv.y, cv.y, str(fv), bar_y, spr_y])
	get_tree().quit()
