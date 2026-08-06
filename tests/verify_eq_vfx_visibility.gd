extends Node
## verify_eq_vfx_visibility.gd — 四件"看不见"的装备演出门禁
## (085 压电火花 / 089 蚀月符纸 / 091 远古龟甲片 / 094 祖龟碑)
##
## ══════════════════════════════════════════════════════════════════════════
##  ★这份门禁守的是别的门禁**结构上守不住**的那一层: 「它在实战里到底看不看得见」
## ══════════════════════════════════════════════════════════════════════════
## 已有的 verify_eq_arcane/gadget/relic_batch 三份守的是**数值与接线**:
## 半径公式是不是那条闭式解、节点有没有真的进 _world、撤场干不干净。
## 这四件在那三份里**全绿**, 而干净台(VFXLAB)一拍才发现:
##   · 089 是一张**纯白空白四边形**(无符文/无月/无边框), 10.8×9.3 屏幕像素, 且每 2.33 秒自转到侧面整张消失
##   · 094 碑身自发光把琥珀刻纹**烧成一块纯白板**, 三个星级的刻纹一条都看不出来
##   · 085 半径 0.08·√E 把常态压到 4.9~10.5 屏幕像素
##   · 091 甲片 17.6×13.7 px、alpha 0.30, 纯黑场上都低对比
## ⇒ 「公式对」与「看得见」是**两件事**, 前者一条都不能证明后者。
##
## ── 标尺(★写字面值, 不引用被测常量 —— 引用就是拿代码跟它自己比 = 恒真式) ──
## 实战默认视角 1280×720: 相机 (0,28,22) look_at (0,0.6,0), fov 40(竖直)。
##   视距 d = √(27.4² + 22²) = 35.13915 米
##   屏高对应 2·d·tan(20°) = 25.5794 米 ⇒ **28.14758 屏幕像素/米**
##   · 与视轴垂直(横向 / 正对镜头的片): ×1        = 28.14758 px/米 = 0.675542 px/码
##   · **世界竖直**(碑高 / 立着的片):    ×22/d     = 17.62155 px/米 = 0.422917 px/码
##   · 贴地纵深(甲片的前后向):          ×27.4/d   = 21.94674 px/米 = 0.526722 px/码
## 参照物: 龟立绘高 ≈ 44 px、**头顶等级徽章 ≈ 16 px**。
## ⇒ 判据: **低于 16 屏幕像素的东西在实战中等于不存在。**
## (标尺自身也焊了一条断言: 拿 EQDEMO 那只龟的立绘世界高度反算, 必须回到 44 px 附近。)
##
## ⚠ 全同步: 形态一律由纯函数 / `apply_*` 直接写到任意时刻, 不等任何 tween(CLAUDE.md §3.5)。
## ⚠ 用干净合成单位, 不用随机 spawn(memory [[fb-ci-vs-local-divergence]])。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_eq_vfx_visibility.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AV := preload("res://scripts/scenes/battle/arcane_eq_vfx.gd")
const GV := preload("res://scripts/scenes/battle/gadget_eq_vfx.gd")
const RV := preload("res://scripts/scenes/battle/relic_eq_vfx.gd")

## ── 标尺(字面值) ──
const PX_PER_M := 28.147577          # 与视轴垂直
const PX_PER_M_VERT := 17.621551     # 世界竖直
const PX_PER_M_DEPTH := 21.946739    # 贴地纵深
const WS_LIT := 0.024                # 码 → 米
const PX_PER_YD := 0.675542          # PX_PER_M * WS
const PX_PER_YD_VERT := 0.422917
const PX_PER_YD_DEPTH := 0.526722
## 存在阈值 = 头顶等级徽章的边长
const VISIBLE_PX := 16.0

var _n := 0
var _fail := 0
var _s
var _av
var _gv
var _rv


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 四件装备演出的【实战可见性】门禁 (085 / 089 / 091 / 094) ===")
	print("标尺: 1280x720 默认视角 %.5f px/米(横) · %.5f px/米(竖) · 阈值 %.0f px" % [
		PX_PER_M, PX_PER_M_VERT, VISIBLE_PX])

	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(8):
		await get_tree().process_frame

	_g0_denominator()
	if _s == null or not is_instance_valid(_s._world):
		print("")
		print("FAIL x%d — ★分母没过, 后面全是空检查" % maxi(1, _fail))
		get_tree().quit(1); return
	_av = AV.new(_s)
	_gv = GV.new(_s)
	_rv = RV.new(_s)

	_g1_ruler()
	_g2_085_spark()
	await _g3_089_size_and_facing()
	_g4_089_texture()
	_g5_091_scutes()
	_g6_094_glyphs()
	_done()


