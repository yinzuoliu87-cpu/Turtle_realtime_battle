extends Node
## verify_barnacle_line.gd — 021 守护贝母【绑定线】的门禁 (2026-09-12)
##
## ════════════════════════════════════════════════════════════════════════
##  ★由来 —— 用户原话钉在这里
## ════════════════════════════════════════════════════════════════════════
## 看 021 的窗口:「**这个线感觉生硬啊**」
## 我给它加了垂坠和摆动, 他当场否:「**不要用什么规则图案敷衍我，不是说过怎么做吗**」
##
## 被否的**不是那条线直不直**, 是我**凭手感编**而不是照参考量。
## 正确做法(docs/specs/装备特效制作流程.md 阶段 2.5 五步):
##   ①真下视频抽帧 ②逐帧定位 ③量成硬指标 ④照量做 ⑤同一把尺子并排比
##
## ★★我在这一轮还栽了一次基准错: 第一次下的参考是 **2013-03-29** 的英雄聚焦。
##   用户:「**拿10年前的干嘛啊，今年都2026了，最新的呢**」。
##   两版差得很远 —— 2013 那条是**粗光束**(占角色高 47%), 2026 版是**细线**(约 8%)。
##   ⇒ 参考视频**必须先看上传日期**。
##
## ── 实测(参考: 08N5yDWo930, 上传 2026-07-25, S16 补丁, f13 t=33.48s) ──
##   量法: 逐列取青度峰行对齐, 取横截面, **扣掉背景**再算宽度
##         (不扣背景会把地面亮度算成"线", 我第一版就是这么量出 8px 的)
##   参考: 峰/背 2.01 · 半高宽 4px · 四分宽 5px · 中心线离首尾直线偏离 5.0% ⇒ 直的
##   我们: 峰/背 3.11 · 半高宽 3px · 四分宽 9px
##   ★4px 一格已到量化极限(芯半径 0.52⇒3px, 0.62⇒8px, 中间没有档), ±1px 就是像素风的精度。
##
## ── 判据 ────────────────────────────────────────────────────────────────
## ★★已知盲区(反向验证抓出来的, 写在这里不装看不见):
##   把 `PRIMITIVE_TRIANGLES` 退回 `PRIMITIVE_LINES`, **这套门禁一条都拦不住** ——
##   `ImmediateMesh` 没有 `surface_get_primitive_type`, 图元类型**读不回来**,
##   而顶点数与包围盒一模一样。同 `verify_bolt_line` 的那条盲区, 读不出来就不能装作读得出。
##   拦得住的是: 有没有贴图(②) / 粗细(③) / 直不直(④) / 贴图本身的三层结构(⑤)。
##
## 量**真实产出的网格**: 调完 `barnacle_line` 从 `_world` 捞出 MeshInstance3D,
## 读它 `ImmediateMesh` 的顶点数与包围盒, 读贴图里的真实像素。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## ★实测常数(染色法量的): 台子镜头下一个屏幕像素 = 多少米。
const M_PER_SCREEN_PX := 0.0426
## 参考实测: 线粗占角色高约 8%; 龟高 2.0 m ⇒ 目标世界粗细
const REF_THICK_M := 0.16
const THICK_TOL := 0.06

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 021 绑定线: 照 2026 版 LoL 卡尔玛 W 的实测做 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED

	var u: Dictionary = {
		"pos": Vector2(500.0, 400.0), "alive": true, "hp": 500.0, "maxHp": 1000.0,
		"height": 0.0, "eq_state": {}, "equips": [],
	}
	var v: Dictionary = {
		"pos": Vector2(900.0, 400.0), "alive": true, "hp": 500.0, "maxHp": 1000.0,
		"height": 0.0, "eq_state": {}, "equips": [],
	}
	_s._vfx.barnacle_line(u, v)
	var im = u.get("barnacle_line", null)

	# ── ① ★分母: 真的建出了网格 ────────────────────────────────────────
	_ok("① ★分母: barnacle_line 建出了 MeshInstance3D", im is MeshInstance3D and is_instance_valid(im))
	if not (im is MeshInstance3D) or not is_instance_valid(im):
		_done(); return
	var mesh: ImmediateMesh = (im as MeshInstance3D).mesh as ImmediateMesh
	_ok("① ★分母: 它是 ImmediateMesh 且有面", mesh != null and mesh.get_surface_count() >= 1)
	if mesh == null or mesh.get_surface_count() < 1:
		_done(); return
	var vn: int = int(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size())
	_ok("① 顶点数是 6 的整数倍(每片两个三角形)", vn > 0 and vn % 6 == 0, "实得 %d" % vn)

	# ── ② ★★不是 1px 裸线: 有贴图、用 NEAREST ────────────────────────
	## 被否的原版是 `PRIMITIVE_LINES` 画 5 条 1px 无贴图的线。
	var mat: StandardMaterial3D = (im as MeshInstance3D).material_override as StandardMaterial3D
	_ok("② ★分母: 拿得到覆盖材质", mat != null)
	if mat != null:
		_ok("② ★★线是【贴图铺出来的】不是 1px 裸 GPU 线", mat.albedo_texture != null)
		_ok("② 像素画用 NEAREST(LINEAR 会糊)",
			mat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST)

	# ── ③ ★★粗细照 2026 实测(不是 2013 那版的 47%) ────────────────────
	var aabb: AABB = (im as MeshInstance3D).get_aabb()
	## 线沿 x 走 ⇒ 世界 z 方向的厚度就是线粗(面朝相机的方片, 相机上向量的 z 分量约 0.78)
	var thick: float = maxf(aabb.size.y, aabb.size.z)
	_ok("③ ★★线粗 ≈ %.2f m(2026 参考实测: 占角色高约 8%%; 龟高 2.0 m)" % thick,
		absf(thick - REF_THICK_M) <= THICK_TOL,
		"实得 %.3f m / 目标 %.2f±%.2f —— 2013 那版是 0.94 m(47%%), 会被这条判红" % [thick, REF_THICK_M, THICK_TOL])

	# ── ④ ★★直的: 参考中心线偏离只有 5.0% ────────────────────────────
	## 判据不拿 BIND_SAG 自己算(那是恒真式) —— 量**真实网格**的包围盒:
	## 一条直线连两点, 包围盒在垂直方向上只该有"线粗"那么厚。
	var span_m: float = (Vector2(900.0, 400.0) - Vector2(500.0, 400.0)).length() * _s.WS
	_ok("④ ★分母: 包围盒长度 ≈ 两点距离(实得 %.2f m / 应 %.2f m)" % [aabb.size.x, span_m],
		absf(aabb.size.x - span_m) < span_m * 0.25)
	## ★判据换过形状: 第一版量 `aabb.size.y`(只抓得到**垂直**方向的弯)。
	##   量**每个顶点离两端直线的垂距** ⇒ 任何方向的弯都抓得到。
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var pa: Vector3 = _s._world_pos(Vector2(500.0, 400.0), 1.15)
	var pb: Vector3 = _s._world_pos(Vector2(900.0, 400.0), 1.15)
	var dirv: Vector3 = (pb - pa).normalized()
	var devmax := 0.0
	for vtx in verts:
		var rel: Vector3 = vtx - pa
		devmax = maxf(devmax, (rel - dirv * rel.dot(dirv)).length())
	_ok("④ ★★是直的: 顶点离两端直线的最大垂距 %.3f m(上限 %.2f m)" % [devmax, REF_THICK_M + THICK_TOL],
		devmax <= REF_THICK_M + THICK_TOL,
		"垂坠一打开这一条当场红 —— 参考实测中心线偏离只有 5.0%")

	# ── ⑤ 贴图本身: 三层横截面 + 硬边 ─────────────────────────────────
	if mat != null and mat.albedo_texture != null:
		var img: Image = mat.albedo_texture.get_image()
		var cnt: Dictionary = {}
		var opaque := 0
		var semi := 0
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c: Color = img.get_pixel(x, y)
				if c.a > 0.02 and c.a < 0.98:
					semi += 1
				if c.a < 0.5:
					continue
				opaque += 1
				var k := "%d_%d_%d" % [int(round(c.r8)), int(round(c.g8)), int(round(c.b8))]
				cnt[k] = int(cnt.get(k, 0)) + 1
		_ok("⑤ ★分母: 贴图里有不透明像素(实得 %d)" % opaque, opaque > 8)
		_ok("⑤ 硬边: 没有半透明羽化像素(实得 %d)" % semi, semi == 0)
		_ok("⑤ ★★横截面是【三层】(实得 %d 色) —— 参考是 芯 + 主体 + 外边" % cnt.size(),
			cnt.size() >= 3)
		var cell: int = int(img.get_width() / 4)
		_ok("⑤ 一格是方的且只有 %d px(2026 版是细线, 不是 2013 那条粗光束)" % cell,
			cell == img.get_height() and cell <= 6, "格 %d × %d" % [cell, img.get_height()])

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 12:
		print("  [FAIL] ★断言只有 %d 条(<12) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 021 绑定线" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
