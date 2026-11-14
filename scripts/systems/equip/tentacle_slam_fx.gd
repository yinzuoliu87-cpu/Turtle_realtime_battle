class_name TentacleSlamFx
extends RefCounted
## 灵物触手 · 拍下特效(2026-11-13 最后一版优化, 方案书 docs/plans/20261113b-灵物触手最后一版优化.md)
##
## 用户 11-13:「需要改的是待机动画、动作、拍下去的时候还有特效都要改」—— 参考 LoL 实机俄洛伊。
## 外服训练营 60fps 逐帧(被动触手拍下, 39.10–39.35 s)看到的顺序 —— **特效先于本体到**:
##   贴地前 1~2 帧  从触手到目标几道白紫细速度线;
##   +0~+2 帧       整条路径一条亮紫「刀光」(白芯, 一侧锯齿 = 背鳍的剪影), 目标处白核爆闪 + 淡紫地面光圈;
##   之后           本体贴地, 刀光融进贴地本体、约 0.3 秒褪成紫光。
## 本文件只管画。何时画由 `TentacleVfx.tick` 按状态计时调: 刀光的 0 时刻 = 贴地 = 伤害时刻(T_TOUCH, 不动)。
## 逐帧直播: 刀光网格**整局一份**(单位空间, 出处键 = 本文件 + `gen_smear_unit`), 位置 / 朝向 / 长宽由节点变换给,
##   每步只改着色器 `age` 一个参数(`assets/shaders/tentacle_smear.gdshader`)。第一版每步重建一份网格,
##   `verify_stream_tentacle` 量到流里多出 245 份定义 —— 那正是 10-31「回放掉帧」那一族, 改掉。

const SRC := "res://scripts/systems/equip/tentacle_slam_fx.gd"
const VfxTex := preload("res://scripts/util/vfx_textures.gd")
const SHADER: Shader = preload("res://assets/shaders/tentacle_smear.gdshader")
## 每步会变的 uniform(录流约定: 节点 meta `stream_shader_params`)
const STREAM_PARAMS := ["age"]

## 速度线 + 目标闪光提前量(秒): 录屏 31.01 s 速度线和目标白光圈就出了, 本体 31.11 才贴地(特效先到)
const LEAD := 0.10
## 速度线在贴地后还留多久
const LINES_AFTER := 0.05
## 刀光: 满亮 HOLD 秒, 再 FADE 秒褪掉
const SMEAR_HOLD := 0.06
const SMEAR_FADE := 0.20
## 刀光几何(场地单位; 预警带半宽 120 = 命中通道, 刀光是「本体扫过的轨迹」, 比通道窄)
const SMEAR_HALF_W := 36.0
const SMEAR_SPIKE := 34.0              # 锯齿只长在一侧
const SMEAR_N := 18                    # 沿长段数(锯齿一段一个)
const SMEAR_LIFT := 0.30               # 离地高度(世界单位): 读成本体扫过的轨迹, 不是地面贴花
const LINE_HALF_W := 2.6
const C_CORE := Color(0.96, 0.84, 1.0)
const C_MID := Color(0.62, 0.20, 1.0)
const C_EDGE := Color(0.40, 0.08, 0.85)


## 贴地裂纹多久淡没(秒; 节点要活到它淡完)
const CRACK_LIFE := 2.4


static func life() -> float:
	return maxf(SMEAR_HOLD + SMEAR_FADE, CRACK_LIFE)


## 刀光亮度包络(age = 贴地后秒数)。贴地前 0。
static func smear_env(age: float) -> float:
	if age < 0.0:
		return 0.0
	return 1.0 - smoothstep(SMEAR_HOLD, SMEAR_HOLD + SMEAR_FADE, age)


## 速度线亮度(贴地前 LEAD 秒满亮, 贴地后 LINES_AFTER 秒内褪掉)。
static func lines_env(age: float) -> float:
	if age < -LEAD or age > LINES_AFTER:
		return 0.0
	return 1.0 if age < 0.0 else 1.0 - age / LINES_AFTER


static var _mesh: ArrayMesh = null