# ── ⓪ 分母 ───────────────────────────────────────────────────────────────
func _g0_denominator() -> void:
	print("")
	print("  ⓪ ★分母:")
	_ok("⓪ 战斗场景与 _world 都在", is_instance_valid(_s) and is_instance_valid(_s._world))
	_ok("⓪ WS 与本文件字面标尺一致(WS 改了这份标尺就全废, 必须一起改)",
		absf(float(_s.WS) - WS_LIT) < 1e-9, "代码 WS=%s / 标尺 %.4f" % [str(_s.WS), WS_LIT])


# ── ① 标尺自证 —— 拿【真实相机 + 真实立绘】反算, 证明这把尺子不是我编的 ─────
func _g1_ruler() -> void:
	print("")
	print("  ① 标尺自证(反算真实相机):")
	var cam = _s._cam
	_ok("① 相机在(分母)", cam != null and is_instance_valid(cam))
	if cam == null or not is_instance_valid(cam):
		return
	## 相机与注视点的几何 → px/米。★这里**不读**本文件的常量, 是从场景里现算的。
	var d: float = (Vector3(cam.position) - Vector3(_s.CAM_TARGET)).length()
	var half_m: float = d * tan(deg_to_rad(float(cam.fov) * 0.5))
	var got_px_per_m: float = 720.0 / (2.0 * half_m)
	_ok("① 现算 px/米 = 本文件标尺(误差 < 0.5%)",
		absf(got_px_per_m - PX_PER_M) / PX_PER_M < 0.005,
		"现算 %.4f / 标尺 %.4f (视距 %.4f 米, fov %.2f°)" % [got_px_per_m, PX_PER_M, d, float(cam.fov)])
	## 世界竖直方向的投影系数 = 视轴与水平面夹角的余弦 —— 由相机自身位置现算
	var fwd: Vector3 = (Vector3(_s.CAM_TARGET) - Vector3(cam.position)).normalized()
	var vert_fac: float = sqrt(1.0 - fwd.y * fwd.y)      # = |(0,1,0) 在屏幕上向的投影|
	_ok("① 现算【世界竖直】投影系数 = 本文件标尺(误差 < 1%)",
		absf(got_px_per_m * vert_fac - PX_PER_M_VERT) / PX_PER_M_VERT < 0.01,
		"现算 %.4f / 标尺 %.4f" % [got_px_per_m * vert_fac, PX_PER_M_VERT])


# ── ② 085 压电火花: 常态可见 + 上限不爆屏 ────────────────────────────────
## 常态每下挨打 8~36 伤害 ⇒ E = 0.15 × 伤害 = 1.2~5.4(3★ 转化率 15%, 见 eq_gadget_batch.piezo_settle)
## 硬上限 E = 60(3★ 每秒配额封顶)。
func _g2_085_spark() -> void:
	print("")
	print("  ② 085 压电火花 —— 常态可见 / 上限不爆屏:")
	var d_lo: float = 2.0 * GV.spark_radius(1.2) * PX_PER_M
	var d_hi: float = 2.0 * GV.spark_radius(5.4) * PX_PER_M
	var d_cap: float = 2.0 * GV.spark_radius(60.0) * PX_PER_M
	_ok("②a 常态下沿(挨 8 伤害·E=1.2) 屏幕直径 ≥ 16 px(等级徽章尺寸)",
		d_lo >= VISIBLE_PX, "实测 %.2f px (改前 4.93 px)" % d_lo)
	_ok("②b 常态上沿(挨 36 伤害·E=5.4) 屏幕直径 ≥ 24 px",
		d_hi >= 24.0, "实测 %.2f px (改前 10.47 px)" % d_hi)
	_ok("②c 设计上限(E=60·3★ 每秒封顶) 屏幕直径 ≤ 80 px(≈ 1.8 只龟高, 不爆屏)",
		d_cap <= 80.0, "实测 %.2f px" % d_cap)
	_ok("②d 单调: E 越大火花越大(常态下沿 < 常态上沿 < 上限)",
		d_lo < d_hi and d_hi < d_cap, "%.2f < %.2f < %.2f" % [d_lo, d_hi, d_cap])
	## 量真实节点: 建一次真火花, 节点 scale 就是半径
	var u := _mk(Vector2(400.0, 400.0))
	var n = _gv.piezo_spark(u, 5.4)
	_ok("②e 真实节点建出来了且进了 _world(分母)",
		n != null and is_instance_valid(n) and (n as Node).get_parent() == _s._world)
	if n != null and is_instance_valid(n):
		_ok("②f 真实节点的 scale ≡ spark_radius(E)(不是「公式对了但没写到节点上」)",
			absf((n as MeshInstance3D).scale.x - GV.spark_radius(5.4)) < 1e-6,
			"scale.x=%.6f / 公式 %.6f" % [(n as MeshInstance3D).scale.x, GV.spark_radius(5.4)])
	_gv.clear()


