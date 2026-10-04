extends Node
## _probe_fg_corner.gd — 量【底部前景剪影带】把站在场地底部两角的龟盖住多少(探针, 不进门禁)。
##
## 由来(2026-10-04): 前景带两角的大海带伸进场地底部两角, 怀疑会挡住站在角上的龟。
##   先量再改 —— 判据 = 龟立绘在前景层后面被盖住的像素比例。
##
## 做法: 起真战斗(SHIP=1 主题由 ARENA_THEME 给), 跑一会儿后把一只左方龟 / 一只右方龟
##   摆到可活动椭圆边界上(底部左/右一段弧, 逐个角度), 冻结战斗, 每个角度拍三张:
##     A = 原样 · B = 藏掉前景带 · C = 藏掉前景带 + 藏掉这两只龟的立绘
##   龟像素 = B≠C 的像素(只在龟投影点附近的框里数); 被盖像素 = 龟像素里 A≠B 的那些。
##   ⇒ 盖住比例 = 被盖 / 龟像素。打印每个角度两只龟的比例与分母。
##
## 跑法: ARENA_THEME=V2_REEF SHIP=1 <godot> --audio-driver Dummy --path . --resolution 1280x720 \
##       --position 2000,80 res://tests/_probe_fg_corner.tscn
##   FG_SHOT_DIR=<目录> 时把每个角度的 A 图存下来(人眼复核)。

func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	## ★本节点是 current_scene, 换场景会把它连同协程一起释放 ⇒ 先在 root 下挂一个同脚本的常驻替身来跑。
	if name != "FgProbeRunner":
		var n := Node.new()
		n.name = "FgProbeRunner"
		n.set_script(get_script())
		get_tree().root.add_child.call_deferred(n)
		get_tree().change_scene_to_file("res://scenes/RealtimeBattle3D.tscn")
		return
	for _i in range(240):
		await get_tree().process_frame
	var b = get_tree().current_scene
	var A: Rect2 = b.ARENA
	var lu = null
	var ru = null
	for u in b._units:
		if not u.get("alive", false) or not u.has("sprite") or not is_instance_valid(u["sprite"]):
			continue
		if u.get("is_summon", false):
			continue
		if lu == null and str(u.get("side", "")) == "left":
			lu = u
		elif ru == null and str(u.get("side", "")) == "right":
			ru = u
	if lu == null or ru == null:
		print("FG_CORNER 找不到两边的龟: left=%s right=%s" % [lu != null, ru != null])
		get_tree().quit(1)
		return
	var band: Array = []
	for ch in b._cam.get_children():
		if ch is Sprite3D and is_equal_approx(ch.sorting_offset, 8.0):
			band.append(ch)
	print("FG_CORNER 前景带节点数=%d  左龟=%s 右龟=%s" % [band.size(), lu.get("id", "?"), ru.get("id", "?")])
	var c: Vector2 = A.position + A.size * 0.5
	var rx: float = A.size.x * 0.5
	var ry: float = A.size.y * 0.5
	var out_dir: String = OS.get_environment("FG_SHOT_DIR")
	var worst := [0.0, 0.0]
	## 角度从正下(90°)往两侧走到水平(0°/180°); 左龟走左下弧, 右龟走右下弧(镜像)。
	for deg in [90, 105, 115, 120, 125, 130, 135, 140, 145, 150, 155, 160, 170, 180]:
		var th: float = deg_to_rad(float(deg))
		var pl: Vector2 = ArenaShape.clamp_in(c + Vector2(cos(th) * rx, sin(th) * ry) * 1.02, A)
		var pr: Vector2 = Vector2(2.0 * c.x - pl.x, pl.y)
		b.process_mode = Node.PROCESS_MODE_INHERIT
		for _k in range(6):
			lu["pos"] = pl
			ru["pos"] = pr
			await get_tree().process_frame
		b.process_mode = Node.PROCESS_MODE_DISABLED
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var ia: Image = get_viewport().get_texture().get_image()
		for s in band: s.visible = false
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var ib: Image = get_viewport().get_texture().get_image()
		lu["sprite"].visible = false
		ru["sprite"].visible = false
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var ic: Image = get_viewport().get_texture().get_image()
		lu["sprite"].visible = true
		ru["sprite"].visible = true
		for s in band: s.visible = true
		var res := []
		var vs: Vector2 = get_viewport().get_visible_rect().size
		for u in [lu, ru]:
			var sp: Vector2 = b._cam.unproject_position(u["sprite"].global_position)
			## 视口 → 截图像素(截图就是视口纹理, 同尺寸)
			var sx: float = float(ia.get_width()) / vs.x
			var sy: float = float(ia.get_height()) / vs.y
			var cx: int = int(sp.x * sx)
			var cy: int = int(sp.y * sy)
			var tot := 0
			var hid := 0
			for y in range(maxi(0, cy - 110), mini(ia.get_height(), cy + 90)):
				for x in range(maxi(0, cx - 90), mini(ia.get_width(), cx + 90)):
					var pb: Color = ib.get_pixel(x, y)
					if _diff(pb, ic.get_pixel(x, y)):
						tot += 1
						if _diff(ia.get_pixel(x, y), pb):
							hid += 1
			res.append([hid, tot, cx, cy])
		for i in range(2):
			var r: float = float(res[i][0]) / maxf(1.0, float(res[i][1]))
			worst[i] = maxf(worst[i], r)
		print("FG_CORNER deg=%3d  左龟 屏幕(%d,%d) 盖住 %d/%d = %.1f%%   右龟 屏幕(%d,%d) 盖住 %d/%d = %.1f%%" % [
			deg, res[0][2], res[0][3], res[0][0], res[0][1], 100.0 * res[0][0] / maxf(1.0, res[0][1]),
			res[1][2], res[1][3], res[1][0], res[1][1], 100.0 * res[1][0] / maxf(1.0, res[1][1])])
		if out_dir != "":
			ia.save_png("%s/corner_%03d.png" % [out_dir, deg])
			ib.save_png("%s/corner_%03d_noband.png" % [out_dir, deg])
			ic.save_png("%s/corner_%03d_noturtle.png" % [out_dir, deg])
	print("FG_CORNER_DONE 最坏: 左 %.1f%%  右 %.1f%%" % [worst[0] * 100.0, worst[1] * 100.0])
	get_tree().quit(0)


func _diff(a: Color, c: Color) -> bool:
	return absf(a.r - c.r) + absf(a.g - c.g) + absf(a.b - c.b) > 0.06