## 整局共用的一份刀光网格。录流按出处键让手机调同一个函数建同一份。
static func shared_mesh() -> ArrayMesh:
	if _mesh == null:
		## 自己设计的外形(style 1)用柔和波浪边(和背上的软薄膜同一母题), 原来的是锯齿(俄洛伊背鳍剪影)
		var soft: bool = float(TentacleMeshVfx.palette().get("style", 0.0)) > 0.5
		_mesh = VfxTex.tag(gen_smear_unit(SMEAR_N, soft), "gen_smear_unit", [SMEAR_N, soft], SRC)
	return _mesh


## 单位空间网格(纯函数): x 沿长 0..1, z 横向以刀光半宽为单位(锯齿那一侧为 +z), y = 0。
## 顶点色 = 颜色 + 不随时间变的透明度(根部淡入 / 横向剖面); 随时间的亮度在着色器里按 age 乘。UV2.x = 1 是速度线。
static func gen_smear_unit(n: int, soft: bool = false) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lw: float = LINE_HALF_W / SMEAR_HALF_W
	## ① 速度线: 三条细线, 从路径 15% 处到末端
	for off in [-0.55, 0.0, 0.55]:
		var c0 := Color(C_CORE.r, C_CORE.g, C_CORE.b, 0.0)
		var c1 := Color(C_CORE.r, C_CORE.g, C_CORE.b, 0.95)
		_quad(st, Vector2(0.15, float(off) - lw), Vector2(0.15, float(off) + lw), Vector2(1.0, float(off) - lw), Vector2(1.0, float(off) + lw),
			c0, c0, c1, c1, 1.0)
	## ② 刀光: 横向五点 无齿侧边缘(0) → 中 → 芯 → 中 → 有齿侧边缘(奇数点伸出锯齿)
	var spike_rel: float = SMEAR_SPIKE / SMEAR_HALF_W
	var prev: Array = []
	for i in range(n + 1):
		var u: float = float(i) / float(n)
		var head: float = smoothstep(0.0, 0.08, u)
		var hw: float = 1.0 - 0.40 * u
		var sp: float = spike_rel * hw * (1.0 - 0.5 * u) if (i % 2 == 1) else 0.0
		if soft:
			sp = spike_rel * 0.55 * hw * (1.0 - 0.5 * u) * (0.5 + 0.5 * sin(u * TAU * 3.0 - 1.2))
		var row: Array = [
			[Vector2(u, -hw), Color(C_EDGE.r, C_EDGE.g, C_EDGE.b, 0.0)],
			[Vector2(u, -hw * 0.42), Color(C_MID.r, C_MID.g, C_MID.b, 0.75 * head)],
			[Vector2(u, 0.0), Color(C_CORE.r, C_CORE.g, C_CORE.b, 0.70 * head)],
			[Vector2(u, hw * 0.42), Color(C_MID.r, C_MID.g, C_MID.b, 0.75 * head)],
			[Vector2(u, hw + sp), Color(C_EDGE.r, C_EDGE.g, C_EDGE.b, 0.55 * head if sp > 0.0 else 0.0)],
		]
		if not prev.is_empty():
			for j in range(row.size() - 1):
				_quad(st, prev[j][0], prev[j + 1][0], row[j][0], row[j + 1][0], prev[j][1], prev[j + 1][1], row[j][1], row[j + 1][1], 0.0)
		prev = row
	## ③ 贴地裂纹带: 落到地面(节点在 SMEAR_LIFT 高处, y 往下抵掉), 横向 ±1.6 个半宽; 花纹全在着色器里
	var gy: float = -SMEAR_LIFT + 0.02
	for i2 in range(8):
		var u0: float = float(i2) / 8.0
		var u1: float = float(i2 + 1) / 8.0
		var cc := Color(1, 1, 1, 1)
		_quad(st, Vector2(u0, -1.6), Vector2(u0, 1.6), Vector2(u1, -1.6), Vector2(u1, 1.6), cc, cc, cc, cc, 2.0, gy)
	st.commit(mesh)
	return mesh


## 一个四边形(两个三角形)。点是 (沿长 x, 横向 z)。
static func _quad(st: SurfaceTool, p00: Vector2, p01: Vector2, p10: Vector2, p11: Vector2,
		c00: Color, c01: Color, c10: Color, c11: Color, kind: float, y: float = 0.0) -> void:
	for pc in [[p00, c00], [p01, c01], [p10, c10], [p01, c01], [p11, c11], [p10, c10]]:
		st.set_color(pc[1])
		st.set_uv2(Vector2(kind, 0.0))
		st.add_vertex(Vector3((pc[0] as Vector2).x, y, (pc[0] as Vector2).y))