# ── ③ 089 蚀月符纸: 尺寸 + 【永不转到侧面】 ──────────────────────────────
func _g3_089_size_and_facing() -> void:
	print("")
	print("  ③ 089 蚀月符纸 —— 尺寸 / 永远正对镜头:")
	var w_px: float = AV.TALISMAN_W_PX * PX_PER_YD
	var h_px: float = AV.TALISMAN_H_PX * PX_PER_YD
	_ok("③a 符纸长边 ≥ 28 屏幕像素(改前 9.30 px —— 竖着的片只吃 0.4229 px/码)",
		maxf(w_px, h_px) >= 28.0, "实测 %.2f × %.2f px" % [w_px, h_px])
	_ok("③b 符纸短边也 ≥ 16 px(等级徽章尺寸)", minf(w_px, h_px) >= VISIBLE_PX,
		"短边 %.2f px" % minf(w_px, h_px))

	# ── 朝向: face_basis 的 +Z ≡ −cam_fwd, 与 roll 无关 ──
	var dirs: Array = [
		Vector3(0, -27.4, -22), Vector3(1, -1, -1), Vector3(-3, -2, 5),
		Vector3(0, -1, 0.001), Vector3(7, -0.2, -1), Vector3(-1, -9, 0.3),
	]
	var face_ok := 0
	var orth_ok := 0
	var tries := 0
	for f in dirs:
		for k in range(9):
			var roll: float = -PI + TAU * float(k) / 9.0
			var b: Basis = AV.face_basis(f, roll)
			tries += 1
			if b.z.dot(-(f as Vector3).normalized()) > 0.999999:
				face_ok += 1
			if absf(b.x.dot(b.y)) < 1e-5 and absf(b.x.length() - 1.0) < 1e-5 \
					and absf(b.y.length() - 1.0) < 1e-5 and absf(b.z.length() - 1.0) < 1e-5:
				orth_ok += 1
	_ok("③c face_basis 的 +Z 轴 ≡ −镜头前向(与 roll 无关) —— %d 组方向×滚角" % tries,
		face_ok == tries and tries == 54, "%d/%d" % [face_ok, tries])
	_ok("③d face_basis 三轴正交且单位长(不会顺手把符纸拉伸/镜像)",
		orth_ok == tries, "%d/%d" % [orth_ok, tries])

	# ── ★核心: 量【真实节点】跑满 12 秒, 投影宽度一刻都不许塌 ──
	#    旧实现 rotation.y = 1.35·t, 每 2.33 秒 |cos| 过零 ⇒ 这条必红。
	var u := _mk(Vector2(500.0, 400.0))
	var node = _av.talisman_stick(u, 15.0)
	_ok("③e 真实符纸建出来了且进了 _world(分母)",
		node != null and is_instance_valid(node) and (node as Node).get_parent() == _s._world)
	if node == null or not is_instance_valid(node):
		return
	var cam_fwd: Vector3 = _av._cam_forward()
	var worst: float = 1.0
	var steps := 0
	for i in range(720):                       # 720 × 1/60 秒 = 12 秒, 跨 5 个旧自转周期
		_av.tick(1.0 / 60.0)
		if not is_instance_valid(node):
			break
		steps += 1
		## 投影宽度比 = |片法线 · 镜头前向|。1.0 = 正对, 0.0 = 侧对(整张消失)
		var face: float = absf((node as Node3D).global_transform.basis.z.dot(cam_fwd))
		worst = minf(worst, face)
	_ok("③f ★逐帧量真实节点: 12 秒里投影宽度比**最低** ≥ 0.999(1.0 = 正对镜头)"
		+ " —— 旧的匀速自转每 2.33 秒会掉到 0",
		steps >= 700 and worst >= 0.999, "推进 %d 帧, 最低 %.6f" % [steps, worst])
	## 摇摆有界(而不是"我把摇摆关了所以当然不消失")
	var roll_max := 0.0
	var roll_nonzero := false
	for i in range(2000):
		var r: float = absf(AV.talisman_roll(float(i) * 0.01))
		roll_max = maxf(roll_max, r)
		if r > 0.05:
			roll_nonzero = true
	_ok("③g 面内摇摆**有界**(≤ 0.25 rad) 且**真的在摇**(不是关掉了事)",
		roll_max <= 0.25 and roll_nonzero, "20 秒扫描最大 %.5f rad" % roll_max)
	_av.clear()


