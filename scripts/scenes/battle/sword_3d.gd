extends RefCounted
class_name Sword3D

## 手半剑 084 的【真 3D 紫剑】—— 程序化网格, 不是贴图。
##
## ══════════════════════════════════════════════════════════════════
##  ★为什么是 3D, 又为什么是【程序化】而不是模型文件
## ══════════════════════════════════════════════════════════════════
## 用户 2026-08-30 拍板「3d 最好啊」。他要的是**效果最好**那条:
##   横斩现在铺在**地面平面**上, 剑尖要沿地面的圆弧扫 120° ⇒ 挥动过程中剑
##   相对镜头**不断转向**(侧对 → 冲着镜头 → 背对)。一张 2D 图绕握把转做不到
##   这件事: 转出来的剑永远是同一个侧面视角、同一个长度, 扫到"朝向镜头"那一段
##   会明显穿帮。竖斩没这个问题(挥动平面基本平行于屏幕), **横斩有**。
##   真 3D 的透视/缩短/遮挡是免费的, 这正是 2D 补不上的那一块。
##
## ★为什么不用 Tripo 生成模型: 额度用完了(403 code 2010)。
##   而且剑的几何极简单(锥形刀身 + 十字护手 + 握把 + 圆头), 程序化反而**更好**:
##   · 没有 PBR 贴图和高光 ⇒ 不会出现"3D 质感 vs 平面像素龟"两种世界
##   · 颜色直接取刀光那套紫, 改一个常量整把剑跟着变
##   · 面数可控(几百面), 不给这台有硬件故障的机器添负担
##
## ★★原点 = 【握把】。整把剑建在 `y >= 0` 一侧, 原点落在握把末端 ⇒
##   直接转这个 Node3D 就是"绕握把挥", 不需要再算偏移。
##   (刀光那边是靠 `slash_pivot_off3` 把图心退开来对齐圆心 —— 网格可以从源头就摆对。)

## 剑的分段长度(米)。总长 = 下面几项之和。
const GRIP_LEN := 0.40         # 握把(双手剑, 跟着刀身一起加长)
const GUARD_LEN := 0.06        # 护手厚度
const BLADE_LEN := 2.55        # 刀身(含尖)。★用户 2026-08-30:「再长一点」「又细又长」
const TIP_FRAC := 0.16         # 刀身末端多少比例收成尖

const GRIP_R := 0.045          # 握把半径
const POMMEL_R := 0.075        # 圆头半径
const GUARD_HALF_W := 0.30     # 护手左右伸出
const GUARD_HALF_T := 0.05     # 护手厚
## ★用户 2026-08-30:「剑是又细又长的啊」。
##   我上一版为了"看得见"把它加宽到 0.215(剑长的 8%) —— 方向错了:
##   该靠**放大**(SWORD_M)解决可读性, 不是把剑改胖。
const BLADE_HALF_W := 0.105    # 刀身最宽处的一半(约剑长的 4%)
const BLADE_HALF_T := 0.030    # 刀身厚度的一半(截面是扁菱形)

## 配色 —— 与刀光同一套紫青, 免得剑和它自己的刀光不是一路货。
## ★★实拍后重调: 原来刀身 (0.62,0.45,0.86) 和刀光都是中调紫 ⇒ **糊在一起**,
##   剑完全被刀光吃掉(逐格看了一遍才读出来)。
##   刀光是**亮**的 ⇒ 剑身改成**深紫**才割得开, 刃口提到近白做对比。
const COL_BLADE := Color(0.30, 0.17, 0.52)      # 刀身(深紫, 与亮刀光拉开)
const COL_EDGE := Color(0.97, 0.94, 1.00)       # 刃口高光(近白)
const COL_GUARD := Color(0.16, 0.12, 0.24)      # 护手(更深)
const COL_GRIP := Color(0.22, 0.17, 0.30)       # 握把


## 无光照纯色材质。★unshaded: 场上没有为 3D 准备的灯, 走光照会变成一坨黑;
##   而且平面像素龟本来就是 unshaded, 保持同一种"世界"。
static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	## ★★剑必须压在刀光【之上】。
	##   实拍: 爆发那几帧(t=1.50~1.66)刀光最亮时剑被完全盖住 ——
	##   而那恰恰是最该看见"是这只龟挥的"那几帧。
	##   刀光的 render_priority 是 7/8 ⇒ 剑给 10, 并关深度测试(与刀光同口径)。
	m.render_priority = 10
	m.no_depth_test = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## 把一串【截面环】缝成三角面。每个环是 4 个点(扁菱形: 左 右 前 后)。
