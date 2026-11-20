extends Node
## _probe_bar_center —— 血条中心 vs 人物中心(屏幕横坐标)逐个单位量(2026-11-20 用户「这个血条中心和人物中心不一样吗」)。
## 探针, 不进门禁, 要非无头跑(要真实相机与画面):
##   SHIP=1 BAR_PROBE_OUT=res://.out/hpbar/center.png godot --path . res://tests/probes/_probe_bar_center.tscn
## 每个单位打一行: 血条中心 / 牌 + 血条整体中心 / 立绘当前帧不透明像素中心 / 脚底 —— 都是屏幕 x(像素), 正数 = 在人物中心右边。
## 截图上画: 黄线 = 血条中心, 品红线 = 牌 + 血条整体中心, 青线 = 立绘中心。

var sc: Node = null
var f := 0


func _ready() -> void:
	sc = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(sc)


func _process(_d: float) -> void:
	f += 1
	if f != int(OS.get_environment("BAR_PROBE_FRAME") if OS.has_environment("BAR_PROBE_FRAME") else "300"):
		return
	var cam: Camera3D = sc._cam
	var img: Image = get_viewport().get_texture().get_image()
	var marks: Array = []
	for u in sc._units:
		if not u.get("alive", false):
			continue
		var root = u.get("bar_root", null)
		var spr = u.get("sprite", null)
		if not is_instance_valid(root) or not (root as Control).visible or not is_instance_valid(spr) or not (spr is Sprite3D):
			continue
		var r: Rect2 = (root as Control).get_global_rect()
		var xf: Transform2D = (root as Control).get_global_transform_with_canvas()
		var bar_l: Vector2 = xf * Vector2(0, 0)
		var bar_r: Vector2 = xf * Vector2(sc.BAR_W, 0)
		var bar_c: float = (bar_l.x + bar_r.x) * 0.5
		var comp_l: float = bar_l.x
		var lb = u.get("level_badge", null)
		if is_instance_valid(lb):
			comp_l = minf(comp_l, ((lb as Control).get_global_transform_with_canvas() * Vector2(0, 0)).x)
		var comp_c: float = (comp_l + bar_r.x) * 0.5
		## 立绘当前帧不透明像素的横向中心
		var st: Sprite3D = spr
		var tex: Texture2D = st.texture
		if tex == null:
			continue
		var timg: Image = tex.get_image()
		if timg == null:
			continue
		if timg.is_compressed():
			timg.decompress()
		var fw: int = timg.get_width() / maxi(1, st.hframes)
		var fh: int = timg.get_height() / maxi(1, st.vframes)
		var fx0: int = (st.frame % maxi(1, st.hframes)) * fw
		var fy0: int = (st.frame / maxi(1, st.hframes)) * fh
		var sx := 0.0
		var n := 0
		for yy in range(fh):
			for xx in range(fw):
				if timg.get_pixel(fx0 + xx, fy0 + yy).a > 0.3:
					sx += float(xx)
					n += 1
		if n == 0:
			continue
		var cx_px: float = sx / float(n) + 0.5
		var off_px: float = (cx_px - float(fw) * 0.5 + st.offset.x) * (-1.0 if st.flip_h else 1.0)
		var b: Basis = cam.global_transform.basis
		var w_c: Vector3 = st.global_position + b.x.normalized() * off_px * st.pixel_size * st.scale.x
		var spr_c: float = cam.unproject_position(w_c).x
		var feet_x: float = cam.unproject_position(sc._world_pos(u["pos"], 0.0)).x
		print("[BARC] %-10s 朝%s 血条%+6.1f 牌+血条%+6.1f 脚底%+6.1f (相对立绘中心, 像素) 立绘中心 x=%.0f" % [
			str(u.get("id", "?")), "右" if st.flip_h else "左", bar_c - spr_c, comp_c - spr_c, feet_x - spr_c, spr_c])
		marks.append([bar_c, comp_c, spr_c, r.position.y])
	for m in marks:
		for k in range(3):
			var col: Color = [Color(1, 0.9, 0.1), Color(1, 0.2, 1), Color(0.2, 1, 1)][k]
			var x: int = int(round(float(m[k])))
			for yy in range(int(m[3]) - 6, int(m[3]) + 70):
				if x >= 0 and x < img.get_width() and yy >= 0 and yy < img.get_height():
					img.set_pixel(x, yy, col)
	var out := OS.get_environment("BAR_PROBE_OUT")
	if out != "":
		img.save_png(ProjectSettings.globalize_path(out))
		print("[BARC] saved ", out)
	get_tree().quit()
