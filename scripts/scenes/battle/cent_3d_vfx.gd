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
const AEGIS_SP := ["open", "fade", "t", "flash", "brk"]
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
