class_name Cent3dVfx
extends RefCounted
## cent_3d_vfx.gd —— 百夫长的 3D 特效网格(11-27 用户「这举盾任何方向上都有可能举盾…需要三 D 特效」「冲击罩…武器头部…冲出去」)
## 只放纯函数: 网格按参数算、挂出处键(VfxTex.tag), 直播播放端按出处键调同一个函数重建(顶点不进流)。
## 节点怎么摆、怎么动在 spear_eq_vfx.gd(位置 / 旋转 / 缩放 + 着色器参数都进流)。
##   龟甲阵弧盾  gen_aegis: 以本地原点为圆心、朝 +X 的一段竖立弧面, 上沿略往外翻(像一面弯的大盾)
##   冲击罩      gen_shock: 绕 X 轴的旋转抛物面, 尖端在原点朝 +X、往 -X 张开(激波罩)
##   骑兵能量罩  gen_sheath: 绕 X 轴的水滴形闭合外壳, 前端钝(朝 +X)、尾巴拉长收尖(11-27 用户「像赛亚冲锋一样…要有个罩子」)
const SRC := "res://scripts/scenes/battle/cent_3d_vfx.gd"
const AEGIS_SHADER: Shader = preload("res://assets/shaders/cent_aegis.gdshader")
const SHOCK_SHADER: Shader = preload("res://assets/shaders/cent_shock.gdshader")
## 龟甲阵分层(11-27 附录 D): 外层 / 内层盾面(同一着色器 layer 区分)、两端翼焰、地面扇形、穿盾矛光; 灰度贴图见 tools/assetgen/build_cent_aegis_tex.py
const AEGIS_SP := ["open", "close", "fade", "t", "flash", "rip0", "rip1", "rip2", "rip3"]
const FLARE_SHADER: Shader = preload("res://assets/shaders/cent_aegis_flare.gdshader")
const FLARE_SP := ["open", "close", "fade", "t"]
const GROUND_SHADER: Shader = preload("res://assets/shaders/cent_aegis_ground.gdshader")
const GROUND_SP := ["open", "close", "fade", "t", "shell_k"]
const RAY_SHADER: Shader = preload("res://assets/shaders/cent_ray.gdshader")
const RAY_SP := ["prog"]
const AT := "res://assets/sprites/vfx/cent_aegis/"
const SHOCK_SP := ["prog", "fade"]
const SHEATH_SHADER: Shader = preload("res://assets/shaders/cent_sheath.gdshader")
const SHEATH_SP := ["t", "fade"]


## r = 半径(米), arc = 张角(弧度), h = 高(米), lean = 顶部往外翻多少(米)
static func gen_aegis(r: float, arc: float, h: float, lean: float, nu: int, nv: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(nv + 1):
		var v: float = float(j) / float(nv)
		var rr: float = r + lean * v * v
		for i in range(nu + 1):
			var u: float = float(i) / float(nu)
			var a: float = lerpf(-arc * 0.5, arc * 0.5, u)
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(cos(a) * rr, v * h, sin(a) * rr))
	_grid_index(st, nu, nv)
	st.generate_normals()   # 菲涅尔轮廓 / 盾面鼓动要法线
	return VfxTex.tag(st.commit(), "gen_aegis", [r, arc, h, lean, nu, nv], SRC)