# ── ④ 089 符纸的程序化纹理: 它到底画了东西没有 ────────────────────────────
func _g4_089_texture() -> void:
	print("")
	print("  ④ 089 符纸纹理 —— 不是一张纯白空白四边形:")
	var img: Image = AV.talisman_tex_image()
	_ok("④a 纹理尺寸非零(分母)", img != null and img.get_width() > 8 and img.get_height() > 8,
		"%dx%d" % [img.get_width(), img.get_height()])
	if img == null:
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	# a. 色阶数 —— 纯白空白只有 1 种颜色
	var seen := {}
	for y in range(h):
		for x in range(w):
			seen[img.get_pixel(x, y).to_rgba32()] = true
	_ok("④b ★纹理里至少有 5 种不同颜色(改前是一整块纯白 ⇒ 1 种)",
		seen.size() >= 5, "实测 %d 种" % seen.size())
	# b. 边框比纸面亮
	var l_edge: float = _luma(img.get_pixel(1, int(h * 0.5)))
	var l_paper: float = _luma(img.get_pixel(8, 50))
	_ok("④c 有边框: 边缘像素比纸面亮 ≥ 1.5 倍", l_edge > l_paper * 1.5,
		"边框 luma %.4f / 纸面 luma %.4f" % [l_edge, l_paper])
	# c. 月牙: 月区亮像素 / 外圆面积 ∈ [0.20, 0.70] —— 满月给 ~1.0, 没画给 0
	var moon_px := 0
	var circ_px := 0
	for y in range(h):
		for x in range(w):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			if p.distance_to(AV.MOON_C) <= AV.MOON_R:
				circ_px += 1
				if _luma(img.get_pixel(x, y)) > 0.80:
					moon_px += 1
	var frac: float = float(moon_px) / maxf(1.0, float(circ_px))
	_ok("④d ★有月牙: 亮像素占外圆的 %.1f%% ∈ [20%%, 70%%](满月会给 ~100%%, 没画给 0%%)"
		% (frac * 100.0), frac >= 0.20 and frac <= 0.70,
		"月 %d px / 外圆 %d px" % [moon_px, circ_px])
	# d. 符文区有笔画
	var rune_px := 0
	for y in range(52, mini(h - 4, 90)):
		for x in range(6, w - 6):
			if _luma(img.get_pixel(x, y)) > 0.60:
				rune_px += 1
	_ok("④e 有符文笔画: 下半张亮像素 ≥ 200 个", rune_px >= 200, "实测 %d px" % rune_px)