## 最后一个环可以只有 1 个点(收成尖)。
static func _stitch(rings: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	for i in range(rings.size() - 1):
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		if b.size() == 1:
			## 收尖: 上一环的 4 个点各与尖点连成一个三角
			for k in range(a.size()):
				verts.append(a[k])
				verts.append(a[(k + 1) % a.size()])
				verts.append(b[0])
			continue
		for k in range(a.size()):
			var k2: int = (k + 1) % a.size()
			verts.append(a[k]); verts.append(a[k2]); verts.append(b[k2])
			verts.append(a[k]); verts.append(b[k2]); verts.append(b[k])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	if verts.size() >= 3:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## 一个扁菱形截面(半宽 w, 半厚 t, 高度 y)。
static func _ring(y: float, w: float, t: float) -> Array:
	return [Vector3(-w, y, 0.0), Vector3(0.0, y, t), Vector3(w, y, 0.0), Vector3(0.0, y, -t)]


## 建出整把剑。返回的 Node3D 原点 = 握把末端, +y = 剑尖方向。
## `scale_m`: 整把剑的缩放(1.0 = 上面那些常量给的尺寸)。
static func build(scale_m: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Sword3D"

	## ① 圆头(握把最末端)
	var pommel := MeshInstance3D.new()
	var ps := SphereMesh.new()
	ps.radius = POMMEL_R
	ps.height = POMMEL_R * 2.0
	ps.radial_segments = 8
	ps.rings = 4
	pommel.mesh = ps
	pommel.material_override = _mat(COL_GUARD)
	pommel.position = Vector3(0, POMMEL_R * 0.5, 0)
	root.add_child(pommel)

	## ② 握把
	var grip := MeshInstance3D.new()
	var gc := CylinderMesh.new()
	gc.top_radius = GRIP_R
	gc.bottom_radius = GRIP_R * 1.05
	gc.height = GRIP_LEN
	gc.radial_segments = 8
	gc.rings = 1
	grip.mesh = gc
	grip.material_override = _mat(COL_GRIP)
	grip.position = Vector3(0, POMMEL_R + GRIP_LEN * 0.5, 0)
	root.add_child(grip)

	## ③ 十字护手
	var guard := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(GUARD_HALF_W * 2.0, GUARD_LEN, GUARD_HALF_T * 2.0)
	guard.mesh = gb
	guard.material_override = _mat(COL_GUARD)
	guard.position = Vector3(0, POMMEL_R + GRIP_LEN + GUARD_LEN * 0.5, 0)
	root.add_child(guard)

	## ④ 刀身: 底部最宽 → 收窄 → 收成尖。截面是扁菱形(有中脊, 侧面看是刀不是板)
	var y0: float = POMMEL_R + GRIP_LEN + GUARD_LEN
	var body_len: float = BLADE_LEN * (1.0 - TIP_FRAC)
	var rings := [
		_ring(y0, BLADE_HALF_W, BLADE_HALF_T),
		_ring(y0 + body_len * 0.45, BLADE_HALF_W * 0.92, BLADE_HALF_T * 0.92),
		_ring(y0 + body_len, BLADE_HALF_W * 0.72, BLADE_HALF_T * 0.72),
		[Vector3(0.0, y0 + BLADE_LEN, 0.0)],
	]
	var blade := MeshInstance3D.new()
	blade.mesh = _stitch(rings)
	blade.material_override = _mat(COL_BLADE)
	root.add_child(blade)

	## ⑤ 刃口高光: 沿两侧棱各贴一条极窄的亮带 —— 让刀身在暗场里读得出"这是刃"
	for sgn in [-1.0, 1.0]:
		var edge := MeshInstance3D.new()
		## ★★原来这条亮带的**半宽和刀身一样**, 从镜头看几乎把紫色刀身整个盖住
		##   ⇒ 屏幕上是一把**白剑**。用户:「不是紫色的剑吗」。
		##   改成只占 22% 半宽的**窄脊高光**, 两侧露出紫色刀身。
		var er := [
			_ring(y0, BLADE_HALF_W * 0.22, BLADE_HALF_T * 0.55),
			_ring(y0 + body_len, BLADE_HALF_W * 0.16, BLADE_HALF_T * 0.55),
			[Vector3(0.0, y0 + BLADE_LEN, 0.0)],
		]
		edge.mesh = _stitch(er)
		edge.material_override = _mat(COL_EDGE)
		## ★第一版只外扩 0.4%, 亮带埋进刀身里了 —— 预览图上根本看不到刃。
		##   改成沿侧棱外推, 且把厚度压极薄 ⇒ 侧面看是一条亮线。
		## 脊高光只往两侧微偏, 不再整体外扩
		edge.position = Vector3(sgn * BLADE_HALF_W * 0.30, 0.0, 0.0)
		edge.scale = Vector3.ONE
		root.add_child(edge)

	root.scale = Vector3.ONE * scale_m
	return root


## 整把剑的长度(米, 未缩放) —— 挥动时算剑尖轨迹半径用。
static func total_len() -> float:
	return POMMEL_R + GRIP_LEN + GUARD_LEN + BLADE_LEN

## ══════════════════════════════════════════════════════════════════
##  ★★挥剑曲线 —— 【不是】线性插值
## ══════════════════════════════════════════════════════════════════
## 用户 2026-08-30:「不是平滑运动, 你自己想想角色是怎么挥剑的」。
##
## 真人挥剑的角度曲线分四段, 每段都有它的道理:
##   ① 蓄力回拉(anticipation)  —— 先往【反方向】带一点。没有这一下, 剑像是
##      被拖着走; 有了它, 观众提前知道"要来了"。动画十二原则第一条。
##   ② 爆发(strike)            —— 整段角度在**极短的一瞬**走完。这是刀真正砍下去的
##      那一刻, 伤害也在这一刻结算 ⇒ 角速度的尖峰必须**对齐结算时刻**。
##   ③ 冲过头(overshoot)       —— 停不住, 越过终点一点。剑有重量。
##   ④ 回弹收势(settle)        —— 阻尼摆回终点。
##
## 返回 0~1 的**归一角度**: 0 = 起手角, 1 = 收势角。
## ★注意它会跑到 [0,1] 之外 —— ①是负的, ③超过 1。这不是 bug, 是这条曲线的全部意义。
##
## ★★可量的判据(见 verify_eq_blade_batch ④s):
##   · 角速度**尖峰/均值 ≥ 4** —— 匀速的话这个比值恒等于 1
##   · 最小值 < -0.04(真的回拉过)、最大值 > 1.02(真的冲过头)
##   这两条把"不是平滑运动"变成硬要求, 而不是我说了算。
const SW_ANTICIP := 0.34       # 蓄力回拉占整段时间的比例
const SW_STRIKE := 0.15        # 爆发段占比(角度绝大部分在这里走完)
const SW_PULL := -0.16         # 回拉到哪(归一角度, 负 = 反方向)
const SW_OVER := 1.13          # 冲过头到哪

static func swing_angle(x: float) -> float:
	var t: float = clampf(x, 0.0, 1.0)
	if t < SW_ANTICIP:
		## ① 回拉: 缓出 —— 起手快、到位慢, 像把剑"端"起来
		var u: float = t / SW_ANTICIP
		return SW_PULL * sin(u * PI * 0.5)
	if t < SW_ANTICIP + SW_STRIKE:
		## ② 爆发: 缓入缓出但压在极短的窗口里 ⇒ 中段角速度极大
		var u2: float = (t - SW_ANTICIP) / SW_STRIKE
		var e: float = u2 * u2 * (3.0 - 2.0 * u2)      # smoothstep
		return lerpf(SW_PULL, SW_OVER, e)
	## ③④ 冲过头之后阻尼摆回 1.0
	var u3: float = (t - SW_ANTICIP - SW_STRIKE) / maxf(0.001, 1.0 - SW_ANTICIP - SW_STRIKE)
	return 1.0 + (SW_OVER - 1.0) * exp(-5.5 * u3) * cos(u3 * PI * 2.2)


## 爆发那一瞬在整段里的位置(0~1) —— 伤害结算时刻要对齐到这里。
static func swing_hit_x() -> float:
	return SW_ANTICIP + SW_STRIKE * 0.5