## ln = 尖端到开口的长(米), rad = 开口半径(米)
static func gen_shock(ln: float, rad: float, nk: int, ns: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(nk + 1):
		var k: float = float(j) / float(nk)
		var rr: float = rad * sqrt(k)
		for i in range(ns + 1):
			var a: float = TAU * float(i) / float(ns)
			st.set_uv(Vector2(float(i) / float(ns), k))
			st.add_vertex(Vector3(-ln * k, cos(a) * rr, sin(a) * rr))
	_grid_index(st, ns, nk)
	st.generate_normals()
	return VfxTex.tag(st.commit(), "gen_shock", [ln, rad, nk, ns], SRC)


## ln = 全长(米), rad = 最粗处半径(米); 前端在 +X 的 ln*0.3 处, 尾尖在 -X 的 ln*0.7 处
static func gen_sheath(ln: float, rad: float, nk: int, ns: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(nk + 1):
		var k: float = float(j) / float(nk)
		var rr: float = rad * pow(sin(PI * pow(k, 0.55)), 0.85)   # pow(k, 0.55): 前端很快就粗起来(钝头), 后面慢慢收(长尾)
		for i in range(ns + 1):
			var a: float = TAU * float(i) / float(ns)
			st.set_uv(Vector2(float(i) / float(ns), k))
			st.add_vertex(Vector3(ln * (0.3 - k), cos(a) * rr, sin(a) * rr))
	_grid_index(st, ns, nk)
	st.generate_normals()
	return VfxTex.tag(st.commit(), "gen_sheath", [ln, rad, nk, ns], SRC)


## 翼焰竖条: 贴在弧盾一端(side = +1 / -1), 沿弧的切线 + 往外翻出去 w 米, 高 h 米(UV.x 0 = 贴盾边 → 1 外侧)
static func gen_aegis_flare(r: float, arc: float, h: float, w: float, side: float, nu: int, nv: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a: float = arc * 0.5 * side
	var base := Vector3(cos(a) * r, 0.0, sin(a) * r)
	var radial := Vector3(cos(a), 0.0, sin(a))
	var tang := Vector3(-sin(a), 0.0, cos(a)) * side
	for j in range(nv + 1):
		var y: float = float(j) / float(nv)
		for i in range(nu + 1):
			var x: float = float(i) / float(nu)
			var out: Vector3 = (tang * 0.75 + radial * 0.65).normalized() * (x * w) - radial * (x * x * w * 0.35)   # 往外翻、末端往回卷一点
			st.set_uv(Vector2(x, y))
			st.add_vertex(base + out + Vector3(0.0, y * h * (1.0 - x * 0.25), 0.0))
	_grid_index(st, nu, nv)
	return VfxTex.tag(st.commit(), "gen_aegis_flare", [r, arc, h, w, side, nu, nv], SRC)


## 贴地扇形(离地 y0 米): 半径 r0 → r1, 张角 arc(TAU = 整圈)
static func gen_fan(r0: float, r1: float, arc: float, y0: float, nu: int, nv: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(nv + 1):
		var k: float = float(j) / float(nv)
		var rr: float = lerpf(r0, r1, k)
		for i in range(nu + 1):
			var u: float = float(i) / float(nu)
			var a: float = lerpf(-arc * 0.5, arc * 0.5, u)
			st.set_uv(Vector2(u, k))
			st.add_vertex(Vector3(cos(a) * rr, y0, sin(a) * rr))
	_grid_index(st, nu, nv)
	return VfxTex.tag(st.commit(), "gen_fan", [r0, r1, arc, y0, nu, nv], SRC)


## 十字交叉两片(沿 +X 长 ln 米, 宽 w 米): 穿盾矛光
static func gen_ray_cross(ln: float, w: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for plane in [Vector3.UP, Vector3.BACK]:
		var p0: int = 0
		for q in [[0.0, -0.5], [0.0, 0.5], [1.0, 0.5], [1.0, -0.5]]:
			st.set_uv(Vector2(float(q[1]) + 0.5, float(q[0])))
			st.add_vertex(Vector3(float(q[0]) * ln, 0.0, 0.0) + plane * (float(q[1]) * w))
	for b in [0, 4]:
		for k in [0, 1, 2, 0, 2, 3]:
			st.add_index(b + k)
	return VfxTex.tag(st.commit(), "gen_ray_cross", [ln, w], SRC)


static func tex(name: String) -> Texture2D:
	return load(AT + name) as Texture2D


static func _grid_index(st: SurfaceTool, nu: int, nv: int) -> void:
	for j in range(nv):
		for i in range(nu):
			var a: int = j * (nu + 1) + i
			var b: int = a + 1
			var c: int = a + (nu + 1)
			var d: int = c + 1
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)


## 地面方向(sim 2D) → 绕 Y 的转角: 本地 +X 转到世界 (dir.x, 0, dir.y)
static func yaw_of(dir: Vector2) -> float:
	return atan2(-dir.y, dir.x)


## 建一个挂着色器的网格节点(着色器参数进流)
## prio > 0: 画在立绘(Sprite3D render_priority 9)前面 —— 冲击罩 / 船头浪要压在马和人身上才看得见; 弧盾用 0(身后那半边该被人挡住)
static func node(world: Node3D, mesh: Mesh, shader: Shader, sp: Array, params: Dictionary, prio: int = 0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = prio
	for k in params:
		mat.set_shader_parameter(k, params[k])
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(&"stream_shader_params", PackedStringArray(sp))
	world.add_child(mi)
	return mi