# ── ⑤ 091 远古龟甲片: 尺寸 + 描边真的被读了 + 爆发档更亮 ──────────────────
func _g5_091_scutes() -> void:
	print("")
	print("  ⑤ 091 远古龟甲片 —— 尺寸 / 描边 / 爆发档:")
	var plate_w_px: float = 2.0 * RV.PLATE_R_PX * PX_PER_YD
	var plate_d_px: float = 2.0 * RV.PLATE_R_PX * PX_PER_YD_DEPTH
	_ok("⑤a 单片屏幕宽 ≥ 16 px(改前 17.56 px 已擦边, 现要求真的过线)",
		plate_w_px >= VISIBLE_PX + 8.0, "实测 %.2f × %.2f px" % [plate_w_px, plate_d_px])
	var span_yd: float = 2.0 * sqrt(3.0) * RV.PLATE_R_PX + 2.0 * RV.PLATE_R_PX
	_ok("⑤b 甲片环整体跨度 ≥ 44 px(= 龟立绘高) —— 要「围着龟」, 不是垫在脚下一小团",
		span_yd * PX_PER_YD >= 44.0, "实测 %.2f px (改前 30.3 px)" % (span_yd * PX_PER_YD))
	# 描边: 网格里必须同时有暗芯与亮沿, 且亮沿在外圈
	var mesh: ArrayMesh = RV._build_hex()
	_ok("⑤c 甲片网格建出来了(分母)", mesh != null and mesh.get_surface_count() == 1)
	var arr: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols = arr[Mesh.ARRAY_COLOR]
	_ok("⑤d ★网格真的带顶点色数组(没有的话描边等于没写)",
		cols != null and cols is PackedColorArray and (cols as PackedColorArray).size() == verts.size(),
		"顶点 %d / 颜色 %d" % [verts.size(), (cols as PackedColorArray).size() if cols is PackedColorArray else -1])
	if cols is PackedColorArray:
		var r_dim := 0.0
		var r_bright := 1e9
		var n_dim := 0
		var n_bright := 0
		for i in range((cols as PackedColorArray).size()):
			var a: float = (cols as PackedColorArray)[i].a
			var r: float = Vector2(verts[i].x, verts[i].z).length()
			if a >= 0.99:
				n_bright += 1
				r_bright = minf(r_bright, r)
			elif a <= 0.60:
				n_dim += 1
				r_dim = maxf(r_dim, r)
		_ok("⑤e 同时存在【暗芯】与【亮沿】顶点", n_dim > 0 and n_bright > 0,
			"暗 %d / 亮 %d" % [n_dim, n_bright])
		_ok("⑤f 亮沿在外圈: 最内的亮顶点半径 ≥ 最外的暗顶点半径",
			r_bright >= r_dim - 1e-6, "亮沿内边界 %.4f / 暗芯外边界 %.4f" % [r_bright, r_dim])
	# ★写了得有人读: 甲片材质必须开 vertex_color_use_as_albedo
	var u := _mk(Vector2(600.0, 400.0))
	var hs: Dictionary = _rv.ensure_scutes(u)
	_ok("⑤g 真实甲片环建出来了(分母)", not hs.is_empty() and (hs["plates"] as Array).size() == 6)
	if not hs.is_empty():
		var mi = (hs["plates"] as Array)[0]
		var mat = (mi as MeshInstance3D).material_override
		_ok("⑤h ★★甲片材质真的开了 vertex_color_use_as_albedo"
			+ "(没开 = 描边写进去了没人读, 网格断言照样全绿)",
			mat is StandardMaterial3D and (mat as StandardMaterial3D).vertex_color_use_as_albedo)
	# 爆发档的 alpha 量程必须还没撞顶(否则 ×√6 那条比值断言是"两边都被钳所以相等")
	var a_low: float = RV.PLATE_A * sqrt(6.0)
	_ok("⑤i 爆发档 alpha = PLATE_A × √6 = %.4f 仍 < 1.0(量程没被钳)" % a_low,
		a_low < 1.0 and a_low > 0.90, "PLATE_A=%.4f ⇒ %.4f" % [RV.PLATE_A, a_low])
	_rv.clear_all()