## 刀光节点(每根触手一个, 懒建)。加色、不吃深度(刀光要盖在目标身上, 实机就是这样)。
static func make_node(world: Node, nm: String, len2: float = 520.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = shared_mesh()
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("hold", SMEAR_HOLD)
	m.set_shader_parameter("fade", SMEAR_FADE)
	m.set_shader_parameter("lead", LEAD)
	m.set_shader_parameter("lines_after", LINES_AFTER)
	m.set_shader_parameter("aspect", len2 / SMEAR_HALF_W)
	m.set_shader_parameter("crack_life", CRACK_LIFE)
	var fc: Dictionary = fx_cols()
	if bool(fc["recolor"]):
		m.set_shader_parameter("recolor", 1.0)
		m.set_shader_parameter("rc_core", fc["core"])
		m.set_shader_parameter("rc_mid", fc["mid"])
		m.set_shader_parameter("rc_edge", fc["edge"])
	m.render_priority = 7
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(&"stream_shader_params", PackedStringArray(STREAM_PARAMS))
	world.add_child(mi)
	return mi


## 每步: 摆好节点(根部 → 射程末端, 锯齿朝 spike_side 那一侧) + 写 age。坐标换算同 VfxTex.wpos。
static func place(mi: MeshInstance3D, from2: Vector2, end2: Vector2, spike_side: float, age: float,
		center: Vector2, ws: float, lift: float) -> void:
	var d: Vector2 = end2 - from2
	var len2: float = d.length()
	if len2 < 1.0:
		mi.visible = false
		return
	var dn: Vector2 = d / len2
	var x := Vector3(dn.x, 0.0, dn.y) * (len2 * ws)
	var z := Vector3(-dn.y, 0.0, dn.x) * (SMEAR_HALF_W * ws * spike_side)
	mi.transform = Transform3D(Basis(x, Vector3.UP, z), VfxTex.wpos(center, ws, from2, lift))
	mi.visible = true
	(mi.material_override as ShaderMaterial).set_shader_parameter("age", age)


## 拍下特效三色(刀光芯 / 刀光中段 / 外沿)。跟触手配色走(TentacleMeshVfx.PALETTES 的 fx_*; 没给 = 原来的灵物紫)。
static func fx_cols() -> Dictionary:
	var pal: Dictionary = TentacleMeshVfx.palette()
	if not pal.has("fx_mid"):
		return {"recolor": false, "core": C_CORE, "mid": C_MID, "edge": C_EDGE}
	return {"recolor": true, "core": pal["fx_core"], "mid": pal["fx_mid"], "edge": pal["fx_edge"]}


## 出土光柱: 竖直一道洋红光(1~2 帧最亮), 0.25 秒内变细褪掉。只绕 Y 轴朝向镜头, 永远竖着。
## 光柱的贴图: 横向一道高斯亮带(中间亮、两边柔), 竖向均匀 —— 整根从地面到画面顶一样亮(不是一团拉长的光晕)
static var _beam_tex: Texture2D = null


static func _beam_texture() -> Texture2D:
	if _beam_tex == null:
		var img := Image.create(32, 8, false, Image.FORMAT_RGBA8)
		for x in range(32):
			var fx: float = (float(x) + 0.5) / 32.0 * 2.0 - 1.0
			var a: float = exp(-fx * fx * 9.0)
			var core: float = exp(-fx * fx * 60.0)
			for yy in range(8):
				img.set_pixel(x, yy, Color(1.0, 1.0, 1.0, clampf(a * 0.75 + core * 0.5, 0.0, 1.0)))
		_beam_tex = ImageTexture.create_from_image(img)
	return _beam_tex


## 出土光柱(11-13 用户逐张对照: 「人家这个向上的紫光这么高，你这个光为什么只光到一半」「光柱很淡很淡，但人家光柱的高度呢」):
##   从地面一直冲出画面顶, 整根一起变淡变细、高度不变; 约 0.2 秒没(LoL 光柱后 0.15 秒还在、0.21 秒没了)。
const BEAM_H := 30.0
const BEAM_W := 0.75
const BEAM_LIFE := 0.21
## 光柱淡入: 光柱那一刻前 BEAM_IN 秒生成, 用 BEAM_RAMP 秒从透明亮到最亮(LoL 72.35 − 0.083 秒淡淡出现、−0.05 秒已经很亮);
##   11-13 夜用户看对比视频「有个闪现」: 原来光柱那一帧直接满亮度冒出来
const BEAM_IN := 0.08
const BEAM_RAMP := 0.07


static func spawn_beam(battle, pos2: Vector2) -> void:
	var b := Sprite3D.new()
	b.texture = _beam_texture()
	b.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	b.shaded = false
	b.transparent = true
	b.no_depth_test = false
	b.render_priority = 6
	var bc: Color = (fx_cols()["mid"] as Color).lerp(Color.WHITE, 0.35)
	b.modulate = Color(bc.r, bc.g, bc.b, 0.0)
	b.pixel_size = BEAM_W / 32.0
	## 底边贴地: 中心放在一半高处
	b.position = battle._world_pos(pos2, battle.GROUND_LIFT + BEAM_H * 0.5)
	b.scale = Vector3(1.0, BEAM_H / (8.0 * b.pixel_size), 1.0)
	battle._world.add_child(b)
	var tw: Tween = battle._reg_tween()
	## 匀速亮起来(先快后慢的话第一帧就亮一半, 还是一闪)
	tw.tween_property(b, "modulate:a", 1.0, BEAM_RAMP).set_trans(Tween.TRANS_LINEAR)
	tw.tween_interval(maxf(BEAM_IN - BEAM_RAMP, 0.0))
	tw.tween_property(b, "scale:x", 0.45, BEAM_LIFE)
	tw.parallel().tween_property(b, "modulate:a", 0.0, BEAM_LIFE).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(b.queue_free)


## 目标处爆闪: 正对镜头的白核, grow 秒内长到最亮(= 贴地那一刻) → 转淡紫褪掉; 脚下一圈淡紫光盘。
## 整套拍下在贴地前 LEAD 秒调(grow = 离贴地的秒数); 点刺在贴地那一刻调(grow 取默认 2 帧)。
static func target_bloom(battle, pos2: Vector2, big: bool, grow: float = 0.034) -> void:
	var k: float = 1.0 if big else 0.6
	var tex: Texture2D = VfxTex._make_glow_texture()
	var b := Sprite3D.new()
	b.texture = tex
	b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	b.shaded = false
	b.transparent = true
	b.no_depth_test = true
	b.render_priority = 9
	b.modulate = Color(1.0, 0.97, 1.0, 1.0)
	b.pixel_size = 0.0060 * k
	b.position = battle._world_pos(pos2, battle.GROUND_LIFT + 0.55)
	battle._world.add_child(b)
	var tw: Tween = battle._reg_tween()
	tw.tween_property(b, "scale", Vector3(1.25, 1.25, 1.0), maxf(grow, 0.017)).from(Vector3(0.45, 0.45, 1.0))
	var fm: Color = fx_cols()["mid"]
	tw.tween_property(b, "modulate", Color(fm.r, fm.g, fm.b, 0.0).lerp(Color(1, 1, 1, 0), 0.3), 0.12)
	tw.tween_callback(b.queue_free)
	var d := Sprite3D.new()
	d.texture = tex
	d.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	d.axis = Vector3.AXIS_Y
	d.shaded = false
	d.transparent = true
	d.no_depth_test = true
	d.render_priority = 6
	var dcol: Color = (fx_cols()["mid"] as Color).lerp(Color.WHITE, 0.4)
	d.modulate = Color(dcol.r, dcol.g, dcol.b, 0.55)
	d.pixel_size = 0.0075 * k
	d.position = battle._world_pos(pos2, battle.GROUND_LIFT + 0.05)
	battle._world.add_child(d)
	var tw2: Tween = battle._reg_tween()
	tw2.tween_property(d, "scale", Vector3(1.30, 1.0, 1.30), maxf(grow, 0.017) + 0.12).from(Vector3(0.70, 1.0, 0.70))
	tw2.parallel().tween_property(d, "modulate:a", 0.0, 0.12).set_delay(maxf(grow, 0.017) + 0.04)
	tw2.tween_callback(d.queue_free)
