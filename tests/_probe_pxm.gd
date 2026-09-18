extends Node
## _probe_pxm.gd — 「一米在屏幕上是多少像素」的实测探针(不进门禁)
##
## 由来: 2026-09-18 做 P1-5「场地边界体积」时, 参考标定给出的是【屏幕比例】
##   (TFT 的边界墙竖面 ÷ 角色屏幕高 = 0.81), 要换成本项目的【世界米】必须知道两件事:
##     ① 竖直世界米 → 屏幕像素 (吃相机俯角压缩)
##     ② 龟(Sprite3D 公告板)的屏幕高 —— 公告板【朝着相机】, 到底吃不吃那个压缩?
##   这两条我都只会算, 没量过。而算出来的数要拿去驱动新素材生成 ——
##   ★本项目有过教训: 推理出来的不算根因, 新尺子必须先拿已知答案的样本验一遍。
##   所以这里用 `Camera3D.unproject_position` 直接问引擎, 不做三角函数推导。
##
## 跑法(headless 即可, 不需要渲染):
##   SHIP=1 TURTLE_SEED=20260918 TURTLE_BACKEND=" " APPDATA=<隔离目录> \
##   <godot> --headless --audio-driver Dummy --path . res://tests/_probe_pxm.tscn --quit-after 900

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

func _ready() -> void:
	await get_tree().process_frame
	var inst = RB.new()
	add_child(inst)
	# 等建场 + 相机就位
	var w := 0
	while w < 600 and (inst._cam == null or not is_instance_valid(inst._cam)):
		await get_tree().process_frame
		w += 1
	## 等单位真的生成(不是等固定帧数 —— 帧数在无头下极快, 等于没等)
	var w2 := 0
	while w2 < 900 and inst._units.size() < 2:
		await get_tree().process_frame
		w2 += 1
	for i in range(30):
		await get_tree().process_frame
	var cam: Camera3D = inst._cam
	if cam == null:
		print("[FAIL] ★分母: 拿不到相机 —— 探针无效, 不是「结果为 0」")
		get_tree().quit(); return

	var vp: Vector2 = cam.get_viewport().get_visible_rect().size
	print("视口 %.0f×%.0f   fov=%.1f   cam@%s   look_at=%s" % [vp.x, vp.y, cam.fov, str(cam.global_position), str(RB.CAM_TARGET)])

	# ── ① 竖直世界米 → 像素: 在场地中心立一根 1 米的竖线, 问它投影出来多高 ──
	var base := Vector3(0.0, 0.0, 0.0)
	var p0: Vector2 = cam.unproject_position(base)
	var p1: Vector2 = cam.unproject_position(base + Vector3(0.0, 1.0, 0.0))
	var v_px: float = absf(p1.y - p0.y)
	print("① 场地中心 1.0 米【竖直】 → %.2f px  (每米 %.2f px)" % [v_px, v_px])

	# ── ② 水平世界米 → 像素(横向, 不吃俯角) ──
	var p2: Vector2 = cam.unproject_position(base + Vector3(1.0, 0.0, 0.0))
	var h_px: float = absf(p2.x - p0.x)
	print("② 场地中心 1.0 米【横向】 → %.2f px" % h_px)
	## ★竖/横 = cos(俯角) —— 竖直世界段被俯视压缩, 横向不被压缩。
	##   (第一版我写成 sin 并报出 39.2°, 是余角, 错的; 真值 50.8° 与
	##    battle_world_builder.gd:370 注释里的「俯角≈51°」一致 —— 对得上才敢用。)
	var ratio: float = v_px / maxf(0.001, h_px)
	print("   ⇒ 竖/横 = %.4f = cos(俯角) ⇒ 俯角 %.1f°  (代码注释写的是 ≈51°, 对得上)" % [
		ratio, rad_to_deg(acos(clampf(ratio, -1.0, 1.0)))])

	# ── ③ 现在的地砖板厚投出来多少像素 ──
	print("③ TILE_THICK=%.3f 米 → %.2f px  ★这就是「场地边界没有体积」的量化值" % [
		RB.TILE_THICK, RB.TILE_THICK * v_px])

	# ── ④ 龟(公告板)到底多高: 量真实单位, 不拿常量当真 ──
	## ★键名是 "sprite" 不是 "node" —— 第一版我凭印象写了 "node", 结果
	##   「一个单位都没取到」。分母断言当场把它抓出来了, 否则会被读成「结果是 0」。
	var shown := 0
	var n_units: int = inst._units.size()
	for u in inst._units:
		if shown >= 4:
			break
		var node = u.get("sprite")
		if node == null or not is_instance_valid(node):
			continue
		if not (node is Sprite3D):
			continue
		var s: Sprite3D = node
		var t: Texture2D = s.texture
		if t == null:
			continue
		## ★用【单帧】高不是整张精灵表高。第一版我写 t.get_height(), 结果
		##   石头龟(vframes=2)报成 4.000 米而实际是 2.000 —— 一张表里两行帧。
		##   `battle_spawn.gd:351` 明写 pixel_size = TARGET_BODY_H / frame_h ⇒ 每只龟单帧等高。
		var vf: int = maxi(1, s.vframes)
		var wh: float = (float(t.get_height()) / float(vf)) * s.pixel_size     # 公告板单帧世界高(米)
		## ★注意这是【矩形】高, 龟本身还小一圈(图里有透明留白) ——
		##   要「龟看起来多高」必须再乘非透明包围盒占比, 那一步在图上量, 不在这里。
		var gp: Vector3 = s.global_position
		var a: Vector2 = cam.unproject_position(gp)
		var b: Vector2 = cam.unproject_position(gp + Vector3(0.0, wh, 0.0))
		var up_px: float = absf(b.y - a.y)
		print("④ 单位 %-10s 世界高 %.3f 米 · billboard=%d · 若当竖直物投影 %.1f px · 但公告板朝相机 ⇒ 屏幕高 = %.1f px" % [
			str(u.get("id", "?")), wh, int(s.billboard), up_px, wh * h_px])
		shown += 1
	if shown == 0:
		print("[FAIL] ★分母: _units 有 %d 个, 但一个 Sprite3D 都没取到 —— 探针无效, 不是「结果为 0」" % n_units)
	else:
		print("   (分母: _units 共 %d 个, 取到 Sprite3D 的 %d 个)" % [n_units, shown])

	print("")
	print("★结论怎么用: 参考给的是【屏幕比例】0.81。")
	print("   若龟是公告板(不吃俯角压缩), 龟屏幕高 = 世界高 × 横向px/米;")
	print("   而边界墙是【竖直面】(吃压缩), 墙世界高 = 0.81 × 龟屏幕高 ÷ 竖向px/米。")
	get_tree().quit()