# ── ⑥ 094 祖龟碑: 刻纹看得出来 + 三个星级分得出 ───────────────────────────
func _g6_094_glyphs() -> void:
	print("")
	print("  ⑥ 094 祖龟碑 —— 刻纹可见 / 三星级可分辨:")
	var shaft_h: float = RV.STELE_H - RV.PLINTH_H
	# a. 条数 = si + 1, 三档互不相同
	var ns: Array = []
	for si in [0, 1, 2]:
		ns.append(RV.glyph_bands(si, shaft_h).size())
	_ok("⑥a ★三个星级的刻纹条数 = 1 / 2 / 3(数得清, 不是「比宽度差 2 px」)",
		ns == [1, 2, 3], "实测 %s" % str(ns))
	# b. 单条刻纹的屏幕尺寸
	var b2: Array = RV.glyph_bands(2, shaft_h)
	var wmin := 1e9
	var hmin := 1e9
	for gb in b2:
		wmin = minf(wmin, 2.0 * float(gb["hw"]) * PX_PER_M)
		hmin = minf(hmin, 2.0 * float(gb["hh"]) * PX_PER_M_VERT)
	_ok("⑥b 单条刻纹屏幕宽 ≥ 16 px", wmin >= VISIBLE_PX, "最窄 %.2f px" % wmin)
	_ok("⑥c 单条刻纹屏幕高 ≥ 4 px(竖直只有 17.62 px/米, 这是能给的上限区间)",
		hmin >= 4.0, "最矮 %.2f px" % hmin)
	# c. 刻纹恒在碑面内(不挑出碑外)
	var inside := 0
	var total := 0
	for si in [0, 1, 2]:
		for gb in RV.glyph_bands(si, shaft_h):
			total += 1
			var f: float = clampf(float(gb["y"]) / shaft_h, 0.0, 1.0)
			var shaft_hw: float = lerpf(RV.SHAFT_HW_BOT, RV.SHAFT_HW_TOP, f)
			if float(gb["hw"]) <= shaft_hw and float(gb["y"]) - float(gb["hh"]) > 0.0 \
					and float(gb["y"]) + float(gb["hh"]) < shaft_h:
				inside += 1
	_ok("⑥d 六条刻纹全在碑面范围内(不挑出碑外、不越过碑座/碑顶)", inside == total and total == 6,
		"%d/%d" % [inside, total])
	# d. ★对比度: 刻纹是"刻上去的漆"不是"打上去的光" —— 量真实材质
	var h0: Dictionary = _rv.raise_stele(Vector2(700.0, 400.0), 2)
	_ok("⑥e 真实碑建出来了(分母)", not h0.is_empty() and is_instance_valid(h0["root"]))
	if h0.is_empty():
		return
	var shaft_mat = null
	var band_mats: Array = []
	for ch in (h0["root"] as Node3D).get_children():
		if not (ch is MeshInstance3D):
			continue
		var m = (ch as MeshInstance3D).material_override
		if not (m is StandardMaterial3D):
			continue
		var c: Color = (m as StandardMaterial3D).albedo_color
		## 刻纹 = 琉珀色且不透明。★ a >= 0.99 这一条不能省 ——
		##   碑脚符环用的是同一个 COL_GLYPH(alpha 0.42), 不排掉会多数出一条。
		if c.r > 0.9 and c.g > 0.7 and c.b < 0.5 and c.a >= 0.99:
			band_mats.append(m)
		## 碑身 = COL_STONE 本色(碑座是它的 0.72~0.78 倍缩色, 不能混进来)
		elif _near3(c, RV.COL_STONE):
			shaft_mat = m
	_ok("⑥f 认出碑身与刻纹材质(分母): 刻纹 %d 条(3★ 两面各 3 条 = 6)" % band_mats.size(),
		shaft_mat != null and band_mats.size() == 6)
	if shaft_mat == null or band_mats.is_empty():
		return
	var add_n := 0
	for m in band_mats:
		if (m as StandardMaterial3D).blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
			add_n += 1
	_ok("⑥g ★刻纹**不是** BLEND_ADD(加法会把它加进自发光的碑身里烧成纯白 —— 改前就是这样)",
		add_n == 0, "%d/%d 条仍是 ADD" % [add_n, band_mats.size()])
	var l_band: float = _luma((band_mats[0] as StandardMaterial3D).albedo_color)
	var l_shaft: float = _luma((shaft_mat as StandardMaterial3D).albedo_color)
	_ok("⑥h ★刻纹 / 碑身 亮度比 ≥ 2.0(改前碑身 luma 0.64 已近白, 加什么都看不出)",
		l_band / maxf(l_shaft, 1e-6) >= 2.0,
		"刻纹 %.4f / 碑身 %.4f = %.3f 倍" % [l_band, l_shaft, l_band / maxf(l_shaft, 1e-6)])
	# e. 碑体本身的屏幕尺寸
	var stele_w_px: float = 2.0 * RV.PLINTH_HW * PX_PER_M
	var stele_h_px: float = RV.STELE_H * PX_PER_M_VERT
	_ok("⑥i 碑体屏幕尺寸 ≥ 30 × 44 px(改前 22.5 × 33.5, 碑面上装不下刻纹)",
		stele_w_px >= 30.0 and stele_h_px >= 44.0,
		"实测 %.2f × %.2f px" % [stele_w_px, stele_h_px])
	_rv.clear_all()


# ── 工具 ─────────────────────────────────────────────────────────────────
## 干净合成单位(不走随机 spawn —— memory [[fb-ci-vs-local-divergence]])
func _mk(pos: Vector2) -> Dictionary:
	return {
		"id": "basic", "side": "left", "pos": pos, "hp": 1000.0, "maxHp": 1000.0,
		"alive": true, "atk": 10.0, "equips": [],
	}


## 两个颜色的 RGB 是不是同一个(用来把【碑身本色】与【碑座的缩色】分开)
func _near3(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 1e-4 and absf(a.g - b.g) < 1e-4 and absf(a.b - b.b) < 1e-4


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _ok(name: String, cond: bool, extra: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] %s%s" % [name, ("  — " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  — " + extra) if extra != "" else ""])


func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS (%d/%d)" % [_n, _n])
		get_tree().quit(0)
	else:
		print("FAIL x%d (共 %d 条)" % [_fail, _n])
		get_tree().quit(1)
